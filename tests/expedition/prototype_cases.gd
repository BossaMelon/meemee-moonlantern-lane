extends RefCounted
## Integrated P16/P17. Uses only the real session's commands, advance, save and load.
const Driver = preload("res://tests/expedition/action_driver.gd")
const ModelCases = preload("res://tests/expedition/model_cases.gd")
var factory: Callable
var root = ""
var cases: Array = []
var traces: Array = []
var simulations: Array = []
var failures: Array = []
var checks = 0
var serial = 0
var label = ""
var seeds = [1,7,23,99,2026]

func expect(condition: bool, message: String):
	checks += 1
	if not condition:
		failures.append(message)
		push_error(label+": "+message)

func act(g, kind: String, args: Dictionary = {}) -> Dictionary:
	serial += 1
	var result: Dictionary = g.command(kind,args,"e01-case-%d" % serial)
	expect(result.ok,kind+": "+str(result))
	return result

func reject(g, kind: String, args: Dictionary = {}):
	var before: Dictionary = g.snapshot()
	var result: Dictionary = g.command(kind,args,"e01-reject-%d" % serial)
	serial += 1
	expect(not result.ok and before == g.snapshot(),kind+" rejects atomically")

func count(g, id: String, location: String = "bag") -> int:
	var n = 0
	for item in g.snapshot().items:
		if item.item_id == id and item.location == location: n += 1
	return n

func ensure_stock(g, id: String, quantity: int):
	var missing = quantity-count(g,id)
	if missing > 0: act(g,"buy",{"item_id":id,"quantity":missing})

func craft(g, id: String, quantity: int):
	act(g,"craft",{"recipe_id":id,"quantity":quantity})

func display(g, id: String, quantity: int):
	act(g,"display",{"item_id":id,"quantity":quantity})

func trade(g):
	act(g,"open_shop")
	var guard = 0
	while g.view().phase == "trading" and guard < 30:
		guard += 1
		var pending: Dictionary = g.view().pending
		if pending.is_empty(): g.advance(1000)
		else:
			var handled = false
			for option in pending.options:
				if option.available:
					act(g,"fulfill",{"order_id":pending.id,"item_id":option.item_id})
					handled = true
					break
			if not handled: act(g,"decline",{"order_id":pending.id})
	expect(g.view().phase == "closing","actual customer queue completes")
	act(g,"settle")

func resume_compare(g, tag: String):
	var path = root+"/"+tag+".json"
	var before: Dictionary = g.snapshot()
	expect(g.save_to(path).ok,"save "+tag)
	var copy = factory.call(1)
	expect(copy.load_from(path).ok,"load "+tag)
	# The contract explicitly clears held inputs on load, not the simulation.
	act(g,"expedition_input",{})
	expect(copy.snapshot() == g.snapshot() or _without_requests(copy.snapshot()) == _without_requests(g.snapshot()),"resume keeps full state except request metadata "+tag)
	var input = Driver.next_input(g.view().expedition)
	act(g,"expedition_input",input)
	act(copy,"expedition_input",input)
	var a: Dictionary = g.advance(137)
	var events: Array = []
	for amount in [17,33,87]: events.append_array(copy.advance(amount).events)
	expect(a.events == events and _without_requests(g.snapshot()) == _without_requests(copy.snapshot()),"continued branch equals saved branch across frame partitions "+tag)
	expect(before.expedition.remaining_ms > g.snapshot().expedition.remaining_ms,"comparison actually advances simulation")

func _without_requests(s: Dictionary) -> Dictionary:
	var out = s.duplicate(true)
	out.erase("requests")
	# JSON has one numeric type; compare both branches in that representation without
	# truncating fractional coordinates or dropping any simulation/economy fields.
	return JSON.parse_string(JSON.stringify(out,"",true,true))

func food_branches(g, seed_value: int):
	# Both branches originate from the exact pie earned/kept by this continuous save.
	var path = root+"/food-choice-%d.json" % seed_value
	expect(g.save_to(path).ok,"save actual earned pie choice")
	var sold = factory.call(1)
	expect(sold.load_from(path).ok,"sale branch loads same pie")
	var cash = sold.view().cash
	act(sold,"finish_shopping"); display(sold,"floating_pie",1); act(sold,"open_shop")
	var guard = 0
	while sold.view().cash == cash and sold.view().phase == "trading" and guard < 15:
		guard += 1
		if not sold.view().pending.is_empty(): act(sold,"decline",{"order_id":sold.view().pending.id})
		else: sold.advance(1000)
	expect(sold.view().cash > cash and not sold.view().next_expedition_shield,"selling this pie earns money without shield")
	var eaten = factory.call(1)
	expect(eaten.load_from(path).ok,"food branch loads same pie")
	var pies = count(eaten,"floating_pie")
	act(eaten,"consume",{"item_id":"floating_pie","quantity":1})
	expect(count(eaten,"floating_pie") == pies-1 and eaten.view().cash == cash,"eating consumes exactly one real pie with no sale income")
	reject(eaten,"consume",{"item_id":"floating_pie","quantity":1})
	act(eaten,"start_expedition")
	expect(eaten.view().expedition.player.shield and not eaten.view().next_expedition_shield,"pending shield transfers once into real action state")
	var events: Array = []
	guard = 0
	while eaten.view().phase == "expedition" and eaten.view().expedition.player.hp == 3 and guard < 3600:
		guard += 1
		events.append_array(eaten.advance(50).events)
	var shield_hits = events.filter(func(e): return e.type == "shield_absorbed").size()
	var actual_damage = events.filter(func(e): return e.type == "hit" and e.entity_id == "player" and e.get("damage",0) == 1).size()
	expect(shield_hits == 1 and actual_damage >= 1,"actual consumed food blocks first attack, later attack still injures")
	if eaten.view().phase == "expedition": act(eaten,"leave_expedition")
	expect(not eaten.view().next_expedition_shield and count(eaten,"floating_pie") == pies-1,"leaving never refunds consumed food or shield")
	traces.append({"scenario":"actual-food-sale-or-shield","seed":seed_value,"sale_cash_delta":sold.view().cash-cash,"food_cash_delta":eaten.view().cash-cash,"attack_events":events,"eaten_final":eaten.snapshot()})

func combat(g, seed_value: int, day: int) -> Dictionary:
	act(g,"start_expedition")
	var start: Dictionary = g.view().expedition
	expect(start.enemies.size() == (3 if day == 1 else 4),"frozen daily enemy configuration")
	var trace: Array = []
	var events: Array = []
	var guard = 0
	var resumed = false
	while g.view().phase == "expedition" and guard < 3800:
		guard += 1
		var state: Dictionary = g.view().expedition
		var input = Driver.next_input(state)
		act(g,"expedition_input",input)
		var step: Dictionary = g.advance(50)
		expect(step.ok,"fixed step accepted")
		events.append_array(step.events)
		trace.append({"tick":state.tick,"input":input,"advance_ms":50,"events":step.events})
		if not resumed and guard == 8 and g.view().phase == "expedition":
			expect(g.set_paused(true).ok,"pause real session during action")
			var paused = g.snapshot()
			g.advance(60000)
			expect(g.snapshot() == paused,"paused session keeps action, inventory and timing unchanged")
			expect(g.set_paused(false).ok,"resume clears held controls")
			resume_compare(g,"seed-%d-day-%d" % [seed_value,day])
			resumed = true
	var end: Dictionary = g.snapshot().expedition
	expect(g.view().phase == "shopping" and end.return_reason == "completed","real combat returns after collecting all drops")
	expect(end.drops.all(func(d): return d.collected),"all drops collected including last enemy")
	var unique = {}
	for event in events:
		if event.type == "drop_collected":
			expect(not unique.has(event.drop_id),"unique drop event "+event.drop_id)
			unique[event.drop_id] = true
	expect(g.validate_snapshot(g.snapshot()).is_empty(),"economic ledger and complete action snapshot validate")
	reject(g,"start_expedition")
	traces.append({"scenario":"actual-spatial-combat","seed":seed_value,"day":day,"actions":trace,"final":end})
	return {"events":events,"end":end,"start":start}

func growth(seed_value: int, stop_before_day: int = 0) -> Dictionary:
	var g = factory.call(seed_value)
	var report = {"seed":seed_value,"days":[],"failures":[]}
	expect(g.view().progression.owned_weapons == ["bolt_wand"],"starts with basic weapon only")
	reject(g,"equip_weapon",{"weapon_id":"fan_wand"})
	for day in [1,2,3]:
		if day > 1:
			act(g,"next_day")
			expect("fan_wand" in g.view().progression.owned_weapons and "gust" in g.view().progression.skills,"paid kit unlocks on next day")
			act(g,"equip_weapon",{"weapon_id":"fan_wand"})
		if day == 3:
			food_branches(g,seed_value)
			var cash = g.view().cash
			var pies = count(g,"floating_pie")
			act(g,"consume",{"item_id":"floating_pie","quantity":1})
			expect(count(g,"floating_pie") == pies-1 and g.view().cash == cash and g.view().next_expedition_shield,"food has real opportunity cost")
			reject(g,"consume",{"item_id":"floating_pie","quantity":1})
		if day == stop_before_day: return {"game":g}
		var fight = combat(g,seed_value,day)
		if day == 1:
			ensure_stock(g,"flour",5); ensure_stock(g,"pumpkin",8); ensure_stock(g,"cream",3)
		elif day == 2:
			ensure_stock(g,"flour",3); ensure_stock(g,"pumpkin",8); ensure_stock(g,"cream",4); ensure_stock(g,"ember_herb",1)
		else:
			expect(count(g,"moonheart") == 1,"only actual elite yields advanced ingredient")
			ensure_stock(g,"flour",4); ensure_stock(g,"pumpkin",6); ensure_stock(g,"ember_herb",2)
		act(g,"finish_shopping")
		if day == 1:
			for item in g.snapshot().items:
				if item.item_id == "stirring_cauldron": act(g,"install",{"uid":item.uid}); break
			craft(g,"floating_pie",5); craft(g,"moon_stew",3)
			display(g,"floating_pie",4); display(g,"moon_stew",3)
		elif day == 2:
			craft(g,"floating_pie",3); craft(g,"moon_stew",4); craft(g,"star_soup",1)
			display(g,"floating_pie",3); display(g,"moon_stew",4); display(g,"star_soup",1)
		else:
			craft(g,"floating_pie",3); craft(g,"star_soup",2); craft(g,"comet_pie",1)
			display(g,"floating_pie",3); display(g,"star_soup",2); display(g,"comet_pie",1)
		trade(g)
		if day == 1:
			act(g,"upgrade",{"upgrade_id":"field_kit"})
			reject(g,"upgrade",{"upgrade_id":"field_kit"})
			act(g,"upgrade",{"upgrade_id":"supply_pass"})
			act(g,"upgrade",{"upgrade_id":"shelf"})
			var path = root+"/pending-kit-%d.json" % seed_value
			expect(g.save_to(path).ok,"pending next-day kit saved")
			var restored = factory.call(1)
			expect(restored.load_from(path).ok and restored.view().progression == g.view().progression,"pending unlock saved without early grant")
		report.days.append({"day":day,"combat":fight,"cash":g.view().cash,"summary":g.view().summary,"progression":g.view().progression})
	var sales: Array = g.snapshot().sales
	expect(sales.any(func(s): return s.item_id == "star_soup" and s.revenue > 0 and "trail_light" in str(s.get("reasons",[]))),"battle ingredient actually serves trail-light customer")
	expect(sales.any(func(s): return s.item_id == "comet_pie" and s.revenue > 0),"elite ingredient actually becomes sold advanced dish")
	expect(count(g,"moonheart") == 0,"advanced material truly consumed by cooking")
	expect(g.validate_snapshot(g.snapshot()).is_empty(),"complete three-day growth state and economic ledger validate")
	report.final = g.snapshot()
	return report

func _case(id: String, test: Callable):
	label = id
	checks = 0
	failures = []
	test.call()
	cases.append({"id":id,"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures.duplicate()})

func purchase_boundaries():
	for source in ["none","recover","recycle"]:
		var g = factory.call(7)
		if source == "recover": act(g,"recover")
		elif source == "recycle": act(g,"recycle",{"item_id":"stirring_cauldron","quantity":1})
		act(g,"finish_shopping"); trade(g)
		expect(g.view().cash >= 24,"non-dish funds could afford kit but do not qualify: "+source)
		reject(g,"upgrade",{"upgrade_id":"field_kit"})
	var poor = factory.call(7)
	act(poor,"buy",{"item_id":"flour","quantity":12})
	act(poor,"buy",{"item_id":"pumpkin","quantity":12})
	act(poor,"finish_shopping"); craft(poor,"floating_pie",2); display(poor,"floating_pie",2); trade(poor)
	expect(poor.view().cash == 20 and poor.snapshot().sales.filter(func(s): return s.revenue > 0).size() == 2,"sales threshold can be met while cash remains insufficient")
	reject(poor,"upgrade",{"upgrade_id":"field_kit"})

func run(session_factory: Callable, output_dir: String) -> Dictionary:
	factory = session_factory
	root = output_dir+"/expedition"
	DirAccess.make_dir_recursive_absolute(root)
	var probe = factory.call(1)
	if probe.snapshot().get("version",0) != 2 or not probe.view().has("progression"):
		for id in ["P16","P17"]:
			cases.append({"id":id,"status":"failed","checks":1,"failures":["Core v2 expedition/progression integration unavailable; no simulated pass"]})
		return {"cases":cases,"simulations":[],"traces":[]}
	_case("P16",func():
		var model = ModelCases.new().run()
		checks += model.checks
		failures.append_array(model.failures)
		for seed_value in seeds: simulations.append(growth(seed_value))
	)
	_case("P17",func():
		purchase_boundaries()
		for report in simulations:
			expect(report.days.size() == 3,"one continuous session spans three days")
			var first: Dictionary = report.days[0].combat.start
			var second: Dictionary = report.days[1].combat.start
			var third: Dictionary = report.days[2].combat
			expect(first.weapon_id == "bolt_wand" and second.weapon_id == "fan_wand","actual earned equipment changes between days")
			expect(report.days[1].combat.events.any(func(e): return e.type == "cast" and e.weapon_id == "fan_wand"),"new weapon actually fired")
			expect(third.events.any(func(e): return e.type == "skill" and not e.affected_ids.is_empty()),"new skill actually pushes enemy")
			expect(third.end.drops.any(func(d): return d.item_id == "moonheart" and d.collected),"advanced drop actually collected")
			expect(report.final.sales.any(func(s): return s.item_id == "comet_pie" and s.revenue > 0),"same save sells advanced recipe")
	)
	var file = FileAccess.open(root+"/action-growth-traces.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"schema_version":1,"seeds":seeds,"simulations":simulations,"traces":traces},"\t")); file.close()
	return {"cases":cases,"simulations":simulations,"traces":traces}
