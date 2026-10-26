extends Control
## Production projection of Core view. No physics bodies, Session or tick here.
const Art = preload("res://game/ui/pixel_assets.gd")
const PortableFont = preload("res://game/ui/portable_font.gd")
const Walk = preload("res://game/ui/world/walk_animation.gd")
const InputRelay = preload("res://game/ui/world/world_input.gd")
const ItemGroup = preload("res://game/ui/world/item_group.gd")
const Structure = preload("res://game/ui/world/world_structure.gd")
const REFERENCE_SIZE = Vector2i(640, 360)
signal movement_requested(axis)
signal interaction_requested(interaction)
signal book_requested(interaction)
signal pause_requested
var relay = InputRelay.new()
var walk = Walk.new()
var current_view: Dictionary = {}
var schema_error = ""
var controls_enabled = true
var viewport: SubViewport
var surface: TextureRect
var stage: Node2D
var floor_layer: Node2D
var mark_layer: Node2D
var objects: Node2D
var camera: Camera2D
var actor: Sprite2D
var hud: Label
var prompt: Label
var feedback: Label
var overlay: Node2D
var touch_overlay: Node2D
var geometry: Dictionary = {}
var _region = ""
var _props: Dictionary = {}
var _customers: Dictionary = {}
var _customer_bubbles: Dictionary = {}
var _carried: Dictionary = {}
var _flights: Dictionary = {}
var _station_items: Dictionary = {}
var _jobs: Dictionary = {}
var _station_labels: Dictionary = {}
var _items: Dictionary = {}
var _primary: Dictionary = {}
var _object_specs: Dictionary = {}
var _feedback_remaining = 0.0
var _cosmetic_clock = 0.0
var _canvas_text_bindings: Array = []
var _touch_text_bindings: Array = []
var _context: Dictionary = {}
var _carry_plate: Sprite2D
var _walls: Dictionary = {}

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var background = ColorRect.new(); background.color = Color("171b29")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(background)
	viewport = SubViewport.new(); viewport.name = "WorldViewport"; viewport.size = REFERENCE_SIZE
	viewport.disable_3d = true; viewport.world_2d = World2D.new(); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(viewport)
	stage = Node2D.new(); viewport.add_child(stage)
	floor_layer = Node2D.new(); stage.add_child(floor_layer); floor_layer.draw.connect(_draw_floor)
	mark_layer = Node2D.new(); stage.add_child(mark_layer); mark_layer.draw.connect(_draw_marks)
	objects = Node2D.new(); objects.y_sort_enabled = true; stage.add_child(objects)
	actor = _sprite("meemee_idle"); actor.name = "AuthoritativeFoot"; objects.add_child(actor); actor.visible = false
	_carry_plate = _sprite("floating_plates"); _carry_plate.scale = Vector2.ONE*0.7; _carry_plate.z_index = 19; _carry_plate.visible = false; objects.add_child(_carry_plate)
	camera = Camera2D.new(); camera.position_smoothing_enabled = false; stage.add_child(camera); camera.make_current()
	surface = TextureRect.new(); surface.texture = viewport.get_texture(); surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	surface.stretch_mode = TextureRect.STRETCH_SCALE; surface.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(surface)
	overlay = Node2D.new(); add_child(overlay); overlay.draw.connect(_draw_controls)
	touch_overlay = Node2D.new(); touch_overlay.name = "TouchControls"; add_child(touch_overlay); touch_overlay.draw.connect(_draw_touch_controls); touch_overlay.visible = false
	hud = _label(17); hud.position = Vector2(18, 14); add_child(hud)
	prompt = _label(18); prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(prompt)
	feedback = _label(18); feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(feedback)
	relay.movement_requested.connect(func(axis): movement_requested.emit(axis))
	relay.interact_requested.connect(_interact)
	relay.pause_requested.connect(func(): pause_requested.emit())
	relay.mode_changed.connect(func(_mode): _sync_controls(); _update_prompt())
	resized.connect(_layout); _layout()
	show_feedback("等待世界核心视图。")

func _label(font_size: int) -> Label:
	var label = Label.new(); label.add_theme_font_override("font", PortableFont.get_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff0cf")); label.add_theme_color_override("font_shadow_color", Color("171821"))
	label.add_theme_constant_override("shadow_offset_x", 2); label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; label.focus_mode = Control.FOCUS_NONE
	return label

func _sprite(id: String) -> Sprite2D:
	var node = Sprite2D.new(); node.centered = false
	_set_sprite(node, id); return node

func _set_sprite(node: Sprite2D, id: String):
	node.texture = Art.sprite(id)
	var pivot: Array = Art.entry(id).get("pivot", [0, 0]); node.offset = -Vector2(pivot[0], pivot[1])

func _layout():
	if not is_instance_valid(surface): return
	var scale_factor = minf(size.x/640.0, size.y/360.0)
	if scale_factor >= 1.0: scale_factor = floorf(scale_factor)
	surface.size = Vector2(REFERENCE_SIZE)*scale_factor; surface.position = ((size-surface.size)/2).floor()
	prompt.size = Vector2(minf(360, surface.size.x-24), 68)
	feedback.position = Vector2(18, 52); feedback.size = Vector2(maxf(100, size.x-36), 32)
	_position_prompt(); _sync_controls()

func _sync_controls():
	if not is_instance_valid(touch_overlay): return
	touch_overlay.visible = controls_enabled and relay.input_mode == "touch"
	overlay.queue_redraw(); touch_overlay.queue_redraw()

func set_controls_enabled(value: bool):
	if controls_enabled != value: relay.clear()
	controls_enabled = value
	_sync_controls()

func clear_inputs(): relay.clear()

func reset_projection():
	clear_inputs(); walk.reset(); _region = ""; current_view = {}; _primary = {}; actor.visible = false
	_clear_nodes(_customers); _clear_nodes(_carried); _clear_nodes(_flights)

func _input(event: InputEvent):
	relay.observe_device(event)
	if not controls_enabled or not is_visible_in_tree(): return
	if relay.handle(event, size): get_viewport().set_input_as_handled(); _sync_controls()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: relay.clear()

func _interact():
	if _primary.is_empty(): return
	var target = str(_primary.get("target_id", ""))
	if str(_object_specs.get(target, {}).get("kind", "")) == "book": book_requested.emit(_primary.duplicate(true))
	else: interaction_requested.emit(_primary.duplicate(true))

func _point(value: Dictionary) -> Vector2: return Vector2(float(value.x), float(value.y))
func _rect(value: Dictionary) -> Rect2: return Rect2(Vector2(float(value.x)-float(value.width)/2, float(value.y)-float(value.height)/2), Vector2(value.width, value.height))

func present(view: Dictionary) -> bool:
	if not is_instance_valid(actor): return false
	if not view.get("world") is Dictionary or not view.world.get("geometry") is Dictionary:
		schema_error = "Core world.geometry 尚未绑定"; actor.visible = false; return false
	var world: Dictionary = view.world
	if not world.get("player") is Dictionary or not world.player.has_all(["x", "y", "facing"]) or not world.geometry.has_all(["width", "height", "colliders", "objects", "portals"]):
		schema_error = "Core 世界几何或脚点字段缺失"; actor.visible = false; return false
	if current_view.is_empty(): feedback.text = ""; _feedback_remaining = 0
	schema_error = ""; current_view = view
	_items.clear()
	for item in view.get("items", []): _items[int(item.uid)] = item
	if str(world.region_id) != _region:
		_region = str(world.region_id); geometry = world.geometry; _rebuild_geometry()
	var pose = walk.observe(_region, world.player, bool(view.get("paused", false)))
	actor.position = pose.foot; actor.texture = pose.texture; actor.offset = -pose.pivot; actor.visible = true
	for node in _walls.values(): node.observe_foot(pose.foot)
	camera.position = pose.foot; camera.force_update_scroll()
	_sync_customers(world.get("customers", [])); _sync_carried(world.get("carried_uids", []), pose.foot); _sync_projected_items(view); _sync_flights(view)
	_primary = {}
	# Core supplies nearest/primary order. Do not recalculate range/LOS or priority.
	for option in view.get("interactions", []):
		if option.get("enabled", false): _primary = option; break
	var phases = {"preparation": "备餐", "trading": "营业", "intermission": "波间备餐", "closing": "收工", "settled": "日结"}
	hud.text = "%s · 第%s夜 · %s  %s 金" % ["小店" if _region == "shop" else "月灯巷", str(view.get("day", "")), phases.get(str(view.get("phase", "")), ""), str(view.get("cash", "?"))]
	if int(view.get("service", {}).get("wave_index", 0)) > 0: hud.text += " · 波%s/3" % str(view.service.wave_index)
	if not world.get("carried_uids", []).is_empty(): hud.text += " · 手上%s件" % str(world.carried_uids.size())
	_update_prompt()
	mark_layer.queue_redraw(); _sync_controls(); return true

func _update_prompt():
	if current_view.is_empty(): return
	var world: Dictionary = current_view.world
	_context = _primary
	var confirm = {"keyboard":"F", "pad":"A", "touch":"互动"}[relay.input_mode]
	prompt.text = "已暂停" if current_view.get("paused", false) else (confirm+" · "+_action_label(_primary) if not _primary.is_empty() else _next_hint(world))
	if not _primary.is_empty() and str(_primary.action) == "serve":
		for quote in current_view.get("serve_quotes", []):
			if quote.order_id == _primary.payload.get("order_id", "") and int(quote.uid) == int(_primary.payload.get("uid", 0)):
				prompt.text += "\n基础%s · 小费%s · 合计%s金" % [str(quote.base_price), str(quote.tip), str(quote.paid_total)]
	if _primary.is_empty() and not current_view.get("paused", false):
		for option in current_view.get("interactions", []):
			if option.reason in ["请走近物件", "中间有障碍", "物件不在当前区域"]: continue
			_context = option
			if str(option.target_id) == "prep":
				for station in world.stations:
					if station.id != "prep" or not station.job is Dictionary: continue
					var name = "这一批料理"
					for recipe in current_view.recipes:
						if recipe.recipe_id == station.job.recipe_id: name = str(recipe.name)
					prompt.text = "料理中 · %s · %.1f秒\n可以走动，做好后回台边取菜。" % [name, float(station.job.remaining_ms)/1000.0]
					_position_prompt(); return
			if option.action not in ["put", "take", "serve"] and str(option.reason) != "": prompt.text = str(option.reason); break
	_position_prompt()

func _position_prompt():
	if not is_instance_valid(prompt) or not is_instance_valid(surface): return
	var anchor: Dictionary = _context.get("anchor", {})
	var at = actor.position if anchor.is_empty() else _point(anchor)
	var point = surface.position+(at-camera.get_screen_center_position()+Vector2(REFERENCE_SIZE)/2)*surface.size.x/REFERENCE_SIZE.x
	var bounds = Rect2(surface.position+Vector2(8,8), surface.size-Vector2(16,16))
	prompt.position = Vector2(point.x-prompt.size.x/2, point.y-110).clamp(bounds.position, bounds.end-prompt.size).round()

func _action_label(option: Dictionary) -> String:
	var action = str(option.get("action", "")); var label = str(option.get("label", ""))
	if label != action and not label.is_empty(): return label
	if action == "take": return "取一篮原料" if str(option.get("target_id", "")) == "pantry" else "端起这一批成菜或材料"
	if action == "put": return {"prep": "把原料放上工作台", "pass": "把料理放上出餐台", "pantry": "放回食材柜"}.get(str(option.get("target_id", "")), "放下手中物品")
	if action == "cook":
		for recipe in current_view.get("recipes", []):
			if str(recipe.recipe_id) == str(option.get("payload", {}).get("recipe_id", "")): return "开工 · %s ×%s" % [str(recipe.name), str(option.payload.quantity)]
	return {"take": "拿起这一批", "put": "放下手中物品", "cook": "开始这一批料理", "serve": "亲手送餐", "plan": "翻开菜谱", "menu": "看看今晚菜单", "buy": "看看食材摊", "recycle": "售回物品", "recover": "基础补助", "open_shop": "摇铃，开门迎客", "start_wave": "摇铃，迎接下一波", "settle": "翻开账本记账", "upgrade": "翻开账本", "next_day": "歇息到次晨", "enter": "走过这扇门", "equip_weapon": "准备出门装备", "consume": "餐前吃一份", "install": "装好厨房设备", "uninstall": "取下厨房设备"}.get(action, label)

func _next_hint(world: Dictionary) -> String:
	if _region == "lane": return "走近食材摊采购，或沿巷道前往菇圃门。"
	var flags: Dictionary = world.get("intro_flags", {})
	if not flags.get("moved", false): return {"keyboard":"WASD / 方向键 · 走近物件", "pad":"左摇杆 · 走近物件", "touch":"左侧圆盘 · 走近物件"}[relay.input_mode]
	if not flags.get("took", false): return "食材柜旁可以拿一篮材料。"
	if not flags.get("loaded", false): return "带到工作台，放下材料。"
	if not flags.get("cooked", false): return "台边开工；料理时可以继续走动。"
	if not flags.get("served", false): return "取成菜、摇门铃，亲送客席或放上出餐台。"
	return "走近客人或桌柜" if _primary.is_empty() else "走近物件互动"

func _clear_nodes(nodes: Dictionary):
	for node in nodes.values():
		if is_instance_valid(node): node.get_parent().remove_child(node); node.queue_free()
	nodes.clear()

func _rebuild_geometry():
	_clear_nodes(_props); _clear_nodes(_customers); _clear_nodes(_carried); _clear_nodes(_flights)
	_clear_nodes(_walls)
	_clear_nodes(_station_items); _clear_nodes(_jobs); _clear_nodes(_station_labels)
	_customer_bubbles.clear()
	_object_specs.clear()
	for object in geometry.objects: _object_specs[str(object.id)] = object
	camera.limit_left = 0; camera.limit_top = 0; camera.limit_right = int(geometry.width); camera.limit_bottom = int(geometry.height)
	var captions = {"storage-body":"食材柜", "prep-body":"料理台", "stove-body":"设备台", "pass-body":"出餐台", "vendor-body":"巷口食材摊", "lane-bench":"长凳"}
	var books = {"recipe-body":"world_recipe_book", "menu-body":"world_menu_board", "ledger-body":"world_ledger"}
	for collider in geometry.colliders:
		var id = str(collider.id)
		if int(collider.width) == 24 or int(collider.height) == 24: continue
		var node = Structure.new(); objects.add_child(node); node.configure(_rect(collider),[id],"",str(captions.get(id,""))); _props[id] = node
		if books.has(id): node.place_book(str(books[id]))
	for piece in Structure.wall_pieces(geometry):
		var node = Structure.new(); objects.add_child(node); node.configure(piece.rect,piece.ids,piece.module); _walls[str(_walls.size())] = node
	for object in geometry.objects:
		if str(object.kind) == "portal":
			# The shop's real 120px opening stays open. Lane leaves attach to
			# existing solid walls; their Core interaction anchors do not move.
			if str(object.id) != "shop-exit":
				var door = _sprite("door"); door.position = Vector2(24 if str(object.id) == "lane-home" else float(geometry.width)-24,float(object.anchor.y)); objects.add_child(door); _props[str(object.id)] = door
		if str(object.kind) in ["portal", "bell"]:
			var label = _label(12); label.position = _point(object.anchor)+Vector2(-48, 10); label.size = Vector2(96, 24); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.text = {"door-bell": "门铃", "shop-exit": "月灯巷 →", "lane-home": "← 回小店", "garden-gate": "菇圃门"}.get(str(object.id), "")
			objects.add_child(label); _props[str(object.id)+"-label"] = label
	floor_layer.queue_redraw()

func _draw_floor():
	if geometry.is_empty(): return
	var bounds = Rect2(0, 0, geometry.width, geometry.height)
	floor_layer.draw_rect(bounds, Color("543b31") if _region == "shop" else Color("3b4351"))
	var tile = Art.sprite("floor_wood" if _region == "shop" else "floor_stone")
	if tile != null:
		for y in range(0, int(geometry.height), 64):
			for x in range(0, int(geometry.width), 128):
				floor_layer.draw_texture_rect(tile, Rect2(x, y, 64, 32), false, Color(1, 1, 1, 0.035))
	for collider in geometry.colliders:
		if _props.has(str(collider.id)): continue
		var rect = _rect(collider); floor_layer.draw_rect(rect, Color("302d38"))
		floor_layer.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("8a7059"), 3)

func _sync_customers(customers: Array):
	var retained: Dictionary = {}
	for customer in customers:
		if not customer.get("spawned", false) or str(customer.state) == "gone" or _region != "shop": continue
		var id = str(customer.id); retained[id] = true
		if not _customers.has(id):
			_customers[id] = _sprite("student_idle"); objects.add_child(_customers[id])
			var bubble = _label(12); bubble.position = Vector2(-64, -86); bubble.size = Vector2(128, 32); bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_customers[id].add_child(bubble); _customer_bubbles[id] = bubble
		var node: Sprite2D = _customers[id]; node.position = _point(customer)
		node.modulate = Color("ffe3a6") if int(customer.get("reaction_remaining_ms", 0)) > 0 else Color.WHITE
		var bubble: Label = _customer_bubbles[id]; bubble.text = ""
		if int(customer.get("reaction_remaining_ms", 0)) > 0: bubble.text = "谢谢，很香！"
		elif str(customer.state) == "waiting":
			for order in current_view.get("service", {}).get("orders", []):
				if order.id != customer.order_id: continue
				var words: Array[String] = []
				for tag in order.get("required", []):
					if tag in ["quick", "hearty", "warming", "heat_hold"]: words.append({"quick": "快餐", "hearty": "正餐", "warming": "暖身", "heat_hold": "保温"}[tag])
				bubble.text = " · ".join(words)+("\n想要亲送" if order.get("prefers_hand_delivery", false) else "")
	for id in _customers.keys():
		if not retained.has(id): var node = _customers[id]; objects.remove_child(node); node.queue_free(); _customers.erase(id); _customer_bubbles.erase(id)

func _sync_carried(uids: Array, foot: Vector2):
	var grouped: Dictionary = {}
	for uid in uids:
		var item: Dictionary = _items.get(int(uid), {})
		if item.is_empty(): continue
		var id = str(item.item_id)
		if not grouped.has(id): grouped[id] = []
		grouped[id].append(int(uid))
	_carry_plate.visible = not grouped.is_empty(); _carry_plate.position = foot+Vector2(20,-12)
	var retained: Dictionary = {}
	var index = 0
	for id in grouped:
		retained[id] = true
		if not _carried.has(id): _carried[id] = ItemGroup.new(); objects.add_child(_carried[id])
		var node = _carried[id]; node.z_index = 20
		node.present(str(id), grouped[id], foot+Vector2(20+(index-(grouped.size()-1)/2.0)*15,-21), 0.42); index += 1
	for id in _carried.keys():
		if not retained.has(id): var node = _carried[id]; objects.remove_child(node); node.queue_free(); _carried.erase(id)

func _work_surface(target: String, collider_id = "") -> Vector2:
	var object: Dictionary = _object_specs.get(target, {})
	var body = str(object.get("collider_id", "")) if collider_id == "" else collider_id
	if _props.has(body) and _props[body].has_method("surface_anchor"): return _props[body].surface_anchor()
	for collider in geometry.colliders:
		if str(collider.id) == body: return _rect(collider).get_center()-Vector2(0,24)
	return _point(object.get("anchor", {"x":0,"y":0}))

func _sync_projected_items(view: Dictionary):
	var retained: Dictionary = {}; var counts: Dictionary = {}; var grouped: Dictionary = {}
	for item in view.get("items", []):
		var location = str(item.location)
		if location not in ["bag", "station_input", "ready", "shelf", "installed"]: continue
		var target = {"bag": "pantry", "station_input": "prep", "ready": "prep", "shelf": "pass", "installed": "prep"}[location]
		if not _object_specs.has(target): continue
		var key = location+":"+str(item.item_id)
		if not grouped.has(key): grouped[key] = {"item_id":str(item.item_id),"location":location,"target":target,"uids":[]}
		grouped[key].uids.append(int(item.uid))
	for key in grouped:
		var group: Dictionary = grouped[key]; var location = str(group.location); var target = str(group.target)
		retained[key] = true
		if not _station_items.has(key): _station_items[key] = ItemGroup.new(); objects.add_child(_station_items[key])
		var node = _station_items[key]
		var index = int(counts.get(location, 0)); counts[location] = index+1
		var anchor = _work_surface(target, "stove-body" if location == "installed" else "")
		node.z_index = 5; node.present(str(group.item_id), group.uids, anchor+Vector2(-18+(index%3)*18, -floori(float(index)/3.0)*16), 0.55 if location == "installed" else 0.48)
	for key in _station_items.keys():
		if not retained.has(key): var node = _station_items[key]; objects.remove_child(node); node.queue_free(); _station_items.erase(key)
	var jobs: Dictionary = {}; var labels: Dictionary = {}
	for station in view.world.get("stations", []):
		var id = str(station.id)
		if not _object_specs.has(id): continue
		var anchor = _work_surface(id)
		var job = station.get("job")
		if job is Dictionary:
			jobs[id] = true
			if not _jobs.has(id): _jobs[id] = _sprite("floating_plates"); objects.add_child(_jobs[id])
			var node: Sprite2D = _jobs[id]; node.position = anchor; node.scale = Vector2(0.65, 0.65); node.z_index = 8
			labels[id] = "料理中 · %.1f秒" % (float(job.remaining_ms)/1000.0)
		elif not station.output_uids.is_empty(): labels[id] = "成菜就绪 ×%s" % str(station.output_uids.size())
		elif not station.input_uids.is_empty(): labels[id] = "台内原料 ×%s" % str(station.input_uids.size())
		if labels.has(id):
			if not _station_labels.has(id):
				var panel = PanelContainer.new(); var paper = StyleBoxFlat.new(); paper.bg_color = Color("171b29dc"); paper.set_content_margin_all(4); paper.corner_radius_top_left = 3; paper.corner_radius_top_right = 3; paper.corner_radius_bottom_left = 3; paper.corner_radius_bottom_right = 3
				panel.add_theme_stylebox_override("panel", paper); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; panel.add_child(_label(11)); objects.add_child(panel); _station_labels[id] = panel
			var panel: PanelContainer = _station_labels[id]; panel.position = anchor+Vector2(-62,-40); panel.size = Vector2(124,22); panel.z_index = 9
			var label: Label = panel.get_child(0); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.text = labels[id]
	for id in _jobs.keys():
		if not jobs.has(id): var node = _jobs[id]; objects.remove_child(node); node.queue_free(); _jobs.erase(id)
	for id in _station_labels.keys():
		if not labels.has(id): var node = _station_labels[id]; objects.remove_child(node); node.queue_free(); _station_labels.erase(id)

func _sync_flights(view: Dictionary):
	var retained: Dictionary = {}
	for row in view.get("service", {}).get("reservations", []):
		var uid = int(row.item_uid); var item: Dictionary = _items.get(uid, {})
		if item.is_empty() or _region != "shop": continue
		var destination: Dictionary = {}
		for customer in view.world.get("customers", []):
			if customer.order_id == row.order_id: destination = customer; break
		if destination.is_empty(): continue
		retained[uid] = true
		if not _flights.has(uid): _flights[uid] = _sprite(str(item.item_id)); objects.add_child(_flights[uid]); _flights[uid].set_meta("item_uid", uid)
		var node: Sprite2D = _flights[uid]; node.scale = Vector2(0.65, 0.65); node.z_index = 21
		var channel = str(row.channel); var duration = {"manual": 50.0, "ordinary": 3000.0, "floating": 1500.0, "pot": 4500.0}.get(channel, 3000.0)
		var progress = clampf(1.0-float(row.remaining_ms)/float(duration), 0, 1)
		var start = actor.position if channel == "manual" else _point(_object_specs.get("pass", {}).get("anchor", {"x": actor.position.x, "y": actor.position.y}))
		node.position = start.lerp(_point(destination), progress)+Vector2(0, -24-sin(progress*PI)*18)
	for uid in _flights.keys():
		if not retained.has(uid): var node = _flights[uid]; objects.remove_child(node); node.queue_free(); _flights.erase(uid)

func _draw_marks():
	if current_view.is_empty(): return
	mark_layer.draw_circle(actor.position, 12, Color("11131b66"))
	if _object_specs.has("door-bell"):
		var bell = _point(_object_specs["door-bell"].anchor)-Vector2(0, 24)
		mark_layer.draw_rect(Rect2(bell-Vector2(6, 7), Vector2(12, 12)), Color("dcb675")); mark_layer.draw_rect(Rect2(bell+Vector2(-9, 5), Vector2(18, 3)), Color("f0d49b")); mark_layer.draw_rect(Rect2(bell+Vector2(-2, 8), Vector2(4, 3)), Color("aa784a"))
	if not _primary.is_empty():
		var anchor: Dictionary = _primary.get("anchor", {})
		if anchor.has_all(["x", "y"]): mark_layer.draw_arc(_point(anchor), 17, 0, TAU, 32, Color("e8cd91"), 2)
	for station in current_view.world.get("stations", []):
		if not station.get("job") is Dictionary: continue
		var anchor: Dictionary = _object_specs.get(str(station.id), {}).get("anchor", {})
		if not anchor.has_all(["x", "y"]): continue
		var at = _point(anchor)-Vector2(0, 50)
		mark_layer.draw_arc(at, 22, _cosmetic_clock*2, _cosmetic_clock*2+PI*1.5, 24, Color("f2c886"), 3)

func _draw_controls():
	if not controls_enabled or relay.input_mode == "touch": return
	var text = "Start 暂停" if relay.input_mode == "pad" else "Esc 暂停"
	var font = PortableFont.get_font()
	overlay.draw_string(font, relay.pause_rect(size).position+Vector2(18,25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e8d7b4"))
	_canvas_text_bindings = [{"text":text,"font":font}]

func _draw_touch_controls():
	if not controls_enabled or relay.input_mode != "touch": return
	var center = relay.stick_center(size)
	touch_overlay.draw_circle(center, 58, Color("1d2534a0")); touch_overlay.draw_arc(center, 58, 0, TAU, 36, Color("bea477"), 2)
	touch_overlay.draw_circle(center+relay.touch_axis()*40, 18, Color("d9bf8da0"))
	for rect in [relay.interact_rect(size), relay.pause_rect(size)]:
		touch_overlay.draw_rect(rect, Color("252a36c0")); touch_overlay.draw_rect(rect, Color("b49b72"), false, 2)
	var font = PortableFont.get_font()
	touch_overlay.draw_string(font, relay.interact_rect(size).position+Vector2(20, 51), "互动", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("fff0cf"))
	touch_overlay.draw_string(font, relay.pause_rect(size).position+Vector2(18, 29), "暂停", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("fff0cf"))
	_touch_text_bindings = [{"text": "互动", "font": font}, {"text": "暂停", "font": font}]

func canvas_text_bindings() -> Array:
	return (_canvas_text_bindings+_touch_text_bindings).duplicate()

func visual_uid_bindings() -> Array:
	var rows: Array = []
	for node in objects.get_children():
		if node.has_meta("item_uid"): rows.append({"uid": int(node.get_meta("item_uid")), "node": str(node.get_path())})
		for uid in node.get_meta("item_uids", []): rows.append({"uid":int(uid), "node":str(node.get_path())})
	return rows

func construction_bindings() -> Array:
	var rows: Array = []
	for node in _props.values()+_walls.values():
		if node.has_method("construction_bindings"): rows.append(node.construction_bindings())
	return rows

func show_feedback(text: String):
	if is_instance_valid(feedback): feedback.text = text; _feedback_remaining = 2.8

func _process(delta):
	if current_view.get("paused", false): return
	_cosmetic_clock += delta
	for id in _jobs:
		_jobs[id].rotation = sin(_cosmetic_clock*4)*0.08
	_feedback_remaining = maxf(0, _feedback_remaining-delta)
	if is_instance_valid(feedback): feedback.visible = _feedback_remaining > 0
	if is_instance_valid(mark_layer): mark_layer.queue_redraw()
