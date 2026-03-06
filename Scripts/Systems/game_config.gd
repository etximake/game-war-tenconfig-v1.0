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
@export var combat_bias_strength: float = 0.9
@export var combat_sample_radius: int = 6

# =========================
# spawn
# =========================
@export_group("spawn")
@export var marbles_per_team: int = 1

# =========================
# game_rules
# =========================
@export_group("game_rules")

@export_subgroup("rule_1_participant_size")
@export var rule_1_enabled: bool = false
@export var rule_1_marble_names: PackedStringArray = PackedStringArray()
@export var rule_1_team_mult: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

@export_subgroup("rule_2_participant_speed")
@export var rule_2_enabled: bool = false
@export var rule_2_marble_names: PackedStringArray = PackedStringArray()
@export var rule_2_team_mult: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

@export_subgroup("rule_3_participant_count")
@export var rule_3_enabled: bool = false
@export var rule_3_marble_names: PackedStringArray = PackedStringArray()
@export var rule_3_team_mult: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

@export_subgroup("rule_4_spawn_pressure")
@export var rule_4_enabled: bool = false
@export var rule_4_marble_names: PackedStringArray = PackedStringArray()
@export var rule_4_period_sec: float = 10.0
@export var rule_4_small_speed_mult: float = 1.35
@export var rule_4_small_size_mult: float = 0.7
@export var rule_4_stop_fill_ratio: float = 0.96
@export var rule_4_swarm_count_min: int = 1
@export var rule_4_swarm_count_max: int = 1
@export var rule_4_spawn_lifetime_sec: float = 0.0

@export_subgroup("rule_5_speed_rain")
@export var rule_5_enabled: bool = false
@export var rule_5_marble_names: PackedStringArray = PackedStringArray()
@export var rule_5_period_sec: float = 6.0
@export var rule_5_zone_count: int = 6
@export var rule_5_zone_radius_cells: float = 1.0
@export var rule_5_boost_mult: float = 1.7
@export var rule_5_boost_duration_min_sec: float = 2.0
@export var rule_5_boost_duration_max_sec: float = 3.0
@export var rule_5_zone_ttl_sec: float = 4.0
@export var rule_5_random_direction_enabled: bool = true
@export var rule_5_angle_min_deg: float = 30.0
@export var rule_5_angle_max_deg: float = 180.0

# =========================
# automation
# =========================
@export_group("automation")
@export var automation_preset_enabled: bool = false
@export var automation_timeline: Array[GameRuleEvent] = []

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
