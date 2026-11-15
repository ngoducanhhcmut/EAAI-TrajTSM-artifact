# -*- coding: utf-8 -*-
"""Sinh rtl/src/bert_v2/fp32_tables.svh tu CHINH cac bang trong sw/hwspec/fp.py."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fp import RSQRT_SEED, RECIP_SEED, EXP2_FRAC, bits

OUT = Path(__file__).resolve().parents[2] / "rtl" / "src" / "bert_v2" / "fp32_tables.svh"


def arr(name, width, vals):
    body = ",\n    ".join(", ".join("%d'h%x" % (width, v) for v in vals[i:i + 8]) for i in range(0, len(vals), 8))
    return "localparam logic [%d:0] %s [%d] = '{\n    %s\n};\n" % (width - 1, name, len(vals), body)


e2 = [int(b) & 0x7FFFFF for b in bits(EXP2_FRAC)]
assert all((int(b) >> 23) == 127 for b in bits(EXP2_FRAC))      # moi o trong [1,2)
txt = ("// TU DONG SINH boi sw/hwspec/gen_rtl_tables.py - KHONG SUA TAY.\n"
       "// Nguon: sw/hwspec/fp.py (RSQRT_SEED, RECIP_SEED, EXP2_FRAC).\n"
       + arr("RSQRT_SEED_T", 32, [int(b) for b in bits(RSQRT_SEED)])
       + arr("RECIP_SEED_T", 32, [int(b) for b in bits(RECIP_SEED)])
       + "// EXP2_FRAC: 2^(k/1024) trong [1,2) -> chi luu 23 bit mantissa (so mu = 127)\n"
       + arr("EXP2_MANT_T", 23, e2))
OUT.write_text(txt, encoding="ascii")
print("ghi", OUT)
