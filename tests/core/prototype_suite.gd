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
	case_id = id
	checks = 0
	failures = []
	test.call()
	cases.append({"id":id,"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures.duplicate()})
	print("%s: %s (%d checks)" % [id,cases.back().status,checks])

func act(g, kind: String, args: Dictionary = {}, request: String = "") -> Dictionary:
	serial += 1
	var result = g.command(kind,args,request if not request.is_empty() else "test-%d" % serial)
	expect(result.ok,kind+" should succeed: "+str(result))
	audit(g)
	return result

func audit(g):
	var s = g.snapshot()
	var cash = int(s.initial_cash)
	var counts = {}
	var ids = {}
	for item in s.items:
		expect(not ids.has(item.uid),"uid unique")
		ids[item.uid] = true
		counts[item.item_id] = counts.get(item.item_id,0)+1
		expect(item.cost >= 0,"nonnegative cost basis")
	var moves = {}
	for entry in s.ledger:
		cash += int(entry.cash_delta)
		for id in entry.moves: moves[id] = moves.get(id,0)+int(entry.moves[id])
	expect(cash == s.cash and cash >= 0,"cash equals initial plus committed ledger")
	for id in Catalog.ITEMS: expect(counts.get(id,0) == moves.get(id,0),"inventory movement conservation "+id)
	expect(g.validate_snapshot(s).is_empty(),"complete snapshot valid: "+g.validate_snapshot(s))

func reject(g, kind: String, args: Dictionary = {}, request: String = "") -> Dictionary:
	var before = g.snapshot()
	var result = g.command(kind,args,request)
	expect(not result.ok,"must reject "+kind+str(args))
	expect(result.code != "" and result.message != "","failure has reason")
	expect(g.snapshot() == before,"failure atomic including RNG and request bookkeeping: "+kind)
	return result

func count(g, id: String, location: String = "") -> int:
	var n = 0
	for item in g.snapshot().items:
		if item.item_id == id and (location.is_empty() or location == item.location): n += 1
	return n

func fixture(g, state: Dictionary, label: String = "fixture"):
	var path = temp_root+"/"+label+str(serial)+".json"
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	var result = g.load_from(path)
	expect(result.ok,"controlled fixture accepted: "+str(result))

func resolve(g):
	var pending = g.view().pending
	if pending.is_empty(): return
	for option in pending.options:
		if option.available:
			act(g,"fulfill",{"order_id":pending.id,"item_id":option.item_id})
			return
	act(g,"decline",{"order_id":pending.id})

func finish_trade(g):
	var guard = 0
	while g.view().phase == "trading" and guard < 20:
		guard += 1
		if not g.view().pending.is_empty(): resolve(g)
		else:
			var result = g.advance(1000)
			expect(result.ok,"automatic trading tick succeeds")
			audit(g)
	expect(g.view().phase == "closing","customer queue completes without waiting indefinitely")
	act(g,"settle")

func stock(g, id: String, desired: int):
	var missing = maxi(0,desired-count(g,id,"bag"))
	if missing == 0: return
	if g.snapshot().supply.has(id):
		act(g,"buy",{"item_id":id,"quantity":missing})
	else:
		for raw in Catalog.RECIPES[id].inputs:
			var needed = missing*int(Catalog.RECIPES[id].inputs[raw])-count(g,raw,"bag")
			if needed > 0: act(g,"buy",{"item_id":raw,"quantity":needed})

func make(g, id: String, desired: int):
	var missing = maxi(0,desired-count(g,id,"bag"))
	if missing > 0: act(g,"craft",{"recipe_id":id,"quantity":missing})

func display_all(g, id: String):
	var n = count(g,id,"bag")
	if n > 0: act(g,"display",{"item_id":id,"quantity":n})

# Strategies use only the same public commands available to players.
func simulate(seed_value: int, strategy: String, existing = null) -> Dictionary:
	var g = Session.new(seed_value) if existing == null else existing
	var upgrade_days = []
	var start = g.snapshot().day
	for day in range(start,4):
		expect(g.view().phase == "shopping" and g.view().day == day,"daily shopping phase")
		var home = strategy in ["home","self_use"]
		if day == 1 and home and count(g,"bell") == 0: act(g,"buy",{"item_id":"bell","quantity":1})
		var pen_target = 4 if day == 2 else 3
		var lamp_target = 4 if day == 1 else (3 if day == 2 else 4)
		if home:
			stock(g,"lamp",lamp_target)
			if day >= 2: stock(g,"pen",1)
		else:
			stock(g,"pen",pen_target)
			if strategy == "conservative" or day >= 2: stock(g,"lamp",1)
		if strategy == "rain" and day == 2:
			# Purchase and craft before day 3; retain it in bag for the forecast.
			stock(g,"charm",1)
		if strategy == "stationery" and day >= 2: stock(g,"charm",1)
		act(g,"finish_shopping")
		if home:
			if day == 1:
				for item in g.snapshot().items:
					if item.item_id == "bell" and item.location == "bag": act(g,"install",{"uid":item.uid}); break
			make(g,"lamp",lamp_target)
			if day >= 2: make(g,"pen",1)
		else:
			make(g,"pen",pen_target)
			if strategy == "conservative" or day >= 2: make(g,"lamp",1)
		if strategy == "rain" and day == 2: make(g,"charm",1)
		if strategy == "stationery" and day >= 2: make(g,"charm",1)
		display_all(g,"lamp")
		display_all(g,"pen")
		if strategy == "stationery" and day >= 2: display_all(g,"charm")
		if strategy == "rain" and day == 3: display_all(g,"charm")
		act(g,"open_shop")
		finish_trade(g)
		if day == 1:
			var upgrade = "supply_pass" if home else "shelf"
			act(g,"upgrade",{"upgrade_id":upgrade})
			upgrade_days.append({"id":upgrade,"day":day})
		if day < 3: act(g,"next_day")
	var s = g.snapshot()
	var gross = 0
	var recoveries = 0
	var purchases = {}
	var processed = {}
	for sale in s.sales: gross += int(sale.revenue)-int(sale.cost)
	for entry in s.ledger:
		if entry.kind == "recover": recoveries += 1
		if entry.kind == "buy": purchases[entry.args.item_id] = purchases.get(entry.args.item_id,0)+int(entry.args.quantity)
		if entry.kind == "craft": processed[entry.args.recipe_id] = processed.get(entry.args.recipe_id,0)+int(entry.args.quantity)
	var record = {"seed":seed_value,"strategy":strategy,"cash":s.cash,"inventory":s.items,"gross_profit":gross,"upgrade_days":upgrade_days,"sales":s.sales,"recoveries":recoveries,"purchases":purchases,"crafts":processed,"day":s.day,"phase":s.phase,"failure_reasons":[]}
	for sale in s.sales:
		if sale.revenue == 0: record.failure_reasons.append({"order_id":sale.order_id,"reasons":sale.reasons})
	expect(s.day == 3 and s.phase == "settled","strategy completes three days")
	expect(s.cash >= 0 and gross > 0,"strategy solvent with positive realised gross profit")
	expect(recoveries == 0,"normal strategy needs no emergency recovery")
	simulations.append(record)
	traces.append({"seed":seed_value,"strategy":strategy,"ledger":s.ledger,"rng_state":s.rng_state})
	return {"game":g,"report":record}

func test_p02():
	var result = simulate(int(seeds[0]),"stationery")
	var s = result.game.snapshot()
	expect(s.summaries.size() == 3,"three daily settlements")
	for day in range(1,4):
		var stages = {}
		for entry in s.ledger:
			if entry.day == day: stages[entry.kind] = true
		for kind in ["buy","craft","display","open_shop","settle"]: expect(stages.has(kind),"day%d includes %s" % [day,kind])
	expect(result.game.view().finished,"third day explicit completed view")
	reject(result.game,"next_day")
	expect("shelf" in s.upgrades and s.known.size() == 3,"upgrades and known recipes persist")

func test_p03():
	var g = Session.new(7)
	act(g,"buy",{"item_id":"feather","quantity":4})
	act(g,"buy",{"item_id":"ink","quantity":4})
	act(g,"buy",{"item_id":"timber","quantity":2})
	expect(g.view().cash == 72,"purchases reduce cash by actual 28, not realised cost")
	act(g,"finish_shopping")
	act(g,"craft",{"recipe_id":"pen","quantity":4})
	act(g,"craft",{"recipe_id":"lamp","quantity":2})
	act(g,"display",{"item_id":"pen","quantity":4})
	act(g,"display",{"item_id":"lamp","quantity":2})
	act(g,"open_shop")
	finish_trade(g)
	var sum = g.view().summary
	expect(sum.revenue == 70 and sum.sold_cost == 24 and sum.gross_profit == 46,"sold cost distinct from purchases: 3 pens + 2 lamps")
	expect(g.view().cash == 138 and count(g,"pen") == 1,"cash138 with remaining pen cost4")
	expect(Catalog.price("pen","friendly",0) == 11,"price half-up rounding")
	expect(Catalog.price("pen","standard",25) == 15 and Catalog.price("pen","standard",999) == 15,"event price cap25%")
	expect(Catalog.price("charm","premium",25) == 16,"composed integer half-up rounding")
	# A lawful controlled order tests the exact budget boundary through the public command.
	var b = Session.new(1)
	act(b,"buy",{"item_id":"timber","quantity":1})
	act(b,"finish_shopping")
	act(b,"craft",{"recipe_id":"lamp","quantity":1})
	act(b,"display",{"item_id":"lamp","quantity":1})
	var state = b.snapshot()
	for order in state.customers:
		if not order.special: order.budget = 0
	state.customers[2].budget = 17
	fixture(b,state,"budget")
	act(b,"open_shop")
	b.advance(3000)
	expect(not b.view().pending.is_empty(),"special order active")
	act(b,"fulfill",{"order_id":b.view().pending.id,"item_id":"lamp"})
	expect(b.snapshot().sales.back().revenue == 17,"budget equals price accepted")
	var device = Session.new(1)
	act(device,"buy",{"item_id":"bell","quantity":1})
	act(device,"finish_shopping")
	var original_items = device.snapshot().items
	var original_cash = device.view().cash
	act(device,"install",{"uid":original_items[0].uid})
	expect(count(device,"bell","installed") == 1 and count(device,"bell","bag") == 0,"install moves one existing instance")
	expect("waterproof" in device.view().inventory[5].tags,"installed device grants lamp effect")
	act(device,"uninstall",{"uid":original_items[0].uid})
	expect(device.snapshot().items == original_items and device.view().cash == original_cash,"uninstall restores same uid, cost and bag location without money change")
	expect("waterproof" not in device.view().inventory[5].tags,"uninstall removes granted effect")
	reject(device,"uninstall",{"uid":original_items[0].uid})

func test_p04():
	var g = Session.new(7)
	for q in [0,-1,1.5,"2",null]: reject(g,"buy",{"item_id":"feather","quantity":q})
	reject(g,"buy",{"item_id":"unknown","quantity":1})
	reject(g,"buy",{"item_id":"timber","quantity":20})
	reject(g,"craft",{"recipe_id":"pen","quantity":1})
	reject(g,"nonsense")
	act(g,"finish_shopping")
	reject(g,"craft",{"recipe_id":"pen","quantity":1})
	reject(g,"craft",{"recipe_id":"unknown","quantity":1})
	reject(g,"buy",{"item_id":"ink","quantity":1})
	reject(g,"display",{"item_id":"bell","quantity":1})
	reject(g,"install",{"uid":900})
	var rich = Session.new(1)
	var state = rich.snapshot(); state.cash = 1000; state.initial_cash = 1000
	fixture(rich,state,"capacity")
	act(rich,"buy",{"item_id":"ink","quantity":30})
	act(rich,"buy",{"item_id":"feather","quantity":30})
	act(rich,"buy",{"item_id":"moss","quantity":20})
	reject(rich,"buy",{"item_id":"timber","quantity":1})
	var h = Session.new(1)
	act(h,"buy",{"item_id":"bell","quantity":1})
	act(h,"buy",{"item_id":"timber","quantity":1})
	act(h,"buy",{"item_id":"moss","quantity":1})
	act(h,"buy",{"item_id":"feather","quantity":1})
	act(h,"finish_shopping")
	act(h,"install",{"uid":1})
	reject(h,"display",{"item_id":"bell","quantity":1})
	act(h,"craft",{"recipe_id":"lamp","quantity":1})
	act(h,"craft",{"recipe_id":"charm","quantity":1})
	act(h,"display",{"item_id":"lamp","quantity":1})
	act(h,"display",{"item_id":"charm","quantity":1})
	expect(reject(h,"display",{"item_id":"feather","quantity":1}).code == "capacity","actual third SKU hits shelf capacity")
	act(h,"open_shop")
	h.advance(3000)
	expect(not h.view().pending.is_empty(),"required-effect rejection reaches special order")
	var mismatch = reject(h,"fulfill",{"order_id":h.view().pending.get("id",""),"item_id":"charm"})
	expect(mismatch.code == "unmatched" and "light" in mismatch.message,"on-shelf charm cannot bypass required light effect")
	var poor = Session.new(1)
	act(poor,"buy",{"item_id":"timber","quantity":1})
	act(poor,"finish_shopping"); act(poor,"craft",{"recipe_id":"lamp","quantity":1}); act(poor,"display",{"item_id":"lamp","quantity":1})
	var limited = poor.snapshot()
	for order in limited.customers: order.budget = 0
	fixture(poor,limited,"lowbudget")
	act(poor,"open_shop"); poor.advance(3000)
	expect(poor.snapshot().cash == 94,"ordinary sales cannot bypass budget")
	reject(poor,"fulfill",{"order_id":poor.view().pending.id,"item_id":"lamp"})
	reject(poor,"fulfill",{"order_id":"absent","item_id":"lamp"})

func test_p05():
	test_noop_request_binding()
	var g = Session.new(23)
	act(g,"buy",{"item_id":"timber","quantity":4},"same-buy")
	var before = g.snapshot()
	expect(g.command("buy",{"item_id":"timber","quantity":4},"same-buy").code == "duplicate","same request id returns duplicate")
	expect(g.snapshot() == before,"duplicate purchase no state change")
	reject(g,"buy",{"item_id":"timber","quantity":3},"same-buy")
	act(g,"finish_shopping"); act(g,"craft",{"recipe_id":"lamp","quantity":4}); act(g,"display",{"item_id":"lamp","quantity":4}); act(g,"open_shop")
	g.advance(3000)
	var order = g.view().pending.id
	act(g,"fulfill",{"order_id":order,"item_id":"lamp"},"special-once")
	before = g.snapshot()
	expect(g.command("fulfill",{"order_id":order,"item_id":"lamp"},"special-once").code == "duplicate","special retry idempotent")
	expect(g.snapshot() == before,"special no duplicated revenue")
	reject(g,"fulfill",{"order_id":order,"item_id":"lamp"})
	finish_trade(g)
	reject(g,"settle")
	var path = temp_root+"/settled.json"
	expect(g.save_to(path).ok,"save after settlement")
	var restored = Session.new(99); expect(restored.load_from(path).ok,"restore settlement")
	reject(restored,"settle")
	act(restored,"next_day",{},"next-once")
	before = restored.snapshot()
	expect(restored.command("next_day",{},"next-once").code == "duplicate","next-day retry same ID")
	expect(restored.snapshot() == before and restored.view().day == 2,"no double daily refresh or skip")
	reject(restored,"next_day")
	act(restored,"recover",{},"recover-once")
	expect(restored.save_to(path).ok,"save after daily reward")
	expect(g.load_from(path).ok,"restore reward")
	reject(g,"recover")
	expect(g.view().daily_recovery == 1,"daily reward flag preserved")

func test_p06():
	var g = Session.new(99)
	var zero = g.snapshot(); zero.cash = 0; zero.initial_cash = 0
	fixture(g,zero,"zero")
	expect(g.view().available_commands.recover.enabled,"visible zero-cost recovery")
	act(g,"recover")
	expect(g.view().cash == 12,"finite recovery supplies basic working capital")
	reject(g,"recover")
	var path = temp_root+"/zero-reward.json"
	expect(g.save_to(path).ok and g.load_from(path).ok,"reward save/reload")
	reject(g,"recover")
	act(g,"buy",{"item_id":"feather","quantity":2}); act(g,"buy",{"item_id":"ink","quantity":2})
	act(g,"finish_shopping"); act(g,"craft",{"recipe_id":"pen","quantity":2}); act(g,"display",{"item_id":"pen","quantity":2}); act(g,"open_shop")
	finish_trade(g)
	expect(g.view().summary.revenue == 24 and g.view().cash == 24,"zero-funds player can resume normal business")
	var recovery_count = 0
	for entry in g.snapshot().ledger:
		if entry.kind == "recover": recovery_count += 1
	expect(recovery_count == 1,"recovery trace count one")
	traces.append({"scenario":"zero-funds-recovery","recoveries":recovery_count,"ledger":g.snapshot().ledger})

func prepared(seed_value: int):
	var g = Session.new(seed_value)
	act(g,"buy",{"item_id":"feather","quantity":4}); act(g,"buy",{"item_id":"ink","quantity":4}); act(g,"buy",{"item_id":"timber","quantity":4}); act(g,"buy",{"item_id":"moss","quantity":1})
	return g

func roundtrip(g, label: String):
	var path = temp_root+"/"+label+".json"
	var before = g.snapshot()
	expect(g.save_to(path).ok,"write complete "+label)
	var clone = Session.new(999)
	expect(clone.load_from(path).ok,"load complete "+label)
	expect(clone.snapshot() == before,"exact state roundtrip "+label)
	expect(clone.snapshot().rng_state is String and clone.snapshot().seed is String,"lossless RNG strings "+label)
	return clone

func same_continuation(a, b):
	if a.view().phase == "shopping":
		for g in [a,b]:
			act(g,"finish_shopping"); act(g,"craft",{"recipe_id":"pen","quantity":4}); act(g,"craft",{"recipe_id":"lamp","quantity":4}); act(g,"craft",{"recipe_id":"charm","quantity":1}); act(g,"display",{"item_id":"pen","quantity":4}); act(g,"display",{"item_id":"lamp","quantity":4}); act(g,"open_shop")
	for g in [a,b]:
		if g.view().phase == "trading": finish_trade(g)
		if g.view().phase == "settled" and g.view().day < 3: act(g,"next_day")
	# Request ids intentionally differ between branches; economic state and RNG must match.
	var sa = a.snapshot(); var sb = b.snapshot(); sa.erase("requests"); sb.erase("requests")
	expect(sa == sb,"continued branch equals uninterrupted branch, including ledger/cursor/RNG")

func test_p07():
	var g = prepared(20261025)
	var clone = roundtrip(g,"after-shopping")
	same_continuation(g,clone)
	g = prepared(20261025)
	act(g,"finish_shopping"); act(g,"craft",{"recipe_id":"pen","quantity":4}); act(g,"craft",{"recipe_id":"lamp","quantity":4}); act(g,"display",{"item_id":"pen","quantity":4}); act(g,"display",{"item_id":"lamp","quantity":4}); act(g,"open_shop")
	g.advance(1500)
	clone = roundtrip(g,"mid-trading")
	same_continuation(g,clone)
	g = prepared(20261025)
	act(g,"finish_shopping"); act(g,"craft",{"recipe_id":"lamp","quantity":4}); act(g,"display",{"item_id":"lamp","quantity":4}); act(g,"open_shop")
	g.advance(3000)
	expect(not g.view().pending.is_empty(),"pending special save point")
	clone = roundtrip(g,"special-pending")
	var frozen = g.snapshot(); g.advance(50000)
	expect(g.snapshot() == frozen,"special demand freezes clock/economy/cursor")
	same_continuation(g,clone)
	g = prepared(20261025)
	act(g,"finish_shopping"); act(g,"open_shop"); finish_trade(g)
	clone = roundtrip(g,"after-settlement")
	same_continuation(g,clone)
	g = prepared(1); act(g,"finish_shopping"); act(g,"open_shop"); g.advance(500)
	act(g,"pause",{"value":true})
	frozen = g.snapshot(); g.advance(60000)
	expect(g.snapshot() == frozen,"pause freezes economic state, cursor and phase clock")
	act(g,"pause",{"value":false}); g.advance(500)
	expect(g.view().cursor == 1,"resume continues saved clock")
	# Populate persistent capabilities as well as economy before comparing a reload.
	g = prepared(7)
	act(g,"buy",{"item_id":"bell","quantity":1},"persistent-device")
	var bell_uid = g.snapshot().items.back().uid
	act(g,"finish_shopping"); act(g,"install",{"uid":bell_uid})
	act(g,"craft",{"recipe_id":"lamp","quantity":4}); act(g,"display",{"item_id":"lamp","quantity":4})
	act(g,"open_shop"); finish_trade(g); act(g,"upgrade",{"upgrade_id":"supply_pass"}); act(g,"next_day")
	act(g,"recover",{},"persistent-recovery")
	act(g,"buy",{"item_id":"pen","quantity":4})
	act(g,"finish_shopping"); act(g,"price",{"item_id":"pen","tier":"friendly"})
	act(g,"display",{"item_id":"pen","quantity":4}); act(g,"open_shop"); g.advance(1500)
	expect(g.set_paused(true).ok,"public pause before persistent-state save")
	expect(count(g,"bell","installed") == 1 and "supply_pass" in g.snapshot().upgrades,"save has nonempty equipment and upgrades")
	expect(g.snapshot().daily_recovery == 1 and g.snapshot().clock_ms == 500,"save has used daily reward and fractional clock")
	clone = roundtrip(g,"persistent-capabilities")
	var restored = clone.snapshot()
	expect(clone.command("buy",{"item_id":"bell","quantity":1},"persistent-device").code == "duplicate","reload preserves committed request across days")
	expect(clone.snapshot() == restored,"duplicate after reload cannot rebuy device")
	reject(clone,"recover")
	clone.advance(60000)
	expect(clone.snapshot() == restored,"loaded paused game preserves partial clock")
	for game in [g,clone]: expect(game.set_paused(false).ok,"resume populated save")
	same_continuation(g,clone)

func test_p08():
	for seed_value in seeds:
		var a = Session.new(int(seed_value)); var b = Session.new(int(seed_value))
		expect(a.snapshot() == b.snapshot(),"same seed gives identical supply and demand")
		for game in [a,b]: act(game,"buy",{"item_id":"moss","quantity":1},"replay-1")
		expect(a.snapshot() == b.snapshot(),"same legal sequence exactly identical")
		var c = roundtrip(a,"seed-%s" % seed_value)
		var snap = c.snapshot()
		expect(c.load_from(temp_root+"/seed-%s.json" % seed_value).ok,"repeat read same save")
		expect(c.snapshot() == snap,"repeated read never rerolls")
	var huge = Session.new(9223372036854775806)
	var huge_clone = roundtrip(huge,"large-seed")
	expect(huge_clone.snapshot().seed == "9223372036854775806","64bit seed remains exact through JSON")

func test_p09():
	test_cost_provenance()
	var g = prepared(7)
	var path = temp_root+"/damage.json"
	expect(g.save_to(path).ok,"first valid primary and backup")
	var backup_state = g.snapshot()
	act(g,"buy",{"item_id":"moss","quantity":1})
	expect(g.save_to(path).ok,"rotate valid previous primary")
	var backup_bytes = FileAccess.get_file_as_string(path+".bak")
	var bad_states = ["{\"version\":", "this is not JSON"]
	var invalid = g.snapshot(); invalid.cash = -1; bad_states.append(JSON.stringify(invalid))
	invalid = g.snapshot(); invalid.items[0].location = "installed"; bad_states.append(JSON.stringify(invalid))
	invalid = g.snapshot(); invalid.ledger = []; bad_states.append(JSON.stringify(invalid))
	for bad in bad_states:
		var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(bad); file.close()
		var loaded = Session.new(1)
		var result = loaded.load_from(path)
		expect(result.ok and result.code == "recovered_backup","damaged primary restores known valid backup")
		expect(loaded.snapshot() == backup_state,"backup state equals exact prior snapshot")
		expect(FileAccess.get_file_as_string(path) == bad,"raw damaged primary preserved")
		expect(FileAccess.get_file_as_string(path+".bak") == backup_bytes,"known valid backup preserved")
		act(loaded,"buy",{"item_id":"ink","quantity":1})
	var missing = temp_root+"/no-backup.json"
	var file = FileAccess.open(missing,FileAccess.WRITE); file.store_string("{"); file.close()
	var before = g.snapshot(); var failure = g.load_from(missing)
	expect(not failure.ok and g.snapshot() == before,"no valid backup fails without partial load/new game")
	invalid = g.snapshot(); invalid.version = 99
	file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(invalid)); file.close()
	before = g.snapshot(); failure = g.load_from(path)
	expect(not failure.ok and failure.message == "不支持的存档版本" and g.snapshot() == before,"unsupported version clear failure even with backup")
	expect(FileAccess.get_file_as_string(path+".bak") == backup_bytes,"unsupported version doesn't overwrite backup")
	var malformed = g.snapshot(); malformed.erase("rng_state")
	expect(not g.validate_snapshot(malformed).is_empty(),"missing save field rejected")

func test_noop_request_binding():
	var g = Session.new(1)
	var ledger_before = g.snapshot().ledger.duplicate(true)
	expect(g.command("pause",{"value":false},"noop-pause").ok,"successful no-op pause")
	expect(g.snapshot().requests.has("noop-pause"),"successful no-op binds request id")
	expect(g.snapshot().ledger == ledger_before,"no-op request adds no economic ledger entry")
	var before = g.snapshot()
	var conflict = g.command("recover",{},"noop-pause")
	expect(not conflict.ok and conflict.code == "request_conflict","no-op id cannot be reused for a reward")
	expect(g.snapshot() == before,"conflicting no-op request atomically rejected")
	g = Session.new(1)
	act(g,"finish_shopping")
	act(g,"price",{"item_id":"pen","tier":"standard"},"price-initial")
	ledger_before = g.snapshot().ledger.duplicate(true)
	expect(g.command("price",{"item_id":"pen","tier":"standard"},"price-noop").ok,"successful no-op price")
	expect(g.snapshot().ledger == ledger_before,"no-op price does not add a ledger row")
	act(g,"price",{"item_id":"pen","tier":"premium"},"price-new")
	before = g.snapshot()
	expect(g.command("price",{"item_id":"pen","tier":"standard"},"price-noop").code == "duplicate","old no-op price retry stays duplicate")
	expect(g.snapshot() == before and g.view().prices.pen == 14,"retry cannot restore an outdated price")
	var clone = roundtrip(g,"noop-requests")
	before = clone.snapshot()
	expect(clone.command("price",{"item_id":"pen","tier":"standard"},"price-noop").code == "duplicate","no-op binding survives reload")
	expect(clone.snapshot() == before,"reloaded no-op retry cannot mutate price")

func test_cost_provenance():
	var g = Session.new(7)
	act(g,"buy",{"item_id":"ink","quantity":1})
	var path = temp_root+"/cost-provenance.json"
	expect(g.save_to(path).ok,"save cost-bearing item and valid backup")
	var backup_bytes = FileAccess.get_file_as_string(path+".bak")
	var bad = g.snapshot(); bad.items[0].cost = 9
	expect(not g.validate_snapshot(bad).is_empty(),"isolated purchase cost corruption rejected")
	var bad_bytes = JSON.stringify(bad)
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(bad_bytes); file.close()
	var clone = Session.new(1)
	var restored = clone.load_from(path)
	expect(restored.ok and restored.code == "recovered_backup","bad cost restores known valid backup")
	expect(clone.snapshot().items.size() == 1,"recovered backup contains the purchased item")
	if clone.snapshot().items.size() != 1: return
	expect(clone.snapshot().items[0].cost == 1,"restored cost equals actual purchase price")
	expect(FileAccess.get_file_as_string(path) == bad_bytes and FileAccess.get_file_as_string(path+".bak") == backup_bytes,"cost recovery preserves damaged primary and backup")
	act(clone,"recycle",{"item_id":"ink","quantity":1})
	expect(clone.view().cash == 99,"recycled cost-one ink cannot mint four coins")
	var h = Session.new(7)
	act(h,"buy",{"item_id":"feather","quantity":2}); act(h,"buy",{"item_id":"ink","quantity":2})
	act(h,"buy",{"item_id":"bell","quantity":1}); act(h,"finish_shopping")
	act(h,"craft",{"recipe_id":"pen","quantity":2}); act(h,"install",{"uid":5})
	act(h,"display",{"item_id":"pen","quantity":2}); act(h,"undisplay",{"item_id":"pen","quantity":1})
	act(h,"uninstall",{"uid":5})
	bad = h.snapshot()
	for item in bad.items:
		if item.item_id == "pen": item.cost += 1; break
	expect(not h.validate_snapshot(bad).is_empty(),"crafted cost must equal actual consumed ingredients")
	expect(h.validate_snapshot(h.snapshot()).is_empty(),"location changes preserve valid uid and cost provenance")
	act(h,"open_shop"); finish_trade(h)
	bad = h.snapshot()
	for sale in bad.sales:
		if sale.revenue > 0:
			sale.cost += 1; bad.summaries[0].sold_cost += 1; bad.summaries[0].gross_profit -= 1; break
	expect(not h.validate_snapshot(bad).is_empty(),"realised cost cannot diverge from the consumed item and ledger")

func test_p10():
	for seed_value in seeds:
		var stationery = simulate(int(seed_value),"stationery").report
		var home = simulate(int(seed_value),"home").report
		expect(stationery.purchases != home.purchases and stationery.crafts != home.crafts,"routes differ in purchases and processing")
		expect(stationery.upgrade_days[0].id != home.upgrade_days[0].id,"routes invest differently")
		for strategy in ["conservative","self_use","rain"]: simulate(int(seed_value),strategy)
	expect(simulations.size() >= 25,"five fixed seeds times five route/strategy runs")

func test_p11():
	var g = Session.new(23)
	act(g,"buy",{"item_id":"bell","quantity":1})
	var keep = roundtrip(g,"keep-sell-origin")
	for game in [g,keep]:
		act(game,"buy",{"item_id":"timber","quantity":4}); act(game,"buy",{"item_id":"feather","quantity":2}); act(game,"buy",{"item_id":"ink","quantity":2}); act(game,"finish_shopping"); act(game,"craft",{"recipe_id":"lamp","quantity":4}); act(game,"craft",{"recipe_id":"pen","quantity":2})
	act(keep,"install",{"uid":1})
	expect("waterproof" in keep.view().inventory[5].tags,"equipped bell actually changes lamp matching rule")
	reject(keep,"display",{"item_id":"bell","quantity":1})
	act(g,"display",{"item_id":"bell","quantity":1})
	act(g,"display",{"item_id":"pen","quantity":2})
	act(keep,"display",{"item_id":"lamp","quantity":4}); act(keep,"display",{"item_id":"pen","quantity":2})
	for game in [g,keep]: act(game,"open_shop"); finish_trade(game); act(game,"next_day")
	var sold_bell = false
	for sale in g.snapshot().sales:
		if sale.item_id == "bell": sold_bell = sale.revenue == 28
	expect(sold_bell and count(g,"bell") == 0,"sell branch cash28 and no owned bell")
	expect(count(keep,"bell","installed") == 1,"keep branch device remains uniquely installed")
	for game in [g,keep]:
		for day in [2,3]:
			stock(game,"lamp",4); stock(game,"pen",2)
			act(game,"finish_shopping"); make(game,"lamp",4); make(game,"pen",2); display_all(game,"lamp"); display_all(game,"pen"); act(game,"open_shop"); finish_trade(game)
			if day < 3: act(game,"next_day")
		expect(game.view().finished,"both opportunity-cost branches finish without reacquiring device")
	var keep_rain = false; var sell_rain = false
	for sale in keep.snapshot().sales:
		if sale.day == 3 and sale.order_id == "d3-special": keep_rain = sale.revenue > 0 and "避雨铃赋予防水效果" in sale.reasons
	for sale in g.snapshot().sales:
		if sale.day == 3 and sale.order_id == "d3-special": sell_rain = sale.revenue > 0
	expect(keep_rain and not sell_rain,"retained capability actually fulfills demand that sale branch cannot")

func rain_branch(seed_value: int, solution: String):
	var g = Session.new(seed_value)
	if solution == "bell": act(g,"buy",{"item_id":"bell","quantity":1})
	for day in range(1,4):
		if day == 2:
			expect(g.view().phase == "shopping" and g.view().forecast.day == 3,"rain forecast readable before second-day purchase")
			expect("雨光苔" in g.view().forecast.text and "避雨铃" in g.view().forecast.text,"forecast explains stable source and both solutions")
		stock(g,"pen",4)
		if solution == "charm" and day == 2: stock(g,"charm",1)
		act(g,"finish_shopping"); make(g,"pen",4)
		if solution == "charm" and day == 2: make(g,"charm",1)
		if solution == "bell" and day == 1: act(g,"install",{"uid":1})
		display_all(g,"pen")
		if solution == "charm" and day == 3: display_all(g,"charm")
		act(g,"open_shop"); finish_trade(g)
		if day < 3: act(g,"next_day")
	var rain_sale = {}
	for sale in g.snapshot().sales:
		if sale.order_id == "d3-special": rain_sale = sale
	return {"game":g,"sale":rain_sale}

func test_p12():
	for seed_value in seeds:
		var prepared_rain = rain_branch(int(seed_value),"charm")
		var unprepared = rain_branch(int(seed_value),"none")
		var second = rain_branch(int(seed_value),"bell")
		expect(prepared_rain.sale.revenue == 14 and prepared_rain.sale.item_id == "charm","stockpiled charm earns explained rain premium")
		expect(unprepared.sale.revenue == 0 and count(unprepared.game,"charm") == 0,"unprepared branch gets neither goods nor rain sale")
		expect(second.sale.revenue == 15 and second.sale.item_id == "pen","second legal waterproof effect solution works")
		expect("第三日雨天需求 +25%（上限）" in prepared_rain.sale.reasons,"sale records match and event reason")
		traces.append({"scenario":"rain-stockpile","seed":seed_value,"prepared":prepared_rain.sale,"unprepared":unprepared.sale,"second_solution":second.sale})

func test_p13():
	var bulk = Session.new(1); var each = Session.new(1)
	for g in [bulk,each]:
		act(g,"buy",{"item_id":"feather","quantity":4}); act(g,"buy",{"item_id":"ink","quantity":4}); act(g,"finish_shopping")
	act(bulk,"craft",{"recipe_id":"pen","quantity":4})
	for i in range(4): act(each,"craft",{"recipe_id":"pen","quantity":1})
	expect(bulk.snapshot().items == each.snapshot().items and bulk.view().cash == each.view().cash,"batch and per-unit materials/cost/output identical without equipment")
	reject(bulk,"craft",{"recipe_id":"pen","quantity":0}); reject(bulk,"craft",{"recipe_id":"pen","quantity":-1}); reject(bulk,"craft",{"recipe_id":"pen","quantity":1})
	var batch_actions = 0; var each_actions = 0
	for e in bulk.snapshot().ledger:
		if e.kind == "craft": batch_actions += 1
	for e in each.snapshot().ledger:
		if e.kind == "craft": each_actions += 1
	expect(batch_actions == 1 and each_actions == 4,"known bulk production reduces repeated input")
	var g = Session.new(1)
	act(g,"finish_shopping"); act(g,"open_shop"); finish_trade(g)
	act(g,"upgrade",{"upgrade_id":"supply_pass"}); act(g,"next_day")
	expect(g.snapshot().supply.has("pen"),"upgrade opens stable finished-goods supplier next day")
	act(g,"buy",{"item_id":"pen","quantity":2})
	act(g,"finish_shopping"); act(g,"display",{"item_id":"pen","quantity":2}); act(g,"open_shop"); finish_trade(g)
	expect(g.view().summary.revenue > 0,"new supplier choice actually used in business")
	var used_third_slot = false
	for trace in traces:
		if trace.get("strategy","") == "stationery":
			var current = {}
			for entry in trace.ledger:
				if entry.kind == "next_day": current = {}
				if entry.kind == "display":
					current[entry.args.item_id] = true
					if current.size() == 3: used_third_slot = true
	expect(used_third_slot,"shelf upgrade's third display choice actually used")

func run(output_directory: String) -> Dictionary:
	temp_root = output_directory+"/core-save-fixtures"
	DirAccess.make_dir_recursive_absolute(temp_root)
	var fixture_data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/prototype-scenarios.json"))
	seeds = fixture_data.seeds
	run_case("P02",test_p02); run_case("P03",test_p03); run_case("P04",test_p04); run_case("P05",test_p05)
	run_case("P06",test_p06); run_case("P07",test_p07); run_case("P08",test_p08); run_case("P09",test_p09)
	run_case("P10",test_p10); run_case("P11",test_p11); run_case("P12",test_p12); run_case("P13",test_p13)
	var file = FileAccess.open(output_directory+"/core-simulations.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"seeds":seeds,"simulations":simulations},"\t")); file.close()
	file = FileAccess.open(output_directory+"/core-traces.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"traces":traces},"\t")); file.close()
	return {"schema_version":1,"suite":"prototype","cases":cases}
