extends Node2D

@onready var world: Node = $World
@onready var cam: Camera2D = $Camera2D
@onready var hud: Label = $UI/HUD

var _hud_timer: float = 0.0
var _cam_base_zoom: Vector2 = Vector2.ONE

func _ready() -> void:
	if App.config == null:
		hud.text = "HUD: missing config"
		push_error("Main: App.config is null")
		return

	# Chờ 1 frame để viewport ổn định (fullscreen/borderless) rồi mới fit camera.
	call_deferred("_refresh_camera_from_viewport")
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



func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_refresh_camera_from_viewport()


func _refresh_camera_from_viewport() -> void:
	if App.config == null:
		return
	_setup_fixed_camera(App.config)

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
	_update_camera_director(delta)
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

	var seed_text: String = "random" if int(App.config.rng_seed) == 0 else str(int(App.config.rng_seed))
	var lines: Array[String] = []
	lines.append("Seed: %s | Preset: %s" % [seed_text, App.config.preset_name])

	if world.has_method("get_territory_ratio_per_team") and world.has_method("get_alive_marbles_per_team"):
		var ratios: Array = world.call("get_territory_ratio_per_team")
		var alive: Array = world.call("get_alive_marbles_per_team")
		var momentum: Array = []
		if world.has_method("get_team_momentum_signs"):
			momentum = world.call("get_team_momentum_signs", float(App.config.hud_momentum_window_sec))

		var rows: Array[Dictionary] = []
		for t in range(min(ratios.size(), alive.size())):
			rows.append({"team": t, "ratio": float(ratios[t]), "alive": int(alive[t])})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("ratio", 0.0)) > float(b.get("ratio", 0.0))
		)

		for i in range(rows.size()):
			var r := rows[i]
			var team: int = int(r.get("team", 0))
			var sign: int = int(momentum[team]) if team < momentum.size() else 0
			var arrow: String = "→"
			if sign > 0:
				arrow = "↑"
			elif sign < 0:
				arrow = "↓"
			var team_name: String = _get_team_label(team)
			lines.append("#%d %s: %5.1f%% | %d marbles | %s" % [i + 1, team_name, float(r.get("ratio", 0.0)) * 100.0, int(r.get("alive", 0)), arrow])

	hud.text = "\n".join(lines)


func _update_camera_director(delta: float) -> void:
	if App.config == null:
		return
	if not bool(App.config.camera_director_enabled):
		return
	if not world:
		return

	var target: Vector2 = Vector2.ZERO
	var zoom_mult: float = 1.0
	if world.has_method("get_camera_director_state"):
		var state: Dictionary = world.call("get_camera_director_state")
		target = state.get("focus", Vector2.ZERO)
		zoom_mult = float(state.get("zoom_mult", 1.0))
	elif world.has_method("get_camera_focus_point"):
		target = world.call("get_camera_focus_point")
	if not target.is_finite():
		return

	zoom_mult = clamp(zoom_mult, float(App.config.camera_director_zoom_in_mult), 1.0)
	if world.has_method("is_lead_change_recent") and bool(world.call("is_lead_change_recent", float(App.config.camera_director_lead_change_boost_sec))):
		zoom_mult = min(zoom_mult, float(App.config.camera_director_zoom_in_mult))

	var map_size := Vector2(float(App.config.grid_width * App.config.grid_cell_size), float(App.config.grid_height * App.config.grid_cell_size))
	target.x = clamp(target.x, 0.0, map_size.x)
	target.y = clamp(target.y, 0.0, map_size.y)

	var t: float = clamp(float(App.config.camera_director_lerp_speed) * delta, 0.0, 1.0)
	cam.position = cam.position.lerp(target, t).round()
	var zoom_target: Vector2 = _cam_base_zoom * zoom_mult
	cam.zoom = cam.zoom.lerp(zoom_target, t)
	_update_camera_limits(App.config)


func _on_match_ended(winner_team: int, reason: String, territory_ratio: float) -> void:
	var msg := ""
	if reason == "last_team_alive":
		msg = "WIN: %s (last team alive)" % _get_team_label(winner_team)
	elif reason == "territory_90":
		msg = "WIN: %s (territory %.1f%%)" % [_get_team_label(winner_team), territory_ratio * 100.0]
	else:
		msg = "WIN: %s" % _get_team_label(winner_team)

	_update_hud()
	hud.text += "\n" + msg


func _setup_fixed_camera(config: GameConfig) -> void:
	cam.enabled = true

	var map_w_px: float = float(config.grid_width * config.grid_cell_size)
	var map_h_px: float = float(config.grid_height * config.grid_cell_size)

	cam.position = Vector2(map_w_px * 0.5, map_h_px * 0.5)

	var vp: Vector2 = get_viewport_rect().size
	# Camera2D: screen_world_size = viewport_size * zoom.
	# Muốn "cover" map (không lộ nền xám) thì zoom phải nhỏ hơn hoặc bằng tỉ lệ map/viewport.
	var z: float = min(map_w_px / max(vp.x, 1.0), map_h_px / max(vp.y, 1.0))
	z = clamp(z, 0.05, 1.0)

	cam.zoom = Vector2(z, z)
	_cam_base_zoom = cam.zoom

	_update_camera_limits(config)


func _update_camera_limits(config: GameConfig) -> void:
	if config == null:
		return
	cam.limit_enabled = true

	var map_w_px: float = float(config.grid_width * config.grid_cell_size)
	var map_h_px: float = float(config.grid_height * config.grid_cell_size)
	var vp: Vector2 = get_viewport_rect().size
	var half_view_world: Vector2 = vp * 0.5 * cam.zoom
	var left_limit: int = int(round(half_view_world.x))
	var top_limit: int = int(round(half_view_world.y))
	var right_limit: int = int(round(map_w_px - half_view_world.x))
	var bottom_limit: int = int(round(map_h_px - half_view_world.y))

	if right_limit < left_limit:
		var cx: int = int(round(map_w_px * 0.5))
		left_limit = cx
		right_limit = cx
	if bottom_limit < top_limit:
		var cy: int = int(round(map_h_px * 0.5))
		top_limit = cy
		bottom_limit = cy

	cam.limit_left = left_limit
	cam.limit_top = top_limit
	cam.limit_right = right_limit
	cam.limit_bottom = bottom_limit


func _get_team_label(team: int) -> String:
	if world and world.has_method("get_team_display_name"):
		return str(world.call("get_team_display_name", team))
	return "Team %d" % (team + 1)
