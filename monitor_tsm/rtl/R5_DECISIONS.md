# R5 decisions — B2 splice
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

1. **Authority and scope.** Designer delegated every decision to the supervisor.
   This overrides skill R-005/006, the module-list approval gate, and R-026's
   consultation gate. Only splice RTL/TB, filelist_R5.f and R5_*.md are written.
   No accepted arithmetic, selector, golden, spec or vector source is modified.
   Rules: `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md`
   v2, plus RTL-generator SKILL.md/rule.md. Header values are designer supplied.
2. **Gap scan.** G-001..006 report absent template subsections 1.1,2.3,7.1,7.3,
   14.2,14.3. Sections 5.3/5.4/7/13/14 provide this leaf's clock/reset/hierarchy
   contract; missing template headings introduce no unresolved B2 behavior.
3. **Module/ABI.** One functional leaf `splice/m_tsmx_splice.sv`, ports exactly
   section 5.3 plus req816 and rsp1 in 5.5.4. Full request captured on handshake.
   Ego occupies [815:560]; Plan [559:0]. Plan apply[239:208], x[207:144],
   v[143:112], a[111:80]. The initial smoke check caught a 24-bit Plan-offset
   transcription error; section9's explicit field sum fixed it before regression.
4. **Parameters.** Section5.5.4 locks all Config1 tube and uncertainty constants.
   No unsupported configurable tube/scale/width parameter is introduced. Named
   localparams hold dx=50000,dv=50000,da=100000,x tube160000,v tube200000,
   max delay100000,v10000000,a magnitude8000000,position limit10000000000.
5. **Oracle/guards.** Golden b2_splice is authoritative. Check both x ranges,
   both v ranges, both a ranges and serial delay in[0,100000]. Negative encoded
   s32 values and s64 minimum sentinels fail these range checks. No type-invalid
   Python object has a hardware representation: parser validates original types
   before packing. All added numeric cases are representable in their wire slots.
   B2 does not independently validate ignored lx/lv,seq,snapshot,generated,tail,
   compute,count,schema; B1/admission owns these. Metadata does not affect B2.
6. **Serial time.** Subtract apply minus ego.t in u32; compare resulting encoding
   <=100000. This admits valid wrap, rejects every negative serial encoding,
   ambiguous half-wrap, and positive excess delay. No timestamp sentinel is used.
7. **Corners.** Counter[3:0]={dx sign,dv sign,da sign,round up}. Propagate all16
   jobs serially, max(0,v+dv), min(0,max(-8000000,a+da)). Every returned x and v
   must lie in the closed tube. Checking all16 points is equivalent to checking
   extrema of both returned arrays; equality at either boundary is accepted.
   No early exit: fault/reject accumulates while all issued work drains.
8. **Arithmetic.** One private, unchanged m_tsmx_arith uses op3 advance, q0=x,
   q1=v,q2=a,q3=h,q4=up, q5..11=0. Never approximate stop/ceil/floor locally.
   Primitive fault clears final accept. No ARITH-ISSUE required. x/v/a local
   containers are unsigned s64 encodings, with explicit sign extension/comparison.
   Once guarded, corner additions and tube limits are far inside s64; no silent
   overflow is possible. ARITH enforces/checks its wider products before return.
9. **Scheduling/reset.** BOOT/IDLE/GUARD/ISSUE/WAIT/RESP Moore control; req ready
   and rsp valid never overlap. Output zero when invalid; stalled response holds.
   Reset aborts this context and the private engine together. Wrapper supplies
   synchronized release, DFT reset control and timeout drain policy (5.3/7).
10. **Style/warnings.** Moore example and skeleton guide three-process FSM.
    HIE-02 justified: this is a functional leaf beneath the structural system top.
    PAR-03 warnings (seven) concern fixed ABI sign extensions32/96 and the factor10
    defining the fixed 10^10 position limit. They are documented header deviations;
    no configurable field width or scale is implied. No latch warning is waived.
11. **Verification.** gen_vectors imports the unchanged golden and reuses its
    pack_ego/pack_plan converters. It also decodes b2.hex through b2.json fields,
    checks vectors.evaluate's entire summary, and constructs the corresponding B2
    request. Full semantic output accept is compared; there is no B2 reason port.
    All18 relevant edge rows replay. Fixed seed0x5253504c; 4494 additional cases
    include min/max/sentinels, overflow attempts, stop, clamps, serial wrap,
    equality +/-1, ignored metadata, and random accepted/rejected poses.
12. **Assertions/mutations.** 24 named spec-derived immediate assertions have hit
    counters and fatal failure/zero-hit behavior. Separate mutants flip a DUT-driven
    observed output wire at the selected assertion's activation, without changing
    expected data or assertion predicates. Five independent copied-source mutants
    target dx omission, tube width, delay equality, corner omission and stall drop.
    make_tb.py emits the checked-in TB reproducibly. Reset interrupts12 phases,
    each followed by25 clocks checking no stale completion. No force/X dependency.
13. **Tools/limits.** Python3.13 locator confirmed. Icarus is available. Verilator
    and slang are absent from PATH/standard suite locations; WSL enumeration is
    denied. R-015 applies: lint and Verilator execution unverified, nothing installed.
    Options: OSS CAD Suite, MSYS2 Verilator, WSL Verilator, or Conda Verilator.
    README has portable Verilator5 --binary --timing --assert reproduction.
14. **Resources.** Splice itself has only add/compare/mux/control and816 payload
    flops before optimization. One constant position multiplication folds away.
    The unchanged private engine contains six divider pipelines: two each of
    96/128/160 bits; op3 only activates the96-bit pair. Reachable op3 expressions
    contain six variable product occurrences (five96-bit, one160-bit container),
    plus constant-scale multiplies. Full unspecialized engine also contains ramp
    and swept multiplier cones. Optimized multiplier/divider counts, sharing,
    mapped area, DSP count and187.5MHz timing require synthesis; none are claimed.
    Synthesis may prune unused opcode cones; no pruning is assumed in the report.
15. **SPEC-ISSUE.** Section8's historical PARA_NUM_W256 is superseded by S1b
    section5.5.1 and the accepted arithmetic ABI. B2 exposes no such parameter.
    Section13 estimates two helper dividers; the accepted unspecialized engine
    instantiates six. Preserve accepted code, disclose this resource excess and
    defer specialization to integration. Cycle compliance does not prove STA/WCET.
