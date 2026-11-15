"""Claude 07/11/2026 (W11): confirm every unit-bench shard PASSed with all jobs completed. Exit 1 on any doubt.
The TBs compare the full B4 response/rows and the full 81-bit B3 response against golden with $fatal on mismatch,
so PASS with golden=N/N means every distinct nuPlan call (plus the original unit vectors) matched bit for bit."""
import json, re, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
man = json.loads((HERE / 'manifest.json').read_text())
bad, tot = [], {'mrmgen': 0, 'geom': 0}
for name, info in man['shards'].items():
    d = HERE / 'rtl' / name
    done = (d / 'run.done').read_text().split() if (d / 'run.done').exists() else None
    log = (d / 'run.log').read_text(errors='replace') if (d / 'run.log').exists() else ''
    n_total = info['total'][0]
    m = re.search(r'PASS (mrmgen|geom): golden=(\d+)/(\d+)', log)
    ok = done is not None and done[0] == '0' and m and int(m.group(2)) == int(m.group(3)) == n_total \
        and 'Fatal' not in log and 'assertion failed' not in log.lower()
    print(f"{name}: {'PASS' if ok else 'FAIL'} jobs={m.group(2) if m else '?'}/{n_total} nuplan={info['nuplan_jobs']}"
          f" wall_s={done[1] if done and len(done) > 1 else '?'}")
    if ok:
        tot[name.split('/')[0]] += info['nuplan_jobs']
    else:
        bad.append(name)
print(f"distinct nuPlan calls verified on RTL: B4 {tot['mrmgen']}/{man['distinct_b4']}, B3 {tot['geom']}/{man['distinct_b3']}")
if bad or tot['mrmgen'] != man['distinct_b4'] or tot['geom'] != man['distinct_b3']:
    print('FAIL:', bad); sys.exit(1)
print('ALL PASS')
