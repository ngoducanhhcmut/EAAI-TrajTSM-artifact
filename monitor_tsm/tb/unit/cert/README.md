# B9 certificate unit
Project TSM-X; author TSMX project; version 0.1.

From the repository root, Python 3.13:
```powershell
$env:PYTHONPATH='tsmx_hw/golden;tsm2_pilot/vendor'
py -3.13 -B tsmx_hw/tb/unit/cert/gen_vectors.py
py -3.13 -B tsmx_hw/tb/unit/cert/build_tb.py
py -3.13 -B tsmx_hw/tb/unit/cert/run.py --mutants
```
The runner executes in this TB directory; readmemh paths are relative to it.
It retains exact commands, exits, assertion hits and individually named mutants.
With Verilator on PATH it also builds and runs the same TB using
`--binary --timing --assert -Wno-fatal --top-module tb_m_tsmx_cert`.
No simulator-dependent design behavior or X-dependent mutant is used.

Synthesis filelist: `../../../rtl/filelist_R9.f`, paths relative to rtl/.
RTL top m_tsmx_cert; simulation top tb_m_tsmx_cert; no parameter overrides.
Icarus source order: arith divider, arith, cert, unit TB. Exact build is compile.log.

The 2904-bit request is spec9 B9_REQ, with first field most significant.
`now32` carries top's sampled `i_time_us`, including the 20ms subcycle and
independent timer jobs. B9 has no extra free-running time port or timer state.
Top owns timer priority, ACK sequence association and immutable codec results.

The generator first replays all golden fixture hex fields and certificate digests,
then converts full semantic inputs with golden packers, removing outer byte padding.
It cross-checks each fixture reason and all original diagnostic hex output bits.
All 20 B9 edge rows are converted; the 11 wrap rows are interpreted as
documented in R9_DECISIONS.md.
Additional jobs cover 20ms ticks and exact expiry/apply/ACK thresholds +/-1us,
lease endpoints, serial wrap/half-wrap, all status outcomes and digest corruption.
Each of 768 supplied local digest bits is individually inverted in extra jobs.
Twenty invalid original scalar values are rejected by the adapter, before packing;
they are not counted as RTL tests or silently narrowed into valid u32 values.

Clocked assertions check spec5.3 handshakes/reset/stalls/accounting and the twelve
reachable golden status codes (spec5.5.9/6.2). All assert checks count hits and fail
if never exercised. Each output-wire mutant flips a DUT-driven observable at the
target assertion's active cycle; the target assertion must fail with nonzero exit.
Eight separate synthesizable source copies inject real timing/binding/lease bugs.
Functional copies are verification artifacts and excluded from synthesis filelist.

Latency includes acceptance as cycle1, matching SEL/R2. Public unstalled II is4.
The printed II range includes deliberately stalled vector jobs; reset warmup
and the waiting-producer directed sequence are excluded from the timing summary.
Only the checker is measured here; top scheduling/codec WCET need integration.
