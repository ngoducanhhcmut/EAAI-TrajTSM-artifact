import json
from dataclasses import replace
from tsmx_golden import model as g

def run(out):
    cases=[]
    def check(block,name,value):cases.append(dict(block=block,name=name,pass_=bool(value)))
    e=g.Ego(1000000,0,6*g.S,0,40*g.S,0)
    p=g.Plan(1,e,e.t,e.t+g.DT,600000,e.v,0)
    c=g.certify(p,e.t+500000)
    tr=g.b4_mrmgen(0,g.S,0,0)
    for i in range(12):
        ee=replace(e,x=i*g.S,lx=(40+i)*g.S)
        pp=replace(p,snapshot=ee,x=ee.x+600000,seq=i+1)
        pkt=g.packet(pp)
        scenarios=[(pkt,'ok'),(replace(pkt,crc=pkt.crc^1),'crc'),
                   (g.packet(replace(pp,seq=0)),'ok'),(g.packet(replace(pp,count=33)),'overflow'),
                   (g.packet(replace(pp,compute=10001)),'deadline'),
                   (g.packet(replace(pp,schema=2)),'range_schema'),
                   (g.packet(replace(pp,a=g.NAN)),'numeric'),
                   (g.packet(replace(pp,snapshot=replace(ee,t=e.t+1))),'freshness'),
                   (g.packet(replace(pp,snapshot=replace(ee,t=e.t-150001))),'freshness'),
                   (g.packet(replace(pp,v=10*g.S+1)),'range_schema'),
                   (replace(pkt,snapshot_ids=(1,2,1)),'snapshot'),(None,'timeout')]
        inp,expected=scenarios[i]
        check('b1',expected,g.b1_ingress(g.Ingress(),e.t,ee,inp)[1]==expected)
        offsets=[0,100000,110000,150000,160000,-100000,-110000,-160000,1,-1,1000000,-1000000]
        px=replace(pp,x=pp.x+offsets[i])
        from oracle import splice
        check('b2',f'tube_offset_{offsets[i]}',not g.b2_splice(ee,px) or splice(ee,px,g.S))
        motion=g.Motion((20 if i%2==0 else 4)*g.S,0)
        geom=g.b3_geom(tr,(motion,)*([1,2,32][i%3]))
        check('b3',f'objects_{i}',geom.accept==(i%2==0))
        tt=g.b4_mrmgen(0,(i+1)*500000,-(i%3)*g.S,i%16)
        check('b4',f'profile_{i}',tt.accept and tt.rows[-1][4]==0 and tt.rows[-1][0]>=tt.stop+2*g.T)
        pool=[g.GeomResult(k==i,0,'ok',1) for k in range(16)]
        cid,label=g.b7_select(pool)
        check('b7',f'pool_{i}',cid==(i if g.LIBRARY[i][1] else 15))
        state=g.b8_fsm(g.Supervisor(),i%2==0,0 if i%3==0 else g.S,
                       reusable=i%4==0,fallback=i%5!=0,reset=i==11)
        expected_mode=('L3' if i==11 else 'RECOVERY' if i%2==0 else 'HOLD' if i%3==0 else 'L2' if i%5!=0 else 'L3')
        check('b8',f'transition_{i}',state.mode==expected_mode)
        cc=c if i%2==0 else replace(c,config=i+2)
        check('b9',f'tamper_{i}',g.b9_cert(p,cc,e.t)==('ok' if i%2==0 else 'binding'))
        rec=g.Recorder(capacity=i+1)
        for k in range(2*(i+1)):rec=g.b10_rec(rec,(k,'fault'))
        check('b10',f'ring_{i}',len(rec.events)==i+1 and rec.lost==i+1 and rec.events[-1][0]==2*i+1)
        check('b13',f'parity_{i}',g.b13_health((i,),(i.bit_count()&1,),fsm_onehot=1<<(i%6))
              and not g.b13_health((i,),(1^(i.bit_count()&1),)))
        st,o=g.tsmx_cycle(g.Supervisor(),dict(now=e.t,ego=e,pkt=g.packet(p),cert=c,reset=i%2==1))
        check('system',f'cycle_{i}',o['accept']==(i%2==0) and (i%2==0 or o['independent_brake']))
    # Named boundary/security tests supplement >=12 cases per block.
    wrapped=replace(e,t=0xfffffff0)
    wp=replace(p,snapshot=wrapped,generated=wrapped.t,apply=(wrapped.t+g.DT)&g.MASK)
    check('b1','timestamp_wrap',g.b1_ingress(g.Ingress(),wrapped.t,wrapped,g.packet(wp))[1]=='ok')
    check('b1','seq_wrap',g.b1_ingress(g.Ingress(seq=0xffffffff),e.t,e,g.packet(replace(p,seq=0)))[1]=='ok')
    check('b1','clock_reset',g.b1_ingress(g.Ingress(last_time=e.t+1),e.t,e,g.packet(p))[1]=='clock_reset')
    check('b1','no_sample_freeze',g.b1_ingress(g.Ingress(last_sample=0),400000,e,None)[1]=='freeze_no_sample')
    check('b1','motion_freeze',g.b1_ingress(g.Ingress(signature=(p.x,p.v,p.a,p.tail),freeze_x=-g.S),e.t,e,g.packet(p))[1]=='freeze')
    check('b3','object_overflow',not g.b3_geom(tr,(g.Motion(20*g.S,0),)*33).accept)
    check('b3','lane_boundary',g.b3_geom(tr,(),lane=(-g.S,g.S)).accept and not g.b3_geom(tr,(),lane=(-g.S+1,g.S)).accept)
    check('b3','interior_min',g.swept(1000,0,2*g.S,g.S,0,100000)<0)
    check('b4','bad_range',not g.b4_mrmgen(0,10*g.S+1,0,0).accept)
    check('b4','phase_straddle',not g.b4_mrmgen(0,g.S,0,0,20000).accept)
    check('b8','first_fault',g.b8_fsm(g.Supervisor(mode='L0'),False,g.S).fault_latched)
    check('b8','startup_no_backup',g.Supervisor().mode=='L3' and not g.Supervisor().backup)
    check('b8','reset_mrm',g.b8_fsm(g.Supervisor(mode='L1'),False,g.S,reset=True).mode=='L3')
    check('b9','executor_expiry',g.b9_cert(p,c,c.t_e,True,e.t,True)=='expiry_at_executor')
    check('b9','ack_timeout',g.b9_cert(p,c,e.t+40000,True,e.t,False)=='ack_timeout')
    check('b9','replay',g.b9_cert(p,c,e.t,expected_seq=2)=='replay')
    check('b9','toctou',g.b9_cert(replace(p,x=p.x+1),c,e.t,True)=='binding')
    check('b13','onehot',not g.b13_health(fsm_onehot=3))
    check('b13','cross_lane',not g.b13_health(lane_pair=(True,False)))
    for gap in (3,4,5,6,10,20):
        ee=g.Ego(0,0,6*g.S,-8*g.S,(gap*g.S)+4800000,0)
        xx,vv=g.advance(0,ee.v,ee.a,g.DT)
        pp=g.Plan(1,ee,0,g.DT,xx,vv,0)
        st,o=g.tsmx_cycle(g.Supervisor(),dict(now=0,ego=ee,pkt=g.packet(pp),cert=g.certify(pp,500000)))
        check('system',f'apply_tail_binding_{gap}',not o['accept'] or bool(st.pending) and st.pending[1].tail!=15)
    world=(g.Motion(40*g.S,0),g.Motion(60*g.S,0))
    wc=g.certify(p,e.t+500000,world)
    _,wo=g.tsmx_cycle(g.Supervisor(),dict(now=e.t,ego=e,pkt=g.packet(p),cert=wc,objects=world))
    check('system','multi_object_accept',wo['accept'])
    _,bad=g.tsmx_cycle(g.Supervisor(),dict(now=e.t,ego=e,pkt=g.packet(p),cert=wc,objects=world+(g.Motion(4*g.S,0),)))
    check('b9','world_toctou',bad['reason']=='context_binding')
    _,bad=g.tsmx_cycle(g.Supervisor(),dict(now=e.t,ego=e,pkt=g.packet(p),cert=wc,objects=world,lane=(-900000,900000)))
    check('b9','map_toctou',bad['reason']=='context_binding')
    summary=dict(passed=all(c['pass_'] for c in cases),n=len(cases),cases=cases)
    (out/'unit_golden_results.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print('UNIT',summary['passed'],[c for c in cases if not c['pass_']],flush=True)
    return summary
