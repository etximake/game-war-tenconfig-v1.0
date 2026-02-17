extends RigidBody2D
class_name Marble

# =========================
# Public stats (per rules)
# (BỎ @export để không trùng với GameConfig)
# =========================
var team_id: int = 0
var move_speed: float = 320.0
var weapon_rotate_speed: float = 8.0
var kill_count: int = 0

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

var _bias_timer: float = 0.0
var _cached_bias_dir: Vector2 = Vector2.ZERO
var _wall_cooldown: float = 0.0

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

# ✅ Weapon tip (B-1)
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


# Optional skin resource
var skin = null

signal team_changed(marble: Marble, new_team: int)

func _ready() -> void:
	can_sleep = false
	sleeping = false
	contact_monitor = true
	max_contacts_reported = 4
	_last_safe_pos = global_position
	_has_safe_pos = true


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
	_reset_dir_timer()
	_bias_timer = 0.0
	_wall_cooldown = 0.0

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
		_desired_velocity = Vector2.ZERO
		_update_skin_label_position()
		return

	if _wall_cooldown > 0.0:
		_wall_cooldown = max(_wall_cooldown - delta, 0.0)

	_update_base_dir(delta)

	_bias_timer -= delta
	if _bias_timer <= 0.0:
		_bias_timer = 1.0 / max(bias_update_hz, 1.0)
		if _wall_cooldown <= 0.0:
			_cached_bias_dir = _compute_bias_dir()
		else:
			_cached_bias_dir = Vector2.ZERO

	var target_dir := base_dir + _cached_bias_dir * bias_strength
	if target_dir.length() < 0.001:
		target_dir = base_dir
	target_dir = target_dir.normalized()

	var t: float = clamp(turn_speed * delta, 0.0, 1.0)
	_move_dir = _move_dir.slerp(target_dir, t).normalized()

	_desired_velocity = _move_dir * move_speed
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
	skin_label.visible = (t != "")

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


func set_team(new_team: int) -> void:
	if team_id == new_team:
		return
	team_id = new_team
	emit_signal("team_changed", self, new_team)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not SIM_RUNNING:
		state.linear_velocity = Vector2.ZERO
		_last_safe_pos = state.transform.origin
		_has_safe_pos = true
		return

	var v := _desired_velocity
	# --- Territory block: core vào lãnh thổ team khác thì bật lại ---
	if territory_block_enabled and territory != null and territory.has_method("world_to_cell") and territory.has_method("get_owner_cell"):
		var pos: Vector2 = state.transform.origin
		var cell: Vector2i = territory.call("world_to_cell", pos)

		# world_to_cell bên TerritoryGrid đã clamp; nhưng vẫn an toàn:
		var owner: int = int(territory.call("get_owner_cell", cell.x, cell.y))

		var is_neutral: bool = (owner < 0)
		var blocked: bool = (owner >= 0 and owner != team_id) or (territory_blocks_neutral and is_neutral)

		if not blocked:
			_last_safe_pos = pos
			_has_safe_pos = true
		else:
			# đưa về vị trí an toàn trước đó
			if _has_safe_pos:
				state.transform = Transform2D(state.transform.get_rotation(), _last_safe_pos)

			# phản xạ vận tốc theo hướng "đi vào vùng cấm"
			var normal: Vector2 = (pos - _last_safe_pos)
			if normal.length() < 0.001:
				normal = -v
			if normal.length() < 0.001:
				normal = Vector2.RIGHT
			normal = normal.normalized()

			if v.length() < 0.001:
				v = (-normal) * territory_push_speed
			else:
				v = v.bounce(normal) * territory_bounce_factor

			# tránh đâm lại liên tục
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

	if v.length() > move_speed:
		v = v.normalized() * move_speed

	state.linear_velocity = v


# ✅ B-1 getter: dùng cho World tick paint theo tip
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


# ✅ FIX SKIN: Resource -> truy cập field trực tiếp (không dùng "in")
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

	for dy in range(-sample_radius_cells, sample_radius_cells + 1):
		for dx in range(-sample_radius_cells, sample_radius_cells + 1):
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
