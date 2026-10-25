extends SceneTree
## A fresh editor process started from an exported PCK, without source PNGs.
var checks = 0
var failures: Array = []
var samples: Array = []
var report_path = ""
var expected_manifest = ""
var expected_font_manifest = ""
var font_evidence: Dictionary = {}
func check(ok: bool, code: String):
	checks += 1
	if not ok: failures.append(code)
func finish():
	var report = {"kind":"editor-pck-resource-regression","claim":"Not a Windows release/native/device validation","engine":Engine.get_version_info(),"checks":checks,"failures":failures,"samples":samples,"manifest_sha256":FileAccess.get_sha256("res://assets/pixel/manifest.json"),"panel_sha256":FileAccess.get_sha256("res://game/expedition/expedition_panel.gd"),"font":font_evidence}
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
		if args[i] == "--font-manifest-sha": expected_font_manifest = args[i+1]
	call_deferred("run")
func data_sha(data: PackedByteArray) -> String:
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(data)
	return context.finish().hex_encode()
func verify_font(panel: Control):
	var path = "res://assets/fonts/font-manifest.json"
	var exists = FileAccess.file_exists(path)
	check(exists,"font_manifest_missing")
	if not exists: return
	check(FileAccess.get_sha256(path) == expected_font_manifest,"font_manifest_hash_mismatch")
	var meta = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(meta is Dictionary and meta.get("primary") is Dictionary,"font_manifest_invalid")
	if not meta is Dictionary or not meta.get("primary") is Dictionary: return
	var provider = load("res://game/ui/portable_font.gd")
	check(provider is Script,"font_provider_missing")
	if not provider is Script: return
	var primary: Font = provider.get_font()
	check(primary is FontFile and not primary is SystemFont,"provider_not_packaged_FontFile")
	if not primary is FontFile: return
	var imported: FontFile = primary
	check(not FileAccess.file_exists(meta.primary.path),"source_font_present_instead_of_import")
	check(imported.data.size() == meta.primary.size_bytes,"font_data_size_mismatch")
	check(data_sha(imported.data) == meta.primary.sha256,"font_data_hash_mismatch")
	check(imported.resource_path == meta.primary.path,"font_resource_path_mismatch")
	check(not imported.allow_system_fallback and imported.fallbacks.is_empty(),"font_fallback_enabled")
	for row in [meta.primary]+meta.fallbacks:
		check(FileAccess.file_exists(row.license_path) and FileAccess.get_sha256(row.license_path) == row.license_sha256,"font_license_missing_or_changed")
		if row.has("notice_path"): check(FileAccess.file_exists(row.notice_path) and FileAccess.get_sha256(row.notice_path) == row.notice_sha256,"font_notice_missing_or_changed")
	root.add_child(panel)
	check(panel.is_node_ready(),"panel_ready_not_executed")
	check(panel.font == primary and panel.font is FontFile,"panel_canvas_font_provider_mismatch")
	var bindings: Array = []
	for button in [panel.pause_button,panel.save_button,panel.save_quit_button,panel.return_button]:
		check(button is Button and button.is_node_ready() and button.get_theme_font("font") == primary,"actual_button_font_provider_mismatch")
		if button is Button: bindings.append({"name":button.text,"ready":button.is_node_ready(),"font_path":button.get_theme_font("font").resource_path,"font_instance":str(button.get_theme_font("font").get_instance_id())})
	font_evidence = {"class":imported.get_class(),"path":imported.resource_path,"data_sha256":data_sha(imported.data),"data_bytes":imported.data.size(),"allow_system_fallback":imported.allow_system_fallback,"fallback_count":imported.fallbacks.size(),"provider_instance":str(primary.get_instance_id()),"panel_ready":panel.is_node_ready(),"panel_font_class":panel.font.get_class(),"panel_font_instance":str(panel.font.get_instance_id()),"bindings":bindings,"provider_source_sha256":FileAccess.get_sha256("res://game/ui/portable_font.gd")}
func run():
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
	verify_font(panel)
	panel.free()
	finish()
