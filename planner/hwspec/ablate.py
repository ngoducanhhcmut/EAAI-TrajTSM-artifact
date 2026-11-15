# -*- coding: utf-8 -*-
"""Giai doan 0.2 — do anh huong tung lua chon so hoc cua hwspec len do chinh xac tac vu.

In ADE/FDE/RMSE so voi GT, do lech so voi mo hinh W4A8 phan mem, va do PHAN TAN waypoint
cuoi giua cac mau (std) — de bat loi "mot quy dao cho moi canh".
"""
import sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "eval")); sys.path.insert(0, str(ROOT / "sw" / "hwspec"))

import torch                                                     # noqa: E402
from model.fp32_model import build_model                         # noqa: E402
from model.w4a8_inference import W4A8PlanningModel               # noqa: E402
from data.nuscenes_loader import load_nuscenes_samples           # noqa: E402
from nuscenes.nuscenes import NuScenes                           # noqa: E402
from hwspec_model import HwSpec                                  # noqa: E402

nusc = NuScenes(version="v1.0-mini", dataroot=str(ROOT / "eval/data/nuscenes"), verbose=False)
ct, cm, _ = load_nuscenes_samples(nusc, num_scenes=5, split="mini_train", include_lane_tokens=True)
fp = build_model()
ck = torch.load(ROOT / "eval/archived_weights/autoregressive_gru_200ep.pt", map_location="cpu")
fp.load_state_dict(ck.get("model", ck)); fp.eval()
m = W4A8PlanningModel.from_fp32(fp, ct, cm, symmetric_acts=True)

G = ROOT / "sw" / "golden_spec"
S = []
for d in sorted(G.glob("sample_*")):
    tok = np.fromfile(d / "input_tokens.bin", np.float32).reshape(64, 6)
    mask = np.fromfile(d / "input_mask.bin", np.uint8).astype(bool)
    gt = np.fromfile(d / "gt_waypoints.bin", np.float32).reshape(4, 2)
    sw = m.forward(tok[None], mask[None])[0]      # moc: mo hinh W4A8 tinh truc tiep
    S.append((tok, mask, gt, sw))
gts = np.array([s[2] for s in S])

CFGS = [
    ("A tham chieu (giong W4A8)",          {}),
    ("B attn INT8",                        dict(attn="int8")),
    ("C attn INT8 + prob u8",              dict(attn="int8", prob="u8")),
    ("D GELU lut8",                        dict(gelu="lut8")),
    ("E residual INT16",                   dict(resid="int16")),
    ("F residual INT8",                    dict(resid="int8")),
    ("G B+C+D (residual FP32)",            dict(attn="int8", prob="u8", gelu="lut8")),
    ("H G + residual INT16",               dict(attn="int8", prob="u8", gelu="lut8", resid="int16")),
    ("I khong bias",                       dict(bias=False)),
    ("J khong proj_ln/final_ln",           dict(proj_ln=False, final_ln=False)),
]
only = sys.argv[1:]
print("%-30s %6s %6s %6s %8s %8s %8s" % ("cau hinh", "ADE", "FDE", "RMSE", "vsSW_ADE", "std_x", "std_y"))
print("%-30s %6s %6s %6s %8s %8.3f %8.3f" % ("(GT)", "", "", "", "", gts[:, -1, 0].std(), gts[:, -1, 1].std()))
for name, opts in CFGS:
    if only and name[0] not in only:
        continue
    hs = HwSpec(m, ct, cm, opts)
    W = np.array([hs.waypoints(t, mk) for t, mk, _, _ in S])
    e = np.linalg.norm(W - gts, axis=2)
    esw = np.linalg.norm(W - np.array([s[3] for s in S]), axis=2)
    print("%-30s %6.3f %6.3f %6.3f %8.3f %8.3f %8.3f" % (
        name, e.mean(), e[:, -1].mean(), np.sqrt((e ** 2).mean()), esw.mean(),
        W[:, -1, 0].std(), W[:, -1, 1].std()), flush=True)
