"""Sinh sw/board/multicase_data.h cho tsm_multicase.c: 15 ca bank B (demo_bank.bin) + ky vong tu mo phong
he thong (sim_sysbd 16/16, clock that). World model chi luu cac ban ghi khac 0 (phan con lai firmware dien 0)."""
import json, struct
from pathlib import Path
R = Path(__file__).resolve().parents[2]
bank = (R / "sw/board/demo_bank.bin").read_bytes()
B = json.loads((R / "sw/board/demo_cases.json").read_text())["B"]
# ky vong: quyet dinh, fault, buoc, vat can (sim_sysbd/.../sysbd_full_fixed.log)
EXP = {"H0261": (0, 0, 12, 1), "H0714": (0, 0, 4, 0), "H0717": (0, 0, 3, 0), "H0720": (0, 0, 3, 0),
       "H0723": (0, 0, 3, 0), "H0726": (0, 0, 4, 0)}
L = ["/* TU DONG SINH boi sw/board/gen_multicase_data.py - khong sua tay. */", "#ifndef MULTICASE_DATA_H",
     "#define MULTICASE_DATA_H", "#include <stdint.h>", "#define N_CASE %d" % len(B)]
names, kinds, exp, nrec = [], [], [], []
for n, (name, kind, g) in enumerate(B):
    tr = bank[0x400000 + n * 0x800: 0x400000 + n * 0x800 + 1404]
    wm = bank[0x480000 + n * 0x2000: 0x480000 + n * 0x2000 + 6400]
    last = max([i for i in range(100) if any(wm[i * 64:(i + 1) * 64])] + [-1]) + 1
    tw = struct.unpack("<351I", tr); ww = struct.unpack("<%dI" % (last * 16), wm[:last * 64])
    L.append("static const uint32_t TR_%d[351] = {%s};" % (n, ",".join("0x%08xu" % w for w in tw)))
    L.append("static const uint32_t WM_%d[%d] = {%s};" % (n, max(1, last * 16), ",".join("0x%08xu" % w for w in ww) or "0"))
    names.append(name); kinds.append(kind.strip()); nrec.append(last)
    d, f, s, o = EXP.get(name, (1, 0, 0, 0)); assert d == g, name
    exp.append((d, f, s, o))
L.append("static const uint32_t *const CASE_TR[N_CASE] = {%s};" % ",".join("TR_%d" % i for i in range(len(B))))
L.append("static const uint32_t *const CASE_WM[N_CASE] = {%s};" % ",".join("WM_%d" % i for i in range(len(B))))
L.append("static const uint16_t CASE_NREC[N_CASE] = {%s};" % ",".join(map(str, nrec)))
L.append("static const char *const CASE_NAME[N_CASE] = {%s};" % ",".join('"%s"' % s for s in names))
L.append("static const char *const CASE_KIND[N_CASE] = {%s};" % ",".join('"%s"' % s for s in kinds))
L.append("/* {grant, fault, step, obstacle} */")
L.append("static const uint16_t CASE_EXP[N_CASE][4] = {%s};" % ",".join("{%d,%d,%d,%d}" % e for e in exp))
L.append("#endif")
(R / "sw/board/multicase_data.h").write_text("\n".join(L) + "\n")
print(len(B), "ca, ban ghi WM:", nrec)
