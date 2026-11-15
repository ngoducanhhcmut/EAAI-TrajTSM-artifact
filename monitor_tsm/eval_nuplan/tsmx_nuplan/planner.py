"""Claude 05/11/2026 (W8): nuPlan closed-loop wrapper — nominal IDM planner, injected planner faults, TSM-X Simplex.

Per 0.1 s simulation step:
  1. nominal plan P = IDMPlanner (target speed capped to the TSM-X ODD, v <= 10 m/s), optionally FAULTED from onset t_f:
       blind  : the planner receives no agents (perception dropout); traffic lights still respected
       stale  : the planner hangs; the executor keeps the last commanded speed (constant-speed plan along the path)
  2. if tsmx: the unchanged TSM-X golden (B4 mrmgen + B3 geom, eval_nuscenes/w7_secondary.py variant VA, proof/
     adapter_lemmas.py) checks the plan's first-step state (v0, a_plan) against the agents projected onto the route path
     (1D, corridor |lateral| <= 1.8 m + agent half-width). ACCEPT (some finite-jerk MRM cid is certified) -> execute P and
     remember cid. REJECT -> latch the most recently certified MRM (brake profile b,j of that cid from the current state)
     until standstill; outside the ODD (v > 10 m/s or a outside [-8, 2]) the monitor passes P through and counts the step.
  3. one JSON line per step is appended to $TSMX_LOG_DIR/<scenario token>_<condition>.jsonl.

World-model limits (reported, not hidden): objects are constant-velocity along the path; reactive IDM agents brake, cut-ins
and lateral motion are outside the 1D model. Soundness is claimed only for the model, not for nuPlan collisions.
"""
import hashlib
import json
import math
import os
import random
import sys
from pathlib import Path
from types import SimpleNamespace
from typing import List, Type

import numpy as np
from shapely.geometry import Point

from nuplan.common.actor_state.ego_state import EgoState
from nuplan.common.actor_state.state_representation import StateSE2, StateVector2D, TimePoint
from nuplan.common.actor_state.tracked_objects import TrackedObjects
from nuplan.common.actor_state.tracked_objects_types import TrackedObjectType
from nuplan.planning.simulation.observation.observation_type import DetectionsTracks, Observation
from nuplan.planning.simulation.planner.abstract_planner import AbstractPlanner, PlannerInitialization, PlannerInput
from nuplan.planning.simulation.planner.idm_planner import IDMPlanner
from nuplan.planning.simulation.trajectory.abstract_trajectory import AbstractTrajectory
from nuplan.planning.simulation.trajectory.interpolated_trajectory import InterpolatedTrajectory

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'golden'))
from tsmx_golden.model import Motion, propagated_objects, b4_mrmgen, b3_geom, LIBRARY  # noqa: E402

S = 1000000
LANE = (-1800000, 1800000)
LAT = 100000                     # one 0.1 s decision step between the checked state and the applied plan
ODD_V = 10.0
LANE_HALF = 1.8
KEEP = (TrackedObjectType.VEHICLE, TrackedObjectType.PEDESTRIAN, TrackedObjectType.BICYCLE,
        TrackedObjectType.TRAFFIC_CONE, TrackedObjectType.BARRIER, TrackedObjectType.CZONE_SIGN,
        TrackedObjectType.GENERIC_OBJECT)


def fx(value):
    return int(round(float(value) * S))


# Claude 07/11 (W11): when TSMX_DUMP_DIR is set, every golden B4/B3 call inside certify() is appended to
# <dir>/<token>_<cond>.calls.jsonl so the decisions can be replayed on the RTL units. Write-only side channel:
# no decision, RNG use or ordering depends on it.
_DUMP = None                     # (path, step, t) of the current planner step, or None


def _dump(kind, **kw):
    if _DUMP is not None:
        path, step, t = _DUMP
        with open(path, 'a') as fh:
            fh.write(json.dumps(dict(kind=kind, step=step, t=t, **kw)) + '\n')


def certify(v0, a0, objects):
    """First finite-jerk (cid, trajectory) whose MRM is certified (VA reduction per candidate horizon), else
    (None, None). objects: list of (x_m, v_mps, half_len_m), x relative to the ego centre along the path.
    Claude 05/11: the certified B4 trajectory is returned so the executor can replay it in its own phase."""
    for cid in range(16):
        if not LIBRARY[cid][1]:
            continue
        tr = b4_mrmgen(0, fx(v0), fx(a0), cid)
        _dump('b4', x=0, v=fx(v0), a=fx(a0), cid=cid, accept=bool(tr.accept), reason=tr.reason, stop=tr.stop,
              nrows=len(tr.rows))
        if not tr.accept:
            return None, None                 # range reject (outside the B4 envelope): fail closed
        horizon = tr.rows[-1][0] - tr.rows[0][0]
        raw = []
        for x, v, ln in objects:
            xi, vi, li = fx(x), fx(v), fx(ln)
            if vi < 0:
                if xi > 0:                      # swept-interval cover (proof/adapter_lemmas.py A1-A3)
                    w = -((vi * (LAT + horizon)) // S)
                    w2 = -(-w // 2)
                    xi, li = xi - w2, li + w2
                vi = 0
            if vi > 20 * S or abs(xi) > 10000 * S or not 0 < li <= 20 * S:
                raw = None
                break
            raw.append(Motion(xi, vi, 0, li, 0, 0))
        if raw is None:
            continue                            # cover too long for this candidate's horizon: try the next one
        if len(raw) > 32:
            _dump('over32', cid=cid, n=len(raw))
            return None, None
        _g = b3_geom(tr, propagated_objects(tuple(raw), LAT, 0), LANE)
        _dump('b3', cid=cid, v=fx(v0), a=fx(a0), objects=[[m.x, m.v, m.length] for m in raw], accept=bool(_g.accept),
              margin=_g.margin, reason=_g.reason, steps=_g.steps)
        if _g.accept:
            return cid, tr
    return None, None


def rows_speeds(rows, phase_s, dt=0.1, n=81):
    """Speeds of a B4 trajectory (midpoint of each row's [vl, vh]) sampled from `phase_s` seconds after its origin,
    linearly interpolated between 0.1 s rows; 0 after the last row (stop + hold). The origin is NEVER refreshed."""
    ts = [(r[0] - rows[0][0]) / 1e6 for r in rows]
    vs = [0.5 * (r[3] + r[4]) / S for r in rows]
    out = []
    for k in range(n):
        t = phase_s + k * dt
        if t >= ts[-1]:
            out.append(0.0)
            continue
        i = max(0, min(len(ts) - 2, int(t / 0.1)))
        while i + 1 < len(ts) - 1 and ts[i + 1] <= t:
            i += 1
        f = (t - ts[i]) / (ts[i + 1] - ts[i]) if ts[i + 1] > ts[i] else 0.0
        out.append(max(0.0, vs[i] + f * (vs[i + 1] - vs[i])))
    return out


def mrm_speeds(v0, a0, cid, dt=0.1, horizon=8.0):
    """Speed samples of the cid brake profile (accel ramps from a0 to -b at jerk j), from v0, until standstill."""
    b, j = LIBRARY[cid][0] / S, LIBRARY[cid][1] / S
    v, a, out, h = v0, min(a0, 0.0), [v0], 0.005
    t = 0.0
    while t < horizon - 1e-9:
        for _ in range(int(round(dt / h))):
            a = max(a - j * h, -b)
            v = max(0.0, v + a * h)
        t += dt
        out.append(v)
    return out


def rss_ok(v0, objs, rho=0.1, amax=2.0, bmin=4.0, bmax=8.0, reserve=0.5):
    """Claude 13/11/2026 (baseline monitor): responsibility-sensitive longitudinal rule.
    Front objects only (the rear vehicle is responsible); objs = (s, v, combined half-length) along the route."""
    for s_rel, v, half in objs:
        if s_rel < 0:
            continue
        d = v0 * rho + .5 * amax * rho ** 2 + (v0 + rho * amax) ** 2 / (2 * bmin) - v * abs(v) / (2 * bmax)
        if s_rel - half < max(d, 0.0) + reserve:
            return False
    return True


class TsmxPlanner(AbstractPlanner):
    requires_scenario: bool = True

    def __init__(self, scenario, tsmx: bool = True, fault: str = 'none', fault_window=(2.0, 6.0), seed: int = 20261105,
                 condition: str = '', contract: bool = False, monitor: str = 'tsmx', **idm):
        self._idm = IDMPlanner(**idm)
        self._tsmx, self._fault, self._cond = tsmx, fault, condition or f"{fault}_{'tsmx' if tsmx else 'raw'}"
        # Claude 05/11: contract=True adds the B1 freshness rule (plan generation time older than 150 ms ->
        # REJECT). A hung planner (stale fault) stops producing new generation times. Default False keeps mainA/mainB.
        self._contract = contract
        self._monitor = monitor          # 'tsmx' (default, unchanged) or 'rss' baseline (13/11/2026)
        self._token = scenario.token
        rng = random.Random(int(hashlib.sha256(f'{seed}:{scenario.token}'.encode()).hexdigest()[:12], 16))
        self._t_fault = rng.uniform(*fault_window)
        self._t0 = None
        self._last_cid = None
        self._backup = None                    # (t_origin_s, rows, cid) of the last certified tail (B4 rows)
        self._mrm = None                       # (start_step, cid, t_origin_s, rows or None) while latched
        self._stale_v = None
        self._step = 0
        dd = os.environ.get('TSMX_DUMP_DIR')
        self._dump = str(Path(dd) / f'{scenario.token}_{self._cond}.calls.jsonl') if dd else None
        if self._dump:
            open(self._dump, 'w').close()
        d = os.environ.get('TSMX_LOG_DIR')
        self._log = str(Path(d) / f'{self._token}_{self._cond}.jsonl') if d else None   # path only: the planner is pickled
        if self._log:
            open(self._log, 'w').close()

    def name(self) -> str:
        return f'TsmxPlanner_{self._cond}'

    def observation_type(self) -> Type[Observation]:
        return DetectionsTracks  # type: ignore

    def initialize(self, initialization: PlannerInitialization) -> None:
        self._idm.initialize(initialization)

    # ---------------------------------------------------------------- helpers
    def _path_traj(self, ego_state: EgoState, speeds: List[float], dt=0.1) -> InterpolatedTrajectory:
        idm = self._idm
        prog = idm._ego_path_linestring.project(Point(*ego_state.center.point.array))
        lo, hi = idm._ego_path.get_start_progress(), idm._ego_path.get_end_progress()
        states, t = [], ego_state.time_point
        for k, v in enumerate(speeds):
            c = idm._ego_path.get_state_at_progress(max(lo, min(prog, hi)))
            acc = (speeds[k + 1] - v) / dt if k + 1 < len(speeds) else 0.0   # consistent with the speeds
            states.append(EgoState.build_from_center(
                center=StateSE2(c.x, c.y, c.heading), center_velocity_2d=StateVector2D(v, 0),
                center_acceleration_2d=StateVector2D(acc, 0), tire_steering_angle=0.0,
                time_point=t + TimePoint(int(k * dt * 1e6)), vehicle_parameters=ego_state.car_footprint.vehicle_parameters))
            if k + 1 < len(speeds):
                prog += 0.5 * (v + speeds[k + 1]) * dt
        return InterpolatedTrajectory(states)

    def _objects(self, ego_state, observation):
        idm = self._idm
        line = idm._ego_path_linestring
        s0 = line.project(Point(*ego_state.center.point.array))
        ego_len = ego_state.car_footprint.vehicle_parameters.length
        out = []
        for obj in observation.tracked_objects.get_tracked_objects_of_types(list(KEEP)):
            p = Point(obj.center.x, obj.center.y)
            s = line.project(p)
            lat = line.distance(p)
            if lat > LANE_HALF + obj.box.width / 2:
                continue
            if s >= line.length - 1e-6 and line.interpolate(s).distance(p) > 0.5:
                continue                        # beyond the end of the path
            st = idm._ego_path.get_state_at_progress(max(idm._ego_path.get_start_progress(),
                                                         min(s, idm._ego_path.get_end_progress())))
            vel = getattr(obj, 'velocity', None)
            v = 0.0 if vel is None else vel.x * math.cos(st.heading) + vel.y * math.sin(st.heading)
            out.append((s - s0, v, (ego_len + obj.box.length) / 2))
        out.sort(key=lambda o: abs(o[0]))
        return out[:32] if len(out) <= 32 else out          # >32 -> certify() fails closed

    def _latch(self, rec, t, v0, ego_state):
        """REJECT -> MRM. L1: continue the last certified backup in its original phase. Never certified: generate the
        b8/j8 profile (cid 11) from the current state, uncertified; outside the B4 envelope: numeric surrogate."""
        if self._backup is not None:
            origin, rows, cid = self._backup
            self._mrm = (self._step, cid, origin, rows)
            rec['mrm_uncertified'] = False
        else:
            a_now = min(2.0, max(-8.0, ego_state.dynamic_car_state.center_acceleration_2d.x))
            tr = b4_mrmgen(0, fx(max(0.0, v0)), fx(a_now), 11)
            self._mrm = (self._step, 11, t, tr.rows if tr.accept else None)
            rec['mrm_uncertified'] = True
            rec['mrm_surrogate'] = not tr.accept
        rec['mode'] = 'MRM'
        rec['mrm_cid'] = self._mrm[1]

    # ---------------------------------------------------------------- main
    def compute_planner_trajectory(self, current_input: PlannerInput) -> AbstractTrajectory:
        ego_state, observation = current_input.history.current_state
        if self._t0 is None:
            self._t0 = ego_state.time_point.time_s
        t = ego_state.time_point.time_s - self._t0
        faulted = self._fault != 'none' and t >= self._t_fault
        v0 = ego_state.dynamic_car_state.center_velocity_2d.x
        # nominal (possibly faulted) plan
        if faulted and self._fault == 'blind':
            # IDMPlanner reads only history.current_state and traffic_light_data
            empty = DetectionsTracks(TrackedObjects([]))
            blind = SimpleNamespace(history=SimpleNamespace(current_state=(ego_state, empty)),
                                    traffic_light_data=current_input.traffic_light_data, iteration=current_input.iteration)
            plan = self._idm.compute_planner_trajectory(blind)
        else:
            plan = self._idm.compute_planner_trajectory(current_input)
        self._idm._policy.target_velocity = min(self._idm._policy.target_velocity, ODD_V)   # ODD cap (all conditions)
        if faulted and self._fault == 'stale':
            if self._stale_v is None:
                self._stale_v = v0
            plan = self._path_traj(ego_state, [self._stale_v] * 81)
        t1 = ego_state.time_point + TimePoint(int(0.1 * 1e6))
        v1 = plan.get_state_at_time(t1).dynamic_car_state.center_velocity_2d.x if t1 <= plan.end_time else v0
        a_plan = (v1 - v0) / 0.1
        rec = dict(step=self._step, t=round(t, 3), v=round(v0, 3), a_plan=round(a_plan, 3), faulted=bool(faulted))
        out = plan
        if self._tsmx:
            in_odd = 0 <= v0 <= ODD_V and -8 <= a_plan <= 2
            rec['odd'] = bool(in_odd)
            if self._mrm is not None:
                if v0 <= 0.05:
                    self._mrm = None            # standstill: release, re-check the nominal plan below
                else:
                    rec['mode'] = 'MRM'
            if self._mrm is None:
                objs = self._objects(ego_state, observation)
                rec['n_obj'] = len(objs)
                stale_age = t - self._t_fault if (faulted and self._fault == 'stale') else 0.0
                if self._contract and stale_age > 0.15:
                    # B1 freshness: the plan's generation time is frozen at the hang -> REJECT regardless of geometry/ODD
                    self._latch(rec, t, v0, ego_state)
                    rec['b1'] = 'freshness'
                elif in_odd and self._monitor == 'rss':
                    ok = rss_ok(max(0.0, v0), objs)
                    rec['rss'] = bool(ok)
                    if ok:
                        rec['mode'] = 'NOMINAL'
                    else:
                        # proper response of the baseline: brake (b = 4, j = 4, cid 5) until standstill, uncertified
                        self._mrm = (self._step, 5, t, None)
                        rec['mode'] = 'MRM'; rec['mrm_cid'] = 5; rec['mrm_uncertified'] = True
                elif in_odd:
                    global _DUMP
                    _DUMP = (self._dump, self._step, round(t, 3)) if self._dump else None
                    try:
                        cid, tr = certify(max(0.0, v0), a_plan, objs)
                    finally:
                        _DUMP = None
                    rec['cid'] = cid
                    if cid is not None:
                        self._last_cid = cid
                        self._backup = (t, tr.rows, cid)          # certified tail, origin = this decision epoch
                        rec['mode'] = 'NOMINAL'
                    else:
                        self._latch(rec, t, v0, ego_state)
                else:
                    rec['mode'] = 'PASS_OOD'
            if self._mrm is not None:
                _, mcid, origin, rows = self._mrm
                if rows is not None:
                    # replay the certified trajectory in its ORIGINAL phase (no restart, no timestamp refresh)
                    rec['mrm_phase'] = round(t - origin, 3)
                    out = self._path_traj(ego_state, rows_speeds(rows, t - origin))
                else:                                          # outside the B4 envelope: surrogate brake, reported
                    a_now = ego_state.dynamic_car_state.center_acceleration_2d.x
                    out = self._path_traj(ego_state, mrm_speeds(max(0.0, v0), a_now, mcid))
        if self._log:
            with open(self._log, 'a') as fh:
                fh.write(json.dumps(rec) + '\n')
        self._step += 1
        return out
