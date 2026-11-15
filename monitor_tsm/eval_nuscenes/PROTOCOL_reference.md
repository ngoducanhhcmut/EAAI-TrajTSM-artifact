# W7 — Giao thức đăng ký trước

1. **Khung:** mọi keyframe của 850 cảnh trainval có `next` ≥ 6 keyframe (3 s tương lai GT).
2. **Trạng thái ego** từ `ego_pose`:
   - v, a bằng sai phân trung tâm trên keyframe (0,5 s), chiếu lên hướng ego.
   - Ghi rõ là ước lượng.
3. **Lọc ODD.** Đây là giả định của TSM-X: chỉ phanh, 1 làn thẳng, v ≤ 10 m/s, a ∈ [−8, +2] m/s². Khung đạt ODD khi:
   - 0 ≤ v ≤ 10 m/s và a ∈ [−8, 2];
   - quỹ đạo GT 3 s tới lệch ngang so với trục ego ≤ 1,0 m và đổi hướng ≤ 10°.
   - Báo tỷ lệ phủ ODD trên tổng số khung.
4. **Chiếu 1D trong khung ego tại t0** (trục x theo hướng ego):
   - Lấy mọi annotation vehicle.*, human.*, cycle có |y| ≤ 1,8 m + nửa bề rộng vật.
   - Đặt x, v, length theo quy ước của golden: đọc `lead_motion` và `b3_geom` để suy ra mốc đo (bumper); ghi ASSUMPTION.
   - v vật lấy bằng sai phân vị trí instance giữa keyframe; a = 0; event = 0.
   - Tối đa 32 vật gần nhất. Nếu > 32 thì đánh dấu khung là `object_overflow`, không cắt.
5. **Ba loại kế hoạch mỗi khung**, trạng thái áp dụng tại t0 + 0,5 s (x, v, a):
   - **H** = người lái (GT ego pose 0,5 s sau).
   - **T** = Traj W4A8: waypoint đầu tiên; v, a từ sai phân các waypoint.
   - **U** = kế hoạch không an toàn tổng hợp: giữ tốc độ và tăng tốc +2 m/s² về phía vật trước gần nhất. Chỉ tạo khi có vật trước.
6. **Quyết định TSM-X cho mỗi kế hoạch:** dùng đúng các hàm golden.
   - Vật được truyền tới thời điểm áp dụng bằng `propagated_objects`.
   - Gọi `select_world(Ego(apply, x, v, a, 0, 0), objects, lane)`.
   - ACCEPT khi có ứng viên ≠ 15.
   - Ghi cid, margin, lý do, và số hàng.
7. **Nhãn an toàn tham chiếu (oracle), độc lập với TSM-X.**
   - Mô phỏng số thực, bước 1 ms, với vị trí GT tương lai thật của các vật (nội suy giữa keyframe, giữ nguyên sau 3 s).
   - Ego áp dụng kế hoạch rồi phanh êm nhất trong 12 profile hữu hạn jerk.
   - SAFE nếu khoảng hở ≥ 0,5 m suốt tới khi dừng. UNSAFE nếu không có profile nào giữ được.
8. **Chỉ số:**

   | Chỉ số | Định nghĩa |
   |---|---|
   | Tỷ lệ phủ ODD | khung đạt ODD / tổng khung |
   | Tỷ lệ chấp nhận | trên H, T, U |
   | Báo nhầm | oracle SAFE nhưng TSM-X REJECT |
   | Chấp nhận sai (quan trọng nhất) | oracle UNSAFE nhưng TSM-X ACCEPT |
   | Recall | trên U |

   - Bootstrap CI 95% theo cảnh, 2000 lần, seed 20261104.
   - Phân tích theo khoảng tốc độ và số vật.
   - Mọi ca **chấp nhận sai** liệt kê từng khung, kèm lý do. Ví dụ hợp lệ: vật thật tăng tốc vi phạm giả định a = 0. Đây là kết quả phải báo, không được giấu.
9. **Vector cho RTL:** xuất 300 khung đạt ODD đầu tiên (thứ tự cảnh cố định) thành `eval_nuscenes/rtl_cases.jsonl` (đầu vào select_world + kết quả mong đợi). Claude sẽ chạy chúng qua RTL và board.

## ASSUMPTION — chi tiết thực thi, đóng băng trước chạy thử

- Thứ tự scene theo name rồi token; keyframe theo chuỗi next. Mẫu số coverage là toàn bộ khung có ≥6 next; đồng thời báo tổng keyframe và coverage trên tổng đó. Đầu scene thiếu prev: trạng thái không ước lượng trung tâm được, đánh dấu thiếu dữ liệu, vẫn trong mẫu số. Dùng timestamp thật (~0,5 s), không ép dt.
- v=(p_next-p_prev)/(t_next-t_prev); a=2*((p_next-p)/dt_next-(p-p_prev)/dt_prev)/(dt_next+dt_prev), chiếu lên yaw ego. Đây là ước lượng, không phải CAN bus. Heading ODD là max |yaw(t)-yaw(t0)|, lệch ngang max tại 7 pose; nội suy tuyến tính giữa keyframe.
- Golden trừ o.length từ khoảng cách hai tọa độ: chọn x ego và object là tâm, o.length=(4,8 m + annotation.size[1])/2 (combined half-length). Bằng tương đương bumper theo footprint thẳng axis-aligned; pose ego được giả định là tâm. Width=size[0], không xoay bbox theo yaw vật. Lane cố định [-1,8,+1,8] m. Không thêm tracking error vào length.
- Category/instance metadata đọc từ JSON gốc vì lite cache chỉ giữ translation/size/prev/next. Cycle gồm bicycle và motorcycle trong vehicle.*. Vật sắp theo |x| rồi token; overflow giữ TẤT CẢ, golden reject. Vật ngược chiều, >20 m/s, không có sai phân, length ngoài miền: ghi lỗi adapter, reject; không clamp hoặc bỏ vật. Vật thiếu prev dùng sai phân tiến, thiếu next dùng lùi; thiếu cả hai là unknown.
- H: x từ pose +1 keyframe, v/a ước lượng trung tâm tại đó, chiếu trục t0. T: x=w1.x, v=(w2.x-0)/1 s, a=(w2.x-2*w1.x+0)/0,25 s²; không clamp. U: x=0,5*v+0,25; v=v+1; a=2 (tích phân +2 trong 0,5 s). T/H/U ngoài miền golden được reject nhưng oracle vẫn đánh giá nếu v>=0; v<0 là oracle UNKNOWN, báo riêng.
- Oracle dùng cùng tập vật lọc tại t0, tâm và combined half-length; không lọc lại vật khi đi ngang. Theo chuỗi annotation cùng instance đến t0+3 s, nội suy tuyến tính, giữ cuối nếu annotation biến mất sớm (ghi cờ), giữ tại 3 s sau đó. Đây là giả định visibility, không phải GT đầy đủ khi mất track.
- Oracle độc lập: tích phân công thức float của 12 cặp (b=2,4,6,8; j=2,4,8), thứ tự b rồi j, prefix 0,1 s giữ a rồi ramp về -b, stop-clipping; lấy profile SAFE đầu tiên (êm nhất theo thứ tự này). Bước 1 ms, đến dừng, không thêm hold 2 s của golden. Tối đa 60 s cho input ngoài miền; không dừng thì UNKNOWN. Không gọi b4/b3 trong oracle. Khoảng hở = |x_obj-x_ego|-combined half-length, kiểm tra cả trước/sau. Chỉ dùng dữ liệu có sẵn t0 cho T; không truyền GT target.
- W4A8 tái dựng đúng export_weights.py mặc định: checkpoint chỉ đọc tại F:/vla_archive_2026-10-29/eval/archived_weights/qat_full_bert_gru_120ep.pt; calibration 200 scene train, samples_per_scene=1, lane tokens=True, symmetric_acts=True. Không gọi export (tránh ghi payload). Cache model suy ra đặt trong eval_nuscenes, không chép checkpoint. Nếu lỗi load chưa xử lý trong 30 phút, mới AMENDMENT GT+nhiễu.
- Báo nhầm=REJECT&SAFE / SAFE; chấp nhận sai=ACCEPT&UNSAFE / UNSAFE, đồng thời báo số ca / tổng và tỷ lệ trên ACCEPT. Recall U=REJECT&UNSAFE / UNSAFE của U; U có thể thực tế SAFE, không mặc định mọi U là UNSAFE. UNKNOWN loại khỏi mẫu số oracle, vẫn trong accept rate. Bootstrap resample 850 cảnh với replacement, dùng cùng 2000 draw cho mọi chỉ số; draw có mẫu số 0 loại riêng. Nhóm tốc độ [0,2),[2,5),[5,10]; số vật 0,1–4,5–16,17+. Không chỉnh ngưỡng sau số.
- frames.jsonl có cả khung ngoài ODD; vector gồm mọi kế hoạch của mỗi khung trong 300 khung ODD đầu tiên. Ghi margin/số hàng từ candidate được chọn; khi reject ghi diagnostic candidate hữu hạn có margin lớn nhất và toàn bộ diagnostics. Margin của trajectory/range reject không có nghĩa hình học.
- Mọi file mới, bytecode/cache/temp/log trong eval_nuscenes; loader chỉ được dùng khi cache dataset đã tồn tại. Chạy thử --limit 200 vào results/pilot; đầy đủ vào results, tiếp tục theo token, flush từng frame; lô tối đa 20 phút (dưới 40 phút), trạng thái incomplete ghi rõ. Giao thức và mã được hash trong kết quả để phát hiện thay đổi.

## AMENDMENT A1 — 2026-11-04 20:39 +07:00 (trước mọi số đánh giá)

Strict load checkpoint gốc thất bại vì thiếu đúng decoder.wp_proj.weight và decoder.wp_proj.bias; các tensor GRU/output và encoder đều có. Adapter bổ sung hai tensor bằng 0, strict-load lại toàn bộ, tương đương bỏ nhánh cộng waypoint trước vào context GRU (decoder legacy). Không ngẫu nhiên hóa tensor thiếu, không sửa checkpoint, không đổi trọng số đã học, không dùng GT proxy. W4A8 calibration giữ cấu hình exporter. Đây là tương thích kiến trúc suy luận từ schema checkpoint; chưa chứng minh bit-exact với payload v2/board. Nếu còn lỗi sẽ tiếp tục xử lý trong giới hạn 30 phút rồi mới dùng phương án proxy được phép. Pilot lỗi chưa tạo frame nào; manifest pilot được lưu lại trước khi chạy lại mã sửa lỗi.
