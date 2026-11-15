"""
FP32 reference model — matches the RTL architecture exactly.

Architecture (from planning_pkg.sv + VLA_HMAO_SPEC_v15_5):
  - FeatureProjector : (B, N, 6) → (B, N, 512)  [INT8 weights on FPGA, FP32 here]
  - BERTEncoder      : (B, N, 512) → (B, N, 512) [Pre-LN, 4 layers, 8 heads, GELU]
  - GRUDecoder       : CLS[B, 512] → (B, 4, 2)   [4 steps, W_out per step]

Token format (bbox6_t):  (x_min, y_min, x_max, y_max, vx, vy)  — all in ego frame (m, m/s)
Token 0 is always CLS; model returns CLS embedding as GRU seed.

MAX_SEQ_LEN = 64, NUM_WAYPOINTS = 4, HIDDEN_DIM = 512, NUM_HEADS = 8, FFN_DIM = 2048.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from typing import Optional

# ── Architecture constants (mirror planning_pkg.sv) ──────────────────────────
NUM_LAYERS    = 4
HIDDEN_DIM    = 512
NUM_HEADS     = 8
HEAD_DIM      = 64        # HIDDEN_DIM // NUM_HEADS
FFN_DIM       = 2048
MAX_SEQ_LEN   = 64
NUM_WAYPOINTS = 4
INPUT_DIM     = 6         # bbox6_t: (x_min, y_min, x_max, y_max, vx, vy)


class FeatureProjector(nn.Module):
    """
    Projects 6-dim bbox6_t tokens into 512-dim hidden space, then adds
    learnable positional embeddings (matches FPGA pos_emb BRAM, 64×512 FP32).

    RTL steps (feature_projector.sv §4.2b):
      1. Quantize bbox6_t FP32 → INT8 (RTL only; skipped in FP32 reference)
      2. W_proj INT8 MAC → INT32
      3. Dequant INT32 → FP32
      4. Add FP32 pos_emb
      5. Requant FP32 → INT8  (RTL only; skipped in FP32 reference)
    Here we implement the combined FP32 equivalent: Linear(6,512) + pos_emb.
    """

    def __init__(self, max_seq_len: int = MAX_SEQ_LEN,
                 hidden_dim: int = HIDDEN_DIM, input_dim: int = INPUT_DIM):
        super().__init__()
        self.proj = nn.Linear(input_dim, hidden_dim)
        self.norm = nn.LayerNorm(hidden_dim)
        self.pos_emb = nn.Embedding(max_seq_len, hidden_dim)

    def forward(self, tokens: torch.Tensor) -> torch.Tensor:
        """
        tokens : (B, N, 6)  — N ≤ MAX_SEQ_LEN
        returns: (B, N, 512)
        """
        B, N, _ = tokens.shape
        pos = torch.arange(N, device=tokens.device).unsqueeze(0)  # (1, N)
        x = self.proj(tokens) + self.pos_emb(pos)                 # (B, N, 512)
        return self.norm(x)


class BERTEncoderLayer(nn.Module):
    """
    Single Pre-LN encoder layer (planning_pkg.sv §2.1 / bert_encoder_layer.sv).

    Pre-LN structure:
      x → LN1 → MHSA → + x  →  LN2 → FFN(GELU) → + x
    """

    def __init__(self, hidden_dim: int = HIDDEN_DIM,
                 num_heads: int = NUM_HEADS, ffn_dim: int = FFN_DIM,
                 dropout: float = 0.0):
        super().__init__()
        self.ln1  = nn.LayerNorm(hidden_dim)
        self.attn = nn.MultiheadAttention(hidden_dim, num_heads,
                                          dropout=dropout, batch_first=True)
        self.ln2  = nn.LayerNorm(hidden_dim)
        self.ffn  = nn.Sequential(
            nn.Linear(hidden_dim, ffn_dim),
            nn.GELU(),
            nn.Linear(ffn_dim, hidden_dim),
        )

    def forward(self, x: torch.Tensor,
                key_padding_mask: Optional[torch.Tensor] = None) -> torch.Tensor:
        """
        x                : (B, N, 512)
        key_padding_mask : (B, N) bool — True = position is PADDING (will be ignored)
        """
        # Pre-LN attention
        h = self.ln1(x)
        h, _ = self.attn(h, h, h, key_padding_mask=key_padding_mask)
        x = x + h
        # Pre-LN FFN
        h = self.ln2(x)
        h = self.ffn(h)
        x = x + h
        return x


class BERTEncoder(nn.Module):
    """
    4-layer Pre-LN BERT encoder.  Returns the CLS token embedding (token 0).
    """

    def __init__(self, num_layers: int = NUM_LAYERS,
                 hidden_dim: int = HIDDEN_DIM,
                 num_heads: int = NUM_HEADS, ffn_dim: int = FFN_DIM):
        super().__init__()
        self.layers = nn.ModuleList([
            BERTEncoderLayer(hidden_dim, num_heads, ffn_dim)
            for _ in range(num_layers)
        ])
        self.final_ln = nn.LayerNorm(hidden_dim)

    def forward(self, x: torch.Tensor,
                padding_mask: Optional[torch.Tensor] = None) -> torch.Tensor:
        """
        x            : (B, N, 512)  — output of FeatureProjector
        padding_mask : (B, N) bool  — True = padding token (ignored in attention)
        returns      : (B, 512)     — CLS token (token 0) after all 4 layers
        """
        for layer in self.layers:
            x = layer(x, key_padding_mask=padding_mask)
        x = self.final_ln(x)
        return x[:, 0, :]   # CLS token


class GRUDecoder(nn.Module):
    """
    4-step autoregressive GRU waypoint decoder (gru_waypoint_decoder.sv §7).

    PyTorch-compatible GRU equations (matching RTL §7.1):
      x_t = cls_emb + wp_proj(prev_wp)   [step 0: x_0 = cls_emb, prev_wp = zeros]
      z_t = σ( W_iz·x_t + b_iz + W_hz·h + b_hz )
      r_t = σ( W_ir·x_t + b_ir + W_hr·h + b_hr )
      n_t = tanh( W_in·x_t + b_in_ih + r_t ⊙ (W_hn·h + b_n_hh) )
      h_t = (1 - z_t) ⊙ n_t + z_t ⊙ h_prev
      wp  = W_out · h_t + b_out  →  (x, y) FP32

    The initial hidden state h_0 is all zeros (§7, [v15.3-R11]).
    wp_proj: Linear(2, 512) injects prev waypoint feedback into each GRU step.
    At step 0, prev_wp = zeros so wp_proj contributes only its bias.
    """

    def __init__(self, input_dim: int = HIDDEN_DIM,
                 hidden_dim: int = HIDDEN_DIM,
                 num_waypoints: int = NUM_WAYPOINTS):
        super().__init__()
        self.hidden_dim   = hidden_dim
        self.num_waypoints = num_waypoints
        self.gru     = nn.GRUCell(input_dim, hidden_dim)
        self.w_out   = nn.Linear(hidden_dim, 2)
        self.wp_proj = nn.Linear(2, hidden_dim)  # prev_wp (x,y) → 512-dim additive injection

    def forward(self, cls_emb: torch.Tensor,
                gt_waypoints: Optional[torch.Tensor] = None) -> torch.Tensor:
        """
        cls_emb     : (B, 512)    — CLS token from BERT encoder
        gt_waypoints: (B, 4, 2)   — GT waypoints for teacher forcing (training only)
                      If provided, use GT as prev_wp instead of model predictions.
                      At inference (gt_waypoints=None), use predicted waypoints (matches RTL).
        returns     : (B, NUM_WAYPOINTS, 2)  — (x, y) waypoints in ego frame (metres)
        """
        B = cls_emb.size(0)
        h        = torch.zeros(B, self.hidden_dim, device=cls_emb.device, dtype=cls_emb.dtype)
        prev_wp  = torch.zeros(B, 2,               device=cls_emb.device, dtype=cls_emb.dtype)
        waypoints = []
        for t in range(self.num_waypoints):
            x_t = cls_emb + self.wp_proj(prev_wp)
            h   = self.gru(x_t, h)
            wp  = self.w_out(h)                    # (B, 2)
            waypoints.append(wp)
            # Teacher forcing: use GT prev_wp during training when provided
            if gt_waypoints is not None:
                prev_wp = gt_waypoints[:, t, :]    # GT waypoint at step t → feeds step t+1
            else:
                prev_wp = wp                       # free-running (inference / RTL)
        return torch.stack(waypoints, dim=1)       # (B, 4, 2)


class PlanningModel(nn.Module):
    """
    Full VLA-Traj FP32 reference model.

    Pipeline:
      tokens (B,N,6) ──► FeatureProjector ──► BERTEncoder ──► GRUDecoder
                                                                   │
                                                       waypoints (B,4,2)

    Usage:
      model = PlanningModel()
      waypoints = model(tokens, padding_mask)   # tokens: (B,64,6), mask: (B,64)
    """

    def __init__(self):
        super().__init__()
        self.projector = FeatureProjector()
        self.encoder   = BERTEncoder()
        self.decoder   = GRUDecoder()

    def forward(self, tokens: torch.Tensor,
                padding_mask: Optional[torch.Tensor] = None,
                gt_waypoints: Optional[torch.Tensor] = None) -> torch.Tensor:
        """
        tokens       : (B, N, 6)  float32  — bbox6_t world model tokens, N ≤ 64
        padding_mask : (B, N)     bool     — True = padding (to be ignored)
        gt_waypoints : (B, 4, 2)  float32  — GT for teacher forcing (training only)
        returns      : (B, 4, 2)  float32  — predicted waypoints (x, y) in ego frame
        """
        x   = self.projector(tokens)                  # (B, N, 512)
        cls = self.encoder(x, padding_mask)           # (B, 512)
        return self.decoder(cls, gt_waypoints)        # (B, 4, 2)


def build_model(dropout: float = 0.0) -> PlanningModel:
    """dropout > 0 during training only; always 0 for inference/RTL export."""
    if dropout == 0.0:
        return PlanningModel()
    # Patch dropout into all BERT attention layers (training regularization only)
    model = PlanningModel()
    for layer in model.encoder.layers:
        # Rebuild attn with dropout; weights will be loaded via state_dict later
        layer.attn = nn.MultiheadAttention(
            HIDDEN_DIM, NUM_HEADS, dropout=dropout, batch_first=True
        )
    return model


if __name__ == "__main__":
    # Smoke test
    B, N = 2, 64
    tokens = torch.randn(B, N, 6)
    mask   = torch.zeros(B, N, dtype=torch.bool)
    mask[:, 10:] = True          # only first 10 tokens are valid
    model  = build_model()
    out    = model(tokens, mask)
    print(f"Output shape: {out.shape}")   # expected: (2, 4, 2)
    total  = sum(p.numel() for p in model.parameters())
    print(f"Total parameters: {total:,}")
