extends Control
## Input adapter and renderer. All authoritative state remains in the bound session.
signal returned
signal pause_requested
signal save_requested
signal save_quit_requested
signal action_events(events: Array)
var session
var state: Dictionary = {}
var keys: Dictionary = {}
var sticks = {"move":Vector2.ZERO,"aim":Vector2.ZERO}
var joy_buttons: Dictionary = {}
var touches: Dictionary = {}
var pointer = Vector2.ZERO
var mouse_cast = false
var mouse_aim = false
var frame_ms = 0.0
var textures: Dictionary = {}
var manifest: Dictionary = {}
var font: SystemFont
var message = ""
var serial = 0
var last_input: Dictionary = {}
var field = Rect2()
var pause_button: Button
var save_button: Button
var save_quit_button: Button
var return_button: Button
var session_prefix = ""

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC","Noto Sans CJK SC","Arial"])
	# This project's effective desktop defaults have keyboard-only ui_accept.
	# Add the missing controller confirmation without replacing existing bindings.
	var confirm = InputEventJoypadButton.new()
	confirm.button_index = JOY_BUTTON_A
	if not InputMap.action_has_event("ui_accept",confirm): InputMap.action_add_event("ui_accept",confirm)
	var path = "res://assets/pixel/manifest.json"
	if FileAccess.file_exists(path): manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	pause_button = _button("暂停 / Esc",func(): release_inputs(); pause_requested.emit())
	save_button = _button("保存",func(): release_inputs(); save_requested.emit())
	save_quit_button = _button("保存退出",func(): release_inputs(); save_quit_requested.emit())
	return_button = _button("返回饭店",_leave)
	resized.connect(_layout)
	_layout()
	session_prefix = "e01-%d-%d" % [Time.get_ticks_usec(),randi()]

func _button(text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",18)
	button.pressed.connect(action)
	add_child(button)
	return button

func _layout():
	if pause_button == null: return
	var scale_factor = clampf(minf((size.x-24.0)/960.0,(size.y-160.0)/540.0),0.2,1.0)
	field = Rect2(Vector2((size.x-960.0*scale_factor)/2.0,62),Vector2(960,540)*scale_factor)
	var compact = size.x < 1000
	var widths = [96,64,88,88] if compact else [130,80,110,110]
	var buttons = [pause_button,save_button,save_quit_button,return_button]
	var left = size.x-12.0-24.0
	for width in widths: left -= width
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		button.add_theme_font_size_override("font_size",16 if compact else 18)
		button.position = Vector2(left,8 if compact else 12)
		button.size = Vector2(widths[i],44 if compact else 46)
		left += widths[i]+8
		button.focus_neighbor_left = button.get_path_to(buttons[(i+3)%4])
		button.focus_neighbor_right = button.get_path_to(buttons[(i+1)%4])
		button.focus_next = button.focus_neighbor_right
		button.focus_previous = button.focus_neighbor_left
	focus_neighbor_top = get_path_to(pause_button)
	focus_neighbor_right = get_path_to(pause_button)
	pause_button.text = _pause_text(session != null and session.view().get("paused",false))
	queue_redraw()

func _pause_text(paused: bool) -> String:
	if size.x < 1000: return "继续" if paused else "暂停"
	return "继续 / Esc" if paused else "暂停 / Esc"

func bind_session(value):
	session = value
	last_input = {}
	refresh()

func refresh():
	if session != null:
		var view: Dictionary = session.view()
		state = view.get("expedition",{})
		if pause_button != null: pause_button.text = _pause_text(view.get("paused",false))
	queue_redraw()

func _command(kind: String, args: Dictionary = {}):
	if session == null: return {}
	serial += 1
	var result: Dictionary = session.command(kind,args,session_prefix+"-"+str(serial))
	if not result.get("events",[]).is_empty(): action_events.emit(result.events)
	if not result.ok: message = result.message
	for event in result.get("events",[]):
		if event.type == "pickup_blocked": message = event.message
		elif event.type == "drop_collected": message = "采得月心菇" if event.item_id == "moonheart" else "采得星火菇"
	refresh()
	return result

func release_inputs():
	keys.clear()
	touches.clear()
	joy_buttons.clear()
	sticks = {"move":Vector2.ZERO,"aim":Vector2.ZERO}
	mouse_cast = false
	mouse_aim = false
	last_input = {}
	if session != null and session.view().get("phase","") == "expedition": _command("expedition_input",{})
	queue_redraw()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: release_inputs()

func _leave():
	release_inputs()
	var result = _command("leave_expedition")
	if result.get("ok",false): returned.emit()

func _process(delta: float):
	if session == null or not visible: return
	var view: Dictionary = session.view()
	if view.get("phase","") != "expedition": return
	var input = current_input()
	if input != last_input:
		var result = _command("expedition_input",input)
		if result.get("ok",false): last_input = input.duplicate(true)
	if view.get("paused",false):
		refresh()
		return
	# Accumulate fractional milliseconds; don't round every rendered frame.
	frame_ms += delta*1000.0
	var elapsed = int(frame_ms)
	frame_ms -= elapsed
	if elapsed > 0:
		var result: Dictionary = session.advance(mini(elapsed,60000))
		if not result.get("events",[]).is_empty(): action_events.emit(result.events)
		for event in result.get("events",[]):
			if event.type == "drop_collected": message = "采得月心菇" if event.item_id == "moonheart" else "采得星火菇"
			elif event.type == "pickup_blocked": message = event.message
		refresh()
		if session.view().get("phase","") != "expedition":
			release_inputs()
			returned.emit()

func _pressed(key: int) -> float:
	return 1.0 if keys.get(key,false) else 0.0

func current_input() -> Dictionary:
	var move = Vector2(_pressed(KEY_D)-_pressed(KEY_A),_pressed(KEY_S)-_pressed(KEY_W))+sticks.move
	var aim = Vector2(_pressed(KEY_RIGHT)-_pressed(KEY_LEFT),_pressed(KEY_DOWN)-_pressed(KEY_UP))+sticks.aim
	var cast = keys.get(KEY_J,false) or keys.get(KEY_SPACE,false) or mouse_cast or joy_buttons.get(JOY_BUTTON_A,false)
	var dodge = keys.get(KEY_K,false) or keys.get(KEY_SHIFT,false) or joy_buttons.get(JOY_BUTTON_B,false)
	var skill = keys.get(KEY_L,false) or keys.get(KEY_E,false) or joy_buttons.get(JOY_BUTTON_X,false)
	for data in touches.values():
		if data.kind in ["move","aim"]:
			var axis = (data.position-data.origin)/55.0
			if data.kind == "move": move += axis.limit_length(1.0)
			else: aim += axis.limit_length(1.0)
		elif data.kind == "cast": cast = true
		elif data.kind == "dodge": dodge = true
		elif data.kind == "skill": skill = true
	if mouse_aim and state.has("player"):
		var world = (pointer-field.position)/field.size*Vector2(960,540)
		aim = world-Vector2(state.player.x,state.player.y)
	move = move.limit_length(1.0)
	aim = aim.limit_length(1.0)
	return {"move_x":move.x,"move_y":move.y,"aim_x":aim.x,"aim_y":aim.y,"cast":bool(cast),"dodge":bool(dodge),"skill":bool(skill)}

func _centers() -> Dictionary:
	return {"move":Vector2(100,size.y-82),"aim":Vector2(size.x-340,size.y-82),"cast":Vector2(size.x-210,size.y-93),
		"dodge":Vector2(size.x-100,size.y-93),"skill":Vector2(size.x-155,size.y-30)}

func _input(event: InputEvent):
	if not visible or session == null or session.view().get("phase","") != "expedition": return
	if event is InputEventKey and not event.echo:
		keys[event.physical_keycode if event.physical_keycode != 0 else event.keycode] = event.pressed
		if event.pressed and event.keycode == KEY_ESCAPE: release_inputs(); pause_requested.emit()
	elif event is InputEventMouseMotion:
		pointer = get_global_transform_with_canvas().affine_inverse()*event.position
		mouse_aim = field.has_point(pointer)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local = get_global_transform_with_canvas().affine_inverse()*event.position
		if not event.pressed: mouse_cast = false
		elif field.has_point(local): mouse_cast = true; mouse_aim = true; pointer = local
	elif event is InputEventJoypadMotion:
		var amount = event.axis_value if absf(event.axis_value) >= 0.2 else 0.0
		if event.axis == JOY_AXIS_LEFT_X: sticks.move.x = amount
		elif event.axis == JOY_AXIS_LEFT_Y: sticks.move.y = amount
		elif event.axis == JOY_AXIS_RIGHT_X: sticks.aim.x = amount; mouse_aim = false
		elif event.axis == JOY_AXIS_RIGHT_Y: sticks.aim.y = amount; mouse_aim = false
	elif event is InputEventJoypadButton:
		joy_buttons[event.button_index] = event.pressed
		if event.pressed and event.button_index == JOY_BUTTON_START: release_inputs(); pause_requested.emit()
	elif event is InputEventScreenTouch:
		var local = get_global_transform_with_canvas().affine_inverse()*event.position
		if not event.pressed: touches.erase(event.index)
		else:
			var centers = _centers()
			for kind in ["skill","cast","dodge","move","aim"]:
				if local.distance_to(centers[kind]) <= (62.0 if kind in ["move","aim"] else 31.0):
					touches[event.index] = {"kind":kind,"origin":centers[kind],"position":local}
					mouse_aim = false
					break
	elif event is InputEventScreenDrag and touches.has(event.index): touches[event.index].position = get_global_transform_with_canvas().affine_inverse()*event.position
	queue_redraw()

func _texture(id: String, background: bool = false) -> Texture2D:
	if textures.has(id): return textures[id]
	var path = "res://assets/pixel/"+("backgrounds/" if background else "sprites/")+id+".png"
	if not FileAccess.file_exists(path): return null
	var image = Image.load_from_file(path)
	if image == null or image.is_empty(): return null
	var texture = ImageTexture.create_from_image(image)
	textures[id] = texture
	return texture

func _sprite(id: String, position: Vector2, fallback: Color, scale_value: float = 2.0):
	var texture = _texture(id)
	if texture == null:
		draw_circle(position,14.0 if scale_value == 2.0 else 24.0,fallback)
		return
	var pivot = Vector2(texture.get_width()/2.0,texture.get_height()-4.0)
	if manifest.get("sprites",{}).has(id):
		var values = manifest.sprites[id].get("pivot",[pivot.x,pivot.y])
		pivot = Vector2(values[0],values[1])
	draw_texture_rect(texture,Rect2((position-pivot*scale_value).round(),texture.get_size()*scale_value),false)

func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("151a31"))
	if font == null: return
	var title = "巷后菇圃 · 瞄准施法，靠近拾取"
	if state.has("player"):
		title = "第%d日  生命 %d/3  %s  %ds" % [state.day,state.player.hp,"散射杖" if state.weapon_id == "fan_wand" else "直线杖",ceili(state.remaining_ms/1000.0)]
	draw_string(font,Vector2(16,40),title,HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("ffe1a0"))
	if field.size.x <= 0: return
	draw_set_transform(field.position,0,field.size/Vector2(960,540))
	var background = _texture("mushroom-garden",true)
	if background != null: draw_texture_rect(background,Rect2(0,0,960,540),false)
	else: draw_rect(Rect2(0,0,960,540),Color("273d3f"))
	draw_rect(Rect2(15,220,30,100),Color(0.7,0.9,0.65,0.5))
	if state.has("player"):
		for enemy in state.enemies:
			if enemy.hp <= 0: continue
			var pos = Vector2(enemy.x,enemy.y)
			if not enemy.telegraph.is_empty():
				var warning: Dictionary = enemy.telegraph
				if warning.shape == "ring": draw_arc(pos,warning.radius,0,TAU,64,Color("ffb35a"),4)
				else:
					var direction = Vector2(warning.direction_x,warning.direction_y)
					var points = PackedVector2Array([pos])
					for i in range(9): points.append(pos+direction.rotated(deg_to_rad(-20.0+i*5.0))*warning.radius)
					draw_colored_polygon(points,Color(1,0.45,0.2,0.35))
			if enemy.state == "wave": draw_arc(pos,enemy.wave_radius,0,TAU,64,Color("e9b7ff"),5)
		for drop in state.drops:
			if not drop.collected: _sprite(drop.item_id,Vector2(drop.x,drop.y),Color("ffe594"),1.0)
		var actors: Array = []
		for enemy in state.enemies:
			if enemy.hp > 0: actors.append(enemy)
		actors.append(state.player)
		actors.sort_custom(func(a,b): return a.y < b.y)
		for actor in actors:
			var pos = Vector2(actor.x,actor.y)
			if actor.has("kind"):
				var id = "moonheart_guard" if actor.kind == "moonheart" else "sparkcap_idle"
				if actor.kind == "moonheart" and not actor.shielded: id = "moonheart_exposed"
				elif actor.kind == "sparkcap" and actor.state == "telegraph": id = "sparkcap_windup"
				_sprite(id,pos,Color("ef8a63"))
				draw_rect(Rect2(pos+Vector2(-16,5),Vector2(32,4)),Color("442c45"))
				draw_rect(Rect2(pos+Vector2(-16,5),Vector2(32.0*actor.hp/(4 if actor.kind == "moonheart" else 2),4)),Color("f8ad60"))
				if actor.shielded:
					var angle = Vector2(actor.direction_x,actor.direction_y).angle()
					draw_arc(pos,25,angle-PI/3,angle+PI/3,14,Color("97e9fa"),4)
			else:
				var id = "meemee_idle"
				if actor.dodge_remaining_ms > 0: id = "meemee_dodge_se" if actor.aim_x >= 0 else "meemee_dodge_sw"
				elif actor.cast_cooldown_ms > (600 if state.weapon_id == "fan_wand" else 300): id = "meemee_cast_se" if actor.aim_x >= 0 else "meemee_cast_nw"
				elif current_input().move_x != 0 or current_input().move_y != 0: id = "meemee_walk_se" if actor.aim_x >= 0 else "meemee_walk_sw"
				_sprite(id,pos,Color("c4e7e1"))
				_sprite(state.weapon_id,pos+Vector2(actor.aim_x*24,-8),Color("ffe1a0"),1.0)
				draw_line(pos,pos+Vector2(actor.aim_x,actor.aim_y)*35,Color("bce7e8"),2)
				if actor.shield: draw_arc(pos,24,0,TAU,40,Color("faf4c0"),2)
				if actor.skill_flash_ms > 0:
					draw_arc(pos,120,0,TAU,48,Color(0.6,1,0.9,0.75),3)
					_sprite("gust_large",pos,Color("a4f0cf"))
		for projectile in state.projectiles: draw_circle(Vector2(projectile.x,projectile.y),4,Color("fff1a9"))
		if state.status == "cleared": draw_string(font,Vector2(320,45),"清场！拾取材料后返回",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("fff0b0"))
	draw_set_transform(Vector2.ZERO)
	var centers = _centers()
	for kind in centers:
		var center: Vector2 = centers[kind]
		var radius = 55.0 if kind in ["move","aim"] else 29.0
		draw_circle(center,radius,Color("26394e"))
		draw_arc(center,radius,0,TAU,40,Color("b0d6d5"),2)
		var label = {"move":"移动","aim":"瞄准","cast":"施法 J","dodge":"闪避 K","skill":"风咒 L"}[kind]
		if kind == "skill" and state.has("skills") and "gust" not in state.skills: label = "未解锁"
		draw_string(font,center+Vector2(-28,6),label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("f6e6c5"))
		for data in touches.values():
			if data.kind == kind and kind in ["move","aim"]: draw_circle(center+(data.position-data.origin).limit_length(45),14,Color("b0d6d5"))
	var hint = "WASD / 左摇杆移动 · 方向键 / 右摇杆瞄准" if size.x >= 1100 else "WASD移动 · 方向键瞄准 / 双摇杆"
	draw_string(font,Vector2(185,size.y-89),hint,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e6ddbd"))
	var cooldown = ""
	if state.has("player"): cooldown = "闪避 %.1fs · 风咒 %.1fs" % [state.player.dodge_cooldown_ms/1000.0,state.player.skill_cooldown_ms/1000.0]
	draw_string(font,Vector2(185,size.y-63),cooldown,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("d7efd8"))
	draw_string(font,Vector2(185,size.y-37),message,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("ffe1a0"))
