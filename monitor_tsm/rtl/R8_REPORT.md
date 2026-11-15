# R8 - B1 ingress integrity and freshness
Project TSM-X; author TSMX project; version0.1; date2026-10-29.

Top: `ingress/m_tsmx_ingress.sv`; generated filelist: `filelist_R8.f`.
ABI: req1374={Ingress332,now32,Ego256,Packet721,local_crc32,parse_ok1};
rsp340={proposed Ingress332,reason8}. One outstanding request; top owns history.
Private accepted ARITH op8 computes clock rollback; codec remains owned by top.

**Icarus PASS ingress: golden=128/128 edges=6/6 extra=2988/2988.**
All3122 responses compared bit-exact across all340 bits; CRC diagnostic edge1/1
checked in Python. Original b1.hex SHA256, accept/reason/digest and semantic
fixtures cross-checked. Seed0xB10008; all14 B1 reasons exercised.
Cases cover Config1 endpoints, sentinels, overflow/count/compute, wrap/half-wrap,
150000us freshness,300000us freeze,200000LSB displacement and history proposals.
Reset cancels five jobs at different phases; jobs3127=completed3122+aborted5.

27 assertions active; failures0, never exercised0. Every targeted output-wire
mutant fails its own named assertion:27/27 killed. Functional source mutants8/8
killed: CRC bypass, equal sequence, age/freeze boundaries, epoch refresh,
last_sample, stalled response loss and clock priority. No X/force dependence.

Measured core latency **4..4 cycles/job**, acceptance edge counted as cycle1.
Measured unstalled **II5**; deliberate response stalls extend observed II to8.
Spec5.5.3/10.3 B1 allowance16384: measured leaf4 is **within budget**.
CRC is outside this interface: accepted R3 reports22 packet-CRC cycles, giving
calculated sequential CRC+leaf26 cycles before top scheduling/stalls. Integrated
CRC-inclusive latency was not measured here; no whole-top WCET/STA claim.
Per-job cycles, hit counts, conservation and PASS line: unit `simulation.log`.

VLSIT v2 rule check **PASS:0ERROR/1WARN/0INFO**, R-012/R-019 clean.
Sole HIE-02 warning justified: functional leaf contains private arithmetic;
system top remains structural. Header and R8_DECISIONS11 record this choice.
R8_RULES.md has mechanical findings; R8_MANUAL.md covers manual R-001..026,
and R8_COVERAGE.md preserves the full tool/manual partition.
R-004 six template-heading BLOCK gaps resolved under delegation (decisions2).

**R-015: lint not run; Verilator5 build/simulation not run: tool unavailable.**
Lint utility and replay attempts are logged; WSL access denied. No installation.
Options: OSS CAD Suite, MSYS2 Verilator, WSL or Conda. Portable replay script
uses --binary --timing --assert with the same TB and relative readmemh path.
Icarus compile notices concern its conservative always_comb sensitivity handling;
they are not lint evidence. No simulation/SYNTHESIS behavioral split exists.

Resources: ingress adds0 variable multipliers/0 dividers;32-bit serial subtracts,
65-bit displacement/absolute path,1374-bit request and340-bit response registers.
Private generic ARITH hierarchy includes six divider pipelines (paired96/128/160)
and its full motion multiplier cones up to160 bits; op8 uses no multiplier/divide.
Constant-op synthesis pruning, mapped multiplier/divider count and area unmeasured.
No synthesis, timing187.5MHz, formal, CDC/RDC or DFT signoff performed.

SPEC-ISSUE: parse_ok alone cannot retain every original malformed-value error
provenance; wire-domain contract and adapter handling are explicit in decisions7.
No supplied fixture needs an ABI extension; no protected sources were modified.

Reproduce: `py -3.13 -B tsmx_hw/tb/unit/ingress/gen_vectors.py`, then `run.py`
in that directory; `run_verilator.py` is the Verilator replay entry point.
Evidence: `tb/unit/ingress/{vectors,results,assertions,mutants}.json`, logs and
`mutants/`, `source_mutants/`. Instructions and exact commands: unit README.md.
