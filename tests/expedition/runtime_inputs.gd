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

func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)

func _initialize():
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
	Engine.time_scale = 6.0
	for mode in ["keyboard","touch","gamepad"]:
		adapter = ActionAdapter.new()
		panel = ExpeditionScene.instantiate()
		root.add_child(panel)
		panel.bind_session(adapter)
		panel.pause_requested.connect(func(): adapter.paused = not adapter.paused; if not adapter.paused: Model.clear_input(adapter.state))
		panel.save_requested.connect(func(): save_count += 1)
		await process_frame
		# Every mode actually holds and releases all three action buttons.
		inject(mode,{"move_x":1.0,"move_y":0.0,"aim_x":1.0,"aim_y":0.0,"cast":true,"dodge":true,"skill":true})
		await process_frame
		await process_frame
		await click(panel.pause_button.position+panel.pause_button.size/2.0)
		expect(adapter.paused,"actual GUI click pauses "+mode)
		var before = adapter.state.duplicate(true)
		await create_timer(0.2,true,false,true).timeout
		expect(before == adapter.state,"actual wait freezes action simulation "+mode)
		await click(panel.save_button.position+panel.save_button.size/2.0)
		expect(save_count > 0,"actual GUI click routes save request "+mode)
		await screenshot(mode+"-paused")
		await click(panel.pause_button.position+panel.pause_button.size/2.0)
		pressed.clear(); active_touches.clear()
		var frames = 0
		var captured = false
		while adapter.phase == "expedition" and frames < 4000:
			frames += 1
			inject(mode,Driver.next_input(adapter.state))
			await process_frame
			if frames > 40 and not captured:
				await screenshot(mode+"-combat")
				captured = true
		expect(adapter.state.return_reason == "completed","InputEvent path defeats and collects through actual panel "+mode+": "+adapter.state.return_reason)
		for type in ["cast","dodge","skill","hit","enemy_defeated","drop_collected"]:
			expect(adapter.events.any(func(e): return e.type == type),"actual "+mode+" event "+type)
		modes.append({"mode":mode,"simulated_input":true,"fixture":"isolated action model; not core progression or full P14","frames":frames,"state":adapter.state,"events":adapter.events})
		panel.release_inputs()
		panel.queue_free()
		await process_frame
	# Narrow screenshot uses the same scene and independently sized touch targets.
	DisplayServer.window_set_size(Vector2i(960,640)); root.size = Vector2i(960,640)
	adapter = ActionAdapter.new(); panel = ExpeditionScene.instantiate(); root.add_child(panel); panel.bind_session(adapter)
	await process_frame
	await screenshot("narrow-960x640")
	var file = FileAccess.open(output+"/runtime-inputs.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"checks":checks,"failures":failures,"modes":modes,"claims":"Isolated real-rendered scene and InputEvent adapter paths only. No physical controller/iOS/full core integration claim."},"\t")); file.close()
	print("E01 rendered InputEvent checks: ",checks," failures: ",failures.size())
	quit(1 if not failures.is_empty() else 0)
