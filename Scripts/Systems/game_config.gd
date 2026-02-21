extends Resource
class_name GameConfig

# =========================
# core
# =========================
@export_group("core")
@export var preset_name: String = "default"
@export var num_teams: int = 4
@export var tick_rate: float = 20.0
@export var win_territory_ratio: float = 0.98

# =========================
# territory
# =========================
@export_group("territory")
@export var team_colors: Array[Color] = [
	Color.RED,
	Color.BLUE,
	Color.GREEN,
	Color.YELLOW,
	Color(1.0, 0.0, 1.0, 1.0),
	Color.CYAN,
	Color.WHITE,
	Color(1.0, 0.5, 0.0, 1.0)
]
@export var grid_cell_size: int = 16
@export var grid_width: int = 80
@export var grid_height: int = 45

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

# =========================
# rules_10
# Cấu trúc chuẩn mỗi rule: enabled, period_sec, strength, cap, chance
# =========================
@export_group("rules_10")
@export_subgroup("rule_1_speed_ramp")
@export var rule_1_enabled: bool = true
@export var rule_1_period_sec: float = 20.0
@export var rule_1_strength: float = 0.08
@export var rule_1_cap: float = 2.0
@export var rule_1_chance: float = 1.0

@export_subgroup("rule_2_shrink_map")
@export var rule_2_enabled: bool = true
@export var rule_2_period_sec: float = 30.0
@export var rule_2_strength: float = 1.0
@export var rule_2_cap: float = 999.0
@export var rule_2_chance: float = 1.0

@export_subgroup("rule_3_giant_spawn")
@export var rule_3_enabled: bool = true
@export var rule_3_period_sec: float = 180.0
@export var rule_3_strength: float = 1.0
@export var rule_3_cap: float = 1.0
@export var rule_3_chance: float = 1.0
@export var rule_3_team_mode: int = 2 # 0=neutral, 1=random, 2=underdog
@export var rule_3_size_mult: float = 2.0

@export_subgroup("rule_4_death_explosion_recolor")
@export var rule_4_enabled: bool = true
@export var rule_4_period_sec: float = 0.0
@export var rule_4_strength: float = 1.0
@export var rule_4_cap: float = 999.0
@export var rule_4_chance: float = 1.0
@export var rule_4_to_neutral: bool = false

@export_subgroup("rule_5_milestone_spawn")
@export var rule_5_enabled: bool = true
@export var rule_5_period_sec: float = 2.0
@export var rule_5_strength: float = 10.0
@export var rule_5_cap: float = 5.0
@export var rule_5_chance: float = 1.0

@export_subgroup("rule_6_underdog_buff")
@export var rule_6_enabled: bool = true
@export var rule_6_period_sec: float = 30.0
@export var rule_6_strength: float = 0.25
@export var rule_6_cap: float = 2.0
@export var rule_6_chance: float = 1.0

@export_subgroup("rule_7_burst_speed")
@export var rule_7_enabled: bool = true
@export var rule_7_period_sec: float = 45.0
@export var rule_7_strength: float = 0.6
@export var rule_7_cap: float = 10.0
@export var rule_7_chance: float = 1.0

@export_subgroup("rule_8_edge_decay")
@export var rule_8_enabled: bool = true
@export var rule_8_period_sec: float = 8.0
@export var rule_8_strength: float = 1.0
@export var rule_8_cap: float = 999.0
@export var rule_8_chance: float = 1.0

@export_subgroup("rule_9_finale")
@export var rule_9_enabled: bool = true
@export var rule_9_period_sec: float = 1.0
@export var rule_9_strength: float = 0.5
@export var rule_9_cap: float = 3.0
@export var rule_9_chance: float = 1.0

@export_subgroup("rule_10_random_events")
@export var rule_10_enabled: bool = true
@export var rule_10_period_sec: float = 120.0
@export var rule_10_strength: float = 1.0
@export var rule_10_cap: float = 999.0
@export var rule_10_chance: float = 1.0

# =========================
# fx
# =========================
@export_group("fx")
@export var explosion_radius_cells: int = 3
@export var explosion_impulse: float = 250.0

# =========================
# ui
# =========================
@export_group("ui")
@export var show_hud: bool = true
@export var hud_update_hz: float = 4.0

# =========================
# content
# =========================

# =========================
# tooling
# =========================
@export_group("tooling")
@export var auto_loop_enabled: bool = true
@export var auto_loop_delay_sec: float = 2.0

@export_group("content")
@export var skin_preset: String = "default"
@export var preset_skins: Array[MarbleSkin] = []

# =========================
# seed
# 0 => randomize mỗi run; !=0 => replay deterministic
# =========================
@export_group("seed")
@export var rng_seed: int = 0
