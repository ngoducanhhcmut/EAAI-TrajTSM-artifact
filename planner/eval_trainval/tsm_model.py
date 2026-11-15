# -*- coding: utf-8 -*-
"""Mo hinh Python (vector hoa NumPy) cua phep kiem va cham trong TSM.

decide_old(): sao lai RTL HIEN TAI (doi chieu voi 10.838 quyet dinh RTL that):
   tam zonotope = tich phan c += dt*vx*(cos h, sin h), dt = 26/256 s; SAT 8 truc
   (x, y, u, u_perp, g1_perp, g2_perp, cheo 45/135) giua DIEM tam va hop vat can coi nhu thang truc
   (ro = |ax|*w/2 + |ay|*l/2), rz = 0, vat can dung yen, loc hop bao +-2 m, tang 2 = 16 muc dau WM.
decide_new(): THIET KE MOI:
   tam = vi tri waypoint (noi suy cho tang 2), hop xe ego that (tam = truc sau + EGO_C theo huong,
   nua dai L/2 + b_long, nua rong W/2 + b_lat), hop vat can xoay dung huong, vat can chuyen dong
   p(t) = p0 + v*t (v uoc luong NHAN QUA tu vi tri ~0,5 s truoc), SAT 8 truc (x, y, u, u_perp, h, h_perp,
   cheo 45/135), chi xet buoc t <= t_check; tang 2 (100 buoc, 0,05 s) chi xet danh sach nghi ngo cua tang 1.
"""
import math
import numpy as np

EGO_L, EGO_W, EGO_C = 4.084, 1.730, 1.38
R2 = 1 / math.sqrt(2)


def q88(v):
    return np.round(np.asarray(v, np.float64) * 256.0) / 256.0


def traj50(wps4):
    """Giong gen_hmao_collision_e2e_dataset.expand_to_50wp + compute_kinematics (kep 35 m/s)."""
    wps4 = np.asarray(wps4, np.float64)
    t = np.array([0.0, 0.5, 1.0, 1.5, 2.0])
    xk = np.r_[0.0, wps4[:, 0]]; yk = np.r_[0.0, wps4[:, 1]]
    ta = np.arange(50) * 0.1
    x = np.polyval(np.polyfit(t, xk, 3), ta); y = np.polyval(np.polyfit(t, yk, 3), ta)
    vx = np.empty(50); vy = np.empty(50)
    vx[:-1] = np.diff(x) / 0.1; vy[:-1] = np.diff(y) / 0.1
    vx[-1] = vx[-2]; vy[-1] = vy[-2]
    sp = np.hypot(vx, vy); s = np.where(sp > 35.0, 35.0 / np.maximum(sp, 1e-9), 1.0)
    vx = vx * s; vy = vy * s
    return x, y, vx, vy, np.arctan2(vy, vx)


def obj_arrays(objs, use_vel=True):
    n = len(objs)
    P = np.zeros((n, 2)); V = np.zeros((n, 2)); Y = np.zeros(n); Lh = np.zeros(n); Wh = np.zeros(n)
    for j, o in enumerate(objs):
        P[j] = (o["x"], o["y"]); Y[j] = o["yaw"]; Lh[j] = o["l"] / 2; Wh[j] = o["w"] / 2
        p = o.get("prv")
        if use_vel and p is not None and not np.isnan(p[0]) and 0.2 < p[2] < 1.0:
            V[j] = ((o["x"] - p[0]) / p[2], (o["y"] - p[1]) / p[2])
    return P, V, Y, Lh, Wh


# ------------------------------------------------------------------ RTL hien tai
def decide_old(wps4, objs, lat_m=1.02, long_m=2.0):
    if not objs:
        return "GRANT"
    x, y, vx, vy, hd = traj50(wps4)
    xq, yq = q88(x), q88(y)
    dt = 26 / 256
    dx = dt * q88(vx[:49]) * np.cos(hd[:49]); dy = dt * q88(vx[:49]) * np.sin(hd[:49])
    cx = xq[0] + np.r_[0, np.cumsum(dx)]; cy = yq[0] + np.r_[0, np.cumsum(dy)]
    k = np.arange(50); lm = lat_m + k * 16 / 256
    g1 = np.stack([lm * np.cos(hd), lm * np.sin(hd)], 1)
    ang = np.cumsum(hd)                                   # g2 = (0,long) quay tich luy
    g2 = np.stack([-long_m * np.sin(ang), long_m * np.cos(ang)], 1)
    P, _, Y, Lh, Wh = obj_arrays(objs, use_vel=False)
    inb = ((P[:, 0] >= xq.min() - 2) & (P[:, 0] <= xq.max() + 2) &
           (P[:, 1] >= yq.min() - 2) & (P[:, 1] <= yq.max() + 2))
    u = np.stack([np.cos(Y), np.sin(Y)], 1)                                   # (n,2)
    ax = np.zeros((len(objs), 50, 8, 2))
    ax[:, :, 0] = (1, 0); ax[:, :, 1] = (0, 1)
    ax[:, :, 2] = u[:, None, :]; ax[:, :, 3] = np.stack([-u[:, 1], u[:, 0]], 1)[:, None, :]
    ax[:, :, 4] = np.stack([-g1[:, 1], g1[:, 0]], 1)[None]; ax[:, :, 5] = np.stack([-g2[:, 1], g2[:, 0]], 1)[None]
    ax[:, :, 6] = (R2, R2); ax[:, :, 7] = (-R2, R2)
    d = np.stack([cx, cy], 1)[None, :, None, :] - P[:, None, None, :]        # (n,50,1,2)
    dv = np.abs((d * ax).sum(-1))
    ro = np.abs(ax[..., 0]) * (2 * Wh)[:, None, None] / 2 + np.abs(ax[..., 1]) * (2 * Lh)[:, None, None] / 2
    coll = (~(dv > ro).any(-1)) & inb[:, None]                               # (n,50)
    if not coll.any():
        return "GRANT"
    return "VETO" if coll[:16].any() else "GRANT"


# ------------------------------------------------------------------ thiet ke moi
def _scan(xq, yq, hd, P, V, Y, Lh, Wh, nstep, dt, b_long, b_lat, t_check, grow):
    t = np.arange(nstep) * dt
    m = t <= t_check + 1e-9
    t = t[m]
    fi = t / 0.1; i0 = np.minimum(fi.astype(int), 49); i1 = np.minimum(i0 + 1, 49); f = fi - i0
    cx = xq[i0] + f * (xq[i1] - xq[i0]); cy = yq[i0] + f * (yq[i1] - yq[i0])
    h = np.stack([np.cos(hd[i0]), np.sin(hd[i0])], 1)                       # (T,2)
    ex = cx + EGO_C * h[:, 0]; ey = cy + EGO_C * h[:, 1]
    eL = EGO_L / 2 + b_long + grow * t; eW = EGO_W / 2 + b_lat + grow * t     # (T,)
    u = np.stack([np.cos(Y), np.sin(Y)], 1)                                   # (n,2)
    n, T = len(P), len(t)
    ax = np.zeros((n, T, 8, 2))
    ax[:, :, 0] = (1, 0); ax[:, :, 1] = (0, 1)
    ax[:, :, 2] = u[:, None]; ax[:, :, 3] = np.stack([-u[:, 1], u[:, 0]], 1)[:, None]
    ax[:, :, 4] = h[None]; ax[:, :, 5] = np.stack([-h[:, 1], h[:, 0]], 1)[None]
    ax[:, :, 6] = (R2, R2); ax[:, :, 7] = (-R2, R2)
    op = P[:, None, :] + V[:, None, :] * t[None, :, None]                    # (n,T,2)
    d = np.stack([ex, ey], 1)[None] - op                                       # (n,T,2)
    dv = np.abs((d[:, :, None, :] * ax).sum(-1))                              # (n,T,8)
    hh = h[None, :, None, :]
    rE = (eL[None, :, None] * np.abs((hh * ax).sum(-1)) +
          eW[None, :, None] * np.abs(-hh[..., 1] * ax[..., 0] + hh[..., 0] * ax[..., 1]))
    uu = u[:, None, None, :]
    rB = (Lh[:, None, None] * np.abs((uu * ax).sum(-1)) +
          Wh[:, None, None] * np.abs(-uu[..., 1] * ax[..., 0] + uu[..., 0] * ax[..., 1]))
    return (~(dv > rE + rB).any(-1)).any(1)                                   # (n,) co va cham


def decide_new(wps4, objs, b_long=0.5, b_lat=0.3, t_check=5.0, use_vel=True, grow=0.0):
    if not objs:
        return "GRANT"
    x, y, vx, vy, hd = traj50(wps4)
    xq, yq = q88(x), q88(y)
    P, V, Y, Lh, Wh = obj_arrays(objs, use_vel)
    s1 = _scan(xq, yq, hd, P, V, Y, Lh, Wh, 50, 0.1, b_long, b_lat, t_check, grow)
    if not s1.any():
        return "GRANT"
    idx = np.nonzero(s1)[0][:16]
    s2 = _scan(xq, yq, hd, P[idx], V[idx], Y[idx], Lh[idx], Wh[idx], 100, 0.05, b_long, b_lat, t_check, grow)
    return "VETO" if s2.any() else "GRANT"


# ------------------------------------------------------------------ RTL v2 (thiet ke da hien thuc)
LAT_M_BD, LONG_M_BD = 396 / 256, 528 / 256      # bien thich nghi voi chat luong 0xFF (block design)


def traj50_v2(wps4, hold=0.5):
    """traj50 + quy uoc giu huong khi |v| < hold (giong compute_kinematics v2)."""
    x, y, vx, vy, hd = traj50(wps4)
    sp = np.hypot(vx, vy)
    hd2 = hd.copy()
    for i in range(50):
        if sp[i] < hold:
            hd2[i] = hd2[i - 1] if i > 0 else 0.0
    return x, y, vx, vy, hd2


def _scan_v2(cx, cy, hk, P, V, Y, Lh, Wh, nstep, dt, EL, EW, nchk):
    k = np.arange(min(nstep, nchk)); t = k * dt
    h = np.stack([np.cos(hk[k]), np.sin(hk[k])], 1)                          # (T,2)
    ex = cx[k] + EGO_C * h[:, 0]; ey = cy[k] + EGO_C * h[:, 1]
    u = np.stack([np.cos(Y), np.sin(Y)], 1)
    op = P[:, None, :] + V[:, None, :] * t[None, :, None]                    # (n,T,2)
    dx = ex[None] - op[..., 0]; dy = ey[None] - op[..., 1]
    hc, hs = h[None, :, 0], h[None, :, 1]; uc, us = u[:, None, 0], u[:, None, 1]
    c = np.abs(hc * uc + hs * us); s = np.abs(hc * us - hs * uc)
    dh = np.abs(dx * hc + dy * hs); dhp = np.abs(dy * hc - dx * hs)
    du = np.abs(dx * uc + dy * us); dup = np.abs(dy * uc - dx * us)
    Lo, Wo = Lh[:, None], Wh[:, None]
    sep = ((dh > EL + Lo * c + Wo * s) | (dhp > EW + Lo * s + Wo * c) |
           (du > EL * c + EW * s + Lo) | (dup > EL * s + EW * c + Wo))
    return (~sep).any(1)


def decide_v2(wps4, objs, k_long=64, k_lat=64, s1_chk=50, use_vel=True, lat_m=LAT_M_BD, long_m=LONG_M_BD):
    if not objs:
        return "GRANT"
    x, y, vx, vy, hd = traj50_v2(wps4)
    xq, yq = np.clip(q88(x), -128, 127.996), np.clip(q88(y), -128, 127.996)
    EL = EGO_L / 2 + long_m * k_long / 256; EW = EGO_W / 2 + lat_m * k_lat / 256
    P, V, Y, Lh, Wh = obj_arrays(objs, use_vel)
    s1 = _scan_v2(xq, yq, hd, P, V, Y, Lh, Wh, 50, 0.1, EL, EW, s1_chk)
    if not s1.any():
        return "GRANT"
    idx = np.nonzero(s1)[0][:16]
    i = np.arange(100) // 2; j = np.minimum(i + 1, 49); odd = (np.arange(100) % 2) == 1
    cx2 = np.where(odd, (xq[i] + xq[j]) / 2, xq[i]); cy2 = np.where(odd, (yq[i] + yq[j]) / 2, yq[i])
    s2 = _scan_v2(cx2, cy2, hd[i], P[idx], V[idx], Y[idx], Lh[idx], Wh[idx], 100, 0.05, EL, EW, 2 * s1_chk)
    return "VETO" if s2.any() else "GRANT"
