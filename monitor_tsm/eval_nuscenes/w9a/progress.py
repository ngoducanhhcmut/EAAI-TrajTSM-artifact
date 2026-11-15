"""Read-only progress query for the detached W9a run."""
import plans_hw as p

result = dict(status=p.json.loads((p.OUT/'status.json').read_text()))
for stage in ('gate','full'):
    n=0
    for path in p.OUT.glob('build_'+stage+'_*.npz'):
        with p.np.load(path) as d:
            n+=len(d['i'])
    result['built_'+stage]=n
    n=bad=0
    maximum=0.
    for path in p.OUT.glob(stage+'_*.jsonl'):
        with path.open(encoding='utf-8') as f:
            for line in f:
                try:
                    r=p.json.loads(line)
                except p.json.JSONDecodeError:
                    continue
                n+=1
                if stage=='gate':
                    bad+=not r['exact']
                    maximum=max(maximum,r['max_abs_diff'])
    result['inferred_'+stage]=n
    if stage=='gate':
        result.update(gate_mismatches=bad,gate_max_abs_diff=maximum)
n=0
for path in p.OUT.glob('replay_*.jsonl'):
    with path.open(encoding='utf-8') as f:
        n+=sum(1 for line in f if line.endswith('\n'))
result['replayed_plans']=n
launch=p.OUT/'w9a3_launch.json'
if launch.exists():
    import datetime
    metadata=p.json.loads(launch.read_text())
    started=datetime.datetime.fromisoformat(metadata['log_created_utc'])
    result['full_elapsed_minutes'] = round((datetime.datetime.now(datetime.timezone.utc)-started).total_seconds()/60, 1)
    result['free_gb'] = round(p.shutil.disk_usage('C:/').free/1e9, 2)
print(p.json.dumps(result))
