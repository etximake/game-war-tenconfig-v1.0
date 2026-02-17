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

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

signal match_ended(winner_team: int, reason: String, territory_ratio: float)
var _last_tip_cell_by_id: Dictionary = {}  # key: instance_id, value: Vector2i

var _match_over: bool = false
@export var reset_delay: float = 2.0


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

	if "rng_seed" in config and int(config.rng_seed) != 0:
		rng.seed = int(config.rng_seed)
	else:
		rng.randomize()

	_clear_previous_match()

	_spawn_grid()
	_spawn_bounds()

	_seed_territory_regions(team_count)

	# ✅ FIX: spawn theo marbles_per_team (không còn 1 per region)
	_spawn_marbles_by_config(team_count, int(config.marbles_per_team))

	_setup_tick_timer()


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
	_reset_after_delay()


func _reset_after_delay() -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = reset_delay
	add_child(t)
	t.timeout.connect(func():
		t.queue_free()
		start_match()
	)
	t.start()


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

			m.team_id = team
			m.move_speed = float(config.move_speed)
			m.weapon_rotate_speed = float(config.weapon_rotate_speed)
			m.size_scale = float(config.initial_size_scale)

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

		m.team_id = team
		m.move_speed = float(config.move_speed)
		m.weapon_rotate_speed = float(config.weapon_rotate_speed)
		m.size_scale = float(config.initial_size_scale)

		m.territory = grid

		if available_skins.size() > 0:
			var skin_idx: int = team % available_skins.size()
			m.apply_skin(available_skins[skin_idx])

		marbles.append(m)
		m.team_changed.connect(_on_marble_team_changed)


func _on_marble_team_changed(marble: Marble, new_team: int) -> void:
	if available_skins.size() == 0:
		return
	var idx := new_team % available_skins.size()
	marble.apply_skin(available_skins[idx])
