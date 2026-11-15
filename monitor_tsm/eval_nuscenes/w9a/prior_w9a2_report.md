# W9a2: complete validation gate FAILED; full study NOT RUN

Supervisor decision (Claude, 06/11), verbatim:
The gate mismatch (1 of 1,584 predictions, 5.96e-8 m, index 554; unmodified `hw_new` reproduces it) is FP32 rounding in the
GRU decoder path, below the 21 ?m decoder RTL tolerance stated in the paper. Gate criterion is now: all 5,419 validation
predictions within 1e-6 m of `pred_hw_new.npy` AND every mismatch listed with its index and size. Encoder bit-exactness is not
affected. Record this decision verbatim in the report.

Gate: all 5419 checked; 5416 exact; 5418 within 1e-6 m; max |diff|=2.9802322387695312e-06 m. One exceeds tolerance.
Every nonzero prediction difference (zero-based RQ1 index, max absolute size):
|Index|Frame token|Size (m)|
|---|---|---|
|554|18b3ef8c389240f39196a55621eb1930|5.960464477539063e-08|
|2851|98e1aaf252bd49faba80f5bd33ada9c5|2.384185791015625e-07|
|4672|dcfd47c0dab94cf79e49221da90564b9|2.9802322387695312e-06|
All 5,419 rebuilt validation inputs/masks match the archived dataset exactly; discrepant frames=0, max token difference=0.
Unmodified hw_new reproduces index 4672 at 2.9802322387695312e-6 m from reference; original vs accelerated/shard=0. Encoder original vs accelerated is bit-exact on this case.
This new exceedance remains above the authorized gate; precise cause is not isolated. No tolerance change, reference update, parameter rebuild or substitution.

Table aligned, part 1. N/R = not run because the revised gate failed.
|Variant|Acceptance|Aligned FR|Aligned FA|
|---|---|---|---|
|V0/H|N/R|N/R|N/R|
|V0/T|N/R|N/R|N/R|
|V0/U|N/R|N/R|N/R|
|VA/H|N/R|N/R|N/R|
|VA/T|N/R|N/R|N/R|
|VA/U|N/R|N/R|N/R|
|VB/H|N/R|N/R|N/R|
|VB/T|N/R|N/R|N/R|
|VB/U|N/R|N/R|N/R|

Table aligned, part 2.
|Variant|Selected S/U/?/Tr|Selected risk|IP|Rejection frequency|
|---|---|---|---|---|
|V0/H|N/R|N/R|N/R|N/R|
|V0/T|N/R|N/R|N/R|N/R|
|V0/U|N/R|N/R|N/R|N/R|
|VA/H|N/R|N/R|N/R|N/R|
|VA/T|N/R|N/R|N/R|N/R|
|VA/U|N/R|N/R|N/R|N/R|
|VB/H|N/R|N/R|N/R|N/R|
|VB/T|N/R|N/R|N/R|N/R|
|VB/U|N/R|N/R|N/R|N/R|

Registered oracle: acceptance, FR / SAFE and FA / UNSAFE are N/R for H, T, U; no new counts or denominators.
Reference W7 ODD coverage only: 17445/29049; 60.05% [58.37,61.90]; inventory 34149 keyframes, 850 scenes.
Count flow H/T/U: 29049 W7 eligible -> 17445 W7 ODD -> 0 W9a full-study plans; adapter-valid N/R.
Encoded-input study check: 0 accepted records evaluated; sampled discrepancies/minimum margin N/R. No study replay, labels or bootstrap computed.
Planned bootstrap unchanged: 2,000 scene draws, seed 20261104.

Read-only W9b audit: the 35 dumps ../tb/e2e/results/wp_rtl_s00.txt through wp_rtl_s34.txt equal final_35 byte-for-byte. They do not predate final bert_v2.
Producer: planning_top + bert_v2, V2 payload, timing-fixed GRU with S_IDLE/S_DONE wp_prev resets (AK.5); s00..02 later r150/r150c regressions equal final_35. Exact immutable source commit unavailable.
Local +07 modification dates: 2026-10-03 (32 files); 2026-10-04 (s00..02). Same 35 scene-0103 frames, saved RQ1 indices 822..856; every token/path/date/hash in rtl_dump_audit.json.
Max vs saved hw_new=0.026161670684814453 m at s16/index 838; vs actual testbench references=0.0000209808349609375 m (20.9808349609375 µm). All 35 CLS error counts are zero.
All 35 masks agree but all 35 archived token arrays differ: this is not a same-input RTL error measurement. Input differences alone are not proven to explain every waypoint difference.
Evidence: ../VERIFICATION_HISTORY.md:3114, :3164, :3197; ../reports/unit/e2e_files_f.txt:1; ../reports/unit/tb_planning_top_e2e_f0.log; ../tb/e2e/tb_planning_top_e2e.sv:254, :279.
Full 35-frame audit and file:line citations: RTL_DUMP_AUDIT.md. No paper numbers or source artifacts changed.

Runtime: 2011.610 s total; prior W9a 1468.845 s, W9a2 invocations 533.218 s, independent verification 9.453 s; detached gate, four workers maximum.
C: free bytes start/end=14452518912/14398619648; >=10 GB before large writes.
Execution: resumed 1584 prior predictions; independently checked complete unique indices and every saved difference. First W9a2 stopped at 4686 records; resumed without fail-fast to check all 5419.
Missing checkpoint path remains documented; existing RQ1 parameter cache/payloads retained without rebuilding. Source hashes and prior run provenance are preserved.
Runtime excludes restart gaps, unmeasured audit/failed-packaging time and final serialization. No new T metrics claimed. Full study remains conditional on passing the supervisor gate.
All writes under w9a; summary.json contains all report values and detailed deviations; w9a2_gate_verification.json contains coordinate-level differences.
