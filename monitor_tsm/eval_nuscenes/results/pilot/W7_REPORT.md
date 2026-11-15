# W7 — nuScenes trainval, open-loop

Status: INCOMPLETE; T = checkpoint W4A8, no GT substitution.
Frames: 200/29049 eligible; 34149 keyframes; 850 scenes.
Ego v/a are central-difference estimates from ego_pose; not CAN measurements.
ODD coverage: 72.50% [54.27, 89.38] (145/200).
Coverage over all keyframes: 0.42%.

| Plan | Acceptance | False reject / SAFE | False accept / UNSAFE | Recall U |
|---|---|---|---|---|
| H | 38.62% [15.56, 60.97] (56/145) | 54.84% [29.59, 82.05] (68/124) | 0.00% [0.00, 0.00] (0/21) | — |
| T | 42.07% [21.74, 61.86] (61/145) | 51.20% [29.59, 75.44] (64/125) | 0.00% [0.00, 0.00] (0/19) | — |
| U | 34.57% [0.00, 65.12] (28/81) | 51.72% [26.44, 100.00] (30/58) | 0.00% [0.00, 0.00] (0/23) | 100.00% [100.00, 100.00] (23/23) |

CI: scene bootstrap, 2000 replicates, seed 20261104. N/A means no denominator.
Recall U uses oracle-UNSAFE U only; synthetic U is not automatically unsafe.
Adapter errors: 57; overflow: 0; oracle UNKNOWN H/T/U: 0/1/0.
Speed and object-count strata, with all CIs: results/summary.json (by_speed, by_object_count).
ASSUMPTION: axis-aligned center coordinates; combined half-length=(4.8+object length)/2; ego_pose treated as center.
Oracle: independent float 1 ms, GT object interpolation to 3 s then hold; lost tracks hold last pose.
Golden: constant nonnegative longitudinal object speed; invalid observations reject without clipping.
Oracle checks until stop; golden additionally holds 2 s. No closed-loop safety claim.

False accepts: 0. Every case, including token and GT mismatch reason: [false_accepts.jsonl](results/false_accepts.jsonl).

Measured runtime across invocations (load, evaluation, summary): 88.8 s.
RTL vectors: 145 frames, all available H/T/U inputs per frame, in rtl_cases.jsonl.
Pilot: `python -B tsmx_hw/eval_nuscenes/run_w7.py --limit 200`.
Reproduce/resume full: `python -B tsmx_hw/eval_nuscenes/run_w7.py` (automatic bounded child batches).
One bounded batch: `python -B tsmx_hw/eval_nuscenes/run_w7.py --batch`.
Protocol: PROTOCOL.md; provenance hashes and full counts in results/summary.json.
Checkpoint compatibility AMENDMENT A1: missing wp_proj tensors set to zero; board bit-exactness unverified.
Not done here: RTL/board execution (vectors provided for Claude).
