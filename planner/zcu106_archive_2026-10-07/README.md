# Lưu trữ kết quả chạy board — VLA-Traj + TSM trên ZCU106 (07/10/2026)

Thư mục này **chỉ để đọc**: là bản chụp nguồn, kết quả build và kết quả đo trên board của lần demo đầy đủ đạt đầu tiên.
Dùng làm căn cứ khi viết paper. Muốn sửa code thì sửa ở cây dự án gốc, **không sửa ở đây**.
Kiểm tra toàn vẹn: `md5sum -c MD5SUMS.txt` (chạy trong thư mục này).

## 1. Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `01_source/` | Nguồn: RTL (`rtl/`, `HMAO/`), ràng buộc (`constrain/`), block design (`block_design/system.bd`), firmware R5 (`firmware_r5/`), payload trọng số DDR (`ddr_payload_weights_v2/`), script build / nạp board / đo (`scripts/`), testbench (`tb/`), mô phỏng hệ thống (`system_sim/`), hướng dẫn (`docs/`). `board_variants/tsm_ocm/hmao_pkg.sv` = bản đổi địa chỉ bộ đệm sang OCM cho bitstream chỉ-TSM. |
| `02_synthesis/` | Kết quả tổng hợp/triển khai: bitstream + XSA + DCP + báo cáo timing/utilization/power/DRC (`full_soc_v2d/`), 2 bitstream chỉ-TSM (`tsm_only_ocm/`, `tsm_only_ddr/`), các psu_init (`psu_init/`), ELF firmware (`firmware_elf/`). |
| `03_board_results/` | Log đo **trên board thật**: demo đầy đủ (`full_demo/`), TSM chỉ-TSM (`tsm_only_ocm/`), lần treo trước khi sửa DDR (`tsm_only_ddr_FAIL_before_ddr_fix/`), điều tra DDR + SPD (`ddr_investigation/`), quét tần số clock (`pl0_frequency_sweep/`). |
| `04_simulation_results/` | Log mô phỏng làm đối chứng: hệ thống TSM với SmartConnect thật (trước/sau sửa), replay 53 ca, Traj hệ thống, hồi quy mini_val 219 + edge 28. |

Mỗi log board có vài dòng `#` ở đầu ghi ngữ cảnh (ngày, bitstream, cấu hình); phần dưới dòng `NGUYEN VAN` là output gốc, không chỉnh.

## 2. Phần cứng và cấu hình

- Board **ZCU106** (XCZU7EV-FFVC1156-2-E). UART CP2108 → COM7, 115200 8N1. JTAG FT232H.
- RAM PS: **SO-DIMM Micron MTA4ATF51264HZ-2G6E1** (4 GB, 1 rank, chip x16 8Gb, 16 bit hàng, 10 bit cột, DDR4-2666). Đọc từ SPD qua I2C1, mux TCA9548 0x75 kênh 3, địa chỉ 0x51 (`03_board_results/ddr_investigation/06_*`).
- psu_init dùng: `02_synthesis/psu_init/psu_init_zcu106_ram_x16_8gb.tcl`. Đây là psu_init ZCU106 gốc, chỉ thay khối `psu_ddr_init_data` bằng khối sinh cho UDIMM x16 8Gb, 16 bit hàng, chạy DDR4-2133. Khối DDR đó sinh bằng `01_source/scripts/gen_psu_init_zcu106_sodimm.tcl`; kết quả sinh là `psu_init_zcu106_sodimm_x16_8gb.tcl`.
- Clock:

  | Clock | Khối | Tần số |
  |---|---|---|
  | PL0 | VLA-Traj, AXI-Lite, GPIO, HP0 | IOPLL 1500 MHz / div. Mặc định psu_init là div 15 = 100 MHz; timing ký ở 150 MHz. |
  | PL2 | TSM (HMAO), HP1 | 187,5 MHz |
  | PL3 | watchdog | 250 MHz |

## 3. Số liệu chính (cho paper)

### 3.1 Tổng hợp/triển khai — `02_synthesis/full_soc_v2d/` (Vivado 2023.2)

- Bitstream `system_wrapper_v2d.bit`, md5 `64ca2432cb651bb2e7faada7537fbad9`, build ngày 07/10/2026.
- Timing sau route: 0 endpoint vi phạm (412 411 endpoint).

  | Clock | WNS (ns) | WHS (ns) |
  |---|---|---|
  | clk_pl_0 (Traj, 150 MHz) | +0,293 | +0,010 |
  | clk_pl_2 (TSM, 187,5 MHz) | +0,014 | +0,010 |
  | clk_pl_3 (WDT, 250 MHz) | +2,369 | +0,044 |

- Tài nguyên. Tỷ lệ % tính trên XCZU7EV: 230 400 LUT, 460 800 FF, 312 BRAM36, 96 URAM, 1 728 DSP.

  | Khối | LUT | FF | BRAM36 (+RAMB18) | URAM | DSP |
  |---|---|---|---|---|---|
  | Toàn hệ | 110 572 (48,0 %) | 103 248 (22,4 %) | 214 (+12) ≈ 70,5 % | 72 (75 %) | 866 (50,1 %) |
  | VLA-Traj (`planning_top_0`) | 80 363 | 68 097 | 214 (+12) | 72 | 646 |
  | TSM (`hmao_engine_0`) | 27 340 | 31 036 | 0 | 0 | 220 |

- Công suất ước tính (Vivado, mặc định): tổng 6,557 W (động 5,834 W, tĩnh 0,723 W). Đây là số **ước tính**, không phải đo trên board.

### 3.2 Demo đầy đủ trên board — `03_board_results/full_demo/uart_full_demo_100MHz_DAT.log`

- Cấu hình chạy: PL0 = 100 MHz, PL2 = 187,5 MHz.
- Dữ liệu: nuScenes VAL scene-0103 (35 khung, idx 822..856). Trọng số + ngân hàng demo tổng 12,6 MB nạp vào DDR, đọc lại đối chiếu từng byte và **khớp toàn bộ** (`xsdb_load_and_ddr_verify.log`).

| Hạng mục | Kết quả |
|---|---|
| [A] Waypoint Traj trên FPGA khớp mô phỏng (≤ 1 mm) | 35/35, lệch lớn nhất 21 µm |
| [A] Quyết định TSM khớp mô phỏng (E2E Traj → TSM) | 35/35 |
| [B] 15 ca nuScenes cho TSM (6 VETO, 9 GRANT) | 15/15 |
| [C] Tiêm lỗi: CRC sai, NaN, xe cản phía trước | 3/3 (fault 0x08, 0x02, VETO không lỗi) |
| Độ trễ TSM (start → complete) | 8,00 ms, cố định (thiết kế: 1 500 000 chu kỳ @ 187,5 MHz) |
| Độ trễ Traj trung bình (BERT + GRU) @ 100 MHz | 60,06 ms |

Thời gian đo bằng bộ đếm hệ thống IOU_SCNTRS (99 990 008 Hz), **không dùng XTime**, vì XTime sai khi boot JTAG không có FSBL.

### 3.3 TSM chỉ-TSM, bộ đệm OCM — `03_board_results/tsm_only_ocm/`

- 17 ca × 3 vòng = **51/51 đúng**: quyết định, fault, bước và vật cản đều khớp mô phỏng RTL.
- Độ trễ 8,000–8,001 ms.
- Chạy ngày 06/10, trước khi sửa được DDR.

### 3.4 Quét tần số clock Traj (PL0) — `03_board_results/pl0_frequency_sweep/`

Cùng một bitstream, chỉ đổi bộ chia của PL0.

| PL0 | Kết quả | Thời gian Traj |
|---|---|---|
| 100,0 MHz | ĐẠT | 60,06 ms |
| 136,4 MHz | ĐẠT | 44,09 ms |
| 150,0 MHz (tần số timing ký) | ĐẠT | 40,10 ms |
| 166,7 MHz | ĐẠT | 36,15 ms |
| 187,5 MHz | ĐẠT | 32,13 ms |
| 214,3 MHz | ĐẠT ×3 lần | 28,13 ms |
| 250,0 MHz | **SAI**: waypoint 0/35, TSM[A] 24/35 | 24,14 ms |

- Mỗi mức ĐẠT: WP 35/35 (lệch tối đa 21 µm), [A] 35/35, [B] 15/15, [C] 3/3, TSM 8,00 ms.
- Ngưỡng lỗi thật nằm giữa 214,3 và 250 MHz.
- **Chỉ 150 MHz là tần số được timing đảm bảo**. Các mức trên 150 MHz là đo thực nghiệm trên 1 board ở nhiệt độ phòng, không phải biên đảm bảo; khi viết paper phải ghi rõ điều này.
- Ghi chú log: UART thô của lần quét 100→250 MHz bị lần chạy lặp 214 MHz ghi đè. Phần còn lại là tóm tắt từng mức, đầy đủ (`sweep_summary_100_to_250MHz.log`), và UART đầy đủ của 3 lần 214 MHz (`uart_214MHz_repeat_x3_full.log`).

### 3.5 Nguyên nhân lỗi DDR — `03_board_results/ddr_investigation/`

| psu_init | Kết quả |
|---|---|
| Preset ZCU106 gốc (UDIMM x8 4Gb) | PGSR0 = 0x80084FFF: bit 19 VERR, lỗi VREF training. Địa chỉ bị trùng, đọc treo AXI-AP. |
| Preset ZCU104 (Components x16 4Gb, psu_init của XSA) | Training không báo lỗi, nhưng dữ liệu sai và đọc treo. |
| **Khớp SPD** (x16 8Gb, 16 bit hàng) | PGSR0 = 0x80004FFF, không trùng địa chỉ, **0/5376 word sai** |

Kết luận: **DDR không hỏng**. Lỗi là do cấu hình bộ điều khiển trong psu_init không khớp thanh RAM thực tế lắp trên board.

Lưu ý: log `01_*` in nhãn bit sai ("ZCERR"); đúng phải là VERR. Script đã được sửa sau đó.

### 3.6 Đối chứng mô phỏng — `04_simulation_results/`

| Log | Nội dung | Kết quả |
|---|---|---|
| `tsm_system_BEFORE_FIX_*` | TSM hệ thống với SmartConnect thật, trước khi sửa | Tái hiện lỗi 0x48 như trên board (lỗi chọn lane khi burst hẹp + phát AR trùng) |
| `tsm_system_16case_realclock_PASS.log` | Cùng sim, sau sửa | 16/16 |
| `tsm_replay_53case_*` | Replay đúng thứ tự firmware, không và có backpressure ngẫu nhiên | 53/53 |
| `traj_system_smartconnect_PASS.log` | Traj hệ thống, nhánh `SYNTHESIS` | AXI-Lite 5/5; 17 758 AR, 0 lỗi; waypoint khớp bit |
| `tsm_mini_val_219_PASS.log` | Hồi quy mini_val | 219/219 |
| `tsm_edge_cases_28_PASS.log` | Hồi quy edge case | 28/28 |

## 4. Tái tạo lại

Nạp và chạy demo đầy đủ:

```text
:: PuTTY COM7 115200 mở sẵn
C:\Vivado\Vivado\2023.2\bin\xsdb.bat <repo>/scripts/board_run_demo_zcu106.tcl
:: Đổi clock Traj (không nạp lại DDR):
set PL0_DIV=10   (10 = 150 MHz; 15 = 100 MHz)
C:\Vivado\Vivado\2023.2\bin\xsdb.bat <repo>/scripts/board_pl0_freq_rerun.tcl
:: Quét tự động (đóng PuTTY trước):
python scripts/board_pl0_sweep.py 15 11 10 9 8 7 6
```

Kiểm tra DDR / đọc SPD (không cần bitstream):

```text
xsdb scripts/board_test_ddr_deep.tcl
xsdb scripts/board_read_spd.tcl
```

Build lại bitstream:

```text
bash scripts/run_build_full_retry.sh
```

`run_build_full_retry.sh` gọi `build_board_v2d.tcl`. Script này reset 4 run OOC module-reference và dùng `ipcache_guard.tcl`, nhằm chặn lỗi Vivado dùng lại netlist cũ.

Firmware R5: `bash scripts/board_build_elf.sh` (armr5-gcc, BSP standalone, linker `firmware_r5/lscript_r5.ld`).

Script trong `01_source/scripts/` dùng đường dẫn tương đối theo gốc dự án. Muốn chạy thì chạy từ cây dự án gốc, hoặc chép `01_source/*` về đúng vị trí.

## 5. KHÔNG dùng các file sau (nằm ngoài thư mục này, ở cây dự án)

| File / thư mục | Lý do |
|---|---|
| `deliverables/v2d_0710_tsmfix_trajcu/` (md5 ed0156d1…) | Build 02:15 ngày 07/10, Vivado dùng lại netlist Traj **cũ** |
| `deliverables/v2d_traj_only_fallback/` (md5 8ddadfe9…) | Bản 05/10, TSM chưa sửa |
| `psu_init/psu_init_zcu106.tcl`, `psu_init/psu_init_zcu104_preset_components.tcl` | Cấu hình DDR sai cho board này. Chỉ lưu lại làm bằng chứng điều tra. |
| Dòng `TSM latency: 11 us` trong log onecase | Sai do XTime; số đúng là 8,000 ms |
| Tiêu đề `demo tren ZCU104` trong log demo đầy đủ | Chuỗi cũ của firmware; phần cứng chạy là ZCU106. ELF lưu ở đây đã sửa chuỗi này. |
