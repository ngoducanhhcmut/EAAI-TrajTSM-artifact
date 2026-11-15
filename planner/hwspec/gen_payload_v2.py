# -*- coding: utf-8 -*-
"""Payload BERT V2 cho board + vector DDR cho tb_planning_top_e2e.

python gen_payload_v2.py [so_mau=35]
Ra:
  sw/payloads/v2/  param_a.bin param_b.bin param_c.bin bert_weights.bin (+ GRU, pos_emb chep tu trained)
                   ddr_preload_v2.tsv (ten tep, dia chi DDR) — cho firmware PS / script nap board
  tb/e2e/vec/      ddr_<vung>.hex (128 bit / dong, byte 0 o bit thap) + regions.txt
                   sXX_wm.hex, sXX_cls.hex (CLS hwspec), sXX_wp.hex (waypoint GRU tuong duong RTL),
                   sXX_gt.hex, sXX_meta.txt
"""
import sys, io, shutil, contextlib
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import load_all, samples, ROOT
import hwspec_exact as hx
import pack

NS = int(sys.argv[1]) if len(sys.argv) > 1 else 35
TRN = ROOT / "sw" / "payloads" / "trained"
OUT = ROOT / "sw" / "payloads" / "v2"
TBV = ROOT / "tb" / "e2e" / "vec"
OUT.mkdir(parents=True, exist_ok=True); TBV.mkdir(parents=True, exist_ok=True)

# dia chi DDR (khop rtl/include/planning_pkg.sv)
DDR = dict(BERT_WEIGHT=0x0000_0000, POS_EMB=0x0060_0000, WM_A=0x0064_0000,
           GRU_BIAS=0x017D_2000, GRU_WEIGHT=0x017D_4000, GRU_WOUT=0x0189_4000,
           GRU_SCALE=0x018A_0000, GRU_WP_PROJ=0x018A_8000,
           PARAM_A=0x0190_0000, PARAM_B=0x0191_0000, PARAM_C=0x0193_0000)
LAYER_STRIDE = 0x18_0000

m, P = load_all()
img = pack.param_image(P)
files = {
    "param_a.bin": img[0:16384].astype("<u4").tobytes(),
    "param_b.bin": img[16384:49152].astype("<u4").tobytes(),
    "param_c.bin": img[49152:57344].astype("<u4").tobytes(),
}
bw = bytearray(4 * LAYER_STRIDE)
for L in range(4):
    u = pack.uram_image(P, L).astype("<u8").tobytes()
    assert len(u) == LAYER_STRIDE
    bw[L * LAYER_STRIDE:(L + 1) * LAYER_STRIDE] = u
files["bert_weights.bin"] = bytes(bw)
for nm, data in files.items():
    (OUT / nm).write_bytes(data)
for nm in ("pos_emb.bin", "gru_bias.bin", "gru_weights.bin", "gru_wout_staging.bin", "gru_scale_zp.bin", "gru_wp_proj.bin"):
    shutil.copy(TRN / nm, OUT / nm)
manifest = [("bert_weights.bin", DDR["BERT_WEIGHT"]), ("pos_emb.bin", DDR["POS_EMB"]),
            ("param_a.bin", DDR["PARAM_A"]), ("param_b.bin", DDR["PARAM_B"]), ("param_c.bin", DDR["PARAM_C"]),
            ("gru_bias.bin", DDR["GRU_BIAS"]), ("gru_weights.bin", DDR["GRU_WEIGHT"]),
            ("gru_wout_staging.bin", DDR["GRU_WOUT"]), ("gru_scale_zp.bin", DDR["GRU_SCALE"]),
            ("gru_wp_proj.bin", DDR["GRU_WP_PROJ"])]
(OUT / "ddr_preload_v2.tsv").write_text(
    "# tep\tdia_chi_DDR\tbyte  (wm_scene_*.bin nap rieng vao WM_A 0x00640000 / WM_B 0x00E40000)\n"
    + "".join("%s\t0x%08X\t%d\n" % (n, a, (OUT / n).stat().st_size) for n, a in manifest))


def hex128(data):
    data = data + b"\0" * ((-len(data)) % 16)
    a = np.frombuffer(data, "<u8").reshape(-1, 2)
    return "".join("%016x%016x\n" % (int(h), int(l)) for l, h in a)


regions = []
for n, a in manifest:
    nm = n.replace(".bin", "")
    (TBV / ("ddr_%s.hex" % nm)).write_text(hex128((OUT / n).read_bytes()))
    regions.append("%s %08x %d" % (nm, a, ((OUT / n).stat().st_size + 15) // 16))
(TBV / "regions.txt").write_text("\n".join(regions) + "\n")

# GRU tuong duong RTL (payload thang UQ0.8 + bang tra) — chuan waypoint cua RTL
with contextlib.redirect_stdout(io.StringIO()):
    src = (ROOT / "sw" / "_verify_all_samples_spec.py").read_text(encoding="utf-8")
    g = {"__file__": str(ROOT / "sw" / "_verify_all_samples_spec.py")}
    exec(src[:src.index("Run all 5 samples") - 6], g)
run_rtl = g["run_gru_rtl_equiv"]

S = samples()[:NS]
for i, s in enumerate(S):
    wm = (s["dir"] / "wm_scene_a.bin").read_bytes()
    n_obj, n_lane = np.frombuffer(wm[:8], "<u4")
    used = 0x2590 + 128 * min(int(n_lane), 20)
    (TBV / ("s%02d_wm.hex" % i)).write_text(hex128(wm[:max(used, 16 + 48 * min(int(n_obj), 200))]))
    cls = hx.forward(P, s["tok"], s["pad"])
    wp = run_rtl(cls.astype(np.float32)).astype(np.float32)
    (TBV / ("s%02d_cls.hex" % i)).write_text("".join("%08x\n" % v for v in cls.view(np.uint32)))
    (TBV / ("s%02d_wp.hex" % i)).write_text("".join("%08x\n" % v for v in wp.reshape(-1).view(np.uint32)))
    (TBV / ("s%02d_gt.hex" % i)).write_text("".join("%08x\n" % v for v in s["gt"].reshape(-1).view(np.uint32)))
    (TBV / ("s%02d_meta.txt" % i)).write_text("%d %d %d %d\n" % (int(n_obj), int(n_lane), int((~s["pad"]).sum()), len(wm)))
print("payload:", OUT, "| vector:", TBV, "| mau:", len(S))
