extends RefCounted

const Catalog = preload("res://game/core/catalog.gd")
const Store = preload("res://game/core/save_store.gd")
const VERSION = 1
const CAPACITY = 80
var _s: Dictionary

func _init(seed_value: int = 1):
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	_s = {"version":VERSION,"seed":str(seed_value),"rng_state":str(rng.state),"day":1,
		"phase":"shopping","paused":false,"clock_ms":0,"cursor":0,"customers":[],"pending":{},
		"cash":100,"initial_cash":100,"items":[],"next_uid":1,"ledger":[],"commits":{},"requests":{},
		"known":["pen","lamp","charm"],"upgrades":[],"read":[],"supply":{},"daily_recovery":0,
		"tiers":{},"sales":[],"summaries":[]}
	_begin_day(_s)

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

func _tags(s: Dictionary, item_id: String) -> Array:
	var tags: Array = Catalog.ITEMS[item_id].tags.duplicate()
	if item_id in ["pen","lamp"] and _count(s,"bell","installed") > 0:
		tags.append("waterproof")
	return tags

func _price(s: Dictionary, item_id: String) -> int:
	var bonus = 25 if s.day == 3 and "waterproof" in _tags(s,item_id) else 0
	return Catalog.price(item_id,s.tiers.get(item_id,"standard"),bonus)

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

func _begin_day(s: Dictionary):
	var rng = RandomNumberGenerator.new()
	rng.seed = int(s.seed)
	rng.state = int(s.rng_state)
	s.supply = {}
	for id in ["feather","ink","timber","moss"]:
		s.supply[id] = 30 + rng.randi_range(0,5)
	if s.day == 1:
		s.supply.bell = 1
	if "supply_pass" in s.upgrades:
		for id in ["pen","lamp","charm"]:
			s.supply[id] = 12
	s.customers = []
	var needs = ["writing","writing","writing","home","home","home"]
	for i in range(needs.size()-1,0,-1):
		var j = rng.randi_range(0,i)
		var hold = needs[i]
		needs[i] = needs[j]
		needs[j] = hold
	for i in range(needs.size()):
		s.customers.append({"id":"d%d-c%d" % [s.day,i],"special":false,"required":[needs[i]],"budget":rng.randi_range(23,30)})
	var effect = {1:"light",2:"writing",3:"waterproof"}[int(s.day)]
	s.customers.insert(2,{"id":"d%d-special" % s.day,"special":true,"required":[effect],"budget":30,
		"text":"想在雨里继续使用的物件" if s.day == 3 else ("想要一盏温暖的灯" if s.day == 1 else "想要方便记笔记的文具")})
	s.rng_state = str(rng.state)
	s.cursor = 0
	s.clock_ms = 0
	s.daily_recovery = 0
	s.pending = {}

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

func _sell(s: Dictionary, order: Dictionary, item_id: String) -> Dictionary:
	var item = _take(s,item_id,1,"shelf")[0]
	var price = _price(s,item_id)
	s.cash += price
	var reasons = ["满足：" + ",".join(order.required),"预算%d ≥ 标价%d" % [order.budget,price]]
	if s.day == 3 and "waterproof" in _tags(s,item_id):
		reasons.append("第三日雨天需求 +25%（上限）")
	if item_id in ["pen","lamp"] and _count(s,"bell","installed") > 0:
		reasons.append("避雨铃赋予防水效果")
	var sale = {"day":s.day,"order_id":order.id,"item_id":item_id,"uid":item.uid,"revenue":price,"cost":item.cost,"reasons":reasons}
	s.sales.append(sale)
	s.commits[order.id] = true
	return sale

func _serve_normal(s: Dictionary, order: Dictionary) -> Dictionary:
	for item_id in Catalog.ITEMS:
		if _matching(s,item_id,order).is_empty():
			return _sell(s,order,item_id)
	var failure = {"day":s.day,"order_id":order.id,"item_id":"","revenue":0,"cost":0,"reasons":["货架无满足用途且预算可及的商品：" + ",".join(order.required)]}
	s.sales.append(failure)
	s.commits[order.id] = true
	return failure

func _apply(s: Dictionary, kind: String, a: Dictionary) -> Dictionary:
	var id = str(a.get("item_id",""))
	var quantity = a.get("quantity",0)
	if kind in ["buy","craft","display","undisplay","recycle"]:
		if not _whole(quantity,1,80):
			return _fail("invalid_quantity","数量必须为1至80的整数")
		quantity = int(quantity)
	if kind in ["buy","display","undisplay","recycle","price"] and not Catalog.ITEMS.has(id):
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
			for material in recipe.inputs:
				if _count(s,material,"bag") < int(recipe.inputs[material]) * quantity: return _fail("insufficient_materials","材料不足")
			for n in range(quantity):
				var basis = 0
				for material in recipe.inputs:
					for item in _take(s,material,int(recipe.inputs[material]),"bag"): basis += int(item.cost)
				_add(s,recipe.output,basis)
		"display", "undisplay":
			if s.phase != "preparation": return _fail("wrong_phase","只可在整备时调整陈列")
			var source = "bag" if kind == "display" else "shelf"
			var target = "shelf" if kind == "display" else "bag"
			if _count(s,id,source) < quantity: return _fail("insufficient_inventory","可移动库存不足；装配物不能出售")
			if kind == "display" and _count(s,id,"shelf") == 0:
				var types = {}
				for item in s.items:
					if item.location == "shelf": types[item.item_id] = true
				if types.size() >= (3 if "shelf" in s.upgrades else 2): return _fail("capacity","陈列种类槽不足")
			for item in _take(s,id,quantity,source):
				item.location = target
				s.items.append(item)
		"install", "uninstall":
			if s.phase != "preparation": return _fail("wrong_phase","只可在整备时装配")
			var found = false
			for item in s.items:
				if item.uid == a.get("uid",-1):
					if item.item_id != "bell": return _fail("not_device","该物品不是设备")
					var source = "bag" if kind == "install" else "installed"
					if item.location != source: return _fail("unavailable","设备位置不符")
					if kind == "install" and _count(s,"bell","installed") >= 1: return _fail("capacity","装配槽已满")
					item.location = "installed" if kind == "install" else "bag"
					found = true
					break
			if not found: return _fail("unknown_id","没有该物品实例")
		"price":
			if s.phase != "preparation": return _fail("wrong_phase","只可在整备时定价")
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
				event = _sell(s,s.pending,id)
			else:
				event = {"day":s.day,"order_id":s.pending.id,"item_id":"","revenue":0,"cost":0,"reasons":["玩家跳过特殊需求"]}
				s.sales.append(event)
				s.commits[s.pending.id] = true
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
			var cost = int(Catalog.UPGRADES[upgrade_id].cost)
			if s.cash < cost: return _fail("insufficient_cash","升级金币不足")
			s.cash -= cost
			s.upgrades.append(upgrade_id)
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
			for item in _take(s,id,quantity,"bag"): s.cash += int(item.cost / 2)
		"pause":
			if not a.get("value") is bool: return _fail("invalid_value","暂停值须为布尔")
			s.paused = a.value
		_:
			return _fail("unknown_command","未知操作")
	return _result(true,"ok","操作完成")

func command(kind: String, args: Dictionary = {}, request_id: String = "") -> Dictionary:
	var fingerprint = JSON.stringify({"kind":kind,"args":args})
	if not request_id.is_empty() and _s.requests.has(request_id):
		if _s.requests[request_id] != fingerprint: return _fail("request_conflict","同一请求ID不能更换操作参数")
		return _result(true,"duplicate","该操作已提交")
	var candidate = _s.duplicate(true)
	var result = _apply(candidate,kind,args)
	if not result.ok: return result
	if candidate == _s: return result
	var movements = {}
	for item_id in Catalog.ITEMS:
		var change = _count(candidate,item_id) - _count(_s,item_id)
		if change != 0: movements[item_id] = change
	candidate.ledger.append({"index":candidate.ledger.size(),"kind":kind,"day":candidate.day,
		"cash_delta":candidate.cash-_s.cash,"moves":movements,"args":args.duplicate(true),"events":result.events.duplicate(true)})
	if not request_id.is_empty(): candidate.requests[request_id] = fingerprint
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
		loaded.erase("state")
	return loaded

func _normalize(value: Variant) -> Variant:
	if value is float: return int(value)
	if value is Array:
		var out: Array = []
		for entry in value: out.append(_normalize(entry))
		return out
	if value is Dictionary:
		var out = {}
		for key in value: out[key] = _normalize(value[key])
		return out
	return value

func validate_snapshot(data: Variant) -> String:
	if not data is Dictionary: return "存档必须为对象"
	var s: Dictionary = data
	for key in _s:
		if not s.has(key): return "存档缺少字段：" + key
	if s.version != VERSION: return "不支持的存档版本"
	for key in ["seed","rng_state"]:
		if not s[key] is String or not s[key].is_valid_int() or str(int(s[key])) != s[key]: return "随机状态必须为无损整数字符串"
	if not _whole(s.day,1,3) or s.phase not in ["shopping","preparation","trading","closing","settled"]: return "非法日历或阶段"
	if not s.paused is bool or not _whole(s.clock_ms,0,60000): return "非法时钟"
	for key in ["cash","initial_cash","next_uid","cursor","daily_recovery"]:
		if not _whole(s[key]): return "非法整数：" + key
	if s.next_uid < 1 or s.daily_recovery > 1: return "非法每日次数或物品序号"
	for key in ["items","ledger","known","upgrades","read","sales","summaries","customers"]:
		if not s[key] is Array: return "非法数组：" + key
	for key in ["commits","requests","pending","tiers","supply"]:
		if not s[key] is Dictionary: return "非法对象：" + key
	if s.items.size() > CAPACITY or s.customers.size() != 7 or s.cursor > 7: return "容量或客流非法"
	var uids = {}
	var counts = {}
	var shelf_types = {}
	var equipped = 0
	for item in s.items:
		if not item is Dictionary: return "非法物品"
		for key in ["uid","item_id","cost","location"]:
			if not item.has(key): return "不完整物品"
		if not _whole(item.uid,1) or item.uid >= s.next_uid or uids.has(str(item.uid)): return "重复或非法物品实例"
		uids[str(item.uid)] = true
		if not Catalog.ITEMS.has(item.item_id) or not _whole(item.cost) or item.location not in ["bag","shelf","installed"]: return "非法物品属性"
		counts[item.item_id] = counts.get(item.item_id,0)+1
		if item.location == "shelf": shelf_types[item.item_id] = true
		if item.location == "installed":
			if item.item_id != "bell": return "非法装配物"
			equipped += 1
	if equipped > 1 or shelf_types.size() > (3 if "shelf" in s.upgrades else 2): return "装配或陈列容量非法"
	for id in s.known:
		if not Catalog.RECIPES.has(id): return "未知配方"
	var upgrade_seen = {}
	for id in s.upgrades:
		if not Catalog.UPGRADES.has(id) or upgrade_seen.has(id): return "非法升级"
		upgrade_seen[id] = true
	for id in s.tiers:
		if not Catalog.ITEMS.has(id) or not Catalog.TIERS.has(s.tiers[id]): return "非法定价"
	for id in s.supply:
		if not Catalog.ITEMS.has(id) or not _whole(s.supply[id],0,40): return "非法货源"
	for i in range(7):
		var order = s.customers[i]
		if not order is Dictionary: return "非法顾客"
		for key in ["id","special","required","budget"]:
			if not order.has(key): return "不完整顾客"
		if not order.id is String or not order.special is bool or not order.required is Array or order.required.is_empty() or not _whole(order.budget,0,100): return "非法需求"
		for tag in order.required:
			if tag not in ["writing","home","light","waterproof"]: return "未知需求效果"
	if not s.pending.is_empty():
		if s.phase != "trading" or s.cursor >= 7 or s.pending != s.customers[int(s.cursor)] or not s.pending.special: return "待处理需求游标不一致"
	if s.phase in ["closing","settled"] and (s.cursor != 7 or not s.pending.is_empty()): return "日结客流不完整"
	if s.phase in ["shopping","preparation"] and (s.cursor != 0 or not s.pending.is_empty()): return "准备阶段客流非法"
	var cash = int(s.initial_cash)
	var balance = {}
	for i in range(s.ledger.size()):
		var entry = s.ledger[i]
		if not entry is Dictionary or not entry.has_all(["index","kind","day","cash_delta","moves","args","events"]): return "账本条目不完整"
		if entry.index != i or not _whole(entry.cash_delta,-1000000) or not entry.moves is Dictionary: return "非法账本"
		cash += int(entry.cash_delta)
		for id in entry.moves:
			if not Catalog.ITEMS.has(id) or not _whole(entry.moves[id],-80,80): return "非法库存流水"
			balance[id] = balance.get(id,0)+int(entry.moves[id])
	if cash != s.cash: return "现金账本不守恒"
	for id in Catalog.ITEMS:
		if balance.get(id,0) != counts.get(id,0): return "库存账本不守恒："+id
	for key in s.commits:
		if not key is String or s.commits[key] != true: return "非法提交记录"
	for key in s.requests:
		if not key is String or not s.requests[key] is String: return "非法请求记录"
	if s.daily_recovery != (1 if s.commits.has("recover:%d" % int(s.day)) else 0): return "恢复次数不一致"
	if s.phase == "settled" and not s.commits.has("settle:%d" % int(s.day)): return "日结提交记录缺失"
	return ""

func view() -> Dictionary:
	var v = snapshot()
	v.finished = _s.day == 3 and _s.phase == "settled"
	v.inventory = []
	v.prices = {}
	for id in Catalog.ITEMS:
		var item = Catalog.ITEMS[id]
		var row = {"item_id":id,"name":item.name,"bag":_count(_s,id,"bag"),"shelf":_count(_s,id,"shelf"),"installed":_count(_s,id,"installed"),"tags":_tags(_s,id),"uids":[]}
		for instance in _s.items:
			if instance.item_id == id: row.uids.append(instance.duplicate(true))
		v.inventory.append(row)
		v.prices[id] = _price(_s,id)
	v.supply = []
	for id in _s.supply:
		v.supply.append({"item_id":id,"name":Catalog.ITEMS[id].name,"quantity":_s.supply[id],"buy":Catalog.ITEMS[id].buy,
			"available":_s.phase == "shopping" and _s.supply[id] > 0 and _s.cash >= Catalog.ITEMS[id].buy,
			"reason":"" if _s.phase == "shopping" else "请在淘货阶段采购"})
	v.recipes = []
	for id in Catalog.RECIPES:
		var recipe = Catalog.RECIPES[id].duplicate(true)
		var maximum = 80
		for material in recipe.inputs: maximum = mini(maximum,int(_count(_s,material,"bag") / recipe.inputs[material]))
		recipe.recipe_id = id
		recipe.max_quantity = maximum
		recipe.available = _s.phase == "preparation" and maximum > 0
		recipe.reason = "" if recipe.available else ("材料不足" if _s.phase == "preparation" else "请在整备阶段制作")
		v.recipes.append(recipe)
	v.upgrades = []
	for id in Catalog.UPGRADES:
		var row = Catalog.UPGRADES[id].duplicate(true)
		row.upgrade_id = id
		row.owned = id in _s.upgrades
		row.available = _s.phase == "settled" and not row.owned and _s.cash >= row.cost
		v.upgrades.append(row)
	v.customers_remaining = _s.customers.size()-_s.cursor
	v.demand_board = []
	for order in _s.customers:
		v.demand_board.append({"id":order.id,"special":order.special,"required":order.required.duplicate(),"budget":order.budget,"processed":_s.commits.has(order.id)})
	v.forecast = {"day":3,"weather":"rain","required":["waterproof"],"text":"第三日有雨：防潮护符，或避雨铃庇护的笔/灯可满足需求；雨光苔每日在旧货摊稳定供应，避雨铃首日保证供应。"}
	v.summary = _s.summaries.back().duplicate(true) if not _s.summaries.is_empty() else {}
	v.shelf_capacity = 3 if "shelf" in _s.upgrades else 2
	v.inventory_capacity = CAPACITY
	v.available_commands = {}
	for kind in ["buy","finish_shopping","craft","display","undisplay","install","uninstall","price","open_shop","fulfill","decline","settle","upgrade","next_day","recover","recycle"]:
		var phases = {"buy":["shopping"],"finish_shopping":["shopping"],"craft":["preparation"],"display":["preparation"],"undisplay":["preparation"],"install":["preparation"],"uninstall":["preparation"],"price":["preparation"],"open_shop":["preparation"],"fulfill":["trading"],"decline":["trading"],"settle":["closing"],"upgrade":["settled"],"next_day":["settled"],"recover":["shopping"],"recycle":["shopping","preparation"]}
		var enabled = _s.phase in phases[kind]
		var reason = "" if enabled else "当前阶段不可用"
		if kind in ["fulfill","decline"] and _s.pending.is_empty(): enabled = false; reason = "没有待处理需求"
		if kind == "next_day" and _s.day >= 3: enabled = false; reason = "三日原型结束，可保存退出"
		if kind == "recover" and _s.daily_recovery >= 1: enabled = false; reason = "今日免费委托已用"
		v.available_commands[kind] = {"enabled":enabled,"reason":reason}
	if not v.pending.is_empty():
		v.pending.options = []
		for id in Catalog.ITEMS:
			var reason = _matching(_s,id,_s.pending)
			v.pending.options.append({"item_id":id,"name":Catalog.ITEMS[id].name,"price":_price(_s,id),"available":reason.is_empty(),"reason":reason})
	return v
