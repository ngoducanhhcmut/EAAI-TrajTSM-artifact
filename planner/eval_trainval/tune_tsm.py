# -*- coding: utf-8 -*-
"""Quet tham so cua bo kiem tra va cham TSM v2 bang mo hinh Python (tsm_model.decide_v2).

CHON tham so tren tap TRAIN (--prefix train_), BAO CAO tren tap VAL (--prefix "") voi cau hinh da chon.
Moi cau hinh: recall (VETO tren quy dao phan cung va cham that), bao dong nham tren quy dao phan cung,
ty le VETO tren quy dao nguoi lai, ty le va cham con lai cua he thong, kha dung.
  python sw/eval_trainval/tune_tsm.py --prefix train_
  python sw/eval_trainval/tune_tsm.py --prefix "" --only 64,64,50
"""
import sys, json, pickle, argparse, itertools, time
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "sw" / "eval_trainval" / "out"
sys.path.insert(0, str(Path(__file__).parent))
import tsm_model as M                       # noqa: E402
import analyze as A                         # noqa: E402
from validate_model import select           # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", default="train_")
    ap.add_argument("--only", default="", help="k_long,k_lat,s1_chk (bo qua quet luoi)")
    ap.add_argument("--novel", action="store_true", help="them cac cau hinh khong dung van toc")
    ap.add_argument("--fine", action="store_true", help="luoi min quanh vung tot (chk 21..35)")
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    D = np.load(OUT / (a.prefix + "dataset.npz"))
    O = pickle.load(open(OUT / (a.prefix + "objects.pkl"), "rb"))
    P = np.load(OUT / (a.prefix + "pred_hw_new.npy")); G = D["gt"]
    idx = np.nonzero(D["keep"])[0]
    t0 = time.time()
    colH = np.array([A.collides(P[i], O[i]) for i in idx]); colG = np.array([A.collides(G[i], O[i]) for i in idx])
    sel = [select(O[i], P[i], G[i]) for i in idx]
    print("%s: %d mau | va cham that H %d, G %d | %.0f s" % (a.prefix or "val", len(idx), colH.sum(), colG.sum(),
                                                          time.time() - t0), flush=True)
    if a.only:
        grid = [tuple(int(v) for v in a.only.split(",")) + (True,)]
    else:
        grid = [(kl, kw, sc, True) for kl, kw, sc in itertools.product((0, 32, 64, 96, 128), (0, 32, 64, 96, 128),
                                                                       (20, 30, 40, 50))]
        if a.fine:
            grid = [(kl, kw, sc, True) for kl, kw, sc in itertools.product((96, 128, 160, 192, 224, 255),
                                                                           (0, 16, 32, 48, 64), (21, 25, 30, 35))]
        if a.novel:
            grid += [(kl, kw, sc, False) for kl, kw, sc in itertools.product((0, 64), (0, 64), (20, 50))]
    rows = []
    for kl, kw, sc, uv in grid:
        vH = np.array([M.decide_v2(P[i], s, kl, kw, sc, uv) == "VETO" for i, s in zip(idx, sel)])
        vG = np.array([M.decide_v2(G[i], s, kl, kw, sc, uv) == "VETO" for i, s in zip(idx, sel)])
        r = dict(k_long=kl, k_lat=kw, s1_chk=sc, vel=uv,
                 b_long=round(M.LONG_M_BD * kl / 256, 3), b_lat=round(M.LAT_M_BD * kw / 256, 3),
                 recall=float((vH & colH).sum() / max(colH.sum(), 1)), caught=int((vH & colH).sum()),
                 fa_H=float((vH & ~colH).sum() / max((~colH).sum(), 1)), veto_G=float(vG.mean()),
                 veto_H=float(vH.mean()), coll_after=float((colH & ~vH).mean()), coll_before=float(colH.mean()))
        rows.append(r)
        print("K_long %3d K_lat %3d chk %2d vel %d | recall %.3f (%d/%d) | FA_H %.3f | VETO_G %.3f | va cham %.4f -> %.4f"
              % (kl, kw, sc, uv, r["recall"], r["caught"], colH.sum(), r["fa_H"], r["veto_G"], r["coll_before"],
                 r["coll_after"]), flush=True)
    name = "tune_%s%s.json" % (a.prefix.rstrip("_") or "val", a.tag)
    if a.only:
        name = "final_%s.json" % (a.prefix.rstrip("_") or "val")
    (OUT / name).write_text(json.dumps(rows, indent=1))
    print("ghi", name)


if __name__ == "__main__":
    main()
