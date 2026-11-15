"""Claude 05/11/2026: decompose O2 false accepts (post hoc). For every plan ACCEPTED by a golden variant and labelled
O2-UNSAFE, classify the O2 culprit (the object of the best candidate's minimum margin):
  later_entrant   culprit not in the W7 object set at t0 (enters the corridor later: outside assumption A5)
  rear_hold       culprit behind the ego and the minimum occurs during the 2 s standstill hold (non-reactive replay
                  of a follower that in the log followed a human driver who did not stop)
  rear_motion     culprit behind, before the hold
  front           culprit ahead
Also stop_only label (same O2 GT, no hold): UNSAFE there means unsafe even without the hold.
usage: python fa_causes.py  -> fa_causes.json + printed table
"""
import json, glob, collections
from pathlib import Path

HERE = Path(__file__).resolve().parent
out = collections.defaultdict(collections.Counter)
dev = collections.defaultdict(list)
for f in sorted(glob.glob(str(HERE / 'plans_*.jsonl'))):
    for line in open(f, encoding='utf-8'):
        r = json.loads(line)
        if r['o2']['label'] != 'UNSAFE':
            continue
        for var, acc in r['decisions'].items():
            if not acc:
                continue
            key = f"{var}/{r['plan']}"
            c = r['o2'].get('culprit') or {}
            if not c.get('in_w7_object_set', True):
                cause = 'later_entrant'
            elif c.get('side') == 'behind':
                cause = 'rear_hold' if c.get('during_hold') else 'rear_motion'
            else:
                cause = 'front'
            out[key][cause] += 1
            out[key]['stop_only_' + str(r.get('stop_only'))] += 1
            out[key]['total'] += 1
            if c.get('gt_minus_constant_v_m') is not None:
                dev[key + '/' + cause].append(abs(c['gt_minus_constant_v_m']))
res = {k: dict(v) for k, v in sorted(out.items())}
med = {k: sorted(v)[len(v) // 2] for k, v in dev.items() if v}
(HERE / 'fa_causes.json').write_text(json.dumps({'counts': res, 'median_abs_gt_minus_cv_m': med}, indent=1))
for k, v in res.items():
    print(k, v)
for k, v in sorted(med.items()):
    print('median |GT-CV|', k, round(v, 2))
