extends SceneTree
## Focused real-session regressions. Snapshots include requests without exclusions.
const Session = preload("res://game/core/game_session.gd")
const Scene = preload("res://scenes/expedition/expedition.tscn")
var g
var panel
var failures: Array = []
var checks = 0
var output = "/tmp/e01-input-boundaries"
var stage = "boundaries"
var source = ""
var active_exit = false
var tools = {"pause":0,"save":0,"save_quit":0,"return":0}

func _initialize():
	var args = OS.get_cmdline_user_args()
	active_exit = "--active-exit" in args
	for i in range(args.size()-1):
		if args[i] == "--output": output = args[i+1]
		if args[i] == "--stage": stage = args[i+1]
		if args[i] == "--source": source = args[i+1]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func expect(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message); push_error(message)

func canonical(snapshot: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(snapshot,"",true,true))

func write_json(name: String, data: Dictionary):
	var file = FileAccess.open(output+"/"+name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t",true,true)); file.close()

func key(code: int, down: bool):
	var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down
	Input.parse_input_event(event)

func axis(code: int, amount: float):
	var event = InputEventJoypadMotion.new(); event.axis = code; event.axis_value = amount
	Input.parse_input_event(event)

func pad(code: int, down: bool):
	var event = InputEventJoypadButton.new(); event.button_index = code; event.pressed = down
	Input.parse_input_event(event)

func click(button: Button):
	var at = button.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new(); motion.position = at; motion.global_position = at
	root.push_input(motion,true); await process_frame
	var down = InputEventMouseButton.new(); down.position = at; down.global_position = at; down.button_index = MOUSE_BUTTON_LEFT; down.button_mask = MOUSE_BUTTON_MASK_LEFT; down.pressed = true
	root.push_input(down,true); await process_frame
	var up = InputEventMouseButton.new(); up.position = at; up.global_position = at; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
	root.push_input(up,true); await process_frame

func attach():
	panel = Scene.instantiate(); root.add_child(panel); panel.bind_session(g)
	panel.pause_requested.connect(func(): tools.pause += 1; g.set_paused(not g.view().paused))
	panel.save_requested.connect(func(): tools.save += 1)
	panel.save_quit_requested.connect(func(): tools.save_quit += 1)
	panel.returned.connect(func(): tools["return"] += 1)

func run():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(844,390)
	if stage == "restore":
		g = Session.new(1)
		expect(g.load_from(output+"/actual-exit-save.json").ok,"fresh process loads actual product exit save")
		var disk = JSON.parse_string(FileAccess.get_file_as_string(output+"/actual-exit-save.json"))
		attach()
		for i in range(5): await process_frame
		expect(canonical(g.snapshot()) == disk,"fresh process binding leaves full saved snapshot and requests exact")
		write_json("restored-memory",g.snapshot())
		finish(); return
	if stage == "write":
		g = Session.new(23)
		if source != "": expect(g.load_from(source).ok,"loads independent P03 source without altering its request table")
		else: g.command("start_expedition"); g.set_paused(true)
		if active_exit: g.set_paused(false)
		attach()
		panel.save_quit_requested.connect(func():
			# The real P02 host releases again, then saves, refreshes, and quits.
			panel.release_inputs()
			expect(g.save_to(output+"/actual-exit-save.json").ok,"product signal saves full real session")
			panel.refresh()
			quit()
		)
		panel.tree_exiting.connect(func():
			var disk = JSON.parse_string(FileAccess.get_file_as_string(output+"/actual-exit-save.json"))
			expect(canonical(g.snapshot()) == disk,"actual tree_exiting equals disk including requests")
			write_json("tree-exiting-memory",g.snapshot())
			write_json("write-report",{"checks":checks,"failures":failures,"tools":tools})
		)
		await process_frame
		if active_exit:
			key(KEY_D,true); key(KEY_J,true)
			await create_timer(0.2).timeout
			key(KEY_ESCAPE,true); await process_frame; key(KEY_ESCAPE,false); await process_frame
			expect(g.view().paused,"active gameplay opens the real pause menu before save-and-quit")
		await click(panel.save_quit_button)
		return
	g = Session.new(23); g.command("start_expedition"); g.set_paused(true)
	var before = canonical(g.snapshot())
	attach()
	for i in range(4): await process_frame
	expect(canonical(g.snapshot()) == before,"binding an already cleared paused session adds no zero-input request")
	write_json("binding-memory",g.snapshot())
	g.set_paused(false); panel.grab_focus()
	key(KEY_D,true); key(KEY_J,true)
	await process_frame; await process_frame
	expect(g.snapshot().expedition.input.cast and g.snapshot().expedition.input.move_x > 0,"actual held action reaches session")
	var request_count = g.snapshot().requests.size()
	panel.release_inputs()
	expect(g.snapshot().requests.size() == request_count+1,"necessary clear is committed exactly once")
	g.set_paused(true)
	before = canonical(g.snapshot())
	panel.release_inputs(); panel.release_inputs()
	for i in range(4): await process_frame
	expect(canonical(g.snapshot()) == before,"repeated clear and idle frames do not append requests")
	key(KEY_D,false); key(KEY_J,false)
	# Replay the raw left/right stick plus held A sequence through the real GUI.
	g.set_paused(false); panel.grab_focus()
	var tool_before = tools.duplicate()
	axis(JOY_AXIS_LEFT_X,0.6); axis(JOY_AXIS_LEFT_Y,-0.8)
	axis(JOY_AXIS_RIGHT_X,0.6); axis(JOY_AXIS_RIGHT_Y,-0.8)
	pad(JOY_BUTTON_A,true)
	await create_timer(0.25).timeout
	var held: Dictionary = g.snapshot().expedition.input
	expect(held.cast and held.move_x > 0.0 and held.move_y < 0.0 and held.aim_y < 0.0,"playing raw sticks and held A still reach actual movement/aim/cast")
	axis(JOY_AXIS_LEFT_X,0.0); axis(JOY_AXIS_LEFT_Y,0.0)
	axis(JOY_AXIS_RIGHT_X,0.0); axis(JOY_AXIS_RIGHT_Y,0.0)
	pad(JOY_BUTTON_A,false)
	await process_frame; await process_frame
	expect(g.view().phase == "expedition" and not g.view().paused and tools == tool_before,"playing stick/A release never activates a toolbar or retreats")
	expect(g.snapshot().expedition.input.move_x == 0 and not g.snapshot().expedition.input.cast,"playing stick/A release reaches actual combat state")
	write_json("pad-after-release",g.snapshot())
	# A stale toolbar focus must also be harmless while playing.
	if g.view().phase == "expedition":
		g.set_paused(true); panel.release_inputs(); panel.grab_focus()
		for code in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_RIGHT]:
			pad(code,true); await process_frame; pad(code,false); await process_frame
		expect(root.gui_get_focus_owner() == panel.return_button,"paused menu remains reachable through actual controller navigation")
		g.set_paused(false)
		pad(JOY_BUTTON_A,true); await process_frame; pad(JOY_BUTTON_A,false); await process_frame
		expect(g.view().phase == "expedition","playing A cannot activate stale focused return button")
		tool_before = tools.duplicate()
		key(KEY_UP,true); key(KEY_SPACE,true)
		await process_frame; await process_frame
		expect(g.view().expedition.input.cast and g.view().expedition.input.aim_y < 0,"playing arrow aim and Space actually reach combat")
		key(KEY_UP,false); key(KEY_SPACE,false)
		await process_frame; await process_frame
		expect(g.view().phase == "expedition" and tools == tool_before,"playing arrow/Space release never activates stale GUI focus")
	write_json("boundaries-memory",g.snapshot())
	await paused_tools()
	await cancelled_exit()
	finish()

func activate_tool(mode: String, button: Button, index: int):
	if mode == "mouse": await click(button)
	elif mode == "touch":
		var at = button.get_global_rect().get_center()
		var down = InputEventScreenTouch.new(); down.index = 25; down.position = at; down.pressed = true
		Input.parse_input_event(down); await process_frame
		var up = InputEventScreenTouch.new(); up.index = 25; up.position = at; up.pressed = false
		Input.parse_input_event(up); await process_frame
	else:
		panel.grab_focus()
		pad(JOY_BUTTON_DPAD_UP,true); await process_frame; pad(JOY_BUTTON_DPAD_UP,false); await process_frame
		for i in range(index):
			pad(JOY_BUTTON_DPAD_RIGHT,true); await process_frame; pad(JOY_BUTTON_DPAD_RIGHT,false); await process_frame
		pad(JOY_BUTTON_A,true); await process_frame; pad(JOY_BUTTON_A,false); await process_frame

func paused_tools():
	for mode in ["mouse","touch","gamepad"]:
		panel.queue_free(); await process_frame
		g = Session.new(23); g.command("start_expedition"); g.set_paused(true)
		attach(); await process_frame
		var before: Dictionary = tools.duplicate()
		await activate_tool(mode,panel.save_button,1)
		expect(tools.save == before.save+1 and tools.save_quit == before.save_quit and g.view().phase == "expedition","paused "+mode+" saves through actual button press/release")
		await activate_tool(mode,panel.save_quit_button,2)
		expect(tools.save_quit == before.save_quit+1 and g.view().phase == "expedition","paused "+mode+" requests save-and-quit through actual button")
		panel.cancel_save_quit()
		await activate_tool(mode,panel.return_button,3)
		expect(tools["return"] == before["return"]+1 and g.view().phase == "shopping" and g.view().expedition.return_reason == "retreat","paused "+mode+" intentionally returns through actual button")

func cancelled_exit():
	panel.queue_free(); await process_frame
	g = Session.new(23); g.command("start_expedition")
	attach(); await process_frame
	key(KEY_ESCAPE,true); await process_frame; key(KEY_ESCAPE,false); await process_frame
	expect(g.view().paused,"save-and-quit is reached from the actual pause menu")
	await click(panel.save_quit_button)
	var frozen = canonical(g.snapshot())
	key(KEY_D,true); panel.release_inputs()
	for i in range(3): await process_frame
	expect(canonical(g.snapshot()) == frozen,"pending exit rejects further frames and input without changing requests")
	panel.cancel_save_quit()
	key(KEY_ESCAPE,true); await process_frame; key(KEY_ESCAPE,false); await process_frame
	expect(not g.view().paused,"cancelled exit can continue through actual pause input")
	key(KEY_D,true)
	await process_frame; await process_frame
	expect(g.snapshot().expedition.input.move_x > 0,"host cancellation restores actual combat input")
	key(KEY_D,false)
	await process_frame; await process_frame
	expect(g.snapshot().expedition.input.move_x == 0,"release after cancelled exit still clears real input")

func finish():
	write_json(stage+"-report",{"checks":checks,"failures":failures,"tools":tools,"claims":"Real InputEvent and full snapshots including requests; no filtered equality."})
	print("E01 input boundary ",stage,": ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
