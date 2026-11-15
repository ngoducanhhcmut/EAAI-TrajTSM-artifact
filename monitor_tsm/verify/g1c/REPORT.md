# G1c — B3 không phép chia (swept_lb / advance_lb) — Claude, 30/10/2026

Lý do: B3 số hữu tỉ chính xác (14 phép chia 128 bit + ~80 nhân/cặp đối tượng-hàng) không thể vừa ZCU106 và ≤10 ms; người dùng chọn đổi thuật toán.
Thay đổi golden (chỉ trong `b3_geom`): `swept`→`swept_lb`, `advance`→`advance_lb` (B2/top giữ dạng chính xác). Chứng minh phác thảo ở chú thích `model.py` trước `disp_lb`.
- Xe trước: cận dưới tuyến tính (dây cung nếu a<0, tiếp tuyến v·t nếu a≥0); xe sau: cận trên tuyến tính (tiếp tuyến nếu a≤0 kể cả dừng, dây cung nếu a>0) ⇒ khoảng cách cận dưới tuyến tính, min tại 0 hoặc h.
- Dừng giữa ô: dưới = max(0, parabol không cắt); trên = ⌈v·h/2T⌉. Bảo thủ ≤ (|aa|+|ab|)h²/2 + 2 LSB (≤8 cm ở h=0,1 s).
Model SHA256 trước: a216ccae9d7b54837138c7f50a4e7bd3306ea879f8f2614dad19b147be7624dc (bản sao `model_before_g1c.py`); sau: ee470932819c9f92125c81516e14edcb45a72cd6fe207f34bd1ed392276c2a50. Không float, không phép chia `/`.

| Kiểm | Kết quả |
|---|---|
| Unit golden | 148/148 PASS |
| V2 soundness (oracle Fraction độc lập), 200.000 đầu vào B2/B3/B4/B7 | 0 phản ví dụ |
| Nhiều ô: 20.000 quỹ đạo B4 thật + 1–8 đối tượng có sự kiện | new-accept ⇒ old-accept: 0 vi phạm; 6/13.830 (0,04 %) bảo thủ hơn; margin giảm ≤ 50.304 µm |
| Ô đơn, mọi dấu gia tốc, 100.000 ca so oracle | 0 unsound; bảo thủ tối đa 0,0498 m |
| Ca biên 117 (interior đổi sang an toàn + bảo thủ có cận) | 117/117 PASS (đăng ký mới; cũ: edge_registration_before_g1c.json) |
| V1 smoke 10 IC × 11 lỗi | 13.886/13.886 dòng quyết định giống hệt (SHA 41b1ad97…) |
| V3 smoke 5 IC × 11 lỗi | 6.761/6.761 dòng giống hệt (SHA 76080846…) |
Vector sinh lại: chỉ b3 (71/128 dòng đổi giá trị margin; 1 cờ accept đổi) và edges; system/b1/b2/b4/b7–b13 giữ nguyên byte. Bản cũ: vectors/legacy_g1b/.
Lệnh: `py -3.13 -B tsmx_hw/verify/g1c/check_g1c.py tsmx_hw/verify/g1c 200000 20000`; `identity_smoke.py {old,new} {v1,v3}`.
