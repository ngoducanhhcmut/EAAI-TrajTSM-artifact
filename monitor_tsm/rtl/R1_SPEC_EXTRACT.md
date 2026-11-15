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
| ARITH_REQ | op8,q[12]×256; W_ARITH_REQ=3080 |
| ARITH_RSP | fault1,q[4]×256; W_ARITH_RSP=1025 |
| CODEC_REQ | op8,Packet,Certificate,World,Lane; W_CODEC_REQ=8+721+1217+8200+384=10530 |
| CODEC_RSP | fault1,crc32,digest256; W_CODEC_RSP=289 |
| B1_REQ | Ingress,now32,Ego,Packet,local_crc32,parse_ok1; W_B1_REQ=1374 |
| B1_RSP | Ingress,reason8; W_B1_RSP=340 |
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

