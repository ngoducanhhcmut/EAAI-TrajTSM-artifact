# -*- coding: utf-8 -*-
"""Vector cap lop cho tb_mm_engine / tb_ln_engine / tb_softmax_u8 / tb_bert_v2.

python gen_layer_vectors.py [mau=0] [lop=0 ...]
Ra tb/unit/bert_v2/vec/sXX/ :
  param.hex (65536 x 8 hex), uram_L.hex (196608 x 16 hex),
  tok.hex (64x6 FP32), pad.hex (64 dong 0/1 — 1 = dem), meta.txt
  proj.hex, proj_ln.hex (64x512 FP32), cls.hex (512 FP32)
  L{L}_xin.hex (FP32 64x512 dau vao lop), L{L}_ln1q.hex, _q8, _k8, _v8, _ctx8, _ln2q (64xC INT8),
  L{L}_qk.hex (8x64x64 INT32), L{L}_p8.hex (8x64x64 u8), L{L}_gelu8.hex (64x2048 INT8),
  L{L}_res1.hex, L{L}_res2.hex (FP32 64x512)
Moi dong 1 gia tri, thu tu C (hang ngoai). INT8/u8 ghi 2 hex, INT32/FP32 ghi 8 hex.
"""
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import load_all, samples, ROOT
import hwspec_exact as hx
import pack

si = int(sys.argv[1]) if len(sys.argv) > 1 else 0
m, P = load_all()
S = samples()[si]
OUT = ROOT / "tb" / "unit" / "bert_v2" / "vec" / ("s%02d" % si)
OUT.mkdir(parents=True, exist_ok=True)


def wr(name, a, width):
    a = np.ascontiguousarray(a).reshape(-1)
    if width == 2:
        v = a.astype(np.int64) & 0xFF
    elif a.dtype == np.float32:
        v = a.view(np.uint32).astype(np.int64)
    else:
        v = a.astype(np.int64) & 0xFFFFFFFF
    fmt = "%%0%dx" % width
    (OUT / name).write_text("\n".join(fmt % x for x in v) + "\n")


st = {}
cls = hx.forward(P, S["tok"], S["pad"], st)
img = pack.param_image(P)
(OUT / "param.hex").write_text("\n".join("%08x" % x for x in img) + "\n")
for L in range(4):
    u = pack.uram_image(P, L)
    (OUT / ("uram_%d.hex" % L)).write_text("\n".join("%016x" % int(x) for x in u) + "\n")
wr("tok.hex", S["tok"].astype(np.float32), 8)
(OUT / "pad.hex").write_text("\n".join("%d" % int(x) for x in S["pad"]) + "\n")
(OUT / "meta.txt").write_text("%d\n" % int((~S["pad"]).sum()))
wr("proj.hex", st["proj"], 8)
# pos_emb dang RAM 64 bit cua planning_top: tu (t*256 + i) = {pos[t][2i+1], pos[t][2i]}
pu = P["pos"].view(np.uint32).astype(np.uint64).reshape(64, 256, 2)
pw = (pu[:, :, 1] << np.uint64(32)) | pu[:, :, 0]
(OUT / "posemb.hex").write_text("\n".join("%016x" % int(x) for x in pw.reshape(-1)) + "\n")
wr("proj_ln.hex", st["proj_ln"], 8)
wr("cls.hex", cls, 8)
xin = st["proj_ln"]
for L in range(4):
    wr("L%d_xin.hex" % L, xin, 8)
    for nm in ("ln1q", "q8", "k8", "v8", "ctx8", "ln2q", "gelu8"):
        wr("L%d_%s.hex" % (L, nm), st["L%d_%s" % (L, nm)], 2)
    wr("L%d_p8.hex" % L, st["L%d_p8" % L], 2)
    wr("L%d_qk.hex" % L, st["L%d_qk" % L], 8)
    wr("L%d_res1.hex" % L, st["L%d_res1" % L], 8)
    wr("L%d_res2.hex" % L, st["L%d_res2" % L], 8)
    xin = st["L%d_res2" % L]
print("ghi", OUT, "token hop le:", int((~S["pad"]).sum()))
