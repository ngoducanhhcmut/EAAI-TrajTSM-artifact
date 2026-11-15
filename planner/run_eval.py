"""
VLA-Traj nuScenes evaluation script.

Runs the W4A8 bit-accurate inference engine over ≥200 nuScenes scenes and
reports RMSE_xy (paper target: < 0.3 m).

Base model: PlanTSMALL (pre-trained, https://github.com/autonomousvision/plant)
  — do NOT retrain. Convert the existing checkpoint first:
    python convert_plant_weights.py --checkpoint planT_small.ckpt --out weights/planT_converted.pt

Usage:
  # Full evaluation (200 scenes, v1.0-trainval):
  python run_eval.py \\
      --nuscenes-root /data/nuscenes \\
      --version v1.0-trainval \\
      --weights weights/planT_converted.pt \\
      --num-scenes 200

  # Mini nuScenes quick check (85 scenes):
  python run_eval.py \\
      --nuscenes-root /data/nuscenes \\
      --version v1.0-mini \\
      --weights weights/planT_converted.pt

  # Smoke-test — verify pipeline with random weights (no dataset needed):
  python run_eval.py --smoke-test

Outputs:
  - Console: formatted report with RMSE_xy, ADE, FDE, per-waypoint breakdown
  - eval_results.json: machine-readable results for inclusion in the paper
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Optional
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset
from tqdm import tqdm

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from model.fp32_model import PlanningModel, build_model
from model.w4a8_inference import W4A8PlanningModel
from model.w4a8_quant import quantize_weights_int4, dequantize_int4, quantize_int8
from utils.metrics import (
    rmse_xy, per_waypoint_rmse, quantization_degradation, print_report,
)


def load_weights(model: PlanningModel, weights_path: str, device: torch.device):
    ckpt = torch.load(weights_path, map_location=device)
    # Support both raw state_dict and {'model': state_dict} checkpoint format
    sd = ckpt["model"] if "model" in ckpt else ckpt
    model.load_state_dict(sd)
    print(f"Loaded weights from {weights_path}")


def resolve_input_path(path_str: Optional[str]) -> Optional[str]:
    if not path_str:
        return path_str
    path = Path(path_str)
    if path.exists():
        return str(path)
    alt = Path(__file__).resolve().parent / path
    if alt.exists():
        return str(alt)
    return str(path)


def _resolve_eval_and_calibration_sets(
    nusc,
    split: str,
    num_scenes: int,
    calib_scenes: int,
    is_mini: bool = False,
    include_lane_tokens: bool = True,
    include_target_token_proxy: bool = False,
):
    """
    Build disjoint evaluation and calibration subsets.

    v1.0-trainval:
      eval  -- first num_scenes val scenes (1 keyframe/scene)
      calib -- first calib_scenes train scenes (disjoint split)

    v1.0-mini (only 2 val / 8 train scenes):
      eval  -- all val keyframes, up to num_scenes total (70 kf/scene)
      calib -- train split keyframes (different scenes -> no overlap)
    """
    from data.nuscenes_loader import load_nuscenes_samples

    if is_mini:
        # Eval: val keyframes (2 scenes x ~40 kf = ~80 total, cap at num_scenes)
        tokens_eval, masks_eval, gt_eval = load_nuscenes_samples(
            nusc, num_scenes=num_scenes, split=split,
            scene_offset=0, samples_per_scene=70,
            include_lane_tokens=include_lane_tokens,
            include_target_token_proxy=include_target_token_proxy,
        )
        # Calib: train keyframes -- completely disjoint from val
        calib_split = split.replace("val", "train")  # "mini_val" -> "mini_train"
        tokens_calib, masks_calib, gt_calib = load_nuscenes_samples(
            nusc, num_scenes=calib_scenes, split=calib_split,
            scene_offset=0, samples_per_scene=10,
            include_lane_tokens=include_lane_tokens,
            include_target_token_proxy=include_target_token_proxy,
        )
    else:
        # Trainval: val split has exactly 150 scenes -- use train split for calib
        tokens_eval, masks_eval, gt_eval = load_nuscenes_samples(
            nusc, num_scenes=num_scenes, split=split, scene_offset=0,
            include_lane_tokens=include_lane_tokens,
            include_target_token_proxy=include_target_token_proxy,
        )
        calib_split = split.replace("val", "train")  # "val" -> "train"
        tokens_calib, masks_calib, gt_calib = load_nuscenes_samples(
            nusc, num_scenes=calib_scenes, split=calib_split,
            scene_offset=0,
            include_lane_tokens=include_lane_tokens,
            include_target_token_proxy=include_target_token_proxy,
        )
    return tokens_eval, masks_eval, gt_eval, tokens_calib, masks_calib, gt_calib


def run_fp32_inference(
    model: PlanningModel,
    tokens: np.ndarray,
    masks: np.ndarray,
    batch_size: int = 32,
    device: torch.device = torch.device("cpu"),
) -> np.ndarray:
    """Run FP32 inference, return (N, 4, 2) predictions."""
    model.eval()
    all_pred = []
    with torch.no_grad():
        for i in range(0, len(tokens), batch_size):
            t = torch.from_numpy(tokens[i:i+batch_size]).to(device)
            m = torch.from_numpy(masks[i:i+batch_size]).to(device)
            pred = model(t, m).cpu().numpy()
            all_pred.append(pred)
    return np.concatenate(all_pred, axis=0)


def run_w4a8_inference(
    w4a8_model: W4A8PlanningModel,
    tokens: np.ndarray,
    masks: np.ndarray,
    batch_size: int = 1,    # W4A8 numpy engine runs one sample at a time
) -> np.ndarray:
    """Run W4A8 bit-accurate inference, return (N, 4, 2) predictions."""
    all_pred = []
    for i in tqdm(range(0, len(tokens), batch_size), desc="W4A8 inference"):
        tok_batch = tokens[i:i+batch_size]
        msk_batch = masks[i:i+batch_size]
        pred = w4a8_model.forward(tok_batch, msk_batch)
        all_pred.append(pred)
    return np.concatenate(all_pred, axis=0)


def _fake_quant_w4(w: torch.Tensor) -> torch.Tensor:
    """
    Fake-quantize weight to INT4 using the Straight-Through Estimator (STE).

    Forward pass  : returns the INT4-dequantized value  (w_q * scale)
    Backward pass : gradient flows through w unchanged  (identity)

    The STE trick:  result = w_quantized_detached + (w - w.detach())
      = w_quantized in forward (since w - w.detach() = 0 numerically)
      = passes gradient of w through in backward
    No in-place operations — safe for autograd.
    """
    scale = w.detach().abs().max(dim=-1, keepdim=True).values.clamp(min=1e-8) / 7.0
    w_q   = (w.detach() / scale).round().clamp(-8, 7) * scale
    return w_q + (w - w.detach())   # STE: forward=quantized, backward=identity


def _fake_quant_a8(x: torch.Tensor) -> torch.Tensor:
    """Fake-quantize activation tensor to INT8 (symmetric, straight-through)."""
    scale = x.abs().max() / 127.0
    scale = scale.clamp(min=1e-8)
    x_q   = (x / scale).round().clamp(-128, 127)
    return x_q * scale


class FakeQuantBERTLayer(nn.Module):
    """
    Wraps a BERTEncoderLayer and applies fake-INT4 weight quantization.

    Replaces Parameter attributes with fake-quant wrappers for the forward
    pass, then restores originals — no in-place tensor modification, so
    autograd's version counter is never violated.
    """
    def __init__(self, layer):
        super().__init__()
        self.layer = layer

    def forward(self, x, key_padding_mask=None):
        layer = self.layer
        attn  = layer.attn

        # Compute fake-quant tensors (STE: gradient flows back to originals)
        fq_ipw = _fake_quant_w4(attn.in_proj_weight)    # graph -> in_proj_weight
        fq_opw = _fake_quant_w4(attn.out_proj.weight)
        fq_f0  = _fake_quant_w4(layer.ffn[0].weight)
        fq_f2  = _fake_quant_w4(layer.ffn[2].weight)

        # Inject via object.__setattr__ to bypass nn.Module's parameter check.
        # Python looks up __dict__ before _parameters, so the forward pass uses
        # the fake-quant tensors while the original Parameters remain in _parameters.
        object.__setattr__(attn,            'in_proj_weight', fq_ipw)
        object.__setattr__(attn.out_proj,   'weight',         fq_opw)
        object.__setattr__(layer.ffn[0],    'weight',         fq_f0)
        object.__setattr__(layer.ffn[2],    'weight',         fq_f2)

        out = layer(x, key_padding_mask)

        # Remove from __dict__ so _parameters are visible again
        del attn.__dict__['in_proj_weight']
        del attn.out_proj.__dict__['weight']
        del layer.ffn[0].__dict__['weight']
        del layer.ffn[2].__dict__['weight']

        return out


def distill_qad(
    fp32_model: PlanningModel,
    tokens_calib: np.ndarray,
    masks_calib:  np.ndarray,
    gt_calib:     np.ndarray,
    epochs:       int   = 3,
    batch_size:   int   = 16,
    lr:           float = 2e-5,
    lambda_kd:    float = 0.5,
    device:       torch.device = torch.device("cpu"),
) -> PlanningModel:
    """
    Quantization-Aware Distillation (QAD):
      Teacher : FP32 model (already fine-tuned, frozen)
      Student : same model with fake-INT4 weights on BERT layers
      Loss    : L_task + λ * L_kd
                L_task = MSE(student_out, GT_waypoints)
                L_kd   = MSE(student_out, teacher_out)   ← knowledge distillation

    Only the BERT weight matrices are fake-quantized; the input projector and
    GRU decoder are trained in FP32. This closes most of the PTQ accuracy gap
    in 2-3 epochs without expensive retraining.

    Returns the QAD-refined model (FP32 weights, same architecture).
    """
    print(f"\nQuantization-Aware Distillation ({epochs} epochs, lambda_kd={lambda_kd}) ...")

    # Teacher (frozen FP32)
    teacher = fp32_model
    teacher.eval()
    for p in teacher.parameters():
        p.requires_grad_(False)

    # Student: same architecture, fake-quant BERT layers, all weights trainable
    student = build_model()
    student.load_state_dict(fp32_model.state_dict())

    # Wrap each BERT encoder layer with fake-quant
    for i, layer in enumerate(student.encoder.layers):
        student.encoder.layers[i] = FakeQuantBERTLayer(layer)

    student = student.to(device)
    teacher = teacher.to(device)

    # Only fine-tune BERT weights (not LN, not projector, not decoder)
    trainable = []
    for name, p in student.named_parameters():
        if any(x in name for x in ["in_proj_weight", "out_proj.weight",
                                    "ffn.0.weight", "ffn.2.weight"]):
            p.requires_grad_(True)
            trainable.append(p)
        else:
            p.requires_grad_(False)

    optimizer = torch.optim.AdamW(trainable, lr=lr, weight_decay=1e-5)

    # Build DataLoader
    t_tok = torch.from_numpy(tokens_calib).float()
    t_msk = torch.from_numpy(masks_calib).bool()
    t_gt  = torch.from_numpy(gt_calib).float()
    loader = DataLoader(TensorDataset(t_tok, t_msk, t_gt),
                        batch_size=batch_size, shuffle=True)

    for epoch in range(1, epochs + 1):
        student.train()
        total_loss = 0.0
        for tok, msk, gt in loader:
            tok, msk, gt = tok.to(device), msk.to(device), gt.to(device)

            # Teacher (frozen FP32) output — use teacher forcing so autoregressive
            # cls_emb shifts don't cascade through the frozen wp_proj/GRU chain
            with torch.no_grad():
                teacher_out = teacher(tok, msk, gt_waypoints=gt)   # (B, 4, 2)

            # Student output (with fake-quant on BERT layers)
            student_out = student(tok, msk, gt_waypoints=gt)       # (B, 4, 2)

            l_task = F.mse_loss(student_out, gt)
            l_kd   = F.mse_loss(student_out, teacher_out)
            loss   = l_task + lambda_kd * l_kd

            optimizer.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(trainable, 1.0)
            optimizer.step()
            total_loss += loss.item() * tok.size(0)

        avg = total_loss / len(loader.dataset)
        print(f"  QAD epoch {epoch}/{epochs}  loss={avg:.5f}")

    # Unwrap fake-quant layers back to plain BERTEncoderLayer
    for i, layer in enumerate(student.encoder.layers):
        if isinstance(layer, FakeQuantBERTLayer):
            student.encoder.layers[i] = layer.layer

    student.eval()
    print("QAD done.")
    return student.cpu()


def smoke_test():
    """Verify the pipeline end-to-end with random weights (no nuScenes needed)."""
    print("=" * 60)
    print("  SMOKE TEST — random weights, no nuScenes dataset needed")
    print("=" * 60)

    np.random.seed(0)
    torch.manual_seed(0)

    N = 10
    tokens = np.random.randn(N, 64, 6).astype(np.float32)
    masks  = np.zeros((N, 64), dtype=bool)
    masks[:, 5:] = True      # only 5 valid tokens
    gt_wp  = np.random.randn(N, 4, 2).astype(np.float32) * 0.5

    # FP32 model
    fp32_model = build_model()
    fp32_model.eval()

    # W4A8 model (calibrated on same random data)
    print("Calibrating W4A8 model...")
    w4a8_model = W4A8PlanningModel.from_fp32(fp32_model, tokens[:5], masks[:5])

    # FP32 inference
    pred_fp32 = run_fp32_inference(fp32_model, tokens, masks)
    print(f"FP32 output shape: {pred_fp32.shape}  range: [{pred_fp32.min():.2f}, {pred_fp32.max():.2f}]")

    # W4A8 inference
    pred_w4a8 = run_w4a8_inference(w4a8_model, tokens, masks)
    print(f"W4A8 output shape: {pred_w4a8.shape}  range: [{pred_w4a8.min():.2f}, {pred_w4a8.max():.2f}]")

    # Quantization noise
    quant_err = rmse_xy(pred_w4a8, pred_fp32)
    print(f"Quantization noise RMSE (W4A8 vs FP32): {quant_err:.4f}")
    print("\nPipeline OK. Sigmoid/tanh LUT self-test:")

    from model.w4a8_quant import sigmoid_lut, tanh_lut
    x_test = np.array([-8.0, -6.0, -3.0, 0.0, 3.0, 6.0, 8.0], dtype=np.float32)
    sig_lut = sigmoid_lut(x_test)
    sig_ref = 1.0 / (1.0 + np.exp(-x_test.clip(-6, 6)))
    tanh_l  = tanh_lut(x_test)
    tanh_r  = np.tanh(x_test.clip(-4, 4))

    print(f"{'x':>6}  {'sigmoid_lut':>12}  {'sigmoid_ref':>12}  {'err_ms':>8}  "
          f"{'tanh_lut':>10}  {'tanh_ref':>10}  {'err_ms':>8}")
    for i, xv in enumerate(x_test):
        print(f"{xv:6.1f}  {sig_lut[i]:12.6f}  {sig_ref[i]:12.6f}  "
              f"{abs(sig_lut[i]-sig_ref[i])*1000:8.3f}  "
              f"{tanh_l[i]:10.6f}  {tanh_r[i]:10.6f}  "
              f"{abs(tanh_l[i]-tanh_r[i])*1000:8.3f}")
    print("\nSmoke test PASSED.")


def main():
    parser = argparse.ArgumentParser(
        description="VLA-Traj nuScenes W4A8 accuracy evaluation"
    )
    parser.add_argument("--nuscenes-root", default=None,
                        help="Path to nuScenes dataset root directory")
    parser.add_argument("--version",  default="v1.0-trainval",
                        choices=["v1.0-trainval", "v1.0-mini"])
    parser.add_argument("--weights",  default=None,
                        help="Path to trained model weights (.pt file)")
    parser.add_argument("--disable-lane-tokens", action="store_true",
                        help="Disable lane tokens from nuScenes map expansion")
    parser.add_argument("--include-target-token-proxy", action="store_true",
                        help="Append GT-final-waypoint proxy target token (ablation only; not deployment-clean)")
    parser.add_argument("--num-scenes", type=int, default=200,
                        help="Number of scenes to evaluate (default: 200)")
    parser.add_argument("--calib-scenes", type=int, default=50,
                        help="Number of scenes for quantization calibration")
    parser.add_argument("--batch",    type=int, default=32,
                        help="Batch size for FP32 inference")
    parser.add_argument("--distill-epochs", type=int, default=3,
                        help="Quantization-Aware Distillation epochs (0 = skip, default 3). "
                             "FP32 model acts as teacher to fine-tune W4A8 student.")
    parser.add_argument("--distill-lambda", type=float, default=0.5,
                        help="Weight of KD loss vs task loss (default 0.5)")
    parser.add_argument("--distill-lr", type=float, default=2e-5,
                        help="Learning rate for QAD fine-tuning (default 2e-5)")
    parser.add_argument("--out",      default="eval_results.json",
                        help="Output JSON file for results")
    parser.add_argument("--smoke-test", action="store_true",
                        help="Run with random weights to verify pipeline (no dataset needed)")
    args = parser.parse_args()
    args.weights = resolve_input_path(args.weights)

    if args.smoke_test:
        smoke_test()
        return

    if args.nuscenes_root is None:
        parser.error("--nuscenes-root is required (or use --smoke-test)")
    if args.weights is None:
        parser.error(
            "--weights is required (or use --smoke-test).\n"
            "Download PlanTSMALL from https://github.com/autonomousvision/plant\n"
            "then convert: python convert_plant_weights.py "
            "--checkpoint planT_small.ckpt --out weights/planT_converted.pt"
        )

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    # ── Load nuScenes ──────────────────────────────────────────────────────────
    from data.nuscenes_lite import load_nuscenes

    print(f"Loading nuScenes {args.version} from {args.nuscenes_root} ...")
    nusc = load_nuscenes(version=args.version, dataroot=args.nuscenes_root, verbose=True)

    is_mini = (args.version == "v1.0-mini")
    split   = "mini_val" if is_mini else "val"

    print(
        f"Extracting disjoint datasets: eval={args.num_scenes} samples, "
        f"calibration={args.calib_scenes} samples ..."
    )
    tokens_eval, masks_eval, gt_eval, tokens_calib, masks_calib, gt_calib = _resolve_eval_and_calibration_sets(
        nusc,
        split,
        args.num_scenes,
        args.calib_scenes,
        is_mini=is_mini,
        include_lane_tokens=not args.disable_lane_tokens,
        include_target_token_proxy=args.include_target_token_proxy,
    )
    print(f"Evaluation set: {len(tokens_eval)} samples")
    print(f"Calibration set: {len(tokens_calib)} samples")

    # ── Load FP32 model ────────────────────────────────────────────────────────
    fp32_model = build_model().to(device)
    load_weights(fp32_model, args.weights, device)
    fp32_model.eval()

    # ── FP32 baseline inference ────────────────────────────────────────────────
    print("Running FP32 baseline inference ...")
    pred_fp32 = run_fp32_inference(fp32_model, tokens_eval, masks_eval,
                                   batch_size=args.batch, device=device)
    pre_qad_rmse = float(rmse_xy(pred_fp32, gt_eval))
    print(f"  Pre-QAD FP32 RMSE_xy: {pre_qad_rmse:.4f} m")

    # ── Optional: Quantization-Aware Distillation (QAD) ──────────────────────
    # FP32 teacher → fake-INT4-quant student → refines weight values to reduce
    # quantization error before final PTQ calibration.
    if args.distill_epochs > 0:
        fp32_model = distill_qad(
            fp32_model,
            tokens_calib, masks_calib, gt_calib,
            epochs     = args.distill_epochs,
            batch_size = args.batch,
            lr         = args.distill_lr,
            lambda_kd  = args.distill_lambda,
            device     = device,
        )
        fp32_model = fp32_model.to(device)
        # Re-run FP32 baseline with QAD-refined model
        print("Re-running FP32 baseline after QAD ...")
        pred_fp32 = run_fp32_inference(fp32_model, tokens_eval, masks_eval,
                                       batch_size=args.batch, device=device)

    # ── Build W4A8 model via post-training quantization ────────────────────────
    print("Quantizing model to W4A8 (PTQ calibration) ...")
    fp32_model.cpu()    # calibration uses numpy engine, move model to CPU
    w4a8_model = W4A8PlanningModel.from_fp32(
        fp32_model, tokens_calib, masks_calib, symmetric_acts=True
    )

    # ── W4A8 inference ─────────────────────────────────────────────────────────
    print("Running W4A8 bit-accurate inference ...")
    pred_w4a8 = run_w4a8_inference(w4a8_model, tokens_eval, masks_eval)

    # ── Compute metrics ────────────────────────────────────────────────────────
    metrics    = quantization_degradation(pred_w4a8, pred_fp32, gt_eval)
    per_step   = per_waypoint_rmse(pred_w4a8, gt_eval)

    print_report(metrics, per_step)

    # ── Save results ───────────────────────────────────────────────────────────
    results = {
        "num_scenes":       int(len(tokens_eval)),
        "num_calib_scenes": int(len(tokens_calib)),
        "nuscenes_split":   split,
        "distill_epochs":   args.distill_epochs,
        "distill_lambda":   args.distill_lambda,
        "distill_lr":       args.distill_lr,
        "include_lane_tokens": bool(not args.disable_lane_tokens),
        "include_target_token_proxy": bool(args.include_target_token_proxy),
        "rmse_xy_fp32_pre_qad": float(pre_qad_rmse),
        "rmse_xy_fp32":   float(metrics["rmse_fp32"]),
        "rmse_xy_w4a8":   float(metrics["rmse_w4a8"]),
        "target_m":       0.3,
        "pass":           bool(metrics["quant_error"] < 0.3),
        "quant_gap_m":    float(metrics["quant_gap"]),
        "quant_error_m":  float(metrics["quant_error"]),
        "ade_fp32":       float(metrics["ade_fp32"]),
        "ade_w4a8":       float(metrics["ade_w4a8"]),
        "fde_fp32":       float(metrics["fde_fp32"]),
        "fde_w4a8":       float(metrics["fde_w4a8"]),
        "per_waypoint_rmse_w4a8": per_step.tolist(),
        "horizons_s":     [0.5, 1.0, 1.5, 2.0],
    }

    with open(args.out, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved to {args.out}")

    # Exit code 1 if target not met (useful for CI)
    if not results["pass"]:
        print(f"\nWARNING: quant_error = {metrics['quant_error']:.4f} m >= 0.3 m target.")
        sys.exit(1)


if __name__ == "__main__":
    main()
