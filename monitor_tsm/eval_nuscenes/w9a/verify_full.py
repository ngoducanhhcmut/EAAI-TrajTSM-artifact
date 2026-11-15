"""Independent accounting of completed W9a3 artifacts; no planner rerun."""
import plans_hw as ph
from plans_hw import OUT, HERE, ROOT, np, json
from pathlib import Path
from collections import Counter
import time


def main():
    started = time.monotonic()
    s = json.loads((OUT/'summary.json').read_text())
    assert s['status'] == 'COMPLETE'
    old = json.loads((OUT/'prior_w9a2_summary.json').read_text())
    unchanged = []
    for key, digest in old['provenance'].items():
        path = Path(key).resolve()
        if OUT in path.parents:
            continue
        relative = str(path.relative_to(ROOT))
        assert s['provenance'][relative] == digest, relative
        unchanged.append(relative)
    assert len(unchanged) == 5
    earlier = json.loads((OUT/'prior_w9a_summary.json').read_text())
    for key, digest in earlier['provenance'].items():
        path = (ROOT/Path(key)).resolve()
        if OUT in path.parents or not isinstance(digest, str):
            continue
        relative = str(path.relative_to(ROOT))
        assert s['provenance'][relative] == digest, relative
        if relative not in unchanged:
            unchanged.append(relative)
    frames = [json.loads(l) for l in (HERE/'results/frames.jsonl').read_text().splitlines()]
    tokens = np.load(OUT/'plan_tokens.npy')
    plans = np.load(OUT/'plans_hw.npy')
    assert list(tokens) == [f['token'] for f in frames]
    assert plans.shape == (29049, 4, 2) and np.isfinite(plans).all()
    rows = []
    for p in sorted(OUT.glob('replay_*.jsonl')):
        rows.extend(json.loads(l) for l in p.read_text().splitlines())
    expected = {(f['token'], label) for f in frames if f['odd'] for label in f['plans']}
    assert {(r['token'], r['plan']) for r in rows} == expected
    assert len(rows) == len(expected) == 44607
    indexed = {r['token']: i for i, r in enumerate(frames)}
    reused = 0
    for path in sorted(OUT.glob('gate_*.jsonl')):
        for r in map(json.loads, path.read_text().splitlines()):
            if r['token'] in indexed:
                assert np.array_equal(plans[indexed[r['token']]], np.asarray(r['wp'], np.float32))
                reused += 1
    for variant in ('V0', 'VA', 'VB'):
        for label in 'HTU':
            rr = [r for r in rows if r['plan'] == label]
            m = s['metrics'][variant][label]
            ac = [r for r in rr if r['cids'][variant] != 15]
            assert m['acceptance']['n'] == len(ac)
            assert m['acceptance']['denominator'] == len(rr)
            assert m['rejection']['n'] + len(ac) == len(rr)
            for key in ('registered', 'aligned'):
                lab = lambda r: r[key]['oracle']['label'] if key == 'registered' else r[key]['label']
                assert m[key]['labels'] == dict(Counter(lab(r) for r in rr))
                for metric, target, accepted in [('false_accept', 'UNSAFE', True), ('false_reject', 'SAFE', False)]:
                    chosen = [r for r in rr if lab(r) == target]
                    assert m[key][metric]['denominator'] == len(chosen)
                    assert m[key][metric]['n'] == sum((r['cids'][variant] != 15) == accepted for r in chosen)
            if variant != 'VB':
                counts = Counter(r['accepted'][variant]['selected']['label'] for r in ac)
                assert all(m['selected_labels'][k] == counts[k] for k in m['selected_labels'])
                assert sum(m['selected_labels'].values()) == len(ac)
    for label in 'HU':
        for variant in ('V0', 'VA', 'VB'):
            # Unchanged H/U must reproduce the published W7B counts.
            ref = {'V0': {'H': (6596,1912,296),'U':(2873,1789,117)},
                   'VA': {'H': (9648,680,395),'U':(5430,842,180)},
                   'VB': {'H': (15880,91,2401),'U':(8179,286,501)}}[variant][label]
            m = s['metrics'][variant][label]
            assert (m['acceptance']['n'], m['aligned']['false_reject']['n'], m['aligned']['false_accept']['n']) == ref
    check = s['encoded_input_check']
    cases = json.loads((OUT/'false_accepts.json').read_text())
    case_keys = {(c['oracle_kind'], c['variant'], c['token'], c['plan']) for c in cases}
    assert len(case_keys) == len(cases) == s['false_accepts_artifact']['records']
    expected_cases = set()
    for r in rows:
        for variant in ('V0', 'VA', 'VB'):
            if r['cids'][variant] != 15:
                if r['registered']['oracle']['label'] == 'UNSAFE':
                    expected_cases.add(('registered', variant, r['token'], r['plan']))
                if r['aligned']['label'] == 'UNSAFE':
                    expected_cases.add(('aligned', variant, r['token'], r['plan']))
    assert case_keys == expected_cases
    audits = [a for r in rows for a in r['accepted'].values()]
    assert check['accepted_records'] == len(audits)
    assert check['sampled_discrepancies'] == sum(a['cv']['margin_m'] < -1e-6 for a in audits)
    assert check['minimum_margin_m'] == min(a['cv']['margin_m'] for a in audits)
    text = (OUT/'W9A_REPORT.md').read_text(encoding='utf-8')
    assert (OUT/'supervisor_decision_w9a3.txt').read_text(encoding='utf-8').rstrip() in text
    assert len(text.splitlines()) <= 80
    assert s['gate']['passed'] and s['gate']['within_tolerance_frames'] == 5419
    evidence = dict(status='PASS', plans=29049, replay_records=len(rows), gate_predictions_reused=reused, report_lines=len(text.splitlines()), accounting_checked=True, unchanged_H_U_counts_match_W7B=True, unchanged_gate_provenance=unchanged, encoded_input_check=check, runtime_seconds=time.monotonic()-started)
    ph.dump('full_verification.json', evidence)
    s['independent_accounting_verification'] = evidence
    ph.dump('summary.json', s)
    print('PASS: all frames, record sets, counts, H/U baseline, selected labels, encoded check, report and gate reuse')


if __name__ == '__main__':
    main()
