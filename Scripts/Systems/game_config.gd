extends Resource
class_name GameConfig
# GameConfig là một Resource dùng để gom toàn bộ tham số của màn chơi.
# Ưu điểm: chỉnh trực tiếp trong Inspector, tạo nhiều file .tres cho nhiều “kịch bản” video khác nhau.

# =========================
# 1) Thiết lập team
# =========================

@export var num_teams: int = 1
# Số lượng team tham gia trong màn chơi.
# Lưu ý: nên khớp với số màu trong team_colors.

@export var team_colors: Array[Color] = [
	Color.RED, Color.BLUE, Color.GREEN, Color.WHITE, Color.BLACK, Color.YELLOW
]
# Danh sách màu đại diện cho từng team.
# Quy ước: team_id = 0 dùng Color.RED, team_id = 1 dùng Color.BLUE, ...
# Territory và Marble sẽ lấy màu theo team_id này.

@export var marbles_per_team: int = 1
# Số lượng marble spawn ban đầu cho mỗi team.
# Tổng số marble = num_teams * marbles_per_team.

# =========================
# 2) Chỉ số Marble (đúng theo luật)
# =========================

@export var move_speed: float = 240.0
# Vận tốc tối đa khi marble di chuyển (giới hạn tốc độ).
# Marble tự động di chuyển, không có input người chơi.

@export var weapon_rotate_speed: float = 5.0
# Tốc độ quay của vũ khí quanh tâm core.
# Thường dùng đơn vị radian/giây nếu bạn cộng trực tiếp vào rotation.

@export var initial_size_scale: float = 0.5
# Hệ số kích thước ban đầu của marble.
# size_scale ảnh hưởng trực tiếp:
# - kích thước core (collision shape / sprite)
# - khoảng cách vũ khí quay quanh tâm và phạm vi đánh

@export var growth_step: float = 0.08
# Mỗi lần marble “kill” (chạm vũ khí vào core khác team):
# attacker.size_scale += growth_step
# Đồng thời kill_count của attacker + 1 (kill_count là biến runtime, không nằm trong config)

@export var max_size_scale: float = 2.2
# Giới hạn trên của size_scale.
# Khi tăng size phải clamp để không vượt quá max_size_scale.

@export var capture_radius: float = 72.0
# Bán kính chiếm lãnh thổ của mỗi marble (tính theo world units/pixel).
# Mỗi tick simulation: toàn bộ cell trong bán kính này đổi owner_team theo team của marble.

# =========================
# 3) Territory Grid (lưới lãnh thổ)
# =========================

@export var grid_cell_size: int = 16
# Kích thước mỗi ô vuông của lưới (pixel).
# Ví dụ 16 nghĩa là mỗi cell là hình vuông 16x16.

@export var grid_width: int = 80
# Số lượng ô theo chiều ngang (X).
# Tổng chiều rộng world của map ~ grid_width * grid_cell_size.

@export var grid_height: int = 45
# Số lượng ô theo chiều dọc (Y).
# Tổng chiều cao world của map ~ grid_height * grid_cell_size.

# =========================
# 4) Tham số simulation / kết thúc trận
# =========================

@export var tick_rate: float = 20.0
# Tần suất tick logic của simulation (lần/giây).
# Dùng cho các tác vụ “theo tick” như:
# - chiếm lãnh thổ (capture)
# - kiểm tra điều kiện thắng
# Mục tiêu: ổn định, dễ kiểm soát (không phụ thuộc quá nhiều vào FPS).

@export var win_territory_ratio: float = 0.90
# Ngưỡng thắng theo lãnh thổ: nếu một team chiếm >= 90% tổng số ô thì thắng.

@export var rng_seed: int = 12345
# Seed cho random để tái hiện đúng một trận đấu (phục vụ quay video).
# Nếu bạn set seed cố định, spawn/hướng ngẫu nhiên sẽ lặp lại theo cùng một kịch bản.
