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
			(paint_map[t] as Array[Vector2i]).append_array(cells)

	# batch paint theo team, redraw 1 lần/team
	for t in range(team_count):
		var arr := paint_map[t] as Array[Vector2i]
		if arr.is_empty():
			continue
		grid.call("set_owner_cells_batch", arr, t)

	_match_time_sec += tick_timer.wait_time if tick_timer else (1.0 / max(config.tick_rate, 1.0))
	_update_speed_state_timers()
	_clamp_marbles_to_play_rect()

	if not _match_over:
		_check_win_conditions()

	
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
	rule_explosion_on_death(marble.global_position, safe_team)

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
	var min_pos: Vector2 = grid.call("cell_to_world", _play_min_cell) + Vector2(cs * 0.5, cs * 0.5)
	var max_pos: Vector2 = grid.call("cell_to_world", _play_max_cell) + Vector2(cs * 0.5, cs * 0.5)

	for m in marbles:
		if not is_instance_valid(m):
			continue
		var p := m.global_position
		var clamped := Vector2(clamp(p.x, min_pos.x, max_pos.x), clamp(p.y, min_pos.y, max_pos.y))
		if clamped != p:
			m.global_position = clamped
			m.linear_velocity *= 0.5


func _spawn_extra_marble_for_team(team: int, scale_mult: float = 1.0) -> void:
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
	m.position = base_pos + Vector2(rng.randf_range(-cs, cs), rng.randf_range(-cs, cs))
	m.team_id = clamp(team, 0, team_count - 1)
	m.move_speed = float(config.move_speed)
	m.weapon_rotate_speed = float(config.weapon_rotate_speed)
	m.size_scale = float(config.initial_size_scale) * max(scale_mult, 0.2)
	m.cache_base_speed()
	m.territory = grid
	if available_skins.size() > 0:
		m.apply_skin(available_skins[team % available_skins.size()])
	m.team_changed.connect(_on_marble_team_changed)
	marbles.append(m)
	_apply_speed_all()


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


func rule_speed_ramp_tick() -> void:
	if config == null or not config.rule_1_enabled:
		return
	var next_mult: float = global_speed_mult + float(config.rule_1_strength)
	global_speed_mult = min(next_mult, float(config.rule_1_cap))
	_apply_speed_all()


func rule_shrink_tick() -> void:
	if config == null or not config.rule_2_enabled:
		return
	if not _play_rect_valid():
		return

	var step_cells: int = max(1, int(round(config.rule_2_strength)))
	if finale_speed_mult > 1.0:
		step_cells += 1

	_play_min_cell += Vector2i(step_cells, step_cells)
	_play_max_cell -= Vector2i(step_cells, step_cells)

	_play_min_cell.x = clamp(_play_min_cell.x, 0, config.grid_width - 1)
	_play_min_cell.y = clamp(_play_min_cell.y, 0, config.grid_height - 1)
	_play_max_cell.x = clamp(_play_max_cell.x, 0, config.grid_width - 1)
	_play_max_cell.y = clamp(_play_max_cell.y, 0, config.grid_height - 1)

	if _play_min_cell.x > _play_max_cell.x or _play_min_cell.y > _play_max_cell.y:
		return

	_neutralize_outside_play_rect()
	_clamp_marbles_to_play_rect()


func rule_spawn_giant_once() -> void:
	if config == null or not config.rule_3_enabled:
		return
	if _giant_spawned:
		return
	_giant_spawned = true

	var mode: int = int(config.rule_3_team_mode)
	var team: int = 0
	if mode == 0:
		team = 0
	elif mode == 1:
		team = rng.randi_range(0, team_count - 1)
	else:
		team = max(get_underdog_team(), 0)

	_spawn_extra_marble_for_team(team, float(config.rule_3_size_mult))


func rule_explosion_on_death(pos: Vector2, attacker_team: int) -> void:
	if config == null or not config.rule_4_enabled:
		return
	if rng.randf() > float(config.rule_4_chance):
		return

	var radius_cells: int = max(1, int(config.explosion_radius_cells))
	var cs: float = float(config.grid_cell_size)
	var radius_px: float = float(radius_cells) * cs

	for m in marbles:
		if not is_instance_valid(m):
			continue
		var d := m.global_position.distance_to(pos)
		if d <= radius_px and d > 0.001:
			var dir := (m.global_position - pos).normalized()
			m.apply_impulse(dir * float(config.explosion_impulse))

	if not is_instance_valid(grid):
		return

	var center: Vector2i = grid.call("world_to_cell", pos)
	var cells: Array[Vector2i] = []
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var c := Vector2i(center.x + dx, center.y + dy)
			var wp: Vector2 = grid.call("cell_to_world", c) + Vector2(cs * 0.5, cs * 0.5)
			if wp.distance_to(pos) <= radius_px:
				cells.append(c)
	if cells.is_empty():
		return
	if config.rule_4_to_neutral:
		grid.call("set_owner_cells_batch", cells, TerritoryGrid.OWNER_NEUTRAL)
	else:
		grid.call("set_owner_cells_batch", cells, clamp(attacker_team, 0, team_count - 1))


func rule_milestone_spawn_tick() -> void:
	if config == null or not config.rule_5_enabled:
		return
	var ratios := get_territory_ratio_per_team()
	var step_ratio: float = max(0.01, float(config.rule_5_strength) * 0.01)
	var cap_extra: int = max(0, int(config.rule_5_cap))

	for team in range(team_count):
		var reached: int = int(floor(float(ratios[team]) / step_ratio))
		var spawned: int = int(_extra_spawned_by_team.get(team, 0))
		if spawned >= cap_extra:
			continue
		if reached > int(_milestone_count_by_team.get(team, 0)):
			_spawn_extra_marble_for_team(team)
			_extra_spawned_by_team[team] = spawned + 1
			_milestone_count_by_team[team] = reached


func rule_underdog_buff_tick() -> void:
	if config == null or not config.rule_6_enabled:
		return
	if rng.randf() > float(config.rule_6_chance):
		return
	var team: int = get_underdog_team()
	if team < 0:
		return

	var buff_strength: float = max(0.0, float(config.rule_6_strength))
	var buff_mult: float = min(1.0 + buff_strength, float(config.rule_6_cap))
	team_buff_mult[team] = max(buff_mult, 1.0)
	team_buff_until_sec[team] = _match_time_sec + max(1.0, float(config.rule_6_period_sec) * 0.75)
	_apply_speed_all()


func rule_burst_tick() -> void:
	if config == null or not config.rule_7_enabled:
		return
	if rng.randf() > float(config.rule_7_chance):
		return
	burst_mult = max(1.0, 1.0 + float(config.rule_7_strength))
	burst_until_sec = _match_time_sec + 10.0
	_apply_speed_all()


func rule_edge_decay_tick() -> void:
	if config == null or not config.rule_8_enabled:
		return
	if not is_instance_valid(grid):
		return

	if _play_min_cell.x + _edge_decay_ring > _play_max_cell.x - _edge_decay_ring:
		return
	if _play_min_cell.y + _edge_decay_ring > _play_max_cell.y - _edge_decay_ring:
		return

	var min_x := _play_min_cell.x + _edge_decay_ring
	var max_x := _play_max_cell.x - _edge_decay_ring
	var min_y := _play_min_cell.y + _edge_decay_ring
	var max_y := _play_max_cell.y - _edge_decay_ring

	var ring: Array[Vector2i] = []
	for x in range(min_x, max_x + 1):
		ring.append(Vector2i(x, min_y))
		ring.append(Vector2i(x, max_y))
	for y in range(min_y + 1, max_y):
		ring.append(Vector2i(min_x, y))
		ring.append(Vector2i(max_x, y))
	grid.call("set_owner_cells_batch", ring, TerritoryGrid.OWNER_NEUTRAL)
	_edge_decay_ring += max(1, int(config.rule_8_strength))


func rule_finale_check_tick() -> void:
	if config == null or not config.rule_9_enabled:
		return
	if get_alive_team_count() <= 2:
		var target_mult: float = min(1.0 + float(config.rule_9_strength), float(config.rule_9_cap))
		if target_mult != finale_speed_mult:
			finale_speed_mult = max(target_mult, 1.0)
			_apply_speed_all()
		# shrink nhanh hơn ở finale
		rule_shrink_tick()


func _trigger_random_event_once() -> void:
	var roll: int = rng.randi_range(0, 4)
	if roll == 0:
		rule_speed_ramp_tick()
	elif roll == 1:
		rule_burst_tick()
	elif roll == 2:
		rule_shrink_tick()
	elif roll == 3:
		var t := rng.randi_range(0, team_count - 1)
		_spawn_extra_marble_for_team(t)
	else:
		var p := Vector2(rng.randf_range(0.0, float(config.grid_width * config.grid_cell_size)), rng.randf_range(0.0, float(config.grid_height * config.grid_cell_size)))
		rule_explosion_on_death(p, rng.randi_range(0, team_count - 1))


func rule_random_event_tick() -> void:
	if config == null or not config.rule_10_enabled:
		return
	if rng.randf() > float(config.rule_10_chance):
		return
	_trigger_random_event_once()
