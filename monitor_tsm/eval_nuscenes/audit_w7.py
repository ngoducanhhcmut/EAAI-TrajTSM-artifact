"""Read-only checks of W7 decisions, independent integration and saved RTL vectors."""
import sys
sys.dont_write_bytecode = True
import json
import numpy as np
import run_w7 as w


def main():
    validation = {}
    compared = 0
    for v in (0., 1., 5., 10.):
        for a in (-8., -3., 0., 2.):
            for k, (b, j) in enumerate(w.PAIRS):
                cid = k//3*4+k%3
                curve = w.float_profile(0., v, a, b, j)
                ts, xs = curve
                tr = w.b4_mrmgen(0, w.fixed(v), w.fixed(a), cid)
                assert tr.accept, (v, a, cid, tr.reason)
                for t, xl, xh, _, _, _, _ in tr.rows:
                    xx = float(np.interp(t/1e6, ts, xs))
                    assert xl/1e6-1e-5 <= xx <= xh/1e6+1e-5, (v, a, cid, t, xl, xh, xx)
                    compared += 1
    validation['oracle_vs_golden_envelope_rows'] = compared
    ref = w.recover(w.HERE / 'results/pilot_reference/frames.jsonl')
    pilot = w.recover(w.HERE / 'results/pilot/frames.jsonl')
    assert len(ref) == len(pilot) == 200
    for left, right in zip(ref, pilot):
        assert left['token'] == right['token'] and left['odd'] == right['odd']
        if left['odd']:
            assert left['traj_waypoints'] == right['traj_waypoints'], left['token']
            for label in left['plans']:
                a, b = left['plans'][label], right['plans'][label]
                assert a['accept'] == b['accept'] and a['cid'] == b['cid']
                assert a['oracle'] == b['oracle']
    validation['pilot_frames_compared_exact'] = 200
    validation['pilot_odd_waypoints_compared_exact'] = sum(r['odd'] for r in pilot)
    frames = w.recover(w.HERE / 'results/frames.jsonl')
    summary = json.loads((w.HERE / 'results/summary.json').read_text(encoding='utf-8'))
    assert summary['complete'] and len(frames) == summary['total_eligible'] == 29049
    assert len({r['scene'] for r in frames}) == 850
    assert [r['scene'] for r in frames] == sorted(r['scene'] for r in frames)
    assert summary['provenance']['code_sha256'] == w.sha(w.HERE / 'run_w7.py')
    assert summary['provenance']['protocol_sha256'] == w.sha(w.HERE / 'PROTOCOL.md')
    for name in ('H', 'T', 'U'):
        plans = [r['plans'][name] for r in frames if name in r['plans']]
        safe = [p for p in plans if p['oracle']['label'] == 'SAFE']
        unsafe = [p for p in plans if p['oracle']['label'] == 'UNSAFE']
        expected = {'acceptance': (sum(p['accept'] for p in plans), len(plans)),
                    'false_reject': (sum(not p['accept'] for p in safe), len(safe)),
                    'false_accept': (sum(p['accept'] for p in unsafe), len(unsafe))}
        if name == 'U':
            expected['recall'] = (sum(not p['accept'] for p in unsafe), len(unsafe))
        for metric, counts in expected.items():
            actual = summary['metrics'][name][metric]
            assert (actual['n'], actual['denominator']) == counts, (name, metric)
            assert actual['rate'] == (counts[0]/counts[1] if counts[1] else None)
    assert summary['odd_coverage']['n'] == sum(r['odd'] for r in frames)
    assert summary['odd_coverage']['denominator'] == len(frames)
    validation['full_frame_count'] = len(frames)
    validation['scenes'] = 850
    validation['primary_metric_counts_independently_recomputed'] = True
    vectors = w.recover(w.HERE / 'rtl_cases.jsonl')
    odd = [r for r in frames if r['odd']]
    assert [r['token'] for r in vectors] == [r['token'] for r in odd[:300]]
    nplans, invalid, overflow = 0, 0, 0
    for frame in vectors:
        for plan in frame['plans'].values():
            ego = w.Ego(**plan['ego'])
            objects = tuple(w.Motion(**o) for o in plan['objects'])
            cid, reason = w.select_world(ego, objects, tuple(plan['lane']))
            assert cid == plan['expected']['cid'] and reason == plan['expected']['reason']
            assert (cid != 15) == plan['expected']['accept']
            nplans += 1
            invalid += not plan['propagation_done']
            overflow += len(objects) > 32
    validation.update(rtl_frames=len(vectors), rtl_plans_replayed=nplans,
                      rtl_invalid_velocity_plans=invalid, rtl_overflow_plans=overflow)
    w.write_json(w.HERE / 'results/audit.json', validation)
    print(json.dumps(validation), flush=True)


if __name__ == '__main__':
    main()
