"""Claude 10/11/2026: check a VCU118 joint-run UART log and summarise the numbers for the manuscript.
   python board_check_joint.py board_logs/uart_XXXX.log  -> prints the verdict, writes board_logs/results_joint.json
Pass criteria (PASS1 = reference replay of the RTL end-to-end bench):
  DDR CRCs equal the host images; 35/35 planner frames bit-exact with recorded RTL waypoints; 35/35 firmware
  packets equal the bench packets; 207/207 responses and 207/207 command frames equal the golden references."""
import sys, re, json, zlib, pathlib, statistics as st

HERE = pathlib.Path(__file__).resolve().parent
DAT = HERE / 'fw' / 'joint_data'
F_HZ = 100e6
log = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()
lines = [l.split(' ', 1)[1] if re.match(r'^\s*\d+\.\d+ ', l) else l for l in (x.strip() for x in log)]
kvp = lambda s: dict(re.findall(r'(\w+)=([0-9a-fx,]+)', s))
res, errs = {}, []

crc = next((l for l in lines if l.startswith('DDRCRC')), None)
if not crc:
    errs.append('no DDRCRC line')
else:
    got = dict(zip(crc.split()[1::2], crc.split()[2::2]))
    host = {'tsm_req': 'tsm_req.bin', 'tsm_meta': 'tsm_meta.bin', 'wm_bank': 'wm_bank.bin',
            'wp_golden': 'wp_golden.bin', 'bert': 'planner_bert_weights.bin'}
    for k, fn in host.items():
        # firmware region_crc = reflected CRC-32, init 0, no final xor (12/11/2026 fix: was zlib.crc32)
        h = f'{(~zlib.crc32((DAT / fn).read_bytes(), 0xFFFFFFFF)) & 0xFFFFFFFF:08x}'
        if got.get(k) != h:
            errs.append(f'DDR CRC {k}: board {got.get(k)} host {h}')
    res['ddr_crc_ok'] = not any(e.startswith('DDR CRC') for e in errs)

s1 = next((l for l in lines if l.startswith('PASS1_SUMMARY')), None)
if not s1:
    errs.append('no PASS1_SUMMARY')
else:
    d = {k: int(v) for k, v in kvp(s1).items()}
    res['pass1'] = d
    for k, want in (('frames', 35), ('wp_exact', 35), ('packets', 35), ('responses', 207), ('commands', 207)):
        if d.get(k) != want:
            errs.append(f'PASS1 {k}={d.get(k)} expected {want}')


def stats(rows, key, frames_only=False, ms=False):
    v = [int(r[key]) for r in rows if key in r and (not frames_only or r.get('f', '0') != '0') and int(r[key]) > 0]
    if not v:
        return None
    sc = (1e3 if ms else 1e6) / F_HZ
    return {'n': len(v), 'min': min(v) * sc, 'mean': st.mean(v) * sc, 'max': max(v) * sc, 'unit': 'ms' if ms else 'us'}


p1 = [kvp(l) for l in lines if l.startswith('P1 ')]
p2 = [kvp(l) for l in lines if l.startswith('P2 ')]
res['pass1_timing'] = {'planner_ms': stats(p1, 'plan', True, True), 'packet_us': stats(p1, 'pack', True),
                       'fifo_us': stats(p1, 'fifo'), 'decide_ms': stats(p1, 'decide', ms=True),
                       'rsp_to_cmd_us': stats(p1, 'rsp2cmd')}
res['pass2_timing'] = {'planner_ms': stats(p2, 'plan', True, True), 'packet_us': stats(p2, 'pack', True),
                       'fifo_us': stats(p2, 'fifo'), 'decide_ms': stats(p2, 'decide', ms=True),
                       'rsp_to_cmd_us': stats(p2, 'rsp2cmd'), 'e2e_frame_ms': stats(p2, 'e2e', True, True)}
# 12/11/2026: real-time (PASS2) agreement with the reference replay (PASS1), per job
res['pass2_vs_pass1'] = {'jobs': min(len(p1), len(p2)),
                         'rsp_equal': sum(a.get('rsp') == b.get('rsp') for a, b in zip(p1, p2)),
                         'cmd_type_equal': sum(a.get('ct') == b.get('ct') for a, b in zip(p1, p2)),
                         'wp_exact': sum(b.get('wpx') == '2' for b in p2 if b.get('f', '0') != '0')}
s2 = next((l for l in lines if l.startswith('PASS2_SUMMARY')), None)
res['pass2'] = {k: int(v) for k, v in kvp(s2).items()} if s2 else None
p3 = next((l for l in lines if l.startswith('P3 ')), None)
res['pass3'] = {k: int(v) for k, v in kvp(p3).items()} if p3 else None
if p3 and res['pass3'].get('captured') != 1:
    errs.append('PASS3 brake rise not captured')
res['joint_done'] = any(l.startswith('JOINT_DONE') for l in lines)
res['errors'] = errs
res['verdict'] = 'PASS' if not errs and res['joint_done'] else 'FAIL'
out = pathlib.Path(sys.argv[1]).with_name('results_joint.json')
out.write_text(json.dumps(res, indent=1))
print(json.dumps(res, indent=1))
print('VERDICT', res['verdict'], '->', out)
sys.exit(0 if res['verdict'] == 'PASS' else 1)
