extends "res://game/ui/checks/restaurant.gd"
## P03: real main scene, synthetic inputs, read-only session observations.
## Common restaurant purchasing helpers are reused from the UI owner's smoke test.
const CombatDriver = preload("res://tests/expedition/action_driver.gd")
var stage = "start"
var attempt = ""
var action_events: Array = []
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

func _initialize():
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i]=="--config": config=JSON.parse_string(FileAccess.get_file_as_string(args[i+1]))
	folder=str(config.get("output","/tmp/p03-runtime-unconfigured"))
	mode=str(config.get("mode","mouse"))
	stage=str(config.get("stage","start"))
	attempt=str(config.get("attempt",stage))
	DirAccess.make_dir_recursive_absolute(folder)
	input_file=FileAccess.open(folder+"/"+attempt+"-inputs.jsonl",FileAccess.WRITE)
	started_ms=Time.get_ticks_msec()
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
	var entry={"elapsed_ms":Time.get_ticks_msec()-started_ms,"event":event.as_text(),"class":event.get_class(),"local":local,"pressed":event.is_pressed()}
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag: entry.position=[event.position.x,event.position.y]
	if event is InputEventJoypadMotion: entry.axis=event.axis; entry.axis_value=event.axis_value
	if event is InputEventScreenTouch or event is InputEventScreenDrag: entry.touch_index=event.index
	input_file.store_line(JSON.stringify(entry))
	if local: root.push_input(event,true)
	else: Input.parse_input_event(event)

func fresh(size: Vector2i, restore_existing: bool = false):
	# Godot desktop ScrollContainer enables the touchscreen drag path only
	# with this runtime emulation flag; no project setting is saved.
	Input.emulate_touch_from_mouse=(mode=="touch")
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size=Vector2i.ZERO
	root.size=size
	DisplayServer.window_set_size(size)
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
	ui.action_completed.connect(func(_kind,_args,result): last_result=result; action_count+=1)
	# Match the parent helper's route/restart intent, but never move or reset a
	# save here: every P03 route uses a distinct supervisor-owned directory.
	var has_existing=startup_files.primary!="missing" or startup_files.backup!="missing"
	expect(has_existing==restore_existing,"startup files match the new-route or real-restart stage")
	if not failures.is_empty(): return
	await frames(6)
	await screenshot(mode+"-initial-viewport")
	expect(ui.game.view().has("progression"),"restaurant core v2 exposes progression")
	expect(ui.size==Vector2(size),"viewport uses requested dimensions")

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
			touch.index=0; touch.position=at; touch.pressed=true; emit_input(touch)
			for j in range(1,7):
				var drag=InputEventScreenDrag.new()
				drag.index=0; drag.position=at-Vector2(0,direction*j*20); drag.relative=Vector2(0,-direction*20)
				emit_input(drag); await frames(1)
			# Hold before lifting to end the gesture without a kinetic fling.
			# Otherwise the button can move between its measured rect and tap.
			await create_timer(0.25,true,false,true).timeout
			touch=InputEventScreenTouch.new()
			touch.index=0; touch.position=at-Vector2(0,direction*120); touch.pressed=false; emit_input(touch)
		else:
			var motion=InputEventMouseMotion.new(); motion.position=clip.get_center(); motion.global_position=motion.position; emit_input(motion)
			var wheel=InputEventMouseButton.new()
			wheel.position=clip.get_center(); wheel.global_position=wheel.position
			wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN if direction>0 else MOUSE_BUTTON_WHEEL_UP
			wheel.pressed=true; emit_input(wheel)
			var release=InputEventMouseButton.new()
			release.position=wheel.position; release.global_position=wheel.global_position
			release.button_index=wheel.button_index; release.pressed=false; emit_input(release)
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
		expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect),"target on viewport: "+id)
		if mode=="mouse":
			var motion=InputEventMouseMotion.new()
			motion.position=rect.get_center(); motion.global_position=motion.position
			emit_input(motion); await frames(1)
		for down in [true,false]:
			trace.append({"control_input":id,"pressed":down,"at":str(rect.get_center()),"current_rect":str(button.get_global_rect()),"scroll_vertical":ui.scroll.scroll_vertical})
			if mode=="touch":
				var event=InputEventScreenTouch.new()
				event.index=0; event.position=rect.get_center(); event.pressed=down
				emit_input(event)
			else:
				var event=InputEventMouseButton.new()
				event.position=rect.get_center(); event.global_position=event.position
				event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down
				event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
				emit_input(event)
			await frames(1)
	await frames(3)
	var economic=id=="primary" or id.begins_with("buy_") or id.begins_with("craft_") or id.begins_with("display_") or id.begins_with("fulfill_") or id.begins_with("upgrade_") or id.begins_with("equip_") or id in ["install_cauldron","sell_cauldron","consume_pie","start_expedition"]
	if economic and action_count==count_before: await screenshot(mode+"-intent-failure-"+id)
	if economic: expect(action_count>count_before,"real control emits expected economic intent: "+id)
	if action_count>count_before: expect(last_result.get("ok",false),"command result: "+id+" "+str(last_result.get("message","")))
	var v: Dictionary=ui.game.view()
	if id.begins_with("tab_"): expect(ui.tab==id.trim_prefix("tab_"),"tab input actually selects "+id)
	if id.begins_with("craft_"):
		var output=id.trim_prefix("craft_")
		expect(ui.illustration.effects.any(func(effect): return effect.item_id==output and effect.source=="craft"),"actual cooking triggers matching visual effect: "+output)
		await screenshot(mode+"-actual-craft-"+output)
	trace.append({"mode":mode,"action":id,"day":v.day,"phase":v.phase,"cash":v.cash,"cursor":v.cursor,"clock_ms":v.clock_ms})
	print("P03 INPUT ",mode," ",id," => ",v.day,"/",v.phase)

func quantity(value: int):
	await super.quantity(value)
	expect(ui.batch==value,"real quantity controls select requested batch: "+str(value))

func screenshot(name: String):
	expect(DisplayServer.get_name()!="headless","runtime screenshot requires rendered display")
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var path=folder+"/"+attempt+"-"+name+".png"
	expect(root.get_texture().get_image().save_png(path)==OK,"engine viewport PNG: "+name)
	screenshots.append(path)

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
	var settled: Dictionary=ui.game.snapshot()
	# Repeated confirmation is directed to the disabled page's settlement? The
	# primary now means next-day, so do not mislabel a different action as retry.
	await activate("save")
	await activate("load")
	expect(json_equal(settled,ui.game.snapshot()),"settled restore adds no second fee/reward")

func inject_combat(input: Dictionary):
	var panel=ui.battle_panel
	if mode=="mouse":
		var next={KEY_W:input.move_y < -0.3,KEY_S:input.move_y > 0.3,KEY_A:input.move_x < -0.3,KEY_D:input.move_x > 0.3,KEY_J:input.cast,KEY_K:input.dodge,KEY_L:input.skill}
		for code in next:
			if next[code]!=pressed_keys.get(code,false):
				var e=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=next[code]; emit_input(e)
		pressed_keys=next
		var p: Dictionary=ui.game.view().expedition.player
		var point=(Vector2(p.x,p.y)+Vector2(input.aim_x,input.aim_y)*100.0)/Vector2(960,540)*panel.field.size+panel.field.position
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
			var on: bool=values[kind].length_squared()>0.00001 if values[kind] is Vector2 else values[kind]
			if on and not active_touches.get(index,false):
				var e=InputEventScreenTouch.new(); e.index=index; e.position=centers[kind]; e.pressed=true; emit_input(e,true)
			if on and values[kind] is Vector2:
				var e=InputEventScreenDrag.new(); e.index=index; e.position=centers[kind]+values[kind]*55.0; emit_input(e,true)
			if not on and active_touches.get(index,false):
				var e=InputEventScreenTouch.new(); e.index=index; e.position=centers[kind]; e.pressed=false; emit_input(e,true)
			active_touches[index]=on
			index+=1

func release_combat():
	inject_combat({"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false})
	await frames(2)

func pause_combat():
	if mode=="pad": await pad_button(JOY_BUTTON_START)
	elif mode=="mouse": await key(KEY_ESCAPE,true); await key(KEY_ESCAPE,false)
	else: await activate_control(ui.battle_panel.pause_button,"battle_pause")
	await frames(3)

func battle(day: int, resume: bool = false):
	if not resume:
		await activate("start_expedition")
		expect(ui.game.view().phase=="expedition","real expedition mounted")
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
		iteration+=1
		if iteration==30: await screenshot(mode+"-combat-day"+str(day))
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

func run():
	expect(not config.is_empty(),"supervisor config supplied")
	var size=Vector2i(1280,800) if mode=="mouse" else Vector2i(960,640)
	if config.has("size"): size=Vector2i(config.size[0],config.size[1])
	await fresh(size,stage=="restore-smoke" or stage.begins_with("after-"))
	if not failures.is_empty(): return
	var hot=mode!="touch"
	if stage=="exit-smoke":
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
		for id in ["pause","save","load","quit","primary","tab_gear"]:
			var control=ui.get_action_control(id)
			expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(control.get_global_rect()),"narrow viewport contains "+id)
		expect(ui.scroll.size.y>=96,"narrow layout leaves usable scroll height")
		await activate("tab_gear"); await activate("start_expedition")
		if not failures.is_empty(): return
		await screenshot(mode+"-narrow-combat")
		for control in [ui.battle_panel.pause_button,ui.battle_panel.save_button,ui.battle_panel.return_button]:
			expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(control.get_global_rect()),"narrow combat button on screen: "+control.text)
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
	var file=FileAccess.open(folder+"/"+attempt+"-report.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  ")); file.close()
