extends Node
## V02 source-only observer/input boundary. Real routes await P10/P11 integration.
## Never replace Main, set geometry/time/save_path, or mutate Session directly.
const MAIN_SCENE = "res://scenes/main.tscn"
const MAIN_SCRIPT = "res://game/ui/main.gd"
const SAVE_PATH = "user://profiles/world-slice-v1/moonlantern.json"
var request: Dictionary = {}
var report: Dictionary = {}
var ui: Variant = null
var ready_seen = false
var failed = false
var input_trace: FileAccess

func _enter_tree():
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--v02-request":
		fail("explicit V02 request required")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not parsed is Dictionary or not parsed.has_all(["nonce", "source_commit", "namespace", "user_dir", "mode", "stage", "output", "qa_sha256"]):
		fail("invalid V02 request")
		return
	request = parsed
	var version = Engine.get_version_info()
	var version_text = "%d.%d.%d.%s.%s.%s" % [version.major, version.minor, version.patch, version.status, version.build, str(version.hash).substr(0, 9)]
	report = {"kind":"world-source-headless-observation", "status":"failed", "nonce":request.nonce, "source_commit":request.source_commit, "pid":OS.get_process_id(), "engine_version":version_text, "mode":request.mode, "namespace":ProjectSettings.get_setting("application/config/custom_user_dir_name", ""), "user_dir":OS.get_user_data_dir(), "save_path":"", "main_scene":"", "main_script":"", "ready_seen":false, "current_scene_matches":false, "display":DisplayServer.get_name(), "inputs":[], "screenshots":[], "failures":[], "ws07_passed":false, "snapshot":{}, "geometry":{}, "files":{}}
	if request.stage != "inspect" or DisplayServer.get_name() != "headless":
		fail("this increment only supports headless inspection, never a rendered route")
		return
	if report.namespace != request.namespace or report.user_dir != request.user_dir or not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		fail("namespace does not match host preflight")
		return
	if FileAccess.get_sha256("res://tests/runtime/world_slice.gd") != request.qa_sha256:
		fail("driver source differs from frozen candidate")
		return
	if FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_PATH + ".bak"):
		fail("fresh inspection already contains a save")
		return
	input_trace = FileAccess.open(request.output.path_join("inputs.jsonl"), FileAccess.WRITE)
	if input_trace == null:
		fail("cannot create input trace")
		return
	get_tree().node_added.connect(observe_node)
	inspect_main.call_deferred()

func observe_node(node: Node):
	if node.scene_file_path != MAIN_SCENE: return
	if ui != null:
		fail("multiple natural Main nodes")
		return
	ui = node
	ui.ready.connect(func(): ready_seen = true, CONNECT_ONE_SHOT)

func inspect_main():
	var deadline = Time.get_ticks_msec() + 15000
	while not ready_seen or get_tree().current_scene != ui:
		if failed: return
		if Time.get_ticks_msec() >= deadline:
			fail("natural Main.ready/current_scene deadline")
			return
		await get_tree().process_frame
	if ui.get_script().resource_path != MAIN_SCRIPT or ui.save_path != SAVE_PATH:
		fail("P11 natural world Main/default save path is not ready")
		return
	for i in range(3): await get_tree().process_frame
	if failed: return
	var snapshot: Dictionary = ui.game.snapshot()
	if snapshot.get("profile_id") != "world-slice-v1" or snapshot.get("version") != 4 or not snapshot.get("world") is Dictionary:
		fail("P10 world snapshot is not available")
		return
	if not ui.game.validate_snapshot(snapshot).is_empty():
		fail("product rejected its own snapshot")
		return
	report.merge({"status":"observed", "save_path":ui.save_path, "main_scene":ui.scene_file_path, "main_script":ui.get_script().resource_path, "ready_seen":ready_seen, "current_scene_matches":get_tree().current_scene == ui, "snapshot":snapshot, "geometry":observe_geometry(), "files":{"primary":FileAccess.file_exists(SAVE_PATH), "backup":FileAccess.file_exists(SAVE_PATH + ".bak")}}, true)
	if write_report(): get_tree().quit(0)

func observe_geometry() -> Dictionary:
	var window = get_window()
	var rect = window.get_visible_rect()
	var transform = window.get_final_transform()
	return {"window":[window.size.x, window.size.y], "viewport":[rect.position.x, rect.position.y, rect.size.x, rect.size.y], "transform":[transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y]}

func dispatch_event(event: InputEvent):
	# Deliberately unreachable from inspect. Route integration must explicitly
	# enable a new request stage and verify product input observations first.
	if request.stage == "inspect":
		fail("read-only inspection cannot inject input")
		return
	if not event is InputEventKey and not event is InputEventMouse and not event is InputEventScreenTouch and not event is InputEventScreenDrag and not event is InputEventJoypadButton and not event is InputEventJoypadMotion:
		fail("unsupported input event")
		return
	var row = {"sequence":report.inputs.size() + 1, "elapsed_ms":Time.get_ticks_msec(), "class":event.get_class(), "event":event.as_text(), "geometry":observe_geometry()}
	report.inputs.append(row)
	input_trace.store_line(JSON.stringify(row)); input_trace.flush()
	Input.parse_input_event(event)
	await get_tree().process_frame

func write_report() -> bool:
	if request.is_empty(): return false
	var file = FileAccess.open(request.output.path_join("observation.json"), FileAccess.WRITE)
	if file == null:
		push_error("V02 cannot write observation")
		get_tree().quit(2)
		return false
	file.store_string(JSON.stringify(report, "  ", true, true)); file.close()
	return true

func fail(message: String):
	if failed: return
	failed = true
	if not report.is_empty():
		report.status = "failed"
		report.failures.append(message)
		write_report()
	push_error("V02: " + message)
	get_tree().quit(2)
