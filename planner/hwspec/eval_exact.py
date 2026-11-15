# -*- coding: utf-8 -*-
"""Cong G0: do chinh xac cua hwspec_exact (dac ta tung bit) tren 35 mau."""
import numpy as np
from common import load_all, samples
import hwspec_exact as hx

m, P = load_all()
S = samples()
W, R, G = [], [], []
for s in S:
    cls = hx.forward(P, s["tok"], s["pad"])
    W.append(m.gru.forward(cls[None])[0])
    R.append(m.forward(s["tok"][None], s["pad"][None])[0])
    G.append(s["gt"])
W, R, G = map(np.array, (W, R, G))
e = np.linalg.norm(W - G, axis=2); er = np.linalg.norm(R - G, axis=2)
print("W4A8 (m.forward)   ADE %.3f FDE %.3f RMSE %.3f" % (er.mean(), er[:, -1].mean(), np.sqrt((er**2).mean())))
print("hwspec_exact       ADE %.3f FDE %.3f RMSE %.3f" % (e.mean(), e[:, -1].mean(), np.sqrt((e**2).mean())))
d = np.linalg.norm(W - R, axis=2)
print("lech hwspec vs W4A8: TB %.3f m, max %.3f m" % (d.mean(), d.max()))
print("phan tan WP cuoi: hwspec std_x %.3f std_y %.3f | GT %.3f %.3f" % (
    W[:, -1, 0].std(), W[:, -1, 1].std(), G[:, -1, 0].std(), G[:, -1, 1].std()))
for i in (0, 9, 15, 34):
    print("  %s hw=%s w4a8=%s gt=%s" % (S[i]["name"], np.round(W[i, -1], 2), np.round(R[i, -1], 2), np.round(G[i, -1], 2)))
