# Chạy board 07/10 — sau khi thay RAM phía PS

Mọi lệnh chạy trong CMD; đường dẫn file `.tcl` dùng dấu `/`. Trước mỗi bước: board bật nguồn,
PuTTY mở **COM7, 115200 8N1, Flow control None** (tắt nguồn board thì phải mở lại PuTTY).

## Bước 1 — Kiểm DDR (bắt buộc, ~10 s, không cần bitstream)

```
C:\Vivado\Vivado\2023.2\bin\xsdb.bat C:/Users/TransformerDA/Downloads/vla_new_arch/scripts/board_test_ddr.tcl
```

Đạt khi: `DDRC STAT ... = 1 (Binh thuong)`, dòng `co LOI training : (khong co)`,
Bước 2 `dung 16 word, sai 0 word` và `DDR doc/ghi dung`.
Nếu vẫn `VERR` hoặc treo: DDR chưa dùng được → **tắt/bật nguồn**, chỉ làm Bước 2 (TSM bằng OCM).

## Bước 2 — TSM trên OCM (đã chạy được 06/10, không dùng DDR)

```
C:\Vivado\Vivado\2023.2\bin\xsdb.bat C:/Users/TransformerDA/Downloads/vla_new_arch/scripts/board_run_tsm_multi_zcu106.tcl
```

Đạt khi PuTTY in `51/51` và `==== TSM TREN FPGA: DAT ====`, độ trễ 8,000–8,001 ms.

## Bước 3 — Demo đầy đủ VLA-Traj + TSM (cần DDR đạt ở Bước 1)

Bitstream `deliverables/v2d/system_wrapper_v2d.bit` (build 07/10: TSM đã sửa đọc AXI + watchdog,
Traj đã sửa AXI-Lite). Script nạp `psu_init` ZCU106, bitstream, 10 tệp trọng số + ngân demo vào DDR,
đọc lại toàn bộ DDR, nhả reset PL, kiểm Traj nạp xong trọng số, rồi chạy R5.

```
C:\Vivado\Vivado\2023.2\bin\xsdb.bat C:/Users/TransformerDA/Downloads/vla_new_arch/scripts/board_run_demo_zcu106.tcl
```

CMD phải có `DDR FULL VERIFY OK ...` cho từng tệp, `Traj STATUS = 0x...5..` (bit 8 và 10).
PuTTY — so với mô phỏng:

| Bảng | Kỳ vọng (mô phỏng) |
|---|---|
| [A] 35 khung: waypoint FPGA khớp mô phỏng ≤ 1 mm | 35/35, quyết định TSM 35/35 GRANT |
| [B] 15 ca | 6 VETO (bước/vật cản như bảng TSM OCM), 9 GRANT |
| [C] C1 CRC / C2 NaN / C3 xe chắn | VETO 0x08 / VETO (0x02) / VETO 0x00 |
| Độ trễ TSM | 8,00 ms |
| Độ trễ Traj | ~60–70 ms/khung (Traj chạy 100 MHz với psu_init ZCU106; mô phỏng 150 MHz: 40–46 ms) |

Chỉ có Traj (nếu muốn tách riêng): `scripts/board_run_traj_zcu106.tcl` (dùng bitstream `deliverables/v2d` mới, không chạm TSM).

## Xử lý sự cố

| Hiện tượng | Xử lý |
|---|---|
| `board power off` / không có target PSU | bật nguồn, kiểm cáp JTAG |
| `AXI AP transaction error` | tắt board 5 s, bật lại, chạy lại |
| `DDR FULL VERIFY` báo khác / treo | DDR vẫn lỗi → chỉ demo Bước 2 |
| `Traj STATUS bits 8 and 10 are not both set` | DDR/trọng số chưa đúng → xem Bước 1 |
| PuTTY không có chữ | đóng/mở lại PuTTY COM7 rồi chạy lại |
| `couldn't read file` | đường dẫn `.tcl` phải dùng `/` |
