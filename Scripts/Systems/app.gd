extends Node

@export var config_path: String = "res://Resources/Configs/default_game_config.tres"
@export var preset_paths: Array[String] = [
	"res://Resources/Configs/default_game_config.tres",
	"res://Resources/Configs/chaos_game_config.tres",
	"res://Resources/Configs/comeback_game_config.tres",
	"res://Resources/Configs/boss_heavy_game_config.tres",
]

var config: GameConfig
var _preset_index: int = 0


func _ready() -> void:
	_sync_preset_index()
	reload_config()


func _sync_preset_index() -> void:
	if preset_paths.is_empty():
		preset_paths.append(config_path)

	var idx: int = preset_paths.find(config_path)
	if idx == -1:
		preset_paths.append(config_path)
		idx = preset_paths.size() - 1
	_preset_index = idx


func reload_config() -> bool:
	config = load(config_path) as GameConfig
	if config == null:
		push_error("App: Failed to load config at: %s" % config_path)
		return false

	print("App: Config loaded OK | preset=%s | seed=%d | path=%s" % [config.preset_name, int(config.rng_seed), config_path])
	return true


func next_preset() -> bool:
	if preset_paths.is_empty():
		return false

	_preset_index = (_preset_index + 1) % preset_paths.size()
	config_path = preset_paths[_preset_index]
	return reload_config()
