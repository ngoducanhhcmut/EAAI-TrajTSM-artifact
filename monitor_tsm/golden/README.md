# Golden TSM-X — A1–A7

Package: `golden/tsmx_golden`, entry API `tsmx_cycle(state, inputs)` và các hàm
`b1_ingress`, `b2_splice`, `b3_geom`, `b4_mrmgen`, `b7_select`, `b8_fsm`,
`b9_cert`, `b10_rec`, `b13_health`. I/O immutable dataclass/tuple/dict; không I/O
file, random hoặc mutation ẩn trong decision functions. `select` có memoization
giới hạn4096 entries; cache chỉ tăng tốc cùng kết quả, không làm state decision.

```python
import sys
sys.path.insert(0, 'tsmx_hw/golden')
from tsmx_golden import model as g
ego = g.Ego(t=0, x=0, v=6*g.S, a=0, lx=40*g.S, lv=0)
plan = g.Plan(1, ego, 0, g.DT, 600000, ego.v, 0)
world = (g.Motion(40*g.S, 0), g.Motion(60*g.S, 0))
cert = g.certify(plan, 500000, world)
state, out = g.tsmx_cycle(g.Supervisor(), dict(
    now=0, ego=ego, pkt=g.packet(plan), cert=cert, objects=world))
assert out['accept'] and state.pending
```

`objects` là world đầy đủ tại ego.t, tối đa32 vật, không phải danh sách bổ sung
cho lead trong Ego. Không truyền `objects` ⇒ adapter một lead P5bd2; `lead` chọn
stationary/braking và event .5s. Truyền `lane` phải dùng cùng lane khi certify.
Certificate context hash bind toàn objects/lane/frame/units; các phiên bản
capability/config/controller nằm trong seal. Commit tái kiểm nguyên snapshot,
plan và expiry trước ACK. Actual actuator ACK/delivery là cổng ngoài A4.
Ở composition, lane bounds đã ở frame ngang ego-centered (reference y=0);
map bounds tuyệt đối phải trừ lateral ego position trước khi certify. B3 riêng
vẫn có cổng y. Như vậy offset ngang được kiểm bằng lane bounds, không bị bỏ qua.

MRM current backup giữ nguyên apply epoch; không refresh timestamp. Nominal chỉ
được phát khi tail hữu hạn-jerk kiểm ở tọa độ t_apply (đã truyền world qua delay),
và bridge không va chạm trong explicit-world mode. B2 corner set thuộc tracking
tube; reserve .5m bao gồm .16m longitudinal tracking allowance, còn≥.34m tách rời.
Không tuyên bố bảo đảm phía sau khi chỉ có nhãn CERT-FRONT/REAR-COND.

Time phases cho `b4_mrmgen` phải ở grid100ms; phase ngoài grid bị reject, không
restart ramp. `phase_state` kiểm backup tại thời gian thực bằng tích phân20ms
và phần bước cuối, từ epoch gốc. B4 horizon tới stop+hold2s, không cắt ở6s/30m.
Theo FORMATS, toàn thư viện cần cận7.6s và30.917m ở10m/s.

Các hàm số học `advance`, `disp`, `swept`, `continuous_advance` là primitive có
precondition fixed-width/range. Public ingress reject dữ liệu không hợp lệ;
primitive raises ValueError khi vi phạm guard. `b3_geom` ACCEPT có nghĩa geometry
trên occupancy arcs/jerk bounds được cung cấp, không chứng minh tính khả thi của
trajectory tùy ý; khả thi/stop do B4 cung cấp, splice do B2 cung cấp.

`outputs.candidate` là kết quả B7 của fallback hiện tại, không thay arbitration:
L0/RECOVERY dùng nominal đã accept và tail trong pending; L1 dùng backup nguyên
epoch; L2 dùng candidate; L3 bắt buộc brake8/instant id15; HOLD dùng parking hold.
Không sử dụng candidate của selector để giảm mức brake khi mode là L3.
`outputs.label` cũng là label của kết quả B7, không phải quyền commit command;
arbitration L3 luôn là MITIGATION. Live ego input phải là estimate tại `now`,
không phải raw measurement cũ. Mismatch/clock rollback đi thẳng L3, không dùng
snapshot đó để tạo fallback; việc project raw sensor thuộc estimator ngoài RTL.

`tsmx_cycle` là transaction tại decision epoch100ms, không phải một clock RTL.
Timer B9 phải được gọi riêng ở subcycle tại ACK deadline40ms/apply/expiry, và
chuyển override ngay theo kết quả; chỉ polling `tsmx_cycle` mỗi100ms không đủ
chứng minh FTTI .285s. Wrapper V3 gọi commit mỗi20ms như d2; unit B9 kiểm đúng
biên40ms. ACK bool của wrapper là pulse đã gắn đúng pending transaction của
simulator; giao diện có ACK ID phải truyền `expected_seq` cho `b9_cert`.
Jerk bound của A2 áp dụng trước standstill clamp; khi v=0 chuyển sang hold theo
mô hình P5, không tuyên bố bound jerk actuator tại chuyển mode parking brake.

Vector CLI (từ thư mục tsmx_hw):
```
py -3.13 -B golden/vectors.py --block b3 --n 5000 --out vectors/b3.hex
```
Mẫu128/block được dump kèm JSON field widths; `vectors/expand.py` xuất thêm
`.ports.jsonl` là đầy đủ semantic I/O, cùng case với hex. Mapping cổng RTL cụ thể
được chốt ở S1. System vectors phải replay state theo dòng, kể cả ACK timeout.
