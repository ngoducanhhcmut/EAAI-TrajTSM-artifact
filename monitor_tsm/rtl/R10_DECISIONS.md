# R10 decisions — m_tsmx_arb
Project TSM-X; author TSMX project; version0.1; date2026-10-29.

1. **Delegation and scope.** The user delegates every decision and forbids stopping.
   This supersedes skill R-005/006, module-list approval and ambiguity gates.
   All generated sources/evidence stay under arb RTL/TB, filelist_R10.f or R10_*.md.
   No accepted RTL, golden, vectors, spec or verify file is edited.
2. **Rules and style.** Read skill SKILL.md/rule.md and the supplied
   `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md`
   v2 completely. Moore example, skeletons, TB guide and accepted SEL pattern apply.
   BOOT/IDLE/RESP use separate next-state, output and sequential processes.
   HIE-02 is a functional-leaf exception, declared in the header; top remains structural.
3. **Gap scan.** Six BLOCK findings are missing template headings1.1,2.3,7.1,7.3,
   14.2,14.3, not unresolved arb behavior. Existing5.3/7/13/14 supply the contract.
   R10_GAPS.md retains the exact scan; delegation resolves these formatting gaps.
4. **SPEC-ISSUE: Command width.** Section9 lists W_CMD1997, but its fields sum1897:
   3+3+8+8+32+32+32+560+1217+1+1. Golden `pack_command` emits exactly1897 bits,
   with7 outer byte-pad bits. Preserve physical o_rsp_data[1996:0]; right-align
   the golden record in[1896:0], set[1996:1897]=0. Do not interpret spare100 as
   a partial hash or new field. Request3863 is consistent as written.
   Top/executor must use this layout; global spec/codec correction is outside scope.
5. **Delegated source codes.** source3: nominal0, backup1, fallback2, mitigation3,
   parking4; codes5..7 reserved. These codes are absent from spec/golden enums.
   They do not change mode codes0..5. Invalid input modes6/7 fail to modeL3.
6. **Authority.** L0/RECOVERY select pending; L1 selects backup. Their valid flag
   means top has completed B9 plus applicable admission/reuse checks. Also require
   Certificate.present; missing either forces L3/id15. Do not redo hashing, lease,
   geometry, ACK or world checks. Preserve the entire original Plan/Certificate,
   including seq, apply, expiry and all four256-bit binding fields. Command candidate
   is Plan.tail and label1; independent B7 candidate/label are not nominal authority.
   An incoherent but asserted authorized flag is a caller contract violation;
   bit-forwarding tests intentionally vary hashes to prove this mux does not rewrite them.
7. **Local commands.** L2 requires candidate0..15 with nonzero library jerk
   (mask0x7777) and label1. Other L2 encodings fail to L3/id15/label2.
   HOLD uses source4, candidate15, label2, parking1, override0; top guarantees
   standstill before selecting HOLD. L3 always uses source3/candidate15/label2,
   parking0, override1, regardless of the independent selector result.
   These source-only records have no certificate. To carry the state required by
   the executor, their Plan contains seq0, snapshot=Ego, generated=apply=now,
   x/v/a=Ego.x/v/a, tail=command candidate, compute0, count0, schema1.
   Envelope apply=now, expiry=now+100000 modulo u32. This is a local one-step
   command envelope, never a B9 certificate or evidence of nominal authorization.
   HOLD is distinguished by parking; executor must not interpret its tail as a
   moving fallback. These otherwise unspecified metadata choices need matching
   top/executor integration; standalone golden has no local Command constructor.
8. **Override.** High i_override at acceptance selects mitigation. A later override
   asserts o_brake combinationally, independent of clk/ready, and is retained at
   the next rising edge. It never mutates an accepted/stalled Command. Brake stays
   asserted until a new command with override0 is accepted while i_override is low.
   Consuming a frame does not withdraw brake. A pulse shorter than a core cycle
   asserts brake during the pulse but needs the external watchdog/controller to
   hold its level until sampled; this leaf is not an asynchronous pulse latch.
9. **Timer boundary.** There is no continuous now input in ARB_REQ. Top owns
   subcycle B9 checks and drives i_override on expiry/timeout, including while
   egress stalls; executor rechecks epoch on receipt. `independent_brake=not accept`
   is telemetry, not i_override: it must not replace valid L1/L2 commands.
   Neither heartbeat generation nor stopped-clock detection belongs in this mux.
10. **Arithmetic applicability.** This source mux has no arithmetic lanes, multiply,
    divide, profile evaluation, replay, signed comparison or numeric integration.
    The only arithmetic is the explicit32-bit constant local-envelope increment;
    its wrap is deliberate serial timestamp behavior. No shared arithmetic primitive
    is needed/instantiated, and no replacement arithmetic implementation is added.
    The request to use private accepted arithmetic applies when a block performs
    those operations; instantiating an idle divider would add no functionality.
    R2 files/interfaces/latencies were read and are untouched. No ARITH-ISSUE found.
11. **Parameter restrictions.** Profiles16 and mitigation15 are locked defaults.
    Unsupported overrides inhibit all safe-source selection and emit fixed id15.
    This is a fail-closed hardware guard rather than a simulation-only elaboration
    failure; users must keep the documented legal values. No SYNTHESIS conditional.
12. **Golden projection.** No arb-specific vectors/function or executor/watchdog
    implementation exists in the supplied model.py. README49..63/spec5.5.13 are
    the authority map. Replay all128 system ports rows and14 system edge rows
    through unmodified tsmx_cycle; compare complete state/telemetry to fixtures.
    Verify system.hex SHA256, summary fields, reasonCRC/digest and vectors.py
    conversion before projecting resulting mode/pending/backup into ARB_REQ.
    Golden packing supplies every expected nested bit; choices4/5/7 define only
    the otherwise missing physical command projection. Report projections honestly,
    not as an independent golden arb implementation.
13. **Coverage and invalid inputs.** Seed101024 yields2600 random jobs; exhaustive
    byte candidates/labels, all modes/valid/override combinations,256 hash patterns,
    wrap/min/max fields and40 golden B9 timer cases supplement fixtures. Six original
    numeric sentinel/range violations reject with live_ego_valid before packing;
    no parse_ok port exists here, so no masked invalid scalar is counted as RTL.
    Missing flags/present, malformed modes and invalid selector reasons are physical
    fail-closed cases. A specific B9 expiry vector triggers override during a held
    nominal frame. Queued requests and reset-aborted responses test transport.
14. **Assertions/mutations.** Thirty-six named, hit-counted immediate assertions
    compare every output bit, fields, reset, ready/valid, stalls, override and
    source-specific authority. Each gets a separately activated DUT observation-wire
    bit-flip mutant and must fail that exact assertion with nonzero exit. Assertion
    operands are unchanged; no force/X or simulator-only RTL branch is used.
    Nine independently compiled source mutations cover authority, epochs, expiry,
    record guard, instant selection, stall, sticky brake, hash and immediate override.
15. **Measurement/tools.** Acceptance edge is cycle1, as accepted SEL. Production
    latency excludes consumer stalls; II counts successive acceptance edges. Report
    minimum II2 as unstalled, maximum only for exercised stalls, not a WCET under
    arbitrary backpressure. Icarus constant-select sensitivity notices mean all
    bits are included; they are not lint results. Verilator/slang unavailable;
    retain failed attempt and R-015 install options without claiming compatibility.
