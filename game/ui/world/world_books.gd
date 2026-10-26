extends PanelContainer
## Nearby planning only. All changes are spatial world_interact requests to Core.
const PortableFont = preload("res://game/ui/portable_font.gd")
signal intent_requested(option)
signal close_requested
var target_id = ""
var view: Dictionary = {}
var controls: Dictionary = {}
var stack: VBoxContainer
var scroll: ScrollContainer
var content: VBoxContainer
var heading: Label
var _recipe = ""
var _quantity = 3

func _ready():
	var ui_theme = Theme.new(); ui_theme.default_font = PortableFont.get_font(); ui_theme.default_font_size = 17; theme = ui_theme
	var paper = StyleBoxFlat.new(); paper.bg_color = Color("e9dcb7"); paper.border_color = Color("8f6b47"); paper.set_border_width_all(2); paper.set_content_margin_all(16)
	add_theme_stylebox_override("panel", paper)
	stack = VBoxContainer.new(); stack.add_theme_constant_override("separation", 10); add_child(stack)
	var row = HBoxContainer.new(); stack.add_child(row)
	heading = _label("", 21); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(heading)
	row.add_child(_button("book_close", "合上 ×", func(): close_requested.emit()))
	scroll = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus = true; stack.add_child(scroll)
	content = VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation", 10); scroll.add_child(content)

func _label(text: String, size = 17) -> Label:
	var label = Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("463626")); label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; return label

func _button(id: String, text: String, callback: Callable, enabled = true) -> Button:
	var button = Button.new(); button.text = text; button.custom_minimum_size = Vector2(48, 48)
	button.set_meta("action_id", id); button.disabled = not enabled; button.pressed.connect(callback, CONNECT_DEFERRED)
	button.add_theme_color_override("font_color", Color("463626")); controls[id] = button
	return button

func _send(action: String, payload: Dictionary):
	intent_requested.emit({"target_id": target_id, "action": action, "payload": payload})

func _allowed(action: String) -> bool:
	# A form may choose a new payload; Core rechecks it when submitted.
	for option in view.get("interactions", []):
		if option.target_id == target_id and option.action == action and option.get("enabled", false): return true
	return false

func present(id: String, fresh: Dictionary):
	var focused = get_viewport().gui_get_focus_owner()
	var focus_id = str(focused.get_meta("action_id", "")) if focused != null else ""
	var old_scroll = scroll.scroll_vertical
	if target_id != id:
		old_scroll = 0
	_recipe = str(fresh.world.plan.recipe_id); _quantity = int(fresh.world.plan.quantity)
	target_id = id; view = fresh
	for child in content.get_children(): content.remove_child(child); child.queue_free()
	var close = controls.get("book_close"); controls.clear(); controls.book_close = close
	heading.text = {"recipe-book": "灯下菜谱 · 出门准备", "menu-board": "今晚的菜单", "vendor": "巷口食材摊", "ledger": "咩咩的账本"}.get(id, "物件册页")
	match id:
		"recipe-book": _recipes()
		"menu-board": _menu()
		"vendor": _vendor()
		"ledger": _ledger()
	_wire_focus()
	call_deferred("_restore", focus_id, old_scroll)

func _restore(id: String, value: int):
	scroll.scroll_vertical = value
	var button = controls.get(id, controls.get("book_close"))
	if is_instance_valid(button) and button.is_visible_in_tree(): button.grab_focus()

func _wire_focus():
	var buttons: Array = []
	for button in controls.values():
		if is_instance_valid(button) and not button.disabled: buttons.append(button)
	for i in range(buttons.size()):
		var button: Button = buttons[i]; var previous: Button = buttons[(i-1+buttons.size())%buttons.size()]; var next: Button = buttons[(i+1)%buttons.size()]
		button.focus_previous = button.get_path_to(previous); button.focus_next = button.get_path_to(next)
		button.focus_neighbor_top = button.focus_previous; button.focus_neighbor_bottom = button.focus_next
		button.focus_entered.connect(func():
			if scroll.is_ancestor_of(button): scroll.ensure_control_visible(button))

func _recipes():
	_forecast()
	content.add_child(_label("下一批 · %s份；选好后，到柜边取料、台边开工。" % _quantity))
	var row = HFlowContainer.new(); content.add_child(row)
	for quantity in range(1, 7):
		row.add_child(_button("plan_quantity_"+str(quantity), ("◆" if quantity == _quantity else "")+str(quantity)+"份", func(): _quantity = quantity; _send("plan", {"recipe_id": _recipe, "quantity": _quantity}), _allowed("plan")))
	for recipe in view.get("recipes", []):
		var recipe_id = str(recipe.recipe_id)
		content.add_child(_button("plan_recipe_"+recipe_id, ("◆ " if recipe_id == _recipe else "")+str(recipe.name), func(): _recipe = recipe_id; _send("plan", {"recipe_id": _recipe, "quantity": _quantity}), _allowed("plan")))
		content.add_child(_label("适合："+_tags(str(recipe.output))+"\n魔法："+_magic(str(recipe.effect_id)), 15))
		if recipe_id == _recipe: _ingredients(recipe)
	content.add_child(_label("携带武器与餐前料理", 19))
	for weapon in view.get("progression", {}).get("owned_weapons", []):
		var weapon_id = str(weapon)
		var name = {"bolt_wand": "直线魔杖", "fan_wand": "散射魔杖"}.get(weapon_id, weapon_id)
		content.add_child(_button("equip_"+weapon_id, "装备 · "+name, func(): _send("equip_weapon", {"weapon_id": weapon_id}), _allowed("equip_weapon")))
	for item in view.get("inventory", []):
		if str(item.item_id) not in ["floating_pie", "star_soup"]: continue
		var item_id = str(item.item_id)
		content.add_child(_button("meal_"+item_id, "餐前吃一份 · "+str(item.name), func(): _send("consume", {"item_id": item_id, "quantity": 1}), _allowed("consume") and int(item.get("bag", 0)) > 0))

func _menu():
	_forecast()
	content.add_child(_label("菜单不搬动物品。成菜要端到出餐台，才会进入真实派送。"))
	var selected: Array = view.service.menu_priority.duplicate()
	for recipe in view.get("recipes", []):
		var item_id = str(recipe.output); var active = item_id in selected
		content.add_child(_button("menu_toggle_"+item_id, ("移出 · " if active else "加入 · ")+str(recipe.name), func():
			var items = selected.duplicate()
			if item_id in items: items.erase(item_id)
			else: items.append(item_id)
			_send("menu", {"item_ids": items, "tiers": _menu_tiers(items)}), _allowed("menu") and (selected.size() > 1 if active else selected.size() < int(view.shelf_capacity))))
		content.add_child(_label("适合："+_tags(item_id)+"\n"+_magic(str(recipe.effect_id)), 15))
		if not active: continue
		var current_tier = str(view.get("tiers", {}).get(item_id, "standard"))
		content.add_child(_label("当前售价 %s金 · %s" % [str(view.prices[item_id]), {"friendly":"亲民", "standard":"标准", "premium":"精品"}[current_tier]], 17))
		var row = HFlowContainer.new(); content.add_child(row)
		for tier in ["friendly", "standard", "premium"]:
			row.add_child(_button("menu_price_"+item_id+"_"+tier, ("◆ " if tier == current_tier else "")+{"friendly": "亲民", "standard": "标准", "premium": "精品"}[tier], func():
				var tiers = _menu_tiers(selected); tiers[item_id] = tier
				_send("menu", {"item_ids": selected.duplicate(), "tiers": tiers}), _allowed("menu")))
		var index = selected.find(item_id)
		if index > 0:
			content.add_child(_button("menu_up_"+item_id, "优先供应 ↑", func():
				var items = selected.duplicate(); items[index] = items[index-1]; items[index-1] = item_id
				_send("menu", {"item_ids": items, "tiers": _menu_tiers(items)}), _allowed("menu")))

func _forecast():
	var forecast: Dictionary = view.get("forecast", {})
	if str(forecast.get("text", "")) != "": content.add_child(_label(str(forecast.text), 16))
	var lines: Array[String] = []
	for wave in forecast.get("waves", []):
		var types: Array[String] = []
		for pair in [["quick","快餐"], ["hearty","正餐"], ["warm","暖身保温"]]:
			if int(wave.get(pair[0], 0)) > 0: types.append(pair[1]+"×"+str(wave[pair[0]]))
		lines.append("第%s波 · %s位 · %s" % [str(wave.index), str(wave.ordinary_count), " / ".join(types)])
	if not lines.is_empty(): content.add_child(_label("\n".join(lines), 15))

func _item(id: String) -> Dictionary:
	for row in view.get("inventory", []):
		if row.item_id == id: return row
	return {}

func _tags(id: String) -> String:
	var names = {"quick":"快餐", "hearty":"正餐", "warming":"暖身", "heat_hold":"保温", "portable":"外带", "trail_light":"照路", "celebration":"庆功"}
	var words: Array[String] = []
	for tag in _item(id).get("tags", []):
		if names.has(tag): words.append(names[tag])
	return " · ".join(words)

func _magic(id: String) -> String:
	return {"floating_delivery":"本波新饼可双通道浮空送餐；跨波余饼不再漂浮。", "ember_aura":"暖焰随汤杯保温，回应暖身、保温需求。", "self_stir":"坩埚自行搅拌送餐；跨波最多保温三份炖锅。", "trail_spark":"星火光点照亮返程，回应照路需求。", "comet_orbit":"彗尾环绕馅饼，回应庆功点单。"}.get(id, "")

func _ingredients(recipe: Dictionary):
	var missing: Array[String] = []
	for id in recipe.inputs:
		var item = _item(id)
		if item.is_empty(): continue
		var unit = int(recipe.inputs[id]); var required = unit*_quantity
		var owned = int(item.bag)+int(item.carried)+int(item.station_input)
		content.add_child(_label("%s · 每份%s；%s份需%s\n柜内%s · 手上%s · 台内%s" % [str(item.name), str(unit), str(_quantity), str(required), str(item.bag), str(item.carried), str(item.station_input)], 15))
		if owned < required: missing.append(str(item.name)+"×"+str(required-owned))
	content.add_child(_label("本批缺料："+"、".join(missing) if not missing.is_empty() else "本批材料已够；仍需取料、放上工作台。", 15))
	var device_id = str(recipe.requires_device)
	if device_id == "": content.add_child(_label("设备：无需专用设备", 15))
	else:
		var device = _item(device_id)
		content.add_child(_label("设备：%s · %s" % [str(device.get("name", "设备资料待提供")), "已装配" if int(device.get("installed", 0)) > 0 else "未装配，需在工作台旁安装"], 15))

func _menu_tiers(items: Array) -> Dictionary:
	var tiers: Dictionary = {}
	for id in items: tiers[id] = view.get("tiers", {}).get(id, "standard")
	return tiers

func _vendor():
	content.add_child(_label("买下的食材由魔法配送到柜内；不用逐份搬回店。"))
	for item in view.get("supply", []):
		var item_id = str(item.item_id)
		content.add_child(_label("%s · 单价%s金 · 余%s" % [str(item.name), str(item.buy), str(item.quantity)]))
		var row = HFlowContainer.new(); content.add_child(row)
		for quantity in [1, 3, 6]: row.add_child(_button("buy_"+item_id+"_"+str(quantity), "买"+str(quantity)+"份", func(): _send("buy", {"item_id": item_id, "quantity": quantity}), _allowed("buy") and bool(item.available) and quantity <= int(item.quantity) and quantity*int(item.buy) <= int(view.cash)))
	for item in view.get("inventory", []):
		if int(item.get("bag", 0)) <= 0: continue
		var item_id = str(item.item_id)
		content.add_child(_button("recycle_"+item_id, "售回一份 · "+str(item.name), func(): _send("recycle", {"item_id": item_id, "quantity": 1}), _allowed("recycle")))
	content.add_child(_button("recover", "需要时领取今日基础补助", func(): _send("recover", {}), _allowed("recover")))

func _ledger():
	content.add_child(_label("现有%s金 · 料理收入%s金" % [str(view.cash), str(view.get("dish_income", 0))], 19))
	var summary: Dictionary = view.get("summary", {})
	if not summary.is_empty():
		content.add_child(_label("料理收入%s − 成本%s − 店铺费用%s = 结末%s金" % [str(summary.get("revenue", "")), str(summary.get("sold_cost", "")), str(summary.get("fee", "")), str(summary.get("cash", ""))]))
	content.add_child(_button("settle", "记下今晚的账", func(): _send("settle", {}), _allowed("settle")))
	for upgrade in view.get("upgrades", []):
		var id = str(upgrade.upgrade_id)
		content.add_child(_label(str(upgrade.name)+" · "+str(upgrade.cost)+"金\n"+str(upgrade.description)))
		if id == "shelf": content.add_child(_label("次晨台上成菜自动接力至出餐台；接不下就留在台上，减少端菜往返。"))
		content.add_child(_button("upgrade_"+id, "投资明天 · "+str(upgrade.name), func(): _send("upgrade", {"upgrade_id": id}), _allowed("upgrade") and bool(upgrade.available)))
	content.add_child(_button("next_day", "歇息，迎接次晨", func(): _send("next_day", {}), _allowed("next_day")))
