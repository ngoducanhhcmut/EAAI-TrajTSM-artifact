# W9a3: RQ1 planner certification rerun

Status: COMPLETE. T = unchanged RQ1 hw_new encoder + RTL-equivalent GRU; no zero-filled wp_proj.
Gate reused without inference: 5419/5419 within 1e-5 m; 5416 exact; max |diff|=2.9802322387695312e-06 m; rebuilt-input discrepant frames=0.
ODD coverage: 17445/29049; 60.05% [58.37,61.90]; all-keyframe coverage=51.08%.

Table aligned, part 1 (count/denominator; percent [95% CI]).
|Variant|Acceptance|Aligned FR|Aligned FA|
|---|---|---|---|
|V0/H|6596/17445; 37.81% [35.29,40.43]|1912/5751; 33.25% [30.03,36.33]|296/2612; 11.33% [9.12,13.78]|
|V0/T|6342/17445; 36.35% [33.86,38.93]|1887/5566; 33.90% [30.59,37.13]|293/2505; 11.70% [9.46,14.26]|
|V0/U|2873/9717; 29.57% [26.97,32.27]|1789/3093; 57.84% [53.11,62.06]|117/672; 17.41% [11.99,23.24]|
|VA/H|9648/17445; 55.31% [52.50,58.21]|680/5751; 11.82% [9.96,13.95]|395/2612; 15.12% [12.61,18.02]|
|VA/T|9188/17445; 52.67% [49.78,55.60]|744/5566; 13.37% [11.25,15.68]|379/2505; 15.13% [12.51,18.04]|
|VA/U|5430/9717; 55.88% [52.75,59.00]|842/3093; 27.22% [23.20,31.39]|180/672; 26.79% [20.38,33.13]|
|VB/H|15880/17445; 91.03% [90.14,91.97]|91/5751; 1.58% [1.08,2.14]|2401/2612; 91.92% [89.71,93.97]|
|VB/T|15293/17445; 87.66% [86.34,88.97]|138/5566; 2.48% [1.81,3.21]|2290/2505; 91.42% [89.37,93.24]|
|VB/U|8179/9717; 84.17% [82.33,85.98]|286/3093; 9.25% [6.98,11.85]|501/672; 74.55% [67.55,81.28]|

Table aligned, part 2. Selected S/U/?/Tr; risk=U/(S+U); IP among labelable rejects.
|Variant|Selected S/U/?/Tr|Selected risk|IP|Rejection frequency|
|---|---|---|---|---|
|V0/H|2472/608/57/3459|608/3080|2316/4228|10849/17445|
|V0/T|2300/599/0/3443|599/2899|2212/4099|11103/17445|
|V0/U|572/229/0/2072|229/801|555/2344|6844/9717|
|VA/H|3340/775/116/5417|775/4115|2217/2897|7797/17445|
|VA/T|3063/753/0/5372|753/3816|2126/2870|8257/17445|
|VA/U|1070/379/0/3981|379/1449|492/1334|4287/9717|
|VB/H|--|--|211/302|1565/17445|
|VB/T|--|--|215/353|2152/17445|
|VB/U|--|--|171/457|1538/9717|

Registered oracle (V0), as W7:
|Plan|Acceptance|FR / SAFE|FA / UNSAFE|
|---|---|---|---|
|H|6596/17445; 37.81% [35.29,40.43]|8986/15523; 57.89% [55.11,60.58]|2/979; 0.20% [0.00,0.52]|
|T|6342/17445; 36.35% [33.86,38.93]|8988/15325; 58.65% [55.90,61.38]|5/914; 0.55% [0.00,1.32]|
|U|2873/9717; 29.57% [26.97,32.27]|5858/8725; 67.14% [64.22,69.87]|6/992; 0.60% [0.19,1.15]|

Count flow: eligible -> ODD -> generated -> V0 adapter-valid; aligned S/U/?/Tr.
H: 29049 -> 17445 -> 17445 -> 11523; 5751/2612/943/8139.
T: 29049 -> 17445 -> 17445 -> 11523; 5566/2505/1206/8168.
U: 29049 -> 17445 -> 9717 -> 5069; 3093/672/0/5952.
C: free bytes before full launch/end=14349537280/12429889536; >=10 GB before large writes.
Full W9a3 measured runtime=8156.172 s; prior W9a/W9a2=2011.610 s; subsequent accounting verification timed separately in summary.json.

Encoded-input check: accepted records=40077; sampled discrepancies=0; minimum margin=0.000804500 m (reserve included).
1 ms samples, encoded ego, V0/VA cid-specific adapted objects; tolerance 1e-6 m; stop +2 s hold.
Shared selection/adapter and finite sampling: regression evidence, not an independent continuous-time theorem check.
Runtime: 10167.782 s including failed/discarded attempts (5967.298 s); detached, four workers.
Runtime includes aggregation/hashing; final report/summary serialization excluded.
CI: 2,000 shared multinomial scene draws, seed 20261104, all 850 scenes.
A7 offline estimator lookahead retained; no online or closed-loop safety claim.
Acceptance covers all generated ODD plans; oracle denominators exclude UNKNOWN/TRUNCATED.
Deviations and execution details:
Reproduce/resume: `python -B plans_hw.py --workers 4`; shards flush each record.
Full precision, all report values, checks and source hashes: summary.json; per-plan evidence: replay_*.jsonl.
Every registered/aligned false accept, with scene/token/variant/plan and full oracle evidence: false_accepts.json.
Execution deviations (full list in summary.json): RQ1 source replaces W7 A1 planner; no other numerical or threshold change. RQ1 builder and current W7 both explicitly enable lane tokens; rebuilt RQ1 inputs checked against archived dataset. Validation gate inputs/predictions reused for identical full-run tokens. Original W7 H/U states and object adapter are replayed and asserted exactly equal. VB selected labels remain unaudited, matching manuscript Table aligned. Initial write-guard bytes-path bug stopped before inference; fixed and restarted; failed runtime included. Sequential input rebuild replaced by four resumable input builders; discarded-prefix elapsed time included. Windows null-device guard compatibility and run_models search path fixed during setup; no numerical changes. Encoder INT4xINT8 matmul uses exact float32 BLAS under protocol A2 bound and per-worker integer-kernel checks; all other hw_new operations unchanged. W9a3 supervisor revised gate to 1e-5 m; all 5419 W9a2 records reused without gate inference; every nonzero difference enumerated. Prior W9a/W9a2 measured runtime included once; restart gaps excluded. Prediction/replay shard recovery discards only an interrupted final line before resuming. W9a3 inference resumed after preloading NPZ arrays once per worker instead of rereading whole arrays per frame; no numerical operations changed; elapsed prior invocation included. Missing original checkpoint path: existing RQ1 parameter cache and GRU payloads used without rebuilding; hashes retained.

Supervisor decision (Claude, 06/11), verbatim:
the three nonzero gate differences (5.96e-8, 2.38e-7, 2.98e-6 m; reproduced by unmodified hw_new; encoder bit-identical)
are FP32 rounding of the GRU decoder path. Gate criterion: all 5,419 within 1e-5 m (10 µm, below the paper's 21 µm decoder
RTL tolerance), every nonzero difference listed. Gate already satisfied by W9a2 data: do NOT re-run it; run the full study
(W9a items 1–4: all 29,049 frames, T rows V0/VA/VB, registered oracle, aligned table, selected labels, count flow, encoded-input
check), detached, resumable, ≤ 4 workers. Update W9A_REPORT.md + summary.json. Final reply ≤ 25 lines with the new T rows.
Nonzero gate differences (zero-based index: max absolute size in m): 554: 5.960464477539063e-08; 2851: 2.384185791015625e-07; 4672: 2.9802322387695312e-06.
Read-only W9b audit: all 35 current dumps equal final_35 byte-for-byte; they do not predate final bert_v2. Original final runs: 2026-10-03; s00..02 regression rewrites: 2026-10-04 (local +07).
Same 35 scene-0103 frames, RQ1 indices 822..856; max vs saved hw_new=0.026161670684814453 m (s16/index 838), vs actual TB references=0.0000209808349609375 m. All masks match; all token arrays differ.
Audit file paths, dates, hashes, every frame token and evidence citations: rtl_dump_audit.json; RTL_DUMP_AUDIT.md. No paper numbers changed.
