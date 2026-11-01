extends Node
## 本关卡的声音入口；音乐与环境跨场景保留，地点短音效在切场景时清理。

signal cue_played(cue: String)

const ROOT := "res://assets/audio/"
const MUSIC := {
	"farm": "music/island_morning.ogg",
	"lab": "music/forecast_office.ogg",
	"field": "music/prepare_again.ogg",
	"ending": "music/ready.ogg",
}
const AMBIENCE := ["island_wind", "shore", "rain", "storm_wind", "equipment", "boat_water"]
const VARIANTS := {"step_soft": 4, "step_wood": 3, "step_hard": 3, "harvest": 3, "land": 2, "pickup": 3, "deposit": 2, "bird": 2, "text_tick": 4}
const COOLDOWNS := {"task": 0.6, "deposit": 0.13, "pickup": 0.09, "data_open": 0.5, "chest_open": 0.3, "chest_close": 0.3, "door_open": 0.3, "door_close": 0.3, "text_tick": 0.05}

var profile: String = ""
var storm_strength: float = 0.0
var quiet: bool = false
var _music: Array[AudioStreamPlayer] = []
var _music_slot := 0
var _music_id := ""
var _ambience: Dictionary = {}
var _streams: Dictionary = {}
var _fades: Dictionary = {}
var _last_played: Dictionary = {}
var _last_variant: Dictionary = {}
var _loops: Dictionary = {}
var _world: Node2D
var _ui: Node
var _dialogue_active := false
var _duck_tween: Tween
var _bird_wait := 14.0
var _warning := false


func _ready() -> void:
	_world = Node2D.new()
	_world.name = "WorldSounds"
	add_child(_world)
	_ui = Node.new()
	_ui.name = "UISounds"
	add_child(_ui)
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "Music" + str(i)
		player.bus = "Music"
		player.volume_linear = 0.0
		add_child(player)
		_music.append(player)
	for id: String in AMBIENCE:
		var player := AudioStreamPlayer.new()
		player.name = id
		player.bus = "Ambience"
		player.stream = _stream("ambience/" + id + ".ogg")
		(player.stream as AudioStreamOggVorbis).loop = true
		player.volume_linear = 0.0
		add_child(player)
		_ambience[id] = player
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _process(delta: float) -> void:
	for key: int in _loops.keys():
		if not is_instance_valid(_loops[key]):
			_loops.erase(key)
	if profile not in ["farm", "field"]:
		return
	_bird_wait -= delta
	if _bird_wait <= 0.0:
		_bird_wait = randf_range(15.0, 29.0)
		var player := get_tree().get_first_node_in_group("Player") as Node2D
		if player != null:
			play_sfx("bird", player.global_position + Vector2(randf_range(-90.0, 90.0), -60.0), -16.0)


func enter_farm() -> void:
	clear_world_sounds()
	if GameState.is_first_farm:
		set_profile("intro")
	elif GameState.step <= 3:
		set_profile("after_storm")
	else:
		set_profile("field")


func enter_lab() -> void:
	clear_world_sounds()
	set_profile("lab")


func set_profile(id: String) -> void:
	profile = id
	quiet = false
	var track := ""
	var level := -6.0
	var ambience: Dictionary = {}
	match id:
		"farm":
			track = "farm"
			level = -5.0
			ambience = {"island_wind": 0.55, "shore": 0.5}
		"storm":
			ambience = {"island_wind": 0.3, "shore": 0.55}
		"after_storm":
			ambience = {"island_wind": 0.3, "shore": 0.45}
		"field":
			track = "field"
			ambience = {"island_wind": 0.45, "shore": 0.45}
		"lab":
			track = "lab"
			level = -9.0
			ambience = {"equipment": 0.75}
		"travel":
			ambience = {"boat_water": 0.9}
		"ending":
			track = "ending"
			level = -4.0
	_play_music(track, level, 1.5 if id == "storm" else 1.2)
	for name: String in AMBIENCE:
		_fade(_ambience[name], float(ambience.get(name, 0.0)), 0.8)
	if id != "storm":
		storm_strength = 0.0
	_update_duck()


## 直接由农场现有的雨量 Tween 驱动，不另设天气计时器。
func set_storm_strength(value: float) -> void:
	storm_strength = clampf(value, 0.0, 1.0)
	for id: String in ["rain", "storm_wind"]:
		var player: AudioStreamPlayer = _ambience[id]
		_cancel_fade(player)
		player.volume_linear = storm_strength * (0.9 if id == "rain" else 0.7)
		if storm_strength > 0.0 and not player.playing:
			player.play()
		elif storm_strength <= 0.0:
			player.stop()


func set_quiet(value: bool) -> void:
	quiet = value
	_update_duck()


func _on_dialogue_started(_resource: DialogueResource) -> void:
	_dialogue_active = true
	_update_duck()


func _on_dialogue_ended(_resource: DialogueResource) -> void:
	_dialogue_active = false
	_update_duck()


func _update_duck() -> void:
	if _duck_tween != null:
		_duck_tween.kill()
	var target := (-4.0 if _dialogue_active else 0.0) + (-10.0 if quiet else 0.0) + (-5.0 if _warning else 0.0)
	var bus := AudioServer.get_bus_index("Music")
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(bus, db), AudioServer.get_bus_volume_db(bus), target, 0.3)


func play_warning() -> void:
	_warning = true
	_update_duck()
	play_sfx("warning")
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		_warning = false
		_update_duck()
	)


func _play_music(id: String, level: float, duration: float) -> void:
	if id.is_empty():
		_music_id = ""
		for player in _music:
			_fade(player, 0.0, duration)
		return
	if _music_id != id:
		_music_slot = 1 - _music_slot
		var player := _music[_music_slot]
		_cancel_fade(player)
		player.stop()
		player.stream = _stream(MUSIC[id])
		(player.stream as AudioStreamOggVorbis).loop = id != "ending"
		player.volume_linear = 0.0
		player.play()
		_music_id = id
		cue_played.emit("music_" + id)
	_fade(_music[_music_slot], db_to_linear(level), duration)
	_fade(_music[1 - _music_slot], 0.0, duration)


func _cancel_fade(player: AudioStreamPlayer) -> void:
	var key := player.get_instance_id()
	if _fades.has(key):
		(_fades[key] as Tween).kill()
		_fades.erase(key)


func _fade(player: AudioStreamPlayer, gain: float, duration: float) -> void:
	_cancel_fade(player)
	if gain > 0.0 and not player.playing:
		player.play()
	var tween := create_tween()
	_fades[player.get_instance_id()] = tween
	tween.tween_property(player, "volume_linear", gain, duration)
	if gain == 0.0:
		tween.tween_callback(player.stop)


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(ROOT + path)
	return _streams[path] as AudioStream


func play_typewriter(letter: String) -> void:
	if letter.strip_edges().is_empty() or "，。！？；：、…—“”‘’（）【】.,!?;:\"'()[]".contains(letter):
		return
	play_sfx("text_tick", null, -5.0)


## position 为 null 的提示音居中；其余短音效由独立节点播完，不依赖道具寿命。
func play_sfx(id: String, position: Variant = null, level: float = 0.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if id == "task" and profile == "ending":
		return
	if now - float(_last_played.get(id, -100.0)) < float(COOLDOWNS.get(id, 0.04)):
		return
	_last_played[id] = now
	if id in ["data_all", "warning", "happy", "surprised", "angry", "awkward"]:
		_last_played["task"] = now + 0.6
	var filename := id
	if VARIANTS.has(id):
		var count: int = VARIANTS[id]
		var index := (int(_last_variant.get(id, -1)) + randi_range(1, count - 1)) % count
		_last_variant[id] = index
		filename += "_%02d" % (index + 1)
	var player: Variant
	if position != null:
		if _world.get_child_count() >= 16:
			return
		player = AudioStreamPlayer2D.new()
		player.bus = "SFX"
		player.max_distance = 320.0
		player.attenuation = 0.6
		player.panning_strength = 0.35
		_world.add_child(player)
		player.global_position = position
	else:
		player = AudioStreamPlayer.new()
		player.bus = "UI"
		_ui.add_child(player)
	player.stream = _stream("sfx/" + filename + ".wav")
	player.volume_db = level
	if VARIANTS.has(id) and id != "bird":
		player.pitch_scale = randf_range(0.97, 1.03)
	player.finished.connect(player.queue_free)
	player.play()
	cue_played.emit(id)


func start_loop(id: String, source: Node2D) -> void:
	var key := source.get_instance_id()
	if _loops.has(key) and is_instance_valid(_loops[key]):
		return
	var player := AudioStreamPlayer2D.new()
	var stream := _stream("sfx/" + id + ".wav").duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	player.stream = stream
	player.bus = "SFX"
	# 2D 居中时每声道减半，补偿后与用户确认的 -2 dB 试听一致。
	player.volume_db = -2.0 + linear_to_db(2.0)
	player.max_distance = 240.0
	player.panning_strength = 0.35
	source.add_child(player)
	_loops[key] = player
	player.play()
	cue_played.emit(id)


func stop_loop(source: Node2D) -> void:
	var key := source.get_instance_id()
	if _loops.has(key):
		if is_instance_valid(_loops[key]):
			_loops[key].stop()
			_loops[key].queue_free()
		_loops.erase(key)


func clear_world_sounds() -> void:
	for child in _world.get_children():
		child.stop()
		child.queue_free()
	for player: Variant in _loops.values():
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_loops.clear()


func fade_out_all(duration: float = 0.5) -> void:
	clear_world_sounds()
	for child in _ui.get_children():
		child.stop()
	for player in _music:
		_fade(player, 0.0, duration)
	for player: AudioStreamPlayer in _ambience.values():
		_fade(player, 0.0, duration)
	await get_tree().create_timer(duration).timeout


