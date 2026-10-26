extends RefCounted
const Session = preload("res://game/core/game_session.gd")
const Walk = preload("res://game/core/world_walk_model.gd")
var checks = 0
var failures: Array = []
var traces: Array = []
var output_dir = "/private/tmp/p10-world-first"
var request_serial = 0
var cases: Array = []
var simulations: Array = []
var seeds: Array = []
var fixture_data: Dictionary = {}

func expect(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message); push_error(message)

func act(g, target: String, action: String, payload: Dictionary = {}):
	request_serial += 1
	var result = g.command("world_interact",{"target_id":target,"action":action,"payload":payload},"test-%d" % request_serial)
	expect(result.ok,"world action %s/%s: %s" % [target,action,str(result)])
	expect(g.validate_snapshot(g.snapshot()) == "","world snapshot validates after "+action+": "+g.validate_snapshot(g.snapshot()))
	return result

func pos(g) -> Vector2:
	var p = g.snapshot().world.player; return Vector2(p.x,p.y)

func move_to(g, target: Vector2):
	for n in range(200):
		var delta = target-pos(g)
		if delta.length() < 1.7: break
		var axis = delta/8.0 if delta.length() < 8 else delta.normalized()
		g.command("world_input",{"move_x":axis.x,"move_y":axis.y}); var result = g.advance(50)
		if not result.ok: expect(false,"movement tick succeeds"); break
	g.command("world_input",{"move_x":0,"move_y":0})
	expect(pos(g).distance_to(target) < 2,"normal movement reaches waypoint "+str(target))

func walk_to(g, id: String):
	var region = g.snapshot().world.region_id; var object = Walk.object(id); var anchor = Vector2(object.anchor.x,object.anchor.y)
	expect(object.region_id == region,"navigation stays in current region")
	if pos(g).distance_to(anchor) < 40 and Walk.clear_line(region,pos(g),anchor): return
	var start = Vector2i(roundi(pos(g).x/16),roundi(pos(g).y/16)); var queue = [start]; var came = {start:start}; var found = start; var index = 0; var reached = false
	while index < queue.size():
		var cell: Vector2i = queue[index]; index += 1; var p = Vector2(cell)*16.0
		if p.distance_to(anchor) < 28 and Walk.clear_line(region,p,anchor): found = cell; reached = true; break
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next = cell+direction
			if not came.has(next) and Walk.clear_position(region,Vector2(next)*16.0): came[next] = cell; queue.append(next)
	expect(reached,"reachable interaction anchor: "+id)
	if not reached: return
	var points = []
	while found != start: points.push_front(Vector2(found)*16.0); found = came[found]
	for p in points: move_to(g,p)
	expect(pos(g).distance_to(anchor) <= 56 and Walk.clear_line(region,pos(g),anchor),"walk reaches real action range: "+id)

func suggested(g, target: String, action: String) -> Dictionary:
	for row in g.view().interactions:
		if row.target_id == target and row.action == action: return row.payload.duplicate(true)
	return {}

func first_income_report() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(output_dir)
	for manual in [true,false]:
		var g = Session.new(1); var initial = g.snapshot()
		expect(initial.profile_id == "world-slice-v1" and initial.phase == "preparation","world is fresh default preparation")
		walk_to(g,"pantry"); act(g,"pantry","take",suggested(g,"pantry","take"))
		expect(g.snapshot().world.carried_uids.size() == 6,"default three recipes move six inherited material UIDs")
		walk_to(g,"prep"); act(g,"prep","put",suggested(g,"prep","put")); act(g,"prep","cook",{"recipe_id":"floating_pie","quantity":3})
		var job = g.snapshot().world.stations[0].job.duplicate(true)
		expect(job.output_uids.size() == 3 and job.remaining_ms == 2000,"cook creates three real in-progress output UIDs")
		g.advance(1950); expect(g.snapshot().world.stations[0].job.remaining_ms == 50,"cooking is not instant")
		g.advance(50); expect(g.snapshot().world.stations[0].job == null,"2s completes exactly once")
		act(g,"prep","take",suggested(g,"prep","take"))
		walk_to(g,"door-bell"); act(g,"door-bell","open_shop")
		if manual:
			walk_to(g,"seat-1")
			for n in range(300):
				if g.snapshot().service.orders[0].status == "waiting": break
				g.advance(50)
			var payload = suggested(g,"seat-1","serve"); var cash = g.snapshot().cash
			act(g,"seat-1","serve",payload)
			expect(g.snapshot().cash == cash and g.snapshot().service.reservations[0].remaining_ms == 50,"hand serve reserves without immediate payment")
			g.advance(50); expect(g.snapshot().cash == cash+14,"next fixed step pays base12 plus optional tip2 once")
		else:
			walk_to(g,"pass"); act(g,"pass","put",suggested(g,"pass","put"))
			for n in range(500):
				if not g.snapshot().sales.is_empty(): break
				g.advance(50)
			expect(not g.snapshot().sales.is_empty() and g.snapshot().sales[0].tip == 0 and g.snapshot().sales[0].paid_total == 12,"automatic floating delivery pays actual price with zero tip")
		var v = g.view()
		expect(g.snapshot().sales[0].uid in job.output_uids,"sale consumes an actual batch UID")
		traces.append({"manual":manual,"cash":v.cash,"sales":v.sales,"view":v,"snapshot":g.snapshot()})
		var file = FileAccess.open(output_dir+("/manual-view.json" if manual else "/automatic-view.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(v,"\t",true,true)); file.close()
	return {"checks":checks,"failures":failures,"traces":traces}

func audit(g, label: String = ""):
	var error = g.validate_snapshot(g.snapshot()); expect(error == "","valid world state "+label+": "+error)

func reject(g, kind: String, args: Dictionary = {}, request: String = ""):
	var before = g.snapshot(); var result = g.command(kind,args,request)
	expect(not result.ok and result.code != "" and before == g.snapshot(),"atomic rejected "+kind+": "+str(result))

func fixture(state: Dictionary, label: String):
	request_serial += 1; var path = output_dir+"/boundary-%s-%d.json" % [label,request_serial]
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(state,"\t",true,true)); file.close()
	var g = Session.new(1); var loaded = g.load_from(path)
	expect(loaded.ok,"controlled boundary loads "+label+": "+str(loaded)); audit(g,label)
	return g

func roundtrip(g, label: String):
	request_serial += 1; var path = output_dir+"/save-%s-%d.json" % [label,request_serial]
	var expected = g.snapshot(); expected.world.input = {"move_x":0,"move_y":0}
	if not expected.expedition.is_empty():
		var model = preload("res://game/expedition/expedition_model.gd"); model.set_input(expected.expedition,{})
		expected = g._game._normalize(expected)
	expect(g.save_to(path).ok,"real world save "+label)
	var restored = Session.new(99); var loaded = restored.load_from(path)
	expect(loaded.ok and restored.snapshot() == expected,"exact restore (only input cleared) "+label+": "+str(loaded)); audit(restored,label)
	return restored

func set_pose(g, p: Vector2, region: String = "shop"):
	var s = g.snapshot(); s.world.region_id = region; s.world.player.x = p.x; s.world.player.y = p.y
	return fixture(s,"position-boundary")

func travel(g, region: String):
	if g.snapshot().world.region_id == region: return
	var portal = "shop-exit" if region == "lane" else "lane-home"
	walk_to(g,portal); act(g,portal,"enter")

func buy(g, purchases: Dictionary):
	travel(g,"lane"); walk_to(g,"vendor")
	for id in purchases: act(g,"vendor","buy",{"item_id":id,"quantity":purchases[id]})
	travel(g,"shop")

func cook_batch(g, recipe: String, quantity: int, take_ready: bool = true):
	walk_to(g,"recipe-book"); act(g,"recipe-book","plan",{"recipe_id":recipe,"quantity":quantity})
	for trip in range(3):
		walk_to(g,"pantry"); var payload = suggested(g,"pantry","take")
		if payload.uids.is_empty(): break
		var inputs = preload("res://game/core/catalog.gd").RECIPES[recipe].inputs; var units = 0
		for id in inputs: units += inputs[id]
		var portions = mini(quantity-int(g.snapshot().world.stations[0].input_uids.size()/units),int(12/units)); var expected_uids = []
		for id in inputs:
			var available = g.snapshot().items.filter(func(i): return i.item_id == id and i.location == "bag"); available.sort_custom(func(a,b): return a.uid < b.uid)
			for i in range(inputs[id]*portions): expected_uids.append(available[i].uid)
		expect(payload.uids == expected_uids,"bundle selects exactly the lowest whole-portion UIDs independent of bag order")
		act(g,"pantry","take",payload)
		if units == 3 and quantity == 6:
			expect(payload.uids.size() == (12 if trip == 0 else 6),"both three-input recipes use exactly4+2 portions")
			if trip == 0: reject(g,"world_interact",{"target_id":"pantry","action":"take","payload":payload}); g = roundtrip(g,"batch6-carried")
		walk_to(g,"prep"); act(g,"prep","put",suggested(g,"prep","put"))
		var station = g.snapshot().world.stations[0]; var needed = units*quantity
		if units == 3 and quantity == 6 and trip == 0:
			reject(g,"world_interact",{"target_id":"prep","action":"cook","payload":{"recipe_id":recipe,"quantity":6}}); g = roundtrip(g,"batch6-loaded")
		if station.input_uids.size() == needed: break
	walk_to(g,"prep"); act(g,"prep","cook",{"recipe_id":recipe,"quantity":quantity}); g.advance(2000); audit(g,"cooked "+recipe)
	if take_ready and not g.snapshot().world.stations[0].output_uids.is_empty():
		act(g,"prep","take",suggested(g,"prep","take")); walk_to(g,"pass"); act(g,"pass","put",suggested(g,"pass","put"))
	return g

func complete_wave(g):
	for n in range(4):
		if g.snapshot().phase != "trading": break
		g.advance(60000)
	expect(g.snapshot().phase in ["intermission","closing"],"actual wave completes with arrived/served/left customers")
	audit(g,"wave complete")

func open_wave(g):
	walk_to(g,"door-bell")
	if g.snapshot().phase == "preparation": act(g,"door-bell","open_shop")
	else: act(g,"door-bell","start_wave",{"wave_id":g.snapshot().service.next_wave_id})

func normal_night(seed_value: int, route: String, tier: String):
	var g = Session.new(seed_value)
	walk_to(g,"menu-board"); var menu = ["floating_pie","moon_stew"] if route == "hot" else ["floating_pie","ember_soup"]
	act(g,"menu-board","menu",{"item_ids":menu,"tiers":{menu[0]:tier,menu[1]:tier}})
	cook_batch(g,"floating_pie",3); open_wave(g); complete_wave(g)
	if route == "quick": buy(g,{"flour":4,"pumpkin":6,"ember_herb":2}); cook_batch(g,"floating_pie",2)
	else: buy(g,{"pumpkin":4,"cream":4}); cook_batch(g,"moon_stew",4)
	open_wave(g); complete_wave(g)
	if route == "quick": cook_batch(g,"floating_pie",2); cook_batch(g,"ember_soup",2)
	else: expect(g.snapshot().service.held_uids.size() == 2,"hot route physically preserves two leftover UIDs for final warm demand")
	open_wave(g); complete_wave(g); walk_to(g,"ledger"); g.set_paused(true); act(g,"ledger","settle"); g.set_paused(false)
	expect(g.snapshot().sales.all(func(s): return s.tip == 0),"required normal route is automatic and never depends on tips")
	expect(g.snapshot().cash >= 125 and g.snapshot().daily_recovery == 0,"normal route affords110 growth and15 basic next-night ingredients")
	simulations.append({"seed":seed_value,"route":route,"tier":tier,"cash":g.snapshot().cash,"sales":g.snapshot().sales,"ledger":g.snapshot().ledger,"remaining":g.snapshot().items})
	return g

func test_movement():
	expect(Walk.LAYOUT == Session.new(1)._game._normalize(fixture_data.configuration.layout),"baked production geometry equals frozen verification layout")
	var g = Session.new(1)
	for id in ["pantry","prep","pass","recipe-book","menu-board","ledger","seat-1","seat-2","seat-3","seat-4","door-bell","shop-exit"]: walk_to(g,id)
	act(g,"shop-exit","enter"); var carried = g.snapshot().world.carried_uids.duplicate()
	for id in ["vendor","garden-gate","lane-home"]: walk_to(g,id)
	act(g,"lane-home","enter"); expect(g.snapshot().world.carried_uids == carried,"portals do not clone carry state")
	expect(g.snapshot().world.player == {"x":1192,"y":580,"facing":"sw"},"portal uses frozen destination pose including facing")
	var outcomes = []
	for partition in fixture_data.configuration.frame_partitions_ms:
		var branch = set_pose(Session.new(1),Vector2(750,580)); branch.command("world_input",{"move_x":1,"move_y":1})
		for delta in partition: branch.advance(int(delta))
		outcomes.append(branch.snapshot())
		expect(absf(pos(branch).distance_to(Vector2(750,580))-160) < 0.1,"diagonal normalizes to160 units per second")
		audit(branch,"partition")
	expect(outcomes[0] == outcomes[1] and outcomes[1] == outcomes[2],"frame partitions produce identical whole snapshot")
	for region in ["shop","lane"]:
		for collider in Walk.LAYOUT.regions[region].colliders:
			var edge = Vector2(collider.x+collider.width/2.0+20,collider.y)
			if not Walk.clear_position(region,edge): continue
			var branch = set_pose(Session.new(1),edge,region)
			branch.command("world_input",{"move_x":-1,"move_y":0}); branch.advance(1000)
			expect(pos(branch).x >= collider.x+collider.width/2.0+12-0.01,"circle sweep blocks "+collider.id)
			expect(Walk.clear_position(region,pos(branch)),"collision ends outside actual geometry")
	var stopped = g.snapshot(); g.command("world_input",{"move_x":0,"move_y":0}); g.advance(500)
	expect(g.snapshot().world.player == stopped.world.player,"released axes do not move or change facing")

func test_spatial_guards():
	var g = Session.new(1)
	for args in [{"target_id":"missing","action":"take","payload":{"uids":[2]}},{"target_id":"vendor","action":"buy","payload":{"item_id":"flour","quantity":1}},{"target_id":"pantry","action":"settle","payload":{}}]: reject(g,"world_interact",args)
	for input in [{"move_x":true,"move_y":0},{"move_x":2,"move_y":0},{"move_x":NAN,"move_y":0}]: reject(g,"world_input",input)
	for kind in ["craft","display","fulfill","start_expedition","buy"]: reject(g,kind,{})
	var state = g.snapshot()
	for n in range(2000): g.command("world_input",{"move_x":1 if n%2 else 0,"move_y":0},"ignored-%d" % n)
	expect(g.snapshot().requests == state.requests and g.snapshot().ledger == state.ledger,"2000 held setters allocate no persistent requests or ledger rows")
	g.command("world_input",{"move_x":0,"move_y":0})
	walk_to(g,"pantry"); var args = {"target_id":"pantry","action":"take","payload":suggested(g,"pantry","take")}
	expect(g.command("world_interact",args,"take-once").ok,"first spatial request commits")
	var taken = g.snapshot(); expect(g.command("world_interact",args,"take-once").code == "duplicate" and taken == g.snapshot(),"same request cannot take twice")
	var changed = args.duplicate(true); changed.action = "put"; reject(g,"world_interact",changed,"take-once")
	reject(g,"world_interact",args,"different-take")
	act(g,"pantry","put",suggested(g,"pantry","put"))
	for uids in [[2,2],[999],[true],null]: reject(g,"world_interact",{"target_id":"pantry","action":"take","payload":{"uids":uids}})
	var money = args.duplicate(true); money.payload.paid_total = 999
	reject(g,"world_interact",money)
	var blocked = 0
	for object in Walk.LAYOUT.objects:
		var anchor = Vector2(object.anchor.x,object.anchor.y)
		for x in range(-56,57,4):
			for y in range(-56,57,4):
				var point = anchor+Vector2(x,y)
				if point.distance_to(anchor) <= 56 and Walk.clear_position(object.region_id,point) and not Walk.clear_line(object.region_id,point,anchor):
					var branch = set_pose(Session.new(1),point,object.region_id)
					reject(branch,"world_interact",{"target_id":object.id,"action":object.actions[0],"payload":{}}); blocked += 1
					break
			if blocked > 0: break
		if blocked > 0: break
	expect(blocked > 0,"a legal near-side position still rejects actual blocked line of sight")
	for distance in [56.0,56.01]:
		var branch = set_pose(Session.new(1),Vector2(430,466+distance))
		var action = {"target_id":"recipe-book","action":"plan","payload":{"recipe_id":"floating_pie","quantity":3}}
		if distance == 56: expect(branch.command("world_interact",action).ok,"exact56 range accepted")
		else: reject(branch,"world_interact",action)
	walk_to(g,"recipe-book"); g.set_paused(true); var paused = g.snapshot(); g.advance(60000)
	expect(g.snapshot() == paused,"all world clocks freeze while paused")
	reject(g,"world_input",{"move_x":1,"move_y":0}); expect(g.command("world_input",{"move_x":0,"move_y":0}).ok,"paused input may clear only")
	act(g,"recipe-book","plan",{"recipe_id":"floating_pie","quantity":6})
	reject(g,"world_interact",{"target_id":"pantry","action":"take","payload":{"uids":[2]}})
	g.set_paused(false); audit(g,"paused book")
	for pair in [["pantry","take"],["pantry","put"],["prep","cook"],["seat-1","serve"],["shop-exit","enter"],["door-bell","open_shop"],["door-bell","start_wave"]]:
		var anchor = Walk.object(pair[0]).anchor; var branch = set_pose(Session.new(1),Vector2(anchor.x,anchor.y)); branch.set_paused(true)
		var before = branch.snapshot(); var rejected = branch.command("world_interact",{"target_id":pair[0],"action":pair[1],"payload":{}})
		expect(not rejected.ok and rejected.code == "paused" and before == branch.snapshot(),"paused physical action rejects before dispatch: "+pair[1])
	var books = Session.new(1)
	walk_to(books,"menu-board"); books.set_paused(true); act(books,"menu-board","menu",{"item_ids":["floating_pie","moon_stew"],"tiers":{"floating_pie":"standard"}}); books.set_paused(false)
	walk_to(books,"prep"); books.set_paused(true); act(books,"prep","uninstall",{"uid":1}); act(books,"prep","install",{"uid":1}); books.set_paused(false)
	travel(books,"lane"); walk_to(books,"vendor"); books.set_paused(true)
	act(books,"vendor","buy",{"item_id":"flour","quantity":1}); act(books,"vendor","recycle",{"item_id":"flour","quantity":1}); act(books,"vendor","recover"); books.set_paused(false)
	travel(books,"shop"); cook_batch(books,"floating_pie",3,false); act(books,"prep","take",suggested(books,"prep","take")); walk_to(books,"pantry"); act(books,"pantry","put",suggested(books,"pantry","put"))
	walk_to(books,"recipe-book"); books.set_paused(true); act(books,"recipe-book","consume",{"item_id":"floating_pie","quantity":1}); act(books,"recipe-book","equip_weapon",{"weapon_id":"bolt_wand"})

func test_cooking_and_carry():
	var g = Session.new(1); walk_to(g,"pantry"); act(g,"pantry","take",suggested(g,"pantry","take"))
	var ids = g.snapshot().world.carried_uids.duplicate(); g = roundtrip(g,"carried-ingredients")
	travel(g,"lane"); travel(g,"shop"); expect(g.snapshot().world.carried_uids == ids,"two-region carry retains identical UID ownership")
	walk_to(g,"prep"); act(g,"prep","put",suggested(g,"prep","put")); g = roundtrip(g,"loaded-station")
	act(g,"prep","take",suggested(g,"prep","take")); expect(g.snapshot().world.carried_uids == ids,"unstarted station returns original UIDs")
	act(g,"prep","put",suggested(g,"prep","put")); act(g,"prep","cook",{"recipe_id":"floating_pie","quantity":3})
	g.advance(1000); var clone = roundtrip(g,"cooking-midway")
	g.set_paused(true); var frozen = g.snapshot(); g.advance(5000); expect(g.snapshot() == frozen,"paused job never finishes from wall time")
	g.set_paused(false); g.advance(1000); clone.advance(1000); expect(g.snapshot() == clone.snapshot(),"cooking disk restore continues once with same output UIDs")
	g = roundtrip(g,"ready-output"); act(g,"prep","take",suggested(g,"prep","take")); g = roundtrip(g,"carried-dish")
	reject(g,"world_interact",{"target_id":"prep","action":"put","payload":{"uids":g.snapshot().world.carried_uids}})
	audit(g,"carried dish")
	var rare = farm_rares()
	var rare_count = rare.snapshot().items.filter(func(i): return i.item_id == "sparkcap").size()
	expect(rare_count >= 6,"actual E02 expedition acquired six rare ingredient UIDs for three-input batch")
	if rare_count < 6: return
	buy(rare,{"pumpkin":6,"ember_herb":6}); walk_to(rare,"recipe-book"); act(rare,"recipe-book","plan",{"recipe_id":"star_soup","quantity":6})
	var portions = []
	for expected_units in [12,6]:
		walk_to(rare,"pantry"); var bundle = suggested(rare,"pantry","take")
		expect(bundle.uids.size() == expected_units,"three-input plan6 supplies complete4+2 portion trips")
		var partial = bundle.duplicate(true); partial.uids.pop_back()
		reject(rare,"world_interact",{"target_id":"pantry","action":"take","payload":partial})
		act(rare,"pantry","take",bundle); portions.append_array(bundle.uids); walk_to(rare,"prep"); act(rare,"prep","put",suggested(rare,"prep","put"))
		if expected_units == 12: reject(rare,"world_interact",{"target_id":"prep","action":"cook","payload":{"recipe_id":"star_soup","quantity":4}})
	expect(rare.snapshot().world.stations[0].input_uids.size() == 18,"two trips fill exactly18 original ingredient UIDs")
	act(rare,"prep","cook",{"recipe_id":"star_soup","quantity":6}); rare.advance(2000); audit(rare,"rare batch6")
	expect(rare.snapshot().world.stations[0].output_uids.size() == 6 and not rare.snapshot().items.any(func(i): return i.uid in portions),"one cook6 consumes18 originals and creates exactly6 real outputs")
	test_recipe_matrix()
	test_holding_limit()

func farm_rares(g = null):
	if g == null: g = Session.new(1)
	travel(g,"lane"); walk_to(g,"garden-gate"); act(g,"garden-gate","enter")
	var driver = preload("res://tests/expedition/rain_driver.gd").new("canal",true)
	driver.route_points.append_array([Vector2(650,100),Vector2(540,100),Vector2(415,95)])
	for n in range(5000):
		if g.snapshot().phase != "expedition": break
		var input = driver.next_input(g.snapshot().expedition)
		expect(g.command("expedition_input",input).ok and g.advance(50).ok,"real rare-material combat/movement advances")
	expect(g.snapshot().phase == "preparation","rare route returns through actual E02 entrance")
	audit(g,"rare harvest")
	traces.append({"scenario":"real-three-input-material-source","snapshot":g.snapshot()})
	return g

func test_recipe_matrix():
	# Controlled boundary snapshot, explicitly not obtainable-route evidence:
	# E02 currently supports days1..2 and one elite unit/run. Extend an isolated
	# previous-day pickup's quantity and its UID/cost ledger consistently so the
	# frozen batch6 boundary can exercise actual save/load and public commands.
	var origin = farm_rares(); travel(origin,"shop")
	for wave in range(3): open_wave(origin); complete_wave(origin)
	walk_to(origin,"ledger"); act(origin,"ledger","settle"); act(origin,"ledger","next_day")
	var boundary = origin.snapshot()
	for row in boundary.ledger:
		if row.kind != "pickup": continue
		for pickup in row.args.pickups:
			if pickup.item_id != "moonheart": continue
			var record = boundary.collected_drops[row.args.run_id+"|"+pickup.drop_id]
			for n in range(5):
				origin._game._add(boundary,"moonheart",0)
				row.created.append(boundary.items.back().duplicate(true)); record.uids.append(boundary.items.back().uid)
			pickup.quantity += 5; record.quantity += 5; row.moves.moonheart += 5
	boundary.items.reverse() # Inventory order must not affect lowest-UID selection.
	origin = fixture(boundary,"controlled-elite-batch-boundary")
	traces.append({"scenario":"controlled-elite-batch-boundary","not_normal_economy":true,"reason":"frozen ingredient_bundle_cases; E02 only days1..2, one elite unit per run"})
	for recipe in preload("res://game/core/catalog.gd").RECIPES:
		for quantity in [1,3,6]:
			var g = fixture(origin.snapshot(),"controlled-batch-"+recipe+str(quantity))
			var definition = preload("res://game/core/catalog.gd").RECIPES[recipe]; var purchases = {}
			for id in definition.inputs:
				if id in ["flour","pumpkin","cream","ember_herb"]:
					var owned = g.snapshot().items.filter(func(i): return i.item_id == id and i.location == "bag").size()
					var shortage = definition.inputs[id]*quantity-owned
					if shortage > 0: purchases[id] = shortage
			buy(g,purchases)
			if quantity == 6 and recipe in ["star_soup","comet_pie"]:
				var short = fixture(g.snapshot(),"shortage-"+recipe); var rare_id = "sparkcap" if recipe == "star_soup" else "moonheart"
				var count = short.snapshot().items.filter(func(i): return i.item_id == rare_id).size()
				travel(short,"lane"); walk_to(short,"vendor"); act(short,"vendor","recycle",{"item_id":rare_id,"quantity":count-3}); travel(short,"shop")
				walk_to(short,"recipe-book"); act(short,"recipe-book","plan",{"recipe_id":recipe,"quantity":6}); walk_to(short,"pantry")
				var available = suggested(short,"pantry","take")
				expect(available.uids.is_empty(),"three available rare units do not silently shrink required four-portion trip")
				reject(short,"world_interact",{"target_id":"pantry","action":"take","payload":available})
			g = cook_batch(g,recipe,quantity,false)
			var ready = g.snapshot().world.stations[0].output_uids
			expect(ready.size() == quantity and g.snapshot().items.filter(func(i): return i.uid in ready).all(func(i): return i.item_id == recipe),"all five recipes support real batch "+str(quantity)+": "+recipe)
			traces.append({"scenario":"five-recipe-batch-matrix","recipe":recipe,"quantity":quantity,"ready_uids":ready,"ledger":g.snapshot().ledger})
	var full = Session.new(1); buy(full,{"flour":12,"pumpkin":12}); cook_batch(full,"floating_pie",6,false); cook_batch(full,"floating_pie",6,false)
	walk_to(full,"recipe-book"); act(full,"recipe-book","plan",{"recipe_id":"floating_pie","quantity":3}); walk_to(full,"pantry"); act(full,"pantry","take",suggested(full,"pantry","take")); walk_to(full,"prep"); act(full,"prep","put",suggested(full,"prep","put"))
	expect(full.snapshot().world.stations[0].output_uids.size() == 12,"two real batches fill the twelve ready slots")
	reject(full,"world_interact",{"target_id":"prep","action":"cook","payload":{"recipe_id":"floating_pie","quantity":3}})

func test_holding_limit():
	var g = Session.new(1); cook_batch(g,"floating_pie",3); open_wave(g); complete_wave(g)
	buy(g,{"pumpkin":6,"cream":6}); cook_batch(g,"moon_stew",6); open_wave(g); complete_wave(g)
	expect(g.snapshot().service.held_uids.size() == 3,"six cooked minus two hearty sales preserves at most three portions")
	var leftovers = g.snapshot().items.filter(func(i): return i.item_id == "moon_stew")
	expect(leftovers.size() == 4 and leftovers.filter(func(i): return i.temperature == "cooled").size() == 1,"overflow fourth stew cools instead of receiving free capacity")
	var original_tags = leftovers[0].intrinsic_tags
	walk_to(g,"prep"); act(g,"prep","uninstall",{"uid":1})
	expect(g.snapshot().service.held_uids.is_empty() and g.snapshot().items.filter(func(i): return i.item_id == "moon_stew").all(func(i): return i.temperature == "cooled" and i.intrinsic_tags == original_tags),"removing pot cools leftovers while preserving intrinsic recipe identity")
	open_wave(g); complete_wave(g)
	expect(g.snapshot().sales.filter(func(s): return s.wave_id == "n1-w3" and s.revenue > 0).is_empty(),"cooled leftovers cannot fulfill the warm final-wave demand")

func manual_origin():
	var g = Session.new(1); walk_to(g,"pantry"); act(g,"pantry","take",suggested(g,"pantry","take")); walk_to(g,"prep")
	act(g,"prep","put",suggested(g,"prep","put")); act(g,"prep","cook",{"recipe_id":"floating_pie","quantity":3}); g.advance(2000); act(g,"prep","take",suggested(g,"prep","take"))
	open_wave(g); walk_to(g,"seat-1"); g.advance(12000); audit(g,"arrived manual origin")
	return g

func test_delivery():
	first_income_report()
	var source = manual_origin().snapshot()
	for boundary in fixture_data.configuration.manual_delivery_cases.cases:
		var s = source.duplicate(true); var order_index = 0 if boundary.preferred else 1; var order_id = "n1-w1-c%02d" % (order_index+1)
		for orders in [s.night.queues["n1-w1"],s.customers,s.service.orders]: orders[order_index].budget = int(boundary.budget)
		s.night.waves[0].budget_min = mini(23,int(boundary.budget)); s.night.waves[0].budget_max = 30
		var g = fixture(s,"tip-budget-"+boundary.id)
		if boundary.channel == "manual":
			walk_to(g,"seat-%d" % (order_index+1)); var uid = g.snapshot().world.carried_uids[0]
			var args = {"target_id":"seat-%d" % (order_index+1),"action":"serve","payload":{"order_id":order_id,"uid":uid}}
			if boundary.get("expected_rejection",false): reject(g,"world_interact",args); continue
			var result = g.command("world_interact",args,"manual-once"); expect(result.ok,"controlled boundary uses real serve")
			var before = g.snapshot(); var clone = roundtrip(g,"manual50-"+boundary.id)
			reject(g,"world_interact",args,"new-request-same-reservation")
			g.advance(50); clone.advance(50); expect(g.snapshot() == clone.snapshot(),"frozen manual quote commits identically after restore")
			var sale = g.snapshot().sales.back()
			expect(sale.tip == int(boundary.expected_tip) and sale.paid_total == int(boundary.expected_paid_total) and g.snapshot().cash-before.cash == sale.paid_total,"real tip/budget arithmetic "+boundary.id)
			var paid = g.snapshot(); expect(g.command("world_interact",args,"manual-once").code == "duplicate" and paid == g.snapshot(),"same request after delivery is inert")
			reject(g,"world_interact",args,"new-request-after-sale"); roundtrip(g,"tip-paid-"+boundary.id)
		else:
			walk_to(g,"pass"); act(g,"pass","put",suggested(g,"pass","put")); g.advance(2000)
			expect(g.snapshot().sales[0].tip == 0,"preferred customer still pays no automatic tip")

func test_nights_and_growth():
	for seed_value in seeds:
		for route in ["quick","hot"]:
			for tier in fixture_data.configuration.price_tiers:
				var g = normal_night(int(seed_value),route,tier); var settled = g.snapshot()
				for upgrade in ["shelf","field_kit"]:
					var branch = fixture(settled,"growth-"+upgrade); branch.set_paused(true); act(branch,"ledger","upgrade",{"upgrade_id":upgrade}); act(branch,"ledger","next_day"); branch.set_paused(false)
					buy(branch,{"flour":3,"pumpkin":3}); cook_batch(branch,"floating_pie",3,upgrade != "shelf")
					if upgrade == "shelf":
						expect(branch.snapshot().world.stations[0].output_uids.size() == 3,"completed output waits for next relay step")
						var before = branch.snapshot(); branch.advance(50)
						expect(branch.snapshot().world.stations[0].output_uids.is_empty() and branch.snapshot().world.carried_uids.is_empty() and branch.snapshot().cash == before.cash,"relay replaces one physical carrying trip, creates no cash")
					else:
						walk_to(branch,"recipe-book"); act(branch,"recipe-book","equip_weapon",{"weapon_id":"fan_wand"})
						expect(branch.snapshot().progression.equipped_weapon == "fan_wand","legitimate weapon growth equips next morning")
						if route == "quick" and tier == "standard":
							travel(branch,"lane"); walk_to(branch,"garden-gate"); act(branch,"garden-gate","enter")
							branch.command("expedition_input",{"aim_x":1,"aim_y":0,"cast":true}); var fired = branch.advance(50)
							expect(fired.events.any(func(e): return e.type == "cast" and e.weapon_id == "fan_wand" and e.projectile_count == 3),"earned fan changes actual E02 projectile behavior")
							expect(branch.command("leave_expedition").ok,"legal growth expedition can return")
					audit(branch,"next-night basics"); roundtrip(branch,"next-night-"+upgrade)
	var poor = Session.new(7); buy(poor,{"flour":12,"pumpkin":12}); expect(poor.snapshot().cash == 0,"legitimate purchases produce zero-cash boundary")
	travel(poor,"lane"); walk_to(poor,"vendor"); act(poor,"vendor","recover"); expect(poor.snapshot().cash == 12 and poor.view().dish_income == 0,"zero-fund rescue remains non-dish income")
	reject(poor,"world_interact",{"target_id":"vendor","action":"recover","payload":{}})
	var resale = Session.new(1); walk_to(resale,"prep"); act(resale,"prep","uninstall",{"uid":1}); travel(resale,"lane"); walk_to(resale,"vendor"); act(resale,"vendor","recycle",{"item_id":"stirring_cauldron","quantity":1})
	expect(resale.snapshot().cash == 78 and resale.view().dish_income == 0,"selling inherited cauldron has real18 opportunity cost without dish income")

func test_save_and_expedition():
	var g = manual_origin(); var original = g.snapshot(); var path = output_dir+"/corrupt-world.json"; expect(g.save_to(path).ok,"world backup created")
	for key in ["daily_recovery","expedition_attempts","summaries"]:
		var bad = Session.new(1).snapshot()
		bad[key] = {"daily_recovery":1,"expedition_attempts":{"1":"n1-expedition"},"summaries":[null]}[key]
		expect(g.validate_snapshot(bad) != "","orphan recovery, expedition or settlement rejected: "+key)
	for section in ["player","input","stations","plan","intro_flags"]:
		for value in [null,false,[],"invalid"]:
			var bad = original.duplicate(true); bad.world[section] = value
			expect(g.validate_snapshot(bad) != "","nested malformed world type rejected: "+section)
	var no_wave_commit = original.duplicate(true); no_wave_commit.commits.erase("wave:n1-w1")
	expect(g.validate_snapshot(no_wave_commit) != "","active wave cannot lose its idempotent start commit")
	for section in ["world","service","items","customers"]:
		var bad = original.duplicate(true)
		if section in ["items","customers"]: bad[section][0] = null
		else: bad[section] = false
		var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(bad,"\t",true,true)); file.close()
		var main_hash = FileAccess.get_sha256(path); var backup_hash = FileAccess.get_sha256(path+".bak"); var clone = Session.new(1)
		expect(g.validate_snapshot(bad) != "" and clone.load_from(path).code == "recovered_backup" and clone.snapshot() == original,"malformed world section falls back atomically: "+section)
		expect(main_hash == FileAccess.get_sha256(path) and backup_hash == FileAccess.get_sha256(path+".bak"),"damaged primary and backup bytes preserved")
	for profile in ["prototype-v1","rain-night-v1"]:
		var old = Session.new(7,profile); var old_path = output_dir+"/controlled-old-"+profile+".json"; expect(old.save_to(old_path).ok,"isolated old test copy created")
		var hashes = [FileAccess.get_sha256(old_path),FileAccess.get_sha256(old_path+".bak")]
		expect(not g.load_from(old_path).ok and not g.save_to(old_path).ok,"world rejects explicit old-profile test copies")
		expect(hashes == [FileAccess.get_sha256(old_path),FileAccess.get_sha256(old_path+".bak")],"old controlled primary/backup untouched")
	var explorer = Session.new(23); travel(explorer,"lane"); walk_to(explorer,"garden-gate"); act(explorer,"garden-gate","enter")
	expect(explorer.snapshot().expedition.ruleset == "rain-night-v1","world reuses the actual E02 ruleset")
	reject(explorer,"world_input",{"move_x":1,"move_y":0}); var world_before = explorer.snapshot().world.duplicate(true)
	var driver = preload("res://tests/expedition/rain_driver.gd").new("shelf",false)
	for n in range(2400):
		if explorer.snapshot().phase != "expedition": break
		var input = driver.next_input(explorer.snapshot().expedition)
		expect(explorer.command("expedition_input",input).ok,"world entry accepts real E02 input"); expect(explorer.advance(50).ok,"one E tick advances")
		if n == 100: roundtrip(explorer,"real-expedition")
	expect(explorer.snapshot().phase == "preparation" and explorer.snapshot().world.region_id == "lane" and explorer.snapshot().world.player == {"x":1384,"y":256,"facing":"sw"},"real entrance return restores saved lane pose")
	expect(explorer.snapshot().world.tick == world_before.tick and explorer.snapshot().world.remainder_ms == world_before.remainder_ms,"world jobs/time freeze under E tick owner")
	expect(not explorer.snapshot().collected_drops.is_empty(),"real E02 resource acquisition creates actual pantry UID")
	audit(explorer,"actual E return"); roundtrip(explorer,"expedition-return")
	test_isolated_processes()

func copy_scripts(source: String, target: String):
	DirAccess.make_dir_recursive_absolute(target)
	for name in DirAccess.get_files_at(source):
		if name.ends_with(".gd") or name.ends_with(".uid"): expect(DirAccess.copy_absolute(source.path_join(name),target.path_join(name)) == OK,"copy isolated production script")
	for name in DirAccess.get_directories_at(source): copy_scripts(source.path_join(name),target.path_join(name))

func child_process(project: String, profile: String, mode: String) -> Dictionary:
	var report = project.path_join(mode+".json"); var output = []
	var script = "world_profile_process.gd" if profile == "world-slice-v1" else "profile_process.gd"
	var code = OS.execute(OS.get_executable_path(),["--headless","--path",project,"--log-file",project.path_join(mode+".log"),"--script","res://tests/core/"+script,"--","--profile",profile,"--mode",mode,"--report",report],output,true)
	var text = "\n".join(output); var result = JSON.parse_string(FileAccess.get_file_as_string(report)) if FileAccess.file_exists(report) else null
	expect(code == 0 and result is Dictionary and result.get("failures",["missing"]).is_empty() and "SCRIPT ERROR" not in text and "ERROR:" not in text,"actual isolated "+profile+" "+mode+": "+text.right(500))
	return result if result is Dictionary else {}

func test_isolated_processes():
	expect(ProjectSettings.get_setting("application/config/use_custom_user_dir") and ProjectSettings.get_setting("application/config/custom_user_dir_name") == "moonlantern-world-slice-v1","new default uses independent actual namespace")
	var created = []
	for profile in ["prototype-v1","rain-night-v1","world-slice-v1"]:
		var project = output_dir.path_join("process-"+profile)
		copy_scripts(ProjectSettings.globalize_path("res://game/core"),project.path_join("game/core")); copy_scripts(ProjectSettings.globalize_path("res://game/expedition"),project.path_join("game/expedition"))
		DirAccess.make_dir_recursive_absolute(project.path_join("tests/core"))
		for script in ["profile_process.gd","world_profile_process.gd"]: expect(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/core/"+script),project.path_join("tests/core/"+script)) == OK,"copy isolated child entry")
		var config = ConfigFile.new(); config.set_value("","config_version",5); config.set_value("application","config/name","World profile acceptance")
		config.set_value("application","config/use_custom_user_dir",true); config.set_value("application","config/custom_user_dir_name","MoonlanternWorldAcceptance/%d/%s" % [OS.get_process_id(),profile]); expect(config.save(project.path_join("project.godot")) == OK,"isolated namespace configuration")
		var written = child_process(project,profile,"write"); var restored = child_process(project,profile,"restore")
		expect(not written.is_empty() and not restored.is_empty() and written.snapshot == restored.snapshot,"separate OS process restores complete "+profile)
		if not written.is_empty(): created.append(written)
	for old in created:
		expect(FileAccess.get_sha256(old.save_path) == old.primary_sha256 and FileAccess.get_sha256(old.save_path+".bak") == old.backup_sha256,"all isolated old/new primary and backup hashes unchanged after world restart")
	traces.append({"scenario":"isolated-default-profiles-no-runtime-fixture","processes":created})

func run(folder: String, selected: String = "") -> Dictionary:
	output_dir = folder+"/world-%d" % OS.get_process_id(); DirAccess.make_dir_recursive_absolute(output_dir)
	fixture_data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/world-slice-scenarios.json")); seeds = fixture_data.seeds
	var callbacks = {"WS01":test_movement,"WS02":test_spatial_guards,"WS03":test_cooking_and_carry,"WS04":test_delivery,"WS05":test_nights_and_growth,"WS06":test_save_and_expedition}
	for id in callbacks:
		if selected != "" and selected != id: continue
		checks = 0; failures = []; traces = []; callbacks[id].call()
		cases.append({"id":id,"status":"passed" if failures.is_empty() and checks > 0 else "failed","checks":checks,"failures":failures.duplicate(),"traces":traces.duplicate(true)})
		print("%s: %s (%d checks)" % [id,cases.back().status,checks])
	return {"schema_version":1,"suite":"world-slice","cases":cases,"simulations":simulations}
