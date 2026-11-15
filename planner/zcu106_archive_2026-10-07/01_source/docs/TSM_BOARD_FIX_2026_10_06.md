# Sửa lỗi TSM trên board — 06/10/2026

## Nguyên nhân xác nhận trong mã nguồn

1. `hmao_preproc.sv` từng coi `RVALID=0` là điều kiện để phát yêu cầu mới.
   Sau khi AR được nhận, AXI cho phép slave/interconnect trì hoãn RVALID.
   Vì vậy điều kiện này không thể biểu thị “không còn burst đang chờ”.
   SmartConnect có độ trễ đã làm lộ các yêu cầu lặp mà mô hình bộ nhớ trả ngay không phát hiện.
   Burst lặp làm sai quỹ đạo/CRC, và dữ liệu còn treo có thể ảnh hưởng lượt sau.
2. Watchdog cũ không biết giai đoạn nào đang hoạt động hay chương trình đã hoàn tất.
   Bộ đếm tầng tiếp tục chạy khi chờ ngắt cố định và khi rảnh. 1.800.000 chu kỳ
   watchdog ở 250 MHz là 7,2 ms, trong khi ngắt hoàn tất bình thường ở khoảng 8 ms.
   Xóa ngắt cũng không xóa timeout trong miền clock watchdog. Vì thế lỗi 0x40
   có thể xuất hiện trong cùng lượt chạy và tồn tại sang lượt sau.

Bản sửa chọn đúng làn dữ liệu xử lý một lỗi khác. Nó không tự giải quyết việc phát
lặp yêu cầu hay bộ đếm watchdog chạy sai vòng đời. Ba lỗi độc lập cần cùng được sửa.

## Thay đổi đã thực hiện

- Preproc: `burst_inflight` được đặt khi AR handshake, chỉ xóa khi nhận RLAST;
  chỉ phát burst mới khi không còn burst đang chờ, giới hạn burst 0–7;
  chỉ rời FETCH sau khi nhận CRC ở word 350 và đã nhận hết burst cuối.
- Watchdog: thêm enable cho từng tầng và toàn lượt chạy; chỉ dùng tầng thứ hai
  của bộ đồng bộ CDC để điều khiển bộ đếm. Tầng 1/2 dừng khi hết công việc;
  watchdog tổng vẫn bảo vệ thời gian chờ hoàn tất. Giữ các ngưỡng sản xuất:
  tầng 1 7,2 ms, tầng 2 5,6 ms, tổng 16 ms tại 250 MHz.
- Đệm thời gian tầng 2: mô phỏng sau hai bản sửa trên cho H0261 VETO fault 0x00
  nhưng hoàn tất ở 8,602 ms. Riêng các phần đệm preproc/tầng 1/tầng 2 đã là
  200k + 600k + 800k = 1,6 triệu chu kỳ, vượt bộ đếm hoàn tất 1,5 triệu.
  Giảm đệm tầng 2 từ 8.000 xuống 6.000 chu kỳ mỗi bước (600k tổng);
  phép tính và điều kiện chờ pipeline xoay thoát hết được giữ nguyên.
  Test hệ thống mới bắt buộc ca fault-free hoàn tất trong 7,999–8,010 ms,
  có dung sai clock mô phỏng và chu kỳ CPU polling. Đang chạy lại bản này.
  Mini_val/ca biên dùng `SIM_FAST_PREPROC`, bỏ đệm 200k của preproc:
  tổng đệm cũ còn 1,4 triệu chu kỳ trong các test đó nên chúng không chứng minh
  mốc hoàn tất 1,5 triệu chu kỳ với cấu hình sản xuất. Thanh ghi latency cũng
  ghi hằng 1,5 triệu; cần đo start → complete thực tế, không chỉ đọc thanh ghi.
- Start/ack: clear được kéo dài 16 chu kỳ TSM, đồng bộ sang watchdog;
  cờ cũ được chặn trong thời gian clear đi qua CDC. Không để clear kéo dài
  làm mất việc arm watchdog từ xung start ngắn hơn.
- Output: ack/start xóa decision, complete và fault báo ra CPU; timeout thật
  vẫn đưa kết quả về VETO và báo hoàn tất lỗi. FSM lỗi thật vẫn cần reset.
- Kiểm tra hệ thống: mỗi ca phải có GPIO1 trước start bằng 0, đúng 8 burst đọc hẹp,
  đúng quyết định/fault và không có AXI RRESP lỗi.
- Build: lỗi implementation/timing làm script trả lỗi; chỉ xuất khi đạt timing/route;
  đồng bộ bitstream/XSA sang platform Vitis. Script nạp ZCU106 từ chối bit cũ hơn RTL.

## Bằng chứng và trạng thái

- Watchdog lifecycle dùng ngưỡng sản xuất, clock board: **22 PASS, 0 FAIL**.
  Ép counter tới sát ngưỡng để kiểm tra lần tăng cuối và timeout/clear qua CDC;
  đây không phải phép đo chờ hết toàn bộ ngưỡng theo thời gian thực.
  Log: `reports/watchdog_lifecycle/lifecycle.log`.
- Kiểm tra tích hợp treo chủ đích: **3 PASS, 0 FAIL**, VETO và fault 0x40.
  Test này dùng `SIM_WDT_FAST` để tạo timeout; macro không dùng trong build board.
  Log: `reports/watchdog_lifecycle/integration_xsim.log`.
- Bộ unit watchdog U12: **79 PASS, 0 FAIL** sau khi sửa lấy mẫu sau NBA,
  phù hợp việc bộ đếm chỉ dùng tầng CDC thứ hai.
  Log: `reports/watchdog_lifecycle/u12_fixed.log`.
- Mô phỏng hệ thống không dùng macro tăng tốc: đang chạy. Các burst quỹ đạo đầu
  đã tăng địa chỉ đúng, đủ 351 beat, không phát lặp. Chưa đồng nghĩa mọi ca đã đạt.
  Log ngắn/toàn bộ nằm trong `sim_sysbd/prj/tsm_sysbd.sim/sim_1/behav/xsim/`.
  Kết quả H0261 trước sửa đệm được giữ ở `sysbd_before_padding_fix.stdout`.
- H0261 sau sửa đệm: **PASS**, VETO fault 0x00, GPIO1 trước start 0,
  8 burst hẹp/351 beat quỹ đạo, không RRESP lỗi, bước va chạm 12/vật cản 1,
  thời gian đo start → complete **8,002 ms**. Đây mới là ca đầu;
  ca H0102 sau 10 ms rảnh, ca CRC và bộ 16 ca vẫn còn chờ hoàn tất.
- Trạng thái các bước tiếp theo và build được cập nhật tự động ở
  `reports/board_fix_validation/status.json` và `progress.log`.
  `tested_sources.json` ghi SHA256 nguồn; nếu nguồn đổi trong lúc kiểm tra,
  pipeline dừng và yêu cầu kiểm tra lại.

## Những phần còn phải xác nhận trên board

DDR vật lý, việc R5 từng đứng ở word 88, và đường suy luận VLA bằng weight
không thể được kết luận chỉ từ mô phỏng TSM + AXI VIP. Dùng init ZCU106,
chạy onecase với kiểm tra đọc lại DDR; sạch mới chạy bảng A của demo đầy đủ.
Không thay weight để chữa lỗi giao tiếp AXI hoặc watchdog.

Xem `docs/HUONG_DAN_DEMO_ZCU106.md` để chạy và đối chiếu log.

## Cập nhật weight và kiểm tra trước buổi lab

- Phân biệt đúng: lỗi AG–AH thuộc kiến trúc số học Traj cũ, không phải file weight.
  AK.13 ghi RMSE phần cứng mới (mô hình RTL-exact) 1,520 m trên 5.419 VAL;
  nguồn checkpoint của exporter là `autoregressive_gru_200ep.pt`.
- Đối chiếu mới: 10/10 payload V2 trùng từng byte với `tb/e2e/vec/ddr_*.hex`,
  đúng kích thước manifest và địa chỉ `planning_pkg.sv`.
  Chi tiết/SHA256: `reports/board_fix_validation/payload_audit.json`.
- Script nạp cũ chỉ đọc word đầu của mỗi payload. Đã thêm `board_verify_ddr.tcl`:
  đọc toàn bộ payload + demo bank theo chunk 64 KB trước khi nhả reset PL.
  Lỗi đọc, thiếu byte hoặc khác bất kỳ word nào đều dừng script và ghi địa chỉ.
  Helper đã qua 11 kiểm tra mock, gồm lỗi ở giữa BERT weight; **chưa thử đọc DDR thật**.
  Log: `reports/board_fix_validation/test_ddr_verify.log`.
- Bộ ngắn hiện đã **3/3 PASS**: H0261 VETO 0x00, H0102 GRANT 0x00 sau nghỉ 10 ms,
  H0261_CRC VETO 0x08. GPIO1 trước start 0 cả ba lượt; thời gian 8,002 ms.
  CRC trong đường preproc này cũng báo hoàn tất sau đệm 8 ms; không phải lỗi nào
  cũng đi qua FSM_ERROR báo ngay. Timeout thật đã được kiểm tra báo VETO 0x40.
- Bộ hệ thống đầy đủ đang chạy; trạng thái build/regression đọc ở `status.json`,
  không suy từ timestamp bitstream cũ.

## Cập nhật sau mô phỏng hệ thống

- Bộ hệ thống hoàn tất lúc 08:14 ngày 06/10: **16 PASS / 0 FAIL**.
  Pipeline xác nhận GPIO1 trước start sạch và đúng 8 burst hẹp trong mọi ca.
- Regression mini_val đầu tiên dừng vì runner chạy ở thư mục riêng, trong khi
  testbench dùng `sw/hmao_payloads/...` tương đối: thiếu dữ liệu đầu vào, 73 ca báo CRC.
  Đã sửa runner chạy tuần tự từ gốc dự án; giữ log riêng từng bước.
- Bổ sung `-ResumeAfterSystem`: chỉ được tiếp tục nếu SHA256 nguồn vẫn trùng
  nguồn đã qua 3/3 và 16/16; không cần chạy lại nhiều giờ mô phỏng đã đạt.
  Đã tiếp tục mini_val lúc 12:01; chưa coi regression hoặc bitstream là hoàn tất.
