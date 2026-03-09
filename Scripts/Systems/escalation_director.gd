extends Node
class_name EscalationDirector

var world: Node = null
var config: GameConfig = null
var match_time_sec: float = 0.0

var _acc_rule_4: float = 0.0
var _acc_rule_5: float = 0.0
var _rule_4_started: bool = false
var _active_rules: Dictionary = {} # RuleType -> bool

func setup(p_world: Node) -> void:
	world = p_world
	config = App.config
	reset_state()
	set_process(true)


func reset_state() -> void:
	match_time_sec = 0.0
	_acc_rule_4 = 0.0
	_acc_rule_5 = 0.0
	_rule_4_started = false
	_active_rules.clear()

	if config != null:
		_active_rules[GameRuleEvent.RuleType.RULE_1_PARTICIPANT_SIZE] = config.rule_1_enabled
		_active_rules[GameRuleEvent.RuleType.RULE_2_PARTICIPANT_SPEED] = config.rule_2_enabled
		_active_rules[GameRuleEvent.RuleType.RULE_3_PARTICIPANT_COUNT] = config.rule_3_enabled
		_active_rules[GameRuleEvent.RuleType.RULE_4_SPAWN_PRESSURE] = config.rule_4_enabled
		_active_rules[GameRuleEvent.RuleType.RULE_5_SPEED_RAIN] = config.rule_5_enabled


func is_rule_active(rule_type: GameRuleEvent.RuleType) -> bool:
	return _active_rules.get(rule_type, false)


func _process(delta: float) -> void:
	if world == null or config == null:
		return

	match_time_sec += delta

	_process_automation()

	_tick_rule_4(delta)
	_tick_rule(delta, is_rule_active(GameRuleEvent.RuleType.RULE_5_SPEED_RAIN), config.rule_5_period_sec, "_acc_rule_5", "rule_speed_rain_tick")


func _process_automation() -> void:
	if not config.automation_preset_enabled or config.automation_timeline.is_empty():
		return

	# Reset all to false when automation is tracking and override them
	for k in _active_rules.keys():
		_active_rules[k] = false

	for event in config.automation_timeline:
		if event == null or event.rule_index == GameRuleEvent.RuleType.NONE:
			continue
		
		var start: float = event.start_time_sec
		var duration: float = event.duration_sec
		
		if match_time_sec >= start:
			if duration <= 0.0 or match_time_sec <= (start + duration):
				_active_rules[event.rule_index] = true


func _tick_rule_4(delta: float) -> void:
	if not is_rule_active(GameRuleEvent.RuleType.RULE_4_SPAWN_PRESSURE):
		return

	if not _rule_4_started:
		_rule_4_started = true

	_tick_rule(delta, true, config.rule_4_period_sec, "_acc_rule_4", "rule_infinite_spawn_tick")


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
