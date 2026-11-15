# -*- coding: utf-8 -*-
"""So sanh TSM v1 va v2.1 tren cung 10.838 luot RTL (VAL), voi hai dinh nghia nhan va cham.

  nhan cu  : huong hop ego = huong dich chuyen neu > 5 cm (LABEL_HOLD_DISP=0.05) — dung trong AK.13/AK.16
  nhan v2  : giu huong khi buoc < 0,25 m / 0,5 s (= 0,5 m/s), cung quy uoc dong goi quy dao (AK.17)
v2.1 = log RTL reports/tsm_eval/run_s0..7/sim.log. v1: log RTL cu da bi ghi de khi chay v2 (cung thu muc
run_s*), nen dung mo hinh tsm_model.decide_old — khop RTL v1 that 99,11% (H) / 99,30% (G) (AK.15).
Ra: sw/eval_trainval/out/compare_v1_v2.json
  python sw/eval_trainval/compare_v1_v2.py
"""
import sys, re, json, pickle
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import analyze as A                                   # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "sw" / "eval_trainval" / "out"


def parse(pattern):
    res = {}
    for f in sorted((ROOT / "reports" / "tsm_eval").glob(pattern)):
        for m in re.finditer(r"\[([HG]\d{4})\] \S+ clearance=\S+ .*?got=\s*(GRANT|VETO)", f.read_text(errors="ignore")):
            res[m.group(1)] = m.group(2)
    return res


def score(dec, colH, colG, n):
    vH = np.array([dec["H%04d" % i] == "VETO" for i in range(n)])
    vG = np.array([dec["G%04d" % i] == "VETO" for i in range(n)])
    return dict(n_coll=int(colH.sum()), caught=int((vH & colH).sum()),
                recall=float((vH & colH).sum() / max(colH.sum(), 1)),
                fa_H=float((vH & ~colH).sum() / max((~colH).sum(), 1)),
                veto_G=float(vG.mean()), veto_H=float(vH.mean()),
                coll_before=float(colH.mean()), coll_after=float((colH & ~vH).mean()),
                availability=float(1 - vH.mean()), gt_coll=int(colG.sum()), gt_caught=int((vG & colG).sum()))


def main():
    D = np.load(OUT / "dataset.npz", allow_pickle=True)
    O = pickle.load(open(OUT / "objects.pkl", "rb"))
    P = np.load(OUT / "pred_hw_new.npy"); G = D["gt"]; n = len(P)
    import tsm_model as M
    from validate_model import select
    v1 = {}
    for i in range(n):
        sel = select(O[i], P[i], G[i])
        v1["H%04d" % i] = M.decide_old(P[i], sel); v1["G%04d" % i] = M.decide_old(G[i], sel)
    dec = {"v1 (mo hinh)": v1, "v2.1 (RTL)": parse("run_s[0-7]/sim.log")}
    for k, v in dec.items():
        assert len(v) == 2 * n, "%s: %d/%d quyet dinh" % (k, len(v), 2 * n)
    R = {}
    for lab, hold in (("nhan_cu", 0.05), ("nhan_v2", 0.25)):
        A.HOLD_DISP = hold
        colH = np.array([A.collides(P[i], O[i]) for i in range(n)])
        colG = np.array([A.collides(G[i], O[i]) for i in range(n)])
        R[lab] = {k: score(v, colH, colG, n) for k, v in dec.items()}
        for k, s in R[lab].items():
            print("%-8s %-13s | va cham %3d | bat %3d (%.1f%%) | bao dong nham %.2f%% | VETO nguoi lai %.2f%% | "
                  "va cham he thong %.2f%% -> %.2f%% | kha dung %.1f%% | GT va cham %d (bat %d)"
                  % (lab, k, s["n_coll"], s["caught"], 100 * s["recall"], 100 * s["fa_H"], 100 * s["veto_G"],
                     100 * s["coll_before"], 100 * s["coll_after"], 100 * s["availability"], s["gt_coll"], s["gt_caught"]))
    (OUT / "compare_v1_v2.json").write_text(json.dumps(R, indent=1))


if __name__ == "__main__":
    main()
