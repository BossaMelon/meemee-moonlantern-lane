extends "res://tests/runtime/critical_path.gd"
## P06: actual published Main, default profile, real wall-clock InputEvent path.
const Controls = preload("res://tests/runtime/quality_controls.gd")
const RainDriver = preload("res://tests/expedition/rain_driver.gd")
const DEFAULT_SAVE = "user://profiles/rain-night-v1/moonlantern.json"
const RAIN_STATIC_ASSETS = ["rain_ground_routes","rain_canal_shallow","garden_root_log_50","garden_root_log_45"]
const RESTORES = {"after-spore":"spore-warning","after-intermission":"intermission","after-delivery":"delivery-in-flight","after-upgrade":"upgrade-pending","after-equipped":"next-morning-equipped"}
var component_observations: Array=[]
var default_profile: Dictionary={}
var last_touch_positions: Dictionary={}
var rain_visual_samples: Array=[]

func emit_input(event: InputEvent, local: bool=false):
	if event is InputEventScreenTouch or event is InputEventScreenDrag: last_touch_positions[event.index]=event.position
	super.emit_input(event,local)

func release_combat():
	if is_instance_valid(ui.battle_panel):
		await super.release_combat()
	else:
		# Main removes the combat panel on a normal return. Release the physical
		# devices using the positions actually emitted before removal; no aim
		# geometry, focus grab, command, or replay of held inputs is needed.
		for code in pressed_keys:
			if pressed_keys[code]:
				var event=InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=false; emit_input(event)
			pressed_keys[code]=false
		for axis in pad_axes:
			if pad_axes[axis]!=0.0:
				var event=InputEventJoypadMotion.new(); event.axis=axis; event.axis_value=0.0; emit_input(event)
			pad_axes[axis]=0.0
		for button in pad_buttons:
			if pad_buttons[button]:
				var event=InputEventJoypadButton.new(); event.button_index=button; event.pressed=false; emit_input(event)
			pad_buttons[button]=false
		for index in active_touches:
			if active_touches[index]:
				expect(last_touch_positions.has(index),"return release retains the last emitted touch position")
				var event=InputEventScreenTouch.new(); event.index=index; event.position=last_touch_positions[index]; event.pressed=false; emit_input(event,true)
			active_touches[index]=false
		await frames(2)
	var held: Dictionary=ui.game.snapshot().expedition.input
	expect(json_equal(held,{"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false}),"actual combat input is fully released at pause/return boundary")

func screenshot(name: String):
	if config.get("headless_diagnostic",false): return
	await super.screenshot(name)
	if visual_evidence.get("active_scene")=="expedition":
		var sample=visual_evidence.duplicate(true)
		sample.capture_name=name
		rain_visual_samples.append(sample)

func configure_save_path():
	default_profile={"save_path":ui.save_path,"user_dir":OS.get_user_data_dir(),"absolute_save":ProjectSettings.globalize_path(ui.save_path),"custom_user_dir_name":ProjectSettings.get_setting("application/config/custom_user_dir_name")}
	expect(default_profile.save_path==DEFAULT_SAVE,"product retains its unassigned rain-night default save path")
	expect(default_profile.user_dir==config.get("expected_user_dir","") and default_profile.custom_user_dir_name==config.get("expected_custom_dir",""),"actual isolated OS user directory matches supervisor probe")
	expect(default_profile.absolute_save==config.get("expected_save_path",""),"product default resolves to the independently observed isolated path")

func is_economic_control(id: String) -> bool:
	return super.is_economic_control(id) or id in ["start_wave","next_morning","menu_priority_apply","consume_star_soup","special_decline"] or id.begins_with("recycle_") or id.begins_with("price_")

func is_presentation_control(id: String) -> bool:
	return super.is_presentation_control(id) or id.begins_with("priority_up_") or id.begins_with("priority_down_") or id.begins_with("select_") or id in ["inventory_details_toggle","rare_keep"] or id.begins_with("rare_cook_")

func activate(id: String):
	if id in ["start_wave"]: await open_sheet("counter")
	elif id=="next_morning": await open_sheet("journal")
	elif id=="consume_star_soup": await open_sheet("gear")
	elif id.begins_with("recycle_") or id.begins_with("rare_"): await open_sheet("storage")
	else:
		await super.activate(id)
		return
	if failures.is_empty(): await activate_visible(id)

func observe_component(section: String):
	var observed=Controls.observe(ui,section,ui.game.view(),ui.selected_item if section=="menu" else "")
	component_observations.append(observed)
	expect(observed.errors.is_empty(),"published "+section+" controls reflect actual view: "+str(observed.errors))

func inspect_visible_assets() -> Dictionary:
	var evidence=super.inspect_visible_assets()
	if evidence.active_scene=="expedition":
		var rendered: Dictionary={}
		for id in ui.battle_panel.textures:
			var texture=ui.battle_panel.textures[id]
			if texture is Texture2D and texture.get_width()>0 and texture.get_height()>0: rendered[id]=[texture.get_width(),texture.get_height()]
		evidence.rendered_textures=rendered
		var state: Dictionary=ui.battle_panel.state
		evidence.rain_static_required=RAIN_STATIC_ASSETS
		evidence.rain_static_loaded=RAIN_STATIC_ASSETS.all(func(id): return rendered.has(id))
		evidence.tick=state.tick
		evidence.player=state.player.duplicate(true)
		evidence.terrain=state.terrain.duplicate(true)
		evidence.collision_records=state.collision_records.duplicate(true)
		evidence.hazards=state.hazards.duplicate(true)
		evidence.spore_poses=[]
		for actor in state.enemies:
			if actor.hp<=0 or actor.kind!="sporecaster": continue
			var id="sporecaster_windup" if actor.state=="spore_windup" else ("sporecaster_release" if actor.state=="spore_release" else "sporecaster_idle")
			evidence.spore_poses.append({"actor_id":actor.id,"state":actor.state,"texture_id":id,"loaded":rendered.has(id)})
		# 345a904 draws water only at moving actors; no ambient grid is assumed.
		var ripples=ui.battle_panel.get("_water_ripples") if ui.battle_panel.get_property_list().any(func(property): return property.name=="_water_ripples") else []
		evidence.water_ripples=ripples.duplicate(true)
		evidence.water_effect_loaded=rendered.has("water_ripple") if not ripples.is_empty() else null
		evidence.active_spore_loaded=rendered.has("spore_cloud") if state.hazards.any(func(h): return h.state=="active") else null
		evidence.stump_visuals=[]
		if ui.battle_panel.has_method("_stump_visual"):
			for obstacle in state.terrain.obstacles:
				var visual: Dictionary=ui.battle_panel._stump_visual(obstacle) # Read the renderer's geometry only.
				evidence.stump_visuals.append({"model":obstacle,"texture_id":visual.id,"foot":[visual.position.x,visual.position.y],"scale":visual.scale,"pivot":ui.battle_panel.manifest.sprites[visual.id].pivot})
		evidence.active_assets_loaded=evidence.active_assets_loaded and evidence.rain_static_loaded and evidence.spore_poses.all(func(pose): return pose.loaded) and evidence.water_effect_loaded!=false and evidence.active_spore_loaded!=false
	return evidence

func observe_dynamic_rain(s: Dictionary, seen: Dictionary):
	# The headless diagnostic makes no render/cache claim and skips this path.
	if verification_kind!="rendered_runtime": return
	var player=Vector2(s.player.x,s.player.y)
	var in_water=s.terrain.water_zones.any(func(water): return Rect2(Vector2(water.x,water.y)-Vector2(water.width,water.height)*0.5,Vector2(water.width,water.height)).has_point(player))
	var ripples=ui.battle_panel.get("_water_ripples") if ui.battle_panel.get_property_list().any(func(property): return property.name=="_water_ripples") else []
	var player_ripple=ripples.any(func(ripple): return Vector2(ripple.x,ripple.y).distance_to(player)<30)
	if not seen.get("visual_water",false) and in_water and player_ripple:
		await screenshot(mode+"-rain-actual-wading-day%d"%s.day)
		expect(not visual_evidence.water_ripples.is_empty() and visual_evidence.water_effect_loaded==true,"real moving-water checkpoint draws its ripple texture")
		seen.visual_water=true
	if not seen.get("visual_spore",false) and s.hazards.any(func(h): return h.state=="active"):
		await screenshot(mode+"-rain-active-spore-day%d"%s.day)
		expect(visual_evidence.active_spore_loaded==true,"real active spore checkpoint draws its cloud texture")
		seen.visual_spore=true
	if not seen.get("visual_collision",false) and not s.collision_records.is_empty():
		await screenshot(mode+"-rain-obstacle-collision-day%d"%s.day)
		expect(not visual_evidence.stump_visuals.is_empty(),"actual collision snapshot includes model obstacles and drawn stump geometry")
		seen.visual_collision=true

func buy_missing(needed: Dictionary):
	await open_sheet("shopping")
	var v: Dictionary=ui.game.view()
	var cost=0
	for id in needed:
		var missing=maxi(0,int(needed[id])-int(inventory(id).bag))
		var supply=v.supply.filter(func(row): return row.item_id==id)
		expect(supply.size()==1 and int(supply[0].quantity)>=missing,"published supply covers planned ingredients: "+id)
		if not failures.is_empty(): return
		cost+=missing*int(supply[0].buy)
	expect(v.cash>=cost,"actual cash covers the complete planned basket before purchases")
	if not failures.is_empty(): return
	trace.append({"basket":needed,"cost":cost,"cash_before":v.cash,"supply":v.supply})
	for id in needed:
		var missing=maxi(0,int(needed[id])-int(inventory(id).bag))
		if missing>0:
			await quantity(missing); await activate("buy_"+id)

func craft_display(id: String, count: int):
	await open_sheet("craft"); await quantity(count); await activate("craft_"+id)
	await open_sheet("shelf"); await activate("select_"+id); await quantity(count)
	await activate("display_"+id); await activate("price_premium")

func prepare_night():
	expect(inventory("sparkcap").bag>=2 and inventory("moonheart").bag>=1,"real combat supplies recyclable, retained and advanced ingredients")
	await activate("recycle_sparkcap")
	observe_component("rare")
	# One real harvested moonheart replaces one pot portion with an advanced
	# dish. Keep the published hot-meal raw basket, add its actual flour input.
	var fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/quality-slice-scenarios.json"))
	var needed: Dictionary={}
	for row in fixtures.configuration.upgrade_restock_tradeoff.baseline_baskets.hot_meals.buys: needed[row.item_id]=row.quantity
	for recipe in ui.game.view().recipes:
		if recipe.output=="comet_pie":
			for id in recipe.inputs:
				if id not in ["moonheart","pumpkin"]: needed[id]=int(recipe.inputs[id])
	await buy_missing(needed)
	await activate("primary")
	await activate("install_cauldron")
	await craft_display("moon_stew",6)
	await craft_display("comet_pie",1)
	var before: Dictionary=ui.game.snapshot()
	var priority: Array=before.service.menu_priority.duplicate()
	expect(priority.size()==2,"actual advanced dish creates a second menu choice")
	await activate_visible("priority_up_"+str(priority[1]))
	expect(json_equal(before,ui.game.snapshot()),"priority draft does not mutate economy or schedule")
	await activate_visible("menu_priority_apply")
	priority.reverse()
	expect(ui.game.view().service.menu_priority==priority,"one apply commits the complete reordered menu")
	observe_component("menu")
	await screenshot(mode+"-rain-menu-priority")
	await activate("primary")
	expect(ui.game.view().phase=="trading","actual counter opens first service wave")

func wait_wave(expected_phase: String):
	var deadline=Time.get_ticks_msec()+60000
	while ui.game.view().phase=="trading" and Time.get_ticks_msec()<deadline:
		if not ui.game.view().pending.is_empty(): await activate("special_decline")
		await process_frame
	expect(ui.game.view().phase==expected_phase,"real wall-clock service reaches "+expected_phase)
	if not failures.is_empty(): return
	var snapshot: Dictionary=ui.game.snapshot()
	expect(snapshot.service.reservations.is_empty(),"wave boundary drains in-flight reservations")
	var wave=int(snapshot.service.wave_index)
	var rows=snapshot.sales.filter(func(row): return row.get("wave_id")==snapshot.service.wave_id)
	battle_observed["wave_%d"%wave]={"sales":rows,"held_uids":snapshot.service.held_uids.duplicate(),"elapsed_ms":snapshot.service.elapsed_ms}
	expect(not rows.is_empty(),"completed wave has actual customer outcomes")
	await create_timer(0.35,true,false,true).timeout
	expect(json_equal(snapshot,ui.game.snapshot()),"true wave boundary freezes the complete state without forced waiting")
	await open_sheet("counter"); observe_component("service")
	await screenshot(mode+"-rain-wave-%d"%wave)
	await close_sheet()

func verify_delivery():
	var saved=battle_observed.get("reserved",[])
	expect(not saved.is_empty(),"restart carries observed in-flight UID/order evidence")
	var snapshot: Dictionary=ui.game.snapshot()
	for row in saved:
		var sales=snapshot.sales.filter(func(sale): return sale.get("uid")==row.item_uid and sale.order_id==row.order_id)
		expect(sales.size()==1,"same reserved UID is delivered exactly once: "+str(row.item_uid))
		expect(not snapshot.items.any(func(item): return item.uid==row.item_uid),"delivered UID leaves inventory exactly once")
		pickup_proofs.append({"kind":"reservation_delivery","reservation":row,"sales":sales})

func combat_checkpoint():
	await release_combat(); await pause_combat()
	expect(ui.game.view().paused,"real pause freezes spore warning")
	var frozen: Dictionary=ui.game.snapshot()
	expect(frozen.expedition.hazards.any(func(h): return h.state=="warning"),"saved combat boundary still contains a real spore warning")
	await create_timer(0.5,true,false,true).timeout
	expect(json_equal(frozen,ui.game.snapshot()),"paused warning/cooldowns do not advance with wall time")
	await activate_control(ui.battle_panel.save_button,"battle_save")
	expect(json_equal(frozen,ui.game.snapshot()),"pause GUI pointer/A input cannot cast or alter combat state")
	await screenshot(mode+"-rain-spore-warning")
	await expect_product_exit("spore-warning",ui.battle_panel.save_quit_button)

func verify_rain_pickups():
	var snapshot: Dictionary=ui.game.snapshot()
	for key in snapshot.collected_drops:
		var drop=snapshot.collected_drops[key]
		if drop.run_id!=snapshot.expedition.run_id: continue
		var occurrences=0
		for row in snapshot.ledger:
			if row.kind=="pickup" and row.args.run_id==drop.run_id:
				for pickup in row.args.pickups:
					if pickup.drop_id==drop.drop_id: occurrences+=1
		expect(occurrences==1 and drop.uids.size()==drop.quantity,"real rain drop has one ledger entry and exact issued UID count")
		for uid in drop.uids: expect(snapshot.items.filter(func(item): return item.uid==uid and item.item_id==drop.item_id).size()==1,"unspent harvested UID occurs once")
		pickup_proofs.append({"key":key,"identity":drop,"ledger_occurrences":occurrences})

func rain_battle(day: int, resume: bool=false):
	if resume:
		await pause_combat()
		expect(not ui.game.view().paused,"real combat pause input resumes restored run")
	else: await activate("start_expedition")
	if not failures.is_empty(): return
	expect(ui.game.view().phase=="expedition","actual Main mounts rain-garden combat")
	var initial: Dictionary=ui.game.view().expedition
	expect(initial.map_id=="rain-garden-two-routes" and initial.version==2,"actual model uses frozen rain-garden map/version")
	if day==2:
		expect(initial.weapon_id=="fan_wand","next morning enters a normal expedition with the paid weapon")
		expect(initial.meal_effect!=null and initial.meal_effect.source_item_uid==battle_observed.get("meal_uid"),"new run atomically receives the real consumed dish UID")
	var seen: Dictionary=battle_observed.get("combat_%d"%day,{"movement":false,"cast":false,"dodge":false,"skill":false,"warning":false,"active_spore":false,"fan_projectiles":false,"routes":[],"events":[]})
	var driver=RainDriver.new("canal" if mode=="touch" else "shelf",true,true)
	ui.battle_panel.action_events.connect(func(events):
		action_events.append_array(events)
		for event in events:
			if event.get("type","") not in seen.events: seen.events.append(event.get("type",""))
	)
	var deadline=Time.get_ticks_msec()+240000
	var iteration=0
	while ui.game.view().phase=="expedition" and Time.get_ticks_msec()<deadline:
		var s: Dictionary=ui.game.view().expedition
		seen.movement=seen.movement or Vector2(s.player.x,s.player.y).distance_to(Vector2(initial.player.x,initial.player.y))>10
		for action in ["cast","dodge","skill"]: seen[action]=seen[action] or s.player[action+"_cooldown_ms"]>0
		seen.warning=seen.warning or s.hazards.any(func(h): return h.state=="warning")
		seen.active_spore=seen.active_spore or s.hazards.any(func(h): return h.state=="active")
		seen.fan_projectiles=seen.fan_projectiles or (s.weapon_id=="fan_wand" and s.projectiles.size()>=3)
		for node in s.resource_nodes:
			if node.get("collected",false) and node.id not in seen.routes: seen.routes.append(node.id)
		battle_observed["combat_%d"%day]=seen
		await observe_dynamic_rain(s,seen)
		if day==1 and stage=="start" and s.hazards.any(func(h): return h.state=="warning"):
			await combat_checkpoint(); return
		var input: Dictionary=driver.next_input(s)
		# Exercise the real dodge input; policy still walks/aims/casts normally.
		if iteration>=3 and iteration<8: input.dodge=true
		inject_combat(input)
		await process_frame
		observe_combat_input(input)
		iteration+=1
		if iteration==30:
			expect(ui.battle_panel.input_mode=={"mouse":"keyboard","pad":"gamepad","touch":"touch"}[mode],"device InputEvents select the actual matching combat HUD")
			await screenshot(mode+"-rain-combat-day%d"%day)
	# Release through the same public input path, including the return boundary.
	await release_combat()
	expect(ui.game.view().phase=="shopping","normal terrain driver returns to the restaurant within deadline")
	if not failures.is_empty(): return
	for action in ["movement","cast","dodge","skill","warning","active_spore"]: expect(seen[action],"observed real rain combat action: "+action)
	if verification_kind=="rendered_runtime":
		for kind in ["visual_water","visual_spore","visual_collision"]: expect(seen.get(kind,false),"actual rain drawing checkpoint was captured: "+kind)
	if day==2: expect(seen.fan_projectiles,"acquired fan wand visibly produces multiple actual projectiles")
	verify_rain_pickups()
	await frames(5)

func resume_restaurant():
	await activate("resume")
	expect(not ui.game.view().paused,"restored restaurant resumes through real pause control")

func run():
	if config.get("headless_diagnostic",false): verification_kind="headless_navigation"
	expect(stage=="start" or RESTORES.has(stage),"known rain-night restart stage")
	if not failures.is_empty(): return
	var dimensions=config.get("size",[1280,800])
	await fresh(Vector2i(int(dimensions[0]),int(dimensions[1])),stage!="start")
	if not failures.is_empty(): return
	var initial: Dictionary=ui.game.snapshot()
	expect(initial.version==3 and initial.profile_id=="rain-night-v1","default Main creates or restores actual rain-night v3")
	if stage!="start":
		await restore(RESTORES[stage])
		if not failures.is_empty(): return
	match stage:
		"start":
			await open_sheet("journal"); observe_component("forecast")
			await screenshot(mode+"-rain-forecast")
			await rain_battle(1)
		"after-spore":
			await rain_battle(1,true)
			await prepare_night(); await wait_wave("intermission")
			expect(ui.game.view().service.held_uids.size()==3,"first wave actually retains three warm pot portions")
			await save_and_exit("intermission")
		"after-intermission":
			await resume_restaurant()
			await craft_display("moon_stew",3)
			await activate("start_wave")
			await open_sheet("counter"); observe_component("service")
			await screenshot(mode+"-rain-in-flight-service")
			await open_sheet("pause")
			battle_observed.reserved=ui.game.snapshot().service.reservations.duplicate(true)
			expect(not battle_observed.reserved.is_empty(),"real wave2 has in-flight delivery UIDs at pause")
			await save_and_exit("delivery-in-flight")
		"after-delivery":
			await resume_restaurant(); await wait_wave("intermission"); verify_delivery()
			await craft_display("moon_stew",2); await activate("start_wave")
			await wait_wave("closing"); await activate("primary")
			await open_sheet("journal"); observe_component("growth")
			var v: Dictionary=ui.game.view()
			var upgrade=v.upgrades.filter(func(row): return row.upgrade_id=="field_kit")[0]
			battle_observed.upgrade={"cost":upgrade.cost,"cash_before":v.cash,"dish_income":v.dish_income,"summary":v.summary}
			expect(upgrade.available,"actual dish revenue and cash unlock the published field kit price")
			await activate("upgrade_field_kit")
			expect("fan_wand" in ui.game.view().progression.pending_unlocks and "fan_wand" not in ui.game.view().progression.owned_weapons,"paid upgrade waits for legal next morning")
			await save_and_exit("upgrade-pending")
		"after-upgrade":
			await resume_restaurant(); await activate("next_morning")
			expect(ui.game.view().day==2 and ui.game.view().phase=="shopping","one legal next_day reaches morning shopping")
			await activate("equip_fan_wand")
			var needed: Dictionary={}
			for recipe in ui.game.view().recipes:
				if recipe.output=="star_soup":
					for id in recipe.inputs:
						if id!="sparkcap": needed[id]=recipe.inputs[id]
			await buy_missing(needed)
			await open_sheet("craft"); await quantity(1); await activate("craft_star_soup")
			await activate("consume_star_soup"); observe_component("meal")
			battle_observed.meal_uid=ui.game.snapshot().pending_meal_effect.source_item_uid
			await save_and_exit("next-morning-equipped")
		"after-equipped":
			await resume_restaurant(); await rain_battle(2)
			for wave in [1,2,3]: expect(battle_observed.has("wave_%d"%wave),"three actual service waves persisted in evidence")
			await screenshot(mode+"-rain-next-morning-trial-complete")
			record_checkpoint("complete"); quit(0 if failures.is_empty() else 1)

func write_report():
	super.write_report()
	var path=folder+"/"+attempt+"-report.json"
	var report=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not report is Dictionary: return
	report.suite="p06-rain-night-main-scene-runtime"
	report.default_profile=default_profile
	report.component_observations=component_observations
	report.rain_visual_samples=rain_visual_samples
	report.human_status="not_assessed"
	report.Q06_status="pending_combined_native_modes_layout_and_focus_evidence"
	report.simulation_scale=Engine.time_scale
	for source in ["tests/runtime/rain_night_path.gd","tests/runtime/quality_controls.gd","game/ui/rain_night/panels.gd","game/core/rain_night_session.gd","tests/expedition/rain_driver.gd"]: report.source_sha256[source]=FileAccess.get_sha256("res://"+source)
	var file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
