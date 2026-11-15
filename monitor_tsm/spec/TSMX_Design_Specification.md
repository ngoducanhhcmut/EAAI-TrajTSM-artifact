---
document_id: "TSMX-V1-S1-SPEC"
title: "TSM-X v1 Design Specification"
ip_name: "TSM-X"
version: "1.0"
status: "Implementation contract; conditional timing and reference gaps recorded in section 20"
author: "S1 / Codex"
date: "2026-10-29"
language: "English"
owner: "TSM-X HW project"
---

# TSM-X v1 Design Specification

## 1. Purpose and scope

Implement a planner-independent longitudinal safety supervisor. PLAN A1–A7 are binding;
the current golden functions define exact behavior. The unit of supervision is one
100 ms decision transaction; it is not one RTL clock. Every normative contract below
belongs to a requirement in section 3. Architectural choices carry section 20 assumptions.

| Included in RTL | Boundary / exclusion |
|---|---|
| B1, B2, B3 ×4, B4, B7, B8, B9, B10, B13, CSR, streams | B12 executor, B11/B14 monitors and actuator are external |
| Straight, axis-aligned braking and lane containment | No lateral maneuver, lane change, shoulder search, B5/B6 ranking or B15 |
| 16 profiles, 32 objects, 128 cells, stop plus 2 s hold | No object relevance truncation; overflow rejects |
| Ego 0–10 m/s, decimal fixed point | 20 m/s ego extension is parameter accommodation, not a validated Config1 mode |
| CRC/SHA binding, parity, BIST, lane comparison | No cryptographic authority, ISO 26262 certification or independent-clock watchdog inside this IP |

## 2. Applicable documents and standards

| Priority | Local source | Applicability |
|---|---|---|
| 1 | `../PLAN.md`, scope A1–A7 | Scope, fixed-point, timing and implementation invariance |
| 2 | `../golden/tsmx_golden/model.py` | Exact arithmetic, guards, precedence, state and function behavior |
| 3 | `../golden/FORMATS.md` | Widths, intervals, contracts and finite-bit bounds |
| 4 | `../golden/LATENCY_MODEL.md` | Conditional architecture estimates, not measured WCET |
| 5 | `../golden/README.md` | Composition, executor, vectors and phase interpretation |
| 6 | `../../tsm_research/TSM_X_DESIGN_v2.md`, B1–B4/B7–B10/B13, labels, FTTI | Intent only; deltas below take precedence |
| 7 | `../../.agents/skills/vlsit-asic-ip-microspec/rule.md` | R-001–R-023 documentation rules, subject to user's delegated decisions |
| 8 | Same skill, `reference/templates/VLSIT_RTL_Design_Rule.md` | Naming, ports, arithmetic, synthesis contract |

AXI4-Lite subordinate is required by A4. Arm IHI 0022 Issue H is the proposed
baseline (ASSUMPTION-011); it is absent from the skill's `reference/md_doc/` index.
Section 6 states the project interface contract, with formal protocol conformance
open under R-006. No network document or external reference IP was used.
The supplied 22-section Markdown template is absent. The ordered structure here
is recovered from `reference/vlsit_spec_writing_guide.md` (ASSUMPTION-012), not
asserted to reproduce the missing original's exact titles.

### 2.1 Golden-vs-design deltas

| Topic | Design intent | Golden binding contract / implementation impact |
|---|---|---|
| Lateral | Braking plus within-lane offset | A1 disables offset; y=0 in composition, lane bounds ego-centered |
| Horizon | At most 6 s / 30 m | Entire library needs up to 7.6 s / 30.916667 m at 10 m/s; no truncation |
| Selection | Hard / conditional / mitigation ranking | Finite-jerk ACCEPT pool only, smallest decel/jerk/id; no B5/B6 |
| Instant profiles | Potential library candidates | IDs 3,7,11,15 diagnostic only; no admissible finite-jerk candidate gives id15 MITIGATION |
| Objects | Sound relevance filter | All supplied objects checked; more than 32 rejects, never drops objects |
| Ingress | WORLD/MAP/HEALTH integrity each | `b1_ingress` CRC covers Plan/three snapshot IDs/schema; world/lane bound by B9 context hash |
| Codec | Canonical JSON binding in G1 | S1b packed big-endian records, zero LSB byte padding; CRC/SHA unchanged, digest values change |
| Reset | Restore backed-up state with ECC | `b8_fsm` clears pending and backup; moving reset gives L3, standstill gives HOLD |
| Labels | CERT-FULL, conditional, MITIGATION, UNKNOWN | `b7_select` emits only conditional or MITIGATION; reject reasons carry uncertainty |
| Health | SEM/ECC/random lane check | Golden parity, one-hot, Boolean lane comparison and exact BIST; no correction/scrub claim |
| Timing | Earlier one-sweep estimate | S1b G8/P8 streaming; full dual sweep and helpers = 1168034 cycles (6.229515ms), section10.3 |
| Command | Certificate as general trajectory guarantee | Golden nominal screening uses id15 proxy plus certified finite-jerk tail; no arbitrary nominal path proof |
| Live data | General age guard | Composition requires live ego.t==now; raw measurements require external projection |
| ACK loss | Fault implies immediate FSM degradation | Commit failure clears pending; admission/FSM still runs in golden order; watchdog override independently blocks expired command |
| Tracking margin | Front separation 0.5 m | Encoded geometry reserve 0.5 m includes 0.16 m tracking tube; physical residual at least 0.34 m under H3 |

## 3. Requirements

Every mandatory statement in the following sections refines these requirements.
Verification methods: D = differential simulation; A = assertion/formal; I = inspection;
T = cycle/timing analysis; B = bus test. None is reported executed at S1.

| ID | Requirement | Source / golden function | Config | Verification method |
|---|---|---|---|---|
| REQ-TSMX-001 | The implementation shall enforce A1–A7 and the Config1 domains without silent extensions. | PLAN; `live_ego_valid` | Config1 | I, boundary D |
| REQ-TSMX-002 | Arithmetic shall preserve integer guards, serial time, directed rounding and stop clipping. | `checked`, `ceildiv`, `elapsed`, `disp`, `advance`, `swept`, `ramp_integrals`, `continuous_advance` | All | D, A against rational reference |
| REQ-TSMX-003 | Serialization and binding shall match canonical golden JSON, CRC32 and full SHA256. | `canonical`, `digest`, `packet`, `cert_seal`, `context_digest`, `certify` | All | Byte-for-byte D |
| REQ-TSMX-004 | B1 shall return the first golden admission reason and proposed ingress state. | `b1_ingress` | All | b1 vectors, D |
| REQ-TSMX-005 | B2 shall contain all eight delayed uncertainty corners inside the splice tube. | `b2_splice` | All | b2 vectors, D, A |
| REQ-TSMX-006 | B4 shall generate every row of continuous capped-jerk braking through stop plus hold. | `profile_a`, `b4_mrmgen` | All 16 IDs | b4 rows D, A |
| REQ-TSMX-007 | B3 shall check lane containment and continuous separation against every supplied object. | `b3_geom`, `swept` | P=4 | b3 vectors, D, A |
| REQ-TSMX-008 | B7 shall select only finite-jerk ACCEPT profiles or id15 MITIGATION. | `b7_select`, `select`, `select_world` | All | b7 vectors, D, exhaustive masks |
| REQ-TSMX-009 | B8 shall preserve exact six-mode transitions and saturating recovery count. | `b8_fsm` | All | b8 vectors, D, state A |
| REQ-TSMX-010 | B9 shall validate binding, context, sequence, lease, expiry and executor ACK boundaries. | `b9_cert` | Config1 | b9 vectors, boundary D/A |
| REQ-TSMX-011 | Backup reuse shall replay the original apply epoch and enforce residual lease and tube guards. | `phase_state`, `reusable` | Config1 | System replay D/A |
| REQ-TSMX-012 | The event ring shall overwrite oldest entries and saturate lost without blocking safety. | `b10_rec` | Capacity 1–1024 | b10 vectors, D/A |
| REQ-TSMX-013 | Health shall evaluate parity, one-hot, lane agreement and the exact BIST result. | `b13_health` | All | b13 vectors, fault D/A |
| REQ-TSMX-014 | Top composition shall preserve admission, commit, reseal, override and recording order. | `tsmx_cycle` | Explicit/legacy world | System vectors, D |
| REQ-TSMX-015 | Reaction admission shall implement the 285000 us front/rear test exactly. | `reaction_safe` | Config1 | Boundary D/A |
| REQ-TSMX-016 | World propagation, bridge and tail checks shall use the golden apply-time coordinates. | `lead_motion`, `propagated_objects`, `nominal_geom`, `plan_tail` | Both world modes | System D |
| REQ-TSMX-017 | Streams shall preserve complete immutable transactions under stalls and bounded overflow. | ASSUMPTION-002/003 | All | A, malformed/stall D |
| REQ-TSMX-018 | CSR shall implement the workbook, locked Config1 limits, atomic status and interrupt rules. | ASSUMPTION-006/011 | AXI4-Lite | B, configuration D |
| REQ-TSMX-019 | Compute shall finish or safely reject within 1875000 clocks at 187.5 MHz. | A7; LATENCY_MODEL; ASSUMPTION-005 | P=4, G=4 | T, deadline A, post-RTL WCET |
| REQ-TSMX-020 | ACK and expiry override shall run below the 100 ms transaction interval. | `b9_cert`; README | Config1 | Timer boundary D/A |
| REQ-TSMX-021 | Reset shall discard old authorization and keep brake/heartbeat outputs safe. | `b8_fsm`, `tsmx_cycle`; ASSUMPTION-001 | All | Reset D, CDC/RDC I |
| REQ-TSMX-022 | Decision behavior shall be identical with and without SYNTHESIS defined. | A6/A7; RTL rules | All | Paired builds D, lint I |
| REQ-TSMX-023 | Every inter-block transfer shall use the explicit section 5/9 ABI and transaction ownership. | ASSUMPTION-002/004/010 | All | Elaboration I, interface A |
| REQ-TSMX-024 | Command authority shall follow mode, with L3 fixed to id15 and HOLD to parking hold. | README; `tsmx_cycle`; ASSUMPTION-007 | All | Arbitration D/A |

## 4. Features and configurations

| Item | Config1 value / behavior |
|---|---|
| Clock, decision period | 187.5 MHz; 100000 us |
| Geometry lanes, generator lanes | P=4; G=4, independent candidate contexts |
| Candidate table | IDs 0..15: decel {2,4,6,8} × jerk {2,4,8,instant}; nested order |
| Profiles / cells / objects | 16 / 128 / 32; row count up to 129 |
| Lane default | [-1800000,1800000], y=0, half-width 950000, lateral error 50000 |
| Reserve | 500000; object length is combined longitudinal extent, default 4800000 |
| Freshness, freeze | 150000 us; freeze 300000 us and movement greater than 200000 |
| Splice | dx±50000, dv±50000, da±100000; tube x±160000,v±200000 |
| Certificate | Versions capability/config/controller/scope all 1; lease at most 500000 us |
| ACK / margin | 40000 us / 20000 us |
| Recovery | Three consecutive accepted decisions; good saturates at 3 |
| Event ring | 64 records by default; capacity 1..1024 |
| Future ego limit | Parameter may accommodate 20 m/s; Config1 rejects ego greater than 10 m/s |

## 5. Architecture

### 5.1 Ownership and transaction boundaries

ASSUMPTION-002: `m_tsmx_top` owns Ingress, Supervisor, immutable pending and backup
records. Leaf blocks receive explicit state and return proposals; there is no shared
memory side channel. Only B10 owns its ring and CSR owns software-visible state.
Packet admission is tentative until final reason==ok. A failed late-stage check does
not consume B1's proposed sequence/signature state; top updates only last_time.
Per-request local arithmetic state is discarded at completion/reset.

Four B4 lanes generate four candidate contexts at a time. Four B3 lanes independently
check complete trajectories; each lane retains object intervals in its own local RAM.
Results are tagged by candidate ID; B7 sees the complete 16-bit accept mask. Parallel
completion order cannot change candidate order, first reject reason or event order.
No leaf reads another leaf's registers. Top drives explicit requests for legacy lead,
apply-time propagation, bridge, proxy nominal and tail scans as specified in section 10.

### 5.2 Block diagram

![TSM-X block diagram](figures/block_diagram.svg)

[JSON source](figures/block_diagram.json), [generated TikZ](figures/block_diagram.tex).
SVG is an offline preview of the JSON, not a compiled LaTeX rendering (ASSUMPTION-013).
The interconnect table, rather than diagram arrow placement, defines connectivity.

### 5.3 Common port and handshake contract

ASSUMPTION-001/002/004: every module has these physical ports, included by reference
in every subsection below. All listed module-specific ports are physical packed-vector
ports; no SystemVerilog interface/package is required in synthesizable RTL.

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_clk_core` | in | 1 | core | Rising-edge 187.5 MHz |
| `i_rst_n_core` | in | 1 | core | Active-low reset, asynchronous assertion, synchronized release |
| `i_req_valid` | in | 1 | core | Request payload valid |
| `o_req_ready` | out | 1 | core | Request accepted on valid AND ready |
| `o_rsp_valid` | out | 1 | core | Response and payload held until consumed |
| `i_rsp_ready` | in | 1 | core | Response consumed on valid AND ready |

One outstanding request per module instance unless explicitly stated for a pipeline.
No payload/state update on valid alone. Input payload stays stable while stalled;
output payload stays stable while stalled. Reset sets req_ready/rsp_valid=0 and
clears local valid bits; ready may assert on the first released clock. Response data
is zero when invalid. Data reset does not authorize a command. No ready combinational
loop. Top retains transaction/candidate/job tags locally until response consumption.
Timeout cancels a job by clearing its transaction context; top drains/discards any
outstanding leaf response before reusing that instance. No newly accepted job may
overtake that drain. Top retains an instance-busy flag; local leaf state is never
cleared by an unlisted hidden reset/cancel signal. A timed-out arithmetic job must
still complete within its stated per-job bound or trigger global health reset.

### 5.4 Complete top-level interconnect

Each row is one named channel: `valid`, `ready`, and the payload port named in the
module tables. All widths are section 9 record widths; all are core domain. Top
terminates every leaf channel; there are no implicit B4→B3 RAM connections. Payload
is copied or buffered by top. Response routing uses the retained job/candidate tag.

| Signal/channel | Producer → consumer | Payload | State owner / meaning |
|---|---|---|---|
| `rx` | external → top | 32-bit words, keep4,last1 | Top staging frame, bounded 64 KiB |
| `codec_req/rsp` | top ↔ codec | CODEC_REQ / CODEC_RSP | Local serializer, CRC/SHA; requests queued by top |
| `b1_req/rsp` | top ↔ ingress | B1_REQ / B1_RSP | Top commits proposed Ingress only after full admission |
| `b2_req/rsp` | top ↔ splice | Ego+Plan / accept1 | Top snapshot |
| `arith_req/rsp` | top ↔ arith | ARITH_REQ / ARITH_RSP | Top helper jobs for reaction/bridge/replay/propagation |
| `b4_req_0..3/rsp_0..3` | top ↔ mrmgen_0..3 | B4_REQ / Trajectory | Each instance has private primitive hardware |
| `b3_req_0..3/rsp_0..3` | top ↔ geom_0..3 | Trajectory+World+Lane / GeomResult | Each instance owns 32 object interval contexts |
| `b7_req/rsp` | top ↔ sel | accept16 / candidate8+label8 | No persistent selector state |
| `b8_req/rsp` | top ↔ supervisor | B8_REQ / B8_RSP | Top owns mode/good/fault and clear flags |
| `b9_req/rsp` | top ↔ cert | B9_REQ / status8 | Top pending/backup owner; timer jobs get priority |
| `rec_req/rsp` | top ↔ rec | Event / lost32 | B10 owns ring; top mirrors golden events_lost |
| `health_req/rsp` | top ↔ health | HEALTH_REQ / healthy1 | B13 owns BIST-local contexts |
| `health_b4_req/rsp` | health ↔ dedicated mrmgen | B4_REQ / Trajectory | Dedicated BIST instance, no datapath contention |
| `health_b3_req/rsp` | health ↔ dedicated geom | Trajectory+World+Lane / GeomResult | Dedicated BIST instance |
| `arb_req/rsp` | top ↔ arb | ARB_REQ / Command | Top supplies mode and immutable authorized records |
| `cmd` | top → external executor | 32-bit words, keep4,last1 | Top egress staging; independent override bypass |
| `ack` | external → top | valid1, seq32 | One pulse per ACK; exact pending ID required |
| `log` | rec → external | Event | Drain reads oldest without deletion; explicit index query |
| `csr_bus` | external ↔ csr | Section 6 bus signals | CSR owns register state |
| `csr_config` | csr → top | config_valid1,en1,soft_rst1,bist_start1 | Held levels, one-cycle pulses for commands |
| `csr_update` | top → csr | CSR_UPDATE | One pulse on completed decision / fault edge |
| `brake/hb/irq` | top/csr → external | 1 each | Brake override, heartbeat, level IRQ |
| `time/live` | external → top | now32,Ego256,health1,cap1,rear_ftti32 | Stable at request acceptance; now sampled continuously for timer jobs |

Each B2/B3/B4 instance contains a private `m_tsmx_arith` instance, or equivalent
inlined implementation with identical ports/contract; it is not a contested global
divider. B1/B9 request supplied hashes through top's codec before their own request;
they do not independently trust host-precomputed hashes. B13 requests its dedicated
B4/B3 instances through the two channels above. Clock/reset fan out to all modules.

### 5.5 RTL sub-block decomposition

For every block: common ports/reset/handshake are section 5.3; all numerical ports
use section 9 and FORMATS; cycle counts exclude external stalls unless stated.
Unit paths are relative to `tsmx_hw/`. `.hex` plus `.json` is the existing fixture
ABI; full `.ports.jsonl` files are expected from G1's expander when available.
Do not use the small hex summaries as substitutes for comparing every output row.

#### 5.5.1 `m_tsmx_arith` - checked rational motion primitives

Private arithmetic belongs to each of the eight B4 contexts and eight B3 lanes;
B2/reaction/replay have a separate helper instance. There is no contended global
arithmetic server. SI scaling, outward division and golden algorithms are unchanged.

| Operation | Operand widths | Product / divider widths |
|---|---|---|
| guards, elapsed, profile_a | x/gap s64; v/a/j/time s32; serial u32 | s64 multiply for j*time; serial s33 subtract |
| advance, integer-time disp | x s64, v/a/h s32 | s96 numerator, u64 denominator; s96 directed divider |
| rational disp, swept | n u46, d u24, v/a s32, gap s64 | s128 numerator and cross products, u96 denominator; s128 directed divider |
| capped ramp, continuous_advance | x s64, v/a/j/target/h s32 | s160 xn, u136 xd; s112 vn, u88 vd; s160 directed divider |

Bound proof: v<2^25, |a|,|j|<2^23 (relative acceleration<2^24),
T<2^20, h<=100000<2^17 in B4; d=|j|<2^23 and n<=h*d<2^40.
xd=6*T^3*d^3<2^132. The three xn terms have absolute bounds
2^153,2^148,2^143 respectively, hence |xn|<2^154 and fit s160.
vd=2*T^2*d^2<2^87. For B4 v<=10000128 (including outward error),
the three vn terms are respectively <2^110,<2^107,<2^103 in magnitude;
their sum gives |vn|<2^111,
which requires s112 (the earlier FORMATS vn<2^104 claim was too small).
For swept, rational n<2^46,d<2^24 give each displacement numerator term
<2^117, their sum<2^118 and denominator<2^89; s128/u96 suffice.
Integer-time advance h<=12800000<2^24 needs numerator<2^74 and
denominator<2^41. Rational time comparison cross products<2^70.
All products are checked before narrowing; minimum-negative numeric sentinels
and nonpositive denominators fault. No 256-bit arithmetic datapath is required.
Full 256-bit values remain necessary only for SHA digests.

The typed request carries op8, twelve s160 operand slots (W_ARITH_REQ=1928);
response fault1 and four s160 slots (W_ARITH_RSP=641). Per-op guards enforce the
narrower widths above. Operations/opcode ordering remains section 9.2.
Directed division is floor/ceil for a signed numerator and positive denominator.
B4 cell service is <=1280 cycles, including both outward intervals and the
<=17 stop-bracket iterations; implementation resource schedule is below and in
LATENCY_MODEL S1b. B3 service II48 is a complete actor-cell contract, including
an event split and all swept points, not a single division. Reset clears all tags;
backpressure preserves coefficients, interval state and tags. Fault returns no pose.
Golden references: checked/ceildiv/disp/advance/swept/profile_a/ramp_integrals/
continuous_advance; validate against b2/b3/b4 full interval vectors.

#### 5.5.2 `m_tsmx_codec` - streaming packed-record CRC32 and SHA-256

Function: consume checked fields as the section 9.2 packed byte stream. No JSON
serializer, decimal conversion or text hashes exist in the hardware decision path.
Input is a 32-bit byte stream with op8, start/last and final-byte count; output is
fault1, CRC32 and digest256 (W_CODEC_RSP=289). Ready/valid stalls retain partial
words and SHA state. B9 timer checks use immutable cached hashes with priority.
Reset clears partial jobs and valid flags; malformed size/schema rejects the job.

CRC-32 IEEE uses reflected polynomial 0xedb88320, initial/final XOR 0xffffffff,
empty result0, exactly Python zlib.crc32. SHA-256 uses full digests. A conservative
SHA compression block takes 68 cycles (64 rounds plus four control cycles),
with double-buffered 32-bit input. Initial buffer fill is conservatively16 cycles;
subsequent fills overlap compression. Compression target range64-68 cycles.
For L bytes SHA padding needs ceil((L+9)/64) blocks. Job bound is
16+68*ceil((L+9)/64), including initial feed. No digest truncation.

| Record / hash material | Bits before byte padding | Bytes | CRC word cycles | SHA job cycles (16+68/block) |
|---|---:|---:|---:|---:|
| Ego | 256 | 32 | 8 | 84 |
| Plan | 560 | 70 | 18 | 152 |
| Packet body: Plan, IDs, schema | 688 | 86 | 22 | 152 |
| Packet incl present/CRC | 721 | 91 | 23 | 152 |
| Row / Motion | 352 / 256 | 44 / 32 | 11 / 8 | 84 / 84 |
| World | 8200 | 1025 | 257 | 1172 |
| Lane | 384 | 48 | 12 | 84 |
| Context: World,lo,hi,frame,units | 8392 | 1049 | 263 | 1172 |
| Certificate seal body | 960 | 120 | 30 | 220 |
| Certificate | 1217 | 153 | 39 | 220 |
| Trajectory | 45458 | 5683 | 1421 | 6068 |
| Ingress | 332 | 42 | 11 | 84 |
| GeomResult | 81 | 11 | 3 | 84 |
| Event | 1056 | 132 | 33 | 220 |
| Command | 1997 | 250 | 63 | 356 |
| TOP_RSP | 38 | 5 | 2 | 84 |
| CSR_UPDATE | 115 | 15 | 4 | 84 |

Each record is padded with zero bits at its LSB end to a whole byte. Nested
records concatenate their unpadded bits; padding occurs only at the outer job
boundary. CRC body excludes present/CRC; seal body excludes present/seal.
Worst-case B9 allocation32768 cycles covers <=24 context hashes (28128),
<=8 Ego/Plan/seal groups (3648), leaving992 cycles for checks/transport.
Actual tsmx_cycle uses fewer jobs, including pending/admission/reuse and reseal;
no full trajectory-row hash is performed: certificate.trajectory binds Plan.
Golden pack_* functions and digest implement these bytes; JSON helpers carry
_json_legacy names and are outside the decision path. Fixtures cover b1/b9/system.


#### 5.5.3 `m_tsmx_ingress` — B1 integrity and freshness

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | W_B1_REQ | core | Ingress state + now32 + Ego + Packet + local_crc32 + parse_ok1 |
| `o_rsp_data` | out | W_B1_RSP | core | proposed Ingress state + reason8 |

| Contract item | Definition |
|---|---|
| Function | Admission with exact ordered checks and explicit freeze history |
| Parameters | Config1 bounds fixed; packet limit65536 bytes |
| Formats / bound | Ego256; Plan560; time/seq u32 serial, transaction separation below2^31 us; state validity flags encode Python sentinels |
| Latency / throughput | ≤16384 clocks per decision including CRC work, no-overlap conservative budget; one admission per decision |
| Handshake | State-in/state-out, no internal persistent ingress history |
| Reset | No accepted seq/time/sample/signature; freeze_since=0,freeze_x=0 at top |
| Fault | Returns unchanged state plus first reason; top only commits proposal after all later checks pass |
| Golden / unit vectors | `b1_ingress`, `packet`; `vectors/b1.hex`, `b1.json`, `b1.ports.jsonl` |

Order: clock rollback; missing packet (`freeze_no_sample` after ≥300000 us else
`timeout`); numeric guards; range/schema; count2..32; compute0..10000 us;
three identical u32 snapshot IDs; CRC; sequence strictly advances; ego freshness;
snapshot/generation freshness; unchanged signature ≥300000 us AND ego displacement
greater than200000. Signature=(plan.x,v,a,tail); unchanged signatures do not refresh
freeze epoch. New state uses last_sample=plan.snapshot.t, not arrival time.

#### 5.5.4 `m_tsmx_splice` — B2 reachability splice

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | 816 | core | Ego256 followed by Plan560 |
| `o_rsp_data` | out | 1 | core | All corners contained |

| Contract item | Definition |
|---|---|
| Function | Propagate8 combinations of dx/dv/da using floor and ceil |
| Parameters | Tube/uncertainties locked to section4; private arith instance |
| Formats / bound | x s64 ±10000S ingress; corner v≤10.05S, a clamped[-8S,0]; delay s32 [0,100000] |
| Latency / throughput | ≤12288 clocks/admission; one outstanding splice |
| Handshake | Full request snapshotted, response1 held until ready |
| Reset | No pending check, accept=0 |
| Fault | Any invalid delay/format/primitive exception produces accept0 |
| Golden / unit vectors | `b2_splice`, `advance`; `vectors/b2.hex`, `b2.json`, `b2.ports.jsonl` |

For each corner: v=max(0,ego.v+dv), a=min(0,max(-8S,ego.a+da)); x=ego.x+dx.
Check both outward endpoints against plan.x±160000 and plan.v±200000. Negative
apply−ego.t rejects; no clamp-to-zero or arbitrary trajectory feasibility test.

#### 5.5.5 `m_tsmx_mrmgen` — B4 continuous MRM generator

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | W_B4_REQ=176 | core | x64,v32,a32,cid8,phase32,limit8 |
| `o_rsp_data` | out | 50 | core | Terminal accept1,reason8,stop_valid1,stop32,row_count8 |
| `o_row_data` | out | 401 | core | cid8,epoch32,index8,Row352,last1; separate row ready/valid |

| Contract item | Definition |
|---|---|
| Function | One complete candidate; replicate8 instances for G=8 |
| Parameters | `PARA_MAX_CELLS=128`; DT100000, hold2000000; private arith |
| Formats / bound | x s64, v/a/j s32, phases s32; phase≤12800000 at entry, absolute rows≤25600000; position≤10070S internal |
| Latency / throughput | Per candidate≤128×1280=163840 clocks; eight instances cover16 candidates in327680; streaming overlap with B3 |
| Handshake | Stream row k as produced with cid/epoch/index tags; terminal metadata commits the buffered Trajectory; preserve rows/count under stall |
| Reset | count0,accept0,stop_valid0,rows0; original epoch is supplied, not inferred |
| Fault | Invalid range/grid gives range, nonaligned crossing gives phase_alignment, insufficient cells gives horizon with partial rows |
| Golden / unit vectors | `b4_mrmgen`, `profile_a`, `continuous_advance`; `vectors/b4.hex`, `b4.json`, `b4.ports.jsonl`, compare every interval row |

First100ms preserves measured a. Thereafter profile_a ramps toward target -b at
signed jerk±j; starting acceleration can be stronger than target and ramp upward.
Instant j=0 switches directly after prefix. At each cell emit current outward
x/v interval, midpoint acceleration and absolute jerk bound, then integrate lower
with floor, upper with ceil. If v endpoint crosses zero, binary-search the stop
bracket to1us; upper dx adds ceil(v0/T), lower uses left bracket. Record first
upper-v==0 stop, append terminal endpoint only after at least2s hold. Never cut at6s
or30m. Standstill clamp defines parking transition without a claimed jerk bound there.

#### 5.5.6 `m_tsmx_geom` — B3 continuous geometry lane

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | 8624 | core | cid8,epoch32,World8200,Lane384; immutable for candidate |
| `i_row_data` | in | 401 | core | cid8,epoch32,index8,Row352,last1; row ready/valid |
| `i_terminal_data` | in | 50 | core | B4 terminal accept/reason/stop/count; separate ready/valid |
| `o_rsp_data` | out | W_GEOM=81 | core | accept1,margin64,reason8,steps8 |

| Contract item | Definition |
|---|---|
| Function | Sequentially validate rows/cells and propagate private per-object intervals; replicate8 |
| Parameters | `PARA_MAX_OBJ=32`, `PARA_MAX_CELLS=128`; private pipelined rational primitive |
| Formats / bound | Trajectory rows x±10070S; v[0,20S]; a[-8S,0]; jerk[0,8S]; object displacement≤256S; gap magnitude below2^35 |
| Latency / throughput | Eight lanes: 393216 cycles for16x128x32 actor-cells at II48; dual sweep/fill/drain/helpers in10.3 |
| Handshake | Tagged row stream plus immutable world/lane; provisional geometry starts with each produced row pair; final accept waits for all endpoint/domain checks |
| Reset | Every object interval/count valid cleared; accept0 |
| Fault | Return exact reason and step count; invalid rows/objects fail before multiplication, no truncation |
| Golden / unit vectors | `b3_geom`, `swept`, `advance`; `vectors/b3.hex`, `b3.json`, `b3.ports.jsonl` |

Validation order: trajectory accept and2..129 rows; lane types; every row including
final endpoint; lane ranges; object count; lateral containment; all actor fields;
horizon; actor speed preflight. Object speed preflight is
v+ceil(max(0,a,after_a)×horizon/T)≤20S. Initial minimum=10000S.
For every adjacent row h in(0,DT], inflate ego x by
ceil(jerk×h³/(8T³))+ceil(h²/(2T²)). Split cells at the actor event. Set ahead using
object lower x≥ego upper x at cell start; evaluate `swept` in that order for every
piece. `swept` enumerates endpoints, both stop times and relative stationary points
over stop phases; compute floor(front displacement)−ceil(ego displacement).
Reject if gap<reserve; equality accepts. Update minimum with gap−reserve. Advance
actor outward, cap actor upper v at20S only after proven preflight; advance inflated
ego bounds with midpoint a for each piece. No endpoint-only collision check.

The full W_TRAJ record in section9.2 remains the golden/vector view reconstructed
from the row stream and terminal status. Geometry runs speculatively before final
horizon/speed preflight is known. At completion, resolve all deferred checks in
b3_geom order; a later row numeric error wins an earlier provisional separation
failure. Hold speculative faults/results until validation resolves, and never
publish early ACCEPT. Positive-acceleration actors use the actual final horizon
for preflight; using12.8s as a rejection threshold would change golden decisions.

#### 5.5.7 `m_tsmx_sel` — B7 lexicographic selector

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | 16 | core | accept mask bit i for candidate i |
| `o_rsp_data` | out | 16 | core | candidate u8 followed by label u8 |

| Contract item | Definition |
|---|---|
| Function | Mask IDs3,7,11,15; first remaining ACCEPT in library order |
| Parameters | `PARA_PROFILES=16` locked |
| Formats / bound | u16 mask, candidate0..15, label8 |
| Latency / throughput | ≤64 clocks per16-way reduction; single outstanding request |
| Handshake | Complete mask, stable response under stall |
| Reset | Invalid output; data candidate0,label0 when invalid; authority supplied only on valid |
| Fault | Empty finite-jerk set returns15/MITIGATION; no dependency on margins or lane completion order |
| Golden / unit vectors | `b7_select`, `select`, `select_world`; `vectors/b7.hex`, `b7.json`, `b7.ports.jsonl`; exhaustive65536 masks |

The key is (decel,jerk,library string ID); with this fixed table it equals increasing
finite-jerk numeric ID. Golden cache in `select` affects performance only; RTL needs
no memoization state. Reported candidate/label is current fallback, not command authority.

#### 5.5.8 `m_tsmx_supervisor` — B8 FSM

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | W_B8_REQ=44 | core | mode3,good2,fault1,accept1,v32,reuse1,fallback1,cap1,reset1,health1 |
| `o_rsp_data` | out | W_B8_RSP=8 | core | mode3,good2,fault1,clear_pending1,clear_backup1 |

| Contract item | Definition |
|---|---|
| Function | Stateless next-state transform; top owns Supervisor record |
| Parameters | Recovery threshold3 locked |
| Formats / bound | Modes6, good saturates0..3, v[0,10S] |
| Latency / throughput | ≤32 clocks/decision; first-fault override is separate bypass |
| Handshake | State snapshot and returned atomic proposal |
| Reset | Top modeL3,good0,fault1; pending/backup invalid |
| Fault | Reset/unhealthy clears both records; corrupted mode protection drives health false |
| Golden / unit vectors | `b8_fsm`; `vectors/b8.hex`, `b8.json`, `b8.ports.jsonl` |

| Precedence | Condition | Next mode / effects |
|---|---|---|
| 1 | reset OR not health | HOLD if v==0 else L3; good0; fault1; clear pending and backup |
| 2 | accept | good=min(3,good+1); L0 if good==3 else RECOVERY; fault0; retain records |
| 3 | reject and v==0 | HOLD; good0; fault1; clear pending; retain backup |
| 4 | reject and reuse and cap | L1; same reject effects |
| 5 | reject and fallback and cap | L2; same reject effects |
| 6 | remaining reject | L3; same reject effects |

#### 5.5.9 `m_tsmx_cert` — B9 binding, lease and ACK checker

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | W_B9_REQ | core | Plan/Certificate, presence, now/issued, flags, expected seq/context, locally computed hashes |
| `o_rsp_data` | out | 8 | core | Exact golden commit/reason status enum |

| Contract item | Definition |
|---|---|
| Function | Pure check; top owns pending/backup and schedules timer invocations |
| Parameters | Versions1, lease500000, ACK40000, margin20000; locked |
| Formats / bound | time/seq u32 serial; hashes256; transaction less than half-wrap |
| Latency / throughput | Aggregate B9 hash/check budget32768 clocks per scan; timer service≤1us after hashes cached against immutable records, ASSUMPTION-005/007 |
| Handshake | One check per request; timer job priority; locally cached binding results invalidated by any record change |
| Reset | No authorized record; status timeout when requested without plan/cert |
| Fault | Ordered reason return; no B9-local commit side effect |
| Golden / unit vectors | `b9_cert`, `cert_seal`, `certify`; `vectors/b9.hex`, `b9.json`, `b9.ports.jsonl`; system vectors for phase reuse |

Order: missing→timeout; scalar range/schema; seal/snapshot/trajectory/apply/version
binding; expected_seq replay; expected_context; lease0<expiry−generated≤500000.
At executor: remaining≤0→expiry_at_executor; elapsed(now,issued)≥40000 AND no ack
→ack_timeout; else committed if ack AND now≥apply, otherwise pending. Thus an ACK
at exactly40000 can avoid timeout, but cannot commit before apply; expiry wins ACK.
On admission: new apply<now→late_apply; remaining≤20000 OR expiry−apply≤20000→expiry;
else ok. Phase reuse bypasses only late_apply. Expected context is optional in API;
top supplies it for new admission, exactly as `tsmx_cycle` does. Executor checks
expected sequence of immutable pending; golden does not rebind to a later world.

#### 5.5.10 `m_tsmx_rec` — B10 bounded event recorder

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | W_EVENT | core | Up to4 typed fields; invalid event is explicitly flagged |
| `o_rsp_data` | out | 32 | core | New saturated lost count |
| `i_log_idx` | in | 10 | core | Oldest-relative read index |
| `i_log_valid` | in | 1 | core | Read request |
| `o_log_ready` | out | 1 | core | Read index accepted |
| `o_log_data` | out | W_EVENT | core | Indexed event; held under stall |
| `o_log_valid` | out | 1 | core | Log response |
| `i_log_ready` | in | 1 | core | Log response consumed |

| Contract item | Definition |
|---|---|
| Function | Append/overwrite ring, preserve chronological events; indexed drain does not change golden ring |
| Parameters | `PARA_LOG_DEPTH=64`, legal1..1024; configured only at elaboration |
| Formats / bound | Lost u32 saturates; pointer u10 modulo depth; four fields each s64 or UTF-8 string≤32 chars |
| Latency / throughput | ≤2 clocks/write; write path never waits for log consumer; one event per decision |
| Handshake | Event always admitted when idle; internal reservation covers bounded completion response; no host backpressure dependency |
| Reset | Empty ring,count0,head0,lost0; no need to clear invalid RAM words |
| Fault | Invalid field/type/count increments lost without append; full ring valid append drops oldest and increments lost |
| Golden / unit vectors | `b10_rec`; `vectors/b10.hex`, `b10.json`, `b10.ports.jsonl` (fixture capacity4) |

All strings reachable from this IP are ASCII enums; the general API allows bounded
strings, represented without hashing away content (ASSUMPTION-010). A digest alone
would lose golden event equality. Read collision observes the pre-write indexed
snapshot; software retries if ring generation changed (ASSUMPTION-006).

#### 5.5.11 `m_tsmx_health` — B13 monitor and BIST sequencer

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | W_HEALTH_REQ | core | schema_ok1,word_count11,parity_count11,words1024×32,parities1024,lane_pair2,onehot6,bist1 |
| `o_rsp_data` | out | 1 | core | Healthy iff every golden check passes |
| `o_b4_data` | out | W_B4_REQ | core | BIST generator request |
| `o_b4_valid` / `i_b4_ready` | out / in | 1 each | core | Request handshake |
| `i_b4_data` | in | W_TRAJ | core | Generated BIST trajectory |
| `i_b4_valid` / `o_b4_ready` | in / out | 1 each | core | Response handshake |
| `o_b3_data` | out | W_TRAJ+W_WORLD+W_LANE | core | Clear/blocked BIST geometry jobs |
| `o_b3_valid` / `i_b3_ready` | out / in | 1 each | core | Request handshake |
| `i_b3_data` | in | W_GEOM | core | BIST geometry result |
| `i_b3_valid` / `o_b3_ready` | in / out | 1 each | core | Response handshake |

| Contract item | Definition |
|---|---|
| Function | Check protected32-bit words, parity, lane Boolean equality, legal6-bit one-hot, exact BIST |
| Parameters | `PARA_HEALTH_WORDS=1024` ASSUMPTION-008; dedicated B4/B3 resources |
| Formats / bound | u32 words, parity1 each; exactly one FSM bit among6; word count≤1024 |
| Latency / throughput | ≤65536 clocks per health transaction including BIST; no shared-resource blocking |
| Handshake | Single health job; BIST subrequests explicit above |
| Reset | Healthy0 until completed passing request; BIST pending contexts cleared |
| Fault | Length/parity mismatch, lane disagreement, illegal FSM or BIST mismatch returns0; no correction claimed |
| Golden / unit vectors | `b13_health`; `vectors/b13.hex`, `b13.json`, `b13.ports.jsonl` |

BIST uses `b4_mrmgen(0,S,0,0)`: accept1,stop1100000, terminal row
(3100000,766660,766670,0,0,0,0). Geometry with Motion(20S,0) accepts;
Motion(4S,0) rejects. Golden bist=False skips only BIST, not other checks.
Default golden calls bist=True; Config1 composition follows that default each cycle.
No probabilistic sampling replaces the supplied lane_pair equality.

#### 5.5.12 `m_tsmx_csr` — AXI4-Lite configuration and status

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_axi_awaddr`, `i_axi_araddr` | in | 16 each | core | Byte address |
| `i_axi_awprot`, `i_axi_arprot` | in | 3 each | core | Protection attributes accepted, no privilege policy in v1 |
| `i_axi_awvalid`, `i_axi_wvalid`, `i_axi_arvalid` | in | 1 each | core | Address/data validity |
| `o_axi_awready`, `o_axi_wready`, `o_axi_arready` | out | 1 each | core | Independent acceptance |
| `i_axi_wdata`, `i_axi_wstrb` | in | 32 / 4 | core | Data and byte enables |
| `o_axi_bvalid`, `o_axi_rvalid` | out | 1 each | core | Response valid |
| `i_axi_bready`, `i_axi_rready` | in | 1 each | core | Response acceptance |
| `o_axi_bresp`, `o_axi_rresp`, `o_axi_rdata` | out | 2 / 2 / 32 | core | Response code/data |
| `i_sts_valid`, `i_sts_data` | in | 1 / W_CSR_UPDATE | core | Atomic status/counter snapshot |
| `o_config_data` | out | 4 | core | config_valid,en,soft_rst,bist_start |
| `o_int_irq` | out | 1 | core | Masked sticky interrupt OR |

| Contract item | Definition |
|---|---|
| Function | Software map solely in JSON/workbook; bus wrapper is not the APB generator |
| Parameters | `PARA_ADDR_W=16`, `PARA_DATA_W=32`; no asynchronous CSR sheet in v1 |
| Formats / bound | All bus words32; bounded Config1 values validated before run |
| Latency / throughput | Response issued≤4 clocks after complete accepted address/data; one read and one write outstanding; host stall not in safety path |
| Handshake | Separate address/data latches; stable B/R payload until ready; no safety-state writes while enabled/busy |
| Reset | Bus valids0; configuration/status defaults only in workbook; disabled until BIST/default validation |
| Fault | Misalignment, unmapped access, illegal config value, write while active returns project error code and flags config fault |
| Golden / unit vectors | No golden CSR function; `tsmx_cycle` inputs/outputs mapped via `vectors/system.hex`, `system.json`, `system.ports.jsonl`; bus/CSR tests separately derived from workbook |

#### 5.5.13 `m_tsmx_arb` — command authority mux

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | W_ARB_REQ | core | mode3,candidate8,label8,now32,pending Plan/Cert,backup Plan/Cert,valid flags,ego |
| `o_rsp_data` | out | W_CMD | core | Immutable command with source/mode/label/epoch |
| `i_override` | in | 1 | core | Immediate first-fault / executor watchdog override |
| `o_brake` | out | 1 | core | Independent brake request, bypasses response backpressure |

| Contract item | Definition |
|---|---|
| Function | Source selection only; no resequencing or recomputing candidate |
| Parameters | Profile count16, mitigation ID15 locked |
| Formats / bound | All commands preserve apply epoch/time32 and full binding hashes256 |
| Latency / throughput | ≤2 registered clocks to command/override while clock runs; allocated inside16384 margin budget |
| Handshake | Response can stall unchanged; separate brake override revokes authority without mutating held response data |
| Reset | Brake1, command invalid; top heartbeat0 |
| Fault | Missing authorized record for selected source forces mitigation; L3 never substitutes a milder selector result |
| Golden / unit vectors | README arbitration contract; `tsmx_cycle`, `b8_fsm`, `b9_cert`; `vectors/system.hex`, `system.json`, `system.ports.jsonl` |

Mode sources: L0/RECOVERY use newly accepted pending nominal plus its certified
tail; L1 uses reusable backup with original apply; L2 uses current selected fallback;
L3 uses brake8/instant id15 MITIGATION; HOLD emits parking hold. Fallback output
label from B7 remains independently visible even when actual L3 command is MITIGATION.
`independent_brake=not accept` in golden telemetry is preserved exactly; it does not
by itself replace the mode-selected L1/L2 command with id15 (ASSUMPTION-007).

#### 5.5.14 `m_tsmx_top` — composition, timers and transport

| Port name | Dir | Width | Clock domain | Description |
|---|---|---:|---|---|
| `i_req_data` | in | W_TOP_REQ | core | now32,Ego256,Packet,Certificate,World,Lane,presence/lead/capability/health/reset/ACK/rear_ftti,HEALTH_REQ |
| `o_rsp_data` | out | W_TOP_RSP | core | accept,reason,mode,candidate,label,independent_brake,commit,heartbeat |
| `i_time_us` | in | 32 | core | Continuously advancing external epoch for subcycle checks |
| `i_ack_valid`, `i_ack_seq` | in | 1 / 32 | core | Executor ACK pulse and exact transaction ID |
| `i_rx_valid`, `o_rx_ready`, `i_rx_last` | in/out/in | 1 each | core | Stream packet ingress |
| `i_rx_data`, `i_rx_keep` | in | 32 / 4 | core | Semantic frame words and byte mask |
| `o_tx_valid`, `i_tx_ready`, `o_tx_last` | out/in/out | 1 each | core | Executor command stream |
| `o_tx_data`, `o_tx_keep` | out | 32 / 4 | core | Encoded Command words |
| `o_brake`, `o_heartbeat` | out | 1 each | core | Independent brake and monitored heartbeat |

Top also exposes all AXI4-Lite, log and IRQ ports of CSR/B10 with identical names,
directions, widths and core domain as above. It contains all section5.4 channels.
The common request interface is the direct unit-test interface; production uses
decoded stream requests selected by `PARA_DIRECT=0`. `PARA_DIRECT=1` is a structural
test configuration using identical decision datapath, not a SYNTHESIS switch.
In direct mode HEALTH_REQ represents the optional golden health_inputs dictionary;
defaults are empty words/parities, lane_pair=(1,1),onehot=1,bist=1. Production health
words/parities/lane comparisons/FSM bits come from internal monitored storage and
lanes; the planner cannot supply or bypass them. Source multiplexing is structural
under ASSUMPTION-008 and leaves the monitor function identical.

| Contract item | Definition |
|---|---|
| Function | Pure golden transaction sequencing plus independent timer/transport wrapper |
| Parameters | P4,G4,Config1, direct0; command/ingress buffers2 transactions ASSUMPTION-003 |
| Formats / bound | Snapshot immutable; time serial below half wrap; live ego.t==now; packed records section9 |
| Latency / throughput | ≤1875000 clocks to result or deadline rejection; one100ms transaction, no overlapping state commits |
| Handshake | Accept only complete coherent frame or direct request; input staging independent from current decision |
| Reset | Ingress invalid; L3,good0,no pending/backup,empty recorder,lost0; brake1,heartbeat0 |
| Fault | Invalid live ego/clock rollback bypasses hash/geometry; timeout blocks command; external watchdog handles stopped clock |
| Golden / unit vectors | `tsmx_cycle`, `reaction_safe`, `phase_state`, `reusable`, `nominal_geom`, `plan_tail`, `propagated_objects`, `live_ego_valid`; `vectors/system.hex`, `system.json`, `system.ports.jsonl` |

## 6. Interfaces and ports

### 6.1 Transport and project AXI4-Lite contract

ASSUMPTION-003: streams are custom valid/ready word streams, without claiming
AXI4-Stream compliance. Little-endian bytes in each32-bit word; lower-address word
first. Each frame starts type32, payload_bytes32, then the section9 packed payload
rounded to bytes, then end-of-frame. Types1=TOP_REQ,2=Command,3=Event. Word0 arrives
first; all keep bits are1 except final contiguous low bytes. No interleaving frames.
Frame length cannot exceed64KiB; type/length/keep/last errors produce numeric/schema
reject before narrowing. Signed wire fields are two's complement, reserved bits0.
The canonical CRC/SHA byte stream is reconstructed locally, not the binary frame.
Two staging slots; full staging deasserts ready; a partial frame stalled beyond the
allocated16384-clock total transport margin is discarded and logged as timeout.

ASSUMPTION-011: project CSR contract uses independent AW/W latches; writes occur
once both have handshaken, with enabled WSTRB bytes only. R/B response stays stable
until accepted. One outstanding write and one read are supported. Error response
encoding2, success0. Unmapped/misaligned accesses error; read-only writes error;
reserved bits read zero and ignore writes. Hardware sticky set wins W1C clear.
PROT is accepted without access-control filtering. Bus stalls cannot stop decision,
timers or recorder. These protocol facts need reconciliation to the missing local
Arm source before a compliance claim; see section20.

### 6.2 Executor, ACK and watchdog

Executor receives Command and the original plan, certificate, apply and expiry;
receiving the stream is not an ACK. ACK includes pending seq and is a pulse tied
to that transaction. Mismatched IDs are ignored and logged as replay. Golden wrapper
ACK Boolean maps to `ack_valid && ack_seq==pending.seq`; B9 receives expected_seq.
ACK pulses before apply do not persist: golden `b9_cert` returns pending; executor
must assert a qualifying ACK at/after apply and within its waiting contract. Config1
plans with apply beyond40ms cannot rely on a single earlier ACK to commit.

The independent deadline timer samples time at least once/us and checks pending
at40ms, apply, and expiry, with already validated immutable hashes. No new nominal
command may bypass apply/expiry authorization. A command sent earlier is rechecked
at executor. B12 retains a valid backup to stop; external watchdog uses its own clock.
Heartbeat is healthy at completed valid-clock transactions, low after unhealthy/live
ego/clock fault; physical pin toggles while healthy (ASSUMPTION-007). External ECU
detects absent toggles if core clock stops; static high is not a valid heartbeat.
ASSUMPTION-007 fixes heartbeat toggle period1000us while healthy; reset/health fault
drives the pin low immediately while core runs. Executor/ECU uses an independently
clocked missing-edge timeout within the external FTTI allocation. A stalled command
frame remains bit-stable even when override asserts. Override removes its authority;
the executor also checks apply/expiry on receipt. It may discard a now-expired frame
after completing transport. A partially transferred frame is never spliced with a
new command payload; independent brake has priority throughout.

### 6.3 Key waveforms

| Transaction | SVG | WaveJSON source |
|---|---|---|
| Ingress success, backpressure and CRC error | [ingress](figures/ingress.svg) | [JSON](figures/ingress.json) |
| Decision generate→check→select→issue→switch | [decision](figures/decision.svg) | [JSON](figures/decision.json) |
| Certificate expiry and lost ACK | [certificate](figures/certificate.svg) | [JSON](figures/certificate.json) |
| Recovery, L0→L1→L2→L3 and HOLD | [FSM](figures/fsm.svg) | [JSON](figures/fsm.json) |
| CSR success/error, split write and response stall | [bus](figures/axi.svg) | [JSON](figures/axi.json) |
| Executor stalled delivery, wrong ACK, timeout | [egress](figures/egress.svg) | [JSON](figures/egress.json) |
| Log overwrite with stalled reader | [log](figures/log.svg) | [JSON](figures/log.json) |

Diagrams illustrate ordering; symbolic gaps do not equate100ms to one core clock.
Normative boundary values are sections4/5/10, not the drawing scale.

## 7. Clock, reset and power

ASSUMPTION-001: one187.5MHz core domain for every internal/CSR/stream port. External
sources provide synchronized handshakes and coherent payloads; asynchronous system
signals require a SoC wrapper outside this IP. Reset asserts asynchronously and
releases through a two-flop core synchronizer. RAM contents are invalidated by valid
bits, not used before initialization. Reset during motion clears authorization and
requests independent mitigation; zero speed may justify HOLD only after valid live
state. No retained backup across reset. No clock gating or power-domain crossing in
v1; scan insertion and clock gating, if later introduced, require timing revalidation.
No logic can detect a stopped own clock without an independent external observer.

## 8. Parameters

| Parameter | Legal / default | Unit | Effect / invalid elaboration |
|---|---|---|---|
| `PARA_GEOM_LANES` | 4 / 4 | count | Other counts outside Config1 timing contract |
| `PARA_GEN_LANES` | 4 / 4 | count | Scalar not A7 conformant |
| `PARA_MAX_OBJ` | 32 / 32 | count | All objects checked; no relevance truncation |
| `PARA_MAX_CELLS` | 128 / 128 | count | Separate endpoint capacity129 |
| `PARA_PROFILES` | 16 / 16 | count | Fixed golden library order |
| `PARA_NUM_W` | 256 / 256 | bit | Fixed checked product width |
| `PARA_LOG_DEPTH` | 1..1024 / 64 | count | Pointer wraps modulo actual depth, not power-of-two mask |
| `PARA_HEALTH_WORDS` | 1..1024 / 1024 | count | Config protected memory capacity; finite hardware choice |
| `PARA_PKT_BYTES` | 65536 / 65536 | byte | Parser bound |
| `PARA_HASH_BYTES` | 32768 / 32768 | byte | Aggregate canonical binding material limit |
| `PARA_ADDR_W`, `PARA_DATA_W` | 16,32 | bit | CSR bus widths |
| `PARA_DIRECT` | 0 or1 /0 | none | Production stream or direct semantic verification interface |

Every RTL parameter declaration uses the exact VLSIT three-comment format:

```systemverilog
// Parameter Description: event ring capacity; pointer wraps modulo this value.
// Parameter values: 1 through 1024; default 64.
// Parameter unit: count
parameter logic [31:0] PARA_LOG_DEPTH = 64
```

Illegal structural settings fail elaboration; no simulation-only behavioral substitute.
Runtime limit/config choices live only in CSR JSON/workbook and are locked for Config1.

## 9. Data representation

### 9.1 Fixed-point domains and finite-bit bounds

All physical quantities use SI×S with S=1000000; time uses us, T=1000000. These
are decimal fixed-point values, not binary Q formats. Negative signed values are
two's-complement bit patterns with explicit sign extension/comparison in RTL.

| Field / intermediate | Width | Accepted or proven bound |
|---|---|---|
| x, lx, object.x | s64 | Ingress ±10000S; internal trajectory ±10070S |
| Ego v/lv | s32 | [0,10S]; corner10.05S; configuration extension to20S unvalidated |
| Actor v, trajectory bound v | s32 | [0,20S], actor preflight proves whole-horizon bound |
| Temporary nv | s32 | B3≤20.2S; primitive h≤12.8s gives≤45.6S, below2^26 |
| Ego a | s32 | [-8S,0]; uncertainties clamp to same range |
| Actor a/after_a | s32 | [-8S,2S] |
| Jerk | s32 | 0 or signed2S/4S/8S; j=0 denotes instant profile |
| Length/lane/y/errors/reserve | s64 | length(0,20S]; lane/y±10000S; half_width(0,10S]; lateral error[0,S]; reserve[0,10S] |
| Time/seq | u32 | Signed serial differences; all transaction spans below2^31us |
| Phase/delay/horizon/stop | s32 | Input phase≤12.8s, grid100ms; row absolute phase≤25.6s; delay≤100ms |
| Numerator/denominator/products | s96/s128/s160 by operation | Bounds and divider widths in5.5.1; B4 xn<2^154, xd<2^132, vn<2^111 |
| Gap/displacement | s64 | Broad±20600S; geometric gap below2^35 |
| Replay error | u13 /u10 | x_error≤4741LSB; n≤640; v allowance640LSB |
| Counters | good u2; lost u32 | Saturation3 and2^32−1, no rollover to healthy |
| Count / endpoint count | u8 | objects≤32,cells≤128,rows≤129 |
| Hash / CRC | u256 /u32 | Full width, never truncates hash to CRC |

Parser guards in s64 before narrowing; -2^63 rejects, as does s32 minimum pattern
-2^31 on numeric measurement ports. u32 timestamps reserve no NaN encoding.
Schema/presence bits carry numeric-invalid before packing. Overflow rejects; no
wrapping or saturating positions. `checked` is strictly asymmetric at the negative
endpoint as golden specifies. Bounds are inherited from FORMATS; G1 finite-bit tests
do not establish actuator/perception truth outside their contract.

B4 worst stop displacement≤30.916667m, with total horizon≤7.6s at10m/s. Outward
integration accumulates interval errors, not reset each step: v≤128LSB and
x≤128×(1+12.8)+11<1778LSB. Stop root bracket1us. B3 jerk inflate covers midpoint
quadratic versus continuous profile, including the1LSB midpoint acceleration bound.

### 9.2 Packed record ABI

ASSUMPTION-004: fields are concatenated in the order shown, first at the most
significant bit; arrays use ascending element order with element0 most significant.
Optional flags are separate from values; all unused slots/reserved bits are zero.
Direct semantic vectors are packed by field name, never by assuming fixture hex
field offsets match these aggregate records. All widths below are bits.

| Record / width symbol | Ordered fields | Width |
|---|---|---:|
| Ego / W_EGO | t32,x64,v32,a32,lx64,lv32 | 256 |
| Plan / W_PLAN | seq32,snapshot256,generated32,apply32,x64,v32,a32,tail8,compute32,count8,schema32 | 560 |
| Packet / W_PKT | present1,plan560,crc32,snapshot_ids[3]×32,schema32 | 721 |
| Ingress / W_ING | seq_valid1,seq32,time_valid1,last_time32,sample_valid1,last_sample32,sig_valid1,signature(x64,v32,a32,tail8),freeze_since32,freeze_x64 | 332 |
| Row / W_ROW | phase32,xlo64,xhi64,vlo32,vhi32,a32,jerk32 | 352 |
| Trajectory / W_TRAJ | accept1,reason8,stop_valid1,stop32,row_count8,rows[129]×352 | 45458 |
| Motion / W_MOTION | x64,v32,a32,length64,event32,after_a32 | 256 |
| World / W_WORLD | count8,objects[32]×256 | 8200 |
| Lane / W_LANE | lo64,hi64,y64,half_width64,lateral_error64,reserve64 | 384 |
| Certificate / W_CERT | present1,snapshot256,trajectory256,t_a32,t_e32,capability32,config32,controller32,scope32,context256,seal256 | 1217 |
| GeomResult / W_GEOM | accept1,margin64,reason8,steps8 | 81 |
| Event / W_EVENT | valid_schema1,count3,fields[4] each(tag1,length6,data256) | 1056 |
| Command / W_CMD | source3,mode3,label8,candidate8,seq32,apply32,expiry32,plan560,certificate1217,parking1,override1 | 1997 |
| TOP_RSP / W_TOP_RSP | accept1,reason8,mode3,candidate8,label8,independent_brake1,commit8,heartbeat1 | 38 |
| CSR_UPDATE / W_CSR_UPDATE | TOP_RSP38,busy1,pending1,backup1,healthy1,bist_done1,cycles32,lost32,irq_set8 | 115 |

Event tag0 means integer: sign-extended64-bit value in data[63:0], remaining bits0,
length0. Tag1 means string: length0..32; first ASCII byte at data[255:248], unused
bytes0. `valid_schema=0` models invalid original event without silently truncating it.
stop_valid0 encodes golden stop=-1; state valid0 encodes Python -1/empty sentinels.
Serial arithmetic is exactly `elapsed(a,b)=((a-b+2^31) modulo 2^32)-2^31`.
Positive wrap through zero is valid; a negative serial difference is regression.
Neither unsigned subtraction comparison nor ordinary signed timestamps substitutes
for this transform. Reinitialize supervision after ambiguous half-wrap separation.

| Composite payload | Ordered fields / width equation |
|---|---|
| ARITH_REQ | op8,q[12]x160; W_ARITH_REQ=1928 |
| ARITH_RSP | fault1,q[4]x160; W_ARITH_RSP=641 |
| CODEC_REQ | op8,start1,last1,byte_count3,data32; W_CODEC_REQ=45; ready/valid stream |
| CODEC_RSP | fault1,crc32,digest256; W_CODEC_RSP=289 |
| B1_REQ | Ingress,now32,Ego,Packet,local_crc32,parse_ok1; W_B1_REQ=1374 |
| B1_RSP | Ingress,reason8; W_B1_RSP=340 |
| B9_REQ | plan_present1,Plan,Certificate,now32,executor1,issued_valid1,issued32,ack1,seq_valid1,expected_seq32,context_valid1,expected_context256,phase_reuse1,local_snapshot256,local_trajectory256,local_seal256; W_B9_REQ=2904 |
| ARB_REQ | mode3,candidate8,label8,now32,pending_valid1,Plan,Certificate,backup_valid1,Plan,Certificate,Ego; W_ARB_REQ=3863 |
| HEALTH_REQ | schema_ok1,word_count11,parity_count11,words[1024]×32,parities[1024]×1,lane_pair2,onehot6,bist1; W_HEALTH_REQ=33824 |
| TOP_REQ | now32,Ego,Packet,Certificate,World,Lane,objects_present1,lane_present1,lead_braking1,capability1,health1,reset1,ack1,rear_ftti32,HEALTH_REQ; W_TOP_REQ=44673 |

Geometry mask bit i corresponds to library[i]. Mode codes follow MODES:
L0=0,L1=1,L2=2,L3=3,HOLD=4,RECOVERY=5. Invalid mode codes6/7 fault.
Onehot bit i represents mode i. Labels conditional=1,MITIGATION=2; code0=UNKNOWN
is reset/invalid metadata only; CERT-FULL is never emitted.

ASSUMPTION-010: reason8/status8 codes use this order, zero-based, shared across
interfaces. Strings in golden remain the semantic comparison; fixture reason CRC32
is compared by CRC32 of the decoded string, not mistaken for the enum value.

| Codes | Golden strings in increasing code order |
|---|---|
| 0..9 | ok, clock_reset, freeze_no_sample, timeout, numeric, range_schema, overflow, deadline, snapshot, crc |
| 10..19 | sequence, ego_freshness, freshness, freeze, range, phase_alignment, horizon, trajectory, lane_range, object_overflow |
| 20..29 | lane, object_range, object_speed_bound, time, separation, binding, replay, context_binding, lease_bound, expiry_at_executor |
| 30..39 | ack_timeout, committed, pending, late_apply, expiry, no_pending, splice, ftti_budget, geometry, capability |
| 40..44 | health, reset, no_backup, ego_live, bridge |

Counts exceeding allocated arrays reject before reading slots; count33 in World
represents object_overflow without needing a33rd stored object. Invalid original
type/range is represented by parse_ok/schema_ok=0 before narrowing. Health rejects
word/parity count mismatch or schema_ok=0, including out-of-range original onehot
values before six-bit narrowing. Undefined enum codes reject, never alias a reason.

Codec op0=packet CRC body;1=snapshot digest;2=plan digest;3=context digest;
4=seal digest. Fields follow the packed record table, big-endian two's complement;
pad each outer record with zeros at the LSB end to a multiple of8 bits. Nested
records use their exact bit widths without internal padding. CRC body is Plan560,
snapshot_ids[3]x32,schema32 (688 bits); Packet present and CRC are excluded.
SHA snapshot=Ego256; trajectory=Plan560. Context is World8200,lo64,hi64,
frame32=1,units32=1; unused World slots are zero. List order remains significant.
Context deliberately binds only lane lo/hi, preserving golden semantics. Seal body
is Certificate fields in table order excluding present and seal (960 bits); embedded
hashes are raw256 bits, not64 ASCII characters. Empty optional hashes encode zero;
a valid certificate requires recomputed matching hashes. Golden diagnostics use a
separate typed binary fixture encoding; it is never a decision-path wire format.
Legacy canonical/digest JSON functions are retained only as *_json_legacy.
Invalid Python fixtures may be encoded modulo field width, but parse validity and
original numeric guards must reject before CRC/hash/admission; packing never
turns an invalid measurement into an admissible one.

ARITH op0=checked(q0,bits=q1);1=ceildiv(n=q0,d=q1);2=disp(v,a,n,d,up);
3=advance(x,v,a,h,up);4=swept(gap,va,aa,vb,ab,h);5=profile_a(cid,t,initial);
6=ramp_integrals(v,a,j,target,h);7=continuous_advance(x,v,a,j,target,h,up);
8=elapsed(a,b), returning the sign-extended serial result in q0.
Operands fill q ascending in listed order, unused q=0; outputs q0 scalar for
ops0/1/2/4/5; q0=x,q1=v for3/7; q0=xn,q1=xd,q2=vn,q3=vd for6.
No primitive may rely on Python's unbounded integer overflow behavior.

## 10. Functional behavior

### 10.1 Exact top-level sequencing

| Step | Function / behavior | State effect / order |
|---|---|---|
| 0 | `live_ego_valid(now,ego)`; clock rollback against ingress.last_time | If false/rollback: health-fault FSM using v=S forces L3, clears pending/backup; update last_time if valid now; record(now,reason,L3,15); heartbeat0; return without hashes or fallback |
| 1 | Build context and effective world | explicit_world if objects OR lane present; absent objects uses legacy lead in effective world, but cert context objects remains empty |
| 2 | health input AND `b13_health`; capability input | Same health evaluated before composition checks; reset precedence applied later |
| 3 | Previous pending `b9_cert` at executor | ACK before new admission; committed→backup=(p,c),pending empty; other nonpending status clears pending; pending retains it |
| 4 | `b1_ingress` proposal | Do not commit proposal yet |
| 5 | If reason ok, `b9_cert` new certificate with context | Preserve first failure |
| 6 | If reason ok, `b2_splice` | Failure reason splice |
| 7 | If reason ok, `reaction_safe` | Failure ftti_budget |
| 8 | If reason ok, `nominal_geom` legacy lead proxy | Runs even when explicit world supplied, as golden does; failure geometry |
| 9 | Override reason if !cap, then !health, then reset | Later override wins; reset highest among these |
| 10 | Select current fallback using effective world | Explicit mode `select_world`, otherwise `select`; independent of new packet acceptance |
| 11 | If still ok, certify tail at apply | Explicit mode checks bridge and propagated full world; legacy mode `plan_tail`; tail15→no_backup |
| 12 | `reusable` AND cap AND health, then `b8_fsm` | Pending ACK result from step3 visible here |
| 13 | If accept, replace plan.tail with actual tail and `certify` anew | Commit ingress proposal; pending=(now,new plan,new cert). A later new admission can replace an older pending exactly as golden does |
| 14 | If reject, update ingress.last_time only | Other ingress state retains previous committed value |
| 15 | `b10_rec(now,reason,mode,current_candidate)` | Append even on reject; output label/candidate remain current fallback |

Speculative jobs can overlap only if observable results retain this sequence and
first-failure semantics. Health/liveness override does not wait for long division.
No partial candidate row authorizes output. Existing committed backup is replaced
only on actual committed status, never on delivery or certificate issuance alone.

### 10.2 Helpers and reuse

`lead_motion`: Motion(ego.lx,ego.lv,a=0,length4800000,event=max(0,500000−ego.t),
after_a=−4S for lead='braking', else0). This legacy event uses golden absolute ego.t
arithmetic exactly; do not replace it with a fresh500ms every frame.

`reaction_safe`: rear_ftti must exceed285000. Coast ego285000us, front brake−4S
immediately, then ego brake−8S for3000000us; both swept gaps must be≥500000 with
combined length4800000. These tests use Ego's legacy lead even in explicit world.

`nominal_geom`: delay=max(0,apply−snapshot.t), reject if>500000. Propagate legacy
lead across event; generate id15 from plan.x/v/a and check B3. This is the golden
proxy, not validation of arbitrary externally sampled nominal trajectories.
`plan_tail`: same lead propagation, delay≤100000, select finite-jerk tail from
plan apply pose. `propagated_objects`: propagate front actors using lower x/v,
rear actors using upper x/v based on original actor.x<ego.x, split at event and
reduce event by delay. Explicit bridge uses live ego's a and interval advance to
apply; zero delay skips bridge geometry. No actor reordering through an unchecked delay.

`phase_state`: original Plan apply retained; negative phase returns plan.x/v.
Replay up to12.8s in20ms steps plus final partial step, recomputing profile at
original epoch, lower rounded continuous integration. No state extrapolation from
a recently rounded row or restart of ramp. `reusable`: requires backup, phase≥0,
B9 phase_reuse ok and remaining>120000. Let n=min(640,ceil(phase/20000));
x_error=max(640,n+ceil(20000n(n−1)/(2T))+11). Require
abs(ego.x−px)+50000+x_error≤160000 and abs(ego.v−pv)+50000+640≤200000.
The short lease normally gives n≤25; do not remove general replay guards.

### 10.3 Latency budget and timing limits

S1b architecture: G=8 private B4 contexts and P=8 private B3 lanes, paired by
candidate. Candidates0..7 then8..15 run as two batches. Geometry starts on row
pairs as produced; complete-row buffering is not a prerequisite for computation.
Each lane retains32 independent actor interval states. Provisional results cannot
commit until all row/end-point/domain checks and terminal status have passed.
This budget counts all16 candidates in BOTH fallback and apply-time tail sweeps,
including diagnostic instant profiles even though selection excludes them.

With N=16,K=128,M=32,C4=1280,I3=48 and drain D3=1536:
Cgen=ceil(N/G)*K*C4=327680;
Cgeom=ceil(N/P)*K*M*I3=393216.
For each of two batches, row-pair fill C4 and final drain D3 are charged:
Csweep=max(Cgen,Cgeom)+ceil(N/8)*(C4+D3)=398848.
Two full sweeps cost797696 cycles. Geometry per row takes32*48=1536 clocks,
so FIFO depth32 row pairs per context covers128*(1-1280/1536)<22 row pairs;
terminal metadata and two endpoints require35 row slots. Use depth>=35 per lane.

Early-out is permitted only after all earlier finite-jerk candidates are resolved.
b7_select ranks by decel/jerk/name, matching select/select_world library traversal;
instant IDs3/7/11/15 never win. Later work in that same sweep can be cancelled.
tsmx_cycle still may perform the independent apply-time tail sweep. No early-out,
cache hit, omitted instant candidate or data-dependent rejection reduces this bound.

| Allocation | Cycles / decision | Time ms |
|---|---:|---:|
| Two full B4->B3 streaming sweeps | 797696 | 4.254379 |
| B1 / packed CRC | 16384 | 0.087381 |
| B2 splice | 12288 | 0.065536 |
| Nominal id15 proxy, generation overlapped with geometry | 166656 | 0.888832 |
| Explicit-world bridge | 3072 | 0.016384 |
| World propagation to apply | 20480 | 0.109227 |
| Reaction / FTTI primitives | 12288 | 0.065536 |
| Backup phase replay | 24320 | 0.129707 |
| B7 twice / B8 / B10 | 162 | 0.000864 |
| B9 all hash/check/reseal work | 32768 | 0.174763 |
| B13 dedicated BIST / health | 65536 | 0.349525 |
| CSR / arbiter / bounded stalls | 16384 | 0.087381 |
| **Worst-case total** | **1168034** | **6.229515** |
| Reserve to8ms target | 331966 | 1.770485 |
| Reserve to10ms A7 deadline | 706966 | 3.770485 |

Helper equations: nominal proxy is max(128*1280,128*32*48)+1280+1536
=199424 if all32 objects are checked; actual nominal_geom uses one lead actor,
so max(163840,6144)+2816=166656 is the golden composition bound. Explicit bridge
uses one cell:32*48+1536=3072. World propagation is32 actors*4 directed
advance operations*160 cycles=20480. Reaction and B2 each reserve12288.
Reusable backup was admitted with apply>=now>=generated; lease<=500000 and
remaining>120000 imply 0<=now-apply<380000, so replay n<=19 cells at20ms:
19*1280=24320. An arbitrary imported backup is outside reachable top state;
phase_state standalone still supports640 cells and is not a decision WCET claim.
B7 two reductions2*64, B8=32, recorder=2. B9 reserves32768 including pending,
admission, reuse, context and new tail reseal. B13 uses dedicated paired BIST
resources, two31-cell profiles in parallel:31*1280 plus geometry/drain<65536.
All helper work is added serially, never hidden in a candidate sweep.

B4 cell1280 includes two outward integrations, <=17 root tests each, four endpoint
quotients and acceleration/control. Two parallel ramp evaluators each use eight
wide multipliers (<=16 cycles/evaluation); two160-cycle dividers service endpoint
quotients in<=320 cycles. Root search<=272 cycles, endpoint evaluation<=32,
plus acceleration/rounding/control<=656 gives1280. No divide is needed per root
test: only vn sign. B3 II48 budgets up to44 directed quotients per actor cell
(two event pieces, each at most7 swept points*2 disp plus4 advances*2 quotient),
plus four spare issue slots; inflate/preflight are amortized over32 actors.
A private fully pipelined128-bit divider has II1 and latency<=128, with a separate
s96 integer-time pipeline for state updates. Lane microcode must fit all dependent
piece work into D3<=1536 and keep32 actor contexts; M<32 reduces work and
permits idle slots to satisfy dependencies. No single nonpipelined divider meets II48.
These are enforceable architecture budgets, not measured RTL or synthesis results;
RTL scheduling assertions and implementation timing remain sign-off requirements.

At1875000 clocks without a valid result reject deadline and assert independent
brake. This containment is not used to prove the above successful-decision bound.
FTTI285000us=wait100000+detect5000+compute10000+ACK40000+switch10000+
actuator100000+margin20000. ACK wait is outside compute; the independent timer
must service cached immutable B9 jobs within1us and tick at most20ms.


## 11. Registers

The authoritative software-visible register/field/offset/reset definitions are
[TSMX_CSR.xlsx](TSMX_CSR.xlsx), generated from [tsmx_csr.json](tsmx_csr.json).
No register map is duplicated here (R-016). The supplied workbook tool defaults
to APB; the artifact builder explicitly corrects its interface metadata to AXI4-Lite
and clears the unused asynchronous sample map (ASSUMPTION-006).

Software sequence: disable; restore supported configuration; request BIST; wait
for complete/valid; enable interrupts and operation. Unsupported configuration
cannot silently widen golden domains. Snapshot completed status atomically, read
event history by index, clear sticky interrupt causes after servicing. Clearing a
software interrupt does not authorize a certificate or erase a live health fault.

## 12. Error handling

| Error class | Detection / first result | Containment / recovery |
|---|---|---|
| Live ego mismatch / clock rollback | Before hash/geometry in top | L3, no pending/backup, heartbeat0; valid new projected epoch needed |
| Packet absent/corrupt/stale/frozen | Ordered B1 reason | Do not commit ingress proposal; mode uses reuse/fallback/capability |
| Splice / FTTI / proxy geometry | First failing gated checker | Reject new nominal; fallback still evaluated |
| Context/binding/replay/lease/expiry | Ordered B9 reason | No unauthorized commit; independent timer checks expiry |
| Wrong ACK ID | Adapter rejects ACK association | Ignore pulse, record replay; original pending timer continues |
| ACK lost at deadline | B9 ack_timeout | Clear pending; watchdog command override; run next decision in golden order |
| Object overflow / bad row / actor range | B3 false with explicit reason | No dropped object, no certificate from failed candidate |
| Health / reset | Final reason override | B8 clears records; HOLD only with valid zero speed elseL3 |
| Internal product overflow / divide-domain fault | Arithmetic fault | Fail parent check; no wrapped result used |
| Log full / invalid event | Saturating lost | Overwrite oldest for valid event; reject malformed event only; safety proceeds |
| Deadline / transport timeout | Wrapper timer | Block incomplete output, independent brake, log fault |

Admission checker order and capability/health/reset overrides are section10. The
live ego early return supersedes all. Misencoded mode/onehot protection drives health
false. Recovery requires three accepted decisions; hard reset does not restore old
backup. No error path can relabel mitigation as certified. `heartbeat=health` in
normal golden output is preserved even when a planner-only reject occurs.

## 13. PPA targets

S1b resource allocation (architecture estimate; no mapped area claim): G=8 B4
each owns16 wide multipliers (two eight-multiplier ramp evaluators) and two
s160 directed dividers; aggregate128 multipliers/16 dividers. P=8 B3 each owns
eight s128 multipliers, one fully pipelined s128 divider (II1) and one s96
divider pipeline for interval updates; aggregate64 multipliers/16 dividers.
B2/reaction/replay helper owns a separate B4-class arithmetic unit; BIST owns
two dedicated B4/B3 pairs. Multipliers here mean full logical operators,
not DSP slices. Width decomposition, pipeline registers and divider area need
synthesis. Relative to P4/G4, functional sweep arithmetic doubles; 35 row slots
per B3 lane and32 actor states are required. Doubling to16 was unnecessary for
the budget10.3. P/G are fixed elaboration parameters with no CSR fields in the existing map;
CSR JSON/workbook therefore require no parameter/reset change. No software
selection of an unverified configuration is allowed.

| Metric | Contract / evidence |
|---|---|
| Frequency |187.5MHz target, requires post-route timing |
| Compute |≤10ms hard deadline; unconditional successful decision WCET unproven |
| Latency estimate |8.455ms conditional one-sweep budget; scalar18.940ms fails |
| Area / power | No numeric guarantee; four generator/divider lanes and dedicated BIST materially affect resources |
| Old research estimate |22–36k LUT,36–52BRAM36,80–160DSP is historical only, not a budget for this architecture |
| Memory | Top staging, candidate row stores, per-lane object state, recorder and parity bits; implementation banking chosen after schedule proof |

ASSUMPTION-009: physical target starts with FPGA validation, then ASIC mapping.
Report actual part/library, corners, tool/version and all parameter overrides before
any PPA claim. No area/power synthesis was performed for S1.

## 14. RTL implementation contract

REQ-TSMX-022/023: follow VLSIT RTL rules: modules `m_tsmx_*`, packed vector ports,
explicit dimensions and extensions, `input wire` / `output logic`, unsigned logic
storage with explicit two's-complement arithmetic, identifiers≤30 characters,
zero-based instances, one driver per state, no latch, no real/float/divergent
simulation implementation. No synthesizable SV package/interface dependency.

Leaf source ownership is one directory per block; see BLOCK_ORDER.md. Independent
agents may rely on this ABI without importing another agent's local types. Private
arith/codec behavior must remain equivalent even if inlined for synthesis. Static
constants are named; parameters carry three required comments. `ifndef SYNTHESIS`
can include assertions/reporting only; it cannot bypass loops, change widths,
replace dividers, alter RAM init, skip CRC/SHA, or produce different valid/ready.
All reset/overflow/error paths use the same executable logic in both builds.

## 15. Verification

| Test ID | Scope | Golden mapping / acceptance criterion |
|---|---|---|
| UT-ARITH | All primitives | Signed floor/ceil, stop roots, stationary points, min-negative guards; parent b2/b3/b4 fixture replay |
| UT-CODEC | Serializer/CRC/SHA | Exact UTF-8 bytes and full digests from b1/b9 fixtures; leading-zero digests, negative ints, object order |
| UT-B1 | Ingress | b1 hex+schema and complete semantic I/O; wrap, future, freeze boundary, rejected proposal state |
| UT-B2 | Splice | b2; 8corners, negative delay, equality at tube bounds |
| UT-B4 | Every trajectory row | b4; all16 IDs, initial acceleration both sides of target, zero speed, short limit, off-grid phase |
| UT-B3 | Geometry | b3; lane edges, front/rear, actor event, intersample collision, final endpoint corruption,33objects |
| UT-B7 | Mask selector | b7 plus all65536 masks, instant-only pool gives15 |
| UT-B8 | Next-state transform | b8; reset/unhealthy, HOLD/reuse/fallback, three-good recovery and saturation |
| UT-B9 | Certificate | b9; all binding fields, context/order, wrongseq, lease and strict20ms/40ms/expiry boundaries |
| UT-B10 | Ring | b10 fixture capacity4; capacities1/64/1024, nonpower-of-two wrap, invalid event, lost saturation |
| UT-B13 | Health | b13; onehot0/3/64, parity/length, lane mismatch, BIST exact rows and blocked/clear jobs |
| UT-CSR | Workbook bus model | AW before W / W before AW, response stall, strobes, bad address, config lock, set-versus-clear |
| UT-ARB | Command source | System state snapshots in every mode; L3 fixed15 despite mild candidate; expiry during stalled egress |
| IT-SYSTEM | Stateful composition | system hex/json/ports; preserve prior state row-to-row, pending commit before new admission, reset and fallback |
| IT-TIMING | Full job schedule | Worst dual sweeps plus helper work/stalls; deadline bound and subcycle timer latency; post-route clock |
| IT-EQUIV | Build invariance | Identical traces with SYNTHESIS0/1; no decision conditional on macro |

Fixtures reside outside spec and remain read-only. At final S1 inspection, all ten
block/system `.ports.jsonl` files and `edges.ports.jsonl` exist. OI-004 tracks later
source/fixture changes. Each fixture `.json`
defines its hex widths/bit order. G1's `.ports.jsonl` carries semantic inputs/outputs
including intervals/hashes; adapter packs section9 and compares every meaningful
field. Helper arithmetic gets replay jobs extracted from the full semantic vectors,
not invented hidden state. Additional boundary tests are required even if128 samples
pass. New RTL-only CSR/transport behavior has no golden function; its source is the
recorded assumption and workbook, not a fabricated model.py API.

Assertions: payload stable under stall; no repeated request consumption; no stale
job after reset; state commits once per decision; no commit at expiry; seq matches
pending; L3 candidate authority15; no acceptance after overflow; good≤3; lost
saturates; row_count≤129; each actor checked; heartbeat low on health/live fault;
deadline override independent of egress/log/bus ready; no uncertified instant backup.
Formal arithmetic reasoning covers sign/rounding/overflow; physical contracts and
FTTI require integration evidence beyond finite random tests.

## 16. DFT

ASSUMPTION-009: functional BIST/parity is included as specified; production scan,
MBIST, ATPG coverage and test-clock topology are implementation-stage obligations,
not silently treated as complete. No v1 functional DFT port is added without a
defined mode; later inserted scan ports use VLSIT `i_dft_*` naming. Functional
reset and brake output behavior during manufacturing test require SoC isolation
review. BIST detects known faults; it is not a scan/MBIST coverage claim.

## 17. Physical implementation and timing

Constrain core period5.333333ns, all I/O synchronous to core with SoC-provided
input/output delays (ASSUMPTION-009, values pending physical integration).
No blanket multicycle/false-path exemption for divider or health logic: any
multicycle constraint must match enables and handshake proof. Paths to independent
brake/heartbeat require explicit timing review. Reset synchronizers carry intended
attributes; CDC/RDC review covers the SoC wrapper. No asynchronous input is silently
sampled as a coherent multi-bit state. RAM banking, divider retiming and buffering
must satisfy full two-sweep worst case, not just mean candidate completion.

## 18. Security and safety

Safety objective is bounded-time authorized execution under PLAN/FORMATS contracts.
Perception completeness, projected live estimate, braking capability, continuous
tracking tube, executor delivery and independent external watchdog are external
assumptions. Physical loss of chip/power is outside this RTL boundary. B3's ACCEPT
is for supplied occupancy arcs and containment, not arbitrary trajectory feasibility.
Conditional rear label does not establish unconditional rear collision avoidance.

Security boundary: CRC/SHA detects mismatch/corruption and binds context; an adversary
who can modify inputs and reseal certificates is not excluded cryptographically.
No key storage, secure boot or authenticated host is claimed. Register access control
is delegated to SoC. Fault injection coverage and diagnostic coverage await RTL/system
verification. Memory parity detects errors; it does not promise correction. A legal
but wrong onehot mode can escape onehot checking, so no complete FSM fault coverage claim.

## 19. Requirements traceability

| Requirement | Implementing modules / golden functions | Verification ID / method | Configuration |
|---|---|---|---|
| REQ-TSMX-001 | top,CSR; live_ego_valid | IT-SYSTEM,UT-CSR / I,D | Config1 |
| REQ-TSMX-002 | arith,splice,geom,mrmgen; arithmetic functions | UT-ARITH / D,A | All |
| REQ-TSMX-003 | codec; canonical,digest,packet,certify | UT-CODEC / D | All |
| REQ-TSMX-004 | ingress; b1_ingress | UT-B1 / D | All |
| REQ-TSMX-005 | splice; b2_splice | UT-B2 / D,A | All |
| REQ-TSMX-006 | mrmgen; b4_mrmgen | UT-B4 / D,A | All16 |
| REQ-TSMX-007 | geom; b3_geom,swept | UT-B3 / D,A | P4 |
| REQ-TSMX-008 | sel; b7_select,select,select_world | UT-B7 / D | All |
| REQ-TSMX-009 | supervisor; b8_fsm | UT-B8 / D,A | All |
| REQ-TSMX-010 | cert; b9_cert | UT-B9 / D,A | Config1 |
| REQ-TSMX-011 | top,arith,cert; phase_state,reusable | IT-SYSTEM / D,A | Config1 |
| REQ-TSMX-012 | rec; b10_rec | UT-B10 / D,A | Capacity1..1024 |
| REQ-TSMX-013 | health; b13_health | UT-B13 / D,A | Config1 |
| REQ-TSMX-014 | top; tsmx_cycle | IT-SYSTEM / D | Both world modes |
| REQ-TSMX-015 | top,arith; reaction_safe | IT-SYSTEM / D,A | Config1 |
| REQ-TSMX-016 | top; lead_motion,propagated_objects,nominal_geom,plan_tail | IT-SYSTEM / D | Both modes |
| REQ-TSMX-017 | top transport; assumption wrapper | IT-SYSTEM / D,A | All |
| REQ-TSMX-018 | CSR; workbook / assumption | UT-CSR / B | AXI4-Lite |
| REQ-TSMX-019 | full hierarchy; latency allocation | IT-TIMING / T,A | P4,G4 |
| REQ-TSMX-020 | top,cert,arb; b9_cert | UT-B9,IT-TIMING / D,A | Config1 |
| REQ-TSMX-021 | full hierarchy; b8_fsm,tsmx_cycle | IT-SYSTEM / D,I | All |
| REQ-TSMX-022 | full hierarchy; A7 | IT-EQUIV / D,I | Both macro builds |
| REQ-TSMX-023 | full hierarchy; packed ABI | All unit tests / I,A | All |
| REQ-TSMX-024 | arb; README arbitration | UT-ARB / D,A | All modes |

## 20. Assumptions, decisions and open items

User delegated all unspecified choices. ASSUMPTION-nnn records the decision rather
than requesting repeated approval. PLAN A1–A7 remain inherited binding assumptions.
All numbers absent from PLAN/golden are architectural choices under this table;
no assumption silently overrides a golden result.

| ID | Delegated choice / rationale | Status / validation needed |
|---|---|---|
| ASSUMPTION-001 | Single core clock, async reset assert/sync release, no retention or gating | SoC CDC/RDC integration pending |
| ASSUMPTION-002 | Explicit request/response ABI, state owned by top, no shared hidden state | Interface assertions and reset/cancel verification pending |
| ASSUMPTION-003 | Custom32-bit framed streams, 64KiB bound, two staging slots, bounded partial-frame stall | Transport tests pending; no AXI4-Stream claim |
| ASSUMPTION-004 | Packed record order/widths, separate invalid flags and local job routing | G1 fixture adapter and elaboration verification pending |
| ASSUMPTION-005 | S1b G8/P8 streaming dual sweep, per-op arithmetic, deadline rejection,1us timer service | Full architecture budget10.3 meets8ms; RTL schedule/synthesis evidence pending |
| ASSUMPTION-006 | CSR map, counters, sticky IRQs, configuration lock, indexed nondestructive log reads; workbook metadata adapted | Bus/CSR tests pending; map authority JSON/workbook |
| ASSUMPTION-007 | Command mux and watchdog wrapper, ACK ID mapping, heartbeat pin toggles, override independent of backpressure | Executor integration, ACK/apply schedule and external-clock watchdog pending |
| ASSUMPTION-008 | Protected word capacity1024, dedicated BIST resources; parity without correction | Resource/schedule verification pending |
| ASSUMPTION-009 | FPGA-first validation; later ASIC scan/timing/power implementation | Device/library/corner/I/O budgets and DFT sign-off pending |
| ASSUMPTION-010 | Shared enum encoding, complete typed event encoding and fixture adapters | Semantic vector equality pending |
| ASSUMPTION-011 | AXI4-Lite project contract, proposed IHI0022H | Local standard missing: R-006 conformance open |
| ASSUMPTION-012 | Recover22-section baseline from supplied writing guide | Original template missing: exact R-013 titles unverified |
| ASSUMPTION-013 | Deliver generated TikZ and offline SVG from same JSON without downloads | LaTeX compiler missing; R-018 build/render unavailable |
| ASSUMPTION-014 | S1b packed binary CRC/SHA, zero LSB byte padding; no JSON decision path | Golden codec/unit/identity evidence in verify/s1b; RTL byte/WCET tests pending |

| Open item | Impact | Decision/evidence needed |
|---|---|---|
| OI-001: RTL decision WCET | S1b full dual-sweep architecture budget closes A7 with margin | Prove cell1280, actor-cell II48/drain1536, FIFO/stall bound and187.5MHz after RTL/synthesis |
| OI-002: local AXI standard | Protocol conformance cannot be verified under R-006 | Supply licensed converted Arm IHI0022 source and reconcile wrapper |
| OI-003: missing VLSIT Markdown template/compiler | Exact-title template check and compiled diagram unavailable | Supply original template; install/provide compiler only with authorization |
| OI-004: concurrent G1 completion | Semantic files may appear or formats/model may change during S1 | Compare SOURCE_MANIFEST hashes and replay complete expanded fixtures before RTL |
| OI-005: ACK/apply contract | Single ACK before apply cannot commit under current B9 Boolean semantics | Executor must deliver qualifying ACK at/after apply within deadline; retain golden semantics |
| OI-006:20m/s extension | Config1 golden only validates10m/s | New bounds/golden/vectors/config version required before enabling |

R-001: report only executed script/inspection outcomes. R-002: all deliverables new
under spec. R-003/004: user delegated choices, recorded above. R-005: English artifacts.
R-006 open as OI-002; R-007/008 no converted documents created. R-009 no downloads or
installation. R-010/011/012 no external reference IP used. R-013 checked only against
explicit recovered baseline; original equivalence open. R-014 no fabricated user
exclusions. R-015 checked by skill logic. R-016 CSR validated/generated with tool.
R-017 diagram plus source and transaction SVG/JSON delivered; diagram is preview.
R-018 LaTeX generation done, compiler/build unavailable. R-019/020 draw.io not used.
R-021 mechanical artifact generation uses reproducible script under user-authorized
spec output scope. R-022 reuses existing openpyxl, no installation. R-023 no PyMuPDF
imported. No S1 RTL simulation, lint, synthesis or physical safety proof claimed.

## 21. Glossary

| Term | Meaning |
|---|---|
| A1–A7 | Binding scope decisions in PLAN |
| ACCEPT | Exact checker result for encoded contract, not a blanket safety claim |
| MRM | Minimum-risk braking maneuver in the fixed16-profile library |
| ODD | Operational design domain |
| FTTI | Fault-tolerant time interval; modeled reaction budget285ms |
| Tube | Reachability/tracking containment set around apply pose |
| Phase | Time from original immutable apply epoch |
| II | Initiation interval, distinct from completion latency |
| P / G | Geometry lane count / generator lane count |
| Config1 | Golden version1 capabilities and bounded operational configuration |
| CERT-FRONT/REAR-COND | Conditional label emitted by selector; no unconditional rear guarantee |
| MITIGATION | Deceleration without a certified separation guarantee |

## 22. References

Local references actually used are listed in section2, with source checksums in
[SOURCE_MANIFEST.json](SOURCE_MANIFEST.json). Reproduction entry point:
`py -3.13 -B tsmx_hw/spec/build_artifacts.py all`.
Artifact validation and its exact-title limitation are recorded in
[VALIDATION.txt](VALIDATION.txt). Dependency waves: [BLOCK_ORDER.md](BLOCK_ORDER.md).
No network research, third-party reference RTL or generated RTL is included in S1.
