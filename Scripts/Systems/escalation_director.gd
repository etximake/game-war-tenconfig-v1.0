extends Node
class_name EscalationDirector

var world: Node = null
var config: GameConfig = null
var elapsed_sec: float = 0.0

var _acc_rule_1: float = 0.0
var _acc_rule_2: float = 0.0
var _acc_rule_3: float = 0.0
var _acc_rule_5: float = 0.0
var _acc_rule_6: float = 0.0
var _acc_rule_7: float = 0.0
var _acc_rule_8: float = 0.0
var _acc_rule_9: float = 0.0
var _acc_rule_10: float = 0.0

var _spawned_giant_once: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(p_world: Node, p_config: GameConfig) -> void:
	world = p_world
	config = p_config
	elapsed_sec = 0.0
	_spawned_giant_once = false
	_reset_accumulators()
	if int(config.rng_seed) != 0:
		_rng.seed = int(config.rng_seed) + 991
	else:
		_rng.randomize()


func on_tick(delta_sec: float) -> void:
	if world == null or config == null:
		return

	elapsed_sec += max(delta_sec, 0.0)

	_tick_rule_1(delta_sec)
	_tick_rule_2(delta_sec)
	_tick_rule_3(delta_sec)
	_tick_rule_5(delta_sec)
	_tick_rule_6(delta_sec)
	_tick_rule_7(delta_sec)
	_tick_rule_8(delta_sec)
	_tick_rule_9(delta_sec)
	_tick_rule_10(delta_sec)


func _tick_rule_1(delta_sec: float) -> void:
	if not config.rule_1_enabled:
		return
	if _step_period("_acc_rule_1", delta_sec, config.rule_1_period_sec) and _roll_chance(config.rule_1_chance):
		world.call("rule_speed_ramp_tick")


func _tick_rule_2(delta_sec: float) -> void:
	if not config.rule_2_enabled:
		return

	var dt: float = delta_sec
	if world.has_method("get_finale_shrink_factor"):
		dt *= float(world.call("get_finale_shrink_factor"))

	if _step_period("_acc_rule_2", dt, config.rule_2_period_sec) and _roll_chance(config.rule_2_chance):
		world.call("rule_shrink_tick")


func _tick_rule_3(delta_sec: float) -> void:
	if not config.rule_3_enabled:
		return
	if _spawned_giant_once:
		return
	if _step_period("_acc_rule_3", delta_sec, config.rule_3_period_sec) and _roll_chance(config.rule_3_chance):
		world.call("rule_spawn_giant_once")
		_spawned_giant_once = true


func _tick_rule_5(delta_sec: float) -> void:
	if not config.rule_5_enabled:
		return
	if _step_period("_acc_rule_5", delta_sec, config.rule_5_period_sec) and _roll_chance(config.rule_5_chance):
		world.call("rule_milestone_spawn_tick")


func _tick_rule_6(delta_sec: float) -> void:
	if not config.rule_6_enabled:
		return
	if _step_period("_acc_rule_6", delta_sec, config.rule_6_period_sec) and _roll_chance(config.rule_6_chance):
		world.call("rule_underdog_buff_tick")


func _tick_rule_7(delta_sec: float) -> void:
	if not config.rule_7_enabled:
		return
	if _step_period("_acc_rule_7", delta_sec, config.rule_7_period_sec) and _roll_chance(config.rule_7_chance):
		world.call("rule_burst_tick")


func _tick_rule_8(delta_sec: float) -> void:
	if not config.rule_8_enabled:
		return
	if _step_period("_acc_rule_8", delta_sec, config.rule_8_period_sec) and _roll_chance(config.rule_8_chance):
		world.call("rule_edge_decay_tick")


func _tick_rule_9(delta_sec: float) -> void:
	if not config.rule_9_enabled:
		return
	if _step_period("_acc_rule_9", delta_sec, config.rule_9_period_sec) and _roll_chance(config.rule_9_chance):
		world.call("rule_finale_check_tick")


func _tick_rule_10(delta_sec: float) -> void:
	if not config.rule_10_enabled:
		return
	if _step_period("_acc_rule_10", delta_sec, config.rule_10_period_sec) and _roll_chance(config.rule_10_chance):
		world.call("rule_random_event_tick")


func _step_period(acc_name: String, delta_sec: float, period_sec: float) -> bool:
	if period_sec <= 0.0:
		return false

	var acc: float = float(get(acc_name)) + max(delta_sec, 0.0)
	if acc < period_sec:
		set(acc_name, acc)
		return false

	set(acc_name, 0.0)
	return true


func _roll_chance(chance: float) -> bool:
	var c: float = clamp(chance, 0.0, 1.0)
	if c <= 0.0:
		return false
	if c >= 1.0:
		return true
	return _rng.randf() <= c


func _reset_accumulators() -> void:
	_acc_rule_1 = 0.0
	_acc_rule_2 = 0.0
	_acc_rule_3 = 0.0
	_acc_rule_5 = 0.0
	_acc_rule_6 = 0.0
	_acc_rule_7 = 0.0
	_acc_rule_8 = 0.0
	_acc_rule_9 = 0.0
	_acc_rule_10 = 0.0


func on_marble_team_changed(marble: Marble, new_team: int) -> void:
	if world == null or config == null:
		return
	if marble == null:
		return
	if not config.rule_4_enabled:
		return
	if not _roll_chance(config.rule_4_chance):
		return
	world.call("rule_explosion_on_death", marble.global_position, new_team)
