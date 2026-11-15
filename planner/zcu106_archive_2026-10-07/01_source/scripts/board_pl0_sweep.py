"""Quet tan so clock PL0 (VLA-Traj) tren board: moi nac doi PL0, reset PL, chay lai demo, doc ket qua qua COM7.
Dung o nac dau tien demo khong DAT (sai ket qua, het gio, hoac Traj khong nap duoc trong so).
Yeu cau: da chay board_run_demo_zcu106.tcl (DDR co du lieu); PuTTY DONG (script tu doc COM7).
  python scripts/board_pl0_sweep.py [div1 div2 ...]   (mac dinh 15 11 10 9 8 7 6)
Cuoi cung tra PL0 ve 100 MHz (div 15) neu board con phan hoi."""
import os, re, sys, time, subprocess, serial
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
XSDB = r"C:\Vivado\Vivado\2023.2\bin\xsdb.bat"
TCL = str(ROOT / "scripts" / "board_pl0_freq_rerun.tcl").replace("\\", "/")
LOG = ROOT / "reports" / "board_fix_validation" / "pl0_sweep.log"
divs = [int(x) for x in sys.argv[1:]] or [15, 11, 10, 9, 8, 7, 6]

def run_div(div, out):
    sp = serial.Serial("COM7", 115200, timeout=0.2)
    sp.reset_input_buffer()
    env = dict(os.environ, PL0_DIV=str(div))
    p = subprocess.run([XSDB, TCL], env=env, capture_output=True, text=True, timeout=180)
    xs = [l for l in p.stdout.splitlines() if re.search(r"PL0_REF_CTRL|Traj STATUS|ERROR|R5_RUNNING", l)]
    for l in xs: out.write("  xsdb: " + l + "\n"); print("  xsdb:", l)
    if not any("R5_RUNNING" in l for l in xs):
        sp.close(); return {"ok": False, "why": "xsdb: " + " | ".join(xs[-2:])}
    buf, t0 = "", time.time()
    while time.time() - t0 < 120:
        buf += sp.read(4096).decode("ascii", "replace")
        if "==== DEMO:" in buf and buf.rstrip().endswith("===="): break
    sp.close()
    out.write(buf + "\n")
    r = {"ok": "==== DEMO: DAT ====" in buf}
    for key, pat in (("wp", r"\[A\] waypoint[^:]*:\s*(\d+/\d+)[^\n]*?lon nhat (\d+) um"), ("a", r"\[A\] quyet dinh[^:]*:\s*(\d+/\d+)"),
                     ("b", r"\[B\][^:]*:\s*(\d+/\d+)"), ("c", r"\[C\][^:]*:\s*(\d+/\d+)"),
                     ("tsm", r"Do tre TSM[^:]*:\s*([\d.]+ \.\. [\d.]+)"), ("traj", r"Do tre Traj trung binh\s*:\s*([\d.]+)")):
        m = re.search(pat, buf)
        r[key] = (m.groups() if m and len(m.groups()) > 1 else (m.group(1) if m else None))
    if not r["ok"]:
        r["why"] = "khong thay DEMO: DAT" if "==== DEMO:" in buf else "het gio doc UART (treo?)"
        tail = [l for l in buf.splitlines() if "LECH" in l or "HET GIO" in l][:5]
        r["tail"] = tail
    return r

with open(LOG, "w", encoding="utf-8") as out:
    res = []
    for d in divs:
        f = 1500.0 / d
        print("=== PL0 = %.1f MHz (div %d) ===" % (f, d)); out.write("=== PL0 = %.1f MHz (div %d) ===\n" % (f, d))
        try:
            r = run_div(d, out)
        except Exception as e:
            r = {"ok": False, "why": "loi: %s" % e}
        res.append((f, d, r)); print("  ->", r); out.write("  -> %s\n" % r); out.flush()
        if not r["ok"]:
            break
    print("\n=== TONG KET QUET PL0 ===")
    for f, d, r in res:
        print("%6.1f MHz: %s | WP %s | TSM[A] %s | [B] %s | [C] %s | Traj %s ms | TSM %s ms%s" % (
            f, "DAT" if r["ok"] else "SAI", r.get("wp"), r.get("a"), r.get("b"), r.get("c"), r.get("traj"), r.get("tsm"),
            "" if r["ok"] else "  (" + r.get("why", "") + ")"))
    if res and not res[-1][2]["ok"] or len(res) == len(divs):
        try:
            print("tra PL0 ve 100 MHz ..."); run_div(15, out)
        except Exception as e:
            print("khong tra ve duoc (can tat/bat nguon board):", e)
