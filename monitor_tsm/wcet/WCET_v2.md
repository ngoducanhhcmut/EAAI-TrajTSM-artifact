# W4b: streaming, reachable-path WCET, P=G=2

All RTL citations are relative to `tsmx_hw/`. v1 is retained. The numeric bound is
for acceptance to ordinary response assertion, with a continuously ready command
consumer: **B = 1,629,173 cycles**, **16.29173 ms at 100 MHz**, **8.688923 ms at
187.5 MHz**. Measured tightness is **947,256/B = 58.1434%**. This is an analytic
state-count argument, supported by simulations; it is not a formal verification certificate.

## Contract and applicability

Use P=G=2, 16 candidates, phase zero, at most 93 endpoints and 32 actors.
The requested elaboration is explicit; top defaults alone do not establish P=G=2
(`rtl/top/m_tsmx_top.sv:19`, `:23`). The 93-endpoint integer-grid proof in
`WCET.md`, section “A8 analytic row maximum”, still applies: v<=10, a<=2,
prefix 0.1 s, slowest ramp 2 s, brake 5.1 s and hold 2 s. Generator guards enforce
the domain (`rtl/mrmgen/m_tsmx_mrmgen.sv:109`), and engine epochs are zero
(`rtl/top/m_tsmx_engine.sv:1502`, `:1520`). Rejected requests take shorter paths.

Assume uninterrupted clock/reset, reachable state from reset, no injected storage
or control faults, no concurrent CSR reset, and ordinary RTL operation. Accepted
backup history is an invariant proved below, not a restriction to the measured jobs.
External executor readiness is an **ASSUMPTION**: with at most W_cmd stalled
DELIVER cycles, completion <= B+W_cmd (`rtl/top/m_tsmx_engine.sv:1100`). Without
that supplied bound, normal external completion is **UNRESOLVED**. Arbitrary host
response backpressure makes response *consumption* unbounded (`:603`), but does
not change response assertion. Host submission, AXI ingress before engine acceptance,
idle BIST and drain after a deadline rejection are outside this decision interval
(`:628`, `:639`, `:1117`). The separate watchdog is not used as the compute bound.

## Calibration: native Windows Icarus

Run `py -3 tsmx_hw/wcet/wcet_model_v2.py --calibrate`, then `--pair`, then no options.
Only `wcet/` is written. Copied unit benches, vectors, extra edge counters, compile
logs, simulation logs and index manifests are under `cal/<unit>/`. Arithmetic uses
145 deterministic stratified vectors; SU uses all 22,741 vectors. Generator and
geometry sample existing unit jobs, retaining their original golden row offsets.
This is calibration, not an exhaustive input-domain proof. Unit golden assertions
remain enabled. The sweep harness adapts the copied mrmgen parameter harness;
there is no existing `tb/unit/sweep/` bench. It stops after completion of candidates
0 and 1, with v=10, a=2, 32 far actors and P=G=2; it does not infer a full-sweep
latency from an acceptance mask (`rtl/top/m_tsmx_sweep.sv:98`, `:138`).

Icarus requires replacing the enum ternary at `rtl/arith/m_tsmx_arith.sv:865`
by equivalent if/else. Simulation-only RTL copies also replace `always_comb` with
`always @*`; copied benches receive an actual reset edge before four-state checks.
No original RTL or testbench is edited. Exact commands are implemented in the script;
both executables are `C:/iverilog/bin/{iverilog,vvp}.exe`; WSL is not used.

| Service | Largest calibration / W4 envelope | v2 interpretation |
|---|---|---|
| Arithmetic op0/5/8 | 2 / 4 each | >1.5x is real two-clock consumption/rearm slack; keep 4. SETUP directly responds (`rtl/arith/m_tsmx_arith.sv:716`, `:737`, `:751`). |
| op1/2/3 | 85/182/200 versus 87/184/202 | Keep W4 service envelopes; fixed quotient widths (`rtl/arith/m_tsmx_arith.sv:761`, `:770`, `:780`, `:995`). |
| op4/6 | 2,093/213 versus 2,803/215 | No >1.5x gap. Keep seven-point maximum despite data-dependent skipped points (`rtl/arith/m_tsmx_arith.sv:839`, `:865`, `:901`). |
| op7 | 377 ordinary; 2,195 sampled search | Keep base 379 and width-dependent E(h). Global W4 maximum is 3,005 at h<=12.8 s, a different h domain (`rtl/arith/m_tsmx_arith.sv:557`, `:796`, `:808`). |
| Generator row | 760 ordinary; 4,598 with searches; 70,350 for 93 endpoints | W4 770+amortized searches is close; keep it. Two searches can share a row, so 770 alone is not a per-row bound (`rtl/mrmgen/m_tsmx_mrmgen.sv:192`, `:221`, `:249`). |
| SU displacement | 22 versus 46 | >2x from charging four extra clocks to already-completed products. Use conservative 24, with schedule below (`rtl/geom/m_tsmx_geom_su.sv:180`, `:332`). |
| SU inflation | 23 versus 27 | Keep 27 (`rtl/geom/m_tsmx_geom_su.sv:261`). |
| Geometry | actor II 20..48 including cell boundaries; ACT..STEP <=49 including split; largest observed cell 1,241 including splits; largest job 85,766 (R=129,M=32) | W4 ordinary actor 50/cell 1,630 at M=32 is too large. v2 actor<=28, ordinary cell<=926, plus <=26 per split actor; full-cell split allowance is 832; at R=129,M=32 the W4/v2 job envelopes are 210,248/119,432 (`rtl/geom/m_tsmx_geom.sv:357`, `:364`, `:389`, `:396`). |
| Candidate pair | 73,511 versus W4 227,024 at R=93,M=32 | >3x: W4 adds streaming producer+consumer and overcounts SU waits. v2 <=90,736; launch/batch overhead is charged separately (`rtl/top/m_tsmx_sweep.sv:112`, `:118`, `:137`). |

The arithmetic program counts remain W4's explicit instruction counts: non-MUL=2,
MUL=7; RAMP=200, VN=99, DISP=105, DINT=91, PT23=20, PTX=80
(`rtl/arith/m_tsmx_arith.sv:249`, `:291`, `:318`, `:345`, `:353`, `:626`, `:633`).
No calibration value replaces these counts. A4's seven-point envelope is real slack
when fewer points are valid. Generator and geometry whole-job maxima may describe
different inputs; only matched R,M comparisons are meaningful. `cal/results_v2.json`
records individual JOB/TIMING checks and calibration summaries.

## Tight SU schedule and streaming recurrence

Index the SU START state as time 0. Multiplications become readable four clocks
after issue (`rtl/geom/m_tsmx_geom_su.sv:332`–`:346`). The longest displacement
path executes S1,S2,S3,S4,S5,S6,S7 at times 1..7; S8 at 9, S9 at 10,
S10 at 11, S11 at 15, S12 at 19, FIN at 20 (`:180`–`:258`, `:287`).
Thus acceptance, START and done observation fit within 24 clocks. Negative or
zero displacement can skip S11; it cannot add a state (`:237`, `:245`). Inflation's
dependent multiplies are genuinely serial; retaining 27 is safe (`:261`–`:285`).
All four SUs run together, so displacement costs their maximum, not four times it
(`rtl/geom/m_tsmx_geom.sv:499`).

Define A7=379 and E(h)=ceil(log2(max(1,h)))*101+202. The 101 is launch+VN99+sample;
202 is final full RAMP rerun (`rtl/arith/m_tsmx_arith.sv:808`–`:821`). Let
D=770=4+2*A5+2*A7 and J=2*E(100000)=3838. Generator service is
Gen(R)=4+770R+J. After zero-speed clipping each side stays zero, so at most one
search per side occurs over the whole generated trajectory
(`rtl/mrmgen/m_tsmx_mrmgen.sv:195`, `:211`, `:221`; `rtl/arith/m_tsmx_arith.sv:699`).
The first row needs <=20 clocks; each later endpoint has <=D ordinary work,
plus bursts whose total is <=J (`rtl/mrmgen/m_tsmx_mrmgen.sv:174`–`:268`).

For C=R-1, define F(M)=30+28M. Its 30 is ROW+INFL+inflation27+IWAIT sample;
28 is ACT+ISSUE+SU24+AWAIT sample+STEP
(`rtl/geom/m_tsmx_geom.sv:330`–`:400`). A fixed event lies inside at most one
strictly increasing-time cell, so add 26M for all event splits (`:364`, `:389`).
Standalone Geom(R,M)=8+2M+C*F(M)+26M, including initial OCHK and final SCHK
(`:312`, `:322`, `:403`). Producer row storage has 129 endpoints and accepts
independently of cell computation (`:245`, `:484`); terminal is independently
latched (`:248`). Therefore neither producer backpressure nor RAM arbitration
introduces another unbounded dependency.

For streaming, cell k finishes at max(previous finish, arrival of endpoint k+1)
plus that cell's work. Expanding this recurrence with endpoint spacing D gives
head+C*max(D,F), with total bursts J and splits 26M added once. A conservative
head includes the first two endpoints, launch/terminal drain and range checks:

`Pair(R,M) = 40 + 2M + D + J + C*max(D,F(M)) + 26M`.

The constant 40 exceeds first-row20 plus acceptance, guard, terminal and response
control counts (`rtl/mrmgen/m_tsmx_mrmgen.sv:174`, `:185`, `:263`, `:268`;
`rtl/geom/m_tsmx_geom.sv:312`, `:322`, `:403`, `:412`). Using max on *whole*
generator and geometry latencies without a startup allowance would be unsafe.
For R=93,M=32, Pair=90,736. Sweep=2+8*(4+Pair)=725,922, with eight batches,
two launches and registered completion/base advance
(`rtl/top/m_tsmx_sweep.sv:104`, `:112`, `:115`, `:123`, `:137`, `:144`).

## Reachable decision paths and replay limit

Fallback and duplicate launch simultaneously and join after both responses
(`rtl/top/m_tsmx_engine.sv:886`–`:905`). Duplicate is one cid0 trajectory with
private resources (`:1513`–`:1523`), so charge max(Sweep,one Pair), not their sum.
Nominal, bridge and tail can all occur before reuse; health can also occur in that
same decision (`:708`, `:867`, `:930`, `:945`, `:966`, `:986`). They remain charged.

W4's late retry edges do exist (`rtl/top/m_tsmx_engine.sv:1048`, `:1062`). They test
the codec error bit. To reach NEWHASH, reason must be zero (`:1034`): ingress
therefore accepted schema=1 (`rtl/ingress/m_tsmx_ingress.sv:169`–`:171`), and
the engine copies the admitted plan, changing only tail byte[79:72]
(`rtl/top/m_tsmx_engine.sv:1035`). Hash data has explicit zero padding (`:1341`,
`:1342`). Hash transport has fixed opcode/length, first/last/count derived from
its monotonically incrementing index (`rtl/top/m_tsmx_hash.sv:59`–`:73`).
For op2, the sole payload check is schema bytes66..69; it remains 1. Op4 has no
payload-schema checks (`rtl/codec/m_tsmx_codec_core.sv:253`–`:295`). Correct
70/120-byte transports cannot set w_bad. Hence these two backward edges cannot
be taken in a fault-free reachable decision. Malformed initial inputs can fail
earlier hashes, then take one fallback and skip tail (`rtl/top/m_tsmx_engine.sv:804`,
`:818`, `:919`). They do not enable a late retry. Injected storage faults are
outside this proof, and are not silently assumed to have zero latency.

Replay does **not** get generator's single-search amortization: math keeps braking
even at zero speed (`rtl/top/m_tsmx_math.sv:121`–`:124`, `:338`–`:369`). Instead,
bound its loop using its caller. Write g=plan.generated[271:240], a=apply[239:208],
e=expiry, n=now. Ingress success gives generated>=snapshot and generated<=now
(`rtl/ingress/m_tsmx_ingress.sv:129`–`:146`, `:192`–`:196`). NEWCHK success
requires 0<=apply-now<2^31, 0<expiry-now<2^31 and 0<expiry-apply<2^31
(`rtl/cert/m_tsmx_cert.sv:119`-`:141`). The margin and lease checks also prevent
a half-wrap ambiguity: ingress freshness gives 0<=now-generated<=snapshot age<=150000
(`rtl/ingress/m_tsmx_ingress.sv:23`, `:139`-`:143`, `:192`-`:199`). With
0<expiry-generated<=500000 from the lease check, successful margin checks force
0<expiry-now<=500000. The positive intervals apply-now and expiry-apply each
have bit31 clear, so their sum is <2^32 and must equal expiry-now without wrap.
Hence 0<=apply-generated<=500000 for every stored pending plan. Pending is
written only from this admitted path (`rtl/top/m_tsmx_engine.sv:1060`); backup
copies that pending plan on either timer commit or successful OLDCHK (`:616`,
`:733`). Reset clears their validity (`:1186`, `:1190`). CSR does not inject
arbitrary plan payloads.

RECHK success proves 0<e-g<=500000 through its private elapsed operation
(`rtl/cert/m_tsmx_cert.sv:89`–`:90`, `:109`–`:114`; lease parameter `:24`),
and 20000<e-a<2^31 (`:120`–`:121`). Since 0<=a-g<=500000, e-a<=500000.
Engine reuse additionally requires 120000<e-n<2^31 and 0<=n-a<2^31
(`rtl/top/m_tsmx_engine.sv:988`, `:998`). The two positive serial differences
sum to e-a without wrap (their sum is <2^32); therefore 0<=phase=n-a<380000.
At 20000 us per iteration, **at most 19 integrations** are possible, not 640
(`rtl/top/m_tsmx_math.sv:339`, `:368`). Charge a full search on every step:
Replay=4+20+19*(A5+A7+E(20000))=39,924 cycles. The loop's phase checks,
profile handshakes and integration waits are all included (`:338`–`:369`).
Only one REPLAY is reachable after eliminating the impossible late hash retry.
For arbitrary corrupted/preloaded history this invariant is **UNRESOLVED**;
the script separately prints a conservative 5,004,470-cycle diagnostic envelope.

## Closing W4's missing services and other terms

| Term | Bound and RTL argument |
|---|---|
| Codec/hash | H(L)=4+ceil(L/4)+32+66*ceil((L+9)/64). SHA EMPTY launch+64 RUN+ADD=66; at most 32 padding words. Serializing feed and SHA is conservative despite two banks (`rtl/codec/m_tsmx_codec_core.sv:234`, `:346`–`:368`, `:428`–`:440`, `:484`–`:489`). CRC is shorter (`:401`–`:406`). Seven L={86,1049,32,70,120,70,120} calls total 2,621 (`rtl/top/m_tsmx_engine.sv:739`, `:764`, `:775`, `:786`, `:797`, `:1041`, `:1055`). Private hash response drains automatically (`rtl/top/m_tsmx_hash.sv:95`). |
| Health lane | Structural wiring exactly connects the leaf and dedicated BIST pair (`rtl/health/m_tsmx_health_lane.sv:36`–`:51`), so there is no omitted auxiliary service. Fixed BIST v=1,a=0,cid0 (`rtl/health/m_tsmx_health.sv:102`) stops at 1.1 s and ends at 3.1 s (`:24`, `:25`): its 0.1-s grid velocity integrals are integers, giving 32 endpoints; allow 33. H<=1024+16+Gen(33)+2*(33+4+Geom(33,1))=34,150 (`:125`–`:150`; replay/capture `rtl/health/m_tsmx_health_bist.sv:78`–`:103`). Keep 1024 parity words even though nondirect engine uses six (`rtl/top/m_tsmx_engine.sv:709`). |
| Supervisor/rec/arb | Two clocks each, acceptance-to-RESP then consumption; decision logic is combinational (`rtl/supervisor/m_tsmx_supervisor.sv:70`–`:78`; `rtl/rec/m_tsmx_rec.sv:99`–`:108`; `rtl/arb/m_tsmx_arb.sv:178`–`:187`). Recorder overwrites the oldest entry when full; indexed host reads cannot stall append (`rtl/rec/m_tsmx_rec.sv:143`–`:165`, `:171`–`:190`). No external log readiness assumption is needed. |
| Reaction | 4+2A3+2A4=6,014 (`rtl/top/m_tsmx_math.sv:217`, `:230`, `:243`, `:256`). |
| NPROP / PROP | 4+32+M*(1+2A3); M=1 / 32 gives 441 / 12,996. Each actor advances on each side of its one event; unused slots rotate in <=32 clocks (`rtl/top/m_tsmx_math.sv:269`–`:300`, `:374`). |
| Bridge math / geom | 4+2A3=408 (`rtl/top/m_tsmx_math.sv:309`, `:322`); 6+Geom(2,M)=1,836 (`rtl/top/m_tsmx_sweep.sv:129`–`:135`; `rtl/top/m_tsmx_engine.sv:945`). |
| Nominal | 6+Pair(93,1)=75,522. Kind1 enables one cid15, one object; retaining 93 endpoints adds real slack (`rtl/top/m_tsmx_sweep.sv:98`, `:106`; `rtl/top/m_tsmx_engine.sv:867`, `:1344`). |
| Ingress / cert | 2+A8=6 (`rtl/ingress/m_tsmx_ingress.sv:233`–`:242`); <=3*(1+A8)=15 for OLDCHK/NEWCHK/RECHK once each (`rtl/cert/m_tsmx_cert.sv:90`, `:176`; `rtl/top/m_tsmx_engine.sv:726`, `:807`, `:992`). |
| Splice / selection | 2+16A3=3,234 (`rtl/splice/m_tsmx_splice.sv:125`–`:143`); two selections *2=4 (`rtl/sel/m_tsmx_sel.sv:83`, `:89`; `rtl/top/m_tsmx_engine.sv:908`, `:976`). |
| Glue / CSR | Retain 152=2*76 clocks for non-service engine control despite eliminating retry (`rtl/top/m_tsmx_engine.sv:76`–`:152`). CSR updates/status are nonblocking side inputs; concurrent CSR reset is excluded (`:1139`). AXI submission before request acceptance is outside the interval; CSR is not a waited-on compute service. |

## Composition and validation

Sum the table's scalar terms plus max(fallback,duplicate)=725,922 and
tail=725,922. Both full sweeps remain charged regardless of output masks.
The model returns **1,629,173**, leaving **245,827 cycles** below 1,875,000.
The dominant term is the two 32-object geometry streams, **1,451,844 cycles**.
The remaining slack versus measurement comes chiefly from charging all candidates
the slowest 93-row trajectory, 24-cycle SU service, maximum event splits, a full
health check, all optional pre-tail helpers, and 19 maximal replay searches together.
Measured average row count or collision early exits never shrink the bound.

The script checks every JOB/TIMING pair in **all** `*.txt` files in the requested
integration directory and in `tb/board/vl_stream_r3/reg300_board.txt`: **289 pairs**,
all <=B; maximum 947,256, second workload 843,634. These include repeated runs;
289 is a record count, not a count of distinct input vectors. Empty files are
reported explicitly. The worst logs end with a testbench coverage/budget failure
after their JOB PASS/TIMING records; those timings remain observations, not a
claim that the integration runs passed. See
`tb/integ/vl_claude_r17_a8_apos/worst_apos.txt:3`–`:6`.
The board interval is also conservatively checked against the same engine budget;
this observation does not analytically bound arbitrary AXI host stalls.
