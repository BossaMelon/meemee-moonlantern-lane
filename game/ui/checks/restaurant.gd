extends SceneTree
## Drives real Controls with InputEvent. No direct Session.command or pressed.emit.
## These are UI/runtime checks; the full prototype gate is a separate requirement.
const Main = preload("res://scenes/main.tscn")
var ui
var mode = "mouse"
var failures: Array[String] = []
var trace: Array = []
var checks = 0
var folder: String
var selected_routes: PackedStringArray = []
var source_hashes: Dictionary = {}
var last_result: Dictionary = {}
var action_count = 0

func _initialize():
	folder = ProjectSettings.globalize_path("res://output/restaurant-ui")
	DirAccess.make_dir_recursive_absolute(folder)
	for path in ["game/ui/main.gd","game/ui/shop_canvas.gd","game/ui/pixel_assets.gd","game/ui/checks/restaurant.gd","game/core/game_session.gd","game/expedition/expedition_panel.gd"]:
		if FileAccess.file_exists("res://"+path): source_hashes[path] = FileAccess.get_sha256("res://"+path)
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

func inventory(id: String) -> Dictionary:
	for item in ui.game.view().inventory:
		if item.item_id==id: return item
	return {}

func fresh(size: Vector2i):
	if is_instance_valid(ui): ui.free()
	root.size = size
	ui = Main.instantiate()
	expect(ui.has_method("get_action_control"),"main script loads")
	if not ui.has_method("get_action_control"): return
	ui.save_path = folder+"/"+mode+"-restaurant-save.json"
	root.add_child(ui)
	ui.action_completed.connect(func(_kind,_args,result): last_result=result; action_count+=1)
	await frames(6)
	expect(ui.game.view().has("progression"),"frozen restaurant core is present; legacy catalog is not acceptance")
	if not ui.game.view().has("progression"): return
	expect(ui.size==Vector2(size),"actual window layout size "+str(size))

func activate(id: String):
	var control = ui.get_action_control(id)
	expect(is_instance_valid(control),mode+" control exists: "+id)
	if not is_instance_valid(control): return
	await activate_control(control,id)

func activate_control(button: Button, id: String):
	expect(not button.disabled,mode+" control enabled: "+id)
	if button.disabled: return
	if ui.scroll.is_ancestor_of(button): ui.scroll.ensure_control_visible(button)
	await frames()
	var rect = button.get_global_rect()
	expect(rect.size.x>=48 and rect.size.y>=48,"48px target: "+id+" "+str(rect.size))
	expect(Rect2(Vector2.ZERO,root.size).encloses(rect),"target stays on screen: "+id)
	var count_before = action_count
	if mode=="pad":
		var guard = 0
		while root.gui_get_focus_owner()!=button and guard<140:
			await pad_button(JOY_BUTTON_DPAD_DOWN)
			guard += 1
		expect(root.gui_get_focus_owner()==button,"D-pad reaches "+id)
		await pad_button(JOY_BUTTON_A)
	elif mode=="touch":
		for down in [true,false]:
			var event = InputEventScreenTouch.new()
			event.index = 0
			event.position = rect.get_center()
			event.pressed = down
			Input.parse_input_event(event)
	else:
		var motion = InputEventMouseMotion.new()
		motion.position = rect.get_center()
		Input.parse_input_event(motion)
		for down in [true,false]:
			var event = InputEventMouseButton.new()
			event.position = rect.get_center()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			Input.parse_input_event(event)
	await frames()
	if action_count>count_before: expect(last_result.get("ok",false),"actual command succeeds: "+id+" "+str(last_result.get("message","")))
	var v: Dictionary = ui.game.view()
	trace.append({"mode":mode,"action":id,"day":v.day,"phase":v.phase,"cash":v.cash,"cursor":v.cursor,"clock_ms":v.clock_ms})
	print("INPUT ",mode," ",id," => ",v.day,"/",v.phase," cash=",v.cash)

func pad_button(index: int):
	for down in [true,false]:
		var event = InputEventJoypadButton.new()
		event.button_index = index
		event.pressed = down
		Input.parse_input_event(event)
		await frames(1)

func key(index: int, down: bool):
	var event = InputEventKey.new()
	event.keycode = index
	event.physical_keycode = index
	event.pressed = down
	Input.parse_input_event(event)
	await frames(1)

func quantity(value: int):
	await activate("batch_1")
	for _i in range(value-1): await activate("batch_more")

func screenshot(name: String):
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(folder+"/"+name+".png")==OK,"save real viewport "+name)

func shop_and_prepare(targets: Dictionary, hot: bool):
	var needed = {}
	for recipe in ui.game.view().recipes:
		if not targets.has(recipe.output): continue
		var missing = maxi(0,targets[recipe.output]-int(inventory(recipe.output).bag))
		for raw in recipe.inputs: needed[raw]=needed.get(raw,0)+missing*int(recipe.inputs[raw])
	for raw in needed:
		var missing = maxi(0,int(needed[raw])-int(inventory(raw).bag))
		if missing>0:
			await quantity(missing)
			await activate("buy_"+raw)
	await activate("primary")
	expect(ui.view.phase=="preparation","procurement enters real preparation")
	if hot and inventory("stirring_cauldron").installed==0:
		await activate("tab_gear")
		await activate("install_cauldron")
		await activate("tab_craft")
	for output in targets:
		var missing = maxi(0,int(targets[output])-int(inventory(output).bag))
		if missing>0:
			await quantity(missing)
			await activate("craft_"+output)
			if ui.view.day==1 or output=="ember_soup": await screenshot(mode+"-"+output+"-cooking")
	await activate("to_shelf")
	for output in targets:
		var count = int(inventory(output).bag)
		if count<=0: continue
		await quantity(count)
		await activate("select_"+output)
		await activate("display_"+output)
		await activate("price_standard")
	await screenshot(mode+"-menu-day"+str(ui.view.day))

func trade(day: int, hot: bool):
	await activate("primary")
	expect(ui.view.phase=="trading","open real restaurant")
	await activate("pause")
	var frozen: Dictionary = ui.game.snapshot()
	await create_timer(1.15).timeout
	expect(ui.game.snapshot()==frozen,"real paused wait freezes full state")
	expect(ui.primary.disabled,"paused economic transition disabled")
	await activate("save")
	await activate("pause")
	var guard = 0
	while ui.game.view().phase=="trading" and guard<180:
		if not ui.view.pending.is_empty():
			frozen = ui.game.snapshot()
			await create_timer(1.15).timeout
			expect(ui.game.snapshot()==frozen,"special order real wait freezes full state")
			expect(ui.order_caption.visible and not ui.order_caption.text.is_empty(),"request remains visible outside scroll")
			if day==2:
				expect(ui.view.pending.character_id=="hagrid" and ui.view.pending.quest_id=="hagrid_patrol","actual Hagrid identity and quest")
				expect("海格" in ui.order_caption.text and "奖励" in ui.order_caption.text,"Hagrid identity and reward visible")
			await screenshot(mode+"-order-day"+str(day))
			await activate("special_menu")
			expect(ui.game.snapshot()==frozen,"viewing menu during consultation has no economic side effect")
			await activate("tab_order")
			var preferred = "floating_pie" if day==1 else ("moon_stew" if hot and day==2 else "ember_soup")
			var options: Array = ui.view.pending.options.duplicate(true)
			var picked = ""
			for option in options:
				if option.available and option.item_id==preferred: picked=preferred
			if picked.is_empty():
				for option in options:
					if option.available: picked=str(option.item_id); break
			expect(not picked.is_empty(),"real stocked dish matches special request")
			if not picked.is_empty(): await activate("fulfill_"+picked)
			if day==2: expect(ui.game.view().quests.hagrid_patrol=="completed","Hagrid completed through actual UI")
		else: await create_timer(0.1).timeout
		guard += 1
	expect(ui.view.phase=="closing","real queue completes")
	await activate("primary")
	expect(ui.view.phase=="settled","daily restaurant settlement")

func battle_route_smoke():
	await activate("start_expedition")
	expect(ui.game.view().phase=="expedition" and is_instance_valid(ui.battle_panel),"E01 real scene mounted")
	expect(ui.battle_panel.global_position==Vector2.ZERO,"E01 coordinates start at viewport origin")
	var before: Dictionary = ui.game.view().expedition.player.duplicate(true)
	await key(KEY_D,true)
	await key(KEY_RIGHT,true)
	await create_timer(0.2).timeout
	await key(KEY_D,false)
	await key(KEY_RIGHT,false)
	expect(ui.game.view().expedition.player.x>before.x,"real key input moves actual player")
	await key(KEY_J,true)
	await create_timer(0.1).timeout
	expect(ui.game.view().expedition.player.cast_cooldown_ms>0,"real cast input reaches E01 simulation")
	await key(KEY_J,false)
	await key(KEY_K,true)
	await create_timer(0.1).timeout
	expect(ui.game.view().expedition.player.dodge_cooldown_ms>0,"real dodge input reaches E01 simulation")
	await key(KEY_K,false)
	await key(KEY_L,true)
	await create_timer(0.1).timeout
	expect(ui.game.view().expedition.player.skill_cooldown_ms>0,"earned new skill has a separate input")
	await key(KEY_L,false)
	await pad_button(JOY_BUTTON_START)
	await frames()
	expect(ui.game.view().paused,"one Start event pauses once across routing boundary")
	var frozen: Dictionary = ui.game.snapshot()
	await create_timer(0.4).timeout
	expect(ui.game.snapshot()==frozen,"mounted action scene freezes while paused")
	await screenshot("mouse-expedition-paused")
	await activate_control(ui.battle_panel.save_button,"battle_save")
	await activate_control(ui.battle_panel.pause_button,"battle_resume")
	expect(not ui.game.view().paused,"action pause button resumes once")
	await activate_control(ui.battle_panel.return_button,"battle_return")
	expect(ui.view.phase=="shopping" and not is_instance_valid(ui.battle_panel),"return unmounts action scene and restores shop")
	await activate("tab_shopping")

func route(value: String, size: Vector2i):
	mode = value
	var hot = mode!="touch"
	await fresh(size)
	if not failures.is_empty(): return
	await screenshot(mode+"-restaurant-opening")
	if not hot:
		await activate("tab_gear")
		await activate("sell_cauldron")
		await activate("tab_shopping")
	for day in range(1,4):
		if day>=2:
			await activate("tab_gear")
			expect("fan_wand" in ui.view.progression.owned_weapons and "gust" in ui.view.progression.skills,"restaurant-funded growth unlocked next day")
			if ui.view.progression.equipped_weapon!="fan_wand": await activate("equip_fan_wand")
			expect(ui.view.progression.equipped_weapon=="fan_wand","equipment selection reaches persistent core")
			if day==3:
				var old_count = int(inventory("floating_pie").bag)
				await activate("consume_pie")
				expect(inventory("floating_pie").bag==old_count-1 and ui.view.next_expedition_shield,"eating trades an actual saleable dish for shield")
			if day==2 and mode=="mouse": await battle_route_smoke()
			else: await activate("tab_shopping")
		var targets = {"floating_pie":4,"moon_stew":4} if hot else {"floating_pie":4}
		if (not hot and day>=2) or (hot and day==3): targets.ember_soup=1
		await shop_and_prepare(targets,hot)
		await trade(day,hot)
		if day==1:
			await activate("upgrade_field_kit")
			await activate("upgrade_supply_pass")
			var before: Dictionary = ui.game.snapshot()
			await activate("save")
			await fresh(size)
			await activate("load")
			expect(JSON.parse_string(JSON.stringify(ui.game.snapshot()))==JSON.parse_string(JSON.stringify(before)),"scene recreation restores actual restaurant state")
		if day==2: await activate("upgrade_shelf")
		if day<3: await activate("primary")
	expect(ui.view.finished,"three restaurant days finish through "+mode)
	await activate("save")
	await screenshot(mode+"-restaurant-finished")
	var before: Dictionary = ui.game.snapshot()
	ui.save_path=folder+"/"+mode+"-invalid.json"
	var file=FileAccess.open(ui.save_path,FileAccess.WRITE)
	file.store_string("{broken save")
	file.close()
	await activate("load")
	expect(ui.game.snapshot()==before and "恢复失败" in ui.feedback.text,"bad save gives visible failure and preserves restaurant")

func run():
	selected_routes=OS.get_cmdline_user_args()
	if selected_routes.is_empty() or "mouse" in selected_routes: await route("mouse",Vector2i(1280,720))
	if failures.is_empty() and (selected_routes.is_empty() or "touch" in selected_routes): await route("touch",Vector2i(960,640))
	if failures.is_empty() and (selected_routes.is_empty() or "pad" in selected_routes): await route("pad",Vector2i(960,640))
	write_report()
	print("RESTAURANT UI checks ",checks," failures ",failures.size())
	quit(0 if failures.is_empty() else 1)

func write_report():
	var name="all" if selected_routes.is_empty() else "-".join(selected_routes)
	var result={"suite":"restaurant-ui-runtime-input","checks":checks,"failures":failures,"trace":trace,"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"input_claim":"synthetic InputEvent through actual controls; not physical device certification"}
	var file=FileAccess.open(folder+"/"+name+"-report.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"  ")); file.close()
