"""Sinh du lieu cho tb_tsm_sysbd: 15 ca bank B cua demo_bank.bin + 1 ca hong CRC (H0261, byte 100 ^ 1).
Moi ca: 512 word quy dao (1404 B dung, phan con lai 0) va 2048 word world model (6400 B dung)."""
import json, struct
from pathlib import Path
R = Path(__file__).resolve().parents[1]
bank = (R / "sw/board/demo_bank.bin").read_bytes()
cases = json.loads((R / "sw/board/demo_cases.json").read_text())["B"]
out = R / "sim_sysbd/data"
tr_lines, wm_lines, exp = [], [], []
def words(b, n):
    b = b + bytes(4 * n - len(b))
    return ["%08x" % w for w in struct.unpack("<%dI" % n, b)]
for n, (name, kind, g) in enumerate(cases):
    tr = bank[0x400000 + n * 0x800: 0x400000 + n * 0x800 + 1404]
    wm = bank[0x480000 + n * 0x2000: 0x480000 + n * 0x2000 + 6400]
    tr_lines += words(tr, 512); wm_lines += words(wm, 2048)
    exp.append("%d %02x %s" % (g, 0, name))
tr = bytearray(bank[0x400000:0x400000 + 1404]); tr[100] ^= 1
tr_lines += words(bytes(tr), 512); wm_lines += words(bank[0x480000:0x480000 + 6400], 2048)
exp.append("0 08 H0261_CRC")
(out / "traj.mem").write_text("\n".join(tr_lines) + "\n")
(out / "wm.mem").write_text("\n".join(wm_lines) + "\n")
(out / "expect.txt").write_text("\n".join(exp) + "\n")
print(len(exp), "ca")
