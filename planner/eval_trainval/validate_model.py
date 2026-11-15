# -*- coding: utf-8 -*-
"""Doi chieu tsm_model.decide_old (mo hinh Python cua RTL hien tai) voi 10.838 quyet dinh RTL that.
Chon vat can GIONG HET gen_tsm_cases.py (100 vat can gan quy dao nhat theo min(clr_H, clr_G)).
  python sw/eval_trainval/validate_model.py
"""
import sys, pickle
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "sw" / "eval_trainval" / "out"
sys.path.insert(0, str(ROOT / "sw")); sys.path.insert(0, str(Path(__file__).parent))
import gen_hmao_collision_e2e_dataset as g   # noqa: E402
import tsm_model as M                         # noqa: E402
import analyze as A                           # noqa: E402
from gen_tsm_cases import poly_dist           # noqa: E402


def select(objs, hw, gt):
    th, tg = g.expand_to_50wp([tuple(p) for p in hw]), g.expand_to_50wp([tuple(p) for p in gt])
    sc = [min(poly_dist(o["x"], o["y"], th), poly_dist(o["x"], o["y"], tg)) - max(o["w"], o["l"]) / 2 for o in objs]
    return [objs[j] for j in np.argsort(sc, kind="stable")[:100]]


def main():
    D = np.load(OUT / "dataset.npz")
    objs_all = pickle.load(open(OUT / "objects_v1_noprv.pkl", "rb"))
    P = np.load(OUT / "pred_hw_new.npy"); G = D["gt"]
    T = A.parse_tsm()
    agree = {"H": [0, 0], "G": [0, 0]}; conf = {"H": {}, "G": {}}
    for i in range(len(G)):
        sel = select(objs_all[i], P[i], G[i])
        for kind, w in (("H", P[i]), ("G", G[i])):
            m = M.decide_old(w, sel); r = T["%s%04d" % (kind, i)]["dec"]
            agree[kind][0] += m == r; agree[kind][1] += 1
            conf[kind][(r, m)] = conf[kind].get((r, m), 0) + 1
        if i % 1000 == 0:
            print(i, {k: "%.4f" % (v[0] / max(v[1], 1)) for k, v in agree.items()}, flush=True)
    for k in "HG":
        print(k, "khop %d/%d = %.4f" % (agree[k][0], agree[k][1], agree[k][0] / agree[k][1]), "(RTL, model):", conf[k])


if __name__ == "__main__":
    main()
