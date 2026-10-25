extends Control
## Presentation only: all economic state and phase changes belong to GameSession.
const Session = preload("res://game/core/game_session.gd")
const ShopCanvas = preload("res://game/ui/shop_canvas.gd")
const CREAM = Color("fff0d1")
const MUTED = Color("c1beca")
const GOLD = Color("efbd76")
const DARK = Color("252c47")
const PANEL = Color("343953")
const PHASES = {"shopping":"淘货", "preparation":"整备", "trading":"营业", "closing":"收工", "settled":"日结"}
const EFFECTS = {"writing":"书写", "home":"家居", "light":"照明", "waterproof":"防水", "material":"材料", "device":"装配奇物"}
const TIER_NAMES = {"friendly":"亲民 90%", "standard":"标准 100%", "premium":"精品 115%"}
var game = Session.new(20261025)
var view: Dictionary = {}
var tab = "shopping"
var batch = 1
var selected_item = "pen"
var request_serial = 0
var request_prefix = str(Time.get_unix_time_from_system()) + ":" + str(Time.get_ticks_usec())
var messages: Array[String] = []
var action_controls: Dictionary = {}
var ordered_controls: Array[Button] = []
var root_box: VBoxContainer
var header: HBoxContainer
var status: Label
var phase_hint: Label
var content: BoxContainer
var shop_column: VBoxContainer
var illustration: Control
var shop_caption: Label
var forecast: Label
var notebook: VBoxContainer
var tabs: HBoxContainer
var scroll: ScrollContainer
var body: VBoxContainer
var feedback: Label
var primary: Button
var pause_button: Button
var narrow = false
var built = false
var rebuild_queued = false
var quit_after_save = false

func _ready():
	get_tree().auto_accept_quit = false
	_build_theme()
	_configure_input()
	_build_shell()
	built = true
	resized.connect(_resize_layout)
	_resize_layout()
	var saved = FileAccess.file_exists("user://moonlantern.json")
	if saved:
		_notice("发现本地存档。点击「恢复」继续上次经营；当前新开预览尚未覆盖存档。")
	else:
		_notice("欢迎回家，咩咩。先看今日需求，再淘些材料；普通顾客会自动结账。")
	_refresh()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save(true)

func _configure_input():
	if not InputMap.has_action("shop_pause"):
		InputMap.add_action("shop_pause")
		var key = InputEventKey.new()
		key.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("shop_pause",key)
		var pad = InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_START
		InputMap.action_add_event("shop_pause",pad)

func _unhandled_input(event):
	if event.is_action_pressed("shop_pause") or event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _process(delta):
	if not built or view.is_empty(): return
	if view.phase == "trading" and not view.paused and view.pending.is_empty():
		var result = game.advance(clampi(roundi(delta*1000),0,60000))
		if not result.get("events",[]).is_empty():
			_record_events(result.events)
			_refresh()
		elif game.view().phase != view.phase:
			_refresh()

func _build_theme():
	var ui_theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC","Microsoft YaHei","Noto Sans CJK SC","Heiti SC"])
	ui_theme.default_font = font
	ui_theme.default_font_size = 19
	ui_theme.set_color("font_color","Label",CREAM)
	ui_theme.set_color("font_color","Button",CREAM)
	ui_theme.set_color("font_hover_color","Button",Color.WHITE)
	ui_theme.set_color("font_focus_color","Button",Color.WHITE)
	ui_theme.set_color("font_disabled_color","Button",Color("85899c"))
	ui_theme.set_stylebox("normal","Button",_style(Color("48506a"),Color("626881")))
	ui_theme.set_stylebox("hover","Button",_style(Color("5a627b"),GOLD))
	ui_theme.set_stylebox("pressed","Button",_style(Color("756246"),GOLD))
	ui_theme.set_stylebox("disabled","Button",_style(Color("30364f"),Color("42485e")))
	var focus_style = _style(Color(0,0,0,0),GOLD,4)
	ui_theme.set_stylebox("focus","Button",focus_style)
	ui_theme.set_constant("separation","VBoxContainer",10)
	ui_theme.set_constant("separation","HBoxContainer",10)
	theme = ui_theme

func _style(color: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(11)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _build_shell():
	var background = ColorRect.new()
	background.color = DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	add_child(margin)
	root_box = VBoxContainer.new()
	margin.add_child(root_box)
	header = HBoxContainer.new()
	root_box.add_child(header)
	var title = _label("咩咩与月灯巷",26,GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	pause_button = _button("pause","歇一歇",_toggle_pause)
	header.add_child(pause_button)
	header.add_child(_button("save","保存",func(): _save(false)))
	header.add_child(_button("load","恢复",_load_game))
	header.add_child(_button("quit","保存退出",func(): _save(true)))
	status = _label("",21)
	root_box.add_child(status)
	content = BoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(content)
	shop_column = VBoxContainer.new()
	shop_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_column.size_flags_stretch_ratio = 0.95
	content.add_child(shop_column)
	var art_panel = PanelContainer.new()
	art_panel.add_theme_stylebox_override("panel",_style(Color("41435c"),Color("676076")))
	art_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_column.add_child(art_panel)
	illustration = ShopCanvas.new()
	illustration.font = theme.default_font
	art_panel.add_child(illustration)
	shop_caption = _label("",18,MUTED)
	shop_column.add_child(shop_caption)
	forecast = _label("",18,GOLD)
	shop_column.add_child(forecast)
	notebook = VBoxContainer.new()
	notebook.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notebook.size_flags_stretch_ratio = 1.12
	content.add_child(notebook)
	tabs = HBoxContainer.new()
	notebook.add_child(tabs)
	for entry in [["shopping","淘货"],["craft","工坊"],["shelf","货架"],["journal","手账"]]:
		var tab_id = entry[0]
		var button = _button("tab_"+tab_id,entry[1],_select_tab.bind(tab_id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(button)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	notebook.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	phase_hint = _label("",18,MUTED)
	notebook.add_child(phase_hint)
	primary = _button("primary","",_primary_action)
	primary.custom_minimum_size.y = 54
	notebook.add_child(primary)
	feedback = _label("",18)
	feedback.custom_minimum_size.y = 52
	root_box.add_child(feedback)

func _resize_layout():
	if not built: return
	var should_narrow = size.x < 1050
	if narrow != should_narrow or not content.has_meta("sized"):
		narrow = should_narrow
		content.vertical = narrow
		illustration.custom_minimum_size.y = 170 if narrow else 280
		shop_column.size_flags_vertical = Control.SIZE_FILL if narrow else Control.SIZE_EXPAND_FILL
		shop_column.custom_minimum_size.y = 205 if narrow else 0
		forecast.visible = not narrow
		shop_caption.visible = not narrow
		header.add_theme_constant_override("separation",6 if narrow else 10)
		content.set_meta("sized",true)

func _label(value: String, font_size: int = 19, color: Color = CREAM) -> Label:
	var label = Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(key: String, value: String, callback: Callable, enabled: bool = true) -> Button:
	var button = Button.new()
	button.name = key.replace(":","_")
	button.set_meta("action_id",key)
	button.text = value
	button.custom_minimum_size = Vector2(48,48)
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = not enabled
	button.pressed.connect(callback)
	button.focus_entered.connect(_focus_visible.bind(button))
	action_controls[key] = button
	return button

func get_action_control(action_id: String) -> Control:
	# Read-only coordinate/focus discovery for runtime input verification.
	return action_controls.get(action_id)

func _focus_visible(button: Button):
	if is_instance_valid(button) and is_instance_valid(scroll) and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)

func _select_tab(value: String):
	tab = value
	_refresh()

func _refresh():
	var focus = get_viewport().gui_get_focus_owner()
	var focus_id = str(focus.get_meta("action_id","")) if focus else ""
	var old_scroll = scroll.scroll_vertical
	for child in body.get_children():
		body.remove_child(child)
		child.free()
	# Existing shell buttons survive; obsolete body references are discarded.
	for key in action_controls.keys():
		if not is_instance_valid(action_controls[key]): action_controls.erase(key)
	view = game.view()
	status.text = "第 %d / 3 日  ·  %s  ·  金币 %d  ·  剩余顾客 %d%s" % [view.day,PHASES[view.phase],view.cash,view.customers_remaining,"  ·  已暂停" if view.paused else ""]
	pause_button.text = "继续" if view.paused else "歇一歇"
	illustration.set_state(view)
	shop_caption.text = "普通客人自动浏览、付款；特殊客人会等咩咩选好。"
	forecast.text = "巷口天气笺  ·  " + view.forecast.text
	for key in ["shopping","craft","shelf","journal"]:
		var button: Button = action_controls["tab_"+key]
		button.modulate = GOLD if tab == key else Color.WHITE
	if not view.pending.is_empty():
		_build_special()
	elif view.phase == "settled":
		_build_summary()
	elif tab == "shopping":
		_build_shopping()
	elif tab == "craft":
		_build_craft()
	elif tab == "shelf":
		_build_shelf()
	else:
		_build_journal()
	var hints = {"shopping":"先看手账需求。基础材料稳定供货，已知配方可直接批量制作。", "preparation":"上架才可出售；装配的避雨铃会留用，不能同时出售。", "trading":"普通营业自动进行。特殊咨询与暂停期间，经营时钟冻结。", "closing":"客流结束了。日结只会扣一次费用，不会重复结算。", "settled":"三日经营已完成。可以保存这段旅程并安心退出。" if view.finished else "升级会拓展明日选择；也可以保留金币直接休息。"}
	phase_hint.text = "已暂停，可保存后继续。" if view.paused else hints[view.phase]
	primary.text = {"shopping":"淘货完成，回店整备 →", "preparation":"开门营业 →", "trading":"等待特殊咨询" if not view.pending.is_empty() else "营业中 · 普通客自动结账", "closing":"收好招牌，查看日结 →", "settled":"保存三日回忆" if view.finished else "休息，迎接第 %d 日 →" % (int(view.day)+1)}[view.phase]
	primary.disabled = view.phase == "trading"
	feedback.text = messages.back() if not messages.is_empty() else ""
	_wire_focus()
	call_deferred("_restore_focus",focus_id,old_scroll)

func _restore_focus(focus_id: String, old_scroll: int):
	if action_controls.has(focus_id) and not action_controls[focus_id].disabled:
		action_controls[focus_id].grab_focus()
	else:
		var fallback = "special_decline" if not view.pending.is_empty() else "primary"
		if action_controls.has(fallback) and not action_controls[fallback].disabled:
			action_controls[fallback].grab_focus()
		elif not ordered_controls.is_empty(): ordered_controls[0].grab_focus()
	scroll.scroll_vertical = old_scroll

func _wire_focus():
	ordered_controls.clear()
	_collect_buttons(self)
	for index in range(ordered_controls.size()):
		var current = ordered_controls[index]
		var previous = ordered_controls[(index-1+ordered_controls.size())%ordered_controls.size()]
		var next = ordered_controls[(index+1)%ordered_controls.size()]
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_left = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_neighbor_right = current.get_path_to(next)

func _collect_buttons(node: Node):
	for child in node.get_children():
		if child is Button and child.is_visible_in_tree() and not child.disabled:
			ordered_controls.append(child)
		_collect_buttons(child)

func _card() -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(PANEL,Color("555b75")))
	body.add_child(panel)
	var box = VBoxContainer.new()
	panel.add_child(box)
	return box

func _batch_selector():
	var row = HBoxContainer.new()
	body.add_child(row)
	var batch_label = _label("本次数量",18,MUTED)
	batch_label.custom_minimum_size.x = 90
	row.add_child(batch_label)
	row.add_child(_button("batch_less","−",_change_batch.bind(-1),batch>1))
	var value = _label(str(batch),23,GOLD)
	value.custom_minimum_size.x = 30
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	row.add_child(_button("batch_more","＋",_change_batch.bind(1),batch<80))
	for n in [1,3,5]: row.add_child(_button("batch_%d"%n,str(n),_set_batch.bind(n)))

func _change_batch(amount: int):
	batch = clampi(batch+amount,1,80)
	_refresh()

func _set_batch(amount: int):
	batch = amount
	_refresh()

func _build_shopping():
	body.add_child(_label("巷口旧货摊",25,GOLD))
	body.add_child(_label("材料会留在背包里；先算好要做的笔、灯或防潮护符。",18,MUTED))
	_batch_selector()
	for supply in view.supply:
		var card = _card()
		var row = HBoxContainer.new()
		card.add_child(row)
		var label = _label("%s  ·  %d 金 / 件\n今余 %d  ·  背包 %d" % [supply.name,supply.buy,supply.quantity,_inventory(supply.item_id).bag])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_button("buy_"+supply.item_id,"买 %d · %d 金" % [batch,batch*int(supply.buy)],_act.bind("buy",{"item_id":supply.item_id,"quantity":batch}),view.phase=="shopping" and supply.available))
		if not supply.available: card.add_child(_label(supply.reason,17,MUTED))
	var recover_enabled = view.available_commands.recover.enabled
	body.add_child(_button("recover","帮邻居回收旧纸 · +12 金（每日一次）",_act.bind("recover",{}),recover_enabled))
	body.add_child(_label(view.available_commands.recover.reason,17,MUTED))

func _build_craft():
	body.add_child(_label("灯下小工坊",25,GOLD))
	body.add_child(_label("已知配方从一开始就支持批量。先淘货，再回来整备。",18,MUTED))
	_batch_selector()
	for recipe in view.recipes:
		var card = _card()
		var materials: Array[String] = []
		for id in recipe.inputs:
			materials.append("%s ×%d（有%d）" % [_inventory(id).name,recipe.inputs[id],_inventory(id).bag])
		card.add_child(_label(recipe.name+"  ←  "+" + ".join(materials),21))
		card.add_child(_label("现在最多可做 %d 件。%s" % [recipe.max_quantity,recipe.reason],17,MUTED))
		card.add_child(_button("craft_"+recipe.recipe_id,"批量制作 %d 件" % batch,_act.bind("craft",{"recipe_id":recipe.recipe_id,"quantity":batch}),view.phase=="preparation" and recipe.available))
	body.add_child(_button("to_shelf","去货架安排陈列 →",_select_tab.bind("shelf")))

func _build_shelf():
	body.add_child(_label("货架与留用奇物",25,GOLD))
	var types = 0
	for item in view.inventory:
		if item.shelf>0: types += 1
	var capacity = 2
	for upgrade in view.upgrades:
		if upgrade.upgrade_id == "shelf" and upgrade.owned: capacity = 3
	body.add_child(_label("陈列 %d / %d 种  ·  装配槽独立于陈列槽" % [types,capacity],18,MUTED))
	_batch_selector()
	var selection = HBoxContainer.new()
	body.add_child(selection)
	for id in ["pen","lamp","charm","bell"]:
		var item = _inventory(id)
		var button = _button("select_"+id,item.name+"\n包%d 架%d" % [item.bag,item.shelf],_select_item.bind(id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.modulate = GOLD if selected_item==id else Color.WHITE
		selection.add_child(button)
	var current = _inventory(selected_item)
	var card = _card()
	card.add_child(_label(current.name+"  ·  "+_effects(current.tags),22,GOLD))
	var price = int(view.prices[selected_item])
	var total_cost = 0
	var quantity = 0
	for instance in current.uids:
		if instance.location != "installed":
			total_cost += int(instance.cost)
			quantity += 1
	var cost_text = "无可售库存" if quantity==0 else "平均成本 %.1f · 预计单件毛利 %.1f" % [float(total_cost)/quantity,price-float(total_cost)/quantity]
	card.add_child(_label("现价 %d 金  ·  %s\n背包 %d / 货架 %d / 装配 %d" % [price,cost_text,current.bag,current.shelf,current.installed],18))
	var moves = HBoxContainer.new()
	card.add_child(moves)
	moves.add_child(_button("display_"+selected_item,"上架 %d"%batch,_act.bind("display",{"item_id":selected_item,"quantity":batch}),view.phase=="preparation"))
	moves.add_child(_button("undisplay_"+selected_item,"撤架 %d"%batch,_act.bind("undisplay",{"item_id":selected_item,"quantity":batch}),view.phase=="preparation"))
	moves.add_child(_button("recycle_"+selected_item,"回收 %d"%batch,_act.bind("recycle",{"item_id":selected_item,"quantity":batch}),view.phase in ["shopping","preparation"]))
	card.add_child(_label("标价先匹配用途，再检查预算；精品档可能超过顾客预算。",17,MUTED))
	var pricing = HBoxContainer.new()
	card.add_child(pricing)
	for tier in ["friendly","standard","premium"]:
		var button = _button("price_"+tier,TIER_NAMES[tier],_act.bind("price",{"item_id":selected_item,"tier":tier}),view.phase=="preparation")
		button.modulate = GOLD if view.tiers.get(selected_item,"standard")==tier else Color.WHITE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pricing.add_child(button)
	var bell = _inventory("bell")
	card.add_child(_label("避雨铃：留用后，所有自写笔与暖月灯获得防水；也可上架换成金币。",18,GOLD))
	for instance in bell.uids:
		if instance.location=="bag":
			card.add_child(_button("install_bell","留用：安装避雨铃",_act.bind("install",{"uid":instance.uid}),view.phase=="preparation"))
		elif instance.location=="installed":
			card.add_child(_button("uninstall_bell","卸下避雨铃，移回背包",_act.bind("uninstall",{"uid":instance.uid}),view.phase=="preparation"))
	var stock: Array[String] = []
	for item in view.inventory:
		if item.bag+item.shelf+item.installed>0:
			stock.append("%s：包%d / 架%d / 留用%d" % [item.name,item.bag,item.shelf,item.installed])
	body.add_child(_label("全部库存\n"+"\n".join(stock),18,MUTED))

func _select_item(id: String):
	selected_item = id
	_refresh()

func _build_special():
	var pending = view.pending
	body.add_child(_label("特别咨询 · 这里可以慢慢想",25,GOLD))
	body.add_child(_label(pending.text,23))
	body.add_child(_label("需要「%s」 · 预算 %d 金\n选择期间普通营业与经营时钟暂停。" % [_effects(pending.required),pending.budget],19,MUTED))
	for option in pending.options:
		if option.available or _inventory(option.item_id).shelf>0:
			var card = _card()
			card.add_child(_button("fulfill_"+option.item_id,"推荐%s · %d 金" % [option.name,option.price],_act.bind("fulfill",{"order_id":pending.id,"item_id":option.item_id}),option.available))
			card.add_child(_label("匹配用途、效果和预算，可以成交。" if option.available else option.reason,18,MUTED))
	body.add_child(_button("special_decline","这次没有合适的，送客并继续营业",_act.bind("decline",{"order_id":pending.id})))

func _build_journal():
	body.add_child(_label("咩咩的经营手账",25,GOLD))
	body.add_child(_label("天气与备货\n"+view.forecast.text,19,GOLD))
	body.add_child(_label("今日需求已提前列出；顾客按用途与预算购买。",18,MUTED))
	for order in view.demand_board:
		body.add_child(_label("%s%s  ·  %s  ·  预算 %d" % ["✓ " if order.processed else "○ ","特别咨询" if order.special else "普通客人",_effects(order.required),order.budget],18))
	body.add_child(_label("最近发生",21,GOLD))
	for index in range(maxi(0,messages.size()-12),messages.size()):
		body.add_child(_label(messages[index],18,MUTED))

func _build_summary():
	body.add_child(_label("三日回忆已收好" if view.finished else "今夜收工，辛苦啦",26,GOLD))
	var summary = view.summary
	body.add_child(_label("第 %d 日账单\n销售收入 %d  −  已售成本 %d  =  毛利 %d\n店铺费用 %d  ·  结末金币 %d" % [summary.day,summary.revenue,summary.sold_cost,summary.gross_profit,summary.fee,summary.cash],21))
	body.add_child(_label("毛利和现金不同：采购与升级付的钱、留在库存中的材料都另有去处。",18,MUTED))
	if view.finished:
		body.add_child(_label("这只是小店的前三夜。没有强制继续，也不用等待。保存后可随时回来查看。",21,GOLD))
	else:
		body.add_child(_label("把收益变成明日的新选择",22,GOLD))
		for upgrade in view.upgrades:
			var card = _card()
			card.add_child(_label(upgrade.description,18,MUTED))
			card.add_child(_button("upgrade_"+upgrade.upgrade_id,"%s%s · %d 金" % ["已拥有 · " if upgrade.owned else "",upgrade.name,upgrade.cost],_act.bind("upgrade",{"upgrade_id":upgrade.upgrade_id}),upgrade.available))
	body.add_child(_label("今日每一笔成交与未成交",21,GOLD))
	for sale in view.sales:
		if sale.day == view.day:
			body.add_child(_label(_event_text(sale),18,MUTED))

func _inventory(id: String) -> Dictionary:
	for item in view.inventory:
		if item.item_id == id: return item
	return {}

func _effects(tags: Array) -> String:
	var names: Array[String] = []
	for tag in tags: names.append(EFFECTS.get(tag,str(tag)))
	return " / ".join(names)

func _primary_action():
	match view.phase:
		"shopping":
			tab = "craft"
			_act("finish_shopping",{})
		"preparation":
			tab = "journal"
			_act("open_shop",{})
		"closing": _act("settle",{})
		"settled":
			if view.finished: _save(false)
			else:
				tab = "shopping"
				_act("next_day",{})

func _act(kind: String, args: Dictionary):
	request_serial += 1
	var result = game.command(kind,args,request_prefix+":"+str(request_serial))
	_notice(("✓ " if result.ok else "无法完成：")+str(result.message))
	_record_events(result.get("events",[]))
	_refresh()

func _toggle_pause():
	var result = game.set_paused(not game.view().paused)
	_notice("已暂停，小店会等你。" if game.view().paused else "继续经营。")
	if not result.ok: _notice(result.message)
	_refresh()

func _save(exit_when_saved: bool):
	var result = game.save_to()
	_notice(("保存成功：" if result.ok else "保存失败：")+str(result.message))
	_refresh()
	if result.ok and exit_when_saved: get_tree().quit()

func _load_game():
	var result = game.load_from()
	_notice(("恢复成功：" if result.ok else "恢复失败，当前经营未改变：")+str(result.message))
	if result.ok:
		request_prefix = str(Time.get_unix_time_from_system())+":"+str(Time.get_ticks_usec())
		tab = {"shopping":"shopping","preparation":"craft","trading":"journal","closing":"journal","settled":"journal"}[game.view().phase]
	_refresh()

func _notice(value: String):
	messages.append(value)
	if messages.size()>80: messages.pop_front()

func _event_text(event: Dictionary) -> String:
	if event.has("special"): return "有客人想请咩咩帮忙，普通营业已暂停。"
	var name_text = "未成交" if str(event.get("item_id","")).is_empty() else _inventory(str(event.item_id)).name
	var reasons: Array[String] = []
	for reason in event.get("reasons",[]):
		var text = str(reason)
		for tag in EFFECTS: text = text.replace(tag,EFFECTS[tag])
		reasons.append(text)
	return "%s · +%d 金 · %s" % [name_text,event.get("revenue",0),"；".join(reasons)]

func _record_events(events: Array):
	for event in events:
		if event is Dictionary: _notice(_event_text(event))
