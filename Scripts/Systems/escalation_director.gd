extends Node
class_name EscalationDirector

var world: Node = null
var config: GameConfig = null
var match_time_sec: float = 0.0

var _acc_rule_2: float = 0.0
var _acc_rule_3: float = 0.0

func setup(p_world: Node) -> void:
	world = p_world
	config = App.config
	reset_state()
	set_process(true)


func reset_state() -> void:
	match_time_sec = 0.0
	_acc_rule_2 = 0.0
	_acc_rule_3 = 0.0


func _process(delta: float) -> void:
	if world == null or config == null:
		return

	match_time_sec += delta

	_tick_rule(delta, config.rule_2_enabled, config.rule_2_period_sec, "_acc_rule_2", "rule_infinite_spawn_tick")
	_tick_rule(delta, config.rule_3_enabled, config.rule_3_period_sec, "_acc_rule_3", "rule_speed_rain_tick")


func _tick_rule(delta: float, enabled: bool, period_sec: float, acc_name: StringName, method_name: StringName) -> void:
	if not enabled:
		return
	if period_sec <= 0.0:
		return
	if world == null:
		return
	if not world.has_method(method_name):
		return

	var acc: float = get(acc_name) + delta
	while acc >= period_sec:
		acc -= period_sec
		world.call(method_name)
	set(acc_name, acc)
