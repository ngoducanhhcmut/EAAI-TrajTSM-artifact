"""Claude 05/11/2026: single proof-suite runner.

Runs every proof script, parses its result lines and compares them with the EXPECTED outcome table. Any FAILED line,
any negative control that is not refuted, any count that differs, a timeout or a non-zero exit (except rtl_ranges,
whose findings are checked explicitly) makes the suite fail. rtl_ranges is composed with rtl_paths: every finding at
the used ranges must be one of the truncations that rtl_paths discharges; findings in the full op-7 guard range are the
documented, unreachable F-W3-1 and must stay confined to op 7.
usage: python run_all.py   -> exit 0 and 'SUITE PASS' only if everything matches
"""
import re, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXPECT = {  # script: (PROVEN, REFUTED negative controls, other expected witnesses)
    'b3_lemmas.py': (14, 6, 0), 'b4_lemmas.py': (8, 4, 0), 'coupling_lemmas.py': (3, 1, 0),
    'geom_div.py': (5, 3, 0), 'rtl_paths.py': (3, 0, 3), 'adapter_lemmas.py': (3, 2, 0)}
DISCHARGED = {'op2 TRZ T24', 'op3 TRZ T24', 'op4 WD0 TRZ T24', 'op4 WD1 TRZ T24'}   # by rtl_paths.py

ok = True
tot = [0, 0, 0]
for f, (p, r, w) in EXPECT.items():
    t0 = time.time()
    try:
        cp = subprocess.run([sys.executable, '-B', str(HERE / f)], capture_output=True, text=True, timeout=3600)
    except subprocess.TimeoutExpired:
        print(f'FAIL {f}: timeout'); ok = False; continue
    out = cp.stdout
    np_ = len(re.findall(r'^PROVEN', out, re.M))
    nr = len(re.findall(r'^REFUTED|control b-1 bits: REFUTED', out, re.M))
    nw = len(re.findall(r'control: negative numerator reachable = True', out))
    bad = re.findall(r'^FAILED.*|not refuted.*|unknown.*', out, re.M | re.I)
    good = cp.returncode == 0 and (np_, nr, nw) == (p, r, w) and not bad
    ok &= good
    tot = [tot[0] + np_, tot[1] + nr, tot[2] + nw]
    print(f"{'ok  ' if good else 'FAIL'} {f:<20} proven={np_}/{p} refuted={nr}/{r} witnesses={nw}/{w} "
          f"rc={cp.returncode} {time.time() - t0:.1f}s" + (f'  {bad[:2]}' if bad else ''))

cp = subprocess.run([sys.executable, '-B', str(HERE / 'rtl_ranges.py')], capture_output=True, text=True, timeout=3600)
out = cp.stdout
used, full = out.split('used ranges', 1) if 'used ranges' in out else (out, '')
findings = [re.sub(r' h<=\d+', '', x) for x in re.findall(r'POSSIBLE OVERFLOW (op\d+[^:]*?):', out)]
used_f = [x for x in findings if not x.startswith('op7')]
op7_f = [x for x in findings if x.startswith('op7')]
extra = re.findall(r'(?i)traceback|error|unknown', out + cp.stderr)
r_ok = (cp.returncode == 1 and 'used ranges' in out and 'FAIL (4 findings)' in out and not extra
        and set(used_f) <= DISCHARGED and len(used_f) == 4 and len(op7_f) == 7)   # documented exit status 1
ok &= r_ok
print(f"{'ok  ' if r_ok else 'FAIL'} rtl_ranges.py       used-range findings={len(used_f)} (all discharged by rtl_paths: "
      f"{set(used_f) <= DISCHARGED}); op-7 full-guard findings={len(op7_f)} (F-W3-1, unreachable: callers pass "
      f"h<=0.1 s)")
print(f'TOTAL proven={tot[0]} refuted={tot[1]} witnesses={tot[2]}')
print('SUITE PASS' if ok else 'SUITE FAIL')
sys.exit(0 if ok else 1)
