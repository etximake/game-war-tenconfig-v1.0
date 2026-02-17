# res://Scripts/KillSfx.gd
extends Node
class_name KillSfx

const BUS_NAME := "KILL"

# Giảm spam khi 20-30 marble
const MIN_INTERVAL := 0.12  # 120ms: đủ nghe rõ nhưng không loạn

# Pool player để phát chồng 1 chút (nhưng vẫn có rate-limit)
const POOL_SIZE := 8

# Tuning tổng
const BASE_VOLUME_DB := -6.0
const SIZE_VOL_DB_MAX := 3.0     # size lớn nhất cộng thêm tối đa ~3dB
const PITCH_JITTER := 0.04       # ±4%

var _streams: Array[AudioStream] = []
var _players: Array[AudioStreamPlayer2D] = []
var _last_play_time := -999.0
var _last_variant := -1
var _pool_i := 0

func _ready() -> void:
	# TODO: sửa list này theo file thật của bạn
	var paths := [
		"res://Assets/Audios/Kills/kill_1.mp3",
		"res://Assets/Audios/Kills/kill_2.mp3",
		"res://Assets/Audios/Kills/kill_3.mp3",
		#"res://Assets/Audios/Kills/kill_5.mp3",
	]

	for p in paths:
		if ResourceLoader.exists(p):
			_streams.append(load(p))

	# Pool players
	for i in POOL_SIZE:
		var pl := AudioStreamPlayer2D.new()
		pl.bus = BUS_NAME
		pl.attenuation = 1.0
		pl.max_distance = 2000.0
		pl.panning_strength = 1.0
		add_child(pl)
		_players.append(pl)

func play_kill(world_pos: Vector2, attacker_size_scale: float) -> void:
	if _streams.is_empty():
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_play_time < MIN_INTERVAL:
		return  # rate-limit để không loạn âm khi kill dồn

	_last_play_time = now

	# chọn variant, tránh lặp y chang
	var idx := randi() % _streams.size()
	if _streams.size() >= 2 and idx == _last_variant:
		idx = (idx + 1) % _streams.size()
	_last_variant = idx

	var pl := _players[_pool_i]
	_pool_i = (_pool_i + 1) % _players.size()

	pl.stream = _streams[idx]
	pl.global_position = world_pos

	# scale nhẹ theo size (chỉ tạo cảm giác, không quá tay)
	var t: float = clampf((attacker_size_scale - 1.0) / 2.0, 0.0, 1.0)
	pl.volume_db = BASE_VOLUME_DB + t * SIZE_VOL_DB_MAX

	# pitch jitter nhỏ để đỡ nhàm
	var jitter := randf_range(-PITCH_JITTER, PITCH_JITTER)
	pl.pitch_scale = 1.0 + jitter - (t * 0.06) # size to hơi trầm hơn chút

	pl.play()
