# -*- coding: utf-8 -*-
"""Mo hinh tham chieu + bo sinh vector + bo cham cho tb_hmao_zonotope_gen_v2.sv.

Kiem tra dau ra hmao_zonotope_gen ma bo kiem tra va cham v2 su dung:
  cx, cy : tam zonotope Q8.8 — KHOP TUNG BIT: fp32 -> Q8.8 cat ve 0 (giong fp32_to_q88),
           bao hoa +-32767; buoc le cua tang 2 = trung diem (a+b)>>1 (dich so hoc).
  hc, hs : cos/sin huong Q8.8 — sai so cho phep +-1 LSB so voi round(256*cos(theta_q/256)),
           theta_q = huong cat ve Q8.8 (CORDIC 16 tang + lam tron; pi xap xi 804/256).
Buoc k dung waypoint i = k // (NZ/50) (j = i+1 cho trung diem buoc le).

  python sw/eval_trainval/zono_ref.py gen            # sinh vec/zg_traj.hex + zg_cases.json
  python sw/eval_trainval/zono_ref.py check FILE NZ  # cham dau ra RTL
"""
import sys, json, math, struct, random
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "sw" / "eval_trainval" / "out"
VEC = ROOT / "tb" / "unit" / "tsm" / "vec"
sys.path.insert(0, str(ROOT / "sw"))


def f32(v):
    return struct.unpack("<f", struct.pack("<f", v))[0]


def q88_trunc(v):
    """fp32_to_q88: |v|*256 cat ve 0 (dich phan dinh tri), giu dau."""
    v = f32(v)
    m = int(abs(v) * 256.0)
    return -m if v < 0 else m


def sat16(v):
    return max(-32768, min(32767, v))


def expected(traj, nz):
    """traj: list 50 x (x, y, z, vx, vy, hd, ts). Tra ve list nz x (cx, cy, hc, hs)."""
    div = nz // 50
    out = []
    for k in range(nz):
        i = k // div; j = min(i + 1, 49)
        ax, ay = q88_trunc(traj[i][0]), q88_trunc(traj[i][1])
        if div == 2 and k % 2 == 1:
            bx, by = q88_trunc(traj[j][0]), q88_trunc(traj[j][1])
            cx, cy = (ax + bx) >> 1, (ay + by) >> 1
        else:
            cx, cy = ax, ay
        th = q88_trunc(traj[i][5]) / 256.0
        out.append((sat16(cx), sat16(cy), int(round(256 * math.cos(th))), int(round(256 * math.sin(th)))))
    return out


def read_traj_hex(p):
    w = [int(l, 16) for l in open(p).read().split()][:350]
    f = struct.unpack("<350f", b"".join(struct.pack("<I", v) for v in w))
    return [tuple(f[k * 7:(k + 1) * 7]) for k in range(50)], w


def synth_cases(rng):
    """Huong quet ca vong tron + gia tri bien; vi tri lon de thu bao hoa."""
    special = [0.0, 1e-6, -1e-6, 0.003, -0.003, 0.0625, -0.0625, 0.07, -0.07,
               math.pi / 2, -math.pi / 2, math.pi / 2 + 1 / 256, -math.pi / 2 - 1 / 256,
               math.pi / 2 - 1 / 256, -math.pi / 2 + 1 / 256, math.pi, -math.pi,
               math.pi - 1 / 512, -math.pi + 1 / 512, 3.0, -3.0, 1.0, -1.0, 2.0, -2.0]
    sweep = list(np.linspace(-math.pi, math.pi, 361))
    hs = special + sweep + [rng.uniform(-math.pi, math.pi) for _ in range(64)]
    cases = []
    for c in range(0, len(hs), 50):
        chunk = (hs[c:c + 50] + [0.0] * 50)[:50]
        traj = []
        for k, h in enumerate(chunk):
            r = rng.choice([0.0, 0.05, 3.0, 27.5, 99.9, 127.9, 128.5, 180.0, -0.05, -40.0, -130.0])
            traj.append((r * math.cos(k), r * math.sin(k) - 0.5 * k, 0.0, 1.0, 0.0, h, 0.1 * k))
        cases.append(("synth%02d" % (c // 50), traj))
    return cases


def gen():
    import tsm_model as M  # noqa: F401  (chi de chac duong dan)
    rng = random.Random(20261005)
    H = OUT / "tsm_hex"
    P = np.load(OUT / "pred_hw_new.npy"); G = np.load(OUT / "dataset.npz")["gt"]
    names = []
    # ca that: quy dao co |huong| > 90 do, gan dung yen, va cac ca da lech truoc khi sua
    rev, slow, other = [], [], []
    for i in range(0, len(P), 3):
        for kind, W in (("H", P), ("G", G)):
            hd = np.arctan2(*np.diff(np.r_[[[0, 0]], W[i]], axis=0)[:, ::-1].T)
            fin = np.linalg.norm(W[i][-1])
            (rev if np.abs(hd).max() > math.pi / 2 else slow if fin < 2 else other).append("%s%04d" % (kind, i))
    names = ["H0003", "H0006", "H0007", "H0008", "H0009", "G0006"] + rng.sample(rev, min(50, len(rev))) + \
        rng.sample(slow, min(40, len(slow))) + rng.sample(other, 60)
    names = list(dict.fromkeys(names))
    words, meta = [], []
    for n in names:
        traj, w = read_traj_hex(H / ("%s.hex" % n))
        words += w; meta.append(dict(name=n, traj=traj))
    for n, traj in synth_cases(rng):
        b = b"".join(struct.pack("<7f", *t) for t in traj)
        words += list(struct.unpack("<350I", b)); meta.append(dict(name=n, traj=traj))
    VEC.mkdir(parents=True, exist_ok=True)
    (VEC / "zg_traj.hex").write_text("\n".join("%08x" % v for v in words) + "\n")
    (VEC / "zg_ncase.txt").write_text("%d\n" % len(meta))
    (VEC / "zg_cases.json").write_text(json.dumps(meta))
    print("zg: %d ca (%d that, %d tong hop)" % (len(meta), len(names), len(meta) - len(names)))


def check(fn, nz):
    meta = json.loads((VEC / "zg_cases.json").read_text())
    rows = [l.split() for l in open(fn) if l.strip()]
    if any(r[0] == "TIMEOUT" for r in rows):
        print("TIMEOUT:", [r for r in rows if r[0] == "TIMEOUT"][:5]); return 1
    got = {}
    for r in rows:
        got[(int(r[0]), int(r[1]))] = tuple(int(v) for v in r[2:7])
    nbad_c = nbad_h = n = 0; worst = 0; bad = []
    for c, m in enumerate(meta):
        exp = expected(m["traj"], nz)
        for k, (ecx, ecy, ehc, ehs) in enumerate(exp):
            g = got.get((c, k))
            if g is None:
                bad.append((m["name"], k, "thieu")); nbad_c += 1; continue
            n += 1
            if (g[0], g[1]) != (ecx, ecy):
                nbad_c += 1; bad.append((m["name"], k, "tam", g[:2], (ecx, ecy)))
            d = max(abs(g[2] - ehc), abs(g[3] - ehs)); worst = max(worst, d)
            if d > 1:
                nbad_h += 1; bad.append((m["name"], k, "cos/sin", g[2:4], (ehc, ehs)))
    print("NZ=%d: %d buoc / %d ca | tam sai %d | cos/sin lech >1 LSB %d | lech lon nhat %d LSB"
          % (nz, n, len(meta), nbad_c, nbad_h, worst))
    for b in bad[:12]:
        print("  ", b)
    return int(bool(nbad_c or nbad_h))


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).parent))
    if sys.argv[1] == "gen":
        gen()
    else:
        sys.exit(check(sys.argv[2], int(sys.argv[3])))
