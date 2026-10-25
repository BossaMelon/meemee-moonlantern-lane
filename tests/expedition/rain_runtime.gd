extends "res://tests/expedition/runtime_inputs.gd"
## Isolated action rendering/InputEvent evidence, never a full Session/Q06 claim.
const RainDriver = preload("res://tests/expedition/rain_driver.gd")
const RainModel = preload("res://game/expedition/rain_garden_model.gd")
var captures: Array = []
var mode_reports: Array = []
var candidate: Dictionary = {}
class RainAdapter extends RefCounted:
	const ExpeditionModel = preload("res://game/expedition/expedition_model.gd")
	var state: Dictionary
	var phase = "expedition"
	var paused = false
	func _init(weapon: String):
		state = ExpeditionModel.create(1,"rendered-rain-"+weapon,23,weapon,["gust"],false,{"ruleset":"rain-night-v1","map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null})
	func view() -> Dictionary: return {"phase":phase,"paused":paused,"expedition":ExpeditionModel.view(state)}
	func command(kind: String, args: Dictionary = {}, _id: String = "") -> Dictionary:
		if kind == "expedition_input": return ExpeditionModel.set_input(state,args)
		if kind == "leave_expedition": phase = "shopping"; return ExpeditionModel.leave(state)
		return {"ok":false,"message":"isolated adapter has no economy commands","events":[]}
	func advance(ms: int) -> Dictionary:
		var result = ExpeditionModel.advance(state,ms,80,paused)
		if result.returned: phase = "shopping"
		return result
	func set_paused(value: bool):
		paused = value
		if not paused: ExpeditionModel.clear_input(state)
func _initialize():
	output = "/tmp/e02-rain-runtime"
	for i in range(OS.get_cmdline_user_args().size()-1):
		if OS.get_cmdline_user_args()[i] == "--output": output = OS.get_cmdline_user_args()[i+1]
	DirAccess.make_dir_recursive_absolute(output)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	call_deferred("run")
func inject(mode: String, input: Dictionary):
	if mode != "keyboard":
		super.inject(mode,input)
		return
	keyboard(input)
	# Continuous real mouse aim accompanies WASD/J/K/L, instead of quantized arrows alone.
	var world = Vector2(adapter.state.player.x,adapter.state.player.y)+Vector2(input.aim_x,input.aim_y)*65
	world.x = clampf(world.x,4,956); world.y = clampf(world.y,4,536)
	var event = InputEventMouseMotion.new()
	event.position = panel.field.position+world/Vector2(960,540)*panel.field.size
	event.global_position = event.position; event.relative = Vector2(4,0)
	root.push_input(event,true)
func _git(args: Array) -> String:
	var result: Array = []
	var command: Array = ["-C",ProjectSettings.globalize_path("res://")]
	command.append_array(args)
	var code = OS.execute("git",command,result,true)
	return "".join(result).strip_edges() if code == 0 else "unavailable"
func capture(name: String):
	if DisplayServer.get_name() == "headless": return
	# Keep the exact observed state stable while macOS presents/resizes the frame.
	# This is an explicit component capture boundary, not an in-game pause claim.
	var was_processing = panel.is_processing()
	panel.set_process(false); panel.refresh()
	await screenshot(name)
	captures.append({"name":name,"size":str(root.get_texture().get_size()),"viewport":str(root.size),"window_size":str(DisplayServer.window_get_size()),"window_mode":DisplayServer.window_get_mode(),"screen_size":str(DisplayServer.screen_get_size()),"usable_rect":str(DisplayServer.screen_get_usable_rect()),"focus":root.has_focus(),"no_focus_flag":root.get_flag(Window.FLAG_NO_FOCUS),"capture_process_suspended":true,"tick":adapter.state.tick,"elapsed_ms":adapter.state.elapsed_ms,"player_foot":[adapter.state.player.x,adapter.state.player.y],"hazards":adapter.state.hazards.duplicate(true),"png_sha256":FileAccess.get_sha256(output+"/"+name+".png")})
	panel.set_process(was_processing)
func run():
	var status = _git(["status","--porcelain"])
	candidate = {"sha":_git(["rev-parse","HEAD"]),"dirty":status != "","status":status}
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	# A fullscreen invocation keeps the real native/Retina viewport unchanged.
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN: root.size = Vector2i(1280,800)
	else: root.size = DisplayServer.window_get_size()
	await create_timer(0.5).timeout
	Engine.time_scale = 2.0
	Input.emulate_mouse_from_touch = false; Input.emulate_touch_from_mouse = false
	for mode in ["keyboard","touch","gamepad"]:
		pressed.clear(); active_touches.clear(); observed_events.clear()
		adapter = RainAdapter.new("bolt_wand" if mode == "keyboard" else "fan_wand")
		panel = ExpeditionScene.instantiate(); root.add_child(panel); panel.bind_session(adapter)
		panel.action_events.connect(func(rows): observed_events.append_array(rows))
		panel.pause_requested.connect(func(): adapter.set_paused(not adapter.paused); panel.refresh())
		panel.save_requested.connect(func():
			save_count += 1
			var file = FileAccess.open(output+"/"+mode+"-model-save.json",FileAccess.WRITE)
			file.store_string(JSON.stringify(adapter.state)))
		await process_frame; await process_frame
		await capture(mode+"-entry")
		var driver = RainDriver.new("shelf" if mode == "keyboard" else "canal",true,true)
		var warning_seen = false; var active_seen = false; var pause_checked = false
		var stagger_seen = false; var water_seen = false; var clear_seen = false
		var trace: Array = []
		for frame in range(6000):
			inject(mode,driver.next_input(adapter.state))
			await process_frame
			if frame % 25 == 0: trace.append({"tick":adapter.state.tick,"x":adapter.state.player.x,"y":adapter.state.player.y,"hp":adapter.state.player.hp,"input":adapter.state.input.duplicate()})
			if not stagger_seen and adapter.state.enemies.any(func(e): return e.state == "stagger"):
				stagger_seen = true
				await capture(mode+"-stagger")
			if not water_seen and not panel._water_ripples.is_empty():
				water_seen = true
				await capture(mode+"-water")
			if not clear_seen and observed_events.any(func(e): return e.type == "spore_cleared" and e.source == "deep-caster"):
				clear_seen = true
				await capture(mode+"-cleared")
			if not warning_seen and adapter.state.hazards.any(func(h): return h.state == "warning" and h.source == "deep-caster"):
				warning_seen = true
				await capture(mode+"-warning")
			if not active_seen and adapter.state.hazards.any(func(h): return h.state == "active" and h.source == "deep-caster"):
				active_seen = true
				await capture(mode+"-active")
			if warning_seen and not pause_checked:
				pause_checked = true
				key_event(KEY_ESCAPE,true); key_event(KEY_ESCAPE,false)
				await process_frame
				expect(adapter.paused,"real Esc pauses quality action "+mode)
				var before = adapter.state.duplicate(true)
				await process_frame; await process_frame
				expect(adapter.state == before,"paused warning/body/elapsed do not advance "+mode)
				var prior_saves = save_count
				await click(panel.save_button.get_global_rect().get_center())
				expect(save_count == prior_saves+1,"real GUI save fires once "+mode)
				var restored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output+"/"+mode+"-model-save.json"))
				expect(Model.validate(restored) == "" and RainModel._same(restored,adapter.state),"quality paused model disk round-trip "+mode)
				await capture(mode+"-pause")
				key_event(KEY_ESCAPE,true); key_event(KEY_ESCAPE,false)
				await process_frame
				expect(not adapter.paused,"real Esc resumes quality action "+mode)
				# Release was intentional. The simulated user presses again after the menu.
				pressed.clear(); active_touches.clear()
			if adapter.phase != "expedition": break
		panel.release_inputs()
		expect(adapter.state.status == "returned" and adapter.state.player.hp > 0,"real input quality route returns alive "+mode)
		expect(adapter.state.drops.any(func(d): return d.item_id == "moonheart" and d.collected),"real input collects actual elite drop "+mode)
		expect(observed_events.any(func(e): return e.type == "spore_cleared" and e.source == "deep-caster"),"real input gust clears deep zone "+mode)
		expect(warning_seen and active_seen,"both hazard phases actually rendered "+mode)
		expect(stagger_seen,"actual stump collision/stagger seen "+mode)
		if mode != "keyboard": expect(water_seen,"actual moving water steps seen "+mode)
		mode_reports.append({"mode":mode,"status":adapter.state.status,"reason":adapter.state.return_reason,"hp":adapter.state.player.hp,"elapsed_ms":adapter.state.elapsed_ms,"trace":trace,"events":observed_events.duplicate(true)})
		panel.queue_free(); await process_frame
	# The same actual layout and controls must fit a narrow touch viewport.
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(844,390); adapter = RainAdapter.new("fan_wand")
	panel = ExpeditionScene.instantiate(); root.add_child(panel); panel.bind_session(adapter); panel.set_input_mode("touch")
	await process_frame; await process_frame
	for kind in panel._centers():
		var center: Vector2 = panel._centers()[kind]
		var radius = panel.touch_radius(kind)
		expect(Rect2(Vector2.ZERO,panel.size).encloses(Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2)),"narrow touch control fits "+kind)
	await capture("narrow-touch")
	adapter.set_paused(true); panel.refresh(); await process_frame
	for button in [panel.pause_button,panel.save_button,panel.save_quit_button,panel.return_button]: expect(Rect2(Vector2.ZERO,panel.size).encloses(button.get_rect()) and button.size.y >= 44,"narrow pause button fits")
	await capture("narrow-pause")
	var report = {"kind":"isolated-rain-action-input-rendering","claim":"No economic Session, full process restore, human fun or device claim","engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"checks":checks,"failures":failures,"captures":captures,"modes":mode_reports,"source_sha256":FileAccess.get_sha256("res://game/expedition/expedition_panel.gd"),"model_sha256":FileAccess.get_sha256("res://game/expedition/rain_garden_model.gd"),"manifest_sha256":FileAccess.get_sha256("res://assets/pixel/manifest.json"),"candidate":candidate,"geometry_sha256":FileAccess.get_sha256("res://game/expedition/rain_garden_map.gd"),"world_sources":{},"stump_visuals":[]}
	for path in ["backgrounds/mushroom-garden.png","backgrounds/rain_ground_routes.png","backgrounds/rain_canal_shallow.png","sprites/garden_stump.png","sprites/garden_root_log_50.png","sprites/garden_root_log_45.png"]: report.world_sources[path] = FileAccess.get_sha256("res://assets/pixel/"+path)
	for obstacle in preload("res://game/expedition/rain_garden_map.gd").OBSTACLES:
		var visual: Dictionary = panel._stump_visual(obstacle)
		report.stump_visuals.append({"model":obstacle,"texture_id":visual.id,"scale":visual.scale,"foot":[visual.position.x,visual.position.y],"pivot":panel.manifest.sprites[visual.id].pivot})
	var file = FileAccess.open(output+"/report.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  "))
	print("E02 rendered input: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
