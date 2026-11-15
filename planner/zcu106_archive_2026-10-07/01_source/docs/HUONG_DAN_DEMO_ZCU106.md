# Chạy demo trên ZCU106

## Trạng thái bản sửa

RTL đã sửa chọn làn dữ liệu AXI, chặn phát lặp burst khi đang chờ dữ liệu,
và quản lý vòng đời watchdog. **Bitstream cũ chưa chứa hai bản sửa cuối.**
Chờ `reports/board_fix_validation/status.json` có trạng thái `passed` và stage
`validation and bitstream complete; physical board test still required`.
Nếu trạng thái `failed`, đọc `progress.log` và log bước lỗi; không coi bản cũ là bản đã sửa.

Script kiểm tra/build là `scripts/verify_build_tsm_board.ps1`. Nó chạy ba ca ngắn,
16 ca mức hệ thống với SmartConnect thật, mini_val 219 kiểm tra, ca biên 28 kiểm tra,
rồi synthesis → implementation → bitstream với `ipcache_guard` và kiểm tra timing/route.
Bitstream chỉ được xuất khi các bước đạt. SHA256 của ba bản bitstream phải giống nhau:

- `hw_project/planning_hw.runs/impl_1/system_wrapper.bit`
- `deliverables/v2d/system_wrapper_v2d.bit`
- `vitis_ws_v2d/v2d_plat/hw/system_wrapper_v2d.bit`

## Kết nối và terminal

Board đang dùng là ZCU106: giữ cấu hình SW6 JTAG đã kiểm tra trong buổi lab.
Kết nối nguồn, USB-JTAG và USB-UART vào máy. Dùng driver cáp JTAG của Vivado
và Silicon Labs CP210x cho UART. Mở PuTTY trước khi chạy XSDB:

- Session → Serial; Serial line: COM của **CP2108 Interface 0** (máy này đã xác nhận COM7).
- Speed: 115200.
- Connection → Serial: Data bits 8, Stop bits 1, Parity None, Flow control None.

Lệnh XSDB chạy trong **CMD hoặc PowerShell trên máy tính**. PuTTY hiển thị log UART.

## Thử một ca trước

Mở CMD tại thư mục dự án rồi chạy:

```cmd
C:\Vivado\Vivado\2023.2\bin\xsdb.bat scripts\board_run_onecase_zcu106.tcl
```

Script dùng `deliverables/zcu106/psu_init_zcu106.tcl`, bitstream trong `deliverables/v2d`
và `vitis_ws_v2d/tsm_onecase.elf`. Ca này dùng quỹ đạo và world model tính sẵn,
**chưa chạy suy luận VLA bằng weight trên PL**.

Log UART cần có:

- CRC nguồn và DDR cùng khớp CRC lưu; H0261: `0xFAEE5BE8`.
- `DDR VERIFY OK trajectory` và `DDR VERIFY OK world model`.
- `GPIO1 before start=0x00000000`.
- `Decision: VETO`, `Fault=0x00`, hoàn tất khoảng 8 ms.

VETO ở H0261 là phát hiện va chạm theo dữ liệu, không phải lỗi phần cứng.
Nếu copy DDR lại đứng, giữ nguyên board và lưu log/địa chỉ bị đứng để kiểm tra bằng JTAG.
Mô phỏng AXI VIP chưa chứng minh DDR vật lý hoặc cấu hình PS trên board hoạt động đúng.

## Chạy demo đầy đủ

Chỉ sau khi ca trên đạt, chạy:

```cmd
C:\Vivado\Vivado\2023.2\bin\xsdb.bat scripts\board_run_demo_zcu106.tcl
```

Script nạp weight `sw/payloads/v2`, `demo_bank.bin` và firmware `tsm_demo.elf`.
Nó kiểm tra kích thước/vùng DDR theo manifest và chờ loader báo sẵn sàng.
Trước khi nhả reset PL, script đọc lại **toàn bộ byte** của cả 10 payload và demo bank
theo chunk 64 KB. Chờ `DDR FULL VERIFY OK` cho từng file và
`DDR FULL readback OK for all model payloads and demo bank.`; việc này tăng thời gian nạp.
Bản script trước chỉ kiểm tra word đầu mỗi file, không đủ chứng minh toàn bộ DDR đúng.
Bảng A chạy VLA-Traj trên PL rồi đưa quỹ đạo sang TSM; bảng B chạy các ca TSM tính sẵn;
bảng C tiêm lỗi. So kết quả bằng `demo_cases.json` và tổng kết firmware.

Weight được train trong phần mềm và xuất sang định dạng của phần cứng;
các bản sửa AXI/watchdog không thay weight. Qua onecase không đủ chứng minh đường weight/inference:
cần bảng A khớp waypoint và quyết định trong demo đầy đủ.
Lỗi cũ AG–AH là kiến trúc số học Traj thiếu LayerNorm và residual khác model đã train;
BERT V2 đã sửa phần đó. Không có bằng chứng file weight hiện tại gây lỗi CRC/watchdog TSM.

Dùng script có hậu tố `_zcu106`. Script `board_run_demo.tcl` dùng cấu hình PS ZCU104.
Ưu tiên XSDB để chắc chắn dùng đúng init và đúng artifact đã kiểm tra.
Một timeout thật vẫn đưa FSM vào trạng thái lỗi cần reset; không chạy tiếp các ca sau khi treo thật.
