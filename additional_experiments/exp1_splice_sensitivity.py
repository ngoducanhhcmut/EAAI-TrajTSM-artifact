"""Experiment 1 (13/11/2026): sensitivity of the certified stopping tail to the
difference between the certified apply state and the vehicle's true state.

Uses the unchanged integer golden generator b4_mrmgen (tsmx_hw/golden). For every finite-jerk candidate,
ego speed v in 0..10 m/s (0.25 steps) and acceleration a in {-8,-4,-2,0,1,2} m/s^2, the tail is generated
from the nominal state (0, v, a) and from perturbed start states; we report the largest forward
(front-object side) and backward (rear-object side) shift of the row envelope over the whole horizon.

Two perturbation boxes:
  SPLICE   : the B2 acceptance tube, |dx|<=0.16 m, |dv|<=0.20 m/s (acceleration unchanged)
  DEPLOYED : measurement box of B2 propagated over the apply delay (<=0.1 s) in the measured-anchored
             encoding, |dx|<=0.05+0.05*0.1+0.5*0.1*0.1^2 m, |dv|<=0.05+0.1*0.1 m/s.
Output: experiments/exp1_results.json + printed summary.
"""
import json, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / 'tsmx_hw' / 'golden'))
from tsmx_golden.model import b4_mrmgen, LIBRARY, S

FIN = [c for c in range(16) if LIBRARY[c][1]]
BOXES = {'SPLICE': (160000, 200000), 'DEPLOYED': (50000 + 5000 + 500, 50000 + 10000)}


def envelope(x, v, a, cid):
    tr = b4_mrmgen(x, v, a, cid)
    if not tr.accept:
        return None
    return {r[0]: (r[1], r[2]) for r in tr.rows}


res = {}
for name, (DX, DV) in BOXES.items():
    worst = {'fwd': (0, None), 'back': (0, None)}
    per_cand_fwd = {}
    for cid in FIN:
        for vi in range(0, 41):
            v = vi * 250000
            for a in (-8 * S, -4 * S, -2 * S, 0, 1 * S, 2 * S):
                nom = envelope(0, v, a, cid)
                if nom is None:
                    continue
                for dx, dv, side in ((DX, DV, 'fwd'), (-DX, -DV, 'back')):
                    v2 = min(10 * S, max(0, v + dv))
                    if v2 == v and dv != 0 and side == 'back' and v == 0:
                        pass
                    pert = envelope(dx, v2, a, cid)
                    if pert is None:
                        continue
                    # compare at common times; after the shorter trajectory ends, hold its last position
                    tn = sorted(nom); tp = sorted(pert)
                    lastn = nom[tn[-1]]; lastp = pert[tp[-1]]
                    shift = 0
                    for t in sorted(set(tn) | set(tp)):
                        pn = nom.get(t, lastn); pp = pert.get(t, lastp)
                        d = (pp[1] - pn[1]) if side == 'fwd' else (pn[0] - pp[0])
                        shift = max(shift, d)
                    if shift > worst[side][0]:
                        worst[side] = (shift, dict(cid=cid, b=LIBRARY[cid][0] / S, j=LIBRARY[cid][1] / S,
                                                   v=v / S, a=a / S))
                    if side == 'fwd':
                        key = (LIBRARY[cid][0] / S, LIBRARY[cid][1] / S)
                        per_cand_fwd[key] = max(per_cand_fwd.get(key, 0), shift)
    res[name] = {'box_dx_m': DX / S, 'box_dv_mps': DV / S,
                 'max_forward_shift_m': worst['fwd'][0] / S, 'at': worst['fwd'][1],
                 'max_backward_shift_m': worst['back'][0] / S, 'at_back': worst['back'][1],
                 'max_forward_shift_by_candidate_m': {f'b{k[0]:g}_j{k[1]:g}': round(v / S, 4)
                                                      for k, v in sorted(per_cand_fwd.items())}}
(HERE / 'exp1_results.json').write_text(json.dumps(res, indent=1), encoding='utf-8')
for k, r in res.items():
    print(k, 'fwd', round(r['max_forward_shift_m'], 3), r['at'], '| back', round(r['max_backward_shift_m'], 3), r['at_back'])
    print('  by candidate', r['max_forward_shift_by_candidate_m'])
