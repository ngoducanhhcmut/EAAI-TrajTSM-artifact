"""One-worker validation of performance-only bridge caches before V3 resume."""
import sys,json,time,hashlib
from pathlib import Path
from dataclasses import replace
ROOT=Path(__file__).resolve().parents[2]
sys.dont_write_bytecode=True
sys.path[:0]=[str(ROOT/'tsmx_hw/verify'),str(ROOT/'tsmx_hw/golden'),str(ROOT/'tsm2_pilot/vendor'),str(ROOT/'tsm2_pilot/src')]
import bridge as b
from tsmx_golden import model as g
r=b.ref
OUT=ROOT/'tsmx_hw/verify'

def main():
    started=time.perf_counter();checks=[]
    e=r.State(1.0,5.0,6.0,0.0,40.0,0.0)
    p=r.Plan(1,e,1.0,1.1,5.6,6.0,0.0,r.LIBRARY[15]['id'])
    plans=[replace(p,a=v) for v in (0,0.0,-0.0,-1,-1.0,-8.0)]
    certs=[b.ev2.certify(pp,1.5) for pp in plans]
    for pp in plans:
        for c in certs:
            checks.append(b.cert_int(pp,c)==b._cert_int_uncached(pp,c))
            checks.append(b.cert_int(pp,c)==b._cert_int_uncached(pp,c))
    bad=replace(p,a=float('nan'))
    checks.append(b.cert_int(bad,certs[0])==b._cert_int_uncached(bad,certs[0]))
    for pp in plans:
        for lead in ('stationary','braking'):
            ip=b.plan_int(pp)
            checks.append(b.integer_geometry(ip,lead)==g.nominal_geom(ip,lead))
    assert all(checks),'pure cache value mismatch'
    scenes=json.loads((OUT/'v3_scenarios.json').read_text())
    scene=scenes[0];target=OUT/'checkpoints/v3'/(scene['id']+'.json')
    expected=json.loads(target.read_text())
    assert expected['hash']==g.digest(expected['data'])
    b.LEAD=scene['lead'];rows=[];r.clear_caches();g.select.cache_clear()
    for model in [m for m in r.actual_models(scene['index']) if m[0] in ('F2','F3')]:
        for fault in r.FAULTS:
            for schedule in r.SCHEDULES:
                b.install('reference');a=r.run(scene,model,fault,schedule,'executor')
                b.install('golden');z=r.run(scene,model,fault,schedule,'executor')
                rows.append(dict(model=model[0],fault=fault,schedule=schedule,reference=a,golden=z))
    actual=g.digest(rows)
    result=dict(passed=actual==expected['hash'] and all(checks),typed_scalar_checks=len(checks),
                scene=scene['id'],paired_rollouts=len(rows),old_row_hash=expected['hash'],replay_row_hash=actual,
                seconds=time.perf_counter()-started,bridge_sha256=hashlib.sha256(Path(b.__file__).read_bytes()).hexdigest(),
                golden_sha256=hashlib.sha256((ROOT/'tsmx_hw/golden/tsmx_golden/model.py').read_bytes()).hexdigest(),
                cert_cache=b._cached_cert_int.cache_info()._asdict(),geometry_cache=b._cached_integer_geometry.cache_info()._asdict(),
                note='Extra replay proves bit-identical data; not counted as a new IC or statistical sample.')
    (OUT/'pure_cache_validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    history=json.loads((OUT/'runtime.json').read_text());history.append(dict(stage='pure_cache_validation',seconds=result['seconds'],peak_rss=0))
    (OUT/'runtime.json').write_text(json.dumps(history,indent=2)+'\n',encoding='utf-8')
    print('CACHE REPLAY',result['passed'],'seconds',round(result['seconds'],2),'checks',len(checks),'pairs',len(rows),flush=True)
    assert result['passed'],'full IC replay hash mismatch'

if __name__=='__main__':main()
