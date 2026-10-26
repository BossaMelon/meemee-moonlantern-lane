extends SceneTree
## Independent input-stage checks; never fabricates a Core/economy view.
var folder: String
var checks = 0
var failures: Array = []
var rows: Array = []
var execution = "input"
var input_mode = "keyboard"
var route = "manual"
var ui
var income_actions: Array = []
var income_inputs: Array = []
var income_trace: Array = []
var _held = Vector2.ZERO
var save_roundtrip = false

func _initialize():
	var args = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--input-only": folder = args[1]
	elif args.size() in [4,5] and args[0] == "--first-income" and args[1] in ["keyboard", "pad", "touch"] and args[2] in ["manual", "automatic"]:
		execution = "income"; input_mode = args[1]; route = args[2]; folder = args[3]
		if args.size() == 5:
			if args[4] != "--save-roundtrip": quit(2); return
			save_roundtrip = true
	else: quit(2); return
	if not folder.is_absolute_path() or not DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(folder+"/world-"+execution+".json"): quit(2); return
	Engine.max_fps = 120; call_deferred("run")

func expect(ok: bool, text: String):
	checks += 1
	if not ok: failures.append(text); print("FAIL ", text)

func frames(count = 3):
	for i in range(count): await process_frame

func send(event: InputEvent):
	if execution == "income": income_inputs.append({"type": event.get_class(), "event": event.as_text(), "device": event.device})
	Input.parse_input_event(event.xformed_by(root.get_final_transform()) if event is InputEventScreenTouch or event is InputEventScreenDrag else event)
	await frames(1)

func key(code: int, down: bool, echo = false):
	var event = InputEventKey.new(); event.physical_keycode = code; event.pressed = down; event.echo = echo
	await send(event)

func axis(index: int, value: float):
	var event = InputEventJoypadMotion.new(); event.device = 0; event.axis = index; event.axis_value = value
	await send(event)

func joy(down: bool):
	var event = InputEventJoypadButton.new(); event.device = 0; event.button_index = JOY_BUTTON_A; event.pressed = down
	await send(event)

func touch(at: Vector2, down: bool, index = 0, canceled = false):
	var event = InputEventScreenTouch.new(); event.position = at; event.pressed = down; event.index = index; event.canceled = canceled
	await send(event)

func run_case(mode: String):
	var ui = load("res://scenes/ui/world_play.tscn").instantiate(); root.add_child(ui); await frames(8)
	expect(is_instance_valid(ui.actor) and is_instance_valid(ui.surface), mode+": production input scene finished initialization")
	if not is_instance_valid(ui.actor) or not is_instance_valid(ui.surface): ui.queue_free(); await frames(); return
	var axes: Array = []; var confirms: Array = []; var actions: Array = []
	ui.movement_requested.connect(func(value): axes.append(value))
	ui.relay.interact_requested.connect(func(): confirms.append(true))
	ui.interaction_requested.connect(func(value): actions.append(value))
	expect(not ui.actor.visible and ui.current_view.is_empty(), "unbound "+mode+" renderer creates no fake player or economy view")
	expect(ui.find_children("*", "CollisionObject2D", true, false).is_empty(), "production renderer owns no physical bodies")
	expect(ui.viewport.size == Vector2i(640, 360), "reference viewport stays640x360 independently of screen size")
	var canvas_bindings: Array = ui.canvas_text_bindings()
	expect(canvas_bindings.size() == 2, "actual Canvas draw executed for touch F and pause text")
	for binding in canvas_bindings: expect(binding.font == load("res://game/ui/portable_font.gd").get_font(), "actual Canvas draw uses shared packaged FontFile")
	if mode == "keyboard":
		await key(KEY_D, true); await key(KEY_W, true)
		expect(not axes.is_empty() and is_equal_approx(axes.back().length(), 1.0) and axes.back().x > 0 and axes.back().y < 0, "real WASD forwards normalized axes")
		await key(KEY_D, false); await key(KEY_W, false)
		expect(axes.back() == Vector2.ZERO, "keyboard release forwards zero")
		await key(KEY_LEFT, true); expect(axes.back() == Vector2.LEFT, "direction arrow shares world movement route"); await key(KEY_LEFT, false)
		await key(KEY_F, true); await key(KEY_F, true, true); await key(KEY_F, true)
		expect(confirms.size() == 1, "held/repeated F emits one rising-edge interaction")
		await key(KEY_F, false)
	elif mode == "pad":
		await axis(JOY_AXIS_LEFT_X, 0.1); expect(axes.is_empty(), "stick deadzone forwards no drift")
		await axis(JOY_AXIS_LEFT_X, 0.8); await axis(JOY_AXIS_LEFT_Y, -0.8)
		expect(not axes.is_empty() and is_equal_approx(axes.back().length(), 1.0), "real left-stick corner is normalized")
		await axis(JOY_AXIS_LEFT_X, 0); await axis(JOY_AXIS_LEFT_Y, 0)
		expect(axes.back() == Vector2.ZERO, "centered stick forwards zero")
		await joy(true); await joy(true); expect(confirms.size() == 1, "held pad A emits one rising edge"); await joy(false)
	else:
		var center = ui.relay.stick_center(ui.size)
		await touch(center, true)
		var drag = InputEventScreenDrag.new(); drag.index = 0; drag.position = center+Vector2(44, -44); drag.relative = Vector2(44, -44)
		await send(drag)
		expect(not axes.is_empty() and is_equal_approx(axes.back().length(), 1.0) and axes.back().x > 0 and axes.back().y < 0, "actual ScreenDrag forwards normalized movement")
		await touch(center, false, 0, true); expect(axes.back() == Vector2.ZERO, "touch cancel releases the stick")
		var at = ui.relay.interact_rect(ui.size).get_center()
		await touch(at, true, 1); await touch(at, true, 1)
		expect(confirms.size() == 1, "held touch F emits one rising edge"); await touch(at, false, 1)
	expect(actions.is_empty(), "F without Core interactions invents no transaction")
	await key(KEY_D, true)
	ui.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT); await frames()
	expect(axes.back() == Vector2.ZERO, "focus-out notification clears all held axes")
	ui.set_controls_enabled(false); var count = axes.size(); await key(KEY_W, true)
	expect(axes.size() == count, "inactive/modal/battle world layer forwards no held movement")
	ui.set_controls_enabled(true); await key(KEY_W, false); await key(KEY_D, false)
	rows.append({"mode": mode, "axes": axes, "confirm_edges": confirms.size(), "core_transactions": actions.size(), "viewport_size": str(ui.viewport.size), "surface_rect": str(ui.surface.get_global_rect()), "no_core_view_injected": ui.current_view.is_empty()})
	ui.queue_free(); await frames()

func run():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED; root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(844, 390)
	if execution == "income": await run_income(); return
	Input.emulate_mouse_from_touch = true
	for mode in ["keyboard", "pad", "touch"]: await run_case(mode)
	expect(rows.size() == 3 and checks > 30, "all three independent input cases completed")
	expect(Engine.time_scale == 1.0, "time scale stays one")
	var sources = {}
	for path in ["game/ui/world_play.gd", "game/ui/world/world_input.gd", "game/ui/world/walk_animation.gd", "game/ui/checks/world_play.gd", "scenes/ui/world_play.tscn"]: sources[path] = FileAccess.get_sha256("res://"+path)
	var file = FileAccess.open(folder+"/world-input.json", FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify({"suite": "world-production-input-only", "checks": checks, "failures": failures, "rows": rows, "source_sha256": sources, "engine": Engine.get_version_info().string, "claim": "Actual InputEvents through independent production WorldPlay input layer. No Core view injected, no economic transaction, movement authority, first income, WS07, native window, default save or physical-device claim."}, "  ")); file.close()
	print("WORLD_INPUT ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _foot() -> Vector2:
	var player: Dictionary = ui.game.view().world.player
	return Vector2(player.x, player.y)

func _anchor(id: String) -> Vector2:
	for object in ui.game.view().world.geometry.objects:
		if str(object.id) == id: return Vector2(object.anchor.x, object.anchor.y)
	expect(false, "Core geometry provides target "+id); return _foot()

func _drive(value: Vector2):
	if value == _held: return
	var old = _held; _held = value
	income_inputs.append({"type": input_mode, "axis": str(value)})
	if input_mode == "keyboard":
		for pair in [[KEY_W, old.y < 0, value.y < 0], [KEY_S, old.y > 0, value.y > 0], [KEY_A, old.x < 0, value.x < 0], [KEY_D, old.x > 0, value.x > 0]]:
			if pair[1] != pair[2]: var event = InputEventKey.new(); event.physical_keycode = pair[0]; event.pressed = pair[2]; Input.parse_input_event(event)
	elif input_mode == "pad":
		for pair in [[JOY_AXIS_LEFT_X, value.x], [JOY_AXIS_LEFT_Y, value.y]]:
			var event = InputEventJoypadMotion.new(); event.device = 0; event.axis = pair[0]; event.axis_value = pair[1]; Input.parse_input_event(event)
	else:
		var center: Vector2 = ui.world_controller.world.relay.stick_center(ui.size)
		if old == Vector2.ZERO and value != Vector2.ZERO:
			var down = InputEventScreenTouch.new(); down.index = 0; down.position = center; down.pressed = true; Input.parse_input_event(down.xformed_by(root.get_final_transform()))
		if value == Vector2.ZERO:
			var up = InputEventScreenTouch.new(); up.index = 0; up.position = center; up.pressed = false; Input.parse_input_event(up.xformed_by(root.get_final_transform()))
		else:
			var drag = InputEventScreenDrag.new(); drag.index = 0; drag.position = center+value*44; drag.relative = (value-old)*44; Input.parse_input_event(drag.xformed_by(root.get_final_transform()))

func _walk_to(target: Vector2) -> bool:
	var deadline = Time.get_ticks_msec()+15000
	var sample = 0
	while _foot().distance_to(target) > 9 and Time.get_ticks_msec() < deadline:
		var delta = target-_foot()
		var axis = Vector2(signf(delta.x) if absf(delta.x) > 6 else 0, signf(delta.y) if absf(delta.y) > 6 else 0).limit_length()
		_drive(axis); await process_frame
		if sample%30 == 0: income_trace.append({"case": "walking", "foot": str(_foot()), "actor_foot": str(ui.world_controller.world.actor.position), "camera": str(ui.world_controller.world.camera.get_screen_center_position()), "frame": ui.world_controller.world.walk.frame_id, "walk_phase_ms": ui.world_controller.world.walk.phase_ms, "pivot": str(-ui.world_controller.world.actor.offset)})
		sample += 1
	_drive(Vector2.ZERO); await frames()
	var reached = _foot().distance_to(target) <= 9
	expect(reached, "actual "+input_mode+" input reaches "+str(target)+"; actual "+str(_foot()))
	expect(ui.world_controller.world.actor.position.distance_to(_foot()) < 0.01, "rendered foot reads authoritative Core position")
	return reached

func _f(expected_action: String) -> bool:
	var selected: Dictionary = ui.world_controller.world._primary
	income_trace.append({"case": "before_F", "expected": expected_action, "selected": selected.duplicate(true), "foot": str(_foot()), "prompt": ui.world_controller.world.prompt.text})
	if str(selected.get("action", "")) != expected_action:
		expect(false, "Core default F should offer "+expected_action+", actual "+str(selected.get("action", "none")))
		return false
	var before = income_actions.size()
	if input_mode == "keyboard": await key(KEY_F, true); await key(KEY_F, false)
	elif input_mode == "pad": await joy(true); await joy(false)
	else:
		var at = ui.world_controller.world.relay.interact_rect(ui.size).get_center()
		await touch(at, true, 1); await touch(at, false, 1)
	await frames()
	var ok = income_actions.size() == before+1 and income_actions.back().ok
	expect(ok, "one real F/A/touch invokes successful "+expected_action)
	return ok

func _projection(stage: String):
	var nodes: Array = ui.world_controller.world.visual_uid_bindings()
	var seen: Dictionary = {}; var items: Dictionary = {}
	for item in ui.game.view().items: items[int(item.uid)] = item
	for node in nodes:
		expect(not seen.has(node.uid), stage+": one visual per authoritative UID")
		seen[node.uid] = true
		expect(items.has(node.uid) and str(items.get(node.uid, {}).get("location", "")) != "cooking", stage+": visual UID resolves to actual non-cooking item")
	income_trace.append({"case": "uid_projection", "stage": stage, "nodes": nodes})
	_check_fonts(ui)

func _check_fonts(node: Node):
	var primary = load("res://game/ui/portable_font.gd").get_font()
	if node is Label or node is Button: expect(node.get_theme_font("font") == primary, "live world/book text uses packaged FontFile: "+str(node.get_path()))
	if node.has_method("canvas_text_bindings"):
		for row in node.canvas_text_bindings(): expect(row.font == primary, "actual live Canvas draw uses packaged FontFile")
	for child in node.get_children(): _check_fonts(child)

func _pause_control():
	if input_mode == "keyboard": await key(KEY_ESCAPE, true); await key(KEY_ESCAPE, false)
	elif input_mode == "pad":
		for down in [true, false]:
			var event = InputEventJoypadButton.new(); event.device = 0; event.button_index = JOY_BUTTON_START; event.pressed = down; await send(event)
	else:
		var at: Vector2
		if ui.game.view().paused: at = ui.get_action_control("resume").get_global_rect().get_center()
		else: at = ui.world_controller.world.relay.pause_rect(ui.size).get_center()
		await touch(at, true, 2); await touch(at, false, 2)
	await frames()

func _button_input(id: String) -> bool:
	var button = ui.get_action_control(id)
	expect(button is Button and button.is_visible_in_tree() and not button.disabled, "actual modal target "+id+" is enabled")
	if not button is Button or button.disabled: return false
	if input_mode == "pad":
		for n in range(60):
			if root.gui_get_focus_owner() == button: break
			for down in [true, false]:
				var event = InputEventJoypadButton.new(); event.device = 0; event.button_index = JOY_BUTTON_DPAD_DOWN; event.pressed = down; await send(event)
		expect(root.gui_get_focus_owner() == button, "real D-pad reaches modal "+id)
		if root.gui_get_focus_owner() != button: return false
		await joy(true); await joy(false)
	elif input_mode == "touch":
		var at = button.get_global_rect().get_center(); await touch(at, true, 3); await touch(at, false, 3)
	else:
		for down in [true, false]:
			var event = InputEventMouseButton.new(); event.position = button.get_global_rect().get_center(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; await send(event)
	await frames(); return true

func run_income():
	ui = load("res://scenes/main.tscn").instantiate(); ui.save_path = folder+"/unused-world-player.json"; root.add_child(ui); await frames(12)
	expect(is_instance_valid(ui.world_controller) and ui.game.view().get("profile_id", "") == "world-slice-v1", "actual Main mounts production world profile")
	if not is_instance_valid(ui.world_controller) or not ui.game.view().has("world"): finish_income(); return
	ui.action_completed.connect(func(kind, args, result): income_actions.append({"kind": kind, "args": args.duplicate(true), "ok": result.ok, "message": result.message, "cash_at_action": ui.game.view().cash, "reservations_at_action": ui.game.view().service.reservations.duplicate(true)}))
	var initial_cash = int(ui.game.view().cash)
	if not await _walk_to(_anchor("pantry")+Vector2(0, 24)): finish_income(); return
	if not await _f("take"): finish_income(); return
	expect(ui.game.view().world.carried_uids.size() == 6, "Core moves the real default ingredient bundle to carried")
	_projection("carried ingredients")
	if not await _walk_to(_anchor("prep")+Vector2(0, 24)): finish_income(); return
	if not await _f("put"): finish_income(); return
	expect(ui.game.view().world.stations[0].input_uids.size() == 6, "real ingredients are loaded at station")
	_projection("loaded ingredients")
	if not await _f("cook"): finish_income(); return
	_projection("cooking, not ready food")
	var stopped_phase = ui.world_controller.world.walk.phase_ms
	var stopped_frame = ui.world_controller.world.walk.frame_id
	var deadline = Time.get_ticks_msec()+3500
	while ui.game.view().world.stations[0].job != null and Time.get_ticks_msec() < deadline: await process_frame
	expect(ui.game.view().world.stations[0].output_uids.size() == 3, "Main alone advances real two-second batch to three ready UIDs")
	_projection("ready food")
	expect(ui.world_controller.world.walk.phase_ms == stopped_phase and ui.world_controller.world.walk.frame_id == stopped_frame, "stationary cooking wait freezes walking phase instead of stepping in place")
	var produced: Array = ui.game.view().world.stations[0].output_uids.duplicate()
	if not await _f("take"): finish_income(); return
	_projection("carried dishes")
	if route == "automatic":
		if not await _walk_to(_anchor("pass")+Vector2(0, 24)): finish_income(); return
		if not await _f("put"): finish_income(); return
	if not await _walk_to(Vector2(1160, 364)): finish_income(); return
	if not await _walk_to(_anchor("door-bell")): finish_income(); return
	if not await _f("open_shop"): finish_income(); return
	if route == "manual":
		if not await _walk_to(Vector2(1160, 580)): finish_income(); return
		if not await _walk_to(Vector2(1160, 360)): finish_income(); return
		if not await _walk_to(_anchor("seat-1")+Vector2(0, 24)): finish_income(); return
		deadline = Time.get_ticks_msec()+8000
		while str(ui.world_controller.world._primary.get("action", "")) != "serve" and Time.get_ticks_msec() < deadline: await process_frame
		expect("基础" in ui.world_controller.world.prompt.text and "小费" in ui.world_controller.world.prompt.text and "合计" in ui.world_controller.world.prompt.text, "actual pre-F prompt displays Core base/tip/total quote")
		if not await _f("serve"): finish_income(); return
		expect(income_actions.back().cash_at_action == initial_cash and not income_actions.back().reservations_at_action.is_empty(), "serve intent reserves without paying before next Core step")
		_projection("after manual intent")
	deadline = Time.get_ticks_msec()+12000
	while ui.game.view().sales.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	var view: Dictionary = ui.game.view()
	expect(not view.sales.is_empty() and int(view.cash) > initial_cash, "real served transaction increases actual cash")
	if not view.sales.is_empty():
		var sale: Dictionary = view.sales[0]
		expect(int(sale.uid) in produced and int(sale.paid_total) == int(view.cash)-initial_cash, "sale consumes actual cooking UID and cash matches authoritative total")
		expect(sale.channel == ("manual" if route == "manual" else "floating"), "requested physical route produced the real service channel")
	_projection("after actual served commit")
	if route == "manual":
		_drive(Vector2.UP); await create_timer(0.8).timeout
		var stopped = _foot(); var phase = ui.world_controller.world.walk.phase_ms
		await create_timer(0.2).timeout
		expect(_foot() == stopped and ui.world_controller.world.walk.phase_ms == phase, "held movement against real table collision freezes walking phase")
		_drive(Vector2.ZERO)
	await _pause_control()
	var tick = int(ui.game.view().world.tick); var foot = _foot(); var phase = ui.world_controller.world.walk.phase_ms; var frame = ui.world_controller.world.walk.frame_id
	await create_timer(0.25).timeout
	expect(ui.game.view().paused and int(ui.game.view().world.tick) == tick and _foot() == foot, "actual pause input stops Core ticks and movement")
	expect(ui.world_controller.world.walk.phase_ms == phase and ui.world_controller.world.walk.frame_id == frame, "pause freezes current animation phase and frame")
	if save_roundtrip:
		var saved: Dictionary = ui.game.snapshot()
		if not await _button_input("save"): finish_income(); return
		expect(FileAccess.file_exists(ui.save_path) and FileAccess.file_exists(ui.save_path+".bak"), "actual Save button writes isolated primary and backup")
		var saved_hash = FileAccess.get_sha256(ui.save_path)
		await _pause_control(); _drive(Vector2.DOWN); await create_timer(0.15).timeout; _drive(Vector2.ZERO); await _pause_control()
		expect(ui.game.snapshot() != saved, "real resumed input changes state after checkpoint")
		if not await _button_input("load"): finish_income(); return
		expect(ui.game.snapshot() == saved, "actual Restore button restores full Core snapshot, including UID/economy/position")
		expect(FileAccess.get_sha256(ui.save_path) == saved_hash, "Restore reads the saved file without overwriting it")
	await _pause_control()
	expect(not ui.game.view().paused and ui.game.view().world.input == {"move_x": 0.0, "move_y": 0.0}, "actual resume clears held input")
	if not save_roundtrip: expect(not FileAccess.file_exists(ui.save_path), "first-income-only check never creates a player save")
	finish_income()

func finish_income():
	var view: Dictionary = ui.game.view() if is_instance_valid(ui) else {}
	var dump = FileAccess.open(folder+"/actual-view.json", FileAccess.WRITE); dump.store_string(JSON.stringify(view, "  ")); dump.close()
	var sources = {}
	for path in ["game/ui/main.gd", "game/ui/world_play.gd", "game/ui/world/world_input.gd", "game/ui/world/walk_animation.gd", "game/ui/world/world_controller.gd", "game/ui/world/world_books.gd", "game/ui/checks/world_play.gd", "game/core/world_night_session.gd"]: sources[path] = FileAccess.get_sha256("res://"+path)
	var file = FileAccess.open(folder+"/world-income.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite": "world-production-first-income", "checks": checks, "failures": failures, "mode": input_mode, "route": route, "save_roundtrip": save_roundtrip, "actions": income_actions, "inputs": income_inputs, "trace": income_trace, "cash": view.get("cash"), "sales": view.get("sales", []), "source_sha256": sources, "engine": Engine.get_version_info().string, "claim": "Actual default Main and real P10 Core through InputEvents only. Fresh temporary profile path; optional same-process GUI save/restore, no test Core command/position/UID injection. First-loop headless only; not full WS, native, default-path/independent-process save proof or human fun proof."}, "  ")); file.close()
	print("WORLD_INCOME ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
