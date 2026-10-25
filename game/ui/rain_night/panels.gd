extends VBoxContainer
## Read-only typed-view presentation. No Session, time advance, save or rewards.
signal intent_requested(kind: String, args: Dictionary)
signal world_requested(action_id: String)
signal content_changed

const INK=Color("493527")
const MUTED=Color("84694d")
const ACCENT=Color("996036")
const CHANNELS={"ordinary":{"name":"普通餐盘","capacity":1},"floating":{"name":"浮空餐盘","capacity":2},"pot":{"name":"热锅成组","capacity":3}}
const EFFECTS={"light_step":"轻步 · 首次闪避延长","clear_breath":"清息 · 首次风咒扩围"}
const TAGS={"meal":"料理","quick":"快捷","portable":"外带","hearty":"正餐","warming":"暖身","heat_hold":"保温","trail_light":"照路","celebration":"庆功"}
const RARE={"sparkcap":{"name":"星火菇","value":4,"dish":"星火汤"},"moonheart":{"name":"月心菇","value":8,"dish":"彗星馅饼"}}
const GEAR_NAMES={"bolt_wand":"直线魔杖","fan_wand":"扇射魔杖","gust":"风咒"}
const REASONS={"unprepared":"菜单份数不足","unmatched":"现有菜品效果不匹配","cooled":"炖锅已凉，不能满足暖身需求","congestion":"供餐通道拥堵，等候耗尽","budget":"标价超过预算","matched":"需求与预算匹配","ordinary":"普通餐盘","floating":"浮空餐盘","pot":"热锅成组","hagrid_patrol":"海格巡护带餐"}
var state: Dictionary={}
var page="forecast"
var selected_item=""
var controls: Dictionary={}
var priority_draft: Array=[]
var priority_source: Array=[]
var details_open=false

func present(value: Dictionary, section: String, item_id: String=""):
	state=value.duplicate(true)
	var source=_service().get("menu_priority",[])
	if not source is Array: source=[]
	if section!=page or source!=priority_source:
		priority_source=source.duplicate()
		priority_draft=priority_source.duplicate()
	page=section
	selected_item=item_id
	_rebuild()

func get_action_control(id: String) -> Control:
	return controls.get(id)

func status_line() -> String:
	if not _ready_view(): return "雨夜经营数据尚未提供"
	var night: Dictionary=state.night
	var service=_service()
	var evening="雨夜" if night.weather=="rain" else "晴夜"
	if state.get("phase","")=="intermission": return "%s%d · 波间停时 · 保温%d/3" % [evening,night.day,service.held_uids.size()]
	if service.status=="planned": return "%s%d · 今晚三波需求已记在账本" % [evening,night.day]
	var waiting=0
	for order in service.orders:
		if order.status=="waiting": waiting+=1
	return "%s%d · 第%d波 · 等餐%d · 在途%d" % [evening,night.day,service.wave_index,waiting,service.reservations.size()]

func _service() -> Dictionary:
	var value=state.get("service",{})
	return value if value is Dictionary else {}

func _ready_view() -> bool:
	var service=_service()
	var night=state.get("night")
	return night is Dictionary and night.has_all(["weather","event_id","day"]) and state.has("pending_meal_effect") and service.has_all(["status","wave_index","wave_id","next_wave_id"]) and service.get("orders") is Array and service.get("reservations") is Array and service.get("menu_priority") is Array and service.get("held_uids") is Array

func _allowed(kind: String, phases: Array) -> bool:
	if not _ready_view() or state.get("paused",true) or state.get("phase","") not in phases: return false
	return state.get("available_commands",{}).get(kind,{}).get("enabled",false)

func _request(kind: String, args: Dictionary):
	# The receiver must use the actual Session result; never mutate the view here.
	intent_requested.emit(kind,args.duplicate(true))

func _text(value: String, id: String="", color: Color=INK, font_size: int=18) -> Label:
	if page=="menu":
		if color==INK: color=Color("f3ebcf")
		elif color==MUTED: color=Color("bdc7ad")
		elif color==ACCENT: color=Color("e6d39a")
	var label=Label.new()
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x=220
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_size_override("font_size",font_size)
	add_child(label)
	if not id.is_empty(): controls[id]=label
	return label

func _button(id: String, caption: String, callback: Callable, enabled: bool=true) -> Button:
	var button=Button.new()
	button.name=id.replace(":","_")
	button.set_meta("action_id",id)
	button.text=caption
	button.custom_minimum_size=Vector2(48,48)
	button.focus_mode=Control.FOCUS_ALL
	button.disabled=not enabled
	button.pressed.connect(callback,CONNECT_DEFERRED)
	add_child(button)
	controls[id]=button
	return button

func _rebuild():
	var focused=get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_id=str(focused.get_meta("action_id","")) if focused else ""
	for child in get_children():
		remove_child(child)
		child.queue_free()
	controls.clear()
	add_theme_constant_override("separation",10)
	if not _ready_view():
		_text("雨夜经营数据尚未提供，此页暂不可操作。","rain_interface_pending",MUTED)
		content_changed.emit()
		return
	match page:
		"forecast": _forecast()
		"service": _service_page()
		"menu": _menu()
		"meal": _meal()
		"rare": _rare()
		"growth": _growth()
	content_changed.emit()
	call_deferred("_restore_focus",focus_id)

func _restore_focus(id: String):
	if controls.has(id) and controls[id] is Button and not controls[id].disabled: controls[id].grab_focus()
	elif controls.has("menu_priority_apply") and not controls.menu_priority_apply.disabled: controls.menu_priority_apply.grab_focus()

func _tags(values: Array) -> String:
	var names: Array[String]=[]
	for value in values: names.append(TAGS.get(value,str(value)))
	return " / ".join(names)

func _forecast():
	_text(status_line(),"night_forecast",ACCENT,22)
	var groups={"w1":[],"w2":[],"w3":[]}
	for order in state.get("demand_board",[]):
		if order.get("special",false): continue
		var parts=str(order.get("id","")).split("-")
		if parts.size()==3 and groups.has(parts[1]): groups[parts[1]].append(order)
	for index in range(1,4):
		var orders: Array=groups["w%d"%index]
		if orders.is_empty():
			_text("第%d波 · 预报暂未提供"%index,"wave_summary_%d"%index,MUTED)
			continue
		var needs={}
		var budgets: Array=[]
		for order in orders:
			var tags=_tags(order.get("required",[]))
			needs[tags]=needs.get(tags,0)+1
			budgets.append(int(order.budget))
		var lines: Array[String]=[]
		for tags in needs: lines.append("%s %d位" % [tags,needs[tags]])
		_text("第%d波 · %d位 · 预算%d–%d金\n%s" % [index,orders.size(),budgets.min(),budgets.max(),"；".join(lines)],"wave_summary_%d"%index)
	_text("看需求再选取材路。稀有料理是额外选择，基础供货也能继续经营。","route_choice_note",MUTED)

func _service_page():
	var service=_service()
	_text(status_line(),"service_status",ACCENT,22)
	var lanes: Array[String]=[]
	for channel in CHANNELS:
		var count=0
		var remaining: Array=[]
		for reservation in service.reservations:
			if reservation.channel==channel:
				count+=1
				remaining.append(int(reservation.remaining_ms))
		lanes.append("%s %d/%d%s" % [CHANNELS[channel].name,count,CHANNELS[channel].capacity," · 下一份%.1f秒"%(remaining.min()/1000.0) if not remaining.is_empty() else " · 空闲"])
	_text("\n".join(lanes),"service_channels")
	for reservation in service.reservations:
		_text("料理#%d → %s · %s · 剩%.1f秒（已预留，不可重复使用）" % [reservation.item_uid,reservation.order_id,CHANNELS[reservation.channel].name,reservation.remaining_ms/1000.0],"reservation_%d"%reservation.item_uid,MUTED,16)
	for order in service.orders:
		var detail=""
		match str(order.status):
			"waiting": detail="等候 · 还可等%.1f秒" % (maxi(0,int(order.patience_ms)-int(order.waited_ms))/1000.0)
			"reserved": detail="已预留，在途期间不再消耗耐心"
			"delivered": detail="已送达"
			"left": detail="已离开 · "+_order_reason(str(order.id))
		_text("%s · 预算%d金\n%s · %s" % [order.id,order.budget,_tags(order.required),detail],"service_order_"+str(order.id),INK,16)
	if state.get("phase","")=="intermission":
		_text("真正波间停时。可到灶台补餐、菜单板改量和优先序；继续不会自动开波。","intermission_note",ACCENT)
		var next_id=service.get("next_wave_id")
		var enabled=next_id is String and not next_id.is_empty() and service.reservations.is_empty() and _allowed("start_wave",["intermission"])
		_button("start_wave","备好后，开下一波",_request.bind("start_wave",{"wave_id":next_id}),enabled)

func _order_reason(id: String) -> String:
	for sale in state.get("sales",[]):
		if sale.get("order_id","")==id:
			var reasons: Array[String]=[]
			for reason in sale.get("reasons",[]): reasons.append(REASONS.get(reason,str(reason)))
			if not reasons.is_empty(): return "；".join(reasons)
	return "暂未收到原因"

func _menu():
	var counts={"hot":0,"held":0,"cooled":0}
	for item in state.get("items",[]):
		if item.item_id=="moon_stew" and counts.has(item.get("temperature")): counts[item.temperature]+=1
	var held=_service().held_uids.size()
	_text("炖锅：新热%d份 · 保温%d份 · 已凉%d份\n保温位 %d/3 · 尚余%d位（份数含真实在途库存）" % [counts.hot,counts.held,counts.cooled,held,maxi(0,3-held)],"temperature_summary",ACCENT)
	_text("已凉仍可作正餐；不能匹配暖身需求，重新上菜单或读档不会复热。","temperature_note",MUTED,16)
	var reserved={}
	for reservation in _service().reservations: reserved[int(reservation.item_uid)]=true
	_button("inventory_details_toggle","收起料理身份明细" if details_open else "查看具体料理身份",_toggle_details)
	for item in state.get("items",[]):
		if not selected_item.is_empty() and item.item_id!=selected_item: continue
		if item.get("prepared_wave_id")==null: continue
		var locked=reserved.has(int(item.uid)) or item.location=="reserved"
		if not details_open and not locked: continue
		_text("%s #%d · %s · %s%s" % [_name(item.item_id),item.uid,item.prepared_wave_id,{"hot":"新热","held":"保温","cooled":"已凉"}.get(item.get("temperature"),"本波资格按制作波次")," · 预留中，不可移出/自食/售回" if locked else ""],"dish_uid_%d"%item.uid,MUTED,16)
	_text("供餐优先序（先选到的匹配菜先出餐）","menu_priority_title",ACCENT)
	var enabled=_allowed("set_menu_priority",["preparation","intermission"])
	for index in range(priority_draft.size()):
		var id=str(priority_draft[index])
		var row=HBoxContainer.new()
		add_child(row)
		var caption=_text("%d. %s" % [index+1,_name(id)],"priority_name_"+id)
		caption.custom_minimum_size.x=0
		caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		remove_child(caption);row.add_child(caption)
		var up=_button("priority_up_"+id,"↑",_move_priority.bind(id,-1),enabled and index>0)
		up.tooltip_text="优先供应"+_name(id)
		remove_child(up);row.add_child(up)
		var down=_button("priority_down_"+id,"↓",_move_priority.bind(id,1),enabled and index<priority_draft.size()-1)
		down.tooltip_text="稍后供应"+_name(id)
		remove_child(down);row.add_child(down)
	var draft=priority_draft.duplicate()
	var source=priority_source.duplicate()
	draft.sort(); source.sort()
	_button("menu_priority_apply","应用这份供餐顺序",_request.bind("set_menu_priority",{"item_ids":priority_draft.duplicate()}),enabled and not draft.is_empty() and draft==source and draft.size()==_unique_size(draft))
	if priority_draft!=priority_source: _text("顺序尚未应用。","priority_draft_note",MUTED)

func _toggle_details():
	details_open=not details_open
	_rebuild()

func _unique_size(values: Array) -> int:
	var seen={}
	for value in values: seen[value]=true
	return seen.size()

func _move_priority(id: String, delta: int):
	var index=priority_draft.find(id)
	var destination=index+delta
	if index<0 or destination<0 or destination>=priority_draft.size(): return
	priority_draft.remove_at(index)
	priority_draft.insert(destination,id)
	_rebuild()

func _name(id: String) -> String:
	for item in state.get("inventory",[]):
		if item.item_id==id: return str(item.name)
	return id

func _bag_uids(id: String) -> Array:
	var reserved={}
	for row in _service().get("reservations",[]): reserved[int(row.item_uid)]=true
	var result=[]
	for item in state.get("items",[]):
		if item.item_id==id and item.location=="bag" and not reserved.has(int(item.uid)): result.append(int(item.uid))
	result.sort()
	return result

func _meal():
	var pending=state.get("pending_meal_effect")
	var carried=state.get("expedition",{}).get("meal_effect")
	if pending is Dictionary:
		_text("待下次正式探险：%s · 来源料理#%d" % [EFFECTS.get(pending.effect_id,pending.effect_id),pending.source_item_uid],"meal_state",ACCENT)
	elif carried is Dictionary:
		_text("已携入探险：%s · 来源料理#%d · %s" % [EFFECTS.get(carried.effect_id,carried.effect_id),carried.source_item_uid,"已触发消耗" if carried.used else "未触发，离场不返还"],"meal_state",ACCENT)
	else: _text("餐前效果空槽 · 两种料理只能选一份","meal_state",ACCENT)
	for id in ["floating_pie","star_soup"]:
		var uids=_bag_uids(id)
		var next_source=" · 下一份#%d"%uids[0] if not uids.is_empty() else " · 储藏没有可食用份数"
		_text(_name(id)+next_source,"meal_source_"+id)
		_button("consume_pie" if id=="floating_pie" else "consume_star_soup","自食一份"+_name(id),_request.bind("consume",{"item_id":id,"quantity":1}),pending==null and not uids.is_empty() and _allowed("consume",["shopping"]))
	_text("自食真实消耗一份料理，放弃其售价。效果不会因暂停或读档刷新。","meal_tradeoff",MUTED)

func _rare():
	for id in RARE:
		var data: Dictionary=RARE[id]
		var amount=_bag_uids(id).size()
		_text("%s · 可操作储藏%d份" % [data.name,amount],"rare_stock_"+id,ACCENT)
		_text("售原料得%d金；做%s可出售或自食，也可保留给之后的菜单。原料售回不计菜品收入。" % [data.value,data.dish],"rare_tradeoff_"+id)
		_button("recycle_"+id,"售回1份%s · %d金" % [data.name,data.value],_request.bind("recycle",{"item_id":id,"quantity":1}),amount>0 and _allowed("recycle",["shopping","preparation"]))
		_button("rare_cook_"+id,"回灶台，看看"+str(data.dish),func(): world_requested.emit("world_craft"))
	_button("rare_keep","先保留，合上储藏柜",func(): world_requested.emit("world_storage"))

func _growth():
	_text("累计菜品收入：%d金" % state.get("dish_income",0),"growth_income",ACCENT)
	for upgrade in state.get("upgrades",[]):
		if upgrade.upgrade_id not in ["field_kit","shelf"]: continue
		_text("%s · %d金\n%s" % [upgrade.name,upgrade.cost,upgrade.description],"growth_"+str(upgrade.upgrade_id))
		var remaining=int(state.get("cash",0))-int(upgrade.cost)
		_text("购买后可用%d金"%remaining if remaining>=0 else "还差%d金"%(-remaining),"growth_balance_"+str(upgrade.upgrade_id),MUTED)
		_button("upgrade_"+str(upgrade.upgrade_id),"已购买" if upgrade.owned else "投资明天 · "+str(upgrade.name),_request.bind("upgrade",{"upgrade_id":upgrade.upgrade_id}),not upgrade.owned and upgrade.available and _allowed("upgrade",["settled"]))
		if not upgrade.available and not upgrade.owned: _text(str(upgrade.reason),"growth_reason_"+str(upgrade.upgrade_id),MUTED)
	var progression: Dictionary=state.get("progression",{})
	_text("已拥有：%s\n次晨待生效：%s" % [_gear_names(progression.get("owned_weapons",[])),_gear_names(progression.get("pending_unlocks",[]))],"growth_state",MUTED)
	_button("next_morning","合上账本，进入次晨",_request.bind("next_day",{}),_allowed("next_day",["settled"]))
	_text("次晨到装备处选新杖，再从门口出发试试新路线。","growth_next_step",MUTED)

func _gear_names(values: Array) -> String:
	var names: Array[String]=[]
	for value in values: names.append(GEAR_NAMES.get(value,str(value)))
	return "、".join(names) if not names.is_empty() else "暂无"
