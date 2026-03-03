extends Node2D

@onready var world: Node = $World
@onready var cam: Camera2D = $Camera2D
@onready var hud: Label = $UI/HUD

var _hud_timer: float = 0.0

func _ready() -> void:
	if App.config == null:
		hud.text = "HUD: missing config"
		push_error("Main: App.config is null")
		return

	_setup_fixed_camera(App.config)
	_setup_hud_visual()
	hud.visible = bool(App.config.show_hud)
	set_process_unhandled_input(true)

	if world.has_method("start_match"):
		world.call("start_match")
	else:
		hud.text = "HUD: World.start_match() not found"
		push_error("Main: World node has no start_match()")

	if world.has_signal("match_ended"):
		world.match_ended.connect(_on_match_ended)

	_update_hud()


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
			hud.visible = not hud.visible


func _process(delta: float) -> void:
	if App.config == null:
		return
	if not hud.visible:
		return
	_hud_timer -= delta
	if _hud_timer > 0.0:
		return
	_hud_timer = 1.0 / max(1.0, float(App.config.hud_update_hz))
	_update_hud()


func _restart_match() -> void:
	if world and world.has_method("start_match"):
		world.call("start_match")


func _next_preset() -> void:
	if not App.next_preset_config():
		return
	_setup_fixed_camera(App.config)
	_setup_hud_visual()
	hud.visible = bool(App.config.show_hud)
	_restart_match()


func _end_run_now() -> void:
	if world and world.has_method("force_end_run"):
		world.call("force_end_run")


func _update_hud() -> void:
	if App.config == null:
		return
	if not world:
		return

	#var seed_text: String = "Ranking marble:" if int(App.config.rng_seed) == 0 else str(int(App.config.rng_seed))
	var lines: Array[String] = []
	lines.append("Ranking marble:")
	var team_names: Array = []
	if world.has_method("get_team_display_names"):
		team_names = world.call("get_team_display_names")

	if world.has_method("get_territory_ratio_per_team") and world.has_method("get_alive_marbles_per_team"):
		var ratios: Array = world.call("get_territory_ratio_per_team")
		var alive: Array = world.call("get_alive_marbles_per_team")
		for t in range(min(ratios.size(), alive.size())):
			var team_name: String = _resolve_team_name(t, team_names)
			lines.append("%s: %5.1f%% | %d marbles" % [team_name, float(ratios[t]) * 100.0, int(alive[t])])

	hud.text = "\n".join(lines)


func _resolve_team_name(team_idx: int, team_names: Array) -> String:
	if team_idx >= 0 and team_idx < team_names.size():
		var candidate := str(team_names[team_idx]).strip_edges()
		if candidate != "":
			return candidate
	return "Marble %d" % [team_idx + 1]


func _on_match_ended(winner_team: int, reason: String, territory_ratio: float) -> void:
	var team_names: Array = []
	if world and world.has_method("get_team_display_names"):
		team_names = world.call("get_team_display_names")
	var team_name: String = _resolve_team_name(winner_team, team_names)

	var msg := ""
	if reason == "last_team_alive":
		msg = "WIN: %s (last team alive)" % team_name
	elif reason == "territory_90":
		msg = "WIN: %s (territory %.1f%%)" % [team_name, territory_ratio * 100.0]
	else:
		msg = "WIN: %s" % team_name

	_update_hud()
	hud.text += "\n" + msg


func _setup_hud_visual() -> void:
	if hud == null:
		return
	var settings := LabelSettings.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans", "Arial", "Segoe UI"])
	font.font_weight = 700
	settings.font = font
	settings.font_color = Color.BLACK
	settings.font_size = 20
	settings.outline_size = 5
	settings.outline_color = Color.WHITE
	hud.label_settings = settings


func _setup_fixed_camera(config: GameConfig) -> void:
	cam.enabled = true

	var map_w_px: float = float(config.grid_width * config.grid_cell_size)
	var map_h_px: float = float(config.grid_height * config.grid_cell_size)

	cam.position = Vector2(map_w_px * 0.5, map_h_px * 0.5)

	var vp: Vector2 = get_viewport_rect().size
	var z: float = min(float(vp.x) / map_w_px, float(vp.y) / map_h_px)
	z = clamp(z, 0.25, 1.0)

	cam.zoom = Vector2(z, z)
