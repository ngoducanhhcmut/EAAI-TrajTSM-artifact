# R9 decisions
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

1. Designer delegation supersedes R-005/006 and the module approval question.
   Scope is cert RTL, cert TB, filelist_R9.f and R9_*.md only.
2. Rules: VLSIT_RTL_Design_Rule.md v2 at the designer-specified template path.
   Read skill/rule, skeleton, Mealy example and accepted SEL. cert is a functional
   leaf (HIE-02 deviation); system top remains structural. Reset release and DFT
   override belong to the wrapper. No standard external bus is present.
3. Gap scan G-001..006: missing template headings 1.1/2.3/7.1/7.3/14.2/14.3.
   Resolve with spec 5.3/5.4/5.5.9/7/13/14 and accepted SEL reset/handshake.
4. Exact spec 9 B9_REQ=2904; no extra time port. The top schedules jobs on the
   20ms subcycle and independent deadline timer, sampling i_time_us into now32.
   cert samples the complete immutable request on acceptance, never refreshes
   time/apply/expiry while stalled, and has no timer or commit state of its own.
   Timer priority and tick coverage are top integration obligations (5.4/6.2).
5. One private accepted m_tsmx_arith instance, fixed opcode8, computes the lease
   serial difference expiry-generated. Other serial differences use explicit
   unsigned 32-bit subtraction and sign-bit tests (exact elapsed modulo2^32).
   No division is needed by B9. Arithmetic sources are unmodified.
6. All version/lease/ACK/margin parameters are locked to Config1; exposed typed
   parameters document the contract and must retain defaults. No runtime CSR.
7. Precompute: local snapshot/trajectory/seal are trusted only as outputs of the
   top-owned codec for these exact immutable records. No hash cache or codec here.
   expected_context is top's locally computed context; optional flags match API.
8. SPEC-ISSUE: range_schema cannot be represented for now/ta/te/seq/generated
   outside u32 or Python non-int on the exact B9 ABI (no parse_ok). Reject before
   packing; do not mask invalid input into an authorized job. TB records adapter
   rejects separately. No invented port or misuse of Plan.schema. Golden does
   not range-check Plan payload in B9; its digest binds it, earlier ingress guards.
9. Edge wrap_* rows omit at_executor although their expected statuses are executor
   results. Interpret those rows as executor invocations, as edge_cases.py intends;
   log fixture reconciliation and verify exact expected string before packing.
10. Response owns one context until consumed; no same-edge replacement. BOOT
    inhibits ready during reset. Full payload reset prevents stale authorization.
    B9 always drains its private arithmetic response before reporting status.
11. Half-wrap: compute now-apply separately for commit. Negating the sign of
    apply-now is not equivalent at difference0x80000000. Admission late_apply
    retains golden's original apply-now subtraction. No signed language types.
12. Icarus scheduling: helper valid is derived from cert's IDLE state, not from
    helper ready. Both IDLE states are synchronized by reset/response drain, so
    acceptance is identical, with no ready/valid combinational feedback path.
13. Oracle range: scalar out-of-u32, NaN sentinel and Python bool values are
    adapter rejects, counted separately. Valid u32 timestamps retain all patterns.
    Every local digest bit is inverted in a distinct test; expected binding comes
    from spec's top-facing precompute equality contract (golden computes internally).
14. Mutation campaign exposed a masked margin test: remaining==20000 also had
    expiry-apply<=20000, so a strict-remaining mutant survived. Added isolated
    phase_reuse tests with long original tail, plus isolated tail margin tests.
    No RTL behavior changed to accommodate a test. This is clear TB coverage
    analysis under R-026, resolved from golden without requiring designer input.
15. ARITH-ISSUE (area integration): elapsed needs no multiplier/divider, but the
    accepted generic helper elaborates two96/two128/two160 divider pipelines and
    motion multiplier cones. Opcode is fixed8 and never issues divide work; do
    not claim these resources are pruned without synthesis. Sources remain intact.
16. Tool constraint: Icarus is available; Verilator/slang discovery found none.
    WSL enumeration was denied. No software was installed; R-015 applies.
    Portable Verilator5 build/run commands are provided but execution is unverified.
