extends Node
class_name EscalationDirector

var world: Node = null
var config: GameConfig = null
var match_time_sec: float = 0.0

var _acc_rule_1: float = 0.0
var _acc_rule_2: float = 0.0
var _acc_rule_3: float = 0.0
var _acc_rule_5: float = 0.0
var _acc_rule_6: float = 0.0
var _acc_rule_7: float = 0.0
var _acc_rule_8: float = 0.0
var _acc_rule_9: float = 0.0
var _acc_rule_10: float = 0.0

func setup(p_world: Node) -> void:
	world = p_world
	config = App.config
	reset_state()
	set_process(true)


func reset_state() -> void:
	match_time_sec = 0.0
	_acc_rule_1 = 0.0
	_acc_rule_2 = 0.0
	_acc_rule_3 = 0.0
	_acc_rule_5 = 0.0
	_acc_rule_6 = 0.0
	_acc_rule_7 = 0.0
	_acc_rule_8 = 0.0
	_acc_rule_9 = 0.0
	_acc_rule_10 = 0.0


func _process(delta: float) -> void:
	if world == null or config == null:
		return

	match_time_sec += delta

	_tick_rule(delta, config.rule_1_enabled, config.rule_1_period_sec, "_acc_rule_1", "rule_speed_ramp_tick")
	_tick_rule(delta, config.rule_2_enabled, config.rule_2_period_sec, "_acc_rule_2", "rule_shrink_tick")
	_tick_rule(delta, config.rule_3_enabled, config.rule_3_period_sec, "_acc_rule_3", "rule_spawn_giant_once")
	_tick_rule(delta, config.rule_5_enabled, config.rule_5_period_sec, "_acc_rule_5", "rule_milestone_spawn_tick")
	_tick_rule(delta, config.rule_6_enabled, config.rule_6_period_sec, "_acc_rule_6", "rule_underdog_buff_tick")
	_tick_rule(delta, config.rule_7_enabled, config.rule_7_period_sec, "_acc_rule_7", "rule_burst_tick")
	_tick_rule(delta, config.rule_8_enabled, config.rule_8_period_sec, "_acc_rule_8", "rule_edge_decay_tick")
	_tick_rule(delta, config.rule_9_enabled, config.rule_9_period_sec, "_acc_rule_9", "rule_finale_check_tick")
	_tick_rule(delta, config.rule_10_enabled, config.rule_10_period_sec, "_acc_rule_10", "rule_random_event_tick")


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
