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
		_recipe = str(fresh.world.plan.recipe_id); _quantity = int(fresh.world.plan.quantity); old_scroll = 0
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
	content.add_child(_label("计划只决定下一篮与下一批。取料、上台、开工和端菜都在物件旁完成。"))
	for wave in view.get("night", {}).get("waves", []):
		content.add_child(_label("第%s波 · %s位客人" % [str(wave.get("index", "")), str(wave.get("ordinary_count", ""))], 15))
	for recipe in view.get("recipes", []):
		var recipe_id = str(recipe.recipe_id)
		content.add_child(_button("plan_recipe_"+recipe_id, ("◆ " if recipe_id == _recipe else "")+str(recipe.name), func(): _recipe = recipe_id; _send("plan", {"recipe_id": _recipe, "quantity": _quantity}), _allowed("plan")))
	var row = HFlowContainer.new(); content.add_child(row)
	for quantity in range(1, 7):
		row.add_child(_button("plan_quantity_"+str(quantity), str(quantity)+"份", func(): _quantity = quantity; _send("plan", {"recipe_id": _recipe, "quantity": _quantity}), _allowed("plan")))
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
	content.add_child(_label("菜单不搬动物品。成菜要端到出餐台，才会进入真实派送。"))
	var selected: Array = view.service.menu_priority.duplicate()
	for recipe in view.get("recipes", []):
		var item_id = str(recipe.output); var active = item_id in selected
		content.add_child(_button("menu_toggle_"+item_id, ("移出 · " if active else "加入 · ")+str(recipe.name), func():
			var items = selected.duplicate()
			if item_id in items: items.erase(item_id)
			else: items.append(item_id)
			_send("menu", {"item_ids": items, "tiers": _menu_tiers(items)}), _allowed("menu") and (selected.size() > 1 if active else selected.size() < int(view.shelf_capacity))))
		if not active: continue
		var row = HFlowContainer.new(); content.add_child(row)
		for tier in ["friendly", "standard", "premium"]:
			row.add_child(_button("menu_price_"+item_id+"_"+tier, {"friendly": "亲民", "standard": "标准", "premium": "精品"}[tier], func():
				var tiers = _menu_tiers(selected); tiers[item_id] = tier
				_send("menu", {"item_ids": selected.duplicate(), "tiers": tiers}), _allowed("menu")))
		var index = selected.find(item_id)
		if index > 0:
			content.add_child(_button("menu_up_"+item_id, "优先供应 ↑", func():
				var items = selected.duplicate(); items[index] = items[index-1]; items[index-1] = item_id
				_send("menu", {"item_ids": items, "tiers": _menu_tiers(items)}), _allowed("menu")))

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
