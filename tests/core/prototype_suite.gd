extends RefCounted
const Session = preload("res://game/core/game_session.gd")
const Catalog = preload("res://game/core/catalog.gd")
var cases: Array = []
var simulations: Array = []
var traces: Array = []
var failures: Array = []
var checks = 0
var case_id = ""
var serial = 0
var temp_root = ""
var seeds: Array = []

func expect(condition: bool, message: String):
	checks += 1
	if not condition:
		failures.append(message)
		push_error(case_id+": "+message)

func run_case(id: String, test: Callable):
	case_id = id; checks = 0; failures = []
	test.call()
	cases.append({"id":id,"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures.duplicate()})
	print("%s: %s (%d checks)" % [id,cases.back().status,checks])

func audit(g):
	var s = g.snapshot(); var cash = int(s.initial_cash); var counts = {}; var ids = {}; var moves = {}
	for item in s.items:
		expect(not ids.has(item.uid),"unique physical item uid")
		ids[item.uid] = true; counts[item.item_id] = counts.get(item.item_id,0)+1
		expect(item.cost >= 0,"nonnegative acquisition cost")
	for row in s.ledger:
		cash += int(row.cash_delta)
		for id in row.moves: moves[id] = moves.get(id,0)+int(row.moves[id])
	expect(cash == s.cash and cash >= 0,"cash reconstructs from actual ledger")
	for id in Catalog.ITEMS: expect(counts.get(id,0) == moves.get(id,0),"conserved ingredient/dish/device "+id)
	var error = g.validate_snapshot(s)
	expect(error == "","full state validates: "+error)

func act(g, kind: String, args: Dictionary = {}, request: String = "") -> Dictionary:
	serial += 1
	var result = g.command(kind,args,request if request != "" else "restaurant-%d" % serial)
	expect(result.ok,kind+" succeeds: "+str(result)); audit(g)
	return result

func reject(g, kind: String, args: Dictionary = {}, request: String = "") -> Dictionary:
	var before = g.snapshot(); var result = g.command(kind,args,request)
	expect(not result.ok and result.code != "" and result.message != "","explicit rejection "+kind)
	expect(g.snapshot() == before,"atomic rejection including RNG/action/request state: "+kind)
	return result

func count(g, id: String, location: String = "bag") -> int:
	var n = 0
	for item in g.snapshot().items:
		if item.item_id == id and (location == "" or item.location == location): n += 1
	return n

func fixture(g, state: Dictionary, label: String):
	serial += 1
	var path = temp_root+"/fixture-%s-%d.json" % [label,serial]
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(state,"",true,true)); file.close()
	expect(g.load_from(path).ok,"controlled boundary fixture validates: "+label)

func stock(g, id: String, target: int):
	if count(g,id) < target: act(g,"buy",{"item_id":id,"quantity":target-count(g,id)})

func make(g, id: String, target: int):
	if count(g,id) < target: act(g,"craft",{"recipe_id":id,"quantity":target-count(g,id)})

func prepare_food(g, targets: Dictionary):
	var needed = {}
	for id in targets:
		var amount = maxi(0,int(targets[id])-count(g,id))
		for material in Catalog.RECIPES[id].inputs:
			needed[material] = needed.get(material,0)+Catalog.RECIPES[id].inputs[material]*amount
	for id in needed: stock(g,id,int(needed[id]))
	act(g,"finish_shopping")
	for id in targets:
		make(g,id,int(targets[id]))
		if targets[id] > 0: act(g,"display",{"item_id":id,"quantity":int(targets[id])})

func trade(g, hagrid: bool = false, preferred: String = ""):
	if g.view().phase == "preparation": act(g,"open_shop")
	var guard = 0
	while g.view().phase == "trading" and guard < 30:
		guard += 1
		var p = g.view().pending
		if p.is_empty(): expect(g.advance(1000).ok,"ordinary automatic serving")
		else:
			var choice = ""
			if hagrid or p.quest_id != "hagrid_patrol":
				for option in p.options:
					if option.available:
						if choice == "": choice = option.item_id
						if option.item_id == preferred: choice = option.item_id; break
			if choice == "": act(g,"decline",{"order_id":p.id})
			else: act(g,"fulfill",{"order_id":p.id,"item_id":choice})
	expect(g.view().phase == "closing","finite queue completes")
	if g.view().phase == "closing": act(g,"settle")

func roundtrip(g, label: String):
	var path = temp_root+"/"+label+".json"; var before = g.snapshot()
	expect(g.save_to(path).ok,"save complete "+label)
	var clone = Session.new(999,"prototype-v1")
	expect(clone.load_from(path).ok,"restore complete "+label)
	expect(clone.snapshot() == before,"exact roundtrip "+label)
	return clone

func comparable(g) -> Dictionary:
	var s = g.snapshot(); s.erase("requests"); return s

func simulate(seed_value: int, strategy: String, existing = null) -> Dictionary:
	var g = Session.new(seed_value,"prototype-v1") if existing == null else existing
	var hot = strategy in ["hot_meals","kitchen_investment"]
	var upgrades = []; var forecasts = []
	if strategy in ["quick_service","rain_stockpile","unprepared"] and count(g,"stirring_cauldron") > 0:
		act(g,"recycle",{"item_id":"stirring_cauldron","quantity":1})
	for day in [1,2,3]:
		forecasts.append(g.view().forecast)
		var targets = {"floating_pie":4 if day == 1 else 3}
		if hot: targets.moon_stew = 3 if day < 3 else 4
		elif strategy != "unprepared" and day >= 2: targets.ember_soup = 2 if strategy == "rain_stockpile" and day == 2 else 1
		if hot and day == 3: targets.ember_soup = 1
		var needed = {}
		for id in targets:
			for material in Catalog.RECIPES[id].inputs:
				needed[material] = needed.get(material,0)+Catalog.RECIPES[id].inputs[material]*maxi(0,int(targets[id])-count(g,id))
		for id in needed: stock(g,id,int(needed[id]))
		act(g,"finish_shopping")
		if hot and day == 1: act(g,"install",{"uid":1})
		for id in targets:
			make(g,id,int(targets[id])); act(g,"display",{"item_id":id,"quantity":int(targets[id])})
		trade(g,false,"moon_stew" if hot else "")
		if day == 1 and strategy != "unprepared":
			var upgrade = "shelf" if hot else "supply_pass"
			act(g,"upgrade",{"upgrade_id":upgrade}); upgrades.append({"id":upgrade,"day":day})
		if day == 2 and hot:
			act(g,"upgrade",{"upgrade_id":"supply_pass"}); upgrades.append({"id":"supply_pass","day":day})
		if day < 3: act(g,"next_day")
	var s = g.snapshot(); var gross = 0; var recoveries = 0; var purchases = {}; var crafts = {}
	for sale in s.sales: gross += int(sale.revenue)-int(sale.cost)
	for entry in s.ledger:
		if entry.kind == "recover": recoveries += 1
		if entry.kind == "buy": purchases[entry.args.item_id] = purchases.get(entry.args.item_id,0)+int(entry.args.quantity)
		if entry.kind == "craft": crafts[entry.args.recipe_id] = crafts.get(entry.args.recipe_id,0)+int(entry.args.quantity)
	expect(g.view().finished and s.cash >= 0 and gross > 0,"strategy completes three days with positive dish gross margin")
	expect(recoveries == 0 and s.expedition_attempts.is_empty() and s.quests.hagrid_patrol == "declined","ordinary routes need no emergency/combat/Hagrid reward")
	var record = {"seed":seed_value,"strategy":strategy,"cash":s.cash,"inventory":s.items,"gross_profit":gross,"recoveries":recoveries,"upgrade_days":upgrades,"purchases":purchases,"crafts":crafts,"sales":s.sales,"forecasts":forecasts,"ledger":s.ledger}
	simulations.append(record); traces.append({"seed":seed_value,"strategy":strategy,"actions":g.action_trace()})
	return {"game":g,"report":record}

func test_p02():
	var r = simulate(int(seeds[0]),"quick_service")
	expect(r.game.snapshot().summaries.size() == 3,"three settlements on one save")
	expect(r.game.view().inventory.size() == 12 and r.game.view().recipes.size() == 5,"twelve SKU and five known recipes")
	reject(r.game,"next_day")
	roundtrip(r.game,"finished-restaurant")

func test_p03():
	var g = Session.new(7,"prototype-v1")
	act(g,"buy",{"item_id":"flour","quantity":4}); act(g,"buy",{"item_id":"pumpkin","quantity":6}); act(g,"buy",{"item_id":"cream","quantity":2})
	act(g,"finish_shopping"); act(g,"install",{"uid":1})
	act(g,"craft",{"recipe_id":"floating_pie","quantity":4}); act(g,"craft",{"recipe_id":"moon_stew","quantity":2})
	act(g,"uninstall",{"uid":1})
	expect(g.view().recipes.filter(func(r): return r.recipe_id == "moon_stew")[0].available == false,"uninstall removes future cooking capability")
	act(g,"display",{"item_id":"floating_pie","quantity":4}); act(g,"display",{"item_id":"moon_stew","quantity":2}); trade(g)
	expect(g.view().summary.revenue == 80 and g.view().summary.sold_cost == 30 and g.view().summary.gross_profit == 50 and g.view().cash == 106,"actual ingredient cost and realised dish margin stay separate")
	expect(g.snapshot().sales.any(func(s): return s.item_id == "moon_stew" and s.effect_id == "self_stir"),"crafted dish retains its magic after device removal")
	expect(Catalog.price("floating_pie","friendly",0) == 11,"positive half-up rounding")
	expect(Catalog.price("ember_soup","standard",25) == 18 and Catalog.price("ember_soup","standard",999) == 18,"rain contribution capped at25%")

func test_p04():
	var g = Session.new(7,"prototype-v1")
	var poor = Session.new(7,"prototype-v1")
	act(poor,"buy",{"item_id":"flour","quantity":12}); act(poor,"buy",{"item_id":"pumpkin","quantity":12})
	expect(poor.view().cash == 0 and reject(poor,"buy",{"item_id":"cream","quantity":1}).code == "insufficient_cash","available ingredient with insufficient cash rejects atomically")
	for q in [0,-1,1.5,"2",null]: reject(g,"buy",{"item_id":"flour","quantity":q})
	reject(g,"buy",{"item_id":"pen","quantity":1}); reject(g,"buy",{"item_id":"moonheart","quantity":1})
	reject(g,"craft",{"recipe_id":"floating_pie","quantity":1}); reject(g,"equip_weapon",{"weapon_id":"fan_wand"}); reject(g,"expedition_input",{"cast":true})
	act(g,"buy",{"item_id":"pumpkin","quantity":1}); act(g,"buy",{"item_id":"cream","quantity":1}); act(g,"finish_shopping")
	reject(g,"display",{"item_id":"pumpkin","quantity":1}); reject(g,"display",{"item_id":"stirring_cauldron","quantity":1})
	reject(g,"craft",{"recipe_id":"moon_stew","quantity":1}); reject(g,"craft",{"recipe_id":"floating_pie","quantity":1})
	act(g,"install",{"uid":1}); reject(g,"install",{"uid":1}); reject(g,"recycle",{"item_id":"stirring_cauldron","quantity":1})
	act(g,"craft",{"recipe_id":"moon_stew","quantity":1}); act(g,"display",{"item_id":"moon_stew","quantity":1})
	var s = g.snapshot()
	for order in s.customers: order.budget = 0
	fixture(g,s,"budget-zero")
	act(g,"open_shop"); g.advance(3000)
	expect(not g.view().pending.is_empty(),"special order actually reached")
	expect("quick" in reject(g,"fulfill",{"order_id":g.view().pending.id,"item_id":"moon_stew"}).message,"on-menu hearty meal cannot bypass quick requirement")
	expect(g.snapshot().sales.all(func(sale): return sale.revenue == 0),"ordinary service cannot bypass budget")

func test_noop_request_binding():
	var g = Session.new(1,"prototype-v1"); var before = g.snapshot().ledger.duplicate(true)
	expect(g.command("pause",{"value":false},"same-noop").ok,"success no-op accepted")
	expect(g.snapshot().ledger == before and g.snapshot().requests.has("same-noop"),"no-op bound without economic row")
	reject(g,"recover",{},"same-noop")
	act(g,"finish_shopping"); act(g,"price",{"item_id":"floating_pie","tier":"standard"})
	act(g,"price",{"item_id":"floating_pie","tier":"standard"},"old-price")
	act(g,"price",{"item_id":"floating_pie","tier":"premium"})
	var state = g.snapshot()
	expect(g.command("price",{"item_id":"floating_pie","tier":"standard"},"old-price").code == "duplicate" and g.snapshot() == state,"stale no-op retry cannot reprice")
	var clone = roundtrip(g,"noop-binding")
	expect(clone.command("price",{"item_id":"floating_pie","tier":"standard"},"old-price").code == "duplicate","no-op binding persists")

func test_p05():
	test_noop_request_binding()
	var g = Session.new(23,"prototype-v1")
	act(g,"recover",{},"reward-once"); var before = g.snapshot()
	expect(g.command("recover",{},"reward-once").code == "duplicate" and g.snapshot() == before,"daily reward retry no change")
	reject(g,"recover"); g = roundtrip(g,"reward-once"); reject(g,"recover")
	act(g,"finish_shopping"); trade(g); reject(g,"settle")
	act(g,"next_day",{},"day-once"); before = g.snapshot()
	expect(g.command("next_day",{},"day-once").code == "duplicate" and g.snapshot() == before,"cross-day refresh once")
	reject(g,"next_day")

func test_p06():
	var g = Session.new(99,"prototype-v1"); var zero = g.snapshot()
	zero.initial_cash = 0; zero.cash = 0; zero.items = []; zero.ledger = []; zero.next_uid = 1
	fixture(g,zero,"zero-funds-empty")
	expect(g.view().available_commands.recover.enabled,"visible zero-cost wash-pot recovery")
	act(g,"recover"); reject(g,"recover"); g = roundtrip(g,"zero-recovery"); reject(g,"recover")
	prepare_food(g,{"floating_pie":2}); trade(g)
	expect(g.view().cash == 22 and g.view().summary.revenue == 24,"zero-funds empty inventory resumes actual business")
	expect(reject(g,"upgrade",{"upgrade_id":"field_kit"}).code == "insufficient_cash","earned income threshold cannot bypass actual upgrade payment")
	traces.append({"scenario":"zero-funds-recovery","ledger":g.snapshot().ledger,"recoveries":1})

func test_p07():
	var g = Session.new(20261025,"prototype-v1")
	act(g,"buy",{"item_id":"flour","quantity":4}); act(g,"buy",{"item_id":"pumpkin","quantity":4})
	var clone = roundtrip(g,"after-shopping")
	for x in [g,clone]:
		act(x,"finish_shopping"); act(x,"craft",{"recipe_id":"floating_pie","quantity":4}); act(x,"display",{"item_id":"floating_pie","quantity":4}); act(x,"open_shop"); x.advance(1500)
	expect(comparable(g) == comparable(clone),"shopping reload continues identically")
	clone = roundtrip(g,"during-service")
	for x in [g,clone]: trade(x)
	expect(comparable(g) == comparable(clone),"fractional service clock survives save")
	act(g,"upgrade",{"upgrade_id":"field_kit"})
	clone = roundtrip(g,"pending-growth")
	expect(clone.view().progression.owned_weapons == ["bolt_wand"] and clone.view().progression.pending_unlocks == ["fan_wand","gust"],"paid growth remains pending on purchase day")
	for x in [g,clone]: act(x,"next_day")
	expect(comparable(g) == comparable(clone),"growth unlocks identically next day")
	reject(clone,"next_day")

func test_p08():
	for seed_value in seeds:
		var a = Session.new(int(seed_value),"prototype-v1"); var b = Session.new(int(seed_value),"prototype-v1")
		expect(a.snapshot() == b.snapshot(),"same seed exact initial state")
		for g in [a,b]: act(g,"buy",{"item_id":"flour","quantity":1},"seed-same")
		expect(a.snapshot() == b.snapshot(),"same commands and seed reproduce supply/economy")
		var clone = roundtrip(a,"seed-%s" % seed_value); var before = clone.snapshot()
		expect(clone.load_from(temp_root+"/seed-%s.json" % seed_value).ok and clone.snapshot() == before,"repeated read cannot reroll")
	var big = roundtrip(Session.new(9223372036854775806,"prototype-v1"),"large-seed")
	expect(big.snapshot().seed == "9223372036854775806","64-bit seed not rounded")

func test_cost_provenance():
	var g = Session.new(7,"prototype-v1"); act(g,"buy",{"item_id":"flour","quantity":1})
	var path = temp_root+"/cost.json"; expect(g.save_to(path).ok,"save valid cost with backup")
	var bad = g.snapshot(); bad.items[1].cost = 9
	expect(g.validate_snapshot(bad) != "","purchase cost corruption rejected")
	var bytes = JSON.stringify(bad); var backup = FileAccess.get_file_as_string(path+".bak")
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(bytes); file.close()
	var clone = Session.new(2,"prototype-v1"); var result = clone.load_from(path)
	expect(result.ok and result.code == "recovered_backup","bad cost restores backup")
	expect(FileAccess.get_file_as_string(path) == bytes and FileAccess.get_file_as_string(path+".bak") == backup,"cost recovery preserves files")
	act(clone,"recycle",{"item_id":"flour","quantity":1}); expect(clone.view().cash == 59,"cost corruption cannot mint recycle income")
	g = Session.new(1,"prototype-v1"); prepare_food(g,{"floating_pie":4})
	bad = g.snapshot(); bad.items.back().cost += 1
	expect(g.validate_snapshot(bad) != "","crafted cost must match consumed ingredients")
	trade(g); bad = g.snapshot()
	for sale in bad.sales:
		if sale.revenue > 0: sale.cost += 1; bad.summaries[0].sold_cost += 1; bad.summaries[0].gross_profit -= 1; break
	expect(g.validate_snapshot(bad) != "","realised margin must match actual outflow")

func test_p09():
	test_cost_provenance()
	var g = Session.new(7,"prototype-v1"); var path = temp_root+"/damaged.json"
	act(g,"buy",{"item_id":"flour","quantity":1}); expect(g.save_to(path).ok,"valid primary+backup")
	var good = g.snapshot(); var backup = FileAccess.get_file_as_string(path+".bak")
	var invalid = good.duplicate(true); invalid.cash = -1
	for bad in ["{","invalid JSON",JSON.stringify(invalid)]:
		var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(bad); file.close()
		var result = g.load_from(path)
		expect(result.ok and result.code == "recovered_backup" and g.snapshot() == good,"damaged primary recovers exact snapshot")
		expect(FileAccess.get_file_as_string(path) == bad and FileAccess.get_file_as_string(path+".bak") == backup,"load never destroys corrupt/backup bytes")
	var old = "{\"version\":1}"
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(old); file.close()
	var result = g.load_from(path)
	expect(not result.ok and result.message == "不支持的存档版本" and g.snapshot() == good,"v1 rejected clearly even with valid v2 backup")
	expect(FileAccess.get_file_as_string(path) == old and FileAccess.get_file_as_string(path+".bak") == backup,"v1 source and backup preserved")
	var earned = Session.new(1,"prototype-v1"); prepare_food(earned,{"floating_pie":4}); trade(earned); act(earned,"upgrade",{"upgrade_id":"field_kit"})
	var malformed = earned.snapshot(); malformed.sales[0] = "broken"
	expect(earned.validate_snapshot(malformed) != "","malformed sales reject before earned-income calculation")
	for bad_value in [null,[],{},"broken"]:
		malformed = earned.snapshot()
		for row in malformed.ledger:
			if not row.removed.is_empty(): row.removed[0].uid = bad_value; break
		expect(earned.validate_snapshot(malformed) != "","malformed consumed UID rejects without numeric coercion")
		malformed = earned.snapshot()
		for row in malformed.ledger:
			if row.kind == "advance": row.events[0] = bad_value; break
		expect(earned.validate_snapshot(malformed) != "","malformed sale event rejects without field access")

func test_p10():
	for seed_value in seeds:
		var quick = simulate(int(seed_value),"quick_service").report
		var hot = simulate(int(seed_value),"hot_meals").report
		expect(quick.purchases != hot.purchases and quick.crafts != hot.crafts,"routes differ in ingredient and cooking choices")
		expect(quick.upgrade_days[0].id != hot.upgrade_days[0].id,"routes invest in different next-day choices")
		for strategy in ["conservative","kitchen_investment","rain_stockpile"]: simulate(int(seed_value),strategy)

func test_p11():
	var origin = Session.new(23,"prototype-v1"); var keep = roundtrip(origin,"device-opportunity-origin")
	act(origin,"recycle",{"item_id":"stirring_cauldron","quantity":1})
	expect(origin.view().cash == 78 and keep.view().cash == 60,"retained zero-cost heirloom costs18 foregone cash")
	var sold = simulate(23,"quick_service",origin); var retained = simulate(23,"hot_meals",keep)
	expect(sold.game.view().finished and retained.game.view().finished,"both device branches finish without rare reacquisition")
	expect(not sold.report.crafts.has("moon_stew") and retained.report.crafts.has("moon_stew"),"device changes actual recipes and matching")
	var g = Session.new(1,"prototype-v1"); act(g,"finish_shopping"); trade(g); act(g,"next_day")
	var cash = g.view().cash
	act(g,"buy",{"item_id":"stirring_cauldron","quantity":1}); act(g,"recycle",{"item_id":"stirring_cauldron","quantity":1})
	expect(g.view().cash == cash-12,"replacement buy30/sell18 cannot arbitrage")

func test_p12():
	for seed_value in seeds:
		for strategy in ["quick_service","hot_meals"]:
			var reports = simulations.filter(func(r): return r.seed == seed_value and r.strategy == strategy)
			if reports.is_empty(): reports.append(simulate(int(seed_value),strategy).report)
			var r = reports[0]; var forecast = r.forecasts[1]
			expect(forecast.required == ["warming","heat_hold"] and forecast.solutions.size() == 2,"rain and two stable solutions readable before day2 buying")
			var rain = r.sales.filter(func(s): return s.order_id == "d3-special")
			expect(rain.size() == 1 and rain[0].revenue > 0 and "+25%" in str(rain[0].reasons),"prepared dish actually earns bounded rain premium")
			expect(rain[0].item_id == ("ember_soup" if strategy == "quick_service" else "moon_stew"),"independent stable rain solution")
		var unprepared = simulate(int(seed_value),"unprepared").report
		expect(unprepared.sales.filter(func(s): return s.order_id == "d3-special")[0].revenue == 0,"unprepared pie gets no rain reward")

func test_p13():
	var bulk = Session.new(1,"prototype-v1"); var each = Session.new(1,"prototype-v1")
	for g in [bulk,each]:
		act(g,"recycle",{"item_id":"stirring_cauldron","quantity":1}); act(g,"buy",{"item_id":"flour","quantity":4}); act(g,"buy",{"item_id":"pumpkin","quantity":4}); act(g,"finish_shopping")
	act(bulk,"craft",{"recipe_id":"floating_pie","quantity":4})
	for i in range(4): act(each,"craft",{"recipe_id":"floating_pie","quantity":1})
	expect(bulk.snapshot().items == each.snapshot().items and bulk.view().cash == each.view().cash,"base bulk input/cost/output equals individual cooking without device")
	for q in [0,-1,1]: reject(bulk,"craft",{"recipe_id":"floating_pie","quantity":q})
	act(bulk,"display",{"item_id":"floating_pie","quantity":4}); trade(bulk)
	act(bulk,"upgrade",{"upgrade_id":"supply_pass"}); act(bulk,"upgrade",{"upgrade_id":"field_kit"})
	expect(not bulk.snapshot().supply.has("ember_herb") and bulk.view().progression.owned_weapons == ["bolt_wand"],"upgrades cannot activate on purchase day")
	reject(bulk,"upgrade",{"upgrade_id":"field_kit"}); act(bulk,"next_day")
	expect(bulk.snapshot().supply.ember_herb >= 12 and "gust" in bulk.view().progression.skills,"next-day stable ingredient and earned skill activated")
	act(bulk,"equip_weapon",{"weapon_id":"fan_wand"}); roundtrip(bulk,"equipped-growth")
	prepare_food(bulk,{"ember_soup":1}); trade(bulk,true)
	expect(bulk.snapshot().sales.any(func(s): return s.item_id == "ember_soup" and s.revenue > 0),"new supplier creates actual sold meal")
	var no_sales = Session.new(1,"prototype-v1"); act(no_sales,"recover"); act(no_sales,"recycle",{"item_id":"stirring_cauldron","quantity":1}); act(no_sales,"finish_shopping"); trade(no_sales)
	expect(no_sales.view().cash >= 24,"boundary has money from non-dish sources")
	reject(no_sales,"upgrade",{"upgrade_id":"field_kit"})

func hagrid_ready(solution: String):
	var g = Session.new(23,"prototype-v1")
	stock(g,"flour",4); stock(g,"pumpkin",4); act(g,"finish_shopping")
	if solution == "moon_stew": act(g,"install",{"uid":1})
	make(g,"floating_pie",4); act(g,"display",{"item_id":"floating_pie","quantity":4}); trade(g)
	if solution == "ember_soup": act(g,"upgrade",{"upgrade_id":"supply_pass"})
	act(g,"next_day"); prepare_food(g,{solution:4 if solution == "moon_stew" else 1})
	act(g,"open_shop"); g.advance(3000)
	expect(g.view().pending.get("id","") == "d2-hagrid-patrol","second-day Hagrid genuinely pending")
	return g

func test_p15():
	for solution in ["ember_soup","moon_stew"]:
		var g = hagrid_ready(solution); var skipped = roundtrip(g,"hagrid-pending-"+solution)
		var p = g.view().pending
		expect(p.character_id == "hagrid" and p.quest_id == "hagrid_patrol" and p.rewards == [{"item_id":"ember_herb","quantity":2}],"persistent Hagrid identity and reward")
		var before = g.snapshot(); g.advance(60000); expect(g.snapshot() == before,"Hagrid decision freezes clock/cursor")
		var grass = count(g,"ember_herb",""); var cash = g.view().cash; var price = g.view().prices[solution]
		act(g,"fulfill",{"order_id":p.id,"item_id":solution},"hagrid-complete-"+solution)
		expect(count(g,"ember_herb","") == grass+2 and g.view().cash == cash+price and g.snapshot().quests.hagrid_patrol == "completed","one dish sells and two free herbs granted atomically")
		before = g.snapshot()
		expect(g.command("fulfill",{"order_id":p.id,"item_id":solution},"hagrid-complete-"+solution).code == "duplicate" and g.snapshot() == before,"same request cannot repeat quest reward")
		reject(g,"fulfill",{"order_id":p.id,"item_id":solution}); g = roundtrip(g,"hagrid-completed-"+solution); reject(g,"fulfill",{"order_id":p.id,"item_id":solution})
		act(skipped,"decline",{"order_id":p.id},"hagrid-skip-"+solution)
		expect(skipped.snapshot().quests.hagrid_patrol == "declined" and count(skipped,"ember_herb","") == grass,"skip has no reward or penalty")
		skipped = roundtrip(skipped,"hagrid-declined-"+solution)
		for branch in [g,skipped]: trade(branch); act(branch,"next_day")
		stock(g,"pumpkin",1); act(g,"finish_shopping"); act(g,"craft",{"recipe_id":"ember_soup","quantity":1})
		expect(count(g,"ember_soup") > 0,"free quest ingredient returns to existing real recipe")
		trade(g); act(skipped,"finish_shopping"); trade(skipped)
		expect(g.view().finished and skipped.view().finished,"complete and skip branches both reach third settlement")
	var full = Session.new(1,"prototype-v1"); var rich = full.snapshot(); rich.cash = 1000; rich.initial_cash = 1000
	fixture(full,rich,"reward-capacity-funds")
	for id in ["flour","pumpkin","cream"]: act(full,"buy",{"item_id":id,"quantity":full.snapshot().supply[id]})
	act(full,"finish_shopping"); act(full,"install",{"uid":1}); act(full,"craft",{"recipe_id":"moon_stew","quantity":1}); trade(full)
	act(full,"upgrade",{"upgrade_id":"supply_pass"}); act(full,"next_day")
	for id in full.snapshot().supply:
		var amount = mini(80-full.snapshot().items.size(),int(full.snapshot().supply[id]))
		if amount > 0: act(full,"buy",{"item_id":id,"quantity":amount})
	expect(full.snapshot().items.size() == 80,"reward capacity fixture actually full")
	for id in full.snapshot().supply:
		if full.snapshot().supply[id] > 0:
			expect(reject(full,"buy",{"item_id":id,"quantity":1}).code == "capacity","full inventory cannot buy one more available ingredient")
			break
	act(full,"finish_shopping"); act(full,"display",{"item_id":"moon_stew","quantity":1})
	var state = full.snapshot()
	for order in state.customers:
		if not order.special: order.budget = 0
	fixture(full,state,"reward-capacity-no-ordinary-sales")
	act(full,"open_shop"); full.advance(3000)
	expect(reject(full,"fulfill",{"order_id":"d2-hagrid-patrol","item_id":"moon_stew"},"full-reward").code == "capacity","whole quest rejected if two reward herbs cannot fit")
	expect(not full.snapshot().requests.has("full-reward") and full.snapshot().quests.hagrid_patrol == "pending","failed reward leaves no commit or request marker")
	act(full,"decline",{"order_id":"d2-hagrid-patrol"}); trade(full)
	var budget = hagrid_ready("ember_soup"); state = budget.snapshot()
	state.customers[2].budget = 13; state.pending.budget = 13; fixture(budget,state,"quest-budget-low")
	expect("预算" in reject(budget,"fulfill",{"order_id":"d2-hagrid-patrol","item_id":"ember_soup"}).message,"budget below actual soup price rejected")
	state = budget.snapshot(); state.customers[2].budget = 14; state.pending.budget = 14; fixture(budget,state,"quest-budget-exact")
	act(budget,"fulfill",{"order_id":"d2-hagrid-patrol","item_id":"ember_soup"})
	expect(budget.snapshot().sales.back().revenue == 14,"exact budget accepted")

func run(output_directory: String, selected: String = "") -> Dictionary:
	# Corruption/backup tests require fresh files, even when reusing a report folder.
	temp_root = output_directory+"/core-save-fixtures-%d" % OS.get_process_id(); DirAccess.make_dir_recursive_absolute(temp_root)
	var fixture_data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/prototype-scenarios.json")); seeds = fixture_data.seeds
	for id in ["P02","P03","P04","P05","P06","P07","P08","P09","P10","P11","P12","P13","P15"]:
		if selected != "" and selected != "core" and selected != id: continue
		run_case(id,Callable(self,"test_"+id.to_lower()))
	for name in ["core-simulations","core-traces"]:
		var file = FileAccess.open(output_directory+"/"+name+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"schema_version":1,"seeds":seeds,"simulations":simulations} if name == "core-simulations" else {"schema_version":1,"traces":traces},"\t",true,true)); file.close()
	return {"schema_version":1,"suite":"prototype","cases":cases}
