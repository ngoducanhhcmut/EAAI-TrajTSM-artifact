"""Claude 14/11/2026: nuPlan RSS baseline.
Loads the RSS-monitor runs (rss_main1: blind_rss, stale_rss; rss_main2: none_rss) with the loaders of analyze_w8.py
and compares them, paired by scenario, with the existing raw / TSM-X runs (mainA/B/C).
Writes results/rss_summary.json and RSS_REPORT.md; does not touch the W8 outputs. Run in WSL env nuplan."""
import json
from math import comb
from pathlib import Path
import numpy as np
from analyze_w8 import load, boot, HERE

BASE = {}
for c in ['none_raw', 'none_tsmx', 'blind_raw', 'blind_tsmx', 'stale_raw', 'stale_tsmx', 'stale_tsmxc']:
    for t in ['mainA', 'mainB', 'mainC']:
        r = load(t, c)
        if r:
            BASE[c] = r
RSS = {}
for t, c in [('rss_main2', 'none_rss'), ('rss_main1', 'blind_rss'), ('rss_main1', 'stale_rss')]:
    r = load(t, c)
    if r:
        RSS[c] = r
data = {**BASE, **RSS}
common = sorted(set.intersection(*[set(v) for v in data.values()]))


def mcnemar(b, c):
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    return min(1.0, 2 * sum(comb(n, i) for i in range(k + 1)) / 2 ** n)


def summ(rows):
    ks = [k for k in common if 'nofault_coll' in rows[k]]
    coll = [1.0 if rows[k]['nofault_coll'] < 1 else 0.0 for k in ks]
    sc = [rows[k].get('score', np.nan) for k in common]
    return dict(n=len(ks), collisions=int(sum(coll)), collision=float(np.mean(coll)), collision_ci=boot(coll),
                score=float(np.nanmean(sc)), score_ci=boot(sc), progress=float(np.nanmean([rows[k].get('progress', np.nan) for k in common])),
                ttc=float(np.nanmean([rows[k].get('ttc_ok', np.nan) for k in common])),
                mrm_per_scen=float(np.mean([rows[k]['mrm_entries'] for k in common])),
                mrm_before_fault=int(sum(rows[k]['mrm_before_fault'] for k in common)), ood_frac=sum(rows[k]['ood_steps'] for k in common)/max(1,sum(rows[k]['steps'] for k in common)))


def paired(a, b):
    ks = [k for k in common if 'nofault_coll' in a[k] and 'nofault_coll' in b[k]]
    ca = np.array([a[k]['nofault_coll'] < 1 for k in ks]); cb = np.array([b[k]['nofault_coll'] < 1 for k in ks])
    av, intro = int((ca & ~cb).sum()), int((~ca & cb).sum())
    ds = np.array([b[k].get('score', np.nan) - a[k].get('score', np.nan) for k in common], float)
    ds = ds[~np.isnan(ds)]
    return dict(n=len(ks), avoided=av, introduced=intro, both=int((ca & cb).sum()), mcnemar_p=mcnemar(av, intro),
                score_diff=float(ds.mean()), score_diff_ci=boot(ds),
                introduced_tokens=[k for k, x, y in zip(ks, ca, cb) if y and not x])


out = {'scenarios_common': len(common), 'conditions': {c: summ(r) for c, r in data.items()}, 'paired': {}}
for f in ['none', 'blind', 'stale']:
    rc = f + '_rss'
    if rc not in data:
        continue
    for ref in [f + '_raw', f + '_tsmx'] + (['stale_tsmxc'] if f == 'stale' else []):
        if ref in data:
            out['paired'][f'{ref}->{rc}'] = paired(data[ref], data[rc])
L = [f'# nuPlan RSS baseline (Claude 14/11/2026) — {len(common)} scenarios common to all conditions', '',
     '| Condition | collisions | rate [95% CI] | score [95% CI] | progress | TTC | stops/scen. | stops before fault |', '|---|---|---|---|---|---|---|---|']
for c, m in out['conditions'].items():
    L.append(f"| {c} | {m['collisions']}/{m['n']} | {100*m['collision']:.1f}% [{100*m['collision_ci'][0]:.1f}, {100*m['collision_ci'][1]:.1f}] | "
             f"{m['score']:.3f} [{m['score_ci'][0]:.3f}, {m['score_ci'][1]:.3f}] | {m['progress']:.3f} | {m['ttc']:.3f} | {m['mrm_per_scen']:.2f} | {m['mrm_before_fault']} | {m['ood_frac']:.3f} |")
L += ['', '| Pair | avoided | introduced | both | McNemar p | score diff [95% CI] |', '|---|---|---|---|---|---|']
for k, d in out['paired'].items():
    L.append(f"| {k} | {d['avoided']} | {d['introduced']} {d['introduced_tokens']} | {d['both']} | {d['mcnemar_p']:.3g} | {d['score_diff']:+.3f} [{d['score_diff_ci'][0]:+.3f}, {d['score_diff_ci'][1]:+.3f}] |")
(HERE / 'results').mkdir(exist_ok=True)
(HERE / 'results' / 'rss_summary.json').write_text(json.dumps(out, indent=1))
(HERE / 'RSS_REPORT.md').write_text('\n'.join(L) + '\n')
print('\n'.join(L))
