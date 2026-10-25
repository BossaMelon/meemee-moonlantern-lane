extends Control
## UI owns presentation/input only. Session and E01 own all persistent rules.
const Session = preload("res://game/core/game_session.gd")
const ShopCanvas = preload("res://game/ui/shop_canvas.gd")
const Art = preload("res://game/ui/pixel_assets.gd")
const EXPEDITION_SCENE = "res://scenes/expedition/expedition.tscn"
const CREAM = Color("fff3d0")
const MUTED = Color("c3d1ad")
const GOLD = Color("edc46e")
const DARK = Color("202438")
const PANEL = Color("25283f")
const PHASES = {"shopping":"采购","preparation":"备餐","trading":"营业","closing":"收工","settled":"日结","expedition":"巷后探险"}
const EFFECTS = {"meal":"料理","quick":"快捷","portable":"外带","hearty":"正餐","warming":"暖身","heat_hold":"保温","trail_light":"照路","celebration":"庆功"}
const MAGIC = {"floating_delivery":"餐盘漂浮送达赶路客","ember_aura":"暖焰随汤杯移动，外带仍保温","self_stir":"坩埚自行搅拌，热食持续冒汽","trail_spark":"星火光点随汤照亮返程路","comet_orbit":"彗尾环绕馅饼，回应庆功点单"}
const TIER_NAMES = {"friendly":"亲民 90%","standard":"标准 100%","premium":"精品 115%"}
const WEAPONS = {"bolt_wand":{"name":"直线魔杖","text":"远射程直线弹 · 适合拉开距离与寻找精英背面"},"fan_wand":{"name":"扇射魔杖","text":"短程三向覆盖 · 可配合推退与闪避重排出手机会"}}
signal action_completed(kind, args, result)
var game = Session.new(20261025)
var view: Dictionary = {}
var tab = "shopping"
var selected_item = "floating_pie"
var batch = 1
var request_serial = 0
var request_prefix = str(Time.get_unix_time_from_system())+":"+str(Time.get_ticks_usec())
var save_path = "user://moonlantern.json"
var save_writes_allowed = false
var messages: Array[String] = []
var action_controls: Dictionary = {}
var ordered_controls: Array[Button] = []
var root_box: VBoxContainer
var header: BoxContainer
var toolbar: HFlowContainer
var margin: MarginContainer
var content: BoxContainer
var shop_column: VBoxContainer
var illustration: Control
var status: Label
var title: Label
var status_row: HBoxContainer
var compact = false
var order_caption: Label
var phase_hint: Label
var feedback: Label
var notebook: VBoxContainer
var tabs: HFlowContainer
var scroll: ScrollContainer
var body: VBoxContainer
var primary: Button
var pause_button: Button
var battle_host: Control
var battle_panel: Control
var battle_missing: VBoxContainer
var narrow = false
var built = false
var refresh_serial = 0
var clock_accumulator = 0.0
var body_context = ""
var last_pending = ""

func _ready():
	get_tree().auto_accept_quit = false
	get_window().content_scale_size = Vector2i.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_theme()
	_configure_input()
	_build_shell()
	built = true
	resized.connect(_resize_layout)
	_resize_layout()
	if FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak"):
		var startup_load = _load_game()
		if not save_writes_allowed:
			game.set_paused(true)
			_notice("存档无法恢复。可以重试恢复，或退出并保留原存档与备份。")
			_show_file_error("RestoreFailure","存档未恢复，原文件已保留",str(startup_load.message)+"\n退出不会覆盖原存档或备份。")
	else:
		save_writes_allowed = true
		_notice("欢迎回家，咩咩。读需求、备料理，也可以去巷后采些特别食材。")
	_refresh()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _save(true)

func _configure_input():
	Input.emulate_mouse_from_touch = true
	var confirm = InputEventJoypadButton.new()
	confirm.button_index = JOY_BUTTON_A
	confirm.device = -1
	if not InputMap.action_has_event("ui_accept",confirm): InputMap.action_add_event("ui_accept",confirm)
	if not InputMap.has_action("shop_pause"):
		InputMap.add_action("shop_pause")
		var key = InputEventKey.new()
		key.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("shop_pause",key)
		var pad = InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_START
		InputMap.action_add_event("shop_pause",pad)

func _unhandled_input(event):
	# E01 owns gameplay bindings, including B=dodge and Start/Escape pause.
	if not view.is_empty() and view.phase=="expedition": return
	if event.is_action_pressed("shop_pause") or event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _process(delta):
	if not built or view.is_empty(): return
	if view.phase == "expedition":
		# E01 advances and emits returned; the main UI never double-ticks it.
		return
	if view.phase != "trading" or view.paused or not view.pending.is_empty():
		clock_accumulator = 0.0
		return
	clock_accumulator += delta
	if clock_accumulator < 0.1: return
	var result = game.advance(clampi(roundi(clock_accumulator*1000),1,60000))
	clock_accumulator = 0.0
	if not result.get("events",[]).is_empty():
		_record_events(result.events)
		_refresh()
	elif game.view().phase != view.phase: _refresh()

func _style(color: Color, border: Color, width: int = 1, padding: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(padding)
	return style

func _build_theme():
	var ui_theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC","Microsoft YaHei","Noto Sans CJK SC","Heiti SC"])
	ui_theme.default_font = font
	ui_theme.default_font_size = 18
	ui_theme.set_color("font_color","Label",CREAM)
	for type in ["normal","hover","pressed","focus"]: ui_theme.set_color("font_"+type+"_color","Button",CREAM)
	ui_theme.set_color("font_color","Button",CREAM)
	ui_theme.set_color("font_disabled_color","Button",Color("8796aa"))
	var normal = Art.skin("button_normal")
	# Compact E01 uses 16px text; keep the shared pixel skin at least 48px high.
	if normal: normal.content_margin_top=maxf(normal.content_margin_top,13)
	ui_theme.set_stylebox("normal","Button",normal if normal else _style(Color("374568"),Color("a5714f")))
	ui_theme.set_stylebox("hover","Button",_style(Color("493b3d"),GOLD,2))
	ui_theme.set_stylebox("pressed","Button",_style(Color("70483c"),GOLD,2))
	ui_theme.set_stylebox("disabled","Button",_style(Color("25283f"),Color("374568")))
	ui_theme.set_stylebox("focus","Button",_style(Color.TRANSPARENT,GOLD,4,0))
	ui_theme.set_constant("separation","VBoxContainer",8)
	ui_theme.set_constant("separation","HBoxContainer",8)
	ui_theme.set_constant("h_separation","HFlowContainer",8)
	ui_theme.set_constant("v_separation","HFlowContainer",8)
	theme = ui_theme

func _build_shell():
	var background = ColorRect.new()
	background.color = DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+edge,12)
	add_child(margin)
	root_box = VBoxContainer.new()
	margin.add_child(root_box)
	header = BoxContainer.new()
	root_box.add_child(header)
	title = _label("咩咩与月灯巷",24,GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	toolbar = HFlowContainer.new()
	toolbar.alignment = FlowContainer.ALIGNMENT_END
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(toolbar)
	pause_button = _button("pause","歇一歇",_toggle_pause)
	toolbar.add_child(pause_button)
	toolbar.add_child(_button("save","保存",func(): _save(false)))
	toolbar.add_child(_button("load","恢复",_load_game))
	toolbar.add_child(_button("quit","保存退出",func(): _save(true)))
	status_row = HBoxContainer.new()
	root_box.add_child(status_row)
	status = _label("",19)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status)
	status_row.add_child(_button("view_room","饭店",_show_world.bind(false)))
	status_row.add_child(_button("view_lane","街巷",_show_world.bind(true)))
	status_row.add_child(_button("to_gear","出发准备",_select_tab.bind("gear")))
	content = BoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(content)
	shop_column = VBoxContainer.new()
	content.add_child(shop_column)
	var art_panel = PanelContainer.new()
	art_panel.add_theme_stylebox_override("panel",_style(PANEL,Color("a5714f"),2,2))
	art_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_column.add_child(art_panel)
	illustration = ShopCanvas.new()
	art_panel.add_child(illustration)
	notebook = VBoxContainer.new()
	notebook.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notebook.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(notebook)
	tabs = HFlowContainer.new()
	notebook.add_child(tabs)
	for entry in [["shopping","采购"],["craft","备餐"],["shelf","菜单"],["gear","装备"],["journal","手账"],["order","委托"]]:
		var id = str(entry[0])
		tabs.add_child(_button("tab_"+id,entry[1],_select_tab.bind(id)))
	order_caption = _label("",18,GOLD)
	order_caption.visible = false
	notebook.add_child(order_caption)
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	notebook.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	phase_hint = _label("",17,MUTED)
	notebook.add_child(phase_hint)
	primary = _button("primary","",_primary_action)
	primary.custom_minimum_size.y = 52
	notebook.add_child(primary)
	battle_host = Control.new()
	battle_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_host.visible = false
	add_child(battle_host)
	feedback = _label("",17)
	feedback.custom_minimum_size.y = 42
	root_box.add_child(feedback)

func _resize_layout():
	if not built: return
	compact = size.y<560 and size.x>=720
	narrow = size.x<880 and not compact
	header.vertical = size.x<680 and not compact
	status_row.visible = not compact
	root_box.add_theme_constant_override("separation",6 if compact else 8)
	for edge in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+edge,8 if compact else 12)
	feedback.custom_minimum_size.y = 24 if compact else 42
	feedback.max_lines_visible = 1 if compact else -1
	feedback.add_theme_font_size_override("font_size",16 if compact else 17)
	phase_hint.max_lines_visible = 1 if compact else -1
	phase_hint.add_theme_font_size_override("font_size",16 if compact else 17)
	content.vertical = narrow
	var zoom = maxi(1,floori(minf((size.x-490)/384.0,(size.y-190)/256.0)))
	shop_column.custom_minimum_size.x = 0 if narrow else 384*zoom+4
	shop_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	shop_column.size_flags_vertical = Control.SIZE_FILL if narrow else Control.SIZE_EXPAND_FILL
	illustration.custom_minimum_size = Vector2(384,256)
	shop_column.custom_minimum_size.y = 260 if narrow else 0
	_update_status()
	_wire_focus()

func _update_status():
	if view.is_empty(): return
	var format = "%d / 3 日 · %s · %d 金\n待服务 %d%s" if size.x<720 else "第 %d / 3 日 · %s · 金币 %d · 待服务 %d%s"
	status.text = format % [view.day,PHASES.get(view.phase,str(view.phase)),view.cash,view.customers_remaining," · 已暂停" if view.paused else ""]
	title.text = "%d/3 %s · %d金 · 余%d客%s" % [view.day,PHASES.get(view.phase,str(view.phase)),view.cash,view.customers_remaining," · 暂停" if view.paused else ""] if compact else "咩咩与月灯巷"
	title.add_theme_font_size_override("font_size",18 if compact else 24)

func _label(value: String, font_size: int = 18, color: Color = CREAM) -> Label:
	var label = Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(id: String, value: String, callback: Callable, enabled: bool = true) -> Button:
	var button = Button.new()
	button.name = id.replace(":","_")
	button.set_meta("action_id",id)
	button.text = value
	button.custom_minimum_size = Vector2(48,48)
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = not enabled
	button.pressed.connect(callback,CONNECT_DEFERRED)
	button.focus_entered.connect(_focus_visible.bind(button))
	action_controls[id] = button
	return button

func get_action_control(id: String) -> Control:
	return action_controls.get(id)

func _icon(id: String, extent: int = 48) -> TextureRect:
	var image = TextureRect.new()
	image.texture = Art.sprite(id)
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.custom_minimum_size = Vector2(extent,extent)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _focus_visible(button: Button):
	if is_instance_valid(button) and scroll.is_ancestor_of(button): scroll.ensure_control_visible(button)

func _show_world(lane: bool):
	illustration.show_lane(lane)

func _select_tab(value: String):
	tab = value
	_refresh()

func _refresh():
	var focus = get_viewport().gui_get_focus_owner()
	var focus_id = str(focus.get_meta("action_id","")) if focus else ""
	var old_scroll = scroll.scroll_vertical
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for id in action_controls.keys():
		if not is_instance_valid(action_controls[id]) or not action_controls[id].is_inside_tree(): action_controls.erase(id)
	view = game.view()
	action_controls["save"].disabled = not save_writes_allowed
	action_controls["quit"].text = "保存退出" if save_writes_allowed else "退出（保留原档）"
	var pending_id = str(view.pending.get("id",""))
	if pending_id != last_pending and not pending_id.is_empty(): tab = "order"
	if pending_id.is_empty() and tab == "order": tab = "journal"
	last_pending = pending_id
	var context = str(view.phase)+":"+tab+":"+pending_id
	if context != body_context: old_scroll = 0
	body_context = context
	_update_status()
	pause_button.text = "继续" if view.paused else "歇一歇"
	illustration.set_state(view)
	order_caption.visible = not view.pending.is_empty()
	if order_caption.visible:
		var pending = view.pending
		var who = "海格 · 巡护带餐" if pending.get("character_id","") == "hagrid" else pending.text
		order_caption.text = "%s · 预算 %d 金\n%s · 停时等候%s" % [who,pending.budget,_effects(pending.required)," · 奖励 "+_rewards(pending.get("rewards",[])) if not pending.get("rewards",[]).is_empty() else ""]
	for id in ["shopping","craft","shelf","gear","journal","order"]:
		var button: Button = action_controls["tab_"+id]
		button.modulate = GOLD if tab==id else Color.WHITE
		button.visible = id!="order" or not view.pending.is_empty()
	if not view.has("progression"):
		body.add_child(_label("料理核心尚未接入",23,GOLD))
		body.add_child(_label("当前界面要求冻结的料理/成长契约；不会用旧商品进度冒充新饭店。"))
	elif tab == "order" and not view.pending.is_empty(): _build_special()
	elif view.phase == "settled" and tab == "journal": _build_summary()
	else:
		match tab:
			"shopping": _build_shopping()
			"craft": _build_craft()
			"shelf": _build_menu()
			"gear": _build_gear()
			_: _build_journal()
	var hints = {"shopping":"需求与天气在手账里。基础食材稳定供应，探险可跳过。","preparation":"先备好料理再放上菜单；保留或售回坩埚会改变可做的菜。","trading":"普通客自动成交。特殊委托停时，可切到菜单查看份数。","closing":"客流结束，日结后可用收入投资供货、菜单或探索套装。","settled":"三日旅程已完成，可以保存退出。" if view.finished else "升级次日生效；可在装备页查看明日的新选择。","expedition":"动作场景由 E01 推进，主界面不会重复计时。"}
	var compact_hints={"shopping":"稳定供货 · 雨天备货见手账","preparation":"先上菜单，再营业；厨具扩展菜谱","trading":"自动出餐；委托停时可看菜单","closing":"客流结束，日结后投资明天","settled":"升级次日生效；可以保存退出","expedition":"探险暂停与保存在动作工具栏"}
	phase_hint.text = ("已暂停，可以保存后继续。" if compact else "已暂停，经营与探险都在等你。") if view.paused else (compact_hints.get(view.phase,"") if compact else hints.get(view.phase,""))
	primary.text = {"shopping":"采购完成，回厨房备餐 →","preparation":"开门营业 →","trading":"营业中 · 普通客自动点餐","closing":"收好招牌，查看日结 →","settled":"保存三日回忆" if view.finished else "休息，迎接第 %d 日 →" % (int(view.day)+1),"expedition":"返回饭店"}.get(view.phase,"")
	primary.visible = view.pending.is_empty()
	primary.disabled = view.paused or view.phase in ["trading","expedition"] or not view.has("progression")
	if view.paused:
		for id in action_controls:
			if id not in ["pause","save","load","quit","view_room","view_lane","to_gear"] and not id.begins_with("tab_"): action_controls[id].disabled = true
	feedback.text = messages.back() if not messages.is_empty() else ""
	feedback.tooltip_text = feedback.text
	_sync_battle_route()
	_wire_focus()
	refresh_serial += 1
	call_deferred("_restore_focus",focus_id,old_scroll,refresh_serial)

func _restore_focus(id: String, old_scroll: int, serial: int):
	if serial != refresh_serial: return
	scroll.scroll_vertical = old_scroll
	if is_instance_valid(battle_panel) and view.phase=="expedition":
		if view.paused and not ordered_controls.is_empty():
			var focused = get_viewport().gui_get_focus_owner()
			if not focused is Button or not battle_panel.is_ancestor_of(focused): ordered_controls[0].grab_focus()
		else: battle_panel.grab_focus()
		return
	if action_controls.has(id) and action_controls[id].is_visible_in_tree() and not action_controls[id].disabled:
		action_controls[id].grab_focus()
	else:
		var fallback = "pause" if view.paused else "primary"
		if not view.pending.is_empty() and tab=="order" and not view.paused:
			fallback = "special_decline"
			for option in view.pending.options:
				if option.available: fallback = "fulfill_"+str(option.item_id); break
		if action_controls.has(fallback) and action_controls[fallback].is_visible_in_tree() and not action_controls[fallback].disabled: action_controls[fallback].grab_focus()
		elif not ordered_controls.is_empty(): ordered_controls[0].grab_focus()
	var focused = get_viewport().gui_get_focus_owner()
	if focused is Button: _focus_visible(focused)

func _wire_focus():
	ordered_controls.clear()
	_collect_buttons(self)
	for i in range(ordered_controls.size()):
		var button = ordered_controls[i]
		var previous = ordered_controls[(i-1+ordered_controls.size())%ordered_controls.size()]
		var next = ordered_controls[(i+1)%ordered_controls.size()]
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_left = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(next)
		button.focus_neighbor_right = button.get_path_to(next)

func _collect_buttons(node: Node):
	for child in node.get_children():
		if child is Button and child.is_visible_in_tree() and not child.disabled: ordered_controls.append(child)
		_collect_buttons(child)

func _card() -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(PANEL,Color("596a88"),1,10))
	body.add_child(panel)
	var box = VBoxContainer.new()
	panel.add_child(box)
	return box

func _row_title(card: VBoxContainer, id: String, title: String, subtitle: String = ""):
	var row = HBoxContainer.new()
	card.add_child(row)
	row.add_child(_icon(id))
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	box.add_child(_label(title,20,GOLD))
	if not subtitle.is_empty(): box.add_child(_label(subtitle,17,MUTED))

func _batch_selector():
	var row = HFlowContainer.new()
	body.add_child(row)
	var caption = _label("本次份数",18,MUTED)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.custom_minimum_size = Vector2(80,48)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	row.add_child(_button("batch_less","−",_change_batch.bind(-1),batch>1))
	var count = _label(str(batch),23,GOLD)
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.custom_minimum_size = Vector2(52,48)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count)
	row.add_child(_button("batch_more","＋",_change_batch.bind(1),batch<80))
	for n in [1,3,5]: row.add_child(_button("batch_%d"%n,str(n),_set_batch.bind(n)))

func _change_batch(amount: int):
	batch = clampi(batch+amount,1,80)
	_refresh()

func _set_batch(value: int):
	batch = value
	_refresh()

func _build_shopping():
	if not compact:
		body.add_child(_label("月灯巷食材摊",24,GOLD))
		body.add_child(_label("第三日有雨：暖焰汤（供货契约）或保温炖锅（留用坩埚）。食材与来源见手账。",17,MUTED))
	_batch_selector()
	for supply in view.supply:
		var card = _card()
		var row=HBoxContainer.new()
		card.add_child(row)
		row.add_child(_icon(supply.item_id))
		var description=_label("%s · %d 金/份\n今日余 %d · 储藏 %d" % [supply.name,supply.buy,supply.quantity,_inventory(supply.item_id).bag],18)
		description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(description)
		var possible = view.phase=="shopping" and supply.available and batch<=supply.quantity and batch*int(supply.buy)<=view.cash
		row.add_child(_button("buy_"+str(supply.item_id),"买%d份 · %d金" % [batch,batch*int(supply.buy)],_act.bind("buy",{"item_id":str(supply.item_id),"quantity":batch}),possible))
		if not possible:
			var reason = str(supply.reason)
			if view.phase=="shopping" and reason.is_empty(): reason = "本次份数超过供货或可用金币，请调低份数。"
			card.add_child(_label(reason,17,MUTED))
	body.add_child(_button("recover","帮邻店洗锅 · +12 金（每日一次）",_act.bind("recover",{}),_enabled("recover")))
	body.add_child(_button("shopping_expedition","查看今日探险与装备 →",_select_tab.bind("gear")))
	_build_stock("ingredient","储藏食材")

func _build_craft():
	body.add_child(_label("灯下厨房 · 已知菜谱",24,GOLD))
	body.add_child(_label("批量备餐立即完成；每一份都消耗真实食材。厨具开放新能力。",17,MUTED))
	_batch_selector()
	for recipe in view.recipes:
		var card = _card()
		var item = _inventory(recipe.output)
		_row_title(card,recipe.output,recipe.name,_effects(item.tags))
		var ingredients: Array[String] = []
		for id in recipe.inputs: ingredients.append("%s ×%d（储藏%d）" % [_inventory(id).name,recipe.inputs[id],_inventory(id).bag])
		card.add_child(_label(" + ".join(ingredients),17))
		if not str(recipe.get("requires_device","")).is_empty(): card.add_child(_label("厨具条件：安装自搅坩埚",17,GOLD))
		card.add_child(_label(MAGIC.get(item.get("effect_id",""),""),17,MUTED))
		var possible = view.phase=="preparation" and recipe.available and batch<=recipe.max_quantity
		card.add_child(_button("craft_"+recipe.recipe_id,"批量备好 %d 份"%batch,_act.bind("craft",{"recipe_id":recipe.recipe_id,"quantity":batch}),possible))
		card.add_child(_label("最多 %d 份 · %s" % [recipe.max_quantity,"本次份数超过现有食材" if batch>recipe.max_quantity and view.phase=="preparation" else recipe.reason],17,MUTED))
	body.add_child(_button("to_shelf","把备好的菜放上菜单 →",_select_tab.bind("shelf")))
	body.add_child(_button("kitchen_gear","查看或安装厨具 →",_select_tab.bind("gear")))
	_build_stock("dish","备好料理 · 尚未上菜单")

func _build_menu():
	body.add_child(_label("今晚菜单与份数",24,GOLD))
	var types = 0
	for item in view.inventory:
		if item.shelf>0: types += 1
	body.add_child(_label("菜单 %d / %d 道 · 上菜单后才可出售" % [types,view.shelf_capacity],17,MUTED))
	_batch_selector()
	var choices = HFlowContainer.new()
	body.add_child(choices)
	for item in view.inventory:
		if item.kind != "dish": continue
		var button = _button("select_"+item.item_id,"%s\n备%d · 菜单%d" % [item.name,item.bag,item.shelf],_select_item.bind(item.item_id))
		button.modulate = GOLD if selected_item==item.item_id else Color.WHITE
		choices.add_child(button)
	var current = _inventory(selected_item)
	if current.is_empty(): return
	var card = _card()
	_row_title(card,selected_item,current.name,_effects(current.tags))
	var price = int(view.prices[selected_item])
	var cost = 0
	var count = 0
	for item in current.uids:
		if item.location != "installed": cost += int(item.cost); count += 1
	card.add_child(_label("标价 %d 金 · 备好 %d / 菜单 %d\n%s" % [price,current.bag,current.shelf,"暂无库存" if count==0 else "平均成本 %.1f · 单份预计毛利 %.1f" % [float(cost)/count,price-float(cost)/count]],18))
	var moves = HFlowContainer.new()
	card.add_child(moves)
	moves.add_child(_button("display_"+selected_item,"上菜单 %d"%batch,_act.bind("display",{"item_id":selected_item,"quantity":batch}),view.phase=="preparation" and current.bag>=batch and (current.shelf>0 or types<view.shelf_capacity)))
	moves.add_child(_button("undisplay_"+selected_item,"撤回 %d"%batch,_act.bind("undisplay",{"item_id":selected_item,"quantity":batch}),view.phase=="preparation" and current.shelf>=batch))
	var prices = HFlowContainer.new()
	card.add_child(prices)
	for tier in ["friendly","standard","premium"]:
		var button = _button("price_"+tier,TIER_NAMES[tier],_act.bind("price",{"item_id":selected_item,"tier":tier}),view.phase=="preparation")
		button.modulate = GOLD if view.tiers.get(selected_item,"standard")==tier else Color.WHITE
		prices.add_child(button)
	card.add_child(_label("先匹配料理效果，再检查预算；加价不保证能卖出。",17,MUTED))
	_build_stock("dish","菜单与储藏总览")

func _select_item(id: String):
	selected_item = id
	_refresh()

func _build_gear():
	if not compact: body.add_child(_label("巷后菇圃 · 今日准备",24,GOLD))
	var expedition = view.expedition
	body.add_child(_label("今日 %d 次 · 撤退不罚款，保留已拾取食材"%expedition.attempts_remaining if compact else "今日剩余 %d 次 · 击败食材怪后靠近拾取\n可以不去；撤退或失败保留已拾取材料，无罚款。"%expedition.attempts_remaining,16 if compact else 18,MUTED))
	body.add_child(_button("start_expedition","进入巷后菇圃 →",_act.bind("start_expedition",{}),_enabled("start_expedition")))
	body.add_child(_label("今日食材：星火菇"+("，以及月心菇精英的高级材料；可做彗星馅饼。" if view.day==3 else "；可让暖焰汤变成会照路的星火汤。"),17,GOLD))
	body.add_child(_label("轻羽护盾："+("下次探险已备好一次免伤" if view.next_expedition_shield else "可吃掉一份储藏浮空饼，换一次免伤并放弃售价"),18,GOLD))
	body.add_child(_button("consume_pie","吃一份浮空饼 · 为下次探险护身",_act.bind("consume",{"item_id":"floating_pie","quantity":1}),view.phase=="shopping" and _inventory("floating_pie").bag>0 and not view.next_expedition_shield))
	body.add_child(_label("武器与技能",22,GOLD))
	for id in view.progression.owned_weapons:
		var card = _card()
		_row_title(card,id,WEAPONS[id].name,WEAPONS[id].text)
		var equipped = view.progression.equipped_weapon==id
		card.add_child(_button("equip_"+id,"已装备" if equipped else "装备这件武器",_act.bind("equip_weapon",{"weapon_id":id}),view.phase=="shopping" and not equipped))
	body.add_child(_label("推风术：半径推退、打断预警并暴露精英护盾；可接施法或闪避。" if "gust" in view.progression.skills else "探索套装次日解锁扇射魔杖与推风术：日结购买，要求实际料理收入。",18,MUTED))
	if not view.progression.pending_unlocks.is_empty():
		var names: Array[String] = []
		for id in view.progression.pending_unlocks: names.append(WEAPONS[id].name if WEAPONS.has(id) else ("推风术" if id=="gust" else str(id)))
		body.add_child(_label("已付款，次日生效："+"、".join(names),18,GOLD))
	body.add_child(_label("厨房的留用取舍",22,GOLD))
	var device = _inventory("stirring_cauldron")
	var card = _card()
	_row_title(card,"stirring_cauldron","自搅坩埚","留用可做自搅炖锅；售回得到18金，失去这项厨房能力。")
	card.add_child(_label("储藏 %d · 装配 %d · 厨具独立占槽" % [device.bag,device.installed],17,MUTED))
	for instance in device.uids:
		if instance.location=="bag": card.add_child(_button("install_cauldron","留用：安装自搅坩埚",_act.bind("install",{"uid":instance.uid}),view.phase=="preparation" and device.installed==0))
		elif instance.location=="installed": card.add_child(_button("uninstall_cauldron","拆下坩埚，回到储藏",_act.bind("uninstall",{"uid":instance.uid}),view.phase=="preparation"))
	card.add_child(_button("sell_cauldron","售回一件未装配坩埚 · 18 金",_act.bind("recycle",{"item_id":"stirring_cauldron","quantity":1}),view.phase in ["shopping","preparation"] and device.bag>0))
	_build_stock("ingredient","探险材料也进入真实储藏")

func _build_special():
	var pending = view.pending
	var card = _card()
	if pending.get("character_id","") == "hagrid":
		_row_title(card,"hagrid","海格 · 巡护带餐","暖身、保温、可外带的料理。完成回赠暖焰草；也可以跳过。")
	else: card.add_child(_label(pending.text,21,GOLD))
	card.add_child(_label("切到菜单可查看实际份数，再回到「委托」交付。",17,MUTED))
	var choices: Array = pending.options.duplicate(true)
	choices.sort_custom(func(a,b): return a.available and not b.available)
	for option in choices:
		if not option.available and _inventory(option.item_id).shelf<=0: continue
		var choice = _card()
		_row_title(choice,option.item_id,option.name,"%d 金 · 菜单剩 %d" % [option.price,_inventory(option.item_id).shelf])
		choice.add_child(_button("fulfill_"+option.item_id,"交付这份料理",_act.bind("fulfill",{"order_id":pending.id,"item_id":option.item_id}),option.available))
		choice.add_child(_label("效果与预算匹配，可以交付。" if option.available else _human_text(str(option.reason)),17,MUTED))
	body.add_child(_button("special_menu","查看菜单与份数",_select_tab.bind("shelf")))
	body.add_child(_button("special_decline","跳过这次委托，继续营业",_act.bind("decline",{"order_id":pending.id})))

func _build_journal():
	body.add_child(_label("咩咩的饭店手账",24,GOLD))
	var world=HFlowContainer.new()
	body.add_child(world)
	world.add_child(_button("journal_room","查看饭店全景",_show_world.bind(false)))
	world.add_child(_button("journal_lane","看看月灯巷",_show_world.bind(true)))
	body.add_child(_label(view.forecast.text,18,GOLD))
	body.add_child(_label("海格巡护带餐："+_quest_status(),18,GOLD))
	for order in view.demand_board:
		var who = "海格 · 巡护带餐" if order.get("character_id","")=="hagrid" else ("特别点单" if order.special else "普通客人")
		body.add_child(_label("%s %s · %s · 预算%d" % ["✓" if order.processed else "○",who,_effects(order.required),order.budget],17))
	body.add_child(_label("最近发生",21,GOLD))
	for i in range(maxi(0,messages.size()-12),messages.size()): body.add_child(_label(messages[i],17,MUTED))

func _build_summary():
	body.add_child(_label("三日饭店回忆" if view.finished else "今夜收工，辛苦啦",24,GOLD))
	var summary = view.summary
	body.add_child(_label("第 %d 日账单\n料理收入 %d − 已售成本 %d = 毛利 %d\n店铺费用 %d · 结末金币 %d" % [summary.day,summary.revenue,summary.sold_cost,summary.gross_profit,summary.fee,summary.cash],20))
	body.add_child(_label("库存、厨具售回、奖励与升级另有来源，不把回收收入当料理毛利。",17,MUTED))
	body.add_child(_label("海格巡护带餐："+_quest_status(),18,GOLD))
	if not view.finished:
		for upgrade in view.upgrades:
			var card = _card()
			card.add_child(_label(upgrade.name,21,GOLD))
			card.add_child(_label(upgrade.description,17,MUTED))
			card.add_child(_button("upgrade_"+upgrade.upgrade_id,"%s · %d 金" % ["已购买" if upgrade.owned else "投资明天",upgrade.cost],_act.bind("upgrade",{"upgrade_id":upgrade.upgrade_id}),upgrade.available))
			if not upgrade.available and not upgrade.owned: card.add_child(_label(str(upgrade.get("reason","")),17,MUTED))
	body.add_child(_button("summary_gear","看看装备、技能与待生效升级 →",_select_tab.bind("gear")))
	for sale in view.sales:
		if sale.day==view.day: body.add_child(_label(_event_text(sale),17,MUTED))

func _build_stock(kind: String, title: String):
	body.add_child(_label(title,21,GOLD))
	for item in view.inventory:
		if item.kind != kind: continue
		body.add_child(_label("%s：%s" % [item.name,"储藏%d"%item.bag if kind=="ingredient" else "备好%d / 菜单%d" % [item.bag,item.shelf]],17,MUTED))

func _quest_status() -> String:
	return {"not_offered":"尚未到访","pending":"正在等候","completed":"已完成，奖励已进入储藏","declined":"已跳过，不影响后续经营"}.get(view.quests.hagrid_patrol,str(view.quests.hagrid_patrol))

func _inventory(id: String) -> Dictionary:
	for item in view.inventory:
		if item.item_id==id: return item
	return {}

func _enabled(kind: String) -> bool:
	return bool(view.available_commands.get(kind,{}).get("enabled",false))

func _human_text(value: String) -> String:
	for tag in EFFECTS: value = value.replace(tag,EFFECTS[tag])
	return value

func _effects(tags: Array) -> String:
	var values: Array[String] = []
	for tag in tags: values.append(EFFECTS.get(tag,str(tag)))
	return " / ".join(values)

func _rewards(rewards: Variant) -> String:
	var values: Array[String] = []
	if rewards is Dictionary:
		for id in rewards: values.append("%s ×%d" % [_inventory(id).get("name",id),rewards[id]])
	elif rewards is Array:
		for reward in rewards: values.append("%s ×%d" % [_inventory(str(reward.get("item_id",""))).get("name",reward.get("item_id","")),reward.get("quantity",0)])
	return "、".join(values)

func _primary_action():
	if game.view().paused: return
	match view.phase:
		"shopping": tab = "craft"; _act("finish_shopping",{})
		"preparation": tab = "journal"; _act("open_shop",{})
		"closing": tab = "journal"; _act("settle",{})
		"settled":
			if view.finished: _save(false)
			else: tab = "shopping"; _act("next_day",{})

func _act(kind: String, args: Dictionary):
	if game.view().paused and kind!="leave_expedition":
		_notice("小店已暂停，请先继续。")
		_refresh()
		return
	if kind=="leave_expedition": _release_battle_inputs()
	var guest = str(game.view().pending.get("character_id","")) if kind=="fulfill" else ""
	request_serial += 1
	var result = game.command(kind,args,request_prefix+":"+str(request_serial))
	_notice(("✓ " if result.ok else "无法完成：")+str(result.message))
	_record_events(result.get("events",[]))
	if result.ok and kind=="craft":
		var fresh: Dictionary = game.view()
		for recipe in fresh.recipes:
			if recipe.recipe_id==args.recipe_id:
				for item in fresh.inventory:
					if item.item_id==recipe.output: illustration.play_effect(str(item.effect_id),str(item.item_id),"craft")
	if result.ok and kind=="fulfill": illustration.thank_guest(guest)
	_refresh()
	action_completed.emit(kind,args,result)

func _release_battle_inputs():
	if is_instance_valid(battle_panel): battle_panel.release_inputs()

func _toggle_pause():
	_release_battle_inputs()
	var result = game.set_paused(not game.view().paused)
	_notice(("已暂停，月灯巷会等你。" if game.view().paused else "继续。") if result.ok else result.message)
	_refresh()

func _save(exit_when_saved: bool):
	if not save_writes_allowed:
		if exit_when_saved: get_tree().quit()
		else:
			_notice("存档尚未恢复，原文件与备份受到保护；请先重试恢复。")
			_refresh()
		return
	# SceneTree.quit() completes at frame end. Freeze both session drivers before
	# writing so the live state cannot advance beyond the successful save.
	var main_was_processing=is_processing()
	var battle_process_mode=battle_panel.process_mode if is_instance_valid(battle_panel) else Node.PROCESS_MODE_INHERIT
	if exit_when_saved:
		set_process(false)
		if is_instance_valid(battle_panel): battle_panel.process_mode=Node.PROCESS_MODE_DISABLED
	_release_battle_inputs()
	var result = game.save_to(save_path)
	if result.ok and exit_when_saved:
		get_tree().quit()
		return
	if exit_when_saved:
		set_process(main_was_processing)
		if is_instance_valid(battle_panel):
			battle_panel.process_mode=battle_process_mode
			battle_panel.cancel_save_quit()
	_notice(("保存成功：" if result.ok else "保存失败：")+str(result.message))
	_refresh()
	if not result.ok:
		game.set_paused(true)
		_refresh()
		_show_file_error("SaveFailure","保存失败，当前进度仍保留",str(result.message))

func _show_file_error(node_name: String, caption: String, detail: String):
	var error_dialog=AcceptDialog.new()
	error_dialog.name=node_name
	error_dialog.title=caption
	error_dialog.dialog_text=detail
	error_dialog.theme=theme
	error_dialog.get_ok_button().custom_minimum_size=Vector2(96,48)
	error_dialog.confirmed.connect(error_dialog.queue_free)
	add_child(error_dialog)
	error_dialog.popup_centered(Vector2i(mini(480,int(size.x)-24),180))

func _load_game() -> Dictionary:
	_release_battle_inputs()
	var result = game.load_from(save_path)
	_notice(("恢复成功：" if result.ok else "恢复失败，当前进度未变：")+str(result.message))
	if result.ok:
		save_writes_allowed = true
		request_prefix = str(Time.get_unix_time_from_system())+":"+str(Time.get_ticks_usec())
		tab = {"shopping":"shopping","preparation":"craft","trading":"journal","closing":"journal","settled":"journal","expedition":"gear"}.get(game.view().phase,"journal")
		last_pending = ""
	_refresh()
	return result

func _sync_battle_route():
	var active = view.phase=="expedition"
	margin.visible = not active
	battle_host.visible = active
	if not active:
		if is_instance_valid(battle_panel): battle_panel.queue_free(); battle_panel = null
		if is_instance_valid(battle_missing): battle_missing.queue_free(); battle_missing = null
		return
	if not is_instance_valid(battle_panel) and ResourceLoader.exists(EXPEDITION_SCENE):
		battle_panel = load(EXPEDITION_SCENE).instantiate()
		battle_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		battle_host.add_child(battle_panel)
		battle_panel.bind_session(game)
		battle_panel.returned.connect(_on_returned,CONNECT_DEFERRED)
		battle_panel.pause_requested.connect(_toggle_pause,CONNECT_DEFERRED)
		battle_panel.save_requested.connect(_save.bind(false),CONNECT_DEFERRED)
		battle_panel.connect("save_quit_requested",_save.bind(true),CONNECT_DEFERRED)
	elif is_instance_valid(battle_panel): battle_panel.refresh()
	elif not is_instance_valid(battle_missing):
		battle_missing = VBoxContainer.new()
		battle_missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		battle_host.add_child(battle_missing)
		battle_missing.add_child(_label("动作场景尚未接入当前候选",24,GOLD))
		battle_missing.add_child(_label("需要 E01 发布的固定模块与场景，不能用菜单代替真实战斗。"))
		battle_missing.add_child(_button("missing_expedition_return","撤退回饭店",_act.bind("leave_expedition",{})))
func _on_returned():
	var counts = {}
	for drop in game.view().expedition.drops:
		if drop.collected: counts[drop.item_id] = counts.get(drop.item_id,0)+1
	_notice("回到饭店："+_rewards(counts)+"已进入储藏。" if not counts.is_empty() else "回到饭店。基础供货仍可继续，探险不会带来罚款。")
	tab = "gear"
	_refresh()

func _notice(value: String):
	messages.append(value)
	if messages.size()>80: messages.pop_front()

func _event_text(event: Dictionary) -> String:
	if event.get("special",false): return "海格正在等一份巡护带餐。" if event.get("character_id","")=="hagrid" else "有特别点单，普通营业已停时。"
	var id = str(event.get("item_id",""))
	var item = _inventory(id)
	var name_text = item.get("name",id) if not id.is_empty() else "未成交"
	var reasons: Array[String] = []
	for value in event.get("reasons",[]):
		var text = str(value)
		for tag in EFFECTS: text = text.replace(tag,EFFECTS[tag])
		reasons.append(text)
	var reward_text = ""
	if event.get("quest_id","")=="hagrid_patrol" and int(event.get("revenue",0))>0:
		reward_text = " · 巡护委托完成，奖励 "+_rewards(event.get("rewards",[]))
	return "%s%s · +%d 金 · %s%s" % ["海格 · " if event.get("character_id","")=="hagrid" else "",name_text,event.get("revenue",0),"；".join(reasons),reward_text]

func _record_events(events: Array):
	for event in events:
		if not event is Dictionary: continue
		if event.has("revenue"):
			_notice(_event_text(event))
			if int(event.revenue)>0: illustration.play_effect(str(event.get("effect_id","")),str(event.get("item_id","")),"sale")
		elif event.get("special",false): _notice(_event_text(event))
		elif event.has("message"): _notice(str(event.message))
