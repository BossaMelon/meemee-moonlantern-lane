extends SceneTree
## Editor-only public-API pack audit and verification derivative, never shipped.
var errors: Array[String] = []

func check(condition: bool, message: String) -> bool:
	if not condition:
		errors.append(message)
	return condition

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if check(file != null, "cannot write " + path):
		file.store_string(text)

func payload(bytes: PackedByteArray) -> Dictionary:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return {"bytes": bytes.size(), "sha256": hash.finish().hex_encode()}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not check(ProjectSettings.load_resource_pack(request.pack), "cannot mount actual player pack"):
		quit(2)
		return
	var inventory := {}
	# DirAccess does not refresh mounted-pack listings. The independently parsed
	# complete inventory is supplied; every byte is read again via FileAccess.
	for path: String in request.inventory:
		var bytes := FileAccess.get_file_as_bytes(path)
		inventory[path] = payload(bytes)
		check(inventory[path].sha256 == request.inventory[path].sha256 and inventory[path].bytes == int(request.inventory[path].bytes), "virtual resource mismatch " + path)
	for path: String in ["res://scenes/main.tscn", "res://scenes/expedition/expedition.tscn"]:
		check(FileAccess.get_file_as_string(path).begins_with("[gd_scene"), "not a source text scene " + path)
		check(ResourceLoader.load(path) is PackedScene, "cannot load PackedScene " + path)
	var font_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fonts/font-manifest.json"))
	var font: FontFile = ResourceLoader.load(font_manifest.primary.path)
	if check(font != null, "cannot load actual FontFile"):
		check(payload(font.data).sha256 == font_manifest.primary.sha256, "font bytes mismatch")
		check(not font.allow_system_fallback, "system font fallback enabled")
	for kind: String in ["license", "notice"]:
		check(FileAccess.get_sha256(font_manifest.primary[kind + "_path"]) == font_manifest.primary[kind + "_sha256"], "font attribution mismatch")
	for path: String in request.inventory:
		if path.ends_with(".import"):
			var cfg := ConfigFile.new()
			if check(cfg.load(path) == OK, "cannot read import remap " + path):
				for key: String in cfg.get_section_keys("remap"):
					if key == "path" or key.begins_with("path."):
						check(FileAccess.file_exists(cfg.get_value("remap", key)), "missing import target " + path)
	# Remove only the audit bootstrap's stored settings. Builtin defaults retain
	# their normal initial values; each product setting is explicitly serialized.
	for key: String in ["application/config/name", "application/config/use_custom_user_dir", "application/config/custom_user_dir_name"]:
		ProjectSettings.clear(key)
	for key: String in request.settings:
		var row: Dictionary = request.settings[key]
		var value: Variant = row.value
		match int(row.tag):
			2, 65538: value = int(value)
			34: value = PackedStringArray(value)
		ProjectSettings.set_setting(key, value)
		ProjectSettings.set_initial_value(key, null)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", request.verification_namespace)
	ProjectSettings.set_setting("autoload/H06NativeQA", "*res://tests/native/qa_autoload.gd")
	check(ProjectSettings.save_custom(request.settings_output) == OK, "cannot serialize verification project.binary")
	if errors.is_empty():
		var packer := PCKPacker.new()
		check(packer.pck_start(request.verification_pck) == OK, "cannot start verification PCK")
		var paths: Array = request.inventory.keys()
		paths.sort()
		for path: String in paths:
			var bytes := FileAccess.get_file_as_bytes(request.settings_output if path == "res://project.binary" else path)
			check(packer.add_file_from_buffer(path, bytes) == OK, "cannot pack " + path)
		for path: String in request.qa:
			check(packer.add_file(path, request.qa[path]) == OK, "cannot add frozen QA resource")
		check(packer.flush() == OK, "cannot flush verification PCK")
	write_text(request.license_output, Engine.get_license_text())
	write_text(request.third_party_output, JSON.stringify({"licenses": Engine.get_license_info(), "copyrights": Engine.get_copyright_info()}, "\t"))
	write_text(request.report, JSON.stringify({"ok": errors.is_empty(), "errors": errors, "inventory": inventory}, "\t"))
	quit(0 if errors.is_empty() else 2)
