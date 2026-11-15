# I1 decisions
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

1. Designer delegation supersedes question/approval gates R-005/006/008 and the
   skill's module-list approval. Only I1-owned paths are written; accepted leaves,
   golden, original vectors and specification remain untouched.
2. Rules: VLSIT_RTL_Design_Rule.md v2 at the designer's exact template path.
   SKILL.md, rule.md, Mealy FSM example, skeletons and TB guide were read.
   Six gap-scan BLOCKs concern template heading numbers, not missing behavior:
   sections5.3/7/13/14 supply the facts. No specification text is changed.
3. Hierarchy: m_tsmx_top is structural. m_tsmx_rst synchronizes release;
   m_tsmx_io stages custom frames; m_tsmx_engine owns persistent golden state;
   m_tsmx_hash serializes local CRC/SHA; m_tsmx_math sequences accepted primitives;
   m_tsmx_sweep pairs accepted B4/B3 resources. One module/file, no simulation split.
   Functional children justify HIE-02 warnings; fixed ABI/SI literals justify PAR-03.
4. PARA_G/PARA_P default8, legal1/2/4/8. All requested G/P instances exist;
   min(G,P) contexts are paired when unequal. Unpaired instances remain inactive.
   All16 candidates execute in both sweeps; no early-out reduces measured work.
   B3's129 endpoint slots exceed S1b's35-slot minimum; rows stream without waiting
   for the complete trajectory. Accepted terminal validation controls commitment.
5. SPEC-ISSUE: golden Row occupies288 bits within zero-extended352 bits (R7).
   Command occupies1897 bits, right-aligned in arb1997 with100 zero MSBs (R10).
   Executor framing sends238 bytes with7 zero LSB pad bits, not250 bytes.
6. Every hash is locally computed by accepted codec. New tail Plan is hashed and
   Certificate resealed before pending ownership changes. Cached immutable hashes
   service timer/reuse B9 calls; no host hash serves as a local precompute.
7. Golden order: live/rollback, health, old pending, B1 proposal, B9, B2, reaction,
   nominal proxy, overrides, current sweep, bridge/propagation/tail, reuse replay,
   B8, ingress/pending commit, recorder, arbiter, transport, atomic CSR completion.
   Rejection updates only ingress.last_time. Supervisor controls pending/backup clears.
8. Timer ticks use a20,000us serial epoch grid, initialized from the first accepted
   request's current i_time_us rounded down to that grid (including cold boot near
   u32 wrap), and reinitialized on detected clock rollback. No authorization exists
   before that initialization. Each later tick adds multiples of20,000 modulo u32;
   a large valid jump coalesces missed ticks to the latest grid point. Exact ACK
   pulses and reached40ms/expiry boundaries also invoke cached checks, meeting
   section6.2's exact safety boundary independently of grid phase. Early ACKs are not retained. Expiry precedes
   ACK timeout; ACK suppresses timeout exactly as b9_cert. Backup expiry asserts
   override independently in L1 or when the last committed record remains the
   sole nominal authority (L0/RECOVERY without new pending). Wrong IDs cannot qualify an ACK.
9. Deadline counts acceptance as clock1 and expires at1,875,000. Response/brake
   bypass command/log/AXI readiness; outstanding leaves are drained, never secretly
   reset. New jobs wait for all dispatched resources to become idle.
10. Production health uses six parity-protected reductions of retained records and
    supervisor state, onehot mode encoding, and the accepted dedicated BIST pair.
    A separate single B4/B3 pair duplicates candidate0 during the current sweep;
    acceptance mismatch revokes production authority and feeds next-job B13 inputs.
    Direct mode supplies explicit HEALTH_REQ. CSR BIST pulses queue while busy
    and run while disabled; completion publishes bist_done/config validation.
    DFT/CDC/STA and injected physical internal-storage faults are not signed off.
11. Transport malformed-frame provenance is an internal reason sideband, never
    encoded as a valid numerical record. Invalid frames force numeric/L3; partial
    timeout forces timeout/L3. Two input slots and two immutable command slots.
    Frame staging timeout delivery and production framing still require regression.
12. CSR_UPDATE irq_set[7] marks a completed decision in the accepted CSR;
    completion uses0x81, BIST-only uses0x10. This preserves counters/reason capture.
13. The system fixture is a128-step continuous chain. Ten arbitration edges form
    another chain. Three imported L0 live-fault snapshots are whole-state equivalent
    to reset after the fault; the generator proves this before packing. Rollback
    uses a physical invalid-live request prefix to establish last_time, then proves
    the original response/retained ingress/latest event match. Fourteen system edge
    fixtures therefore require15 physical jobs; no hidden top preload is used.
    The other block edges belong to their accepted unit interfaces.
14. Seed0x1A20261029 generates500 six-cycle sequences/3000 decisions. Expected
    response, command projection, ingress, supervision, lost count and Event bits
    derive from the unmodified golden. Command projection follows spec5.5.13/R10.
    Fast timer probes initialize I1-owned cache registers; they do not test admission.
    The separate physical control TB, selected for Verilator, admits each real Plan
    before its timer boundary; it contains no cache deposits.
15. Assertion mutations are sampled DUT-output observation faults, not RTL source
    mutations or physical fault-coverage claims. All20 must fail their named check.
    The40-check smoke includes20 project AXI assertions; inactive checks are fatal.
16. Debugging: separated arithmetic request decode from ready-dependent state
    logic to remove an Icarus delta-event loop in the owned math helper. Isolated
    original B2 first-system request passes without any leaf change.
17. XSim2023.2 is installed, but its isolated accepted CSR probe has X next-state
    after reset; Icarus passes the same probe. O0 also fails. This is unresolved
    simulator compatibility, not evidence authorizing an accepted CSR modification.
    Verilator/slang unavailable; WSL invocation denied. No tools installed.
18. Open integration work is listed honestly in I1_REPORT.md; generated stimuli,
    elaboration, limited smoke or isolated probes do not establish full acceptance.
19. Wrong-ID ACKs queue a replay Event; overflowing that queue is drained as invalid
    recorder appends so lost accounting saturates through the accepted recorder.
    Timer status edges update CSR flags without counting another decision. Only
    real accepted decisions run the1875000-clock deadline; idle log/BIST work cannot
    create unsolicited decision responses. CSR reset cancels authority immediately,
    drains in-flight leaves and preserves stalled external frame contents.
20. A health/reset HOLD still emits the R10 parking command; the independent brake
    pin remains asserted. The pin ORs the last golden independent_brake telemetry
    with urgent health/timer/deadline and arbiter brake requests; this does not
    feed the telemetry into arbiter i_override. Brake telemetry never forces a valid L1/L2 command
    to mitigation. A final cached expiry guard precedes new arbiter publication.
21. The BIST-fault auxiliary TB corrupts only the dedicated BIST result's stop field.
    It drives health=True; the golden health=False path provides the containment
    oracle. This source fault is separate from the500 sequences' parity faults.
    Its execution/Verilator compatibility are not claimed unless a run confirms them.
22. Owned controller FSMs use explicit one-hot enums. The engine checks its actual
    state encoding, rather than re-encoding a binary state and calling it protection.
    Invalid/unknown encodings clear authorization/heartbeat and drain active work;
    inactive faults recover through BOOT. The top assertion checks the actual state.
23. B4 phase/row epoch is profile elapsed time, not the supervisor timestamp. Fresh
    fallback/proxy/tail sweeps pass phase0; bridge row tags also use0. Original-
    epoch backup replay uses the dedicated20ms math replay. An audit corrected the
    top's earlier timestamp-as-phase wiring; no accepted block was changed.
24. Only direct mode accepts the semantic TOP_REQ ACK Boolean. Production commit
    requires the external exact-ID ACK pulse; a planner frame cannot invent ACKs.
    Cached timer results preempt stale old-pending checker responses, and faults
    discard queued status so a later job cannot report an obsolete commit.
    A direct semantic ACK services the old pending record at acceptance, so it
    cannot be lost behind BIST latency. Wrong external IDs are still logged.

25. I1b CSR diagnosis: CSR_UPDATE[75]=pending,[74]=backup; the accepted CSR
    maps these to STATUS[6] and STATUS[7]. The old TB compared STATUS[7:6]
    directly to packed supervisor[pending,backup], reversing the two bits.
    Actual first-job STATUS=0x0001016a means healthy RECOVERY, pending=1,
    backup=0, bist_done=1 and conditional label=1, consistent with the oracle.
    The current full-word expected_status maps each bit separately. No accepted
    CSR or top wiring change is required. Profile count at0x30 is16; profile
    LIMIT at0x34 is128 cells. XSim2023.2 still returns profile0 and unknown
    CSR next-state in the isolated probe, including with a timed reset edge;
    Icarus passes. Do not reinterpret that simulator failure as a map change.
26. Helper reuse audit (I1b): m_tsmx_math contains one accepted m_tsmx_arith;
    it sequences ops3/4 for reaction, op3 for split actor propagation/bridge,
    and ops5/7 for original-epoch replay. These multi-call stateful helpers are
    not operations of the accepted primitive ABI (R2_REPORT). No divider,
    ramp integrator or swept arithmetic is reimplemented in this wrapper.
    m_tsmx_hash contains one accepted m_tsmx_codec; it supplies start/last,
    byte_count and big-endian four-byte beats for top-owned immutable records.
    CRC polynomial, SHA rounds, padding and length validation remain in the
    accepted codec. The names denote orchestration wrappers, not alternative
    arith/codec implementations. probe_helpers.py independently checks400
    composite math jobs and400 typed CRC/SHA jobs against unmodified golden
    packers plus hashlib/zlib; execution results must be read from its logs.
27. The worst.mem input uses legal maximum10m/s with initial a=0 and32 actors.
    Config1's proven stop+hold horizon is7.6s (spec9.1), below the12.8s storage
    cap. Requiring128 physically reachable cells would contradict that domain.
    The timing monitor prints actual max rows, both16-candidate masks and
    B4-to-B3 overlap; WORST additionally fails absent either complete sweep,
   32 actors, streaming, or on exceeding1168034 clocks. This is a measured
    maximum-load input, not a proof of unconditional128-cell WCET.
28. I1b evidence names include simulator and optional category tag, preventing
    XSim diagnostics from overwriting a concurrent Icarus category's log.
    Default control execution now uses physical Plan admission with either
    Icarus or Verilator; --timers-only remains the explicitly cached probe.

29. I1b helper regression isolated a zero-time Icarus event loop at job6,
    math OBJ state, after a replay with nonzero retained phase. The decoded
    object/acceleration/jerk process made default-then-override writes to
    signals consumed by other combinational processes. Replace these three
    pure decodes with continuous expressions, including explicit sign-bit
    comparison for jerk direction. Snapshot: tb/integ/m_tsmx_math_before_I1b.txt;
    failing diagnostic: helpers_delta_sim.log. No algorithm, latency state,
    accepted primitive, clock or reset changes. build_rtl.py emits the same fix.
    The corrected helper passes400 composite math jobs and400 typed CRC/SHA
    jobs against independent golden calculations. This supplies bit checks of
    the wrapper glue in addition to actual accepted-leaf reuse (D26).
30. Eight additional physical jobs establish the requested mode chain without
    deposits: RECOVERY,RECOVERY,L0,L1,L2,L3,HOLD,RECOVERY. Generated corpus now
    contains3151 jobs:128 system,15 edge,8 transition and3000 new sequence jobs.
    Original system.hex checksum and every supplied semantic transition are
    revalidated by the generator. Three-event health/parity faults remain
    distinct from the auxiliary TB's actual dedicated-BIST stop corruption.
