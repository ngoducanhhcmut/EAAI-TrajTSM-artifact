# -*- coding: utf-8 -*-
"""Dong goi tham so hwspec thanh anh bo nho phan cung (docs/KIEN_TRUC_BERT_V2.md §4, §5).

  param_image(P)     -> np.uint32[65536]   (PARAM; 57344 tu dau duoc DMA o static boot)
  uram_image(P, L)   -> np.uint64[196608]  (trong so lop L)
Ham doc nguoc (unpack_*) dung de tu kiem: dong goi -> mo -> phai ra dung tham so.
"""
import numpy as np

F32 = np.float32
PARAM_WORDS = 65536
LAYER_STRIDE = 9216
OFF_CS = {"wq": 0, "wk": 512, "wv": 1024, "wo": 1536, "w1": 2048, "w2": 4096}
SZ = {"wq": 512, "wk": 512, "wv": 512, "wo": 512, "w1": 2048, "w2": 512}
OFF_BIAS = 4608
LN_BASE = 36864
GLN_BASE = 45056          # pln_w, pln_b, fln_w, fln_b
PW_BASE = 47104           # proj_w[o*6+k]
PB_BASE = 50176
SCAL_BASE = 50688         # + L*16
SCAL_NAMES = ["inv_s_in", "inv_sq", "inv_sk", "inv_sv", "c_qk", "c_ctx", "inv_s1"]
GELU_BASE = 50752         # + L*64
URAM_LAYER_WORDS = 196608
URAM_BASE = {"wq": 0, "wk": 16384, "wv": 32768, "wo": 49152, "w1": 65536, "w2": 131072}


def f2u(x):
    return np.asarray(x, F32).view(np.uint32)


def param_image(P):
    img = np.zeros(PARAM_WORDS, np.uint32)
    for L, lp in enumerate(P["layers"]):
        b0 = L * LAYER_STRIDE
        for nm, off in OFF_CS.items():
            img[b0 + off: b0 + off + SZ[nm]] = f2u(lp["cs_" + nm])
            img[b0 + OFF_BIAS + off: b0 + OFF_BIAS + off + SZ[nm]] = f2u(lp["b_" + nm])
        lb = LN_BASE + L * 2048
        for i, nm in enumerate(["ln1_w", "ln1_b", "ln2_w", "ln2_b"]):
            img[lb + i * 512: lb + (i + 1) * 512] = f2u(lp[nm])
        for i, nm in enumerate(SCAL_NAMES):
            img[SCAL_BASE + L * 16 + i] = f2u(lp[nm])
        g = lp["gelu_lut"].astype(np.int8).view(np.uint8).astype(np.uint32)
        img[GELU_BASE + L * 64: GELU_BASE + L * 64 + 64] = (g[0::4] | (g[1::4] << 8) | (g[2::4] << 16) | (g[3::4] << 24))
    for i, nm in enumerate(["pln_w", "pln_b", "fln_w", "fln_b"]):
        img[GLN_BASE + i * 512: GLN_BASE + (i + 1) * 512] = f2u(P[nm])
    img[PW_BASE: PW_BASE + 3072] = f2u(P["proj_w"].reshape(-1))          # (512,6) hang o
    img[PB_BASE: PB_BASE + 512] = f2u(P["proj_b"])
    return img


def pack_matrix(W):
    """W (Cout, K) INT4 -> tu 64 bit: tu (g,u) nibble 2j+e = W[8g+j][2u+e]."""
    Co, K = W.shape
    G, U = Co // 8, K // 2
    n = (W.astype(np.int64) & 0xF).reshape(G, 8, U, 2)          # [g, j, u, e]
    n = n.transpose(0, 2, 1, 3).reshape(G, U, 16)               # nibble idx = 2j+e
    words = np.zeros((G, U), np.uint64)
    for i in range(16):
        words |= (n[:, :, i].astype(np.uint64) << np.uint64(4 * i))
    return words.reshape(-1)


def unpack_matrix(words, Co, K):
    G, U = Co // 8, K // 2
    w = words.reshape(G, U)
    n = np.stack([((w >> np.uint64(4 * i)) & np.uint64(0xF)).astype(np.int64) for i in range(16)], -1)
    n = np.where(n >= 8, n - 16, n).reshape(G, U, 8, 2).transpose(0, 2, 1, 3)
    return n.reshape(Co, K).astype(np.int8)


def uram_image(P, L):
    lp = P["layers"][L]
    img = np.zeros(URAM_LAYER_WORDS, np.uint64)
    for nm, base in URAM_BASE.items():
        w = pack_matrix(lp[nm])
        img[base: base + w.size] = w
    return img


def selftest(P):
    img = param_image(P)
    for L, lp in enumerate(P["layers"]):
        for nm in OFF_CS:
            b0 = L * LAYER_STRIDE + OFF_CS[nm]
            assert np.array_equal(img[b0:b0 + SZ[nm]].view(F32), lp["cs_" + nm])
        u = uram_image(P, L)
        for nm, base in URAM_BASE.items():
            Co, K = lp[nm].shape
            assert np.array_equal(unpack_matrix(u[base: base + Co * K // 16], Co, K), lp[nm]), nm
    return True
