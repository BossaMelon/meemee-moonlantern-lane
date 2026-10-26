extends "res://tests/core/quality_expedition_cases.gd"
const Driver = preload("res://tests/expedition/rain_driver.gd")
var cases: Array = []
var simulations: Array = []
var report_dir = ""
var seeds: Array = []
var battle_origin: Dictionary = {}
var last_settled: Dictionary = {}
var configuration: Dictionary = {}

func run_case(id: String, callback: Callable):
	checks = 0; failures = []; traces = []; observed = []
	callback.call()
	var row = {"id":id,"status":"passed" if failures.is_empty() and checks > 0 else "failed","checks":checks,"failures":failures.duplicate(),"traces":traces.duplicate(true)}
	cases.append(row); print("%s: %s (%d checks)" % [id,row.status,checks])

func component(script: String, label: String):
	var output = []
	var exit_code = OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",report_dir+"/"+label+".log","--script",script],output,true)
	var text = "\n".join(output)
	var regex = RegEx.new(); regex.compile("([0-9]+) checks, ([0-9]+) failures")
	var summary = regex.search(text)
	expect(exit_code == 0 and summary != null and summary.get_string(2) == "0" and "SCRIPT ERROR" not in text and "ERROR:" not in text,"actual "+label+" process completes its assertions: "+text.right(1500))
	if summary != null: checks += int(summary.get_string(1))
	traces.append({"component":script,"exit_code":exit_code,"output":text})

func test_map_case():
	component("res://tests/expedition/run_geometry.gd","geometry")
	test_real_routes_and_isolation()

func save_continue_at(g, label: String):
	clear_input(g); var restored = roundtrip(g,label)
	return {"game":restored,"label":label}

func drive(g, route: String, deep: bool = false):
	var driver = Driver.new(route,deep,deep); var captured = {}; var combined = false; var events = []; var track = []; var restored_branches = []
	for i in range(3600):
		if g.view().phase != "expedition": break
		var input = driver.next_input(g.snapshot().expedition)
		var result = step(g,input)
		for branch in restored_branches:
			step(branch.game,input)
			expect(g.snapshot() == branch.game.snapshot(),"actual "+branch.label+" full Session continuation matches after disk restore")
		restored_branches = []
		events.append_array(result.events)
		var state = g.snapshot().expedition
		if i%20 == 0: track.append({"tick":state.tick,"player":state.player.duplicate(true)})
		if deep:
			for hazard in state.hazards:
				if hazard.source != "deep-caster" or state.enemies[3].hp <= 0 or not state.enemies[3].engaged: continue
				if hazard.state == "active": combined = true
				if not captured.has(hazard.state): captured[hazard.state] = true; restored_branches.append(save_continue_at(g,"combined-"+hazard.state))
			if state.enemies[3].state == "stagger" and not captured.has("stagger"): captured.stagger = true; restored_branches.append(save_continue_at(g,"elite-stagger"))
	var end = g.snapshot().expedition
	expect(end.status == "returned" and end.return_reason == "entrance" and end.player.hp > 0,"normal "+route+" driver returns alive through real entrance")
	if deep:
		expect(combined,"actual deep caster zone coexists with living engaged shield elite")
		expect(events.any(func(e): return e.type == "spore_cleared" and e.source == "deep-caster"),"actual gust clears deep caster zone")
		expect(g.snapshot().collected_drops.values().any(func(d): return d.item_id == "moonheart"),"actual elite defeat grants core a real moonheart UID")
	traces.append({"scenario":"normal-input-route","route":route,"deep":deep,"events":events,"track":track,"snapshot":g.snapshot()})

func cook(g, id: String, count: int):
	if count == 0: return
	act(g,"craft",{"recipe_id":id,"quantity":count}); act(g,"display",{"item_id":id,"quantity":count})

func basket(g, route: String):
	var recipe = configuration.upgrade_restock_tradeoff.baseline_baskets["hot_meals" if route == "heat" else "quick_service"]
	for purchase in recipe.buys: act(g,"buy",{"item_id":purchase.item_id,"quantity":int(purchase.quantity)})

func normal_night(seed_value: int, route: String, explore: bool = false, tier: String = "standard"):
	var g = Session.new(seed_value,"rain-night-v1")
	if explore:
		act(g,"start_expedition"); drive(g,"shelf" if route == "quick" else "canal")
	if route == "quick": act(g,"recycle",{"item_id":"stirring_cauldron","quantity":1})
	basket(g,route); act(g,"finish_shopping")
	if route == "heat": act(g,"install",{"uid":1})
	for id in (["moon_stew"] if route == "heat" else ["floating_pie","ember_soup"]): act(g,"price",{"item_id":id,"tier":tier})
	var service_ms = 0; var wave_records = []
	for wave in range(3):
		if route == "heat": cook(g,"moon_stew",[6,3,3][wave])
		else:
			cook(g,"floating_pie",[5,3,0][wave]); cook(g,"ember_soup",[3,0,1][wave])
		if wave == 0: act(g,"open_shop")
		else: act(g,"start_wave",{"wave_id":g.snapshot().service.next_wave_id})
		advance_wave(g); service_ms += g.snapshot().service.elapsed_ms
		var sales = g.snapshot().sales.filter(func(row): return row.get("wave_id") == "n1-w%d" % (wave+1))
		var revenue = 0; var cost = 0; var served = 0; var left_reasons = {}
		for sale in sales:
			revenue += int(sale.revenue); cost += int(sale.cost)
			if sale.revenue > 0: served += 1
			else:
				for reason in sale.reasons: left_reasons[reason] = left_reasons.get(reason,0)+1
		wave_records.append({"wave_id":g.snapshot().service.wave_id,"served":served,"left":sales.size()-served,"left_reasons":left_reasons,"revenue":revenue,"sold_cost":cost,"gross_profit":revenue-cost,"cash":g.view().cash,"elapsed_ms":g.snapshot().service.elapsed_ms,"remaining_items":g.snapshot().items,"held_uids":g.snapshot().service.held_uids,"sales":sales})
		if route == "heat" and wave == 0: expect(g.snapshot().service.held_uids.size() == 3,"normal hot route carries three actual held meals into patrol wave")
	act(g,"settle")
	last_settled = g.snapshot()
	var upgrade_cost = g.view().upgrades.filter(func(u): return u.upgrade_id == "field_kit")[0].cost
	expect(g.view().cash >= upgrade_cost+(60 if route == "heat" else 64),"normal route can invest and fully restock without emergency work")
	expect(g.snapshot().ledger.all(func(row): return row.kind != "recover"),"normal route never depends on emergency income")
	var summary = {"seed":seed_value,"strategy":route,"tier":tier,"explored":explore,"cash_before_upgrade":g.view().cash,"summary":g.view().summary,"service_ms":service_ms,"waves":wave_records,"remaining_items":g.snapshot().items,"ledger":g.snapshot().ledger,"upgrade_spending":upgrade_cost}
	act(g,"upgrade",{"upgrade_id":"field_kit"},"earned-kit")
	summary.cash_after_upgrade = g.view().cash
	expect(g.snapshot().progression.pending_unlocks == ["fan_wand"] and "fan_wand" not in g.snapshot().progression.owned_weapons,"paid kit is pending until normal next day")
	var paid = roundtrip(g,"paid-upgrade")
	act(g,"next_day"); act(paid,"next_day"); expect(g.snapshot() == paid.snapshot(),"next day after purchased upgrade matches saved branch")
	act(g,"equip_weapon",{"weapon_id":"fan_wand"}); var equipped = roundtrip(g,"equipped-next-morning")
	basket(g,route); basket(equipped,route); expect(g.snapshot() == equipped.snapshot(),"normal morning equip and full restock survive disk restore")
	summary.cash_after_upgrade_restock = g.view().cash; simulations.append(summary)
	return g

func test_combat_case():
	component("res://tests/expedition/run_rain_model.gd","rain-model-components")
	for seed_value in seeds:
		var g = Session.new(int(seed_value)); act(g,"start_expedition"); drive(g,"shelf",true)
		if battle_origin.is_empty(): battle_origin = g.snapshot()
		g = normal_night(int(seed_value),"heat")
		act(g,"start_expedition"); expect(g.snapshot().expedition.weapon_id == "fan_wand","deep fan route uses legitimately earned weapon")
		drive(g,"canal",true)

func test_growth_case():
	test_meal_transfer()
	if battle_origin.is_empty():
		var acquired = Session.new(1,"rain-night-v1"); act(acquired,"start_expedition"); drive(acquired,"shelf",true); battle_origin = acquired.snapshot()
	var origin = fixture(battle_origin,"real-combat-rare-origin")
	test_rare_four_uses(origin)
	var heart = fixture(battle_origin,"real-moonheart-sale"); var cash = heart.view().cash
	act(heart,"recycle",{"item_id":"moonheart","quantity":1})
	expect(heart.view().cash == cash+8 and heart.view().dish_income == 0,"real elite moonheart sells for fixed8 without dish income")
	reject(heart,"recycle",{"item_id":"unknown","quantity":1}); reject(heart,"recycle",{"item_id":"moonheart","quantity":80})
	var g = normal_night(7,"quick")
	act(g,"start_expedition",{},"morning-formal")
	expect(g.snapshot().expedition.version == 2 and g.snapshot().expedition.day == 2 and g.snapshot().expedition.weapon_id == "fan_wand","actual revenue unlocks next-day equipped fan in formal quality expedition")
	var result = step(g,{"aim_x":1.0,"cast":true})
	expect(result.events.any(func(e): return e.type == "cast" and e.weapon_id == "fan_wand" and e.projectile_count == 3),"earned fan actually changes cast to three projectiles")
	traces.append({"scenario":"earned-next-day-fan","actions":g.action_trace(),"snapshot":g.snapshot()})

func test_correctness_case():
	for seed_value in seeds:
		for route in ["quick","heat"]:
			for tier in ["standard","premium"]:
				var g = normal_night(int(seed_value),route,true,tier)
				test_actual_double_investment(last_settled,route,tier,true)
				act(g,"start_expedition"); clear_input(g); var restored = roundtrip(g,"five-seed-start")
				act(g,"expedition_input",{"move_y":-1.0,"cast":true,"aim_x":1.0}); act(restored,"expedition_input",{"move_y":-1.0,"cast":true,"aim_x":1.0})
				act(g,"advance",{"delta_ms":1237})
				for ms in [13,41,89,7,1087]: act(restored,"advance",{"delta_ms":ms})
				expect(g.snapshot() == restored.snapshot(),"five-seed complete Session is invariant to frame partition and restore")
				act(g,"leave_expedition"); reject(g,"start_expedition")
				var no_expedition = normal_night(int(seed_value),route,false,tier)
				test_actual_double_investment(last_settled,route,tier,false)
				expect(no_expedition.snapshot().expedition_attempts.is_empty(),"explicit no-expedition branch can invest and continue")
				act(no_expedition,"finish_shopping")
				if route == "heat": cook(no_expedition,"moon_stew",3)
				else: cook(no_expedition,"floating_pie",5); cook(no_expedition,"ember_soup",3)
				act(no_expedition,"open_shop"); advance_wave(no_expedition)
				expect(no_expedition.view().day == 2 and no_expedition.view().phase == "intermission","no-expedition branch actually continues second-night service")
	# Real separate OS processes and their user:// directories are checked below.
	test_profile_processes()

func test_actual_double_investment(settled: Dictionary, route: String, tier: String, explored: bool):
	var g = fixture(settled,"actual-double-investment")
	act(g,"upgrade",{"upgrade_id":"field_kit"})
	var second_cost = g.view().upgrades.filter(func(u): return u.upgrade_id == "shelf")[0].cost
	if g.view().cash < second_cost:
		var refused = reject(g,"upgrade",{"upgrade_id":"shelf"})
		expect(refused.code == "insufficient_cash","quick route cannot buy both without sufficient real cash")
		traces.append({"scenario":"second-investment-unaffordable","seed":settled.seed,"strategy":route,"tier":tier,"explored":explored,"cash_after_one":g.view().cash,"result":refused,"ledger":g.snapshot().ledger})
		return
	act(g,"upgrade",{"upgrade_id":"shelf"}); act(g,"next_day")
	var cash_after_two = g.view().cash; var refused: Dictionary = {}
	var full = roundtrip(g,"double-investment-before-basket")
	for purchase in configuration.upgrade_restock_tradeoff.baseline_baskets.hot_meals.buys:
		var unit_cost = preload("res://game/core/catalog.gd").ITEMS[purchase.item_id].buy
		var args = {"item_id":purchase.item_id,"quantity":int(purchase.quantity)}
		if full.view().cash < unit_cost*purchase.quantity:
			refused = reject(full,"buy",args,"over-budget-full-restock"); break
		act(full,"buy",args)
	expect(not refused.is_empty(),"full unchanged baseline basket actually reaches cash guard")
	if refused.is_empty(): return
	expect(refused.code == "insufficient_cash","two paid upgrades make original full basket unaffordable without partial charge")
	var reduced_basket = configuration.upgrade_restock_tradeoff.reduced_hot_baskets[tier]
	for purchase in reduced_basket.buys: act(g,"buy",{"item_id":purchase.item_id,"quantity":int(purchase.quantity)})
	var reduced = g.snapshot().items.filter(func(i): return i.item_id == "pumpkin" and i.location == "bag").size()
	expect(reduced > 0 and reduced < 12,"a deliberately reduced basket remains available")
	act(g,"finish_shopping")
	cook(g,"moon_stew",reduced); act(g,"open_shop"); advance_wave(g)
	act(g,"start_wave",{"wave_id":"n2-w2"}); act(g,"decline",{"order_id":"n2-hagrid-patrol"}); advance_wave(g)
	act(g,"start_wave",{"wave_id":"n2-w3"}); advance_wave(g); act(g,"settle")
	expect(g.view().cash >= 0 and g.snapshot().ledger.all(func(row): return row.kind != "recover"),"compressed next-night stock completes without negative cash or emergency income")
	traces.append({"scenario":"actual-double-investment-restock-choice","seed":settled.seed,"strategy":route,"tier":tier,"explored":explored,"cash_after_two":cash_after_two,"full_basket_refusal":refused,"reduced_meals":reduced,"remaining_items":g.snapshot().items,"ledger":g.snapshot().ledger,"sales":g.snapshot().sales,"summary":g.view().summary})

func copy_tree(source: String, destination: String):
	DirAccess.make_dir_recursive_absolute(destination)
	for file in DirAccess.get_files_at(source):
		if file.ends_with(".gd") or file.ends_with(".uid"): expect(DirAccess.copy_absolute(source.path_join(file),destination.path_join(file)) == OK,"copy bounded test project script")
	for directory in DirAccess.get_directories_at(source): copy_tree(source.path_join(directory),destination.path_join(directory))

func profile_process(project: String, profile: String, mode: String) -> Dictionary:
	var report = project.path_join(mode+"-report.json"); var output = []
	var code = OS.execute(OS.get_executable_path(),["--headless","--path",project,"--log-file",project.path_join(mode+".log"),"--script","res://tests/core/profile_process.gd","--","--profile",profile,"--mode",mode,"--report",report],output,true)
	var result = JSON.parse_string(FileAccess.get_file_as_string(report)) if FileAccess.file_exists(report) else null
	expect(code == 0 and result is Dictionary and result.get("failures",["missing"]).is_empty(),"separate profile process "+mode+": "+"\n".join(output))
	return result if result is Dictionary else {}

func test_profile_processes():
	expect(ProjectSettings.get_setting("application/config/use_custom_user_dir",false) and ProjectSettings.get_setting("application/config/custom_user_dir_name","") == "MeeMeeMoonlanternLane/rain-night-v1","actual new launcher configuration chooses an independent user directory")
	var projects = []
	for profile in ["prototype-v1","rain-night-v1"]:
		var project = output_dir.path_join(profile); projects.append(project)
		copy_tree(ProjectSettings.globalize_path("res://game/core"),project.path_join("game/core"))
		copy_tree(ProjectSettings.globalize_path("res://game/expedition"),project.path_join("game/expedition"))
		DirAccess.make_dir_recursive_absolute(project.path_join("tests/core"))
		expect(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/core/profile_process.gd"),project.path_join("tests/core/profile_process.gd")) == OK,"copy profile entrypoint")
		var config = ConfigFile.new(); config.set_value("","config_version",5)
		config.set_value("application","config/name","Moonlantern acceptance")
		config.set_value("application","config/use_custom_user_dir",true)
		config.set_value("application","config/custom_user_dir_name","MoonlanternAcceptance/%d/%s" % [OS.get_process_id(),profile])
		expect(config.save(project.path_join("project.godot")) == OK,"write isolated profile project")
	var old = profile_process(projects[0],"prototype-v1","write")
	if old.is_empty(): return
	var new = profile_process(projects[1],"rain-night-v1","write")
	var restored = profile_process(projects[1],"rain-night-v1","restore")
	expect(not new.is_empty() and not restored.is_empty() and new.user_dir != old.user_dir,"old and new entrypoints resolve different actual user directories")
	if not new.is_empty() and not restored.is_empty(): expect(new.snapshot == restored.snapshot,"new default path restores full state in another OS process")
	expect(FileAccess.get_sha256(old.save_path) == old.primary_sha256 and FileAccess.get_sha256(old.save_path+".bak") == old.backup_sha256,"new default write/read leaves old primary and backup SHA256 unchanged")
	var old_restored = profile_process(projects[0],"prototype-v1","restore")
	expect(not old_restored.is_empty() and old_restored.snapshot == old.snapshot,"old explicit profile still opens its untouched v2 save")
	traces.append({"scenario":"separate-profile-processes","legacy":old,"quality":new,"quality_restored":restored,"legacy_restored":old_restored})

func run(folder: String, selected: String = "") -> Dictionary:
	report_dir = folder; output_dir = folder+"/quality-%d" % OS.get_process_id(); DirAccess.make_dir_recursive_absolute(output_dir)
	var fixture_data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/quality-slice-scenarios.json"))
	if not fixture_data is Dictionary or not fixture_data.get("seeds") is Array or not fixture_data.seeds.all(func(n): return (n is int or n is float) and n == floor(n)) or fixture_data.seeds.map(func(n): return int(n)) != [1,7,23,99,20261025]:
		return {"schema_version":1,"suite":"quality-slice","cases":[{"id":"Q05","status":"failed","checks":1,"failures":["Missing or mismatched quality fixture seeds"]}]}
	seeds = fixture_data.seeds
	configuration = fixture_data.configuration
	if selected == "" or selected == "Q01": run_case("Q01",test_map_case)
	if selected == "" or selected == "Q02": run_case("Q02",test_combat_case)
	if selected == "" or selected == "Q03": run_case("Q03",func():
		var service = preload("res://tests/core/quality_service_cases.gd").new().run(folder)
		checks += service.checks; failures.append_array(service.failures); traces.append_array(service.traces))
	if selected == "" or selected == "Q04": run_case("Q04",test_growth_case)
	if selected == "" or selected == "Q05": run_case("Q05",test_correctness_case)
	return {"schema_version":1,"suite":"quality-slice","cases":cases,"simulations":simulations}
