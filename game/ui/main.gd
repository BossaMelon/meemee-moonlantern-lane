extends Control
## UI owns presentation/input only. Session and E01 own all persistent rules.
const Session = preload("res://game/core/game_session.gd")
const ShopCanvas = preload("res://game/ui/shop_canvas.gd")
const Art = preload("res://game/ui/pixel_assets.gd")
const EXPEDITION_SCENE = "res://scenes/expedition/expedition.tscn"
const CREAM = Color("493527")
const MUTED = Color("84694d")
const GOLD = Color("996036")
const DARK = Color("211a1c")
const PANEL = Color("eee0bd")
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
var margin: Control
var illustration: Control
var status: Label
var title: Label
var compact = false
var order_caption: Label
var phase_hint: Label
var feedback: Label
var scroll: ScrollContainer
var body: VBoxContainer
var primary: Button
var pause_button: Button
var sheet_layer: Control
var sheet_surface: PanelContainer
var sheet_title: Label
var sheet_open = false
var world_view = "room"
var return_hotspot = "world_lane"
var focus_caption: Label
var world_buttons: Dictionary = {}
var world_specs: Dictionary = {}
var recipe_selected = "floating_pie"
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
	var window=get_window()
	if window.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_size=Vector2i(1440,roundi(1440.0*window.size.y/window.size.x))
	else: window.content_scale_size=Vector2i.ZERO
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
	if not view.is_empty() and view.phase=="expedition": return
	if event.is_action_pressed("shop_pause") or event.is_action_pressed("ui_cancel"):
		if sheet_open and tab!="pause": _close_sheet()
		else: _toggle_pause()
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
	for state_name in ["normal","hover","pressed","focus"]: ui_theme.set_color("font_"+state_name+"_color","Button",CREAM)
	ui_theme.set_color("font_color","Button",CREAM)
	ui_theme.set_color("font_disabled_color","Button",Color("ac9b81"))
	ui_theme.set_stylebox("normal","Button",_style(Color("e5d2a7"),Color("c9b184"),1,10))
	ui_theme.set_stylebox("hover","Button",_style(Color("f7eac9"),Color("a87640"),1,10))
	ui_theme.set_stylebox("pressed","Button",_style(Color("cfb789"),Color("a87640"),1,10))
	ui_theme.set_stylebox("disabled","Button",_style(Color("e0d6be"),Color.TRANSPARENT,0,10))
	ui_theme.set_stylebox("focus","Button",_style(Color.TRANSPARENT,Color("ad783c"),3,0))
	ui_theme.set_constant("separation","VBoxContainer",10)
	ui_theme.set_constant("separation","HBoxContainer",10)
	ui_theme.set_constant("h_separation","HFlowContainer",8)
	ui_theme.set_constant("v_separation","HFlowContainer",8)
	theme = ui_theme

func _build_shell():
	margin=Control.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var backdrop=ColorRect.new()
	backdrop.color=DARK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	margin.add_child(backdrop)
	illustration=ShopCanvas.new()
	illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(illustration)
	_add_hotspot("world_stove","灶台 · 菜谱",Rect2(27,94,49,62),"room","craft")
	_add_hotspot("world_craft","备餐桌 · 菜谱",Rect2(82,105,67,44),"room","craft")
	_add_hotspot("world_menu","墙上菜单",Rect2(228,71,52,38),"room","shelf")
	_add_hotspot("world_counter","柜台 · 招呼客人",Rect2(223,160,85,62),"room","order")
	_add_hotspot("world_journal","桌上账本",Rect2(278,117,53,43),"room","journal")
	_add_hotspot("world_gear","门口 · 探险装备",Rect2(331,82,37,84),"room","gear")
	_add_hotspot("world_storage","储藏柜格",Rect2(156,101,40,42),"room","storage")
	_add_hotspot("world_lane","去月灯巷",Rect2(91,225,80,24),"room","lane")
	_add_hotspot("world_stall","巷口食材摊",Rect2(301,155,76,88),"lane","shopping")
	_add_hotspot("world_home","回到饭店",Rect2(7,91,48,104),"lane","home")
	focus_caption=_label("",18,Color("fff0c7"))
	focus_caption.add_theme_stylebox_override("normal",_style(Color("352619dd"),Color.TRANSPARENT,0,8))
	focus_caption.visible=false
	margin.add_child(focus_caption)
	var hud=HBoxContainer.new()
	hud.position=Vector2(24,18)
	hud.name="DayWeatherHUD"
	margin.add_child(hud)
	status=_label("",20,Color("fff0d0"))
	status.autowrap_mode=TextServer.AUTOWRAP_OFF
	status.add_theme_stylebox_override("normal",_style(Color("332519dd"),Color("705333"),1,12))
	hud.add_child(status)
	pause_button=_button("pause","Ⅱ",_toggle_pause)
	pause_button.tooltip_text="暂停 · 保存与退出"
	pause_button.size=Vector2(52,52)
	margin.add_child(pause_button)
	phase_hint=_label("",18,Color("f5dfb3"))
	phase_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	phase_hint.max_lines_visible=2
	margin.add_child(phase_hint)
	feedback=_label("",16,Color("f4d7a5"))
	feedback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	feedback.max_lines_visible=1
	margin.add_child(feedback)
	_build_sheet()
	battle_host=Control.new()
	battle_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_host.visible=false
	add_child(battle_host)

func _add_hotspot(id: String, caption: String, native: Rect2, location: String, sheet: String):
	var button=_button(id,"",_activate_hotspot.bind(id))
	button.tooltip_text=caption
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled",StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover",_style(Color("ffe7a318"),Color("f2d59088"),1,0))
	button.add_theme_stylebox_override("pressed",_style(Color("ffe7a328"),Color("f2d590"),2,0))
	button.add_theme_stylebox_override("focus",_style(Color("ffe7a310"),Color("f2d590"),2,0))
	button.focus_entered.connect(_point_hotspot.bind(id))
	button.mouse_entered.connect(_point_hotspot.bind(id))
	button.mouse_exited.connect(_leave_hotspot.bind(id))
	illustration.add_child(button)
	world_buttons[id]=button
	world_specs[id]={"caption":caption,"native":native,"location":location,"sheet":sheet}

func _point_hotspot(id: String):
	if sheet_open or not world_buttons.has(id): return
	focus_caption.text=world_specs[id].caption
	focus_caption.visible=true
	var rect: Rect2=world_buttons[id].get_global_rect()
	focus_caption.position=Vector2(clampf(rect.get_center().x-90,12,size.x-240),clampf(rect.end.y+5,76,size.y-100))
	focus_caption.size=Vector2(230,38)

func _leave_hotspot(id: String):
	if get_viewport().gui_get_focus_owner()!=world_buttons[id]: focus_caption.visible=false

func _activate_hotspot(id: String):
	return_hotspot=id
	var target: String=world_specs[id].sheet
	if target in ["lane","home"]:
		world_view="lane" if target=="lane" else "room"
		illustration.show_lane(world_view=="lane")
		_refresh()
		call_deferred("_focus_world", "world_stall" if world_view=="lane" else "world_lane")
	else:
		tab=target
		sheet_open=true
		_refresh()

func get_open_sheet() -> String:
	return tab if sheet_open else ""

func get_world_view() -> String:
	return world_view

func _build_sheet():
	sheet_layer=Control.new()
	sheet_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet_layer.visible=false
	margin.add_child(sheet_layer)
	var veil=ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color=Color("1d160e66")
	veil.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and tab!="pause": _close_sheet())
	sheet_layer.add_child(veil)
	sheet_surface=PanelContainer.new()
	sheet_surface.add_theme_stylebox_override("panel",_style(PANEL,Color("b58a55"),2,24))
	sheet_layer.add_child(sheet_surface)
	var stack=VBoxContainer.new()
	sheet_surface.add_child(stack)
	var heading=HBoxContainer.new()
	stack.add_child(heading)
	sheet_title=_label("",26,GOLD)
	sheet_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(sheet_title)
	heading.add_child(_button("sheet_close","合上 ×",_close_sheet))
	order_caption=_label("",18,GOLD)
	stack.add_child(order_caption)
	scroll=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	stack.add_child(scroll)
	body=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	primary=_button("primary","",_primary_action)
	stack.add_child(primary)

func _close_sheet():
	if tab=="pause" and game.view().paused:
		_toggle_pause()
		return
	sheet_open=false
	_refresh()
	call_deferred("_focus_world",return_hotspot)

func _focus_world(id: String):
	if world_buttons.has(id) and world_buttons[id].is_visible_in_tree() and not world_buttons[id].disabled:
		world_buttons[id].grab_focus()

func _resize_layout():
	if not built: return
	compact=size.y<560
	narrow=size.x<720
	pause_button.position=Vector2(size.x-76,18)
	status.get_parent().position=Vector2(16 if compact else 24,12 if compact else 18)
	status.add_theme_font_size_override("font_size",16 if compact else 20)
	phase_hint.position=Vector2(24,size.y-74)
	phase_hint.size=Vector2(size.x-48,32)
	feedback.position=Vector2(24,size.y-38)
	feedback.size=Vector2(size.x-48,26)
	_layout_sheet()
	_update_status()
	_position_hotspots()
	_wire_focus()

func _layout_sheet():
	var limits={"pause":Vector2(460,420),"craft":Vector2(880,600),"shopping":Vector2(820,660),"shelf":Vector2(820,680)}
	var preferred: Vector2=limits.get(tab,Vector2(800,680))
	var sheet_size=Vector2(minf(preferred.x,size.x-32),minf(preferred.y,size.y-112))
	if compact: sheet_size=Vector2(minf(710,size.x-24),size.y-24)
	sheet_surface.position=((size-sheet_size)/2).round()
	sheet_surface.size=sheet_size

func _position_hotspots():
	var scale_factor=minf(size.x/384.0,size.y/256.0)
	var origin=(size-Vector2(384,256)*scale_factor)/2
	for id in world_buttons:
		var spec: Dictionary=world_specs[id]
		var native: Rect2=spec.native
		var button: Button=world_buttons[id]
		button.position=(origin+native.position*scale_factor).round()
		button.size=(native.size*scale_factor).max(Vector2(48,48))
		button.visible=spec.location==world_view
		button.disabled=sheet_open or (not view.is_empty() and view.paused)

func _update_status():
	if view.is_empty(): return
	var weather="雨" if int(view.day)==3 else "晴"
	status.text="第%d日  ·  %s  ·  %s     %d 金" % [view.day,weather,PHASES.get(view.phase,view.phase),view.cash]

func _label(value: String, font_size: int = 18, color: Color = CREAM) -> Label:
	if sheet_open and tab=="shelf":
		if color==CREAM: color=Color("f3ebcf")
		elif color==MUTED: color=Color("bdc7ad")
		elif color==GOLD: color=Color("e6d39a")
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
	world_view="lane" if lane else "room"
	illustration.show_lane(lane)
	_close_sheet()

func _refresh():
	var focused=get_viewport().gui_get_focus_owner()
	var focus_id=str(focused.get_meta("action_id","")) if focused else ""
	var old_scroll=scroll.scroll_vertical
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for id in action_controls.keys():
		if not is_instance_valid(action_controls[id]) or not action_controls[id].is_inside_tree(): action_controls.erase(id)
	view=game.view()
	if view.phase!="expedition" and view.paused and not sheet_open:
		tab="pause"
		sheet_open=true
	if tab=="order" and view.pending.is_empty(): tab="counter"
	if tab=="counter" and not view.pending.is_empty(): tab="order"
	var context=str(view.phase)+":"+tab+":"+str(view.pending.get("id",""))
	if context!=body_context: old_scroll=0
	body_context=context
	_update_status()
	illustration.set_state(view)
	sheet_layer.visible=sheet_open and view.phase!="expedition"
	focus_caption.visible=false
	order_caption.visible=sheet_open and tab in ["order","counter"] and not view.pending.is_empty()
	if order_caption.visible:
		var pending=view.pending
		order_caption.text="%s · 预算 %d 金
%s%s" % ["海格 · 巡护带餐" if pending.get("character_id","")=="hagrid" else pending.text,pending.budget,_effects(pending.required)," · 奖励 "+_rewards(pending.get("rewards",[])) if not pending.get("rewards",[]).is_empty() else ""]
	var captions={"shopping":"月灯巷 · 食材摊","craft":"灯下菜谱册","shelf":"今晚的菜单","gear":"出门前的准备","journal":"咩咩的账本","storage":"厨房储藏","order":"柜台上的点单纸","counter":"柜台 · 开门迎客","pause":"灯还亮着，歇一歇"}
	sheet_title.text=captions.get(tab,"")
	sheet_title.add_theme_color_override("font_color",Color("e6d39a") if tab=="shelf" else GOLD)
	sheet_surface.add_theme_stylebox_override("panel",_style(Color("304437") if tab=="shelf" else PANEL,Color("8d633b"),3,16 if compact else 24))
	if sheet_open:
		match tab:
			"shopping": _build_shopping()
			"craft": _build_craft()
			"shelf": _build_menu()
			"gear": _build_gear()
			"storage":
				_build_stock("ingredient","篮子里的食材")
				_build_stock("dish","备好料理与菜单")
			"order": _build_special()
			"counter": _build_counter()
			"pause": _build_pause_menu()
			"journal":
				if view.phase=="settled": _build_summary()
				else: _build_journal()
	primary.text={"shopping":"食材备齐，回厨房 →","preparation":"翻开门牌，开门营业 →","closing":"收工，记下今天的账 →","settled":"保存三日回忆" if view.finished else "休息，迎接第%d日 →" % (int(view.day)+1)}.get(view.phase,"")
	primary.visible=sheet_open and ((tab=="shopping" and view.phase=="shopping") or (tab=="craft" and view.phase=="shopping") or (tab=="counter" and view.phase=="preparation") or (tab=="journal" and view.phase in ["closing","settled"]))
	primary.disabled=view.paused or not view.has("progression")
	if view.paused:
		for id in action_controls:
			if id not in ["pause","resume","save","load","quit","sheet_close"]: action_controls[id].disabled=true
	var hints={"shopping":"从巷口带回食材，再在备餐桌翻开菜谱。","preparation":"灶台备餐，墙上写菜单；准备好后到柜台开门。","trading":"普通客自动点餐。灯下的特别客人，会在柜台等你。","closing":"今晚的客人都走了。去桌边翻开账本吧。","settled":"账本里可以投资明天，也可以早点歇息。"}
	phase_hint.text="已暂停 · 保存与退出在暂停册页" if view.paused else ("巷口的食材摊亮着灯，店门随时为你留着。" if world_view=="lane" else hints.get(view.phase,""))
	if not view.pending.is_empty(): phase_hint.text="海格在柜台等一份温暖的带餐。" if view.pending.get("character_id","")=="hagrid" else "柜台有客人想和你说说特别的点单。"
	feedback.text=messages.back() if not messages.is_empty() else ""
	feedback.tooltip_text=feedback.text
	_position_hotspots()
	pause_button.disabled=sheet_open
	_layout_sheet()
	_sync_battle_route()
	_wire_focus()
	refresh_serial+=1
	call_deferred("_restore_focus",focus_id,old_scroll,refresh_serial)

func _build_counter():
	body.add_child(_label("把备好的料理写上菜单，巷里的客人就会循着灯来。",20))
	for item in view.inventory:
		if item.kind=="dish" and item.shelf>0: body.add_child(_label("%s    %d份    %d金" % [item.name,item.shelf,view.prices[item.item_id]],20))
	body.add_child(_label("特别点单会暂停客流；可到墙上的菜单板查份数，再回来交付。",17,MUTED))

func _build_pause_menu():
	body.add_child(_button("resume","继续今晚的故事",_toggle_pause,save_writes_allowed))
	body.add_child(_button("save","保存这一刻",_save.bind(false),save_writes_allowed))
	body.add_child(_button("load","重试恢复本地存档",_load_game))
	body.add_child(_button("quit","保存并退出" if save_writes_allowed else "退出，保留原存档",_save.bind(true)))
	body.add_child(_label("离开不会惩罚你，月灯巷会等你回来。",17,MUTED))

func _restore_focus(id: String, old_scroll: int, serial: int):
	if serial!=refresh_serial: return
	scroll.scroll_vertical=old_scroll
	if is_instance_valid(battle_panel) and view.phase=="expedition":
		if view.paused and not ordered_controls.is_empty():
			var focused=get_viewport().gui_get_focus_owner()
			if not focused is Button or not battle_panel.is_ancestor_of(focused): ordered_controls[0].grab_focus()
		else: battle_panel.grab_focus()
		return
	if action_controls.has(id) and action_controls[id].is_visible_in_tree() and not action_controls[id].disabled:
		action_controls[id].grab_focus()
	elif sheet_open:
		if not ordered_controls.is_empty(): ordered_controls[0].grab_focus()
	else:
		var fallback="world_stall" if world_view=="lane" else return_hotspot
		_focus_world(fallback)

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
	panel.add_theme_stylebox_override("panel",_style(Color("354a3c") if tab=="shelf" else Color("f5e9cb"),Color("d4be91"),0,12))
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
	body.add_child(_button("shopping_expedition","合上，去门口看看装备",_close_sheet))
	_build_stock("ingredient","储藏食材")

func _choose_recipe(id: String):
	recipe_selected=id
	_refresh()

func _build_craft():
	_batch_selector()
	var spread=HBoxContainer.new()
	spread.add_theme_constant_override("separation",24)
	body.add_child(spread)
	var index=VBoxContainer.new()
	index.custom_minimum_size.x=150 if compact else 190
	spread.add_child(index)
	var selected: Dictionary={}
	for recipe in view.recipes:
		var button=_button("recipe_"+recipe.recipe_id,recipe.name,_choose_recipe.bind(recipe.recipe_id))
		button.add_theme_font_size_override("font_size",16 if compact else 18)
		if recipe.recipe_id==recipe_selected:
			selected=recipe
			button.add_theme_stylebox_override("normal",_style(Color("cdb78a"),Color("9d7847"),1,10))
		index.add_child(button)
	if selected.is_empty(): return
	var page=VBoxContainer.new()
	page.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	spread.add_child(page)
	var item=_inventory(selected.output)
	var portrait=_icon(selected.output,88 if not compact else 56)
	portrait.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	page.add_child(portrait)
	page.add_child(_label(selected.name,26,GOLD))
	page.add_child(_label(_effects(item.tags),17,MUTED))
	var ingredients: Array[String]=[]
	for id in selected.inputs: ingredients.append("%s ×%d  ·  储藏%d" % [_inventory(id).name,selected.inputs[id],_inventory(id).bag])
	page.add_child(_label("\n".join(ingredients),18))
	page.add_child(_label(MAGIC.get(item.get("effect_id",""),""),17,MUTED))
	if not str(selected.get("requires_device","")).is_empty(): page.add_child(_label("需要装配自搅坩埚",17,GOLD))
	var possible=view.phase=="preparation" and selected.available and batch<=selected.max_quantity
	page.add_child(_button("craft_"+selected.recipe_id,"备好 %d 份" % batch,_act.bind("craft",{"recipe_id":selected.recipe_id,"quantity":batch}),possible))
	page.add_child(_label("最多 %d 份 · %s" % [selected.max_quantity,selected.reason],16,MUTED))
	page.add_child(_label("备好的料理还要写上墙上的菜单。",16,MUTED))

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
	card.add_child(_label("菜单板就在墙上；合上点单纸查看份数，再回到柜台交付。",17,MUTED))
	var choices: Array = pending.options.duplicate(true)
	choices.sort_custom(func(a,b): return a.available and not b.available)
	for option in choices:
		if not option.available and _inventory(option.item_id).shelf<=0: continue
		var choice = _card()
		_row_title(choice,option.item_id,option.name,"%d 金 · 菜单剩 %d" % [option.price,_inventory(option.item_id).shelf])
		choice.add_child(_button("fulfill_"+option.item_id,"交付这份料理",_act.bind("fulfill",{"order_id":pending.id,"item_id":option.item_id}),option.available))
		choice.add_child(_label("效果与预算匹配，可以交付。" if option.available else _human_text(str(option.reason)),17,MUTED))
	body.add_child(_button("special_menu","合上点单纸，去看墙上菜单",_close_sheet))
	body.add_child(_button("special_decline","跳过这次委托，继续营业",_act.bind("decline",{"order_id":pending.id})))

func _build_journal():
	body.add_child(_label("咩咩的饭店手账",24,GOLD))
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
	body.add_child(_button("summary_gear","合上账本，去看看装备",_close_sheet))
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
		"shopping": _act("finish_shopping",{})
		"preparation": _act("open_shop",{})
		"closing": _act("settle",{})
		"settled":
			if view.finished: _save(false)
			else: _act("next_day",{})
	if game.view().phase!="settled":
		sheet_open=false
		world_view="room"
		illustration.show_lane(false)
	_refresh()

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
	if result.ok and kind in ["fulfill","decline"]: sheet_open=false
	_refresh()
	action_completed.emit(kind,args,result)

func _release_battle_inputs():
	if is_instance_valid(battle_panel): battle_panel.release_inputs()

func _toggle_pause():
	_release_battle_inputs()
	var result=game.set_paused(not game.view().paused)
	_notice(("月灯巷会等你。" if game.view().paused else "继续。") if result.ok else result.message)
	if game.view().phase!="expedition":
		sheet_open=game.view().paused
		if sheet_open: tab="pause"
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
	sheet_open=false
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
