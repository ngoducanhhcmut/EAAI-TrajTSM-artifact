# TSM-X HW — kế hoạch hiện thực (29/10/2026, Claude giám sát; Codex thực hiện từng gói)

Nguồn yêu cầu: `journalQ1/tsm_research/TSM_X_DESIGN_v2.md` + kết quả P5a–P5c2 (OVERNIGHT_LOG.md hàng 8–12).
Người dùng yêu cầu: golden model → kiểm chuẩn → spec (VLSIT microspec) chia khối nhỏ → RTL từng khối (VLSIT rtl-generator) + unit test → tích hợp + integration test → báo cáo.
Người dùng giao toàn quyền quyết định (mọi "bạn quyết" ghi là ASSUMPTION trong spec, rule R-004).

## Quyết định phạm vi (ASSUMPTION, chốt bởi Claude dựa trên bằng chứng P5)
- A1 ODD bản 1: dọc 1 làn + kiểm containment ngang; v ≤ 10 m/s (tham số hoá tới 20 m/s); braking-only. KHÔNG lệch ngang/đổi làn/tấp lề (P5c2: không có giá trị, kể cả oracle).
- A2 Thư viện MRM = 16 profile P5a: decel {2,4,6,8} m/s² × jerk {2,4,8,instant}; sinh on-the-fly từ hệ số tới dừng + giữ ≥ 2 s; bước 0,1 s.
- A3 Selector = lexicographic: front-admissible (B3) → decel nhỏ nhất → jerk nhỏ nhất → id (= d2 của P5bd2). Không còn admissible ⇒ L3 mitigation brake8/instant, nhãn MITIGATION.
- A4 Khối trên FPGA/ASIC (RTL): B1 Integrity/Freshness, B2 Splice, B3 Geometry checker ×P (P=4), B4 MRM generator, B7 Selector, B8 Supervisor FSM, B9 Certificate/Expiry/ACK/Arbitration, B10 Event recorder, B13 Health monitor (BIST + parity/ECC-lite + lane cross-check + FSM protection), CSR (AXI4-Lite), ingress/egress stream.
- A5 Ngoài RTL bản 1 (chỉ đặc tả giao diện/golden C nếu cần): B12 Safety Executor (R5F), B11/B14 (R5F), B5/B6 (bỏ khỏi đường quyết định — P5c2), B15 (future), phanh ngoài (heartbeat ra chân).
- A6 Số học: số nguyên/fixed-point thuần, không float trong đường quyết định; định dạng do golden chốt kèm chứng minh cận (soundness hữu hạn-bit = mệnh đề 1).
- A7 Mục tiêu thời gian: ≤ 10 ms/chu kỳ quyết định @187,5 MHz (ước lượng R10a P=4: ~2,8–4,4 ms); dùng `ifndef SYNTHESIS` không được làm khác hành vi (bài học BERT).

## Gói (tuần tự; Claude kiểm độc lập sau mỗi gói)
| Gói | Nội dung | Đầu ra |
|---|---|---|
| G1 | Golden model bit-accurate + kiểm chuẩn (V1 tương đương tham chiếu float P5bd2, V2 soundness hữu hạn-bit ≥10⁶, V3 vòng kín) | `golden/`, `verify/`, `G1_REPORT.md` |
| S1 | Spec VLSIT (22 mục, REQ-ID, CSR json/xlsx, block diagram, waveform), chia khối con + bảng cổng/latency mỗi khối | `spec/TSMX_Design_Specification.md` |
| R1..Rn | RTL từng khối con (VLSIT rules, rule check + lint) + unit TB vector golden + assertion | `rtl/`, `tb/unit/<blk>/` |
| I1 | Top tích hợp + integration TB (vector golden cấp hệ thống, fault bursts, timing) | `rtl/m_tsmx_top.sv`, `tb/integ/` |
| F1 | Báo cáo cuối + (tuỳ) synth OOC Vivado ZCU106 | `FINAL_REPORT.md` |

Mô phỏng: Codex dùng Icarus (`C:\iverilog\bin`) trong sandbox; Claude chạy lại Verilator (WSL, chính) + lint `verilator --lint-only -Wall`.
