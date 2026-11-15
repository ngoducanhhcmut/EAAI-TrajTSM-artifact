"""Claude 05/11/2026: offline smoke test of the wrapper changes (no simulation): certify -> backup,
_latch (L1 phase replay and never-certified path), rows_speeds. Run in WSL env nuplan."""
from types import SimpleNamespace
from tsmx_nuplan.planner import TsmxPlanner, certify, rows_speeds

cid, tr = certify(8.0, 0.0, [(40.0, 5.0, 4.8)])
assert cid is not None and tr.accept, (cid, tr)
p = TsmxPlanner.__new__(TsmxPlanner)
p._backup, p._mrm, p._step = (1.0, tr.rows, cid), None, 7
ego = SimpleNamespace(dynamic_car_state=SimpleNamespace(center_acceleration_2d=SimpleNamespace(x=0.3)))
rec = {}
p._latch(rec, 1.1, 8.0, ego)
assert rec['mode'] == 'MRM' and rec['mrm_cid'] == cid and not rec['mrm_uncertified'], rec
sp = rows_speeds(p._mrm[3], 1.1 - p._mrm[2])
print('L1 replay phase 0.1 s, cid', cid, 'speeds', [round(x, 2) for x in sp[:6]], 'zero at', sp.index(0.0))
p._backup, rec = None, {}
p._latch(rec, 2.0, 6.0, ego)
assert rec['mrm_uncertified'] and rec['mrm_cid'] == 11 and not rec['mrm_surrogate'], rec
rec = {}
p._latch(rec, 2.0, 15.0, ego)          # outside the B4 envelope -> surrogate
assert rec['mrm_surrogate'] and p._mrm[3] is None, rec
cid2, _ = certify(8.0, 0.0, [(6.0, 0.0, 4.8)])
print('blocked case cid', cid2)
print('SMOKE OK')
