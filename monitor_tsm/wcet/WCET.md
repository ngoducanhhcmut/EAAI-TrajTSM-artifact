# W4: analytic state-count audit, P=G=2
**FAIL to certify normal completion within 1,875,000 cycles.** Its bound is UNRESOLVED under the permitted read scope. A separate, proven response-assertion bound is **B_response=1,875,000 cycles**, including deadline rejection: 18.75 ms at 100 MHz; 10 ms at 187.5 MHz. This is not a proof that the decision computation finishes before its watchdog.
All citations are relative to `tsmx_hw/`. No measured latency supplies a constant. `golden/LATENCY_MODEL.md:38` S1b describes a different architecture; none of its budgets are reused. Top defaults are 8, not 2 (`rtl/top/m_tsmx_top.sv:19`, `:23`); P=G=2 is the requested elaboration ASSUMPTION, not verified deployment metadata.
Cycle convention: conservative service envelopes include acceptance, response sampling/drain and readiness for the next call. Four arithmetic boundary clocks cover acceptance, SETUP, RESP consumption and rearm; some are deliberately double-counted by callers. Reset release/clock stoppage and waiting to submit a request are outside the decision interval.

**Arithmetic micro-programs and divider**
| Unit / formula (cycles) | RTL evidence and trip bound |
|---|---|
| Non-MUL=2; MUL=7; program U=2(n+1)+5m, including END | `rtl/arith/m_tsmx_arith.sv:626` fetch/execute; `:633` counter 0..5; `:632` END. Prologue MOV=2 each, no extra END (`:688`). |
| RAMP U=200 (n=39,m=24); VN=99 (22,11, stops at ENDVN); DISP=105 (24,11); DINT=91 (22,9); PT23=20 (4,2); PTX=80 (19,8) | Explicit finite programs `rtl/arith/m_tsmx_arith.sv:249`, `:291`, `:318`, `:345`, `:353`; default END. `:657` VN exit. Script counts these entries directly. |
| Iterative D(W)=W/2+2 = 50/66/82 for W=96/128/160 | `rtl/arith/m_tsmx_arith.sv:995`: launch; `:1001` loads 48/64/80; `:1007` decrements; `:1009` finalize; one consumer sampling clock. Faults still finish. |
| Root extra E(h)=ceil(log2(max(1,h)))*(1+99+1)+(1+200+1) | `rtl/arith/m_tsmx_arith.sv:808`: launch, VN, sample/update; `:812` final full rerun at width<=1; `:818` halves width. Max 24 iterations from h<=12,800,000 guard (`:557`); h=100,000 gives 17, h=20,000 gives 15. |
| Standalone pipelined divider: 1+W/16 registered stages = 7/9/11 | `rtl/arith/m_tsmx_arith_div.sv:17`-`:19`, `:40`, `:68`, `:104`, `:118`; each stage has 16 combinational steps (`:77`), no data-dependent stalls. This module is not instantiated by the reviewed arithmetic engine. |
| A0=A5=A8=4 | `rtl/arith/m_tsmx_arith.sv:716`, `:722`, `:737`, `:751`: SETUP directly to RESP; four-clock service convention above. |
| A1=4+1+D160=87 | `rtl/arith/m_tsmx_arith.sv:723`, `:761`: launch and fixed divider wait. |
| A2=4+2*4+105+1+D128=184 | `rtl/arith/m_tsmx_arith.sv:386` four MOVs; `:726`, `:770`, `:774` program, launch, quotient. |
| A3=4+2*3+91+1+2D96=202 | `rtl/arith/m_tsmx_arith.sv:393` three MOVs; `:731`, `:780`, `:784`, `:789` two divisions. |
| A4=4+[2(2+4+2)+2(2+4+20)+3(2+80)]+7[2(1+4+105+1+D128)+1]=2803 | `rtl/arith/m_tsmx_arith.sv:839` point launch/sample and point programs; `:415` two-MOV point prologues; `:868`, `:884` two displacement sides, two MOVs each (`:435`); `:900` NEXT. Seven points 0..6 (`:901`); take every point valid. |
| A6=4+10+200+1=215; A7_base=4+10+200+1+2D160=379; A7_max(h)=379+E(h) | `rtl/arith/m_tsmx_arith.sv:399`, `:407` five MOVs; `:741`, `:746`, `:796`, `:823`, `:832`; stop flag (`:800`) permits one search per operation. |
Private arithmetic instances have one requester and drain each result before the next issue (`rtl/mrmgen/m_tsmx_mrmgen.sv:204`, `:205`, `:324`; `rtl/top/m_tsmx_math.sv:448`). Thus no unbounded arbiter wait. RF reads are combinational and writes take one edge (`rtl/arith/m_tsmx_arith.sv:509`, `:975`), with no RAM ready input.

**MRM generator, one row / context**
| Formula | Evidence / bounded loops |
|---|---|
| Per row <=4+2A5+2A7_base=770, plus stop-search extras; Gen(R)=4+770R+2E(100000) | `rtl/mrmgen/m_tsmx_mrmgen.sv:192` PREP, `:211`/`:215` two profiles, `:221`/`:225` lower/upper integrations, `:232` STEP, `:240` ROW, `:249` CHECK. Four outer clocks include accept/GUARD/END/RESP (`:174`, `:185`, `:263`, `:268`). Terminal row charged full work conservatively. |
| At most one stop search per lower/upper side per context, not per row | `rtl/mrmgen/m_tsmx_mrmgen.sv:195` zero speed forces zero acceleration/jerk after prefix; clipped zero remains zero; `rtl/arith/m_tsmx_arith.sv:699` sets velocity zero on stop. Positive-prefix case cannot clip to zero. |
| R<=129 structurally, R<=93 in A8 phase-zero sweeps | `rtl/mrmgen/m_tsmx_mrmgen.sv:19`, `:110` limit<=128; count increment `:241`; held terminal endpoint `:254` can add one row after 128 integrations. Therefore 128 is not a universal endpoint-count bound. |
ROW ready cannot block in the paired sweep: geom accepts up to 129 endpoints independently of computation (`rtl/geom/m_tsmx_geom.sv:245`), and cannot respond before terminal (`:331`); producer cannot exceed that capacity. Terminal ready is available until accepted (`:248`); arithmetic is private. Response stalls of an isolated generator require an explicit consumer assumption; sweep wires it to terminal ready (`rtl/top/m_tsmx_sweep.sv:120`).

**Geometry, one cell / context**
| Formula | Evidence / bounded loops |
|---|---|
| SU displacement S<=14+8*4=46; inflation I<=7+5*4=27 | `rtl/geom/m_tsmx_geom_su.sv:166` START, `:180`-`:258` twelve displacement states, `:287` FIN; eight waiting states S4,S6..S12. Inflation has five waits (`:261`-`:285`). Each tagged product visible after four pipeline clocks (`:332`-`:346`), so charging four EXTRA clocks per wait is conservative. |
| C=R-1 cells; cell<=1+1+I+1+M(1+1+S+1+1)=30+50M | `rtl/geom/m_tsmx_geom.sv:330` ROW, `:351` INFL/IWAIT, `:357` ACT, `:371` ISSUE/AWAIT, `:396` STEP. Four SUs run in parallel (`:499`), so use maximum, not sum. |
| Geom(R,M)=8+2M+C(30+50M)+48M | `rtl/geom/m_tsmx_geom.sv:312` OCHK M+1; `:322` SCHK M+2; accept, terminal ROW, FIN, RESP add five. Extra split ISSUE+S+sample=48 per actor (`:364`, `:389`); a fixed event can lie strictly inside only one increasing-time cell. |
| C<=128, M<=32 | `rtl/geom/m_tsmx_geom.sv:27`, `:31`, `:337`, `:338`, `:397`; malformed/empty world skips work (`:338`), invalid terminal rejects (`:211`). No unchecked infinite actor loop is entered for M>32. |
Row wait is bounded by Gen; terminal wait by generator drain. All four SUs are dedicated and always return to IDLE with sticky done (`rtl/geom/m_tsmx_geom_su.sv:302`, `:307`); no contention. Row RAM writes are synchronous, reads asynchronous, registered cell operands settle before use (`rtl/geom/m_tsmx_geom.sv:159`, `:484`, `:494`). No RAM handshake can stall.

**Sweep**
| Formula | Evidence / bounded loops |
|---|---|
| S(R,M,N,q)=2+ceil(N/q)*(4+Gen(R)+Geom(R,M)); q=min(P,G)=2 | `rtl/top/m_tsmx_sweep.sv:24`, `:104`, `:112` geom launch, `:115` generator launch, `:123` done capture, `:137` registered done/base advance, `:144` RESP. Two full sweeps each have 8 batches; no early cancellation. Serial addition safely discards streaming overlap. |
| Nominal N=q=1; duplicate N=q=1; bridge N=q=1,R=2, omit Gen | `rtl/top/m_tsmx_sweep.sv:98`, `:106`, `:129`-`:135`, `:138`; 16 candidates fixed by base<16. `rtl/top/m_tsmx_engine.sv:867`, `:1513`-`:1523` instantiate nominal/duplicate paths. |
Private lanes cannot contend across batches; a batch ends only after both responses. Endpoint ready/terminal arguments above break the streaming dependency cycle. Acceptance masks are results, not candidate-enable masks (`rtl/top/m_tsmx_sweep.sv:125`, `:138`); even mask 0000 cannot justify fewer than 16 executions.

**Math helpers**
| Formula | Evidence / bounded loops |
|---|---|
| Reaction=4+2A3+2A4; bridge=4+2A3 | `rtl/top/m_tsmx_math.sv:217`, `:230`, `:243`, `:256`; bridge `:309`, `:322`. Four clocks cover accept/START/RESP/rearm. |
| Prop(M)=4+32+M(1+2A3); nominal Prop(1) | `rtl/top/m_tsmx_math.sv:269` OBJ, `:279`, `:292` two advances, `:300` rotate/increment; `:374` finishes at 32 rotations. M<=32 guarded at `:196`. |
| Replay<=4+641+640*(A5+A7_base+E(20000)) | `rtl/top/m_tsmx_math.sv:201` initialization; `:338` PHASE, h=min(remaining,20000), cap t=12,800,000; `:347` profile, `:360` integrate, `:368` increment. Max 640 integrations, 641 phase checks; conservatively charge profiles/search on every iteration. |
All math waits use the one private arithmetic instance (`rtl/top/m_tsmx_math.sv:448`); response ready is tied high (`:456`). Fault responses/zero delay shorten work. The final partial step is followed by termination, so cannot produce an infinite zero-step loop.

**Hash**
| Formula | Evidence / bounded loops |
|---|---|
| H(L)=1+ceil(L/4)*Q_codec+F_codec | `rtl/top/m_tsmx_hash.sv:59`, `:62`-`:73`: each accepted beat advances index by 4; final WAIT uses codec response. Seven engine calls L={86,1049,32,70,120,70,120}, total 389 beats (`rtl/top/m_tsmx_engine.sv:739`, `:764`, `:775`, `:786`, `:797`, `:1041`, `:1055`). |
**ASSUMPTION / UNRESOLVED:** finite codec ready/response bounds Q_codec,F_codec. `rtl/top/m_tsmx_hash.sv:95` instantiates `m_tsmx_codec`, whose implementation is outside the read list. Being its sole requester proves no external contention, not bounded internal service. No numeric codec latency is invented.

**BIST / health**
| Formula | Evidence / bounded loops |
|---|---|
| Leaf H_leaf<=1024+10+Gen(129)+2+2*(129+4+Geom(129,1))=125070 | `rtl/health/m_tsmx_health.sv:20`, `:67`, `:125` at most 1024 word checks plus final check; `:137`-`:150` GEN then two B3 calls with one object (`:93`). Ten control/service clocks overcount final check and three request/response pairs. |
| BIST replay <=129 endpoint sends+4 controls+Geom(129,1); generator capture adds 2 | `rtl/health/m_tsmx_health_bist.sv:20`, `:78` capture READ/HOLD; `:95`-`:103` replay bounded by terminal row count; RAM async read `:75`, sync write `:126`; generator row ready=1 (`:135`). |
**ASSUMPTION / UNRESOLVED:** engine instantiates `m_tsmx_health_lane`, not the health leaf (`rtl/top/m_tsmx_engine.sv:1459`). Its omitted wiring/checks prevent using H_leaf as an engine health bound. Engine has six protected words in nondirect mode (`:709`); standalone default is 1024. Idle BIST (`:639`) is before request acceptance and excluded; per-decision health may run BIST again.

**Ingress**
| Formula | Evidence / bounded loops |
|---|---|
| Ingress<=2+A8=6 | `rtl/ingress/m_tsmx_ingress.sv:233` accept, `:237` ISSUE, `:238` sample private op8, `:242` RESP; `:269` private instance. No iterative data loop. |

**Certificate**
| Formula | Evidence / bounded loops |
|---|---|
| Cert<=1+A8=5; at most four calls | `rtl/cert/m_tsmx_cert.sv:90`-`:94` helper accepted simultaneously, `:154`, `:176`, `:212` private arithmetic. Calls OLDCHK/NEWCHK once and RECHK up to twice across retry (`rtl/top/m_tsmx_engine.sv:726`, `:807`, `:992`); no waiting for an external ACK, just sampling fields. |

**Splice**
| Formula | Evidence / bounded loops |
|---|---|
| Splice<=2+16A3=3234 | `rtl/splice/m_tsmx_splice.sv:125` accept, `:131` GUARD; `:138` ISSUE/WAIT; `:141` 4-bit corner stops at 15, increments at `:143`. No short circuit of issued jobs. |

**Selection**
| Formula | Evidence / bounded loops |
|---|---|
| Sel<=2 per call, at most three including retry | `rtl/sel/m_tsmx_sel.sv:83` direct IDLE->RESP; `:89` drain. Combinational fixed priority `:105`, not a 16-cycle scan. Engine calls `rtl/top/m_tsmx_engine.sv:908`, `:976`. |

**Engine glue, missing services, and composition**
| Formula | Evidence / bounded loops |
|---|---|
| Glue<=2*76=152 non-service clocks, ordinary fault-free-control path | 76 enumerated states `rtl/top/m_tsmx_engine.sv:76`-`:152`; the only normal backward edges are late hash failures (`:1048`, `:1062`) to OVERRIDE. They set reason=4; the retry cannot return to NEWHASH because COMMIT0 tests reason==0 (`:1034`). Thus each state at most twice; waits are charged separately. |
| Reviewed-unit envelope E=2S(R,M,16,2)+S(R,M,16,2)+2S(R,M,1,1)+S(R,1,1,1)+S_bridge(2,M)+Math+Ingress+4Cert+Splice+3Sel+152 | Two normal fallback/tail sweeps (`rtl/top/m_tsmx_engine.sv:886`, `:966`); one retry fallback; duplicate runs alongside each fallback (`:888`) but is conservatively added; nominal (`:867`), bridge (`:945`); math reaction/NPROP/bridge/PROP once, replay up to twice (`:835`, `:856`, `:930`, `:956`, `:1006`). |
| E(93,32)=8,701,321; B_completion=E+H_lane+7+389Q_codec+7F_codec+2U_super+U_rec+U_arb+W_cmd | E is a sum of conservative envelopes for reviewed units, not a total bound or a lower bound on actual runtime. Missing services are symbolic, never zero. E alone already exceeds the requested certification budget; tightening overlap/search/replay would be necessary even after closing missing dependencies. |
**ASSUMPTION / UNRESOLVED:** U_super,U_rec,U_arb include readiness, response and rearm (`rtl/top/m_tsmx_engine.sv:1019`, `:1065`, `:1090`; instances `:1421`, `:1431`, `:1443`). Recorder may depend on host log traffic: cannot decide from these files. W_cmd is external `i_cmd_ready` stall at DELIVER (`:1100`). Assume finite supplied bounds to obtain finite normal completion; none are supplied. Unlimited `i_rsp_ready` stall makes response-consumption latency unbounded (`:603`). DRAIN readiness (`:1117`) also needs all these services; reacceptance is not proven bounded.
For the ordinary composition assume uninterrupted clock/reset, valid FSM encodings, no concurrent CSR reset (`rtl/top/m_tsmx_engine.sv:1139`), and the requested P=G=2. Internal arithmetic/geometry producer responses need no fairness assumption beyond their counted FSMs. CSR/ACK/time input changes do not suspend the independent deadline counter.
**B_response proof:** acceptance sets active and count=1 (`rtl/top/m_tsmx_engine.sv:628`-`:637`); each active nondeadline cycle increments it (`:1124`-`:1126`). At count=1,874,999, absent earlier response, it asserts response, revokes pending/backup, suppresses command and enters DRAIN (`:1127`-`:1136`). Continuous assignments expose registered valid (`:576`). Hence <=1,875,000 clocks conservatively from acceptance to first response, regardless of service/backpressure. This proves a rejection deadline only; normal completion and next-request readiness remain UNRESOLVED.

**A8 analytic row maximum (phase=0)**
The library is b={2,4,6,8} and finite j={2,4,8}, plus instant (`rtl/mrmgen/m_tsmx_mrmgen.sv:93`-`:104`); acceleration profile is `rtl/arith/m_tsmx_arith.sv:166`-`:192`. Prefix=0.1 s, steps=0.1 s and hold=2 s (`rtl/mrmgen/m_tsmx_mrmgen.sv:103`, `:117`, `:253`). All sweep epochs are zero (`rtl/top/m_tsmx_engine.sv:1502`, `:1520`).
The pointwise largest acceleration envelope over all entries and a<=2 is a*(t)=2 during prefix, max(2-2(t-0.1),-2) afterward. For initial a>=target, larger jerk/braking magnitude only lowers acceleration; for initial a<target, the entire ramp stays <=target<=-2. Initial v<=10 gives v(0.1)<=10.2. Slowest b2/j2 takes (2+2)/2=2 s to reach -2; its ramp adds 2*2-2*2^2/2=0 velocity. Then 10.2/2=5.1 s braking: stop at 7.2 s. Hold ends at 9.2 s; rows include t=0 and terminal t=9.2, so **K_max=93**, attained by cid0,v=10,a=2.
Rounding proof for the smaller-than-128 bound: the envelope's prefix increment is 200000 speed units; its twenty ramp increments are 190000-20000k (k=0..19); then every brake increment is -200000. All are integers in the 1e-6 SI representation. Integration is monotone in velocity and the acceleration integral; directed ceil cannot exceed an integer envelope endpoint. Induction gives RTL upper speed <=envelope on every grid endpoint; negative VN is clipped to zero (`rtl/arith/m_tsmx_arith.sv:800`, `:699`), so all profiles stop by endpoint 72 and finish the hold by endpoint 92. Lower rounding and numeric rejection cannot extend it. No numerical tolerance or grid-based proof is substituted for this argument.
Golden rows are endpoints, including the appended held endpoint (`golden/tsmx_golden/model.py:406`-`:437`, especially `:430`, `:435`). `py -3.13 tsmx_hw/wcet/wcet_model.py --grid` checked 3696 combinations: v=0..10 by 1, a=-8..2 by 0.5, all 16 candidates. All accepted, maximum 93, unique grid witness (10,+2,cid0), stop=7,200,000 us. Position fixed at zero; position-dependent arithmetic failures can only terminate earlier. Grid enumeration corroborates, not proves, the bound.

**Data dependence and measured checks**
All guards/fault exits in arithmetic (`rtl/arith/m_tsmx_arith.sv:527`, `:718`, `:775`, `:791`, `:834`), point validity/skips (`:865`), sign/rounding/stop clipping (`:648`-`:684`, `:699`, `:800`), generator stopped-prefix/profile/held/horizon (`rtl/mrmgen/m_tsmx_mrmgen.sv:185`, `:195`, `:254`), geometry lane/object/speed checks, event split, zero objects and collision exits (`rtl/geom/m_tsmx_geom.sv:211`, `:330`-`:400`) use maximum work above. Divider work is fixed even on error. Math rear guard, invalid count, numeric failures, delay and replay horizon (`rtl/top/m_tsmx_math.sv:188`-`:379`) use their full paths. Health header/parity/BIST skips (`rtl/health/m_tsmx_health.sv:125`), admission/certificate/splice rejects and every engine optional path/reuse/hash retry (`rtl/top/m_tsmx_engine.sv:642`-`:1063`) are included or explicitly unresolved above. Selection mask changes values, not latency.
`job_bounds.csv` lists EVERY matching JOB/TIMING pair with row/object parameters, both masks, reviewed envelope, predicted response bound and slack. Masks do not justify omitted sweeps; `stream_hits` does not establish timing. All 14 available jobs satisfy predicted response>=measured; min/max slack=927744/1658868 clocks. These checks validate only the response/watchdog bound, not normal-completion WCET. `reg300` has only jobs 288..299; `apos` has zero records, so there is no positive coverage there. `summary` has zero JOB/TIMING records. Observed worst is 947256, not the prompt's 947263; both are kept distinct. Requested tightness 947263/B_response=50.520693%; tightness against B_completion is UNRESOLVED.
