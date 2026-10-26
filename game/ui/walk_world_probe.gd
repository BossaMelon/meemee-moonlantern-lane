extends Node2D
## P02 disposable movement/object probe. No GameSession, economy or save access.
const Art = preload("res://game/ui/pixel_assets.gd")
const PortableFont = preload("res://game/ui/portable_font.gd")
const WORLD = Rect2(0, 0, 2400, 1120)
const SPEED = 240.0
const REACH = 110.0
const SHOP = Rect2(64, 64, 1536, 912)
const LANE = Rect2(1600, 512, 736, 288)
@export var spawn_position = Vector2(496, 460)
var player: CharacterBody2D
var camera: Camera2D
var avatar: Sprite2D
var dish: Sprite2D
var guest: Sprite2D
var objects: Node2D
var marks: Node2D
var overlay: Node2D
var hint: Label
var reaction: Label
var title: Label
var paused = false
var clock = 0.0
var keys: Dictionary = {}
var stick = Vector2.ZERO
var touch_vector = Vector2.ZERO
var touch_index = -1
var facing = Vector2(1, 1)
var walking_sprite = "meemee_idle"
var item_location = "prep"
var pickup_count = 0
var place_count = 0
var response_remaining = 0.0
var response = ""
var collisions: Array[Rect2] = []
var asset_failures: Array[String] = []
var surfaces = {
	"prep": {"name": "备餐桌", "anchor": Vector2(496, 420), "item": Vector2(496, 316)},
	"table": {"name": "窗边客席", "anchor": Vector2(1190, 480), "item": Vector2(1190, 370)}
}

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var floor_layer = Node2D.new()
	add_child(floor_layer); floor_layer.draw.connect(_draw_floor.bind(floor_layer)); floor_layer.queue_redraw()
	marks = Node2D.new(); add_child(marks); marks.draw.connect(_draw_marks)
	objects = Node2D.new(); objects.y_sort_enabled = true; add_child(objects)
	_build_walls()
	_prop("stove", Vector2(240, 240), Vector2(112, 42))
	_prop("sink", Vector2(640, 230), Vector2(80, 36))
	_prop("prep_table", Vector2(496, 360), Vector2(164, 48))
	_prop("serving_counter", Vector2(1100, 220), Vector2(170, 44))
	_prop("dining_table", Vector2(1190, 416), Vector2(150, 44))
	_prop("dining_table", Vector2(1370, 780), Vector2(150, 44))
	_prop("dining_table", Vector2(1040, 780), Vector2(150, 44))
	guest = _sprite("student_idle", Vector2(1290, 468)); objects.add_child(guest)
	player = CharacterBody2D.new(); player.name = "WalkingMeemee"; player.position = spawn_position
	player.collision_layer = 2; player.collision_mask = 1; player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape = CollisionShape2D.new(); var circle = CircleShape2D.new(); circle.radius = 15
	shape.shape = circle; player.add_child(shape)
	avatar = _sprite("meemee_idle", Vector2.ZERO); player.add_child(avatar); objects.add_child(player)
	camera = Camera2D.new(); camera.position_smoothing_enabled = false
	camera.limit_left = 0; camera.limit_top = 0; camera.limit_right = int(WORLD.end.x); camera.limit_bottom = int(WORLD.end.y)
	player.add_child(camera); camera.make_current()
	dish = _sprite("floating_pie", surfaces.prep.item); dish.z_index = 3; objects.add_child(dish)
	var canvas = CanvasLayer.new(); canvas.layer = 10; add_child(canvas)
	overlay = Node2D.new(); canvas.add_child(overlay); overlay.draw.connect(_draw_controls)
	title = _label("咩咩 · 走进小店\nWASD / 左摇杆 / 左下圆盘移动 · F / A / 右下拿放 · Esc / Start 暂停", 16)
	title.position = Vector2(20, 16); overlay.add_child(title)
	hint = _label("", 20); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; overlay.add_child(hint)
	reaction = _label("", 18); reaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; overlay.add_child(reaction)
	_update_presentation()

func _label(text: String, size: int) -> Label:
	var label = Label.new(); label.text = text
	label.add_theme_font_override("font", PortableFont.get_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("fff0c7"))
	label.add_theme_color_override("font_shadow_color", Color("201a21"))
	label.add_theme_constant_override("shadow_offset_x", 2); label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; label.focus_mode = Control.FOCUS_NONE
	return label

func _sprite(id: String, foot: Vector2) -> Sprite2D:
	var sprite = Sprite2D.new(); sprite.texture = Art.sprite(id)
	if sprite.texture == null: asset_failures.append(id)
	sprite.centered = false; sprite.scale = Vector2(2, 2); sprite.position = foot
	var pivot = Art.entry(id).get("pivot", [0, 0]); sprite.offset = -Vector2(pivot[0], pivot[1])
	return sprite

func _wall(rect: Rect2):
	collisions.append(rect)
	var body = StaticBody2D.new(); body.position = rect.get_center(); body.collision_layer = 1
	var collider = CollisionShape2D.new(); var shape = RectangleShape2D.new(); shape.size = rect.size
	collider.shape = shape; body.add_child(collider); add_child(body)

func _build_walls():
	for rect in [Rect2(64, 64, 1536, 24), Rect2(64, 64, 24, 912), Rect2(64, 952, 1536, 24), Rect2(1576, 64, 24, 448), Rect2(1576, 720, 24, 256), Rect2(1600, 512, 736, 24), Rect2(1600, 776, 736, 24), Rect2(2312, 512, 24, 288), Rect2(800, 64, 24, 376), Rect2(800, 640, 24, 336)]: _wall(rect)

func _prop(id: String, foot: Vector2, footprint: Vector2):
	_wall(Rect2(foot-Vector2(footprint.x/2, footprint.y), footprint))
	var prop = _sprite(id, foot); objects.add_child(prop)

func _draw_floor(layer: Node2D):
	layer.draw_rect(WORLD, Color("191d2a"))
	for room in [{"rect": SHOP, "tile": "floor_wood", "color": Color("5b3b31")}, {"rect": LANE, "tile": "floor_stone", "color": Color("454958")}]:
		var rect: Rect2 = room.rect; var tile = Art.sprite(room.tile)
		if tile == null: asset_failures.append(room.tile)
		layer.draw_rect(rect, room.color)
		if tile != null:
			for row in range(int(rect.size.y/32)):
				for column in range(int(rect.size.x/128)):
					var at = rect.position+Vector2(64+column*128+(64 if row%2 else 0), 16+row*32)
					layer.draw_texture_rect(tile, Rect2(at-Vector2(64, 32), Vector2(128, 64)), false)
	for rect in collisions:
		# Only room walls: furniture has its own authored sprite.
		if rect.size.x == 24 or rect.size.y == 24:
			layer.draw_rect(rect, Color("443a48")); layer.draw_line(rect.position, rect.position+Vector2(rect.size.x, 0), Color("90745c"), 4)
	for x in range(144, 1520, 128):
		var wall = Art.sprite("wall_right")
		if wall != null: layer.draw_texture_rect(wall, Rect2(Vector2(x, 28), Vector2(128, 128)), false)
	var door = Art.sprite("door")
	if door != null: layer.draw_texture_rect(door, Rect2(1552, 408, 96, 128), false)

func joystick_center() -> Vector2:
	return Vector2(96, get_viewport_rect().size.y-106)

func interact_rect() -> Rect2:
	return Rect2(get_viewport_rect().size-Vector2(164, 164), Vector2(136, 100))

func pause_rect() -> Rect2:
	return Rect2(Vector2(get_viewport_rect().size.x-108, 18), Vector2(88, 48))

func _draw_controls():
	var center = joystick_center()
	overlay.draw_circle(center, 70, Color("222338aa")); overlay.draw_arc(center, 70, 0, TAU, 40, Color("c1a57a"), 2)
	overlay.draw_circle(center+touch_vector*48, 21, Color("e9cf9ba0"))
	overlay.draw_rect(interact_rect(), Color("302c39c0")); overlay.draw_rect(interact_rect(), Color("bc9e72"), false, 2)
	overlay.draw_rect(pause_rect(), Color("302c39c0")); overlay.draw_rect(pause_rect(), Color("bc9e72"), false, 2)
	var font = PortableFont.get_font()
	overlay.draw_string(font, interact_rect().position+Vector2(30, 56), "拿 / 放", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("fff0c7"))
	overlay.draw_string(font, pause_rect().position+Vector2(19, 30), "继续" if paused else "暂停", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("fff0c7"))

func _draw_marks():
	if not is_instance_valid(player): return
	marks.draw_circle(player.position+Vector2(0, -2), 19, Color("13151c88"))
	for id in surfaces:
		var at: Vector2 = surfaces[id].anchor
		var close = player.position.distance_to(at) <= REACH
		marks.draw_arc(at, 30 if close else 18, 0, TAU, 32, Color("f4d28c") if close else Color("aa997966"), 3)
	# A short trail of light makes the carried object visibly belong to the actor.
	if item_location == "carried": marks.draw_line(player.position+Vector2(12, -24), dish.position, Color("e9cb8e88"), 2)

func _input(event: InputEvent):
	if event is InputEventKey:
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE: _toggle_pause(); return
		if event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]: keys[event.physical_keycode] = event.pressed and not paused
		if event.pressed and not event.echo and event.physical_keycode == KEY_F and not paused: _interact()
	elif event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_LEFT_X: stick.x = event.axis_value if not paused else 0.0
		if event.axis == JOY_AXIS_LEFT_Y: stick.y = event.axis_value if not paused else 0.0
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START: _toggle_pause()
		elif event.button_index == JOY_BUTTON_A and not paused: _interact()
	elif event is InputEventScreenTouch:
		if event.pressed:
			if pause_rect().has_point(event.position): _toggle_pause()
			elif not paused and interact_rect().has_point(event.position): _interact()
			elif not paused and touch_index < 0 and event.position.distance_to(joystick_center()) <= 88:
				touch_index = event.index; touch_vector = ((event.position-joystick_center())/48.0).limit_length()
		elif event.index == touch_index: touch_index = -1; touch_vector = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == touch_index and not paused:
		touch_vector = ((event.position-joystick_center())/48.0).limit_length()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _clear_input()

func _clear_input():
	keys.clear(); stick = Vector2.ZERO; touch_vector = Vector2.ZERO; touch_index = -1
	if is_instance_valid(player): player.velocity = Vector2.ZERO

func _toggle_pause():
	paused = not paused; _clear_input(); _update_presentation()

func movement() -> Vector2:
	var keyboard = Vector2(float(keys.get(KEY_D, false))-float(keys.get(KEY_A, false)), float(keys.get(KEY_S, false))-float(keys.get(KEY_W, false)))
	return (keyboard+(stick if stick.length() >= 0.18 else Vector2.ZERO)+touch_vector).limit_length()

func _physics_process(delta):
	if paused: return
	clock += delta; response_remaining = maxf(0, response_remaining-delta)
	var direction = movement()
	player.velocity = direction*SPEED; player.move_and_slide()
	if direction.length() > 0.01:
		if direction.x != 0: facing.x = signf(direction.x)
		if direction.y != 0: facing.y = signf(direction.y)
		walking_sprite = "meemee_walk_"+("n" if facing.y < 0 else "s")+("w" if facing.x < 0 else "e")
	else: walking_sprite = "meemee_idle"
	avatar.texture = Art.sprite(walking_sprite)
	var pivot = Art.entry(walking_sprite).get("pivot", [24, 59]); avatar.offset = -Vector2(pivot[0], pivot[1])
	avatar.position.y = sin(clock*15)*1.5 if direction.length() > 0.01 else 0.0
	dish.position = player.position+Vector2(36, -54)+Vector2(0, sin(clock*4)*5) if item_location == "carried" else surfaces[item_location].item
	guest.modulate = Color("ffe3ad") if response_remaining > 0 and item_location == "table" else Color.WHITE
	_update_presentation(); marks.queue_redraw(); overlay.queue_redraw()

func nearest_surface() -> String:
	var nearest = ""; var distance = REACH
	for id in surfaces:
		var value = player.position.distance_to(surfaces[id].anchor)
		if value <= distance: nearest = id; distance = value
	return nearest

func _interact():
	var target = nearest_surface()
	if target.is_empty(): response = "走近亮圈，再拿起或放下。"
	elif item_location == target:
		item_location = "carried"; pickup_count += 1; response = "餐盘轻轻浮起，跟着咩咩走。"
	elif item_location == "carried":
		item_location = target; place_count += 1
		response = "好香呀！谢谢你送过来。" if target == "table" else "餐盘回到备餐桌。"
	else: response = "这里空着。先从另一张桌边拿起餐盘。"
	response_remaining = 2.6; _update_presentation()

func _update_presentation():
	if not is_instance_valid(hint): return
	var size = get_viewport_rect().size
	hint.position = Vector2(186, size.y-78); hint.size = Vector2(maxf(100, size.x-372), 64)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var nearest = nearest_surface()
	hint.text = "已暂停 · 继续后再走走" if paused else ("靠近"+str(surfaces[nearest].name)+" · F / A 拿起" if item_location == nearest else ("F / A 放到"+str(surfaces[nearest].name) if item_location == "carried" and not nearest.is_empty() else ("带着餐盘穿过厨房门，送到右侧亮圈的客席。" if item_location == "carried" else "先靠近备餐桌拿餐盘；也可以走出右侧店门看看巷道。")))
	reaction.position = Vector2(20, 86); reaction.size = Vector2(size.x-40, 30)
	reaction.text = response if response_remaining > 0 else ""
	overlay.queue_redraw()

func probe_state() -> Dictionary:
	var dishes = objects.get_children().filter(func(node): return node is Sprite2D and node.texture == Art.sprite("floating_pie"))
	return {"position": player.position, "velocity": player.velocity, "camera_center": camera.get_screen_center_position(), "item_location": item_location, "item_position": dish.position, "item_nodes": dishes.size(), "pickups": pickup_count, "placements": place_count, "paused": paused, "clock": clock, "walking_sprite": walking_sprite, "nearby": nearest_surface(), "response": response, "asset_failures": asset_failures.duplicate()}
