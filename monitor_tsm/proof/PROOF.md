# W3: chứng minh đúng đắn hữu hạn bit của TSM-X (cập nhật 05/11/2026)

## Định lý mục tiêu (B3 cộng B4)
Với mọi đầu vào trong miền `FORMATS.md`, nếu `b3_geom(b4_mrmgen(x, v, a, cid), objects, lane)` trả ACCEPT, thì
trong suốt horizon (tới dừng và giữ 2 s), khoảng hở dọc **liên tục theo thời gian** giữa ego (bám profile phanh cid,
sai lệch jerk ≤ J, lệch 1 LSB gia tốc) và mỗi vật (gia tốc hằng từng đoạn, có điểm đổi `event`, dừng bị chặn tại 0)
luôn ≥ `reserve`.

Giả định ngoài (không chứng minh, phải nêu trong bài):
- Vật tuân mô hình gia tốc hằng từng đoạn.
- Ego bám quỹ đạo trong sai số đã khai báo (lateral_error, tube).
- Phạm vi 1D, làn thẳng.

## Cấu trúc chứng minh
1. **Bổ đề hàng (B3, máy kiểm bằng Z3):** `proof/b3_lemmas.py`, 12/12 PROVEN, cộng 5 đối chứng âm đều REFUTED, cộng kiểm không rỗng.

   | Bổ đề | Nội dung | Dùng ở |
   |---|---|---|
   | L1, L2 | vật phía trước: độ dời ≥ đường la·u/w (dây cung lõm khi a < 0, tiếp tuyến khi a ≥ 0) | `swept_lb` |
   | L3, L4 | vật phía sau: độ dời ≤ ub·u/w (tiếp tuyến khi a ≤ 0 kể cả dừng; dây cung lồi khi a > 0) | `swept_lb` |
   | L5a, L5b, L6 | `disp_ub` ≥ s(h) ≥ `disp_lb` (cả nhánh đã dừng) | `advance_lb` |
   | L7 | độ dời đơn điệu theo vận tốc đầu (lý do dùng vl cho cận dưới, vh cho cận trên) | trạng thái khoảng |
   | L8a, L8b | cận vận tốc sau h | `advance_lb` |
   | L9 | bao tuyến tính đạt cực tiểu ở hai đầu mút | giá trị trả về `swept_lb` |
   | L10 | `inflate` phủ sai lệch do jerk so với quadratic điểm giữa trên toàn [0, h] | `b3_geom` dòng 480–482 |

   Mọi bổ đề phát biểu trên **số thực** trong miền ODD. Đây là phát biểu mạnh hơn bản số nguyên, vì floor/ceil
   chỉ được mô hình bằng q ≤ x ≤ c.
2. **Ghép (chứng minh bằng tay, quy nạp theo hàng và theo đoạn event):**
   - Trạng thái khoảng [ol, oh] × [ovl, ovh] luôn chứa trạng thái thật (L5–L8).
   - Quadratic điểm giữa đánh giá từng đoạn với làm tròn hướng ra luôn ≥ quadratic liên tục (L5, L7, L8b).
     Sai lệch thật so với quadratic đó ≤ inflate (L10), cộng một lần ở đầu hàng.
   - Do đó khoảng hở thật ≥ g ≥ reserve tại mọi u (L1–L4, L9).
3. **Còn phải làm:**
   - [x] B4 (`proof/b4_lemmas.py`, 8 PROVEN + 4 đối chứng âm REFUTED, 05/11):
     - B4-1/2: `ramp_integrals` = tích phân đúng của ramp có chặn.
     - B4-3: một điểm cắt duy nhất (ramp luôn hướng về đích ≤ 0), nên tìm nhị phân đúng.
     - B4-4a/c: cận dưới lúc dừng.
     - B4-4b1–3: |v| < 10 µm/s trong 1 µs quanh điểm dừng. Bước tích phân (bằng tay): x(τ) − x(lo) ≤ 1e-5 µm ≤ ceil(v/T) = 1 µm, vì nhánh trên chỉ vào nhánh dừng khi vh ≥ 1 LSB.
     - Lần đầu 3 bổ đề bị bác do phát biểu thiếu ràng buộc cấu trúc (hướng ramp; nhánh trên có v ≥ 1). Ghi lại trong bài như ví dụ về giả định ẩn.
   - [x] Ghép B4 → B3 (`proof/coupling_lemmas.py`, 3 PROVEN + 1 đối chứng âm REFUTED): gia tốc B4 tích phân lệch so với `cmd` điểm giữa ≤ |sgn|·|r − h/2|/T + 1 LSB (C1, C1b). Đây đúng là giả thiết của L10. C2: jerk trong hàng ≤ bound. Hàng tiền tố (t < DT) và profile instant có start = cmd nên hiển nhiên.
   - [x] B2 splice, `propagated_objects`, `reaction_safe`, B7 (05/11).
     - B2: hộp sai số 8 góc (x ± 5 cm, v ± 5 cm/s, a ± 0,1 m/s²) phủ mọi trạng thái thật, vì vị trí và vận tốc sau delay đơn điệu theo x (hiển nhiên), theo v (L7, L12) và theo a (**L11, L12 mới**, `b3_lemmas.py` nay 14 PROVEN + 6 đối chứng REFUTED).
     - `propagated_objects`: vật phía trước dùng cận dưới, vật phía sau dùng cận trên. Đúng hướng bảo thủ theo L7/L11; `advance` lấy floor/ceil của giá trị chính xác.
     - `reaction_safe` dùng `swept()` chính xác. Trên mỗi đoạn không có điểm dừng, khoảng hở là bậc hai, nên cực tiểu nằm ở hai đầu mút hoặc ở đỉnh. Hàm liệt kê đủ các điểm đó (đầu mút, thời điểm dừng, đỉnh tương đối), làm tròn floor cho vật trước và ceil cho vật sau. Đây là lập luận giải tích chuẩn, viết bằng tay.
     - B7 chỉ chọn thứ tự (êm nhất) trong các ứng viên đã ACCEPT, nên không ảnh hưởng an toàn.
   - [x] Khối số học dùng chung `rtl/arith` (05/11). Guard đầu vào và kiểm đầu ra đều sinh fault, nên là fail-safe. Các điểm cắt **không kiểm** (MUL/ADD/SUB mod 2^160, TRZ/TRS 88–128 bit, bộ chia che theo lớp 96/128/160) được kiểm như sau:
     - `proof/rtl_ranges.py`: đọc vi chương trình trực tiếp từ RTL, chạy số học khoảng từ guard. Ở dải dùng thật (h ≤ 0,1 s) không có phép nhân hay bộ chia nào tràn. **T11 (tử số vận tốc) dùng 99,99% giới hạn TRS112**: vẫn đúng nhưng biên rất mỏng, nên ghi trong bài.
     - `proof/rtl_paths.py` (Z3): 4 cảnh báo TRZ trên tử số âm là báo động giả. Giá trị âm chỉ có ở nhánh đã dừng, và DSEL ghi đè ở đó (3 PROVEN, có đối chứng).
     - **PHÁT HIỆN F-W3-1:** guard op 7 cho h ≤ 12,8 s, nhưng với h > 0,1 s phép nhân tràn 2^160 thật. Không đến được: `mrmgen` truyền hằng 100000, `math` truyền ≤ 20000. Đề xuất siết guard op 7 xuống h ≤ 100000 (1 dòng) ở lần sửa RTL tới.
   - [x] Khối B3 `rtl/geom/m_tsmx_geom_su.sv` v0.6 (`proof/geom_div.py`, Z3 số nguyên tuyến tính, 05/11). Cả 5 phép chia hằng (lin, velq, disp, disp khi đã dừng, infl) cho **đúng floor/ceil với MỌI tử số trong dải**. Đã kiểm cả điều kiện phụ N' < 2^s và q0 < 2^22. Đối chứng âm: bớt 1 bit hiệu chỉnh thì sai ở 3/3 trường hợp áp dụng được.
     - Độ rộng tích (theo START guard): P = v·w < 2^41; PT = 2e6·P < 2^62; A2 = |a|·w² < 2^57; PT + A2 + (2e12 − 1) < 2^62; JW = j·w³ < 2^82 (j < 2^32). Đều khớp trường bit trong RTL.
   - [ ] Liên kết RTL ↔ golden: bằng chứng hiện có là mô phỏng khớp bit (hồi quy 300 + 360 + worst). Có thể bổ sung kiểm tương đương hình thức cho khối số học (SymbiYosys), nếu kịp.
   - [x] **Bộ chuyển vật vận tốc âm VA** (`proof/adapter_lemmas.py`, Z3, 3 PROVEN + 2 đối chứng REFUTED, 05/11). Dùng ở W7 (nuScenes) và W8 (nuPlan). Golden chỉ nhận vật có 0 ≤ v ≤ 20 m/s. Vật có v < 0 được thay như sau:
     - Vật phía trước: thay bằng vật đứng yên phủ toàn bộ đoạn quét trên [0, L+H], với w = ⌈|v|(L+H)⌉, tâm x − w2, nửa dài + w2, w2 = ⌈w/2⌉.
     - Vật phía sau: chỉ đặt v := 0.

     Các bổ đề, với mọi độ trễ L ∈ [0; 0,5 s] và H ≤ 12,8 s:
     - A1: vị trí thật luôn nằm trong đoạn phủ.
     - A2: khoảng hở mô hình đạt thì khoảng hở thật đạt.
     - A3: vật phía sau chỉ lùi xa thêm.
     - N1: bản "chỉ dời tâm" (lần chạy VA đầu, 74 FA trên nuScenes) là **không đúng đắn**, Z3 tìm được phản ví dụ. Giữ lại làm đối chứng hồi quy.
     - N2: phủ mà bỏ quên L cũng sai.

     Kết luận: định lý mục tiêu mở rộng sang vật đi ngược chiều với vận tốc hằng, không phải sửa RTL. Bộ chuyển là tiền xử lý phía host, tuyến tính theo số vật.
   - [x] **Deadline (watchdog) trên RTL** (`proof/watchdog/`, SymbiYosys k-induction, Yices; 05/11). Dùng engine RTL nguyên bản. Cả 12 khối con được thay bằng stub có đầu ra tự do mỗi chu kỳ (`gen.py`), kể cả CSR reset. Chỉ thay `f_mod20k` bằng phép `%` tương đương, vì Yosys không đọc được ROM.
     - Thuộc tính W1–W9 (`props.svh`) đều PASS ở độ sâu 6, mất khoảng 28 phút.
     - Hai lần thất bại trước đều do CTI không đạt tới được: W2 thiếu các trạng thái TLOG/BIST; W5 cần thêm W9.
     - Hệ quả: mọi request được nhận đều có phản hồi trong ≤ 1.874.999 chu kỳ. Nếu quá hạn thì REJECT, lý do 7, và brake được giữ.
     - Giả định A6: reset một lần, clock liên tục.
     - Kiểm cover (`run_checks.sh`): C1 (active) đạt ở bước 4, C2 (kết thúc active kèm phản hồi) đạt ở bước 14.
     - Đối chứng âm: W1 với giới hạn nhỏ hơn 1 chu kỳ không chứng minh được (induction fail đúng ở W1).
