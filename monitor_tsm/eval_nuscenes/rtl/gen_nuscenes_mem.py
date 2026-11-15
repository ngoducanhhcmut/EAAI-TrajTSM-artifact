"""W7r physical reset/admission jobs; run with Python >=3.10, -B.

Encoding references (paths relative to tsmx_hw):
tb/integ/gen_sequences.py:40-55 request/health; :56-70 command projection;
:75-84 reset, request, response, command, ingress, supervisor, event concatenation.
golden/tsmx_golden/model.py:32-79 signed ABI/ego/plan/packet/world;
:79-98 lane/context/certificate; :114-145 ingress/event/response/command.
Each job starts at Supervisor() (model.py:570-578), real packet/certificate
(model.py:193-214,544-547), now=ego.t, generated=apply=now, plan state=ego
(model.py:249-256,330-347). Zero delay preserves the exact W7 ego state;
count=2, compute=5000, tail=15 are Plan defaults (:201-204). Lease=500000
(:560-568); no ACK, no hidden state. System checks remain enabled (:702-789).
W7 input semantics: eval_nuscenes/run_w7.py:302-334, including invalid raw
objects (not removed); legal objects already include latency propagation.
VA: eval_nuscenes/w7_secondary.py:52-86; proof/adapter_lemmas.py:4-19,42-64.
"""
import ast
import hashlib
import json
import sys
import time
from collections import Counter
from dataclasses import asdict
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
HW = HERE.parents[1]
sys.path[:0] = [str(HW / 'tb/integ'), str(HW / 'golden')]
import gen_sequences as enc
g = enc.g


def load_reduce():
    # Execute only the verbatim adapter function; importing its module loads numpy.
    tree = ast.parse((HW / 'eval_nuscenes/w7_secondary.py').read_text())
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'reduce_neg')
    env = dict(Motion=g.Motion, LAT=500000, S=g.S,
               fixed=lambda x: int(round(float(x) * g.S)))
    exec(compile(ast.Module(body=[fn], type_ignores=[]), 'w7_secondary.py', 'exec'), env)
    return env['reduce_neg']


def encode(e, objects, lane, index):
    p = g.Plan(index + 1, e, e.t, e.t, e.x, e.v, e.a)
    d = dict(now=e.t, ego=e, pkt=g.packet(p),
             cert=g.certify(p, e.t + 500000, objects, lane), objects=objects, lane=lane)
    ns, o = g.tsmx_cycle(g.Supervisor(), d)
    bits = enc.cat([(1, 1), (enc.request(d), 44673),
                    (enc.record(g.pack_top_rsp(o), 38), 38),
                    (enc.command(ns, o, d), 1897),
                    (enc.record(g.pack_ingress(ns.ingress), 332), 332),
                    (g.MODES.index(ns.mode), 3), (ns.good, 2), (ns.fault_latched, 1),
                    (bool(ns.pending), 1), (bool(ns.backup), 1), (ns.events_lost, 32),
                    (enc.record(g.pack_event(ns.events[-1]), 1056), 1056)])
    return f'{bits:012010x}\n', o


def main():
    start = time.monotonic()
    source = HW / 'eval_nuscenes/rtl_cases.jsonl'
    frames = [json.loads(x) for x in source.read_text().splitlines()]
    reduce_neg = load_reduce()
    jobs = {'nuscenes': [], 'nuscenes_va': []}
    meta = {k: [] for k in jobs}
    mismatches = []
    for frame in frames:
        for label, case in frame['plans'].items():
            i = len(jobs['nuscenes'])
            e = g.Ego(**case['ego'])
            objects = tuple(g.Motion(**x) for x in case['objects'])
            lane = tuple(case['lane'])
            trajectories = [(cid, g.b4_mrmgen(e.x, e.v, e.a, cid))
                            for cid in range(16) if g.LIBRARY[cid][1]]
            horizons = {cid: tr.rows[-1][0] - tr.rows[0][0]
                        for cid, tr in trajectories if tr.accept}
            horizon = max(horizons.values(), default=0)
            # Invalid-domain W7 cases are raw for ALL objects (run_w7.py:308-309).
            # Otherwise VA is identity and the stored list is already propagated.
            raw_case = not case['propagation_done']
            records = [dict(x=o.x/g.S, v=o.v/g.S, length=o.length/g.S) for o in objects]
            def va_objects(h):
                if not raw_case:
                    return objects
                raw = reduce_neg(records, h, False)
                return g.propagated_objects(raw, 500000, 0)
            va = va_objects(horizon)
            per_cid = next((cid for cid, tr in trajectories if tr.accept and
                            g.b3_geom(tr, va_objects(horizons[cid]), lane).accept), 15)
            for name, world in [('nuscenes', objects), ('nuscenes_va', va)]:
                line, out = encode(e, world, lane, i)
                jobs[name].append(line)
                decision = dict(accept=out['accept'], cid=out['candidate'])
                expected = {k: case['expected'][k] for k in ('accept', 'cid')}
                same = decision == expected
                row = dict(job=i, scene=frame['scene'], token=frame['token'], plan=label,
                           w7_expected=case['expected'], golden_system=decision,
                           response=out, matches_w7=same, reset=True,
                           ego=case['ego'], objects=[asdict(o) for o in world], lane=case['lane'],
                           adapter_errors=case['adapter_errors'])
                if name.endswith('_va'):
                    row.update(cover_horizon_us=horizon, candidate_horizons_us=horizons,
                               per_candidate_va_cid=per_cid,
                               max_cover_cid=g.select_world(e, world, lane)[0])
                if not same:
                    row['mismatch_reason'] = ('VA changes object adapter; ' if name.endswith('_va') else '') + \
                        'tsmx_cycle admission reason=' + out['reason'] + \
                           '; accept is packet admission, cid is live-world fallback selection (model.py:736-770)'
                    mismatches.append(dict(corpus=name, **row))
                meta[name].append(row)
    summary = dict(frames=len(frames), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), corpora={})
    for name in jobs:
        (HERE / (name + '.mem')).write_text(''.join(jobs[name]), encoding='ascii')
        counts = {}
        for label in 'HTU':
            rows = [r for r in meta[name] if r['plan'] == label]
            accepts = sum(r['golden_system']['accept'] for r in rows)
            counts[label] = dict(jobs=len(rows), accepts=accepts, rejects=len(rows)-accepts,
                                w7_accepts=sum(r['w7_expected']['accept'] for r in rows),
                                fallback_accepts=sum(r['golden_system']['cid'] != 15 for r in rows))
        summary['corpora'][name] = dict(jobs=len(jobs[name]), counts=counts,
            mismatches=sum(not r['matches_w7'] for r in meta[name]),
            cid_mismatches=sum(r['golden_system']['cid'] != r['w7_expected']['cid'] for r in meta[name]),
            reasons=dict(Counter(r['response']['reason'] for r in meta[name])))
        (HERE / (name + '.json')).write_text(json.dumps(dict(jobs=meta[name]), indent=2))
    summary.update(adapter_error_plans=sum(bool(r['adapter_errors']) for r in meta['nuscenes']),
                   negative_speed_plans=sum(any(o['v'] < 0 for o in r['objects']) for r in meta['nuscenes']),
                   va_per_candidate_vs_cover_differences=sum(r['per_candidate_va_cid'] != r['max_cover_cid'] for r in meta['nuscenes_va']),
                   va_rear_origin_unresolved=sum(r['golden_system']['cid'] != 15 and
                       any(o['v'] < 0 and o['x'] <= 0 and o['x'] > r['ego']['x'] for o in original['objects'])
                       for r, original in zip(meta['nuscenes_va'], meta['nuscenes'])),
                   seconds=time.monotonic()-start)
    (HERE / 'mismatches.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in mismatches))
    (HERE / 'crosscheck.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
