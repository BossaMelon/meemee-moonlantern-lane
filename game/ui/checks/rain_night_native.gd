extends "res://game/ui/checks/rain_night_flow.gd"
## Limited UI visual closure. Real GUI only; no battle/Q06/physical-input claim.
var small_view=false
var focus_events: Array=[]
var started_ms=Time.get_ticks_msec()

func _initialize():
	super._initialize()
	small_view="--small" in OS.get_cmdline_user_args()
	sources["game/ui/checks/rain_night_native.gd"]=FileAccess.get_sha256("res://game/ui/checks/rain_night_native.gd")
	root.focus_entered.connect(_record_focus.bind(true))
	root.focus_exited.connect(_record_focus.bind(false))
	_record_focus(root.has_focus())

func mount_ui():
	if small_view:
		root.min_size=Vector2i.ZERO
		root.size=Vector2i(844,390)
	ui=load("res://scenes/main.tscn").instantiate()
	ui.save_path=folder+"/preview-save.json"
	root.add_child(ui)

func wheel(down: bool, factor: float=1.0):
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=ui.scroll.get_global_rect().get_center()
		event.button_index=MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		event.factor=factor
		event.pressed=pressed
		ui.get_viewport().push_input(event,true)
		await process_frame
	await frames(2)

func scroll_range(top: Control, bottom: Control):
	for i in range(160):
		var client=ui.scroll.get_global_rect()
		if client.encloses(top.get_global_rect()) and client.encloses(bottom.get_global_rect()): return
		await wheel(top.get_global_rect().position.y>=client.position.y,0.25)
	expect(false,"real wheel input could not reveal requested controls")

func click(id: String):
	var button: Button=ui.get_action_control(id)
	expect(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"visible enabled GUI control "+id)
	if not is_instance_valid(button): return
	if ui.scroll.is_ancestor_of(button): await scroll_range(button,button)
	var rect=button.get_global_rect()
	expect(Rect2(Vector2.ZERO,ui.size).encloses(rect),"viewport contains actual GUI target "+id)
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=rect.get_center()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		ui.get_viewport().push_input(event,true)
		await process_frame
	await frames()
	trace.append({"id":id,"rect_virtual":str(rect),"phase":ui.game.view().phase,"window_focused":root.has_focus()})

func check_intermission_page():
	var before: Dictionary=ui.game.snapshot()
	var count=actions.size()
	var button=ui.get_action_control("start_wave")
	var rect=button.get_global_rect()
	expect(button.is_visible_in_tree() and not ui.scroll.is_ancestor_of(button),"start-wave footer is visible outside scroll history")
	var capture=before.service.wave_index==1
	if capture: await screenshot("intermission-folded")
	await click("service_history_toggle")
	for i in range(80):
		var bar=ui.scroll.get_v_scroll_bar()
		if bar.value+bar.page>=bar.max_value-1: break
		await wheel(true)
	var bar=ui.scroll.get_v_scroll_bar()
	expect(bar.value+bar.page>=bar.max_value-1,"actual wheel events reach expanded history bottom")
	expect(button==ui.get_action_control("start_wave") and button.get_global_rect()==rect,"history expansion and bottom scrolling retain the same visible footer")
	if capture: await screenshot("intermission-expanded-bottom")
	await click("service_history_toggle")
	expect(ui.game.snapshot()==before and actions.size()==count,"history navigation does not advance or write the real intermission")

func check_growth_page():
	if not small_view:
		super.check_growth_page()
		return
	await scroll_range(ui.get_action_control("growth_field_kit"),ui.get_action_control("upgrade_shelf"))
	for id in ["growth_field_kit","growth_shelf","growth_effect_field_kit","growth_effect_shelf","growth_balance_field_kit","growth_balance_shelf","upgrade_field_kit","upgrade_shelf"]:
		expect(ui.scroll.get_global_rect().encloses(ui.get_action_control(id).get_global_rect()),"844x390 comparison is visible together after real wheel input: "+id)

func finish_route():
	# This slot ends at the equipped summary; combat is a separate owner's scope.
	await scroll_range(ui.get_action_control("departure_summary"),ui.get_action_control("start_expedition"))
	await screenshot("equipped-departure-summary")
	await click("sheet_close")
	await click("pause")
	await click("save")
	expect(FileAccess.file_exists(ui.save_path),"actual product save writes isolated profile")
	write_report()
	await click("quit")
	expect(false,"actual product save-and-quit must close this process")

func screenshot(name: String):
	var requested=["intermission-folded","intermission-expanded-bottom","settled-growth"] if small_view else ["forecast","intermission-folded","intermission-expanded-bottom","settled-growth","equipped-departure-summary"]
	if name not in requested: return
	await frames(8)
	if DisplayServer.get_name()=="headless":
		trace.append({"layout_probe":name,"ui_size":str(ui.size),"scroll_rect":str(ui.scroll.get_global_rect())})
		return
	var drawn={"ready":false}
	var on_draw=func(): drawn.ready=true
	RenderingServer.frame_post_draw.connect(on_draw,CONNECT_ONE_SHOT)
	var deadline=Time.get_ticks_msec()+5000
	while not drawn.ready and Time.get_ticks_msec()<deadline: await process_frame
	if not drawn.ready:
		if RenderingServer.frame_post_draw.is_connected(on_draw): RenderingServer.frame_post_draw.disconnect(on_draw)
		trace.append({"render_wait_timeout":name,"window_focused":root.has_focus(),"elapsed_ms":Time.get_ticks_msec()-started_ms})
		expect(false,"viewport did not draw within 5 seconds: "+name)
		return
	var image=root.get_texture().get_image()
	expect(image!=null,"actual native viewport returns pixels at "+name)
	if image==null: return
	expect(image.save_png(folder+"/"+name+".png")==OK,"raw native PNG saved at "+name)
	var stretch=root.get_stretch_transform()
	var focused=root.gui_get_focus_owner()
	trace.append({"screenshot":name,"elapsed_ms":Time.get_ticks_msec()-started_ms,"png_sha256":FileAccess.get_sha256(folder+"/"+name+".png"),"png_size":str(image.get_size()),"window_size":str(root.size),"display_window_size":str(DisplayServer.window_get_size()),"virtual_ui_size":str(ui.size),"window_mode":root.mode,"display_mode":DisplayServer.window_get_mode(root.get_window_id()),"screen_size":str(DisplayServer.screen_get_size(root.current_screen)),"screen_dpi":DisplayServer.screen_get_dpi(root.current_screen),"screen_scale":DisplayServer.screen_get_scale(root.current_screen),"window_focused":root.has_focus(),"focus_owner":str(focused.get_path()) if focused else "","content_scale_size":str(root.content_scale_size),"content_scale_factor":root.content_scale_factor,"viewport_visible_rect":str(root.get_visible_rect()),"viewport_texture_size":str(root.get_texture().get_size()),"stretch_transform":[stretch.x.x,stretch.x.y,stretch.y.x,stretch.y.y,stretch.origin.x,stretch.origin.y],"png_per_ui_unit":[image.get_width()/ui.size.x,image.get_height()/ui.size.y],"display_server":DisplayServer.get_name(),"renderer_setting":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"adapter":RenderingServer.get_video_adapter_name()})
	if ui.get_open_sheet()!="":
		expect(Rect2(Vector2.ZERO,ui.size).encloses(ui.sheet_surface.get_global_rect()),"entire sheet fits actual native viewport at "+name)
	write_report()

func _record_focus(focused: bool):
	focus_events.append({"elapsed_ms":Time.get_ticks_msec()-started_ms,"unix_time":Time.get_unix_time_from_system(),"signal_focus":focused,"window_focused":root.has_focus()})
	write_report()

func write_report():
	super.write_report()
	var path=folder+"/rain-flow-report.json"
	var report=JSON.parse_string(FileAccess.get_file_as_string(path))
	report.suite="rain-night-ui-layout-probe" if DisplayServer.get_name()=="headless" else "rain-night-ui-visual-closure"
	report.focus_events=focus_events
	report.requested_window="844x390 windowed" if small_view else "fullscreen"
	report.checks=int(report.checks)
	report.observed_upgrade_cost=int(report.observed_upgrade_cost)
	if DisplayServer.get_name()=="headless": report.render_claim="Headless root viewport layout only; no native window or PNG claim."
	report.claims="Three UI presentation corrections only, actual GUI InputEvents and real Session. Ends at next-morning equipment; no Q06, battle, physical device or fun claim."
	var file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
