# TSM-X integration
Project TSM-X; author TSMX project; version 0.1.

Run from the repository root. Python3.13 is the Windows interpreter used here.
On Linux substitute `python3` for `py -3.13`; scripts resolve all paths themselves.
The runner uses the generated compile-order filelist and records exact commands.
No golden, original vector, accepted RTL or specification source is rewritten.

```powershell
py -3.13 -B tsmx_hw/tb/integ/gen_sequences.py
py -3.13 -B tsmx_hw/tb/integ/build_tb.py
py -3.13 -B tsmx_hw/tb/integ/build_control_tb.py
py -3.13 -B tsmx_hw/tb/integ/check.py
py -3.13 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 2
py -3.13 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 8 --limit 128 --allow-inactive
py -3.13 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 8 --file worst.mem --limit 1 --allow-inactive --worst --tag worst
py -3.13 -B tsmx_hw/tb/integ/run_control.py --tool verilator --lanes 8
```

Both Verilator runners use `--binary --timing --assert -Wno-fatal -j 4`.
Simulation top: `tb_m_tsmx_top`, or `tb_tsmx_control_phy` for control tests.
Default control execution on Icarus and Verilator performs genuine admission before all timer cases and
uses three physical requests with a stalled executor to force the decision deadline.
Its SV source contains no cache deposits. Verilator compilation is not verified here.

For Icarus, omit `--tool verilator`. `run_control.py --timers-only` runs the fast
cached-state timer probe, which initializes **only owned engine cache registers**;
it is explicitly separate from the physical admission/ACK test used by Verilator.
The simulator executable can be selected with PATH; nothing is installed by scripts.
Use `--tag full/system/worst/smoke` for distinct evidence files. Simulator names
are included automatically, preventing concurrent diagnostic log collisions.
XSim is optional (`--tool xsim`, installed location in run.py). Its CSR compatibility
probe fails in this environment, so it is not the primary functional simulator.

Quick physical fault and protocol check, followed by all20 observation mutants:

```powershell
py -3.13 -B tsmx_hw/tb/integ/run.py --lanes 2 --file smoke.mem --limit 2
py -3.13 -B tsmx_hw/tb/integ/mutants.py
py -3.13 -B tsmx_hw/tb/integ/source_mutants.py
py -3.13 -B tsmx_hw/tb/integ/probe_csr.py
py -3.13 -B tsmx_hw/tb/integ/probe_helpers.py
py -3.13 -B tsmx_hw/tb/integ/run_control.py --timers-only
```

`vectors.json` contains seed, original fixture checksum,500 new six-cycle sequences,
all oracle responses and group counts. `vectors.mem` contains3151 jobs. Each compares
38 response bits,1897 command bits,1056 Event bits and CSR snapshots. Ingress and
supervisor ownership proposals are also compared after each completed job.
The128 system cases retain state throughout. Ten arbitration edge cases form
a separate reset-to-reset chain. Three imported live-fault snapshots are proved
whole-state equivalent to reset; rollback uses a physical invalid-live prefix.
Thus14 system edge fixtures use15 physical jobs. No hidden preload port is used.
Eight additional physically reachable jobs cover RECOVERY,RECOVERY,L0,L1,L2,L3,
HOLD,RECOVERY in one continuous chain (`modes.mem`).

The32-object timing input in `worst.mem` invokes two full sixteen-candidate sweeps.
`--worst` requires both candidate masks=ffff,32 objects,77 maximum rows,streaming overlap and
latency<=1168034; the log also prints actual maximum generator row count.
The128-row budget is an architectural cap; the legal generator profiles can stop
earlier. It must not be described as a measured128-row worst case without evidence.
All printed cycle latencies are RTL clocks; divide by187500 to obtain milliseconds.
Neither simulation cycles nor source divider counts prove187.5MHz or PPA.

`ck` is a hit-counted immediate protocol check. Every failed check calls `$fatal`.
The normal run also fails when any of40 checks has no hit. Focused positive timing
cases use explicit `--allow-inactive`; all inactive counts are still printed and
must be covered by the mandatory fault smoke. The full run has no such waiver.
Observation mutants alter only sampled DUT output observations, never an oracle.
They prove sensitivity of each named top check; they are not RTL-source mutations.
`source_mutants.py` additionally changes copies of the owned engine's FSM encoding
and brake output, requiring the corresponding assertions to catch both mutations.
`probe_helpers.py` checks400 composite math and400 CRC/SHA jobs, including32-object
contexts, against independent golden helpers and hashlib/zlib.

`regress.py --tool verilator` executes the acceptance matrix and records each
category's exit status. It stops on failure and never labels an unrun category PASS.
Run helper and mutant scripts separately with Icarus. `build_rtl.py` is a source
generator; ordinary reruns use the checked-in RTL and do not regenerate it.

`I1_REPORT.md` is the acceptance record. A generated corpus, successful elaboration
or a partial replay is never a substitute for the unrun complete regression.
