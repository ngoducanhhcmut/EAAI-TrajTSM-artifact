# W9b: full-packet replay at +0.1 s; golden complete, TSM RTL replay pending

Coverage: 150 validation scenes visited; 5119 W7-eligible frames, 3040 ODD frames/source; scenes with admissions H/T = 143/143.
T reuses saved RQ1 `../sw/eval_trainval/out/pred_hw_new.npy`, matched by `dataset.npz` token; missing tokens 0. No W9a shards were present.
H uses ego-pose future positions at 0.5/1.0 s; both use manuscript eq. plannerpacket at +0.1 s; no velocity clipping.
Continuous independent H/T histories reset only per scene, at first ODD admission; no preload. Non-ODD intervals retain command-driven service history.
Assumed schedule (not measured): planner 40 ms, firmware 5 ms, transfer 35 ms; admission +80 ms, delivery +99 ms, apply/ACK +100 ms.
The 19 ms admission-to-delivery allowance accommodates the stated 1,874,999-cycle deadline at 100 MHz; transport/clock assumptions remain unvalidated.
Packet `compute=5000` retains the golden Plan default (limit 10000); its physical-unit mapping is unresolved. Wall-time schedule is a separate assumption. Sequence/IDs increase; CRC uses golden ABI.
Snapshot timestamp and generated timestamp are tr; apply=tr+100000 us; common snapshot IDs; context-bound lease expires at tr+500000 us.
LIDAR_TOP ego_pose spacing median/p95/max: 49788/50351/149857 us.
Ego at tc uses irregular central pose differences and linear interpolation; acceleration uses three-point differences. Offline future poses are used, not CAN measurements.
Executor idealization: command-tail tracking between measurements, ACK at apply (20 ms after issue). Each admission reanchors measured ego; physical tracking is not established.
Every 100 ms service plus explicit apply/ACK calls the unmodified system; no-packet timeouts/freeze checks and lease/backup history remain active.
Packets use dataset keyframes, not synthetic 10 Hz plans: ODD packet gap median/max 499890/14149694 us. No-packet service breaks recovery streaks; L0 occupancy is zero.
Objects use W7 corridor projection, causal previous/current annotation velocity; unknown velocity retains raw input and withholds certificate, failing closed.
Object velocity difference chain min/mean/max: 398234/501122.2/14449943 us; latest input is tr, VA age to checked tc is 80000 us.
VA is W7 reduce_neg with parameterized latency, no rear drop; common cover spans maximum legal live/plan tail plus bridge. No range clipping.
Lead scalar uses nearest conservative front bumper from that world; absent front is a stationary sentinel at station 9999 m (ABI lacks absence bit).
Persistent arc-length station offsets retain scalar history while reference axes rotate per frame; lateral dynamics are abstracted.

| Source | Attempts | B1 admitted | System accepted | Issued fallback | Backup | Mitigation | HOLD |
|---|---:|---:|---:|---:|---:|---:|---:|
| H | 3040 | 2026 | 1252 | 441 | 0 | 1320 | 27 |
| T | 3040 | 1933 | 427 | 1251 | 0 | 1325 | 37 |

Admission reason-code histogram:

- H: {"ego_live": 540, "ftti_budget": 38, "no_backup": 524, "ok": 1252, "range_schema": 474, "splice": 155, "timeout": 57}
- T: {"ego_live": 540, "ftti_budget": 11, "no_backup": 202, "ok": 427, "range_schema": 567, "splice": 1232, "timeout": 61}

Supervisor occupancy in transactions (not wall time), including no-packet service:

- H: {"HOLD": 3306, "L0": 0, "L1": 3489, "L2": 6913, "L3": 9435, "RECOVERY": 1252}; commit results {"committed": 1252, "ego_live": 5408, "no_pending": 17735}
- T: {"HOLD": 3062, "L0": 0, "L1": 1252, "L2": 10249, "L3": 9405, "RECOVERY": 427}; commit results {"committed": 427, "ego_live": 5368, "no_pending": 18600}

Registered W7 oracle is unchanged, including its +0.5 s object offset; applying its labels to +0.1 s packets has an epoch mismatch. Aligned labels are additionally reported below.
Rates are percent, scene-bootstrap 95% percentile intervals, 2000 draws, seed 20261104; oracle UNKNOWN H/T = 120/170, excluded from FA/FR denominators.

| Source/comparator | Acceptance | FR / SAFE | FA / UNSAFE |
|---|---|---|---|
| H registered | 1252/3040 = 41.184% [36.712, 45.476] | 1427/2673 = 53.386% [48.711, 57.989] | 3/247 = 1.215% [0.000, 3.020] |
| T registered | 427/3040 = 14.046% [12.095, 16.126] | 2208/2634 = 83.827% [81.567, 85.913] | 1/236 = 0.424% [0.000, 1.415] |
| H aligned +0.1 s | 1252/3040 = 41.184% [36.712, 45.476] | 1483/2731 = 54.302% [49.589, 59.042] | 1/189 = 0.529% [0.000, 1.695] |
| T aligned +0.1 s | 427/3040 = 14.046% [12.095, 16.126] | 2282/2709 = 84.238% [81.966, 86.313] | 0/161 = 0.000% [0.000, 0.000] |

Absolute encoding error versus measured ego at tr+0.1 s; mean/p95/max:
| Source | Position m | q-prime error m/s | q-double-prime error m/s² | >16 cm / >20 cm/s / either | B2 failures |
|---|---|---|---|---|---|
| H | 0.007645/0.020789/0.070546 | 0.063144/0.182078/0.444570 | 1.641572/5.316923/21.314364 | 0/102/102 | 687 |
| T | 0.037671/0.087751/1.000876 | 0.378139/0.888880/9.968954 | 1.839650/5.531650/20.641520 | 61/1721/1721 | 2209 |
Error threshold exceedance is distinct from B2: B2 compares the complete propagated live uncertainty tube; acceleration has no ±20 cm/s splice threshold.
Scene-0103: 35 consecutive RTL planner outputs (`../tb/e2e/results/wp_rtl_s00.txt` … `wp_rtl_s34.txt`), token mapping `../sw/golden_spec/summary.csv`; 207 physical TSM jobs.
These available RTL dumps differ from saved RQ1 hw_new by max 0.026161671 m; exact revision equivalence is unresolved. Dumps are used as requested, with hashes retained.
RTL subset: first 300 admission attempts in validation sequence order (H), including ACK/service history: 2513 jobs; resets only between scenes.
All expected response/command/ingress/supervisor/event bits come from golden and gen_sequences command projection; manifests include full inputs and planner dump hashes.
Independent analytic quadratic/B1/B2 check and complete golden bit regeneration: {"analytic_quadratic_and_b1_b2": true, "cosim_0103": {"accepted": 5, "all_bits_regenerated_exactly": true, "committed": 5, "jobs": 207}, "replay_rtl_subset": {"accepted": 142, "all_bits_regenerated_exactly": true, "committed": 142, "jobs": 2513}}.
Icarus compile exit 9; 0 jobs simulated; engine.sv lines 299–301 syntax errors. No TSM RTL agreement claimed.
Measured extraction/augmentation/replay times: 93.74/25.41/428.06 s; four detached workers; free C: start/end 14.171/13.095 GiB.
Reproduce: `py -3.9 -B prepare.py`, `augment.py`, `replay.py`, `check.py`, `smoke.py`, `finalize.py` (paths under this directory); replay also supports four `--worker i 4` processes plus `--shards` aggregation.
Claude: from `tsmx_hw/tb/integ` in WSL, use existing r17 binary:
```sh
./obj_2/Vtb_m_tsmx_top +FILE=../../eval_nuscenes/w9b/cosim_0103.mem +LIMIT=207 +ALLOW_INACTIVE > ../../eval_nuscenes/w9b/verilator_cosim_0103.log 2>&1
./obj_2/Vtb_m_tsmx_top +FILE=../../eval_nuscenes/w9b/replay_rtl_subset.mem +LIMIT=2513 +ALLOW_INACTIVE > ../../eval_nuscenes/w9b/verilator_replay_rtl_subset.log 2>&1
```
Limitations: conditional firmware/executor timing, pose-derived open-loop state, scalar coordinate abstraction and original GT-track hold assumptions. These artifacts establish a replay chain, not physical closed-loop safety.
