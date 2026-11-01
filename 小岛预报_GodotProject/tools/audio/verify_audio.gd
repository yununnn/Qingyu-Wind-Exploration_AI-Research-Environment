extends SceneTree
## 场景级回归：真实输入、实际动作完成回调与音频总线采样。
## godot --path . --script res://tools/audio/verify_audio.gd -- --suite-only

var failures: Array[String] = []
var checks: Array[String] = []
var cues: Dictionary = {}
var audio: Node
var state: Node
var world: Node2D
var output := "res://docs/audio/validation"
var capture: AudioEffectCapture
var mix_peak := 0.0
var mix_frames := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	checks.append(label)
	if not condition:
		failures.append(label)
	print("AUDIO_CHECK ", "PASS " if condition else "FAIL ", label)


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func until(predicate: Callable, seconds: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await wait(0.05)
	var passed: bool = predicate.call()
	check(passed, label)
	return passed


func sample_mix() -> void:
	var frames := capture.get_frames_available()
	if frames > 0:
		var buffer := capture.get_buffer(frames)
		mix_frames += buffer.size()
		for frame in buffer:
			mix_peak = maxf(mix_peak, maxf(absf(frame.x), absf(frame.y)))


func snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	audio = root.get_node("AudioManager")
	state = root.get_node("GameState")
	audio.cue_played.connect(func(id: String) -> void: cues[id] = int(cues.get(id, 0)) + 1)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 10.0
	AudioServer.add_bus_effect(0, capture)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	if "--intern-only" in OS.get_cmdline_user_args():
		state.step = 6
		state.is_first_farm = false
		change_scene_to_file("res://scenes/laboratory/laboratory.tscn")
		await scene_changed
		await wait(1.3)
		var intern = current_scene.get_node("Scene/Decoration/椅子/椅子2_实习生之椅/Intern")
		var rabbit = get_first_node_in_group("Player")
		rabbit.global_position = intern.global_position + Vector2(0, 20)
		await wait(0.3)
		check(intern.is_entered and not intern.is_dialogue_active, "intern ready for actual interaction")
		await process_frame
		Input.action_press("interact")
		await wait(0.1)
		Input.action_release("interact")
		await until(func() -> bool: return state.step == 7, 60.0, "intern interaction reaches step 7")
		check(int(cues.get("warning", 0)) == 1, "warning is emitted once by the actual dialogue")
		sample_mix()
		await snapshot("06_warning")
		await audio.fade_out_all(0.1)
		_finish()
		return
	if "--story-only" in OS.get_cmdline_user_args():
		await _story()
		return
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	var loaded := 0
	for entry: Dictionary in manifest:
		var stream := load("res://assets/audio/" + entry.file) as AudioStream
		if stream != null and stream.get_length() > 0.05:
			loaded += 1
	check(loaded == manifest.size(), "all catalog audio assets load with nonzero duration")
	check(AudioServer.bus_count == 5, "Master + Music/Ambience/SFX/UI buses")
	audio.set_profile("farm")
	await wait(1.5)
	var music: AudioStreamPlayer = audio._music[audio._music_slot]
	var before := music.get_playback_position()
	audio.set_profile("farm")
	await wait(0.25)
	check(music.get_playback_position() > before, "same music request preserves playback position")
	sample_mix()
	check(mix_frames > 0 and mix_peak > 0.001, "real mixer produces non-silent output")
	audio.set_profile("lab")
	await wait(0.1)
	audio.set_profile("field")
	await wait(1.5)
	var playing := 0
	for player: AudioStreamPlayer in audio._music:
		if player.playing:
			playing += 1
	check(playing == 1, "rapid music changes leave one playing track after crossfade")
	audio.set_profile("storm")
	for amount in [0.0, 0.25, 0.75, 1.0, 0.4, 0.0]:
		audio.set_storm_strength(amount)
		await wait(0.08)
		check(is_equal_approx(audio._ambience.rain.volume_linear, amount * 0.9), "rain follows weather strength " + str(amount))
	check(not audio._ambience.rain.playing and not audio._ambience.storm_wind.playing, "zero weather strength stops wind and rain")
	audio._on_dialogue_started(null)
	await wait(0.4)
	check(is_equal_approx(AudioServer.get_bus_volume_db(1), -4.0), "dialogue ducks music 4 dB")
	audio.set_quiet(true)
	await wait(0.4)
	check(is_equal_approx(AudioServer.get_bus_volume_db(1), -14.0), "awkward pause applies extra 10 dB duck")
	audio.set_quiet(false)
	audio._on_dialogue_ended(null)
	await wait(0.4)
	check(absf(AudioServer.get_bus_volume_db(1)) < 0.01, "dialogue music level restores")
	var start := Time.get_ticks_msec()
	audio.play_warning()
	check(Time.get_ticks_msec() - start < 100, "warning cue does not block the dialogue line")
	await wait(1.3)
	var rabbit = load("res://scenes/characters/rabbit.tscn").instantiate()
	world.add_child(rabbit)
	rabbit.collision_mask = 0
	root.get_node("PlayerState").current_state = 0
	Input.action_press("move_right")
	await wait(0.8)
	Input.action_release("move_right")
	await wait(0.1)
	var steps := int(cues.get("step_soft", 0))
	check(steps > 0, "actual player movement emits footstep cues")
	await wait(0.4)
	check(int(cues.get("step_soft", 0)) == steps, "standing still emits no footsteps")
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 64)
	shape.shape = rectangle
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = rabbit.global_position + Vector2(18, 0)
	rabbit.collision_mask = 1
	Input.action_press("move_right")
	await wait(0.8)
	steps = int(cues.get("step_soft", 0))
	await wait(0.4)
	check(int(cues.get("step_soft", 0)) == steps, "holding direction against a wall emits no footsteps")
	Input.action_release("move_right")
	wall.queue_free()
	rabbit.collision_mask = 0
	for material: String in ["wood", "hard"]:
		rabbit.set_meta("footstep_surface", material)
		Input.action_press("move_right")
		await wait(0.6)
		Input.action_release("move_right")
		await wait(0.1)
		check(int(cues.get("step_" + material, 0)) > 0, "actual movement plays " + material + " surface footsteps")
	rabbit.set_meta("footstep_surface", "soft")
	var crop = load("res://scenes/fram/农作物/胡萝卜.tscn").instantiate()
	crop.stage = crop.get_max_stage()
	world.add_child(crop)
	crop.global_position = rabbit.global_position
	await wait(0.1)
	Input.action_press("interact")
	await wait(0.2)
	Input.action_release("interact")
	await wait(0.1)
	check(not audio._loops.has(crop.get_instance_id()) and is_instance_valid(crop), "cancelled harvest stops loop without completing")
	Input.action_press("interact")
	await wait(1.2)
	Input.action_release("interact")
	check(not is_instance_valid(crop) and int(cues.get("harvest", 0)) == 1, "completed harvest emits once and frees crop")
	await wait(0.3)
	var drops := get_nodes_in_group("drop")
	check(drops.size() == 1 and int(cues.get("land", 0)) == 1, "drop landing sound survives crop deletion")
	if drops.size() == 1:
		var drop = drops[0]
		state.step = 6
		drop._pick_up()
		check(state.carrots_held == 0 and not cues.has("pickup"), "locked pickup emits no success sound")
		state.step = 7
		drop._pick_up()
		check(state.carrots_held == 1 and int(cues.get("pickup", 0)) == 1, "successful pickup increments count and plays once")
	var chest = load("res://scenes/fram/house/chest/chest.tscn").instantiate()
	world.add_child(chest)
	chest.global_position = rabbit.global_position
	await wait(0.15)
	state.carrots_held = 20
	state.carrots_required = 0
	state.carrots_in_chest = 0
	chest._deposit_all()
	chest._deposit_all()
	await wait(1.9)
	check(state.carrots_in_chest == 20 and state.carrots_held == 0, "repeated deposit request deposits each carrot once")
	check(int(cues.get("deposit", 0)) > 0 and int(cues.get("deposit", 0)) <= 10, "20 carrot landings are rate limited")
	var door = load("res://scenes/fram/house/door/door.tscn").instantiate()
	world.add_child(door)
	chest._on_body_exited(rabbit)
	chest._on_body_entered(rabbit)
	door.open_door(rabbit)
	door.close_door(rabbit)
	door.open_door(rabbit)
	await wait(1.2)
	check(door._door_open and int(cues.get("door_open", 0)) == 1, "rapid door crossings retain latest open state with one cue")
	check(chest._lid_open, "rapid chest crossings retain latest open state")
	door.close_door(rabbit)
	await wait(0.8)
	door.close_door(rabbit)
	await wait(0.1)
	check(not door._door_open and int(cues.get("door_close", 0)) == 1, "repeated door close does not replay its cue")
	var task_count := int(cues.get("task", 0))
	audio.play_sfx("data_all")
	audio.play_sfx("task")
	check(int(cues.get("task", 0)) == task_count, "data completion suppresses duplicate task cue")
	audio.start_loop("harvest_work", chest)
	audio.play_sfx("harvest", rabbit.global_position)
	audio.clear_world_sounds()
	await process_frame
	check(audio._loops.is_empty() and audio._world.get_child_count() == 0, "scene cleanup removes source loops and world one-shots")
	state.is_first_farm = false
	state.step = 7
	audio.enter_farm()
	await wait(1.0)
	check(audio.profile == "field" and not audio._ambience.rain.playing, "future storm warning does not cause rain on return")
	sample_mix()
	check(mix_peak < 0.9, "captured output remains below limiter ceiling")
	if "--suite-only" not in OS.get_cmdline_user_args() and failures.is_empty():
		await _story()
	else:
		await audio.fade_out_all(0.1)
		world.queue_free()
		await process_frame
		_finish()


func _story() -> void:
	# 定位到交互点，但保留真实采集、自动对话、天气、场景切换和结束流程。
	var data_all_before := int(cues.get("data_all", 0))
	state.is_first_farm = true
	state.step = 0
	state.carrots_held = 0
	state.carrots_required = 0
	state.carrots_in_chest = 0
	change_scene_to_file("res://scenes/fram/farm.tscn")
	await scene_changed
	if not await until(func() -> bool: return not state.is_first_farm, 60.0, "story opening and first dialogue finish"):
		_finish()
		return
	await snapshot("01_farm")
	var farm = current_scene
	var rabbit = get_first_node_in_group("Player")
	rabbit.global_position = farm.tip_location_farmland.global_position
	if not await until(func() -> bool: return state.step == 1, 5.0, "farmland area triggers tutorial"):
		_finish()
		return
	await until(func() -> bool: return root.get_node("PlayerState").current_state == 0, 15.0, "harvest tutorial dialogue finishes")
	for i in range(2):
		var target: Node2D
		for crop in farm.crops_root.get_children():
			if crop.is_mature():
				target = crop
				break
		rabbit.global_position = target.global_position + Vector2(0, 9)
		await wait(0.2)
		Input.action_press("interact")
		await wait(1.2)
		Input.action_release("interact")
		await wait(0.1)
	await until(func() -> bool: return audio.storm_strength > 0.5, 12.0, "two harvests trigger actual storm tween")
	await snapshot("02_storm")
	await until(func() -> bool: return state.step == 3 and root.get_node("PlayerState").current_state == 0, 40.0, "storm and complaint preparation finish")
	await snapshot("03_after_storm")
	rabbit.global_position = farm.get_node("Boat/Detection").global_position
	if not await until(func() -> bool: return current_scene.scene_file_path.ends_with("laboratory.tscn"), 12.0, "boat area performs actual scene transition"):
		_finish()
		return
	await until(func() -> bool: return state.step == 4 and audio.quiet, 60.0, "laboratory story reaches awkward pause")
	await snapshot("04_office")
	if not await until(func() -> bool: return root.get_node("TaskPanel").label.text == "回到农场，收集数据", 120.0, "director explanation finishes"):
		_finish()
		return
	var lab = current_scene
	rabbit = get_first_node_in_group("Player")
	rabbit.global_position = lab.get_node("Scene/Door").global_position
	if not await until(func() -> bool: return current_scene.scene_file_path.ends_with("farm.tscn"), 12.0, "laboratory exit returns to farm"):
		_finish()
		return
	await wait(1.5)
	farm = current_scene
	rabbit = get_first_node_in_group("Player")
	for point in get_nodes_in_group("collection_point"):
		rabbit.global_position = point.global_position
		await wait(0.2)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_X
		key.pressed = true
		Input.parse_input_event(key)
		await wait(2.3)
		key = InputEventKey.new()
		key.physical_keycode = KEY_X
		key.pressed = false
		Input.parse_input_event(key)
	check(state.step == 6, "all three data points complete through X input")
	check(int(cues.get("data_done", 0)) == 2 and int(cues.get("data_all", 0)) == data_all_before + 1, "last data point uses one all-complete cue")
	await snapshot("05_data_complete")
	rabbit.global_position = farm.get_node("Boat/Detection").global_position
	await until(func() -> bool: return current_scene.scene_file_path.ends_with("laboratory.tscn"), 12.0, "second boat visit reaches laboratory")
	await wait(1.2)
	var intern = current_scene.get_node("Scene/Decoration/椅子/椅子2_实习生之椅/Intern")
	rabbit = get_first_node_in_group("Player")
	rabbit.global_position = intern.global_position + Vector2(0, 20)
	await wait(0.3)
	check(intern.is_entered, "player reaches intern interaction range without overlapping chair")
	await process_frame
	Input.action_press("interact")
	await wait(0.1)
	Input.action_release("interact")
	if not await until(func() -> bool: return state.step == 7, 60.0, "actual intern dialogue reaches future storm warning"):
		_finish()
		return
	await snapshot("06_warning")
	rabbit.global_position = current_scene.get_node("Scene/Door").global_position
	await until(func() -> bool: return current_scene.scene_file_path.ends_with("farm.tscn"), 12.0, "return to farm for advance harvest")
	await wait(1.3)
	farm = current_scene
	rabbit = get_first_node_in_group("Player")
	check(not audio._ambience.rain.playing, "advance harvest has no present rain")
	for attempt in range(20):
		if state.carrots_held >= state.carrots_required:
			break
		var target: Node2D
		for crop in farm.crops_root.get_children():
			if crop.name.begins_with("胡萝卜") and crop.is_mature():
				target = crop
				break
		if target == null:
			break
		var position := target.global_position
		rabbit.global_position = position + Vector2(0, 9)
		await wait(0.15)
		Input.action_press("interact")
		await wait(1.15)
		Input.action_release("interact")
		await wait(0.1)
		rabbit.global_position = position
		await wait(0.15)
		await process_frame
		Input.action_press("interact")
		await wait(0.1)
		Input.action_release("interact")
		await wait(0.1)
	# 碰撞恢复可能改变最近作物；按实际掉落位置补捡，避免以原作物坐标猜测。
	for drop in get_nodes_in_group("drop"):
		if not is_instance_valid(drop) or state.carrots_held >= state.carrots_required:
			continue
		rabbit.global_position = drop.global_position
		await wait(0.2)
		await process_frame
		Input.action_press("interact")
		await wait(0.15)
		Input.action_release("interact")
		await wait(0.1)
	check(state.carrots_held >= state.carrots_required and state.carrots_required > 0, "actual harvest and pickup collect required carrots")
	var chest = farm.get_node("排序层/House/装饰/Chest")
	rabbit.global_position = chest.global_position + Vector2(0, 8)
	await wait(0.3)
	await process_frame
	Input.action_press("interact")
	await wait(0.1)
	Input.action_release("interact")
	if not await until(func() -> bool: return audio.profile == "ending", 8.0, "actual deposit starts ending music"):
		_finish()
		return
	await wait(3.2)
	await snapshot("07_ending")
	sample_mix()
	_finish(false)
	# 箱子脚本继续执行结束文字、淡出并退出；报告在退出前已落盘。


func _finish(exit_now: bool = true) -> void:
	var mode := "suite and story with interaction-point positioning"
	if "--suite-only" in OS.get_cmdline_user_args():
		mode = "suite"
	elif "--story-only" in OS.get_cmdline_user_args():
		mode = "story with interaction-point positioning"
	elif "--intern-only" in OS.get_cmdline_user_args():
		mode = "isolated intern interaction and dialogue"
	var result := {"checks": checks.size(), "failures": failures, "cues": cues, "mix_frames": mix_frames, "mix_peak": mix_peak, "audio_driver": AudioServer.get_driver_name(), "renderer": RenderingServer.get_current_rendering_method(), "mode": mode}
	var file := FileAccess.open(output.path_join("runtime_results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("AUDIO_VALIDATION ", JSON.stringify(result))
	if exit_now:
		quit(0 if failures.is_empty() else 1)
