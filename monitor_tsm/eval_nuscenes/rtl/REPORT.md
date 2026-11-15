# W7r: generated; full RTL replay pending; smoke UNRESOLVED
Generated from 300 frames in frame/plan order: 771 independent reset/admission attempts per file; no preload.
All writes are in this directory. Reproduce: `py -3.13 -B tsmx_hw/eval_nuscenes/rtl/gen_nuscenes_mem.py`.
| Plan | Jobs/file | W7 accept/reject | System accept/reject (both files) | Primary fallback accept/reject | VA fallback accept/reject |
|---|---:|---:|---:|---:|---:|
| H | 300 | 165/135 | 0/300 | 165/135 | 246/54 |
| T | 300 | 174/126 | 0/300 | 174/126 | 253/47 |
| U | 171 | 93/78 | 0/171 | 93/78 | 135/36 |
Primary cross-check (accept,cid): 432 mismatches; cid alone: 0 mismatches. System checks: 757 ftti_budget, 14 ego_live.
VA cross-check against original W7: 634 mismatches; every mismatch and reason is in `mismatches.jsonl`; totals in `crosscheck.json`.
Exact ego has lx=lv=0: reaction_safe blocks new admission independently of packet/history (`golden/tsmx_golden/model.py:615-621,739`); invalid live states fail at :689-722.
Thus successful admissions matching W7 accept are UNRESOLVED under the exact-snapshot constraint; fallback selections are separately reported, never relabeled admission.
264 plans retain negative-speed objects: W7 source retains them, contrary to the prompt's “absent” description (`eval_nuscenes/run_w7.py:305-312`).
VA uses verbatim reduce_neg, latency 500000, largest valid candidate horizon per plan; single-world coverage follows A1-A3 (`proof/adapter_lemmas.py:4-14`).
Per-candidate VA versus common-cover selection differs on 20 plans; both decisions and all candidate horizons are in `nuscenes_va.json`.
Encoding, physical reachability, cover justification and file:line references: `ENCODING.md`; per-job manifests: `nuscenes.json`, `nuscenes_va.json`.
Icarus smoke: UNRESOLVED / compile FAILED, syntax errors at `rtl/top/m_tsmx_engine.sv:299-301`; no jobs simulated, no PASS claimed.
Attempt: `$env:PATH='C:\iverilog\bin;'+$env:PATH; py -3.13 -B tsmx_hw/eval_nuscenes/rtl/run.py --file nuscenes.mem --limit 2 --lanes 2 --allow-inactive --tag smoke`.
Both ordinary and --synthesis compile attempts failed; see `compile_2_iverilog_smoke.log` and `compile_2_synthesis_iverilog_smoke.log`.
Claude: run from journalQ1 (native Linux or a native Verilator environment; no WSL used here):
```text
python -B tsmx_hw/eval_nuscenes/rtl/run.py --tool verilator --lanes 2 --file nuscenes.mem --limit 771 --allow-inactive --tag nuscenes
python -B tsmx_hw/eval_nuscenes/rtl/run.py --tool verilator --lanes 2 --file nuscenes_va.mem --limit 771 --allow-inactive --tag nuscenes_va
```
Projected simulation time from supplied reg300 baseline 15 s/job: 11565 s = 3 h 12 m 45 s/file; both 6 h 25 m 30 s, plus compilation; not measured here.
Focused replay explicitly permits inactive fault checks; it does not replace mandatory fault coverage (`tb/integ/README.md:73-76`).
