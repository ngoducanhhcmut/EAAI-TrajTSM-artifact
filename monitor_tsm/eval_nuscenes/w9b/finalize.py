"""Summarize completed replay, validation and limitations; never infer RTL PASS."""
import json,pickle,hashlib,time,struct
from collections import Counter
from dataclasses import replace
import numpy as np
from packetizer import *
from replay import metrics,save,w7

def main():
    s=json.loads((HERE/'summary.json').read_text());c=pickle.loads((HERE/'inputs.pkl').read_bytes())
    grouped={p:[] for p in 'HT'};ingress={};b1={p:Counter() for p in 'HT'}
    allout={p:Counter() for p in 'HT'};host={p:0 for p in 'HT'}
    frame={r['token']:r for r in c['frames']}
    for line in (HERE/'replay.jsonl').open():
        row=json.loads(line);label=row['source'];key=label,row['scene'];d=row['input']
        ing=ingress.get(key,g.Ingress());e=g.Ego(**d['ego']);pkt=None
        if d.get('pkt'):
            pk=d['pkt'];p=pk['plan'].copy();p['snapshot']=g.Ego(**p['snapshot'])
            pkt=g.Packet(g.Plan(**p),pk['crc'],tuple(pk['snapshot_ids']),pk['schema'])
        ni,reason=g.b1_ingress(ing,d['now'],e,pkt)
        ingress[key]=ni if row['response']['accept'] else replace(ing,last_time=d['now'])
        o=row['response'];mode=row['mode']
        category='accepted' if o['accept'] else 'backup' if mode=='L1' else 'fallback' if mode=='L2' else 'hold' if mode=='HOLD' else 'mitigation'
        allout[label][category]+=1
        if row['kind']=='admission':
            b1[label][reason]+=1;host[label]+=row['host_object_guard']
            # Also expose the temporally aligned label without altering the
            # registered comparator: shift knots so W7's ts+.5 queries ts+.1.
            records=frame[row['token']]['objects']
            shifted=[dict(r,times=[t+.4 for t in r['times']]) for r in records]
            row['registered_oracle']=row['oracle'];row['oracle']=w7.oracle(tuple(row['q']),shifted)
            grouped[label].append(row)
    s['b1_reasons']={p:dict(b1[p]) for p in 'HT'}
    s['all_transaction_outcomes']={p:dict(allout[p]) for p in 'HT'}
    s['host_object_guard_counts']=host
    for p in 'HT':s['counts'][p]['admitted']=b1[p]['ok']
    s['definitions']=dict(admitted='passes B1 ingress; does not imply system acceptance',
                          accepted='tsmx_cycle accept; B1/B2/B9/front gate and bridge/tail pass',
                          fallback='rejected admission with issued L2 command',
                          mitigation='rejected admission in L3; HOLD and backup reported separately')
    s['metrics_aligned_100ms']={p:metrics(grouped[p]) for p in 'HT'}
    s['scenes_with_admissions']={p:len(set(r['scene'] for r in grouped[p])) for p in 'HT'}
    packet_gaps=[]
    for scene in c['scenes']:
        times=sorted(r['now'] for r in grouped['H'] if r['scene']==scene)
        packet_gaps.extend(np.diff(times).tolist())
    s['odd_packet_gap_us']=dict(median=float(np.median(packet_gaps)),max=max(packet_gaps))
    s['deviations'].append('Planner packets are only issued for W7 ODD keyframes (~2 Hz), not fabricated at 10 Hz; no-packet service resets recovery streaks, so L0 occupancy is zero.')
    s['supervisor_occupancy_jobs']={p:{m:s['supervisor_occupancy_jobs'][p].get(m,0) for m in g.MODES} for p in 'HT'}
    intervals=np.concatenate([np.diff(np.unique([r['timestamp'] for r in rows])) for rows in c['sweeps'].values()])
    s['lidar_sweep_spacing_us']=dict(n=len(intervals),median=float(np.median(intervals)),
                                    p95=float(np.percentile(intervals,95)),max=int(intervals.max()))
    s['constants']=dict(apply_delay_s=.1,waypoint_times_s=[.5,1.],freshness_ms=150,
                        splice_position_m=.16,splice_velocity_mps=.2,ack_limit_ms=40,
                        service_period_us=100000,raw_width_bits=48037,hex_digits=12010,
                        absent_front_station_m=9999,oracle_step_s=.001,oracle_track_limit_s=3.,
                        stopping_hold_s=2.,tsm_response_deadline_cycles=1874999,tsm_clock_hz=100000000,
                        workers=4,free_space_requirement_gib=10)
    s['timing_us'].update(firmware=5000,transfer=35000,delivery=99000)
    s['timing_us'].pop('firmware_transfer',None)
    s['compute_field']=dict(encoded=5000,golden_limit=10000,interpretation='legacy Plan default; golden source does not specify physical units; not a measured planner duration')
    s['deviations']=[v for v in s['deviations'] if not v.startswith('B1 compute=')]
    s['deviations'].append('compute=5000 retains the golden Plan default; physical-unit mapping of this field is unresolved. Planner/firmware elapsed timing is an independent assumption.')
    s['checks']=json.loads((HERE/'checks.json').read_text())
    s['icarus']=json.loads((HERE/'smoke.json').read_text())
    s['icarus']['error_lines']=[299,300,301]
    base=HW.parents[1]
    files=[base/'sw/eval_trainval/out/pred_hw_new.npy',base/'sw/eval_trainval/out/dataset.npz',
           base/'sw/golden_spec/summary.csv',HW/'golden/tsmx_golden/model.py',
           HW/'tb/integ/gen_sequences.py',HW.parents[0]/'manuscript_v5/sections/03_architecture.tex']
    s['provenance']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    s['cosim_sources']=json.loads((HERE/'cosim_0103.json').read_text())['sources']
    deltas=[]
    for source in s['cosim_sources']:
        wp=np.array([struct.unpack('>f',bytes.fromhex(word))[0]
                     for word in Path(source['path']).read_text().split()[:8]]).reshape(4,2)
        deltas.append(float(np.max(np.abs(wp-c['plans'][source['token']]))))
    s['cosim_rtl_vs_saved_hw_new_max_abs_m']=max(deltas)
    s['cosim_token_order_consecutive']=all(c['samples'][s['cosim_sources'][i]['token']]['next']==s['cosim_sources'][i+1]['token'] for i in range(34))
    s['deviations'].append(f"The available 35 RTL dumps differ from the saved RQ1 hw_new predictions by up to {max(deltas)} m; file hashes and token mapping are retained. Revision equivalence is not established here.")
    fa=[dict(comparator=kind,**row) for label in 'HT' for row in grouped[label]
        for kind,oracle in [('registered',row['registered_oracle']),('aligned_100ms',row['oracle'])]
        if row['response']['accept'] and oracle['label']=='UNSAFE']
    (HERE/'false_accepts.jsonl').write_text(''.join(json.dumps(row)+'\n' for row in fa),encoding='utf8')
    s['false_accept_audit_records']=len(fa)
    s['free_bytes_end']=__import__('shutil').disk_usage('C:/').free
    s['verilator_commands']=[f'./obj_2/Vtb_m_tsmx_top +FILE=../../eval_nuscenes/w9b/{name}.mem +LIMIT={s[key]} +ALLOW_INACTIVE > ../../eval_nuscenes/w9b/verilator_{name}.log 2>&1' for name,key in [('cosim_0103','cosim_jobs'),('replay_rtl_subset','subset_jobs')]]
    s['deviations']=list(dict.fromkeys(s['deviations']))
    save('summary.json',s)
    def triple(p,key):
        d=s['derivative_errors'][p][key]
        return '/'.join(f'{d[k]:.6f}' for k in ('mean','p95','max'))
    def rate(d):
        if d['denominator']==0:return 'N/A (0 denominator)'
        lo,hi=d['ci95_pct']
        return f"{d['n']}/{d['denominator']} = {d['rate_pct']:.3f}% [{lo:.3f}, {hi:.3f}]"
    lines=['# W9b: full-packet replay at +0.1 s; golden complete, TSM RTL replay pending','',
      f"Coverage: {s['scenes']} validation scenes visited; {s['eligible_frames']} W7-eligible frames, {s['odd_frames']} ODD frames/source; scenes with admissions H/T = {s['scenes_with_admissions']['H']}/{s['scenes_with_admissions']['T']}.",
      f"T reuses saved RQ1 `../sw/eval_trainval/out/pred_hw_new.npy`, matched by `dataset.npz` token; missing tokens {len(s['missing_T_tokens'])}. No W9a shards were present.",
      'H uses ego-pose future positions at 0.5/1.0 s; both use manuscript eq. plannerpacket at +0.1 s; no velocity clipping.',
      'Continuous independent H/T histories reset only per scene, at first ODD admission; no preload. Non-ODD intervals retain command-driven service history.',
      'Assumed schedule (not measured): planner 40 ms, firmware 5 ms, transfer 35 ms; admission +80 ms, delivery +99 ms, apply/ACK +100 ms.',
      'The 19 ms admission-to-delivery allowance accommodates the stated 1,874,999-cycle deadline at 100 MHz; transport/clock assumptions remain unvalidated.',
      'Packet `compute=5000` retains the golden Plan default (limit 10000); its physical-unit mapping is unresolved. Wall-time schedule is a separate assumption. Sequence/IDs increase; CRC uses golden ABI.',
      'Snapshot timestamp and generated timestamp are tr; apply=tr+100000 us; common snapshot IDs; context-bound lease expires at tr+500000 us.',
      f"LIDAR_TOP ego_pose spacing median/p95/max: {s['lidar_sweep_spacing_us']['median']:.0f}/{s['lidar_sweep_spacing_us']['p95']:.0f}/{s['lidar_sweep_spacing_us']['max']} us.",
      'Ego at tc uses irregular central pose differences and linear interpolation; acceleration uses three-point differences. Offline future poses are used, not CAN measurements.',
      'Executor idealization: command-tail tracking between measurements, ACK at apply (20 ms after issue). Each admission reanchors measured ego; physical tracking is not established.',
      'Every 100 ms service plus explicit apply/ACK calls the unmodified system; no-packet timeouts/freeze checks and lease/backup history remain active.',
      f"Packets use dataset keyframes, not synthetic 10 Hz plans: ODD packet gap median/max {s['odd_packet_gap_us']['median']:.0f}/{s['odd_packet_gap_us']['max']} us. No-packet service breaks recovery streaks; L0 occupancy is zero.",
      'Objects use W7 corridor projection, causal previous/current annotation velocity; unknown velocity retains raw input and withholds certificate, failing closed.',
      f"Object velocity difference chain min/mean/max: {s['annotation_velocity_chain_us']['min']}/{s['annotation_velocity_chain_us']['mean']:.1f}/{s['annotation_velocity_chain_us']['max']} us; latest input is tr, VA age to checked tc is 80000 us.",
      'VA is W7 reduce_neg with parameterized latency, no rear drop; common cover spans maximum legal live/plan tail plus bridge. No range clipping.',
      'Lead scalar uses nearest conservative front bumper from that world; absent front is a stationary sentinel at station 9999 m (ABI lacks absence bit).',
      'Persistent arc-length station offsets retain scalar history while reference axes rotate per frame; lateral dynamics are abstracted.',
      '', '| Source | Attempts | B1 admitted | System accepted | Issued fallback | Backup | Mitigation | HOLD |',
      '|---|---:|---:|---:|---:|---:|---:|---:|']
    for p in 'HT':
        d=s['counts'][p];lines.append('| '+p+' | '+' | '.join(str(d.get(k,0)) for k in ('attempts','admitted','accepted','fallback','backup','mitigation','hold'))+' |')
    lines+=['','Admission reason-code histogram:','']
    for p in 'HT':lines.append(f"- {p}: {json.dumps(s['admission_reasons'][p],sort_keys=True)}")
    lines+=['','Supervisor occupancy in transactions (not wall time), including no-packet service:','']
    for p in 'HT':lines.append(f"- {p}: {json.dumps(s['supervisor_occupancy_jobs'][p],sort_keys=True)}; commit results {json.dumps(s['commits'][p],sort_keys=True)}")
    lines+=['','Registered W7 oracle is unchanged, including its +0.5 s object offset; applying its labels to +0.1 s packets has an epoch mismatch. Aligned labels are additionally reported below.',
      f"Rates are percent, scene-bootstrap 95% percentile intervals, 2000 draws, seed 20261104; oracle UNKNOWN H/T = {s['metrics']['H']['oracle_unknown']}/{s['metrics']['T']['oracle_unknown']}, excluded from FA/FR denominators.",'',
      '| Source/comparator | Acceptance | FR / SAFE | FA / UNSAFE |','|---|---|---|---|']
    for key,name in [('metrics','registered'),('metrics_aligned_100ms','aligned +0.1 s')]:
        for p in 'HT':lines.append('| '+p+' '+name+' | '+' | '.join(rate(s[key][p][k]) for k in ('acceptance','false_reject','false_accept'))+' |')
    lines+=['','Absolute encoding error versus measured ego at tr+0.1 s; mean/p95/max:',
      '| Source | Position m | q-prime error m/s | q-double-prime error m/s² | >16 cm / >20 cm/s / either | B2 failures |',
      '|---|---|---|---|---|---|']
    for p in 'HT':
        e=s['derivative_errors'][p]
        lines.append(f"| {p} | {triple(p,'position_error_m')} | {triple(p,'velocity_error_mps')} | {triple(p,'acceleration_error_mps2')} | {e['position_over_16cm']}/{e['velocity_over_20cmps']}/{e['either_over_tolerance']} | {e['b2_reject']} |")
    lines+=['Error threshold exceedance is distinct from B2: B2 compares the complete propagated live uncertainty tube; acceleration has no ±20 cm/s splice threshold.',
      f"Scene-0103: 35 consecutive RTL planner outputs (`../tb/e2e/results/wp_rtl_s00.txt` … `wp_rtl_s34.txt`), token mapping `../sw/golden_spec/summary.csv`; {s['cosim_jobs']} physical TSM jobs.",
      f"These available RTL dumps differ from saved RQ1 hw_new by max {s['cosim_rtl_vs_saved_hw_new_max_abs_m']:.9f} m; exact revision equivalence is unresolved. Dumps are used as requested, with hashes retained.",
      f"RTL subset: first {s['subset_admission_attempts']} admission attempts in validation sequence order (H), including ACK/service history: {s['subset_jobs']} jobs; resets only between scenes.",
      'All expected response/command/ingress/supervisor/event bits come from golden and gen_sequences command projection; manifests include full inputs and planner dump hashes.',
      f"Independent analytic quadratic/B1/B2 check and complete golden bit regeneration: {json.dumps(s['checks'],sort_keys=True)}.",
      f"Icarus compile exit {s['icarus']['compile_exit']}; {s['icarus']['simulated_jobs']} jobs simulated; engine.sv lines 299–301 syntax errors. No TSM RTL agreement claimed.",
      f"Measured extraction/augmentation/replay times: {s['prepare_seconds']:.2f}/{s['augment_seconds']:.2f}/{s['replay_seconds']:.2f} s; four detached workers; free C: start/end {s['free_bytes_start']/2**30:.3f}/{s['free_bytes_end']/2**30:.3f} GiB.",
      'Reproduce: `py -3.9 -B prepare.py`, `augment.py`, `replay.py`, `check.py`, `smoke.py`, `finalize.py` (paths under this directory); replay also supports four `--worker i 4` processes plus `--shards` aggregation.',
      'Claude: from `tsmx_hw/tb/integ` in WSL, use existing r17 binary:', '```sh',*s['verilator_commands'],'```',
      'Limitations: conditional firmware/executor timing, pose-derived open-loop state, scalar coordinate abstraction and original GT-track hold assumptions. These artifacts establish a replay chain, not physical closed-loop safety.']
    assert len(lines)<=80,len(lines)
    (HERE/'W9B_REPORT.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    print('report lines',len(lines));print(json.dumps(s['counts'],indent=2))
if __name__=='__main__':main()
