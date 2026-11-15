# Báo cáo phân tích kiến trúc HMAO từ RTL thực tế

## 1. Mục đích báo cáo

Báo cáo này tổng hợp phân tích kiến trúc phần cứng của khối HMAO dựa trên mã nguồn RTL thực tế trong workspace, bao gồm các module cốt lõi, luồng dữ liệu, tín hiệu điều khiển, cơ chế fault handling và các điểm kỹ thuật quan trọng để phục vụ nghiên cứu, thảo luận và trình bày slide.

---

## 2. Tổng quan hệ thống

HMAO là một accelerator phần cứng dùng để kiểm tra tính an toàn của trajectory trước khi quyết định cho phép hoặc chặn hành vi điều khiển. Kiến trúc được thiết kế theo hướng fail-safe, có nghĩa là khi gặp lỗi hoặc không đủ bằng chứng an toàn, hệ thống mặc định chọn quyết định VETO.

### Mục tiêu chức năng
- Nhận trajectory đầu vào từ bộ nhớ hoặc buffer.
- Kiểm tra tính hợp lệ và an toàn của trajectory.
- Tạo vùng reachable của xe bằng zonotope.
- Phân tích khả năng va chạm bằng collision SAT.
- Tạo quyết định GRANT hoặc VETO.
- Báo lỗi và fault đến hệ thống an toàn cao hơn.

### Đặc điểm kiến trúc chính
- Pipeline điều khiển phân tầng.
- Luồng xử lý có thể phân nhánh Stage 1 / Stage 2.
- Default an toàn là VETO.
- Có cơ chế watchdog, SMPU, fault aggregation và sticky fault register.
- Dùng định dạng Q8.8 cho nhiều đại lượng số học quan trọng.

---

## 3. Kiến trúc tầng cao

### 3.1 Các khối chức năng chính

1. Pre-processing unit
   - Đọc trajectory từ bộ nhớ.
   - Kiểm tra CRC.
   - Kiểm tra kinematic.
   - Kiểm tra format/NaN/Inf.
   - Tính bounding box.

2. Adaptive margin controller
   - Sinh các khoảng an toàn dựa trên chất lượng cảm biến.
   - Tạo lateral, longitudinal và time margin.

3. Zonotope generator
   - Tạo vùng reachable state của xe.
   - Chia thành Stage 1 và Stage 2.

4. ADMM solver
   - Thực hiện kiểm tra tính khả thi và tiềm năng vi phạm.
   - Chạy song song với Stage 1.

5. Collision SAT checker
   - Phân tích va chạm giữa zonotope và obstacle bằng cách dùng separating axis test.

6. FSM controller
   - Điều phối toàn bộ quá trình.
   - Chuyển đổi giữa các trạng thái xử lý, kiểm tra và đầu ra.

7. Safety support blocks
   - Watchdog.
   - SMPU.
   - Fault manager.
   - CDC / parity.

---

## 4. Phân tích module theo module

### 4.1 Module hmao_engine_top

#### Vai trò
Đây là module điều phối trung tâm của HMAO. Nó kết nối toàn bộ sub-module và tạo ra các tín hiệu đầu ra cho hệ thống bên ngoài.

#### Chức năng chính
- Nhận tín hiệu start từ RISCV hoặc testbench.
- Khởi tạo các pipeline con: preproc, zonotope, ADMM, SAT.
- Thu thập fault từ các module con.
- Tạo tín hiệu đầu ra: decision, status, latency, fault.
- Gắn sticky latch cho một số tín hiệu để FSM vẫn có thể đọc được sau khi stage đã chạy xong.

#### Tín hiệu nội bộ quan trọng
- start_preproc
- start_s1
- start_s2
- start_admm
- output_grant
- output_veto
- s1_no_collision_latch
- s1_potential_latch
- admm_done_latch
- admm_diverged_latch

#### Điểm kỹ thuật đáng chú ý
- Hệ thống dùng chế độ timeout cố định để đảm bảo latency gần như không đổi cho path bình thường.
- HMAO_COMPLETE được phát theo logic cố định thay vì chỉ khi công việc kết thúc ngay lập tức.
- Tín hiệu decision mặc định là VETO, phù hợp nguyên tắc fail-safe.

#### Kết luận
Module này là bộ não điều phối của HMAO, kết nối các khối tính toán và các khối bảo vệ an toàn.

---

### 4.2 Module hmao_fsm

#### Vai trò
FSM điều khiển luồng công việc của toàn bộ hệ thống.

#### Các trạng thái chính
- FSM_IDLE
- FSM_STAGE1_COMP
- FSM_STAGE1_CHECK
- FSM_STAGE2_COMP
- FSM_STAGE2_CHECK
- FSM_OUTPUT_GRANT
- FSM_OUTPUT_VETO
- FSM_ERROR

#### Logic điều khiển
- Nếu nhận start và preproc chưa xong, FSM kích hoạt preproc.
- Nếu preproc xuất hiện lỗi, FSM kết thúc bằng VETO.
- Nếu Stage 1 không có collision và ADMM không diverge, FSM đi đến GRANT nhanh.
- Nếu Stage 1 cho thấy potential collision, FSM kích hoạt Stage 2.
- Nếu Stage 2 không collision, FSM cho GRANT.
- Nếu Stage 2 phát hiện collision, FSM cho VETO.
- Nếu watchdog hoặc numerical error xảy ra, FSM chuyển sang ERROR và VETO.

#### Cơ chế bảo vệ
- Hai bản trạng thái được duy trì song song: state_reg_a và state_reg_b.
- Nếu hai bản này không đồng bộ, FSM sẽ ép vào ERROR.
- Mã trạng thái dùng Hamming-3, tăng khả năng phát hiện lỗi bit flip.

#### Kết luận
FSM là phần quyết định chính của hệ thống và là lớp bảo vệ quan trọng nhất trong luồng điều khiển.

---

### 4.3 Module hmao_preproc

#### Vai trò
Tiền xử lý dữ liệu trajectory trước khi đưa vào pipeline chính.

#### Các giai đoạn xử lý
1. Fetch trajectory từ bộ nhớ
2. Tính CRC32
3. Kiểm tra kinematic feasibility
4. Kiểm tra format và NaN/Inf
5. Tính bounding box
6. Xuất kết quả cho các stage tiếp theo

#### Tín hiệu đầu ra
- valid_out
- error_out
- waypoints_out
- bbox_xmin_out / bbox_xmax_out
- bbox_ymin_out / bbox_ymax_out
- crc_fail
- kinematic_fail
- fmt_fail_out

#### Điểm kỹ thuật quan trọng
- Preproc có latency cố định để đảm bảo deterministic timing.
- CRC32 được xử lý bằng pipeline để giảm overhead.
- Các lỗi format và NaN được phát hiện trước khi công việc tiếp tục.
- Bounding box được tính theo giá trị Q8.8, phù hợp với các module sau này.

#### Kết luận
Preproc là bộ lọc đầu vào và là lớp bảo vệ bảo đảm dữ liệu đầu vào có chất lượng đủ tốt để đi tiếp.

---

### 4.4 Module hmao_adaptive_margin

#### Vai trò
Sinh khoảng an toàn cho các margin dựa vào mức độ tin cậy của cảm biến.

#### Inputs
- gps_quality
- camera_quality
- road_friction
- actuator_health
- weather_severity

#### Logic hoạt động
- Tính weighted score từ các tín hiệu chất lượng cảm biến.
- Dùng LUT để chuyển thành scale factor.
- Tính margin ở định dạng Q8.8.
- Dùng clamp cứng để giới hạn giá trị trong khoảng hợp lệ.

#### Outputs
- lateral_margin
- long_margin
- time_margin

#### Điểm đáng chú ý
- Module này là combinational, không có latency pipeline.
- Các clamp là hardwired, không thể bị bypass bằng phần mềm.

#### Kết luận
Đây là lớp điều chỉnh độ bảo toàn dựa vào độ tin cậy môi trường và cảm biến.

---

### 4.5 Module hmao_zonotope_gen

#### Vai trò
Sinh zonotope đại diện cho vùng reachable của xe theo thời gian.

#### Cấu trúc
- Stage 1 dùng 16 generators và 50 time steps.
- Stage 2 dùng 32 generators và 100 time steps.
- Sử dụng CORDIC để tính sin/cos của heading.
- Sử dụng MAC để lan truyền center và generators.

#### Output
- zonotopes_out
- valid_out
- overflow_err
- zonotope_err

#### Điểm kỹ thuật đáng chú ý
- Hệ thống dùng fixed-point Q8.8 cho các giá trị vị trí và góc.
- Có các sửa lỗi về chuyển đổi float32 sang Q8.8.
- Có pipeline và chiến lược chia timing để dễ synthesize ở tần số 400MHz.

#### Kết luận
Đây là module tạo vùng an toàn đại số cho việc đánh giá va chạm tiềm năng.

---

### 4.6 Module hmao_admm_solver

#### Vai trò
Thực hiện kiểm tra khả thi an toàn bằng giải pháp ADMM unrolled pipeline.

#### Cấu trúc
- 15-stage pipeline.
- Không dùng vòng lặp thực tế, toàn bộ dữ liệu đi thẳng qua các stage.
- Dùng một cấu trúc dữ liệu flat array để tránh vấn đề compiler đối với array lồng nhau.

#### Outputs
- collision_possible
- done
- diverged
- admm_diverge_fault

#### Điểm đáng chú ý
- Đây là một phiên bản đơn giản hóa của ADMM, phù hợp với mục tiêu accelerator hardware.
- Thay vì tối ưu toàn bộ, module kiểm tra xu hướng vi phạm và divergence.

#### Kết luận
ADMM solver là lớp phân tích khả thi song song với zonotope generation.

---

### 4.7 Module hmao_collision_sat

#### Vai trò
Thực hiện collision check dựa trên geometry và zonotope.

#### Cách làm việc
- Nhận zonotope đầu vào.
- Đọc obstacle từ world model qua AXI.
- Dùng bounding box prefilter để loại bỏ obstacle không liên quan.
- Dùng separating axis test để đánh giá xem obstacle có làm trajectory bị va chạm hay không.

#### Outputs
- no_collision
- potential_coll
- suspicious_ids
- violation_info
- overflow_err

#### Điểm kỹ thuật đáng chú ý
- Module có pipeline 3-stage để tăng tốc và chia tải cho DSP.
- RTL đã sửa các lỗi liên quan đến dấu số và việc so sánh absolute magnitude.
- Hệ thống phát hiện suspicious obstacle và lưu lại danh sách nghi ngờ.

#### Kết luận
Đây là module chính để xác nhận xem trajectory có an toàn trước các vật cản hay không.

---

### 4.8 Module hmao_axi_arbiter

#### Vai trò
Quản lý việc chia sẻ bus AXI read-only giữa nhiều master requesters.

#### Các requester
- Preproc
- SAT Stage 1
- SAT Stage 2
- ADMM solver

#### Chính sách ưu tiên
1. Preproc
2. SAT1
3. SAT2
4. ADMM

#### Điểm đáng chú ý
- Priority là fixed, deterministic, không dùng round-robin.
- Dễ kiểm soát latency và tránh race condition.
- Có logic routing của R-channel theo RID.

#### Kết luận
Arbiter đóng vai trò điều phối memory access và đảm bảo bus không bị tranh chấp không kiểm soát.

---

### 4.9 Module hmao_safety_modules

#### Các submodule chính

1. hmao_watchdog
   - Dùng clock riêng, độc lập với system clock.
   - Có các counter cho Stage 1, Stage 2 và total timeout.
   - Nếu hệ thống treo, watchdog phát timeout và báo fault.

2. hmao_smpu
   - Giới hạn quyền truy cập bộ nhớ đọc/ghi.
   - Chỉ cho phép các vùng nhớ hợp lệ cho HMAO.
   - Chặn write request và báo violation.

3. hmao_fault_manager
   - Gom các fault từ submodule lại với nhau.
   - Xuất tín hiệu fault valid và fault flags.

4. hmao_regfile
   - Chứa các register MMIO cho giao tiếp với RISCV.

5. cdc_async_handshake_parity
   - Chuyển uncertainty vector từ QM domain sang ASIL-D domain.
   - Có parity để tăng tính toàn vẹn dữ liệu.

#### Kết luận
Những module này là nền tảng của lớp bảo vệ an toàn của hệ thống.

---

### 4.10 Module hmao_soc_top

#### Vai trò
Tích hợp HMAO vào toàn bộ SoC.

#### Các khối được tích hợp
- HMAO engine.
- RISCV DCLS.
- SMPU.
- Watchdog.
- CDC.
- Fault interface.

#### Vai trò hệ thống
- Là nơi kết nối HMAO với RISCV và môi trường bên ngoài.
- Cho phép RISCV phát start, đọc decision và nhận interrupt khi HMAO hoàn thành.

#### Kết luận
SoC top-level là lớp tích hợp hệ thống, biến HMAO thành một accelerator hoàn chỉnh trong chip.

---

## 5. Cơ chế dữ liệu và định dạng số

### 5.1 Định dạng Q8.8
Nhiều đại lượng quan trọng trong RTL dùng định dạng Q8.8, ví dụ:
- margin
- position
- speed/heading propagation
- bong bóng an toàn

### 5.2 Vì sao dùng Q8.8
- Dễ synthesize trên FPGA.
- Dễ làm fixed-point arithmetic.
- Phù hợp cho các phép toán geometry và margin.

### 5.3 Ưu điểm
- Tăng độ ổn định khi so sánh và clamp.
- Giảm phụ thuộc vào floating-point hardware.

---

## 6. Cơ chế fault và safety

### 6.1 Fault sources
HMAO có nhiều nguồn fault, bao gồm:
- CRC fail
- kinematic invalid
- numeric overflow
- zonotope error
- ADMM divergence
- watchdog timeout
- memory protection violation

### 6.2 Cách xử lý
- Một số fault gây VETO ngay lập tức.
- Một số fault được ghi vào sticky fault register.
- Fault được giữ lại để CPU có thể đọc sau khi IRQ được acknowledge.

### 6.3 Thiết kế fail-safe
Mặc định là VETO khi:
- reset
- lỗi FSM
- lỗi preproc
- timeout
- collision phát hiện
- fault không rõ nguyên nhân

---

## 7. Điểm mạnh của kiến trúc

- Mô hình phân tầng rõ ràng.
- Có FSM điều phối riêng.
- Có lớp bảo vệ an toàn với watchdog và SMPU.
- Có cách xử lý fault rõ ràng.
- Dùng fixed-point và pipeline, phù hợp triển khai trên FPGA.
- Default VETO phù hợp với requirement fail-safe.

---

## 8. Điểm cần chú ý khi đánh giá thực tế

- Một số module vẫn là phiên bản simplified so với kiến trúc lý thuyết đầy đủ.
- ADMM và collision SAT đang được tối ưu cho mục tiêu hardware accelerator hơn là mô phỏng toán học toàn diện.
- Một số phần có ghi chú bug-fix và cải tiến, cho thấy RTL đang được tinh chỉnh liên tục.
- Các module có thể cần kiểm chứng thêm bằng simulation và formal verification để chắc chắn về tính toàn vẹn.

---

## 9. Kết luận

Kiến trúc HMAO thể hiện một accelerator phần cứng chuyên biệt cho việc kiểm tra an toàn trajectory, với cấu trúc gồm các lớp:
- tiền xử lý,
- tạo margin,
- sinh zonotope,
- phân tích ADMM,
- kiểm tra va chạm,
- và điều khiển quyết định bằng FSM.

Hệ thống không chỉ tập trung vào hiệu suất tính toán mà còn đặc biệt chú trọng an toàn, fault tolerance và deterministic behavior. Đây là một nền tảng phù hợp cho việc phát triển tiếp trong các thiết kế ASIL-D hoặc các hệ thống tự động hóa an toàn cao.
