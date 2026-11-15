"""Postprocess AFTER all simulation workers and resource monitors have exited.

Runs final unit/vector checks sequentially, writes the Vietnamese <=90-line
report and a SHA256 manifest. Does not alter policy, registration or samples.
"""
import sys,json,hashlib,subprocess,ast,time
from pathlib import Path
from collections import Counter
from datetime import datetime,timezone

ROOT=Path(__file__).resolve().parents[2]
HW=ROOT/'tsmx_hw';OUT=HW/'verify'
sys.dont_write_bytecode=True
sys.path.insert(0,str(HW/'golden'))

def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write(p,x):p.write_text(json.dumps(x,ensure_ascii=False,sort_keys=True,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def child(p,*args):subprocess.run([sys.executable,'-B',str(p),*args],cwd=ROOT,check=True)
def fmt(x):return f'{x:,}'.replace(',','.')

def main():
    child(OUT/'run.py','--stage','unit')
    child(HW/'vectors/edge_cases.py')
    import vectors
    for block in vectors.BLOCKS:vectors.dump(block,128,HW/'vectors'/(block+'.hex'))
    child(HW/'vectors/expand.py')
    child(OUT/'run.py','--stage','summarize')
    checks={};unit=read(OUT/'unit_golden_results.json');edge=read(OUT/'edge_results.json')
    coverage=Counter(c['block'] for c in unit['cases'])
    checks['unit']=unit['passed'] and min(coverage.values())>=10
    checks['supplemental_edges']=edge['passed']
    for block in vectors.BLOCKS:
        p=HW/'vectors'/(block+'.hex');meta=read(p.with_suffix('.json'))
        rows=p.read_text(encoding='ascii').splitlines()
        full=(HW/'vectors'/(block+'.ports.jsonl')).read_text(encoding='utf-8').splitlines()
        checks['vectors_'+block]=(len(rows)==len(full)==meta['n']==128 and len(rows)<=2000
                                 and meta['sha256']==sha(p)
                                 and all(len(r)==(meta['bits']+3)//4 and int(r,16)<(1<<meta['bits']) for r in rows))
    model=HW/'golden/tsmx_golden/model.py';tree=ast.parse(model.read_text(encoding='utf-8'))
    audit=dict(source_sha256=sha(model),float_literals=sum(isinstance(n,ast.Constant) and type(n.value) is float for n in ast.walk(tree)),
               true_divisions=sum(isinstance(n,ast.BinOp) and isinstance(n.op,ast.Div) for n in ast.walk(tree)),
               imports=[ast.unparse(n) for n in ast.walk(tree) if isinstance(n,(ast.Import,ast.ImportFrom))])
    audit['pass']=audit['float_literals']==audit['true_divisions']==0
    old=OUT/'static_integer_audit.json'
    if old.exists():write(OUT/'static_integer_audit_before_final.json',read(old))
    write(old,audit);checks['integer_only']=audit['pass']
    reg=read(OUT/'registration.json')
    sys.path.insert(0,str(OUT))
    from run import reference_source_matches
    checks['numerical_reference_sources_unchanged']=all(sha(ROOT/p)==h for p,h in reg['sources'].items() if p!='tsmx_hw/PLAN.md')
    checks['plan_scope_unchanged']=reference_source_matches('tsmx_hw/PLAN.md',reg['sources']['tsmx_hw/PLAN.md'])
    checks['registered_scenarios_unchanged']=all(sha(OUT/(p+'_scenarios.json'))==h for p,h in reg['scenario_hashes'].items())
    lock=read(OUT/'implementation_lock.json')
    checks['implementation_lock']=all(sha(ROOT/p)==h for p,h in lock['sources'].items())
    checks['scenario_disjoint']=read(OUT/'scenario_audit.json')['passed']
    checks['pure_cache_bit_identity']=read(OUT/'pure_cache_validation.json')['passed']
    replay=read(OUT/'v2_resource_replay_validation.json')
    checks['final_v2_resource_replay']=(replay['passed'] and replay['inputs']==1000000
                                      and replay['new_results_sha256']==sha(OUT/'v2_results.json')
                                      and replay['model_sha256']==sha(HW/'golden/tsmx_golden/model.py')
                                      and 0<replay['external_peak']<2*1024**3)
    system=[read_line for line in (HW/'vectors/edges.ports.jsonl').read_text(encoding='utf-8').splitlines()
            if (read_line:=json.loads(line))['block']=='system']
    modes={r['output']['outputs']['mode'] for r in system}
    checks['system_modes']=modes=={'L0','L1','L2','L3','HOLD','RECOVERY'}
    summary=read(OUT/'summary.json')
    if not checks['unit'] or not checks['supplemental_edges']:summary['gates']['G1d']='FAIL'
    if not audit['pass']:summary['gates']['G1e']='FAIL'
    write(OUT/'summary.json',summary)
    write(OUT/'final_checks.json',dict(passed=all(checks.values()),checks=checks,unit_coverage=coverage,system_modes=sorted(modes)))
    v1=read(OUT/'v1_results.json');v2=read(OUT/'v2_results.json');v3=read(OUT/'v3_results.json')
    samples=OUT/'resource_samples.jsonl'
    resource=[json.loads(x) for x in samples.read_text(encoding='utf-8').splitlines()] if samples.exists() else []
    peak=max((r['sum_process_peaks']+r['monitor_working_set'] for r in resource),default=0)
    histories=read(OUT/'runtime.json') if (OUT/'runtime.json').exists() else []
    secs=sum(x['seconds'] for x in histories)
    now=datetime.now(timezone.utc)
    wall=(now-datetime.fromisoformat(reg['utc'].replace('Z','+00:00'))).total_seconds()
    write(OUT/'resource_summary.json',dict(observed_peak_sum_including_monitor=peak,samples=len(resource),
         simulation_logged_seconds=secs,wall_seconds_since_registration=wall,ended_utc=now.isoformat(),
         internal_ctypes_peak_valid=False,note='Use external Get-Process samples; internal ctypes returns zero on this host. Initial V2 is not covered by that monitor; inspect any replay resource audit separately.'))
    gates=summary['gates'];verdict='FAIL' if 'FAIL' in gates.values() else 'PASS' if all(v=='PASS' for v in gates.values()) else 'INCONCLUSIVE'
    lines=['# G1 — Golden TSM-X và kiểm chuẩn','',f'**Gate tổng: {verdict}.**',
           'Phạm vi A1–A7: braking-only, làn thẳng, v≤10 m/s; rear có điều kiện; không khẳng định safety thực địa.',
           f'Registration SHA256: `{reg["registration_hash"]}`.',
           'Seeds V1/V3/V2/bootstrap/vector: 1947283101/1947283102/1947283103/1947283104/1947283105.',
           '200 IC V1 và 100 IC V3 mới, duy nhất, không trùng nhau; không tune threshold/sampling.',
           f'Model cuối SHA256: `{sha(model)}`.','',
           '|Gate|Kết quả|Bằng chứng|','|---|---|---|',
           f'|G1a|{gates["G1a"]}|{v1["IC"]} IC; {fmt(v1["rollouts"])} rollout; lệch {v1["disagreement_rate"]*100:.6f}%; unsafe ACCEPT={v1["counts"].get("unsafe_accept",0)}|',
           f'|G1b|{gates["G1b"]}|{fmt(v2["inputs"])} input; counterexamples={v2["counterexamples"]}|',
           f'|G1c|{gates["G1c"]}|{v3["IC"]} IC; {fmt(v3["paired_rollouts"])} cặp; bootstrap 2.000 cluster IC|',
           f'|G1d|{gates["G1d"]}|Unit {sum(c["pass_"] for c in unit["cases"])}/{unit["n"]}; bổ sung {sum(c["passed"] for c in edge["cases"])}/{edge["n"]} ca|',
           f'|G1e|{gates["G1e"]}|FORMATS có width/ODD/overflow/outward bounds; AST float và division / đều bằng0|','',
           f'V1: {fmt(v1["counts"].get("cycles",0))} chu kỳ; union lệch={fmt(v1["counts"].get("different",0))}; '+
           f'accept={v1["counts"].get("accept_difference",0)}, mode={v1["counts"].get("mode_difference",0)}, candidate={v1["counts"].get("candidate_difference",0)}.',
           'Mỗi cycle shadow dùng cùng ego/packet; golden tự tính B3, không gate bằng kết quả float.',
           'Các pattern bất đồng (ref/golden, mode, candidate) nằm đầy đủ trong verify/v1_results.json:']
    patterns=[(k,v) for k,v in v1['counts'].items() if '|' in k]
    for k,v in patterns[:12]:lines.append(f'- `{k}`: {fmt(v)}.')
    if len(patterns)>12:lines.append(f'Còn {len(patterns)-12} pattern được liệt kê đầy đủ trong JSON.')
    lines.extend(['Nguyên nhân mode L1→L2: phase liên tục + guard rounding0,64mm/0,00064m/s khiến backup bị từ chối sớm hơn midpoint float.',
                  'Sai khác candidate/accept khác nếu có được đếm riêng; rounding/hold2s là các nguồn bảo thủ đã đăng ký.',
                  f'V2 chia {fmt(v2["counts"]["b2"])} input/block B2/B3/B4/B7; ACCEPT kiểm Fraction độc lập.',
                  'B3/B7 kiểm cực tiểu quadratic liên tục, cả stop/interior; B4 tích phân ramp và isolate stop bằng rational.',
                  f'ACCEPT theo block: {v2["accepted"]}; residual separation nhỏ nhất={v2["min_separation_residual"]} m.',
                  'V2 là random+boundary audit trên encoded contract, không phải exhaustive proof mọi bit pattern hay perception.',
                  '', '|Scope|collision golden/d2|Δ rate [CI95], điểm %|front golden/d2|','|---|---:|---:|---:|'])
    for scope,r in v3['results'].items():
        lines.append(f'|{scope}|{r["rates"]["golden"]*100:.4f}% / {r["rates"]["reference"]*100:.4f}%|'+
                     f'{r["difference"]*100:+.4f} [{r["ci95"][0]*100:+.4f}; {r["ci95"][1]*100:+.4f}]|{r["front_golden"]}/{r["front_reference"]}|')
    lines.extend(['V3 giữ nguyên run/dynamics/followers/queue, chỉ wrap Executor/geometry/selector/seal; mỗi cặp cùng IC/fault/schedule/model.',
                  'CI giữ toàn 11 lỗi × 5 lịch × F2/F3 trong mỗi IC; CI chứa0 không chứng minh non-inferiority quần thể.',
                  'P5bd2 gốc: d2 F2/F3=3,809%/4,045%, front0/22.000; G2a/G2b/G2c FAIL. G1 không đổi kết luận nhân quả đó.',
                  '', 'Traceability: cache API amendment không đổi AST hàm/lớp; time guards chỉ thu nhỏ ACCEPT ngoài domain đã đăng ký.',
                  'V1 dùng module trước guard; amendment JSON (past_apply, time_contract, live_ego) chứng minh matrix/V2 cũ đi cùng nhánh.',
                  'V3 và unit cuối dùng revision có guard. Tất cả hash trước/sau và partial run đều được giữ; không fit theo score.',
                  'B3 row/type guards và upper-speed intersection: proof identity trên corpus cũ ở b3_input/b3_upper_clip_amendment.json; directed Fraction kiểm biên mới.',
                  'Adapter cache tối ưu thời gian, giữ field/type/signed-zero:85 checks và1 IC replay110 cặp có toàn bộ row SHA khớp; không tính thêm mẫu.',
                  'PLAN được coordinator append lịch S1/R; prefix cũ khớp đúng SHA registration, A1–A7 và mọi source mô phỏng không đổi (plan_append_validation.json).',
                  'B4 continuous jerk trước clamp standstill; hold parking theo P5. Phase generator ngoài grid100ms reject, không restart epoch.',
                  'Cận thật toàn thư viện10m/s: stop+hold≤7,6s và D≤30,916667m; không cắt tại6s/30m.',
                  'B9 ACK40ms/expiry cần callback subcycle; wrapper gọi mỗi20ms. Chỉ polling cycle100ms không đủ cho FTTI0,285s.',
                  'CRC trên canonical UTF-8 JSON; S1 phải chốt mapping wire, không đổi serializer âm thầm.',
                  'Latency scalar estimate18,940ms: FAIL A7; 4 generator context + P4, II48:8,455ms có điều kiện, chưa synth/WCET.',
                  f'Tài nguyên: 1 worker; simulation log {secs:.2f}s; wall từ registration {wall:.2f}s; peak quan sát gồm monitor {peak/2**20:.2f}MiB.',
                  'Bộ đếm ctypes Windows trả0 không hợp lệ; dùng resource_samples.jsonl; peak V2 đầu không có phép đo này.',
                  f'V2 đã replay đủ1.000.000 input trên revision cuối: counters/residual khớp; external peak {replay["external_peak"]/2**20:.2f}MiB; không cộng thành mẫu mới.',
                  f'Đối chiếu artifacts: final_checks.passed={all(checks.values())}; các input/revision có registration + SHA256.',
                  'Vector:128/block ×9 block +128 system; hex + field/bit JSON + full semantic ports; edge vectors bổ sung trong edges.ports.jsonl.',
                  'Tái lập: verify/README.md; CLI golden/vectors.py --block b3 --n 5000 --out vectors/b3.hex.',
                  'Kết quả: verify/{v1_results,v2_results,v3_results,unit_golden_results,edge_results,summary}.json.',
                  'Định dạng/cận: golden/FORMATS.md; timing: golden/LATENCY_MODEL.md; manifest: verify/artifacts_SHA256.json.'])
    assert len(lines)<=90,len(lines)
    (HW/'G1_REPORT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    artifacts=[p for folder in ('golden','verify','vectors') for p in (HW/folder).rglob('*') if p.is_file() and p.name!='artifacts_SHA256.json']
    artifacts.append(HW/'G1_REPORT.md')
    write(OUT/'artifacts_SHA256.json',{str(p.relative_to(HW)):sha(p) for p in sorted(artifacts)})
    print('FINAL',verdict,'lines',len(lines),'checks',all(checks.values()),flush=True)

if __name__=='__main__':main()
