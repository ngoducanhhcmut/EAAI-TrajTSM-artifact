# TSM-X phần mềm trên CPU: số đo so sánh với phần cứng

Bản C của lõi quyết định TSM-X ([tsmx_kernel.c](tsmx_kernel.c)), gồm:
- B4 sinh quỹ đạo phanh;
- B3 kiểm hình học;
- select_world.

Bản này khớp từng bit với golden Python: 120 ca × 16 ứng viên, so cả hàng quỹ đạo, margin, lý do và ứng viên được chọn.

## Chạy trên ZCU106 (không cần bitstream, không cần UART)
1. Đặt SW6 ở JTAG boot, cắm cáp JTAG, bật nguồn.
2. Tại `journalQ1\tsmx_hw\sw_baseline`, chạy:
```
C:\Vivado\Vivado\2023.2\bin\xsdb.bat run_cpu_bench.tcl
python parse_cpu.py results\cpu_YYYYMMDD_HHMMSS.log
```
Script lần lượt chạy A53 #0 rồi R5F #0, mỗi lõi mất khoảng 1–3 phút.

Mỗi lõi làm hai việc:
- **Kiểm khớp bit** với golden.
- **Đo thời gian** theo hai cách:
  - từng ca `select_world`;
  - "một sweep đầy đủ": 16 ứng viên × 32 vật, xe 9,8 m/s, a = +2, mọi hàng đều được kiểm. Đây là phần mềm tương đương với trường hợp xấu nhất của phần cứng (worst_apos: 947.263 chu kỳ, gồm hai sweep).

## Dựng lại
- `python gen_cases.py 120`: sinh `cases.h` từ golden.
- `sh build_cpu.sh`: ra `tsmx_a53.elf` và `tsmx_r5.elf`.
  - A53 dùng BSP standalone tạo bằng `xsct mk_bsp_a53.tcl`, lấy từ XSA của board TSM-X.
  - R5 dùng BSP của `vitis_ws_v2d`.

Chạy trên PC (WSL):
```
gcc -O2 -DHOST bench.c tsmx_kernel.c && ./a.out
```
Thêm `-DTS_PORTABLE` để dùng limb 32 bit như trên R5.

## Đã đo trên PC (04/11)
- Máy: Ryzen 5 6600H. Lúc đo máy đang chạy song song Vivado và mô phỏng BEV, nên số có nhiễu.
- Limb 64 bit: một sweep 4,66 ms (B4 2,57 ms, B3 2,09 ms), hai sweep 9,32 ms.
- Limb 32 bit: một sweep 6,43 ms.
