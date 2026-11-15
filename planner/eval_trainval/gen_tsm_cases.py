# -*- coding: utf-8 -*-
"""Buoc 3 — sinh ca chay RTL TSM (hmao_engine_top) cho moi mau VAL.

Moi mau i -> 2 ca, dung CHUNG 1 world model (toi da 100 vat the that gan quy dao nhat, huong that):
  H<i> : quy dao = waypoint PHAN CUNG MOI (pred_hw_new)   -> quyet dinh cua he thong hop nhat Traj+TSM
  G<i> : quy dao = quy dao THAT cua nguoi lai (GT)        -> do ty le bao dong nham cua TSM
Dong goi giong het luong cosim da kiem (sw/gen_hmao_collision_e2e_dataset.py: expand_to_50wp,
build_traj_hex, pack_world_model_object), chi them huong that cua vat the va nhieu vat the/ca.
Ra: out/tsm_hex/*.hex, out/tsm_cases.json, tb/eval_tsm/tb_tsm_eval_<k>.sv (K manh chay song song)
  python sw/eval_trainval/gen_tsm_cases.py [--shards 10] [--limit N]
"""
import sys, json, math, pickle, argparse
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "sw" / "eval_trainval" / "out"
HEX = OUT / "tsm_hex"
TBD = ROOT / "tb" / "eval_tsm"
sys.path.insert(0, str(ROOT / "sw"))
import gen_hmao_collision_e2e_dataset as g          # noqa: E402


def obj_vel(o):
    """Van toc NHAN QUA (m/s) tu vi tri ~0,5 s truoc; khong co -> 0 (giong tsm_model.obj_arrays)."""
    p = o.get("prv")
    if p is None or np.isnan(p[0]) or not (0.2 < p[2] < 1.0):
        return 0.0, 0.0
    return (o["x"] - p[0]) / p[2], (o["y"] - p[1]) / p[2]

MAXOBJ = g.WM_MAX_OBJECTS                            # 100 = MAX_OBSTACLES cua hmao_collision_sat


def poly_dist(px, py, poly):
    P = np.asarray(poly); A, B = P[:-1], P[1:]
    d = B - A; L2 = (d ** 2).sum(1)
    t = np.clip(((px - A[:, 0]) * d[:, 0] + (py - A[:, 1]) * d[:, 1]) / np.maximum(L2, 1e-9), 0, 1)
    q = A + t[:, None] * d
    return float(np.min(np.hypot(px - q[:, 0], py - q[:, 1])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shards", type=int, default=10)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--pred", default="pred_hw_new.npy")
    a = ap.parse_args()
    D = np.load(OUT / "dataset.npz")
    objs_all = pickle.load(open(OUT / "objects.pkl", "rb"))
    pred = np.load(OUT / a.pred)
    idx = [int(i) for i in np.nonzero(D["keep"])[0]]
    if a.limit:
        idx = idx[:a.limit]
    HEX.mkdir(parents=True, exist_ok=True); TBD.mkdir(parents=True, exist_ok=True)
    cases, ntrunc = [], 0
    for i in idx:
        hw = [(float(x), float(y)) for x, y in pred[i]]
        gt = [(float(x), float(y)) for x, y in D["gt"][i]]
        th, tg = g.expand_to_50wp(hw), g.expand_to_50wp(gt)
        objs = objs_all[i]
        for o in objs:
            o["clr_h"] = poly_dist(o["x"], o["y"], th) - max(o["w"], o["l"]) / 2
            o["clr_g"] = poly_dist(o["x"], o["y"], tg) - max(o["w"], o["l"]) / 2
        sel = sorted(objs, key=lambda o: min(o["clr_h"], o["clr_g"]))[:MAXOBJ]
        ntrunc += len(objs) > MAXOBJ
        wm = bytearray()
        for k, o in enumerate(sel):
            vxo, vyo = obj_vel(o)
            wm += g.pack_world_model_object(o["x"], o["y"], o["w"], o["l"], heading_rad=o["yaw"], track_id=k,
                                            vel_x_ms=vxo, vel_y_ms=vyo,
                                            obj_class=g.CATEGORY_MAP.get(o["cat"], g.OBJ_CAR), confidence=100)
        wm += bytes(g.WM_OBJECT_BYTES * (MAXOBJ - len(sel)))
        g.write_hex(HEX / ("W%04d.hex" % i), bytes(wm), word_size=4)
        g.build_traj_hex(hw, HEX / ("H%04d.hex" % i))
        g.build_traj_hex(gt, HEX / ("G%04d.hex" % i))
        for kind, key in (("H", "clr_h"), ("G", "clr_g")):
            cmin = min([o[key] for o in sel], default=99.0)
            cases.append(dict(tc_id="%s%04d" % (kind, i), idx=i, kind=kind, traj_hex="%s%04d.hex" % (kind, i),
                              wm_hex="W%04d.hex" % i, category="n%d" % len(sel), clearance=cmin,
                              expected="BOUNDARY"))
    (OUT / "tsm_cases.json").write_text(json.dumps(cases))
    # chia manh: xen ke de moi manh co tai tuong duong
    K = a.shards
    for k in range(K):
        sub = cases[k::K]
        g.TB_OUT_PATH = TBD / ("tb_tsm_eval_%d.sv" % k)
        g.generate_sv_testbench(sub)
        s = g.TB_OUT_PATH.read_text(encoding="utf-8")
        s = s.replace("module tb_hmao_collision_e2e_real_nuscenes", "module tb_tsm_eval_%d" % k)
        s = s.replace('`define HEX_DIR "sw/hmao_payloads/collision_e2e"', '`define HEX_DIR "%s"' % HEX.as_posix())
        # in them co vi pham (64 bit) + do tre + bien -> so sanh tuong duong tung ca (che do nhanh vs day du)
        old1 = 'BOUNDARY (no assert) got=%s faults=0x%02h",'
        new1 = 'BOUNDARY (no assert) got=%s faults=0x%02h viol=%016h lat=%0d mg=%04h/%04h/%04h",'
        old2 = 'decision?"GRANT":"VETO", fault_bits);\n          if (decision)'
        new2 = ('decision?"GRANT":"VETO", fault_bits, hmao_violation, hmao_latency, lat_margin, '
                'long_margin, time_margin);\n          if (decision)')
        assert old1 in s and old2 in s, "khong tim thay dong $display BOUNDARY de va"
        s = s.replace(old1, new1).replace(old2, new2)
        # v2: chat luong cam bien giong HET block design that (wrapper noi cung 0xFF / thoi tiet 0x00)
        for q in ("gps_quality", "cam_quality", "road_friction", "act_health"):
            s = s.replace("logic [7:0]  %s%s= 8'd200;" % (q, " " * (14 - len(q))), "logic [7:0]  %s%s= 8'd255;" % (q, " " * (14 - len(q))))
        s = "// TU DONG SINH boi sw/eval_trainval/gen_tsm_cases.py — danh gia TSM dien rong (VAL nuScenes).\n" + s
        g.TB_OUT_PATH.write_text(s, encoding="utf-8")
    print("ca: %d (%d mau x 2) | mau co > %d vat the (cat bot): %d | %d manh -> %s" %
          (len(cases), len(idx), MAXOBJ, ntrunc, K, TBD))


if __name__ == "__main__":
    main()
