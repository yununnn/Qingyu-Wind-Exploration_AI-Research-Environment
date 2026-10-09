extends SceneTree

func _initialize() -> void:
	call_deferred("validate")

func validate() -> void:
	Engine.max_fps = 60
	var scene_path := "res://scenes/weather/ripple_preview.tscn"
	var scene := load(scene_path) as PackedScene
	assert(scene != null)
	var preview := scene.instantiate()
	root.add_child(preview)
	var particles := preview.get_node("Ripple") as GPUParticles2D
	assert(particles.material is ShaderMaterial)
	assert(particles.process_material is ParticleProcessMaterial)
	assert(particles.texture.get_size() == Vector2(32, 32))
	assert(particles.process_material.scale_min == 1.0)
	assert(particles.process_material.scale_max == 1.0)
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	save_preview("res://output/ripple_validation/preview.png")
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	save_preview("res://output/ripple_validation/preview_later.png")
	for i in 16:
		await create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		save_preview("res://output/ripple_validation/motion_%02d.png" % i)

	# 固定生命周期的 8 帧，直接通过实例数据验证实际 GPU Shader 输出。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 40)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var atlas := MultiMeshInstance2D.new()
	atlas.material = particles.material
	atlas.texture = particles.texture
	var mesh := QuadMesh.new()
	mesh.size = Vector2(32, 32)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = 8
	for i in 8:
		multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2(20 + 40 * i, 20)))
		multimesh.set_instance_custom_data(i, Color(0, (i + 0.5) / 8.0, 0, 1))
	atlas.multimesh = multimesh
	viewport.add_child(atlas)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://output/ripple_validation/frames.png")
	preview.queue_free()
	viewport.queue_free()
	await process_frame
	print("RIPPLE_VALIDATION_OK: scene/material/texture loaded; fixed scale; live frames and 8-frame atlas captured")
	call_deferred("quit")

func save_preview(path: String) -> void:
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	if root.use_hdr_2d:
		image.linear_to_srgb()
	image.save_png(path)
