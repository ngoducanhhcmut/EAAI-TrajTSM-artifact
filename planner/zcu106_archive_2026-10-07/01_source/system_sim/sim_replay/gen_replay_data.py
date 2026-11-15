"""Du lieu phat lai DUNG thu tu firmware sw/board/tsm_demo.c: [A] 35 khung, [B] 15 ca, [C] C1 CRC / C2 NaN / C3 xe chan.
Moi ca: 512 word quy dao + 2048 word world model. expect.txt: <grant> <fault_mode> <fault> <ten>
  fault_mode 0 = fault phai bang dung <fault>; 1 = chi can co bit <fault>; 2 = khong kiem fault (chi quyet dinh)."""
import sys, json, struct, zlib
from pathlib import Path
R = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(R / "sw" / "board"))
import importlib.util
spec = importlib.util.spec_from_file_location("gdp", R / "sw/board/gen_demo_payload.py")
src = (R / "sw/board/gen_demo_payload.py").read_text(encoding="utf-8")
ns = {"__file__": str(R / "sw/board/gen_demo_payload.py")}
exec(compile(src.split("def main():")[0], "gdp", "exec"), ns)       # chi lay build_traj_like_fw + PINV
build = ns["build_traj_like_fw"]
bank = (R / "sw/board/demo_bank.bin").read_bytes()
cases = json.loads((R / "sw/board/demo_cases.json").read_text())
gh = (R / "sw/board/demo_golden.h").read_text()
import re
A_WP = [[int(x, 16) for x in re.findall(r"0x([0-9a-f]+)u", row)] for row in
        re.search(r"A_WP_BITS\[N_A\]\[8\] = \{(.*?)\};", gh, re.S).group(1).split("},{")]
A_EXP = [int(v) for v in re.search(r"A_EXP_GRANT\[N_A\] = \{(.*?)\}", gh).group(1).split(",")]
HEX = R / "sw/eval_trainval/out/tsm_hex"
def hexbytes(p): return b"".join(struct.pack("<I", int(l, 16)) for l in open(p).read().split())
def words(b, n):
    b = b + bytes(4 * n - len(b)); return ["%08x" % w for w in struct.unpack("<%dI" % n, b)]
TR, WM, EX = [], [], []
def add(tr, wm, g, mode, f, name):
    assert len(tr) == 1404 and len(wm) == 6400, (name, len(tr), len(wm))
    TR.extend(words(tr, 512)); WM.extend(words(wm, 2048)); EX.append("%d %d %02x %s" % (g, mode, f, name))
nbad = 0
for n, i in enumerate(cases["A"]):
    wpf = struct.unpack("<8f", struct.pack("<8I", *A_WP[n]))
    tr = build(wpf)
    nbad += tr != hexbytes(HEX / ("H%04d.hex" % i))
    add(tr, bank[0x300000 + n * 0x2000: 0x300000 + n * 0x2000 + 6400], A_EXP[n], 0, 0, "A%02d" % n)
for n, (name, kind, g) in enumerate(cases["B"]):
    add(bank[0x400000 + n * 0x800: 0x400000 + n * 0x800 + 1404], bank[0x480000 + n * 0x2000: 0x480000 + n * 0x2000 + 6400], g, 0, 0, "B_" + name)
b0t = bank[0x400000:0x400000 + 1404]; b0w = bank[0x480000:0x480000 + 6400]
t = bytearray(b0t); t[100] ^= 1; add(bytes(t), b0w, 0, 1, 0x08, "C1_CRC")                  # firmware: !grant && (fault & 0x08)
t = bytearray(b0t); t[280:284] = struct.pack("<I", 0x7FC00000)
t[1400:1404] = struct.pack("<I", zlib.crc32(bytes(t[:1400])) & 0xFFFFFFFF); add(bytes(t), b0w, 0, 2, 0, "C2_NaN")   # firmware: !grant
w = [0] * 16
w[0] = 5 * 256; w[6] = int(4.5 * 256); w[7] = int(1.9 * 256); w[9] = (0 << 16) | 256; w[10] = (100 << 24)
wm = struct.pack("<16I", *w) + bytes(6400 - 64)
wpf = struct.unpack("<8f", struct.pack("<8I", *A_WP[0]))
add(build(wpf), wm, 0, 0, 0, "C3_xe_chan")                                                  # firmware: !grant && fault == 0
O = R / "sim_replay/data"
(O / "traj.mem").write_text("\n".join(TR) + "\n"); (O / "wm.mem").write_text("\n".join(WM) + "\n")
(O / "expect.txt").write_text("\n".join(EX) + "\n")
print(len(EX), "ca; quy dao A khac hex RTL:", nbad, "; GRANT mong doi A:", sum(A_EXP))
