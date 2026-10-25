extends RefCounted
const Session = preload("res://game/core/game_session.gd")
var checks = 0
var failures: Array = []
var traces: Array = []
var output_dir = ""
var serial = 0

func expect(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message); push_error("quality service: "+message)

func audit(g):
	var error = g.validate_snapshot(g.snapshot())
	expect(error == "","complete service/economy snapshot validates: "+error)

func act(g, kind: String, args: Dictionary = {}, request: String = ""):
	var result = g.command(kind,args,request)
	expect(result.ok,kind+" succeeds: "+str(result)); audit(g)
	return result

func reject(g, kind: String, args: Dictionary = {}, request: String = ""):
	var before = g.snapshot(); var result = g.command(kind,args,request)
	expect(not result.ok and result.code != "" and result.message != "","explicit rejection "+kind)
	expect(before == g.snapshot(),"atomic rejection "+kind)
	return result

func fixture(s: Dictionary, label: String):
	serial += 1
	var path = output_dir+"/boundary-%s-%d.json" % [label,serial]
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(s,"\t",true,true)); file.close()
	var g = Session.new(1)
	expect(g.load_from(path).ok,"controlled boundary fixture loads: "+label); audit(g)
	return g

func roundtrip(g, label: String):
	serial += 1
	var path = output_dir+"/save-%s-%d.json" % [label,serial]
	expect(g.save_to(path).ok,"actual save "+label)
	var clone = Session.new(1)
	expect(clone.load_from(path).ok and clone.snapshot() == g.snapshot(),"exact roundtrip "+label)
	return clone

func advance_wave(g):
	act(g,"advance",{"delta_ms":60000})
	expect(g.view().phase in ["intermission","closing"],"large delta finishes only current wave")
	expect(g.snapshot().service.remainder_ms == 0,"wave boundary clears all excess time")

func prepare_quick(extra: int = 0):
	var g = Session.new(1)
	act(g,"buy",{"item_id":"flour","quantity":5+extra})
	act(g,"buy",{"item_id":"pumpkin","quantity":8+extra})
	act(g,"buy",{"item_id":"ember_herb","quantity":3})
	expect(g.view().cash == 60-43-extra*5,"real initial recipe cost, no free inventory")
	act(g,"finish_shopping")
	act(g,"craft",{"recipe_id":"floating_pie","quantity":5})
	act(g,"craft",{"recipe_id":"ember_soup","quantity":3})
	act(g,"display",{"item_id":"floating_pie","quantity":5})
	act(g,"display",{"item_id":"ember_soup","quantity":3})
	act(g,"set_menu_priority",{"item_ids":["floating_pie","ember_soup"]})
	return g

func test_profile():
	var g = Session.new(1); var s = g.snapshot()
	expect(s.version == 3 and s.profile_id == "rain-night-v1","new default enters actual v3 rain-night profile")
	expect(s.night.day == 1 and s.night.weather == "rain" and s.night.event_id == "rain_return","first-night rain independent of day3")
	expect(s.supply.has("ember_herb") and s.progression.skills == ["gust"],"first-night herbs and gust ready")
	expect(s.pending_meal_effect == null and s.service.wave_id == null and s.service.status == "planned","typed nullable slots and planned service")
	expect(s.service.orders.is_empty() and s.night.queues.values().map(func(queue): return queue.size()) == [8,9,9],"all queues persist but service exposes only current wave")
	expect(Session.new(1,"prototype-v1").snapshot().version == 2,"legacy factory explicitly preserves v2")
	expect(not Session.new(1,"legacy").command("recover").ok,"unknown profile does not silently choose rules")
	audit(g); roundtrip(g,"default-profile")
	act(g,"buy",{"item_id":"flour","quantity":1}); act(g,"buy",{"item_id":"pumpkin","quantity":1})
	act(g,"craft",{"recipe_id":"floating_pie","quantity":1})
	var pie = g.snapshot().items.filter(func(item): return item.item_id == "floating_pie")[0]
	var cash = g.view().cash
	act(g,"consume",{"item_id":"floating_pie","quantity":1},"meal-once")
	expect(g.snapshot().pending_meal_effect == {"effect_id":"light_step","source_item_uid":pie.uid,"used":false} and g.view().cash == cash,"one actual bag UID becomes a typed pending effect without income")
	var before = g.snapshot()
	expect(g.command("consume",{"item_id":"floating_pie","quantity":1},"meal-once").code == "duplicate" and g.snapshot() == before,"meal request retry cannot duplicate consumption")
	reject(g,"consume",{"item_id":"floating_pie","quantity":1})
	roundtrip(g,"pending-meal")
	act(g,"start_expedition")
	expect(g.snapshot().pending_meal_effect == null and g.snapshot().expedition.meal_effect == before.pending_meal_effect and g.snapshot().expedition.version == 2,"real quality model atomically receives pending meal")
	act(g,"leave_expedition"); reject(g,"start_expedition")
	expect(g.snapshot().pending_meal_effect == null,"unused meal is not refunded on return")
	roundtrip(g,"returned-meal")

func test_throughput():
	var fresh = prepare_quick(); var old = fresh.snapshot()
	# Explicit H04 boundary counterexample: only the pie creation wave differs.
	for item in old.items:
		if item.item_id == "floating_pie": item.prepared_wave_id = "n0-w3"
	for entry in old.ledger:
		for item in entry.created:
			if item.item_id == "floating_pie": item.prepared_wave_id = "n0-w3"
	var carryover = fixture(old,"carryover-pies")
	for g in [fresh,carryover]: act(g,"open_shop")
	expect(fresh.snapshot().service.reservations.size() == 3 and carryover.snapshot().service.reservations.size() == 1,"real floating and ordinary concurrent channel capacities")
	expect(fresh.snapshot().items.size() == 9 and fresh.view().cash == 17,"reservation keeps physical inventory and charges nothing")
	var reserved_uids = fresh.snapshot().service.reservations.map(func(r): return r.item_uid)
	expect(reserved_uids.size() == 3 and reserved_uids[0] != reserved_uids[1],"concurrent orders reserve distinct physical UIDs")
	act(fresh,"advance",{"delta_ms":137}); var copy = roundtrip(fresh,"in-flight-37ms")
	expect(copy.snapshot().service.remainder_ms == 37,"service fixed-step remainder persists")
	act(fresh,"advance",{"delta_ms":863}); act(copy,"advance",{"delta_ms":13}); act(copy,"advance",{"delta_ms":850})
	expect(fresh.snapshot() == copy.snapshot(),"service frame partitions continue exactly")
	act(fresh,"advance",{"delta_ms":8000})
	expect(fresh.view().phase == "intermission" and fresh.snapshot().service.elapsed_ms == 9000,"fresh eight actual deliveries finish at9s")
	act(carryover,"advance",{"delta_ms":20000})
	var late = carryover.snapshot().service.orders.filter(func(o): return o.id == "n1-w1-c08")[0]
	expect(late.status == "left" and carryover.snapshot().service.reservations.size() == 1 and carryover.view().phase == "trading","20s patience expires only unreserved c08, last promised dish stays in flight")
	act(carryover,"advance",{"delta_ms":1000})
	for record in [[fresh,"fresh"],[carryover,"carryover"]]:
		var s = record[0].snapshot()
		traces.append({"scenario":"floating-throughput-"+record[1],"boundary":"H04 explicit creation-wave counterfactual","sales":s.sales,"ledger":s.ledger,"service":s.service})
	expect(fresh.snapshot().sales.filter(func(s): return s.revenue > 0).size() == 8 and carryover.snapshot().sales.filter(func(s): return s.revenue > 0).size() == 7,"same real 43-cost ingredients yield8 versus7 sales")
	expect(fresh.view().cash-carryover.view().cash == 18 and carryover.snapshot().service.elapsed_ms == 21000,"actual recovered c08 revenue is18; last promised carryover delivery completes21s")
	expect(carryover.snapshot().sales.filter(func(s): return s.order_id == "n1-w1-c08")[0].reasons == ["congestion"],"missed order reports actual channel congestion")

func test_guards_and_waves():
	var g = prepare_quick(2); var initial = g.snapshot()
	act(g,"open_shop",{},"open-first")
	for paused in [false,true]:
		g.set_paused(paused)
		for action in [["craft",{"recipe_id":"floating_pie","quantity":1}],["display",{"item_id":"floating_pie","quantity":1}],["undisplay",{"item_id":"floating_pie","quantity":1}],["price",{"item_id":"floating_pie","tier":"premium"}],["set_menu_priority",{"item_ids":["ember_soup","floating_pie"]}]]:
			reject(g,action[0],action[1])
	var before = g.snapshot(); g.advance(60000)
	expect(g.snapshot() == before,"paused service freezes waits, reservations, inventory and time")
	g.set_paused(false); advance_wave(g); roundtrip(g,"intermission")
	expect(g.snapshot().rng_state == initial.rng_state and g.snapshot().supply == initial.supply and g.snapshot().day == 1,"wave boundary neither rerolls nor refreshes supplies/date")
	act(g,"craft",{"recipe_id":"floating_pie","quantity":2})
	act(g,"display",{"item_id":"floating_pie","quantity":2})
	reject(g,"set_menu_priority",{"item_ids":[]}); reject(g,"set_menu_priority",{"item_ids":["floating_pie","floating_pie"]})
	act(g,"set_menu_priority",{"item_ids":["floating_pie"]})
	for action in [["buy",{"item_id":"flour","quantity":1}],["install",{"uid":1}],["uninstall",{"uid":1}],["recycle",{"item_id":"stirring_cauldron","quantity":1}],["recover",{}],["start_expedition",{}]]: reject(g,action[0],action[1])
	reject(g,"start_wave",{"wave_id":"n1-w1"}); reject(g,"start_wave",{"wave_id":"n1-w3"})
	act(g,"start_wave",{"wave_id":"n1-w2"},"wave-two"); advance_wave(g)
	before = g.snapshot()
	expect(g.command("start_wave",{"wave_id":"n1-w2"},"wave-two").code == "duplicate" and g.snapshot() == before,"stale successful retry cannot skip the next intermission")
	reject(g,"start_wave",{"wave_id":"n1-w2"})
	act(g,"start_wave",{"wave_id":"n1-w3"}); advance_wave(g)
	expect(g.view().phase == "closing" and g.snapshot().service.next_wave_id == null and g.snapshot().service.reservations.is_empty(),"third wave closes without phantom next wave or in-flight inventory")
	act(g,"settle"); reject(g,"settle")

func heat_origin():
	var g = Session.new(7)
	act(g,"buy",{"item_id":"pumpkin","quantity":4}); act(g,"buy",{"item_id":"cream","quantity":4})
	act(g,"finish_shopping"); act(g,"install",{"uid":1}); act(g,"open_shop"); advance_wave(g)
	var boundary = g.snapshot(); boundary.next_uid = 101
	for order in boundary.night.queues["n1-w2"]: order.budget = 0
	for order in boundary.customers:
		if order.wave_id == "n1-w2": order.budget = 0
	g = fixture(boundary,"H04-heat-leftover-wave2")
	act(g,"craft",{"recipe_id":"moon_stew","quantity":4}); act(g,"display",{"item_id":"moon_stew","quantity":4})
	return g

func four_warm_orders(g, label: String):
	var state = g.snapshot(); var queue = state.night.queues["n1-w3"].slice(0,4)
	for order in queue: order.required = ["meal","warming","heat_hold"]; order.budget = 30
	state.night.queues["n1-w3"] = queue; state.night.waves[2].ordinary_count = 4
	state.customers = []
	for orders in state.night.queues.values(): state.customers.append_array(orders.duplicate(true))
	return fixture(state,label)

func test_heat():
	var hot = heat_origin(); var boundary = hot.snapshot()
	for item in boundary.items:
		if item.item_id == "stirring_cauldron": item.location = "bag"
	var no_pot = fixture(boundary,"H04-same-hot-stock-no-pot")
	for g in [hot,no_pot]: act(g,"start_wave",{"wave_id":"n1-w2"}); advance_wave(g)
	expect(hot.snapshot().service.held_uids == [101,102,103],"only three smallest shelf UIDs are held at real wave boundary")
	expect(hot.snapshot().items.filter(func(i): return i.uid == 104)[0].temperature == "cooled","fourth actual stew cools")
	expect(no_pot.snapshot().items.filter(func(i): return i.item_id == "moon_stew").all(func(i): return i.temperature == "cooled"),"no installed pot leaves every leftover cooled")
	var moved = roundtrip(hot,"held-stock")
	act(moved,"undisplay",{"item_id":"moon_stew","quantity":1}); act(moved,"display",{"item_id":"moon_stew","quantity":1})
	expect(moved.snapshot().items.filter(func(i): return i.uid == 101)[0].temperature == "cooled" and 101 not in moved.snapshot().service.held_uids,"moving out and redisplaying cannot reheat UID101")
	hot = four_warm_orders(hot,"four-warm-with-pot"); no_pot = four_warm_orders(no_pot,"four-warm-no-pot")
	for g in [hot,no_pot]: act(g,"start_wave",{"wave_id":"n1-w3"})
	expect(hot.snapshot().service.reservations.map(func(r): return r.item_uid) == [101,102,103],"matching and reserving use exactly three held UIDs")
	act(hot,"advance",{"delta_ms":1500}); var clone = roundtrip(hot,"pot-batch-in-flight")
	act(hot,"advance",{"delta_ms":3000}); act(clone,"advance",{"delta_ms":3000})
	expect(hot.snapshot() == clone.snapshot(),"saved pot batch delivers the same physical UIDs and money")
	var sales = hot.snapshot().sales.filter(func(s): return s.revenue > 0)
	expect(sales.size() == 3 and sales.all(func(s): return s.delivered_ms == 4500 and s.channel == "pot"),"three actual warm dishes delivered simultaneously at4.5s")
	advance_wave(hot); advance_wave(no_pot)
	expect(no_pot.snapshot().sales.all(func(s): return s.revenue == 0),"without pot warm sales stay zero")
	expect(hot.view().cash-no_pot.view().cash == 60,"heat creates three20-coin actual sales, not cosmetic labels")
	for g in [hot,no_pot]: traces.append({"scenario":"heat-capacity","service":g.snapshot().service,"items":g.snapshot().items,"sales":g.snapshot().sales,"ledger":g.snapshot().ledger})

func test_menu_priority():
	var a = Session.new(23)
	for purchase in [["pumpkin",2],["cream",1],["ember_herb",1]]: act(a,"buy",{"item_id":purchase[0],"quantity":purchase[1]})
	act(a,"finish_shopping"); act(a,"install",{"uid":1})
	for id in ["moon_stew","ember_soup"]:
		act(a,"craft",{"recipe_id":id,"quantity":1}); act(a,"display",{"item_id":id,"quantity":1})
	var b = roundtrip(a,"priority-origin")
	act(a,"set_menu_priority",{"item_ids":["moon_stew","ember_soup"]})
	act(b,"set_menu_priority",{"item_ids":["ember_soup","moon_stew"]})
	for g in [a,b]: act(g,"open_shop")
	var first_a = a.snapshot().service.reservations.filter(func(r): return r.order_id == "n1-w1-c06")[0]
	var first_b = b.snapshot().service.reservations.filter(func(r): return r.order_id == "n1-w1-c06")[0]
	expect(first_a.channel == "pot" and first_b.channel == "ordinary" and first_a.item_uid != first_b.item_uid,"player priority changes actual first matching UID and delivery channel")

func test_cooling_and_day_boundary():
	var g = heat_origin(); act(g,"start_wave",{"wave_id":"n1-w2"}); advance_wave(g)
	act(g,"undisplay",{"item_id":"moon_stew","quantity":1}); act(g,"display",{"item_id":"moon_stew","quantity":1})
	var mixed = four_warm_orders(g,"mixed-cold-smallest-uid")
	act(mixed,"start_wave",{"wave_id":"n1-w3"})
	expect(mixed.snapshot().service.reservations.map(func(r): return r.item_uid) == [102,103],"cold lowest UID is skipped, not swapped in after matching another instance")
	var state = g.snapshot()
	for order in state.night.queues["n1-w3"]: order.budget = 0
	for order in state.customers:
		if order.wave_id == "n1-w3": order.budget = 0
	g = fixture(state,"held-through-final-wave")
	act(g,"start_wave",{"wave_id":"n1-w3"}); advance_wave(g); act(g,"settle")
	var temperatures = g.snapshot().items.filter(func(i): return i.item_id == "moon_stew").map(func(i): return [i.uid,i.temperature,i.prepared_wave_id])
	act(g,"next_day")
	expect(g.snapshot().items.filter(func(i): return i.item_id == "moon_stew").map(func(i): return [i.uid,i.temperature,i.prepared_wave_id]) == temperatures,"next day preserves actual leftover temperature and original preparation wave")
	act(g,"finish_shopping"); act(g,"uninstall",{"uid":1})
	expect(g.snapshot().service.held_uids.is_empty() and g.snapshot().items.filter(func(i): return i.item_id == "moon_stew").all(func(i): return i.temperature == "cooled" and "warming" in i.intrinsic_tags and i.effect_id == "self_stir"),"legal uninstall cools held stock but does not erase intrinsic recipe effects")
	state = g.snapshot()
	for order in state.night.queues["n2-w1"]: order.required = ["meal","hearty"]
	g = fixture(state,"cooled-still-hearty")
	act(g,"open_shop"); advance_wave(g)
	expect(g.snapshot().sales.filter(func(s): return s.day == 2 and s.revenue > 0).size() == 4,"all four cooled meals remain sellable to hearty customers")

func test_save_identity():
	var g = Session.new(1); var legacy = Session.new(1,"prototype-v1")
	var path = output_dir+"/legacy-preserved.json"
	expect(legacy.save_to(path).ok,"real legacy v2 fixture saved")
	var main_bytes = FileAccess.get_file_as_bytes(path); var backup_bytes = FileAccess.get_file_as_bytes(path+".bak")
	var before = g.snapshot()
	expect(not g.load_from(path).ok and not g.save_to(path).ok,"new profile refuses reading or replacing existing v2 primary/backup")
	expect(FileAccess.get_file_as_bytes(path) == main_bytes and FileAccess.get_file_as_bytes(path+".bak") == backup_bytes and g.snapshot() == before,"legacy bytes and current progress preserved")
	expect(not g.save_to("user://moonlantern.json").ok,"new profile refuses the legacy default destination")
	path = output_dir+"/profile-identity.json"
	expect(g.save_to(path).ok,"new v3 primary and backup created")
	var wrong = before.duplicate(true); wrong.profile_id = "prototype-v1"
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(wrong)); file.close()
	expect(not g.load_from(path).ok and g.snapshot() == before,"wrong profile cannot silently recover a different primary identity from backup")
	file = FileAccess.open(path,FileAccess.WRITE); file.store_string("{broken"); file.close()
	expect(g.load_from(path).code == "recovered_backup" and FileAccess.get_file_as_string(path) == "{broken","malformed primary recovers same-profile backup while preserving damaged bytes")
	var underway = prepare_quick(); act(underway,"open_shop"); act(underway,"advance",{"delta_ms":1500})
	var corrupt = underway.snapshot(); corrupt.cursor += 1
	expect(underway.validate_snapshot(corrupt) != "","cursor corruption rejected against actual sales")
	corrupt = underway.snapshot(); corrupt.service.reservations[0].batch_id = "fake-pot"
	expect(underway.validate_snapshot(corrupt) != "","ordinary/floating channel cannot invent a pot batch")
	corrupt = g.snapshot(); corrupt.night.queues["n1-w2"][0] = null
	expect(g.validate_snapshot(corrupt) != "","malformed future-wave order cannot survive until start_wave")
	corrupt = g.snapshot(); corrupt.items[0].temperature = "hot"
	expect(g.validate_snapshot(corrupt) != "","only actual stew may carry temperature")
	corrupt = underway.snapshot(); corrupt.service.orders[0].budget += 1
	expect(underway.validate_snapshot(corrupt) != "","current-wave order cannot diverge from committed immutable queue")
	var expedition = Session.new(1); act(expedition,"start_expedition")
	path = output_dir+"/model-identity.json"; expect(expedition.save_to(path).ok,"model identity primary and backup created")
	for field in ["version","ruleset","map_id","map_revision"]:
		corrupt = expedition.snapshot(); corrupt.expedition[field] = "wrong"
		file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(corrupt)); file.close()
		var unchanged = expedition.snapshot()
		expect(not expedition.load_from(path).ok and expedition.snapshot() == unchanged,"wrong model identity cannot silently restore backup: "+field)

func test_optional_hagrid():
	var g = Session.new(7); act(g,"finish_shopping"); act(g,"open_shop"); advance_wave(g)
	for wave in [2,3]: act(g,"start_wave",{"wave_id":"n1-w%d" % wave}); advance_wave(g)
	act(g,"settle"); act(g,"next_day")
	act(g,"buy",{"item_id":"pumpkin","quantity":1}); act(g,"buy",{"item_id":"ember_herb","quantity":1})
	act(g,"finish_shopping"); act(g,"open_shop"); advance_wave(g)
	act(g,"craft",{"recipe_id":"ember_soup","quantity":1}); act(g,"display",{"item_id":"ember_soup","quantity":1})
	act(g,"start_wave",{"wave_id":"n2-w2"})
	expect(g.snapshot().service.orders.size() == 9 and g.view().pending.id == "n2-hagrid-patrol","optional character is separate from nine ordinary patrol orders")
	var before = g.snapshot(); act(g,"advance",{"delta_ms":60000})
	expect(g.snapshot() == before,"pending character freezes whole wave clock and reservations")
	var declined = roundtrip(g,"pending-hagrid")
	reject(g,"fulfill",{"order_id":"stale","item_id":"ember_soup"})
	act(g,"fulfill",{"order_id":"n2-hagrid-patrol","item_id":"ember_soup"},"hagrid-once")
	expect(g.snapshot().quests.hagrid_patrol == "completed" and g.view().cash == before.cash+18 and g.snapshot().items.filter(func(i): return i.item_id == "ember_herb" and i.cost == 0).size() == 2,"one actual dish trades for revenue and exactly two reward herbs")
	before = g.snapshot(); expect(g.command("fulfill",{"order_id":"n2-hagrid-patrol","item_id":"ember_soup"},"hagrid-once").code == "duplicate" and before == g.snapshot(),"quest reward request replay is inert")
	act(declined,"decline",{"order_id":"n2-hagrid-patrol"})
	expect(declined.snapshot().quests.hagrid_patrol == "declined" and declined.snapshot().service.orders.size() == 9,"skipping character leaves ordinary queue intact")
	for branch in [g,declined]: advance_wave(branch); act(branch,"start_wave",{"wave_id":"n2-w3"}); advance_wave(branch); act(branch,"settle"); roundtrip(branch,"hagrid-outcome")

func test_saved_field_types():
	var g = prepare_quick(); act(g,"open_shop"); act(g,"advance",{"delta_ms":1500})
	var source = g.snapshot()
	for section in ["", "night", "service", "progression", "items", "ledger", "sales"]:
		var original = source if section == "" else (source[section][0] if source[section] is Array else source[section])
		for key in original:
			if original[key] == null: continue
			var corrupt = source.duplicate(true)
			var target = corrupt if section == "" else (corrupt[section][0] if corrupt[section] is Array else corrupt[section])
			target[key] = false if original[key] is String else "wrong-type"
			expect(g.validate_snapshot(corrupt) != "","malformed saved type rejected without script exception: "+section+"."+str(key))
	var path = output_dir+"/invalid-validator-result.json"
	var store = preload("res://game/core/save_store.gd")
	expect(g.save_to(path).ok,"validator boundary fixture saved through actual core")
	var bytes = FileAccess.get_file_as_bytes(path)
	var interrupted = func(_state): return null
	expect(not store.load_state(path,interrupted).ok and not store.save_state(path,source,interrupted).ok,"missing validator result cannot be converted to an empty success string")
	expect(FileAccess.get_file_as_bytes(path) == bytes,"failed validator leaves existing save bytes unchanged")

func run(folder: String) -> Dictionary:
	output_dir = folder+"/fixtures-%d" % OS.get_process_id(); DirAccess.make_dir_recursive_absolute(output_dir)
	test_profile(); test_throughput(); test_guards_and_waves(); test_heat(); test_menu_priority(); test_cooling_and_day_boundary(); test_save_identity(); test_optional_hagrid(); test_saved_field_types()
	var result = {"suite":"quality-service-focused","checks":checks,"failures":failures,"traces":traces}
	return result
