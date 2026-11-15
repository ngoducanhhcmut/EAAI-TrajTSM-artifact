# Latency model — đầu vào cho S1, chưa phải WCET đã synthesis

Clock187.5MHz; 10ms=1,875,000 cycles. N=16, M≤32, K≤128,
P=4 geometry lanes. Golden tuần tự có thứ tự xác định, không mô phỏng timing RTL.
Mọi con số là ASSUMPTION kiến trúc, phải đo sau RTL; không suy ra LUT/DSP từ Python.

|Khối|Cận cycle / decision|Giả định|
|---|---:|---|
|B1|16,384|packet bound64KiB, CRC32 32-bit/cycle, schema/seq cùng pipeline|
|B2|12,288|8 corners; 256-bit restoring division và control guard|
|B3 P=4|786,432|ceil(16·128·32/4)·48; II48 cho swept rational primitive, latency được amortize|
|B4 scalar|2,621,440|16·128·1280; ≤5 dependent256-cycle divides / continuous integration cell|
|B7|64|16-way lexicographic reduction|
|B8|32|registered first-fault override|
|B9|32,768|SHA256 engine1round/cycle, ≤32KiB canonical prepacked material|
|B10|2|ring write không chờ host|
|B13|65,536|BIST profile31 cells qua B4/B3, parity on-access/onehot song song, 1 lane duplicate|
|CSR/arbiter/margin|16,384|bounded stream stalls; timeout rejects|
|Tổng bảo thủ, không overlap|3,551,330|18.940ms: **không đạt A7** cho scalar divider model|

B3 II48 yêu cầu pipeline divider, không thể có nếu chỉ một divider256-cycle/lane
không pipeline. Khi đó B3 còn chậm hơn cận bảng; phải xác nhận ở S1/R1.

Một cấu hình khả thi cần khảo sát: 4 generator context/divider lane, B4=655,360
cycles, geometry II48 giữ nguyên; tổng=1,585,250 cycles≈8.455ms, còn1.545ms.
Đây là estimate có điều kiện, **không chứng minh** đáp ứng10ms hoặc resource budget.
Có thể interleave16 candidates để che divider latency nhưng dependency x/v của
cùng candidate cấm giả định II1 vô điều kiện. Register coefficient, interval và
seal state qua stall; không được đổi thuật toán chỉ trong `ifndef SYNTHESIS`.

Host dump/vector/recorder drain không nằm trên critical path. Ack40ms là budget
giao dịch với executor, không cộng vào compute10ms; FTTI .285s bao gồm wait .1,
detect .005, compute .01, ACK .04, switch .01, actuator .1, margin .02.
Nếu implementation scalar mất18.940ms thì không được giữ budget FTTI .285 mà
không cập nhật bound và kiểm chuẩn lại; golden chỉ mô hình timeout/budget đã chốt.


## S1b


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



Arithmetic resources and width bounds are specified in spec5.5.1/13. Earlier scalar/P4/G4 estimates above are historical and superseded.
