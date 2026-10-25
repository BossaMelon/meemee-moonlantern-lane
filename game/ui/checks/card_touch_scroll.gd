extends SceneTree
## F05: desktop-emulated real touch drag through an actual narrow Main card.
const Session=preload("res://game/core/game_session.gd")
var ui
var folder="/private/tmp/p05-card-touch"
var failures: Array=[]
var rows: Array=[]
var actions: Array=[]
var checks=0

func _initialize():
	if not OS.get_cmdline_user_args().is_empty(): folder=OS.get_cmdline_user_args()[0]
	if not folder.begins_with("/private/tmp/"): quit(2); return
	DirAccess.make_dir_recursive_absolute(folder)
	Engine.max_fps=120
	Input.emulate_touch_from_mouse=true
	call_deferred("run")

func expect(ok: bool, message: String):
	checks+=1
	if not ok:
		failures.append(message)
		print("FAIL ",message)

func frames(count=3):
	for i in range(count): await process_frame

func touch(at: Vector2, down: bool):
	var event=InputEventScreenTouch.new()
	event.index=0;event.position=at;event.pressed=down
	Input.parse_input_event(event.xformed_by(root.get_final_transform()))
	await frames(1)

func focus_control(id: String):
	for i in range(100):
		var button=ui.get_action_control(id)
		if button!=null and root.gui_get_focus_owner()==button: return
		for down in [true,false]:
			var event=InputEventJoypadButton.new()
			event.button_index=JOY_BUTTON_DPAD_DOWN;event.pressed=down
			Input.parse_input_event(event);await frames(1)
	expect(false,"real D-pad setup reaches "+id)

func tap(id: String, hold=0.0):
	await focus_control(id)
	var button=ui.get_action_control(id)
	expect(button is Button and not button.disabled and ui.get_global_rect().encloses(button.get_global_rect()),"actual visible enabled touch target "+id)
	var at=button.get_global_rect().get_center()
	var started=Time.get_ticks_msec()
	await touch(at,true)
	if hold>0: await create_timer(hold).timeout
	await touch(at,false);await frames()
	rows.append({"case":"touch_tap","id":id,"requested_hold_ms":roundi(hold*1000),"elapsed_ms":Time.get_ticks_msec()-started})

func drag(at: Vector2, delta_y: float):
	await touch(at,true)
	for step in range(1,7):
		var event=InputEventScreenDrag.new()
		event.index=0;event.position=at+Vector2(0,delta_y*step/6.0)
		event.relative=Vector2(0,delta_y/6.0)
		Input.parse_input_event(event.xformed_by(root.get_final_transform()))
		await frames(1)
	await create_timer(0.25).timeout
	await touch(at+Vector2(0,delta_y),false);await frames()

func mount(preparation: bool):
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(844,390)
	var game=Session.new(23,"rain-night-v1")
	for id in ["flour","pumpkin"]: expect(game.command("buy",{"item_id":id,"quantity":6}).ok,"legal pre-mount ingredient fixture")
	if preparation:
		expect(game.command("finish_shopping").ok,"legal preparation fixture")
		expect(game.command("craft",{"recipe_id":"floating_pie","quantity":3}).ok,"legal cooked inventory fixture")
	ui=load("res://scenes/main.tscn").instantiate();ui.game=game
	ui.save_path=folder+("/unused-preparation.json" if preparation else "/unused-shopping.json")
	root.add_child(ui)
	ui.action_completed.connect(func(kind,args,result): actions.append({"kind":kind,"args":args,"ok":result.ok}))
	await frames()

func decorative_point(panel: Control) -> Vector2:
	var clip=ui.scroll.get_global_rect().intersection(panel.get_global_rect())
	for y in range(int(clip.position.y)+8,int(clip.end.y)-8,4):
		var at=Vector2(clip.get_center().x,y)
		var blocked=false
		for button in panel.find_children("*","Button",true,false):
			if button.is_visible_in_tree() and button.get_global_rect().has_point(at): blocked=true;break
		if not blocked: return at
	return clip.get_center()

func button_drag_does_not_act(id: String):
	await focus_control(id)
	var at=ui.get_action_control(id).get_global_rect().get_center()
	var before: Dictionary=ui.game.snapshot()
	var count=actions.size()
	await drag(at,-120.0 if at.y>195 else 120.0)
	expect(actions.size()==count and ui.game.snapshot()==before,"dragging off "+id+" neither buys nor crafts")

func one_action(id: String, kind: String, hold=0.0):
	var count=actions.size()
	await tap(id,hold)
	expect(actions.size()==count+1 and actions.back().kind==kind and actions.back().ok,"touch tap/long hold produces exactly one accepted "+kind)

func run():
	await mount(true)
	await tap("world_menu")
	print("ROUTING window=",root.get_window_id()," size=",ui.size," transform=",root.get_final_transform()," mouse_from_touch=",Input.emulate_mouse_from_touch," touchscreen=",DisplayServer.is_touchscreen_available()," open=",ui.get_open_sheet())
	if ui.get_open_sheet()!="shelf": quit(2); return
	await tap("select_comet_pie")
	var panel=ui.get_action_control("price_standard").get_parent().get_parent().get_parent()
	var at=decorative_point(panel)
	var before_scroll=ui.scroll.scroll_vertical
	var before: Dictionary=ui.game.snapshot()
	var count=actions.size()
	expect(before_scroll>0 and panel.get_global_rect().has_point(at),"fixture reproduces scrolled comet card under touch origin")
	await drag(at,120.0)
	rows.append({"case":"comet_card_drag","card_rect":str(panel.get_global_rect()),"card_mouse_filter":panel.mouse_filter,"touch_origin":str(at),"scroll_before":before_scroll,"scroll_after":ui.scroll.scroll_vertical,"scroll_max":ui.scroll.get_v_scroll_bar().max_value,"scroll_page":ui.scroll.get_v_scroll_bar().page,"economic_intents":actions.size()-count})
	expect(ui.scroll.scroll_vertical<before_scroll,"real touch drag on decorative menu card scrolls toward batch controls")
	expect(actions.size()==count and ui.game.snapshot()==before,"card drag has zero economic intent and preserves full gameplay state")
	# Continue using only actual touch until the original inaccessible target fits.
	for i in range(8):
		if ui.scroll.get_global_rect().encloses(ui.get_action_control("batch_1").get_global_rect()): break
		await drag(decorative_point(panel),120.0)
	expect(ui.scroll.get_global_rect().encloses(ui.get_action_control("batch_1").get_global_rect()),"actual touch scrolling reaches original batch_1 target")
	await tap("sheet_close")
	await tap("world_craft")
	await button_drag_does_not_act("craft_floating_pie")
	await one_action("craft_floating_pie","craft")
	await one_action("craft_floating_pie","craft",0.35)
	ui.queue_free();await frames()
	await mount(false)
	await tap("world_lane");await tap("world_stall")
	await button_drag_does_not_act("buy_flour")
	await one_action("buy_flour","buy")
	await one_action("buy_pumpkin","buy",0.35)
	var sources={}
	for path in ["game/ui/main.gd","game/ui/checks/card_touch_scroll.gd","game/core/game_session.gd","game/core/rain_night_session.gd","project.godot"]: sources[path]=FileAccess.get_sha256("res://"+path)
	var file=FileAccess.open(folder+"/card-touch-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"actions":actions,"source_sha256":sources,"engine":Engine.get_version_info().string,"touch_emulation":Input.emulate_touch_from_mouse,"touchscreen_available":DisplayServer.is_touchscreen_available(),"ui_size":str(ui.size),"claim":"Headless actual Main/root viewport at844x390. Legal pre-mount Session fixture; real D-pad focus setup, then actual InputEventScreenTouch/ScreenDrag via Input.parse_input_event and normal engine emulation. No scroll writes, wheel, pressed emission or runtime test core commands; no native/Q06/device claim."},"  "));file.close()
	print("CARD TOUCH ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
