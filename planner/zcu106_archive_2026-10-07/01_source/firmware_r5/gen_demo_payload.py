# -*- coding: utf-8 -*-
"""Sinh du lieu demo board v2d: sw/board/demo_bank.bin (nap vao DDR 0x6000_0000) + demo_golden.h.

  [A] 35 khung scene-0103 (sw/golden_spec/sample_00..34 = VAL idx 822..856):
      world model VLA-Traj (64 KB/khung), world model TSM (100 x 64 B), waypoint mong doi
      (GRU tuong duong RTL, tb/e2e/vec/sXX_wp.hex) va quyet dinh TSM mong doi (RTL v2.1, 10.838 luot).
  [B] kich ban TSM chon tu ket qua RTL tren VAL: va cham that ma TSM bat, quy dao an toan,
      quy dao nguoi lai. Mong doi = quyet dinh RTL (mo phong) — board phai tai hien dung.
Kiem tra them: ban Python cua build_traj() trong firmware (PINV) cho ra 1.404 byte trung
tung bit voi tep hex RTL da dung (sw/eval_trainval/out/tsm_hex/Hxxxx.hex).
  python sw/board/gen_demo_payload.py
"""
import sys, re, json, math, struct, pickle, zlib
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BRD = ROOT / "sw" / "board"
OUT = ROOT / "sw" / "eval_trainval" / "out"
HEX = OUT / "tsm_hex"
VEC = ROOT / "tb" / "e2e" / "vec"
sys.path.insert(0, str(ROOT / "sw" / "eval_trainval")); sys.path.insert(0, str(ROOT / "sw"))
import analyze as A                                   # noqa: E402

T = np.array([0.0, 0.5, 1.0, 1.5, 2.0])
PINV = np.linalg.pinv(np.vander(T, 4))                # 4x5: he so [a3 a2 a1 a0] = PINV @ v


def hexwords(p):
    return [int(l, 16) for l in open(p).read().split()]


def build_traj_like_fw(wp8):
    """Ban sao Python cua build_traj() trong tsm_demo.c (PINV, double, float32 khi dong goi)."""
    wp = [float(np.float32(v)) for v in wp8]
    vx = np.array([0, wp[0], wp[2], wp[4], wp[6]]); vy = np.array([0, wp[1], wp[3], wp[5], wp[7]])
    cx = PINV @ vx; cy = PINV @ vy
    t = 0.1 * np.arange(50)
    x = ((cx[0] * t + cx[1]) * t + cx[2]) * t + cx[3]; y = ((cy[0] * t + cy[1]) * t + cy[2]) * t + cy[3]
    b = bytearray(); hd_prev = 0.0
    for i in range(50):
        if i < 49:
            dx, dy = (x[i + 1] - x[i]) / 0.1, (y[i + 1] - y[i]) / 0.1
        else:
            dx, dy = (x[i] - x[i - 1]) / 0.1, (y[i] - y[i - 1]) / 0.1
        sp = math.sqrt(dx * dx + dy * dy)
        if sp > 35.0:
            dx *= 35.0 / sp; dy *= 35.0 / sp
        hd = math.atan2(dy, dx) if sp >= 0.5 else (hd_prev if i else 0.0)
        hd_prev = hd
        b += struct.pack("<7f", x[i], y[i], 0.0, dx, dy, hd, 0.1 * i)
    return bytes(b) + struct.pack("<I", zlib.crc32(bytes(b)) & 0xFFFFFFFF)


def main():
    R = A.parse_tsm()
    D = np.load(OUT / "dataset.npz", allow_pickle=True); O = pickle.load(open(OUT / "objects.pkl", "rb"))
    P = np.load(OUT / "pred_hw_new.npy")
    bank = bytearray(0x500000)
    # ---------------------------------------------------------------- [A]
    A_idx, A_wp, A_exp, nbit = [], [], [], 0
    for n in range(35):
        d = ROOT / "sw" / "golden_spec" / ("sample_%02d" % n)
        tok = re.search(r"token=(\w+)", (d / "report.txt").read_text(errors="ignore")).group(1)
        i = int(np.nonzero(D["token"] == tok)[0][0]); A_idx.append(i)
        wm = (d / "wm_scene_a.bin").read_bytes()[:0x10000]
        bank[n * 0x10000:n * 0x10000 + len(wm)] = wm
        bank[0x300000 + n * 0x2000:0x300000 + n * 0x2000 + 6400] = bytes(
            b"".join(struct.pack("<I", w) for w in hexwords(HEX / ("W%04d.hex" % i))))
        wpb = hexwords(VEC / ("s%02d_wp.hex" % n)); A_wp.append(wpb)
        wpf = struct.unpack("<8f", struct.pack("<8I", *wpb))
        same_wp = np.allclose(np.float32(wpf).reshape(4, 2), P[i].astype(np.float32), atol=0)
        fw = build_traj_like_fw(wpf)
        rtl = b"".join(struct.pack("<I", w) for w in hexwords(HEX / ("H%04d.hex" % i)))
        nbit += fw != rtl
        dec = R["H%04d" % i]["dec"]; A_exp.append(1 if dec == "GRANT" else 0)
        if not same_wp:
            print("  canh bao: s%02d waypoint golden khac pred_hw_new[%d]" % (n, i))
    print("[A] 35 khung idx %d..%d | quy dao firmware != hex RTL: %d | GRANT mong doi %d/35"
          % (A_idx[0], A_idx[-1], nbit, sum(A_exp)))
    # ---------------------------------------------------------------- [B]
    G = D["gt"]
    caught, safe, human = [], [], []
    for i in range(len(P)):
        h = R.get("H%04d" % i); g = R.get("G%04d" % i)
        if not h or not g:
            continue
        cH = A.collides(P[i], O[i])
        if cH and h["dec"] == "VETO" and len(caught) < 6 and i % 3 == 0:
            caught.append(("H%04d" % i, "va cham that, bat  ", 0))
        elif not cH and h["dec"] == "GRANT" and len(safe) < 6 and i % 97 == 5:
            safe.append(("H%04d" % i, "an toan (phan cung) ", 1))
        if not A.collides(G[i], O[i]) and g["dec"] == "GRANT" and len(human) < 3 and i % 211 == 7:
            human.append(("G%04d" % i, "nguoi lai, an toan  ", 1))
    B = caught + safe + human
    for n, (name, kind, exp) in enumerate(B):
        i = int(name[1:])
        tr = b"".join(struct.pack("<I", w) for w in hexwords(HEX / ("%s.hex" % name)))
        wm = b"".join(struct.pack("<I", w) for w in hexwords(HEX / ("W%04d.hex" % i)))
        bank[0x400000 + n * 0x800:0x400000 + n * 0x800 + 1404] = tr
        bank[0x480000 + n * 0x2000:0x480000 + n * 0x2000 + 6400] = wm
    print("[B] %d ca: %d va cham bat duoc, %d an toan, %d nguoi lai" % (len(B), len(caught), len(safe), len(human)))
    (BRD / "demo_bank.bin").write_bytes(bytes(bank))
    # ---------------------------------------------------------------- header
    L = ["/* TU DONG SINH boi sw/board/gen_demo_payload.py — khong sua tay. */",
         "#ifndef DEMO_GOLDEN_H", "#define DEMO_GOLDEN_H", "#include <stdint.h>",
         '#define SCENE_A "scene-0103 (VAL idx %d..%d)"' % (A_idx[0], A_idx[-1]),
         "#define N_A 35", "#define N_B %d" % len(B),
         "static const double PINV[4][5] = {" + ",".join(
             "{" + ",".join("%.17g" % v for v in row) + "}" for row in PINV) + "};",
         "static const uint32_t A_WP_BITS[N_A][8] = {" + ",".join(
             "{" + ",".join("0x%08xu" % v for v in w) + "}" for w in A_wp) + "};",
         "static const int A_EXP_GRANT[N_A] = {" + ",".join(str(v) for v in A_exp) + "};",
         "static const char *B_NAME[N_B] = {" + ",".join('"%s   "' % b[0] for b in B) + "};",
         "static const char *B_KIND[N_B] = {" + ",".join('"%s"' % b[1] for b in B) + "};",
         "static const int B_EXP_GRANT[N_B] = {" + ",".join(str(b[2]) for b in B) + "};",
         "#endif"]
    (BRD / "demo_golden.h").write_text("\n".join(L) + "\n")
    (BRD / "demo_cases.json").write_text(json.dumps(dict(A=A_idx, A_exp=A_exp, B=B), indent=1))
    print("ghi", BRD / "demo_bank.bin", "(%d byte)" % len(bank), "+ demo_golden.h")


if __name__ == "__main__":
    main()
