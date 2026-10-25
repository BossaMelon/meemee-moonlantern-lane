extends "res://game/core/legacy_session.gd"
## Rain-night v3 owns its rules; inherited helpers retain atomic commands and UID accounting.
const PROFILE_ID = "rain-night-v1"
const SAVE_PATH = "user://profiles/rain-night-v1/moonlantern.json"
const STEP_MS = 50
const WAIT_MS = 20000
const MAP_ID = "rain-garden-two-routes"
const DELIVERY_MS = {"ordinary":3000,"floating":1500,"pot":4500}
const QUALITY_UPGRADES = {
	"field_kit":{"name":"散射魔杖","cost":60,"description":"菜品收入达到24后投资，次晨可装备散射杖"},
	"shelf":{"name":"扩展菜单","cost":60,"description":"次晨同时供应第三种料理"}}
const PHASE_COMMANDS = {
	"buy":["shopping"],"finish_shopping":["shopping"],"craft":["shopping","preparation","intermission"],
	"display":["preparation","intermission"],"undisplay":["preparation","intermission"],
	"price":["preparation","intermission"],"set_menu_priority":["preparation","intermission"],
	"install":["preparation"],"uninstall":["preparation"],"open_shop":["preparation"],"start_wave":["intermission"],
	"fulfill":["trading"],"decline":["trading"],"settle":["closing"],"upgrade":["settled"],"next_day":["settled"],
	"recover":["shopping"],"recycle":["shopping","preparation"],"consume":["shopping"],
	"equip_weapon":["shopping"],"start_expedition":["shopping"],"leave_expedition":["expedition"],"expedition_input":["expedition"]}

func _init(seed_value: int = 1):
	super(seed_value)
	_s.version = 3; _s.profile_id = PROFILE_ID; _s.rules_version = 1
	_s.erase("next_expedition_shield")
	_s.pending_meal_effect = null; _s.expedition_meals = {}; _s.night = {}; _s.service = {}
	_s.progression.skills = ["gust"]
	var rng = RandomNumberGenerator.new(); rng.seed = seed_value; _s.rng_state = str(rng.state)
	_begin_night(_s)

func _begin_night(s: Dictionary):
	var held = s.service.get("held_uids",[]).duplicate()
	var priority = s.service.get("menu_priority",[]).duplicate()
	s.active_upgrades = s.upgrades.duplicate()
	s.progression.owned_weapons = ["bolt_wand","fan_wand"] if "field_kit" in s.active_upgrades else ["bolt_wand"]
	s.progression.skills = ["gust"]; s.progression.pending_unlocks = []
	var rng = RandomNumberGenerator.new(); rng.seed = int(s.seed); rng.state = int(s.rng_state)
	s.supply = {}
	for id in ["flour","pumpkin","cream","ember_herb"]: s.supply[id] = 12+rng.randi_range(0,2)
	if s.day >= 2: s.supply.stirring_cauldron = 1
	var night_id = "n%d" % s.day
	s.night = {"id":night_id,"day":s.day,"weather":"rain","event_id":"rain_return","waves":[],"queues":{}}
	s.service = {"night_id":night_id,"wave_id":null,"next_wave_id":night_id+"-w1","wave_index":0,"status":"planned",
		"orders":[],"reservations":[],"menu_priority":priority,"held_uids":held,"elapsed_ms":0,"remainder_ms":0}
	var needs = [[5,3],[3,6],[5,4]]
	for wave in range(3):
		var wave_id = night_id+"-w%d" % (wave+1)
		var total = needs[wave][0]+needs[wave][1]
		var summary = {"id":wave_id,"index":wave+1,"ordinary_count":total,"quick":needs[wave][0],"warm":needs[wave][1] if wave != 1 else 0,"hearty":needs[wave][1] if wave == 1 else 0,"budget_min":23,"budget_max":30}
		s.night.waves.append(summary)
		s.night.queues[wave_id] = []
		for i in range(total):
			var required = ["meal","quick"] if i < needs[wave][0] else (["meal","hearty"] if wave == 1 else ["meal","warming","heat_hold"])
			if s.day >= 2 and wave == 0 and i == 7: required = ["meal","trail_light"]
			if s.day >= 2 and wave == 2 and i == 8: required = ["meal","celebration"]
			var order = _order(wave_id+"-c%02d" % (i+1),required,rng.randi_range(23,30))
			order.wave_id = wave_id; order.status = "waiting"; order.arrival_ms = 0; order.patience_ms = WAIT_MS; order.waited_ms = 0; order.channel = null
			s.night.queues[wave_id].append(order)
	s.rng_state = str(rng.state)
	s.customers = []
	for queue in s.night.queues.values(): s.customers.append_array(queue.duplicate(true))
	s.cursor = 0; s.clock_ms = 0; s.pending = {}; s.daily_recovery = 0; s.expedition = {}

func _target_wave(s: Dictionary) -> String:
	return s.service.next_wave_id

func _add(s: Dictionary, item_id: String, cost: int, location: String = "bag"):
	super._add(s,item_id,cost,location)
	var item = s.items.back()
	item.prepared_wave_id = null; item.temperature = null
	if Catalog.ITEMS[item_id].kind == "dish":
		item.intrinsic_tags = Catalog.ITEMS[item_id].tags.duplicate()
		item.effect_id = Catalog.ITEMS[item_id].effect_id

func _instances(s: Dictionary, item_id: String, location: String) -> Array:
	var found = s.items.filter(func(item): return item.item_id == item_id and item.location == location)
	found.sort_custom(func(a,b): return int(a.uid) < int(b.uid))
	return found

func _item(s: Dictionary, uid: int) -> Dictionary:
	for item in s.items:
		if item.uid == uid: return item
	return {}

func _remove_item(s: Dictionary, uid: int) -> Dictionary:
	for i in range(s.items.size()):
		if s.items[i].uid == uid:
			var item = s.items[i]; s.items.remove_at(i); s.service.held_uids.erase(uid); return item
	return {}

func _take_oldest(s: Dictionary, id: String, quantity: int, location: String) -> Array:
	var items = _instances(s,id,location); var taken = []
	for n in range(quantity): taken.append(_remove_item(s,int(items[n].uid)))
	return taken

func _menu_types(s: Dictionary) -> Array:
	var ids = []
	for item in s.items:
		if item.location in ["shelf","reserved"] and item.item_id not in ids: ids.append(item.item_id)
	return ids

func _sync_priority(s: Dictionary):
	var ids = _menu_types(s); var priority = []
	for id in s.service.menu_priority:
		if id in ids: priority.append(id)
	for id in ids:
		if id not in priority: priority.append(id)
	s.service.menu_priority = priority

func _price(s: Dictionary, item_id: String) -> int:
	var rain = s.night.weather == "rain" and s.night.event_id == "rain_return" and _rain_dish(item_id)
	return Catalog.price(item_id,s.tiers.get(item_id,"standard"),25 if rain else 0)

func _match_instance(s: Dictionary, item: Dictionary, order: Dictionary) -> String:
	if Catalog.ITEMS[item.item_id].kind != "dish": return "not_dish"
	for tag in order.required:
		if tag not in item.intrinsic_tags: return "unmatched"
	if item.item_id == "moon_stew" and "warming" in order.required and item.temperature == "cooled": return "cooled"
	if _price(s,item.item_id) > order.budget: return "budget"
	return ""

func _channel(s: Dictionary, item: Dictionary) -> String:
	if item.item_id in ["floating_pie","comet_pie"] and item.prepared_wave_id == s.service.wave_id: return "floating"
	if item.item_id == "moon_stew" and _count(s,"stirring_cauldron","installed") > 0: return "pot"
	return "ordinary"

func _apply(s: Dictionary, kind: String, a: Dictionary) -> Dictionary:
	if kind == "pause": return super._apply(s,kind,a)
	if not PHASE_COMMANDS.has(kind): return _fail("unknown_command","未知操作")
	if s.phase not in PHASE_COMMANDS[kind]: return _fail("wrong_phase","当前阶段不可执行此操作")
	var id = a.get("item_id",""); var quantity = a.get("quantity",0)
	if kind in ["buy","craft","display","undisplay","recycle","consume"] and not _whole(quantity,1,80): return _fail("invalid_quantity","数量须为1至80整数")
	if kind in ["buy","display","undisplay","price","recycle","consume"] and not Catalog.ITEMS.has(id): return _fail("unknown_id","未知物品")
	match kind:
		"buy","finish_shopping","recover": return super._apply(s,kind,a)
		"install","uninstall":
			var result = super._apply(s,kind,a)
			if result.ok and kind == "uninstall": _cool_held(s)
			return result
		"craft":
			var recipe_id = a.get("recipe_id","")
			if not Catalog.RECIPES.has(recipe_id): return _fail("unknown_id","未知配方")
			var recipe = Catalog.RECIPES[recipe_id]
			if recipe.requires_device != "" and _count(s,recipe.requires_device,"installed") == 0: return _fail("missing_device","需装配自搅坩埚")
			for material in recipe.inputs:
				if _count(s,material,"bag") < recipe.inputs[material]*quantity: return _fail("insufficient_materials","材料不足")
			for n in range(int(quantity)):
				var cost = 0
				for material in recipe.inputs:
					for part in _take_oldest(s,material,recipe.inputs[material],"bag"): cost += int(part.cost)
				_add(s,recipe.output,cost)
				var dish = s.items.back(); dish.prepared_wave_id = _target_wave(s)
				dish.intrinsic_tags = Catalog.ITEMS[recipe.output].tags.duplicate(); dish.effect_id = Catalog.ITEMS[recipe.output].effect_id
				if recipe.output == "moon_stew": dish.temperature = "hot"
			return _result(true,"ok","批量备餐完成",[{"type":"crafted","item_id":recipe.output,"quantity":int(quantity),"effect_id":Catalog.ITEMS[recipe.output].effect_id}])
		"display","undisplay":
			if Catalog.ITEMS[id].kind != "dish": return _fail("not_dish","菜单只能供应已制成料理")
			var source = "bag" if kind == "display" else "shelf"
			if _count(s,id,source) < quantity: return _fail("insufficient_inventory","可移动库存不足")
			if kind == "display" and id not in _menu_types(s) and _menu_types(s).size() >= (3 if "shelf" in s.active_upgrades else 2): return _fail("capacity","菜单种类已满")
			for n in range(int(quantity)):
				var item = _instances(s,id,source)[0]
				if kind == "undisplay" and item.get("temperature","") == "held": item.temperature = "cooled"; s.service.held_uids.erase(item.uid)
				item.location = "shelf" if kind == "display" else "bag"
			_sync_priority(s)
		"set_menu_priority":
			var order = a.get("item_ids")
			if not order is Array or order.size() != _menu_types(s).size(): return _fail("invalid_priority","优先序必须完整列出菜单菜种")
			var seen = []
			for value in order:
				if not value is String or value not in _menu_types(s) or value in seen: return _fail("invalid_priority","优先序含重复或未知菜种")
				seen.append(value)
			s.service.menu_priority = order.duplicate()
		"price":
			if Catalog.ITEMS[id].kind != "dish": return _fail("not_dish","原料不可标为顾客菜品")
			if not Catalog.TIERS.has(a.get("tier")): return _fail("unknown_id","未知价格档")
			s.tiers[id] = a.tier
		"open_shop":
			if s.service.wave_index != 0: return _fail("wave_started","首波已经开始")
			return _start_wave(s,s.service.next_wave_id)
		"start_wave":
			if not a.get("wave_id") is String or a.wave_id != s.service.next_wave_id: return _fail("stale_wave","波次已过期或不匹配")
			return _start_wave(s,a.wave_id)
		"settle":
			var result = super._apply(s,kind,a)
			if result.ok:
				s.summaries.back().ingredient_sales = _ingredient_income(s,int(s.day))
				s.summaries.back().unsold_uids = s.items.filter(func(item): return Catalog.ITEMS[item.item_id].kind == "dish").map(func(item): return item.uid)
			return result
		"upgrade":
			var upgrade_id = a.get("upgrade_id","")
			if not QUALITY_UPGRADES.has(upgrade_id): return _fail("unknown_id","未知升级")
			if upgrade_id in s.upgrades: return _fail("already_owned","升级已经购买")
			if upgrade_id == "field_kit" and _dish_income(s) < 24: return _fail("income_required","需累计实际菜品收入24")
			if s.cash < QUALITY_UPGRADES[upgrade_id].cost: return _fail("insufficient_cash","升级金币不足")
			s.cash -= QUALITY_UPGRADES[upgrade_id].cost; s.upgrades.append(upgrade_id)
			if upgrade_id == "field_kit": s.progression.pending_unlocks = ["fan_wand"]
		"next_day":
			s.commits["next:%d" % s.day] = true; s.day += 1; s.phase = "shopping"; _begin_night(s)
		"recycle":
			if _count(s,id,"bag") < quantity: return _fail("insufficient_inventory","只能售回真实储藏实例")
			for item in _take_oldest(s,id,int(quantity),"bag"):
				s.cash += _recycle_value(item)
		"consume":
			if id not in ["floating_pie","star_soup"] or quantity != 1: return _fail("invalid_food","餐前只可食用一份浮空饼或星火汤")
			if s.pending_meal_effect != null: return _fail("meal_active","已有待用餐前效果，请保留其他料理")
			if _count(s,id,"bag") == 0: return _fail("insufficient_inventory","储藏中没有这份料理")
			var item = _take_oldest(s,id,1,"bag")[0]
			s.pending_meal_effect = {"effect_id":"light_step" if id == "floating_pie" else "clear_breath","source_item_uid":item.uid,"used":false}
			return _result(true,"ok","餐前效果已准备",[{"type":"consumed","item_id":id,"item_uid":item.uid,"effect_id":s.pending_meal_effect.effect_id}])
		"equip_weapon":
			if a.get("weapon_id","") not in s.progression.owned_weapons: return _fail("weapon_locked","未取得该武器")
			s.progression.equipped_weapon = a.weapon_id
		"start_expedition":
			if s.expedition_attempts.has(str(s.day)): return _fail("daily_limit","今日探险次数已使用")
			if _expedition_model() == null: return _fail("module_unavailable","动作模块尚未集成")
			var run_id = "n%d-expedition" % s.day
			var options = {"ruleset":PROFILE_ID,"map_id":MAP_ID,"map_revision":1,"meal_effect":s.pending_meal_effect}
			var created: Dictionary = _model.create(int(s.day),run_id,int(s.seed),s.progression.equipped_weapon,s.progression.skills,false,options)
			if created.is_empty() or created.get("version") != 2 or _model.validate(created) != "": return _fail("invalid_expedition","新规则探索创建失败，次数与餐前效果已保留")
			s.expedition = created; s.expedition_attempts[str(s.day)] = run_id
			s.expedition_meals[run_id] = s.pending_meal_effect.duplicate(true) if s.pending_meal_effect != null else null
			s.pending_meal_effect = null; s.phase = "expedition"
		"leave_expedition":
			var ended = _model.leave(s.expedition)
			if not ended.ok: return ended
			_model.set_input(s.expedition,{}); s.phase = "shopping"
			return _result(true,"ok","已返回采购，保留已拾取食材",ended.events)
		"fulfill","decline":
			if s.pending.is_empty(): return _fail("no_pending_order","当前没有待处理人物委托")
			if a.get("order_id") != s.pending.id: return _fail("stale_order","委托已处理或身份不匹配")
			var row: Dictionary
			if kind == "fulfill":
				var candidates = _instances(s,id,"shelf").filter(func(item): return _match_instance(s,item,s.pending).is_empty())
				if candidates.is_empty(): return _fail("unmatched","菜单上没有满足委托的未预留料理")
				if s.items.size()-1+2 > CAPACITY: return _fail("capacity","储藏不足以接收全部委托奖励")
				var item = _remove_item(s,int(candidates[0].uid)); var price = _price(s,id)
				s.cash += price; row = _sale_row(s,s.pending,id,price,item.cost,["matched","hagrid_patrol"])
				row.uid = item.uid; row.prepared_wave_id = item.prepared_wave_id; row.temperature = item.temperature
				for n in range(2): _add(s,"ember_herb",0)
				s.quests.hagrid_patrol = "completed"
			else:
				row = _sale_row(s,s.pending,"",0,0,["玩家跳过特殊需求"]); s.quests.hagrid_patrol = "declined"
			row.wave_id = null; row.channel = null; row.delivered_ms = s.service.elapsed_ms
			s.sales.append(row); s.commits[s.pending.id] = true; s.pending = {}; _sync_priority(s); _schedule(s)
			return _result(true,"ok","人物委托已处理",[row])
	return _result(true,"ok","操作完成")

func _recycle_value(item: Dictionary) -> int:
	if item.item_id == "sparkcap": return 4
	if item.item_id == "moonheart": return 8
	return 18 if item.item_id == "stirring_cauldron" else int(item.cost/2)

func _ingredient_income(s: Dictionary, day: int) -> int:
	var total = 0
	for entry in s.ledger:
		if entry.kind == "recycle" and entry.day == day:
			for item in entry.removed:
				if Catalog.ITEMS[item.item_id].kind == "ingredient": total += _recycle_value(item)
	return total

func _cool_held(s: Dictionary):
	for uid in s.service.held_uids:
		var item = _item(s,int(uid))
		if not item.is_empty(): item.temperature = "cooled"
	s.service.held_uids = []

func _hagrid_order() -> Dictionary:
	var order = _order("n2-hagrid-patrol",["meal","warming","heat_hold","portable"],30,true,"海格：巡护时想带一份始终温暖的料理")
	order.character_id = "hagrid"; order.quest_id = "hagrid_patrol"; order.rewards = [{"item_id":"ember_herb","quantity":2}]
	return order

func _start_wave(s: Dictionary, wave_id: String) -> Dictionary:
	if s.commits.has("wave:"+wave_id): return _fail("wave_started","该波已提交，不能重开")
	if not s.service.reservations.is_empty(): return _fail("in_flight","尚有在途料理")
	s.service.wave_index += 1; s.service.wave_id = wave_id
	s.service.next_wave_id = s.service.night_id+"-w%d" % (int(s.service.wave_index)+1) if s.service.wave_index < 3 else null
	s.service.orders = s.night.queues[wave_id].duplicate(true)
	s.service.status = "active"; s.service.elapsed_ms = 0; s.service.remainder_ms = 0
	s.phase = "trading"; s.commits["wave:"+wave_id] = true
	for order in s.service.orders:
		if order.wave_id == wave_id: order.status = "waiting"
	_schedule(s)
	if s.day == 2 and s.service.wave_index == 2 and s.quests.hagrid_patrol == "not_offered":
		s.pending = _hagrid_order(); s.quests.hagrid_patrol = "pending"
	return _result(true,"ok","本波开始",[{"type":"wave_started","wave_id":wave_id}])

func _schedule(s: Dictionary):
	var batch_id = s.service.wave_id+":%d" % s.service.elapsed_ms
	for order in s.service.orders:
		if order.wave_id != s.service.wave_id or order.status != "waiting" or order.special: continue
		var found = {}; var channel = ""
		for id in s.service.menu_priority:
			for item in _instances(s,id,"shelf"):
				if not _match_instance(s,item,order).is_empty(): continue
				var proposed = _channel(s,item)
				var active = s.service.reservations.filter(func(r): return r.channel == proposed)
				if proposed == "ordinary" and not active.is_empty(): continue
				if proposed == "floating" and active.size() >= 2: continue
				if proposed == "pot" and (active.size() >= 3 or (not active.is_empty() and active[0].batch_id != batch_id)): continue
				found = item; channel = proposed; break
			if not found.is_empty(): break
		if found.is_empty(): continue
		found.location = "reserved"; s.service.held_uids.erase(found.uid)
		order.status = "reserved"; order.channel = channel
		s.service.reservations.append({"item_uid":found.uid,"order_id":order.id,"channel":channel,"remaining_ms":DELIVERY_MS[channel],"batch_id":batch_id if channel == "pot" else null,"price":_price(s,found.item_id),"cost":found.cost})

func _unserved_reason(s: Dictionary, order: Dictionary) -> String:
	var reason = "unprepared"
	for id in s.service.menu_priority:
		for item in _instances(s,id,"shelf"):
			var mismatch = _match_instance(s,item,order)
			if mismatch.is_empty(): return "congestion"
			if mismatch == "budget": reason = "budget"
			elif mismatch == "cooled" and reason != "budget": reason = "cooled"
			elif reason == "unprepared": reason = "unmatched"
	return reason

func _deliver(s: Dictionary, reservation: Dictionary) -> Dictionary:
	var item = _remove_item(s,int(reservation.item_uid))
	var order: Dictionary
	for candidate in s.service.orders:
		if candidate.id == reservation.order_id: order = candidate; break
	order.status = "delivered"
	s.cash += int(reservation.price)
	var row = _sale_row(s,order,item.item_id,int(reservation.price),int(item.cost),["matched",reservation.channel])
	row.uid = item.uid; row.wave_id = order.wave_id; row.channel = reservation.channel; row.delivered_ms = s.service.elapsed_ms
	row.prepared_wave_id = item.prepared_wave_id
	if item.has("temperature"): row.temperature = item.temperature
	s.sales.append(row); s.commits[order.id] = true; s.cursor += 1
	return row

func _service_step(s: Dictionary, events: Array):
	s.service.elapsed_ms += STEP_MS
	var finished = []
	for reservation in s.service.reservations:
		reservation.remaining_ms -= STEP_MS
		if reservation.remaining_ms <= 0: finished.append(reservation)
	for reservation in finished:
		events.append(_deliver(s,reservation)); s.service.reservations.erase(reservation)
	for order in s.service.orders:
		if order.wave_id != s.service.wave_id or order.status != "waiting" or order.special: continue
		order.waited_ms = mini(int(order.patience_ms),int(order.waited_ms)+STEP_MS)
		if order.waited_ms >= order.patience_ms:
			var row = _sale_row(s,order,"",0,0,[_unserved_reason(s,order)])
			row.wave_id = order.wave_id; row.channel = null; row.delivered_ms = s.service.elapsed_ms
			s.sales.append(row); s.commits[order.id] = true; s.cursor += 1; order.status = "left"; events.append(row)
	_schedule(s)
	var unfinished = s.service.orders.any(func(order): return order.wave_id == s.service.wave_id and order.status in ["waiting","reserved","pending"])
	if not unfinished and s.service.reservations.is_empty(): _end_wave(s,events)

func _end_wave(s: Dictionary, events: Array):
	var keep = []
	if _count(s,"stirring_cauldron","installed") > 0:
		for id in s.service.menu_priority:
			if id != "moon_stew": continue
			for item in _instances(s,id,"shelf"):
				if item.temperature in ["hot","held"] and keep.size() < 3: keep.append(item.uid)
	for item in s.items:
		if item.item_id == "moon_stew": item.temperature = "held" if item.uid in keep else "cooled"
	s.service.held_uids = keep; s.service.remainder_ms = 0; s.clock_ms = 0
	if s.service.wave_index < 3:
		s.phase = "intermission"; s.service.status = "intermission"
		s.service.next_wave_id = s.service.night_id+"-w%d" % (int(s.service.wave_index)+1)
	else: s.phase = "closing"; s.service.status = "complete"; s.service.next_wave_id = null
	_sync_priority(s)
	events.append({"type":"wave_completed","wave_id":s.service.wave_id,"next_wave_id":s.service.next_wave_id})

func _advance(delta_ms: Variant) -> Dictionary:
	if not _whole(delta_ms,0,60000): return _fail("invalid_time","时间须为0至60000整数毫秒")
	if _s.phase == "expedition": return _advance_expedition(int(delta_ms))
	if _s.paused or _s.phase != "trading" or not _s.pending.is_empty(): return _result(true,"idle","当前时钟冻结")
	var candidate = _s.duplicate(true); var events = []
	candidate.service.remainder_ms += int(delta_ms)
	while candidate.service.remainder_ms >= STEP_MS and candidate.phase == "trading" and candidate.pending.is_empty():
		candidate.service.remainder_ms -= STEP_MS; _service_step(candidate,events)
	_record_economy(candidate,"advance",{"delta_ms":int(delta_ms)},events,int(_s.cash),_s.items)
	_s = candidate
	_action_trace.append({"kind":"advance","args":{"delta_ms":int(delta_ms)}})
	return _result(true,"ok","营业已推进",events)

func _drop_key(run_id: String, drop_id: String) -> String:
	return run_id+"|"+drop_id

func _advance_expedition(delta_ms: int) -> Dictionary:
	if _s.paused: return _result(true,"idle","暂停中")
	var next = _s.expedition.duplicate(true)
	var result = _model.advance(next,delta_ms,CAPACITY-_s.items.size(),false)
	if not result.ok: return result
	var seen = {}; var quantity = 0
	for pickup in result.pickups:
		if not pickup is Dictionary or not pickup.has_all(["drop_id","item_id","quantity","cost"]) or not pickup.drop_id is String or pickup.drop_id.is_empty() or pickup.item_id not in ["sparkcap","moonheart"] or not _whole(pickup.quantity,1,CAPACITY) or pickup.cost != 0:
			return _fail("invalid_pickup","动作模块返回了非法掉落")
		var key = _drop_key(next.run_id,pickup.drop_id)
		if _s.collected_drops.has(key) or seen.has(key): return _fail("duplicate_pickup","该次探索的掉落已领取")
		seen[key] = true; quantity += int(pickup.quantity)
	if _s.items.size()+quantity > CAPACITY: return _fail("capacity","动作拾取超出储藏容量")
	# Copy the economy only when the model actually acquired inventory.
	var candidate = _s.duplicate(true) if quantity > 0 else _s
	var old_items = _s.items if quantity > 0 else []
	candidate.expedition = next
	for pickup in result.pickups:
		var uids = []
		for n in range(int(pickup.quantity)):
			_add(candidate,pickup.item_id,0); uids.append(candidate.next_uid-1)
		candidate.collected_drops[_drop_key(next.run_id,pickup.drop_id)] = {"run_id":next.run_id,"drop_id":pickup.drop_id,"item_id":pickup.item_id,"quantity":int(pickup.quantity),"uids":uids,"day":candidate.day}
	if quantity > 0:
		var economic_events = result.events.filter(func(event): return event.get("type","") == "drop_collected")
		_record_economy(candidate,"pickup",{"run_id":next.run_id,"pickups":result.pickups},economic_events,int(_s.cash),old_items)
	if result.returned: candidate.phase = "shopping"
	_s = candidate
	_action_trace.append({"kind":"advance","args":{"delta_ms":delta_ms},"events":result.events.duplicate(true)})
	return _result(true,"ok",result.message,result.events)

func save_to(path: String = SAVE_PATH) -> Dictionary:
	if ProjectSettings.globalize_path(path).simplify_path() == ProjectSettings.globalize_path("user://moonlantern.json").simplify_path():
		return _fail("legacy_save_path","新规则不能覆盖旧原型存档路径")
	for target in [path,path+".bak"]:
		if FileAccess.file_exists(target):
			var existing = JSON.parse_string(FileAccess.get_file_as_string(target))
			if existing is Dictionary and (existing.get("version") != 3 or existing.get("profile_id") != PROFILE_ID):
				return _fail("incompatible_save","原路径含其他版本或规则存档，已保留")
	if path == SAVE_PATH: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_PATH.get_base_dir()))
	return Store.save_state(path,_s,validate_snapshot)

func load_from(path: String = SAVE_PATH) -> Dictionary:
	return super.load_from(path)

func validate_snapshot(data: Variant) -> String:
	if not data is Dictionary: return "存档必须为对象"
	var s: Dictionary = _normalize(data)
	if s.get("version") != 3: return "不支持的存档版本"
	if s.get("profile_id") != PROFILE_ID or s.get("rules_version") != 1: return "不支持的存档规则"
	for key in _s:
		if not s.has(key): return "存档缺少字段："+key
	for key in ["seed","rng_state"]:
		if not s[key] is String or not s[key].is_valid_int() or str(int(s[key])) != s[key]: return "随机状态须为无损整数字符串"
	if not _whole(s.day,1) or s.phase not in ["shopping","preparation","trading","intermission","closing","settled","expedition"]: return "非法日期或阶段"
	if not s.paused is bool or s.clock_ms != 0: return "非法暂停或旧经营时钟"
	for key in ["cash","initial_cash","next_uid","cursor","daily_recovery"]:
		if not _whole(s[key]): return "非法经济整数："+key
	if s.next_uid < 1 or s.daily_recovery > 1: return "非法实例序号或恢复次数"
	for key in ["items","ledger","known","upgrades","active_upgrades","sales","summaries","customers","read"]:
		if not s[key] is Array: return "非法数组："+key
	for key in ["night","service","pending","progression","commits","requests","supply","tiers","quests","expedition","expedition_attempts","expedition_meals","collected_drops"]:
		if not s[key] is Dictionary: return "非法对象："+key
	if not s.expedition.is_empty() and (s.expedition.get("version") != 2 or s.expedition.get("ruleset") != PROFILE_ID or s.expedition.get("map_id") != MAP_ID or s.expedition.get("map_revision") != 1): return "不支持的存档规则"
	var night = s.night; var service = s.service
	if not night.has_all(["id","day","weather","event_id","waves","queues"]) or night.id != "n%d" % s.day or night.day != s.day or not night.queues is Dictionary or night.weather != "rain" or night.event_id != "rain_return" or not night.waves is Array or night.waves.size() != 3: return "非法夜晚规则"
	if not service.has_all(["night_id","wave_id","next_wave_id","wave_index","status","orders","reservations","menu_priority","held_uids","elapsed_ms","remainder_ms"]): return "波次字段缺失"
	if service.night_id != night.id or not _whole(service.wave_index,0,3) or not (service.wave_id == null or service.wave_id is String) or not (service.next_wave_id == null or service.next_wave_id is String): return "波次身份错误"
	for key in ["orders","reservations","menu_priority","held_uids"]:
		if not service[key] is Array: return "非法波次数组"
	if not _whole(service.elapsed_ms) or int(service.elapsed_ms)%STEP_MS != 0 or not _whole(service.remainder_ms,0,49): return "非法固定步经营时钟"
	if s.phase != "trading" and service.remainder_ms != 0: return "停时边界未清余数"
	var wave_index = int(service.wave_index)
	if service.wave_id != (null if wave_index == 0 else night.id+"-w%d" % wave_index): return "当前波ID错误"
	var next_id = night.id+"-w%d" % (wave_index+1) if wave_index < 3 else null
	if service.next_wave_id != next_id: return "下一波ID错误"
	if s.phase in ["shopping","preparation","expedition"] and wave_index != 0: return "开夜前波次已推进"
	if s.phase == "intermission" and wave_index not in [1,2]: return "波间位置错误"
	if s.phase in ["closing","settled"] and wave_index != 3: return "尚未完成三波"
	var expected_status = "active" if s.phase == "trading" else ("intermission" if s.phase == "intermission" else ("complete" if s.phase in ["closing","settled"] else "planned"))
	if service.status != expected_status: return "经营阶段与波次状态不一致"
	var uids = {}; var types = []; var equipped = 0
	for item in s.items:
		if not item is Dictionary or not item.has_all(["uid","item_id","cost","location"]): return "物品实例缺失"
		if not _whole(item.uid,1) or item.uid >= s.next_uid or uids.has(str(item.uid)) or not Catalog.ITEMS.has(item.item_id) or not _whole(item.cost): return "物品实例非法"
		uids[str(item.uid)] = item
		if item.location not in ["bag","shelf","installed","reserved"]: return "非法库存位置"
		if item.location in ["shelf","reserved"]:
			if Catalog.ITEMS[item.item_id].kind != "dish": return "菜单或在途存在原料"
			if item.item_id not in types: types.append(item.item_id)
		if item.location == "installed":
			if item.item_id != "stirring_cauldron": return "非法装配物"
			equipped += 1
		if Catalog.ITEMS[item.item_id].kind == "dish":
			if not item.has_all(["prepared_wave_id","intrinsic_tags","effect_id"]) or not item.prepared_wave_id is String or item.prepared_wave_id.is_empty(): return "菜品缺少制作身份"
			if item.intrinsic_tags != Catalog.ITEMS[item.item_id].tags or item.effect_id != Catalog.ITEMS[item.item_id].effect_id: return "固有料理效果被改写"
			if item.item_id == "moon_stew":
				if item.get("temperature") not in ["hot","held","cooled"]: return "非法炖锅温度"
				var hot_wave = service.wave_id if s.phase == "trading" else service.next_wave_id
				if item.temperature == "hot" and item.prepared_wave_id != hot_wave: return "跨波热菜未处理"
	if s.items.size() > CAPACITY or equipped > 1 or types.size() > (3 if "shelf" in s.active_upgrades else 2): return "库存/菜单/设备超容量"
	var priority_seen = []
	for id in service.menu_priority:
		if not Catalog.ITEMS.has(id) or Catalog.ITEMS[id].kind != "dish" or id in priority_seen: return "非法菜单优先序"
		priority_seen.append(id)
	for id in types:
		if id not in priority_seen: return "菜单优先序遗漏菜种"
	if s.phase != "trading" and types.size() != priority_seen.size(): return "优先序包含未上菜单的菜种"
	if service.held_uids.size() > 3: return "保温锅超过三份"
	var held_seen = []
	for uid in service.held_uids:
		if not _whole(uid,1) or uid in held_seen or not uids.has(str(uid)): return "非法保温实例"
		held_seen.append(uid); var item = uids[str(uid)]
		if item.item_id != "moon_stew" or item.location != "shelf" or item.temperature != "held" or equipped != 1: return "保温与真实装配库存不一致"
	for item in s.items:
		if item.get("temperature") == "held" and item.location != "reserved" and item.uid not in held_seen: return "游离保温实例"
	if s.known != Catalog.RECIPES.keys(): return "已知菜谱被改写"
	for field in ["upgrades","active_upgrades"]:
		var seen = []
		for id in s[field]:
			if not QUALITY_UPGRADES.has(id) or id in seen: return "非法升级"
			if field == "active_upgrades" and id not in s.upgrades: return "未购买升级生效"
			seen.append(id)
	if s.phase != "settled" and s.active_upgrades != s.upgrades: return "升级未按次晨生效"
	var progress = s.progression; var active_kit = "field_kit" in s.active_upgrades
	if not progress.has_all(["owned_weapons","equipped_weapon","skills","pending_unlocks"]): return "成长字段缺失"
	if progress.owned_weapons != (["bolt_wand","fan_wand"] if active_kit else ["bolt_wand"]) or progress.skills != ["gust"] or progress.equipped_weapon not in progress.owned_weapons: return "成长所有权不一致"
	if progress.pending_unlocks != (["fan_wand"] if "field_kit" in s.upgrades and not active_kit else []): return "待生效成长不一致"
	for id in s.supply:
		if id not in ["flour","pumpkin","cream","ember_herb","stirring_cauldron"] or not _whole(s.supply[id],0,14): return "非法供货"
		if id == "stirring_cauldron" and (s.day == 1 or s.supply[id] > 1): return "替代厨具供货非法"
	for id in s.tiers:
		if not Catalog.ITEMS.has(id) or Catalog.ITEMS[id].kind != "dish" or not Catalog.TIERS.has(s.tiers[id]): return "非法定价"
	var order_ids = {}; var processed = 0
	for wave in range(1,4):
		var key = night.id+"-w%d" % wave
		if not night.queues.get(key) is Array or night.queues[key].is_empty() or night.queues[key].size() > 9: return "夜晚队列缺失"
	if service.orders.size() != (0 if wave_index == 0 else night.queues[service.wave_id].size()): return "本波订单数量错误"
	for order in service.orders:
		if not order is Dictionary or not order.has_all(["id","wave_id","required","budget","special","status","arrival_ms","patience_ms","waited_ms","channel","character_id","quest_id","rewards"]): return "订单字段缺失"
		if not order.id is String or order_ids.has(order.id) or not order.required is Array or order.required.is_empty() or not _whole(order.budget,0,100) or not order.special is bool: return "订单非法"
		if order.wave_id not in [night.id+"-w1",night.id+"-w2",night.id+"-w3"]: return "订单波次非法"
		var order_wave = int(String(order.wave_id).get_slice("-w",1))
		if order.status not in ["waiting","reserved","delivered","left"] or not _whole(order.arrival_ms) or not _whole(order.patience_ms,1) or not _whole(order.waited_ms,0,int(order.patience_ms)) or int(order.waited_ms)%STEP_MS != 0: return "订单等待状态非法"
		for tag in order.required:
			if tag not in Catalog.TAGS: return "未知订单效果"
		if order_wave != wave_index: return "本波订单身份错误"
		if order.status in ["delivered","left"]: processed += 1
		if s.commits.has(order.id) != (order.status in ["delivered","left"]): return "订单提交身份不一致"
		order_ids[order.id] = order
	var reserved_uids = []; var reserved_orders = []; var channel_counts = {}; var pot_batch = ""; var pot_time = 0
	for reservation in service.reservations:
		if not reservation is Dictionary or not reservation.has_all(["item_uid","order_id","channel","remaining_ms","batch_id","price","cost"]): return "在途预留字段缺失"
		if not _whole(reservation.item_uid,1) or reservation.item_uid in reserved_uids or reservation.order_id in reserved_orders or not uids.has(str(reservation.item_uid)) or not order_ids.has(reservation.order_id): return "重复或未知预留身份"
		if not DELIVERY_MS.has(reservation.channel) or not _whole(reservation.remaining_ms,1,int(DELIVERY_MS[reservation.channel])) or int(reservation.remaining_ms)%STEP_MS != 0: return "交付通道或时间非法"
		if reservation.channel == "pot":
			if not reservation.batch_id is String or reservation.batch_id.is_empty(): return "锅批次身份缺失"
		elif reservation.batch_id != null: return "普通通道不应有锅批次"
		var item = uids[str(reservation.item_uid)]; var order = order_ids[reservation.order_id]
		if item.location != "reserved" or order.status != "reserved" or order.wave_id != service.wave_id or not _match_instance(s,item,order).is_empty(): return "预留与真实库存/需求不符"
		if reservation.channel != _channel(s,item) or order.channel != reservation.channel or reservation.price != _price(s,item.item_id) or reservation.cost != item.cost: return "预留报价/通道/成本不一致"
		reserved_uids.append(reservation.item_uid); reserved_orders.append(reservation.order_id)
		channel_counts[reservation.channel] = channel_counts.get(reservation.channel,0)+1
		if reservation.channel == "pot":
			if pot_batch != "" and (pot_batch != reservation.batch_id or pot_time != reservation.remaining_ms): return "锅批次未同时出发"
			pot_batch = reservation.batch_id; pot_time = reservation.remaining_ms
	if channel_counts.get("ordinary",0) > 1 or channel_counts.get("floating",0) > 2 or channel_counts.get("pot",0) > 3: return "交付通道超容量"
	for item in s.items:
		if (item.location == "reserved") != (item.uid in reserved_uids): return "预留库存孤立"
	for order in service.orders:
		if (order.status == "reserved") != (order.id in reserved_orders): return "预留订单孤立"
	if s.phase != "trading" and not service.reservations.is_empty(): return "非营业阶段仍有在途单"
	if s.phase in ["intermission","closing","settled"]:
		for order in service.orders:
			if order.wave_id == service.wave_id and order.status not in ["delivered","left"]: return "波次尚未完成"
	for i in range(1,4):
		if s.commits.has("wave:"+night.id+"-w%d" % i) != (i <= wave_index): return "开波提交身份不一致"
	var sale_ids = {}; var revenues = {}; var costs = {}; var night_processed = 0; var wave_processed = 0
	for sale in s.sales:
		if not sale is Dictionary or not sale.has_all(["day","order_id","item_id","revenue","cost","reasons","effect_id","wave_id"]): return "成交记录字段缺失"
		if not _whole(sale.day,1,int(s.day)) or not sale.order_id is String or sale_ids.has(sale.order_id) or not _whole(sale.revenue) or not _whole(sale.cost) or not sale.reasons is Array or sale.reasons.is_empty(): return "成交记录非法"
		if not s.commits.has(sale.order_id): return "成交未提交"
		if sale.revenue > 0:
			if not Catalog.ITEMS.has(sale.item_id) or Catalog.ITEMS[sale.item_id].kind != "dish" or not _whole(sale.get("uid"),1) or sale.effect_id != Catalog.ITEMS[sale.item_id].effect_id: return "成交菜品不一致"
		elif sale.item_id != "" or sale.cost != 0: return "未成交不能扣菜"
		if sale.wave_id != null and sale.wave_id == service.wave_id and (not order_ids.has(sale.order_id) or order_ids[sale.order_id].status != ("delivered" if sale.revenue > 0 else "left")): return "本夜成交与订单不一致"
		if sale.wave_id == null and (sale.day != 2 or sale.order_id != "n2-hagrid-patrol" or sale.get("quest_id") != "hagrid_patrol"): return "人物成交身份错误"
		if sale.day == s.day and sale.wave_id != null: night_processed += 1
		if sale.wave_id != null and sale.wave_id == service.wave_id: wave_processed += 1
		sale_ids[sale.order_id] = sale; revenues[str(sale.day)] = revenues.get(str(sale.day),0)+sale.revenue; costs[str(sale.day)] = costs.get(str(sale.day),0)+sale.cost
	if night_processed != s.cursor or wave_processed != processed: return "处理计数与成交记录不一致"
	if s.quests != {"hagrid_patrol":s.quests.get("hagrid_patrol")} or s.quests.hagrid_patrol not in ["not_offered","pending","completed","declined"]: return "人物委托状态非法"
	if s.quests.hagrid_patrol == "pending":
		if s.day != 2 or s.phase != "trading" or wave_index != 2 or s.pending != _hagrid_order() or sale_ids.has("n2-hagrid-patrol"): return "待处理人物委托不一致"
	elif not s.pending.is_empty(): return "游离人物委托"
	if s.quests.hagrid_patrol in ["completed","declined"]:
		if not sale_ids.has("n2-hagrid-patrol") or (sale_ids["n2-hagrid-patrol"].revenue > 0) != (s.quests.hagrid_patrol == "completed"): return "人物委托结果未对账"
	elif sale_ids.has("n2-hagrid-patrol"): return "人物委托结果缺失"
	if "field_kit" in s.upgrades and _dish_income(s) < 24: return "装备缺少营业收入来源"
	var error = _validate_economy(s,uids,sale_ids)
	if error != "": return error
	if s.summaries.size() != (int(s.day) if s.phase == "settled" else int(s.day)-1): return "日结数量不一致"
	for i in range(s.summaries.size()):
		var summary = s.summaries[i]
		if not summary is Dictionary or not summary.has_all(["day","revenue","sold_cost","gross_profit","fee","cash"]): return "日结字段缺失"
		if summary.day != i+1 or not s.commits.has("settle:%d" % (i+1)) or summary.revenue != revenues.get(str(i+1),0) or summary.sold_cost != costs.get(str(i+1),0) or summary.gross_profit != summary.revenue-summary.sold_cost: return "日结与成交不一致"
	for key in s.requests:
		if not key is String or not s.requests[key] is String: return "非法请求绑定"
	for key in s.commits:
		if not key is String or s.commits[key] != true: return "非法提交记录"
	if s.daily_recovery != (1 if s.commits.has("recover:%d" % int(s.day)) else 0): return "恢复次数不一致"
	for day in s.expedition_attempts:
		if not day is String or not day.is_valid_int() or str(int(day)) != day or int(day) < 1 or int(day) > s.day or s.expedition_attempts[day] != "n%s-expedition" % day: return "每日探险记录错误"
		if not s.expedition_meals.has(s.expedition_attempts[day]): return "餐前效果转移记录缺失"
	if s.expedition_meals.size() != s.expedition_attempts.size(): return "游离餐前效果转移记录"
	if not s.expedition.is_empty():
		if _expedition_model() == null: return "动作模块尚未集成"
		error = _model.validate(s.expedition)
		if error != "": return error
		if s.expedition.day != s.day or s.expedition_attempts.get(str(int(s.day)),"") != s.expedition.run_id: return "动作日期或次数不一致"
		if (s.phase == "expedition") != (s.expedition.status in ["active","cleared"]): return "动作与经营阶段不一致"
		if s.phase == "expedition" and (s.expedition.weapon_id != progress.equipped_weapon or s.expedition.skills != progress.skills): return "动作装备或技能与成长不一致"
		var meal = s.expedition_meals[s.expedition.run_id]
		if (meal == null) != (s.expedition.meal_effect == null): return "动作餐前效果转移不一致"
		if meal != null and (meal.effect_id != s.expedition.meal_effect.effect_id or meal.source_item_uid != s.expedition.meal_effect.source_item_uid): return "动作餐前效果来源被改写"
		for drop in s.expedition.drops:
			if drop.collected != s.collected_drops.has(_drop_key(s.expedition.run_id,drop.id)): return "场上掉落与经济领取记录不一致"
		for node in s.expedition.resource_nodes:
			if node.collected != s.collected_drops.has(_drop_key(s.expedition.run_id,"resource:"+node.id)): return "资源节点与经济领取记录不一致"
	elif s.phase == "expedition" or s.expedition_attempts.has(str(int(s.day))): return "缺少本次动作模拟状态"
	return ""

func _validate_economy(s: Dictionary, uids: Dictionary, sales: Dictionary) -> String:
	var live = {}; var issued = {}; var cash = int(s.initial_cash); var paid = []; var sold = {}; var consumed = {}; var drops = {}
	for i in range(s.ledger.size()):
		var row = s.ledger[i]
		if not row is Dictionary or not row.has_all(["index","kind","day","cash_delta","moves","created","removed","args","events"]): return "经济流水字段缺失"
		if row.index != i or not row.kind is String or not _whole(row.day,1,int(s.day)) or not _whole(row.cash_delta,-1000000) or not row.moves is Dictionary or not row.created is Array or not row.removed is Array or not row.args is Dictionary or not row.events is Array: return "非法经济流水"
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
		match row.kind:
			"inheritance":
				if i != 0 or row.created.size() != 1 or row.created[0].item_id != "stirring_cauldron" or output_cost != 0 or not row.removed.is_empty(): return "遗留厨具来源错误"
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
			for key in ["prepared_wave_id","intrinsic_tags","effect_id"]:
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

func view() -> Dictionary:
	var v = snapshot(); v.finished = false; v.inventory = []; v.prices = {}; v.supply = []; v.recipes = []; v.upgrades = []
	for id in Catalog.ITEMS:
		var definition = Catalog.ITEMS[id]
		var row = {"item_id":id,"name":definition.name,"kind":definition.kind,"effect_id":definition.effect_id,"tags":definition.tags.duplicate(),"uids":[],"bag":0,"shelf":0,"installed":0,"reserved":0}
		for item in _s.items:
			if item.item_id == id: row[item.location] += 1; row.uids.append(item.duplicate(true))
		v.inventory.append(row); v.prices[id] = _price(_s,id)
	for id in _s.supply:
		var available = _s.phase == "shopping" and _s.supply[id] > 0 and _s.cash >= Catalog.ITEMS[id].buy
		v.supply.append({"item_id":id,"name":Catalog.ITEMS[id].name,"quantity":_s.supply[id],"buy":Catalog.ITEMS[id].buy,"available":available,"reason":"" if available else "需采购阶段、余货与足够金币"})
	for id in Catalog.RECIPES:
		var recipe = Catalog.RECIPES[id].duplicate(true); var maximum = 80
		for material in recipe.inputs: maximum = mini(maximum,int(_count(_s,material,"bag")/recipe.inputs[material]))
		var missing = recipe.requires_device != "" and _count(_s,recipe.requires_device,"installed") == 0
		recipe.recipe_id = id; recipe.max_quantity = 0 if missing else maximum; recipe.effect_id = Catalog.ITEMS[id].effect_id
		recipe.available = _s.phase in PHASE_COMMANDS.craft and not missing and maximum > 0
		recipe.reason = "" if recipe.available else ("需装配自搅坩埚" if missing else ("食材不足" if maximum == 0 else "营业中不能备餐"))
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
