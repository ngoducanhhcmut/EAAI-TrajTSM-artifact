# R7 decisions
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

1. **Authority and scope.** The designer delegated all decisions and instructed no
   questions. This overrides skill R-005/R-006 and the module approval gate. Only
   `rtl/geom`, `tb/unit/geom`, `filelist_R7.f`, and `R7_*.md` are written. Accepted
   arithmetic, golden, spec and vector sources are read only. Rule file is the
   requested `VLSIT_RTL_Design_Rule.md` v2. Skeleton, Mealy example, TB guide and
   accepted SEL implementation were read before generation.
2. **Template gaps.** Gap scan reports six missing headings: 1.1, 2.3, 7.1, 7.3,
   14.2, 14.3. Existing spec 5.3/7/13/14 supply the relevant leaf contracts.
   Core clock is 187.5 MHz; asynchronous active-low reset release is synchronized
   by the wrapper. The leaf does not duplicate reset synchronization or DFT overrides.
3. **SPEC-ISSUE: Row352.** Seven declared fields and golden `pack_row` occupy288
   bits. Golden `pack_trajectory` zero-extends each row into352 bits. Retain the
   physical401-bit row stream, with64 zero MSBs in Row352, then phase32,xlo64,
   xhi64,vlo32,vhi32,a32,jerk32. Nonzero padding is numeric-invalid. This agrees
   with the existing B4 vector converter. Never shift fields to fill the unused bits.
4. **Stream ownership.** Request is cid8,epoch32,World8200,Lane384. Row tags must
   match cid/epoch and monotonically increasing index. Tag errors reject trajectory.
   Terminal accept and row count determine trajectory validity; terminal reason/stop
   do not affect golden B3. `last` is advisory because failed B4 partial trajectories
   legitimately have no last row. Requester must supply exactly terminal.row_count
   rows (at most129), stable data until handshake, and one terminal record. Missing
   rows/terminal are handled by the top's bounded timeout/drain contract, not an
   invented local timeout. No same-edge response replacement is supported.
5. **Storage and speculation.** Allocate129 resetless row slots (exceeds the S1b
   minimum35) plus32 actor interval slots. Request initializes actor slots; count
   guards row reads. Rows and terminal can arrive independently while geometry
   runs. No full-trajectory buffering prerequisite exists. Speculative separation
   stops geometry but does not stop row ingestion or endpoint validation.
6. **Golden precedence.** Resolve trajectory, row numeric, lane range, object count,
   lateral containment, all object ranges, final horizon and actor speed before
   provisional time/separation results. Lane types are an upstream parsing duty.
   Return exactly accept, signed margin, enum reason and steps; first failing
   actor/piece follows input order. Equality with reserve accepts. The initial
   margin remains10000S, including when there are no actors.
7. **Preflight arithmetic.** For nonnegative p=max(0,a,after_a), exact
   v+ceil(p*H/T)<=20S is equivalent to p*H<=(20S-v)*T. This removes a division
   without approximating the final-horizon check. Actual H is used, never12.8s
   as a substitute rejection threshold. Positive actor upper-v is intersected
   with20S after each piece, exactly as golden.
8. **Private arithmetic.** Instantiate accepted `m_tsmx_arith_div` unchanged.
   `m_tsmx_geom_swept` schedules its seven exact candidates through two s128 II1
   pipelines; `m_tsmx_geom_adv` issues four outward x/v pairs through two s96 II1
   pipelines concurrently with swept. Two additional s96 pipelines compute the
   two inflate ceilings once per row. No serial divider or slash/modulo operator.
   No ARITH-ISSUE was found: the exposed divider supports every required quotient.
9. **Widths and stop phases.** Use s128 rational products, unsigned s64 containers
   for rational n/d and explicit two's-complement tests, s96 integer-time products,
   and s64 pose/gap/margin. Seven slots are endpoints, both stops, and relative
   stationary points for both-active/front-only/rear-only phases. Invalid slots
   issue zero-over-one, equivalent to the already included t=0 endpoint. Stop
   clipping and front-floor/rear-ceil remain exact. Four advance quotients issue
   in order actor lower/upper, ego lower/upper. Pieces preserve the initial ahead flag.
10. **SPEC-ISSUE: P/G.** Historical P4/G4 text conflicts with S1b. This module is
    one lane; top instantiatesP8. II48 is per complete actor-cell, including event
    pieces, not per quotient. Resource expansion relative to section13 is explicit;
    no mapped area or187.5 MHz timing result is inferred from simulation cycles.
11. **SPEC-ISSUE: typed fixtures.** `noninteger_extent` supplies float4.8, which
    cannot exist on the integer-only RTL ABI. The converter detects noninteger
    object fields before narrowing and encodes length0 (object_range). It verifies
    original and adapted golden GeomResult equality. No float is silently truncated
    into a valid actor. Fixture-only trajectory reason `cell` is encoded as ok;
    B3 does not inspect that reason. Extra `exact_min_gap` metadata is not an output.
12. **Parameters.** PARA_MAX_OBJ supports1..32; PARA_MAX_CELLS supports1..128,
    defaults32/128. Wire ABI retains32 actor slots and an8-bit row index/count.
    Config1 remains the default. Unsupported elaboration values are outside the contract.
13. **Simulation behavior.** Operand reads are independent of arithmetic ready.
    Group callers of shared combinational functions as in accepted arithmetic to
    avoid Icarus sensitivity churn. No SYNTHESIS conditional or functional bypass.
14. **Tools.** Python3.13 and Icarus are available. Verilator/slang discovery found
    neither; WSL reports E_ACCESSDENIED. R-015 applies: lint and actual Verilator
    compilation are not claimed. Reproduction commands and installation options
    are in the TB README and lint log. No tool is installed without authorization.
15. **Verification mutations.** Each named assertion has its own DUT-output-wire
    bit-flip mutant, with no force/X-dependent behavior and no alteration of the
    expected operand. Mutation is temporary and verification-only. Every full81-bit
    response is scored from golden; schedule observation never supplies expected data.
16. **Warnings and manual audit.** All three HIE-02 warnings identify functional
    leaves, not the system structural top. PAR-03 warnings cover fixed SI coefficients,
    explicit extension counts, row/actor bounds and fixed candidate-slot counts;
    these are dimensional formula/ABI constants rather than configurable quantities,
    with the same rationale as accepted R2. Headers record both warning categories.
    NAM-01/05, COM-01, SEQ-02/04, RST-01, P9/P15/P16 and PRT-01 were inspected:
    zero-based replicas, one owner per signal, unsigned4-state data, explicit next
    state, reset validity, pure functions, only core posedge clocks, no gating or
    external standard bus. RST-02/04 and CLK-01/P28 are wrapper responsibilities;
    this lane has no CDC. SCP-02/CHK-11 synthesis, RAM inference, reset-cell mapping,
    STA, formal, CDC/RDC and DFT signoff were not performed. Lint-only checks
    TYP-03/COM-05/ARI-01/P5/P8/P23 are not claimed clean by a lint tool; Icarus
    elaboration, manual sizing review and executable simulations provide partial evidence.
17. **Failure analysis.** Initial job159 (edge `noninteger_extent`) expected
    object_range/step0 but packed4.8 as integer4 and accepted. Spec9.2 explicitly
    requires original type rejection before narrowing. The converter was wrong;
    the integer RTL guard was correct. Encode invalid extent0 before packing,
    prove original/adapted golden equality, and rerun the affected100-case shard.
    Other shards use identical input words; only this typed-adapter case changed.
    The final aggregate2615/2615 and the independent34-case stalled-edge run pass.
    All26 output mutants and three independent source mutants fail as required.
