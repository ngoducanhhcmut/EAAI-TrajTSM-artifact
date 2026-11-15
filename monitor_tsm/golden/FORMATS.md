# Định dạng và cận của golden G1

ASSUMPTION A1: đường thẳng, footprint axis-aligned, yaw = 0; không đổi làn.
Đơn vị mọi tọa độ/chiều dài/vận tốc/gia tốc/jerk là SI × S, S=10^6.
Thời gian là microsecond, T=10^6; decision step=100000, physical bridge=20000.
Đây là decimal fixed-point (chia hằng), không phải binary Q-format.
Không có float/Fraction/Arb trong package `tsmx_golden`.
Parser/adapter dùng guard s64 trước khi narrow về các port logic s32/u32.
NAN adapter=-2^63 phải reject trước pack/narrow, không được mask thành0.
Ở port s32, pattern -2^31 cũng bị range reject; timestamp u32 không reserve
NaN vì cần toàn miền wrap: numeric-invalid phải đi qua schema/validity của parser.

|Biến/nhóm|Bit signedness|Miền được chấp nhận|
|---|---|---|
|x, lx, object.x, row.xlo/xhi|s64, -2^63 là NaN sentinel|Ingress ±10000 m; nội bộ ±10070 m|
|v, lv, row.vlo/vhi|s32 logic, s64 guard|ego [0,10], corner ≤10.05, object [0,20] m/s|
|temporary nv trước ODD intersection|s32|B3 cell≤20.2; primitive advance h≤12.8s cho cận≤45.6 m/s; đều<2^26 LSB|
|a, midpoint/start/target|s32|ego [-8,0], uncertainty clamp [-8,0] m/s²|
|object.a/after_a|s32|[-8,2] m/s², tốc độ trên mỗi bước vẫn ≤20|
|jerk, signed jerk|s32|0, ±2, ±4, ±8 m/s³; 0+instant có nghĩa riêng|
|length, lane, y, half_width, errors, reserve|s64|length (0,20] m; lane ±10000 m; errors không âm|
|now, snapshot.t, generated, apply, expiry, seq|u32|serial arithmetic; mỗi transaction <2^31 μs|
|phase, delay, step, horizon, stop|s32|phase/horizon [0,12800000]; delay ≤100000; step ≤100000|
|AGE, ACK, MARGIN, FTTI reaction|s32|150000,40000,20000,285000 μs|
|lease tối đa, phase_reuse|u32/u1|500000 μs từ generated; reuse không refresh apply|
|replay step count, x_error|u10/u13|n≤640; x_error=max(640,n+ceil(.02·n(n−1)/2)+11)≤4741 LSB|
|tail/candidate, schema, capability/config/controller/scope|u8/u32|id 0..15; phiên bản hợp đồng =1|
|count, row index, limit|u8|object count ≤32, limit≤128, endpoint count≤129|
|mode, onehot, good|u3/u6/u2|6 modes; đúng 1 bit; good bão hòa tại3|
|accept, health, ack, capability-present, fault_latched, heartbeat, live_ok, clock_bad|u1|0/1; bool là cờ, không phải số đo|
|reason, commit status, label|u8 mỗi enum khi encode RTL|golden dùng string enum cố định; vector dùng reason CRC32|
|seq/last_time/last_sample/signature valid|u1 riêng mỗi trường|Python dùng -1/empty tuple làm invalid marker, không gửi -1 lên wire|
|signature, freeze_since, freeze_x|{s64,s32,s32,u4},u32,s64|giữ x/v/a/id tại lần thay trajectory; epoch không refresh|
|recorder capacity, ring pointer|u11/u10|capacity1..1024, pointer modulo capacity; event digest tùy interface S1|
|CRC, sequence, event lost|u32|CRC-32 IEEE; lost bão hòa 2^32−1|
|snapshot IDs, recorder event|u32 ids / bounded record|3 coherent ids; ring64 mặc định, tối đa1024; event≤4 fields s64/string≤32|
|SHA256 snapshot/traj/context/seal, output digest|u256|S1b packed big-endian records; đầy đủ trường, không cắt hash|
|numerator, denominator, cross-products|s96/s128/s160 by operation|cận dẫn xuất bên dưới; checked trước phép chia|
|margin/clearance, displacement/delta|s64|cận rộng ±20600 m (horizon ≤12.8 s)|

## Cận không tràn
1. Ingress chỉ nhận int (bool không thay int), loại sentinel và range vi phạm. Dữ liệu
   vị trí không wrap/saturate thành một vị trí có vẻ an toàn. Overflow ⇒ reject.
2. Vận tốc ego không tăng vì a≤0. Profile b2/j2 từ a0=0 dừng chậm nhất:
   prefix .1 + ramp 1 + coast-equivalent braking 4.5 =5.6s; hold2 ⇒7.6s≤12.8s.
   D_stop≤1+(10−1/3)+9²/4=30.916667m. Con số 30m/6s trong design không phải
   cận cho toàn bộ A2: golden giữ cận thật và không cắt trajectory ở 30m/6s.
   x nội bộ ≤10000+31m+error. Corner actuator ở10.05 không tạo overflow s32.
3. Object v≤20, |a|≤8; trong12.8s displacement≤256m khi v bound được duy trì.
   Hai tọa độ/footprint/reserve cho gap <(20000+512+40+1)S<2^35.
   s64 có >28 bit dự phòng; geometric API cần bounded actor contract.
4. B2/B3 `disp`: với n≤vT≤2·10^13, d≤8·10^6, T=10^6,
   mọi tích bậc hai <2^153; swept stationary-point cross-product <2^110.
5. B4 capped ramp: d≤8·10^6, h≤10^5, |v|≤10^7, |a|≤8·10^6.
   xd=6T³d³<2^132; |xn|≤(2m·S)xd<2^154; vn<2^111.
   Tích không vượt s160; checked không phụ thuộc arbitrary-precision wrap của Python.
6. Thời gian cộng được mask u32 duy nhất ở wire boundary. elapsed là phép trừ
   signed serial. Wrap hợp lệ qua0; regression/reset hoặc cách nhau ≥half-period
   phải tái khởi tạo supervisor; không suy ra thời gian thực từ clock đã dừng.
   External watchdog/executor clock độc lập nằm ngoài A4 theo A5.

## Sai số một phía và containment
`floor(n/d)` là lower, `ceil(n/d)` là upper, d>0, kể cả n âm. Motion x/v
monotone theo x/v/a trên miền braking+stop-clipping. B2 truyền đủ8 corner,
lower floor / upper ceil: ACCEPT ⇒ tập reachability nằm trong tube x±.16,v±.20.
Nominal mới phải có signed apply−ego.t trong[0,100000]; delay âm reject,
không clamp về0. Backup đã commit được kiểm riêng bằng original-time phase.
Sai số input quantization thuộc adapter, không được nhầm với theorem cho encoded input.

B4 tích phân chính xác capped linear jerk bằng numerator/denominator nguyên;
mỗi bước lưu interval x/v outward. Root stop được bracket tới1 μs; dx upper
cộng ceil(v0/T) LSB, lower dùng vị trí tại bracket trái. Tối đa128 bước:
error v≤128 LSB, error x≤128·(1+12.8)+11<1778 LSB, vẫn <2mm.
Các interval tích lũy thực tế được dump đầy đủ, không bỏ sai số sau mỗi bước.

B3 dùng exact quadratic minimum (endpoint, stop, relative stationary point) và
`floor(d_front)−ceil(d_ego)`. Với jerk liên tục, quanh acceleration midpoint,
|a(u)−a(h/2)|≤J|u−h/2|+1 LSB, nên sai số vị trí ≤Jh³/8+h²/(2T²) LSB.
Inflate hai phía bởi ceil cận đó, ngoài interval x/v của B4. Split thêm tại
actor event; không dùng endpoint-only test. Vì vậy ACCEPT ⇒ gap liên tục≥reserve.
Footprint dùng combined longitudinal length, half-width+.05m tracking envelope
phải ở trong làn cả horizon; yaw/lateral motion không thuộc A1. Trên32 vật ⇒UNKNOWN.
Mọi row/config/object phải là Python int; row x ngoài±10070m hoặc endpoint sai
type/range reject trước primitive, kể cả endpoint cuối. Actor speed preflight
v0+ceil(max(0,a,after_a)·H/T)≤20S chứng minh true v(t)≤20S; vì vậy intersect
upper velocity với20S sau mỗi cell là sound, tránh ceil tích lũy gây overflow giả.

B7 chỉ chọn finite-jerk ACCEPT theo decel/jerk/id; id15 chỉ MITIGATION. B8
good/lost saturate tường minh, không overflow counter thành healthy. B9 bind toàn
snapshot/plan/version/apply/expiry, kiểm lại khi executor nhận và trước ACK commit.
SHA/CRC là mô hình binding/integrity, không tuyên bố chống đối thủ có khả năng reseal.
V2 là kiểm thử finite-bit trên contract này, không thay thế proof toàn hệ thống vật lý.

Context seal bổ sung hash toàn world objects và lane bounds (frame/unit version1).
`stop=-1` là invalid marker; với phase đầu≤12.8s và horizon≤12.8s,
row.phase/stop tuyệt đối tương đối original apply≤25.6s, vẫn nằm trong s32.
Trong explicit-world mode, kiểm bridge delay trước, sau đó propagate front objects
bằng lower x/v, rear objects bằng upper x/v; bridge separation cấm đổi thứ tự
trước apply. Certificate tail được kiểm ở plan.x/v tại apply, không ở ego cũ.
Canonical list order là một phần hash; thay thứ tự cũng cần certificate mới.
S1b ABI: CRC32 uses Plan560 + three u32 IDs + schema32 (86 bytes), big endian,
two's complement. Zero-pad every outer record at its LSB end to whole bytes;
nested fields have no internal padding. SHA snapshot=Ego256; trajectory=Plan560;
context=World8200 + lane lo64/hi64 + frame32=1 + units32=1 (1049 bytes), unused
object slots zero. Seal hashes Certificate body without present/seal (960 bits),
with raw256-bit embedded hashes. Algorithms remain CRC-32 IEEE and SHA-256.
Legacy JSON helpers have *_json_legacy names and are unused by decisions.
Typed binary diagnostic fixture hashes never enter hardware decisions.
Invalid fixtures may be masked by packing; original parse/numeric guards reject
before admission, so narrowing never legitimizes invalid input.
Arithmetic: s96 integer-time disp; s128 rational swept; s160 capped ramp.
B4 xn<2^154, xd<2^132, vn<2^111 (old2^104 bound corrected), vd<2^87.
See spec5.5.1 for per-term proofs. Python checked(...,256) remains a conservative
overflow guard, not an RTL datapath requirement.
`b4_mrmgen.phase` là bội100ms; phase ngoài grid reject. `phase_state` replay nguyên
epoch tại thời gian thực. Với n≤640 bước20ms, v floor error≤n LSB; x floor error
≤n+ceil(.02·n(n−1)/2)+11≤4741 LSB, gồm một clipped stop. Reuse cộng max(640,cận x)
vào x và640 LSB vào v. Lease config1≤.5s và apply≥generated làm phase P5<.5s,
n≤25, nên guard thông thường vẫn640 LSB. Nominal mới apply<now phải reject;
backup dùng phase_reuse và kiểm epoch gốc. Ego timestamp phải trong [now−.15s,now].
Tại supervisor, live ego estimate phải đã được estimator ngoài RTL project về
decision epoch `ego.t==now`; đây không phải timestamp raw sensor. Mismatch hoặc
clock rollback ⇒ L3/heartbeat false, bỏ backup trước hash/geometry, không dùng
measurement cũ để xuất một MRM mới. B1 standalone vẫn kiểm packet age .15s;
B2 standalone vẫn hỗ trợ dated-measurement reachability tới apply.
Longitudinal tracking allowance .16m nằm trong front reserve .5m; separation vật
lý còn≥.34m khi H3 giữ tube suốt horizon. Không suy ra≥.5m cho xe thực có tracking error.

S1b supersedes the historical s256 bound discussion above with per-operation widths in spec5.5.1.
