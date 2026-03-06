# Giải thích tham số Config & 5 Rule Automation

Tài liệu này diễn giải ý nghĩa các tham số trong `GameConfig` phiên bản mới hỗ trợ **Automation Preset** (thiết lập kịch bản tự động kích hoạt luật theo thời gian) và **Lọc The Tên Bi (Marble Names)***, cùng các thông số lõi của game.

---

## 0. Các Thông Số Cơ Bản (Lõi Game / Bi / Sân Chơi)
Trước khi tới phần luật, đây là các thông số chính cấu tạo nên sức mạnh và quy định trò chơi.

**NHÓM CORE & TERRITORY (Lõi và Bản Đồ)**
- **`num_teams`**: Số lượng quân/phe tối đa tham gia trận đấu (Ví dụ: `6` là 6 phe).
- **`tick_rate`**: Tần suất tính toán áp lực sơn màu trong 1 giây. Càng lớn lấn đất càng nhanh. (Ví dụ: `20.0` là 20 lần mỗi giây).
- **`win_territory_ratio`**: Tỉ lệ lãnh thổ phần trăm phải đạt được để chiến thắng ngay lập tức (Ví dụ: `0.98` nghĩa là chiếm 98% diện tích là thắng).
- **`team_colors`**: Danh sách mã màu để vẽ lên phe lãnh thổ. Cần nhập số lượng màu >= số lượng phe.
- **`grid_cell_size`**: Kích thước mỗi ô vuông bản đồ nhỏ nhất của lõi game (pixel). Góc này ảnh hưởng bản đồ to hay nhỏ (thường là `24`).

**NHÓM MARBLE (Lực Chiến Bi)**
- **`move_speed`**: Tốc độ di chuyển cơ bản của tất cả các viên bi lúc mới sinh ra.
- **`weapon_rotate_speed`**: Tốc độ quay của lưỡi kiếm/vũ khí, rất quan trọng, nó quét sơn càng nhanh thì lấn đất càng lẹ.
- **`initial_size_scale`**: Kích thước gốc tỷ lệ lúc ban đầu của viên bi.
- **`growth_step` / `max_size_scale`**: Hệ số trương phình kích cỡ sau khi ăn được mạng và mức to nhất có thể.
- **`capture_radius`**: Bán kính ảnh hưởng bắt lãnh thổ (quét màu).
- **`combat_bias_strength` / `_sample_radius`**: Các biến ảnh hưởng sức mạnh khi có tranh chấp lãnh thổ lân cận và độ rộng lấy viền tham chiếu.
- **`marbles_per_team`**: Số viên bi sinh ra mỗi phe ngay đầu trận lúc chưa có luật nào nhúng vai.

**NHÓM FX, UI, TOOLING & SEED (Hiệu Ứng, Giao Diện, Tiện ích, Custom Seed)**
- **`explosion_radius_cells` / `_impulse`**: Bán kính và độ giật văng của hiệu ứng nổ.
- **`show_hud` / `hud_update_hz`**: Bật/tắt UI điểm số HUD trên màn hình / Và số lần update hình ảnh UI HUD trên giây.
- **`auto_loop_enabled` / `_delay_sec`**: Sau khi ván kết thúc (Match end), có tính năng tự động loop vây lại và thời gian nghỉ chuyển ván (seconds).
- **`skin_preset` / `preset_skins`**: Mảng chứa các skin áp thẳng vào game thay đổi giao diện các đội.
- **`rng_seed`**: ID bộ tạo bóng ngẫu nhiên. Nếu để `0` -> Trận nào cũng khác nhau, ngẫu nhiên hết mọi thứ. Nếu để dạng 1 con số (Ví dụ như `5` hay `1231`) -> Trận đó sẽ replay chính xác một diễn biến random, dễ dàng tái hiện lại mọi tình huống trận đấu cho mục đích test!

---

## 1. Automation Preset (Kịch bản tự động)

- **`automation_preset_enabled`**: Bật/tắt chế độ tự động. Nếu `true`, game sẽ bỏ qua các check box `enabled` riêng lẻ của từng rule, mà sẽ được điều khiển bởi Timeline thời gian.
- **`automation_timeline`**: Một mảng chứa các mốc sự kiện (`GameRuleEvent`).
  Mỗi sự kiện gồm:
  - `start_time_sec`: Cứ sau từng này thời gian kể từ lúc bắt đầu trận, sẽ châm/kích hoạt luật này.
  - `duration_sec`: Thời gian luật duy trì trước khi tắt đi (Bằng `0` nghĩa là vô hạn).
  - `rule_index`: Chọn kích hoạt luật nào trong 5 luật bên dưới.

---

## 2. Các Luật Cơ Bản (Rules 1 đến 5)

Tất cả các Rule đều có 2 thông số mặc định (trừ khi tự động kích hoạt đè lên):
- **`enabled` (Bật / Tắt bằng tay)**: Dùng để test cố định 1 luật suốt trận (chỉ có tác dụng nếu Automation TẮT).
- **`marble_names` (Lọc theo tên Viên Bi)**: Một mảng chuỗi (ví dụ: `["red_dragon", "blue_shark"]`). Nếu để RỖNG `[]`, luật áp dụng với *tất cả phe*. Nếu điền giá trị nhập tên skin, luật *chỉ áp dụng* cho các phe có loại bi đúng với tên truyền vào.

### Rule 1: Participant Size (Luật Kích Thước)
Thay đổi tỷ lệ kích thước khởi điểm của các viên bi thuộc từng phe khi spawn.
- **`rule_1_team_mult`**: Một mảng quy mô (scale) dựa theo danh sách các phe lúc đầu. Index 0 là phe đầu, 1 là phe kế.
  - *Ví dụ:* `[1.0, 2.5]` sẽ làm phe 0 kích thước bình thường (1.0x), phe 1 bự lên (x2.5).

### Rule 2: Participant Speed (Luật Vận Tốc Nhóm)
Tăng giảm tốc độ gốc và tốc độ xoay vũ khí của nhóm.
- **`rule_2_team_mult`**: Hệ số tốc độ di chuyển và xoáy gốc cho từng team.
  - *Ví dụ:* `[0.7, 2.0]` làm phe 0 chậm bằng 70% mặc định, và phe 1 nhanh x2.

### Rule 3: Participant Count (Luật Cân Quân Số Tỷ Lệ)
Dành cho cân bằng số lượng bầy đàn - nhân hệ số từ số `marbles_per_team` làm tròn lên.
- **`rule_3_team_mult`**: Hệ số số lượng viên bi tham chiến ban đầu.
  - *Ví dụ `marbles_per_team=2`*: Nếu phe 0 là `1.0` -> có 2 bi. Nếu phe 1 là `3.0` -> có 6 bi.

### Rule 4: Spawn Pressure (Bầy Đàn Gia Tăng Áp Lực)
Tạo hiệu ứng thỉnh thoảng triệu hồi các bi "đàn hồi" bé xíu để gây áp lực hoặc giúp nhanh chóng phủ sơn map khi một team quá lép vế, hay lấp vào các lỗ hổng trên grid.
- **`rule_4_period_sec`**: Cứ sau `X` giây lại kích hoạt spawn đàn đệ.
- **`rule_4_swarm_count_min` / `_max`**: Số lượng đệ spawn nhẫu nhiên trong 1 đợt (ví dụ 1 đến 3 con).
- **`rule_4_small_speed_mult` & `_size_mult`**: Tỉ lệ búp tốc / thu nhỏ của đệ con (ví dụ tốc `1.35x` - bự `0.7x`).
- **`rule_4_spawn_lifetime_sec`**: Đệ nhỏ sống bao lâu thì nổ bùm biến mất (`0` là sống vĩnh cửu).
- **`rule_4_stop_fill_ratio`**: Ngưỡng %, nếu đã có 1 team phủ sơn hơn `%` này (vd 0.96 tức là 96% map bị chiếm), rule sẽ ngừng sinh thêm để tránh lag.

### Rule 5: Speed Rain (Mưa Thần Tốc / Flash Hỗn Loạn)
Thả ngẫu nhiên xuống bản đồ các vùng buff vàng, viên bi nào chạm vào sẽ hóa điên, x2 vận tốc, bay lao theo 1 góc độ lung tung trong vài giây.
- **`rule_5_period_sec`**: Bao lâu thì lặp lại thả vùng buff.
- **`rule_5_zone_count`**: Số lượng "vùng sét/buff" quăng ngẫu nhiên trên mặt lưới lãnh thổ mỗi lần tick.
- **`rule_5_zone_radius_cells`**: Bán kính (tính bằng cell ô vuông) bao lớn thì bi phải chạm để lấy buff.
- **`rule_5_boost_mult`**: Tăng bao nhiêu lần tốc độ (vd x`1.7`).
- **`rule_5_boost_duration_min_sec` / `_max_sec`**: Kéo dài khoảng bao nhiêu giây thì hết hóa Chaos.
- **`rule_5_zone_ttl_sec`**: Khu vực buff nằm trên grid đợi bi ủi vô được tồn tại bao lâu (vd `4` giây rồi tự tiêu).
- **`rule_5_random_direction_enabled` / `_angle_deg`**: Khi dẫm phải, có quặt ngẫu nhiên một góc (min/max độ) hay không. (Ví dụ 30 tới 180 độ).
