extends Resource
class_name GameRuleEvent

enum RuleType {
	NONE = 0,
	RULE_1_PARTICIPANT_SIZE = 1,
	RULE_2_PARTICIPANT_SPEED = 2,
	RULE_3_PARTICIPANT_COUNT = 3,
	RULE_4_SPAWN_PRESSURE = 4,
	RULE_5_SPEED_RAIN = 5
}

@export var start_time_sec: float = 0.0
@export var duration_sec: float = 0.0 # 0 means infinite
@export var rule_index: RuleType = RuleType.NONE
