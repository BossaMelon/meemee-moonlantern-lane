extends SceneTree
## Real rendered InputEvent path checks. Model adapter is explicitly NOT a core/P14 pass.
const Model = preload("res://game/expedition/expedition_model.gd")
const Driver = preload("res://tests/expedition/action_driver.gd")
const ExpeditionScene = preload("res://scenes/expedition/expedition.tscn")
var output = "/tmp/e01-runtime"
var panel
var adapter
var failures: Array = []
var checks = 0
var modes: Array = []
var pressed: Dictionary = {}
var active_touches: Dictionary = {}
var save_count = 0
var real_core = false
var observed_events: Array = []
var save_quit_only = false

class ActionAdapter extends RefCounted:
	var state: Dictionary
	var phase = "expedition"
	var paused = false
	var events: Array = []
	func _init(): state = Model.create(3,"rendered-input-fixture",23,"fan_wand",["gust"],true)
	func view() -> Dictionary: return {"phase":phase,"paused":paused,"expedition":Model.view(state)}
	func command(kind: String, args: Dictionary = {}, _id: String = "") -> Dictionary:
		if kind == "expedition_input": return Model.set_input(state,args)
		if kind == "leave_expedition": phase = "shopping"; return Model.leave(state)
		return {"ok":false,"message":"Unsupported isolated action adapter command","events":[]}
	func advance(ms: int) -> Dictionary:
		var result = Model.advance(state,ms,80,paused)
		events.append_array(result.events)
		if result.returned: phase = "shopping"
		return result
	func set_paused(value: bool) -> Dictionary:
		paused = value
		if not paused: Model.clear_input(state)
		return {"ok":true}

func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)

func _initialize():
	real_core = "--real-core" in OS.get_cmdline_user_args()
	save_quit_only = "--save-quit-only" in OS.get_cmdline_user_args()
	for i in range(OS.get_cmdline_user_args().size()-1):
		if OS.get_cmdline_user_args()[i] == "--output": output = OS.get_cmdline_user_args()[i+1]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func key_event(code: int, down: bool):
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func keyboard(input: Dictionary):
	var next = {KEY_W:input.move_y < -0.3,KEY_S:input.move_y > 0.3,KEY_A:input.move_x < -0.3,KEY_D:input.move_x > 0.3,
		KEY_UP:input.aim_y < -0.3,KEY_DOWN:input.aim_y > 0.3,KEY_LEFT:input.aim_x < -0.3,KEY_RIGHT:input.aim_x > 0.3,
		KEY_J:input.cast,KEY_K:input.dodge,KEY_L:input.skill}
	for code in next:
		if next[code] != pressed.get(code,false): key_event(code,next[code])
	pressed = next

func joy(input: Dictionary):
	for pair in [[JOY_AXIS_LEFT_X,input.move_x],[JOY_AXIS_LEFT_Y,input.move_y],[JOY_AXIS_RIGHT_X,input.aim_x],[JOY_AXIS_RIGHT_Y,input.aim_y]]:
		var event = InputEventJoypadMotion.new()
		event.axis = pair[0]; event.axis_value = pair[1]
		Input.parse_input_event(event)
	for pair in [[JOY_BUTTON_A,input.cast],[JOY_BUTTON_B,input.dodge],[JOY_BUTTON_X,input.skill]]:
		var event = InputEventJoypadButton.new()
		event.button_index = pair[0]; event.pressed = pair[1]
		Input.parse_input_event(event)

func touch(input: Dictionary):
	var centers: Dictionary = panel._centers()
	var values = {"move":Vector2(input.move_x,input.move_y),"aim":Vector2(input.aim_x,input.aim_y),"cast":input.cast,"dodge":input.dodge,"skill":input.skill}
	var index = 0
	for kind in values:
		var on: bool = values[kind].length_squared() > 0.00001 if values[kind] is Vector2 else values[kind]
		var center: Vector2 = centers[kind]
		if on and not active_touches.get(index,false):
			var start = InputEventScreenTouch.new()
			start.index = index; start.pressed = true; start.position = center
			root.push_input(start,true)
		if on and values[kind] is Vector2:
			var drag = InputEventScreenDrag.new()
			drag.index = index; drag.position = center+values[kind]*55.0
			root.push_input(drag,true)
		if not on and active_touches.get(index,false):
			var stop = InputEventScreenTouch.new()
			stop.index = index; stop.pressed = false; stop.position = center
			root.push_input(stop,true)
		active_touches[index] = on
		index += 1

func inject(mode: String, input: Dictionary):
	match mode:
		"keyboard": keyboard(input)
		"touch": touch(input)
		"gamepad": joy(input)

func click(at: Vector2):
	var motion = InputEventMouseMotion.new()
	motion.position = at; motion.global_position = at
	root.push_input(motion,true)
	await process_frame
	var event = InputEventMouseButton.new()
	event.position = at; event.global_position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
	await process_frame
	event = InputEventMouseButton.new()
	event.position = at; event.global_position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = false
	root.push_input(event,true)
	await process_frame

func screenshot(name: String):
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png(output+"/"+name+".png")
	expect(error == OK,"viewport PNG saved "+name)

func run():
	DisplayServer.window_set_size(Vector2i(1280,800))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,800)
	if save_quit_only:
		await check_save_quit()
		return
	Engine.time_scale = 6.0
	for mode in ["keyboard","touch","gamepad"]:
		if real_core:
			var core = load("res://game/core/game_session.gd")
			var setup = load("res://tests/expedition/prototype_cases.gd").new()
			setup.factory = func(seed_value): return core.new(seed_value)
			setup.root = output+"/normal-setup-"+mode
			DirAccess.make_dir_recursive_absolute(setup.root)
			var probe = core.new(1)
			if probe.snapshot().get("version",0) != 2:
				expect(false,"--real-core requires actual v2 integration")
				quit(1); return
			adapter = setup.growth(23,3).game
			expect(setup.failures.is_empty(),"real-session fixture earned growth through normal commands "+mode)
			expect(adapter.command("start_expedition").ok,"real third-day expedition started")
		else: adapter = ActionAdapter.new()
		observed_events = []
		panel = ExpeditionScene.instantiate()
		root.add_child(panel)
		panel.bind_session(adapter)
		panel.action_events.connect(func(events): observed_events.append_array(events))
		panel.pause_requested.connect(func(): adapter.set_paused(not adapter.view().paused))
		panel.save_requested.connect(func():
			save_count += 1
			if real_core: expect(adapter.save_to(output+"/"+mode+"-actual-session.json").ok,"actual GUI save request writes full session "+mode)
		)
		await process_frame
		# Every mode actually holds and releases all three action buttons.
		inject(mode,{"move_x":1.0,"move_y":0.0,"aim_x":1.0,"aim_y":0.0,"cast":true,"dodge":true,"skill":true})
		await process_frame
		await process_frame
		inject(mode,{"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false})
		await process_frame
		var released: Dictionary = panel.current_input()
		expect(released.move_x == 0.0 and released.move_y == 0.0 and not released.cast and not released.dodge and not released.skill,"actual release clears held controls "+mode)
		await click(panel.pause_button.position+panel.pause_button.size/2.0)
		expect(adapter.view().paused,"actual GUI click pauses "+mode)
		var before = adapter.view().expedition.duplicate(true)
		await create_timer(0.2,true,false,true).timeout
		expect(before == adapter.view().expedition,"actual wait freezes action simulation "+mode)
		var saved_before = save_count
		await click(panel.save_button.position+panel.save_button.size/2.0)
		expect(save_count == saved_before+1,"actual GUI click routes save request "+mode)
		if real_core:
			var restored = load("res://game/core/game_session.gd").new(1)
			expect(restored.load_from(output+"/"+mode+"-actual-session.json").ok,"real scene save reloads into fresh session "+mode)
			var before_restore: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output+"/"+mode+"-actual-session.json"))
			var restored_state: Dictionary = restored.snapshot()
			expect(JSON.parse_string(JSON.stringify(before_restore,"",true,true)) == JSON.parse_string(JSON.stringify(restored_state,"",true,true)),"real saved full session restores exactly while paused "+mode)
			adapter = restored
			panel.bind_session(adapter)
		await screenshot(mode+"-paused")
		await click(panel.pause_button.position+panel.pause_button.size/2.0)
		panel.grab_focus()
		pressed.clear(); active_touches.clear()
		var frames = 0
		var captured = false
		while adapter.view().phase == "expedition" and frames < 4000:
			frames += 1
			inject(mode,Driver.next_input(adapter.view().expedition))
			await process_frame
			if frames > 40 and not captured:
				await screenshot(mode+"-combat")
				captured = true
		var final_state: Dictionary = adapter.view().expedition
		expect(final_state.return_reason == "completed","InputEvent path defeats and collects through actual panel "+mode+": "+final_state.return_reason)
		for type in ["cast","dodge","skill","hit","enemy_defeated","drop_collected"]:
			expect(observed_events.any(func(e): return e.type == type),"actual "+mode+" event "+type)
		if real_core: expect(adapter.validate_snapshot(adapter.snapshot()).is_empty(),"real session inventory and complete state validate after UI combat "+mode)
		modes.append({"mode":mode,"simulated_input":true,"fixture":"real session, normal command setup" if real_core else "isolated model adapter","frames":frames,"state":final_state,"events":observed_events})
		panel.release_inputs()
		panel.queue_free()
		await process_frame
	# Narrow screenshot uses the same scene and independently sized touch targets.
	DisplayServer.window_set_size(Vector2i(960,640)); root.size = Vector2i(960,640)
	adapter = ActionAdapter.new(); panel = ExpeditionScene.instantiate(); root.add_child(panel); panel.bind_session(adapter)
	await process_frame
	await screenshot("narrow-960x640")
	var file = FileAccess.open(output+"/runtime-inputs.json",FileAccess.WRITE)
	var sources = {}
	for path in ["game/expedition/expedition_model.gd","game/expedition/expedition_panel.gd","game/core/game_session.gd","game/core/catalog.gd","assets/pixel/manifest.json"]:
		if FileAccess.file_exists("res://"+path): sources[path] = FileAccess.get_sha256("res://"+path)
	file.store_string(JSON.stringify({"schema_version":1,"checks":checks,"failures":failures,"modes":modes,"real_core":real_core,
		"engine":Engine.get_version_info(),"source_sha256":sources,"desktop_size":{"width":1280,"height":800},"narrow_size":{"width":960,"height":640},
		"claims":"Real-rendered action scene and InputEvent paths. Normal command setup is not a full restaurant UI/P14 claim; no physical controller/iOS claim."},"\t")); file.close()
	print("E01 rendered InputEvent checks: ",checks," failures: ",failures.size())
	quit(1 if not failures.is_empty() else 0)

func check_save_quit():
	DisplayServer.window_set_size(Vector2i(844,390)); root.size = Vector2i(844,390)
	adapter = ActionAdapter.new()
	adapter.set_paused(true)
	panel = ExpeditionScene.instantiate()
	root.add_child(panel)
	panel.bind_session(adapter)
	await process_frame
	if not panel.has_signal("save_quit_requested") or panel.get("save_quit_button") == null:
		expect(false,"visible save-and-quit button and signal required")
		quit(1); return
	var counts = {"save":0,"save_quit":0,"clean":true}
	panel.save_requested.connect(func(): counts.save += 1)
	panel.save_quit_requested.connect(func():
		counts.save_quit += 1
		var held: Dictionary = panel.current_input()
		counts.clean = counts.clean and held.move_x == 0.0 and held.move_y == 0.0 and not held.cast and not held.dodge and not held.skill
		var simulated: Dictionary = adapter.view().expedition.input
		for axis in ["move_x","move_y","aim_x","aim_y"]: counts.clean = counts.clean and simulated[axis] == 0.0
		for action in ["cast","dodge","skill"]: counts.clean = counts.clean and not simulated[action]
	)
	for mode in ["mouse","touch","gamepad"]:
		# Actual input first leaves several device controls held at the same time.
		panel.grab_focus()
		joy({"move_x":1.0,"move_y":0.0,"aim_x":1.0,"aim_y":0.0,"cast":true,"dodge":true,"skill":true})
		await process_frame
		var before: int = counts.save_quit
		var center: Vector2 = panel.save_quit_button.get_global_rect().get_center()
		if mode == "mouse": await click(center)
		elif mode == "touch":
			var down = InputEventScreenTouch.new(); down.index = 19; down.position = center; down.pressed = true
			Input.parse_input_event(down)
			await process_frame
			var up = InputEventScreenTouch.new(); up.index = 19; up.position = center; up.pressed = false
			Input.parse_input_event(up)
			await process_frame
		else:
			# Start at the same panel focus used by the real main UI, then navigate.
			joy({"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false})
			key_event(KEY_D,true); key_event(KEY_J,true); key_event(KEY_L,true)
			await process_frame
			panel.grab_focus()
			for code in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_A]:
				var down = InputEventJoypadButton.new(); down.button_index = code; down.pressed = true
				Input.parse_input_event(down)
				await process_frame
				var up = InputEventJoypadButton.new(); up.button_index = code; up.pressed = false
				Input.parse_input_event(up)
				await process_frame
		expect(counts.save_quit == before+1,"actual "+mode+" activates save-and-quit once")
		expect(counts.save == 0,"save-and-quit remains distinct from save "+mode)
		expect(counts.clean,"device and simulation holds clear before signal "+mode)
	for button in [panel.pause_button,panel.save_button,panel.save_quit_button,panel.return_button]:
		expect(Rect2(Vector2.ZERO,Vector2(844,390)).encloses(button.get_global_rect()),"toolbar target fits 844x390: "+button.text)
		expect(button.size.y >= 44.0,"touch target remains >=44px")
	await screenshot("save-quit-844x390")
	var file = FileAccess.open(output+"/save-quit-inputs.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"counts":counts,"width":844,"height":390,"claims":"Actual InputEvent activation of product signal; host owns full save and process exit."},"\t")); file.close()
	print("E01 save-and-quit checks: ",checks," failures: ",failures.size())
	quit(1 if not failures.is_empty() else 0)
