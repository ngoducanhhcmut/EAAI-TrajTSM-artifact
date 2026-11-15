# -*- coding: utf-8 -*-
"""Doi chieu quyet dinh RTL TSM v2 (10.838 luot) voi mo hinh Python tsm_model.decide_v2 (cau hinh 255/64/21)."""
import sys, pickle
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import tsm_model as M, analyze as A            # noqa: E401,E402
from validate_model import select              # noqa: E402
OUT = Path(__file__).parent / "out"
D = np.load(OUT / "dataset.npz"); O = pickle.load(open(OUT / "objects.pkl", "rb"))
P = np.load(OUT / "pred_hw_new.npy"); G = D["gt"]; T = A.parse_tsm()
for kind, W in (("H", P), ("G", G)):
    agree, n, conf = 0, 0, {}
    for i in range(len(W)):
        k = "%s%04d" % (kind, i)
        if k not in T: continue
        m = M.decide_v2(W[i], select(O[i], P[i], G[i]), 255, 64, 21); r = T[k]["dec"]
        agree += m == r; n += 1; conf[(r, m)] = conf.get((r, m), 0) + 1
    print(kind, "khop %d/%d = %.4f" % (agree, n, agree / max(n, 1)), "(RTL, mo hinh):", conf)
