"""Regenerate every expected bit and audit the firmware numerical/CRC contract."""
import sys
sys.dont_write_bytecode=True
import json, zlib, hashlib
from dataclasses import replace
import gen_e2e_vectors as v

def sv_packet(p, wp):
    # Independent arithmetic form used by the SV firmware model.
    s=p.snapshot
    a=round(max(-8.,min(2.,2*sum(float(v.fw._fit[1,k])*wp[k] for k in range(4))))*1e6)
    if 0<=s.v<=20000000 and -8000000<=s.a<=2000000:
        dx=s.v*s.v//(-2*s.a) if s.a<0 and 100000*(-s.a)>=s.v*1000000 else (20*s.v+s.a)//200
        x=s.x+dx;vel=max(0,(10*s.v+s.a)//10)
    else:
        x=round(float(s.x)+float(s.v)*.1+.5*float(s.a)*.1*.1)
        vel=round(float(s.v)+float(s.a)*.1)
    return v.g.packet(replace(p,x=x,v=vel,a=a),(p.seq,)*3)

def main():
    h=v.HERE;m=json.loads((h/'manifest.json').read_text())
    rows=(h/'vectors.mem').read_text().splitlines()
    fmap=[int(x,16) for x in (h/'frames.mem').read_text().splitlines()]
    old=json.loads((v.HW/'eval_nuscenes/w9b/cosim_0103.json').read_text())
    assert hashlib.sha256((v.HW/'eval_nuscenes/w9b/cosim_0103.json').read_bytes()).hexdigest()==m['source_manifest_sha256']
    assert len(rows)==len(fmap)==len(m['jobs'])==207
    assert [r['now'] for r in m['jobs']]==[r['now'] for r in old['jobs_meta']]
    for path,sha in m['reference_sha256'].items():
        assert hashlib.sha256((v.BASE/path).read_bytes()).hexdigest()==sha,path
    state=v.g.Supervisor();mut=m['mutant']; witnessed=False; firmware_mismatches=[]
    recorded=v.words(h/'recorded_wp.mem')
    assert len(recorded)==280 and mut['frame']==7
    max_delta=0.
    for idx,(row,bits) in enumerate(zip(m['jobs'],rows)):
        d=v.enc.inputs(row['input'])
        ns,o,expected=v.packed(state,d,idx==0)
        assert expected==int(bits,16),idx
        assert fmap[idx]==row['frame']+1
        if row['frame']>=0:
            frame=m['frames'][row['frame']];p=d['pkt'].plan
            fi=row['frame']
            rtlws=v.words(v.BASE/f'tb/e2e/results/final_35/wp_rtl_s{fi:02d}.txt')
            assert len(rtlws)==9 and rtlws[8]==0
            assert frame['recorded_rtl_words']==recorded[fi*8:fi*8+8]==rtlws[:8]
            refpath=next(p for p in m['reference_sha256'] if v.Path(p).name==f's{fi:02d}_wp.hex')
            assert frame['planner_reference_words']==v.words(v.BASE/refpath)
            delta=max(abs(a-b) for a,b in zip(v.floats(rtlws[:8]),v.floats(frame['planner_reference_words'])))
            max_delta=max(max_delta,delta); assert delta<=0.000021
            assert frame['firmware_words']==(frame['planner_reference_words'] if m['waypoint_source']=='reference_documentation_only' else rtlws[:8])
            wp=v.floats(frame['firmware_words'])[::2]
            pk=sv_packet(p,wp)
            assert pk==d['pkt'],('SV arithmetic differs',row['frame'],pk,d['pkt'])
            body=v.g.pack_packet_body(p,(p.seq,)*3)
            c=0xffffffff
            for byte in body:
                c^=byte
                for _ in range(8): c=(c>>1)^(0xedb88320 if c&1 else 0)
            assert c^0xffffffff==zlib.crc32(body)==pk.crc
            if sv_packet(p,v.floats(rtlws[:8])[::2])!=pk:
                firmware_mismatches.append(row['frame'])
            if idx==mut['job']:
                mw=list(frame['firmware_words']);mw[0]=mut['value']
                md=dict(d,pkt=sv_packet(p,v.floats(mw)[::2]))
                _,mo,mb=v.packed(state,md,idx==0)
                assert md['pkt']!=d['pkt'] and mut['packet_changed']
                assert o['accept'] and not mo['accept'] and mo['reason']=='binding'
                assert (o['accept'],mo['accept'],o['reason'],mo['reason'])==(mut['expected_accept'],mut['mutated_accept'],mut['expected_reason'],mut['mutated_reason'])
                assert ((mb & ((1<<3363)-1)) != (expected & ((1<<3363)-1)))==mut['golden_output_changed']
                witnessed=True
        state=ns
    assert witnessed
    if m['waypoint_source']=='recorded_final_35': assert not firmware_mismatches
    result=dict(golden_jobs_regenerated=207,firmware_packets=35,crc_checks=35,
                waypoint_source=m['waypoint_source'],recorded_word_checks=280,
                max_reference_waypoint_delta_m=max_delta,
                timestamps_match_w9b=True,mutant_golden_witness=mut,
                saved_rtl_packet_mismatches=firmware_mismatches,rtl_simulated_jobs=0)
    (h/'checks.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))

if __name__=='__main__':main()
