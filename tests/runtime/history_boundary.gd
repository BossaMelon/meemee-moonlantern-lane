extends "res://tests/runtime/rain_night_path.gd"
## Real shopping/service at 1x, then hold actual controls across live updates.
var history_rows: Array=[]
var history_toggles=0

func hold_event(point: Vector2, down: bool):
	if mode=="pad":
		var event=InputEventJoypadButton.new(); event.button_index=JOY_BUTTON_A; event.pressed=down; emit_input(event)
	elif mode=="touch":
		var event=InputEventScreenTouch.new(); event.index=0; event.position=point; event.pressed=down; emit_gui_pointer(event)
	else:
		var event=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.position=point; event.global_position=point; event.pressed=down; event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0; emit_gui_pointer(event)

func history_panel() -> Control:
	return ui.get_action_control("service_history_toggle").get_parent()

func held_history(delivery: bool):
	var button=ui.get_action_control("service_history_toggle")
	expect(is_instance_valid(button),"actual live history control exists")
	if not failures.is_empty(): return
	if mode=="pad":
		for i in range(160):
			if root.gui_get_focus_owner()==button: break
			await pad_button(JOY_BUTTON_DPAD_DOWN)
		expect(root.gui_get_focus_owner()==button,"real D-pad reaches live history")
	else: await scroll_to(button)
	var deadline=Time.get_ticks_msec()+10000
	var ready=false
	while ui.game.view().phase=="trading" and Time.get_ticks_msec()<deadline:
		var remaining: Array=ui.game.view().service.reservations.map(func(row): return int(row.remaining_ms))
		ready=not remaining.is_empty() and (remaining.min()<=150 if delivery else remaining.min()>=650)
		if ready: break
		await process_frame
	expect(ready,"actual reservation timing reaches the requested hold boundary")
	if not failures.is_empty(): return
	var before: Dictionary=ui.game.view()
	var initial_open: bool=history_panel().history_open
	var instance=button.get_instance_id()
	var rect=button.get_global_rect()
	expect(root.get_visible_rect().encloses(rect) and ui.scroll.get_global_rect().encloses(rect),"entire live target remains on viewport and inside scroll clip")
	var point=rect.get_center()
	var intents=action_count
	var count=history_toggles
	button.pressed.connect(func(): history_toggles+=1,CONNECT_ONE_SHOT)
	hold_event(point,true)
	var started=Time.get_ticks_msec()
	await create_timer(0.30,true,false,true).timeout
	var during=ui.get_action_control("service_history_toggle")
	var during_id=during.get_instance_id() if is_instance_valid(during) else -1
	var pressed_during=during.is_pressed() if is_instance_valid(during) else false
	var rect_stable=during.get_global_rect()==rect if is_instance_valid(during) else false
	var focus_id=root.gui_get_focus_owner().get_instance_id() if root.gui_get_focus_owner() else -1
	var held_ms=Time.get_ticks_msec()-started
	hold_event(point,false); await frames(3)
	var after: Dictionary=ui.game.view()
	var current=ui.get_action_control("service_history_toggle")
	var row={"delivery_expected":delivery,"held_ms":held_ms,"before_instance":instance,"during_instance":during_id,"after_instance":current.get_instance_id() if is_instance_valid(current) else -1,"pressed_during":pressed_during,"rect_stable":rect_stable,"focus_during":focus_id,"focus_after":root.gui_get_focus_owner().get_instance_id() if root.gui_get_focus_owner() else -1,"toggle_count":history_toggles-count,"economic_intents":action_count-intents,"before_service_ms":before.service.elapsed_ms,"after_service_ms":after.service.elapsed_ms,"sales_before":before.sales.size(),"sales_after":after.sales.size(),"initial_open":initial_open,"history_open":history_panel().history_open,"phase":after.phase}
	history_rows.append(row); write_report()
	expect(row.held_ms>=250 and row.held_ms<=350,"actual hold spans 250–350ms")
	expect(row.before_instance==row.during_instance and row.before_instance==row.after_instance and row.pressed_during and row.rect_stable,"live update retains pressed instance and geometry")
	expect(row.focus_during==instance and row.focus_after==instance,"actual device focus survives hold and release")
	expect(row.toggle_count==1 and row.history_open!=initial_open and row.economic_intents==0,"release toggles exactly once with zero economic intent")
	expect(row.after_service_ms>row.before_service_ms and row.phase=="trading","service advances normally through hold")
	expect(row.sales_after>row.sales_before if delivery else row.sales_after==row.sales_before,"hold crosses actual delivery" if delivery else "hold crosses ordinary service ticks")
	await screenshot(mode+"-history-"+("delivery" if delivery else "tick"))

func run():
	if config.get("headless_diagnostic",false): verification_kind="headless_navigation"
	await fresh(Vector2i(1280,800),false)
	await buy_missing({"flour":5,"pumpkin":5})
	await activate("primary")
	await craft_display("floating_pie",5)
	await activate("primary"); await open_sheet("counter")
	var deadline=Time.get_ticks_msec()+10000
	while not is_instance_valid(ui.get_action_control("service_history_toggle")) and Time.get_ticks_msec()<deadline: await process_frame
	await held_history(false)
	if not failures.is_empty(): return
	await held_history(true)
	if not failures.is_empty(): return
	await save_and_exit("history-complete")

func write_report():
	super.write_report()
	var path=folder+"/"+attempt+"-report.json"
	var report=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not report is Dictionary: return
	report.history_hold_samples=history_rows
	report.source_sha256["tests/runtime/history_boundary.gd"]=FileAccess.get_sha256("res://tests/runtime/history_boundary.gd")
	var file=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
