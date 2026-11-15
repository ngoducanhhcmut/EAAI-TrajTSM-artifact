# -*- coding: utf-8 -*-
"""So GRU tuong duong RTL (payload: thang UQ0.8 + LUT) voi GRU W4A8 (m.gru) khi dau vao la CLS cua hwspec."""
import sys, io, contextlib
import numpy as np
from common import load_all, samples, ROOT
import hwspec_exact as hx
sys.argv = [sys.argv[0]]
with contextlib.redirect_stdout(io.StringIO()):
    sys.path.insert(0, str(ROOT / "sw"))
    src = (ROOT / "sw" / "_verify_all_samples_spec.py").read_text(encoding="utf-8")
    src = src[:src.index("Run all 5 samples") - 6]
    g = {"__file__": str(ROOT / "sw" / "_verify_all_samples_spec.py")}
    exec(src, g)
run_rtl = g["run_gru_rtl_equiv"]
m, P = load_all()
S = samples()
E = {"m.gru": [], "rtl_equiv": []}; D = []
for s in S:
    cls = hx.forward(P, s["tok"], s["pad"])
    a = m.gru.forward(cls[None])[0]; b = run_rtl(cls.astype(np.float32))
    E["m.gru"].append(np.linalg.norm(a - s["gt"], axis=1)); E["rtl_equiv"].append(np.linalg.norm(b - s["gt"], axis=1))
    D.append(np.linalg.norm(a - b, axis=1))
for k, v in E.items():
    v = np.array(v); print("%-10s ADE %.3f FDE %.3f RMSE %.3f" % (k, v.mean(), v[:, -1].mean(), np.sqrt((v**2).mean())))
D = np.array(D); print("lech rtl_equiv vs m.gru: TB %.3f max %.3f m" % (D.mean(), D.max()))
# so sanh trong so: thang UQ0.8 vs thang FP32
G = m.gru
for nm, mat in (("W_iz", "w_iz"), ("W_hn", "w_hn")):
    q = g["mats"][nm].astype(np.float32); sc, zp = g["scales"][nm]
    dq_rtl = (q - zp[:, None]) * (sc[:, None] / 256.0)
    dq_m = getattr(G, mat + "_int4").astype(np.float32) * getattr(G, mat + "_scale")[:, None]
    print(nm, "int4 giong nhau:", bool(np.array_equal(q.astype(np.int8), getattr(G, mat + "_int4"))),
          " lech trong so TB %.4f, tuong doi %.2f%%" % (np.abs(dq_rtl - dq_m).mean(), 100 * np.abs(dq_rtl - dq_m).mean() / np.abs(dq_m).mean()))
