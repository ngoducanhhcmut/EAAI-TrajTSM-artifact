# W6 pre-registration (2026-11-05, before fault outcomes)

Only this directory is writable. No golden model is executed or modified.
P=G=2; direct semantic requests, with the real top transport transmitting commands.
The integration bench packing/comparisons are the ABI reference
(`tb/integ/build_tb.py:246`, `tb/integ/build_tb.py:175`, `tb/integ/build_tb.py:304`).

Fault: a hierarchical blocking deposit of the complement of one selected register
bit, one time, at a rising edge plus 1 ns (after NBA settlement). No stuck fault,
no forced inputs, no cache initialization. Read back immediately and 1 ns later;
require both to equal the complemented, known original bit. Compile once per tool.
Verilator portability is UNRESOLVED until Claude executes the provided commands.
Icarus cannot parse the engine's unpacked constant ROMs
(`rtl/top/m_tsmx_engine.sv:299`). The builder may lower those constants in a copy
to packed constants with identical indexed slices, exhaustively checking entries.
Both tools use that same copied engine; all other RTL is compiled in place.

Population: declared packed/scalar `reg_*` variables assigned in clocked logic,
including enum state bits, in the selected instances. All bits, including constant
or inactive bits, remain eligible. Unpacked memories are excluded (RAM upset is
outside this flip-flop pilot); parameterized packed widths are resolved explicitly.
The generator records every register, width, instance and original file:line.
Units: engine, sweep (main and duplicate), mrmgen (both main lanes, duplicate and
BIST), geom (same instances), geom_su (all four subunits of each geom), arith
(mrmgen children, engine math, ingress and cert), cert, selection, ingress, codec,
supervisor, health (controller plus BIST control, not row RAM).
No claim of coverage of every synthesized flip-flop: hash/math wrapper state,
I/O, CSR, recorder, arbiter and splice state are outside the population.

Sampling: seed 20261105, Python Random, with replacement, uniform by bit within
each unit; units visited round-robin. Planned main campaign: 1440 injections,
120 per unit. Pilot: first 24 (2 per unit). Overall is the equal-unit mixture,
not a silicon-bit-weighted rate. Inventory and realized samples are generated
before injections and must never be changed in response to outcomes.
Four fixed reset-start jobs: first reset ACCEPT and first reset REJECT from each
of `reg300_board.mem` and `apos.mem`. Job draw is uniform. Exact zero-based rows
and fixture hashes go in workload.json. No prefixes or assumed retained state.
Unfaulted baselines must match all compared golden fields before injections on
that job. Independent jobs may begin after their own baseline passes.
Cycle is uniform in [1, baseline response latency-1], excluding the request edge
and the response edge. This is the golden active window, even if faulted latency
changes. A response before the scheduled injection is UNRESOLVED, not MASKED.

Compare response (38), command (1897), Event (1056), retained ingress (332),
supervisor (8), lost count (32), CSR reason and status; latency is recorded but
not required equal. Command framing/count and missing artifacts are differences.
Unsafe takes precedence: response ACCEPT when golden rejects, or any accepted
certificate/plan/authority differing from the golden-certified record. Conservatively
use exact accepted command equality; alternative certificates are not certified.
Unknown bits or incomplete probes are UNRESOLVED, never safe.
Otherwise: all compared fields equal = MASKED; a differing result with a new
fault/health flag, safe reject, or changed fallback = DETECTED; remaining changed
outputs = SDC-SAFE. Golden-existing faults/fallback are not new detection evidence.
SDC-UNSAFE is retained even if detection flags also occur. DC uses DETECTED /
(DETECTED + SDC-SAFE + SDC-UNSAFE); MASKED and uncontained HANG are excluded and
reported separately. HANG at 1875010 active cycles becomes DETECTED-by-timeout
only with an observed RTL deadline flag; external wall timeout is UNRESOLVED.
The real deadline action is `rtl/top/m_tsmx_engine.sv:1124`.

Report exact two-sided Clopper-Pearson 95% binomial intervals overall/per unit,
with empty denominators UNRESOLVED. Equal-unit stratification means the pooled
interval is descriptive for the registered mixture, not a hardware reliability
bound. No gate. Report every unsafe unit/register/bit/cycle/job and propose only
register-local dual rail or residue protection; never alter the RTL.

The arithmetic copy also lowers the ternary enum assignment at
`rtl/arith/m_tsmx_arith.sv:865` to five bit assignments. Each bit preserves the
conditional operator, including its four-state merge; state encodings and timing
are unchanged. No `always_comb` replacement or cache deposit is used.

Generated population (generation.log; inventory.json is the complete enumeration):

| Unit | Eligible bits | Planned main samples | Planned pilot samples |
|---|---:|---:|---:|
| arith | 19012 | 120 | 2 |
| cert | 2914 | 120 | 2 |
| codec | 2441 | 120 | 2 |
| engine | 72952 | 120 | 2 |
| geom | 40508 | 120 | 2 |
| geom_su | 13488 | 120 | 2 |
| health | 34384 | 120 | 2 |
| ingress | 1717 | 120 | 2 |
| mrmgen | 4300 | 120 | 2 |
| selection | 18 | 120 | 2 |
| supervisor | 10 | 120 | 2 |
| sweep | 19008 | 120 | 2 |

The generated total is 210752 eligible bits in 1212 instance-register entries.
These are RTL storage bits, including inactive/constant fields, not post-synthesis
flip-flop counts. `geom_su.reg_rv` uses LPARA_NT=13
(`rtl/geom/m_tsmx_geom_su.sv:66`). Unpacked arrays, even if mapped to flip-flops
by a synthesis tool, remain outside this explicitly bounded population.
Cycle selection uses Random(cycle_seed).randrange(1, baseline_cycles), not a
modulo reduction of a random integer. The cycle seed is frozen in faults.json.

From the repository root on Windows (Python 3.13; no WSL):

```powershell
py -3.13 -B tsmx_hw/fault/gen_faults.py
py -3.13 -B tsmx_hw/fault/build_fault_tb.py
py -3.13 -B tsmx_hw/fault/check_tools.py
py -3.13 -B tsmx_hw/fault/run_campaign.py --tool iverilog --n 24 --timeout 1800
# Resume without recompiling:
py -3.13 -B tsmx_hw/fault/run_campaign.py --tool iverilog --n 24 --timeout 1800 --skip-compile
py -3.13 -B tsmx_hw/fault/classify.py
```

The optional run_pilot_parallel.py executes exactly the same frozen pilot prefix
with independent processes after baselines pass (`--ready-only` selects only
jobs with a completed, passing baseline). Its records have the same
resume format. Do not run both injection runners on the same results file at once.
The pilot does not substitute its separate deposit_probe diagnostic for a sampled
injection. deposit_probe.log proves the actual hierarchical write and delayed
readback on Icarus, and deposit_probe.json records its completion/time.

Exact Claude commands on Linux with Verilator 5 available (from repository root):

```bash
export PATH="$HOME/oss-cad-suite/bin:$PATH"
python3 -B tsmx_hw/fault/gen_faults.py
python3 -B tsmx_hw/fault/build_fault_tb.py
python3 -B tsmx_hw/fault/check_tools.py
python3 -B tsmx_hw/fault/run_campaign.py --tool verilator --compile-only
# Readback probe: require PROBE ... before=0 after=1 ok=1 (or the inverse).
cd tsmx_hw/fault
./obj_fault/Vtb_fault +FILE=job1.mem +FAULT_ID=0 +FAULT_CYCLE=1 > verilator_deposit_probe.log 2>&1
cd ../..
python3 -B tsmx_hw/fault/run_campaign.py --tool verilator --skip-compile --n 1440 --timeout 300 --results results_verilator.jsonl
python3 -B tsmx_hw/fault/classify.py tsmx_hw/fault/results_verilator.jsonl
```

The compiler command is emitted verbatim in verilator_compile.log and saved as
an argument array in verilator_build.json. Its flags are `--binary --timing
--assert -Wno-fatal -Wno-BLKANDNBLK -j 4 --top-module tb_fault -Mdir .../obj_fault`.
BLKANDNBLK is waived specifically for the intentional bench deposit after NBA;
the DUT clocked assignments remain nonblocking. All sources appear in sources.json.
The runner compiles once and runs four unfaulted baselines before the frozen
injections; --skip-compile verifies the build identity. Resume keeps completed
attempts, including UNRESOLVED, without silently retrying unfavorable results.
Do not regenerate files once a campaign has started. Different simulators need
different results files; mixed build identities are rejected.

Budget calculation, not a measured Verilator runtime: 6*3600/15 = 1440 injections
at the user-supplied 15 seconds/job. Compilation, baselines, probe and startup are
additional; reserve overhead or stop/resume the frozen prefix at the time limit.
No claim of a measured six-hour throughput is made before Claude's run.
