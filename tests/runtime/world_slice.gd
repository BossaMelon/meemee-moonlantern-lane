extends Node
## V02 real-input source driver. Execution awaits a fixed P10/P11 candidate.
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
var world_ui: Variant
var held_axis = Vector2.ZERO
var touch_down = false
var started_ms = 0
var last_tick = -1
var previous: Dictionary = {}

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
	report.merge({"stage":request.stage, "checkpoints":[], "trajectory":[], "events":[], "actions":[], "intents":[], "quit_input_dispatched":false})
	if request.stage not in ["inspect", "first-manual", "first-auto", "restore-exit"] or DisplayServer.get_name() != "headless":
		fail("unsupported stage/display; rendered WS07 is not enabled")
		return
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
	get_tree().node_added.connect(observe_node)
	inspect_main.call_deferred()

func observe_node(node: Node):
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
	var size = request.get("window_size", [])
	if not check(size.size() == 2 and observe_geometry().window == size, "declared CLI resolution differs from actual window: " + JSON.stringify(observe_geometry())): return
	if not check(world_ui.size.x >= 640 and world_ui.size.y >= 360, "actual world control too small for declared input route"): return
	if request.stage == "restore-exit":
		checkpoint("settled-before-input")
		if not restore_barrier(): return
		await quit_from_pause()
	else:
		await first_loop()

func observe_geometry() -> Dictionary:
	var window = get_window()
	var rect = window.get_visible_rect()
	var transform = window.get_final_transform()
	return {"window":[window.size.x, window.size.y], "viewport":[rect.position.x, rect.position.y, rect.size.x, rect.size.y], "transform":[transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y]}

func dispatch_event(event: InputEvent):
	send_event(event)
	await get_tree().process_frame

func send_event(event: InputEvent):
	if failed: return
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
	input_trace.store_line(JSON.stringify(row)); input_trace.flush()
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
		if check(view().service.reservations.any(func(r): return r.channel == "manual" and r.remaining_ms == 50 and r.order_id == option.payload.order_id), "manual reservation was not synchronously observable before service step"):
			send_event(pause_event(true)); send_event(pause_event(false))
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
	if await save_at("carrying"): return
	if not await walk_to("prep"): return
	await interact("prep","put")
	if not await wait_for(func(): return view().world.carried_uids.is_empty() and same(station().input_uids,take.payload.uids),1000,"exact ingredients loaded"): return
	await interact("prep","cook")
	if failed: return
	if not check(station().job is Dictionary and station().job.remaining_ms > 0 and station().job.remaining_ms <= 2000, "actual timed cooking job missing"): return
	var job = station().job.duplicate(true); var cooking_tick = int(view().world.tick); checkpoint("cooking")
	if await save_at("cooking"): return
	if not await wait_for(func(): return station().job == null and same(station().output_uids,job.output_uids),4000,"two-second cooking output"): return
	var ready_events: Array = report.events + view().events
	var ready_event: Dictionary = {}
	for event in ready_events:
		if event.get("type") == "cooking_ready" and event.get("job_id") == job.id: ready_event = event; break
	if not check(not ready_event.is_empty() and (int(ready_event.tick)-cooking_tick)*50 == job.remaining_ms, "cooking_ready event differs from authoritative fixed-step duration"): return
	report.cooking_timing = {"observed_start_tick":cooking_tick,"observed_remaining_ms":job.remaining_ms,"ready_event_tick":ready_event.tick,"observed_ready_tick":view().world.tick}
	checkpoint("ready")
	await interact("prep","take")
	if not await wait_for(func(): return same(view().world.carried_uids,job.output_uids),1000,"ready dish UIDs carried"): return
	if not await walk_to("door-bell"): return
	await interact("door-bell","open_shop")
	if not await wait_for(func(): return view().phase == "trading" and not view().world.customers.is_empty(),1000,"real arriving customers"): return
	checkpoint("customer-arriving")
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
	checkpoint("first-sale")
	await save_and_exit("after-sale")

func save_at(boundary: String) -> bool:
	if failed: return true
	if request.save_boundary != boundary: return false
	await save_and_exit(boundary)
	return true

func click_control(id: String, exiting: bool = false):
	if not check(ui.has_method("get_action_control"), "P11 control locator unavailable"): return
	var control = ui.get_action_control(id)
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
