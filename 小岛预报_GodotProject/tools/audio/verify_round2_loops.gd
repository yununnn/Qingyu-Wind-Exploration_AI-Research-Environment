extends SceneTree
## 检查实际 SFX 混音输出，避免只验证播放信号却没有可听声音。

func _initialize() -> void:
	call_deferred("_run")


func _measure(capture: AudioEffectCapture, duration: float) -> Dictionary:
	capture.clear_buffer()
	await create_timer(duration).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var energy := 0.0
	for sample in samples:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		energy += (sample.x * sample.x + sample.y * sample.y) * 0.5
	return {"frames": samples.size(), "peak": peak, "rms": sqrt(energy / maxf(samples.size(), 1.0))}


func _run() -> void:
	await process_frame
	var audio := root.get_node("AudioManager")
	var source := Node2D.new()
	root.add_child(source)
	current_scene = source
	var camera := Camera2D.new()
	source.add_child(camera)
	camera.make_current()
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var bus := AudioServer.get_bus_index("SFX")
	AudioServer.add_bus_effect(bus, capture)
	await create_timer(0.1).timeout
	var result := {"loops": {}, "driver": AudioServer.get_driver_name(), "passed": true}
	for id: String in ["harvest_work", "data_absorb"]:
		audio.start_loop(id, source)
		var playing: Dictionary = await _measure(capture, 0.7)
		audio.stop_loop(source)
		await create_timer(0.15).timeout
		var stopped: Dictionary = await _measure(capture, 0.3)
		var reference := AudioStreamPlayer.new()
		reference.stream = load("res://assets/audio/sfx/" + id + ".wav")
		reference.volume_db = -2.0
		reference.bus = "SFX"
		source.add_child(reference)
		reference.play()
		var flat: Dictionary = await _measure(capture, 0.7)
		reference.stop()
		reference.queue_free()
		var passed: bool = playing.frames > 0 and playing.rms > 0.005 and playing.peak < 0.9 and stopped.peak < 0.0001 and absf(playing.peak - flat.peak) < 0.015
		result.loops[id] = {"playing": playing, "stopped": stopped, "audition_reference": flat, "passed": passed}
		result.passed = result.passed and passed
	var file := FileAccess.open("res://docs/audio/validation/round2_loop_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ROUND2_LOOP_RESULT ", JSON.stringify(result))
	source.queue_free()
	await process_frame
	quit(0 if result.passed else 1)
