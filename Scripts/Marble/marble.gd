extends RigidBody2D
class_name Marble

# =========================
# Public stats (per rules)
# (BỎ @export để không trùng với GameConfig)
# =========================
var team_id: int = 0
var move_speed: float = 320.0
var speed: float:
	get:
		return move_speed
	set(value):
		move_speed = value
@export var accel: float = 2200.0
@export var max_turn_rate: float = 7.5
@export var squash_strength: float = 0.08
@export var squash_time: float = 0.12
var weapon_rotate_speed: float = 8.0
var kill_count: int = 0

var _base_move_speed: float = 320.0
var _base_weapon_rotate_speed: float = 8.0
var _external_speed_mult: float = 1.0
var _temp_boost_mult: float = 1.0
var _temp_boost_left_sec: float = 0.0

# ===== Simulation gate (intro mode) =====
static var SIM_RUNNING: bool = false   # tất cả marble dùng chung

@export var start_on_key_p: bool = true


const SKIN_LABEL_OFFSET_PX: float = 30.0
# -------------------------
# size_scale (backing field) (BỎ @export)
# -------------------------
var _size_scale: float = 1.0
var size_scale: float:
	get:
		return _size_scale
	set(value):
		_size_scale = value
		if is_inside_tree():
			apply_size_scale()

# =========================
# Movement tuning (Step 6)
# =========================
var base_dir: Vector2 = Vector2.RIGHT
var _dir_timer: float = 0.0

@export var base_dir_change_time_min: float = 1.5
@export var base_dir_change_time_max: float = 3.5
@export var base_dir_jitter_deg: float = 12.0  # nhỏ để bớt rung

@export var bias_strength: float = 0.9
@export var sample_radius_cells: int = 1

@export var turn_speed: float = 10.0
@export var bias_update_hz: float = 10.0

var territory: Node = null

# internal movement state
var _move_dir: Vector2 = Vector2.RIGHT
var _desired_velocity: Vector2 = Vector2.ZERO
var _current_velocity: Vector2 = Vector2.ZERO
var _prev_target_dir: Vector2 = Vector2.RIGHT
var _turn_squash_cooldown_left: float = 0.0

var _bias_timer: float = 0.0
var _cached_bias_dir: Vector2 = Vector2.ZERO
var _wall_cooldown: float = 0.0

# Sweep hit state
var _sweep_knockback_vel: Vector2 = Vector2.ZERO
var _sweep_spin_tween: Tween = null
var _knockback_tween: Tween = null
var capture_power_mult: float = 1.0

# =========================
# Node refs (scene structure)
# =========================
@onready var core_shape: CollisionShape2D = $CoreShape
@onready var core_sprite: Sprite2D = $CoreSprite

@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_area: Area2D = $WeaponPivot/Weapon
@onready var weapon_shape: CollisionShape2D = $WeaponPivot/Weapon/WeaponShape
@onready var weapon_sprite: Sprite2D = $WeaponPivot/Weapon/WeaponSprite
@onready var skin_label: Label = $Name

@onready var weapon_tip: Marker2D = get_node_or_null("WeaponPivot/Weapon/WeaponTip")

# =========================
# Cached base values from scene
# =========================
var _cached_base: bool = false

var _base_core_radius: float = 12.0
var _base_weapon_rect_size: Vector2 = Vector2(24.0, 8.0)
var _base_weapon_offset: Vector2 = Vector2(22.0, 0.0)

var _base_core_sprite_scale: Vector2 = Vector2.ONE
var _base_weapon_sprite_scale: Vector2 = Vector2.ONE

@export var territory_block_enabled: bool = true
@export var territory_bounce_factor: float = 0.85
@export var territory_push_speed: float = 80.0
@export var territory_blocks_neutral: bool = false  # giữ FALSE để không kẹt ở neutral

var _last_safe_pos: Vector2 = Vector2.ZERO
var _has_safe_pos: bool = false
var _turn_squash_tween: Tween = null
var _capture_squash_tween: Tween = null
var _visual_scale_mult_value: Vector2 = Vector2.ONE
var _visual_scale_mult: Vector2:
	get:
		return _visual_scale_mult_value
	set(value):
		_visual_scale_mult_value = value
		_apply_visual_scale_multiplier()


# Optional skin resource
var skin = null

signal team_changed(marble: Marble, new_team: int)
signal marble_stuck(node: Marble, pos: Vector2, team: int, is_stuck: bool)

var _territory_immunity_left: float = 0.0
var _stuck_sec: float = 0.0
var _is_sos: bool = false
var _sos_tween: Tween = null
var _orig_label_text: String = ""
# Tween refs để kill trước khi tạo mới (tránh Tween orphan gây lag)
var _pierce_tween: Tween = null
var _power_tween: Tween = null
var _ws_tween: Tween = null
var _rescue_timer: float = 0.0
var _last_pos_check: Vector2 = Vector2.ZERO
var _pos_check_timer: float = 0.0
var _sos_release_timer: float = 0.0  # đếm ngược sau khi giải thoát trước khi xóa Help!

func _ready() -> void:
	can_sleep = false
	sleeping = false
	contact_monitor = true
	max_contacts_reported = 4
	_last_safe_pos = global_position
	_has_safe_pos = true
	_base_move_speed = move_speed
	speed = move_speed
	_base_weapon_rotate_speed = weapon_rotate_speed

	if core_shape and core_shape.shape:
		core_shape.shape = core_shape.shape.duplicate(true)
	if weapon_shape and weapon_shape.shape:
		weapon_shape.shape = weapon_shape.shape.duplicate(true)
		
	set_process_unhandled_input(true)

	_cache_base_from_scene_once()
	_apply_no_tint_visuals()
	apply_size_scale()

	_randomize_base_dir()
	_move_dir = base_dir
	_prev_target_dir = _move_dir
	_current_velocity = _move_dir * move_speed
	_reset_dir_timer()
	_bias_timer = 0.0
	_wall_cooldown = 0.0
	_last_pos_check = global_position
	_pos_check_timer = 0.0

	collision_layer = 1
	collision_mask = 1

	weapon_area.collision_layer = 2
	weapon_area.collision_mask = 1 | 2
	weapon_area.monitoring = true
	weapon_area.monitorable = true

	weapon_area.body_entered.connect(_on_weapon_body_entered)
	weapon_area.area_entered.connect(_on_weapon_area_entered)
	
	if skin_label:
		skin_label.top_level = true
		skin_label.z_index = 100
		skin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# text có thể phụ thuộc skin (spawn/team change)
	_update_skin_label_text()
	call_deferred("_update_skin_label_position")


func _physics_process(delta: float) -> void:
	
	# Weapon vẫn quay dù chưa chạy
	if weapon_pivot:
		weapon_pivot.rotation += weapon_rotate_speed * delta

	# Nếu chưa start -> đứng yên, không update AI dir/bias
	if not SIM_RUNNING:
		_current_velocity = _current_velocity.move_toward(Vector2.ZERO, accel * delta)
		_desired_velocity = Vector2.ZERO
		_update_skin_label_position()
		return

	if _wall_cooldown > 0.0:
		_wall_cooldown = max(_wall_cooldown - delta, 0.0)
	if _turn_squash_cooldown_left > 0.0:
		_turn_squash_cooldown_left = max(_turn_squash_cooldown_left - delta, 0.0)
	if _temp_boost_left_sec > 0.0:
		_temp_boost_left_sec = max(_temp_boost_left_sec - delta, 0.0)
		if _temp_boost_left_sec <= 0.0:
			_temp_boost_mult = 1.0
			_recompute_speed()
	if _territory_immunity_left > 0.0:
		_territory_immunity_left = max(_territory_immunity_left - delta, 0.0)
	if _rescue_timer > 0.0:
		_rescue_timer = max(_rescue_timer - delta, 0.0)

	# =====================================================================
	# STUCK DETECTION: 2 pha (TH1: weapon tu giai thoat, TH2: Help!)
	# =====================================================================
	if SIM_RUNNING:
		_pos_check_timer += delta
		if _pos_check_timer >= 0.2:
			if _stuck_sec > 0.0 or _is_sos:
				# Khi dang stuck/SOS: check land tho truc tiep (bo qua immunity) de biet marble co tu giai thoat khong
				if _is_blocked_by_enemy_territory():
					# Van bi block, chi tang khi chua SOS
					if not _is_sos:
						_stuck_sec += _pos_check_timer
						# Kiem tra lai ngay vi _pos_check_timer se = 0 sau day
				else:
					# Vung xung quanh da duoc weapon quet sang team minh → tu giai thoat
					_stuck_sec = max(_stuck_sec - _pos_check_timer * 3.0, 0.0)
			else:
				# Binh thuong: check displacement de phat hien stuck
				var dist := global_position.distance_to(_last_pos_check)
				if dist < 5.0 and move_speed > 50.0:
					_stuck_sec += _pos_check_timer
				else:
					_stuck_sec = max(_stuck_sec - _pos_check_timer * 2.0, 0.0)

			_last_pos_check = global_position
			_pos_check_timer = 0.0

		# TH2: stuck qua lau (>1.2s), weapon khong tu giai thoat duoc → show Help!
		if _stuck_sec > 1.2 and not _is_sos:
			_set_sos_state(true)
			_sos_release_timer = 0.0
		elif _stuck_sec <= 0.0 and _is_sos:
			if _sos_release_timer <= 0.0:
				_sos_release_timer = 0.2  # giu 0.2s roi moi xoa Help!

	# TH1 + TH2: duy tri immunity de marble khong bi teleport (giu nguyen vi tri mac ket)
	if _stuck_sec > 0.0 or _is_sos:
		_territory_immunity_left = 0.3

	# Dem nguoc release SOS
	if _sos_release_timer > 0.0:
		_sos_release_timer -= delta
		if _sos_release_timer <= 0.0 and _is_sos and _stuck_sec <= 0.0:
			_set_sos_state(false)

	_update_base_dir(delta)

	_bias_timer -= delta
	if _bias_timer <= 0.0:
		_bias_timer = 1.0 / max(bias_update_hz, 1.0)
		if _wall_cooldown <= 0.0:
			_cached_bias_dir = _compute_bias_dir()
		else:
			_cached_bias_dir = Vector2.ZERO

	var target_dir := base_dir
	if _rescue_timer <= 0.0:
		var bias_str := bias_strength
		if App.config != null:
			bias_str = float(App.config.combat_bias_strength)
		target_dir = base_dir + _cached_bias_dir * bias_str
	
	if target_dir.length() < 0.001:
		target_dir = base_dir
	target_dir = target_dir.normalized()

	var current_dir: Vector2 = _move_dir if _move_dir.length() > 0.001 else target_dir
	var angle_delta: float = wrapf(target_dir.angle() - current_dir.angle(), -PI, PI)
	var max_step: float = maxf(max_turn_rate, 0.01) * delta
	var turn_step: float = clampf(angle_delta, -max_step, max_step)
	_move_dir = current_dir.rotated(turn_step).normalized()

	var sharp_turn_ratio: float = absf(angle_delta) / PI
	var eased_speed_ratio: float = lerpf(1.0, 0.82, smoothstep(0.35, 1.0, sharp_turn_ratio))
	var desired_velocity: Vector2 = _move_dir * move_speed * eased_speed_ratio
	_current_velocity = _current_velocity.move_toward(desired_velocity, maxf(accel, 1.0) * delta)
	_desired_velocity = _current_velocity

	var target_changed: bool = _prev_target_dir.dot(target_dir) < 0.90
	var is_hard_turn: bool = absf(angle_delta) > 0.40 and absf(turn_step) >= max_step * 0.8
	if (target_changed or is_hard_turn) and _turn_squash_cooldown_left <= 0.0:
		_play_turn_squash()
		_turn_squash_cooldown_left = clampf(squash_time * 0.65, 0.05, 0.12)
	_prev_target_dir = target_dir

	# Khi marble bi ket (TH1 hoac TH2): giu nguyen vi tri, chi weapon quay
	# Override velocity SAU KHI movement AI da tinh toan xong
	if _stuck_sec > 0.0 or _is_sos:
		_current_velocity = Vector2.ZERO
		_desired_velocity = Vector2.ZERO

	_update_skin_label_position()


func _unhandled_input(event: InputEvent) -> void:
	if not start_on_key_p:
		return
	if SIM_RUNNING:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			SIM_RUNNING = true


func _on_weapon_body_entered(body: Node) -> void:
	if body == self:
		return
	if not (body is Marble):
		return

	var victim := body as Marble
	if victim.team_id == team_id:
		return

	victim.set_team(team_id)
	victim.apply_sweep_hit(global_position)

	kill_count += 1
	if App.config != null:
		size_scale = min(size_scale + float(App.config.growth_step), float(App.config.max_size_scale))
	else:
		size_scale += 0.08

	apply_size_scale()
	KillSfxMgr.play_kill(victim.global_position, size_scale)




func _resource_has_property(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if p.name == prop:
			return true
	return false

func _get_skin_display_name() -> String:
	if skin == null:
		return ""

	if skin is Resource:
		# Ưu tiên biến tự đặt trong MarbleSkin (nếu có)
		if _resource_has_property(skin, "skin_name"):
			var v := str(skin.get("skin_name")).strip_edges()
			if v != "":
				return v

		if _resource_has_property(skin, "display_name"):
			var v2 := str(skin.get("display_name")).strip_edges()
			if v2 != "":
				return v2

		# Fallback: resource_name (set trong Inspector)
		var rn := (skin as Resource).resource_name.strip_edges()
		if rn != "":
			return rn

		# Fallback: tên file .tres
		var rp := (skin as Resource).resource_path
		if rp != "":
			return rp.get_file().get_basename()

	return ""

func _update_skin_label_text() -> void:
	if skin_label == null:
		return
	var t := _get_skin_display_name()
	skin_label.text = t
	skin_label.visible = (t != "" or _is_sos) # Stay visible if SOS

func _update_skin_label_position() -> void:
	if skin_label == null or not skin_label.visible:
		return

	# label không bị xoay theo RigidBody2D
	# top_level = true => label bỏ qua transform cha, ta đặt global_position thủ công
	var y := -(_base_core_radius * size_scale) - SKIN_LABEL_OFFSET_PX

	# canh giữa theo width của label (Control origin ở góc trái trên)
	var pos := global_position + Vector2(0, y)
	pos.x -= skin_label.size.x * 0.5
	skin_label.global_position = pos


func _on_weapon_area_entered(area: Area2D) -> void:
	if area == weapon_area:
		return

	var other_marble := area.get_parent()
	if other_marble is Node2D and other_marble.name == "WeaponPivot":
		other_marble = other_marble.get_parent()

	if not (other_marble is Marble):
		return

	var other := other_marble as Marble
	if other == self:
		return

	var dir := (global_position - other.global_position)
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	var strength: float = 80.0
	apply_impulse(dir * strength)
	other.apply_impulse(-dir * strength)


func cache_base_speed() -> void:
	_base_move_speed = move_speed
	speed = move_speed
	_base_weapon_rotate_speed = weapon_rotate_speed
	_external_speed_mult = 1.0
	_temp_boost_mult = 1.0
	_temp_boost_left_sec = 0.0


func apply_speed_mult(mult: float) -> void:
	_external_speed_mult = max(mult, 0.01)
	_recompute_speed()


func apply_temp_speed_boost(mult: float, duration_sec: float, random_direction_boost_enabled: bool, angle_min_deg: float, angle_max_deg: float) -> void:
	_temp_boost_mult = max(mult, 1.0)
	_temp_boost_left_sec = max(_temp_boost_left_sec, duration_sec)
	if random_direction_boost_enabled:
		_apply_random_direction_offset(angle_min_deg, angle_max_deg)
	_recompute_speed()


func _apply_random_direction_offset(angle_min_deg: float, angle_max_deg: float) -> void:
	var min_deg: float = angle_min_deg if angle_min_deg <= angle_max_deg else angle_max_deg
	var max_deg: float = angle_max_deg if angle_max_deg >= angle_min_deg else angle_min_deg
	var sign := -1.0 if randf() < 0.5 else 1.0
	var angle := deg_to_rad(randf_range(min_deg, max_deg) * sign)
	var ref := _move_dir if _move_dir.length() > 0.001 else base_dir
	if ref.length() <= 0.001:
		ref = Vector2.RIGHT
	base_dir = ref.normalized().rotated(angle)
	_move_dir = base_dir


func _recompute_speed() -> void:
	var final_mult: float = max(_external_speed_mult * _temp_boost_mult, 0.01)
	move_speed = speed * final_mult
	weapon_rotate_speed = _base_weapon_rotate_speed * final_mult


func set_team(new_team: int) -> void:
	if team_id == new_team:
		return
	team_id = new_team
	emit_signal("team_changed", self, new_team)


func _is_territory_owner_blocked(owner: int) -> bool:
	var is_neutral: bool = (owner < 0)
	return (owner >= 0 and owner != team_id) or (territory_blocks_neutral and is_neutral)


# Kiem tra marble co dang nam trong vung lanh tho dich khong (KHONG qua immunity)
# Dung rieng cho stuck detection de biet marble da tu giai thoat chua
func _is_blocked_by_enemy_territory() -> bool:
	if territory == null:
		return false
	if not territory.has_method("world_to_cell") or not territory.has_method("get_owner_cell"):
		return false
	var center_cell: Vector2i = territory.call("world_to_cell", global_position)
	var owner: int = int(territory.call("get_owner_cell", center_cell.x, center_cell.y))
	return _is_territory_owner_blocked(owner)




func _is_position_blocked_by_territory(pos: Vector2) -> bool:
	if _territory_immunity_left > 0.0:
		return false

	if territory == null:
		return false
	if not territory.has_method("world_to_cell") or not territory.has_method("get_owner_cell"):
		return false

	# kiểm tra cả tâm + vòng biên core để dừng ở mép ngoài, không cho tâm lọt sâu vào lãnh thổ địch
	var center_cell: Vector2i = territory.call("world_to_cell", pos)
	var center_owner: int = int(territory.call("get_owner_cell", center_cell.x, center_cell.y))
	if _is_territory_owner_blocked(center_owner):
		return true

	var probe_radius: float = _base_core_radius * size_scale
	var probe_dirs: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.UP,
		Vector2.DOWN,
		Vector2(1.0, 1.0).normalized(),
		Vector2(1.0, -1.0).normalized(),
		Vector2(-1.0, 1.0).normalized(),
		Vector2(-1.0, -1.0).normalized(),
	]

	for d in probe_dirs:
		var probe_pos: Vector2 = pos + d * probe_radius
		var probe_cell: Vector2i = territory.call("world_to_cell", probe_pos)
		var probe_owner: int = int(territory.call("get_owner_cell", probe_cell.x, probe_cell.y))
		if _is_territory_owner_blocked(probe_owner):
			return true

	return false

func apply_sweep_hit(attacker_pos: Vector2) -> void:
	# Cấp quyền miễn nhiễm tạm thời để không kẹt mép
	_territory_immunity_left = 0.6
	
	# 1. Knockback (hất)
	var dir := (global_position - attacker_pos)
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	
	# Bật ra nhanh với lực lớn (ví dụ 600-800)
	var knockback_strength: float = randf_range(600.0, 800.0)
	_sweep_knockback_vel = dir * knockback_strength
	
	if _knockback_tween != null and _knockback_tween.is_valid():
		_knockback_tween.kill()
	_knockback_tween = create_tween()
	_knockback_tween.set_trans(Tween.TRANS_CUBIC)
	_knockback_tween.set_ease(Tween.EASE_OUT)
	# Giảm tốc từ từ trong 0.4s
	_knockback_tween.tween_property(self, "_sweep_knockback_vel", Vector2.ZERO, 0.4)

	# 2. Spin nhỏ
	if _sweep_spin_tween != null and _sweep_spin_tween.is_valid():
		_sweep_spin_tween.kill()
	
	var spin_sign := 1.0 if randf() > 0.5 else -1.0
	var spin_deg := randf_range(20.0, 60.0)
	var spin_rad := deg_to_rad(spin_deg) * spin_sign
	var spin_duration := randf_range(0.3, 0.5)
	
	if core_sprite:
		_sweep_spin_tween = create_tween()
		_sweep_spin_tween.set_trans(Tween.TRANS_QUAD)
		_sweep_spin_tween.set_ease(Tween.EASE_OUT)
		_sweep_spin_tween.tween_property(core_sprite, "rotation", core_sprite.rotation + spin_rad, spin_duration)

	# 3. Squash and Stretch
	_play_sweep_squash()

	# 4. Weapon Pierce & Spin to clear out stuck territory
	if weapon_pivot:
		if _pierce_tween != null and _pierce_tween.is_valid():
			_pierce_tween.kill()
		_pierce_tween = create_tween()
		_pierce_tween.set_trans(Tween.TRANS_QUAD)
		_pierce_tween.set_ease(Tween.EASE_OUT)
		# Spin super fast
		var sweep_spin_dir := 1.0 if randf() > 0.5 else -1.0
		_pierce_tween.tween_property(weapon_pivot, "rotation", weapon_pivot.rotation + PI * 3.0 * sweep_spin_dir, 0.4)
	
	# Boost capture power to guarantee clearing phantom colors
	capture_power_mult = 10.0
	if _power_tween != null and _power_tween.is_valid():
		_power_tween.kill()
	_power_tween = create_tween()
	_power_tween.tween_property(self, "capture_power_mult", 1.0, 0.4)

	# Pierce effect: visually extend the weapon
	if weapon_sprite and weapon_shape and weapon_shape.shape is RectangleShape2D:
		if _ws_tween != null and _ws_tween.is_valid():
			_ws_tween.kill()
		_ws_tween = create_tween()
		_ws_tween.set_trans(Tween.TRANS_ELASTIC)
		_ws_tween.set_ease(Tween.EASE_OUT)
		
		var cur_scale := weapon_sprite.scale
		var tgt_scale := cur_scale
		tgt_scale.x *= 1.8
		
		var rect_shape = weapon_shape.shape as RectangleShape2D
		var cur_size: Vector2 = rect_shape.size
		var tgt_size: Vector2 = cur_size
		tgt_size.x *= 1.8
		
		_ws_tween.tween_property(weapon_sprite, "scale", tgt_scale, 0.1)
		_ws_tween.parallel().tween_property(rect_shape, "size", tgt_size, 0.1)
		
		_ws_tween.tween_property(weapon_sprite, "scale", cur_scale, 0.3)
		_ws_tween.parallel().tween_property(rect_shape, "size", cur_size, 0.3)

func _play_sweep_squash() -> void:
	if not is_inside_tree():
		return
	if _capture_squash_tween != null and _capture_squash_tween.is_valid():
		_capture_squash_tween.kill()
	# Stretch theo chiều hướng bị hất (nếu có_thể, mượn tạm cách uniform hoặc phi uniform)
	_visual_scale_mult = Vector2(1.25, 0.75)  # squash & stretch mạnh hơn một chút
	_capture_squash_tween = create_tween()
	_capture_squash_tween.set_trans(Tween.TRANS_ELASTIC)
	_capture_squash_tween.set_ease(Tween.EASE_OUT)
	_capture_squash_tween.tween_property(self, "_visual_scale_mult", Vector2.ONE, 0.5)

func _set_sos_state(on: bool) -> void:
	_is_sos = on
	if _sos_tween != null and _sos_tween.is_valid():
		_sos_tween.kill()

	if on:
		_orig_label_text = skin_label.text
		skin_label.text = "Help!"
		skin_label.visible = true  # Đảm bảo hiện dù marble không có skin
		skin_label.add_theme_color_override("font_color", Color.WHITE)
		skin_label.add_theme_color_override("font_outline_color", Color.BLACK)
		skin_label.add_theme_constant_override("outline_size", 4)
		
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.RED
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.set_corner_radius_all(4)
		skin_label.add_theme_stylebox_override("normal", sb)
		
		skin_label.pivot_offset = skin_label.size * 0.5
		
		_sos_tween = create_tween().set_loops()
		_sos_tween.tween_property(skin_label, "scale", Vector2(1.3, 1.3), 0.3).set_trans(Tween.TRANS_SINE)
		_sos_tween.tween_property(skin_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_SINE)
		
		# Boost capture power while stuck to help clear nearby territory
		capture_power_mult = 5.0
		
		emit_signal("marble_stuck", self, global_position, team_id, true)
	else:
		skin_label.text = _orig_label_text
		skin_label.remove_theme_color_override("font_color")
		skin_label.remove_theme_color_override("font_outline_color")
		skin_label.remove_theme_constant_override("outline_size")
		skin_label.remove_theme_stylebox_override("normal")
		skin_label.scale = Vector2.ONE
		_update_skin_label_text()
		
		capture_power_mult = 1.0
		
		emit_signal("marble_stuck", self, global_position, team_id, false)

func start_rescue(target_pos: Vector2, duration: float) -> void:
	var dir := (target_pos - global_position)
	if dir.length() > 0.1:
		base_dir = dir.normalized()
		_move_dir = base_dir
		_rescue_timer = duration
		# Also reset dir timer to prevent immediate change after rescue
		_reset_dir_timer()
		_wall_cooldown = duration * 0.5

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not SIM_RUNNING:
		state.linear_velocity = Vector2.ZERO
		_last_safe_pos = state.transform.origin
		_has_safe_pos = true
		return

	var v := _desired_velocity + _sweep_knockback_vel
	# --- Territory block: chặn từ mép core, không cho tâm đi vào vùng cấm ---
	if territory_block_enabled and territory != null and territory.has_method("world_to_cell") and territory.has_method("get_owner_cell"):
		var pos: Vector2 = state.transform.origin
		var dt: float = max(state.step, 1.0 / 240.0)
		var predicted_pos: Vector2 = pos + v * dt

		var blocked_now: bool = _is_position_blocked_by_territory(pos)
		var blocked_next: bool = _is_position_blocked_by_territory(predicted_pos)
		var blocked: bool = blocked_now or blocked_next

		if not blocked:
			_last_safe_pos = pos
			_has_safe_pos = true
		else:
			if _has_safe_pos:
				state.transform = Transform2D(state.transform.get_rotation(), _last_safe_pos)

			var normal: Vector2 = (predicted_pos - _last_safe_pos)
			if normal.length() < 0.001:
				normal = -v
			if normal.length() < 0.001:
				normal = Vector2.RIGHT
			normal = normal.normalized()

			if v.length() < 0.001:
				v = (-normal) * territory_push_speed
			else:
				v = v.bounce(normal) * territory_bounce_factor

			if v.length() > 0.001:
				base_dir = v.normalized()
				_move_dir = base_dir
				_wall_cooldown = 0.25

	var cc := state.get_contact_count()
	if cc > 0:
		for i in range(cc):
			var n: Vector2 = state.get_contact_local_normal(i)
			if v.dot(n) < 0.0:
				v = v.bounce(n)

		if v.length() > 0.001:
			base_dir = v.normalized()
			_move_dir = base_dir
			_wall_cooldown = 0.25

	# Remove maximum limit on knockback or just limit the base velocity
	if _sweep_knockback_vel.length() < 10.0:
		if v.length() > move_speed:
			v = v.normalized() * move_speed
	else:
		# Giới hạn xíu nếu knockback quá to
		if v.length() > move_speed + _sweep_knockback_vel.length():
			v = v.normalized() * (move_speed + _sweep_knockback_vel.length())

	state.linear_velocity = v
	_current_velocity = v


func get_weapon_tip_global_pos() -> Vector2:
	if weapon_tip != null:
		return weapon_tip.global_position
	# fallback an toàn
	if weapon_area != null:
		return weapon_area.global_position
	return global_position


func apply_size_scale() -> void:
	_cache_base_from_scene_once()

	if App.config != null:
		_size_scale = clamp(_size_scale, 0.1, float(App.config.max_size_scale))
	else:
		_size_scale = max(_size_scale, 0.1)

	var s: float = _size_scale

	var core_circle := core_shape.shape as CircleShape2D
	if core_circle:
		core_circle.radius = _base_core_radius * s

	var weapon_rect := weapon_shape.shape as RectangleShape2D
	if weapon_rect:
		weapon_rect.size = _base_weapon_rect_size * s

	if weapon_area:
		weapon_area.position = _base_weapon_offset * s

	if core_sprite:
		core_sprite.scale = _base_core_sprite_scale * s
	if weapon_sprite:
		weapon_sprite.scale = _base_weapon_sprite_scale * s
	_apply_visual_scale_multiplier()

	_apply_no_tint_visuals()
	_update_skin_label_position()


func _cache_base_from_scene_once() -> void:
	if _cached_base:
		return

	var core_circle := core_shape.shape as CircleShape2D
	if core_circle:
		_base_core_radius = core_circle.radius

	var weapon_rect := weapon_shape.shape as RectangleShape2D
	if weapon_rect:
		_base_weapon_rect_size = weapon_rect.size

	if weapon_area:
		_base_weapon_offset = weapon_area.position

	if core_sprite:
		_base_core_sprite_scale = core_sprite.scale
	if weapon_sprite:
		_base_weapon_sprite_scale = weapon_sprite.scale

	_cached_base = true


func _apply_no_tint_visuals() -> void:
	if core_sprite:
		core_sprite.modulate = Color.WHITE
	if weapon_sprite:
		weapon_sprite.modulate = Color.WHITE


func trigger_capture_squash() -> void:
	_play_capture_squash()


func _play_turn_squash() -> void:
	if not is_inside_tree():
		return
	if _turn_squash_tween != null and _turn_squash_tween.is_valid():
		_turn_squash_tween.kill()
	var strength_ratio: float = clampf(squash_strength / 0.08, 0.0, 2.0)
	var stretch: float = lerpf(1.0, 1.08, strength_ratio)
	var squish: float = lerpf(1.0, 0.92, strength_ratio)
	_visual_scale_mult = Vector2(stretch, squish)
	_turn_squash_tween = create_tween()
	_turn_squash_tween.set_trans(Tween.TRANS_QUAD)
	_turn_squash_tween.set_ease(Tween.EASE_OUT)
	_turn_squash_tween.tween_property(self, "_visual_scale_mult", Vector2.ONE, clamp(squash_time, 0.10, 0.16))


func _play_capture_squash() -> void:
	if not is_inside_tree():
		return
	if _capture_squash_tween != null and _capture_squash_tween.is_valid():
		_capture_squash_tween.kill()
	_visual_scale_mult = Vector2(1.06, 1.06)
	_capture_squash_tween = create_tween()
	_capture_squash_tween.set_trans(Tween.TRANS_BACK)
	_capture_squash_tween.set_ease(Tween.EASE_OUT)
	_capture_squash_tween.tween_property(self, "_visual_scale_mult", Vector2.ONE, clamp(squash_time * 0.8, 0.08, 0.12))


func _apply_visual_scale_multiplier() -> void:
	var s: float = size_scale
	if core_sprite:
		core_sprite.scale = _base_core_sprite_scale * s * _visual_scale_mult_value
	if weapon_sprite:
		weapon_sprite.scale = _base_weapon_sprite_scale * s * _visual_scale_mult_value


func apply_skin(p_skin) -> void:
	skin = p_skin
	if skin == null:
		return

	# MarbleSkin Resource fields: core_texture, weapon_texture
	if core_sprite and skin.core_texture:
		core_sprite.texture = skin.core_texture
	if weapon_sprite and skin.weapon_texture:
		weapon_sprite.texture = skin.weapon_texture

	_apply_no_tint_visuals()
	_update_skin_label_text()
	call_deferred("_update_skin_label_position")


func _randomize_base_dir() -> void:
	var a: float = randf() * TAU
	base_dir = Vector2(cos(a), sin(a)).normalized()


func _reset_dir_timer() -> void:
	_dir_timer = randf_range(base_dir_change_time_min, base_dir_change_time_max)


func _update_base_dir(delta: float) -> void:
	if _rescue_timer > 0.0:
		return
	
	_dir_timer -= delta
	if _dir_timer > 0.0:
		return

	var jitter_rad: float = deg_to_rad(base_dir_jitter_deg)
	var da: float = randf_range(-jitter_rad, jitter_rad)
	base_dir = base_dir.rotated(da).normalized()
	_reset_dir_timer()


func _compute_bias_dir() -> Vector2:
	if territory == null:
		return Vector2.ZERO
	if not territory.has_method("world_to_cell"):
		return Vector2.ZERO
	if not territory.has_method("get_owner_cell"):
		return Vector2.ZERO
	if not territory.has_method("cell_to_world"):
		return Vector2.ZERO

	var cell: Vector2i = territory.call("world_to_cell", global_position)

	var sum := Vector2.ZERO
	var count := 0
	
	# Use config if available, otherwise use export defaults
	var radius: int = sample_radius_cells
	var b_strength: float = bias_strength
	
	if App.config != null:
		radius = int(App.config.combat_sample_radius)
		b_strength = float(App.config.combat_bias_strength)

	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue

			var cx := cell.x + dx
			var cy := cell.y + dy

			var cell_owner: int = int(territory.call("get_owner_cell", cx, cy))
			if cell_owner != team_id:
				var world_pos: Vector2 = territory.call("cell_to_world", Vector2i(cx, cy))
				var cs: float = float(App.config.grid_cell_size) if App.config != null else 16.0
				var center: Vector2 = world_pos + Vector2(cs * 0.5, cs * 0.5)

				var v: Vector2 = center - global_position
				if v.length() > 0.001:
					sum += v.normalized()
					count += 1

	if count == 0:
		return Vector2.ZERO
	return sum.normalized()
