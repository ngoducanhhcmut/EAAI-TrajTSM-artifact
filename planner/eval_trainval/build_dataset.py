# -*- coding: utf-8 -*-
"""Buoc 1 — trich du lieu danh gia dien rong tu nuScenes v1.0-trainval, tach VAL (150 canh, 5.419 keyframe).

Cung danh sach mau voi bai bao (sw/golden_trainval/eval_scenarios.json). Moi mau:
  tok (64,6) f32, pad (64,) bool, gt (4,2) f32         — dau vao / nhan Traj (nuscenes_loader, nhu luc huan luyen)
  objs: moi vat the trong 50 m: vi tri + kich thuoc + huong (khung ego HIEN TAI), lop,
        vi tri tuong lai tai t = 0,5 / 1,0 / 1,5 / 2,0 s (theo chuoi annotation 'next' cua cung instance,
        doi ve khung ego hien tai; NaN neu vat the bien mat)       — dung de cham an toan TSM
Ra: sw/eval_trainval/out/dataset.npz + objects.pkl
  python sw/eval_trainval/build_dataset.py
"""
import sys, json, math, pickle, time
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "eval"))
from data.nuscenes_lite import load_nuscenes                       # noqa: E402
from data.nuscenes_loader import build_tokens_for_sample, get_gt_waypoints, _get_ego_pose  # noqa: E402
from pyquaternion import Quaternion                                  # noqa: E402

OUT = ROOT / "sw" / "eval_trainval" / "out"
OUT.mkdir(parents=True, exist_ok=True)
R_MAX = 50.0


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", default="val", choices=["val", "train"])
    ap.add_argument("--stride", type=int, default=12, help="train: lay 1 keyframe moi STRIDE keyframe")
    a = ap.parse_args()
    t0 = time.time()
    nusc = load_nuscenes(version="v1.0-trainval", dataroot=str(ROOT / "eval/data/nuscenes"), verbose=True)
    print("nap nuScenes trainval: %.0f s" % (time.time() - t0), flush=True)
    if a.split == "val":
        rows = json.load(open(ROOT / "sw" / "golden_trainval" / "eval_scenarios.json"))
        pre = ""
    else:
        # Tap con TRAIN (chi dung de CHON THAM SO cua TSM, khong bao cao): keyframe cach deu, du 4 waypoint tuong lai
        from nuscenes.utils.splits import create_splits_scenes
        trs = set(create_splits_scenes()["train"])
        rows, n = [], 0
        for sc in nusc.scene:
            if sc["name"] not in trs:
                continue
            t = sc["first_sample_token"]
            while t:
                if n % a.stride == 0:
                    rows.append(dict(scene=sc["name"], token=t, tags="", spd_ms=0.0,
                                     **{"pred_t%.1f_%s" % (tt, c): 0.0 for tt in (0.5, 1.0, 1.5, 2.0) for c in "xy"}))
                n += 1
                t = nusc.get("sample", t)["next"]
        pre = "train_"
        print("tap TRAIN: %d keyframe (stride %d / %d)" % (len(rows), a.stride, n), flush=True)
    # Ban lite chi giu translation/size/prev/next -> doc them rotation + instance (chi canh VAL) va lop.
    from data.nuscenes_lite import _stream_json_array
    base = ROOT / "eval/data/nuscenes/v1.0-trainval"
    vscn = {r["scene"] for r in rows}
    vsmp = set()
    for sc in nusc.scene:
        if sc["name"] in vscn:
            t = sc["first_sample_token"]
            while t:
                vsmp.add(t); t = nusc.get("sample", t)["next"]
    cat = {c["token"]: c["name"] for c in json.load(open(base / "category.json"))}
    inst_cat = {x["token"]: cat[x["category_token"]] for x in json.load(open(base / "instance.json"))}
    EXTRA = {}
    for a in _stream_json_array(str(base / "sample_annotation.json")):
        if a["sample_token"] in vsmp:
            EXTRA[a["token"]] = (a["rotation"], a["instance_token"], inst_cat[a["instance_token"]])
    print("bo sung rotation/lop cho %d annotation VAL: %.0f s" % (len(EXTRA), time.time() - t0), flush=True)
    N = len(rows)
    TOK = np.zeros((N, 64, 6), np.float32); PAD = np.zeros((N, 64), bool); GT = np.zeros((N, 4, 2), np.float32)
    keep = np.ones(N, bool)
    objs_all = []
    for i, r in enumerate(rows):
        st = r["token"]
        gt = get_gt_waypoints(nusc, st)
        if gt is None:
            keep[i] = False; objs_all.append([]); continue
        tok, pad = build_tokens_for_sample(nusc, st, include_lane_tokens=True)
        TOK[i], PAD[i], GT[i] = tok, pad, gt
        ego_t, ego_r = _get_ego_pose(nusc, st)
        inv = ego_r.inverse
        ego_yaw = ego_r.yaw_pitch_roll[0]
        sample = nusc.get("sample", st)
        objs = []
        for at in sample["anns"]:
            ann = nusc.get("sample_annotation", at)
            c = inv.rotate(np.array(ann["translation"]) - ego_t)
            if math.hypot(c[0], c[1]) > R_MAX:
                continue
            rot, inst, cname = EXTRA[at]
            yaw = Quaternion(rot).yaw_pitch_roll[0] - ego_yaw
            fut = np.full((4, 3), np.nan, np.float32)          # x, y, yaw tai 0,5..2,0 s
            # Vi tri QUA KHU (annotation 'prev', ~0,5 s truoc) -> uoc luong van toc NHAN QUA nhu bo tracking
            prv = np.full(3, np.nan, np.float32)               # x, y (khung ego hien tai), dt (s)
            if ann.get("prev"):
                pa = nusc.get("sample_annotation", ann["prev"])
                pc = inv.rotate(np.array(pa["translation"]) - ego_t)
                dtp = (sample["timestamp"] - nusc.get("sample", pa["sample_token"])["timestamp"]) * 1e-6
                prv[:] = (pc[0], pc[1], dtp)
            a = ann
            for k in range(4):
                if not a.get("next"):
                    break
                a = nusc.get("sample_annotation", a["next"])
                fc = inv.rotate(np.array(a["translation"]) - ego_t)
                fut[k] = (fc[0], fc[1], Quaternion(EXTRA[a["token"]][0]).yaw_pitch_roll[0] - ego_yaw)
            objs.append(dict(x=float(c[0]), y=float(c[1]), yaw=float(yaw), w=float(ann["size"][0]),
                             l=float(ann["size"][1]), cat=cname, inst=inst,
                             fut=fut, prv=prv))
        objs_all.append(objs)
        if i % 250 == 0:
            print("  %d/%d  %.0f s" % (i, N, time.time() - t0), flush=True)
    np.savez_compressed(OUT / (pre + "dataset.npz"), tok=TOK, pad=PAD, gt=GT, keep=keep,
                        token=np.array([r["token"] for r in rows]), scene=np.array([r["scene"] for r in rows]),
                        tags=np.array([r["tags"] for r in rows]), spd=np.array([r["spd_ms"] for r in rows]),
                        paper_w4a8=np.array([[[r["pred_t%.1f_x" % t], r["pred_t%.1f_y" % t]]
                                              for t in (0.5, 1.0, 1.5, 2.0)] for r in rows], np.float32))
    with open(OUT / (pre + "objects.pkl"), "wb") as f:
        pickle.dump(objs_all, f)
    print("XONG: %d mau (giu %d), %d vat the, %.0f s" % (N, keep.sum(), sum(map(len, objs_all)), time.time() - t0))


if __name__ == "__main__":
    main()
