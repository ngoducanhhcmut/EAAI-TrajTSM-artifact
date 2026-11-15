"""Claude 05/11/2026 (W8): aggregate the nuPlan closed-loop runs (run inside WSL, env nuplan).

Per condition (none|blind|stale x raw|tsmx): at-fault collision rate (no_ego_at_fault_collisions score < 1), TTC
compliance, progress, nuPlan final score (closed_loop_reactive_agents weighted average), plus TSM-X step logs
(MRM interventions, out-of-ODD pass-through, never-certified fallbacks). Paired by scenario token; CI = scenario
bootstrap (2000, seed 20261105). usage: python analyze_w8.py <tag> [<tag> ...]  -> results/w8_summary.json, W8_REPORT.md
"""
import glob, json, os, sys
from pathlib import Path
import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
EXP = Path(os.path.expanduser('~/nuplan_exp/exp'))
CONDS = ['none_raw', 'none_tsmx', 'blind_raw', 'blind_tsmx', 'stale_raw', 'stale_tsmx', 'stale_tsmxc']
METRICS = {'no_ego_at_fault_collisions': 'nofault_coll', 'time_to_collision_within_bound': 'ttc_ok',
           'ego_progress_along_expert_route': 'progress', 'drivable_area_compliance': 'drivable'}


def latest(tag, cond):
    runs = sorted(glob.glob(str(EXP / f'w8_{tag}_{cond}' / '*' / '*')))
    runs = [r for r in runs if os.path.exists(os.path.join(r, 'aggregator_metric'))]
    return runs[-1] if runs else None


def load(tag, cond):
    run = latest(tag, cond)
    if not run:
        return None
    rows = {}
    for m, short in METRICS.items():
        f = os.path.join(run, 'metrics', m + '.parquet')
        if os.path.exists(f):
            d = pd.read_parquet(f)
            for _, r in d.iterrows():
                rows.setdefault(r['scenario_name'], {'type': r['scenario_type']})[short] = float(r['metric_score'])
    agg = pd.read_parquet(glob.glob(os.path.join(run, 'aggregator_metric', '*.parquet'))[0])
    for _, r in agg.iterrows():
        if r['scenario'] in rows:
            rows[r['scenario']]['score'] = float(r['score'])
    logdir = HERE / 'logs' / tag / cond
    for tok, rec in rows.items():
        f = logdir / f'{tok}_{cond}.jsonl'
        steps = [json.loads(l) for l in open(f)] if f.exists() else []
        rec['steps'] = len(steps)
        rec['mrm_steps'] = sum(s.get('mode') == 'MRM' for s in steps)
        rec['mrm_entries'] = sum('mrm_cid' in s for s in steps)
        rec['mrm_before_fault'] = sum('mrm_cid' in s and not s['faulted'] for s in steps)
        rec['uncertified'] = sum(bool(s.get('mrm_uncertified')) for s in steps)
        rec['ood_steps'] = sum(s.get('odd') is False for s in steps)
    return rows


def boot(vals, n=2000, seed=20261105):
    vals = np.asarray(vals, float)
    if len(vals) == 0:
        return [float('nan')] * 2
    rng = np.random.default_rng(seed)
    m = [vals[rng.integers(0, len(vals), len(vals))].mean() for _ in range(n)]
    return [float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))]


def main():
    tags = sys.argv[1:] or ['mainA', 'mainB', 'mainC']
    data = {}
    for c in CONDS:
        for t in tags:
            r = load(t, c)
            if r:
                data[c] = r
    missing = [c for c in CONDS if c not in data]
    sizes = {c: len(v) for c, v in data.items()}
    common = set.intersection(*[set(v) for v in data.values()]) if data else set()
    out = {'scenarios_common': len(common), 'per_condition_scenarios': sizes, 'missing_conditions': missing, 'conditions': {}}
    L = ['# W8 — nuPlan mini, closed loop, reactive IDM agents (Claude 05/11/2026)', '',
         f'Scenarios common to all conditions: {len(common)} (paired); per condition: {sizes}; MISSING conditions: {missing}. CI: scenario bootstrap 2000, seed 20261105.', '',
         '| Condition | n | At-fault collision rate | TTC compliance | Progress | nuPlan score | MRM entries / scen. | MRM before fault | uncertified MRM |',
         '|---|---|---|---|---|---|---|---|---|']
    for c, rows in data.items():
        ks = sorted(common)
        miss = [k for k in ks if 'nofault_coll' not in rows[k]]
        coll = [1.0 if rows[k]['nofault_coll'] < 1 else 0.0 for k in ks if k not in miss]
        ttc = [rows[k].get('ttc_ok', np.nan) for k in ks]
        prog = [rows[k].get('progress', np.nan) for k in ks]
        sc = [rows[k].get('score', np.nan) for k in ks]
        mrm = [rows[k]['mrm_entries'] for k in ks]
        pre = sum(rows[k]['mrm_before_fault'] for k in ks)
        unc = sum(rows[k]['uncertified'] for k in ks)
        m = dict(n=len(ks), missing_metric=len(miss), collision=float(np.mean(coll)) if coll else float('nan'), collision_ci=boot(coll), collided=[k for k in ks if k not in miss and rows[k]['nofault_coll'] < 1],
                 ttc=float(np.nanmean(ttc)), progress=float(np.nanmean(prog)), score=float(np.nanmean(sc)), score_ci=boot(sc),
                 mrm_per_scen=float(np.mean(mrm)), mrm_before_fault=pre, uncertified=unc,
                 ood_steps=sum(rows[k]['ood_steps'] for k in ks), steps=sum(rows[k]['steps'] for k in ks),
                 mrm_steps_per_scen=float(np.mean([rows[k]['mrm_steps'] for k in ks])))
        m['ood_frac'] = m['ood_steps'] / max(1, m['steps'])
        out['conditions'][c] = m
        L.append(f"| {c} | {m['n']} | {100*m['collision']:.1f}% [{100*m['collision_ci'][0]:.1f}, {100*m['collision_ci'][1]:.1f}] | "
                 f"{m['ttc']:.3f} | {m['progress']:.3f} | {m['score']:.3f} [{m['score_ci'][0]:.3f}, {m['score_ci'][1]:.3f}] | "
                 f"{m['mrm_per_scen']:.2f} | {pre} | {unc} |")
    L += ['', '| Condition | MRM steps / scen. (0.1 s) | out-of-ODD step fraction |', '|---|---|---|']
    for c, m in out['conditions'].items():
        L.append(f"| {c} | {m['mrm_steps_per_scen']:.1f} | {m['ood_frac']:.3f} |")
    # paired collision differences raw -> tsmx
    L += ['', 'Paired (same scenario) collision changes raw -> tsmx:']
    for f, x, y in (('none', 'raw', 'tsmx'), ('blind', 'raw', 'tsmx'), ('stale', 'raw', 'tsmx'),
                    ('stale', 'raw', 'tsmxc'), ('stale', 'tsmx', 'tsmxc')):
        a, b = data.get(f + '_' + x), data.get(f + '_' + y)
        if not (a and b):
            continue
        ks = sorted(common)
        ks = [k for k in ks if 'nofault_coll' in a[k] and 'nofault_coll' in b[k]]
        ca = np.array([a[k]['nofault_coll'] < 1 for k in ks]); cb = np.array([b[k]['nofault_coll'] < 1 for k in ks])
        diff = (cb.astype(float) - ca.astype(float))
        d = dict(n_pairs=len(ks), diff_rate=float(diff.mean()), diff_ci=boot(diff), avoided=int((ca & ~cb).sum()), introduced=int((~ca & cb).sum()), both=int((ca & cb).sum()),
                 introduced_tokens=[k for k, x, y in zip(ks, ca, cb) if y and not x])
        out['conditions'][f'{f}_{x}_vs_{y}_paired'] = d
        L.append(f"- {f} {x}->{y}: avoided {d['avoided']}, introduced {d['introduced']} {d['introduced_tokens']}, both {d['both']}")
    L += ['', 'TSM-X soundness is claimed for its 1D constant-velocity world model only; reactive agents, cut-ins and lateral',
          'motion are outside it, so nuPlan collisions are an empirical measurement, not a verified property.']
    (HERE / 'results').mkdir(exist_ok=True)
    (HERE / 'results' / 'w8_summary.json').write_text(json.dumps(out, indent=1))
    (HERE / 'W8_REPORT.md').write_text('\n'.join(L) + '\n')
    print('\n'.join(L))


if __name__ == '__main__':
    main()
