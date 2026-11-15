# TSM-X trên ZCU106: chạy board và lấy kết quả

Bitstream chỉ có TSM-X: P=G=2, đường stream (PARA_DIRECT=0), clock 100 MHz.
Không cần firmware: xsdb đọc/ghi thanh ghi qua JTAG, phát lại đúng trình tự của mô phỏng "giống board".

## Chuẩn bị (một lần)
- ZCU106, cáp JTAG (micro-USB J2) và nguồn. Không cần UART.
- **SW6 đặt JTAG boot.**
- Kiểm có file `board/out/system_wrapper_tsmx.bit`. File này do `build_tsmx_zcu106.tcl` sinh ra, và chỉ được chép ra khi timing đạt.

## Chạy
Mở cmd tại `journalQ1\tsmx_hw\board`:

```
C:\Vivado\Vivado\2023.2\bin\xsdb.bat run_tsmx_board.tcl smoke5
C:\Vivado\Vivado\2023.2\bin\xsdb.bat run_tsmx_board.tcl reg300_board
C:\Vivado\Vivado\2023.2\bin\xsdb.bat run_tsmx_board.tcl apos
C:\Vivado\Vivado\2023.2\bin\xsdb.bat run_tsmx_board.tcl worst2
C:\Vivado\Vivado\2023.2\bin\xsdb.bat run_tsmx_board.tcl worst_apos
```

- `smoke5`: 5 job, chạy trước để kiểm đường AXI.
- `reg300_board`: 261 job hồi quy (300 job đầu, bỏ 39 job tiêm lỗi health chỉ có ở chế độ DIRECT=1; xem filter_health_inject.py).
- `apos`: 360 job, gia tốc dương (A8).
- `worst2`: trường hợp nặng nhất, 32 vật cản.
- `worst_apos`: trường hợp nặng nhất có gia tốc dương.

Mỗi lần chạy, script nạp psu_init, bitstream, bỏ cô lập PS-PL, rồi chạy từng job.
Log ghi vào `board/results/<tag>_<giờ>.log`.

## Chấm kết quả
```
python check_board.py reg300_board results\reg300_board_YYYYMMDD_HHMMSS.log
```

Mỗi job được so:
- response 38 bit, log sự kiện 1056 bit;
- số khung lệnh ra và nội dung 238 byte của lệnh;
- CSR reason, status, lost;
- **số chu kỳ quyết định đo trên phần cứng, phải trùng từng chu kỳ với mô phỏng.**

## Lỗi thường gặp
- `shim ID ... (bitstream/AXI path wrong)`: sai bitstream, hoặc PS chưa nạp psu_init đúng loại DDR.
- `timeout waiting for job=N response`: ghi lại N rồi gửi log cho Claude.
- Nếu JTAG không thấy target PSU: kiểm nguồn, SW6, cáp.
