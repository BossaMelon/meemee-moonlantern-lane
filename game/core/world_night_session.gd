extends "res://game/core/rain_night_session.gd"
const SnapshotValidator = preload("res://game/core/world_snapshot_validator.gd")
const Walk = preload("res://game/core/world_walk_model.gd")
const WORLD_PROFILE = "world-slice-v1"
const WORLD_SAVE = "user://profiles/world-slice-v1/moonlantern.json"
const BOOK_ACTIONS = ["plan","menu","buy","recycle","recover","equip_weapon","consume","install","uninstall","settle","upgrade","next_day"]
var _world_events: Array = []

func snapshot() -> Dictionary:
	# JSON has one numeric domain; canonicalize integral coordinates as well as money.
	return _normalize(_s)

func _normalize(value: Variant) -> Variant:
	var result = super._normalize(value)
	if result.get("world") is Dictionary:
		var positions = []
		if result.world.get("player") is Dictionary: positions.append(result.world.player)
		if result.world.get("customers") is Array: positions.append_array(result.world.customers)
		for p in positions:
			if not p is Dictionary or not SnapshotValidator.number(p.get("x")) or not SnapshotValidator.number(p.get("y")): continue
			# Simulation positions are Vector2 (float32). Restore that exact precision
			# after JSON's float64 parse, before both validation and continuation.
			var point = Vector2(p.x,p.y)
			p.x = int(point.x) if is_finite(point.x) and floor(point.x) == point.x else float(point.x)
			p.y = int(point.y) if is_finite(point.y) and floor(point.y) == point.y else float(point.y)
	return result

func _init(seed_value: int = 1):
	super(seed_value)
	_s.version = 4; _s.profile_id = WORLD_PROFILE; _s.phase = "preparation"
	_s.items = []; _s.next_uid = 1; _s.ledger = []; _s.requests = {}; _s.commits = {}
	_s.world = {"version":1,"map_id":"moonlantern-shop-lane","map_revision":1,"region_id":"shop",
		"player":{"x":220.0,"y":380.0,"facing":"se"},"input":{"move_x":0.0,"move_y":0.0},"carried_uids":[],
		"plan":{"recipe_id":"floating_pie","quantity":3},"stations":[{"id":"prep","input_uids":[],"output_uids":[],"job":null}],
		"customers":[],"intro_flags":{"moved":false,"took":false,"loaded":false,"cooked":false,"served":false},
		"remainder_ms":0,"tick":0,"travelled_mm":0,"return_pose":null}
	_add(_s,"stirring_cauldron",0,"installed")
	for n in range(3): _add(_s,"flour",0); _add(_s,"pumpkin",0)
	_record_economy(_s,"inheritance",{},[],60,[])
	var rng = RandomNumberGenerator.new(); rng.seed = seed_value; _s.rng_state = str(rng.state)
	_begin_night(_s)

func _begin_night(s: Dictionary):
	var held = s.service.get("held_uids",[]).duplicate()
	var menu = s.service.get("menu_priority",["floating_pie","moon_stew"]).duplicate()
	s.active_upgrades = s.upgrades.duplicate()
	s.progression.owned_weapons = ["bolt_wand","fan_wand"] if "field_kit" in s.active_upgrades else ["bolt_wand"]
	s.progression.skills = ["gust"]; s.progression.pending_unlocks = []
	var rng = RandomNumberGenerator.new(); rng.seed = int(s.seed); rng.state = int(s.rng_state)
	s.supply = {}
	for id in ["flour","pumpkin","cream","ember_herb"]: s.supply[id] = 12+rng.randi_range(0,2)
	if s.day >= 2: s.supply.stirring_cauldron = 1
	var night_id = "n%d" % s.day
	s.night = {"id":night_id,"day":s.day,"weather":"rain","event_id":"rain_return","waves":[],"queues":{}}
	s.service = {"night_id":night_id,"wave_id":null,"next_wave_id":night_id+"-w1","wave_index":0,"status":"planned","orders":[],
		"reservations":[],"menu_priority":menu,"held_uids":held,"elapsed_ms":0,"remainder_ms":0,"tip_paid_by_wave":{}}
	s.customers = []
	for wave in range(1,4):
		var id = night_id+"-w%d" % wave; var count = 3 if wave == 1 else 4; var queue = []
		for i in range(count):
			var required = ["meal","quick"] if wave == 1 or i < 2 else (["meal","hearty"] if wave == 2 else ["meal","warming","heat_hold"])
			if s.day >= 2 and wave == 1 and i == 2: required = ["meal","trail_light"]
			if s.day >= 2 and wave == 3 and i == 3: required = ["meal","celebration"]
			var order = _order(id+"-c%02d" % (i+1),required,rng.randi_range(23,30))
			order.merge({"wave_id":id,"status":"arriving","arrival_ms":i*4000,"patience_ms":60000,"waited_ms":0,"channel":null,"seat_id":"seat-%d" % (i+1),"prefers_hand_delivery":i == 0})
			queue.append(order)
		s.night.queues[id] = queue; s.customers.append_array(queue.duplicate(true))
		s.night.waves.append({"id":id,"index":wave,"ordinary_count":count,"quick":3 if wave == 1 else 2,"warm":2 if wave == 3 else 0,"hearty":2 if wave == 2 else 0,"budget_min":23,"budget_max":30})
	s.rng_state = str(rng.state); s.cursor = 0; s.clock_ms = 0; s.pending = {}; s.daily_recovery = 0; s.expedition = {}
	if s.has("world"): s.world.customers = []

func _sync_priority(_state: Dictionary):
	pass # A declared menu remains available after its final physical portion is sold.

func _position(s: Dictionary) -> Vector2:
	return Vector2(s.world.player.x,s.world.player.y)

func _spatial_error(s: Dictionary, target: Dictionary) -> String:
	if target.is_empty(): return "未知物件"
	if s.phase == "expedition" or target.region_id != s.world.region_id: return "物件不在当前区域"
	var anchor = Vector2(target.anchor.x,target.anchor.y)
	if _position(s).distance_to(anchor) > 56.000001: return "请走近物件"
	if not Walk.clear_line(s.world.region_id,_position(s),anchor): return "中间有障碍"
	return ""

func _uids(s: Dictionary, ids: Variant, location: String) -> bool:
	if not ids is Array or ids.is_empty() or ids.size() > 12: return false
	var seen = []
	for uid in ids:
		if not _whole(uid,1) or uid in seen or _item(s,uid).get("location") != location: return false
		seen.append(uid)
	return true

func _bundle(s: Dictionary) -> Dictionary:
	var recipe = Catalog.RECIPES[s.world.plan.recipe_id]; var station = s.world.stations[0]
	var loaded = {}; var units = 0
	for material in recipe.inputs: loaded[material] = 0; units += int(recipe.inputs[material])
	for uid in station.input_uids+s.world.carried_uids:
		var item = _item(s,uid)
		if not loaded.has(item.item_id): return {"uids":[],"reason":"台面或托盘含其他配方材料"}
		loaded[item.item_id] += 1
	var portions = -1
	for material in loaded:
		if loaded[material]%int(recipe.inputs[material]) != 0: return {"uids":[],"reason":"材料须为完整配方束"}
		var n = int(loaded[material]/recipe.inputs[material])
		if portions != -1 and portions != n: return {"uids":[],"reason":"材料束数量不一致"}
		portions = n
	var trip = mini(s.world.plan.quantity-portions,int(12/units))
	if trip <= 0: return {"uids":[],"reason":"本计划材料已齐或托盘已满"}
	if s.world.carried_uids.size()+trip*units > 12: return {"uids":[],"reason":"请先放下当前完整材料束"}
	var ids = []
	for material in recipe.inputs:
		var available = _instances(s,material,"bag"); var needed = int(recipe.inputs[material])*trip
		if available.size() < needed: return {"uids":[],"reason":"缺少完整材料束："+material}
		for i in range(needed): ids.append(available[i].uid)
	return {"uids":ids,"reason":"","portions":trip}

func command(kind: String, args: Dictionary = {}, request_id: String = "") -> Dictionary:
	if kind == "world_input":
		if args.size() != 2 or not args.has_all(["move_x","move_y"]): return _fail("invalid_input","需要两个移动轴")
		for axis in [args.move_x,args.move_y]:
			if not (axis is int or axis is float) or not is_finite(float(axis)) or absf(axis) > 1: return _fail("invalid_input","移动轴须为有限的-1至1")
		if _s.phase == "expedition" or (_s.paused and (args.move_x != 0 or args.move_y != 0)): return _fail("wrong_phase","此时只能停止移动")
		_s.world.input = args.duplicate(true)
		return _result(true,"ok","移动输入已更新")
	if kind in ["pause","advance","expedition_input","leave_expedition"]:
		if kind == "leave_expedition":
			var result = super.command(kind,args,request_id)
			if result.ok and result.code != "duplicate": _return_world(_s)
			return result
		var result = super.command(kind,args,request_id)
		if result.ok and result.code != "duplicate" and kind == "pause": _s.world.input = {"move_x":0.0,"move_y":0.0}
		return result
	if kind != "world_interact": return _fail("spatial_required","请走近物件进行操作")
	var fingerprint = JSON.stringify({"kind":kind,"args":args},"",true,true)
	if request_id != "" and _s.requests.has(request_id):
		return _result(true,"duplicate","该操作已提交") if _s.requests[request_id] == fingerprint else _fail("request_conflict","请求ID不能换参数")
	var candidate = _s.duplicate(true); var result = _interact(candidate,args)
	if not result.ok: return result
	var action = args.action; var record_kind = "craft" if action == "cook" else action
	_record_economy(candidate,record_kind,args.payload,result.events,int(_s.cash),_s.items)
	if request_id != "": candidate.requests[request_id] = fingerprint
	_s = candidate; _world_events = result.events.duplicate(true)
	_action_trace.append({"kind":kind,"args":args.duplicate(true)})
	return result

func _interact(s: Dictionary, args: Dictionary) -> Dictionary:
	if args.size() != 3 or not args.has_all(["target_id","action","payload"]) or not args.target_id is String or not args.action is String or not args.payload is Dictionary: return _fail("invalid_action","物件动作字段不完整")
	var target = Walk.object(args.target_id); var error = _spatial_error(s,target)
	if error != "": return _fail("out_of_reach",error)
	var action = args.action; var a = args.payload
	if action not in target.actions: return _fail("wrong_target","物件不提供此动作")
	if s.paused and action not in BOOK_ACTIONS: return _fail("paused","暂停时不能搬运、开工或交付")
	var fields = {"take":["uids"],"put":["uids"],"cook":["recipe_id","quantity"],"serve":["order_id","uid"],"plan":["recipe_id","quantity"],"menu":["item_ids","tiers"],"buy":["item_id","quantity"],"recycle":["item_id","quantity"],"consume":["item_id","quantity"],"equip_weapon":["weapon_id"],"install":["uid"],"uninstall":["uid"],"start_wave":["wave_id"],"upgrade":["upgrade_id"]}.get(action,[])
	if a.size() != fields.size() or not a.has_all(fields): return _fail("invalid_payload","动作参数不匹配")
	var station = s.world.stations[0]; var events = []
	match action:
		"take":
			var location = "bag" if target.id == "pantry" else ("ready" if not station.output_uids.is_empty() else "station_input")
			if not _uids(s,a.uids,location) or s.world.carried_uids.size()+a.uids.size() > 12: return _fail("invalid_uid","取物UID或托盘容量错误")
			if target.id == "prep" and location == "station_input" and station.job != null: return _fail("busy","料理已开工")
			var kinds = []
			for uid in s.world.carried_uids+a.uids:
				var kind = Catalog.ITEMS[_item(s,uid).item_id].kind
				if kind not in ["ingredient","dish"]: return _fail("invalid_item","设备不能装托盘")
				if kind not in kinds: kinds.append(kind)
			if kinds.size() != 1: return _fail("mixed_carry","托盘不能混装原料与成菜")
			if target.id == "pantry" and kinds[0] == "ingredient":
				var bundle = _bundle(s)
				if bundle.reason != "" or a.uids != bundle.uids: return _fail("incomplete_bundle",bundle.reason if bundle.reason != "" else "请取完整建议材料束")
			for uid in a.uids:
				_item(s,uid).location = "carried"; s.world.carried_uids.append(uid)
				station.input_uids.erase(uid); station.output_uids.erase(uid)
			s.world.intro_flags.took = true; events.append({"type":"item_taken","uids":a.uids.duplicate(),"target_id":target.id})
		"put":
			if not _uids(s,a.uids,"carried"): return _fail("invalid_uid","只能放置实际携带物")
			var location = {"pantry":"bag","prep":"station_input","pass":"shelf"}[target.id]
			if target.id == "prep" and (station.job != null or station.input_uids.size()+a.uids.size() > 24): return _fail("busy","工作台忙碌或已满")
			for uid in a.uids:
				var item = _item(s,uid); var kind = Catalog.ITEMS[item.item_id].kind
				if target.id == "prep" and kind != "ingredient": return _fail("not_ingredient","工作台只接收原料")
				if target.id == "pass" and (kind != "dish" or item.item_id not in s.service.menu_priority): return _fail("not_on_menu","请先声明该料理菜单")
			for uid in a.uids:
				var item = _item(s,uid); item.location = location; s.world.carried_uids.erase(uid)
				if location == "station_input": station.input_uids.append(uid)
			if target.id == "prep": s.world.intro_flags.loaded = true
			events.append({"type":"item_put","uids":a.uids.duplicate(),"target_id":target.id})
		"plan","cook":
			if not a.recipe_id is String or not Catalog.RECIPES.has(a.recipe_id) or not _whole(a.quantity,1,6): return _fail("invalid_recipe","配方或批量错误")
			if s.phase not in (["preparation","intermission"] if action == "plan" else ["preparation","trading","intermission"]): return _fail("wrong_phase","当前不能计划或开工")
			if action == "plan": s.world.plan = a.duplicate(true)
			else:
				if a != s.world.plan: return _fail("planned_batch","请按当前完整批量计划开工")
				if station.job != null or station.output_uids.size()+a.quantity > 12: return _fail("busy","工作台任务或成菜位已满")
				var recipe = Catalog.RECIPES[a.recipe_id]; var expected = 0
				if recipe.requires_device != "" and _count(s,recipe.requires_device,"installed") == 0: return _fail("missing_device","需装配自搅锅")
				for material in recipe.inputs:
					expected += int(recipe.inputs[material])*int(a.quantity)
					if _count(s,material,"station_input") != recipe.inputs[material]*a.quantity: return _fail("insufficient_materials","台内材料与批量不匹配")
				if station.input_uids.size() != expected: return _fail("wrong_materials","台内有其他材料")
				var outputs = []
				for n in range(a.quantity):
					var cost = 0
					for material in recipe.inputs:
						for item in _take_oldest(s,material,recipe.inputs[material],"station_input"): cost += int(item.cost)
					_add(s,recipe.output,cost,"cooking"); outputs.append(s.items.back().uid)
				station.input_uids = []; station.job = {"id":"cook:%d" % outputs[0],"recipe_id":a.recipe_id,"output_uids":outputs,"remaining_ms":2000}
				events.append({"type":"cooking_started","job_id":station.job.id,"uids":outputs.duplicate()})
		"serve":
			if s.phase != "trading" or not _whole(a.uid,1) or not a.order_id is String or _item(s,a.uid).get("location") != "carried": return _fail("invalid_serve","需要真实携带料理和营业客人")
			var order = _find_order(s,a.order_id)
			if order.is_empty() or order.seat_id != target.id or order.status != "waiting": return _fail("stale_order","该座位客人尚未到达或已经处理")
			var item = _item(s,a.uid); var mismatch = _match_instance(s,item,order)
			if mismatch != "": return _fail(mismatch,"料理不满足需求或预算")
			_reserve(s,item,order,"manual",null); s.world.carried_uids.erase(item.uid)
			events.append({"type":"delivery_reserved","order_id":order.id,"uid":item.uid,"channel":"manual"})
		"menu":
			if s.phase not in ["preparation","intermission"] or not a.item_ids is Array or a.item_ids.is_empty() or a.item_ids.size() > (3 if "shelf" in s.active_upgrades else 2) or not a.tiers is Dictionary: return _fail("invalid_menu","菜单阶段或容量错误")
			var seen = []
			for id in a.item_ids:
				if not id is String or not Catalog.RECIPES.has(id) or id in seen: return _fail("invalid_menu","菜单含重复或未知料理")
				seen.append(id)
			for id in a.tiers:
				if id not in seen or not a.tiers[id] is String or not Catalog.TIERS.has(a.tiers[id]): return _fail("invalid_menu","价格档错误")
			for item in s.items:
				if item.location in ["shelf","reserved"] and item.item_id not in seen: return _fail("menu_occupied","台面或在途料理仍占菜单位")
			s.service.menu_priority = seen; s.tiers.merge(a.tiers,true)
		"open_shop","start_wave":
			if (action == "open_shop" and s.phase != "preparation") or (action == "start_wave" and s.phase != "intermission"): return _fail("wrong_phase","当前不能开波")
			if action == "start_wave" and a.wave_id != s.service.next_wave_id: return _fail("stale_wave","目标波次已过期")
			var opened = _start_wave(s,s.service.next_wave_id)
			if not opened.ok: return opened
			events.append_array(opened.events)
		"next_day":
			if s.phase != "settled": return _fail("wrong_phase","先完成日结")
			s.commits["next:%d" % s.day] = true; s.day += 1; s.phase = "preparation"; _begin_night(s)
		"enter":
			if target.id == "garden-gate":
				if s.phase != "preparation" or not s.world.carried_uids.is_empty() or station.job != null or not s.service.reservations.is_empty(): return _fail("not_ready","出发需准备阶段、空手且无料理或配送在途")
				var result = _old_action(s,"start_expedition",{})
				if not result.ok: return result
				s.world.return_pose = Walk.LAYOUT.portals[2]["return"].duplicate(true)
			else:
				for portal in Walk.LAYOUT.portals:
					if portal.id == target.id: s.world.region_id = portal.to_region; s.world.player = portal.arrival.duplicate(true)
				events.append({"type":"region_changed","region_id":s.world.region_id})
			s.world.input = {"move_x":0.0,"move_y":0.0}
		"buy","recycle","recover","equip_weapon","consume","install","uninstall","upgrade","settle":
			if action in ["buy","recycle","recover","install","uninstall"] and s.phase not in ["preparation","intermission"]: return _fail("wrong_phase","请在准备或波间处理")
			if action in ["equip_weapon","consume"] and s.phase != "preparation": return _fail("wrong_phase","请在准备阶段处理")
			if action in ["install","uninstall"] and (station.job != null or (action == "uninstall" and s.service.reservations.any(func(r): return r.channel == "pot"))): return _fail("busy","锅仍在料理或配送")
			var result = _old_action(s,action,a)
			if not result.ok: return result
			events.append_array(result.events)
	var direction = Vector2(target.anchor.x,target.anchor.y)-_position(s)
	if action != "enter" and not direction.is_zero_approx(): s.world.player.facing = Walk.facing(direction)
	for event in events: event.tick = s.world.tick
	return _result(true,"ok","操作完成",events)

func _old_action(s: Dictionary, kind: String, args: Dictionary) -> Dictionary:
	var phase = s.phase
	if kind in ["buy","recover","recycle","consume","equip_weapon","start_expedition"]: s.phase = "shopping"
	elif kind in ["install","uninstall"]: s.phase = "preparation"
	var result = super._apply(s,kind,args)
	if kind != "start_expedition" or not result.ok: s.phase = phase if kind != "settle" or not result.ok else "settled"
	return result

func _find_order(s: Dictionary, id: String) -> Dictionary:
	for order in s.service.orders:
		if order.id == id: return order
	return {}

func _find_customer(s: Dictionary, id: String) -> Dictionary:
	for customer in s.world.customers:
		if customer.order_id == id: return customer
	return {}

func _quote(s: Dictionary, item: Dictionary, order: Dictionary, channel: String) -> Dictionary:
	var base = _price(s,item.item_id); var tip = 0; var reason = "automatic"
	if channel == "manual":
		if base > order.budget: reason = "base_unaffordable"
		elif not order.prefers_hand_delivery: reason = "not_preferred"
		elif s.service.tip_paid_by_wave.has(order.wave_id): reason = "already_paid"
		elif base+2 > order.budget: reason = "budget_no_room"
		else: reason = "eligible"; tip = 2
	return {"order_id":order.id,"uid":item.uid,"base_price":base,"tip":tip,"paid_total":base+tip,"tip_reason":reason}

func _reserve(s: Dictionary, item: Dictionary, order: Dictionary, channel: String, batch: Variant):
	var quote = _quote(s,item,order,channel)
	item.location = "reserved"; s.service.held_uids.erase(item.uid); order.status = "reserved"; order.channel = channel
	_find_customer(s,order.id).state = "reserved"
	s.service.reservations.append({"item_uid":item.uid,"order_id":order.id,"channel":channel,"remaining_ms":50 if channel == "manual" else DELIVERY_MS[channel],"batch_id":batch,
		"price":quote.paid_total,"base_price":quote.base_price,"tip":quote.tip,"paid_total":quote.paid_total,"cost":item.cost})

func _start_wave(s: Dictionary, wave_id: String) -> Dictionary:
	if wave_id == "" or s.commits.has("wave:"+wave_id) or not s.service.reservations.is_empty(): return _fail("stale_wave","该波已处理或仍有在途单")
	s.service.wave_index += 1; s.service.wave_id = wave_id; s.service.next_wave_id = s.night.id+"-w%d" % (s.service.wave_index+1) if s.service.wave_index < 3 else null
	s.service.orders = s.night.queues[wave_id].duplicate(true); s.service.status = "active"; s.service.elapsed_ms = 0; s.service.remainder_ms = 0
	s.phase = "trading"; s.commits["wave:"+wave_id] = true
	for order in s.service.orders:
		s.world.customers.append({"id":order.id,"order_id":order.id,"seat_id":order.seat_id,"x":1192.0,"y":580.0,"state":"arriving","path_index":0,"reaction_remaining_ms":0,"spawned":false})
	return _result(true,"ok","客人开始进店",[{"type":"wave_started","wave_id":wave_id,"tick":s.world.tick}])

func _schedule(s: Dictionary):
	for order in s.service.orders:
		if order.status != "waiting": continue
		for id in s.service.menu_priority:
			var reserved = false
			for item in _instances(s,id,"shelf"):
				if _match_instance(s,item,order) != "": continue
				var channel = _channel(s,item); var active = s.service.reservations.filter(func(r): return r.channel == channel)
				var batch = s.service.wave_id+":%d" % s.service.elapsed_ms
				if active.size() >= (2 if channel == "floating" else (3 if channel == "pot" else 1)): continue
				if channel == "pot" and not active.is_empty() and active[0].batch_id != batch: continue
				_reserve(s,item,order,channel,batch if channel == "pot" else null); reserved = true; break
			if reserved: break

func _deliver(s: Dictionary, reservation: Dictionary) -> Dictionary:
	var row = super._deliver(s,reservation)
	row.base_price = reservation.base_price; row.tip = reservation.tip; row.paid_total = reservation.paid_total
	if row.tip > 0: s.service.tip_paid_by_wave[row.wave_id] = row.order_id
	var customer = _find_customer(s,row.order_id); customer.state = "eating"; customer.reaction_remaining_ms = 1000
	s.world.intro_flags.served = true
	return row

func _customer_step(s: Dictionary, events: Array):
	for c in s.world.customers:
		var order = _find_order(s,c.order_id)
		if not c.spawned:
			if order.is_empty() or s.service.elapsed_ms < order.arrival_ms: continue
			c.spawned = true
		if c.state == "eating":
			c.reaction_remaining_ms -= 50
			if c.reaction_remaining_ms == 0: c.state = "leaving"; c.path_index = 0
		elif c.state in ["arriving","leaving"]:
			var seat = Walk.object(c.seat_id).anchor
			var path = [Vector2(1160,seat.y),Vector2(seat.x,seat.y)] if c.state == "arriving" else [Vector2(1160,seat.y),Vector2(1192,580)]
			var p = Vector2(c.x,c.y).move_toward(path[c.path_index],6.0); c.x = p.x; c.y = p.y
			if p.is_equal_approx(path[c.path_index]):
				c.path_index += 1
				if c.path_index == path.size():
					if c.state == "arriving": c.state = "waiting"; order.status = "waiting"; events.append({"type":"customer_arrived","order_id":order.id})
					else: c.state = "gone"

func _end_wave(s: Dictionary, events: Array):
	var keep = []
	if _count(s,"stirring_cauldron","installed") > 0:
		for item in _instances(s,"moon_stew","shelf"):
			if item.temperature in ["hot","held"] and keep.size() < 3: keep.append(item.uid)
	for item in s.items:
		if item.item_id == "moon_stew" and item.location != "cooking": item.temperature = "held" if item.uid in keep else "cooled"
	s.service.held_uids = keep; s.service.remainder_ms = 0
	s.phase = "intermission" if s.service.wave_index < 3 else "closing"; s.service.status = "intermission" if s.service.wave_index < 3 else "complete"
	events.append({"type":"wave_completed","wave_id":s.service.wave_id,"next_wave_id":s.service.next_wave_id})

func _world_step(s: Dictionary, events: Array):
	s.world.tick += 1
	var w = s.world; var axes = Vector2(w.input.move_x,w.input.move_y); var old = _position(s)
	var moved = Walk.move(w.region_id,old,axes); w.player.x = moved.x; w.player.y = moved.y
	if axes.length() > 0.2: w.player.facing = Walk.facing(axes)
	w.travelled_mm += roundi(old.distance_to(moved)*1000)
	if w.travelled_mm >= 32000: w.intro_flags.moved = true
	if not old.is_equal_approx(moved): events.append({"type":"world_moved","x":moved.x,"y":moved.y})
	var station = w.stations[0]
	if "shelf" in s.active_upgrades:
		var count = 0
		for uid in station.output_uids.duplicate():
			if count == 3: break
			var item = _item(s,uid)
			if item.item_id in s.service.menu_priority:
				item.location = "shelf"; station.output_uids.erase(uid); count += 1; events.append({"type":"item_put","target_id":"pass","uids":[uid],"automatic":true})
	if station.job != null:
		station.job.remaining_ms -= 50
		if station.job.remaining_ms == 0:
			for uid in station.job.output_uids:
				var item = _item(s,uid); item.location = "ready"; item.prepared_wave_id = s.service.wave_id if s.phase == "trading" or s.service.next_wave_id == null else s.service.next_wave_id
				if item.item_id == "moon_stew": item.temperature = "hot"
				station.output_uids.append(uid)
			events.append({"type":"cooking_ready","job_id":station.job.id,"uids":station.job.output_uids.duplicate()}); station.job = null; w.intro_flags.cooked = true
	if s.phase == "trading": s.service.elapsed_ms += 50
	_customer_step(s,events)
	if s.phase != "trading": return
	for reservation in s.service.reservations.duplicate():
		reservation.remaining_ms -= 50
		if reservation.remaining_ms == 0:
			var sale = _deliver(s,reservation); events.append(sale); events.append({"type":"served","uid":sale.uid,"order_id":sale.order_id,"paid_total":sale.paid_total}); s.service.reservations.erase(reservation)
	for order in s.service.orders:
		if order.status != "waiting": continue
		order.waited_ms += 50
		if order.waited_ms >= order.patience_ms:
			var row = _sale_row(s,order,"",0,0,[_unserved_reason(s,order)])
			row.merge({"wave_id":order.wave_id,"channel":null,"delivered_ms":s.service.elapsed_ms,"base_price":0,"tip":0,"paid_total":0})
			s.sales.append(row); s.commits[order.id] = true; s.cursor += 1; order.status = "left"
			var c = _find_customer(s,order.id); c.state = "leaving"; c.path_index = 0
			events.append(row); events.append({"type":"customer_left","order_id":order.id})
	_schedule(s)
	if s.service.orders.all(func(o): return o.status in ["delivered","left"]) and s.service.reservations.is_empty(): _end_wave(s,events)

func _advance(delta_ms: Variant) -> Dictionary:
	if not _whole(delta_ms,0,60000): return _fail("invalid_time","时间须为0至60000整数毫秒")
	if _s.paused: return _result(true,"idle","暂停中")
	if _s.phase == "expedition":
		var result = super._advance_expedition(delta_ms)
		if result.ok and _s.phase == "shopping": _return_world(_s)
		return result
	var candidate = _s.duplicate(true); var events = []; candidate.world.remainder_ms += int(delta_ms)
	while candidate.world.remainder_ms >= 50:
		candidate.world.remainder_ms -= 50; var start = events.size(); _world_step(candidate,events)
		for i in range(start,events.size()): events[i].tick = candidate.world.tick
	var sales = events.filter(func(e): return e.get("revenue",0) > 0)
	_record_economy(candidate,"advance",{"delta_ms":int(delta_ms)},sales,int(_s.cash),_s.items)
	_s = candidate; _world_events = events
	return _result(true,"ok","世界已推进",events)

func _return_world(s: Dictionary):
	s.phase = "preparation"; s.world.region_id = "lane"
	var pose = s.world.return_pose
	s.world.player = {"x":pose.x,"y":pose.y,"facing":pose.facing}; s.world.input = {"move_x":0.0,"move_y":0.0}

func _suggestions(s: Dictionary) -> Array:
	var rows = []; var station = s.world.stations[0]
	for target in Walk.LAYOUT.objects:
		if target.region_id != s.world.region_id: continue
		for action in target.actions:
			var payload = {}
			match action:
				"take": payload = {"uids":_bundle(s).uids if target.id == "pantry" else (station.output_uids.slice(0,12-s.world.carried_uids.size()) if not station.output_uids.is_empty() else station.input_uids.slice(0,12-s.world.carried_uids.size()))}
				"put": payload = {"uids":s.world.carried_uids.duplicate()}
				"cook","plan": payload = s.world.plan.duplicate(true)
				"serve":
					payload = {"order_id":"","uid":0}
					for order in s.service.orders:
						if order.seat_id != target.id or order.status != "waiting": continue
						for uid in s.world.carried_uids:
							if _match_instance(s,_item(s,uid),order) == "": payload = {"order_id":order.id,"uid":uid}; break
				"menu": payload = {"item_ids":s.service.menu_priority.duplicate(),"tiers":s.tiers.duplicate()}
				"buy","recycle": payload = {"item_id":"flour","quantity":1}
				"consume": payload = {"item_id":"floating_pie","quantity":1}
				"equip_weapon": payload = {"weapon_id":s.progression.equipped_weapon}
				"install","uninstall":
					var items = _instances(s,"stirring_cauldron","bag" if action == "install" else "installed"); payload = {"uid":0 if items.is_empty() else items[0].uid}
				"start_wave": payload = {"wave_id":s.service.next_wave_id}
				"upgrade": payload = {"upgrade_id":"shelf"}
			var options = [payload]
			if action == "upgrade": options = [{"upgrade_id":"field_kit"},{"upgrade_id":"shelf"}]
			elif action == "buy":
				options = []
				for id in s.supply: options.append({"item_id":id,"quantity":1})
			elif action == "recycle":
				options = []
				for id in Catalog.ITEMS:
					if _count(s,id,"bag") > 0: options.append({"item_id":id,"quantity":1})
				if options.is_empty(): options = [payload]
			elif action == "consume": options = [{"item_id":"floating_pie","quantity":1},{"item_id":"star_soup","quantity":1}]
			elif action == "menu":
				payload.tiers = {}
				for id in s.service.menu_priority: payload.tiers[id] = s.tiers.get(id,"standard")
			for offered in options:
				var spatial = _spatial_error(s,target)
				var result = _fail("out_of_reach",spatial) if spatial != "" else _interact(s.duplicate(true),{"target_id":target.id,"action":action,"payload":offered})
				rows.append({"target_id":target.id,"action":action,"payload":offered,"label":action,"enabled":result.ok,"reason":"" if result.ok else result.message,"anchor":target.anchor.duplicate(true)})
	rows.sort_custom(func(a,b):
		var da = _position(s).distance_squared_to(Vector2(a.anchor.x,a.anchor.y)); var db = _position(s).distance_squared_to(Vector2(b.anchor.x,b.anchor.y))
		return da < db if not is_equal_approx(da,db) else a.target_id < b.target_id)
	return rows

func view() -> Dictionary:
	var v = _base_world_view()
	for row in v.inventory:
		for location in ["carried","station_input","cooking","ready"]: row[location] = _count(_s,row.item_id,location)
	v.world = _s.world.duplicate(true); v.world.geometry = Walk.geometry(_s.world.region_id)
	v.interactions = _suggestions(_s); v.serve_quotes = []; v.events = _world_events.duplicate(true)
	for order in _s.service.orders:
		if order.status == "waiting":
			for uid in _s.world.carried_uids:
				var item = _item(_s,uid)
				if Catalog.ITEMS[item.item_id].kind == "dish": v.serve_quotes.append(_quote(_s,item,order,"manual"))
	v.available_commands = {"world_input":{"enabled":not _s.paused and _s.phase != "expedition","reason":""},"world_interact":{"enabled":_s.phase != "expedition","reason":""}}
	return v

func save_to(path: String = WORLD_SAVE) -> Dictionary:
	if ProjectSettings.globalize_path(path).simplify_path() in [ProjectSettings.globalize_path("user://moonlantern.json").simplify_path(),ProjectSettings.globalize_path("user://profiles/rain-night-v1/moonlantern.json").simplify_path()]: return _fail("legacy_save_path","禁止访问旧默认存档")
	for target in [path,path+".bak"]:
		if FileAccess.file_exists(target):
			var existing = JSON.parse_string(FileAccess.get_file_as_string(target))
			if existing is Dictionary and (existing.get("version") != 4 or existing.get("profile_id") != WORLD_PROFILE): return _fail("incompatible_save","其他规则原档已保留")
	if path == WORLD_SAVE: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return Store.save_state(path,_s,validate_snapshot)

func load_from(path: String = WORLD_SAVE) -> Dictionary:
	if ProjectSettings.globalize_path(path).simplify_path() in [ProjectSettings.globalize_path("user://moonlantern.json").simplify_path(),ProjectSettings.globalize_path("user://profiles/rain-night-v1/moonlantern.json").simplify_path()]: return _fail("legacy_save_path","禁止访问旧默认存档")
	var result = Store.load_state(path,validate_snapshot)
	if result.ok:
		_s = _normalize(result.state); _s.world.input = {"move_x":0.0,"move_y":0.0}; result.erase("state")
		if not _s.expedition.is_empty() and _expedition_model() != null: _model.set_input(_s.expedition,{})
		_world_events = []; _action_trace = []
	return result

func validate_snapshot(data: Variant) -> String:
	if not data is Dictionary: return "存档必须为对象"
	if data.get("version") != 4: return "不支持的存档版本"
	if data.get("profile_id") != WORLD_PROFILE or data.get("rules_version") != 1: return "不支持的存档规则"
	return SnapshotValidator.validate(data,self)

func _base_world_view() -> Dictionary:
	var v = snapshot(); v.finished = false; v.inventory = []; v.prices = {}; v.supply = []; v.recipes = []; v.upgrades = []
	for id in Catalog.ITEMS:
		var definition = Catalog.ITEMS[id]
		var row = {"item_id":id,"name":definition.name,"kind":definition.kind,"effect_id":definition.effect_id,"tags":definition.tags.duplicate(),"uids":[],"bag":0,"shelf":0,"installed":0,"reserved":0,"carried":0,"station_input":0,"cooking":0,"ready":0}
		for item in _s.items:
			if item.item_id == id: row[item.location] += 1; row.uids.append(item.duplicate(true))
		v.inventory.append(row); v.prices[id] = _price(_s,id)
	for id in _s.supply:
		var available = _s.phase in ["preparation","intermission"] and _s.supply[id] > 0 and _s.cash >= Catalog.ITEMS[id].buy
		v.supply.append({"item_id":id,"name":Catalog.ITEMS[id].name,"quantity":_s.supply[id],"buy":Catalog.ITEMS[id].buy,"available":available,"reason":"" if available else "需采购阶段、余货与足够金币"})
	for id in Catalog.RECIPES:
		var recipe = Catalog.RECIPES[id].duplicate(true); var maximum = 6
		for material in recipe.inputs: maximum = mini(maximum,int((_count(_s,material,"bag")+_count(_s,material,"carried")+_count(_s,material,"station_input"))/recipe.inputs[material]))
		var missing = recipe.requires_device != "" and _count(_s,recipe.requires_device,"installed") == 0
		recipe.recipe_id = id; recipe.max_quantity = 0 if missing else maximum; recipe.effect_id = Catalog.ITEMS[id].effect_id
		recipe.available = _s.phase in ["preparation","trading","intermission"] and not missing and maximum > 0
		recipe.reason = "" if recipe.available else ("需装配自搅坩埚" if missing else ("食材不足" if maximum == 0 else "当前阶段不能开工"))
		v.recipes.append(recipe)
	for id in QUALITY_UPGRADES:
		var row = QUALITY_UPGRADES[id].duplicate(true); row.upgrade_id = id; row.owned = id in _s.upgrades; row.active = id in _s.active_upgrades
		row.available = _s.phase == "settled" and not row.owned and _s.cash >= row.cost and (id != "field_kit" or _dish_income(_s) >= 24)
		row.reason = "" if row.available else "日结后按实际收入与资金购买，次晨生效"; v.upgrades.append(row)
	v.demand_board = _s.customers.duplicate(true)
	for order in v.demand_board: order.processed = _s.commits.has(order.id)
	v.customers_remaining = _s.customers.size()-_s.cursor
	v.forecast = {"day":_s.day,"weather":_s.night.weather,"event_id":_s.night.event_id,"waves":_s.night.waves.duplicate(true),"required":["warming","heat_hold"],"text":"雨夜三波：赶路小食、巡护正餐、雨中返程；本波新饼走浮空通道，锅内最多保温三份。"}
	v.summary = _s.summaries.back().duplicate(true) if not _s.summaries.is_empty() else {}
	if not _s.pending.is_empty():
		v.pending.options = []
		for id in Catalog.RECIPES:
			var matching = _instances(_s,id,"shelf").filter(func(item): return _match_instance(_s,item,_s.pending).is_empty())
			v.pending.options.append({"item_id":id,"name":Catalog.ITEMS[id].name,"available":not matching.is_empty(),"reason":"" if not matching.is_empty() else "需要满足委托的未预留菜单料理","price":_price(_s,id)})
	v.shelf_capacity = 3 if "shelf" in _s.active_upgrades else 2; v.inventory_capacity = CAPACITY; v.dish_income = _dish_income(_s)
	v.available_commands = {}
	for kind in PHASE_COMMANDS:
		var enabled = _s.phase in PHASE_COMMANDS[kind]; var reason = "" if enabled else "当前阶段不可用"
		if kind == "recover" and _s.daily_recovery > 0: enabled = false; reason = "今日免费恢复已用"
		if kind in ["fulfill","decline"] and _s.pending.is_empty(): enabled = false; reason = "没有待处理委托"
		if kind == "consume" and _s.pending_meal_effect != null: enabled = false; reason = "已有待用餐前效果"
		if kind == "start_expedition" and _s.expedition_attempts.has(str(_s.day)): enabled = false; reason = "今日探索次数已用"
		v.available_commands[kind] = {"enabled":enabled,"reason":reason}
	v.expedition = _model.view(_s.expedition) if not _s.expedition.is_empty() and _expedition_model() != null else {"status":"idle","day":_s.day,"run_id":"","remaining_ms":null,"elapsed_ms":0,"attempts_remaining":1,"player":{},"enemies":[],"projectiles":[],"drops":[],"hazards":[],"resource_nodes":[],"meal_effect":null}
	v.expedition.attempts_remaining = 0 if _s.expedition_attempts.has(str(_s.day)) else 1
	return v

func _validate_economy(s: Dictionary, uids: Dictionary, sales: Dictionary) -> String:
	var live = {}; var issued = {}; var cash = int(s.initial_cash); var paid = []; var sold = {}; var consumed = {}; var drops = {}
	for i in range(s.ledger.size()):
		var row = s.ledger[i]
		if not row is Dictionary or not row.has_all(["index","kind","day","cash_delta","moves","created","removed","args","events"]): return "经济流水字段缺失"
		if not _whole(row.index,i,i) or not row.kind is String or not _whole(row.day,1,int(s.day)) or not _whole(row.cash_delta,-1000000) or not row.moves is Dictionary or not row.created is Array or not row.removed is Array or not row.args is Dictionary or not row.events is Array: return "非法经济流水"
		var moves = {}; var input_cost = 0; var output_cost = 0
		for item in row.removed:
			if not item is Dictionary or not item.has_all(["uid","item_id","cost"]) or not _whole(item.uid,1) or not live.has(str(item.uid)) or not Catalog.ITEMS.has(item.item_id) or not _whole(item.cost): return "消耗实例非法"
			if live[str(item.uid)].item_id != item.item_id or live[str(item.uid)].cost != item.cost: return "消耗成本来源错误"
			live.erase(str(item.uid)); input_cost += item.cost; moves[item.item_id] = moves.get(item.item_id,0)-1
		for item in row.created:
			if not item is Dictionary or not item.has_all(["uid","item_id","cost"]) or not _whole(item.uid,1) or item.uid >= s.next_uid or issued.has(str(item.uid)) or not Catalog.ITEMS.has(item.item_id) or not _whole(item.cost): return "创建实例非法"
			issued[str(item.uid)] = item; live[str(item.uid)] = item; output_cost += item.cost; moves[item.item_id] = moves.get(item.item_id,0)+1
		for id in moves:
			if row.moves.get(id,0) != moves[id]: return "库存流水与实例不一致"
		for id in row.moves:
			if not Catalog.ITEMS.has(id) or not _whole(row.moves[id],-80,80) or row.moves[id] != moves.get(id,0): return "非法库存流水"
		var expected_cash = 0
		if row.kind in ["buy","craft","recycle","consume"] and not _whole(row.args.get("quantity"),1,CAPACITY): return "经济流水数量类型错误"
		if row.kind in ["buy","recycle","consume"] and not row.args.get("item_id") is String: return "经济流水物品类型错误"
		if row.kind == "craft" and not row.args.get("recipe_id") is String: return "经济流水配方类型错误"
		match row.kind:
			"inheritance":
				if i != 0 or row.created.size() != 7 or output_cost != 0 or not row.removed.is_empty(): return "继承来源错误"
				var inherited = {}
				for item in row.created: inherited[item.item_id] = inherited.get(item.item_id,0)+1
				if inherited != {"stirring_cauldron":1,"flour":3,"pumpkin":3}: return "继承数量错误"
			"buy":
				var id = row.args.get("item_id","")
				if id not in ["flour","pumpkin","cream","ember_herb","stirring_cauldron"] or row.created.size() != row.args.get("quantity") or not row.removed.is_empty(): return "采购来源错误"
				for item in row.created:
					if item.item_id != id or item.cost != Catalog.ITEMS[id].buy: return "采购成本错误"
				expected_cash = -output_cost
			"craft":
				var recipe = Catalog.RECIPES.get(row.args.get("recipe_id"),{})
				if recipe.is_empty() or row.created.size() != row.args.get("quantity") or row.created.is_empty() or input_cost != output_cost: return "配方成本不守恒"
				var ingredients = {}
				for item in row.removed: ingredients[item.item_id] = ingredients.get(item.item_id,0)+1
				if ingredients.size() != recipe.inputs.size(): return "配方投入种类错误"
				for id in recipe.inputs:
					if ingredients.get(id,0) != recipe.inputs[id]*row.created.size(): return "配方投入数量错误"
				for item in row.created:
					if item.item_id != recipe.output: return "配方产出错误"
			"recycle":
				if not row.created.is_empty() or row.removed.is_empty() or row.removed.size() != row.args.get("quantity"): return "售回实例错误"
				for item in row.removed:
					if item.item_id != row.args.get("item_id"): return "售回种类错误"
					expected_cash += _recycle_value(item)
			"consume":
				if row.removed.size() != 1 or row.removed[0].item_id not in ["floating_pie","star_soup"] or not row.created.is_empty(): return "餐前食用来源错误"
				consumed[str(row.removed[0].uid)] = row.removed[0]
			"recover":
				if not row.created.is_empty() or not row.removed.is_empty(): return "恢复奖励类型错误"
				expected_cash = 12
			"upgrade":
				var id = row.args.get("upgrade_id")
				if not QUALITY_UPGRADES.has(id) or id in paid or not row.created.is_empty() or not row.removed.is_empty(): return "重复或非法升级支付"
				paid.append(id); expected_cash = -QUALITY_UPGRADES[id].cost
			"settle": expected_cash = -mini(4,cash)
			"pickup":
				if not row.args.get("run_id") is String or not row.args.get("pickups") is Array or row.args.pickups.is_empty() or not row.removed.is_empty() or s.expedition_attempts.get(str(int(row.day))) != row.args.run_id: return "拾取来源不一致"
				var offset = 0
				for pickup in row.args.pickups:
					if not pickup is Dictionary or not pickup.has_all(["drop_id","item_id","quantity","cost"]) or not pickup.drop_id is String or pickup.drop_id.is_empty() or not _whole(pickup.quantity,1,CAPACITY) or pickup.item_id not in ["sparkcap","moonheart"] or pickup.cost != 0: return "非法拾取记录"
					var key = _drop_key(row.args.run_id,pickup.drop_id); var picked_uids = []
					if drops.has(key) or offset+pickup.quantity > row.created.size(): return "重复掉落或数量不一致"
					for n in range(int(pickup.quantity)):
						var item = row.created[offset]; offset += 1
						if item.item_id != pickup.item_id or item.cost != 0: return "拾取物品或成本错误"
						picked_uids.append(item.uid)
					drops[key] = {"run_id":row.args.run_id,"drop_id":pickup.drop_id,"item_id":pickup.item_id,"quantity":int(pickup.quantity),"uids":picked_uids,"day":row.day}
				if offset != row.created.size(): return "拾取与实例数量错误"
			"advance","fulfill":
				var removed = {}
				for event in row.events:
					if not event is Dictionary or not _whole(event.get("revenue",0)): return "非法成交事件"
					if event.get("revenue",0) == 0: continue
					if not event.has("order_id") or not sales.has(event.order_id) or sales[event.order_id] != event or sold.has(event.order_id): return "成交事件未对账"
					sold[event.order_id] = true; removed[str(event.uid)] = event; expected_cash += event.revenue
				if removed.size() != row.removed.size(): return "交付扣除数量不一致"
				if row.kind == "fulfill":
					if row.created.size() != 2 or row.events.size() != 1 or row.events[0].get("quest_id") != "hagrid_patrol": return "人物奖励来源错误"
					for reward in row.created:
						if reward.item_id != "ember_herb" or reward.cost != 0: return "人物奖励数量或成本错误"
				elif not row.created.is_empty(): return "普通交付不能产生物品"
				for item in row.removed:
					if not removed.has(str(item.uid)) or removed[str(item.uid)].cost != item.cost: return "交付扣除UID/成本错误"
			_: return "未知经济流水种类"
		if row.cash_delta != expected_cash: return "现金变动来源错误"
		cash += row.cash_delta
		if cash < 0: return "历史现金为负"
	if cash != s.cash or live.size() != uids.size() or paid != s.upgrades or drops != s.collected_drops: return "经济总账不守恒"
	for uid in uids:
		if not live.has(uid) or live[uid].item_id != uids[uid].item_id or live[uid].cost != uids[uid].cost: return "库存取得来源错误"
		if Catalog.ITEMS[uids[uid].item_id].kind == "dish":
			for key in ["intrinsic_tags","effect_id"]:
				if live[uid].get(key) != uids[uid].get(key): return "菜品制作身份被改写"
	for id in sales:
		if sales[id].revenue > 0 and not sold.has(id): return "成交收入未入账"
	var effects = s.expedition_meals.values(); effects.append(s.pending_meal_effect); var meal_uids = []
	for meal in effects:
		if meal == null: continue
		if not meal is Dictionary or not meal.has_all(["effect_id","source_item_uid","used"]) or not _whole(meal.source_item_uid,1) or not consumed.has(str(meal.source_item_uid)) or not meal.used is bool or meal.used != false or meal.source_item_uid in meal_uids: return "待用餐前效果来源错误"
		meal_uids.append(meal.source_item_uid)
		var source = consumed[str(meal.source_item_uid)]
		if meal.effect_id != ("light_step" if source.item_id == "floating_pie" else "clear_breath"): return "餐前效果种类错误"
	if meal_uids.size() != consumed.size(): return "食用效果未进入待用槽或正式探索"
	return ""
