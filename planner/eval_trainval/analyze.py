# -*- coding: utf-8 -*-
"""Buoc 4 — cham diem: do chinh xac Traj + an toan he thong hop nhat Traj->TSM tren VAL nuScenes.

Quy uoc RMSE (giong bai bao): rmse_xy = RMS cua 4 gia tri per-waypoint RMSE (moi gia tri = sqrt(mean L2^2)).
Va cham THAT (doc lap voi TSM): hop ego 4,084 x 1,730 m (Renault Zoe, nuScenes), truc banh sau tai waypoint du doan,
huong theo tiep tuyen quy dao, so voi hop vat the tai VI TRI TUONG LAI THAT cua no (nhan nuScenes) o cung thoi diem.
  python sw/eval_trainval/analyze.py
"""
import re, json, pickle
from pathlib import Path
from collections import defaultdict
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "sw" / "eval_trainval" / "out"
EGO_L, EGO_W = 4.084, 1.730
EGO_C = 1.38   # goc khung ego nuScenes = TRUC BANH SAU; tam hop xe = 4,084/2 - nho sau ~0,66 m phia truoc
HOLD_DISP = float(__import__('os').environ.get('LABEL_HOLD_DISP', '0.25'))   # 0.05 = nhan cu (v1 bao cao)
NAMES = {"fp32": "FP32 (mo hinh goc, phan mem)", "w4a8": "W4A8 (luong tu, phan mem)",
         "hw_new": "PHAN CUNG MOI (BERT V2, khop tung bit RTL)", "hw_old": "Phan cung CU (BERT cu)"}


def metrics(P, G):
    e = np.linalg.norm(P - G, axis=2)
    pw = np.sqrt((e ** 2).mean(0))
    return dict(n=int(len(e)), ade=float(e.mean()), fde=float(e[:, -1].mean()),
                rmse_xy=float(np.sqrt((pw ** 2).mean())), per_wp_rmse=[float(x) for x in pw],
                l2_t=[float(x) for x in e.mean(0)], miss2m=float((e[:, -1] > 2.0).mean()),
                fde_p50=float(np.median(e[:, -1])), fde_p90=float(np.percentile(e[:, -1], 90)))


def corners(x, y, yaw, l, w):
    c, s = np.cos(yaw), np.sin(yaw)
    dx = np.array([l, l, -l, -l]) / 2; dy = np.array([w, -w, -w, w]) / 2
    return np.stack([x + c * dx - s * dy, y + s * dx + c * dy], -1)


def overlap(A, B):
    for P in (A, B):
        for k in range(2):
            ax = P[k + 1] - P[k]; n = np.array([-ax[1], ax[0]])
            pa, pb = A @ n, B @ n
            if pa.max() < pb.min() or pb.max() < pa.min():
                return False
    return True


def collides(path4, objs):
    """True neu hop ego tai 1 trong 4 waypoint chong lan hop vat the tai vi tri tuong lai that cung thoi diem."""
    pts = np.vstack([[0, 0], path4])
    # Bo vat the DA chong len hop ego o tu the HIEN TAI (t = 0): ve vat ly khong the -> la sai so hinh hoc
    # (kich thuoc/goc ego, nhan hop). Chi tinh chong lan PHAT SINH do chuyen dong trong 2 s toi.
    E0 = corners(EGO_C, 0.0, 0.0, EGO_L, EGO_W)
    objs = [o for o in objs if np.hypot(o["x"] - EGO_C, o["y"]) > 8.0 or
            not overlap(E0, corners(o["x"], o["y"], o["yaw"], o["l"], o["w"]))]
    # Nhan v2 (05/10/2026): GIU HUONG khi buoc dich chuyen < HOLD_DISP (0,25 m / 0,5 s = 0,5 m/s), cung quy
    # uoc voi dong goi quy dao. Nhan cu xoay hop xe theo huong cua vai cm dich chuyen (vd -176 do khi xe nhich
    # 8 cm) -> "va cham" gia voi xe dau canh; 12/16 ca TSM v2.1 "bo sot" la loai nay (VH AK.17).
    yaw = 0.0
    for k in range(4):
        d = pts[k + 1] - pts[k]
        if np.hypot(*d) >= HOLD_DISP:
            yaw = np.arctan2(d[1], d[0])
        elif HOLD_DISP <= 0.05:
            yaw = np.arctan2(d[1], d[0]) if np.hypot(*d) > 0.05 else 0.0
        cx, cy = pts[k + 1][0] + EGO_C * np.cos(yaw), pts[k + 1][1] + EGO_C * np.sin(yaw)
        E = corners(cx, cy, yaw, EGO_L, EGO_W)
        for o in objs:
            fx, fy, fyaw = o["fut"][k]
            if np.isnan(fx) or np.hypot(fx - cx, fy - cy) > 8.0:
                continue
            if overlap(E, corners(fx, fy, fyaw, o["l"], o["w"])):
                return True
    return False


def parse_tsm():
    res = {}
    for f in sorted((ROOT / "reports" / "tsm_eval").glob("run_s*/sim.log")):
        for m in re.finditer(r"\[([HG]\d{4})\] \S+ clearance=(\S+)m .*?got=\s*(GRANT|VETO) faults=0x(\w+) viol=(\w+)",
                             f.read_text(errors="ignore")):
            res[m.group(1)] = dict(dec=m.group(3), faults=int(m.group(4), 16), viol=int(m.group(5), 16))
    return res


def main():
    D = np.load(OUT / "dataset.npz")
    objs_all = pickle.load(open(OUT / "objects.pkl", "rb"))
    keep = D["keep"]; idx = np.nonzero(keep)[0]; G = D["gt"]
    preds = {k: np.load(OUT / ("pred_%s.npy" % k)) for k in NAMES if (OUT / ("pred_%s.npy" % k)).exists()}
    R = dict(n_samples=int(len(idx)), n_scenes=int(len(set(D["scene"][idx]))), traj={}, by_tag={}, tsm={})
    for k, P in preds.items():
        R["traj"][k] = metrics(P[idx], G[idx])
        R["traj"][k]["final_wp_std"] = [float(x) for x in P[idx, -1].std(0)]
        R["traj"][k]["unique_traj"] = int(len(np.unique(np.round(P[idx], 3), axis=0)))
    R["traj"]["paper_w4a8_json"] = metrics(D["paper_w4a8"][idx], G[idx])
    R["traj"]["gt_final_wp_std"] = [float(x) for x in G[idx, -1].std(0)]
    if "hw_new" in preds:
        for ref in ("w4a8", "fp32"):
            if ref in preds:
                d = np.linalg.norm(preds["hw_new"][idx] - preds[ref][idx], axis=2)
                R["traj"]["hw_new_vs_" + ref] = dict(mean=float(d.mean()), p99=float(np.percentile(d, 99)),
                                                     max=float(d.max()))
    tags = defaultdict(list)
    for i in idx:
        for t in str(D["tags"][i]).split("|"):
            if t: tags[t].append(i)
    for t, ii in sorted(tags.items(), key=lambda x: -len(x[1])):
        R["by_tag"][t] = {k: dict(n=len(ii), ade=float(np.linalg.norm(P[ii] - G[ii], axis=2).mean()),
                                  fde=float(np.linalg.norm(P[ii, -1] - G[ii, -1], axis=1).mean()))
                          for k, P in preds.items()}
    # ---- va cham that cua ke hoach (doc lap TSM) ----
    col = {}
    for k, P in list(preds.items()) + [("gt", G)]:
        col[k] = np.array([collides(P[i], objs_all[i]) for i in idx])
        R.setdefault("collision", {})[k] = dict(rate=float(col[k].mean()), n=int(col[k].sum()))
    # ---- TSM (RTL) ----
    T = parse_tsm()
    if T:
        pos = {int(i): j for j, i in enumerate(idx)}
        for kind, pk in (("H", "hw_new"), ("G", "gt")):
            ids = [i for i in idx if ("%s%04d" % (kind, i)) in T]
            veto = np.array([T["%s%04d" % (kind, i)]["dec"] == "VETO" for i in ids])
            wdt = sum(T["%s%04d" % (kind, i)]["faults"] & 0x40 != 0 for i in ids)
            c = col[pk][[pos[i] for i in ids]]
            R["tsm"][pk] = dict(n=len(ids), veto_rate=float(veto.mean()) if len(ids) else None, wdt_faults=int(wdt),
                                collide_n=int(c.sum()), veto_on_collide=int((veto & c).sum()),
                                recall=float((veto & c).sum() / max(c.sum(), 1)),
                                false_alarm_rate=float((veto & ~c).sum() / max((~c).sum(), 1)))
            if pk == "hw_new":
                # he thong hop nhat: GRANT -> chay quy dao Traj; VETO -> dung khan cap (MRM)
                R["tsm"]["system"] = dict(collide_before_tsm=int(c.sum()),
                                          collide_after_tsm=int((c & ~veto).sum()),
                                          collide_rate_before=float(c.mean()), collide_rate_after=float((c & ~veto).mean()),
                                          availability=float(1 - veto.mean()))
        # ty le VETO theo khoang ho TINH (quy dao 0-5 s vs vi tri HIEN TAI cua vat the = dieu TSM nhin thay)
        C = {c["tc_id"]: c["clearance"] for c in json.load(open(OUT / "tsm_cases.json"))}
        bins = [(-99, -0.5), (-0.5, 0.0), (0.0, 1.0), (1.0, 2.0), (2.0, 3.0), (3.0, 99)]
        for kind in "HG":
            tb = []
            for lo, hi in bins:
                ids = [t for t in T if t[0] == kind and lo <= C[t] < hi]
                tb.append(dict(range=[lo, hi], n=len(ids),
                               veto_rate=float(np.mean([T[t]["dec"] == "VETO" for t in ids])) if ids else None))
            R["tsm"]["veto_by_static_clearance_" + kind] = tb
        both = [i for i in idx if ("H%04d" % i) in T and ("G%04d" % i) in T]
        agree = np.mean([T["H%04d" % i]["dec"] == T["G%04d" % i]["dec"] for i in both]) if both else None
        R["tsm"]["agree_hw_vs_gt_decision"] = float(agree) if agree is not None else None
    (OUT / "results.json").write_text(json.dumps(R, indent=1))
    print(json.dumps(R["traj"], indent=1)); print(json.dumps(R.get("collision"), indent=1)); print(json.dumps(R["tsm"], indent=1))


if __name__ == "__main__":
    main()
