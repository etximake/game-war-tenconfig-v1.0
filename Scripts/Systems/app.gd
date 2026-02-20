extends Node

@export var config_path: String = "res://Resources/Configs/default_game_config.tres"
@export var preset_config_paths: Array[String] = [
	"res://Resources/Configs/default_game_config.tres",
	"res://Resources/Configs/chaos_game_config.tres",
	"res://Resources/Configs/comeback_game_config.tres",
	"res://Resources/Configs/boss-heavy_game_config.tres"
]

var config: GameConfig

func _ready() -> void:
	load_config_path(config_path)


func load_config_path(path: String) -> bool:
	var loaded := load(path) as GameConfig
	if loaded == null:
		push_error("App: Failed to load config at: %s" % path)
		return false

	config_path = path
	config = loaded
	print("App: Config loaded OK -> %s" % config_path)
	return true


func next_preset_config() -> bool:
	if preset_config_paths.is_empty():
		return false

	var idx: int = preset_config_paths.find(config_path)
	if idx < 0:
		idx = 0
	else:
		idx = (idx + 1) % preset_config_paths.size()

	return load_config_path(preset_config_paths[idx])
