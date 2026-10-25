extends RefCounted

const Catalog = preload("res://game/core/catalog.gd")
const Store = preload("res://game/core/save_store.gd")
const VERSION = 2
const CAPACITY = 80
const MODEL_PATH = "res://game/expedition/expedition_model.gd"
var _s: Dictionary
var _action_trace: Array = []
var _model: Script

func _init(seed_value: int = 1):
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	_s = {"version":VERSION,"seed":str(seed_value),"rng_state":str(rng.state),"day":1,
		"phase":"shopping","paused":false,"clock_ms":0,"cursor":0,"customers":[],"pending":{},
		"cash":60,"initial_cash":60,"items":[],"next_uid":1,"ledger":[],"commits":{},"requests":{},
		"known":Catalog.RECIPES.keys(),"upgrades":[],"active_upgrades":[],"read":[],"supply":{},"daily_recovery":0,
		"tiers":{},"sales":[],"summaries":[],"quests":{"hagrid_patrol":"not_offered"},
		"progression":{"owned_weapons":["bolt_wand"],"equipped_weapon":"bolt_wand","skills":[],"pending_unlocks":[]},
		"next_expedition_shield":false,"expedition_attempts":{},"expedition":{},"collected_drops":{}}
	_add(_s,"stirring_cauldron",0)
	_record_economy(_s,"inheritance",{},[],60,[])
	_begin_day(_s)

func _expedition_model():
	if _model == null and ResourceLoader.exists(MODEL_PATH): _model = load(MODEL_PATH)
	return _model

func action_trace() -> Array:
	return _action_trace.duplicate(true)

func snapshot() -> Dictionary:
	return _s.duplicate(true)

func _result(ok: bool, code: String = "ok", message: String = "", events: Array = []) -> Dictionary:
	return {"ok":ok,"code":code,"message":message if not message.is_empty() else code,"events":events}

func _fail(code: String, message: String) -> Dictionary:
	return _result(false,code,message)

func _count(s: Dictionary, item_id: String, location: String = "") -> int:
	var amount = 0
	for item in s.items:
		if item.item_id == item_id and (location.is_empty() or item.location == location):
			amount += 1
	return amount

func _tags(_state: Dictionary, item_id: String) -> Array:
	return Catalog.ITEMS[item_id].tags.duplicate()

func _rain_dish(item_id: String) -> bool:
	var tags = Catalog.ITEMS[item_id].tags
	return "warming" in tags and "heat_hold" in tags

func _price(s: Dictionary, item_id: String) -> int:
	return Catalog.price(item_id,s.tiers.get(item_id,"standard"),25 if s.day == 3 and _rain_dish(item_id) else 0)

func _dish_income(s: Dictionary) -> int:
	var income = 0
	for sale in s.sales: income += int(sale.revenue)
	return income

func _take(s: Dictionary, item_id: String, quantity: int, location: String) -> Array:
	var taken: Array = []
	for i in range(s.items.size()-1,-1,-1):
		if taken.size() == quantity:
			break
		if s.items[i].item_id == item_id and s.items[i].location == location:
			taken.push_front(s.items[i])
			s.items.remove_at(i)
	return taken

func _add(s: Dictionary, item_id: String, cost: int, location: String = "bag"):
	s.items.append({"uid":s.next_uid,"item_id":item_id,"cost":cost,"location":location})
	s.next_uid += 1

func _order(id: String, required: Array, budget: int, special: bool = false, text: String = "") -> Dictionary:
	return {"id":id,"required":required,"budget":budget,"special":special,"text":text,"character_id":"","quest_id":"","rewards":[]}

func _begin_day(s: Dictionary):
	var rng = RandomNumberGenerator.new()
	rng.seed = int(s.seed)
	rng.state = int(s.rng_state)
	s.active_upgrades = s.upgrades.duplicate()
	if "field_kit" in s.active_upgrades:
		s.progression.owned_weapons = ["bolt_wand","fan_wand"]
		s.progression.skills = ["gust"]
		s.progression.pending_unlocks = []
	s.supply = {}
	for id in ["flour","pumpkin","cream"]: s.supply[id] = 12 + rng.randi_range(0,2)
	if "supply_pass" in s.active_upgrades: s.supply.ember_herb = 12 + rng.randi_range(0,2)
	if s.day >= 2: s.supply.stirring_cauldron = 1
	s.customers = []
	var needs = ["quick","quick","quick","hearty","hearty","hearty"]
	for i in range(needs.size()-1,0,-1):
		var j = rng.randi_range(0,i)
		var hold = needs[i]; needs[i] = needs[j]; needs[j] = hold
	for i in range(needs.size()): s.customers.append(_order("d%d-c%d" % [s.day,i],["meal",needs[i]],rng.randi_range(23,30)))
	var special: Dictionary
	if s.day == 1: special = _order("d1-special",["meal","quick","portable"],30,true,"赶路巫师想带一份浮空小食")
	elif s.day == 2:
		special = _order("d2-hagrid-patrol",["meal","warming","heat_hold","portable"],30,true,"海格：巡护时想带一份始终温暖的料理")
		special.character_id = "hagrid"; special.quest_id = "hagrid_patrol"
		special.rewards = [{"item_id":"ember_herb","quantity":2}]
	else: special = _order("d3-special",["meal","warming","heat_hold"],30,true,"雨天返程客想吃暖身又保温的料理")
	s.customers.insert(2,special)
	if s.day >= 2: s.customers.append(_order("d%d-trail" % s.day,["meal","trail_light"],30))
	if s.day == 3: s.customers.append(_order("d3-celebration",["meal","celebration"],40))
	s.rng_state = str(rng.state)
	s.cursor = 0; s.clock_ms = 0; s.daily_recovery = 0; s.pending = {}; s.expedition = {}

func _phase(s: Dictionary, phases: Array) -> bool:
	return s.phase in phases

func _whole(value: Variant, minimum: int = 0, maximum: int = 1000000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

func _matching(s: Dictionary, item_id: String, order: Dictionary) -> String:
	if _count(s,item_id,"shelf") < 1:
		return "商品不在可售货架"
	for tag in order.required:
		if tag not in _tags(s,item_id):
			return "缺少必需效果：" + tag
	if _price(s,item_id) > order.budget:
		return "标价超过顾客预算"
	return ""

func _sale_row(s: Dictionary, order: Dictionary, id: String, revenue: int, cost: int, reasons: Array) -> Dictionary:
	return {"type":"sale" if revenue > 0 else "unmatched","day":s.day,"order_id":order.id,"item_id":id,
		"revenue":revenue,"cost":cost,"reasons":reasons,"character_id":order.character_id,"quest_id":order.quest_id,
		"rewards":order.rewards.duplicate(true) if revenue > 0 else [],"effect_id":Catalog.ITEMS[id].effect_id if id != "" else ""}

func _sell(s: Dictionary, order: Dictionary, item_id: String) -> Dictionary:
	var item = _take(s,item_id,1,"shelf")[0]
	var price = _price(s,item_id)
	s.cash += price
	var reasons = ["满足：" + ",".join(order.required),"预算%d ≥ 标价%d" % [order.budget,price]]
	if s.day == 3 and _rain_dish(item_id): reasons.append("暖身与保温匹配雨天 +25%（上限）")
	var sale = _sale_row(s,order,item_id,price,item.cost,reasons)
	sale.uid = item.uid
	s.sales.append(sale); s.commits[order.id] = true
	return sale

func _decline_sale(s: Dictionary, order: Dictionary, reason: String) -> Dictionary:
	var failed = _sale_row(s,order,"",0,0,[reason])
	s.sales.append(failed); s.commits[order.id] = true
	return failed

func _serve_normal(s: Dictionary, order: Dictionary) -> Dictionary:
	# Satisfy scarce effects first without consuming another customer's reserved dish when a base option exists.
	for item_id in Catalog.ITEMS:
		if _matching(s,item_id,order).is_empty(): return _sell(s,order,item_id)
	return _decline_sale(s,order,"菜单无满足用途且预算可及的料理：" + ",".join(order.required))

func _apply(s: Dictionary, kind: String, a: Dictionary) -> Dictionary:
	var id = str(a.get("item_id",""))
	var quantity = a.get("quantity",0)
	if kind in ["buy","craft","display","undisplay","recycle","consume"]:
		if not _whole(quantity,1,80):
			return _fail("invalid_quantity","数量必须为1至80的整数")
		quantity = int(quantity)
	if kind in ["buy","display","undisplay","recycle","price","consume"] and not Catalog.ITEMS.has(id):
		return _fail("unknown_id","未知商品")
	match kind:
		"buy":
			if s.phase != "shopping": return _fail("wrong_phase","只可在淘货时采购")
			if not s.supply.has(id): return _fail("unavailable","该货源尚未开放")
			if s.supply[id] < quantity: return _fail("insufficient_supply","当日货源不足")
			var cost = int(Catalog.ITEMS[id].buy) * quantity
			if s.cash < cost: return _fail("insufficient_cash","金币不足")
			if s.items.size() + quantity > CAPACITY: return _fail("capacity","背包容量不足")
			s.cash -= cost
			s.supply[id] -= quantity
			for n in range(quantity): _add(s,id,Catalog.ITEMS[id].buy)
		"finish_shopping":
			if s.phase != "shopping": return _fail("wrong_phase","当前不是淘货阶段")
			s.phase = "preparation"
		"craft":
			if s.phase != "preparation": return _fail("wrong_phase","只可在整备时制作")
			var recipe_id = str(a.get("recipe_id",""))
			if not Catalog.RECIPES.has(recipe_id) or recipe_id not in s.known: return _fail("unknown_id","未知配方")
			var recipe = Catalog.RECIPES[recipe_id]
			if recipe.requires_device != "" and _count(s,recipe.requires_device,"installed") == 0: return _fail("missing_device","制作炖锅需要装配自搅坩埚")
			for material in recipe.inputs:
				if _count(s,material,"bag") < int(recipe.inputs[material]) * quantity: return _fail("insufficient_materials","材料不足")
			for n in range(quantity):
				var basis = 0
				for material in recipe.inputs:
					for item in _take(s,material,int(recipe.inputs[material]),"bag"): basis += int(item.cost)
				_add(s,recipe.output,basis)
			return _result(true,"ok","批量备餐完成",[{"type":"crafted","item_id":recipe.output,"quantity":quantity,"effect_id":Catalog.ITEMS[recipe.output].effect_id}])
		"display", "undisplay":
			if s.phase != "preparation": return _fail("wrong_phase","只可在整备时调整陈列")
			if Catalog.ITEMS[id].kind != "dish": return _fail("not_dish","菜单只能供应已制成料理")
			var source = "bag" if kind == "display" else "shelf"
			var target = "shelf" if kind == "display" else "bag"
			if _count(s,id,source) < quantity: return _fail("insufficient_inventory","可移动库存不足；装配物不能出售")
			if kind == "display" and _count(s,id,"shelf") == 0:
				var types = {}
				for item in s.items:
					if item.location == "shelf": types[item.item_id] = true
				if types.size() >= (3 if "shelf" in s.active_upgrades else 2): return _fail("capacity","陈列种类槽不足")
			for item in _take(s,id,quantity,source):
				item.location = target
				s.items.append(item)
		"install", "uninstall":
			if s.phase != "preparation": return _fail("wrong_phase","只可在整备时装配")
			var found = false
			for item in s.items:
				if item.uid == a.get("uid",-1):
					if item.item_id != "stirring_cauldron": return _fail("not_device","该物品不是设备")
					var source = "bag" if kind == "install" else "installed"
					if item.location != source: return _fail("unavailable","设备位置不符")
					if kind == "install" and _count(s,"stirring_cauldron","installed") >= 1: return _fail("capacity","装配槽已满")
					item.location = "installed" if kind == "install" else "bag"
					found = true
					break
			if not found: return _fail("unknown_id","没有该物品实例")
		"price":
			if s.phase != "preparation": return _fail("wrong_phase","只可在整备时定价")
			if Catalog.ITEMS[id].kind != "dish": return _fail("not_dish","仅料理可标价")
			var tier = str(a.get("tier",""))
			if not Catalog.TIERS.has(tier): return _fail("unknown_id","未知价格档")
			s.tiers[id] = tier
		"open_shop":
			if s.phase != "preparation": return _fail("wrong_phase","尚未整备完成")
			s.phase = "trading"
		"advance":
			if not _whole(a.get("delta_ms"),0,60000): return _fail("invalid_time","时间步长须为0至60000整数毫秒")
			if s.phase != "trading" or s.paused or not s.pending.is_empty(): return _result(true,"idle","当前经营时钟冻结")
			s.clock_ms += int(a.delta_ms)
			var events: Array = []
			while s.clock_ms >= 1000 and s.cursor < s.customers.size():
				s.clock_ms -= 1000
				var customer = s.customers[s.cursor]
				if customer.special:
					s.pending = customer.duplicate(true)
					if customer.quest_id == "hagrid_patrol": s.quests.hagrid_patrol = "pending"
					events.append({"special":customer})
					break
				events.append(_serve_normal(s,customer))
				s.cursor += 1
			if s.cursor >= s.customers.size():
				s.phase = "closing"
				s.clock_ms = 0
			return _result(true,"ok","客流已推进",events)
		"fulfill", "decline":
			if s.phase != "trading" or s.pending.is_empty(): return _fail("wrong_phase","没有待处理的特殊需求")
			if str(a.get("order_id","")) != s.pending.id: return _fail("unknown_id","订单已处理或ID错误")
			var event: Dictionary
			if kind == "fulfill":
				if not Catalog.ITEMS.has(id): return _fail("unknown_id","未知商品")
				var reason = _matching(s,id,s.pending)
				if not reason.is_empty(): return _fail("unmatched",reason)
				if s.items.size()-1+_reward_quantity(s.pending) > CAPACITY: return _fail("capacity","储藏容量不足以接收全部任务奖励")
				event = _sell(s,s.pending,id)
				for reward in s.pending.rewards:
					for n in range(reward.quantity): _add(s,reward.item_id,0)
				if s.pending.quest_id == "hagrid_patrol": s.quests.hagrid_patrol = "completed"
			else:
				event = _decline_sale(s,s.pending,"玩家跳过特殊需求")
				if s.pending.quest_id == "hagrid_patrol": s.quests.hagrid_patrol = "declined"
			s.pending = {}
			s.cursor += 1
			# Discard accumulated frame time at the interaction boundary.
			s.clock_ms = 0
			return _result(true,"ok","特殊需求已处理",[event])
		"settle":
			if s.phase != "closing": return _fail("wrong_phase","客流尚未结束或已结算")
			var fee = mini(4,int(s.cash))
			s.cash -= fee
			s.phase = "settled"
			s.commits["settle:%d" % s.day] = true
			var revenue = 0
			var sold_cost = 0
			for sale in s.sales:
				if sale.day == s.day:
					revenue += int(sale.revenue)
					sold_cost += int(sale.cost)
			s.summaries.append({"day":s.day,"revenue":revenue,"sold_cost":sold_cost,"gross_profit":revenue-sold_cost,"fee":fee,"cash":s.cash})
		"upgrade":
			if s.phase != "settled": return _fail("wrong_phase","请在日结后升级")
			var upgrade_id = str(a.get("upgrade_id",""))
			if not Catalog.UPGRADES.has(upgrade_id): return _fail("unknown_id","未知升级")
			if upgrade_id in s.upgrades: return _fail("already_owned","已拥有该升级")
			if upgrade_id == "field_kit" and _dish_income(s) < 24: return _fail("income_required","探索套装需要累计实际菜品收入至少24")
			var cost = int(Catalog.UPGRADES[upgrade_id].cost)
			if s.cash < cost: return _fail("insufficient_cash","升级金币不足")
			s.cash -= cost
			s.upgrades.append(upgrade_id)
			if upgrade_id == "field_kit": s.progression.pending_unlocks = ["fan_wand","gust"]
		"next_day":
			if s.phase != "settled": return _fail("wrong_phase","先完成本日日结")
			if s.day >= 3: return _fail("finished","三日原型已完成，可保存退出")
			s.commits["next:%d" % s.day] = true
			s.day += 1
			s.phase = "shopping"
			# Unsold display returns to stock for the next day's choices.
			for item in s.items:
				if item.location == "shelf": item.location = "bag"
			_begin_day(s)
		"recover":
			if s.phase != "shopping": return _fail("wrong_phase","回收委托在淘货阶段领取")
			if s.daily_recovery >= 1: return _fail("daily_limit","免费回收委托每日一次，今日已完成")
			s.daily_recovery = 1
			s.cash += 12
			s.commits["recover:%d" % s.day] = true
		"recycle":
			if not _phase(s,["shopping","preparation"]): return _fail("wrong_phase","当前不能回收")
			if _count(s,id,"bag") < quantity: return _fail("insufficient_inventory","回收库存不足")
			for item in _take(s,id,quantity,"bag"): s.cash += 18 if id == "stirring_cauldron" else int(item.cost / 2)
		"consume":
			if s.phase != "shopping": return _fail("wrong_phase","只能在采购阶段食用储藏料理")
			if id != "floating_pie" or quantity != 1: return _fail("invalid_food","只能食用一份浮空饼")
			if s.next_expedition_shield: return _fail("shield_active","已有待用轻羽护盾，不能叠加")
			if _count(s,id,"bag") < 1: return _fail("insufficient_inventory","储藏中没有浮空饼")
			_take(s,id,1,"bag"); s.next_expedition_shield = true
			return _result(true,"ok","食用浮空饼：下一次探险抵消一次伤害",[{"type":"consumed","item_id":id,"quantity":1}])
		"equip_weapon":
			if s.phase != "shopping": return _fail("wrong_phase","只能在采购阶段更换武器")
			var weapon = a.get("weapon_id","")
			if weapon not in s.progression.owned_weapons: return _fail("weapon_locked","未拥有该武器")
			s.progression.equipped_weapon = weapon
		"start_expedition":
			if s.phase != "shopping": return _fail("wrong_phase","只能在采购阶段出发")
			var run_id = "d%d-expedition" % s.day
			if s.expedition_attempts.has(str(s.day)): return _fail("daily_limit","今日探险次数已使用")
			if _expedition_model() == null: return _fail("module_unavailable","动作模块尚未集成")
			s.expedition = _model.create(int(s.day),run_id,int(s.seed),s.progression.equipped_weapon,s.progression.skills,s.next_expedition_shield)
			s.expedition_attempts[str(s.day)] = run_id; s.next_expedition_shield = false; s.phase = "expedition"
		"leave_expedition":
			if s.phase != "expedition": return _fail("wrong_phase","当前不在探险中")
			var ended = _model.leave(s.expedition)
			_model.set_input(s.expedition,{})
			s.phase = "shopping"
			return _result(true,"ok","已返回采购，保留已拾取食材",ended.events)
		"pause":
			if not a.get("value") is bool: return _fail("invalid_value","暂停值须为布尔")
			s.paused = a.value
			if not s.expedition.is_empty() and _expedition_model() != null: _model.set_input(s.expedition,{})
		_:
			return _fail("unknown_command","未知操作")
	return _result(true,"ok","操作完成")

func _reward_quantity(order: Dictionary) -> int:
	var total = 0
	for reward in order.rewards: total += int(reward.quantity)
	return total

func _record_economy(s: Dictionary, kind: String, args: Dictionary, events: Array, old_cash: int, old_items: Array):
	var old_by_uid = {}; var new_by_uid = {}; var created = []; var removed = []; var moves = {}
	for item in old_items: old_by_uid[str(item.uid)] = item
	for item in s.items: new_by_uid[str(item.uid)] = item
	for key in new_by_uid:
		if not old_by_uid.has(key): created.append(new_by_uid[key].duplicate(true))
	for key in old_by_uid:
		if not new_by_uid.has(key): removed.append(old_by_uid[key].duplicate(true))
	if old_cash == s.cash and created.is_empty() and removed.is_empty(): return
	for item in created: moves[item.item_id] = moves.get(item.item_id,0)+1
	for item in removed: moves[item.item_id] = moves.get(item.item_id,0)-1
	s.ledger.append({"index":s.ledger.size(),"kind":kind,"day":s.day,"cash_delta":s.cash-old_cash,
		"moves":moves,"created":created,"removed":removed,"args":args.duplicate(true),"events":events.duplicate(true)})

func command(kind: String, args: Dictionary = {}, request_id: String = "") -> Dictionary:
	var fingerprint = JSON.stringify({"kind":kind,"args":args},"",true,true)
	if not request_id.is_empty() and _s.requests.has(request_id):
		if _s.requests[request_id] != fingerprint: return _fail("request_conflict","同一请求ID不能更换操作参数")
		return _result(true,"duplicate","该操作已提交")
	var result: Dictionary
	if kind == "advance":
		result = _advance(args.get("delta_ms"))
	elif kind == "expedition_input":
		if _s.phase != "expedition": return _fail("wrong_phase","当前不在探险中")
		result = _model.set_input(_s.expedition,args)
		if result.ok: _action_trace.append({"kind":kind,"args":args.duplicate(true)})
	else:
		var candidate = _s.duplicate(true)
		result = _apply(candidate,kind,args)
		if not result.ok: return result
		_record_economy(candidate,kind,args,result.events,int(_s.cash),_s.items)
		_s = candidate
		_action_trace.append({"kind":kind,"args":args.duplicate(true)})
	# Successful no-op requests are still bound; retries cannot mutate a later state.
	if result.ok and not request_id.is_empty(): _s.requests[request_id] = fingerprint
	return result.duplicate(true)

func _advance(delta_ms: Variant) -> Dictionary:
	if not _whole(delta_ms,0,60000): return _fail("invalid_time","时间步长须为0至60000整数毫秒")
	if _s.paused: return _result(true,"idle","暂停中")
	if _s.phase == "expedition":
		var next = _s.expedition.duplicate(true)
		var result = _model.advance(next,int(delta_ms),CAPACITY-_s.items.size(),false)
		if not result.ok: return result
		var seen = {}
		for pickup in result.pickups:
			if pickup.item_id not in ["sparkcap","moonheart"] or pickup.quantity != 1 or pickup.cost != 0 or _s.collected_drops.has(pickup.drop_id) or seen.has(pickup.drop_id):
				return _fail("invalid_pickup","动作模块返回了非法或重复掉落")
			seen[pickup.drop_id] = true
		if _s.items.size()+seen.size() > CAPACITY: return _fail("capacity","动作拾取超出储藏容量")
		var old_items = _s.items.duplicate(true) if not seen.is_empty() else []
		_s.expedition = next
		for pickup in result.pickups:
			_add(_s,pickup.item_id,0)
			_s.collected_drops[pickup.drop_id] = {"item_id":pickup.item_id,"uid":_s.next_uid-1,"day":_s.day}
		if not seen.is_empty():
			var economic_events = result.events.filter(func(event): return event.get("type","") == "drop_collected")
			_record_economy(_s,"pickup",{"drop_ids":seen.keys()},economic_events,int(_s.cash),old_items)
		if result.returned: _s.phase = "shopping"
		_action_trace.append({"kind":"advance","delta_ms":int(delta_ms)})
		return _result(true,"ok",result.message,result.events)
	if _s.phase != "trading" or not _s.pending.is_empty(): return _result(true,"idle","当前经营时钟冻结")
	# Most render frames only accumulate clock time; do not copy or append the ledger.
	if _s.clock_ms+delta_ms < 1000:
		_s.clock_ms += int(delta_ms)
		return _result(true)
	var candidate = _s.duplicate(true)
	var result = _apply(candidate,"advance",{"delta_ms":int(delta_ms)})
	_record_economy(candidate,"advance",{"delta_ms":int(delta_ms)},result.events,int(_s.cash),_s.items)
	_s = candidate
	return result

func advance(delta_ms: int) -> Dictionary:
	return command("advance",{"delta_ms":delta_ms})

func set_paused(value: bool) -> Dictionary:
	return command("pause",{"value":value})

func save_to(path: String = "user://moonlantern.json") -> Dictionary:
	return Store.save_state(path,_s,validate_snapshot)

func load_from(path: String = "user://moonlantern.json") -> Dictionary:
	var loaded = Store.load_state(path,validate_snapshot)
	if loaded.ok:
		_s = _normalize(loaded.state)
		if not _s.expedition.is_empty() and _expedition_model() != null: _model.set_input(_s.expedition,{})
		_action_trace = []
		loaded.erase("state")
	return loaded

func _normalize(value: Variant) -> Variant:
	# JSON numbers in the economy are integral. The simulation owns its numeric schema;
	# preserve all action coordinates, directions and velocities exactly.
	var result = value.duplicate(true)
	for key in result:
		result[key] = _action_numbers(result[key]) if key == "expedition" else _economy_integers(result[key])
	return result

func _action_numbers(value: Variant) -> Variant:
	# The model canonicalizes exact whole values to int, including coordinates.
	# Match that representation without rounding or truncating any fraction.
	if value is int or value is float:
		return int(value) if is_finite(float(value)) and floor(value) == value else value
	if value is Array:
		var out: Array = []
		for entry in value: out.append(_action_numbers(entry))
		return out
	if value is Dictionary:
		var out = {}
		for key in value: out[key] = _action_numbers(value[key])
		return out
	return value

func _economy_integers(value: Variant) -> Variant:
	if value is float: return int(value) if is_finite(value) and floor(value) == value else value
	if value is Array:
		var out: Array = []
		for entry in value: out.append(_economy_integers(entry))
		return out
	if value is Dictionary:
		var out = {}
		for key in value: out[key] = _economy_integers(value[key])
		return out
	return value

func validate_snapshot(data: Variant) -> String:
	if not data is Dictionary: return "存档必须为对象"
	var s: Dictionary = _normalize(data)
	if not s.has("version") or s.version != VERSION: return "不支持的存档版本"
	for key in _s:
		if not s.has(key): return "存档缺少字段："+key
	for key in ["seed","rng_state"]:
		if not s[key] is String or not s[key].is_valid_int() or str(int(s[key])) != s[key]: return "随机状态必须为无损整数字符串"
	if not _whole(s.day,1,3) or s.phase not in ["shopping","expedition","preparation","trading","closing","settled"]: return "非法日历或阶段"
	if not s.paused is bool or not s.next_expedition_shield is bool or not _whole(s.clock_ms,0,60000): return "非法时钟或护盾"
	for key in ["cash","initial_cash","next_uid","cursor","daily_recovery"]:
		if not _whole(s[key]): return "非法整数："+key
	if s.next_uid < 1 or s.daily_recovery > 1: return "非法每日次数或物品序号"
	for key in ["items","ledger","known","upgrades","active_upgrades","read","sales","summaries","customers"]:
		if not s[key] is Array: return "非法数组："+key
	for key in ["commits","requests","pending","tiers","supply","quests","progression","expedition","expedition_attempts","collected_drops"]:
		if not s[key] is Dictionary: return "非法对象："+key
	var customer_count = 7 if s.day == 1 else (8 if s.day == 2 else 9)
	if s.items.size() > CAPACITY or s.customers.size() != customer_count or s.cursor > customer_count: return "容量或客流非法"
	var uids = {}; var counts = {}; var shelf_types = {}; var equipped = 0
	for item in s.items:
		if not item is Dictionary or not item.has_all(["uid","item_id","cost","location"]): return "不完整物品"
		if not _whole(item.uid,1) or item.uid >= s.next_uid or uids.has(str(int(item.uid))): return "重复或非法物品实例"
		uids[str(int(item.uid))] = item
		if not Catalog.ITEMS.has(item.item_id) or not _whole(item.cost) or item.location not in ["bag","shelf","installed"]: return "非法物品属性"
		counts[item.item_id] = counts.get(item.item_id,0)+1
		if item.location == "shelf":
			if Catalog.ITEMS[item.item_id].kind != "dish": return "菜单中存在非料理"
			shelf_types[item.item_id] = true
		if item.location == "installed":
			if item.item_id != "stirring_cauldron": return "非法装配物"
			equipped += 1
	if equipped > 1 or shelf_types.size() > (3 if "shelf" in s.active_upgrades else 2): return "装配或菜单容量非法"
	if s.known.size() != Catalog.RECIPES.size(): return "已知菜谱缺失"
	var known_seen = {}
	for id in s.known:
		if not Catalog.RECIPES.has(id) or known_seen.has(id): return "非法已知菜谱"
		known_seen[id] = true
	for text in s.read:
		if not text is String: return "非法已读信息"
	for field in ["upgrades","active_upgrades"]:
		var seen = {}
		for id in s[field]:
			if not Catalog.UPGRADES.has(id) or seen.has(id): return "非法升级"
			seen[id] = true
			if field == "active_upgrades" and id not in s.upgrades: return "未购买的升级生效"
	if s.phase != "settled" and s.active_upgrades != s.upgrades: return "升级次日生效状态不一致"
	var progress = s.progression
	if not progress.has_all(["owned_weapons","equipped_weapon","skills","pending_unlocks"]): return "成长字段缺失"
	var active_kit = "field_kit" in s.active_upgrades
	if progress.owned_weapons != (["bolt_wand","fan_wand"] if active_kit else ["bolt_wand"]): return "武器取得来源不一致"
	if progress.skills != (["gust"] if active_kit else []): return "技能取得来源不一致"
	if progress.equipped_weapon not in progress.owned_weapons: return "未拥有的装备"
	if progress.pending_unlocks != (["fan_wand","gust"] if "field_kit" in s.upgrades and not active_kit else []): return "成长待生效状态不一致"
	for id in s.tiers:
		if not Catalog.ITEMS.has(id) or Catalog.ITEMS[id].kind != "dish" or not Catalog.TIERS.has(s.tiers[id]): return "非法定价"
	for id in s.supply:
		if not Catalog.ITEMS.has(id) or not _whole(s.supply[id],0,14): return "非法货源"
		if id not in ["flour","pumpkin","cream","ember_herb","stirring_cauldron"]: return "战斗食材不能凭空供应"
		if id == "ember_herb" and "supply_pass" not in s.active_upgrades: return "未解锁的供货"
		if id == "stirring_cauldron" and (s.day == 1 or s.supply[id] > 1): return "替代厨具供货非法"
	var order_seen = {}
	for i in range(customer_count):
		var order = s.customers[i]
		if not order is Dictionary or not order.has_all(["id","special","required","budget","text","character_id","quest_id","rewards"]): return "不完整顾客"
		if not order.id is String or not order.special is bool or not order.required is Array or order.required.is_empty() or not _whole(order.budget,0,100): return "非法需求"
		if order_seen.has(order.id) or order.special != (i == 2): return "重复顾客或特殊需求位置非法"
		order_seen[order.id] = true
		for tag in order.required:
			if tag not in Catalog.TAGS: return "未知需求效果"
		if not order.text is String or not order.rewards is Array: return "非法订单说明或奖励"
		var hagrid = s.day == 2 and i == 2
		if order.character_id != ("hagrid" if hagrid else "") or order.quest_id != ("hagrid_patrol" if hagrid else ""): return "人物任务身份不一致"
		if order.rewards != ([{"item_id":"ember_herb","quantity":2}] if hagrid else []): return "人物任务奖励不一致"
		if hagrid and order.id != "d2-hagrid-patrol": return "海格订单身份错误"
	if not s.pending.is_empty():
		if s.phase != "trading" or s.cursor >= customer_count or s.pending != s.customers[int(s.cursor)] or not s.pending.special: return "待处理需求游标不一致"
	if s.phase in ["closing","settled"] and (s.cursor != customer_count or not s.pending.is_empty()): return "日结客流不完整"
	if s.phase in ["shopping","expedition","preparation"] and (s.cursor != 0 or not s.pending.is_empty()): return "准备阶段客流非法"
	if s.phase == "trading" and s.cursor >= customer_count: return "营业游标已越界"
	if s.phase != "trading" and s.clock_ms != 0: return "非营业阶段时钟非法"
	if s.phase == "trading" and s.pending.is_empty() and s.clock_ms >= 1000: return "营业时钟未处理"
	var sale_seen = {}; var revenues = {}; var costs = {}; var quest_status = "not_offered"
	for sale in s.sales:
		if not sale is Dictionary or not sale.has_all(["day","order_id","item_id","revenue","cost","reasons","character_id","quest_id","rewards","effect_id"]): return "不完整成交记录"
		if not _whole(sale.day,1,int(s.day)) or not sale.order_id is String or sale.order_id.is_empty() or sale_seen.has(sale.order_id): return "重复或非法成交订单"
		if not _whole(sale.revenue) or not _whole(sale.cost) or not sale.reasons is Array or sale.reasons.is_empty(): return "非法成交经济数据"
		for reason in sale.reasons:
			if not reason is String: return "非法成交原因"
		if sale.revenue > 0:
			if not Catalog.ITEMS.has(sale.item_id) or Catalog.ITEMS[sale.item_id].kind != "dish" or not sale.has("uid") or not _whole(sale.uid,1) or sale.uid >= s.next_uid: return "非法成交物品"
			if sale.effect_id != Catalog.ITEMS[sale.item_id].effect_id: return "菜品效果与成交不一致"
		elif sale.item_id != "" or sale.cost != 0: return "未成交不能消耗商品成本"
		sale_seen[sale.order_id] = sale
		revenues[str(int(sale.day))] = revenues.get(str(int(sale.day)),0)+int(sale.revenue)
		costs[str(int(sale.day))] = costs.get(str(int(sale.day)),0)+int(sale.cost)
		if not s.commits.has(sale.order_id): return "成交缺少提交记录"
		if sale.order_id == "d2-hagrid-patrol":
			if sale.day != 2 or sale.character_id != "hagrid" or sale.quest_id != "hagrid_patrol": return "海格任务成交身份错误"
			quest_status = "completed" if sale.revenue > 0 else "declined"
			if sale.rewards != ([{"item_id":"ember_herb","quantity":2}] if sale.revenue > 0 else []): return "海格奖励轨迹错误"
	if "field_kit" in s.upgrades and _dish_income(s) < 24: return "探索套装缺少营业收入"
	if s.pending.get("quest_id","") == "hagrid_patrol": quest_status = "pending"
	if s.quests != {"hagrid_patrol":quest_status}: return "人物任务持久状态不一致"
	for i in range(customer_count):
		var processed = i < s.cursor
		if s.commits.has(s.customers[i].id) != processed or sale_seen.has(s.customers[i].id) != processed: return "顾客游标与提交记录不一致"
	var expected_summaries = int(s.day) if s.phase == "settled" else int(s.day)-1
	if s.summaries.size() != expected_summaries: return "日结数量不一致"
	for i in range(s.summaries.size()):
		var summary = s.summaries[i]
		if not summary is Dictionary or not summary.has_all(["day","revenue","sold_cost","gross_profit","fee","cash"]): return "不完整日结"
		if summary.day != i+1 or not s.commits.has("settle:%d" % (i+1)): return "日结日期或提交不一致"
		for key in ["revenue","sold_cost","fee","cash"]:
			if not _whole(summary[key]): return "非法日结数据"
		if summary.revenue != revenues.get(str(i+1),0) or summary.sold_cost != costs.get(str(i+1),0) or summary.gross_profit != summary.revenue-summary.sold_cost or summary.fee > 4: return "日结与成交账不一致"
	var live = {}; var issued = {}; var cash = int(s.initial_cash); var balance = {}; var paid_upgrades = []; var drops = {}; var ledger_sales = {}
	for i in range(s.ledger.size()):
		var entry = s.ledger[i]
		if not entry is Dictionary or not entry.has_all(["index","kind","day","cash_delta","moves","created","removed","args","events"]): return "账本条目不完整"
		if entry.index != i or not _whole(entry.cash_delta,-1000000) or not entry.moves is Dictionary or not entry.created is Array or not entry.removed is Array: return "非法账本"
		if not _whole(entry.day,1,int(s.day)) or not entry.kind is String or not entry.args is Dictionary or not entry.events is Array: return "非法账本元数据"
		var moved = {}; var added_cost = 0; var removed_cost = 0
		for item in entry.removed:
			if not item is Dictionary or not item.has_all(["uid","item_id","cost"]): return "账本消耗实例缺失"
			if not _whole(item.uid,1) or not Catalog.ITEMS.has(item.item_id) or not _whole(item.cost): return "账本消耗实例非法"
			var key = str(int(item.uid))
			if not live.has(key) or live[key].item_id != item.item_id or live[key].cost != item.cost: return "物品成本或消耗来源不一致"
			live.erase(key); removed_cost += int(item.cost); moved[item.item_id] = moved.get(item.item_id,0)-1
		for item in entry.created:
			if not item is Dictionary or not item.has_all(["uid","item_id","cost"]) or not _whole(item.uid,1) or item.uid >= s.next_uid or not Catalog.ITEMS.has(item.item_id) or not _whole(item.cost): return "账本创建实例非法"
			var key = str(int(item.uid))
			if issued.has(key): return "物品实例重复取得"
			issued[key] = true; live[key] = item; added_cost += int(item.cost); moved[item.item_id] = moved.get(item.item_id,0)+1
		for id in moved:
			if moved[id] == 0: continue
			if entry.moves.get(id,0) != moved[id]: return "实例与库存流水不一致"
		for id in entry.moves:
			if not Catalog.ITEMS.has(id) or not _whole(entry.moves[id],-80,80) or moved.get(id,0) != entry.moves[id]: return "非法库存流水"
			balance[id] = balance.get(id,0)+int(entry.moves[id])
			if balance[id] < 0: return "历史库存为负"
		var expected_cash = 0
		match entry.kind:
			"inheritance":
				if i != 0 or entry.created.size() != 1 or entry.created[0].item_id != "stirring_cauldron" or added_cost != 0 or not entry.removed.is_empty(): return "遗留厨具来源错误"
			"buy":
				var id = entry.args.get("item_id","")
				if not Catalog.ITEMS.has(id) or entry.created.size() != entry.args.get("quantity",0) or not entry.removed.is_empty(): return "采购流水错误"
				for item in entry.created:
					if item.item_id != id or item.cost != Catalog.ITEMS[id].buy: return "采购成本错误"
				expected_cash = -added_cost
			"craft":
				var recipe = Catalog.RECIPES.get(entry.args.get("recipe_id",""),{})
				if recipe.is_empty() or entry.created.size() != entry.args.get("quantity",0) or added_cost != removed_cost: return "制作成本错误"
				var materials = {}
				for item in entry.removed: materials[item.item_id] = materials.get(item.item_id,0)+1
				for id in recipe.inputs:
					if materials.get(id,0) != recipe.inputs[id]*entry.created.size(): return "制作原料错误"
				if materials.size() != recipe.inputs.size(): return "制作使用未知原料"
				for item in entry.created:
					if item.item_id != recipe.output: return "制作产出错误"
			"recycle":
				if not entry.created.is_empty(): return "回收不能创建物品"
				for item in entry.removed: expected_cash += 18 if item.item_id == "stirring_cauldron" else int(item.cost/2)
			"consume":
				if entry.removed.size() != 1 or entry.removed[0].item_id != "floating_pie" or not entry.created.is_empty(): return "食用来源错误"
			"recover":
				expected_cash = 12
				if not entry.created.is_empty() or not entry.removed.is_empty(): return "洗锅奖励类型错误"
			"upgrade":
				var id = entry.args.get("upgrade_id","")
				if not Catalog.UPGRADES.has(id) or id in paid_upgrades: return "重复或非法升级支付"
				paid_upgrades.append(id); expected_cash = -int(Catalog.UPGRADES[id].cost)
			"settle": expected_cash = -mini(4,cash)
			"pickup":
				if not entry.args.get("drop_ids") is Array or entry.args.drop_ids.size() != entry.created.size() or not entry.removed.is_empty(): return "拾取数量不一致"
				for n in range(entry.created.size()):
					var id = entry.args.drop_ids[n]; var item = entry.created[n]
					if not id is String or id.is_empty() or drops.has(id) or item.item_id not in ["sparkcap","moonheart"] or item.cost != 0: return "非法或重复拾取"
					drops[id] = {"item_id":item.item_id,"uid":item.uid,"day":entry.day}
			"advance", "fulfill":
				var sold = {}; var reward_count = 0
				for event in entry.events:
					if not event is Dictionary or not _whole(event.get("revenue",0)): return "非法成交事件"
					if event.get("revenue",0) <= 0: continue
					if not event.has("order_id") or not sale_seen.has(event.order_id) or sale_seen[event.order_id] != event or ledger_sales.has(event.order_id): return "成交与账本事件不一致"
					ledger_sales[event.order_id] = true; expected_cash += int(event.revenue); sold[str(int(event.uid))] = event
					if event.quest_id == "hagrid_patrol": reward_count += 2
				if sold.size() != entry.removed.size() or entry.created.size() != reward_count: return "成交扣菜或任务奖励数量不一致"
				for item in entry.removed:
					if not sold.has(str(int(item.uid))) or sold[str(int(item.uid))].cost != item.cost: return "成交成本不一致"
				for item in entry.created:
					if item.item_id != "ember_herb" or item.cost != 0: return "海格奖励来源错误"
			_: return "未知经济流水类型"
		if entry.cash_delta != expected_cash: return "经济流水现金来源不一致"
		cash += int(entry.cash_delta)
		if cash < 0: return "历史现金为负"
	if cash != s.cash: return "现金账本不守恒"
	if paid_upgrades != s.upgrades or drops != s.collected_drops: return "升级或掉落来源不一致"
	if live.size() != s.items.size(): return "物品实例账本不守恒"
	for key in uids:
		if not live.has(key) or live[key].item_id != uids[key].item_id or live[key].cost != uids[key].cost: return "库存成本与取得来源不一致"
	for id in Catalog.ITEMS:
		if balance.get(id,0) != counts.get(id,0): return "库存账本不守恒："+id
	for sale in s.sales:
		if sale.revenue > 0 and not ledger_sales.has(sale.order_id): return "成交未入账"
	for key in s.commits:
		if not key is String or s.commits[key] != true: return "非法提交记录"
	for key in s.requests:
		if not key is String or not s.requests[key] is String: return "非法请求记录"
	if s.daily_recovery != (1 if s.commits.has("recover:%d" % int(s.day)) else 0): return "恢复次数不一致"
	for day in s.expedition_attempts:
		if not day is String or not day.is_valid_int() or int(day) < 1 or int(day) > s.day or s.expedition_attempts[day] != "d%s-expedition" % day: return "每日探险记录错误"
	if not s.expedition.is_empty():
		if _expedition_model() == null: return "动作模块尚未集成"
		var error: String = _model.validate(s.expedition)
		if error != "": return error
		if s.expedition.day != s.day or s.expedition_attempts.get(str(int(s.day)),"") != s.expedition.run_id: return "动作日期或次数不一致"
		if s.phase == "expedition" and (s.expedition.weapon_id != progress.equipped_weapon or s.expedition.skills != progress.skills): return "动作装备或技能与成长不一致"
		if (s.phase == "expedition") != (s.expedition.status in ["active","cleared"]): return "动作与经营阶段不一致"
		for drop in s.expedition.drops:
			if drop.collected != s.collected_drops.has(drop.id): return "场上掉落与经济领取记录不一致"
	elif s.phase == "expedition": return "缺少动作模拟状态"
	return ""

func view() -> Dictionary:
	var v = snapshot()
	v.finished = _s.day == 3 and _s.phase == "settled"
	v.inventory = []; v.prices = {}
	for id in Catalog.ITEMS:
		var item = Catalog.ITEMS[id]
		var row = {"item_id":id,"name":item.name,"kind":item.kind,"effect_id":item.effect_id,
			"bag":_count(_s,id,"bag"),"shelf":_count(_s,id,"shelf"),"installed":_count(_s,id,"installed"),"tags":_tags(_s,id),"uids":[]}
		for instance in _s.items:
			if instance.item_id == id: row.uids.append(instance.duplicate(true))
		v.inventory.append(row); v.prices[id] = _price(_s,id)
	v.supply = []
	for id in _s.supply:
		var reason = ""
		if _s.phase != "shopping": reason = "请在采购阶段购买"
		elif _s.supply[id] <= 0: reason = "当日供货已售罄"
		elif _s.cash < Catalog.ITEMS[id].buy: reason = "金币不足"
		v.supply.append({"item_id":id,"name":Catalog.ITEMS[id].name,"quantity":_s.supply[id],"buy":Catalog.ITEMS[id].buy,"available":reason == "","reason":reason})
	v.recipes = []
	for id in Catalog.RECIPES:
		var recipe = Catalog.RECIPES[id].duplicate(true)
		var maximum = 80
		for material in recipe.inputs: maximum = mini(maximum,int(_count(_s,material,"bag") / recipe.inputs[material]))
		var missing_device = recipe.requires_device != "" and _count(_s,recipe.requires_device,"installed") == 0
		var reason = ""
		if _s.phase != "preparation": reason = "请在备餐阶段制作"
		elif missing_device: reason = "需装配自搅坩埚"
		elif maximum < 1: reason = "食材不足；查看采购或探险来源"
		recipe.recipe_id = id; recipe.max_quantity = 0 if missing_device else maximum
		recipe.available = reason == ""; recipe.reason = reason; recipe.effect_id = Catalog.ITEMS[id].effect_id
		v.recipes.append(recipe)
	v.upgrades = []
	for id in Catalog.UPGRADES:
		var row = Catalog.UPGRADES[id].duplicate(true)
		row.upgrade_id = id; row.owned = id in _s.upgrades; row.active = id in _s.active_upgrades
		row.available = _s.phase == "settled" and not row.owned and _s.cash >= row.cost and (id != "field_kit" or _dish_income(_s) >= 24)
		row.reason = "" if row.available else ("需累计菜品收入24" if id == "field_kit" and _dish_income(_s) < 24 else "请在日结后按资金购买；次日生效")
		v.upgrades.append(row)
	v.customers_remaining = _s.customers.size()-_s.cursor
	v.demand_board = []
	for order in _s.customers:
		var row = order.duplicate(true); row.processed = _s.commits.has(order.id); v.demand_board.append(row)
	v.forecast = {"day":3,"weather":"rain","required":["warming","heat_hold"],
		"text":"第三日雨天需要暖身与保温：供货契约次日开放稳定暖焰草，与每日南瓜煮暖焰汤；或保留装配遗留坩埚，用每日南瓜和奶油做炖锅。第三日庆功客想吃彗星馅饼，月心菇来自菇圃精英；未探险可跳过。",
		"solutions":[{"item_id":"ember_soup","materials":["pumpkin","ember_herb"],"requires_upgrade":"supply_pass","requires_device":"","source":"每日稳定供货"},
		{"item_id":"moon_stew","materials":["pumpkin","cream"],"requires_upgrade":"","requires_device":"stirring_cauldron","source":"每日基础供货；开店遗留或次日替代厨具"}]}
	v.summary = _s.summaries.back().duplicate(true) if not _s.summaries.is_empty() else {}
	v.shelf_capacity = 3 if "shelf" in _s.active_upgrades else 2
	v.inventory_capacity = CAPACITY; v.dish_income = _dish_income(_s)
	v.available_commands = {}
	var phases = {"buy":["shopping"],"finish_shopping":["shopping"],"craft":["preparation"],"display":["preparation"],"undisplay":["preparation"],"install":["preparation"],"uninstall":["preparation"],"price":["preparation"],"open_shop":["preparation"],"fulfill":["trading"],"decline":["trading"],"settle":["closing"],"upgrade":["settled"],"next_day":["settled"],"recover":["shopping"],"recycle":["shopping","preparation"],"start_expedition":["shopping"],"leave_expedition":["expedition"],"expedition_input":["expedition"],"consume":["shopping"],"equip_weapon":["shopping"]}
	for kind in phases:
		var enabled = _s.phase in phases[kind]
		var reason = "" if enabled else "当前阶段不可用"
		if kind in ["fulfill","decline"] and _s.pending.is_empty(): enabled = false; reason = "没有待处理需求"
		if kind == "next_day" and _s.day >= 3: enabled = false; reason = "三日原型结束，可保存退出"
		if kind == "recover" and _s.daily_recovery >= 1: enabled = false; reason = "今日洗锅委托已用"
		if kind == "start_expedition" and _s.expedition_attempts.has(str(_s.day)): enabled = false; reason = "今日探险次数已用"
		if kind == "consume" and (_s.next_expedition_shield or _count(_s,"floating_pie","bag") == 0): enabled = false; reason = "需储藏浮空饼且无待用护盾"
		v.available_commands[kind] = {"enabled":enabled,"reason":reason}
	if not v.pending.is_empty():
		v.pending.options = []
		for id in Catalog.ITEMS:
			if Catalog.ITEMS[id].kind != "dish": continue
			var reason = _matching(_s,id,_s.pending)
			if reason == "" and _s.items.size()-1+_reward_quantity(_s.pending) > CAPACITY: reason = "储藏容量不足以接收奖励"
			v.pending.options.append({"item_id":id,"name":Catalog.ITEMS[id].name,"price":_price(_s,id),"available":reason == "","reason":reason})
	if _s.expedition.is_empty():
		v.expedition = {"status":"idle","day":_s.day,"run_id":"","remaining_ms":180000,"attempts_remaining":0 if _s.expedition_attempts.has(str(_s.day)) else 1,"player":{},"enemies":[],"projectiles":[],"drops":[]}
	else: v.expedition = _model.view(_s.expedition)
	return v
