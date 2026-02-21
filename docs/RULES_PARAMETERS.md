# Giải thích tham số 10 rule game

Tài liệu này diễn giải ý nghĩa các tham số rule trong `GameConfig` và cách chúng được code sử dụng.

## Schema chung cho 10 rule

Mỗi rule có 5 tham số chính:

- `enabled`: bật/tắt rule.
- `period_sec`: chu kỳ gọi rule bởi `EscalationDirector` (nếu `<=0` thì không tick).
- `strength`: cường độ tác động (mỗi rule diễn giải khác nhau).
- `cap`: giới hạn trên (hoặc số lần tối đa tùy rule).
- `chance`: xác suất kích hoạt mỗi lần tick (0..1).

## Diễn giải theo từng rule

1. **Rule 1 – speed ramp**
   - `strength`: lượng cộng vào `global_speed_mult` mỗi lần tick.
   - `cap`: trần tối đa của `global_speed_mult`.

2. **Rule 2 – shrink map**
   - `strength`: số ô co vào từ mỗi cạnh sau mỗi tick (làm tròn và tối thiểu 1).
   - `cap`: hiện chưa dùng trực tiếp trong code cho rule này.

3. **Rule 3 – giant spawn (one-shot)**
   - `period_sec`: thời điểm thử spawn, nhưng chỉ spawn 1 lần cho cả trận (do cờ `_giant_spawned`).
   - `strength`: hiện chưa dùng trực tiếp trong code của rule 3.
   - `cap`: hiện chưa dùng trực tiếp trong code của rule 3.
   - `team_mode` (tham số riêng): 0=team 0, 1=random, 2=underdog.
   - `size_mult` (tham số riêng): hệ số scale viên marble spawn thêm.

4. **Rule 4 – death explosion recolor**
   - Không chạy theo `period_sec` mà chạy khi có sự kiện đổi phe sau va chạm.
   - `chance`: xác suất nổ/recolor khi sự kiện xảy ra.
   - `strength/cap/period_sec`: chưa dùng trực tiếp.
   - `rule_4_to_neutral` (tham số riêng): recolor về neutral thay vì team tấn công.

5. **Rule 5 – milestone spawn**
   - `strength`: bước mốc % lãnh thổ (`10` nghĩa là mỗi 10% lãnh thổ).
   - `cap`: số marble cộng thêm tối đa mỗi team.

6. **Rule 6 – underdog buff**
   - `strength`: % cộng tốc độ (hệ số = `1 + strength`).
   - `cap`: trần hệ số buff.
   - `chance`: xác suất áp buff mỗi tick.
   - `period_sec`: vừa là chu kỳ kiểm tra, vừa ảnh hưởng thời gian tồn tại buff (`~75% period`, tối thiểu 1 giây).

7. **Rule 7 – burst speed**
   - `strength`: % tăng tốc global tạm thời (`1 + strength`).
   - `chance`: xác suất kích hoạt burst ở mỗi lần tick.
   - `cap`: hiện chưa dùng trực tiếp trong code rule 7.
   - Burst kéo dài cố định 10 giây.

8. **Rule 8 – edge decay**
   - `strength`: số “vòng biên” tăng thêm sau mỗi lần neutralize (tối thiểu 1).
   - `cap`: hiện chưa dùng trực tiếp trong code rule 8.

9. **Rule 9 – finale**
   - Điều kiện: còn <=2 team sống.
   - `strength`: cộng tốc độ finale (`1 + strength`).
   - `cap`: trần tốc độ finale.
   - Mỗi tick còn gọi `rule_shrink_tick()` để ép trận nhanh hơn.

10. **Rule 10 – random events**
    - `chance`: xác suất bốc event mỗi chu kỳ.
    - Event có thể gọi một trong các rule: speed ramp, burst, shrink, spawn thêm, explosion.
    - `strength/cap`: không tác động trực tiếp tại rule 10, vì tác động phụ thuộc rule con được gọi.

## So sánh nhanh các preset hiện có

- `default`: chỉ để core gameplay, tắt rule 3..10.
- `chaos`: tăng nhịp Rule 1, Rule 7, Rule 10 để trận biến động nhanh.
- `comeback`: tăng Rule 6 và Rule 5 để hỗ trợ lật kèo.
- `boss-heavy`: tăng growth/size, rút ngắn chu kỳ Rule 3 để có “boss marble” sớm.
