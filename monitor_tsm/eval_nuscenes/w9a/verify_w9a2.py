"""Read-only numerical cross-check; all evidence writes stay inside w9a."""
import plans_hw as ph
from plans_hw import OUT,ROOT,np,json
import time
start=time.monotonic()
records=[]
for path in OUT.glob('gate_*.jsonl'):
    records.extend(json.loads(l) for l in path.read_text().splitlines())
records.sort(key=lambda r:r['i'])
assert [r['i'] for r in records]==list(range(5419))
ref=np.load(ROOT/'sw/eval_trainval/out/pred_hw_new.npy')
for r in records:
    wp=np.asarray(r['wp'],np.float32)
    assert r['max_abs_diff']==float(np.max(np.abs(wp-ref[r['i']])))
    assert r['exact']==bool(np.array_equal(wp,ref[r['i']]))
    if not r['exact']:
        r['coordinate_differences']=[dict(waypoint=int(k),axis='xy'[int(c)],reference_m=float(ref[r['i'],k,c]),computed_m=float(wp[k,c]),abs_diff_m=float(abs(wp[k,c]-ref[r['i'],k,c]))) for k,c in np.argwhere(wp!=ref[r['i']])]
import run_models as rm
import hwspec_exact as hx
rm._init('hw_new')
d=np.load(OUT/'gate_inputs.npz')
checks=[]
for r in records:
    if r['max_abs_diff']<=1e-6:continue
    i=r['i']
    # Original integer encoder and unchanged GRU implementation.
    cls_original=hx.forward(rm._W['P'],d['tok'][i],d['pad'][i])
    original=np.asarray(rm._W['gru_rtl'](np.asarray(cls_original,np.float32)),np.float32)
    ph.exact_integer_blas()
    cls_accelerated=hx.forward(rm._W['P'],d['tok'][i],d['pad'][i])
    accelerated=np.asarray(rm._W['gru_rtl'](np.asarray(cls_accelerated,np.float32)),np.float32)
    checks.append(dict(i=i,token=r['token'],original_vs_reference_max_abs_diff_m=float(np.max(np.abs(original-ref[i]))),original_vs_shard_max_abs_diff_m=float(np.max(np.abs(original-np.asarray(r['wp'],np.float32)))),original_vs_accelerated_max_abs_diff_m=float(np.max(np.abs(original-accelerated))),encoder_original_vs_accelerated_bit_exact=bool(np.array_equal(cls_original,cls_accelerated)),original_waypoints=original.tolist(),reference_waypoints=ref[i].tolist()))
ph.dump('w9a2_gate_verification.json',dict(all_gate_indices_unique_complete=True,recomputed_every_difference=True,frames=len(records),mismatches=[r for r in records if not r['exact']],above_tolerance_checks=checks,runtime_seconds=time.monotonic()-start))
print(json.dumps(checks))
