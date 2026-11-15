# R3 codec decisions
Project **TSM-X**; author **TSMX project**; version **0.1**; 2026-10-29.

The user delegates all designer decisions to the supervisor and authorizes new RTL,
TB, vectors, mutation copies and evidence within the R3 ownership paths. This
supersedes the skill's question/approval gates R-005/006 and initial module approval.
No existing shared RTL, golden, spec, vector or verify source is changed.

| ID | Resolution and rationale |
|---|---|
| D01 | Use VLSIT rule v2 at `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md`; headers use the user-supplied project/author/version. Structural `m_tsmx_codec` instantiates `m_tsmx_codec_core`. Both use the physical 45-bit request and 289-bit response in spec9.2. No new sideband ports. |
| D02 | Gap scanner reports six missing-template BLOCKs: purpose1.1, compliance2.3, clocks7.1, reset7.3, hierarchy14.2, synthesis14.3. The actual prose in spec5.3/5.5.2/7/14 supplies these contracts; they are section-number mismatches, resolved under delegation. Read-only specification remains unchanged. |
| D03 | Packed request is `{op8,start1,last1,byte_count3,data32}`. First byte is data31:24. Every nonfinal beat has count4; final count1..4. Unused low data bytes must be zero. Only raw empty jobs permit count0 with start=last=1. Start is mandatory on the first beat, forbidden thereafter; opcode must remain constant. State changes only on valid AND ready. |
| D04 / SPEC-ISSUE | Spec supplies only fixed-size op0..4, but asks for general empty CRC/SHA behavior and the task requires random lengths0..max. Reserve diagnostic op5=raw CRC, op6=raw SHA in the same ABI. They execute the same datapaths and accept lengths0..32768. These are supervisor-defined extensions, not a change to op0..4. Top must not issue op5/6 for production record binding. Unknown op7..255 faults. |
| D05 | Fixed lengths: op0=86, op1=32, op2=70, op3=1049, op4=120 bytes. Maximum is `PARA_HASH_BYTES=32768`, locked Config1, as in the specification. No record-sized whole-job RAM. Per-beat length is checked before acceptance effects; oversized/final-short jobs fault. CRC op0/5 returns `{0,crc,0}`; SHA op1..4/6 returns `{0,0,digest}`; a fault returns `{1,0,0}`. |
| D06 / SPEC-ISSUE | “Malformed size/schema” has no complete codec validator definition. Validate Plan schema32=1 (bytes66..69 in op0/2), outer packet schema32=1 (bytes82..85 in op0), context count<=32, zero unused World slots and frame/units32=1. Numeric, type, enum, original overflow and admission guards belong upstream: the stream has no parse_ok bit and cannot recover information lost by packing. Seal capability/config fields are hash material, not codec schema. |
| D07 | Faults abort at the first accepted malformed beat and produce a held fault response. Host stops the rest of that job, consumes the response, and begins the next job after ready returns. No hidden cancel/reset. A rejected beat cannot contaminate the next job. This avoids waiting forever for last on an invalid stream. |
| D08 | Two 512-bit input banks plus a 512-bit sliding schedule; producer fills a free bank at one 32-bit word/cycle. Engine copies a full bank, then performs64 rounds and one feed-forward cycle: compression starts every66 cycles when buffered. Filling continues during compression; occupancy gates ready. Padding locally appends80, zeros and the unsigned64-bit big-endian bit length. Final partial word is retained. |
| D09 | No request acceptance during local padding, final drain or response. A response holds every bit until consumed; data is zero when invalid. Response consumption goes through BOOT, then IDLE, introducing two clocks before another first-beat acceptance. BOOT also permits ready on the first released edge. Producer gaps and consumer stalls are external time, excluded from computation bounds; internal ready stalls remain charged. |
| D10 | Reset asserts asynchronously, clears partial jobs, buffers, schedule, state and response. Core release is synchronized by the system wrapper per spec7. No leaf reset synchronizer, gating, CDC, DFT override, retained authorization, or conditional synthesis behavior. Unused FSM encodings recover through BOOT/EMPTY with cleared occupancy. |
| D11 | CRC is reflected IEEE polynomialedb88320, init/final XORffffffff. SHA constants/round equations implement FIPS180-4. All additions intentionally wrap32 bits; all state is unsigned. No multiplier, divider, `/`, `%`, JSON, decimal conversion, UTF-8 serializer, truncated digest or simulation substitute exists in RTL. Embedded certificate hashes are raw256-bit values; only outer records have byte padding, performed by the golden packers/top before this byte stream. |
| D12 | TB conversion walks every nested relevant Ego/Plan/Certificate/context in b1/b9/system and edge port fixtures; fixture hex SHA256 metadata is checked before conversion. Packet CRC is recomputed over the body, including when the supplied packet CRC is deliberately corrupt. Seal is recomputed over the supplied immutable certificate fields, including deliberately tampered certificates. Fixture-only diagnostic hashes never become wire fields. |
| D13 | Generated random/field-boundary jobs use golden packers and an independent Python zlib/hashlib oracle. Cover two's-complement extrema, sentinel/one-past-width masking, timestamps, IDs, schema, Plan count/tail, all World counts0..32, object order, raw embedded hashes, empty/leading-zero digests, 55/56/63/64-byte padding edges and32768-byte maximum. Invalid original numeric data is tested as hash material, not falsely declared admitted by the codec. |
| D14 | Thirty explicit immediate assertions follow accepted sel TB portability/style. They cite spec5.3/5.5.2/7/10.3 and count activation. Each has its own verification-only DUT-output stuck-X mutation, with nonzero exit and the targeted assertion ID required. Also mutate six real RTL source behaviors in separate copies. These fault-injection demonstrations are Icarus evidence; X-force detection is not claimed for Verilator's two-state simulation. |
| D15 | The checker requires32-bit localparams, so SHA IV and K constants are named individual32-bit localparams; an automatic function concatenates/decodes them. PAR-03 warnings for round selector literals2..9 are intentional FIPS round indices, not unnamed hardware configuration. All64 selector encodings are explicit with a safe default. |
| D16 | Reference skeleton and Moore/Mealy examples guide separate combinational next-state/output and sequential state processes. `build_rtl.py` records the source recipe; it is not required for verification. `gen_vectors.py`, `build_tb.py`, and `run.py` regenerate the independent stimuli/TB and evidence without editing delivered RTL. |
| D17 | No Verilator/slang was found by the skill tool locator; attempted WSL enumeration is denied by the environment. Record R-015 and provide replayable Verilator5 build in run.py. No installation, network access, mapped synthesis, STA, memory inference, formal, CDC/RDC or DFT signoff is claimed. |

Verification corrections are recorded here rather than changing reference behavior:
the first context beat uses its newly accepted count when validating unused slots;
the driver stops unaccepted remaining beats on an early fault response. Both follow
D03/D06/D07. The first temporary source-generation path was corrected immediately;
those temporary files/directories were moved/removed, leaving only owned paths.

D18 / verification correction: at cycle1746526 the malformed first beat with
start=0 correctly returned `{fault=1,crc=0,digest=0}`, but the TB's response_has_job
assertion failed because its monitor created pending only on start=1. Spec5.3
defines acceptance by valid AND ready, including invalid payloads; D07 requires a
fault response. Fix only the monitor: the first acceptance with no pending job
creates the pending token. A spurious start in the middle does not create another
token. Re-run the complete suite and all mutants after this correction.

D19 / RTL correction: focused fault job51 (context count0, byte100=ff) returned
the altered SHA0936cd49... instead of fault. D06 requires zero unused World slots.
Inspection found the new `w_objects` temporary undriven because a source-recipe
text replacement matched a quoted literal incorrectly. Assign it explicitly from
reg_objects, or the first beat's count when reg_len=0, in the source template.
The independent expected fault remains unchanged. Run every fault in a focused
regression, then re-run the full suite. This is an RTL schema-validation bug, not
a golden discrepancy. Lint remains unavailable and is not reported as passed.

D20 / verification scope: supplement `format_boundaries.py` covers all golden
pack_* record families with263 physical-domain/wire-width endpoint jobs, including
records outside production op0..4 using raw CRC/SHA. This covers outer-only padding
of bit-unaligned Packet/Certificate/Trajectory/Ingress/Geom/Event/Command/TOP_RSP/CSR
records as well as every Row/Motion/Lane field. Main timing regression uses +NOGAPS
to measure literal acceptance-to-response bounds; focused and boundary regressions
retain reproducible producer pauses and consumer stalls. No hidden reset/cancel or
different RTL implementation is used by any test variant.
