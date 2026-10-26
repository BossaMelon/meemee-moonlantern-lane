extends RefCounted
const Catalog = preload("res://game/core/catalog.gd")
const Walk = preload("res://game/core/world_walk_model.gd")

static func number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func whole(v: Variant, low: int = 0, high: int = 2147483647) -> bool:
	return number(v) and float(v) == floor(float(v)) and v >= low and v <= high

static func fields(v: Variant, template: Dictionary) -> bool:
	if not v is Dictionary: return false
	for key in template:
		if not v.has(key): return false
		var sample = template[key]
		if sample is int:
			if not whole(v[key],-2147483647): return false
		elif sample is float:
			if not number(v[key]): return false
		elif typeof(v[key]) != typeof(sample): return false
	return true

static func uid_refs(ids: Variant, location: String, items: Dictionary, used: Array, max_count: int) -> bool:
	if not ids is Array or ids.size() > max_count: return false
	for uid in ids:
		if not whole(uid,1) or uid in used or not items.has(str(uid)) or items[str(uid)].location != location: return false
		used.append(uid)
	return true

static func validate(data: Dictionary, owner) -> String:
	var s: Dictionary = owner._normalize(data)
	if not fields(s,{"version":0,"profile_id":"","rules_version":0,"day":0,"phase":"","paused":false,"seed":"","rng_state":"","clock_ms":0,"cash":0,"initial_cash":0,"next_uid":0,"cursor":0,"daily_recovery":0,
		"world":{},"night":{},"service":{},"items":[],"ledger":[],"customers":[],"sales":[],"summaries":[],"known":[],"upgrades":[],"active_upgrades":[],"requests":{},"commits":{},"supply":{},"tiers":{},"progression":{},"pending":{},"quests":{},"read":[],"expedition":{},"expedition_attempts":{},"expedition_meals":{},"collected_drops":{}}) or not s.has("pending_meal_effect"): return "世界存档字段或类型缺失"
	if s.version != 4 or s.profile_id != "world-slice-v1" or s.rules_version != 1: return "不支持的存档规则"
	if not whole(s.day,1) or s.phase not in ["preparation","trading","intermission","closing","settled","expedition"] or s.clock_ms != 0 or s.initial_cash != 60 or not whole(s.cash) or not whole(s.next_uid,8) or not whole(s.cursor,0,11) or not whole(s.daily_recovery,0,1): return "世界阶段或经济整数非法"
	for key in ["seed","rng_state"]:
		if not s[key].is_valid_int() or str(int(s[key])) != s[key]: return "随机状态非法"
	for key in s.requests:
		if not key is String or not s.requests[key] is String: return "请求去重状态非法"
	for key in s.commits:
		if not key is String or not s.commits[key] is bool or not s.commits[key]: return "提交状态非法"
	var w = s.world
	if not fields(w,{"version":0,"map_id":"","map_revision":0,"region_id":"","player":{},"input":{},"carried_uids":[],"plan":{},"stations":[],"customers":[],"intro_flags":{},"remainder_ms":0,"tick":0,"travelled_mm":0}) or not w.has("return_pose"): return "世界模型字段缺失"
	if w.version != 1 or w.map_id != "moonlantern-shop-lane" or w.map_revision != 1: return "不支持的存档规则"
	if w.region_id not in ["shop","lane"] or not fields(w.player,{"x":0.0,"y":0.0,"facing":""}) or w.player.facing not in ["nw","ne","sw","se"]: return "玩家位姿非法"
	if not Walk.clear_position(w.region_id,Vector2(w.player.x,w.player.y)): return "玩家存档位置与碰撞冲突"
	if not fields(w.input,{"move_x":0.0,"move_y":0.0}) or absf(w.input.move_x) > 1 or absf(w.input.move_y) > 1: return "移动轴非法"
	if (s.paused or s.phase == "expedition") and (w.input.move_x != 0 or w.input.move_y != 0): return "停时或探索边界未清移动输入"
	if not whole(w.remainder_ms,0,49) or not whole(w.tick) or not whole(w.travelled_mm) or not fields(w.intro_flags,{"moved":false,"took":false,"loaded":false,"cooked":false,"served":false}): return "世界时钟或引导标记非法"
	if w.intro_flags.moved != (w.travelled_mm >= 32000): return "移动引导来源错误"
	if not fields(w.plan,{"recipe_id":"","quantity":0}) or not Catalog.RECIPES.has(w.plan.recipe_id) or not whole(w.plan.quantity,1,6): return "料理计划非法"
	if w.return_pose != null and w.return_pose != Walk.LAYOUT.portals[2]["return"]: return "菇圃返回位姿错误"
	if s.phase == "expedition" and (w.region_id != "lane" or w.return_pose == null or not w.carried_uids.is_empty()): return "探索入口状态错误"
	var night = s.night; var service = s.service
	if not fields(night,{"id":"","day":0,"weather":"","event_id":"","waves":[],"queues":{}}) or night.id != "n%d" % s.day or night.day != s.day or night.weather != "rain" or night.event_id != "rain_return" or night.waves.size() != 3 or night.queues.size() != 3: return "夜晚身份错误"
	if not fields(service,{"night_id":"","wave_index":0,"status":"","orders":[],"reservations":[],"menu_priority":[],"held_uids":[],"elapsed_ms":0,"remainder_ms":0,"tip_paid_by_wave":{}}) or not service.has_all(["wave_id","next_wave_id"]) or service.night_id != night.id or not whole(service.wave_index,0,3): return "服务状态字段缺失"
	var wi = int(service.wave_index); var wave_id = null if wi == 0 else night.id+"-w%d" % wi
	if service.wave_id != wave_id or service.next_wave_id != (night.id+"-w%d" % (wi+1) if wi < 3 else null): return "服务波次身份错误"
	if not whole(service.elapsed_ms) or service.elapsed_ms%50 != 0 or service.remainder_ms != 0: return "服务必须使用唯一世界步时钟"
	if s.phase in ["preparation","expedition"] and wi != 0: return "准备阶段波次已推进"
	if s.phase == "intermission" and wi not in [1,2]: return "波间位置错误"
	if s.phase in ["closing","settled"] and wi != 3: return "未完成三波"
	var status = "active" if s.phase == "trading" else ("intermission" if s.phase == "intermission" else ("complete" if wi == 3 else "planned"))
	if service.status != status: return "波次状态与阶段冲突"
	var queues = []; var queue_ids = {}
	for wave in range(1,4):
		var key = night.id+"-w%d" % wave; var count = 3 if wave == 1 else 4
		if not night.queues.get(key) is Array or night.queues[key].size() != count: return "预生成客流数量错误"
		var summary = night.waves[wave-1]
		if not fields(summary,{"id":"","index":0,"ordinary_count":0,"quick":0,"warm":0,"hearty":0,"budget_min":0,"budget_max":0}) or summary.id != key or summary.index != wave or summary.ordinary_count != count or summary.quick != (3 if wave == 1 else 2) or summary.hearty != (2 if wave == 2 else 0) or summary.warm != (2 if wave == 3 else 0) or not whole(summary.budget_min,0,100) or not whole(summary.budget_max,summary.budget_min,100): return "波次摘要错误"
		for i in range(count):
			var o = night.queues[key][i]
			if not fields(o,{"id":"","wave_id":"","seat_id":"","required":[],"budget":0,"special":false,"text":"","status":"","arrival_ms":0,"patience_ms":0,"waited_ms":0,"character_id":"","quest_id":"","rewards":[],"prefers_hand_delivery":false}) or not o.has("channel"): return "预生成订单字段缺失"
			var required = ["meal","quick"] if wave == 1 or i < 2 else (["meal","hearty"] if wave == 2 else ["meal","warming","heat_hold"])
			if s.day >= 2 and wave == 1 and i == 2: required = ["meal","trail_light"]
			if s.day >= 2 and wave == 3 and i == 3: required = ["meal","celebration"]
			if o.id != key+"-c%02d" % (i+1) or o.wave_id != key or o.seat_id != "seat-%d" % (i+1) or o.required != required or not whole(o.budget,summary.budget_min,summary.budget_max) or o.prefers_hand_delivery != (i == 0): return "订单身份、需求或偏好不一致"
			if o.status != "arriving" or o.channel != null or o.arrival_ms != i*4000 or o.patience_ms != 60000 or o.waited_ms != 0 or o.special or o.character_id != "" or o.quest_id != "" or o.rewards != []: return "预生成订单被改写"
			queues.append(o); queue_ids[o.id] = o
	if s.customers != queues: return "顾客列表与已校验队列不一致"
	var order_ids = {}
	if service.orders.size() != (0 if wi == 0 else night.queues[wave_id].size()): return "当波订单数错误"
	for i in range(service.orders.size()):
		var o = service.orders[i]; var definition = night.queues[wave_id][i]
		if not o is Dictionary or not o.has_all(definition.keys()) or o.size() != definition.size(): return "当前订单字段缺失"
		for key in definition:
			if key not in ["status","channel","waited_ms"] and (typeof(o[key]) != typeof(definition[key]) or o[key] != definition[key]): return "订单与预生成来源不一致"
		if not o.status is String or o.status not in ["arriving","waiting","reserved","delivered","left"] or not whole(o.waited_ms,0,60000) or o.waited_ms%50 != 0 or (o.channel != null and o.channel not in ["manual","ordinary","floating","pot"]): return "订单状态非法"
		if s.commits.has(o.id) != (o.status in ["delivered","left"]): return "订单提交不一致"
		order_ids[o.id] = o
	var items = {}; var installed = 0
	for item in s.items:
		if not fields(item,{"uid":0,"item_id":"","cost":0,"location":""}) or not item.has_all(["prepared_wave_id","temperature"]) or not whole(item.uid,1,s.next_uid-1) or items.has(str(item.uid)) or not Catalog.ITEMS.has(item.item_id) or not whole(item.cost): return "物品字段或UID非法"
		if item.location not in ["bag","carried","station_input","cooking","ready","shelf","reserved","installed"]: return "物品归属非法"
		var kind = Catalog.ITEMS[item.item_id].kind
		if item.location == "installed":
			if item.item_id != "stirring_cauldron": return "装配非锅物品"
			installed += 1
		if item.location in ["cooking","ready","shelf","reserved"] and kind != "dish": return "非料理占据成菜位置"
		if item.location == "station_input" and kind != "ingredient": return "工作台原料归属错误"
		if kind == "dish":
			if not fields(item,{"intrinsic_tags":[],"effect_id":""}) or item.intrinsic_tags != Catalog.ITEMS[item.item_id].tags or item.effect_id != Catalog.ITEMS[item.item_id].effect_id: return "固有效果被改写"
			if item.location == "cooking":
				if item.prepared_wave_id != null or item.temperature != null: return "未完成料理提前取得新鲜身份"
			else:
				if not item.prepared_wave_id is String: return "成菜缺少制作波次"
				var regex = RegEx.new(); regex.compile("^n([1-9][0-9]*)-w([123])$"); var m = regex.search(item.prepared_wave_id)
				if m == null or int(m.get_string(1)) > s.day: return "制作波次非法"
				if item.item_id == "moon_stew":
					if item.temperature not in ["hot","held","cooled"]: return "炖锅温度非法"
					if item.temperature == "hot" and item.prepared_wave_id != (service.wave_id if s.phase == "trading" or service.next_wave_id == null else service.next_wave_id): return "旧波热菜未冷却"
				elif item.temperature != null: return "非炖锅温度非法"
		elif item.prepared_wave_id != null or item.temperature != null: return "非料理带有制作状态"
		items[str(item.uid)] = item
	if s.items.size() > 80 or installed > 1: return "实体容量超限"
	var refs = []
	if not uid_refs(w.carried_uids,"carried",items,refs,12): return "携带UID错误"
	var carry_kind = ""
	for uid in w.carried_uids:
		var kind = Catalog.ITEMS[items[str(uid)].item_id].kind
		if kind not in ["ingredient","dish"] or (carry_kind != "" and kind != carry_kind): return "混装托盘"
		carry_kind = kind
	if w.stations.size() != 1 or not fields(w.stations[0],{"id":"","input_uids":[],"output_uids":[]}) or not w.stations[0].has("job"): return "料理台缺失"
	var station = w.stations[0]
	if station.id != "prep" or not uid_refs(station.input_uids,"station_input",items,refs,24) or not uid_refs(station.output_uids,"ready",items,refs,12): return "台面归属错误"
	if station.job != null:
		var job = station.job
		if not fields(job,{"id":"","recipe_id":"","output_uids":[],"remaining_ms":0}) or not Catalog.RECIPES.has(job.recipe_id) or not whole(job.remaining_ms,1,2000) or job.remaining_ms%50 != 0 or job.output_uids.is_empty() or not uid_refs(job.output_uids,"cooking",items,refs,6) or not station.input_uids.is_empty() or station.output_uids.size()+job.output_uids.size() > 12: return "料理任务非法"
		if job.id != "cook:%d" % job.output_uids[0]: return "料理任务身份错误"
		for uid in job.output_uids:
			if items[str(uid)].item_id != job.recipe_id: return "料理产出配方错误"
	var reserved_orders = []; var channels = {}; var batch = null; var batch_time = 0
	for r in service.reservations:
		if not fields(r,{"item_uid":0,"order_id":"","channel":"","remaining_ms":0,"price":0,"base_price":0,"tip":0,"paid_total":0,"cost":0}) or not r.has("batch_id") or r.channel not in ["manual","ordinary","floating","pot"]: return "配送字段缺失"
		if not uid_refs([r.item_uid],"reserved",items,refs,1) or r.order_id in reserved_orders or not order_ids.has(r.order_id): return "配送重复归属"
		var o = order_ids[r.order_id]; var item = items[str(r.item_uid)]
		if o.status != "reserved" or o.channel != r.channel or owner._match_instance(s,item,o) != "" or r.cost != item.cost: return "配送与实体订单不一致"
		var quote = owner._quote(s,item,o,r.channel)
		if r.base_price != quote.base_price or r.tip != quote.tip or r.paid_total != quote.paid_total or r.price != r.paid_total: return "冻结报价错误"
		var duration = 50 if r.channel == "manual" else owner.DELIVERY_MS[r.channel]
		if not whole(r.remaining_ms,1,duration) or r.remaining_ms%50 != 0: return "配送剩余时间非法"
		if r.channel == "pot":
			if not r.batch_id is String or r.batch_id.is_empty() or (batch != null and (batch != r.batch_id or batch_time != r.remaining_ms)): return "锅批次错误"
			batch = r.batch_id; batch_time = r.remaining_ms
		elif r.batch_id != null: return "非锅渠道批次错误"
		if r.channel != "manual" and owner._channel(s,item) != r.channel: return "自动渠道与料理不一致"
		reserved_orders.append(r.order_id); channels[r.channel] = channels.get(r.channel,0)+1
	if channels.get("ordinary",0) > 1 or channels.get("floating",0) > 2 or channels.get("pot",0) > 3: return "配送渠道超容量"
	for item in s.items:
		if (item.location in ["carried","station_input","cooking","ready","reserved"]) != (item.uid in refs): return "物品引用孤立"
	for o in service.orders:
		if (o.status == "reserved") != (o.id in reserved_orders): return "订单预留孤立"
	if s.phase != "trading" and not service.reservations.is_empty(): return "非营业仍有配送"
	var customer_ids = []
	for c in w.customers:
		if not fields(c,{"id":"","order_id":"","seat_id":"","x":0.0,"y":0.0,"state":"","path_index":0,"reaction_remaining_ms":0,"spawned":false}) or c.id != c.order_id or c.id in customer_ids or not queue_ids.has(c.id) or c.seat_id != queue_ids[c.id].seat_id: return "客人来源错误"
		if c.state not in ["arriving","waiting","reserved","eating","leaving","gone"] or not whole(c.path_index,0,2) or not whole(c.reaction_remaining_ms,0,1000) or c.reaction_remaining_ms%50 != 0: return "客人运动状态非法"
		var seat = Walk.object(c.seat_id).anchor
		if c.x < minf(seat.x,1160)-0.01 or c.x > 1192.01 or c.y < seat.y-0.01 or c.y > 580.01: return "客人离开固定路径范围"
		if c.state in ["waiting","reserved","eating"] and Vector2(c.x,c.y).distance_to(Vector2(seat.x,seat.y)) > 0.01: return "未到座客人进入服务"
		var entrance = Vector2(1192,580); var corridor = Vector2(1160,seat.y); var seat_point = Vector2(seat.x,seat.y); var point = Vector2(c.x,c.y)
		if not c.spawned and (c.state != "arriving" or c.path_index != 0 or point != entrance): return "未入场客人状态错误"
		if c.state in ["arriving","leaving"]:
			if c.path_index > 1: return "客人路径段越界"
			var path = [entrance,corridor,seat_point] if c.state == "arriving" else [seat_point,corridor,entrance]
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,path[c.path_index],path[c.path_index+1])) > 0.01: return "客人偏离固定路径"
		elif c.path_index != 2 or (c.state == "gone" and point != entrance): return "客人终点路径错误"
		if (c.state == "eating") != (c.reaction_remaining_ms > 0): return "客人反应计时错误"
		if order_ids.has(c.id):
			var expected = {"arriving":["arriving"],"waiting":["waiting"],"reserved":["reserved"],"delivered":["eating","leaving","gone"],"left":["leaving","gone"]}[order_ids[c.id].status]
			if c.state not in expected: return "客人与订单状态不一致"
		customer_ids.append(c.id)
	for o in service.orders:
		if o.id not in customer_ids: return "服务客人缺失"
	var held = []
	for uid in service.held_uids:
		if not whole(uid,1) or uid in held or not items.has(str(uid)) or installed != 1 or items[str(uid)].item_id != "moon_stew" or items[str(uid)].location != "shelf" or items[str(uid)].temperature != "held": return "保温归属错误"
		held.append(uid)
	if held.size() > 3: return "保温超容量"
	for item in s.items:
		if item.get("temperature") == "held" and item.location != "reserved" and item.uid not in held: return "保温实例孤立"
	if s.known != Catalog.RECIPES.keys() or not s.pending.is_empty() or s.quests != {"hagrid_patrol":"not_offered"}: return "世界配方或人物状态错误"
	var seen = []
	for id in service.menu_priority:
		if not id is String or not Catalog.RECIPES.has(id) or id in seen: return "菜单非法"
		seen.append(id)
	if seen.is_empty() or seen.size() > (3 if "shelf" in s.active_upgrades else 2): return "菜单容量错误"
	for id in s.tiers:
		if not Catalog.RECIPES.has(id) or not s.tiers[id] is String or not Catalog.TIERS.has(s.tiers[id]): return "定价非法"
	for id in s.supply:
		if id not in ["flour","pumpkin","cream","ember_herb","stirring_cauldron"] or not whole(s.supply[id],0,14) or (id == "stirring_cauldron" and (s.day == 1 or s.supply[id] > 1)): return "供货非法"
	for key in ["upgrades","active_upgrades"]:
		seen = []
		for id in s[key]:
			if id not in ["shelf","field_kit"] or id in seen: return "成长所有权非法"
			seen.append(id)
	if not fields(s.progression,{"owned_weapons":[],"equipped_weapon":"","skills":[],"pending_unlocks":[]}): return "成长字段缺失"
	var active = "field_kit" in s.active_upgrades
	if s.progression.owned_weapons != (["bolt_wand","fan_wand"] if active else ["bolt_wand"]) or s.progression.equipped_weapon not in s.progression.owned_weapons or s.progression.skills != ["gust"] or s.progression.pending_unlocks != (["fan_wand"] if "field_kit" in s.upgrades and not active else []): return "成长状态不一致"
	if s.phase != "settled" and s.upgrades != s.active_upgrades: return "成长未在次晨生效"
	for id in s.active_upgrades:
		if id not in s.upgrades: return "未购买成长生效"
	var sale_ids = {}; var tipped = {}; var current_processed = 0; var revenues = {}; var costs = {}
	for sale in s.sales:
		if not fields(sale,{"day":0,"order_id":"","item_id":"","revenue":0,"cost":0,"reasons":[],"effect_id":"","wave_id":"","base_price":0,"tip":0,"paid_total":0}) or not sale.has("channel") or not whole(sale.day,1,s.day) or sale_ids.has(sale.order_id) or not s.commits.has(sale.order_id) or sale.paid_total != sale.base_price+sale.tip or sale.revenue != sale.paid_total or sale.tip not in [0,2]: return "成交身份或金额错误"
		if sale.revenue > 0:
			if not Catalog.RECIPES.has(sale.item_id) or not whole(sale.get("uid"),1) or sale.effect_id != Catalog.ITEMS[sale.item_id].effect_id or sale.channel not in ["manual","ordinary","floating","pot"]: return "成交料理错误"
			var prices = []
			for tier in Catalog.TIERS: prices.append(Catalog.price(sale.item_id,tier,25 if owner._rain_dish(sale.item_id) else 0))
			if sale.base_price not in prices: return "基础报价错误"
			if sale.tip > 0:
				if sale.channel != "manual" or sale.order_id != sale.wave_id+"-c01" or tipped.has(sale.wave_id): return "重复或非法亲送小费"
				tipped[sale.wave_id] = sale.order_id
		elif sale.item_id != "" or sale.cost != 0 or sale.base_price != 0 or sale.tip != 0 or sale.channel != null: return "未成交不能付钱或消耗料理"
		if sale.day == s.day:
			if not queue_ids.has(sale.order_id) or sale.revenue > queue_ids[sale.order_id].budget: return "成交超过真实需求或预算"
			current_processed += 1
		sale_ids[sale.order_id] = sale
		revenues[str(sale.day)] = revenues.get(str(sale.day),0)+sale.revenue; costs[str(sale.day)] = costs.get(str(sale.day),0)+sale.cost
	var current_tips = {}
	for wave in tipped:
		if wave.begins_with(night.id+"-"): current_tips[wave] = tipped[wave]
	if service.tip_paid_by_wave != current_tips or current_processed != s.cursor: return "小费标记或处理数量不一致"
	for o in service.orders:
		if o.status in ["delivered","left"] and (not sale_ids.has(o.id) or (sale_ids[o.id].revenue > 0) != (o.status == "delivered")): return "订单终态未对账"
	if s.phase in ["intermission","closing","settled"] and service.orders.any(func(o): return o.status not in ["delivered","left"]): return "服务尚未完成"
	for wave in range(1,4):
		if s.commits.has("wave:"+night.id+"-w%d" % wave) != (wave <= wi): return "开波提交身份不一致"
	if "field_kit" in s.upgrades and owner._dish_income(s) < 24: return "成长缺少实际营业来源"
	var economic_error = owner._validate_economy(s,items,sale_ids)
	if economic_error != "": return economic_error
	var settled = {}; var recovered = {}; var running_cash = 60
	for row in s.ledger:
		running_cash += row.cash_delta
		if row.kind == "settle":
			if settled.has(str(row.day)): return "重复日结流水"
			settled[str(row.day)] = {"cash":running_cash,"fee":-row.cash_delta}
		if row.kind == "recover":
			if recovered.has(str(row.day)): return "重复每日恢复流水"
			recovered[str(row.day)] = true
	if s.summaries.size() != (int(s.day) if s.phase == "settled" else int(s.day)-1) or s.summaries.size() != settled.size(): return "日结数量不一致"
	for i in range(s.summaries.size()):
		var summary = s.summaries[i]; var day = str(i+1)
		if not fields(summary,{"day":0,"revenue":0,"sold_cost":0,"gross_profit":0,"fee":0,"cash":0}) or not settled.has(day): return "日结字段或流水缺失"
		if summary.day != i+1 or summary.revenue != revenues.get(day,0) or summary.sold_cost != costs.get(day,0) or summary.gross_profit != summary.revenue-summary.sold_cost or summary.fee != settled[day].fee or summary.cash != settled[day].cash: return "日结与成交或现金不一致"
		if not s.commits.has("settle:"+day) or s.commits.has("next:"+day) != (i+1 < s.day): return "日结或次晨提交不一致"
	for key in s.commits:
		if key.begins_with("recover:") and not recovered.has(key.trim_prefix("recover:")): return "游离恢复提交"
		if key.begins_with("settle:") and not settled.has(key.trim_prefix("settle:")): return "游离日结提交"
	for day in recovered:
		if not s.commits.has("recover:"+day): return "恢复流水未提交"
	if s.daily_recovery != (1 if recovered.has(str(s.day)) else 0): return "恢复次数不一致"
	for day in s.expedition_attempts:
		if not day is String or not day.is_valid_int() or str(int(day)) != day or int(day) < 1 or int(day) > s.day or s.expedition_attempts[day] != "n%s-expedition" % day: return "每日探险记录错误"
		if not s.expedition_meals.has(s.expedition_attempts[day]): return "餐前效果转移记录缺失"
	if s.expedition_meals.size() != s.expedition_attempts.size(): return "游离餐前效果记录"
	if not s.expedition.is_empty():
		if s.expedition.get("version") != 2 or s.expedition.get("ruleset") != "rain-night-v1" or s.expedition.get("map_id") != "rain-garden-two-routes" or s.expedition.get("map_revision") != 1: return "不支持的存档规则"
		var model = owner._expedition_model()
		if model == null or model.validate(s.expedition) != "": return "探索模型存档非法"
		if (s.expedition.status in ["active","cleared"]) != (s.phase == "expedition"): return "探索阶段不一致"
		if s.expedition.day != s.day or s.expedition_attempts.get(str(int(s.day)),"") != s.expedition.run_id: return "探索日期或次数不一致"
		if s.phase == "expedition" and (s.expedition.weapon_id != s.progression.equipped_weapon or s.expedition.skills != s.progression.skills): return "探索与成长不一致"
		var meal = s.expedition_meals[s.expedition.run_id]
		if (meal == null) != (s.expedition.meal_effect == null): return "探索餐前效果转移不一致"
		if meal != null and (meal.effect_id != s.expedition.meal_effect.effect_id or meal.source_item_uid != s.expedition.meal_effect.source_item_uid): return "探索餐前效果来源被改写"
		for drop in s.expedition.drops:
			if drop.collected != s.collected_drops.has(owner._drop_key(s.expedition.run_id,drop.id)): return "场上掉落与领取记录不一致"
		for node in s.expedition.resource_nodes:
			if node.collected != s.collected_drops.has(owner._drop_key(s.expedition.run_id,"resource:"+node.id)): return "资源节点与领取记录不一致"
	elif s.phase == "expedition" or s.expedition_attempts.has(str(int(s.day))): return "探索模型缺失"
	return ""
