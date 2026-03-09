extends Node2D
class_name TerritoryFXManager

@export_range(20, 100, 1) var pool_size: int = 40
@export_range(8.0, 256.0, 1.0) var tile_size: float = 32.0
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

var _pool: Array[CaptureFXItem] = []
var _cursor: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


class CaptureFXItem:
	extends Node2D

	var tile_size: float = 32.0
	var flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	var team_color: Color = Color.WHITE
	var flash_duration: float = 0.20
	var ripple_duration: float = 0.30
	var elapsed: float = 0.0
	var is_active: bool = false

	func activate(world_pos: Vector2, p_team_color: Color, p_flash_duration: float, p_ripple_duration: float, p_tile_size: float, p_flash_color: Color) -> void:
		position = world_pos
		team_color = p_team_color
		flash_duration = max(p_flash_duration, 0.01)
		ripple_duration = max(p_ripple_duration, 0.01)
		tile_size = max(p_tile_size, 1.0)
		flash_color = p_flash_color
		elapsed = 0.0
		is_active = true
		visible = true
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_active:
			return
		elapsed += delta
		if elapsed >= max(flash_duration, ripple_duration):
			is_active = false
			visible = false
			return
		queue_redraw()

	func _draw() -> void:
		if not is_active:
			return

		var flash_t: float = clamp(elapsed / flash_duration, 0.0, 1.0)
		var flash_alpha: float = lerpf(1.0, 0.0, flash_t)
		var flash_rect := Rect2(Vector2(-tile_size * 0.5, -tile_size * 0.5), Vector2(tile_size, tile_size))
		draw_rect(flash_rect, Color(flash_color.r, flash_color.g, flash_color.b, flash_alpha), true)

		var ripple_t: float = clamp(elapsed / ripple_duration, 0.0, 1.0)
		var radius: float = (tile_size * 0.5) * lerpf(0.6, 2.2, ripple_t)
		var ripple_alpha: float = lerpf(0.8, 0.0, ripple_t)
		var ring_color := Color(team_color.r, team_color.g, team_color.b, ripple_alpha)
		var line_width: float = max(2.0, tile_size * 0.08)

		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ring_color, line_width, true)
		draw_circle(Vector2.ZERO, radius * 0.25, Color(1.0, 1.0, 1.0, ripple_alpha * 0.35))


func _ready() -> void:
	_rng.randomize()
	_ensure_pool()


func configure_from_cell_size(p_cell_size: float) -> void:
	tile_size = max(p_cell_size, 1.0)
	for item in _pool:
		if not is_instance_valid(item):
			continue
		item.tile_size = tile_size


func spawn_capture_fx(tile_world_pos: Vector2, team_color: Color) -> void:
	if _pool.is_empty():
		_ensure_pool()
	if _pool.is_empty():
		return

	var item: CaptureFXItem = _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()

	var flash_duration: float = _rng.randf_range(0.18, 0.25)
	var ripple_duration: float = _rng.randf_range(0.25, 0.35)
	var local_pos: Vector2 = to_local(tile_world_pos)
	item.activate(local_pos, team_color, flash_duration, ripple_duration, tile_size, flash_color)


func _ensure_pool() -> void:
	if not _pool.is_empty():
		return

	var target_size: int = max(pool_size, 20)
	_pool.resize(target_size)
	for i in range(target_size):
		var item := CaptureFXItem.new()
		item.name = "CaptureFX_%d" % i
		item.visible = false
		item.tile_size = tile_size
		item.flash_color = flash_color
		add_child(item)
		_pool[i] = item
