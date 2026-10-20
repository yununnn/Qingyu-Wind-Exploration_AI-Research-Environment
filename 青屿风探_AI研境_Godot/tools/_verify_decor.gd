extends SceneTree

func _init() -> void:
	var base: String = "res://scenes/fram/装饰物"
	var dirs: Array = ["蘑菇", "石头", "花草", "建筑"]
	var ok: int = 0
	var bad: int = 0
	var nocoll: int = 0
	for d in dirs:
		var path: String = base + "/" + str(d)
		var da: DirAccess = DirAccess.open(path)
		if da == null:
			print("[MISSING DIR] ", path)
			bad += 1
			continue
		da.list_dir_begin()
		var fn: String = da.get_next_file()
		while fn != "":
			if fn.ends_with(".tscn"):
				var full: String = path + "/" + fn
				var ps: PackedScene = load(full) as PackedScene
				if ps == null:
					print("[LOAD FAIL] ", full)
					bad += 1
				else:
					var inst: Node = ps.instantiate()
					var sp: Sprite2D = inst.get_node_or_null("Sprite2D") as Sprite2D
					var cs: CollisionShape2D = inst.get_node_or_null("CollisionShape2D") as CollisionShape2D
					var atlas_ok: bool = sp != null and sp.texture is AtlasTexture
					var rect: Rect2 = Rect2()
					if atlas_ok:
						rect = (sp.texture as AtlasTexture).region
					if cs == null:
						nocoll += 1
					print("%s %-18s root=%-13s region=%-20s sprite_y=%-5s collider=%s" % [
						"OK  " if atlas_ok else "WARN",
						fn, inst.get_class(), str(rect),
						str(sp.position.y) if sp else "-",
						"yes" if cs else "no"])
					inst.free()
					ok += 1
			fn = da.get_next_file()
		da.list_dir_end()
	print("RESULT ok=%d bad=%d no_collider=%d" % [ok, bad, nocoll])
	quit(0 if bad == 0 else 1)
