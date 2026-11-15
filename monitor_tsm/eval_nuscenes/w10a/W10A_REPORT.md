# W10a: firmware encoding and complete validation replay
Selection rule fixed before W10a outcomes: maximize training T system ACCEPT subject to registered-oracle FA(T) and FA(H) rates each <= E0 (exact fractions). Undefined FA makes a candidate ineligible; E0 fallback. Ties E0/E1/E2. See immutable `PREREGISTRATION.md`; `selection.json` is sealed before validation.
Training: first 150 official trainval TRAIN scenes in name order; 444 saved stride-12 prediction tokens, 235 eligible ODD packets/source; continuous no-packet service between available packets. This sparse sample limits generalization.
E0: origin/0.5/1.0 s interpolating quadratic. E1: degree-2 LS q=beta*t+alpha*t^2, hard q(0)=0, unit residual weights on all four 0.5/1/1.5/2 s waypoints. E2: propagate measured snapshot x/v by 0.1 s using measured a (stop-clipped golden advance), command a=clip(E1 acceleration,-8,2). No velocity clipping; invalid measured snapshots remain invalid.
H waypoints are sweep-pose interpolations; T uses saved RQ1 hw_new arrays, token matched. E0 counts and derivative statistics match W9b exactly. All validation encodings use the same 3040 ODD attempts/source and original W7 registered oracle.

| Training | H ACCEPT | T ACCEPT | H FA/UNSAFE | T FA/UNSAFE | Feasible |
|---|---:|---:|---|---|---|
| E0 | 96 | 41 | 0/12 = 0.000% [0.000,0.000] | 0/12 = 0.000% [0.000,0.000] | True |
| E1 | 69 | 41 | 0/10 = 0.000% [0.000,0.000] | 0/12 = 0.000% [0.000,0.000] | True |
| E2 | 75 | 75 | 0/12 = 0.000% [0.000,0.000] | 0/12 = 0.000% [0.000,0.000] | True |

Chosen: **E2**, selected on training only. Validation cannot change the choice.

| Validation | ACCEPT/attempts | FA/UNSAFE | FR/SAFE |
|---|---|---|---|
| E0/H | 1252/3040 = 41.184% [36.568,45.527] | 3/247 = 1.215% [0.000,3.054] | 1427/2673 = 53.386% [48.823,58.269] |
| E0/T | 427/3040 = 14.046% [12.014,16.108] | 1/236 = 0.424% [0.000,1.342] | 2208/2634 = 83.827% [81.606,86.131] |
| E1/H | 990/3040 = 32.566% [28.664,36.364] | 3/230 = 1.304% [0.000,3.382] | 1642/2616 = 62.768% [58.747,67.053] |
| E1/T | 474/3040 = 15.592% [13.322,17.827] | 3/247 = 1.215% [0.000,2.554] | 2155/2626 = 82.064% [79.653,84.594] |
| E2/H | 999/3040 = 32.862% [29.004,36.600] | 4/271 = 1.476% [0.000,3.187] | 1691/2686 = 62.956% [58.983,67.151] |
| E2/T | 994/3040 = 32.697% [28.866,36.439] | 3/282 = 1.064% [0.000,2.713] | 1684/2675 = 62.953% [59.029,67.128] |

Validation tradeoff: H ACCEPT 1252 -> 999, FA 1.215% -> 1.476%; T ACCEPT 427 -> 994, FA 0.424% -> 1.064%. Training feasibility does not establish validation FA non-increase.
Intervals: 95% percentile scene bootstrap, 2000 draws, seed 20261104, all 150 scenes including empty scenes. Oracle UNKNOWN excluded from FA/FR denominators.
Registered W7 oracle retains its +0.5 s object offset despite encoded +0.1 s apply: an epoch mismatch, not an aligned safety claim.

| Chosen source | Attempts / B1 admitted / accepted / fallback / backup / mitigation / HOLD |
|---|---|
| H | 3040 / 2068 / 999 / 694 / 0 / 1323 / 24 |
| T | 3040 / 2068 / 994 / 697 / 0 / 1325 / 24 |

H admission reasons: `{"ego_live": 540, "ftti_budget": 40, "no_backup": 392, "ok": 999, "range_schema": 432, "splice": 578, "timeout": 59}`.
H occupancy in all transactions: `{"HOLD": 3218, "L0": 0, "L1": 2714, "L2": 8083, "L3": 9381, "RECOVERY": 999}`; oracle UNKNOWN=83.
T admission reasons: `{"ego_live": 540, "ftti_budget": 37, "no_backup": 398, "ok": 994, "range_schema": 432, "splice": 578, "timeout": 61}`.
T occupancy in all transactions: `{"HOLD": 2990, "L0": 0, "L1": 2769, "L2": 8397, "L3": 9245, "RECOVERY": 994}`; oracle UNKNOWN=83.

Absolute encoding errors vs measured apply ego, mean/p95/max (all encodings in summary.json):
| Chosen source | Position m | Velocity m/s | Acceleration m/s^2 | >16 cm / >20 cm/s / B2 reject |
|---|---|---|---|---|
| H | 0.006057/0.019433/0.089791 | 0.158102/0.494516/2.413687 | 1.659900/5.278622/21.398954 | 0/897/1424 |
| T | 0.006057/0.019433/0.089791 | 0.158102/0.494516/2.413687 | 1.768998/5.394411/21.126992 | 0/897/1424 |

Certification: unchanged TSM checks the bridge and chosen stopping tail from the encoded apply state in the supplied scalar world. It does not certify the planner waypoint trajectory; E2 constrains commanded acceleration only.
Freshness/freeze contract: planner completion owns seq/generated/snapshot/apply. Retry the original encoded packet without refreshing anchors, CRC or metadata. Stale snapshot => freshness; replay => sequence; no new sample >=300 ms => freeze_no_sample; unchanged encoded state >=300 ms plus >20 cm motion => freeze.
Existing verify/unit.py stale/frozen witnesses pass for E0/E1/E2 (golden only, witnesses.json); exact-quadratic LS, stop-clipped E2 and TransactionEncoder retry checks pass. New measured anchors can hide unchanged planner waypoints: ABI freeze checks cannot prove semantic liveness; transaction ownership is required.
Complete chosen validation set: 48790 jobs; eight canonical shard counts: 6130, 6128, 5978, 6148, 6148, 5978, 6128, 6152. Each shard owns whole scenes with independent H/T resets; no preloads or mid-sequence resets.
rtl_manifest.json lists scenes, sequence offsets and every golden expected decision; replay.jsonl retains complete golden input/output history. SHA256 hashes protect canonical and runnable batch files.
Existing obj_2 binary has a 3151-vector limit. run_rtl_shards.sh runs eight shard workers in parallel using complete-scene bounded batches; it never splits a retained-state sequence. Logs: tb/integ/vl_claude_r17_a8_apos/w10a_shard_<k>.txt plus .txt.done markers.
Claude: `bash eval_nuscenes/w10a/run_rtl_shards.sh` from tsmx_hw (or invoke by absolute path). check_rtl.py requires every indexed JOB PASS, completion/assertion summaries, successful markers and matching input hashes; then tallies proven golden decisions. Missing logs fail closed.
RTL pending supervisor. JOB PASS includes bit agreement and CSR cycles == observed TB latency; no golden absolute cycle prediction or RTL pass is claimed.
Assumptions retained: planner/firmware/transfer 40/5/35 ms; admission/delivery/apply 80/99/100 ms; ACK 20 ms after issue; 100 ms service; context lease 500 ms. compute=5000 physical units unresolved.
Limitations: offline future-pose ego estimates, ideal intermeasurement command tracking, open-loop measured reanchors, scalar corridor/local-axis abstraction and original held GT tracks. This is conditional replay, not physical closed-loop safety.
Detached golden workers <=4; resumed replay/export elapsed 1141.86 s (finishing checks and earlier extraction/training attempts excluded); C: free start/end 13.252/11.975 GiB (>=10). All writes under w10a; golden/RTL/TB/run_w7/manuscripts unchanged.
Reproduce: Python 3.9 -B prepare_train.py; witnesses.py; test_checker.py; run_eval.py (launch detached). Saved per-scene workers resume completed sequences. summary.json contains all counts, errors, hashes and training/validation metrics.
