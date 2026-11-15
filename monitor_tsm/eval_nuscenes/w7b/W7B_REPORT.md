# W7b aligned-horizon remeasurement — POST HOC

Primary W7 results, golden and proof unchanged. Offline estimators retain A7 lookahead.
O2: independent float 1 ms, original plan, apply t0+0.5 s, reaction 0.1 s, 0.5 m reserve; W7 finite-jerk library order.
Checks apply through exact float stop + 2 s stationary hold. No GT extrapolation or last-pose holding.
Relevance: all scene vehicle/human/cycle tracks intersecting |y|<=1.8+width/2 at any time in [t0,end], including later entrants; then retain them throughout.
Full linked annotations are interpolated in fixed t0 ego axes with W7 axis-aligned footprints; retain t0 combined half-length (earliest size for future-born tracks).
Each candidate needs scene and relevant-track coverage from t0 through its end. SAFE: a complete safe candidate; UNSAFE: all complete and unsafe; otherwise GT_TRUNCATED.
UNKNOWN: invalid float plan or >60 s stop. Missing tracks take precedence over collision evidence for that candidate.
No t0 longitudinal range cap. Golden variants retain W7 objects; VB drops rear objects as the existing ablation.

|Variant/plan|Acceptance (both)|Old FR / SAFE|O2 FR / SAFE|Old FA / UNSAFE|O2 FA / UNSAFE|
|---|---|---|---|---|---|
|V0/H|37.81% [35.29,40.43] (6596/17445)|57.89% [55.11,60.58] (8986/15523)|33.25% [30.03,36.33] (1912/5751)|0.20% [0.00,0.52] (2/979)|11.33% [9.12,13.78] (296/2612)|
|V0/T|36.24% [33.69,38.88] (6322/17445)|57.97% [55.15,60.76] (8718/15038)|32.50% [29.18,35.76] (1774/5459)|0.25% [0.00,0.61] (2/794)|11.76% [9.52,14.30] (284/2415)|
|V0/U|29.57% [26.97,32.27] (2873/9717)|67.14% [64.22,69.87] (5858/8725)|57.84% [53.11,62.06] (1789/3093)|0.60% [0.19,1.15] (6/992)|17.41% [11.99,23.24] (117/672)|
|VA/H|55.31% [52.50,58.21] (9648/17445)|38.61% [35.52,41.59] (5994/15523)|11.82% [9.96,13.95] (680/5751)|0.31% [0.00,0.69] (3/979)|15.12% [12.61,18.02] (395/2612)|
|VA/T|51.73% [48.81,54.62] (9024/17445)|40.02% [36.83,43.12] (6018/15038)|13.43% [11.23,15.86] (733/5459)|0.50% [0.12,1.03] (4/794)|15.16% [12.51,18.09] (366/2415)|
|VA/U|55.88% [52.75,59.00] (5430/9717)|37.89% [34.52,41.10] (3306/8725)|27.22% [23.20,31.39] (842/3093)|1.11% [0.34,2.23] (11/992)|26.79% [20.38,33.13] (180/672)|
|VB/H|91.03% [90.14,91.97] (15880/17445)|3.01% [2.53,3.52] (467/15523)|1.58% [1.08,2.14] (91/5751)|66.60% [60.21,72.58] (652/979)|91.92% [89.71,93.97] (2401/2612)|
|VB/T|86.09% [84.49,87.62] (15018/17445)|3.36% [2.80,3.92] (505/15038)|2.23% [1.48,3.16] (122/5459)|61.08% [53.49,67.73] (485/794)|92.13% [89.96,94.08] (2225/2415)|
|VB/U|84.17% [82.33,85.98] (8179/9717)|10.54% [8.96,12.13] (920/8725)|9.25% [6.98,11.85] (286/3093)|37.70% [30.16,45.32] (374/992)|74.55% [67.55,81.28] (501/672)|

CI: original W7 scene bootstrap (all scenes), 2000 shared multinomial draws, seed 20261104. Secondary report CIs used a different sampler; counts must match.
Count flow H/T/U: eligible keyframes -> ODD keyframes -> generated plans -> V0 adapter-valid; O2 labels below cover all generated ODD plans.

- H: 29049 -> 17445 -> 17445 -> 11523; SAFE/UNSAFE/UNKNOWN/TRUNCATED=5751/2612/943/8139.
- T: 29049 -> 17445 -> 17445 -> 11523; SAFE/UNSAFE/UNKNOWN/TRUNCATED=5459/2415/1613/7958.
- U: 29049 -> 17445 -> 9717 -> 5069; SAFE/UNSAFE/UNKNOWN/TRUNCATED=3093/672/0/5952.

Acceptance denominator includes every ODD plan; FR uses SAFE, FA uses UNSAFE, including adapter-invalid. UNKNOWN/truncated are excluded only from oracle denominators.
O2 FR/FA describe the labelable subset; GT_TRUNCATED is a separate unresolved class. Per-label accepted/rejected counts are in results.json.
FR first-cause priority: negative-velocity adapter (V0), rear separation, front separation, lane/other. Selected diagnostic = greatest-margin finite-jerk candidate.
Separation side: minimum singleton golden margin in the earliest failing interval of that diagnostic; ahead/behind at interval start. Details are in plans_*.jsonl.

- V0/H FR=1912: adapter 1427 (74.63%); rear 448 (23.43%); front 0 (0.00%); lane_or_other 37 (1.94%).
- V0/T FR=1774: adapter 1275 (71.87%); rear 468 (26.38%); front 0 (0.00%); lane_or_other 31 (1.75%).
- V0/U FR=1789: adapter 1267 (70.82%); rear 268 (14.98%); front 66 (3.69%); lane_or_other 188 (10.51%).
- VA/H FR=680: adapter 0 (0.00%); rear 588 (86.47%); front 6 (0.88%); lane_or_other 86 (12.65%).
- VA/T FR=733: adapter 0 (0.00%); rear 610 (83.22%); front 5 (0.68%); lane_or_other 118 (16.10%).
- VA/U FR=842: adapter 0 (0.00%); rear 438 (52.02%); front 123 (14.61%); lane_or_other 281 (33.37%).

Old SAFE -> O2 UNSAFE / isolated hold conversions H/T/U (remove hold, retain each candidate's full-window relevance set): H 2111/1979; T 2061/1916; U 411/341.
Paired V0->VA changes by O2 label (accept->reject / reject->accept): H SAFE 0/1232, UNSAFE 0/99, UNKNOWN 0/59, GT_TRUNCATED 0/1662; T SAFE 0/1041, UNSAFE 0/82, UNKNOWN 0/0, GT_TRUNCATED 0/1579; U SAFE 0/947, UNSAFE 0/63, UNKNOWN 0/0, GT_TRUNCATED 0/1547.
Every newly VA-accepted O2-UNSAFE plan (244) is listed with scene/token/plan, culprit and GT-minus-constant-v in results.json:newly_accepted_unsafe.
Reuse citations: ../run_w7.py:30 (12 finite-jerk cids in the 16-entry library), :168 (scene poses), :189 (categories/footprints), :234 (float profile), :302 (encoding), :501 (bootstrap); ../w7_secondary.py:51 (reduction), :72 (VA/VB); ../../golden/tsmx_golden/model.py:439 (diagnostics).
Status COMPLETE; measured orchestration wall runtime 1771.0 s; secondary aggregate count replay verified. Full counts, CIs, transitions, paired cases and input/code hashes: results.json.
Runtime covers the successful resumed invocation; duration of the earlier failed diagnostic replay is UNRESOLVED (not timed persistently).
Reproduce: native W7 Python, `python -B tsmx_hw/eval_nuscenes/w7b/run_w7b.py`; workers resume only within w7b.
