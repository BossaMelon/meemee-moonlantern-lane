extends SceneTree
## A fresh editor process started from an exported PCK, without source PNGs.
var checks = 0
var failures: Array = []
var samples: Array = []
var report_path = ""
var expected_manifest = ""
func check(ok: bool, code: String):
	checks += 1
	if not ok: failures.append(code)
func finish():
	var report = {"kind":"editor-pck-resource-regression","claim":"Not a Windows release/native/device validation","engine":Engine.get_version_info(),"checks":checks,"failures":failures,"samples":samples,"manifest_sha256":FileAccess.get_sha256("res://assets/pixel/manifest.json"),"panel_sha256":FileAccess.get_sha256("res://game/expedition/expedition_panel.gd"),"font_status":"pending_P07_provider"}
	if report_path != "":
		var file = FileAccess.open(report_path,FileAccess.WRITE)
		if file == null: print("Cannot write resource report"); quit(2); return
		file.store_string(JSON.stringify(report,"  "))
	print("E03 editor/PCK resources: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
func _initialize():
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i] == "--report": report_path = args[i+1]
		if args[i] == "--manifest-sha": expected_manifest = args[i+1]
	check(FileAccess.file_exists("res://assets/pixel/manifest.json"),"manifest_missing")
	if not failures.is_empty(): finish(); return
	check(FileAccess.get_sha256("res://assets/pixel/manifest.json") == expected_manifest,"manifest_hash_mismatch")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pixel/manifest.json"))
	check(manifest is Dictionary and manifest.get("sprites") is Dictionary and manifest.get("backgrounds") is Dictionary,"manifest_shape_invalid")
	if not failures.is_empty(): finish(); return
	var script = load("res://game/expedition/expedition_panel.gd")
	check(script != null,"product_panel_missing")
	if script == null: finish(); return
	var panel = script.new()
	var required_count = 0
	for group in ["sprites","backgrounds"]:
		for id in manifest[group]:
			var meta: Dictionary = manifest[group][id]
			var path = "res://assets/pixel/"+meta.file
			required_count += 1
			var raw_present = FileAccess.file_exists(path)
			var remapped = ResourceLoader.exists(path,"Texture2D")
			check(not raw_present,"source_png_present:"+id)
			check(not ResourceLoader.has_cached(path),"texture_pre_cached:"+id)
			check(remapped,"imported_resource_missing:"+id)
			var control = ResourceLoader.load(path,"Texture2D",ResourceLoader.CACHE_MODE_IGNORE) as Texture2D if remapped else null
			check(control != null,"imported_resource_unloadable:"+id)
			var texture: Texture2D = panel._texture(id,group == "backgrounds")
			check(texture != null,"required_texture_missing:"+id)
			if texture != null:
				check(texture.get_width() == meta.size[0] and texture.get_height() == meta.size[1],"texture_dimensions:"+id)
				check(panel._texture(id,group == "backgrounds") == texture,"local_cache_identity:"+id)
			samples.append({"id":id,"group":group,"raw_source_present":raw_present,"imported_resource_exists":remapped,"control_loaded":control != null,"product_loaded":texture != null,"texture_class":"" if texture == null else texture.get_class(),"resource_path":"" if texture == null else texture.resource_path,"size":[] if texture == null else [texture.get_width(),texture.get_height()]})
	check(required_count > 0,"no_required_textures")
	check(panel._texture("__e03_optional_missing__") == null,"optional_missing_fallback_changed")
	panel.free()
	finish()
