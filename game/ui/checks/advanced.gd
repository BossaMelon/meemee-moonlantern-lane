extends "res://game/ui/checks/restaurant.gd"
## Complete business→earned equipment→real combat input→advanced cuisine loop.
## E01's policy reads actual positions; this adapter emits only native key events.
const Driver = preload("res://tests/expedition/action_driver.gd")
var held_keys: Dictionary = {}
var action_events: Array = []
var battle_runs: Array = []

func _initialize():
	super._initialize()
	folder=ProjectSettings.globalize_path("res://output/restaurant-ui/advanced")
	DirAccess.make_dir_recursive_absolute(folder)
	source_hashes["game/ui/checks/advanced.gd"]=FileAccess.get_sha256("res://game/ui/checks/advanced.gd")

func inject_keyboard(input: Dictionary):
	var values={KEY_W:input.move_y < -0.3,KEY_S:input.move_y > 0.3,KEY_A:input.move_x < -0.3,KEY_D:input.move_x > 0.3,
		KEY_UP:input.aim_y < -0.3,KEY_DOWN:input.aim_y > 0.3,KEY_LEFT:input.aim_x < -0.3,KEY_RIGHT:input.aim_x > 0.3,
		KEY_J:input.cast,KEY_K:input.dodge,KEY_L:input.skill}
	for code in values:
		if values[code]==held_keys.get(code,false): continue
		var event=InputEventKey.new()
		event.keycode=code;event.physical_keycode=code;event.pressed=values[code]
		Input.parse_input_event(event)
	held_keys=values

func harvest(day: int):
	await activate("tab_gear")
	await activate("start_expedition")
	expect(is_instance_valid(ui.battle_panel) and ui.game.view().phase=="expedition","actual action scene begins for harvest")
	if not is_instance_valid(ui.battle_panel): return
	ui.battle_panel.action_events.connect(func(events): action_events.append_array(events))
	var initial: Dictionary=ui.game.view().expedition.duplicate(true)
	var frame_count=0
	var photographed=false
	var old_time_scale=Engine.time_scale
	Engine.time_scale=3.0
	while ui.game.view().phase=="expedition" and frame_count<12000:
		inject_keyboard(Driver.next_input(ui.game.view().expedition))
		await process_frame
		frame_count+=1
		if frame_count>35 and not photographed:
			await screenshot("actual-harvest-day"+str(day))
			photographed=true
	inject_keyboard({"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false})
	Engine.time_scale=old_time_scale
	await frames(5)
	var final: Dictionary=ui.game.view().expedition.duplicate(true)
	battle_runs.append({"day":day,"initial":initial,"final":final,"render_frames":frame_count,"simulation_time_scale":3.0,"native_input":"keyboard InputEventKey, held and released"})
	expect(ui.view.phase=="shopping","harvest returns through main UI route")
	if day==1: expect(inventory("sparkcap").bag>=1,"real ordinary enemies yielded cooking ingredient")
	if day==3: expect(inventory("moonheart").bag==1,"real elite yielded unique advanced ingredient")
	await activate("tab_shopping")

func run():
	selected_routes=PackedStringArray(["advanced"])
	mode="mouse"
	await fresh(Vector2i(1280,720))
	if not failures.is_empty(): return
	for day in range(1,4):
		if day==2:
			await activate("tab_gear")
			expect("fan_wand" in ui.view.progression.owned_weapons and "gust" in ui.view.progression.skills,"real dish income bought new combat tools")
			await activate("equip_fan_wand")
			await activate("tab_shopping")
		if day==3:
			await activate("tab_gear")
			await activate("consume_pie")
			expect(ui.view.next_expedition_shield,"a real stored pie is consumed for next harvest")
		if day in [1,3]: await harvest(day)
		var targets={"floating_pie":4,"moon_stew":4}
		if day==2: targets.star_soup=1
		if day==3: targets={"floating_pie":3,"moon_stew":4,"comet_pie":1}
		await shop_and_prepare(targets,true)
		await trade(day,true)
		if day==1:
			await activate("upgrade_field_kit")
			await activate("upgrade_supply_pass")
			await activate("upgrade_shelf")
		if day<3: await activate("primary")
	expect(ui.view.finished,"advanced harvest and cuisine loop finishes three real UI days")
	var sold_star=false
	var sold_comet=false
	for sale in ui.view.sales:
		if sale.revenue>0 and sale.item_id=="star_soup": sold_star=true
		if sale.revenue>0 and sale.item_id=="comet_pie": sold_comet=true
	expect(sold_star and sold_comet,"combat ingredients actually cooked and sold as both advanced dishes")
	await activate("save")
	await screenshot("advanced-loop-finished")
	write_report()
	print("ADVANCED UI checks ",checks," failures ",failures.size())
	quit(0 if failures.is_empty() else 1)

func write_report():
	super.write_report()
	var path=folder+"/advanced-report.json"
	if not FileAccess.file_exists(path): return
	var data=JSON.parse_string(FileAccess.get_file_as_string(path))
	data.action_events=action_events
	data.battle_runs=battle_runs
	data.input_claim="business controls and keyboard combat were driven by real InputEvent; simulation accelerated 3x only during harvest, not a human playtime claim"
	var file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "));file.close()
