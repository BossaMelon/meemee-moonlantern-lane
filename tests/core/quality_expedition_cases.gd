extends "res://tests/core/quality_service_cases.gd"
const Map = preload("res://game/expedition/rain_garden_map.gd")
var observed: Array = []

func step(g, input: Dictionary, ms: int = 50) -> Dictionary:
	var accepted = g.command("expedition_input",input)
	expect(accepted.ok,"actual expedition input accepted")
	var result = g.advance(ms)
	expect(result.ok,"real model advances through Session")
	observed.append_array(result.events)
	audit(g)
	return result

func walk(g, goal: Vector2, cast: bool = true):
	var s = g.snapshot().expedition
	var position = Vector2(s.player.x,s.player.y)
	var path = Map.path(position,goal,12)
	expect(not path.is_empty(),"published map has traversable route")
	for point in path:
		for _i in range(220):
			s = g.snapshot().expedition
			if g.view().phase != "expedition":
				expect(false,"normal route returned before destination"); return
			position = Vector2(s.player.x,s.player.y)
			if position.distance_to(point) < 3: break
			var movement = (point-position)/8.0
			if movement.length() > 1: movement = movement.normalized()
			var aim = Vector2.RIGHT; var distance = 10000.0
			for enemy in s.enemies:
				var delta = Vector2(enemy.x,enemy.y)-position
				if enemy.hp > 0 and delta.length() < distance: aim = delta.normalized(); distance = delta.length()
			var clear_spore = s.hazards.any(func(h): return h.state == "active" and Vector2(h.x,h.y).distance_to(position) < 115)
			step(g,{"move_x":movement.x,"move_y":movement.y,"aim_x":aim.x,"aim_y":aim.y,"cast":cast,"skill":distance < 100 or clear_spore})
			expect(Map.point_clear(Vector2(g.snapshot().expedition.player.x,g.snapshot().expedition.player.y),12),"real player footprint never crosses terrain")
	position = Vector2(g.snapshot().expedition.player.x,g.snapshot().expedition.player.y)
	expect(position.distance_to(goal) < 4,"real input arrives at intended map point")

func clear_input(g):
	act(g,"expedition_input",{})

func finish_empty_night(g):
	act(g,"finish_shopping"); act(g,"open_shop"); advance_wave(g)
	for wave in [2,3]: act(g,"start_wave",{"wave_id":"n%d-w%d" % [g.view().day,wave]}); advance_wave(g)
	act(g,"settle")

func acquire_rare(seed_value: int = 1):
	var g = Session.new(seed_value)
	act(g,"start_expedition")
	walk(g,Vector2(415,95)); clear_input(g)
	expect(g.snapshot().collected_drops.has("n1-expedition|resource:shelf-patch"),"real path acquires published resource node")
	expect(g.view().inventory.filter(func(i): return i.item_id == "sparkcap")[0].bag >= 1,"pickup creates actual zero-cost ingredient UID")
	act(g,"leave_expedition")
	return g

func test_meal_transfer():
	var g = Session.new(7)
	act(g,"buy",{"item_id":"flour","quantity":1}); act(g,"buy",{"item_id":"pumpkin","quantity":1})
	act(g,"craft",{"recipe_id":"floating_pie","quantity":1}); act(g,"consume",{"item_id":"floating_pie","quantity":1})
	var pending = g.snapshot().pending_meal_effect
	g._game._model = preload("res://tests/core/rejecting_model_fixture.gd")
	reject(g,"start_expedition")
	expect(g.snapshot().pending_meal_effect == pending and g.snapshot().expedition_attempts.is_empty(),"real create-failure boundary preserves effect and attempt")
	g._game._model = null
	act(g,"start_expedition",{},"formal-start")
	var before = g.snapshot(); expect(g.command("start_expedition",{},"formal-start").code == "duplicate" and before == g.snapshot(),"start request retry cannot create a second run")
	var result = step(g,{"move_y":-1.0,"dodge":true})
	var dodges = result.events.filter(func(e): return e.type == "dodge")
	expect(dodges.size() == 1 and dodges[0].duration_ms == 300 and g.snapshot().expedition.meal_effect.used,"real first dodge consumes light_step for 300ms")
	expect(g.snapshot().expedition.player.y == 255,"food does not increase dodge speed")
	clear_input(g); var resumed = roundtrip(g,"light-step-used")
	act(g,"pause",{"value":true}); var paused = g.snapshot(); act(g,"advance",{"delta_ms":60000})
	expect(g.snapshot() == paused,"paused actual model and effect freeze")
	act(g,"pause",{"value":false})
	for branch in [g,resumed]: step(branch,{"move_y":-1.0,"dodge":true},1200); clear_input(branch)
	expect(g.snapshot() == resumed.snapshot(),"used meal and cooldown continue identically after load")
	act(g,"leave_expedition"); reject(g,"start_expedition")
	traces.append({"scenario":"meal-transfer","actions":g.action_trace(),"final":g.snapshot()})

func test_rare_four_uses():
	var origin = acquire_rare(23); var base = origin.snapshot()
	var rare_uid = base.items.filter(func(i): return i.item_id == "sparkcap")[0].uid
	var raw = fixture(base,"rare-raw-sale")
	act(raw,"recycle",{"item_id":"sparkcap","quantity":1})
	expect(raw.view().cash == base.cash+4 and raw.view().dish_income == 0,"raw sale uses fixed 4 without dish revenue")
	reject(raw,"buy",{"item_id":"sparkcap","quantity":1})
	var sale = fixture(base,"rare-cooked-sale")
	for pair in [["pumpkin",1],["ember_herb",1]]: act(sale,"buy",{"item_id":pair[0],"quantity":pair[1]})
	act(sale,"craft",{"recipe_id":"star_soup","quantity":1}); act(sale,"finish_shopping")
	reject(sale,"display",{"item_id":"sparkcap","quantity":1}); reject(sale,"price",{"item_id":"sparkcap","tier":"standard"})
	act(sale,"display",{"item_id":"star_soup","quantity":1}); act(sale,"open_shop"); act(sale,"advance",{"delta_ms":3000})
	expect(sale.view().dish_income == 23 and sale.view().cash == base.cash-6+23,"processed actual star soup earns dish revenue with paid input costs")
	var food = fixture(base,"rare-self-eat")
	for id in ["pumpkin","ember_herb"]: act(food,"buy",{"item_id":id,"quantity":1})
	act(food,"craft",{"recipe_id":"star_soup","quantity":1}); act(food,"consume",{"item_id":"star_soup","quantity":1})
	expect(food.snapshot().pending_meal_effect.effect_id == "clear_breath" and food.view().dish_income == 0,"same rare UID can instead become pending breath effect")
	reject(food,"consume",{"item_id":"floating_pie","quantity":1}); reject(food,"start_expedition")
	finish_empty_night(food); act(food,"next_day"); act(food,"start_expedition")
	var result = step(food,{"skill":true}); var skills = result.events.filter(func(e): return e.type == "skill")
	expect(skills.size() == 1 and skills[0].range == 160 and food.snapshot().expedition.meal_effect.used,"real second-day first gust consumes clear_breath for range160")
	clear_input(food); roundtrip(food,"clear-breath-used")
	var kept = fixture(base,"rare-retained"); finish_empty_night(kept); act(kept,"next_day")
	expect(kept.snapshot().items.any(func(i): return i.uid == rare_uid and i.item_id == "sparkcap" and i.cost == 0),"retained exact rare UID survives night and next day")
	for branch in [raw,sale,food,kept]:
		audit(branch); traces.append({"scenario":"rare-four-uses","rare_uid":rare_uid,"actions":branch.action_trace(),"ledger":branch.snapshot().ledger,"final":branch.snapshot()})

func test_real_routes_and_isolation():
	var g = Session.new(99); act(g,"start_expedition")
	for point in [Vector2(415,95),Vector2(375,395),Vector2(560,440),Vector2(805,225),Vector2(850,380)]:
		walk(g,point); clear_input(g); g = roundtrip(g,"actual-route")
	var acquired = g.snapshot().collected_drops.duplicate(true)
	expect(acquired.has("n1-expedition|resource:shelf-patch") and acquired.has("n1-expedition|resource:canal-west-patch") and acquired.has("n1-expedition|resource:canal-east-patch"),"both actual routes acquire all finite map nodes")
	act(g,"leave_expedition"); finish_empty_night(g); act(g,"next_day"); act(g,"start_expedition")
	var node = g.view().expedition.resource_nodes.filter(func(n): return n.id == "shelf-patch")[0]
	walk(g,Vector2(node.x,node.y)); clear_input(g)
	expect(g.snapshot().collected_drops.has("n2-expedition|resource:shelf-patch"),"same stable node ID can be legitimately acquired in a later distinct run")
	for key in acquired: expect(g.snapshot().collected_drops.get(key) == acquired[key],"old run pickup receipt retained unchanged")
	var count = g.snapshot().items.size(); step(g,{},200); expect(g.snapshot().items.size() == count,"staying on collected node cannot duplicate inventory")
	traces.append({"scenario":"real-two-routes-two-runs","events":observed.duplicate(true),"ledger":g.snapshot().ledger,"final":g.snapshot()})

func run(folder: String) -> Dictionary:
	output_dir = folder+"/expedition-%d" % OS.get_process_id(); DirAccess.make_dir_recursive_absolute(output_dir)
	test_meal_transfer(); test_rare_four_uses(); test_real_routes_and_isolation()
	return {"suite":"quality-expedition-focused","checks":checks,"failures":failures,"traces":traces}
