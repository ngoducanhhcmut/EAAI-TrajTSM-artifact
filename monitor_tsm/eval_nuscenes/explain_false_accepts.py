"""Post-evaluation evidence for every false acceptance; no metric/threshold changes."""
import sys
sys.dont_write_bytecode = True
import json
from collections import Counter
import numpy as np
import run_w7 as w


def finish_report(summary, explanations, categories):
    w.report(summary, w.HERE)
    path = w.HERE / 'W7_REPORT.md'
    lines = path.read_text(encoding='utf-8').splitlines()
    for case in explanations:
        prefix = f"- {case['scene']} / {case['token']} / {case['plan']}:"
        e = case['evidence']
        detail = (prefix+f" {e['reason_category']}; object={e['object']}, "
                  f"t={e['time_from_t0_s']:.3f}s, GT-constant-v="
                  f"{e['GT_object_x_m']-e['constant_v_object_x_m']:+.3f}m, "
                  f"selected-profile oracle margin={e['oracle_margin_m']:.3f}m.")
        lines = [detail if line.startswith(prefix) else line for line in lines]
    def pct(value):
        return 'N/A' if value['rate'] is None else f"{100*value['rate']:.1f}"
    lines += ['', 'Strata: acceptance H/T/U (%), false-accept counts H/T/U; full subgroup CIs in summary.json.', '',
              '| Stratum | ODD frames | Acceptance H/T/U | False accepts H/T/U |',
              '|---|---:|---|---|']
    for group, groups in [('v m/s', summary['by_speed']), ('objects', summary['by_object_count'])]:
        for name, metrics in groups.items():
            accepts = '/'.join(pct(metrics[k]['acceptance']) for k in ('H', 'T', 'U'))
            counts = '/'.join(str(metrics[k]['false_accept']['n']) for k in ('H', 'T', 'U'))
            n = metrics['H']['acceptance']['denominator']
            lines.append(f'| {group} {name} | {n} | {accepts} | {counts} |')
    lines += ['', 'Posthoc evidence for EVERY false accept: [false_accept_evidence.jsonl](results/false_accept_evidence.jsonl); metrics unchanged.',
              'Evidence categories: '+json.dumps(dict(categories))+'.',
              'Prior serial attempt observed a 36232.422 s wall-time gap including overnight OS suspension; excluded from fresh full runtime and retained as serial_partial_*.',
              'Validation: exact pilot comparison, 808-frame serial prefix, and 300-frame RTL replay; results/audit.json and evidence_summary.json.',
              'SI-to-golden encoding uses Python round(value*1e6), with no saturation; original SI plan states remain in frames.jsonl.',
              'An event-free bootstrap can yield CI [0,0]; this is not an upper bound on unseen failure probability.',
              'Offline estimator lookahead: T/TSM object velocities use prev/next annotations; no GT waypoint target. See [AMENDMENT A7](AMENDMENT_A7.md).',
              'Optional evidence/report rebuild after core run: `python -B tsmx_hw/eval_nuscenes/explain_false_accepts.py`.']
    assert len(lines) <= 80, len(lines)
    path.write_text('\n'.join(lines)+'\n', encoding='utf-8')


def main():
    folder = w.HERE / 'results'
    summary = json.loads((folder / 'summary.json').read_text(encoding='utf-8'))
    assert summary['complete'], 'Wait for full evaluation to finish'
    rows = w.recover(folder / 'frames.jsonl')
    assert len(rows) == summary['total_eligible']
    previous = w.recover(folder / 'serial_partial_frames.jsonl')
    for left, right in zip(previous, rows):
        assert left == right, left['token']
    explanations = []
    categories = Counter()
    for row in rows:
        for label, plan in row['plans'].items():
            if not (plan['accept'] and plan['oracle']['label'] == 'UNSAFE'):
                continue
            cid = plan['cid']
            b, j = (2., 4., 6., 8.)[cid//4], (2., 4., 8.)[cid%4]
            ts, xs = w.float_profile(*plan['state_si'], b, j)
            best, evidence = 1e10, None
            for obj in row['objects']:
                ot = ts+.5
                truth = np.interp(ot, obj['times'], obj['xs'])
                gap = np.abs(truth-xs)-obj['length']-.5
                k = int(np.argmin(gap))
                if gap[k] < best:
                    best = float(gap[k])
                    t = float(ot[k])
                    predicted = obj['x'] + obj['v']*t
                    predicted_margin = float(abs(predicted-xs[k])-obj['length']-.5)
                    reason = ('track_ended_early_hold' if obj['track_ends_early'] and t > obj['times'][-2]
                              else 'oracle_hold_after_3s' if t > 3
                              else 'observed_GT_differs_from_constant_velocity')
                    side = 'front' if truth[k] >= xs[k] else 'rear'
                    if reason == 'observed_GT_differs_from_constant_velocity':
                        if side == 'front' and truth[k] < predicted:
                            reason = 'front_object_lags_constant_velocity_prediction'
                        elif side == 'rear' and truth[k] > predicted:
                            reason = 'rear_object_advances_beyond_constant_velocity_prediction'
                    if predicted_margin < 0:
                        reason = 'negative_constant_velocity_margin_check_model_and_quantization'
                    velocities = np.diff(obj['xs'])/np.diff(obj['times'])
                    evidence = {'object': obj['token'], 'category': obj['category'],
                        'time_from_t0_s': t, 'ego_x_m': float(xs[k]),
                        'GT_object_x_m': float(truth[k]), 'constant_v_object_x_m': predicted,
                        'measured_object_v_mps': obj['v'], 'oracle_margin_m': best,
                        'side_at_GT_minimum': side,
                        'constant_v_margin_m': predicted_margin,
                        'track_ends_early': obj['track_ends_early'],
                        'GT_segment_velocity_range_mps': [float(velocities.min()), float(velocities.max())],
                        'reason_category': reason,
                        'interpretation': 'Model/GT mismatch evidence at the selected profile closest approach; not proof of causality.'}
            assert best < 0, (row['token'], label, best)
            categories[evidence['reason_category']] += 1
            explanations.append({'scene': row['scene'], 'token': row['token'], 'plan': label,
                                 'cid': cid, 'golden_margin_um': plan['margin'], 'evidence': evidence})
    assert len(explanations) == len(summary['false_accept_cases'])
    assert {(c['scene'], c['token'], c['plan']) for c in explanations} == {
        (c['scene'], c['token'], c['plan']) for c in summary['false_accept_cases']}
    with (folder / 'false_accept_evidence.jsonl').open('w', encoding='utf-8') as f:
        for explanation in explanations:
            f.write(json.dumps(explanation)+'\n')
    w.write_json(folder / 'evidence_summary.json', {
        'source_summary_sha256': w.sha(folder / 'summary.json'),
        'analysis_code_sha256': w.sha(__file__), 'posthoc_explanation_only': True,
        'clarification_A7_sha256': w.sha(w.HERE / 'AMENDMENT_A7.md'),
        'serial_prefix_compared_exact': len(previous), 'false_accepts': len(explanations),
        'reason_categories': dict(categories)})
    finish_report(summary, explanations, categories)
    print(json.dumps({'compared_serial_prefix': len(previous), 'false_accepts': len(explanations),
                      'reason_categories': dict(categories)}))


if __name__ == '__main__':
    main()
