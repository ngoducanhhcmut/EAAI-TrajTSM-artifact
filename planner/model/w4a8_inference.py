"""
W4A8 bit-accurate inference engine -- numpy implementation matching RTL.

Quantization scheme:
  BERT weights  : INT4 symmetric per-row (URAM)
  BERT acts     : INT8 asymmetric per-tensor, calibrated on training data
  BERT MAC path : INT4 x INT8 -> INT32 accumulator -> directly dequant to FP32
                  (residual adds stay in FP32 throughout)
  GRU weights   : INT4 symmetric per-row (URAM blocks 48-71)
  GRU acts      : FP32 throughout (dequant INT4 weights before FP32 FMAC)
  GRU gates     : fp32_sigmoid_lut / fp32_tanh_lut (256-entry, 3-cy fixed)
  Output        : FP32 waypoints (x, y)

RTL references:
  - bert_encoder_layer.sv, shared_int8_macs.sv, int32_to_int8_requant.sv
  - gru_waypoint_decoder.sv SS7
  - fp32_sigmoid_lut.sv / fp32_tanh_lut.sv SS7.6
"""

import numpy as np
import torch
from typing import Dict, List, Optional, Tuple

from .fp32_model import PlanningModel, NUM_LAYERS, HIDDEN_DIM, NUM_WAYPOINTS
from .w4a8_quant import (
    quantize_weights_int4, dequantize_int4,
    quantize_int8, calibrate_int8,
    sigmoid_lut, tanh_lut,
    int4x8_matmul_int32,
)


# ── Helper: dequantize INT32 accumulation to FP32 ─────────────────────────────

def _dq_acc(acc_int32: np.ndarray,
            w_scale: np.ndarray,
            act_scale: float) -> np.ndarray:
    """
    Dequantize INT32 MAC accumulation to FP32.
    acc[n, r] = sum_c( W_int4[r, c] * x_int8[n, c] )
    FP32[n, r] = acc[n, r] * w_scale[r] * act_scale
    """
    return acc_int32.astype(np.float32) * (w_scale * act_scale)[np.newaxis, :]


# ── W4A8BERTLayer ─────────────────────────────────────────────────────────────

class W4A8BERTLayer:
    """
    One Pre-LN BERT encoder layer with W4A8 quantization.

    INT32 accumulations are dequantized directly to FP32 before residual adds,
    so the FP32 residual path stays in correct numerical range throughout.

    Calibration scales:
      act_scale_in   : input to QKV projections (ln1 output)
      act_zp_in      : zero-point for act_scale_in
      act_scale_ctx  : input to WO projection (attention output ctx)
      act_zp_ctx     : zero-point for act_scale_ctx
      act_scale_gelu : input to W2 projection (GELU output)
      act_zp_gelu    : zero-point for act_scale_gelu
    """

    def __init__(self):
        # Weight INT4 quantization
        self.wq_int4: Optional[np.ndarray] = None; self.wq_scale = None
        self.wk_int4: Optional[np.ndarray] = None; self.wk_scale = None
        self.wv_int4: Optional[np.ndarray] = None; self.wv_scale = None
        self.wo_int4: Optional[np.ndarray] = None; self.wo_scale = None
        self.w1_int4: Optional[np.ndarray] = None; self.w1_scale = None
        self.w2_int4: Optional[np.ndarray] = None; self.w2_scale = None

        # Biases (FP32)
        self.bq = self.bk = self.bv = self.bo = self.b1 = self.b2 = None

        # LayerNorm params (FP32)
        self.ln1_w = self.ln1_b = None
        self.ln2_w = self.ln2_b = None

        # Activation scales (calibrated)
        self.act_scale_in:   float = 1.0;  self.act_zp_in:   int = 0
        self.act_scale_ctx:  float = 1.0;  self.act_zp_ctx:  int = 0
        self.act_scale_gelu: float = 1.0;  self.act_zp_gelu: int = 0

        # Attention parameters
        self.num_heads = 8
        self.head_dim  = 64
        self.attn_shift = 3   # >>3 = /8 = /sqrt(64)

    def _layer_norm(self, x, w, b, eps=1e-5):
        mean = x.mean(axis=-1, keepdims=True)
        std  = np.sqrt(x.var(axis=-1, keepdims=True) + eps)
        return w * (x - mean) / std + b

    def _gelu(self, x):
        return 0.5 * x * (1.0 + np.tanh(np.sqrt(2.0 / np.pi) * (x + 0.044715 * x**3)))

    def forward(self, x_fp32: np.ndarray,
                padding_mask: Optional[np.ndarray] = None) -> np.ndarray:
        """
        x_fp32       : (N, 512) float32 -- input to this BERT layer (FP32 residual)
        padding_mask : (N,) bool -- True = padding token (masked out in attention)
        returns      : (N, 512) float32 -- layer output (FP32 residual)

        Quantization path (correct dequant at each stage):
          LN1(x_fp32) -> INT8 -> W_QKV INT4xINT8 -> INT32 -> FP32 -> attention
          ctx_fp32 -> INT8 -> W_O INT4xINT8 -> INT32 -> FP32 -> residual
          LN2(x_fp32) -> INT8 -> W1 INT4xINT8 -> INT32 -> FP32 -> GELU
          gelu_fp32 -> INT8 -> W2 INT4xINT8 -> INT32 -> FP32 -> residual
        """
        N, D = x_fp32.shape

        # ── Pre-LN 1 ────────────────────────────────────────────────────────
        h_ln1 = self._layer_norm(x_fp32, self.ln1_w, self.ln1_b)

        # ── Quantize LN1 output to INT8 (input to QKV + W1 projections) ─────
        x_int8 = quantize_int8(h_ln1, self.act_scale_in, self.act_zp_in)

        # ── Q projection: INT4xINT8 -> INT32 -> FP32 ────────────────────────
        q_int32 = int4x8_matmul_int32(self.wq_int4, x_int8)        # (N, 512)
        q_fp32  = _dq_acc(q_int32, self.wq_scale, self.act_scale_in)
        if self.bq is not None:
            q_fp32 += self.bq

        # ── K projection: INT4xINT8 -> INT32 -> FP32 ────────────────────────
        k_int32 = int4x8_matmul_int32(self.wk_int4, x_int8)
        k_fp32  = _dq_acc(k_int32, self.wk_scale, self.act_scale_in)
        if self.bk is not None:
            k_fp32 += self.bk

        # ── V projection: INT4xINT8 -> INT32 -> FP32 ────────────────────────
        v_int32 = int4x8_matmul_int32(self.wv_int4, x_int8)
        v_fp32  = _dq_acc(v_int32, self.wv_scale, self.act_scale_in)
        if self.bv is not None:
            v_fp32 += self.bv

        # ── Multi-head attention (FP32 throughout) ───────────────────────────
        H, d = self.num_heads, self.head_dim
        Q = q_fp32.reshape(N, H, d).transpose(1, 0, 2)   # (H, N, d)
        K = k_fp32.reshape(N, H, d).transpose(1, 0, 2)
        V = v_fp32.reshape(N, H, d).transpose(1, 0, 2)

        # QK^T with RTL scale shift (>>3 = /8 = /sqrt(64))
        scores = np.matmul(Q, K.transpose(0, 2, 1)) * (2.0 ** -self.attn_shift)

        # Apply padding mask: set scores to -inf for key=padding positions
        # scores shape: (H, N_query, N_key); mask shape: (N,) bool
        if padding_mask is not None:
            scores[:, :, padding_mask] = -1e9

        # Softmax (numerically stable)
        scores = scores - scores.max(axis=-1, keepdims=True)
        weights = np.exp(scores)
        weights = weights / (weights.sum(axis=-1, keepdims=True) + 1e-8)

        # Attention x V -> context (H, N, d) -> (N, D)
        ctx_fp32 = np.matmul(weights, V).transpose(1, 0, 2).reshape(N, D)

        # ── WO projection: quantize ctx, INT4xINT8 -> INT32 -> FP32 ─────────
        ctx_int8 = quantize_int8(ctx_fp32, self.act_scale_ctx, self.act_zp_ctx)
        wo_int32 = int4x8_matmul_int32(self.wo_int4, ctx_int8)      # (N, 512)
        wo_fp32  = _dq_acc(wo_int32, self.wo_scale, self.act_scale_ctx)
        if self.bo is not None:
            wo_fp32 += self.bo

        # ── Residual add #1 (both sides in correct FP32 scale) ───────────────
        x_fp32 = x_fp32 + wo_fp32

        # ── Pre-LN 2 ────────────────────────────────────────────────────────
        h_ln2 = self._layer_norm(x_fp32, self.ln2_w, self.ln2_b)

        # ── W1 FFN: INT4xINT8 -> INT32 -> FP32 -> GELU ──────────────────────
        h2_int8  = quantize_int8(h_ln2, self.act_scale_in, self.act_zp_in)
        w1_int32 = int4x8_matmul_int32(self.w1_int4, h2_int8)       # (N, 2048)
        w1_fp32  = _dq_acc(w1_int32, self.w1_scale, self.act_scale_in)
        if self.b1 is not None:
            w1_fp32 += self.b1

        # GELU on actual FP32 values (correct activation range)
        w1_gelu = self._gelu(w1_fp32)

        # ── W2 FFN: quantize GELU output, INT4xINT8 -> INT32 -> FP32 ────────
        w1g_int8 = quantize_int8(w1_gelu, self.act_scale_gelu, self.act_zp_gelu)
        w2_int32 = int4x8_matmul_int32(self.w2_int4, w1g_int8)      # (N, 512)
        w2_fp32  = _dq_acc(w2_int32, self.w2_scale, self.act_scale_gelu)
        if self.b2 is not None:
            w2_fp32 += self.b2

        # ── Residual add #2 (both sides in correct FP32 scale) ───────────────
        x_fp32 = x_fp32 + w2_fp32

        return x_fp32


# ── W4A8GRUDecoder ────────────────────────────────────────────────────────────

class W4A8GRUDecoder:
    """
    GRU decoder with INT4 weights (dequantized to FP32 before FMAC) and
    256-entry LUTRAM sigmoid/tanh (matching gru_waypoint_decoder.sv SS7).
    """

    def __init__(self):
        self.w_iz_int4 = None; self.w_iz_scale = None
        self.w_hz_int4 = None; self.w_hz_scale = None
        self.w_ir_int4 = None; self.w_ir_scale = None
        self.w_hr_int4 = None; self.w_hr_scale = None
        self.w_in_int4 = None; self.w_in_scale = None
        self.w_hn_int4 = None; self.w_hn_scale = None
        self.w_out = None     # (512, 2) FP32
        self.b_out = None
        self.b_iz = self.b_hz = self.b_ir = self.b_hr = self.b_in = self.b_hn = None
        self.wp_proj_w = None  # (512, 2) FP32 — prev-wp injection weights
        self.wp_proj_b = None  # (512,)   FP32
        self.num_waypoints = NUM_WAYPOINTS

    def _dq(self, W_int4, scale):
        return dequantize_int4(W_int4, scale)

    def _mm(self, W, x):
        return x @ W.T   # (batch, C_out)

    def forward(self, cls_fp32: np.ndarray) -> np.ndarray:
        """
        cls_fp32 : (B, 512) float32 -- CLS embedding from BERT encoder
        returns  : (B, NUM_WAYPOINTS, 2) float32

        GRU equations (RTL SS7.1, PyTorch [r,z,n] order):
          z_t = sigmoid_lut(W_iz x + b_iz + W_hz h + b_hz)
          r_t = sigmoid_lut(W_ir x + b_ir + W_hr h + b_hr)
          n_t = tanh_lut(W_in x + b_in + r_t * (W_hn h + b_hn))
          h_t = (1-z_t)*n_t + z_t*h
          wp  = W_out h_t + b_out
        """
        B = cls_fp32.shape[0]

        Wiz = self._dq(self.w_iz_int4, self.w_iz_scale)
        Whz = self._dq(self.w_hz_int4, self.w_hz_scale)
        Wir = self._dq(self.w_ir_int4, self.w_ir_scale)
        Whr = self._dq(self.w_hr_int4, self.w_hr_scale)
        Win = self._dq(self.w_in_int4, self.w_in_scale)
        Whn = self._dq(self.w_hn_int4, self.w_hn_scale)

        h       = np.zeros((B, HIDDEN_DIM), dtype=np.float32)
        prev_wp = np.zeros((B, 2),          dtype=np.float32)
        waypoints = []

        for _ in range(self.num_waypoints):
            biz = self.b_iz if self.b_iz is not None else 0
            bhz = self.b_hz if self.b_hz is not None else 0
            bir = self.b_ir if self.b_ir is not None else 0
            bhr = self.b_hr if self.b_hr is not None else 0
            bin_ = self.b_in if self.b_in is not None else 0
            bhn = self.b_hn if self.b_hn is not None else 0

            # Autoregressive injection: x_t = cls + W_wp @ prev_wp + b_wp
            wp_inj = prev_wp @ self.wp_proj_w.T
            if self.wp_proj_b is not None:
                wp_inj = wp_inj + self.wp_proj_b
            x = cls_fp32 + wp_inj

            z = sigmoid_lut(self._mm(Wiz, x) + biz + self._mm(Whz, h) + bhz)
            r = sigmoid_lut(self._mm(Wir, x) + bir + self._mm(Whr, h) + bhr)
            n = tanh_lut(self._mm(Win, x) + bin_ + r * (self._mm(Whn, h) + bhn))
            h = (1.0 - z) * n + z * h
            wp = h @ self.w_out + (self.b_out if self.b_out is not None else 0)
            waypoints.append(wp)
            prev_wp = wp

        return np.stack(waypoints, axis=1)   # (B, 4, 2)


# ── W4A8PlanningModel ─────────────────────────────────────────────────────────

class W4A8PlanningModel:
    """
    Full W4A8 planning model -- bit-accurate numpy inference.

    Usage:
      1. Calibrate from a trained FP32 model and calibration data:
           w4a8 = W4A8PlanningModel.from_fp32(fp32_model, calib_tokens, calib_masks)
      2. Run inference:
           waypoints = w4a8.forward(tokens_np, mask_np)
    """

    def __init__(self):
        self.projector_w = None   # Linear weight (512, 6)
        self.projector_b = None   # bias (512,)
        self.pos_emb     = None   # (64, 512)
        self.proj_ln_w   = None
        self.proj_ln_b   = None
        self.final_ln_w  = None
        self.final_ln_b  = None
        self.bert_layers: List[W4A8BERTLayer] = []
        self.gru:          Optional[W4A8GRUDecoder] = None

    @classmethod
    def from_fp32(
        cls,
        fp32_model: PlanningModel,
        calib_tokens: np.ndarray,   # (C, 64, 6)
        calib_masks:  np.ndarray,   # (C, 64) bool
        symmetric_acts: bool = False,
    ) -> "W4A8PlanningModel":
        """
        Build W4A8 model via PTQ from a trained FP32 model.

        Activation calibration hooks collect:
          bert_layer_i_in   : ln1(x) output  -> INT8 scale for Q, K, V, W1 inputs
          bert_layer_i_ctx  : attn(h,h,h) output -> INT8 scale for WO input
          bert_layer_i_gelu : GELU output -> INT8 scale for W2 input
        """
        model = cls()
        fp32_model.eval()

        # ── 1. Extract FP32 weights ──────────────────────────────────────────
        sd = {k: v.detach().numpy().copy() for k, v in fp32_model.state_dict().items()}

        model.projector_w = sd["projector.proj.weight"]
        model.projector_b = sd["projector.proj.bias"]
        model.pos_emb     = sd["projector.pos_emb.weight"]
        model.proj_ln_w   = sd["projector.norm.weight"]
        model.proj_ln_b   = sd["projector.norm.bias"]
        model.final_ln_w  = sd["encoder.final_ln.weight"]
        model.final_ln_b  = sd["encoder.final_ln.bias"]

        # ── 2. Calibration: collect activation statistics ────────────────────
        act_stats: Dict[str, List[np.ndarray]] = {}
        for i in range(NUM_LAYERS):
            act_stats[f"l{i}_in"]   = []   # ln1 output (input to Q,K,V,W1)
            act_stats[f"l{i}_ctx"]  = []   # attn output (input to WO)
            act_stats[f"l{i}_gelu"] = []   # GELU output (input to W2)

        hooks = []

        def make_ln1_out_hook(idx):
            def hook(module, inp, out):
                act_stats[f"l{idx}_in"].append(out.detach().numpy().reshape(-1).copy())
            return hook

        def make_attn_out_hook(idx):
            def hook(module, inp, out):
                # attn returns (output, weights) -- capture output
                attn_out = out[0] if isinstance(out, tuple) else out
                act_stats[f"l{idx}_ctx"].append(attn_out.detach().numpy().reshape(-1).copy())
            return hook

        def make_gelu_out_hook(idx):
            def hook(module, inp, out):
                act_stats[f"l{idx}_gelu"].append(out.detach().numpy().reshape(-1).copy())
            return hook

        for i, layer in enumerate(fp32_model.encoder.layers):
            hooks.append(layer.ln1.register_forward_hook(make_ln1_out_hook(i)))
            hooks.append(layer.attn.register_forward_hook(make_attn_out_hook(i)))
            hooks.append(layer.ffn[1].register_forward_hook(make_gelu_out_hook(i)))

        calib_batch = 8   # small batches to avoid peak OOM on GELU hook (200*64*2048 floats)
        with torch.no_grad():
            for start in range(0, len(calib_tokens), calib_batch):
                _ = fp32_model(
                    torch.from_numpy(calib_tokens[start:start + calib_batch]),
                    torch.from_numpy(calib_masks[start:start + calib_batch]),
                )

        for h in hooks:
            h.remove()

        # ── 3. Build per-layer W4A8 BERT layers ─────────────────────────────
        for i in range(NUM_LAYERS):
            layer  = W4A8BERTLayer()
            prefix = f"encoder.layers.{i}"

            # Split fused in_proj_weight back to Q, K, V
            ipw = sd[f"{prefix}.attn.in_proj_weight"]
            wq_fp = ipw[:512, :]
            wk_fp = ipw[512:1024, :]
            wv_fp = ipw[1024:, :]
            wo_fp = sd[f"{prefix}.attn.out_proj.weight"]
            w1_fp = sd[f"{prefix}.ffn.0.weight"]
            w2_fp = sd[f"{prefix}.ffn.2.weight"]

            # Biases
            ipb = sd.get(f"{prefix}.attn.in_proj_bias")
            layer.bq = ipb[:512]    if ipb is not None else None
            layer.bk = ipb[512:1024] if ipb is not None else None
            layer.bv = ipb[1024:]   if ipb is not None else None
            layer.bo = sd.get(f"{prefix}.attn.out_proj.bias")
            layer.b1 = sd.get(f"{prefix}.ffn.0.bias")
            layer.b2 = sd.get(f"{prefix}.ffn.2.bias")

            # LayerNorm params
            layer.ln1_w = sd[f"{prefix}.ln1.weight"]
            layer.ln1_b = sd[f"{prefix}.ln1.bias"]
            layer.ln2_w = sd[f"{prefix}.ln2.weight"]
            layer.ln2_b = sd[f"{prefix}.ln2.bias"]

            # INT4 weight quantization
            layer.wq_int4, layer.wq_scale = quantize_weights_int4(wq_fp)
            layer.wk_int4, layer.wk_scale = quantize_weights_int4(wk_fp)
            layer.wv_int4, layer.wv_scale = quantize_weights_int4(wv_fp)
            layer.wo_int4, layer.wo_scale = quantize_weights_int4(wo_fp)
            layer.w1_int4, layer.w1_scale = quantize_weights_int4(w1_fp)
            layer.w2_int4, layer.w2_scale = quantize_weights_int4(w2_fp)

            # Activation scale calibration
            in_data   = np.concatenate(act_stats[f"l{i}_in"])
            ctx_data  = np.concatenate(act_stats[f"l{i}_ctx"])
            gelu_data = np.concatenate(act_stats[f"l{i}_gelu"])

            layer.act_scale_in,   layer.act_zp_in   = calibrate_int8(in_data,   symmetric_acts)
            layer.act_scale_ctx,  layer.act_zp_ctx  = calibrate_int8(ctx_data,  symmetric_acts)
            layer.act_scale_gelu, layer.act_zp_gelu = calibrate_int8(gelu_data, symmetric_acts)

            model.bert_layers.append(layer)

        # ── 4. GRU decoder (INT4 weights, FP32 FMAC + LUT sigmoid/tanh) ──────
        gru = W4A8GRUDecoder()

        ih = sd["decoder.gru.weight_ih"]     # (1536, 512) [r, z, n] order
        hh = sd["decoder.gru.weight_hh"]
        bi = sd.get("decoder.gru.bias_ih")
        bh = sd.get("decoder.gru.bias_hh")

        H = HIDDEN_DIM
        gru.w_ir_int4, gru.w_ir_scale = quantize_weights_int4(ih[0:H])
        gru.w_iz_int4, gru.w_iz_scale = quantize_weights_int4(ih[H:2*H])
        gru.w_in_int4, gru.w_in_scale = quantize_weights_int4(ih[2*H:3*H])
        gru.w_hr_int4, gru.w_hr_scale = quantize_weights_int4(hh[0:H])
        gru.w_hz_int4, gru.w_hz_scale = quantize_weights_int4(hh[H:2*H])
        gru.w_hn_int4, gru.w_hn_scale = quantize_weights_int4(hh[2*H:3*H])

        if bi is not None:
            gru.b_ir = bi[0:H]; gru.b_iz = bi[H:2*H]; gru.b_in = bi[2*H:3*H]
        if bh is not None:
            gru.b_hr = bh[0:H]; gru.b_hz = bh[H:2*H]; gru.b_hn = bh[2*H:3*H]

        gru.w_out = sd["decoder.w_out.weight"].T   # (512, 2)
        gru.b_out = sd.get("decoder.w_out.bias")

        gru.wp_proj_w = sd["decoder.wp_proj.weight"]   # (512, 2)
        gru.wp_proj_b = sd.get("decoder.wp_proj.bias")  # (512,)

        model.gru = gru
        return model

    # ── Forward inference ────────────────────────────────────────────────────

    def _layer_norm(self, x, w, b, eps=1e-5):
        mean = x.mean(axis=-1, keepdims=True)
        std  = np.sqrt(x.var(axis=-1, keepdims=True) + eps)
        return w * (x - mean) / std + b

    def _feature_projector(self, tokens: np.ndarray) -> np.ndarray:
        """tokens: (N, 6) -> (N, 512) FP32"""
        N = tokens.shape[0]
        x = tokens @ self.projector_w.T + self.projector_b
        x = x + self.pos_emb[np.arange(N)]
        return self._layer_norm(x, self.proj_ln_w, self.proj_ln_b)

    def forward(self, tokens: np.ndarray,
                padding_mask: Optional[np.ndarray] = None) -> np.ndarray:
        """
        tokens       : (B, N, 6)  float32
        padding_mask : (B, N)     bool  (True = padding, ignored here as in calibration)
        returns      : (B, 4, 2)  float32
        """
        B, N, _ = tokens.shape
        results = []

        for b in range(B):
            x = self._feature_projector(tokens[b])    # (N, 512)
            pmask = padding_mask[b] if padding_mask is not None else None

            for layer in self.bert_layers:
                x = layer.forward(x, pmask)            # (N, 512)

            x = self._layer_norm(x, self.final_ln_w, self.final_ln_b)
            cls = x[0:1]                               # (1, 512) CLS token
            wp = self.gru.forward(cls)                 # (1, 4, 2)
            results.append(wp[0])

        return np.stack(results, axis=0)               # (B, 4, 2)
