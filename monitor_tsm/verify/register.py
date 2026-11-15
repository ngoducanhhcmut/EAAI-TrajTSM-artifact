"""Freeze protocol, source hashes and new ICs BEFORE validation/test execution."""
import hashlib,json,time,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tsmx_hw/verify'
sys.dont_write_bytecode=True
sys.path[:0]=[str(ROOT/'tsm2_pilot/vendor'),str(ROOT/'tsm2_pilot/src')]

def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,sort_keys=True,indent=2)+'\n',encoding='utf-8')

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    from tsm2.p5 import p5bd_v2 as ref
    reg=OUT/'registration.json'
    if reg.exists():raise RuntimeError('registration immutable')
    sources=['tsmx_hw/PLAN.md','tsm_research/TSM_X_DESIGN_v2.md','tsm_research/P5bd2_REPORT.md',
             *['tsm2_pilot/src/tsm2/p5/'+s+'.py' for s in ('executor_ref_v2','executor_ref','p5bd_v2','candidates','dynamics','contract_v2')],
             'tsm2_pilot/src/tsm2/numeric.py','tsm2_pilot/src/tsm2/baselines/support_adaptive.py']
    for name,n,seed in [('v1',200,1947283101),('v3',100,1947283102)]:
        write(OUT/(name+'_scenarios.json'),ref.make_scenarios(seed,n,'g1_'+name))
    data=dict(utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
              seeds=dict(v1=1947283101,v3=1947283102,v2=1947283103,bootstrap=1947283104,vectors=1947283105),
              V1=dict(IC=200,rollouts=22000,faults=list(ref.FAULTS),schedules=list(ref.SCHEDULES),models=['F2','F3'],
                      compare='shadow golden on every reference decision input; mode/accept/candidate union; commit mirrored at physical .02 steps',
                      gate='union disagreement <= .005 and zero golden accept/reference safety reject'),
              V2=dict(n=1000000,allocation='250000 cases per B2/B3/B4/B7; random plus deterministic boundaries',
                      oracle='independent Fraction continuous stop-clipped quadratic/sample-hold model; all accepted cases checked',
                      gate='zero counterexamples; random testing is not a universal proof'),
              V3=dict(IC=100,paired_rollouts=11000,models=['F2','F3'],bootstrap=2000,
                      gate='front=0; separately F2,F3,pooled: CI includes zero OR upper<=0',
                      wrapper='unchanged run/dynamics/follower; replace Executor, geometry, choose, select_tail, seal_tail only'),
              budget=dict(workers=1,bytes=2000000000,seconds=21600),
              stopping='checkpoint each IC; stop before 6h, incomplete stages INCONCLUSIVE; no tuning on test',
              assumptions=['B4 continuous jerk ramp; d2 midpoint sample-hold is an explicit numerical discrepancy source',
                           'axis-aligned straight lane; no yaw; bounded longitudinal actors, tracking uncertainty in footprints',
                           'hold checked 2s beyond zero speed; stationary/no reverse front actors',
                           'serial timestamp/seq modular difference valid within half of uint32 period'],
              sources={s:sha(ROOT/s) for s in sources},
              scenario_hashes={s:sha(OUT/(s+'_scenarios.json')) for s in ('v1','v3')})
    data['registration_hash']=hashlib.sha256(json.dumps(data,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    write(reg,data)
    print(data['registration_hash'])

if __name__=='__main__':main()
