extends Node2D

@onready var world: Node = $World
@onready var cam: Camera2D = $Camera2D
@onready var hud: Label = $UI/HUD

func _ready() -> void:
	if App.config == null:
		hud.text = "HUD: missing config"
		push_error("Main: App.config is null")
		return

	_setup_fixed_camera(App.config)

	if world.has_method("start_match"):
		world.call("start_match")
		hud.text = "HUD: match started"
	else:
		hud.text = "HUD: World.start_match() not found"
		push_error("Main: World node has no start_match()")
		
	if world.has_signal("match_ended"):
		world.match_ended.connect(_on_match_ended)

func _on_match_ended(winner_team: int, reason: String, territory_ratio: float) -> void:
	var msg := ""
	if reason == "last_team_alive":
		msg = "WIN: Team %d (last team alive)" % winner_team
	elif reason == "territory_90":
		msg = "WIN: Team %d (territory %.1f%%)" % [winner_team, territory_ratio * 100.0]
	else:
		msg = "WIN: Team %d" % winner_team

	hud.text = msg


func _setup_fixed_camera(config: GameConfig) -> void:
	cam.enabled = true

	var map_w_px: float = float(config.grid_width * config.grid_cell_size)
	var map_h_px: float = float(config.grid_height * config.grid_cell_size)

	cam.position = Vector2(map_w_px * 0.5, map_h_px * 0.5)

	var vp: Vector2 = get_viewport_rect().size
	var z: float = min(float(vp.x) / map_w_px, float(vp.y) / map_h_px)
	z = clamp(z, 0.25, 1.0)

	cam.zoom = Vector2(z, z)
