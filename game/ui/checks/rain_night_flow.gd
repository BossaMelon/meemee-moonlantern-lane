extends "res://game/ui/checks/scene_layout.gd"
## Real Main + Session, via visible GUI only. Headless business integration, not Q06.
var actions: Array=[]
var observed_upgrade_cost=0
var old_scale=1.0

func _initialize():
	super._initialize()
	for path in ["game/ui/checks/rain_night_flow.gd","game/ui/rain_night/panels.gd","game/core/rain_night_session.gd"]:
		sources[path]=FileAccess.get_sha256("res://"+path)

func act_click(id: String, kind: String):
	var count=actions.size()
	await click(id)
	expect(actions.size()==count+1,"one GUI action produces one actual command: "+id)
	if actions.size()>count:
		expect(actions.back().kind==kind and actions.back().result.ok,"real Session accepts "+id+": "+str(actions.back().result))

func quantity(value: int):
	await click("batch_5" if value>=5 else "batch_3" if value>=3 else "batch_1")
	while ui.batch<value: await click("batch_more")
	while ui.batch>value: await click("batch_less")

func await_phase(phase: String):
	var deadline=Time.get_ticks_msec()+9000
	while ui.game.view().phase!=phase and Time.get_ticks_msec()<deadline:
		await create_timer(0.05,true,false,true).timeout
	expect(ui.game.view().phase==phase,"actual service reaches "+phase)

func run():
	old_scale=Engine.time_scale
	mount_ui()
	ui.action_completed.connect(func(kind,args,result): actions.append({"kind":kind,"args":args,"result":result}))
	await frames()
	expect(ui.PROFILE_ID=="rain-night-v1","Main explicitly selects new profile")
	expect(ui.game.snapshot().version==3 and ui.game.snapshot().profile_id=="rain-night-v1","real facade creates v3 rain-night Session")
	expect(ui.game.view().night.weather=="rain" and ui.game.view().day==1,"first night is rain, not a legacy day3 mask")
	await click("world_journal")
	expect("8位" in ui.get_action_control("wave_summary_1").text and "9位" in ui.get_action_control("wave_summary_2").text,"real full-night forecast is visible before purchases")
	await screenshot("forecast")
	await click("sheet_close")
	await click("world_lane")
	await click("world_stall")
	await quantity(3); await act_click("buy_flour","buy")
	await quantity(9); await act_click("buy_pumpkin","buy")
	await quantity(6); await act_click("buy_cream","buy")
	await act_click("primary","finish_shopping")
	await click("world_gear")
	await act_click("install_cauldron","install")
	await click("sheet_close")
	await click("world_craft")
	await quantity(2); await act_click("craft_floating_pie","craft")
	await click("recipe_moon_stew")
	await quantity(6); await act_click("craft_moon_stew","craft")
	await click("sheet_close")
	await click("world_menu")
	await quantity(2); await act_click("display_floating_pie","display")
	await click("select_moon_stew")
	await quantity(6); await act_click("display_moon_stew","display")
	await click("priority_up_moon_stew")
	await act_click("menu_priority_apply","set_menu_priority")
	expect(ui.game.view().service.menu_priority[0]=="moon_stew","core commits explicit full menu priority")
	await screenshot("menu-before-service")
	await click("sheet_close")
	await click("world_counter")
	var cash_before_dispatch=int(ui.game.view().cash)
	await act_click("primary","open_shop")
	expect(ui.game.view().service.reservations.size()==5,"t0 reserves actual two floating and three pot UIDs")
	expect(ui.game.view().cash==cash_before_dispatch,"reservation does not fake delivery revenue")
	Engine.time_scale=12.0
	await await_phase("intermission")
	Engine.time_scale=old_scale
	var boundary: Dictionary=ui.game.snapshot()
	await create_timer(0.15).timeout
	expect(ui.game.snapshot()==boundary,"true intermission freezes service without paused flag")
	expect(not boundary.paused and boundary.service.reservations.is_empty() and boundary.service.held_uids.size()==3,"wave drains all in-flight food and retains actual three held portions")
	await click("world_craft")
	await click("recipe_floating_pie")
	await quantity(1); await act_click("craft_floating_pie","craft")
	await click("sheet_close")
	await click("world_menu")
	await click("select_floating_pie")
	await quantity(1); await act_click("display_floating_pie","display")
	await click("priority_up_floating_pie")
	await act_click("menu_priority_apply","set_menu_priority")
	expect(ui.game.view().service.menu_priority[0]=="floating_pie","intermission applies real new priority")
	await click("sheet_close")
	for wave in [2,3]:
		var next_id=ui.game.view().service.next_wave_id
		await click("world_counter")
		await screenshot("before-wave-%d"%wave)
		await act_click("start_wave","start_wave")
		expect(actions.back().args.wave_id==next_id,"GUI sends actual next_wave_id without reroll")
		Engine.time_scale=12.0
		await await_phase("intermission" if wave==2 else "closing")
		Engine.time_scale=old_scale
	await click("world_journal")
	await act_click("primary","settle")
	await screenshot("settled-growth")
	observed_upgrade_cost=int(ui.game.view().upgrades.filter(func(row): return row.upgrade_id=="field_kit")[0].cost)
	await act_click("upgrade_field_kit","upgrade")
	await act_click("next_morning","next_day")
	expect(ui.game.view().day==2 and "fan_wand" in ui.game.view().progression.owned_weapons,"real legal next_day immediately unlocks purchased wand")
	await click("world_gear")
	await screenshot("next-morning-gear")
	await act_click("equip_fan_wand","equip_weapon")
	expect(ui.game.view().progression.equipped_weapon=="fan_wand","actual next morning equipment command succeeds")
	await act_click("start_expedition","start_expedition")
	expect(ui.game.view().phase=="expedition" and is_instance_valid(ui.battle_panel),"legal next-morning departure mounts the real E02 scene")
	expect(ui.game.view().expedition.version==2 and ui.game.view().expedition.weapon_id=="fan_wand","real E02 model receives the newly equipped wand")
	await battle_click(ui.battle_panel.pause_button,"battle_pause")
	expect(ui.game.view().paused,"actual E02 pause signal reaches Main Session")
	await screenshot("actual-next-morning-expedition")
	await act_save()
	write_report()
	await battle_click(ui.battle_panel.save_quit_button,"battle_save_quit")
	expect(false,"real product save-and-quit closes engine")

func battle_click(button: Button, id: String):
	expect(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"actual visible E02 control "+id)
	var rect=button.get_global_rect()
	expect(Rect2(Vector2.ZERO,ui.size).encloses(rect),"E02 control fits actual viewport "+id)
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=rect.get_center()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		ui.get_viewport().push_input(event,true)
		await process_frame
	await frames()
	trace.append({"id":id,"rect_virtual":str(rect),"phase":ui.game.view().phase})

func act_save():
	await battle_click(ui.battle_panel.save_button,"battle_save")
	expect(FileAccess.file_exists(ui.save_path),"real UI saves only isolated temporary profile path")
	var saved=JSON.parse_string(FileAccess.get_file_as_string(ui.save_path))
	expect(saved.version==3 and saved.profile_id=="rain-night-v1","actual file is new profile v3")

func write_report():
	var file=FileAccess.open(folder+"/rain-flow-report.json",FileAccess.WRITE)
	var native=DisplayServer.get_name()!="headless"
	file.store_string(JSON.stringify({"suite":"rain-night-real-main-native" if native else "rain-night-real-main-headless","checks":checks,"failures":failures,"trace":trace,"actions":actions,"observed_upgrade_cost":observed_upgrade_cost,"source_sha256":sources,"engine":Engine.get_version_info().string,"claims":"Real Main/Session through InputEventMouseButton; no direct test core commands, fake inventory or transaction injection. Not Q06, physical input certification or fun evidence.","render_claim":"Raw actual native viewport PNGs and display metadata" if native else "Headless SubViewport geometry only; no native-window or PNG claim","simulation_scale":"12x during active service only; no human-duration claim","save_path":ui.save_path if is_instance_valid(ui) else folder},"  "))
	file.close()
