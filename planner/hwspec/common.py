# -*- coding: utf-8 -*-
"""Nap mo hinh W4A8, tap hieu chinh, 35 mau golden_spec, va tham so hwspec — dung chung."""
import sys
import pickle
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
for p in (ROOT / "eval", ROOT / "sw" / "hwspec"):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

CACHE = ROOT / "sw" / "hwspec" / "_cache_params.pkl"


def load_model():
    import torch
    from model.fp32_model import build_model
    from model.w4a8_inference import W4A8PlanningModel
    from data.nuscenes_loader import load_nuscenes_samples
    from nuscenes.nuscenes import NuScenes
    nusc = NuScenes(version="v1.0-mini", dataroot=str(ROOT / "eval/data/nuscenes"), verbose=False)
    ct, cm, _ = load_nuscenes_samples(nusc, num_scenes=5, split="mini_train", include_lane_tokens=True)
    fp = build_model()
    ck = torch.load(ROOT / "eval/archived_weights/autoregressive_gru_200ep.pt", map_location="cpu")
    fp.load_state_dict(ck.get("model", ck)); fp.eval()
    m = W4A8PlanningModel.from_fp32(fp, ct, cm, symmetric_acts=True)
    return m, ct, cm


def load_all(rebuild=False):
    """Tra (m, P): mo hinh W4A8 va tham so phan cung (co cache)."""
    from hwspec_model import HwSpec
    from hwspec_exact import build_params
    if CACHE.exists() and not rebuild:
        with open(CACHE, "rb") as f:
            return pickle.load(f)
    m, ct, cm = load_model()
    hs = HwSpec(m, ct, cm, {})
    P = build_params(m, hs.cal)
    with open(CACHE, "wb") as f:
        pickle.dump((m, P), f)
    return m, P


def samples():
    G = ROOT / "sw" / "golden_spec"
    out = []
    for d in sorted(G.glob("sample_*")):
        tok = np.fromfile(d / "input_tokens.bin", np.float32).reshape(64, 6)
        pad = np.fromfile(d / "input_mask.bin", np.uint8).astype(bool)
        gt = np.fromfile(d / "gt_waypoints.bin", np.float32).reshape(4, 2)
        out.append(dict(name=d.name, dir=d, tok=tok, pad=pad, gt=gt))
    return out
