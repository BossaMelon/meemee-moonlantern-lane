extends SceneTree
## Real Control input regression; uses public UI actions, never mutates core state.
## Run with Godot --path . --script game/ui/checks/interaction.gd.
## Synthetic touch/pad input is not physical device certification.
## This route uses the legacy catalog to cover generic controls while the
## restaurant contract is being frozen; it is not restaurant acceptance.
const Main = preload("res://scenes/main.tscn")
var ui
var mode = "mouse"
var failures: Array[String] = []
var trace: Array = []
var checks = 0
var folder: String
var selected_routes: PackedStringArray = []

func _initialize():
	folder = ProjectSettings.globalize_path("res://output/p02")
	DirAccess.make_dir_recursive_absolute(folder)
	call_deferred("run")

func expect(value: bool, message: String):
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
		write_report()
		quit(1)

func frames(n: int = 3):
	for _i in range(n): await process_frame

func activate(id: String):
	var button = ui.get_action_control(id)
	expect(is_instance_valid(button),mode+" control exists: "+id)
	if not is_instance_valid(button): return
	expect(not button.disabled,mode+" control enabled: "+id)
	if button.disabled: return
	if ui.scroll.is_ancestor_of(button):
		ui.scroll.ensure_control_visible(button)
	await frames()
	var rect: Rect2 = button.get_global_rect()
	var pos = rect.get_center()
	expect(rect.size.x >= 48 and rect.size.y >= 48,"minimum target: "+id)
	expect(Rect2(Vector2.ZERO,root.size).encloses(rect),"target on screen: "+id+" "+str(rect))
	if mode == "pad":
		# Focus discovery is read-only; move with actual D-pad events until target.
		var guard = 0
		while root.gui_get_focus_owner() != button and guard < 100:
			var direction = InputEventJoypadButton.new()
			direction.button_index = JOY_BUTTON_DPAD_DOWN
			direction.pressed = true
			Input.parse_input_event(direction)
			await frames(1)
			direction = InputEventJoypadButton.new()
			direction.button_index = JOY_BUTTON_DPAD_DOWN
			direction.pressed = false
			Input.parse_input_event(direction)
			await frames(1)
			guard += 1
		expect(root.gui_get_focus_owner() == button,"D-pad reaches "+id)
		for down in [true,false]:
			var event = InputEventJoypadButton.new()
			event.button_index = JOY_BUTTON_A
			event.pressed = down
			Input.parse_input_event(event)
			await frames(1)
	elif mode == "touch":
		for down in [true,false]:
			var event = InputEventScreenTouch.new()
			event.index = 0
			event.position = pos
			event.pressed = down
			Input.parse_input_event(event)
	else:
		var motion = InputEventMouseMotion.new()
		motion.position = pos
		Input.parse_input_event(motion)
		for down in [true,false]:
			var event = InputEventMouseButton.new()
			event.position = pos
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			Input.parse_input_event(event)
	await frames()
	var v: Dictionary = ui.game.view()
	print("INPUT ",mode," ",id," => ",v.day,"/",v.phase," cash=",v.cash)
	trace.append({"mode":mode,"action":id,"day":v.day,"phase":v.phase,"cash":v.cash,"clock_ms":v.clock_ms,"cursor":v.cursor})

func screenshot(name: String):
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	expect(image.save_png(folder+"/"+name+".png") == OK,"screenshot "+name)

func fresh(size: Vector2i):
	if is_instance_valid(ui):
		ui.free()
	root.size = size
	ui = Main.instantiate()
	expect(ui.has_method("get_action_control"),"main UI script must load")
	if not ui.has_method("get_action_control"): return
	# A separate temporary save for every input route; never touches player saves.
	ui.save_path = folder+"/"+mode+"-save.json"
	root.add_child(ui)
	await frames(6)
	expect(ui.size == Vector2(size),"actual responsive size "+str(ui.size))

func batch(value: int):
	if value in [1,3,5]: await activate("batch_"+str(value))
	else:
		await activate("batch_3")
		await activate("batch_more")

func trade(day: int):
	await activate("primary")
	expect(ui.view.phase == "trading","open day "+str(day))
	await activate("pause")
	var frozen: Dictionary = ui.game.snapshot()
	await create_timer(1.15).timeout
	expect(ui.game.snapshot() == frozen,"real wait while paused "+mode)
	expect(ui.primary.disabled,"pause disables economic transition")
	await activate("save")
	await activate("pause")
	var guard = 0
	while ui.game.view().phase == "trading" and guard < 150:
		if not ui.view.pending.is_empty():
			frozen = ui.game.snapshot()
			await create_timer(1.15).timeout
			expect(ui.game.snapshot() == frozen,"real special-order wait freezes state")
			if day == 1: await screenshot(mode+"-special")
			var picked = false
			for option in ui.view.pending.options:
				if option.available:
					await activate("fulfill_"+option.item_id)
					picked = true
					break
			expect(picked,"at least one stocked matching special option")
			if not picked: await activate("special_decline")
		else:
			await create_timer(0.1).timeout
		guard += 1
	expect(ui.view.phase == "closing","queue completes")
	await activate("primary")
	expect(ui.view.phase == "settled","settle day "+str(day))

func run_route(route: String, size: Vector2i):
	mode = route
	await fresh(size)
	await screenshot(mode+"-shopping")
	for day in range(1,4):
		await batch(4)
		for raw in ["feather","ink","timber"]: await activate("buy_"+raw)
		if day == 1:
			await batch(1)
			await activate("buy_bell")
		await activate("primary")
		expect(ui.view.phase == "preparation","finish shopping")
		await batch(4)
		for product in ["pen","lamp"]: await activate("craft_"+product)
		await activate("to_shelf")
		if day == 1: await activate("install_bell")
		for product in ["pen","lamp"]:
			await activate("select_"+product)
			await activate("display_"+product)
			await activate("price_standard")
		if day == 1: await screenshot(mode+"-shelf")
		await trade(day)
		if day == 1:
			await activate("upgrade_shelf")
			var before: Dictionary = ui.game.snapshot()
			await activate("save")
			# Recreate the actual scene; load through its visible restore action.
			await fresh(size)
			await activate("load")
			if ui.game.snapshot() != before:
				for key in before:
					if before[key] != ui.game.snapshot()[key]: print("RESTORE DIFFERENCE ",key,"; persisted values equal: ",JSON.stringify(before[key]) == JSON.stringify(ui.game.snapshot()[key]))
			expect(ui.game.snapshot() == before,"restore preserves settlement, ledger and random state")
		if day < 3: await activate("primary")
	expect(ui.view.finished,"three days finish via "+route)
	await activate("save")
	await screenshot(mode+"-finished")
	var before: Dictionary = ui.game.snapshot()
	ui.save_path = folder+"/"+mode+"-damaged.json"
	var file = FileAccess.open(ui.save_path,FileAccess.WRITE)
	file.store_string("{broken save")
	file.close()
	await activate("load")
	expect(ui.game.snapshot() == before,"bad save leaves current session intact")
	expect("恢复失败" in ui.feedback.text,"bad save gives visible feedback")

func run():
	var routes = OS.get_cmdline_user_args()
	selected_routes = routes
	if "consult" in routes:
		await check_consult_layout()
		return
	if "resume" in routes:
		await resume_saved_route()
		return
	if routes.is_empty() or "mouse" in routes: await run_route("mouse",Vector2i(1280,720))
	if failures.is_empty() and (routes.is_empty() or "touch" in routes): await run_route("touch",Vector2i(960,640))
	if failures.is_empty() and (routes.is_empty() or "pad" in routes): await run_route("pad",Vector2i(960,640))
	write_report()
	print("P02 UI checks: ",checks,"; failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)

func write_report():
	var report = {"suite":"P02 UI synthetic input regression","checks":checks,"failures":failures,"trace":trace,"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string}
	var file = FileAccess.open(folder+"/interaction-"+("all" if selected_routes.is_empty() else "-".join(selected_routes))+"-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()

func resume_saved_route():
	mode = "mouse"
	var path = folder+"/mouse-save.json"
	expect(FileAccess.file_exists(path),"previous engine process left a real save")
	var expected = JSON.parse_string(FileAccess.get_file_as_string(path))
	await fresh(Vector2i(1280,720))
	await activate("load")
	expect(JSON.parse_string(JSON.stringify(ui.game.snapshot())) == expected,"new engine process restores full persisted state")
	expect(ui.view.finished,"new engine process restores day-three completion")
	await screenshot("mouse-restarted")
	var before: Dictionary = ui.game.snapshot()
	await activate("primary")
	expect(ui.game.snapshot() == before,"completed journey save cannot repeat settlement")
	write_report()
	await activate("quit")
	expect(false,"save-and-quit must exit the engine")

func check_consult_layout():
	mode = "pad"
	await fresh(Vector2i(960,640))
	ui.save_path = folder+"/pad-save.json.bak"
	await activate("load")
	expect(ui.view.phase == "trading","consult fixture is a real earlier trading save")
	if ui.view.paused: await activate("pause")
	var guard = 0
	while ui.view.pending.is_empty() and guard < 100:
		await create_timer(0.1).timeout
		guard += 1
	expect(not ui.view.pending.is_empty(),"real customer reaches consultation")
	expect(ui.order_caption.visible and not ui.order_caption.text.is_empty(),"request and budget remain outside scrolling actions")
	expect(Rect2(Vector2.ZERO,root.size).encloses(ui.order_caption.get_global_rect()),"request caption stays on screen")
	var frozen: Dictionary = ui.game.snapshot()
	await create_timer(1.15).timeout
	expect(ui.game.snapshot() == frozen,"consultation remains frozen")
	await screenshot("pad-consult-fixed")
	var served = false
	for option in ui.view.pending.options:
		if option.available:
			await activate("fulfill_"+option.item_id)
			served = true
			break
	expect(served,"matching recommendation remains reachable with D-pad/A")
	write_report()
	quit(0 if failures.is_empty() else 1)
