# W7c accepted-candidate audit — POST HOC

Each accepted V0/VA plan is replayed using its own golden cid_g; all records: accepted.jsonl. Golden and W7/W7b unchanged.
O2: original float plan; apply +0.5 s, reaction 0.1 s, 1 ms samples, reserve 0.5 m, exact stop +2 s hold; W7b full-window relevance/coverage.
CV: exact encoded ego/t0 objects after V0/VA adapter, same velocities/covers, through stop + hold; also replay original float ego. Tolerance 1e-6 m: golden rounds outward. Empty-object margins use the inherited 10000 m sentinel.
Missing GT coverage: GT_TRUNCATED, minimum/object/time UNRESOLVED; no extrapolation. SAFE/UNSAFE labels below apply only to cid_g.

|Variant/plan|Accepted|Selected SAFE/UNSAFE/UNKNOWN/TRUNCATED|CV violations|min CV margin m|O2 library FA|Old FA|
|---|---:|---|---:|---:|---:|---:|
|V0/H|6596|2472/608/57/3459|0|0.020687188|296|2|
|V0/T|6322|2333/598/0/3391|0|0.009918997|284|2|
|V0/U|2873|572/229/0/2072|0|0.000804500|117|6|
|VA/H|9648|3340/775/116/5417|0|0.008936000|395|3|
|VA/T|9024|3013/734/0/5277|0|0.005082000|366|4|
|VA/U|5430|1070/379/0/3981|0|0.000804500|180|11|

Selected-UNSAFE attribution: a = absent from golden input (A5); b = in input, GT deviates from adapted CV; c = footprint/lateral convention; d = other/UNRESOLVED.
d is signed longitudinal GT minus adapted golden CV at the selected minimiser; original pre-cover d is also stored. Predicted margins use that same object/time.
|Variant/plan|a before/hold|b before/hold|c before/hold|d before/hold|median / p95 abs d m|
|---|---|---|---|---|---|
|V0/H|137/128|5/338|0/0|0/0|7.871239 / 19.740620|
|V0/T|150/126|3/319|0/0|0/0|7.838534 / 18.899788|
|V0/U|68/36|15/110|0/0|0/0|8.221855 / 25.980601|
|VA/H|150/158|6/461|0/0|0/0|6.968128 / 19.531740|
|VA/T|162/156|3/413|0/0|0/0|6.821579 / 19.042259|
|VA/U|116/48|17/198|0/0|0/0|9.232516 / 21.571779|

Full distributions (signed/absolute d and predicted margin), split by hold, plus original O2-library FA and old-FA subsets: results.json:classifications.
Every old-oracle FA is listed in results.json:old_false_accepts with cid_g O2 audit, CV audit, and old-selected no-hold replay (including old 3 s cap).
CV violations (encoded or original): 0; full inputs/rows/explanation: results.json:cv_violations. Original-profile UNKNOWN: 173; all listed with encoded replay in results.json.
Citations: ../run_w7.py:189 (corridor/combined half-length), :234 (float profile), :270 (old oracle), :302 (encoding/latency); ../w7_secondary.py:51 (VA covers), :72 (selection).
Citations: ../w7b/run_w7b.py:52 (projection), :93 (selected profile coverage/minimum); ../w7b/fa_causes.py:26 (old best-candidate attribution); ../../golden/tsmx_golden/model.py:406 (B4), :439 (B3), :683 (select_world).
Status COMPLETE; native Python 3.9.0; measured runtime 1209.009 s (load, replay, aggregation, hashes; final serialization excluded).
Old FA V0 (old-selected minimiser): {"b_in_input_GT_deviates/before_hold": 10}. O2-selected attribution is separately stored per case.
Old FA VA (old-selected minimiser): {"b_in_input_GT_deviates/before_hold": 18}. O2-selected attribution is separately stored per case.
Original-float UNKNOWN cases: 173; all have negative speed rounding to encoded zero. Their original O2 minima are UNRESOLVED; encoded CV results are explicit.
Audit code: run_w7c.py:55 (CV), :71 (selected O2), :80 (attribution), :128 (distributions); finalize_w7c.py:10 (independent record checks).
All audits: results.json:accepted_candidate_audits. Runtime sums completed-prefix elapsed + parallel-suffix wall + validation; restart gap/discarded work/serialization excluded. Failed-attempt duration UNRESOLVED.
Reproduce: `python -B tsmx_hw/eval_nuscenes/w7c/run_w7c.py`. Selection and accepted/FA count checks passed; source/input hashes in results.json. Then `python -B tsmx_hw/eval_nuscenes/w7c/finalize_w7c.py` for full packaging/validation.
