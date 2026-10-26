extends Node
## H06 verification-only observer. Never instantiate a scene or mutate product state.
const MAIN_SCENE = "res://scenes/main.tscn"
const MAIN_SCRIPT = "res://game/ui/main.gd"
const DEFAULT_SAVE = "user://profiles/rain-night-v1/moonlantern.json"
const REQUIRED_RESOURCES = ["res://assets/SOURCES.md", "res://assets/pixel/SOURCES.md", "res://assets/pixel/manifest.json", "res://assets/fonts/font-manifest.json", "res://assets/fonts/noto-sans-sc/OFL.txt", "res://assets/fonts/noto-sans-sc/NOTICE.txt"]
var request: Dictionary = {}
var report: Dictionary = {}
var ui: Variant = null
var ready_seen = false
var failed = false
var input_count = 0
var started_ms = 0
var trace_file: FileAccess
var expected: Dictionary = {}

func _enter_tree():
	started_ms = Time.get_ticks_msec()
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--p08-request":
		push_error("H06 requires an explicit host request")
		get_tree().quit(2)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not parsed is Dictionary:
		push_error("H06 request is not JSON")
		get_tree().quit(2)
		return
	request = parsed
	var version = Engine.get_version_info()
	var version_text = "%d.%d.%d.%s.%s.%s" % [version.major, version.minor, version.patch, version.status, version.build, str(version.hash).substr(0,9)]
	var features: Array = []
	for feature in ["template", "release", "editor", "debug", "macos", "windows"]:
		if OS.has_feature(feature): features.append(feature)
	report = {"schema_version":1, "run_id":request.run_id, "nonce":request.nonce, "stage":request.stage, "pid":OS.get_process_id(), "executable_path":OS.get_executable_path(), "engine_version":version_text, "features":features, "main":{}, "profile":{}, "initial_files":_files(), "checkpoints":[], "actions":[], "inputs":[], "font":{}, "resources":{}, "displays":[], "quit_input_dispatched":false, "failures":[]}
	if not _check(request.schema_version == 1 and request.expected_default_save_path == DEFAULT_SAVE, "unsupported request/default path"): return
	if not _check(OS.has_feature("template") and OS.has_feature("release") and not OS.has_feature("editor") and not OS.has_feature("debug"), "not a standard release execution"): return
	if not _check(ProjectSettings.get_setting("application/config/use_custom_user_dir", false) and ProjectSettings.get_setting("application/config/custom_user_dir_name", "") == request.expected_namespace, "effective namespace mismatch"): return
	if not _check(OS.get_user_data_dir() == request.expected_user_dir, "OS user directory mismatch"): return
	if not _check(FileAccess.get_sha256("res://tests/native/qa_autoload.gd") == request.qa_sha256, "QA source hash mismatch"): return
	if request.profile == "release_headless":
		if not _check(DisplayServer.get_name() == "headless", "headless request has a native display"): return
	elif not _check(request.profile == "mac_release_rendered" and OS.has_feature("macos") and DisplayServer.get_name() != "headless", "invalid rendered profile"): return
	if request.stage == "purchase_save":
		if not _check(not report.initial_files.primary.exists and not report.initial_files.backup.exists, "fresh namespace has prior saves"): return
	elif request.stage == "restore_exit":
		if not _check(FileAccess.get_sha256(request.previous_evidence) == request.previous_evidence_sha256, "previous observation hash mismatch"): return
		var previous = JSON.parse_string(FileAccess.get_file_as_string(request.previous_evidence))
		if not _check(previous is Dictionary and previous.has_all(["snapshot", "files"]), "previous observation missing"): return
		expected = previous
	else:
		_fail("unknown stage")
		return
	trace_file = FileAccess.open(request.output_dir.path_join(request.stage + "-inputs.jsonl"), FileAccess.WRITE)
	if not _check(trace_file != null, "cannot open input trace"): return
	get_tree().node_added.connect(_node_added)
	_run.call_deferred()

func _node_added(node: Node):
	if node.scene_file_path != MAIN_SCENE: return
	if not _check(ui == null, "more than one Main appeared"): return
	ui = node
	ui.ready.connect(_main_ready, CONNECT_ONE_SHOT)
	ui.action_completed.connect(_action_observed)

func _main_ready():
	ready_seen = true
	if not _check(ui.save_path == DEFAULT_SAVE, "Main default save path changed"): return
	report.profile = {"namespace":ProjectSettings.get_setting("application/config/custom_user_dir_name"), "user_dir":OS.get_user_data_dir(), "save_path":ui.save_path, "absolute_save":ProjectSettings.globalize_path(ui.save_path)}
	_checkpoint("fresh" if request.stage == "purchase_save" else "startup_before_input")

func _action_observed(kind, args, result):
	report.actions.append({"kind":kind, "args":args.duplicate(true), "result":result.duplicate(true), "input_count":input_count})

func _check(condition: bool, detail: String) -> bool:
	if not condition: _fail(detail)
	return condition

func _fail(detail: String):
	if failed: return
	failed = true
	if not report.is_empty():
		report.failures.append(detail)
		_write()
	push_error("H06: " + detail)
	get_tree().quit(2)

func _write():
	if request.is_empty() or not request.has("output_dir"): return
	var path: String = request.output_dir.path_join(request.stage + "-observation.json")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ", true, true))
		file.flush()

func _file_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"exists":false, "bytes":null, "sha256":null}
	var file = FileAccess.open(path, FileAccess.READ)
	return {"exists":true, "bytes":file.get_length() if file != null else -1, "sha256":FileAccess.get_sha256(path)}

func _files() -> Dictionary:
	return {"primary":_file_state(DEFAULT_SAVE), "backup":_file_state(DEFAULT_SAVE + ".bak")}

func _checkpoint(label: String):
	var snapshot: Dictionary = ui.game.snapshot()
	if not _check(ui.game.validate_snapshot(snapshot).is_empty(), "product snapshot validation failed"): return
	report.checkpoints.append({"name":label, "snapshot":snapshot, "files":_files(), "input_count":input_count, "feedback":ui.feedback.text})
	_write()

func _same(left: Variant, right: Variant) -> bool:
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]: return is_finite(float(left)) and is_finite(float(right)) and left == right
	if typeof(left) != typeof(right): return false
	if left is Dictionary:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not _same(left[key], right[key]): return false
		return true
	if left is Array:
		if left.size() != right.size(): return false
		for i in range(left.size()):
			if not _same(left[i], right[i]): return false
		return true
	return left == right

func _restore_barrier() -> bool:
	return _check(input_count == 0 and _same(ui.game.snapshot(), expected.snapshot) and _same(_files(), expected.files) and "恢复成功" in ui.feedback.text, "automatic restore before input differs from final host observation")

func _frames(count: int):
	for i in range(count):
		await get_tree().process_frame

func _inside_clip(control: Control) -> bool:
	var rect = control.get_global_rect()
	if not get_window().get_visible_rect().encloses(rect): return false
	var parent = control.get_parent()
	while parent is Control:
		if parent.clip_contents and not parent.get_global_rect().encloses(rect): return false
		parent = parent.get_parent()
	return true

func _click(id: String, exiting: bool = false):
	var control: Variant = null
	var deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		control = ui.get_action_control(id)
		if is_instance_valid(control) and control is Button and control.is_visible_in_tree() and not control.disabled and _inside_clip(control): break
		await get_tree().process_frame
	if not _check(is_instance_valid(control) and control is Button and control.is_visible_in_tree() and not control.disabled and _inside_clip(control), "unreachable actual control: " + id): return
	var rect: Rect2 = control.get_global_rect()
	var logical: Vector2 = rect.get_center()
	var transform: Transform2D = get_window().get_final_transform()
	var position: Vector2 = transform * logical
	for index in range(3):
		var event: InputEvent
		if index == 0:
			var motion = InputEventMouseMotion.new()
			motion.position = position
			motion.global_position = position
			event = motion
		else:
			var button = InputEventMouseButton.new()
			button.position = position
			button.global_position = position
			button.button_index = MOUSE_BUTTON_LEFT
			button.button_mask = MOUSE_BUTTON_MASK_LEFT if index == 1 else 0
			button.pressed = index == 1
			event = button
		input_count += 1
		var entry = {"sequence":input_count, "control_id":id, "control_path":str(control.get_path()), "kind":"motion" if index == 0 else "button", "pressed":index == 1, "position":[position.x,position.y], "logical_position":[logical.x,logical.y], "rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y], "transform":[transform.x.x,transform.x.y,transform.y.x,transform.y.y,transform.origin.x,transform.origin.y]}
		Input.parse_input_event(event)
		report.inputs.append(entry)
		trace_file.store_line(JSON.stringify(entry)); trace_file.flush()
		if exiting and index == 2:
			report.quit_input_dispatched = true
			_write()
			var exit_deadline = Time.get_ticks_msec() + 10000
			while Time.get_ticks_msec() < exit_deadline: await get_tree().process_frame
			_fail("real UI quit did not terminate the process")
			return
		await _frames(1)
	await _frames(2)

func _font_consumers(node: Node, font: Font) -> bool:
	if (node is Label or node is Button) and node.is_visible_in_tree() and node.get_theme_font("font") != font: return false
	for child in node.get_children():
		if not _font_consumers(child, font): return false
	return true

func _resources():
	var font: Font = ui.theme.default_font
	if not _check(font is FontFile and not font is SystemFont, "Main lacks packaged FontFile"): return
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256); hashing.update(font.data)
	report.font = {"class":font.get_class(), "path":font.resource_path, "sha256":hashing.finish().hex_encode(), "bytes":font.data.size(), "system_fallback":font.allow_system_fallback, "fallback_count":font.fallbacks.size(), "consumer_same_font":_font_consumers(ui, font)}
	for path in REQUIRED_RESOURCES:
		if not _check(FileAccess.file_exists(path), "missing attribution resource: " + path): return
		report.resources[path] = FileAccess.get_sha256(path)

func _capture(label: String):
	if request.profile == "release_headless": return
	var window = get_window()
	var deadline = Time.get_ticks_msec() + 5000
	while not window.has_focus() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	if not _check(window.has_focus() and window.mode == Window.MODE_FULLSCREEN, "actual native fullscreen/focus absent"): return
	var drawn = [false]
	RenderingServer.frame_post_draw.connect(func(): drawn[0] = true, CONNECT_ONE_SHOT)
	deadline = Time.get_ticks_msec() + 5000
	while not drawn[0] and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	if not _check(drawn[0], "no native frame drawn"): return
	var image = window.get_texture().get_image()
	var path: String = request.output_dir.path_join(label + ".png")
	if not _check(image != null and not image.is_empty() and image.save_png(path) == OK, "viewport PNG unavailable"): return
	var screen = DisplayServer.screen_get_size(window.current_screen)
	var dimensions = image.get_size()
	var content = window.get_visible_rect().size
	var transform = window.get_final_transform()
	report.displays.append({"name":label, "mode":window.mode, "focused":window.has_focus(), "window_size":[window.size.x,window.size.y], "screen_size":[screen.x,screen.y], "viewport_size":[dimensions.x,dimensions.y], "content_size":[int(content.x),int(content.y)], "transform":[transform.x.x,transform.x.y,transform.y.x,transform.y.y,transform.origin.x,transform.origin.y], "png":label + ".png", "sha256":FileAccess.get_sha256(path)})
	_write()

func _run():
	while not ready_seen or get_tree().current_scene != ui:
		if failed: return
		if not _check(Time.get_ticks_msec() - started_ms < 15000, "natural current_scene/Main.ready timed out"): return
		await get_tree().process_frame
	if not _check(ui.is_node_ready() and ui.get_script().resource_path == MAIN_SCRIPT, "wrong ready Main script"): return
	report.main = {"scene":ui.scene_file_path, "script":ui.get_script().resource_path, "instance_id":str(ui.get_instance_id()), "ready_observed":ready_seen, "current_scene_matches":get_tree().current_scene == ui, "node_ready":ui.is_node_ready()}
	_resources()
	if failed: return
	if request.stage == "restore_exit":
		if not _restore_barrier(): return
		await _frames(3)
		await _capture("restored-before-input")
		if failed or not _restore_barrier(): return
		_checkpoint("settled_before_input")
		if not _check(ui.get_open_sheet() == "pause", "restored pause UI not available"): return
	else:
		await _frames(3)
		await _capture("fresh-main")
		for id in ["world_lane", "world_stall", "batch_1", "buy_flour"]:
			await _click(id)
			if failed: return
		if not _check(ui.get_world_view() == "lane" and ui.get_open_sheet() == "shopping" and ui.batch == 1, "world navigation/batch state differs"): return
		_checkpoint("after_buy")
		await _capture("after-buy")
		for id in ["sheet_close", "pause", "save"]:
			await _click(id)
			if failed: return
		if not _check(ui.game.snapshot().paused and "保存成功" in ui.feedback.text, "UI pause/save feedback missing"): return
		_checkpoint("paused_saved")
		await _capture("paused-saved")
	if failed: return
	_checkpoint("pre_quit")
	_write()
	await _click("quit", true)
