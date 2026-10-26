extends Node
## V02 real-input source driver. Execution awaits a fixed P10/P11 candidate.
## Never replace Main, set control/map geometry/time/save_path, or mutate Session.
## Explicit headless-only Root content scaling is recorded after Main.ready, before input.
const MAIN_SCENE = "res://scenes/main.tscn"
const MAIN_SCRIPT = "res://game/ui/main.gd"
const SAVE_PATH = "user://profiles/world-slice-v1/moonlantern.json"
var request: Dictionary = {}
var report: Dictionary = {}
var ui: Variant = null
var ready_seen = false
var failed = false
var input_trace: FileAccess
var world_ui: Variant
var held_axis = Vector2.ZERO
var touch_down = false
var started_ms = 0
var last_tick = -1
var previous: Dictionary = {}
var native_focus_required = false

func _enter_tree():
	started_ms = Time.get_ticks_msec()
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
	report.merge({"stage":request.stage, "checkpoints":[], "trajectory":[], "events":[], "actions":[], "intents":[], "waves":[], "batches":[], "scroll":[], "combat_events":[], "dish_carry_trips":0, "quit_input_dispatched":false})
	var native = request.get("native",false)
	if native and request.get("headless_logical_size") != null:
		fail("headless logical preparation is forbidden for native evidence"); return
	if native: report.kind = "world-source-native-first-observation"
	if request.stage not in ["inspect", "first-manual", "first-auto", "night-quick", "night-hot", "restore-exit"] or DisplayServer.get_name() != ("macOS" if native else "headless"):
		fail("unsupported diagnostic stage/display")
		return
	if native:
		if request.stage not in ["first-manual","first-auto"] or request.get("save_boundary") != "after-sale" or str(request.get("native_slot","")).is_empty():
			fail("native preview requires declared slot and first-loop-only scope"); return
		if not request.get("ui_source_sha256") is Dictionary or request.ui_source_sha256.size() != 16:
			fail("native runtime requires 16 UI source bindings"); return
		report.ui_source_sha256 = {}
		for path in request.ui_source_sha256:
			var actual = FileAccess.get_sha256("res://"+path)
			if actual != request.ui_source_sha256[path]: fail("runtime UI source hash mismatch: "+path); return
			report.ui_source_sha256[path] = actual
	if report.namespace != request.namespace or report.user_dir != request.user_dir or not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		fail("namespace does not match host preflight")
		return
	if FileAccess.get_sha256("res://tests/runtime/world_slice.gd") != request.qa_sha256:
		fail("driver source differs from frozen candidate")
		return
	if request.stage == "restore-exit":
		if not request.has("previous") or FileAccess.get_sha256(request.previous) != request.get("previous_sha256", ""):
			fail("restore evidence hash mismatch"); return
		previous = JSON.parse_string(FileAccess.get_file_as_string(request.previous))
	elif FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_PATH + ".bak"):
		fail("fresh inspection already contains a save")
		return
	input_trace = FileAccess.open(request.output.path_join(request.stage + "-inputs.jsonl"), FileAccess.WRITE)
	if input_trace == null:
		fail("cannot create input trace")
		return
	# Godot desktop ScrollContainer uses this declared synthetic-touch mode.
	# It changes input routing only, never geometry, clocks or product state.
	if request.stage != "inspect": Input.emulate_touch_from_mouse = request.mode == "touch"
	report.desktop_touch_emulation = Input.emulate_touch_from_mouse
	get_tree().node_added.connect(observe_node)
	inspect_main.call_deferred()

func observe_node(node: Node):
	if node.has_signal("action_events") and node.get_script() != null and node.get_script().resource_path == "res://game/expedition/expedition_panel.gd":
		node.action_events.connect(func(events):
			for event in events: report.combat_events.append({"event":event.duplicate(true),"input_count":report.inputs.size(),"elapsed_ms":Time.get_ticks_msec()-started_ms}))
	if node.scene_file_path != MAIN_SCENE: return
	if ui != null:
		fail("multiple natural Main nodes")
		return
	ui = node
	ui.ready.connect(main_ready, CONNECT_ONE_SHOT)
	if ui.has_signal("action_completed"): ui.action_completed.connect(func(kind, args, result): report.actions.append({"kind":kind,"args":args.duplicate(true),"result":result.duplicate(true),"input_count":report.inputs.size()}))

func main_ready():
	ready_seen = true
	checkpoint("startup-before-input")
	if request.stage == "restore-exit" and not restore_barrier(): return

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
	var logical_size = request.get("headless_logical_size")
	if logical_size != null:
		if request.get("native",false) or request.stage == "inspect" or not logical_size is Array or logical_size.size() != 2 or logical_size[0] < 640 or logical_size[1] < 360 or request.get("window_size") != null:
			fail("invalid explicit headless logical preparation"); return
		var root = get_tree().root
		var before = observe_geometry()
		var current = get_tree().current_scene
		var main_before = {"exists":current != null,"inside_tree":current.is_inside_tree() if current != null else false,"ready":current.is_node_ready() if current != null else false,"scene":current.scene_file_path if current != null else ""}
		if not main_before.inside_tree or not main_before.ready or report.inputs.size() != 0:
			fail("headless logical preparation requires ready Main and no inputs: "+JSON.stringify(main_before)); return
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_size = Vector2i(logical_size[0],logical_size[1])
		report.headless_preparation = {"role":"headless-input-only","target":"/root","timing":"after-main-ready-before-input","input_count":report.inputs.size(),"main_before":main_before,"requested":logical_size,"before":before,"after":observe_geometry()}
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
	if request.stage == "inspect":
		if write_report(): get_tree().quit(0)
		return
	world_ui = find_world(ui)
	if not check(is_instance_valid(world_ui) and world_ui.is_visible_in_tree(), "actual P11 world projection missing"): return
	report.geometry = observe_geometry()
	var size = request.get("window_size", [])
	if request.get("headless_logical_size") != null:
		if not check(observe_geometry().viewport == [0.0,0.0,request.headless_logical_size[0],request.headless_logical_size[1]] and observe_geometry().window == report.headless_preparation.before.window,"declared headless logical viewport unavailable or physical size changed"): return
	elif not (request.get("native",false) and request.get("fullscreen",false)):
		if not check(size is Array and size.size() == 2 and observe_geometry().window == size, "declared CLI resolution differs from actual window: " + JSON.stringify(observe_geometry())): return
	if not check(world_ui.size.x >= 640 and world_ui.size.y >= 360, "actual world control too small for declared input route"): return
	if request.get("native",false):
		if not await wait_for(func(): return get_window().has_focus(),5000,"native window naturally receives focus"): return
		native_focus_required = true
		if not await capture_native("startup") or not await native_visual_tour(): return
	if request.stage == "restore-exit":
		checkpoint("settled-before-input")
		if not restore_barrier(): return
		await quit_from_pause()
	else:
		if request.stage.begins_with("night-") and not await configure_menu(): return
		await first_loop()

func observe_geometry() -> Dictionary:
	var window = get_window()
	var rect = window.get_visible_rect()
	var transform = window.get_final_transform()
	return {"window":[window.size.x, window.size.y], "viewport":[rect.position.x, rect.position.y, rect.size.x, rect.size.y], "transform":[transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y],"content_scale_mode":window.content_scale_mode,"content_scale_size":[window.content_scale_size.x,window.content_scale_size.y],"world_control_size":[world_ui.size.x,world_ui.size.y] if is_instance_valid(world_ui) else null}

func dispatch_event(event: InputEvent):
	send_event(event)
	await get_tree().process_frame

func send_event(event: InputEvent):
	if failed: return
	if request.get("native",false) and not check(get_window().has_focus(),"native focus lost; no input or focus reacquisition"): return
	if request.stage == "inspect":
		fail("read-only inspection cannot inject input")
		return
	if not event is InputEventKey and not event is InputEventMouse and not event is InputEventScreenTouch and not event is InputEventScreenDrag and not event is InputEventJoypadButton and not event is InputEventJoypadMotion:
		fail("unsupported input event")
		return
	var row = {"sequence":report.inputs.size() + 1, "elapsed_ms":Time.get_ticks_msec()-started_ms, "class":event.get_class(), "event":event.as_text(), "geometry":observe_geometry(), "position":event.position if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag else null}
	if event is InputEventKey: row.merge({"code":event.physical_keycode,"pressed":event.pressed})
	if event is InputEventJoypadMotion: row.merge({"axis":event.axis,"value":event.axis_value})
	if event is InputEventJoypadButton: row.merge({"button":event.button_index,"pressed":event.pressed})
	if event is InputEventScreenTouch: row.merge({"index":event.index,"pressed":event.pressed})
	if event is InputEventScreenDrag: row.index = event.index
	if event is InputEventMouseButton: row.merge({"button":event.button_index,"pressed":event.pressed})
	if row.position != null: row.position = [row.position.x, row.position.y]
	report.inputs.append(row)
	input_trace.store_line(JSON.stringify(row,"",true,true)); input_trace.flush()
	write_report()
	Input.parse_input_event(event)

func write_report() -> bool:
	if request.is_empty(): return false
	var file = FileAccess.open(request.output.path_join(request.stage + "-observation.json"), FileAccess.WRITE)
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

func check(ok: bool, message: String) -> bool:
	if not ok: fail(message)
	return ok and not failed

func find_world(node: Node) -> Node:
	if node.get_script() != null and node.get_script().resource_path == "res://game/ui/world_play.gd": return node
	for child in node.get_children():
		var found = find_world(child)
		if found != null: return found
	return null

func view() -> Dictionary: return ui.game.view()
func foot() -> Vector2: return Vector2(view().world.player.x, view().world.player.y)
func station() -> Dictionary: return view().world.stations[0]

func _process(_delta):
	if not ready_seen or failed or request.stage == "inspect": return
	if native_focus_required and not check(get_window().has_focus(),"native window lost focus during diagnostic"): return
	var v = view()
	if not v.get("world") is Dictionary: return
	var tick = int(v.world.get("tick", -1))
	if tick == last_tick: return
	last_tick = tick
	report.trajectory.append({"elapsed_ms":Time.get_ticks_msec()-started_ms,"tick":tick,"region":v.world.region_id,"player":v.world.player.duplicate(true),"held":v.world.input.duplicate(true),"carried":v.world.carried_uids.duplicate(),"cash":v.cash})
	for event in v.get("events", []):
		if event.get("type") != "world_moved": report.events.append(event.duplicate(true))
	if report.trajectory.size() > 12000: fail("trajectory bound exceeded")

func same(left: Variant, right: Variant) -> bool:
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]: return is_finite(float(left)) and is_finite(float(right)) and left == right
	if typeof(left) != typeof(right): return false
	if left is Dictionary:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not same(left[key], right[key]): return false
		return true
	if left is Array:
		if left.size() != right.size(): return false
		for i in range(left.size()):
			if not same(left[i], right[i]): return false
		return true
	return left == right

func file_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"exists":false,"bytes":null,"sha256":null}
	var file = FileAccess.open(path, FileAccess.READ)
	return {"exists":true,"bytes":file.get_length(),"sha256":FileAccess.get_sha256(path)}

func save_files() -> Dictionary: return {"primary":file_state(SAVE_PATH),"backup":file_state(SAVE_PATH + ".bak")}

func checkpoint(label: String):
	if not check(ui.game.validate_snapshot(ui.game.snapshot()).is_empty(), "invalid product snapshot at " + label): return
	report.checkpoints.append({"name":label,"elapsed_ms":Time.get_ticks_msec()-started_ms,"input_count":report.inputs.size(),"snapshot":ui.game.snapshot(),"files":save_files()})
	write_report()

func restore_barrier() -> bool:
	return check(report.inputs.is_empty() and same(ui.game.snapshot(), previous.get("snapshot")) and same(save_files(), previous.get("files")), "complete automatic restore/raw primary-backup differs before input")

func wait_for(predicate: Callable, milliseconds: int, label: String) -> bool:
	var deadline = Time.get_ticks_msec() + milliseconds
	while not predicate.call():
		if failed: return false
		if Time.get_ticks_msec() >= deadline: return check(false, "deadline: " + label)
		await get_tree().process_frame
	return not failed

func key_event(code: int, down: bool) -> InputEventKey:
	var event = InputEventKey.new(); event.physical_keycode = code; event.keycode = code; event.pressed = down; event.echo = false
	return event

func pad_button(button: int, down: bool) -> InputEventJoypadButton:
	var event = InputEventJoypadButton.new(); event.device = 0; event.button_index = button; event.pressed = down
	return event

func pointer_position(control: Control, local: Vector2) -> Vector2:
	var logical = control.get_global_transform() * local
	if not check(control.is_visible_in_tree() and control.get_global_rect().has_point(logical) and get_window().get_visible_rect().has_point(logical), "pointer outside actual control/viewport"): return Vector2.ZERO
	var parent = control.get_parent()
	while parent is Control:
		if not check(not parent.clip_contents or parent.get_global_rect().has_point(logical), "pointer clipped by " + str(parent.get_path())): return Vector2.ZERO
		parent = parent.get_parent()
	return get_window().get_final_transform() * logical

func touch_event(point: Vector2, down: bool, index: int = 1) -> InputEventScreenTouch:
	var event = InputEventScreenTouch.new(); event.index = index; event.position = point; event.pressed = down
	return event

func set_axis(axis: Vector2):
	if failed or held_axis == axis: return
	if request.mode == "mouse":
		for pair in [[KEY_A,axis.x < -0.2,held_axis.x < -0.2],[KEY_D,axis.x > 0.2,held_axis.x > 0.2],[KEY_W,axis.y < -0.2,held_axis.y < -0.2],[KEY_S,axis.y > 0.2,held_axis.y > 0.2]]:
			if pair[1] != pair[2]: send_event(key_event(pair[0], pair[1]))
	elif request.mode == "pad":
		for i in range(2):
			var event = InputEventJoypadMotion.new(); event.device = 0; event.axis = JOY_AXIS_LEFT_X if i == 0 else JOY_AXIS_LEFT_Y; event.axis_value = axis[i]; send_event(event)
	else:
		var center: Vector2 = world_ui.relay.stick_center(world_ui.size)
		if axis == Vector2.ZERO:
			if touch_down: send_event(touch_event(pointer_position(world_ui, center + held_axis*44), false, 0))
			touch_down = false
		else:
			if not touch_down: send_event(touch_event(pointer_position(world_ui, center), true, 0)); touch_down = true
			var drag = InputEventScreenDrag.new(); drag.index = 0; drag.position = pointer_position(world_ui, center + axis*44); drag.relative = (axis-held_axis)*44; send_event(drag)
	held_axis = axis

func stop_moving():
	set_axis(Vector2.ZERO)
	await get_tree().process_frame
	await wait_for(func(): return same(view().world.input,{"move_x":0,"move_y":0}), 1000, "physical release clears world axes")

func confirm_event(down: bool) -> InputEvent:
	if request.mode == "mouse": return key_event(KEY_F, down)
	if request.mode == "pad": return pad_button(JOY_BUTTON_A, down)
	return touch_event(pointer_position(world_ui, world_ui.relay.interact_rect(world_ui.size).get_center()), down)

func pause_event(down: bool) -> InputEvent:
	if request.mode == "mouse": return key_event(KEY_ESCAPE, down)
	if request.mode == "pad": return pad_button(JOY_BUTTON_START, down)
	return touch_event(pointer_position(world_ui, world_ui.relay.pause_rect(world_ui.size).get_center()), down, 2)

func primary() -> Dictionary:
	for option in view().interactions:
		if option.enabled: return option
	return {}

func interact(target: String, action: String) -> Dictionary:
	await stop_moving()
	var option = primary()
	if not check(option.get("target_id") == target and option.get("action") == action, "actual primary differs from intended " + target + "/" + action + ": " + JSON.stringify(option)): return {}
	report.intents.append({"target_id":target,"action":action,"option":option.duplicate(true),"input_count":report.inputs.size(),"player":view().world.player.duplicate(true)})
	send_event(confirm_event(true))
	# Catch the real 50ms reservation before yielding to another service step.
	if action == "serve" and request.save_boundary == "manual-reservation":
		# parse_input_event may buffer the event. Flush through the real input loop;
		# never advance time or create/pause a reservation through a product API.
		Input.flush_buffered_events()
		report.manual_reservation_flush = {"method":"Input.flush_buffered_events","confirmation_input_count":report.inputs.size(),"tick":view().world.tick}
		if check(view().service.reservations.any(func(r): return r.channel == "manual" and r.remaining_ms == 50 and r.order_id == option.payload.order_id), "manual reservation was not synchronously observable before service step"):
			send_event(pause_event(true)); send_event(pause_event(false))
			Input.flush_buffered_events()
			check(view().paused and view().service.reservations.any(func(r): return r.channel == "manual" and r.remaining_ms == 50 and r.order_id == option.payload.order_id),"actual pause input did not preserve the 50ms manual reservation")
	send_event(confirm_event(false))
	await get_tree().process_frame
	return option

# Conservative route planning only, never an alternate physics or state model.
# Every step is driven by events and rechecked against the actual Core foot point.
func clear_point(point: Vector2, geometry: Dictionary, radius: float = 20.0) -> bool:
	# Core radius12 + waypoint tolerance6 + margin2; this only plans clearance.
	if point.x < radius or point.y < radius or point.x > geometry.width-radius or point.y > geometry.height-radius: return false
	for c in geometry.colliders:
		var rect = Rect2(c.x-c.width/2.0,c.y-c.height/2.0,c.width,c.height).grow(radius)
		if rect.has_point(point): return false
	return true

func clear_segment(a: Vector2, b: Vector2, geometry: Dictionary) -> bool:
	var steps = maxi(1, ceili(a.distance_to(b)/4.0))
	for i in range(steps+1):
		if not clear_point(a.lerp(b,float(i)/steps),geometry): return false
	return true

func plan_path(start: Vector2, target: Vector2, geometry: Dictionary) -> Array:
	var step = 16.0
	var first = Vector2i(roundi(start.x/step), roundi(start.y/step))
	if not clear_segment(start, Vector2(first)*step, geometry): return []
	var queue: Array[Vector2i] = [first]; var parents: Dictionary = {first:first}; var cursor = 0
	while cursor < queue.size() and cursor < 10000:
		var cell = queue[cursor]; cursor += 1; var at = Vector2(cell)*step
		if at.distance_to(target) <= 32 and clear_segment(at, target, geometry):
			var path: Array = [at]
			while parents[cell] != cell:
				cell = parents[cell]; path.push_front(Vector2(cell)*step)
			return path
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next = cell+direction
			if not parents.has(next) and clear_segment(at, Vector2(next)*step, geometry):
				parents[next] = cell; queue.append(next)
	return []

func walk_to(target_id: String) -> bool:
	var v = view(); var target: Dictionary = {}
	for object in v.world.geometry.objects:
		if object.id == target_id: target = object; break
	if not check(not target.is_empty(), "target absent in authoritative region: " + target_id): return false
	var path = plan_path(foot(), Vector2(target.anchor.x,target.anchor.y), v.world.geometry)
	if not check(not path.is_empty(), "no conservative path to " + target_id): return false
	var deadline = Time.get_ticks_msec()+45000
	for waypoint in path:
		var progress_at = Time.get_ticks_msec(); var last = foot()
		while foot().distance_to(waypoint) > 6:
			if failed: return false
			if not check(view().world.region_id == v.world.region_id and not view().paused, "world route interrupted by region/pause"): return false
			if not check(Time.get_ticks_msec() < deadline and Time.get_ticks_msec()-progress_at < 1500, "movement stalled/expired: " + target_id): return false
			var delta = waypoint-foot()
			set_axis(Vector2(signf(delta.x),0) if absf(delta.x) >= absf(delta.y) else Vector2(0,signf(delta.y)))
			await get_tree().process_frame
			if foot().distance_to(last) >= 2: last = foot(); progress_at = Time.get_ticks_msec()
	await stop_moving()
	return check(foot().distance_to(Vector2(target.anchor.x,target.anchor.y)) <= 56, "actual foot outside interaction radius")

func first_loop():
	var fresh = view()
	if not check(fresh.phase == "preparation" and fresh.cash == 60 and fresh.sales.is_empty(), "first loop requires untouched default world"): return
	checkpoint("fresh")
	if not await walk_to("pantry"): return
	var take = await interact("pantry", "take")
	if failed: return
	if not await wait_for(func(): return same(view().world.carried_uids,take.payload.uids), 1000, "ingredient UIDs actually carried"): return
	checkpoint("carrying")
	if not await capture_native("carrying"): return
	if await save_at("carrying"): return
	if not await walk_to("prep"): return
	await interact("prep","put")
	if not await wait_for(func(): return view().world.carried_uids.is_empty() and same(station().input_uids,take.payload.uids),1000,"exact ingredients loaded"): return
	await interact("prep","cook")
	if failed: return
	if not check(station().job is Dictionary and station().job.remaining_ms > 0 and station().job.remaining_ms <= 2000, "actual timed cooking job missing"): return
	var job = station().job.duplicate(true); var cooking_tick = int(view().world.tick); checkpoint("cooking")
	if not await capture_native("cooking"): return
	if await save_at("cooking"): return
	if not await wait_for(func(): return station().job == null and same(station().output_uids,job.output_uids),4000,"two-second cooking output"): return
	var ready_events: Array = report.events + view().events
	var ready_event: Dictionary = {}
	for event in ready_events:
		if event.get("type") == "cooking_ready" and event.get("job_id") == job.id: ready_event = event; break
	if not check(not ready_event.is_empty() and (int(ready_event.tick)-cooking_tick)*50 == job.remaining_ms, "cooking_ready event differs from authoritative fixed-step duration"): return
	report.cooking_timing = {"observed_start_tick":cooking_tick,"observed_remaining_ms":job.remaining_ms,"ready_event_tick":ready_event.tick,"observed_ready_tick":view().world.tick}
	checkpoint("ready")
	if not await capture_native("ready"): return
	await interact("prep","take")
	if not await wait_for(func(): return same(view().world.carried_uids,job.output_uids),1000,"ready dish UIDs carried"): return
	report.dish_carry_trips += 1
	if not await walk_to("door-bell"): return
	await interact("door-bell","open_shop")
	if not await wait_for(func(): return view().phase == "trading" and not view().world.customers.is_empty(),1000,"real arriving customers"): return
	checkpoint("customer-arriving")
	if not await capture_native("customer-arriving"): return
	if await save_at("customer"): return
	var order: Dictionary = view().service.orders[0].duplicate(true)
	var before = view(); var served_uid = int(job.output_uids[0]); var quote: Dictionary = {}
	if request.stage == "first-manual":
		if not await walk_to(order.seat_id): return
		if not await wait_for(func(): return primary().get("action") == "serve" and primary().get("payload",{}).get("order_id") == order.id,15000,"seated eligible order"): return
		served_uid = int(primary().payload.uid)
		for row in view().serve_quotes:
			if row.order_id == order.id and int(row.uid) == served_uid: quote = row.duplicate(true); break
		if not check(not quote.is_empty() and quote.paid_total == quote.base_price+quote.tip, "actual manual quote missing"): return
		report.manual_quote = quote; before = view()
		await interact(order.seat_id,"serve")
		if await save_at("manual-reservation"): return
	else:
		if not await walk_to("pass"): return
		before = view(); await interact("pass","put")
	if failed: return
	if not await wait_for(func(): return view().sales.any(func(s): return s.order_id == order.id and s.get("revenue",0)>0),15000,"actual paid sale"): return
	var after = view(); var matches = after.sales.filter(func(s): return s.order_id == order.id and s.get("revenue",0)>0)
	if not check(matches.size() == 1, "first order paid more than once"): return
	var sale: Dictionary = matches[0]
	var revenues = 0
	for s in after.sales.slice(before.sales.size()): revenues += int(s.get("revenue",0))
	if not check(after.cash-before.cash == revenues and sale.revenue == sale.paid_total and sale.paid_total == sale.base_price+sale.tip, "actual sale/cash does not balance"): return
	if not check(not after.items.any(func(i): return i.uid == sale.uid) and after.service.orders.any(func(o): return o.id == order.id and o.status == "delivered"), "paid UID/order not committed"): return
	if request.stage == "first-manual":
		if not check(sale.uid == served_uid and sale.channel == "manual" and sale.paid_total == quote.paid_total and sale.tip == quote.tip, "manual sale differs from frozen quote"): return
	elif not check(sale.channel == "floating" and sale.tip == 0, "automatic route did not use floating/no-tip delivery"): return
	if not check(after.world.customers.any(func(c): return c.order_id == order.id and c.state == "eating" and c.reaction_remaining_ms > 0), "real customer receipt reaction missing"): return
	var observed_events: Array = report.events + after.events
	if not check(observed_events.any(func(e): return e.get("type") == "sale" and e.get("order_id") == order.id and e.get("uid") == sale.uid) and observed_events.any(func(e): return e.get("type") == "served" and e.get("order_id") == order.id), "authoritative sale/served events not observed"): return
	report.first_sale = sale.duplicate(true); report.first_income_ms = Time.get_ticks_msec()-started_ms
	report.first_batch = {"recipe":job.recipe_id,"quantity":job.output_uids.size(),"manual_dish_trips":report.dish_carry_trips}
	checkpoint("first-sale")
	if not await capture_native("first-sale"): return
	if request.stage.begins_with("night-"): await complete_night()
	else: await save_and_exit("after-sale")

func save_at(boundary: String) -> bool:
	if failed: return true
	if request.save_boundary != boundary: return false
	await save_and_exit(boundary)
	return true

func click_control(id: String, exiting: bool = false):
	if not check(ui.has_method("get_action_control"), "P11 control locator unavailable"): return
	var control = ui.get_action_control(id)
	await activate_control(control,id,exiting)

func activate_control(control: Variant, id: String, exiting: bool = false):
	if not check(is_instance_valid(control) and control is Button and control.is_visible_in_tree() and not control.disabled, "actual enabled control missing: " + id): return
	if request.mode == "pad":
		var visited: Dictionary = {}
		for i in range(32):
			if get_window().gui_get_focus_owner() == control: break
			var focus = get_window().gui_get_focus_owner()
			var key = str(focus.get_instance_id()) if focus != null else "none"
			if not check(not visited.has(key), "pad focus cycle cannot reach " + id): return
			visited[key] = true
			await dispatch_event(pad_button(JOY_BUTTON_DPAD_DOWN,true)); await dispatch_event(pad_button(JOY_BUTTON_DPAD_DOWN,false))
		if not check(get_window().gui_get_focus_owner() == control, "pad control not focused"): return
		await dispatch_event(pad_button(JOY_BUTTON_A,true)); send_event(pad_button(JOY_BUTTON_A,false))
	else:
		if not await scroll_to_control(control): return
		var position = pointer_position(control, control.size/2)
		if failed: return
		if request.mode == "touch":
			await dispatch_event(touch_event(position,true,3)); send_event(touch_event(position,false,3))
		else:
			var motion = InputEventMouseMotion.new(); motion.position = position; motion.global_position = position; await dispatch_event(motion)
			for down in [true,false]:
				var event = InputEventMouseButton.new(); event.position = position; event.global_position = position; event.button_index = MOUSE_BUTTON_LEFT; event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0; event.pressed = down; send_event(event)
				if down: await get_tree().process_frame
	if not exiting: await get_tree().process_frame

func save_and_exit(boundary: String):
	await stop_moving()
	if failed: return
	if not view().paused: send_event(pause_event(true)); send_event(pause_event(false))
	if not await wait_for(func(): return view().paused,1000,"real pause input"): return
	var paused = ui.game.snapshot(); var until = Time.get_ticks_msec()+250
	while Time.get_ticks_msec() < until: await get_tree().process_frame
	if not check(same(paused,ui.game.snapshot()), "paused state progressed during real wait"): return
	checkpoint("paused-"+boundary)
	await click_control("save")
	if not await wait_for(func(): return FileAccess.file_exists(SAVE_PATH),1000,"actual save file"): return
	checkpoint("saved")
	await quit_from_pause()

func quit_from_pause():
	if not check(view().paused,"quit stage must retain actual pause"): return
	checkpoint("pre-quit")
	report.snapshot = ui.game.snapshot(); report.files = save_files(); report.status = "exit_requested"; report.quit_input_dispatched = true
	write_report()
	await click_control("quit",true)

func capture_native(label: String) -> bool:
	if not request.get("native",false): return not failed
	if not check(DisplayServer.get_name() == "macOS" and get_window() == get_tree().root,"native capture must be the root Window viewport"): return false
	var drawn = {"ready":false}; var on_draw = func(): drawn.ready = true
	RenderingServer.frame_post_draw.connect(on_draw,CONNECT_ONE_SHOT)
	var deadline = Time.get_ticks_msec()+5000
	while not drawn.ready and not failed and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	if not drawn.ready:
		if RenderingServer.frame_post_draw.is_connected(on_draw): RenderingServer.frame_post_draw.disconnect(on_draw)
		return check(false,"root viewport did not draw within five seconds: "+label)
	var window = get_window(); var texture = window.get_texture(); var picture = texture.get_image()
	if not check(picture != null and not picture.is_empty(),"root viewport image unavailable"): return false
	var screen = DisplayServer.window_get_current_screen()
	var screen_rect = Rect2i(DisplayServer.screen_get_position(screen),DisplayServer.screen_get_size(screen))
	var usable = DisplayServer.screen_get_usable_rect(screen)
	var window_rect = Rect2i(DisplayServer.window_get_position(),DisplayServer.window_get_size())
	var coverage = "screen" if window_rect == screen_rect else ("macos_usable_rect" if screen_rect.encloses(usable) and window_rect == usable else "")
	var logical = window.get_visible_rect(); var stretch = window.get_stretch_transform(); var final = window.get_final_transform()
	var mapped = (stretch*logical).size
	var row = {"name":label,"path":request.output.path_join("native-"+label+".png"),"source_commit":request.source_commit,"elapsed_ms":Time.get_ticks_msec()-started_ms,"input_count":report.inputs.size(),"capture_viewport":str(window.get_path()),"screen":screen,"screen_rect":[screen_rect.position.x,screen_rect.position.y,screen_rect.size.x,screen_rect.size.y],"usable_rect":[usable.position.x,usable.position.y,usable.size.x,usable.size.y],"window_position":[window_rect.position.x,window_rect.position.y],"window_size":[window_rect.size.x,window_rect.size.y],"window_mode":DisplayServer.window_get_mode(),"root_mode":window.mode,"root_size":[window.size.x,window.size.y],"logical_root_viewport":[logical.position.x,logical.position.y,logical.size.x,logical.size.y],"root_texture_size":[texture.get_width(),texture.get_height()],"png_size":[picture.get_width(),picture.get_height()],"world_viewport_size":[world_ui.viewport.size.x,world_ui.viewport.size.y],"screen_dpi":DisplayServer.screen_get_dpi(screen),"screen_scale":DisplayServer.screen_get_scale(screen),"final_transform":[final.x.x,final.x.y,final.y.x,final.y.y,final.origin.x,final.origin.y],"stretch_transform":[stretch.x.x,stretch.x.y,stretch.y.x,stretch.y.y,stretch.origin.x,stretch.origin.y],"mapped_root_size":[mapped.x,mapped.y],"content_scale_size":[window.content_scale_size.x,window.content_scale_size.y],"content_scale_mode":window.content_scale_mode,"content_scale_factor":window.content_scale_factor,"window_focused":window.has_focus(),"fullscreen_coverage":coverage,"player":view().world.player.duplicate(true),"region":view().world.region_id,"cash":view().cash,"phase":view().phase,"carried_uids":view().world.carried_uids.duplicate(),"station":station().duplicate(true),"customers":view().world.customers.duplicate(true)}
	if not check(picture.save_png(row.path) == OK,"root PNG save failed"): return false
	row.sha256 = FileAccess.get_sha256(row.path); report.screenshots.append(row); report.geometry = observe_geometry(); write_report()
	# ViewportTexture proxy dimensions are separate evidence, not raw image size.
	if not check(row.window_focused and row.root_size == row.window_size and row.png_size[0] in [floori(mapped.x),ceili(mapped.x)] and row.png_size[1] in [floori(mapped.y),ceili(mapped.y)] and row.png_size != [640,360] and row.world_viewport_size == [640,360],"root/native/world viewport dimensions differ from observed transforms"): return false
	if request.fullscreen:
		return check(row.window_mode in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN] and int(row.root_mode) == int(row.window_mode) and coverage != "","actual root viewport does not cover native fullscreen bounds")
	return check(row.window_mode == DisplayServer.WINDOW_MODE_WINDOWED and int(row.root_mode) == int(row.window_mode) and row.window_size == request.window_size,"actual native windowed dimensions/mode differ")

func native_visual_tour() -> bool:
	if not await open_book("recipe-book") or not await capture_native("recipe-book"): return false
	if not await close_book() or not await travel("lane") or not await capture_native("lane"): return false
	return await travel("shop")

func scroll_to_control(control: Control) -> bool:
	var ancestor = control.get_parent()
	while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
	if ancestor == null: return true
	var scroll: ScrollContainer = ancestor
	var before = ui.game.snapshot()
	for attempt in range(40):
		var clip = scroll.get_global_rect().intersection(get_window().get_visible_rect()).grow(-6)
		var rect = control.get_global_rect()
		if clip.has_point(rect.get_center()):
			return check(same(before,ui.game.snapshot()), "scrolling changed authoritative book state")
		var direction = 1 if rect.get_center().y > clip.get_center().y else -1
		report.scroll.append({"control":str(control.get_meta("action_id","")),"attempt":attempt,"value":scroll.scroll_vertical,"clip":[clip.position.x,clip.position.y,clip.size.x,clip.size.y],"target":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
		if request.mode == "touch":
			# Start on a real visible label/gap. Never tap a transaction button to scroll.
			var point = Vector2.ZERO; var found = false
			for label in scroll.find_children("*","Label",true,false):
				var visible = label.get_global_rect().intersection(clip)
				if visible.size.x < 8 or visible.size.y < 8: continue
				var candidate = visible.get_center()
				if (candidate.y-clip.position.y if direction > 0 else clip.end.y-candidate.y) >= 32:
					point = candidate; found = true; break
			if not check(found,"no visible non-action touch scroll origin"): return false
			var distance = minf(112,(point.y-clip.position.y if direction > 0 else clip.end.y-point.y)-4)
			var origin = get_window().get_final_transform()*point
			await dispatch_event(touch_event(origin,true,7))
			var last = origin
			for step in range(1,7):
				var drag = InputEventScreenDrag.new(); drag.index = 7
				drag.position = get_window().get_final_transform()*(point-Vector2(0,direction*distance*step/6.0)); drag.relative = drag.position-last; last = drag.position
				await dispatch_event(drag)
			var until = Time.get_ticks_msec()+250
			while Time.get_ticks_msec() < until: await get_tree().process_frame
			await dispatch_event(touch_event(last,false,7))
		else:
			var point = get_window().get_final_transform()*clip.get_center()
			var motion = InputEventMouseMotion.new(); motion.position = point; motion.global_position = point; await dispatch_event(motion)
			for down in [true,false]:
				var wheel = InputEventMouseButton.new(); wheel.position = point; wheel.global_position = point
				wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN if direction > 0 else MOUSE_BUTTON_WHEEL_UP; wheel.pressed = down; await dispatch_event(wheel)
		await get_tree().process_frame
	return check(false,"real scrolling did not reach control")

func open_book(target: String) -> bool:
	if not await walk_to(target): return false
	var option = primary()
	if not check(option.get("target_id") == target,"book is not actual primary: "+target): return false
	await interact(target,option.action)
	if not await wait_for(func(): return ui.world_controller.book_target == target and ui.world_controller.books.is_visible_in_tree() and view().paused,1000,"actual nearby book opened"): return false
	for i in range(2): await get_tree().process_frame
	return true

func book_action(id: String, action: String, payload: Dictionary = {}) -> bool:
	var count = report.actions.size(); var target = ui.world_controller.book_target
	if not check(not target.is_empty() and view().paused,"book transaction requires actual paused book"): return false
	await click_control(id)
	if not await wait_for(func(): return report.actions.size() > count,1000,"actual book command: "+id): return false
	var rows = report.actions.slice(count)
	if not check(rows.size() == 1 and rows[0].kind == "world_interact" and same(rows[0].args,{"target_id":target,"action":action,"payload":payload}) and rows[0].result.get("ok",false),"book control emitted wrong/rejected/duplicate action: "+id): return false
	for i in range(2): await get_tree().process_frame
	return not failed

func close_book() -> bool:
	await click_control("book_close")
	return await wait_for(func(): return ui.world_controller.book_target.is_empty() and not view().paused,1000,"book closes and restores unpaused world")

func configure_menu() -> bool:
	var desired = ["floating_pie","ember_soup"] if request.stage == "night-quick" else ["floating_pie","moon_stew"]
	if not await open_book("menu-board"): return false
	for id in view().service.menu_priority.duplicate():
		if id in desired: continue
		var items = view().service.menu_priority.duplicate(); items.erase(id)
		if not await book_action("menu_toggle_"+id,"menu",{"item_ids":items,"tiers":menu_tiers(items)}): return false
	for id in desired:
		if id not in view().service.menu_priority:
			var items = view().service.menu_priority.duplicate(); items.append(id)
			if not await book_action("menu_toggle_"+id,"menu",{"item_ids":items,"tiers":menu_tiers(items)}): return false
		if view().tiers.get(id,"standard") != request.tier:
			var tiers = menu_tiers(view().service.menu_priority); tiers[id] = request.tier
			if not await book_action("menu_price_"+id+"_"+request.tier,"menu",{"item_ids":view().service.menu_priority.duplicate(),"tiers":tiers}): return false
	if not check(same(view().service.menu_priority,desired),"actual menu differs from route"): return false
	return await close_book()

func menu_tiers(items: Array) -> Dictionary:
	# UI emits only selected items, including each implicit standard price.
	var tiers: Dictionary = {}
	for id in items: tiers[id] = view().tiers.get(id,"standard")
	return tiers

func travel(region: String) -> bool:
	if view().world.region_id == region: return true
	var portal = "shop-exit" if region == "lane" else "lane-home"
	if not await walk_to(portal): return false
	var before = view(); await interact(portal,"enter")
	if not await wait_for(func(): return view().world.region_id == region,1000,"actual portal transition"): return false
	return check(view().day == before.day and view().cash == before.cash and same(view().world.carried_uids,before.world.carried_uids),"portal changed day/cash/carried UIDs")

func bag_count(id: String) -> int:
	return view().items.filter(func(item): return item.item_id == id and item.location == "bag").size()

func purchase(purchases: Dictionary) -> bool:
	if not await travel("lane") or not await open_book("vendor"): return false
	for id in purchases:
		var remaining = int(purchases[id])
		while remaining > 0:
			var quantity = 6 if remaining >= 6 else (3 if remaining >= 3 else 1)
			var offers = view().supply.filter(func(item): return item.item_id == id)
			if not check(offers.size() == 1,"actual supply item missing: "+id): return false
			var before = view(); var count = bag_count(id); var cost = int(offers[0].buy)*quantity
			if not await book_action("buy_"+id+"_"+str(quantity),"buy",{"item_id":id,"quantity":quantity}): return false
			if not check(bag_count(id) == count+quantity and view().cash == before.cash-cost and view().cash >= 0,"actual supply/cash delta differs"): return false
			remaining -= quantity
	if not await close_book(): return false
	return await travel("shop")

func prepare_batch(recipe: String, quantity: int, relay: bool = false) -> bool:
	if not check(view().world.carried_uids.is_empty() and station().input_uids.is_empty() and station().output_uids.is_empty() and station().job == null,"batch starts with empty hands/station"): return false
	if not await open_book("recipe-book"): return false
	if view().world.plan.recipe_id != recipe:
		if not await book_action("plan_recipe_"+recipe,"plan",{"recipe_id":recipe,"quantity":view().world.plan.quantity}): return false
	if int(view().world.plan.quantity) != quantity:
		if not await book_action("plan_quantity_"+str(quantity),"plan",{"recipe_id":recipe,"quantity":quantity}): return false
	if not await close_book(): return false
	var recipes = view().recipes.filter(func(row): return row.recipe_id == recipe)
	if not check(recipes.size() == 1,"actual recipe missing"): return false
	var inputs: Dictionary = recipes[0].inputs; var units = 0
	for amount in inputs.values(): units += int(amount)
	var input_uids: Array = []; var input_cost = 0; var counts: Dictionary = {}
	for trip in range(3):
		if input_uids.size() == quantity*units: break
		if not await walk_to("pantry"): return false
		var taken = await interact("pantry","take")
		if failed: return false
		if not await wait_for(func(): return same(view().world.carried_uids,taken.payload.uids),1000,"actual ingredient bundle"): return false
		for uid in taken.payload.uids:
			var rows = view().items.filter(func(item): return item.uid == uid)
			if not check(uid not in input_uids and rows.size() == 1 and rows[0].item_id in inputs,"bundle UID duplicated or unexpected"): return false
			input_uids.append(uid); input_cost += int(rows[0].cost); counts[rows[0].item_id] = counts.get(rows[0].item_id,0)+1
		if not await walk_to("prep"): return false
		await interact("prep","put")
		if not await wait_for(func(): return view().world.carried_uids.is_empty() and same(station().input_uids,input_uids),1000,"all original UIDs loaded once"): return false
	for id in inputs:
		if not check(counts.get(id,0) == int(inputs[id])*quantity,"loaded ingredients differ from requested full batch"): return false
	var before_cash = view().cash; var trips_before = report.dish_carry_trips
	await interact("prep","cook")
	if failed: return false
	if not check(station().job is Dictionary and station().job.output_uids.size() == quantity,"actual batch job missing/wrong quantity"): return false
	var job = station().job.duplicate(true); var tick = int(view().world.tick)
	if not await wait_for(func(): return station().job == null,4000,"actual batch cooking completes"): return false
	var events: Array = report.events + view().events
	if not check(events.any(func(e): return e.get("type") == "cooking_ready" and e.get("job_id") == job.id and (int(e.tick)-tick)*50 == job.remaining_ms),"actual batch completion tick missing/differs"): return false
	var dishes = view().items.filter(func(item): return item.uid in job.output_uids)
	var output_cost = 0
	for item in dishes: output_cost += int(item.cost)
	if not check(dishes.size() == quantity and dishes.all(func(item): return item.item_id == recipes[0].output) and output_cost == input_cost and not view().items.any(func(item): return item.uid in input_uids),"cooked UID/count/cost conservation failed"): return false
	if relay:
		if not await wait_for(func(): return station().output_uids.is_empty() and view().items.filter(func(item): return item.uid in job.output_uids and item.location == "shelf").size() == quantity,1000,"earned shelf relays actual dishes"): return false
		if not check(view().world.carried_uids.is_empty() and report.dish_carry_trips == trips_before,"relay needed manual dish carry"): return false
	else:
		await interact("prep","take")
		if not await wait_for(func(): return same(view().world.carried_uids,job.output_uids),1000,"batch dishes actually carried"): return false
		report.dish_carry_trips += 1
		if not await walk_to("pass"): return false
		await interact("pass","put")
		if not await wait_for(func(): return view().world.carried_uids.is_empty(),1000,"actual pass deposit"): return false
	if not check(view().cash == before_cash,"preparation created cash before customer delivery"): return false
	report.batches.append({"day":view().day,"recipe":recipe,"quantity":quantity,"input_uids":input_uids,"output_uids":job.output_uids,"input_cost":input_cost,"output_cost":output_cost,"manual_dish_trips":report.dish_carry_trips-trips_before,"relay":relay})
	return true

func finish_wave(index: int) -> bool:
	var before = view(); var wave = before.service.wave_id
	if not check(before.phase == "trading" and int(before.service.wave_index) == index,"wrong real wave start"): return false
	if not await wait_for(func(): return view().phase in ["intermission","closing"],100000,"normal wall-clock wave completion"): return false
	var after = view(); var rows = after.sales.filter(func(s): return s.wave_id == wave)
	var paid = rows.filter(func(s): return s.get("revenue",0) > 0); var revenue = 0; var seen: Dictionary = {}
	for sale in rows:
		if not check(not seen.has(sale.order_id) and sale.get("tip",0) == 0,"duplicate order/payment or tip-dependent night"): return false
		seen[sale.order_id] = true; revenue += int(sale.get("revenue",0))
	var interval_revenue = 0
	for sale in after.sales.slice(before.sales.size()): interval_revenue += int(sale.get("revenue",0))
	if not check(rows.size() == (3 if index == 1 else 4) and not paid.is_empty() and after.cash-before.cash == interval_revenue and after.service.reservations.is_empty() and after.service.orders.all(func(o): return o.status in ["delivered","left"]),"actual wave cash/order/reservation reconciliation failed"): return false
	report.waves.append({"wave_id":wave,"paid":paid.size(),"left":rows.size()-paid.size(),"revenue":revenue,"cash":after.cash,"held_uids":after.service.held_uids.duplicate(),"elapsed_ms":Time.get_ticks_msec()-started_ms})
	checkpoint("wave-%d-complete" % index)
	return not failed

func start_next_wave(index: int) -> bool:
	if not await walk_to("door-bell"): return false
	var next = view().service.next_wave_id
	await interact("door-bell","start_wave")
	return await wait_for(func(): return view().phase == "trading" and view().service.wave_id == next and int(view().service.wave_index) == index,1000,"real next wave bell")

func complete_night():
	if not await finish_wave(1): return
	if request.stage == "night-quick":
		if not await purchase({"flour":4,"pumpkin":6,"ember_herb":2}) or not await prepare_batch("floating_pie",2): return
	else:
		if not await purchase({"pumpkin":4,"cream":4}) or not await prepare_batch("moon_stew",4): return
	if not await start_next_wave(2) or not await finish_wave(2): return
	if request.stage == "night-quick":
		if not await prepare_batch("floating_pie",2) or not await prepare_batch("ember_soup",2): return
	else:
		if not check(view().service.held_uids.size() == 2 and view().items.filter(func(i): return i.uid in view().service.held_uids).all(func(i): return i.item_id == "moon_stew" and i.temperature == "held"),"hot route did not preserve two real warm portions"): return
	if not await start_next_wave(3) or not await finish_wave(3): return
	if not await open_book("ledger") or not await book_action("settle","settle"): return
	if not check(view().phase == "settled" and view().cash >= 125 and ui.game.snapshot().daily_recovery == 0 and view().sales.all(func(s): return s.get("tip",0) == 0),"normal night cannot fund growth and basics without recovery/tips"): return
	checkpoint("settled")
	var upgrade = request.growth; var offered = view().upgrades.filter(func(row): return row.upgrade_id == upgrade)
	if not check(offered.size() == 1 and offered[0].available,"earned upgrade not actually available"): return
	var cash = view().cash
	if not await book_action("upgrade_"+upgrade,"upgrade",{"upgrade_id":upgrade}): return
	if not check(upgrade in ui.game.snapshot().upgrades and upgrade not in view().active_upgrades and view().cash == cash-int(offered[0].cost),"upgrade purchase not deferred/cash-exact"): return
	checkpoint("upgrade-purchased")
	if not await book_action("next_day","next_day"): return
	if not check(view().day == 2 and view().phase == "preparation" and upgrade in view().active_upgrades,"next morning did not activate purchased upgrade"): return
	checkpoint("next-morning")
	# P11 next_day closes the ledger itself; observe that actual transition.
	if not await wait_for(func(): return ui.world_controller.book_target.is_empty() and not view().paused,1000,"next morning leaves ledger"): return
	if not await purchase({"flour":3,"pumpkin":3}) or not await prepare_batch("floating_pie",3,upgrade == "shelf"): return
	if upgrade == "shelf" and not check(report.first_batch.recipe == report.batches.back().recipe and report.first_batch.quantity == report.batches.back().quantity and report.first_batch.manual_dish_trips > report.batches.back().manual_dish_trips,"observed relay batch did not reduce manual dish trips"): return
	if upgrade == "field_kit" and not await demonstrate_fan(): return
	report.growth = {"upgrade":upgrade,"day":view().day,"demonstrated":true,"active_upgrades":view().active_upgrades.duplicate(),"last_batch":report.batches.back().duplicate(true),"baseline_first_batch":report.first_batch.duplicate(true),"combat_event_count":report.combat_events.size()}
	checkpoint("growth-demonstrated")
	await save_and_exit("growth")

func demonstrate_fan() -> bool:
	if not await open_book("recipe-book") or not await book_action("equip_fan_wand","equip_weapon",{"weapon_id":"fan_wand"}): return false
	if not check(view().progression.equipped_weapon == "fan_wand","earned fan not equipped"): return false
	if not await close_book() or not await travel("lane") or not await walk_to("garden-gate"): return false
	var portals = view().world.geometry.portals.filter(func(p): return p.id == "garden-gate")
	if not check(portals.size() == 1 and portals[0].get("return") is Dictionary,"authoritative garden return anchor unavailable"): return false
	var expected_return: Dictionary = portals[0]["return"].duplicate(true)
	await interact("garden-gate","enter")
	if not await wait_for(func(): return view().phase == "expedition" and is_instance_valid(ui.world_controller.battle_panel),2000,"actual reused garden scene"): return false
	var panel = ui.world_controller.battle_panel
	if not check(panel.is_visible_in_tree() and panel.has_method("touch_radius"),"actual E02 panel/input geometry unavailable"): return false
	var count = report.combat_events.size()
	if request.mode == "mouse":
		send_event(key_event(KEY_RIGHT,true)); send_event(key_event(KEY_J,true))
	elif request.mode == "pad":
		var aim = InputEventJoypadMotion.new(); aim.axis = JOY_AXIS_RIGHT_X; aim.axis_value = 1; send_event(aim); send_event(pad_button(JOY_BUTTON_A,true))
	else:
		var centers: Dictionary = panel._centers()
		send_event(touch_event(pointer_position(panel,centers.aim),true,4))
		var drag = InputEventScreenDrag.new(); drag.index = 4; drag.position = pointer_position(panel,centers.aim+Vector2(panel.touch_radius("aim"),0)); send_event(drag)
		send_event(touch_event(pointer_position(panel,centers.cast),true,5))
	if not await wait_for(func(): return report.combat_events.slice(count).any(func(row): return row.event.get("type") == "cast" and row.event.get("weapon_id") == "fan_wand" and row.event.get("projectile_count") == 3),3000,"real earned fan casts three projectiles"): return false
	if request.mode == "mouse":
		send_event(key_event(KEY_RIGHT,false)); send_event(key_event(KEY_J,false))
	elif request.mode == "pad":
		var aim = InputEventJoypadMotion.new(); aim.axis = JOY_AXIS_RIGHT_X; aim.axis_value = 0; send_event(aim); send_event(pad_button(JOY_BUTTON_A,false))
	else:
		var centers: Dictionary = panel._centers()
		send_event(touch_event(pointer_position(panel,centers.aim),false,4)); send_event(touch_event(pointer_position(panel,centers.cast),false,5))
	if request.mode == "touch": await activate_control(panel.pause_button,"battle-pause")
	else:
		send_event(key_event(KEY_ESCAPE,true) if request.mode == "mouse" else pad_button(JOY_BUTTON_START,true))
		send_event(key_event(KEY_ESCAPE,false) if request.mode == "mouse" else pad_button(JOY_BUTTON_START,false))
	if not await wait_for(func(): return view().paused,1000,"actual battle pause"): return false
	await activate_control(panel.return_button,"battle-return")
	if not await wait_for(func(): return view().phase == "preparation" and view().world.region_id == "lane",2000,"actual battle return"): return false
	var expected_player = {"x":expected_return.x,"y":expected_return.y,"facing":expected_return.facing}
	if not check(view().progression.equipped_weapon == "fan_wand" and view().world.region_id == expected_return.region_id and same(view().world.return_pose,expected_return) and same(view().world.player,expected_player),"growth/authoritative return pose changed on return"): return false
	# Returning from a paused battle may preserve pause; resume through actual UI.
	if view().paused:
		await click_control("resume")
		if not await wait_for(func(): return not view().paused,1000,"resume returned world"): return false
	return true
