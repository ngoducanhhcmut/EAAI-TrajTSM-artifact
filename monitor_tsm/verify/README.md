# G1 tái lập

S1b results and reproduction are in `s1b/REPORT.md`. S1b uses packed binary
CRC/SHA records; the G1 JSON model is preserved as `s1b/model_json_legacy.py`.
New results belong only in `s1b/`; do not rerun the locked G1 stages in place.

Từ workspace journalQ1, dùng Python3.13, không cài package, không network.
`run.py` thêm `tsm2_pilot/vendor` cho flint0.8.0/numpy; decision package độc lập.

```
py -3.13 -B tsmx_hw/verify/register.py
py -3.13 -B tsmx_hw/verify/run.py --stage unit
py -3.13 -B tsmx_hw/verify/run.py --stage freeze
py -3.13 -B tsmx_hw/verify/run.py --stage v2
py -3.13 -B tsmx_hw/verify/run.py --stage v1
py -3.13 -B tsmx_hw/verify/run.py --stage v3
py -3.13 -B tsmx_hw/verify/run.py --stage summarize
```

Registration đã tồn tại thì không được overwrite. Chạy lại rollout resume từng
IC và kiểm checkpoint hash; nếu muốn thực nghiệm mới cần output/registration mới
(sửa OUT trong bản sao, không thay kết quả đã khóa). Một process/worker duy nhất.
Implementation hash freeze trước held-out; unit/smoke là kiểm mã, không tune policy.
Amendments giữ hash trước/sau: cache API của adapter (AST hàm/lớp không đổi),
và guard B2 reject NEW packet có apply trong quá khứ. Guard chỉ thu nhỏ tập
ACCEPT; `past_apply_amendment.json` chứng minh mọi input của matrix đã đăng ký
không đổi nhánh. V1 đang chạy dùng module cũ trong RAM; V3 và unit cuối dùng
revision mới. Không đổi threshold, seed, sampling hoặc fit theo score held-out.
`time_contract_amendment.json` bổ sung ego freshness, apply>=now cho nominal,
lease config1 tối đa.5s (từ P5), và cận tích lũy x replay dài≤4741 LSB. Các
lease/callback P5 giữ nguyên nhánh và guard640; B2/B3/B4/B7 V2 không đổi số học.
`live_ego_amendment.json` thêm fail-closed ở composition cho live estimate không
đúng decision epoch/clock rollback; tất cả P5 inputs thỏa epoch hiện tại nên
không đổi matrix. Các fault WORLD/ego này được kiểm riêng bằng directed vectors.
`pure_cache_amendment.json` là tối ưu adapter để giữ budget6h: cache certificate
giữ field names/type/signed zero; cache geometry dùng immutable integer Plan.
`pure_cache_validation.json` kiểm85 scalar cases và replay1 IC đủ110 cặp, SHA
toàn bộ rows khớp trước tối ưu. Không đổi golden, arithmetic hoặc collision score;
7 IC V3 cũ được giữ, resume phần còn lại, replay không tính là mẫu thống kê mới.
`b3_input_amendment.json` và `b3_upper_clip_amendment.json` đóng cận row/type và
intersect upper velocity với physical20m/s đã được preflight chứng minh. Guards
đều identity trên B4 traces/P5; clip identity trên actors a≤0 của V2/P5. Các ca
positive fractional acceleration và max s64 được đăng ký directed trước khi chạy.

V1: shadow golden có state/backup riêng trên mỗi input của rollout reference d2.
Mode là mode tại decide (trước queue/commit), candidate được so trên mỗi cycle,
packet acceptance được so độc lập; union count không double count nhiều loại.
Không lấy kết quả float geometry làm gate của shadow golden. Đây là so policy
trên common inputs; V3 mới kiểm feedback sau khi thay controller decision.

V3: monkeypatch scoped tại runtime cho run, không sửa nguồn. Followers/dynamics,
injection, command queue, ACK/drop/expiry, .02s physical integration giữ nguyên.
Adapter chỉ chuyển float↔encoded int, xác minh seal ngoài bằng canonical format
gốc, rồi dùng B1/B2/B3/B4/B7/B8/B9 của golden. Module-local seal_tail được đổi
cùng selector. Safety path golden không gọi float checker hoặc float selector.
Physical actuator abstraction của harness vẫn là sample-hold d2; B4 golden là
continuous ramp có envelope, nên không suy từ V3 thành proof của actuator thật.

V2: đủ10^6 independent generated inputs, chia đều B2/B3/B4/B7, bao gồm max actor,
overflow, gap≈0/.5m, v≈0, x tại biên, timestamp wrap. B3 oracle kiểm analytic
continuous minimum bằng Fraction; B4 oracle tích phân ramp liên tục độc lập,
isolate stop45 lần rational bisection. B7 kiểm contract ACCEPT của candidate
đã qua B3, không coi bit đầu vào tùy ý là chứng nhận vật lý. B2 mọi8 corner.
Counterexample log tối đa100 ví dụ nhưng counter tổng không bị cap.

Unit results có case định hướng từng block. Vector hex là canonical fixture
ports; JSON định nghĩa width/signedness/LSB/digest, `golden/vectors.py:evaluate`
giải fixture thành I/O đầy đủ của block, gồm trajectory rows cho B4/B3. System
vector cần giữ state giữa dòng. Unit RTL sau này nên bổ sung raw full-port dumps
cho cấu hình interface đã chốt ở S1; fixture không tự định nghĩa cổng RTL.
