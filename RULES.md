# RULES — Luật chơi chuẩn hoá (Godot 4.5 simulation)

## 1) Mục tiêu trận đấu
- Mỗi đội điều khiển các `Marble` để **mở rộng lãnh thổ** bằng cách quét đầu vũ khí lên lưới ô (`TerritoryGrid`).
- Trận đấu kết thúc khi xảy ra **một trong hai điều kiện thắng**:
  1. Chỉ còn 1 đội còn Marble sống (`last_team_alive`).
  2. Một đội chiếm tỉ lệ ô >= `win_territory_ratio` (mặc định 98%, lý do `territory_90`).

## 2) Vòng lặp mô phỏng chuẩn
1. `App` nạp file cấu hình `.tres` vào `GameConfig`.
2. `Main` gọi `World.start_match()`.
3. `World`:
   - reset state,
   - tạo `TerritoryGrid` + tường biên,
   - chia map thành vùng theo số đội,
   - spawn Marble theo `marbles_per_team`,
   - chạy tick theo `tick_rate`.
4. Mỗi tick:
   - lấy `weapon tip` của từng Marble,
   - tô các ô đi qua (Bresenham + thickness),
   - cập nhật buff/tốc độ,
   - kiểm tra win condition.
5. `EscalationDirector` chạy song song theo thời gian thực để kích hoạt 10 rule tăng độ khó.

## 3) Cơ chế cốt lõi
### 3.1 Territory capture
- Đơn vị bản đồ là ô vuông (`grid_cell_size`, `grid_width`, `grid_height`).
- `owner` mỗi ô:
  - `-1`: neutral,
  - `0..num_teams-1`: thuộc đội tương ứng.
- Marble không cần đứng yên để chiếm: chỉ cần đầu vũ khí quét qua ô là repaint theo team.

### 3.2 Combat & chuyển phe
- Khi vũ khí Marble A chạm thân Marble B khác team:
  - B đổi `team_id` thành team của A,
  - A tăng `kill_count`, tăng `size_scale` theo `growth_step` (không vượt `max_size_scale`),
  - phát SFX kill.

### 3.3 Di chuyển & va chạm
- Marble là `RigidBody2D`, tự hành theo hướng nền + bias theo lãnh thổ mục tiêu.
- Có chặn vào lãnh thổ đối thủ (bật `territory_block_enabled`): Marble bị bật ngược/đẩy ra.
- Có tường biên vật lý bao quanh toàn map.

## 4) 10 rule escalation (chuẩn hoá)
Các rule dùng cùng schema trong `GameConfig`: `enabled`, `period_sec`, `strength`, `cap`, `chance`.

1. **Rule 1 – speed ramp**: tăng dần `global_speed_mult` theo chu kỳ.
2. **Rule 2 – shrink map**: thu hẹp vùng chơi hợp lệ từ biên vào trong, ngoài vùng thành neutral. tại vùng này các marble khi quét qua sẽ không có tác dụng mở rộng là một vùng chết để có tác dụng thu hẹp bản đồ, 
nếu marble nằm trên vùng này khi mở rộng sẽ bị chết, loại bỏ khỏi bản đồ.
3. **Rule 3 – giant spawn (one-shot)**: spawn thêm 1 Marble cỡ nhỏ cho neutral/random/underdog team, sau
4. **Rule 4 – death explosion recolor**: khi đổi phe gây xung lực nổ và recolor vùng tròn quanh điểm va chạm.
5. **Rule 5 – milestone spawn**: đội đạt mốc % lãnh thổ sẽ nhận thêm Marble (có `cap`).
6. **Rule 6 – underdog buff**: buff tốc độ tạm thời cho đội yếu thế nhất theo territory.
7. **Rule 7 – burst speed**: kích hoạt speed burst toàn cục trong ~10 giây.
8. **Rule 8 – edge decay**: làm neutral dần theo vòng từ rìa vào trong.
9. **Rule 9 – finale**: còn <=2 đội thì tăng tốc + ép shrink nhanh hơn.
10. **Rule 10 – random events**: định kỳ bốc ngẫu nhiên 1 event (speed/burst/shrink/spawn/explosion).

## 5) Vai trò các file config game
> Các file này đều là preset `GameConfig` dùng để đổi “luật trận” mà không sửa code.

### `Resources/Configs/default_game_config.tres`
- Preset **ổn định/cơ bản** để test gameplay nền.
- Đang tắt nhiều rule escalation (rule 3..10), phù hợp kiểm thử hành vi core (capture, win condition, HUD).

### `Resources/Configs/chaos_game_config.tres`
- Preset **hỗn loạn/tốc độ cao**.
- Tăng số đội, mở rộng map, tăng số Marble mỗi đội, rút ngắn chu kỳ rule để trận biến động mạnh.

### `Resources/Configs/comeback_game_config.tres`
- Preset **ưu tiên cơ chế lật kèo**.
- Nhấn mạnh rule underdog buff + milestone spawn để đội yếu có cơ hội quay lại trận.

### `Resources/Configs/boss-heavy_game_config.tres`
- Preset **thiên về “boss marble”**.
- Tăng scale/growth/cap kích thước và hỗ trợ giant spawn sớm hơn để tạo đơn vị vượt trội.

## 6) Vai trò file hệ thống liên quan
- `Scripts/Systems/game_config.gd`: schema chuẩn cho toàn bộ tham số luật, map, marble, fx, ui, tooling, seed.
- `Scripts/Systems/app.gd`: autoload quản lý preset hiện tại + chuyển preset (`N`).
- `Scripts/Systems/escalation_director.gd`: bộ đếm thời gian và gọi rule tick trong `World`.
- `Scripts/Level/world.gd`: lõi trận đấu (spawn, tick paint, win condition, 10 rules).
- `Scripts/Level/territory_grid.gd`: dữ liệu owner theo ô + vẽ lưới.
- `Scripts/Marble/marble.gd`: logic từng Marble (di chuyển, va chạm, đổi team, skin, scale).
- `Scripts/Level/main.gd`: orchestration scene + HUD + hotkeys.

## 7) Hotkeys vận hành nhanh
- `P`: bắt đầu simulation (nếu đang chờ start).
- `R`: restart match cùng preset.
- `N`: chuyển preset config kế tiếp.
- `K`: kết thúc run ngay (chọn đội đang nhiều territory nhất).
- `H`: bật/tắt HUD.

## 8) Tiêu chuẩn chỉnh luật về sau
- Không sửa code khi chỉ muốn cân bằng gameplay; ưu tiên chỉnh các `.tres` preset.
- Khi thêm rule mới, phải:
  1. thêm field vào `GameConfig`,
  2. thêm lịch tick trong `EscalationDirector`,
  3. thêm implementation ở `World`,
  4. xác nhận tương thích với preset hiện có.
- Giữ tính tái lập bằng `rng_seed != 0` khi cần replay deterministic.
