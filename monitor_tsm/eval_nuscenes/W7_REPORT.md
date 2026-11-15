# W7 — nuScenes trainval, open-loop

Status: COMPLETE; T = checkpoint W4A8, no GT substitution.
Frames: 29049/29049 eligible; 34149 keyframes; 850 scenes.
Ego v/a are central-difference estimates from ego_pose; not CAN measurements.
ODD coverage: 60.05% [58.37, 61.90] (17445/29049).
Coverage over all keyframes: 51.08%.

| Plan | Acceptance | False reject / SAFE | False accept / UNSAFE | Recall U |
|---|---|---|---|---|
| H | 37.81% [35.29, 40.43] (6596/17445) | 57.89% [55.11, 60.58] (8986/15523) | 0.20% [0.00, 0.52] (2/979) | — |
| T | 36.24% [33.69, 38.88] (6322/17445) | 57.97% [55.15, 60.76] (8718/15038) | 0.25% [0.00, 0.61] (2/794) | — |
| U | 29.57% [26.97, 32.27] (2873/9717) | 67.14% [64.22, 69.87] (5858/8725) | 0.60% [0.19, 1.15] (6/992) | 99.40% [98.85, 99.81] (986/992) |

CI: scene bootstrap, 2000 replicates, seed 20261104. N/A means no denominator.
Recall U uses oracle-UNSAFE U only; synthetic U is not automatically unsafe.
Adapter errors: 5922; overflow: 0; oracle UNKNOWN H/T/U: 943/1613/0.
Speed and object-count strata, with all CIs: results/summary.json (by_speed, by_object_count).
ASSUMPTION: axis-aligned center coordinates; combined half-length=(4.8+object length)/2; ego_pose treated as center.
Oracle: independent float 1 ms, GT object interpolation to 3 s then hold; lost tracks hold last pose.
Golden: constant nonnegative longitudinal object speed; invalid observations reject without clipping.
Oracle checks until stop; golden additionally holds 2 s. No closed-loop safety claim.

False accepts: 10. Every case, including token and GT mismatch reason: [false_accepts.jsonl](results/false_accepts.jsonl).
- scene-0043 / 4b57dce76aaa48fe82ae6268a90f70a0 / U: front_object_lags_constant_velocity_prediction; object=7dd37174c33c4e3eb01cd2ae155785f5, t=2.658s, GT-constant-v=-1.791m, selected-profile oracle margin=-1.557m.
- scene-0219 / 07d09f687a7c494fa8237c511fea0fe8 / U: rear_object_advances_beyond_constant_velocity_prediction; object=2e7550b974304c72a0e7b37f9587d83f, t=0.500s, GT-constant-v=+0.037m, selected-profile oracle margin=-0.024m.
- scene-0520 / b999707d600d4b0db25404e6f41085aa / U: front_object_lags_constant_velocity_prediction; object=87038009ca9147fdbe673d4b7e3d39ad, t=2.566s, GT-constant-v=-5.224m, selected-profile oracle margin=-3.298m.
- scene-0542 / e0d475c67668479fa244ceaffa3d47f7 / H: rear_object_advances_beyond_constant_velocity_prediction; object=87ff955e97fa4e34b373c98f7b094d4b, t=0.500s, GT-constant-v=+0.112m, selected-profile oracle margin=-0.082m.
- scene-0560 / cb277e7166c94ffcbc2177c695a5c108 / U: front_object_lags_constant_velocity_prediction; object=a1fc928f53bf4172ae8fec779bcf6523, t=2.832s, GT-constant-v=-4.531m, selected-profile oracle margin=-2.731m.
- scene-0560 / ed106be96a684bce9379a75dac61ed54 / T: front_object_lags_constant_velocity_prediction; object=4203ed2c6c004b308a6af62db19d2eb0, t=2.376s, GT-constant-v=-2.216m, selected-profile oracle margin=-1.817m.
- scene-0564 / 0e6efc712c9e47ac95d5dd133007c3c9 / H: rear_object_advances_beyond_constant_velocity_prediction; object=50be5ba3484d43299a1cf45ba4dc3af6, t=2.385s, GT-constant-v=+3.607m, selected-profile oracle margin=-1.424m.
- scene-0564 / 0e6efc712c9e47ac95d5dd133007c3c9 / T: rear_object_advances_beyond_constant_velocity_prediction; object=50be5ba3484d43299a1cf45ba4dc3af6, t=2.127s, GT-constant-v=+3.061m, selected-profile oracle margin=-1.523m.
- scene-1108 / f966614ccaf44d99baa7f1d8f1b7d4b3 / U: front_object_lags_constant_velocity_prediction; object=9f8575884ce14b4e8d2debfc809e12f6, t=1.580s, GT-constant-v=-0.237m, selected-profile oracle margin=-0.206m.
- scene-1109 / 629323e575754fe2815ed5926581565e / U: oracle_hold_after_3s; object=9c17fc146d1c410291ff706caa22cc36, t=3.417s, GT-constant-v=-4.606m, selected-profile oracle margin=-3.423m.

Measured runtime across invocations (load, evaluation, summary): 6763.0 s.
RTL vectors: 300 frames, all available H/T/U inputs per frame, in rtl_cases.jsonl.
Pilot: `python -B tsmx_hw/eval_nuscenes/run_w7.py --limit 200`.
Reproduce/resume full: `python -B tsmx_hw/eval_nuscenes/run_w7.py` (automatic bounded child batches).
One bounded batch: `python -B tsmx_hw/eval_nuscenes/run_w7.py --batch`.
Protocol: PROTOCOL.md; provenance hashes and full counts in results/summary.json.
Checkpoint compatibility AMENDMENT A1: missing wp_proj tensors set to zero; board bit-exactness unverified.
Not done here: RTL/board execution (vectors provided for Claude).

Strata: acceptance H/T/U (%), false-accept counts H/T/U; full subgroup CIs in summary.json.

| Stratum | ODD frames | Acceptance H/T/U | False accepts H/T/U |
|---|---:|---|---|
| v m/s 0-2 | 4117 | 23.7/16.8/26.3 | 2/1/2 |
| v m/s 2-5 | 3685 | 35.1/34.8/31.0 | 0/0/3 |
| v m/s 5-10 | 9643 | 44.9/45.1/30.7 | 0/1/1 |
| objects 0 | 2039 | 97.6/97.3/N/A | 0/0/0 |
| objects 1-4 | 13657 | 32.7/30.8/33.1 | 2/2/5 |
| objects 5-16 | 1746 | 8.2/7.8/11.9 | 0/0/1 |
| objects 17+ | 3 | 0.0/0.0/0.0 | 0/0/0 |

Posthoc evidence for EVERY false accept: [false_accept_evidence.jsonl](results/false_accept_evidence.jsonl); metrics unchanged.
Evidence categories: {"front_object_lags_constant_velocity_prediction": 5, "rear_object_advances_beyond_constant_velocity_prediction": 4, "oracle_hold_after_3s": 1}.
Prior serial attempt observed a 36232.422 s wall-time gap including overnight OS suspension; excluded from fresh full runtime and retained as serial_partial_*.
Validation: exact pilot comparison, 808-frame serial prefix, and 300-frame RTL replay; results/audit.json and evidence_summary.json.
SI-to-golden encoding uses Python round(value*1e6), with no saturation; original SI plan states remain in frames.jsonl.
An event-free bootstrap can yield CI [0,0]; this is not an upper bound on unseen failure probability.
Offline estimator lookahead: T/TSM object velocities use prev/next annotations; no GT waypoint target. See [AMENDMENT A7](AMENDMENT_A7.md).
Optional evidence/report rebuild after core run: `python -B tsmx_hw/eval_nuscenes/explain_false_accepts.py`.
