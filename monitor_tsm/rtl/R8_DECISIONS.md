# R8 decisions
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

1. **Delegation and ownership.** User delegation supersedes skill R-005/006,
   module-list approval and R-026 question gates. Generate new ingress files only;
   accepted SEL/ARITH/CODEC, spec/golden/vectors/verify remain unchanged. Header
   and rules use the supplied values and VLSIT_RTL_Design_Rule.md v2 at the named
   `.agents/skills/vlsit-asic-ip-microspec/reference/templates/` path.
2. **Gap scan.** Six BLOCK findings are missing template subsections 1.1,2.3,
   7.1,7.3,14.2,14.3; `gaps.log` preserves them. Existing spec5.3/7/13/14 provides
   the necessary functional/clock/reset/implementation contract. These heading
   mismatches are resolved as formatting gaps under delegation; no spec edit.
3. **Interface.** Exactly section9.2: request1374 = Ingress332,now32,Ego256,
   Packet721,local_crc32,parse_ok1; response340 = Ingress332,reason8. First field
   is MSB; nested records have no byte padding. Tail is8 bits as the ABI specifies,
   despite FORMATS' compact signature notation. State validity flags preserve
   all32-bit sequence/timestamp encodings; invalid fields are canonically zero.
   `PARA_PACKET_LIMIT=65536` is locked; top enforces transport length.
4. **Codec boundary.** Top must derive local_crc from its own accepted codec,
   not trust a host-provided value. The block compares local_crc to Packet.crc;
   it does not instantiate or edit codec. CRC body is Plan+three IDs+schema.
   Packet-present0 skips payload checks after clock regression. The CRC KAT edge
   is checked in Python because CRC generation is not a physical B1 function.
5. **Arithmetic.** One private, unmodified m_tsmx_arith instance uses op8 for
   elapsed(now,last_time). It is issued even with time_valid0; only the validity
   flag determines whether the returned sign matters. Remaining ages use32-bit
   modular differences, testing sign before positive bounds. No general division
   or multiplication occurs in ingress; the position limit is a constant product.
   Position delta sign-extends both operands to65 bits before subtract/absolute,
   avoiding overflow even with a full-width freeze_x. No ARITH-ISSUE identified.
6. **Proposal/order.** Reject returns every input-state bit unchanged. Golden
   order is preserved, including Ego numeric/range before snapshot numeric/range,
   then plan numeric/range, count, compute, IDs, CRC, sequence and freshness.
   Success sets last_sample=snapshot.t. Equal signatures preserve freeze epoch/x;
   changed signatures set now/ego.x. Freeze requires age>=300000 and distance
   strictly>200000. Reject proposals are not persistent internal state.
7. **Parser contract / SPEC-ISSUE.** A single parse_ok flag cannot encode every
   Python malformed-value provenance and ordered multi-error combination. For
   example, an Ego range error precedes a snapshot type error in Python, while
   parse_ok0 must represent numeric failure before narrowed data checks. Physical
   implementation follows spec's parse_ok0 => numeric after clock/missing packet;
   direct representable records retain golden's finer numeric/range ordering.
   Adapter rejects invalid original types/s64 values before narrowing. Representable
   invalid count/tail/compute/schema domains map to out-of-domain representatives,
   never wrap into valid values; malformed IDs map to incoherent IDs. Out-of-u32
   time/sequence originals use parse_ok0. Such records are outside the wire domain;
   exact original failure provenance needs a future top-facing parse-reason field.
   No supplied B1 fixture requires that extension. Golden is never modified.
8. **Handshake/reset.** Moore example and SEL provide BOOT, IDLE and held RESP;
   ISSUE/WAIT reserve the private ARITH job. One outstanding request, no replacement
   on response-consumption edge. Measured latency4, unstalled II5; stalls extend
   II only. Reset asynchronously clears all local validity/payload and ARITH;
   wrapper owns synchronized deassertion and DFT reset override (spec5.3/7).
   Reset phase tests cancel acceptance, setup, return and stalled responses.
9. **Verification.** Reuse R1 semantic-name packing/SHA verification pattern,
   not fixture-hex offsets as physical ports. Import original golden for full
   expected state/reason; normalize JSON lists/tuples only. Check original fixture
   hex SHA256, accept/reason CRC/output digest and semantic output consistency.
   Deterministic seed0xB10008; all14 B1 reasons, boundaries, signed extrema,
   half-wrap, unchanged signature history and parser narrowing are exercised.
   First TB run found wrong request offsets in semantic field assertions while
   full response already matched; corrected offsets against9.2, no oracle change.
10. **Assertions/mutation.** Portable timed immediate assertions have distinct
    clause names and hit counts. Every assertion has a targeted single-bit XOR
    corruption of the actual DUT output wire and must itself fail nonzero.
    No expected value or predicate is mutated; no X/force or SYNTHESIS dependence.
    Eight separate source mutants check CRC, equal sequence, age/freeze boundaries,
    epoch refresh, last_sample, stall preservation and clock precedence.
11. **Style.** Enum reason codes and named SI bounds eliminate magic-number
    findings. HIE-02 is justified: ingress is a functional leaf containing a
    private arithmetic child; the system top remains structural. Header records
    this deviation. Fixed ABI widths are intentionally not configurable.
12. **Tools/signoff.** Icarus is present. Verilator/slang are absent from PATH
    and skill tool discovery; WSL launch returns E_ACCESSDENIED. No installation
    or privileged execution is attempted. R-015 applies: lint and Verilator
    simulation remain unverified. Replay script uses --binary --timing --assert.
    Options are OSS CAD Suite, MSYS2 Verilator, WSL or Conda, as printed in lint.log.
    No synthesis, STA, mapped resource, formal, CDC/RDC or DFT signoff claim.
