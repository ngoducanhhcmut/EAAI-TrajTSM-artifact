# -*- coding: utf-8 -*-
"""Vector cho tb_fp32_special (chuan sw/hwspec/fp.py)."""
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fp import exp_neg, rsqrt, recip, bits, F32, LOG2E

OUT = Path(__file__).resolve().parents[2] / "tb" / "unit" / "bert_v2" / "vec"
rng = np.random.default_rng(777)
N = int(sys.argv[1]) if len(sys.argv) > 1 else 200000

x = np.concatenate([-rng.uniform(0, 100, N), -10 ** rng.uniform(-30, 0, N // 4),
                    np.array([0.0, -0.0, -87.3365, -87.33654, -87.3366, -1e-38, -126 / 1.4426950408889634])]).astype(F32)
x = np.nextafter(x, F32(0))  # giu nguyen dau; bien doi nho cho da dang
x = np.concatenate([x, np.array([0.0, -0.0], F32)])
# hop dong: dau vao khong denormal (nguon la ket qua FTZ) -> denormal thanh 0 co dau
x = np.where((bits(x) & 0x7F800000) == 0, np.copysign(F32(0), x), x).astype(F32)
with open(OUT / "exp.hex", "w") as f:
    for a, r in zip(bits(x), bits(exp_neg(x))):
        f.write("%08x %08x\n" % (a, r))

v = np.concatenate([10 ** rng.uniform(-5, 5, N // 4), rng.uniform(1, 64, N // 4),
                    np.array([1.0, 2.0, 4.0, 0.5, 1e-5, 64.0])]).astype(F32)
with open(OUT / "rsqrt.hex", "w") as f:
    for a, r in zip(bits(v), bits(rsqrt(v))):
        f.write("%08x %08x\n" % (a, r))
with open(OUT / "recip.hex", "w") as f:
    for a, r in zip(bits(v), bits(recip(v))):
        f.write("%08x %08x\n" % (a, r))
print("exp", x.size, "rsqrt/recip", v.size)
