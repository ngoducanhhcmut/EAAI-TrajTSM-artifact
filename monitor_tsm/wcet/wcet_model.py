"""RTL state-count envelopes; measurements are checks, never fitted constants.

Run: py -3.13 tsmx_hw/wcet/wcet_model.py [--grid]
Normal-completion WCET is deliberately UNRESOLVED: permitted sources omit
codec, health_lane, supervisor, recorder and arbiter implementations.
The numeric response bound is the engine's independent deadline mechanism.
All generated reports stay beside this script. No simulator is needed.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
OUT = Path(__file__).resolve().parent
ROOT = OUT.parent
K_MAX = 93
DEADLINE = 1_874_999 + 1  # engine:629,1124-1136; conservative edge convention
FILES = ("reg300", "apos", "worst2", "worst_apos")


def program_counts():
    """Count explicit f_uprog entries, with END; MUL=fetch+6 execute cycles.

    arith:244-379,626-692. Prologues have no extra END cycle (look-ahead).
    """
    source = (ROOT / "rtl/arith/m_tsmx_arith.sv").read_text(encoding="utf8")
    result = {}
    for name, body in re.findall(r"LPARA_P_(\w+): case \(w_pc\)(.*?)endcase", source, re.S):
        kinds = re.findall(r"6'd\d+:\s*w_r=f_u\(LPARA_K_(\w+)", body)
        result[name] = dict(entries=len(kinds), mul=kinds.count("MUL"),
                            cycles=2 * (len(kinds) + 1) + 5 * kinds.count("MUL"))
        if name == "RAMP":
            prefix = kinds[:kinds.index("ENDVN") + 1]
            result["VN"] = dict(entries=len(prefix), mul=prefix.count("MUL"),
                                cycles=2 * len(prefix) + 5 * prefix.count("MUL"))
    return result


P = program_counts()


def div(w):
    # arith:995-1013: W/2 iterations + finalization + consumer sampling.
    return w // 2 + 2


def root_extra(h):
    # arith:808-821: halve [lo,hi] until width<=1, then full RAMP rerun.
    n = (max(h, 1) - 1).bit_length()
    return n * (1 + P["VN"]["cycles"] + 1) + 1 + P["RAMP"]["cycles"] + 1


def arith():
    # Four boundary clocks cover public accept, SETUP, RESP drain and rearm.
    ramp, disp, dint = (P[k]["cycles"] for k in ("RAMP", "DISP", "DINT"))
    point = 2 * (2 + 4 + 2) + 2 * (2 + 4 + P["PT23"]["cycles"]) + 3 * (2 + P["PTX"]["cycles"])
    side = 1 + 4 + disp + 1 + div(128)
    return {0: 4, 1: 4 + 1 + div(160), 2: 4 + 8 + disp + 1 + div(128),
            3: 4 + 6 + dint + 1 + 2 * div(96),
            4: 4 + point + 7 * (2 * side + 1), 5: 4,
            6: 4 + 10 + ramp + 1, 7: 4 + 10 + ramp + 1 + 2 * div(160), 8: 4}


A = arith()
SU = 14 + 8 * 4  # START, S1..S12, FIN; eight waits, <=4 extra each
INFL = 7 + 5 * 4  # START, I1..I5, FIN; five waits


def gen(rows):
    # mrmgen:185-268. Charge full work even to terminal row (safe overcount).
    # At most one stop search per interval side over a trajectory: after clipping
    # to zero, PREP chooses zero acceleration/jerk and speed stays zero.
    return 4 + rows * (4 + 2 * A[5] + 2 * A[7]) + 2 * root_extra(100_000)


def geom(rows, objects):
    # geom:312-410. One acceleration event per actor over the whole horizon.
    cells = max(rows - 1, 0)
    cell = 1 + 1 + INFL + 1 + objects * (1 + 1 + SU + 1 + 1)
    split = objects * (1 + SU + 1)
    return 8 + 2 * objects + cells * cell + split


def sweep(rows, objects, candidates=16, pairs=2, bridge=False):
    # sweep:104-145: accept/RESP + batches*(two launches, done capture/base).
    # Serialize producer/consumer envelopes: overlap can only reduce elapsed time.
    batches = (candidates + pairs - 1) // pairs
    return 2 + batches * (4 + geom(rows, objects) + (0 if bridge else gen(rows)))


def math_costs(objects):
    # math:217-337,338-379. Private, drained arithmetic; A includes handshakes.
    return dict(reaction=4 + 2 * A[3] + 2 * A[4],
                nominal_propagation=4 + 32 + 1 * (1 + 2 * A[3]),
                propagation=4 + 32 + objects * (1 + 2 * A[3]),
                bridge=4 + 2 * A[3],
                replay=4 + 641 + 640 * (A[5] + A[7] + root_extra(20_000)))


def resolved_envelope(rows=K_MAX, objects=32):
    """Numeric envelope of reviewed compute units, NOT an upper bound on total.

    All normal branches plus one late-hash-fault retry are charged together.
    Missing services must be added before calling this a completion bound.
    """
    return dict(fallback_and_tail=2 * sweep(rows, objects),
                late_hash_retry=sweep(rows, objects),
                duplicate_lanes=2 * sweep(rows, objects, 1, 1),
                nominal=sweep(rows, 1, 1, 1), bridge_geom=sweep(2, objects, 1, 1, True),
                math=sum(math_costs(objects).values()) + math_costs(objects)["replay"],
                ingress=2 + A[8], cert=4 * (1 + A[8]),
                splice=2 + 16 * A[3], sel=3 * 2,
                engine_glue=2 * 76)


def health_leaf():
    # health:67-83,125-153; bist:78-105. 129 endpoint capacity, 1024 words.
    # This is conditional on the omitted health_lane wiring having this topology.
    return 1024 + 10 + gen(129) + 2 + 2 * (129 + 4 + geom(129, 1))


def grid():
    sys.path.insert(0, str(ROOT / "golden"))
    from tsmx_golden.model import b4_mrmgen
    maximum = 0
    witnesses = []
    count = 0
    for v in range(0, 10_000_001, 1_000_000):
        for a in range(-8_000_000, 2_000_001, 500_000):
            for cid in range(16):
                traj = b4_mrmgen(0, v, a, cid, phase=0, limit=128)
                count += 1
                assert traj.accept, (v, a, cid, traj.reason)
                assert len(traj.rows) <= K_MAX, (v, a, cid, len(traj.rows))
                if len(traj.rows) > maximum:
                    maximum, witnesses = len(traj.rows), []
                if len(traj.rows) == maximum:
                    witnesses.append(dict(v=v, a=a, cid=cid, stop=traj.stop))
    return dict(evaluations=count, v_step=1_000_000, a_step=500_000,
                max_rows=maximum, witnesses=witnesses,
                purpose="finite-grid cross-check; analytical proof is in WCET.md")


def measurements():
    directory = ROOT / "tb/integ/vl_claude_r17_a8_apos"
    results, coverage = [], {}
    for name in FILES:
        jobs, timing = {}, {}
        for line_no, line in enumerate((directory / (name + ".txt")).read_text(encoding="utf8").splitlines(), 1):
            job = re.search(r"JOB (\d+) PASS cycles=(\d+)", line)
            tick = re.search(r"TIMING job=(\d+) fallback=([0-9a-fA-F]+) tail=([0-9a-fA-F]+) max_rows=(\d+) stream_hits=(\d+) objects=(\d+)", line)
            if job:
                key, cycles = map(int, job.groups())
                if key in jobs:
                    raise ValueError(f"Duplicate JOB {key} in {name}")
                jobs[key] = (cycles, line_no)
            if tick:
                key, fallback, tail, rows, hits, objects = tick.groups()
                if int(key) in timing:
                    raise ValueError(f"Duplicate TIMING {key} in {name}")
                timing[int(key)] = dict(fallback=fallback, tail=tail, rows=int(rows),
                                        stream_hits=int(hits), objects=int(objects), timing_line=line_no)
        assert jobs.keys() == timing.keys(), (name, "unpaired JOB/TIMING", jobs.keys() ^ timing.keys())
        coverage[name] = len(jobs)
        for key, (cycles, line_no) in jobs.items():
            t = timing[key]
            assert 0 <= t["objects"] <= 32 and 0 <= t["rows"] <= 129
            # Masks describe acceptance, not execution enables. Do not count bits
            # or omit tail on 0000: sweep:98,138 executes all sixteen regardless.
            terms = resolved_envelope(t["rows"], t["objects"])
            predicted = DEADLINE
            assert predicted >= cycles, (name, key, predicted, cycles)
            results.append(dict(file=name, job=key, job_line=line_no, **t, measured=cycles,
                                reviewed_units_envelope=sum(terms.values()),
                                predicted_response_bound=predicted, slack=predicted - cycles,
                                predicted_normal_completion="UNRESOLVED"))
    return results, coverage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--grid", action="store_true", help="also enumerate the permitted golden B4 grid")
    args = parser.parse_args()
    terms = resolved_envelope()
    jobs, coverage = measurements()
    summary = dict(status="FAIL: normal-completion WCET unresolved; reviewed envelope exceeds target",
                   K_max=K_MAX, P=2, G=2, M=32, candidates=16,
                   normal_completion_bound=None, reviewed_units_envelope=sum(terms.values()),
                   reviewed_terms=terms, response_bound=DEADLINE,
                   response_ms_100MHz=DEADLINE / 100_000,
                   response_ms_187_5MHz=DEADLINE / 187_500,
                   arith=A, programs=P, su=SU, inflation=INFL,
                   health_leaf_conditional=health_leaf(), coverage=coverage, jobs_checked=len(jobs),
                   min_slack=min(j["slack"] for j in jobs), max_slack=max(j["slack"] for j in jobs),
                   supplied_worst_ratio=947_263 / DEADLINE,
                   observed_worst=max(j["measured"] for j in jobs),
                   unresolved=["codec per-beat readiness and final-response latency",
                               "health_lane composition and auxiliary checks",
                               "supervisor, recorder, arbiter ready/response latency",
                               "i_cmd_ready and response consumption backpressure"],
                   interpretation="response checks validate watchdog bound only; no completion proof")
    if args.grid:
        summary["golden_grid"] = grid()
    (OUT / "results.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf8")
    with (OUT / "job_bounds.csv").open("w", newline="", encoding="utf8") as f:
        writer = csv.DictWriter(f, fieldnames=list(jobs[0]))
        writer.writeheader()
        writer.writerows(jobs)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
