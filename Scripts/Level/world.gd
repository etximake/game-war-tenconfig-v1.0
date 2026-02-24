extends Node2D

var config: GameConfig
var grid: Node2D
var marbles: Array[Marble] = []

var tick_timer: Timer
var bounds: StaticBody2D = null

# GIỮ biến này để không phá scene, nhưng từ giờ sẽ sync theo config.num_teams
@export_range(2, 10, 2) var team_count: int = 6

@export var available_skins: Array[MarbleSkin] = []

# ✅ độ dày vệt paint theo tip (0: 1 cell, 1: 3 cell)
@export_range(0, 1, 1) var paint_thickness: int = 1

@onready var GridScene: PackedScene = preload("res://Scenes/Level/TerritoryGrid.tscn")
@onready var MarbleScene: PackedScene = preload("res://Scenes/Marble/Marble.tscn")
@onready var EscalationDirectorScript: Script = preload("res://Scripts/Systems/escalation_director.gd")

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

signal match_ended(winner_team: int, reason: String, territory_ratio: float)
var _last_tip_cell_by_id: Dictionary = {}  # key: instance_id, value: Vector2i

var _match_over: bool = false
@export var reset_delay: float = 2.0

var escalation_director: EscalationDirector = null
var global_speed_mult: float = 1.0
var burst_mult: float = 1.0
var burst_until_sec: float = 0.0
var finale_speed_mult: float = 1.0
var team_buff_mult: Dictionary = {}
var team_buff_until_sec: Dictionary = {}
var _match_time_sec: float = 0.0
var _giant_spawned: bool = false
var _play_min_cell: Vector2i = Vector2i.ZERO
var _play_max_cell: Vector2i = Vector2i.ZERO
var _edge_decay_ring: int = 0
var _milestone_count_by_team: Dictionary = {}
var _extra_spawned_by_team: Dictionary = {}
var _speed_rain_zones: Array[Dictionary] = []
var _mini_swarm_ids: Dictionary = {}


func start_match() -> void:
	print("World.start_match() called")

	config = App.config
	if config == null:
		push_error("World: App.config is null")
		return

	_match_over = false

	# ✅ FIX: sync team_count theo config.num_teams (không dùng hardcode 6 nữa)
	team_count = int(config.num_teams)
	if team_count < 2:
		push_error("World: config.num_teams must be >= 2")
		return
	if config.team_colors.size() < team_count:
		push_error("World: Not enough team_colors to run (need >= num_teams).")
		return

	if int(config.rng_seed) != 0:
		rng.seed = int(config.rng_seed)
	else:
		rng.randomize()

	_clear_previous_match()
	_play_min_cell = Vector2i(0, 0)
	_play_max_cell = Vector2i(config.grid_width - 1, config.grid_height - 1)
	_edge_decay_ring = 0

	_spawn_grid()
	_spawn_bounds()

	_load_preset_skins_from_config()
	_apply_team_skin_colors_to_grid()

	_seed_territory_regions(team_count)
	_milestone_count_by_team.clear()
	_extra_spawned_by_team.clear()
	for t in range(team_count):
		_milestone_count_by_team[t] = 0
		_extra_spawned_by_team[t] = 0

	# ✅ FIX: spawn theo marbles_per_team (không còn 1 per region)
	_spawn_marbles_by_config(team_count, int(config.marbles_per_team))

	_setup_tick_timer()
	_setup_escalation_director()
	_apply_speed_all()


func _physics_process(_delta: float) -> void:
	if config == null:
		return
	if marbles.is_empty() and _speed_rain_zones.is_empty():
		return
	_update_speed_rain(_delta)



func _setup_escalation_director() -> void:
	if escalation_director and is_instance_valid(escalation_director):
		escalation_director.queue_free()

	escalation_director = EscalationDirectorScript.new() as EscalationDirector
	if escalation_director == null:
		return
	escalation_director.name = "EscalationDirector"
	add_child(escalation_director)
	escalation_director.setup(self)


# =========================
# Step 7 (B-3): Tick paint theo WEAPON TIP + batch (B-2)
# =========================
func _setup_tick_timer() -> void:
	if tick_timer and is_instance_valid(tick_timer):
		tick_timer.queue_free()

	tick_timer = Timer.new()
	tick_timer.name = "TickTimer"
	tick_timer.one_shot = false
	tick_timer.autostart = true
	tick_timer.wait_time = 1.0 / float(config.tick_rate)
	add_child(tick_timer)

	tick_timer.timeout.connect(_on_tick)


# Hook trung tâm 1: theo thời gian (tick timer)
func _on_tick() -> void:
	if not is_instance_valid(grid):
		return
	if marbles.is_empty():
		return

	# Godot 4.x: không dùng Array[Array[Vector2i]]
	var paint_map: Array = []
	paint_map.resize(team_count)
	for t in range(team_count):
		var a: Array[Vector2i] = []
		paint_map[t] = a

	for m in marbles:
		if not is_instance_valid(m):
			continue

		var t: int = int(m.team_id)
		if t < 0 or t >= team_count:
			continue

		var cells := _cells_to_paint_for_marble(m)
		if not cells.is_empty():
			var filtered_cells: Array[Vector2i] = []
			for c in cells:
				if _is_inside_play_rect(c):
					filtered_cells.append(c)
			if not filtered_cells.is_empty():
				(paint_map[t] as Array[Vector2i]).append_array(filtered_cells)

	# batch paint theo team, redraw 1 lần/team
	for t in range(team_count):
		var arr := paint_map[t] as Array[Vector2i]
		if arr.is_empty():
			continue
		grid.call("set_owner_cells_batch", arr, t)

	_match_time_sec += tick_timer.wait_time if tick_timer else (1.0 / max(config.tick_rate, 1.0))
	_update_speed_state_timers()

	if not _match_over:
		_check_win_conditions()


func _draw() -> void:
	if config == null:
		return
	if _speed_rain_zones.is_empty():
		return
	var radius_px: float = float(config.grid_cell_size) * max(float(config.rule_3_zone_radius_cells), 0.5)
	for zone in _speed_rain_zones:
		var p: Vector2 = zone.get("pos", Vector2.ZERO)
		var alpha: float = clamp(float(zone.get("ttl", 0.0)) / max(float(config.rule_3_zone_ttl_sec), 0.1), 0.25, 1.0)
		draw_circle(p, radius_px, Color(1.0, 1.0, 0.6, 0.16 * alpha))
		draw_circle(p, radius_px * 0.45, Color(1.0, 1.0, 0.8, 0.35 * alpha))

	
func _cells_to_paint_for_marble(m: Marble) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	var tip_pos: Vector2 = m.get_weapon_tip_global_pos()
	var cur: Vector2i = grid.call("world_to_cell", tip_pos)

	var id := m.get_instance_id()
	if _last_tip_cell_by_id.has(id):
		var prev: Vector2i = _last_tip_cell_by_id[id]
		# paint toàn bộ cell trên đoạn prev -> cur (không hở nét)
		cells.append_array(_bresenham_cells(prev, cur))
	else:
		cells.append(cur)

	_last_tip_cell_by_id[id] = cur

	# optional thickness: thêm 2 ô lân cận để nét dày hơn
	if paint_thickness > 0:
		var v: Vector2 = m.linear_velocity
		var dir: Vector2 = v.normalized() if v.length() > 0.001 else Vector2.RIGHT
		if abs(dir.x) >= abs(dir.y):
			cells.append(cur + Vector2i(0, 1))
			cells.append(cur + Vector2i(0, -1))
		else:
			cells.append(cur + Vector2i(1, 0))
			cells.append(cur + Vector2i(-1, 0))

	return cells

func _bresenham_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y

	var dx: int = abs(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -abs(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy

	while true:
		result.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

	return result



func _check_win_conditions() -> void:
	var alive_counts: Array[int] = []
	alive_counts.resize(team_count)
	for i in range(team_count):
		alive_counts[i] = 0

	for m in marbles:
		if not is_instance_valid(m):
			continue
		var t: int = int(m.team_id)
		if t >= 0 and t < team_count:
			alive_counts[t] += 1

	var alive_teams: Array[int] = []
	for t in range(team_count):
		if alive_counts[t] > 0:
			alive_teams.append(t)

	if alive_teams.size() == 1:
		_end_match(alive_teams[0], "last_team_alive", 0.0)
		return

	var total_cells: int = int(config.grid_width * config.grid_height)
	if total_cells <= 0:
		return

	var owner_counts: Array[int] = []
	owner_counts.resize(team_count)
	for i in range(team_count):
		owner_counts[i] = 0

	for y in range(config.grid_height):
		for x in range(config.grid_width):
			var owner: int = int(grid.call("get_owner_cell", x, y))
			if owner >= 0 and owner < team_count:
				owner_counts[owner] += 1

	for t in range(team_count):
		var ratio: float = float(owner_counts[t]) / float(total_cells)
		if ratio >= float(config.win_territory_ratio):
			_end_match(t, "territory_90", ratio)
			return


# Hook trung tâm 3: kết thúc trận
func _end_match(winner_team: int, reason: String, ratio: float) -> void:
	if _match_over:
		return
	_match_over = true
	winner_team = clamp(winner_team, 0, max(team_count - 1, 0))

	if tick_timer and is_instance_valid(tick_timer):
		tick_timer.stop()
	if escalation_director and is_instance_valid(escalation_director):
		escalation_director.set_process(false)

	for m in marbles:
		if not is_instance_valid(m):
			continue
		m.sleeping = true
		m.linear_velocity = Vector2.ZERO
		m.angular_velocity = 0.0

	var seed_value: int = int(config.rng_seed) if config != null else 0
	var seed_text: String = "random" if seed_value == 0 else str(seed_value)
	var preset_name: String = config.preset_name if config != null else "unknown"
	print("MATCH_RESULT winner=%d reason=%s ratio=%.4f seed=%s duration=%.2fs preset=%s" % [winner_team, reason, ratio, seed_text, _match_time_sec, preset_name])

	emit_signal("match_ended", winner_team, reason, ratio)
	_reset_after_delay()


func _reset_after_delay() -> void:
	var should_loop: bool = config != null and bool(config.auto_loop_enabled)
	if not should_loop:
		return

	var loop_delay: float = reset_delay
	if config != null:
		loop_delay = max(0.1, float(config.auto_loop_delay_sec))

	var t := Timer.new()
	t.one_shot = true
	t.wait_time = loop_delay
	add_child(t)
	t.timeout.connect(func():
		t.queue_free()
		start_match()
	)
	t.start()


func force_end_run() -> void:
	if _match_over:
		return
	if config == null:
		return
	var counts := get_territory_count_per_team()
	if counts.is_empty():
		return
	var best_team: int = 0
	var best_cells: int = -1
	for t in range(team_count):
		var c: int = int(counts[t])
		if c > best_cells:
			best_cells = c
			best_team = t
	var total: float = float(max(config.grid_width * config.grid_height, 1))
	var ratio: float = float(best_cells) / total
	_end_match(best_team, "manual_end_run", ratio)


# =========================
# GIỮ NGUYÊN: capture cũ (không dùng nữa)
# =========================
func _capture_for_marble(m: Marble, radius_cells: int, radius_px: float) -> bool:
	var team: int = int(m.team_id)
	var center_cell: Vector2i = grid.call("world_to_cell", m.global_position)

	var changed: bool = false
	var cs: float = float(config.grid_cell_size)

	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var c := Vector2i(center_cell.x + dx, center_cell.y + dy)
			var world_pos: Vector2 = grid.call("cell_to_world", c)
			var cell_center: Vector2 = world_pos + Vector2(cs * 0.5, cs * 0.5)

			if cell_center.distance_to(m.global_position) > radius_px:
				continue

			var current_owner: int = int(grid.call("get_owner_cell", c.x, c.y))
			if current_owner != team:
				grid.call("set_owner_cell", c.x, c.y, team, false)
				changed = true

	return changed


# =========================
# Spawn / Clear
# =========================
func _clear_previous_match() -> void:
	for m in marbles:
		if is_instance_valid(m):
			m.queue_free()
	marbles.clear()

	if is_instance_valid(grid):
		grid.queue_free()
		grid = null

	if is_instance_valid(bounds):
		bounds.queue_free()
		bounds = null

	if tick_timer and is_instance_valid(tick_timer):
		tick_timer.queue_free()
		tick_timer = null

	if escalation_director and is_instance_valid(escalation_director):
		escalation_director.reset_state()
		escalation_director.queue_free()
	escalation_director = null

	global_speed_mult = 1.0
	burst_mult = 1.0
	burst_until_sec = 0.0
	finale_speed_mult = 1.0
	team_buff_mult.clear()
	team_buff_until_sec.clear()
	_match_time_sec = 0.0
	_giant_spawned = false
	_play_min_cell = Vector2i.ZERO
	_play_max_cell = Vector2i.ZERO
	_edge_decay_ring = 0
	_milestone_count_by_team.clear()
	_extra_spawned_by_team.clear()
	_speed_rain_zones.clear()
	_mini_swarm_ids.clear()
	
	_last_tip_cell_by_id.clear()



func _spawn_grid() -> void:
	grid = GridScene.instantiate()
	add_child(grid)
	grid.call("setup", config)


func _spawn_bounds() -> void:
	var map_w: float = float(config.grid_width * config.grid_cell_size)
	var map_h: float = float(config.grid_height * config.grid_cell_size)
	var t: float = float(config.grid_cell_size) * 2.0

	bounds = StaticBody2D.new()
	bounds.name = "Bounds"
	add_child(bounds)

	_make_wall(bounds, "Top",    Vector2(map_w * 0.5, -t * 0.5),         Vector2(map_w + 2.0 * t, t))
	_make_wall(bounds, "Bottom", Vector2(map_w * 0.5, map_h + t * 0.5),  Vector2(map_w + 2.0 * t, t))
	_make_wall(bounds, "Left",   Vector2(-t * 0.5, map_h * 0.5),         Vector2(t, map_h + 2.0 * t))
	_make_wall(bounds, "Right",  Vector2(map_w + t * 0.5, map_h * 0.5),  Vector2(t, map_h + 2.0 * t))

	bounds.collision_layer = 1
	bounds.collision_mask = 1


func _make_wall(parent: Node, wall_name: String, pos: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	cs.name = wall_name
	cs.position = pos

	var rect := RectangleShape2D.new()
	rect.size = size

	cs.shape = rect
	parent.add_child(cs)


func _compute_layout(n: int) -> Vector2i:
	var cols: int = int(ceil(sqrt(float(n))))
	var rows: int = int(ceil(float(n) / float(cols)))
	return Vector2i(cols, rows)


func _build_regions_in_cells(n: int) -> Array[Rect2i]:
	var layout := _compute_layout(n)
	var cols: int = layout.x
	var rows: int = layout.y

	var W: int = config.grid_width
	var H: int = config.grid_height

	var base_w: int = int(floor(float(W) / float(cols)))
	var rem_w: int = W % cols
	var base_h: int = int(floor(float(H) / float(rows)))
	var rem_h: int = H % rows

	var regions: Array[Rect2i] = []
	regions.resize(n)

	var y0: int = 0
	for r in range(rows):
		var h: int = base_h + (1 if r < rem_h else 0)
		var x0: int = 0
		for c in range(cols):
			var w: int = base_w + (1 if c < rem_w else 0)
			var idx: int = r * cols + c
			if idx < n:
				regions[idx] = Rect2i(x0, y0, w, h)
			x0 += w
		y0 += h

	return regions


func _seed_territory_regions(n: int) -> void:
	var regions := _build_regions_in_cells(n)

	for team in range(n):
		var rect: Rect2i = regions[team]
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				grid.call("set_owner_cell", x, y, team, false)

	grid.queue_redraw()


# ✅ NEW: spawn theo marbles_per_team (không xóa hàm spawn cũ)
func _spawn_marbles_by_config(n: int, marbles_per_team: int) -> void:
	var regions := _build_regions_in_cells(n)
	var cs: float = float(config.grid_cell_size)
	marbles_per_team = max(1, marbles_per_team)

	for team in range(n):
		var rect: Rect2i = regions[team]
		var cx: int = rect.position.x + int(floor(float(rect.size.x) * 0.5))
		var cy: int = rect.position.y + int(floor(float(rect.size.y) * 0.5))
		var base_pos: Vector2 = grid.call("cell_to_world", Vector2i(cx, cy)) + Vector2(cs * 0.5, cs * 0.5)

		for i in range(marbles_per_team):
			var m := MarbleScene.instantiate() as Marble
			add_child(m)

			var jx: float = rng.randf_range(-cs * 2.0, cs * 2.0)
			var jy: float = rng.randf_range(-cs * 2.0, cs * 2.0)
			m.position = base_pos + Vector2(jx, jy)

			m.team_id = clamp(team, 0, team_count - 1)
			m.move_speed = float(config.move_speed)
			m.weapon_rotate_speed = float(config.weapon_rotate_speed)
			m.size_scale = float(config.initial_size_scale)
			m.cache_base_speed()

			m.territory = grid

			if available_skins.size() > 0:
				var skin_idx: int = team % available_skins.size()
				m.apply_skin(available_skins[skin_idx])

			marbles.append(m)
			m.team_changed.connect(_on_marble_team_changed)


# =========================
# GIỮ NGUYÊN: spawn cũ (1 per region) (không dùng nữa)
# =========================
func _spawn_one_marble_per_region(n: int) -> void:
	var regions := _build_regions_in_cells(n)
	var cs: float = float(config.grid_cell_size)

	for team in range(n):
		var rect: Rect2i = regions[team]
		var cx: int = rect.position.x + int(floor(float(rect.size.x) * 0.5))
		var cy: int = rect.position.y + int(floor(float(rect.size.y) * 0.5))
		var pos: Vector2 = grid.call("cell_to_world", Vector2i(cx, cy))
		pos += Vector2(cs * 0.5, cs * 0.5)

		var m := MarbleScene.instantiate() as Marble
		add_child(m)
		m.position = pos

		m.team_id = clamp(team, 0, team_count - 1)
		m.move_speed = float(config.move_speed)
		m.weapon_rotate_speed = float(config.weapon_rotate_speed)
		m.size_scale = float(config.initial_size_scale)
		m.cache_base_speed()

		m.territory = grid

		if available_skins.size() > 0:
			var skin_idx: int = team % available_skins.size()
			m.apply_skin(available_skins[skin_idx])

		marbles.append(m)
		m.team_changed.connect(_on_marble_team_changed)


# Hook trung tâm 2: marble đổi team
func _on_marble_team_changed(marble: Marble, new_team: int) -> void:
	if not is_instance_valid(marble):
		return
	var safe_team: int = clamp(new_team, 0, team_count - 1)

	if available_skins.size() == 0:
		return
	var idx := safe_team % available_skins.size()
	marble.apply_skin(available_skins[idx])


func _update_speed_state_timers() -> void:
	var changed: bool = false

	if burst_mult > 1.0 and _match_time_sec >= burst_until_sec:
		burst_mult = 1.0
		changed = true

	for team in team_buff_until_sec.keys():
		var until_sec: float = float(team_buff_until_sec[team])
		if _match_time_sec >= until_sec and float(team_buff_mult.get(team, 1.0)) != 1.0:
			team_buff_mult[team] = 1.0
			changed = true

	if changed:
		_apply_speed_all()


func _apply_speed_all() -> void:
	for m in marbles:
		if not is_instance_valid(m):
			continue
		var team_mult: float = float(team_buff_mult.get(int(m.team_id), 1.0))
		var final_mult: float = global_speed_mult * burst_mult * finale_speed_mult * team_mult
		m.apply_speed_mult(final_mult)


func get_alive_marbles_per_team() -> Array[int]:
	var alive: Array[int] = []
	alive.resize(team_count)
	for i in range(team_count):
		alive[i] = 0

	for m in marbles:
		if not is_instance_valid(m):
			continue
		var t: int = int(m.team_id)
		if t >= 0 and t < team_count:
			alive[t] += 1
	return alive


func get_alive_team_count() -> int:
	var alive := get_alive_marbles_per_team()
	var c: int = 0
	for v in alive:
		if int(v) > 0:
			c += 1
	return c


func get_underdog_team_by_marbles() -> int:
	var alive := get_alive_marbles_per_team()
	var min_team: int = -1
	var min_count: int = 999999
	for t in range(team_count):
		var c: int = int(alive[t])
		if c <= 0:
			continue
		if c < min_count:
			min_count = c
			min_team = t
	return min_team


func get_territory_count_per_team() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(team_count)
	for i in range(team_count):
		counts[i] = 0
	if not is_instance_valid(grid):
		return counts

	for y in range(config.grid_height):
		for x in range(config.grid_width):
			var owner: int = int(grid.call("get_owner_cell", x, y))
			if owner >= 0 and owner < team_count:
				counts[owner] += 1
	return counts


func get_territory_ratio_per_team() -> Array[float]:
	var counts := get_territory_count_per_team()
	var ratios: Array[float] = []
	ratios.resize(team_count)
	var total: float = float(max(config.grid_width * config.grid_height, 1))
	for t in range(team_count):
		ratios[t] = float(counts[t]) / total
	return ratios


func get_underdog_team() -> int:
	var ratios := get_territory_ratio_per_team()
	var min_team: int = -1
	var min_ratio: float = 99999.0
	for t in range(team_count):
		var r: float = float(ratios[t])
		if r < min_ratio:
			min_ratio = r
			min_team = t
	return min_team


func _is_inside_play_rect(c: Vector2i) -> bool:
	if not _play_rect_valid():
		return false
	return c.x >= _play_min_cell.x and c.x <= _play_max_cell.x and c.y >= _play_min_cell.y and c.y <= _play_max_cell.y


func _play_rect_valid() -> bool:
	return _play_max_cell.x >= _play_min_cell.x and _play_max_cell.y >= _play_min_cell.y


func _neutralize_outside_play_rect() -> void:
	if not is_instance_valid(grid):
		return
	if not _play_rect_valid():
		return
	var cells: Array[Vector2i] = []
	for y in range(config.grid_height):
		for x in range(config.grid_width):
			if x < _play_min_cell.x or x > _play_max_cell.x or y < _play_min_cell.y or y > _play_max_cell.y:
				cells.append(Vector2i(x, y))
	if not cells.is_empty():
		grid.call("set_owner_cells_batch", cells, TerritoryGrid.OWNER_NEUTRAL)


func _clamp_marbles_to_play_rect() -> void:
	if not _play_rect_valid() or not is_instance_valid(grid):
		return
	var cs: float = float(config.grid_cell_size)
	var hard_min_pos: Vector2 = grid.call("cell_to_world", _play_min_cell) + Vector2(cs * 0.5, cs * 0.5)
	var hard_max_pos: Vector2 = grid.call("cell_to_world", _play_max_cell) + Vector2(cs * 0.5, cs * 0.5)

	# đặt điểm clamp lệch vào trong một chút để marble thoát góc ổn định,
	# tránh bị kẹt tại đúng biên shrink do clamp lặp theo frame.
	var inset: float = max(cs * 0.35, 2.0)
	var min_pos := hard_min_pos + Vector2(inset, inset)
	var max_pos := hard_max_pos - Vector2(inset, inset)
	if min_pos.x > max_pos.x:
		var mid_x := (hard_min_pos.x + hard_max_pos.x) * 0.5
		min_pos.x = mid_x
		max_pos.x = mid_x
	if min_pos.y > max_pos.y:
		var mid_y := (hard_min_pos.y + hard_max_pos.y) * 0.5
		min_pos.y = mid_y
		max_pos.y = mid_y

	var center_pos := (hard_min_pos + hard_max_pos) * 0.5


	for m in marbles:
		if not is_instance_valid(m):
			continue
		var p := m.global_position
		var clamped := Vector2(clamp(p.x, min_pos.x, max_pos.x), clamp(p.y, min_pos.y, max_pos.y))
		if clamped == p:
			continue

		m.global_position = clamped

		var n := Vector2.ZERO
		if p.x < hard_min_pos.x:
			n.x += 1.0
		elif p.x > hard_max_pos.x:
			n.x -= 1.0
		if p.y < hard_min_pos.y:
			n.y += 1.0
		elif p.y > hard_max_pos.y:
			n.y -= 1.0
		if n == Vector2.ZERO:
			n = (center_pos - clamped)
		if n == Vector2.ZERO:
			n = Vector2.RIGHT
		n = n.normalized()

		var v: Vector2 = m.linear_velocity
		if v.length() > 0.001 and v.dot(n) <= 0.0:
			v = v.bounce(n)

		var escape_speed: float = max(float(config.move_speed) * 0.65, 120.0)
		var target_speed: float = max(v.length(), escape_speed)
		var inward_speed: float = max(v.dot(n), target_speed * 0.7)
		var tangent: Vector2 = v - n * v.dot(n)
		tangent *= 0.25
		v = n * inward_speed + tangent
		if v.length() < escape_speed:
			v = v.normalized() * escape_speed if v.length() > 0.001 else n * escape_speed

		m.linear_velocity = v
		m.base_dir = v.normalized()



func _eliminate_marbles_outside_play_rect() -> void:
	if not _play_rect_valid() or not is_instance_valid(grid):
		return

	for i in range(marbles.size() - 1, -1, -1):
		var m := marbles[i]
		if not is_instance_valid(m):
			marbles.remove_at(i)
			continue

		var c: Vector2i = grid.call("world_to_cell", m.global_position)
		if not _is_inside_play_rect(c):
			var id := m.get_instance_id()
			if _last_tip_cell_by_id.has(id):
				_last_tip_cell_by_id.erase(id)
			m.queue_free()
			marbles.remove_at(i)


func _spawn_custom_marble_for_team(team: int, scale_mult: float = 1.0, speed_mult: float = 1.0, lifetime_sec: float = 0.0, from_center: bool = true) -> void:
	if team < 0 or team >= team_count:
		return
	var regions := _build_regions_in_cells(team_count)
	if team >= regions.size():
		return
	var rect: Rect2i = regions[team]
	var cs: float = float(config.grid_cell_size)
	var cx: int = rect.position.x + int(floor(float(rect.size.x) * 0.5))
	var cy: int = rect.position.y + int(floor(float(rect.size.y) * 0.5))
	var base_pos: Vector2 = grid.call("cell_to_world", Vector2i(cx, cy)) + Vector2(cs * 0.5, cs * 0.5)

	var m := MarbleScene.instantiate() as Marble
	add_child(m)
	if from_center:
		m.position = base_pos + Vector2(rng.randf_range(-cs, cs), rng.randf_range(-cs, cs))
	else:
		m.position = Vector2(
			rng.randf_range(0.0, float(config.grid_width) * cs),
			rng.randf_range(0.0, float(config.grid_height) * cs)
		)
	m.team_id = clamp(team, 0, team_count - 1)
	m.move_speed = float(config.move_speed) * max(speed_mult, 0.1)
	m.weapon_rotate_speed = float(config.weapon_rotate_speed) * max(speed_mult, 0.1)
	m.size_scale = float(config.initial_size_scale) * max(scale_mult, 0.2)
	m.cache_base_speed()
	m.territory = grid
	if available_skins.size() > 0:
		m.apply_skin(available_skins[team % available_skins.size()])
	m.team_changed.connect(_on_marble_team_changed)
	marbles.append(m)
	_apply_speed_all()

	if lifetime_sec > 0.0:
		var id := m.get_instance_id()
		_mini_swarm_ids[id] = true
		var t := get_tree().create_timer(lifetime_sec)
		t.timeout.connect(func():
			_remove_marble_if_alive(id)
		)


func _spawn_extra_marble_for_team(team: int, scale_mult: float = 1.0) -> void:
	_spawn_custom_marble_for_team(team, scale_mult, 1.0, 0.0, true)


func _remove_marble_if_alive(instance_id: int) -> void:
	for i in range(marbles.size() - 1, -1, -1):
		var m := marbles[i]
		if not is_instance_valid(m):
			marbles.remove_at(i)
			continue
		if m.get_instance_id() != instance_id:
			continue
		m.queue_free()
		marbles.remove_at(i)
		_mini_swarm_ids.erase(instance_id)
		return


func _apply_team_skin_colors_to_grid() -> void:
	if config == null:
		return
	if available_skins.is_empty():
		return
	for i in range(min(team_count, config.team_colors.size())):
		var skin := available_skins[i % available_skins.size()]
		if skin != null and skin.team_color_override.a > 0.0:
			config.team_colors[i] = skin.team_color_override


func _load_preset_skins_from_config() -> void:
	if config == null:
		return
	if not config.preset_skins.is_empty():
		available_skins = config.preset_skins.duplicate()


func _get_non_neutral_fill_ratio() -> float:
	if not is_instance_valid(grid) or config == null:
		return 0.0
	var total: int = max(config.grid_width * config.grid_height, 1)
	var owned: int = 0
	for y in range(config.grid_height):
		for x in range(config.grid_width):
			if int(grid.call("get_owner_cell", x, y)) >= 0:
				owned += 1
	return float(owned) / float(total)


func _spawn_speed_rain_zone() -> void:
	if config == null:
		return
	var cs: float = float(config.grid_cell_size)
	var p := Vector2(
		rng.randf_range(0.0, float(config.grid_width) * cs),
		rng.randf_range(0.0, float(config.grid_height) * cs)
	)
	_speed_rain_zones.append({"pos": p, "ttl": float(config.rule_3_zone_ttl_sec)})


func _update_speed_rain(delta: float) -> void:
	if config == null:
		return
	if _speed_rain_zones.is_empty():
		return

	var zone_radius: float = float(config.grid_cell_size) * max(float(config.rule_3_zone_radius_cells), 0.5)
	for i in range(_speed_rain_zones.size() - 1, -1, -1):
		var zone := _speed_rain_zones[i]
		zone["ttl"] = float(zone.get("ttl", 0.0)) - delta
		if float(zone["ttl"]) <= 0.0:
			_speed_rain_zones.remove_at(i)
			continue
		_speed_rain_zones[i] = zone

	for m in marbles:
		if not is_instance_valid(m):
			continue
		for zone in _speed_rain_zones:
			var zp: Vector2 = zone.get("pos", Vector2.ZERO)
			if m.global_position.distance_to(zp) > zone_radius:
				continue
			var dur := rng.randf_range(float(config.rule_3_boost_duration_min_sec), float(config.rule_3_boost_duration_max_sec))
			m.apply_temp_speed_boost(float(config.rule_3_boost_mult), dur, bool(config.rule_5_enabled), float(config.rule_5_angle_min_deg), float(config.rule_5_angle_max_deg))
			break

	queue_redraw()


func rule_infinite_spawn_tick() -> void:
	if config == null or not config.rule_2_enabled:
		return
	if _get_non_neutral_fill_ratio() >= float(config.rule_2_stop_fill_ratio):
		return
	var team := rng.randi_range(0, team_count - 1)
	_spawn_custom_marble_for_team(team, float(config.rule_2_small_size_mult), float(config.rule_2_small_speed_mult), 0.0, false)


func rule_speed_rain_tick() -> void:
	if config == null or not config.rule_3_enabled:
		return
	var count :float = max(1, int(config.rule_3_zone_count))
	for i in range(count):
		_spawn_speed_rain_zone()
	queue_redraw()


func rule_mini_swarm_tick() -> void:
	if config == null or not config.rule_4_enabled:
		return
	var n := rng.randi_range(int(config.rule_4_swarm_count_min), int(config.rule_4_swarm_count_max))
	for i in range(max(1, n)):
		var team := rng.randi_range(0, team_count - 1)
		_spawn_custom_marble_for_team(
			team,
			float(config.rule_4_mini_size_mult),
			float(config.rule_4_mini_speed_mult),
			float(config.rule_4_mini_lifetime_sec),
			false
		)
