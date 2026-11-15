"""Finalize measured golden results; no RTL agreement is inferred."""
import sys, os, json, hashlib, subprocess
from pathlib import Path
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent

def tradeoff_line(s):
    chosen=s['validation'][s['chosen']];baseline=s['validation']['E0']
    parts=[]
    for p in 'HT':
        a=baseline[p]['metrics'];b=chosen[p]['metrics']
        parts.append(f"{p} ACCEPT {a['acceptance']['n']} -> {b['acceptance']['n']}, FA {a['false_accept']['rate_pct']:.3f}% -> {b['false_accept']['rate_pct']:.3f}%")
    return 'Validation tradeoff: '+ '; '.join(parts)+'. Training feasibility does not establish validation FA non-increase.'

def main():
    s=json.loads((HERE/'summary.json').read_text());e=s['chosen']
    old=json.loads((HERE.parent/'w9b/summary.json').read_text())
    baseline={}
    for p in 'HT':
        baseline[p]={key:s['validation']['E0'][p]['metrics'][key]==old['metrics'][p][key] for key in ('false_accept','false_reject','acceptance')}
        # W10a correctly samples all 150 clusters including empty scenes; counts
        # must match W9b, whose intervals sampled only nonempty scene clusters.
        for key in baseline[p]:
            a=s['validation']['E0'][p]['metrics'][key];b=old['metrics'][p][key]
            baseline[p][key]=a['n']==b['n'] and a['denominator']==b['denominator']
        baseline[p]['derivative_errors']=s['validation']['E0'][p]['derivative_errors']==old['derivative_errors'][p]
        assert all(baseline[p].values()),baseline
    s['E0_matches_W9b_counts_and_derivatives']=baseline
    s['training_extraction']=json.loads((HERE/'training_extraction.json').read_text())
    s['witnesses']=json.loads((HERE/'witnesses.json').read_text())
    s['checker_selftests']=json.loads((HERE/'checker_selftests.json').read_text())
    s['validation_tradeoff']=tradeoff_line(s)
    s['runtime_scope']='resumed replay and canonical export; finishing checks and earlier extraction/training attempts excluded'
    s['definitions']=dict(admitted='passes B1 ingress',accepted='full system accept',fallback='rejected admission issuing L2',mitigation='rejected admission in L3',occupancy='all transactions including service/ACK, not time',registered_oracle='unchanged W7 oracle: +0.5 s object offset applied to encoded +0.1 s state; epoch mismatch retained')
    s['limitations']=['Pose-derived offline ego is not causal CAN/IMU; measured reanchors and ideal command tracking between keyframes do not establish closed-loop tracking.',
        'Training predictions are stride-12 tokens; validation is full W9b 150-scene continuous replay. Selection is conditional on this sparse training sample.',
        'Scalar corridor and rotating local axes, no lateral dynamics; original object-track hold assumptions retained.',
        'Planner/firmware/transport/apply/ACK schedule and executor tracking are assumptions, not measured hardware latency bounds; compute=5000 retains unresolved golden work units.',
        'TSM certifies bridge/encoded-state stopping tail, not the original four-waypoint path. E2 transmits acceleration intent only.',
        'Invalid measured snapshot remains unmodified and fails closed; E2 uses unclipped diagnostic constant-acceleration propagation outside golden advance domain.',
        'Fresh waypoint re-encoding with new measured anchors can conceal planner freeze. Firmware must retain original transaction metadata and encoded packet on retries.',
        'Existing obj_2 binary has 3151-vector capacity. Eight canonical shards run in parallel via complete-scene batches within each shard; no retained sequence is split.',
        'RTL logs pending supervisor; JOB PASS verifies bit decisions and TB CSR cycles == observed latency. Golden has no absolute cycle prediction.']
    hw=HERE.parents[1]; base=hw.parents[1]
    paths=[HERE/'PREREGISTRATION.md',HERE/'packetizer_v2.py',HERE/'replay_core.py',HERE/'run_eval.py',hw/'golden/tsmx_golden/model.py',hw/'tb/integ/gen_sequences.py',hw/'eval_nuscenes/run_w7.py']
    paths.extend([HERE/'train_inputs.pkl',HERE.parent/'w9b/inputs.pkl',HERE.parent/'w9b/packetizer.py',HERE.parent/'w9b/summary.json',hw/'tb/integ/obj_2/Vtb_m_tsmx_top'])
    paths.extend(base/'sw/eval_trainval/out'/n for n in ('dataset.npz','pred_hw_new.npy','train_dataset.npz','train_pred_hw_new.npy'))
    s['provenance_sha256']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    subprocess.run([sys.executable,'-B',str(HERE/'prepare_batches.py')],check=True)
    subprocess.run([sys.executable,'-B',str(HERE/'verify_artifacts.py')],check=True)
    s['artifact_checks']=json.loads((HERE/'artifact_checks.json').read_text())
    s['rtl_batches']=json.loads((HERE/'rtl_batches.json').read_text())
    s['free_bytes_end']=__import__('shutil').disk_usage('C:/').free
    assert s['free_bytes_end']>=10*2**30
    (HERE/'summary.json').write_text(json.dumps(s,indent=2,allow_nan=False))
    def rate(m):
        if not m['denominator']:return 'undefined (zero denominator)'
        lo,hi=m['ci95_pct'];return f"{m['n']}/{m['denominator']} = {m['rate_pct']:.3f}% [{lo:.3f},{hi:.3f}]"
    def triple(d,key):return '/'.join(f"{d[key][k]:.6f}" for k in ('mean','p95','max'))
    lines=['# W10a: firmware encoding and complete validation replay',
        'Selection rule fixed before W10a outcomes: maximize training T system ACCEPT subject to registered-oracle FA(T) and FA(H) rates each <= E0 (exact fractions). Undefined FA makes a candidate ineligible; E0 fallback. Ties E0/E1/E2. See immutable `PREREGISTRATION.md`; `selection.json` is sealed before validation.',
        f"Training: first 150 official trainval TRAIN scenes in name order; {s['training_extraction']['available_prediction_tokens']} saved stride-12 prediction tokens, {s['training_extraction']['odd_prediction_tokens']} eligible ODD packets/source; continuous no-packet service between available packets. This sparse sample limits generalization.",
        'E0: origin/0.5/1.0 s interpolating quadratic. E1: degree-2 LS q=beta*t+alpha*t^2, hard q(0)=0, unit residual weights on all four 0.5/1/1.5/2 s waypoints. E2: propagate measured snapshot x/v by 0.1 s using measured a (stop-clipped golden advance), command a=clip(E1 acceleration,-8,2). No velocity clipping; invalid measured snapshots remain invalid.',
        'H waypoints are sweep-pose interpolations; T uses saved RQ1 hw_new arrays, token matched. E0 counts and derivative statistics match W9b exactly. All validation encodings use the same 3040 ODD attempts/source and original W7 registered oracle.',
        '', '| Training | H ACCEPT | T ACCEPT | H FA/UNSAFE | T FA/UNSAFE | Feasible |', '|---|---:|---:|---|---|---|']
    for enc in ('E0','E1','E2'):
        r=s['selection']['training'][enc]
        lines.append(f"| {enc} | {r['H']['metrics']['acceptance']['n']} | {r['T']['metrics']['acceptance']['n']} | {rate(r['H']['metrics']['false_accept'])} | {rate(r['T']['metrics']['false_accept'])} | {enc in s['selection']['feasible']} |")
    lines.extend(['',f"Chosen: **{e}**, selected on training only. Validation cannot change the choice.",'','| Validation | ACCEPT/attempts | FA/UNSAFE | FR/SAFE |','|---|---|---|---|'])
    for enc in ('E0','E1','E2'):
        for p in 'HT':
            m=s['validation'][enc][p]['metrics'];lines.append(f"| {enc}/{p} | {rate(m['acceptance'])} | {rate(m['false_accept'])} | {rate(m['false_reject'])} |")
    lines.extend(['',tradeoff_line(s)])
    lines.extend(['Intervals: 95% percentile scene bootstrap, 2000 draws, seed 20261104, all 150 scenes including empty scenes. Oracle UNKNOWN excluded from FA/FR denominators.','Registered W7 oracle retains its +0.5 s object offset despite encoded +0.1 s apply: an epoch mismatch, not an aligned safety claim.','','| Chosen source | Attempts / B1 admitted / accepted / fallback / backup / mitigation / HOLD |','|---|---|'])
    for p in 'HT':
        r=s['validation'][e][p];c=r['outcomes'];lines.append(f"| {p} | "+' / '.join(str(c.get(k,0)) for k in ('attempts','admitted','accepted','fallback','backup','mitigation','hold'))+' |')
    lines.append('')
    for p in 'HT':
        r=s['validation'][e][p]
        lines.extend([f"{p} admission reasons: `{json.dumps(r['admission_reasons'],sort_keys=True)}`.",f"{p} occupancy in all transactions: `{json.dumps(r['occupancy'],sort_keys=True)}`; oracle UNKNOWN={r['metrics']['oracle_unknown']}."])
    lines.extend(['','Absolute encoding errors vs measured apply ego, mean/p95/max (all encodings in summary.json):','| Chosen source | Position m | Velocity m/s | Acceleration m/s^2 | >16 cm / >20 cm/s / B2 reject |','|---|---|---|---|---|'])
    for p in 'HT':
        d=s['validation'][e][p]['derivative_errors'];lines.append(f"| {p} | {triple(d,'position_error_m')} | {triple(d,'velocity_error_mps')} | {triple(d,'acceleration_error_mps2')} | {d['position_over_16cm']}/{d['velocity_over_20cmps']}/{d['b2_reject']} |")
    lines.extend(['','Certification: unchanged TSM checks the bridge and chosen stopping tail from the encoded apply state in the supplied scalar world. It does not certify the planner waypoint trajectory; E2 constrains commanded acceleration only.',
        'Freshness/freeze contract: planner completion owns seq/generated/snapshot/apply. Retry the original encoded packet without refreshing anchors, CRC or metadata. Stale snapshot => freshness; replay => sequence; no new sample >=300 ms => freeze_no_sample; unchanged encoded state >=300 ms plus >20 cm motion => freeze.',
        'Existing verify/unit.py stale/frozen witnesses pass for E0/E1/E2 (golden only, witnesses.json); exact-quadratic LS, stop-clipped E2 and TransactionEncoder retry checks pass. New measured anchors can hide unchanged planner waypoints: ABI freeze checks cannot prove semantic liveness; transaction ownership is required.',
        f"Complete chosen validation set: {s['total_jobs']} jobs; eight canonical shard counts: "+', '.join(map(str,s['shard_job_counts']))+'. Each shard owns whole scenes with independent H/T resets; no preloads or mid-sequence resets.',
        'rtl_manifest.json lists scenes, sequence offsets and every golden expected decision; replay.jsonl retains complete golden input/output history. SHA256 hashes protect canonical and runnable batch files.',
        'Existing obj_2 binary has a 3151-vector limit. run_rtl_shards.sh runs eight shard workers in parallel using complete-scene bounded batches; it never splits a retained-state sequence. Logs: tb/integ/vl_claude_r17_a8_apos/w10a_shard_<k>.txt plus .txt.done markers.',
        'Claude: `bash eval_nuscenes/w10a/run_rtl_shards.sh` from tsmx_hw (or invoke by absolute path). check_rtl.py requires every indexed JOB PASS, completion/assertion summaries, successful markers and matching input hashes; then tallies proven golden decisions. Missing logs fail closed.',
        'RTL pending supervisor. JOB PASS includes bit agreement and CSR cycles == observed TB latency; no golden absolute cycle prediction or RTL pass is claimed.',
        'Assumptions retained: planner/firmware/transfer 40/5/35 ms; admission/delivery/apply 80/99/100 ms; ACK 20 ms after issue; 100 ms service; context lease 500 ms. compute=5000 physical units unresolved.',
        'Limitations: offline future-pose ego estimates, ideal intermeasurement command tracking, open-loop measured reanchors, scalar corridor/local-axis abstraction and original held GT tracks. This is conditional replay, not physical closed-loop safety.',
        f"Detached golden workers <=4; resumed replay/export elapsed {s['runtime_seconds']:.2f} s (finishing checks and earlier extraction/training attempts excluded); C: free start/end {s['free_bytes_start']/2**30:.3f}/{s['free_bytes_end']/2**30:.3f} GiB (>=10). All writes under w10a; golden/RTL/TB/run_w7/manuscripts unchanged.",
        'Reproduce: Python 3.9 -B prepare_train.py; witnesses.py; test_checker.py; run_eval.py (launch detached). Saved per-scene workers resume completed sequences. summary.json contains all counts, errors, hashes and training/validation metrics.'])
    assert len(lines)<=80,len(lines)
    (HERE/'W10A_REPORT.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    print('report lines',len(lines),flush=True)

if __name__=='__main__':main()
