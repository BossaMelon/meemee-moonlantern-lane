extends SceneTree
## Actual placement and PNG alpha coverage, not a claim that canopy pixels collide.
const Map = preload("res://game/expedition/rain_garden_map.gd")
const Scene = preload("res://scenes/expedition/expedition.tscn")
var failures: Array = []
var checks = 0
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize(): call_deferred("run")
func run():
	var panel = Scene.instantiate(); root.add_child(panel)
	var evidence: Array = []
	for obstacle in Map.OBSTACLES:
		var visual: Dictionary = panel._stump_visual(obstacle)
		var meta: Dictionary = panel.manifest.sprites[visual.id]
		var image = Image.load_from_file("res://assets/pixel/"+meta.file)
		expect(image != null and not image.is_empty(),"registered stump texture decodes "+obstacle.id)
		if image == null or image.is_empty(): continue
		var pivot = Vector2(meta.pivot[0],meta.pivot[1])
		var origin: Vector2 = (visual.position-pivot*visual.scale).round()
		var size = Vector2.ONE*(obstacle.radius*2) if obstacle.shape == "circle" else Vector2(obstacle.width,obstacle.height)
		var bounds = Rect2(Vector2(obstacle.x,obstacle.y)-size*0.5,size)
		var samples = 0; var missing: Array = []
		for y in range(floori(bounds.position.y),ceili(bounds.end.y)):
			for x in range(floori(bounds.position.x),ceili(bounds.end.x)):
				var point = Vector2(x+0.5,y+0.5)
				var covered = point.distance_to(Vector2(obstacle.x,obstacle.y)) < obstacle.radius if obstacle.shape == "circle" else bounds.has_point(point)
				if not covered: continue
				samples += 1
				var pixel = Vector2i(((point-origin)/visual.scale).floor())
				if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height() or image.get_pixelv(pixel).a == 0: missing.append([point.x,point.y])
		expect(missing.is_empty(),"visible root/body covers unchanged solid footprint "+obstacle.id+" missing "+str(missing.size()))
		evidence.append({"obstacle_id":obstacle.id,"texture_id":visual.id,"scale":visual.scale,"origin":[origin.x,origin.y],"covered_samples":samples,"missing_samples":missing})
	var file = FileAccess.open("/tmp/e02-stump-visibility.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"geometry_sha256":FileAccess.get_sha256("res://game/expedition/rain_garden_map.gd"),"manifest_sha256":FileAccess.get_sha256("res://assets/pixel/manifest.json"),"evidence":evidence},"  "))
	print("E02 stump visibility: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
