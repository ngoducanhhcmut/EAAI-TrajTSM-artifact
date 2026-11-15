# -*- coding: utf-8 -*-
"""Buoc 2 — chay cac mo hinh Traj tren 5.419 mau VAL (song song nhieu tien trinh).

  fp32    : mo hinh goc PyTorch (autoregressive_gru_200ep.pt)
  w4a8    : mo hinh luong tu W4A8 phan mem (hieu chinh mini_train — dung bo tham so phan cung dung)
  hw_new  : PHAN CUNG MOI = hwspec_exact (dac ta khop TUNG BIT voi RTL bert_v2, da kiem 35/35 mau E2E)
            + GRU TUONG DUONG RTL (run_gru_rtl_equiv: payload thang UQ0.8 + LUT; RTL lech <= 0,021 mm, VH AK.6)
  hw_old  : PHAN CUNG CU = ban sao bit-exact BERT cu (sw/golden_layer0_dump.py, nhu sw/hw_replica_e2e.py)
            + cung GRU tuong duong RTL (khoi GRU phan cung dung chung)
Ra: out/pred_<ten>.npy (N,4,2)
  python sw/eval_trainval/run_models.py [ten ...] [--workers 8]
"""
import sys, io, time, contextlib, argparse
from pathlib import Path
from multiprocessing import Pool
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "sw" / "eval_trainval" / "out"
for p in (ROOT / "eval", ROOT / "sw", ROOT / "sw" / "hwspec"):
    sys.path.insert(0, str(p))

_W = {}


def _init(kind):
    import torch
    torch.set_num_threads(1)
    from common import load_all
    m, P = load_all()
    _W.update(kind=kind, m=m, P=P)
    if kind in ("hw_new", "hw_old"):
        with contextlib.redirect_stdout(io.StringIO()):
            src = (ROOT / "sw" / "_verify_all_samples_spec.py").read_text(encoding="utf-8")
            g = {"__file__": str(ROOT / "sw" / "_verify_all_samples_spec.py")}
            exec(src[:src.index("Run all 5 samples") - 6], g)
        _W["gru_rtl"] = g["run_gru_rtl_equiv"]
    if kind == "fp32":
        from model.fp32_model import build_model
        fp = build_model()
        ck = torch.load(ROOT / "eval/archived_weights/autoregressive_gru_200ep.pt", map_location="cpu")
        fp.load_state_dict(ck.get("model", ck)); fp.eval()
        _W["fp"] = fp
    if kind == "hw_old":
        with contextlib.redirect_stdout(io.StringIO()):
            import golden_layer0_dump as g0
            PD = ROOT / "sw/payloads/trained"
            pl = [g0.read_layer0_weights_from_payload(PD, layer_idx=i) for i in range(4)]
            cg = [g0.read_ctx_gelu_scales_from_header(ROOT / "sw", layer_idx=i) for i in range(4)]
            gt0 = g0.build_gelu_lut_table(pl[0]["scales"]["w1"], cg[0]["act_scale_gelu"], 0)
        _W.update(g0=g0, pl=pl, cg=cg, gt0=gt0, sc_wo3=pl[3]["scales"]["wo"].astype(np.float64) / 256.0)


def _run(arg):
    i, tok, pad = arg
    k, m = _W["kind"], _W["m"]
    if k == "w4a8":
        return i, m.forward(tok[None], pad[None])[0]
    if k == "fp32":
        import torch
        with torch.no_grad():
            return i, _W["fp"](torch.from_numpy(tok[None]), torch.from_numpy(pad[None])).numpy()[0]
    if k == "hw_new":
        import hwspec_exact as hx
        cls = hx.forward(_W["P"], tok, pad)
        return i, np.asarray(_W["gru_rtl"](np.asarray(cls, np.float32)), np.float32)
    if k == "hw_old":
        g0, x = _W["g0"], None
        with contextlib.redirect_stdout(io.StringIO()):
            for L in range(4):
                st = g0.dump_layer0(m, tok, pad, _W["pl"][L], _W["cg"][L], layer_idx=L, x_in_override=x,
                                    gelu_table_override=_W["gt0"])
                x = st["res2_int8_layer0_out"]
        cls = x[0].astype(np.float64) * _W["sc_wo3"]
        return i, np.asarray(_W["gru_rtl"](cls.astype(np.float32)), np.float32)
    raise ValueError(k)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kinds", nargs="*", default=["fp32", "w4a8", "hw_new", "hw_old"])
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--prefix", default="", help="train_ -> dung tap TRAIN")
    a = ap.parse_args()
    D = np.load(OUT / (a.prefix + "dataset.npz"))
    idx = np.nonzero(D["keep"])[0]
    if a.limit:
        idx = idx[:a.limit]
    for k in a.kinds:
        t0 = time.time()
        pred = np.full((len(D["keep"]), 4, 2), np.nan, np.float32)
        with Pool(a.workers, initializer=_init, initargs=(k,)) as pool:
            for n, (i, wp) in enumerate(pool.imap_unordered(_run, ((i, D["tok"][i], D["pad"][i]) for i in idx),
                                                            chunksize=8)):
                pred[i] = wp
                if n % 500 == 0:
                    print("  %s %d/%d  %.0f s" % (k, n, len(idx), time.time() - t0), flush=True)
        suf = "_lim%d" % a.limit if a.limit else ""
        np.save(OUT / ("%spred_%s%s.npy" % (a.prefix, k, suf)), pred)
        e = np.linalg.norm(pred[idx] - D["gt"][idx], axis=2)
        print("%-7s xong %.0f s | ADE %.3f FDE %.3f" % (k, time.time() - t0, e.mean(), e[:, -1].mean()), flush=True)


if __name__ == "__main__":
    main()
