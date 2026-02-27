# Kế hoạch cải tiến game (chốt theo phương án B + C)

Tài liệu này đã được rút gọn theo đúng yêu cầu: **chỉ giữ các cải tiến thuộc nhóm B (Competitive drama) và C (Spectator readability)**, đồng thời **bỏ các phương án còn lại**.

---

## B. Competitive drama (ưu tiên cao)

## 5) Kiểm soát snowball bằng tham số growth
### Mục tiêu
- Giảm lợi thế tăng size quá sớm để trận không bị 1 chiều từ early game.
- Dời “sức mạnh bùng nổ” sang mid/late để tăng khả năng lật kèo.

### Hướng triển khai trong code hiện tại
- Tinh chỉnh `growth_step`, `initial_size_scale`, `max_size_scale` trong `GameConfig`.
- Áp dụng tăng trưởng theo phase trận (early thấp, mid/late cao) thay vì cố định toàn trận.
- Giữ logic tăng size khi đổi phe tại `Marble._on_weapon_body_entered()` nhưng thêm điều kiện scale theo thời gian hoặc theo tỷ lệ territory.

### KPI cần theo dõi
- `top1_hold_ratio` (đội top giữ top quá lâu hay không).
- `lead_changes` (số lần đổi top).
- `max_comeback_delta` (độ lật kèo lớn nhất).

---

## 6) Underdog mechanics rõ ràng
### Mục tiêu
- Buff đội yếu theo cửa sổ ngắn để tạo comeback có kiểm soát.

### Hướng triển khai trong code hiện tại
- Chọn underdog theo territory hoặc marble alive.
- Cấp buff tốc độ tạm thời theo chu kỳ (duration ngắn, có cooldown).
- Ưu tiên hook vào hệ thống tick thời gian trong `EscalationDirector._process()` để dễ bật/tắt theo preset.

### Nguyên tắc cân bằng
- Buff phải ngắn và có giới hạn trần.
- Không stack vô hạn để tránh “ảo chiều” quá mức.
- Có thể giảm dần buff khi đội underdog đã quay lại top 2.

---

## 7) Milestone rewards có điều kiện
### Mục tiêu
- Tạo các “điểm bùng nổ” có thể dự đoán cho người xem.

### Hướng triển khai trong code hiện tại
- Đặt các mốc territory (ví dụ 20/35/50%).
- Khi đạt mốc, cấp thưởng spawn/buff nhưng có `cap` theo đội.
- Track số lần nhận thưởng theo team để tránh spam.

### KPI cần theo dõi
- `milestone_trigger_count_by_team`.
- `post_milestone_swing` (độ đổi territory sau mỗi mốc).

---

## C. Spectator readability (ưu tiên cao)

## 8) HUD xếp hạng trực quan theo thời gian thực
### Mục tiêu
- Người xem đọc được ngay ai đang dẫn, ai đang tăng tốc.

### Nội dung HUD đề xuất
- Top team hiện tại.
- `% territory` từng đội.
- `marble alive` từng đội.
- Momentum `↑ / ↓ / →` theo xu hướng 3–5 giây gần nhất.

### Hook triển khai
- Tận dụng `Main._update_hud()` để thêm ranking + momentum.
- Dùng dữ liệu từ `World.get_territory_ratio_per_team()` và `World.get_alive_marbles_per_team()`.

---

## 9) Hot-zone highlight
### Mục tiêu
- Hướng mắt người xem vào nơi giao tranh thực sự.

### Cách làm
- Mỗi tick, ghi nhận cell đổi chủ.
- Gom cụm khu vực đổi chủ dày trong 2–3 giây gần nhất.
- Vẽ overlay nhấp nháy nhẹ (không che map) trên vùng nóng.

### Hook triển khai
- Mở rộng pipeline repaint tại `World._on_tick()`.
- Vẽ overlay bằng `_draw()` trên `World`.

---

## 10) Camera director nhẹ
### Mục tiêu
- Giảm thời lượng khung hình “trống”, tăng mật độ khoảnh khắc đáng xem.

### Chiến lược camera
- Ưu tiên center vào vùng có 3+ team giáp biên.
- Ưu tiên vùng vừa xảy ra lead change hoặc hot-zone intensity cao.
- Nội suy mượt (lerp) để tránh giật hình.

### Hook triển khai
- Camera logic đặt ở `Main` (điều phối) hoặc module riêng gọi từ `World`.
- Input cho camera: top hot-zone, lead-change event, mật độ marble theo cụm.

---

## Kế hoạch triển khai ngắn hạn (chỉ cho B + C)

### Sprint 1
- Cân bằng snowball (`growth_step`, phase growth).
- Bật underdog buff có cooldown.
- Thêm milestone rewards có cap.

### Sprint 2
- Nâng HUD: ranking + territory + alive + momentum.
- Thêm hot-zone highlight.

### Sprint 3
- Thêm camera director nhẹ theo hot-zone + lead-change.
- Chạy batch seed, đo KPI comeback/readability và chốt preset baseline.

---

## Mapping tới code hiện tại
- Growth/convert: `Marble._on_weapon_body_entered()`.
- Territory/alive stats: `World.get_territory_ratio_per_team()`, `World.get_alive_marbles_per_team()`.
- Tick & event timing: `EscalationDirector._process()`.
- Repaint loop / overlay draw: `World._on_tick()`, `World._draw()`.
- HUD update: `Main._update_hud()`.

Tài liệu này là bản chốt theo yêu cầu mới: **giữ B + C, loại các phương án còn lại**.
