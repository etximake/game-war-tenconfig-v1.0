extends Resource
class_name GameConfig

# =========================
# core
# =========================
@export_group("core")
@export var preset_name: String = "default"
@export var num_teams: int = 4
@export var tick_rate: float = 20.0
@export var win_territory_ratio: float = 0.90

# =========================
# territory
# =========================
@export_group("territory")
@export var grid_cell_size: int = 16
@export var grid_width: int = 80
@export var grid_height: int = 45
@export var team_colors: Array[Color] = [
	Color.RED, Color.BLUE, Color.GREEN, Color.WHITE, Color.BLACK, Color.YELLOW
]

# =========================
# marble
# =========================
@export_group("marble")
@export var move_speed: float = 240.0
@export var weapon_rotate_speed: float = 5.0
@export var initial_size_scale: float = 0.5
@export var growth_step: float = 0.08
@export var max_size_scale: float = 2.2
@export var capture_radius: float = 72.0

# =========================
# spawn
# =========================
@export_group("spawn")
@export var marbles_per_team: int = 1
@export var spawn_jitter_cells: float = 2.0
@export var giant_spawn_team_mode: String = "neutral" # neutral|random|underdog
@export var preset_skins: Array[MarbleSkin] = []

# =========================
# rules_10
# Mỗi rule có cấu trúc chuẩn: enabled, period_sec, strength, cap, chance.
# =========================
@export_group("rules_10")

# 1) Speed ramp
@export var rule_1_enabled: bool = true
@export var rule_1_period_sec: float = 30.0
@export var rule_1_strength: float = 0.10
@export var rule_1_cap: float = 3.0
@export var rule_1_chance: float = 1.0

# 2) Shrink map
@export var rule_2_enabled: bool = true
@export var rule_2_period_sec: float = 45.0
@export var rule_2_strength: float = 1.0
@export var rule_2_cap: float = 999.0
@export var rule_2_chance: float = 1.0

# 3) Giant spawn
@export var rule_3_enabled: bool = true
@export var rule_3_period_sec: float = 120.0
@export var rule_3_strength: float = 2.0
@export var rule_3_cap: float = 1.0
@export var rule_3_chance: float = 1.0

# 4) Death explosion recolor
@export var rule_4_enabled: bool = true
@export var rule_4_period_sec: float = 0.0
@export var rule_4_strength: float = 1.0
@export var rule_4_cap: float = 999.0
@export var rule_4_chance: float = 1.0

# 5) Milestone spawn
@export var rule_5_enabled: bool = true
@export var rule_5_period_sec: float = 5.0
@export var rule_5_strength: float = 0.10
@export var rule_5_cap: float = 6.0
@export var rule_5_chance: float = 1.0

# 6) Underdog buff
@export var rule_6_enabled: bool = true
@export var rule_6_period_sec: float = 30.0
@export var rule_6_strength: float = 1.20
@export var rule_6_cap: float = 15.0
@export var rule_6_chance: float = 1.0

# 7) Burst speed
@export var rule_7_enabled: bool = true
@export var rule_7_period_sec: float = 60.0
@export var rule_7_strength: float = 1.40
@export var rule_7_cap: float = 10.0
@export var rule_7_chance: float = 1.0

# 8) Edge decay
@export var rule_8_enabled: bool = true
@export var rule_8_period_sec: float = 20.0
@export var rule_8_strength: float = 1.0
@export var rule_8_cap: float = 999.0
@export var rule_8_chance: float = 1.0

# 9) Finale when 2 teams
@export var rule_9_enabled: bool = true
@export var rule_9_period_sec: float = 1.0
@export var rule_9_strength: float = 1.30
@export var rule_9_cap: float = 3.0
@export var rule_9_chance: float = 1.0

# 10) Random events
@export var rule_10_enabled: bool = true
@export var rule_10_period_sec: float = 120.0
@export var rule_10_strength: float = 1.0
@export var rule_10_cap: float = 999.0
@export var rule_10_chance: float = 1.0

# =========================
# fx
# =========================
@export_group("fx")
@export var explosion_force: float = 400.0
@export var explosion_radius_cells: int = 3
@export var kill_sfx_volume_db: float = -6.0

# =========================
# ui
# =========================
@export_group("ui")
@export var show_hud_by_default: bool = true
@export var hud_compact_mode: bool = true

# =========================
# seed
# rng_seed = 0  -> randomize mỗi run
# rng_seed != 0 -> replay đúng trận
# =========================
@export_group("seed")
@export var rng_seed: int = 0
