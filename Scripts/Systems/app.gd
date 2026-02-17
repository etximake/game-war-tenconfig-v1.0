extends Node

@export var config_path: String = "res://Resources/Configs/default_game_config.tres"

var config: GameConfig

func _ready() -> void:
	config = load(config_path) as GameConfig
	if config == null:
		push_error("App: Failed to load config at: %s" % config_path)
		return
	print("App: Config loaded OK")
