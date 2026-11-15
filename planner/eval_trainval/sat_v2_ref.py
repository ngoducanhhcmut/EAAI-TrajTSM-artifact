# -*- coding: utf-8 -*-
"""Mo hinh tham chieu KHOP TUNG BIT cho hmao_collision_sat v2 + bo sinh vector cho tb_hmao_collision_sat_v2.

So hoc giong RTL: Q8.8 so nguyen, mul88(a,b) = (a*b) >> 8 (dich so hoc), |.|, so sanh '>'.
Sinh 3 bo vector (moi bo cho mot cau hinh DUT trong testbench):
  s1   : NUM_ZONOTOPES=50,  MAX_OBSTACLES=100, LIST_MODE=0, STEP_DT_Q16=6554, MAX_CHECK_STEPS=50
  s2   : NUM_ZONOTOPES=100, MAX_OBSTACLES=16,  LIST_MODE=1, STEP_DT_Q16=3277, MAX_CHECK_STEPS=100
  s1c20: nhu s1 nhung MAX_CHECK_STEPS=20
Ca kiem: tu du lieu THAT (quy dao phan cung + vat can nuScenes VAL) va ngau nhien.
  python sw/eval_trainval/sat_v2_ref.py
"""
import math, pickle, random
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "sw" / "eval_trainval" / "out"
VEC = ROOT / "tb" / "unit" / "tsm" / "vec"
EGO_C_Q88 = 353
EGO_HALF_LEN_Q88, EGO_HALF_WID_Q88 = 523, 221


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def s32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def mul88(a, b):
    return (a * b) >> 8


def q(v):
    return int(round(v * 256.0))


def sat_ref(zono, wm, el, ew, nz, max_obs, list_mode, lst, lcnt, dt_q16, max_chk):
    """zono: list[(cx,cy,hc,hs)] (16 bit co dau); wm: list[dict] cac truong 32 bit; tra ve dict ket qua."""
    order = [lst[k] & 0x7F for k in range(lcnt)] if list_mode else list(range(max_obs))
    found, cnt, ids, fstep, fobs = False, 0, [0] * 16, 0, 0
    for slot in order:
        o = wm[slot]
        if o["conf"] == 0:
            continue
        uc, us = s16(o["head"] & 0xFFFF), s16(o["head"] >> 16)
        lo, wo = s32(o["len"]) >> 1, s32(o["wid"]) >> 1
        px, py, vx, vy = s32(o["px"]), s32(o["py"]), s32(o["vx"]), s32(o["vy"])
        step = 0
        while True:
            cx, cy, hc, hs = zono[step]
            t = (step * dt_q16) & ((1 << 23) - 1)
            ex = cx + mul88(EGO_C_Q88, hc); ey = cy + mul88(EGO_C_Q88, hs)
            ox = px + ((vx * t) >> 16); oy = py + ((vy * t) >> 16)
            cosd = mul88(hc, uc) + mul88(hs, us); sind = mul88(hc, us) - mul88(hs, uc)
            dx, dy, c, s = ex - ox, ey - oy, abs(cosd), abs(sind)
            dh = abs(mul88(dx, hc) + mul88(dy, hs)); dhp = abs(mul88(dy, hc) - mul88(dx, hs))
            du = abs(mul88(dx, uc) + mul88(dy, us)); dup = abs(mul88(dy, uc) - mul88(dx, us))
            reu = mul88(el, c) + mul88(ew, s); reup = mul88(el, s) + mul88(ew, c)
            rbh = mul88(lo, c) + mul88(wo, s); rbhp = mul88(lo, s) + mul88(wo, c)
            sep = dh > el + rbh or dhp > ew + rbhp or du > reu + lo or dup > reup + wo
            coll = (not sep) and step < max_chk
            if coll:
                if not found:
                    found, fstep, fobs = True, step, o["tid"]
                if cnt < 16:
                    ids[cnt] = slot; cnt += 1
            if coll or step >= nz - 1 or step >= max_chk - 1:
                break
            step += 1
    return dict(pot=int(found), cnt=cnt, ids=ids, fstep=fstep, fobs=fobs)


# ------------------------------------------------------------------ sinh vector
def zono_from_traj(wps4, nz):
    import tsm_model as M
    x, y, vx, vy, hd = M.traj50_v2(wps4)
    xq = [max(-32768, min(32767, q(v))) for v in x]; yq = [max(-32768, min(32767, q(v))) for v in y]
    out = []
    for s in range(nz):
        i = s if nz == 50 else s // 2
        j = min(i + 1, 49)
        odd = nz == 100 and s % 2 == 1
        cx = (xq[i] + xq[j]) >> 1 if odd else xq[i]
        cy = (yq[i] + yq[j]) >> 1 if odd else yq[i]
        out.append((cx, cy, q(math.cos(hd[i])), q(math.sin(hd[i]))))
    return out


def wm_from_objs(objs, rng):
    import tsm_model as M
    P, V, Y, Lh, Wh = M.obj_arrays(objs, True)
    wm = []
    for j, o in enumerate(objs):
        head = ((q(math.sin(Y[j])) & 0xFFFF) << 16) | (q(math.cos(Y[j])) & 0xFFFF)
        wm.append(dict(px=q(P[j, 0]) & 0xFFFFFFFF, py=q(P[j, 1]) & 0xFFFFFFFF, vx=q(V[j, 0]) & 0xFFFFFFFF,
                       vy=q(V[j, 1]) & 0xFFFFFFFF, len=q(2 * Lh[j]), wid=q(2 * Wh[j]), head=head,
                       tid=j & 0xFFFF, conf=0 if rng.random() < 0.05 else 100))
    while len(wm) < 100:
        wm.append(dict(px=0, py=0, vx=0, vy=0, len=0, wid=0, head=0, tid=0, conf=0))
    return wm


def rand_case(nz, rng):
    v = rng.uniform(0, 15); yaw = rng.uniform(-0.5, 0.5); cur = rng.uniform(-0.05, 0.05)
    zono, x, y, h = [], 0.0, 0.0, 0.0
    dt = 5.0 / nz
    for s in range(nz):
        zono.append((q(x), q(y), q(math.cos(h)), q(math.sin(h))))
        x += v * dt * math.cos(h); y += v * dt * math.sin(h); h += cur
    objs = []
    for k in range(rng.randint(1, 30)):
        a = rng.uniform(-math.pi, math.pi)
        objs.append(dict(x=rng.uniform(-10, 60), y=rng.uniform(-12, 12), yaw=a, w=rng.uniform(0.4, 3.0),
                         l=rng.uniform(0.4, 12.0), prv=np.array([np.nan, np.nan, np.nan])))
        if rng.random() < 0.6:
            sp = rng.uniform(0, 15); objs[-1]["prv"] = np.array([objs[-1]["x"] - sp * 0.5 * math.cos(a),
                                                                objs[-1]["y"] - sp * 0.5 * math.sin(a), 0.5])
    return zono, objs


def write_set(tag, cases, nz, max_obs, list_mode, dt_q16, max_chk):
    VEC.mkdir(parents=True, exist_ok=True)
    fz, fw, fp, fe = [], [], [], []
    stats = [0, 0]
    for zono, wm, el, ew, lst, lcnt in cases:
        r = sat_ref(zono, wm, el, ew, nz, max_obs, list_mode, lst, lcnt, dt_q16, max_chk)
        stats[r["pot"]] += 1
        for cx, cy, hc, hs in zono:
            fz.append("%04x%04x%04x%04x" % (cx & 0xFFFF, cy & 0xFFFF, hc & 0xFFFF, hs & 0xFFFF))
        for o in wm:
            beat0 = [o["px"], o["py"], 0, o["vx"], o["vy"], 0, o["len"], o["wid"]]
            beat1 = [0, o["head"], (o["conf"] << 24) | (o["tid"] & 0xFFFF), 0, 0, 0, 0, 0]
            fw += ["%08x" % (w & 0xFFFFFFFF) for w in beat0 + beat1]
        fp += ["%08x" % el, "%08x" % ew, "%08x" % lcnt] + ["%08x" % (lst[k] if k < len(lst) else 0) for k in range(16)]
        fe += ["%08x" % r["pot"], "%08x" % r["cnt"]] + ["%08x" % v for v in r["ids"]] + ["%08x" % r["fstep"],
                                                                                       "%08x" % r["fobs"]]
    for name, lines in (("zono", fz), ("wm", fw), ("par", fp), ("exp", fe)):
        (VEC / ("%s_%s.hex" % (tag, name))).write_text("\n".join(lines) + "\n")
    print("%-6s %d ca: VETO %d / GRANT %d" % (tag, len(cases), stats[1], stats[0]))
    return len(cases)


def main():
    import sys
    sys.path.insert(0, str(Path(__file__).parent))
    from validate_model import select
    rng = random.Random(20261004)
    D = np.load(OUT / "dataset.npz"); O = pickle.load(open(OUT / "objects.pkl", "rb"))
    P = np.load(OUT / "pred_hw_new.npy"); G = D["gt"]
    import analyze as A
    # chon mau that: uu tien mau co va cham that + mau ngau nhien
    coll = [i for i in range(0, len(P), 7) if A.collides(P[i], O[i])][:40]
    other = rng.sample([i for i in range(len(P)) if i not in set(coll)], 100 - len(coll))
    counts = {}
    for tag, nz, max_obs, lmode, dtq, chk in (("s1", 50, 100, 0, 6554, 50), ("s2", 100, 16, 1, 3277, 100),
                                               ("s1c20", 50, 100, 0, 6554, 20)):
        cases = []
        for n, i in enumerate(coll + other):
            w = P[i] if n % 2 == 0 else G[i]
            objs = select(O[i], P[i], G[i])
            wm = wm_from_objs(objs, rng)
            el = EGO_HALF_LEN_Q88 + rng.choice([0, 129, 264]); ew = EGO_HALF_WID_Q88 + rng.choice([0, 99, 198])
            lst = rng.sample(range(len(objs)), min(len(objs), rng.randint(1, 16))) if lmode else []
            cases.append((zono_from_traj(w, nz), wm, el, ew, lst, len(lst)))
        for _ in range(100):
            zono, objs = rand_case(nz, rng)
            wm = wm_from_objs(objs, rng)
            el = EGO_HALF_LEN_Q88 + rng.randint(0, 300); ew = EGO_HALF_WID_Q88 + rng.randint(0, 250)
            lst = rng.sample(range(len(objs)), min(len(objs), rng.randint(0, 16))) if lmode else []
            cases.append((zono, wm, el, ew, lst, len(lst)))
        counts[tag] = write_set(tag, cases, nz, max_obs, lmode, dtq, chk)
    (VEC / "ncase.txt").write_text(" ".join("%s=%d" % kv for kv in counts.items()) + "\n")


if __name__ == "__main__":
    main()
