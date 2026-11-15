# R11 decisions — B13 health
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

1. Authority: explicit supervisor delegation supersedes skill R-005/R-006,
   the module-list approval gate, and R-026's request for a decision. No accepted
   source, spec, golden, vector or verification directory is modified.
   Rules are `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md`, v2.
2. Gap scan reports six BLOCK template-heading omissions: 1.1, 2.3, 7.1,
   7.3, 14.2, 14.3. Actual sections 5.3, 7, 13, 14 provide clock/reset,
   hierarchy and synthesis constraints. These formatting gaps do not prevent B13.
3. The main module `m_tsmx_health` preserves every specified physical port,
   HEALTH_REQ33824, B4_REQ176, aggregate Trajectory45458 and B3_REQ54042.
   `m_tsmx_health_bist` instantiates the unmodified accepted B4/B3 blocks and
   adapts streamed endpoints/terminal metadata to and from aggregate records.
   `m_tsmx_health_lane` is the structural integration top with private resources.
   The system top may instantiate the core and route its channels separately.
4. ABI array element0 is most significant. Count fields remain11 bits and the
   allocation remains1024 slots for every PARA_HEALTH_WORDS setting (1..1024).
   Counts above the chosen capacity or1024 reject before any array read.
   Unused words/parities are ignored, matching golden. Empty matching arrays pass.
   schema_ok preserves original word/type/onehot/parity guards before narrowing.
   Out-of-range counts cannot be legitimized by truncation in the test adapter.
5. Check one protected word per clock. Parity is XOR reduction of all32 bits,
   including bit31: all u32 encodings, including0x80000000, are valid words.
   SI measurement NaN/range restrictions do not apply to protected u32 data.
   Length mismatch, bad schema, bad onehot, lane disagreement or parity return0.
   This interface returns only healthy1, with no physical reason field.
6. Golden bist=False skips only the BIST. With bist=True, prior monitor failures
   may return0 without running BIST because golden returns before its BIST calls.
   There is no persistent passing status or cached BIST result across requests.
7. BIST requests b4(0,1000000,0,0,phase0,limit128). It requires accept1,
   stop_valid1,stop1100000, a count in1..129, and the exact final Row352
   (including its64 zero ABI padding bits). It then requires B3 clear accept1
   and blocked accept0. Golden does not compare full intermediate B4 rows or
   geometry reason/margin/steps inside b13_health; those values are transported
   unchanged and no extra acceptance restrictions are introduced.
8. B3 uses golden Motion defaults: length4800000,a0,event0,after_a0; clear
   x20000000, blocked x4000000. Lane is[-1800000,1800000],y0,half950000,
   lateral_error50000,reserve500000. Every unspecified object slot is zero.
9. SPEC-ISSUE: section13 estimates two B4/B3 pairs, while5.5.11 exposes one
   pair of channels. This implementation uses one dedicated accepted pair,
   generates once, then replays to clear and blocked jobs sequentially. There is
   no contention with functional lanes. Measured latency determines compliance
   with65536; the two-pair area estimate is not imposed on this lower-latency RTL.
10. B4 adapter captures each tagged row by its index, then concatenates the held
    terminal50 and padded129-row storage. B3 adapter captures the aggregate,
    issues an immutable tagged header, replays count-qualified rows and finally
    terminal metadata. Extra slots cannot enter the stream. Both dependencies
    share reset; reset aborts all local/private arithmetic contexts.
11. Ready is suppressed during asynchronous reset and enabled after the first
    released clock. One outstanding public job, no same-edge replacement.
    Invalid public/subrequest payloads drive zero. All responses remain stable
    under consumer stalls. No internal watchdog fabricates a missing BIST result;
    top owns timeout/drain/global-health-reset as5.3 specifies. Budget excludes
    arbitrary external backpressure; integrated private resources have none.
12. Examples: Moore FSM and VLSIT skeletons were read before generation; SEL
    supplies the public-channel style. Grouped next-state/datapath processes
    follow accepted blocks. Functional BIST adapter justifies HIE-02; only the
    lane top is structural. PAR-03 findings are fixed ABI/SI/golden constants:
    1024 slots,32-bit word,129 endpoints,352-bit Row,stop1100000,phase3100000,
    terminal xlo766660, lane extent1800000,half950000, actor positions20000000
    and4000000, initial velocity1000000. SI values are decimal fixed-point.
    These fixed representations are documented in every owned RTL header.
13. Verification derives expectations by importing unmodified golden. All direct
    B13 fixtures and B13 edge rows are enumerated (currently zero B13 edge rows).
    Legacy metadata drives field extraction; full fixture diagnostics are checked
    against vectors.evaluate, then health is converted by named fields. Seed1113
    adds2200 random cases plus legal/invalid count, parity, u32, onehot boundaries.
    Original out-of-range values map to schema_ok0, never masked into acceptance.
14. Injected BIST-resource tests corrupt accept, stop, terminal row, count,
    stop_valid, clear result and blocked result. Assertions include channel
    stability, reset, zero-invalid payloads, exact requests and healthy comparison.
    Sampled-output/scoreboard mutants test each named check independently; they
    flip the sampled observed bit and leave the expected value/predicate intact.
    They establish assertion sensitivity, not physical fault coverage.
15. Tool limitation: no Verilator/slang was found by vlsit_lint_rtl.py. WSL
    distribution enumeration returns E_ACCESSDENIED. R-015 applies: lint not run;
    Verilator5 compilation/simulation unverified. No installation attempted.
    Available installation routes: OSS CAD Suite (~600MB, no admin), MSYS2,
    WSL Ubuntu or Conda. Reproduction commands are in the unit README.
16. Capacity0 or1025 fails elaboration through an intentionally undefined
    diagnostic cell in a statically disabled generate branch for all legal
    settings. This guard also explains the core's HIE-02 checker warning; it
    introduces no live child hardware in a legal configuration.
    Filelist generation warns that the diagnostic module has no definition;
    this is intentional and legal configurations elaborate without that branch.
17. Supplemental no-stall measurement initially failed the R-025 inactive-check
    requirement: disabling all holds also disabled hold assertion activation.
    The latency values were produced, but that run was not a passing verification.
    The TB now retains directed protocol holds during the BIST stub preamble and
    disables holds only for measured real-resource jobs. Expected values and
    assertions were unchanged. The corrected run is retained in measure.log.
