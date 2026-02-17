extends Node2D

@onready var world: Node = $World
@onready var cam: Camera2D = $Camera2D
@onready var hud: Label = $UI/HUD

var _hud_visible: bool = true


func _ready() -> void:
	if App.config == null:
		hud.text = "HUD: missing config"
		push_error("Main: App.config is null")
		return

	_setup_fixed_camera(App.config)

	if world.has_method("start_match"):
		world.call("start_match")
	else:
		hud.text = "HUD: World.start_match() not found"
		push_error("Main: World node has no start_match()")

	if world.has_signal("match_ended"):
		world.match_ended.connect(_on_match_ended)

	_hud_visible = true
	hud.visible = _hud_visible
	set_process(true)
	set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	if _hud_visible:
		_update_hud_live()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_R:
			_restart_match()
		KEY_N:
			_next_preset()
		KEY_K:
			_end_run_now()
		KEY_H:
			_toggle_hud()


func _restart_match() -> void:
	if world and world.has_method("start_match"):
		world.call("start_match")


func _next_preset() -> void:
	if not App.next_preset():
		return
	_setup_fixed_camera(App.config)
	_restart_match()


func _end_run_now() -> void:
	if world and world.has_method("force_end_run"):
		world.call("force_end_run", "hotkey_k")


func _toggle_hud() -> void:
	_hud_visible = not _hud_visible
	hud.visible = _hud_visible
	if _hud_visible:
		_update_hud_live()


func _on_match_ended(winner_team: int, reason: String, territory_ratio: float) -> void:
	var result := ""
	if reason == "last_team_alive":
		result = "WIN: Team %d (last team alive)" % winner_team
	elif reason == "territory_90":
		result = "WIN: Team %d (territory %.1f%%)" % [winner_team, territory_ratio * 100.0]
	else:
		result = "WIN: Team %d (%s)" % [winner_team, reason]

	if _hud_visible:
		hud.text = "%s\n\n%s" % [result, _build_hud_stats_block()]


func _build_hud_stats_block() -> String:
	if App.config == null:
		return ""
	if world == null:
		return ""
	if not world.has_method("get_alive_marbles_per_team"):
		return ""
	if not world.has_method("get_territory_ratio_per_team"):
		return ""

	var seed: int = int(App.config.rng_seed)
	var seed_txt: String = "random" if seed == 0 else str(seed)
	var lines: Array[String] = []
	lines.append("Seed: %s | Preset: %s" % [seed_txt, App.config.preset_name])
	lines.append("")

	var alive: Array = world.call("get_alive_marbles_per_team")
	var ratios: Array = world.call("get_territory_ratio_per_team")
	var teams: int = min(alive.size(), ratios.size())
	for t in range(teams):
		lines.append("Team %d: %5.1f%% | alive %d" % [t, float(ratios[t]) * 100.0, int(alive[t])])

	return "\n".join(lines)


func _update_hud_live() -> void:
	hud.text = _build_hud_stats_block()


func _setup_fixed_camera(config: GameConfig) -> void:
	cam.enabled = true

	var map_w_px: float = float(config.grid_width * config.grid_cell_size)
	var map_h_px: float = float(config.grid_height * config.grid_cell_size)

	cam.position = Vector2(map_w_px * 0.5, map_h_px * 0.5)

	var vp: Vector2 = get_viewport_rect().size
	var z: float = min(float(vp.x) / map_w_px, float(vp.y) / map_h_px)
	z = clamp(z, 0.25, 1.0)

	cam.zoom = Vector2(z, z)
