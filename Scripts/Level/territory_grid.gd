extends Node2D
class_name TerritoryGrid

var config: GameConfig
var owners: PackedInt32Array = PackedInt32Array()

@export var draw_grid_lines: bool = true
@export_range(0.0, 1.0, 0.01) var grid_line_alpha: float = 0.25
@export_range(0.5, 4.0, 0.1) var grid_line_base: float = 1.0

# Neutral = -1 (chưa ai chiếm)
const OWNER_NEUTRAL: int = -1
const OWNER_OOB: int = -999


func setup(p_config: GameConfig) -> void:
	config = p_config
	if config == null:
		push_error("TerritoryGrid.setup(): config is null")
		return

	var w: int = int(config.grid_width)
	var h: int = int(config.grid_height)
	var n: int = w * h

	owners.resize(n)
	for i in range(n):
		owners[i] = OWNER_NEUTRAL

	queue_redraw()


# =========================
# Coordinate conversion
func world_to_cell(pos: Vector2) -> Vector2i:
	var cs: int = config.grid_cell_size
	var x: int = int(floor(pos.x / float(cs)))
	var y: int = int(floor(pos.y / float(cs)))

	x = clamp(x, 0, config.grid_width - 1)
	y = clamp(y, 0, config.grid_height - 1)

	return Vector2i(x, y)



func cell_to_world(cell: Vector2i) -> Vector2:
	# trả về top-left của cell
	if config == null:
		return Vector2.ZERO
	var cs: float = float(config.grid_cell_size)
	return Vector2(float(cell.x) * cs, float(cell.y) * cs)


# =========================
# Owner accessors
# =========================
func get_owner_cell(x: int, y: int) -> int:
	if config == null:
		return OWNER_OOB
	var w: int = int(config.grid_width)
	var h: int = int(config.grid_height)
	if x < 0 or y < 0 or x >= w or y >= h:
		return OWNER_OOB
	var idx: int = y * w + x
	return owners[idx]


func set_owner_cell(x: int, y: int, team: int, redraw: bool = true) -> void:
	if config == null:
		return
	var w: int = int(config.grid_width)
	var h: int = int(config.grid_height)
	if x < 0 or y < 0 or x >= w or y >= h:
		return

	var idx: int = y * w + x
	if owners[idx] == team:
		return

	owners[idx] = team
	if redraw:
		queue_redraw()


func set_owner_cells_batch(cells: Array[Vector2i], team: int) -> void:
	if config == null:
		return
	if cells.is_empty():
		return

	var w: int = int(config.grid_width)
	var h: int = int(config.grid_height)

	var changed: bool = false
	for c in cells:
		var x: int = c.x
		var y: int = c.y
		if x < 0 or y < 0 or x >= w or y >= h:
			continue

		var idx: int = y * w + x
		if owners[idx] == team:
			continue

		owners[idx] = team
		changed = true

	if changed:
		queue_redraw()


func fill_all(team: int) -> void:
	if config == null:
		return
	if owners.is_empty():
		return

	var changed: bool = false
	for i in range(owners.size()):
		if owners[i] == team:
			continue
		owners[i] = team
		changed = true

	if changed:
		queue_redraw()


# =========================
# Draw
# =========================
func _draw() -> void:
	if config == null:
		return

	var w: int = int(config.grid_width)
	var h: int = int(config.grid_height)
	var cs: float = float(config.grid_cell_size)

	# draw cells
	for y in range(h):
		for x in range(w):
			var idx: int = y * w + x
			var owner: int = owners[idx]

			var col: Color
			if owner >= 0 and owner < config.team_colors.size():
				col = config.team_colors[owner]
			else:
				# neutral: hơi xám/đậm để thấy rõ biên
				col = Color(0.05, 0.05, 0.05, 1.0)

			draw_rect(Rect2(Vector2(x * cs, y * cs), Vector2(cs, cs)), col, true)

	# grid lines (optional)
	if draw_grid_lines:
		var lc := Color(0.0, 0.0, 0.0, grid_line_alpha)
		var total_w: float = float(w) * cs
		var total_h: float = float(h) * cs

		# vertical lines
		for x in range(w + 1):
			var px: float = float(x) * cs
			draw_line(Vector2(px, 0.0), Vector2(px, total_h), lc, grid_line_base)

		# horizontal lines
		for y in range(h + 1):
			var py: float = float(y) * cs
			draw_line(Vector2(0.0, py), Vector2(total_w, py), lc, grid_line_base)
