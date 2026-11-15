"""
Bit-accurate W4A8 quantization utilities — matches the RTL exactly.

References:
  - planning_pkg.sv  : WEIGHT_BITS=4, ACT_BITS=8, ACCUM_BITS=32
  - int32_to_int8_requant.sv §5.1 : q8 = clamp(round((acc × scale_q8)>>8) + zp, -128, 127)
  - fp32_sigmoid_lut.sv §7.6     : 256-entry LUT, range [-6.0, +6.0]
  - fp32_tanh_lut.sv §7.6        : 256-entry LUT, range [-4.0, +4.0]
  - sigmoid_lut_init.hex comment : Array[I] = sigmoid((I-128)*6/128)
  - tanh_lut_init.hex comment    : Array[I] = tanh((I-128)*4/128)
"""

import numpy as np
from typing import Tuple


# ── LUT tables (generated once, reused across all calls) ─────────────────────

def _build_sigmoid_lut() -> np.ndarray:
    """256-entry FP32 sigmoid LUT matching sigmoid_lut_init.hex.
    Array[I] = sigmoid((I - 128) * 6 / 128)  for I in [0, 255].
    """
    indices = np.arange(256, dtype=np.float32)
    x = (indices - 128.0) * 6.0 / 128.0
    return (1.0 / (1.0 + np.exp(-x))).astype(np.float32)


def _build_tanh_lut() -> np.ndarray:
    """256-entry FP32 tanh LUT matching tanh_lut_init.hex.
    Array[I] = tanh((I - 128) * 4 / 128)  for I in [0, 255].
    """
    indices = np.arange(256, dtype=np.float32)
    x = (indices - 128.0) * 4.0 / 128.0
    return np.tanh(x).astype(np.float32)


_SIGMOID_LUT = _build_sigmoid_lut()   # shape (256,)
_TANH_LUT    = _build_tanh_lut()      # shape (256,)


# ── LUT lookup functions (match RTL fp32_sigmoid_lut / fp32_tanh_lut) ─────────

def sigmoid_lut(x: np.ndarray) -> np.ndarray:
    """
    256-entry LUTRAM sigmoid, input range [-6, +6], clamped outside.
    Index formula: idx = round(x * 128/6 + 128), clamp [0, 255].
    NaN propagates as NaN (RTL: y_final = 0x7FC00000 quiet NaN).
    """
    nan_mask = np.isnan(x)
    x_sat    = np.clip(x, -6.0, 6.0)
    idx      = np.round(x_sat * (128.0 / 6.0) + 128.0).astype(np.int32)
    idx      = np.clip(idx, 0, 255)
    out      = _SIGMOID_LUT[idx]
    out      = np.where(nan_mask, np.nan, out)
    return out.astype(np.float32)


def tanh_lut(x: np.ndarray) -> np.ndarray:
    """
    256-entry LUTRAM tanh, input range [-4, +4], clamped outside.
    Index formula: idx = round(x * 128/4 + 128) = round(x*32 + 128), clamp [0, 255].
    NaN propagates as NaN.
    """
    nan_mask = np.isnan(x)
    x_sat    = np.clip(x, -4.0, 4.0)
    idx      = np.round(x_sat * 32.0 + 128.0).astype(np.int32)
    idx      = np.clip(idx, 0, 255)
    out      = _TANH_LUT[idx]
    out      = np.where(nan_mask, np.nan, out)
    return out.astype(np.float32)


# ── INT4 weight quantization (symmetric per-row, matching URAM packing) ───────

def quantize_weights_int4(
    W: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Symmetric per-row INT4 quantization.
      scale[r] = max(|W[r, :]|) / 7.0   (use 7 to keep headroom for -8)
      W_int4    = clamp(round(W / scale[:, None]), -8, 7)

    Args:
      W : (C_out, C_in) float32

    Returns:
      W_int4     : (C_out, C_in) int8   (values in [-8, 7])
      scale      : (C_out,)      float32  — per-row dequant scale
    """
    W     = W.astype(np.float32)
    scale = np.max(np.abs(W), axis=1, keepdims=True) / 7.0
    scale = np.where(scale == 0.0, 1.0, scale)  # avoid /0 for zero rows
    W_int4 = np.clip(np.round(W / scale), -8, 7).astype(np.int8)
    return W_int4, scale.squeeze(1)


def dequantize_int4(W_int4: np.ndarray, scale: np.ndarray) -> np.ndarray:
    """
    Dequantize INT4 weights back to FP32 for FP32 GRU path.
      W_fp32 = W_int4 * scale[:, None]

    Args:
      W_int4 : (C_out, C_in) int8
      scale  : (C_out,)      float32

    Returns:
      W_fp32 : (C_out, C_in) float32
    """
    return W_int4.astype(np.float32) * scale[:, np.newaxis]


# ── INT8 activation quantization (asymmetric per-tensor) ─────────────────────

def calibrate_int8(
    x: np.ndarray,
    symmetric: bool = False,
) -> Tuple[float, int]:
    """
    Calibrate INT8 quantization parameters from a FP32 tensor.

    Asymmetric: scale = (max - min) / 255, zp = round(-min / scale) clamped [0, 255].
    Symmetric:  scale = max(|x|) / 127, zp = 0.

    Returns: (scale, zp)
    """
    if symmetric:
        scale = float(np.max(np.abs(x))) / 127.0
        scale = max(scale, 1e-8)
        return scale, 0
    else:
        x_min = float(np.min(x))
        x_max = float(np.max(x))
        scale = (x_max - x_min) / 255.0
        scale = max(scale, 1e-8)
        zp    = int(np.round(-x_min / scale))
        zp    = int(np.clip(zp, 0, 255))
        return scale, zp


def quantize_int8(
    x: np.ndarray,
    scale: float,
    zp: int,
) -> np.ndarray:
    """
    Quantize FP32 tensor to INT8 (signed, [-128, 127]).
      q = clamp(round(x / scale) + zp_offset, -128, 127)
    Note: zp here is stored as per the RTL convention (signed w_zp byte).
    """
    q = np.round(x.astype(np.float32) / scale) + zp
    return np.clip(q, -128, 127).astype(np.int8)


def dequantize_int8(q: np.ndarray, scale: float, zp: int) -> np.ndarray:
    return (q.astype(np.float32) - zp) * scale


# ── INT32 → INT8 requantization (matches int32_to_int8_requant.sv §5.1) ───────

def compute_requant_params(
    weight_scale_per_row: np.ndarray,   # (C_out,)
    act_scale: float,
    out_scale: float,
    out_zp: int = 0,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Compute the (scale_q8, zp) parameters needed by the RTL requantizer,
    given calibrated weight/activation/output scales.

    RTL formula (int32_to_int8_requant.sv):
      q8 = clamp(round((acc_int32 × scale_q8) >> 8) + signed(w_zp), -128, 127)
    where scale_q8 is UQ0.8 (actual scale = scale_q8 / 256).

    Combined floating-point requantization scale:
      req_scale = weight_scale_per_row × act_scale / out_scale

    Encoding into RTL format:
      scale_q8[r] = clamp(round(req_scale[r] × 256), 0, 255)

    Args:
      weight_scale_per_row : (C_out,) — per-row INT4 weight scale
      act_scale            : scalar   — INT8 activation scale
      out_scale            : scalar   — output INT8 scale
      out_zp               : scalar   — output zero-point

    Returns:
      scale_q8 : (C_out,) uint8   — UQ0.8 requant scale per output channel
      w_zp     : (C_out,) int8    — zero-point (constant out_zp broadcast)
    """
    req_scale_fp = weight_scale_per_row * act_scale / out_scale
    scale_q8     = np.clip(np.round(req_scale_fp * 256.0), 0, 255).astype(np.uint8)
    w_zp         = np.full(len(weight_scale_per_row), out_zp, dtype=np.int8)
    return scale_q8, w_zp


def requantize_int32_to_int8(
    acc: np.ndarray,          # (..., C_out) int32
    scale_q8: np.ndarray,     # (C_out,)     uint8
    w_zp: np.ndarray,         # (C_out,)     int8
) -> np.ndarray:
    """
    Bit-accurate INT32 → INT8 requantization matching int32_to_int8_requant.sv.

    Stage 1: q_int = (acc × scale_q8) >> 8   [signed 40-bit product → 32-bit]
    Stage 2: q8    = clamp(q_int + signed(w_zp), -128, 127)
    """
    acc       = acc.astype(np.int64)                            # widen to avoid overflow
    scale_q8  = scale_q8.astype(np.int64)
    product   = acc * scale_q8                                  # broadcast over C_out
    q_int     = (product >> 8).astype(np.int32)
    q8        = q_int + w_zp.astype(np.int32)
    return np.clip(q8, -128, 127).astype(np.int8)


# ── Utility: matmul in INT32 accumulator (INT4×INT8 → INT32) ─────────────────

def int4x8_matmul_int32(
    W_int4: np.ndarray,   # (C_out, C_in)  int8  (values in [-8, 7])
    x_int8: np.ndarray,   # (..., C_in)    int8
) -> np.ndarray:
    """
    Emulate the shared_int8_macs INT32 accumulation: acc = W @ x.
    Uses int32 accumulation to match the RTL exactly.
    Returns (..., C_out) int32.
    """
    return np.dot(x_int8.astype(np.int32), W_int4.T.astype(np.int32))


if __name__ == "__main__":
    # Quick self-test
    np.random.seed(42)
    x_vals = np.linspace(-8.0, 8.0, 17, dtype=np.float32)

    print("Sigmoid LUT vs exact:")
    for xv in x_vals:
        lut_val  = sigmoid_lut(np.array([xv]))[0]
        exact    = 1.0 / (1.0 + np.exp(-float(xv)))
        print(f"  sigmoid({xv:6.2f}) LUT={lut_val:.6f}  exact={exact:.6f}  "
              f"err={abs(lut_val-exact)*1000:.2f}e-3")

    print("\nTanh LUT vs exact:")
    for xv in np.linspace(-5.0, 5.0, 11, dtype=np.float32):
        lut_val  = tanh_lut(np.array([xv]))[0]
        exact    = np.tanh(float(xv))
        print(f"  tanh({xv:6.2f})    LUT={lut_val:.6f}  exact={exact:.6f}  "
              f"err={abs(lut_val-exact)*1000:.2f}e-3")

    print("\nINT4 weight quantization:")
    W = np.random.randn(512, 512).astype(np.float32)
    W_int4, scale = quantize_weights_int4(W)
    W_rec = dequantize_int4(W_int4, scale)
    print(f"  max quantization error: {np.max(np.abs(W - W_rec)):.4f}")

    print("\nRequantization test:")
    acc   = np.random.randint(-10000, 10000, (64, 512), dtype=np.int32)
    sq8   = np.random.randint(1, 200, (512,), dtype=np.uint8)
    zp    = np.zeros(512, dtype=np.int8)
    q8    = requantize_int32_to_int8(acc, sq8, zp)
    print(f"  q8 range: [{q8.min()}, {q8.max()}]  (expected [-128, 127])")
