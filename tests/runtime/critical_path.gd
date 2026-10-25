extends "res://game/ui/checks/restaurant.gd"
## P03: real main scene, synthetic inputs, read-only session observations.
## Common restaurant purchasing helpers are reused from the UI owner's smoke test.
const CombatDriver = preload("res://tests/expedition/action_driver.gd")
var stage = "start"
var attempt = ""
var action_events: Array = []
var economic_intents: Array = []
var checkpoint = ""
var input_file: FileAccess
var pressed_keys: Dictionary = {}
var pad_axes: Dictionary = {}
var pad_buttons: Dictionary = {}
var active_touches: Dictionary = {}
var screenshots: Array = []
var observations: Array = []
var battle_observed: Dictionary = {}
var started_ms = 0
var config: Dictionary = {}
var pending_product_exit = ""
var product_exit_observed = false
var saved_sha256 = ""
var pickup_proofs: Array = []
var restore_sources: Array = []
var startup_snapshot: Dictionary = {}
var startup_feedback = ""
var startup_files: Dictionary = {}
var automatic_restore_verified = false
var input_count = 0
var visual_evidence: Dictionary = {}
var display_samples: Array = []
var focus_events: Array = []
var window_size_events: Array = []
var combat_input_samples: Array = []
var last_combat_input_summary: Dictionary = {}
var sheet_origin = ""
var verification_kind = "rendered_runtime"
const SHEET_ENTRANCES = {"shopping":"world_stall","craft":"world_craft","shelf":"world_menu","gear":"world_gear","journal":"world_journal","storage":"world_storage","counter":"world_counter","order":"world_counter"}

func _initialize():
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i]=="--config": config=JSON.parse_string(FileAccess.get_file_as_string(args[i+1]))
	folder=str(config.get("output","/tmp/p03-runtime-unconfigured"))
	mode=str(config.get("mode","mouse"))
	stage=str(config.get("stage","start"))
	attempt=str(config.get("attempt",stage))
	for path in ["game/ui/main.gd","game/ui/shop_canvas.gd","game/ui/checks/restaurant.gd","game/expedition/expedition_panel.gd","game/core/game_session.gd","tests/runtime/critical_path.gd","tests/runtime/navigation_headless.gd"]:
		if FileAccess.file_exists("res://"+path): source_hashes[path]=FileAccess.get_sha256("res://"+path)
	DirAccess.make_dir_recursive_absolute(folder)
	input_file=FileAccess.open(folder+"/"+attempt+"-inputs.jsonl",FileAccess.WRITE)
	started_ms=Time.get_ticks_msec()
	root.focus_entered.connect(record_focus.bind(true))
	root.focus_exited.connect(record_focus.bind(false))
	root.size_changed.connect(record_window_size)
	record_window_size()
	call_deferred("run")

func expect(value: bool, message: String):
	checks+=1
	observations.append({"check":message,"passed":value})
	if not value:
		failures.append(message)
		push_error(message)
		write_report()
		quit(1)

func emit_input(event: InputEvent, local: bool = false):
	input_count+=1
	var entry={"elapsed_ms":Time.get_ticks_msec()-started_ms,"sequence":input_count,"window_focused":root.has_focus(),"event":event.as_text(),"class":event.get_class(),"local":local,"pressed":event.is_pressed()}
	entry.device=event.device
	if event is InputEventJoypadButton: entry.button_index=event.button_index
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag: entry.position=[event.position.x,event.position.y]
	if event is InputEventJoypadMotion: entry.axis=event.axis; entry.axis_value=event.axis_value
	if event is InputEventScreenTouch or event is InputEventScreenDrag: entry.touch_index=event.index
	input_file.store_line(JSON.stringify(entry))
	if local: root.push_input(event,true)
	else: Input.parse_input_event(event)

func emit_gui_pointer(event: InputEvent):
	# Controls expose logical viewport coordinates. Input.parse_input_event
	# receives window coordinates; preserve its normal touch/mouse emulation.
	var mapped=event.xformed_by(root.get_final_transform())
	trace.append({"pointer_mapping":{"viewport":str(event.position),"window":str(mapped.position),"transform":str(root.get_final_transform())}})
	emit_input(mapped)

func fresh(size: Vector2i, restore_existing: bool = false):
	# Godot desktop ScrollContainer enables the touchscreen drag path only
	# with this runtime emulation flag; no project setting is saved.
	Input.emulate_touch_from_mouse=(mode=="touch")
	if verification_kind=="headless_navigation":
		expect(DisplayServer.get_name()=="headless" and not config.get("fullscreen",false),"headless navigation makes no native window claim")
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size=Vector2i.ZERO
		root.size=size
	elif config.get("fullscreen",false):
		# The CLI requests actual fullscreen. Never replace its screen-sized
		# viewport with the old 1280/960 test dimensions or enlarge a PNG.
		var deadline=Time.get_ticks_msec()+10000
		var stable_since=Time.get_ticks_msec()
		var last_rect=Rect2i()
		while Time.get_ticks_msec()<deadline:
			var current_rect=Rect2i(DisplayServer.window_get_position(),DisplayServer.window_get_size())
			var correct=root.mode==Window.MODE_FULLSCREEN and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN and fullscreen_coverage()!=""
			if current_rect!=last_rect or not correct: stable_since=Time.get_ticks_msec()
			last_rect=current_rect
			if correct and Time.get_ticks_msec()-stable_since>=500: break
			await process_frame
		expect(root.mode==Window.MODE_FULLSCREEN and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN,"CLI enters actual fullscreen mode")
		expect(fullscreen_coverage()!="","fullscreen window reaches the API-reported screen area before scene startup")
		expect(Time.get_ticks_msec()-stable_since>=500,"native fullscreen rectangle is stable for at least 500 ms")
	else:
		expect(root.mode==Window.MODE_WINDOWED and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_WINDOWED,"CLI enters explicit windowed mode")
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size=Vector2i.ZERO
		root.size=size
		DisplayServer.window_set_size(size)
	if not failures.is_empty(): return
	ui=Main.instantiate()
	# Configuration only: no seed/economy/phase/state replacement.
	ui.save_path=folder+"/restaurant-save.json"
	startup_files=save_file_hashes()
	root.add_child(ui)
	# _ready() performs the product's automatic load. Observe it before any
	# test input or rendered frame, then compare again after normal processing.
	startup_snapshot=ui.game.snapshot()
	startup_feedback=ui.feedback.text
	ui.tree_exiting.connect(_observe_product_exit)
	ui.action_completed.connect(func(kind,args,result):
		last_result=result
		action_count+=1
		economic_intents.append({"elapsed_ms":Time.get_ticks_msec()-started_ms,"input_sequence":input_count,"kind":kind,"args":args.duplicate(true),"ok":result.get("ok",false)})
	)
	expect(ui.has_method("get_open_sheet") and ui.has_method("get_world_view"),"published world/sheet read-only API is present")
	# Match the parent helper's route/restart intent, but never move or reset a
	# save here: every P03 route uses a distinct supervisor-owned directory.
	var has_existing=startup_files.primary!="missing" or startup_files.backup!="missing"
	expect(has_existing==restore_existing,"startup files match the new-route or real-restart stage")
	if not failures.is_empty(): return
	await frames(6)
	await screenshot(mode+"-initial-viewport")
	expect(ui.game.view().has("progression"),"restaurant core v2 exposes progression")
	if config.get("fullscreen",false):
		expect(ui.size==root.get_visible_rect().size,"main scene fills actual fullscreen viewport")
	else:
		expect(ui.size==Vector2(size),"viewport uses requested dimensions")

func activate_visible(id: String):
	var control=ui.get_action_control(id)
	expect(is_instance_valid(control) and control.is_visible_in_tree(),"actual visible control exists: "+id)
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return
	await activate_control(control,id)

func close_sheet():
	if ui.get_open_sheet()=="": return
	var count_before=action_count
	if ui.get_open_sheet()=="pause":
		await activate_visible("resume")
		expect(not ui.game.view().paused and ui.get_open_sheet()=="","resume closes real pause sheet")
		return
	var origin=sheet_origin
	if mode=="pad":
		trace.append({"actual_navigation":"ui_cancel","device":"pad_B","from_sheet":ui.get_open_sheet()})
		await pad_button(JOY_BUTTON_B)
	elif mode=="mouse":
		trace.append({"actual_navigation":"ui_cancel","device":"keyboard_Escape","from_sheet":ui.get_open_sheet()})
		await key(KEY_ESCAPE,true); await key(KEY_ESCAPE,false)
	else: await activate_visible("sheet_close")
	await frames(3)
	expect(action_count==count_before,"closing a sheet emits no economic intent")
	expect(ui.get_open_sheet()=="","real close input returns to world")
	if origin!="": expect(root.gui_get_focus_owner()==ui.get_action_control(origin),"closing sheet restores actual object focus: "+origin)
	sheet_origin=""

func open_sheet(kind: String):
	if ui.get_open_sheet()==kind: return
	await close_sheet()
	if not failures.is_empty(): return
	if kind=="pause":
		await activate_visible("pause")
		expect(ui.game.view().paused and ui.get_open_sheet()=="pause","visible pause control opens pause sheet")
		return
	expect(SHEET_ENTRANCES.has(kind),"published world entrance exists for sheet: "+kind)
	if not SHEET_ENTRANCES.has(kind): return
	var world="lane" if kind=="shopping" else "room"
	if ui.get_world_view()!=world:
		await activate_visible("world_lane" if world=="lane" else "world_home")
		expect(ui.get_world_view()==world and ui.get_open_sheet()=="","real doorway reaches "+world)
	if not failures.is_empty(): return
	var entrance: String=SHEET_ENTRANCES[kind]
	await activate_visible(entrance)
	var expected="order" if kind=="counter" and not ui.game.view().pending.is_empty() else kind
	expect(ui.get_open_sheet()==expected,"world object opens expected visible sheet: "+entrance+" -> "+expected)
	sheet_origin=entrance

func activate(id: String):
	# Legacy semantic callers are routed through visible objects. These aliases
	# never reach get_action_control(), and the trace contains actual world IDs.
	if id.begins_with("tab_"):
		await open_sheet(id.trim_prefix("tab_")); return
	if id=="to_shelf": await open_sheet("shelf"); return
	if id=="pause":
		if ui.game.view().paused: await activate("resume")
		else: await open_sheet("pause")
		return
	if id in ["save","load","quit","resume"]:
		await open_sheet("pause")
	elif id=="primary":
		var target={"shopping":"shopping","preparation":"counter","closing":"journal","settled":"journal"}.get(ui.game.view().phase,"")
		expect(target!="","current phase has an economic primary action")
		if target=="": return
		await open_sheet(target)
	elif id.begins_with("buy_"): await open_sheet("shopping")
	elif id.begins_with("craft_"):
		await open_sheet("craft")
		await activate_visible("recipe_"+id.trim_prefix("craft_"))
	elif id.begins_with("fulfill_") or id=="special_decline": await open_sheet("order")
	elif id.begins_with("upgrade_"): await open_sheet("journal")
	elif id.begins_with("equip_") or id in ["install_cauldron","sell_cauldron","consume_pie","start_expedition"]: await open_sheet("gear")
	if not failures.is_empty(): return
	await activate_visible(id)
	if id=="resume": expect(not ui.game.view().paused and ui.get_open_sheet()=="","resume returns to unpaused world")

func pad_button(index: int):
	for down in [true,false]:
		var e=InputEventJoypadButton.new()
		e.button_index=index; e.pressed=down
		emit_input(e)
		await frames(1)

func key(index: int, down: bool):
	var e=InputEventKey.new()
	e.keycode=index; e.physical_keycode=index; e.pressed=down
	emit_input(e)
	await frames(1)

func scroll_gesture_origin(clip: Rect2) -> Vector2:
	# Begin on visible text/gap, not a child that consumes the pointer gesture.
	var children=ui.scroll.find_children("*","Control",true,false)
	for y in range(int(clip.position.y)+4,int(clip.end.y)-4,4):
		var point=Vector2(clip.get_center().x,y)
		var blocked=false
		for control in children:
			if control.mouse_filter==Control.MOUSE_FILTER_STOP and control.is_visible_in_tree() and control.get_global_rect().has_point(point): blocked=true; break
		if not blocked: return point
	return clip.get_center()

func scroll_to(button: Button):
	if not ui.scroll.is_ancestor_of(button): return
	for _i in range(50):
		var clip=ui.scroll.get_global_rect()
		var rect=button.get_global_rect()
		if clip.encloses(rect): return
		if _i in [0,1,49]: trace.append({"scroll_target":str(button.get_meta("action_id",button.name)),"iteration":_i,"clip":str(clip),"target_rect":str(rect),"scroll_vertical":ui.scroll.scroll_vertical})
		var direction=1 if rect.get_center().y>clip.get_center().y else -1
		if mode=="touch":
			var at=scroll_gesture_origin(clip)
			var touch=InputEventScreenTouch.new()
			touch.index=0; touch.position=at; touch.pressed=true; emit_gui_pointer(touch)
			for j in range(1,7):
				var drag=InputEventScreenDrag.new()
				drag.index=0; drag.position=at-Vector2(0,direction*j*20); drag.relative=Vector2(0,-direction*20)
				emit_gui_pointer(drag); await frames(1)
			# Hold before lifting to end the gesture without a kinetic fling.
			# Otherwise the button can move between its measured rect and tap.
			await create_timer(0.25,true,false,true).timeout
			touch=InputEventScreenTouch.new()
			touch.index=0; touch.position=at-Vector2(0,direction*120); touch.pressed=false; emit_gui_pointer(touch)
		else:
			var motion=InputEventMouseMotion.new(); motion.position=clip.get_center(); motion.global_position=motion.position; emit_gui_pointer(motion)
			var wheel=InputEventMouseButton.new()
			wheel.position=clip.get_center(); wheel.global_position=wheel.position
			wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN if direction>0 else MOUSE_BUTTON_WHEEL_UP
			wheel.pressed=true; emit_gui_pointer(wheel)
			var release=InputEventMouseButton.new()
			release.position=wheel.position; release.global_position=wheel.global_position
			release.button_index=wheel.button_index; release.pressed=false; emit_gui_pointer(release)
		await frames(2)
	await screenshot(mode+"-scroll-failure-"+str(button.get_meta("action_id",button.name)))
	expect(false,"real scrolling reaches "+str(button.get_meta("action_id",button.name)))

func activate_control(button: Button, id: String):
	expect(is_instance_valid(button) and button.is_visible_in_tree(),"visible control: "+id)
	if not is_instance_valid(button): return
	expect(not button.disabled,"enabled control: "+id)
	if button.disabled: return
	var count_before=action_count

	if mode=="pad":
		for _i in range(160):
			if root.gui_get_focus_owner()==button: break
			await pad_button(JOY_BUTTON_DPAD_DOWN)
		expect(root.gui_get_focus_owner()==button,"actual D-pad focus reaches "+id)
		if root.gui_get_focus_owner()!=button: return
		await pad_button(JOY_BUTTON_A)
	else:
		await scroll_to(button)
		await frames(2)
		var rect=button.get_global_rect()
		expect(root.get_visible_rect().encloses(rect),"target on logical viewport: "+id)
		if mode=="mouse":
			var motion=InputEventMouseMotion.new()
			motion.position=rect.get_center(); motion.global_position=motion.position
			emit_gui_pointer(motion); await frames(1)
		for down in [true,false]:
			trace.append({"control_input":id,"pressed":down,"at":str(rect.get_center()),"current_rect":str(button.get_global_rect()),"scroll_vertical":ui.scroll.scroll_vertical})
			if mode=="touch":
				var event=InputEventScreenTouch.new()
				event.index=0; event.position=rect.get_center(); event.pressed=down
				emit_gui_pointer(event)
			else:
				var event=InputEventMouseButton.new()
				event.position=rect.get_center(); event.global_position=event.position
				event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down
				event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
				emit_gui_pointer(event)
			await frames(1)
	await frames(3)
	var economic=id=="primary" or id.begins_with("buy_") or id.begins_with("craft_") or id.begins_with("display_") or id.begins_with("fulfill_") or id.begins_with("upgrade_") or id.begins_with("equip_") or id in ["install_cauldron","sell_cauldron","consume_pie","start_expedition"]
	if economic and action_count==count_before: await screenshot(mode+"-intent-failure-"+id)
	if economic: expect(action_count==count_before+1,"one real control input emits exactly one economic intent: "+id)
	if id.begins_with("world_") or id.begins_with("recipe_") or id=="sheet_close": expect(action_count==count_before,"presentation control emits no economic intent: "+id)
	if action_count>count_before: expect(last_result.get("ok",false),"command result: "+id+" "+str(last_result.get("message","")))
	var v: Dictionary=ui.game.view()
	if id.begins_with("craft_"):
		var output=id.trim_prefix("craft_")
		expect(ui.illustration.effects.any(func(effect): return effect.item_id==output and effect.source=="craft"),"actual cooking triggers matching visual effect: "+output)
		await screenshot(mode+"-actual-craft-"+output)
	trace.append({"mode":mode,"action":id,"sheet":ui.get_open_sheet(),"world":ui.get_world_view(),"day":v.day,"phase":v.phase,"cash":v.cash,"cursor":v.cursor,"clock_ms":v.clock_ms})
	print("P03 INPUT ",mode," ",id," => ",v.day,"/",v.phase)

func quantity(value: int):
	await super.quantity(value)
	expect(ui.batch==value,"real quantity controls select requested batch: "+str(value))

func screenshot(name: String):
	expect(DisplayServer.get_name()!="headless","runtime screenshot requires rendered display")
	if DisplayServer.get_name()=="headless": return
	# An unfocused native window may stop drawing while process frames continue.
	# Keep this boundary finite and report the real state instead of hanging until
	# the OS-process supervisor kills the only in-memory diagnostic evidence.
	var drawn={"ready":false}
	var on_draw=func(): drawn.ready=true
	RenderingServer.frame_post_draw.connect(on_draw,CONNECT_ONE_SHOT)
	var deadline=Time.get_ticks_msec()+5000
	while not drawn.ready and Time.get_ticks_msec()<deadline: await process_frame
	if not drawn.ready:
		if RenderingServer.frame_post_draw.is_connected(on_draw): RenderingServer.frame_post_draw.disconnect(on_draw)
		trace.append({"render_wait_timeout":name,"input_state":observe_input_state()})
		expect(false,"viewport did not draw within 5 seconds: "+name)
		return
	var path=folder+"/"+attempt+"-"+name+".png"
	var texture=root.get_texture()
	var picture=texture.get_image()
	var screen=DisplayServer.window_get_current_screen()
	var screen_size=DisplayServer.screen_get_size(screen)
	var screen_position=DisplayServer.screen_get_position(screen)
	var usable=DisplayServer.screen_get_usable_rect(screen)
	var window_position=DisplayServer.window_get_position()
	var window_size=DisplayServer.window_get_size()
	var viewport_size=root.get_visible_rect().size
	var stretch=root.get_stretch_transform()
	var mapped_size=(stretch*root.get_visible_rect()).size
	var sample={"path":path,"elapsed_ms":Time.get_ticks_msec()-started_ms,"requested_mode":"fullscreen" if config.get("fullscreen",false) else "windowed","window_mode":DisplayServer.window_get_mode(),"root_mode":root.mode,"screen":screen,"screen_scale":DisplayServer.screen_get_scale(screen),"screen_size":[screen_size.x,screen_size.y],"window_size":[window_size.x,window_size.y],"root_size":[root.size.x,root.size.y],"viewport_size":[int(viewport_size.x),int(viewport_size.y)],"texture_size":[texture.get_width(),texture.get_height()],"png_size":[picture.get_width(),picture.get_height()],"window_focused":root.has_focus()}
	sample.content_scale_mode=root.content_scale_mode
	sample.content_scale_size=[root.content_scale_size.x,root.content_scale_size.y]
	sample.content_scale_aspect=root.content_scale_aspect
	sample.content_scale_factor=root.content_scale_factor
	sample.stretch_transform=[stretch.x.x,stretch.x.y,stretch.y.x,stretch.y.y,stretch.origin.x,stretch.origin.y]
	sample.mapped_viewport_size=[mapped_size.x,mapped_size.y]
	sample.screen_position=[screen_position.x,screen_position.y]
	sample.screen_usable_rect=[usable.position.x,usable.position.y,usable.size.x,usable.size.y]
	sample.window_position=[window_position.x,window_position.y]
	sample.fullscreen_coverage=fullscreen_coverage()
	display_samples.append(sample)
	expect(picture.save_png(path)==OK,"engine viewport PNG: "+name)
	screenshots.append(path)
	var required_mode=DisplayServer.WINDOW_MODE_FULLSCREEN if config.get("fullscreen",false) else DisplayServer.WINDOW_MODE_WINDOWED
	expect(sample.window_mode==required_mode and int(root.mode)==int(required_mode),"screenshot uses requested native window mode")
	expect(sample.root_size==sample.window_size,"root reports actual native window dimensions")
	expect(sample.png_size==[roundi(mapped_size.x),roundi(mapped_size.y)],"raw viewport image dimensions follow the observed stretch transform")
	if config.get("fullscreen",false): expect(sample.fullscreen_coverage!="","fullscreen viewport covers screen or exact macOS system usable area")
	else: expect(sample.png_size==sample.viewport_size,"windowed layout PNG matches requested logical viewport")
	visual_evidence=inspect_visible_assets()
	visual_evidence.viewport_png=path
	visual_evidence.observed_after_render=true
	visual_evidence.elapsed_ms=Time.get_ticks_msec()-started_ms
	expect(visual_evidence.active_assets_loaded,"visible "+visual_evidence.active_scene+" pixel assets loaded after actual draw")

func fullscreen_coverage() -> String:
	var screen=DisplayServer.window_get_current_screen()
	var window_rect=Rect2i(DisplayServer.window_get_position(),DisplayServer.window_get_size())
	var screen_rect=Rect2i(DisplayServer.screen_get_position(screen),DisplayServer.screen_get_size(screen))
	if window_rect==screen_rect: return "screen"
	# macOS native fullscreen can exclude the system's top safe region.
	# Require an exact API-reported rectangle, never a guessed tolerance.
	var usable=DisplayServer.screen_get_usable_rect(screen)
	if DisplayServer.get_name()=="macOS" and screen_rect.encloses(usable) and window_rect==usable: return "macos_usable_rect"
	return ""

func record_window_size():
	var window_size=DisplayServer.window_get_size()
	window_size_events.append({"elapsed_ms":Time.get_ticks_msec()-started_ms,"mode":DisplayServer.window_get_mode(),"window_size":[window_size.x,window_size.y],"root_size":[root.size.x,root.size.y]})

func observe_input_state() -> Dictionary:
	# Diagnostic reads only. In particular, focus changes never clear/replay
	# the driver's caches or submit a replacement command to the game core.
	var sample={"elapsed_ms":Time.get_ticks_msec()-started_ms,"focused":root.has_focus(),"input_sequence":input_count,"action_event_count":action_events.size(),"driver_cache":{"pressed_keys":pressed_keys.duplicate(true),"pad_axes":pad_axes.duplicate(true),"pad_buttons":pad_buttons.duplicate(true),"active_touches":active_touches.duplicate(true)}}
	if is_instance_valid(ui):
		var view: Dictionary=ui.game.view()
		sample.phase=view.phase
		sample.paused=view.paused
		if view.phase=="expedition":
			sample.authoritative_input=view.expedition.get("input",{}).duplicate(true)
			if is_instance_valid(ui.battle_panel) and ui.battle_panel.has_method("current_input"):
				sample.product_device_input=ui.battle_panel.current_input().duplicate(true)
				sample.input_mode=ui.battle_panel.get("input_mode")
	return sample

func record_focus(focused: bool):
	var sample=observe_input_state()
	sample.signal_focused=focused
	sample.observed_at="window_focus_signal"
	focus_events.append(sample)
	persist_focus_events()
	# Application/window notification order is not assumed. A second read on
	# the next frame records whether the product actually released held input.
	await process_frame
	sample=observe_input_state()
	sample.signal_focused=focused
	sample.observed_at="frame_after_window_focus_signal"
	focus_events.append(sample)
	persist_focus_events()

func persist_focus_events():
	# Preserve focus evidence even when no further draw/report checkpoint arrives.
	if input_file!=null: input_file.flush()
	var file=FileAccess.open(folder+"/"+attempt+"-focus.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(focus_events,"  ")); file.close()

func observe_combat_input(requested: Dictionary):
	var sample=observe_input_state()
	if sample.get("phase")!="expedition": return
	var summary={"focused":sample.focused,"paused":sample.paused,"requested":{},"device":{},"authoritative":{}}
	for action in ["cast","dodge","skill"]:
		summary.requested[action]=requested.get(action,false)
		summary.device[action]=sample.get("product_device_input",{}).get(action)
		summary.authoritative[action]=sample.get("authoritative_input",{}).get(action)
	if summary==last_combat_input_summary: return
	last_combat_input_summary=summary.duplicate(true)
	sample.requested_input=requested.duplicate(true)
	combat_input_samples.append(sample)

func active_scene_name() -> String:
	if not is_instance_valid(ui): return ""
	return "expedition" if ui.game.view().phase=="expedition" else "restaurant"

func inspect_visible_assets() -> Dictionary:
	var scene=active_scene_name()
	var evidence={"active_scene":scene,"visible":false,"active_assets_loaded":false}
	if scene=="expedition" and is_instance_valid(ui.battle_panel):
		var panel=ui.battle_panel
		evidence.visible=panel.is_visible_in_tree() and ui.battle_host.is_visible_in_tree()
		var rendered_textures: Dictionary={}
		var character_loaded=false
		# Read the renderer's populated cache only; never load a texture here.
		for id in panel.textures:
			if id!="mushroom-garden" and not str(id).begins_with("meemee_"): continue
			var texture=panel.textures[id]
			if texture is Texture2D and texture.get_width()>0 and texture.get_height()>0:
				rendered_textures[id]=[texture.get_width(),texture.get_height()]
				if str(id).begins_with("meemee_"): character_loaded=true
		evidence.rendered_textures=rendered_textures
		evidence.active_assets_loaded=evidence.visible and rendered_textures.has("mushroom-garden") and character_loaded
	elif scene=="restaurant":
		evidence.visible=ui.illustration.is_visible_in_tree()
		evidence.room_loaded=not ui.illustration.missing.visible
		evidence.active_assets_loaded=evidence.visible and evidence.room_loaded
	return evidence

func json_equal(a: Variant,b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a,"",true,true))==JSON.parse_string(JSON.stringify(b,"",true,true))

func save_file_hashes() -> Dictionary:
	var hashes: Dictionary={}
	for suffix in ["",".bak"]:
		var path=ui.save_path+suffix
		hashes["primary" if suffix.is_empty() else "backup"]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return hashes

func compare_restored_snapshot(actual: Dictionary, expected: Dictionary, label: String):
	var differences: Array=[]
	for field in expected:
		if not json_equal(expected[field],actual.get(field)): differences.append(field)
	for field in actual:
		if not expected.has(field): differences.append(field)
	expect(json_equal(actual,expected),label+"; differing fields="+str(differences))

func record_checkpoint(name: String):
	checkpoint=name
	var file=FileAccess.open(folder+"/"+name+"-expected.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(ui.game.snapshot(),"  ",true,true)); file.close()
	var context=FileAccess.open(folder+"/"+name+"-context.json",FileAccess.WRITE)
	context.store_string(JSON.stringify({"producer_attempt":attempt,"producer_process_id":OS.get_process_id(),"battle_observed":battle_observed},"  ",true,true)); context.close()
	write_report()

func _observe_product_exit():
	if pending_product_exit.is_empty(): return
	product_exit_observed=true
	var disk=JSON.parse_string(FileAccess.get_file_as_string(ui.save_path))
	saved_sha256=FileAccess.get_sha256(ui.save_path)
	var actual: Dictionary=ui.game.snapshot()
	var differences: Array=[]
	for field in actual:
		if not json_equal(actual[field],disk.get(field)): differences.append(field)
	expect(json_equal(actual,disk),"product exit writes the complete final snapshot; differing fields="+str(differences))
	record_checkpoint(pending_product_exit)

func expect_product_exit(name: String, control: Button):
	pending_product_exit=name
	write_report() # Intent alone is never a completed checkpoint.
	await activate_control(control,"product_save_quit")
	expect(false,"product save-and-quit input must terminate this process")

func save_and_exit(name: String):
	await activate("save")
	expect("保存成功" in ui.feedback.text,"save reports success before process exit")
	await screenshot(mode+"-"+name)
	await expect_product_exit(name,ui.get_action_control("quit"))

func restore(name: String, check_explicit_button: bool = false):
	var expected=JSON.parse_string(FileAccess.get_file_as_string(folder+"/"+name+"-expected.json"))
	var context=JSON.parse_string(FileAccess.get_file_as_string(folder+"/"+name+"-context.json"))
	expect(context.producer_process_id!=OS.get_process_id(),"restore runs in a different process from its checkpoint producer")
	restore_sources.append({"checkpoint":name,"producer_attempt":context.producer_attempt,"producer_process_id":context.producer_process_id,"method":"automatic_startup","startup_files":startup_files})
	# Carry only test observations across process segments, never gameplay state.
	battle_observed=context.battle_observed
	expect(input_count==0,"automatic restore is observed before any injected input")
	expect("恢复成功" in startup_feedback,"automatic startup restore reports success")
	var startup_file=FileAccess.open(folder+"/"+attempt+"-startup-actual.json",FileAccess.WRITE)
	startup_file.store_string(JSON.stringify(startup_snapshot,"  ",true,true)); startup_file.close()
	compare_restored_snapshot(startup_snapshot,expected,"exact automatic startup snapshot: "+name)
	var actual: Dictionary=ui.game.snapshot()
	var restored_file=FileAccess.open(folder+"/"+attempt+"-restored-actual.json",FileAccess.WRITE)
	restored_file.store_string(JSON.stringify(actual,"  ",true,true)); restored_file.close()
	compare_restored_snapshot(actual,expected,"automatic restore remains exact after rendered frames: "+name)
	expect(save_file_hashes()==startup_files,"automatic restore leaves primary and backup bytes unchanged")
	if ui.game.view().phase=="expedition":
		expect(json_equal(ui.game.snapshot().expedition.input,{"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false}),"restored combat has no held input")
	if not failures.is_empty(): return
	automatic_restore_verified=true
	# Explicit restore remains a separate regression on the visible restaurant
	# button. Combat startup must not depend on that hidden control.
	if check_explicit_button:
		await activate("load")
		expect("恢复成功" in ui.feedback.text,"explicit restore button still reports success")
		compare_restored_snapshot(ui.game.snapshot(),expected,"explicit restore preserves the automatically restored snapshot: "+name)
	await screenshot(mode+"-restored-"+name)

func trade(day: int, hot: bool, resume: bool = false):
	if resume and ui.game.view().paused: await activate("resume")
	if not resume:
		await activate("primary")
		expect(ui.game.view().phase=="trading","restaurant opened")
		await activate("pause")
		var paused_snapshot: Dictionary=ui.game.snapshot()
		await create_timer(1.15,true,false,true).timeout
		expect(ui.game.snapshot()==paused_snapshot,"real 1.15 second pause freezes full restaurant state")
		await activate("pause")
	var until=Time.get_ticks_msec()+45000
	while ui.game.view().phase=="trading" and Time.get_ticks_msec()<until:
		var v: Dictionary=ui.game.view()
		if not v.pending.is_empty():
			var frozen: Dictionary=ui.game.snapshot()
			await create_timer(1.05,true,false,true).timeout
			expect(frozen==ui.game.snapshot(),"pending order freezes full state during real wait")
			if day==2 and stage=="start":
				expect(v.pending.character_id=="hagrid","Hagrid is pending before restart")
				await save_and_exit("hagrid-pending")
				return
			await open_sheet("order")
			await screenshot(mode+"-order-day"+str(day))
			var preferred="floating_pie" if day==1 else ("moon_stew" if hot else "ember_soup")
			var picked=""
			for option in v.pending.options:
				if option.available and option.item_id==preferred: picked=preferred
			if picked.is_empty():
				for option in v.pending.options:
					if option.available: picked=str(option.item_id); break
			expect(not picked.is_empty(),"a legitimately stocked dish matches the request")
			if picked.is_empty(): return
			await activate("fulfill_"+picked)
			if day==2: expect(ui.game.view().quests.hagrid_patrol=="completed","Hagrid actual delivery completes quest")
		else: await create_timer(0.1,true,false,true).timeout
	expect(ui.game.view().phase=="closing","customer queue completes")
	await activate("primary")
	expect(ui.game.view().phase=="settled","daily settlement committed")
	await open_sheet("pause")
	var settled: Dictionary=ui.game.snapshot()
	# Repeated confirmation is directed to the disabled page's settlement? The
	# primary now means next-day, so do not mislabel a different action as retry.
	await activate("save")
	await activate("load")
	expect(json_equal(settled,ui.game.snapshot()),"settled restore adds no second fee/reward")
	await activate("resume")

func inject_combat(input: Dictionary):
	var panel=ui.battle_panel
	if mode=="mouse":
		var next={KEY_W:input.move_y < -0.3,KEY_S:input.move_y > 0.3,KEY_A:input.move_x < -0.3,KEY_D:input.move_x > 0.3,KEY_J:input.cast,KEY_K:input.dodge,KEY_L:input.skill}
		for code in next:
			if next[code]!=pressed_keys.get(code,false):
				var e=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=next[code]; emit_input(e)
		pressed_keys=next
		var p: Dictionary=ui.game.view().expedition.player
		var local_point=(Vector2(p.x,p.y)+Vector2(input.aim_x,input.aim_y)*100.0)/Vector2(960,540)*panel.field.size+panel.field.position
		var point=panel.get_global_transform_with_canvas()*local_point
		var motion=InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; emit_input(motion,true)
	elif mode=="pad":
		for pair in [[JOY_AXIS_LEFT_X,input.move_x],[JOY_AXIS_LEFT_Y,input.move_y],[JOY_AXIS_RIGHT_X,input.aim_x],[JOY_AXIS_RIGHT_Y,input.aim_y]]:
			if not is_equal_approx(pad_axes.get(pair[0],0.0),pair[1]):
				var e=InputEventJoypadMotion.new(); e.axis=pair[0]; e.axis_value=pair[1]; emit_input(e)
			pad_axes[pair[0]]=pair[1]
		for pair in [[JOY_BUTTON_A,input.cast],[JOY_BUTTON_B,input.dodge],[JOY_BUTTON_X,input.skill]]:
			if pad_buttons.get(pair[0],false)!=pair[1]:
				var e=InputEventJoypadButton.new(); e.button_index=pair[0]; e.pressed=pair[1]; emit_input(e)
			pad_buttons[pair[0]]=pair[1]
	else:
		var centers: Dictionary=panel._centers() # Read geometry only.
		var values={"move":Vector2(input.move_x,input.move_y),"aim":Vector2(input.aim_x,input.aim_y),"cast":input.cast,"dodge":input.dodge,"skill":input.skill}
		var index=0
		for kind in values:
			var center=panel.get_global_transform_with_canvas()*centers[kind]
			var on: bool=values[kind].length_squared()>0.00001 if values[kind] is Vector2 else values[kind]
			if on and not active_touches.get(index,false):
				var e=InputEventScreenTouch.new(); e.index=index; e.position=center; e.pressed=true; emit_input(e,true)
			if on and values[kind] is Vector2:
				var e=InputEventScreenDrag.new(); e.index=index; e.position=panel.get_global_transform_with_canvas()*(centers[kind]+values[kind]*panel.touch_radius(kind)); emit_input(e,true)
			if not on and active_touches.get(index,false):
				var e=InputEventScreenTouch.new(); e.index=index; e.position=center; e.pressed=false; emit_input(e,true)
			active_touches[index]=on
			index+=1

func release_combat():
	inject_combat({"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false})
	await frames(2)

func pause_combat():
	if mode=="pad": await pad_button(JOY_BUTTON_START)
	else: await activate_control(ui.battle_panel.pause_button,"battle_pause")
	await frames(3)

func battle(day: int, resume: bool = false):
	if not resume:
		await activate("start_expedition")
		expect(ui.game.view().phase=="expedition","real expedition mounted")
		expect(ui.battle_panel.has_method("touch_radius"),"published E01 adaptive touch radius API is present")
	else:
		await pause_combat()
		expect(not ui.game.view().paused,"resume paused battle through real input")
	var until=Time.get_ticks_msec()+180000
	ui.battle_panel.action_events.connect(func(events): action_events.append_array(events))
	var observations_before: Dictionary=ui.game.view().expedition
	var initial_position=Vector2(observations_before.player.x,observations_before.player.y)
	var seen=battle_observed.get(str(day),{"movement":false,"cast":false,"dodge":false,"skill":false,"hit":false,"telegraph":false,"drop":false}).duplicate(true)
	var iteration=0
	while ui.game.view().phase=="expedition" and Time.get_ticks_msec()<until:
		var s: Dictionary=ui.game.view().expedition
		seen.movement=seen.movement or Vector2(s.player.x,s.player.y).distance_to(initial_position)>10
		for action in ["cast","dodge","skill"]: seen[action]=seen[action] or s.player[action+"_cooldown_ms"]>0
		for enemy in s.enemies:
			seen.telegraph=seen.telegraph or not enemy.telegraph.is_empty()
			for initial_enemy in observations_before.enemies:
				if enemy.id==initial_enemy.id and enemy.hp<initial_enemy.hp: seen.hit=true
		seen.drop=seen.drop or not s.drops.is_empty()
		# Separate real-process checkpoints retain a telegraph, an uncollected
		# drop, and an already-collected drop before the remaining fight.
		var save_boundary=""
		if day==3:
			if stage=="after-hagrid" and seen.telegraph: save_boundary="combat-paused"
			elif stage=="after-combat" and s.drops.any(func(drop): return not drop.collected): save_boundary="combat-drop"
			elif stage=="after-drop" and s.drops.any(func(drop): return drop.collected): save_boundary="combat-collected"
		if not save_boundary.is_empty():
			battle_observed[str(day)]=seen
			await release_combat()
			await pause_combat()
			expect(ui.game.view().paused,"active combat paused for restart")
			var frozen: Dictionary=ui.game.snapshot()
			await create_timer(1.1,true,false,true).timeout
			expect(frozen==ui.game.snapshot(),"real wait freezes enemies/cooldowns/drop state")
			await activate_control(ui.battle_panel.save_button,"battle_save")
			expect("保存成功" in ui.feedback.text,"combat save reaches actual store")
			await screenshot(mode+"-combat-checkpoint")
			# E01 published this control/signal in 9fec5d4. P02 must bind the
			# signal to its existing save-success-only exit; input proves routing.
			expect(ui.battle_panel.has_signal("save_quit_requested"),"published E01 save-and-quit signal exists")
			var quit_control=ui.battle_panel.get("save_quit_button")
			expect(quit_control is Button,"published E01 save-and-quit control exists")
			if quit_control is Button: await expect_product_exit(save_boundary,quit_control)
			return
		var input=CombatDriver.next_input(s)
		# Exercise acquired actions once, then reuse E01's actual movement policy.
		if iteration>=3 and iteration<15: input.dodge=true
		if day>=2 and iteration>=16 and iteration<28: input.skill=true
		inject_combat(input)
		await process_frame
		observe_combat_input(input)
		iteration+=1
		if iteration==30:
			expect(ui.battle_panel.input_mode=={"mouse":"keyboard","pad":"gamepad","touch":"touch"}[mode],"actual device input selects matching combat HUD")
			await screenshot(mode+"-combat-day"+str(day))
	var end: Dictionary=ui.game.view()
	expect(end.phase=="shopping","battle returns to restaurant")
	expect(end.expedition.return_reason=="completed","actual enemies defeated and drops collected")
	for action in ["movement","cast","dodge","hit","drop"]: expect(seen[action],"observed real battle "+action)
	if day>=2: expect(seen.skill,"new skill executed from input")
	if day==3: expect(inventory("moonheart").bag>0,"elite yields actual advanced ingredient")
	verify_pickups_once()
	battle_observed[str(day)]=seen
	pressed_keys.clear(); active_touches.clear()
	await frames(5)
	await activate("tab_shopping")

func verify_pickups_once():
	var saved: Dictionary=ui.game.snapshot()
	for drop in saved.expedition.drops:
		if not drop.collected: continue
		var identity: Dictionary=saved.collected_drops.get(drop.id,{})
		expect(not identity.is_empty(),"collected drop has persisted identity: "+drop.id)
		if identity.is_empty(): continue
		var items=saved.items.filter(func(item): return item.uid==identity.uid and item.item_id==drop.item_id)
		var ledger_count=0
		for row in saved.ledger:
			if row.kind=="pickup": ledger_count+=row.args.get("drop_ids",[]).count(drop.id)
		expect(items.size()==1,"drop has exactly one actual inventory UID: "+drop.id)
		expect(ledger_count==1,"drop appears exactly once in economic ledger: "+drop.id)
		pickup_proofs.append({"drop_id":drop.id,"uid":identity.uid,"matching_items":items.size(),"ledger_occurrences":ledger_count})

func prepare_day(day: int, hot: bool):
	var targets={"floating_pie":4,"moon_stew":4} if hot else {"floating_pie":4}
	if hot and day==2: targets={"floating_pie":4,"star_soup":2}
	if (not hot and day>=2) or day==3: targets.ember_soup=1
	if day==3:
		targets.erase("moon_stew") # Three menu kinds after actual shelf upgrade.
		targets.comet_pie=1
	await shop_and_prepare(targets,hot)

func shop_and_prepare(targets: Dictionary, hot: bool):
	await open_sheet("shopping")
	var needed={}
	for recipe in ui.game.view().recipes:
		if not targets.has(recipe.output): continue
		var missing=maxi(0,int(targets[recipe.output])-int(inventory(recipe.output).bag))
		for raw in recipe.inputs: needed[raw]=needed.get(raw,0)+missing*int(recipe.inputs[raw])
	for raw in needed:
		var missing=maxi(0,int(needed[raw])-int(inventory(raw).bag))
		if missing>0:
			await quantity(missing)
			await activate("buy_"+str(raw))
	await activate("primary")
	expect(ui.game.view().phase=="preparation" and ui.get_open_sheet()=="","procurement returns to real preparation world")
	if hot and inventory("stirring_cauldron").installed==0: await activate("install_cauldron")
	await open_sheet("craft")
	for output in targets:
		var missing=maxi(0,int(targets[output])-int(inventory(output).bag))
		if missing>0:
			await quantity(missing)
			await activate("craft_"+str(output))
			if ui.game.view().day==1 or output in ["ember_soup","star_soup","comet_pie"]: await screenshot(mode+"-"+str(output)+"-cooking")
	await open_sheet("shelf")
	for output in targets:
		var count=int(inventory(output).bag)
		if count<=0: continue
		await quantity(count)
		await activate("select_"+str(output))
		await activate("display_"+str(output))
		await activate("price_standard")
	await screenshot(mode+"-menu-day"+str(ui.game.view().day))

func end_day(day: int):
	if day==1:
		await activate("upgrade_field_kit")
		await activate("upgrade_supply_pass")
	if day==2: await activate("upgrade_shelf")
	if day<3: await activate("primary")

func gear(day: int):
	await activate("tab_gear")
	if day>=2:
		expect("fan_wand" in ui.game.view().progression.owned_weapons and "gust" in ui.game.view().progression.skills,"earned equipment and skill persist across day")
		if ui.game.view().progression.equipped_weapon!="fan_wand": await activate("equip_fan_wand")
	if day==3:
		var before=int(inventory("floating_pie").bag)
		await activate("consume_pie")
		expect(inventory("floating_pie").bag==before-1 and ui.game.view().next_expedition_shield,"food removes a real dish and grants next expedition shield")

func navigation_checks():
	expect(ui.get_open_sheet()=="" and ui.get_world_view()=="room","new game starts in the room without a sheet")
	var before: Dictionary=ui.game.snapshot()
	for kind in ["shopping","craft","shelf","counter","journal","gear","storage"]:
		await open_sheet(kind)
		if not failures.is_empty(): return
		expect(ui.get_action_control("pause").disabled,"open sheet owns focus instead of background pause: "+kind)
		await screenshot(mode+"-navigation-"+kind)
		await close_sheet()
		if not failures.is_empty(): return
		expect(json_equal(before,ui.game.snapshot()),"world navigation leaves complete economic state unchanged: "+kind)
	await activate_visible("world_stove")
	sheet_origin="world_stove"
	expect(ui.get_open_sheet()=="craft","actual stove opens the recipe book")
	await activate_visible("recipe_moon_stew")
	expect(is_instance_valid(ui.get_action_control("craft_moon_stew")) and ui.get_action_control("craft_moon_stew").is_visible_in_tree(),"recipe selection exposes its actual craft control")
	await quantity(3)
	await close_sheet()
	if not failures.is_empty(): return
	await open_sheet("pause")
	for id in ["resume","save","load","quit"]:
		var button=ui.get_action_control(id)
		expect(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"pause sheet exposes real "+id)
	var paused: Dictionary=ui.game.snapshot()
	await activate("save")
	expect("保存成功" in ui.feedback.text,"pause sheet saves through the actual product control")
	await activate("load")
	compare_restored_snapshot(ui.game.snapshot(),paused,"explicit load preserves complete paused snapshot")
	expect(ui.get_open_sheet()=="pause","restoring a paused save exposes the pause sheet and resume control")
	if not failures.is_empty(): return
	await activate("resume")
	expect(json_equal(before,ui.game.snapshot()),"navigation and pause roundtrip preserve complete economic state")

func run():
	expect(not config.is_empty(),"supervisor config supplied")
	var size=Vector2i(1280,800) if mode=="mouse" else Vector2i(960,640)
	if config.has("size"): size=Vector2i(config.size[0],config.size[1])
	await fresh(size,stage=="restore-smoke" or stage.begins_with("after-"))
	if not failures.is_empty(): return
	var hot=mode!="touch"
	if stage=="display":
		checkpoint="display-checked"; write_report(); quit(0 if failures.is_empty() else 1)
	elif stage=="navigation":
		await navigation_checks()
		if not failures.is_empty(): return
		checkpoint="navigation-complete"; write_report(); quit(0)
	elif stage=="exit-smoke":
		await save_and_exit("smoke")
	elif stage=="restore-smoke":
		await restore("smoke",true)
		if not failures.is_empty(): return
		checkpoint="complete"; write_report(); quit(0 if failures.is_empty() else 1)
	elif stage=="battle-pause":
		await activate("tab_gear"); await activate("start_expedition")
		ui.battle_panel.pause_requested.connect(func(): trace.append({"pause_signal":true,"paused_before_callback":ui.game.view().paused}))
		for _i in range(30):
			inject_combat({"move_x":0.6,"move_y":-0.8,"aim_x":0.6,"aim_y":-0.8,"cast":true,"dodge":false,"skill":false})
			await process_frame
		await release_combat()
		var released: Dictionary=ui.game.view()
		trace.append({"phase_after_action_release":released.phase,"paused_after_action_release":released.paused,"return_reason":released.expedition.get("return_reason","")})
		await screenshot(mode+"-after-action-release")
		expect(released.phase=="expedition","combat stick/cast input does not activate return-to-restaurant control")
		expect(not ui.game.view().paused,"releasing combat actions does not activate a focused toolbar button")
		if not failures.is_empty(): return
		await pause_combat()
		await screenshot(mode+"-pause-input")
		trace.append({"pause_result":ui.game.view().paused,"ui_accept_events":str(InputMap.action_get_events("ui_accept"))})
		expect(ui.game.view().paused,"published device pause input pauses actual combat")
		checkpoint="pause-checked"; write_report(); quit(0 if failures.is_empty() else 1)
	elif stage=="layout":
		for id in ["pause","world_gear","world_stove","world_menu","world_counter","world_journal","world_lane"]:
			var control=ui.get_action_control(id)
			expect(is_instance_valid(control) and control.is_visible_in_tree() and root.get_visible_rect().encloses(control.get_global_rect()),"narrow viewport contains actual world control "+id)
		await open_sheet("shopping")
		expect(ui.scroll.size.y>=96,"narrow layout leaves usable scroll height")
		await close_sheet()
		await activate("tab_gear"); await activate("start_expedition")
		if not failures.is_empty(): return
		await screenshot(mode+"-narrow-combat")
		await pause_combat()
		for control in [ui.battle_panel.pause_button,ui.battle_panel.save_button,ui.battle_panel.return_button]:
			expect(control.is_visible_in_tree() and root.get_visible_rect().encloses(control.get_global_rect()),"narrow paused combat button on screen: "+control.text)
		checkpoint="layout-complete"; write_report(); quit(0 if failures.is_empty() else 1)
	elif stage=="start":
		await screenshot(mode+"-opening")
		if not hot:
			await activate("tab_gear"); await activate("sell_cauldron"); await activate("tab_shopping")
		await gear(1); await battle(1)
		await prepare_day(1,hot); await trade(1,hot); await end_day(1)
		await gear(2); await battle(2)
		await prepare_day(2,hot); await trade(2,hot)
	elif stage=="after-hagrid":
		await restore("hagrid-pending")
		if not failures.is_empty(): return
		await trade(2,hot,true); await end_day(2)
		await gear(3); await battle(3)
	elif stage=="after-combat":
		await restore("combat-paused")
		if not failures.is_empty(): return
		await battle(3,true)
	elif stage=="after-drop":
		await restore("combat-drop")
		if not failures.is_empty(): return
		await battle(3,true)
	elif stage=="after-collected":
		await restore("combat-collected")
		if not failures.is_empty(): return
		verify_pickups_once()
		await battle(3,true)
		await prepare_day(3,hot); await trade(3,hot)
		expect(ui.game.view().finished,"all three days finish")
		var advanced_sales=ui.game.view().sales.filter(func(row): return row.get("item_id","")=="comet_pie" and row.get("revenue",0)>0)
		expect(not advanced_sales.is_empty(),"advanced material becomes an actually sold comet pie")
		await save_and_exit("finished")
	elif stage=="after-finished":
		await restore("finished")
		if not failures.is_empty(): return
		var before: Dictionary=ui.game.snapshot()
		# Isolated negative fixture only; no player's save or economy is modified.
		ui.save_path=folder+"/invalid.json"
		var file=FileAccess.open(ui.save_path,FileAccess.WRITE); file.store_string("{broken"); file.close()
		await activate("load")
		expect(ui.game.snapshot()==before and "恢复失败" in ui.feedback.text,"corrupt isolated save fails visibly and preserves state")
		checkpoint="complete"
		write_report(); quit(0 if failures.is_empty() else 1)
	else:
		expect(false,"known stage")

func write_report():
	if input_file!=null: input_file.flush()
	var report={"suite":"p03-main-scene-runtime","mode":mode,"stage":stage,"attempt":attempt,"checkpoint":checkpoint,"checks":checks,"failures":failures,"observations":observations,"actions":trace,"combat_observations":battle_observed,"action_events":action_events,"pickup_proofs":pickup_proofs,"restore_sources":restore_sources,"product_exit_observed":product_exit_observed,"saved_sha256":saved_sha256,"window_size":[DisplayServer.window_get_size().x,DisplayServer.window_get_size().y],"viewport_size":[root.size.x,root.size.y],"pixel_room_loaded":not ui.illustration.missing.visible if is_instance_valid(ui) else false,"screenshots":screenshots,"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"process_id":OS.get_process_id(),"synthetic_input":true,"desktop_touch_emulation":Input.emulate_touch_from_mouse,"limitations":["No physical controller, iOS/Windows device or human fun claim."]}
	report["automatic_restore_verified"]=automatic_restore_verified
	report["startup_files"]=startup_files
	report["startup_feedback"]=startup_feedback
	report["active_scene"]=active_scene_name()
	report["active_asset_evidence"]=visual_evidence
	report["display_samples"]=display_samples
	report["focus_events"]=focus_events
	report["window_size_events"]=window_size_events
	report["combat_input_samples"]=combat_input_samples
	report["economic_intents"]=economic_intents
	report["verification_kind"]=verification_kind
	report["source_sha256"]=source_hashes
	if verification_kind=="headless_navigation": report["suite"]="p03-headless-world-navigation"
	report["rendering_verified"]=verification_kind=="rendered_runtime" and DisplayServer.get_name()!="headless" and not display_samples.is_empty()
	report["input_bindings"]={}
	for action in ["ui_accept","ui_cancel","shop_pause"]:
		report.input_bindings[action]=[]
		if InputMap.has_action(action):
			for event in InputMap.action_get_events(action): report.input_bindings[action].append({"event":event.as_text(),"device":event.device})
	report["active_assets_loaded"]=visual_evidence.get("active_scene")==report.active_scene and visual_evidence.get("active_assets_loaded",false)
	# The last live rendered frame is authoritative; children may already be
	# exiting when the product's tree_exiting observer writes the final report.
	report["pixel_room_loaded"]=visual_evidence.get("room_loaded") if report.active_scene=="restaurant" else null
	var file=FileAccess.open(folder+"/"+attempt+"-report.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  ")); file.close()
