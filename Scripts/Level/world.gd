extends Node2D

var config: GameConfig
var grid: TerritoryGrid
var marbles: Array[Marble] = []

var tick_timer: Timer
var bounds: StaticBody2D = null

@export_range(2, 10, 2) var team_count: int = 6
@export var available_skins: Array[MarbleSkin] = []
@export_range(0, 1, 1) var paint_thickness: int = 1

@onready var GridScene: PackedScene = preload("res://Scenes/Level/TerritoryGrid.tscn")
@onready var MarbleScene: PackedScene = preload("res://Scenes/Marble/Marble.tscn")
@onready var EscalationDirectorScript: Script = preload("res://Scripts/Systems/escalation_director.gd")

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var director: EscalationDirector

var global_speed_mult: float = 1.0
var burst_mult: float = 1.0
var burst_time_left: float = 0.0
var finale_speed_mult: float = 1.0
var finale_mode: bool = false
var team_buff_mult: Array[float] = []
var team_buff_time_left: Array[float] = []
var _speed_dirty: bool = false

var play_rect_cells: Rect2i = Rect2i.ZERO
var _edge_decay_layers_done: int = 0
var _milestone_next_ratio_by_team: Array[float] = []
var _milestone_spawned_count_by_team: Array[int] = []
var _active_skins: Array[MarbleSkin] = []

signal match_ended(winner_team: int, reason: String, territory_ratio: float)
var _last_tip_cell_by_id: Dictionary = {}

var _match_over: bool = false
@export var reset_delay: float = 2.0
@export var auto_loop_enabled: bool = true
@export var auto_loop_delay_sec: float = 2.0

var _match_started_msec: int = 0
var _pending_reset_timer: Timer = null


func start_match() -> void:
	config = App.config
	if config == null:
		push_error("World: App.config is null")
		return

	_match_over = false
	_match_started_msec = Time.get_ticks_msec()
	team_count = int(config.num_teams)
	if team_count < 2:
		push_error("World: config.num_teams must be >= 2")
		return
	if config.team_colors.size() < team_count:
		push_error("World: Not enough team_colors to run (need >= num_teams).")
		return

	_active_skins = _get_active_skins()
	_sync_team_colors_from_skins()

	if int(config.rng_seed) != 0:
		rng.seed = int(config.rng_seed)
	else:
		rng.randomize()

	_clear_previous_match()
	_spawn_grid()
	_spawn_bounds()
	_seed_territory_regions(team_count)
	_spawn_marbles_by_config(team_count, int(config.marbles_per_team))

	_init_play_area()
	_init_speed_state()
	_init_rule_runtime_state()
	_setup_director()
	_apply_speed_all()
	_setup_tick_timer()


func _setup_tick_timer() -> void:
	if tick_timer and is_instance_valid(tick_timer):
		tick_timer.queue_free()

	tick_timer = Timer.new()
	tick_timer.name = "TickTimer"
	tick_timer.one_shot = false
	tick_timer.autostart = true
	tick_timer.wait_time = 1.0 / max(float(config.tick_rate), 1.0)
	add_child(tick_timer)
	tick_timer.timeout.connect(_on_tick)


func _on_tick() -> void:
	if not is_instance_valid(grid):
		return

	var paint_map: Array = []
	paint_map.resize(team_count)
	for t in range(team_count):
		paint_map[t] = [] as Array[Vector2i]

	for m in marbles:
		if not is_instance_valid(m):
			continue
		var t: int = int(m.team_id)
		if t < 0 or t >= team_count:
			continue
		var cells := _cells_to_paint_for_marble(m)
		if not cells.is_empty():
			(paint_map[t] as Array[Vector2i]).append_array(cells)

	for t in range(team_count):
		var arr := paint_map[t] as Array[Vector2i]
		if arr.is_empty():
			continue
		grid.set_owner_cells_batch(arr, t)

	_clamp_marbles_to_play_area()

	var tick_dt: float = 1.0 / max(float(config.tick_rate), 1.0)
	_update_speed_timers(tick_dt)
	if director != null:
		director.on_tick(tick_dt)
	_apply_speed_all()

	if not _match_over:
		_check_win_conditions()


func _cells_to_paint_for_marble(m: Marble) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var tip_pos: Vector2 = m.get_weapon_tip_global_pos()
	var cur: Vector2i = grid.world_to_cell(tip_pos)

	var id := m.get_instance_id()
	if _last_tip_cell_by_id.has(id):
		var prev: Vector2i = _last_tip_cell_by_id[id]
		cells.append_array(_bresenham_cells(prev, cur))
	else:
		cells.append(cur)
	_last_tip_cell_by_id[id] = cur

	if paint_thickness > 0:
		var dir: Vector2 = m.linear_velocity.normalized() if m.linear_velocity.length() > 0.001 else Vector2.RIGHT
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

	var owner_counts := get_territory_count_per_team()
	for t in range(team_count):
		var ratio: float = float(owner_counts[t]) / float(total_cells)
		if ratio >= float(config.win_territory_ratio):
			_end_match(t, "territory_90", ratio)
			return


func _end_match(winner_team: int, reason: String, ratio: float) -> void:
	if _match_over:
		return
	_match_over = true

	if tick_timer and is_instance_valid(tick_timer):
		tick_timer.stop()

	for m in marbles:
		if not is_instance_valid(m):
			continue
		m.sleeping = true
		m.linear_velocity = Vector2.ZERO
		m.angular_velocity = 0.0

	emit_signal("match_ended", winner_team, reason, ratio)
	var duration_sec: float = get_match_duration_sec()
	var seed_txt: String = "random" if int(config.rng_seed) == 0 else str(int(config.rng_seed))
	print("MATCH_END | winner=%d | reason=%s | seed=%s | duration=%.2fs | preset=%s" % [winner_team, reason, seed_txt, duration_sec, config.preset_name])

	if auto_loop_enabled:
		_reset_after_delay()


func _reset_after_delay() -> void:
	if _pending_reset_timer and is_instance_valid(_pending_reset_timer):
		_pending_reset_timer.queue_free()

	_pending_reset_timer = Timer.new()
	_pending_reset_timer.one_shot = true
	_pending_reset_timer.wait_time = max(auto_loop_delay_sec, 0.1)
	add_child(_pending_reset_timer)
	_pending_reset_timer.timeout.connect(func():
		if _pending_reset_timer and is_instance_valid(_pending_reset_timer):
			_pending_reset_timer.queue_free()
		_pending_reset_timer = null
		start_match()
	)
	_pending_reset_timer.start()


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

	if _pending_reset_timer and is_instance_valid(_pending_reset_timer):
		_pending_reset_timer.queue_free()
		_pending_reset_timer = null

	if director and is_instance_valid(director):
		director.queue_free()
	director = null

	_last_tip_cell_by_id.clear()
	_speed_dirty = false
	finale_mode = false
	play_rect_cells = Rect2i.ZERO
	_edge_decay_layers_done = 0
	_milestone_next_ratio_by_team.clear()
	_milestone_spawned_count_by_team.clear()
	team_buff_mult.clear()
	team_buff_time_left.clear()


func _spawn_grid() -> void:
	grid = GridScene.instantiate() as TerritoryGrid
	add_child(grid)
	grid.setup(config)


func _spawn_bounds() -> void:
	var map_w: float = float(config.grid_width * config.grid_cell_size)
	var map_h: float = float(config.grid_height * config.grid_cell_size)
	var t: float = float(config.grid_cell_size) * 2.0

	bounds = StaticBody2D.new()
	bounds.name = "Bounds"
	add_child(bounds)

	_make_wall(bounds, "Top", Vector2(map_w * 0.5, -t * 0.5), Vector2(map_w + 2.0 * t, t))
	_make_wall(bounds, "Bottom", Vector2(map_w * 0.5, map_h + t * 0.5), Vector2(map_w + 2.0 * t, t))
	_make_wall(bounds, "Left", Vector2(-t * 0.5, map_h * 0.5), Vector2(t, map_h + 2.0 * t))
	_make_wall(bounds, "Right", Vector2(map_w + t * 0.5, map_h * 0.5), Vector2(t, map_h + 2.0 * t))

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
				grid.set_owner_cell(x, y, team, false)
	grid.queue_redraw()


func _spawn_marbles_by_config(n: int, marbles_per_team: int) -> void:
	var regions := _build_regions_in_cells(n)
	var cs: float = float(config.grid_cell_size)
	marbles_per_team = max(1, marbles_per_team)

	for team in range(n):
		var rect: Rect2i = regions[team]
		for i in range(marbles_per_team):
			var m := _spawn_single_marble(team, rect)
			if m != null:
				marbles.append(m)


func _spawn_single_marble(team: int, rect: Rect2i) -> Marble:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return null

	var cs: float = float(config.grid_cell_size)
	var cx: int = rect.position.x + int(floor(float(rect.size.x) * 0.5))
	var cy: int = rect.position.y + int(floor(float(rect.size.y) * 0.5))
	var base_pos: Vector2 = grid.cell_to_world(Vector2i(cx, cy)) + Vector2(cs * 0.5, cs * 0.5)

	var m := MarbleScene.instantiate() as Marble
	add_child(m)

	var jitter_cells: float = max(float(config.spawn_jitter_cells), 0.0)
	var jx: float = rng.randf_range(-cs * jitter_cells, cs * jitter_cells)
	var jy: float = rng.randf_range(-cs * jitter_cells, cs * jitter_cells)
	m.position = base_pos + Vector2(jx, jy)
	m.team_id = clamp(team, 0, team_count - 1)
	m.set_base_speeds(float(config.move_speed), float(config.weapon_rotate_speed))
	m.apply_speed_mult(1.0)
	m.size_scale = float(config.initial_size_scale)
	m.territory = grid

	if _active_skins.size() > 0:
		var skin_idx: int = m.team_id % _active_skins.size()
		m.apply_skin(_active_skins[skin_idx])

	m.team_changed.connect(_on_marble_team_changed)
	return m


func _on_marble_team_changed(marble: Marble, new_team: int) -> void:
	if not is_instance_valid(marble):
		return
	var safe_team: int = clamp(new_team, 0, team_count - 1)

	if _active_skins.size() > 0:
		var idx := safe_team % _active_skins.size()
		marble.apply_skin(_active_skins[idx])

	if director != null:
		director.on_marble_team_changed(marble, safe_team)


func _get_active_skins() -> Array[MarbleSkin]:
	if config != null and config.preset_skins.size() > 0:
		return config.preset_skins
	return available_skins


func _sync_team_colors_from_skins() -> void:
	if config == null:
		return
	if _active_skins.is_empty():
		return

	var colors := config.team_colors.duplicate()
	if colors.size() < team_count:
		return

	for t in range(team_count):
		var skin: MarbleSkin = _active_skins[t % _active_skins.size()]
		if skin != null and skin.use_team_color_override:
			colors[t] = skin.team_color_override

	config.team_colors = colors

func _setup_director() -> void:
	director = EscalationDirectorScript.new() as EscalationDirector
	director.name = "EscalationDirector"
	add_child(director)
	director.setup(self, config)


func _init_speed_state() -> void:
	global_speed_mult = 1.0
	burst_mult = 1.0
	burst_time_left = 0.0
	finale_speed_mult = 1.0
	finale_mode = false
	_speed_dirty = true

	team_buff_mult.resize(team_count)
	team_buff_time_left.resize(team_count)
	for i in range(team_count):
		team_buff_mult[i] = 1.0
		team_buff_time_left[i] = 0.0


func _init_rule_runtime_state() -> void:
	_edge_decay_layers_done = 0
	_milestone_next_ratio_by_team.resize(team_count)
	_milestone_spawned_count_by_team.resize(team_count)
	for t in range(team_count):
		_milestone_next_ratio_by_team[t] = max(float(config.rule_5_strength), 0.01)
		_milestone_spawned_count_by_team[t] = 0


func _init_play_area() -> void:
	play_rect_cells = Rect2i(0, 0, int(config.grid_width), int(config.grid_height))


func _update_speed_timers(delta_sec: float) -> void:
	if burst_time_left > 0.0:
		burst_time_left = max(burst_time_left - delta_sec, 0.0)
		if burst_time_left <= 0.0 and burst_mult != 1.0:
			burst_mult = 1.0
			_speed_dirty = true

	for t in range(team_buff_time_left.size()):
		if team_buff_time_left[t] <= 0.0:
			continue
		team_buff_time_left[t] = max(team_buff_time_left[t] - delta_sec, 0.0)
		if team_buff_time_left[t] <= 0.0 and team_buff_mult[t] != 1.0:
			team_buff_mult[t] = 1.0
			_speed_dirty = true


func _apply_speed_all() -> void:
	if not _speed_dirty:
		return
	for m in marbles:
		if not is_instance_valid(m):
			continue
		var t: int = int(m.team_id)
		var buff: float = 1.0
		if t >= 0 and t < team_buff_mult.size():
			buff = team_buff_mult[t]
		var total_mult: float = global_speed_mult * burst_mult * finale_speed_mult * buff
		m.apply_speed_mult(total_mult)
	_speed_dirty = false


func _clamp_marbles_to_play_area() -> void:
	if play_rect_cells.size.x <= 0 or play_rect_cells.size.y <= 0:
		return

	var cs: float = float(config.grid_cell_size)
	var min_x: float = float(play_rect_cells.position.x) * cs + cs * 0.5
	var max_x: float = float(play_rect_cells.position.x + play_rect_cells.size.x) * cs - cs * 0.5
	var min_y: float = float(play_rect_cells.position.y) * cs + cs * 0.5
	var max_y: float = float(play_rect_cells.position.y + play_rect_cells.size.y) * cs - cs * 0.5

	for m in marbles:
		if not is_instance_valid(m):
			continue
		var p := m.global_position
		var clamped := Vector2(clamp(p.x, min_x, max_x), clamp(p.y, min_y, max_y))
		if clamped != p:
			m.global_position = clamped


func _neutralize_outside_play_rect() -> void:
	var neutral: int = TerritoryGrid.OWNER_NEUTRAL
	var cells: Array[Vector2i] = []
	for y in range(int(config.grid_height)):
		for x in range(int(config.grid_width)):
			if play_rect_cells.has_point(Vector2i(x, y)):
				continue
			cells.append(Vector2i(x, y))
	if not cells.is_empty():
		grid.set_owner_cells_batch(cells, neutral)


func get_match_duration_sec() -> float:
	if _match_started_msec <= 0:
		return 0.0
	return max(float(Time.get_ticks_msec() - _match_started_msec) / 1000.0, 0.0)


func force_end_run(reason: String = "forced_end") -> void:
	if _match_over:
		return
	var counts := get_territory_count_per_team()
	var winner: int = 0
	var best_cells: int = -1
	for t in range(team_count):
		if counts[t] > best_cells:
			best_cells = counts[t]
			winner = t
	var total_cells: float = max(float(config.grid_width * config.grid_height), 1.0)
	var ratio: float = float(best_cells) / total_cells
	_end_match(winner, reason, ratio)

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
	var alive: Array[bool] = []
	alive.resize(team_count)
	for i in range(team_count):
		alive[i] = false

	for m in marbles:
		if not is_instance_valid(m):
			continue
		var t: int = int(m.team_id)
		if t >= 0 and t < team_count:
			alive[t] = true

	var c: int = 0
	for f in alive:
		if f:
			c += 1
	return c


func get_territory_count_per_team() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(team_count)
	for i in range(team_count):
		counts[i] = 0

	for y in range(config.grid_height):
		for x in range(config.grid_width):
			var owner: int = int(grid.get_owner_cell(x, y))
			if owner >= 0 and owner < team_count:
				counts[owner] += 1
	return counts


func get_territory_ratio_per_team() -> Array[float]:
	var counts := get_territory_count_per_team()
	var total_cells: float = max(float(config.grid_width * config.grid_height), 1.0)
	var ratios: Array[float] = []
	ratios.resize(team_count)
	for t in range(team_count):
		ratios[t] = float(counts[t]) / total_cells
	return ratios


func get_underdog_team() -> int:
	var counts := get_territory_count_per_team()
	var best_team: int = -1
	var min_cells: int = 2147483647
	for t in range(team_count):
		if counts[t] < min_cells:
			min_cells = counts[t]
			best_team = t
	return best_team


func get_finale_shrink_factor() -> float:
	return max(float(config.rule_9_cap), 1.0) if finale_mode else 1.0


func rule_speed_ramp_tick() -> void:
	var step: float = max(float(config.rule_1_strength), 0.0)
	var capv: float = max(float(config.rule_1_cap), 1.0)
	global_speed_mult = min(global_speed_mult + step, capv)
	_speed_dirty = true


func rule_shrink_tick() -> void:
	if play_rect_cells.size.x <= 2 or play_rect_cells.size.y <= 2:
		return

	var shrink: int = max(1, int(round(float(config.rule_2_strength))))
	for i in range(shrink):
		if play_rect_cells.size.x <= 2 or play_rect_cells.size.y <= 2:
			break
		play_rect_cells = Rect2i(
			play_rect_cells.position + Vector2i.ONE,
			play_rect_cells.size - Vector2i(2, 2)
		)

	_clamp_marbles_to_play_area()
	_neutralize_outside_play_rect()


func rule_spawn_giant_once() -> void:
	var team: int = 0
	var mode: String = String(config.giant_spawn_team_mode).to_lower()
	if mode == "random":
		team = rng.randi_range(0, team_count - 1)
	elif mode == "underdog":
		team = max(get_underdog_team(), 0)

	var center_rect := Rect2i(
		play_rect_cells.position + Vector2i(play_rect_cells.size.x / 2, play_rect_cells.size.y / 2),
		Vector2i(1, 1)
	)
	var giant := _spawn_single_marble(team, center_rect)
	if giant == null:
		return
	giant.size_scale = max(float(config.rule_3_strength), float(config.initial_size_scale))
	giant.apply_size_scale()
	marbles.append(giant)
	_speed_dirty = true


func rule_explosion_on_death(pos: Vector2, attacker_team: int) -> void:
	var attacker: int = clamp(attacker_team, 0, team_count - 1)
	var radius_cells: int = max(1, int(round(float(config.explosion_radius_cells) * max(float(config.rule_4_strength), 0.1))))
	var radius_px: float = float(radius_cells * int(config.grid_cell_size))
	var push_force: float = max(float(config.explosion_force) * max(float(config.rule_4_strength), 0.1), 0.0)

	for m in marbles:
		if not is_instance_valid(m):
			continue
		var d: float = m.global_position.distance_to(pos)
		if d <= 0.001 or d > radius_px:
			continue
		var dir := (m.global_position - pos).normalized()
		var falloff: float = 1.0 - (d / radius_px)
		m.apply_impulse(dir * push_force * falloff)

	var center_cell: Vector2i = grid.world_to_cell(pos)
	var changed: Array[Vector2i] = []
	for y in range(center_cell.y - radius_cells, center_cell.y + radius_cells + 1):
		for x in range(center_cell.x - radius_cells, center_cell.x + radius_cells + 1):
			if x < 0 or y < 0 or x >= int(config.grid_width) or y >= int(config.grid_height):
				continue
			var c := Vector2i(x, y)
			var wp: Vector2 = grid.cell_to_world(c) + Vector2(float(config.grid_cell_size) * 0.5, float(config.grid_cell_size) * 0.5)
			if wp.distance_to(pos) <= radius_px:
				changed.append(c)
	if not changed.is_empty():
		grid.set_owner_cells_batch(changed, attacker)


func rule_milestone_spawn_tick() -> void:
	var step_ratio: float = max(float(config.rule_5_strength), 0.01)
	var cap_per_team: int = max(int(round(float(config.rule_5_cap))), 0)
	var ratios := get_territory_ratio_per_team()
	var regions := _build_regions_in_cells(team_count)

	for t in range(team_count):
		while ratios[t] >= _milestone_next_ratio_by_team[t] and _milestone_spawned_count_by_team[t] < cap_per_team:
			var m := _spawn_single_marble(t, regions[t])
			if m == null:
				break
			marbles.append(m)
			_milestone_spawned_count_by_team[t] += 1
			_milestone_next_ratio_by_team[t] += step_ratio

	_speed_dirty = true


func rule_underdog_buff_tick() -> void:
	var t: int = get_underdog_team()
	if t < 0 or t >= team_count:
		return
	team_buff_mult[t] = max(float(config.rule_6_strength), 1.0)
	team_buff_time_left[t] = max(float(config.rule_6_cap), 0.0)
	_speed_dirty = true


func rule_burst_tick() -> void:
	burst_mult = max(float(config.rule_7_strength), 1.0)
	burst_time_left = 10.0
	_speed_dirty = true


func rule_edge_decay_tick() -> void:
	var max_layers: int = int(min(play_rect_cells.size.x, play_rect_cells.size.y) / 2)
	if _edge_decay_layers_done >= max_layers:
		return

	var neutral: int = TerritoryGrid.OWNER_NEUTRAL
	var ring := Rect2i(
		play_rect_cells.position + Vector2i(_edge_decay_layers_done, _edge_decay_layers_done),
		play_rect_cells.size - Vector2i(_edge_decay_layers_done * 2, _edge_decay_layers_done * 2)
	)
	if ring.size.x <= 0 or ring.size.y <= 0:
		return

	var cells: Array[Vector2i] = []
	for x in range(ring.position.x, ring.position.x + ring.size.x):
		cells.append(Vector2i(x, ring.position.y))
		if ring.size.y > 1:
			cells.append(Vector2i(x, ring.position.y + ring.size.y - 1))
	for y in range(ring.position.y + 1, ring.position.y + ring.size.y - 1):
		cells.append(Vector2i(ring.position.x, y))
		if ring.size.x > 1:
			cells.append(Vector2i(ring.position.x + ring.size.x - 1, y))

	if not cells.is_empty():
		grid.set_owner_cells_batch(cells, neutral)
	_edge_decay_layers_done += 1


func rule_finale_check_tick() -> void:
	var alive_teams: int = get_alive_team_count()
	var should_finale: bool = alive_teams <= 2
	if should_finale and not finale_mode:
		finale_mode = true
		rule_shrink_tick()
	elif not should_finale and finale_mode:
		finale_mode = false

	var next_mult: float = max(float(config.rule_9_strength), 1.0) if finale_mode else 1.0
	if not is_equal_approx(finale_speed_mult, next_mult):
		finale_speed_mult = next_mult
		_speed_dirty = true


func rule_random_event_tick() -> void:
	var roll: int = rng.randi_range(0, 4)
	match roll:
		0:
			rule_speed_ramp_tick()
		1:
			rule_burst_tick()
		2:
			rule_shrink_tick()
		3:
			var team: int = rng.randi_range(0, team_count - 1)
			var regions := _build_regions_in_cells(team_count)
			var m := _spawn_single_marble(team, regions[team])
			if m != null:
				marbles.append(m)
				_speed_dirty = true
		4:
			var event_pos := Vector2(
				rng.randf_range(0.0, float(config.grid_width * config.grid_cell_size)),
				rng.randf_range(0.0, float(config.grid_height * config.grid_cell_size))
			)
			rule_explosion_on_death(event_pos, rng.randi_range(0, team_count - 1))
