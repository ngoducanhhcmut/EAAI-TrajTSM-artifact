# R2 arithmetic decisions
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

1. **Authority.** The designer explicitly delegated all decisions. This supersedes
   skill R-005/R-006 and the module-list approval gate. No baseline file is changed.
   RTL rules: `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md`, v2.
   Moore example and skeleton were read; SEL supplies the public handshake pattern.
2. **Gap scan.** Six BLOCK findings concern missing template subsections 1.1, 2.3,
   7.1, 7.3, 14.2, 14.3. Existing spec 5.3, 7, 13, 14 give the arithmetic clock,
   reset, hierarchy and implementation contract. These formatting gaps do not block
   generation under delegation. No spec or golden file was edited.
3. **ABI.** Exactly spec 9.2: req[1927:1920]=op; req[1919:1760]=q0,
   followed by eleven s160 slots in ascending order. Response[640]=fault,
   [639:480]=q0, [479:320]=q1, [319:160]=q2, [159:0]=q3.
   Undefined opcodes, nonzero unused input slots, malformed booleans and guards
   fault, returning all four output slots zero. There is no reason-code sideband.
4. **checked.** Supported bit counts are 1..160, with the strictly asymmetric
   negative endpoint in golden `checked`. bits=1 admits zero only. Python's
   internal checked(...,256) guards are not callable 256-bit datapaths. All
   consumed arithmetic measurements reject their minimum-negative sentinel.
   elapsed timestamps are unsigned and retain all u32 encodings including 0x80000000.
5. **Primitive domain.** advance/swept use v=[0,20S], a=[-8S,2S], h=[0,12.8T].
   disp uses n=u46, positive d=u24 and the same motion bounds. A quotient or
   displacement that does not fit its output s64/s32 faults. gap/x are checked
   s64, not ingress-limited positions: internal translated positions remain useful.
   ramp/continuous use h=[0,100000], j=[-8S,8S], target=[-8S,2S], the same v/a
   bounds, and checked s64 x for continuous. profile has cid=0..15, checked s32
   time, initial=[-8S,0]; negative elapsed time clamps to zero as golden specifies.
   These envelopes are necessary because standalone Python helpers omit some
   guards assumed at their B2/B3/B4 callers. Slot padding is enforced before use.
6. **Widths.** Integer disp products/division are s96. Rational disp products and
   division are s128. Ramp xn is s160, xd occupies u136 of its s160 wire slot,
   vn is computed s112 then extended, vd is computed u88 then zero extended.
   The standalone ceildiv is s160. No 256-bit arithmetic is used. Request slots,
   time-candidate containers, checked result addition and sign helpers use s160
   to preserve ABI high-bit validation and detect narrowing faults. Swept time
   products currently use these 160-bit containers, wider than the proven s128
   need: this avoids a separate sign-extension path and preserves checking;
   this is an explicit area deviation, not a claim that the S1b proof needs s160.
7. **Division.** `m_tsmx_arith_div` is an exposed internal II1 pipeline. PARA_W
   supports 96/128/160; each stage performs sixteen explicit restoring steps.
   No slash or modulo division operator is present in RTL. There are paired
   pipelines per width, allowing simultaneous x/v or floor/ceil displacement.
   Payload registers reset with validity. Positive denominator is mandatory.
   Negative inexact floor adjusts magnitude; positive inexact ceil adjusts it.
8. **Swept.** Evaluate seven slots: 0,h,t_stop_a,t_stop_b and stationary roots
   for both active, a-only active and b-only active. Stop and stationary slots
   are qualified by strict horizon and phase inequalities; inactive slots issue
   harmless zero-over-one jobs. Duplicates do not affect the minimum. This is
   equivalent to golden's sorted stop cuts without hardware sorting. Faults
   accumulate while all seven jobs drain, preventing a stale job overtaking reuse.
9. **Continuous stop.** Test endpoint vn sign, then golden's integer bisection
   until hi-lo<=1 (at most17 tests). Integrate at lo; upper x adds ceil(v/T),
   both velocities return zero. Do not replace this with endpoint-only clipping.
10. **Handshake.** One public request context; no same-edge response replacement.
    Reset aborts context and divider validity; first released edge enables ready.
    Consumer stalls do not enter production latency. Wrapper owns reset release
    synchronizer, DFT reset override and timeout response draining, as spec 5.3/7.
11. **SPEC-ISSUE: integration scheduling.** Spec 10.3's B3 II48 describes a complete
    actor cell, not an ARITH command. This serialized public command controller
    alone does not establish the two-piece actor schedule. Integrators can use
    the exposed II1 divider leaf, or equivalent inlining (spec 5.4), with actor
    contexts and microcode. Six physical divider pipelines here exceed the
    per-context counts estimated in section13; unused width pairs can be pruned
    in a specialized integration. Do not claim whole-system WCET from this unit.
    Ramp expressions are combinational and need synthesis/retiming for187.5MHz.
12. **Tool/style decisions.** Icarus12 cross-process automatic-function sensitivity
    caused a zero-time oscillation. One ordered combinational arithmetic process
    plus one sequential state process fixes it without build-dependent behavior.
    This is a documented Moore-example process-grouping deviation. HIE-02 warning
    is justified: arith is a functional leaf, the system top remains structural.
    PAR-03 literal warnings name160 (ABI width),2 (quadratic coefficient),T=1000000,
    2T=2000000 and2T^2=2000000000000. These fixed SI formula coefficients are
    explained here and in function comments; scale is not an elaboration option.
13. **Oracle.** There is no arith fixture file. gen_vectors.py imports unmodified
    golden and emits 2200 random trials per opcode, boundaries, faults, and
    deduplicated helper calls captured while replaying every b2/b3/b4 semantic
    fixture and relevant edges. Full block outputs are first cross-checked with
    fixtures. Edge `exact_min_gap` is diagnostic metadata, not a GeomResult field;
    only fields actually returned by golden are compared there. Fixture SHA256s,
    per-op counts and seed are retained in vectors.json. checked(...,256) internal
    guards are excluded from helper calls because they are not physical requests.
14. **Verification strength.** All641 response bits are compared, including fault
    and zero padding. Each named assertion has a hit count and a separate flipped
    DUT-output-wire mutant that must fail that assertion. Six independent source
    mutants exercise real datapath/control defects. No force/X-dependent mutation
    or simulator-specific RTL branch is needed; the same TB supports Verilator.
