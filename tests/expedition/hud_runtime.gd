extends SceneTree
## Actual fullscreen viewport evidence; no synthetic canvas composites.
const Session = preload("res://game/core/game_session.gd")
const Scene = preload("res://scenes/expedition/expedition.tscn")
const Driver = preload("res://tests/expedition/action_driver.gd")
var panel
var g
var source = ""
var output = "/tmp/e01-hud-fullscreen"
var checks = 0
var failures: Array = []
var captures: Array = []
var pressed: Dictionary = {}
var active_touches: Dictionary = {}
var events: Array = []
var focus_events: Array = []
var input_events: Array = []

func _initialize():
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i] == "--source": source = args[i+1]
		if args[i] == "--output": output = args[i+1]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)

func coverage() -> String:
	var screen = DisplayServer.window_get_current_screen()
	var window_rect = Rect2i(DisplayServer.window_get_position(),DisplayServer.window_get_size())
	var screen_rect = Rect2i(DisplayServer.screen_get_position(screen),DisplayServer.screen_get_size(screen))
	if window_rect == screen_rect: return "screen"
	var usable = DisplayServer.screen_get_usable_rect(screen)
	if DisplayServer.get_name() == "macOS" and screen_rect.encloses(usable) and window_rect == usable: return "macos_usable_rect"
	return ""

func key(code: int, down: bool):
	var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down
	emit_input(event)

func emit_input(event: InputEvent, local: bool = false):
	input_events.append({"at_ms":Time.get_ticks_msec(),"event":event.as_text(),"class":event.get_class(),"focused":root.has_focus()})
	if local: root.push_input(event,true)
	else: Input.parse_input_event(event)

func inject(mode: String, input: Dictionary):
	if mode == "keyboard":
		var next = {KEY_W:input.move_y < -0.3,KEY_S:input.move_y > 0.3,KEY_A:input.move_x < -0.3,KEY_D:input.move_x > 0.3,
			KEY_UP:input.aim_y < -0.3,KEY_DOWN:input.aim_y > 0.3,KEY_LEFT:input.aim_x < -0.3,KEY_RIGHT:input.aim_x > 0.3,KEY_J:input.cast,KEY_K:input.dodge,KEY_L:input.skill}
		for code in next:
			if next[code] != pressed.get(code,false): key(code,next[code])
		pressed = next
	elif mode == "gamepad":
		for pair in [[JOY_AXIS_LEFT_X,input.move_x],[JOY_AXIS_LEFT_Y,input.move_y],[JOY_AXIS_RIGHT_X,input.aim_x],[JOY_AXIS_RIGHT_Y,input.aim_y]]:
			var event = InputEventJoypadMotion.new(); event.axis = pair[0]; event.axis_value = pair[1]; emit_input(event)
		for pair in [[JOY_BUTTON_A,input.cast],[JOY_BUTTON_B,input.dodge],[JOY_BUTTON_X,input.skill]]:
			var event = InputEventJoypadButton.new(); event.button_index = pair[0]; event.pressed = pair[1]; emit_input(event)
	else:
		var values = {"move":Vector2(input.move_x,input.move_y),"aim":Vector2(input.aim_x,input.aim_y),"cast":input.cast,"dodge":input.dodge,"skill":input.skill}
		var index = 0
		for kind in values:
			var center: Vector2 = panel._centers()[kind]
			var on: bool = values[kind].length_squared() > 0.00001 if values[kind] is Vector2 else values[kind]
			if on and not active_touches.get(index,false):
				var event = InputEventScreenTouch.new(); event.index = index; event.position = center; event.pressed = true; emit_input(event,true)
			if on and values[kind] is Vector2:
				var event = InputEventScreenDrag.new(); event.index = index; event.position = center+values[kind]*panel.touch_radius(kind); emit_input(event,true)
			if not on and active_touches.get(index,false):
				var event = InputEventScreenTouch.new(); event.index = index; event.position = center; event.pressed = false; emit_input(event,true)
			active_touches[index] = on
			index += 1

func fresh():
	if is_instance_valid(panel): panel.release_inputs(); panel.queue_free(); await process_frame
	g = Session.new(23)
	if source != "": expect(g.load_from(source).ok,"load earned P03 action checkpoint")
	else: expect(g.command("start_expedition").ok,"start real expedition")
	g.set_paused(false)
	panel = Scene.instantiate(); root.add_child(panel); panel.bind_session(g)
	panel.pause_requested.connect(func(): g.set_paused(not g.view().paused); panel.refresh())
	panel.action_events.connect(func(rows): events.append_array(rows))
	pressed.clear(); active_touches.clear()
	panel.grab_focus()
	await process_frame

func capture(name: String):
	await RenderingServer.frame_post_draw
	var texture = root.get_texture()
	var picture = texture.get_image()
	expect(picture.save_png(output+"/"+name+".png") == OK,"save actual viewport "+name)
	var screen = DisplayServer.window_get_current_screen()
	var usable = DisplayServer.screen_get_usable_rect(screen)
	var screen_size = DisplayServer.screen_get_size(screen)
	var window_size = DisplayServer.window_get_size()
	var row = {"name":name,"path":output+"/"+name+".png","window_mode":DisplayServer.window_get_mode(),"root_mode":root.mode,
		"screen_size":[screen_size.x,screen_size.y],"usable_rect":[usable.position.x,usable.position.y,usable.size.x,usable.size.y],
		"screen_scale":DisplayServer.screen_get_scale(screen),"window_size":[window_size.x,window_size.y],"viewport_size":[root.size.x,root.size.y],
		"png_size":[picture.get_width(),picture.get_height()],"coverage":coverage(),"focused":root.has_focus(),"input_mode":panel.input_mode,"field":[panel.field.position.x,panel.field.position.y,panel.field.size.x,panel.field.size.y],
		"field_fraction":panel.field.get_area()/(panel.size.x*panel.size.y),"state":g.snapshot().expedition,"source_checkpoint":source}
	captures.append(row)
	expect(row.field_fraction > 0.85,"arena occupies useful fullscreen area")
	expect(row.png_size == row.window_size and row.png_size == row.viewport_size,"PNG, window and logical viewport match without image resizing")
	expect(row.window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN and row.coverage != "","actual native fullscreen coverage")
	print(name,": ",row.png_size," mode ",row.window_mode," field ",row.field_fraction)

func run():
	root.focus_entered.connect(func(): focus_events.append({"at_ms":Time.get_ticks_msec(),"focused":true}))
	root.focus_exited.connect(func(): focus_events.append({"at_ms":Time.get_ticks_msec(),"focused":false}))
	# Native transition is asynchronous on macOS. Never resize fullscreen to a test box.
	var deadline = Time.get_ticks_msec()+10000
	var stable_since = Time.get_ticks_msec()
	var last = Rect2i()
	while Time.get_ticks_msec() < deadline:
		var current = Rect2i(DisplayServer.window_get_position(),DisplayServer.window_get_size())
		var correct = root.mode == Window.MODE_FULLSCREEN and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN and coverage() != ""
		if current != last or not correct: stable_since = Time.get_ticks_msec()
		last = current
		if correct and Time.get_ticks_msec()-stable_since >= 500: break
		await process_frame
	expect(Time.get_ticks_msec()-stable_since >= 500 and coverage() != "","native fullscreen rect stable for 500ms")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	await process_frame
	for mode in ["keyboard","gamepad","touch"]:
		await fresh()
		var until = Time.get_ticks_msec()+1600
		while Time.get_ticks_msec() < until and g.view().phase == "expedition":
			inject(mode,Driver.next_input(g.view().expedition))
			await process_frame
			if not g.view().expedition.projectiles.is_empty(): break
		expect(panel.input_mode == mode,"HUD follows actual "+mode+" events")
		expect(g.view().phase == "expedition","actual input never activates return toolbar")
		await capture("fullscreen-"+mode)
		if mode == "touch":
			for kind in panel._centers():
				var radius = panel.touch_radius(kind)
				expect(Rect2(Vector2.ZERO,panel.size).encloses(Rect2(panel._centers()[kind]-Vector2.ONE*radius,Vector2.ONE*radius*2)),"touch target fits "+kind)
	await fresh()
	var until = Time.get_ticks_msec()+3500
	while Time.get_ticks_msec() < until:
		if g.view().expedition.enemies.any(func(e): return not e.telegraph.is_empty()): break
		await process_frame
	expect(g.view().expedition.enemies.any(func(e): return not e.telegraph.is_empty()),"warning screenshot shows actual active telegraph")
	await capture("fullscreen-warning")
	key(KEY_ESCAPE,true); await process_frame; key(KEY_ESCAPE,false); await process_frame
	expect(g.view().paused and panel.save_button.is_visible_in_tree(),"native pause reveals real save controls")
	await capture("fullscreen-pause")
	var hashes = {}
	for path in ["game/expedition/expedition_panel.gd","game/expedition/expedition_model.gd","assets/pixel/manifest.json","assets/pixel/backgrounds/mushroom-garden.png"]:
		hashes[path] = FileAccess.get_sha256("res://"+path)
	var file = FileAccess.open(output+"/hud-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"events":events,"focus_events":focus_events,"input_events":input_events,"engine":Engine.get_version_info(),"source_sha256":hashes,"synthetic_input":true,"claims":"Actual native fullscreen viewport and input; checkpoint setup is not full restaurant runtime acceptance."},"\t")); file.close()
	print("E01 fullscreen HUD ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
