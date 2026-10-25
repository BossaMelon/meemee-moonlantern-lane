extends Control
## Input adapter and renderer. All authoritative state remains in the bound session.
signal returned
signal pause_requested
signal save_requested
signal save_quit_requested
signal action_events(events: Array)
signal input_mode_changed(mode: String)
const WORLD_TINT = Color(0.82,0.88,0.88)
const EMPTY_INPUT = {"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false}
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
var last_input: Dictionary = EMPTY_INPUT.duplicate()
var _exit_pending = false
var field = Rect2()
var pause_button: Button
var save_button: Button
var save_quit_button: Button
var return_button: Button
var session_prefix = ""
var input_mode = "keyboard"
var ui_scale = 1.0
var menu_rect = Rect2()
var _paused = false
var hud_style: StyleBoxFlat
var menu_style: StyleBox
var _paper_available = false
var _hint_run_id = ""
var _hint_regions: Dictionary = {}
var _region_hint = ""
var _region_hint_until_tick = 0
var _ripple_run_id = ""
var _water_positions: Dictionary = {}
var _ripple_next_tick: Dictionary = {}
var _water_ripples: Array = []
var _input_window: Window

func _enter_tree():
	_input_window = get_window()
	if _input_window != null and not _input_window.focus_exited.is_connected(release_inputs):
		_input_window.focus_exited.connect(release_inputs)

func _exit_tree():
	if is_instance_valid(_input_window) and _input_window.focus_exited.is_connected(release_inputs):
		_input_window.focus_exited.disconnect(release_inputs)
	_input_window = null

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC","Noto Sans CJK SC","Arial"])
	hud_style = _box(Color(0.045,0.095,0.105,0.86),Color(0.72,0.65,0.43,0.48),8)
	menu_style = _box(Color("142a2b"),Color("ac9767"),10)
	# This project's effective desktop defaults have keyboard-only ui_accept.
	# Add the missing controller confirmation without replacing existing bindings.
	var confirm = InputEventJoypadButton.new()
	confirm.button_index = JOY_BUTTON_A
	if not InputMap.action_has_event("ui_accept",confirm): InputMap.action_add_event("ui_accept",confirm)
	var path = "res://assets/pixel/manifest.json"
	if FileAccess.file_exists(path): manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	var paper = _paper_box("ui_paper_panel")
	if paper != null: menu_style = paper; _paper_available = true
	pause_button = _button("暂停 / Esc",func(): release_inputs(); pause_requested.emit())
	save_button = _button("保存",func(): release_inputs(); save_requested.emit())
	save_quit_button = _button("保存退出",_request_save_quit)
	return_button = _button("返回饭店",_leave)
	resized.connect(_layout)
	_layout()
	session_prefix = "e01-%d-%d" % [Time.get_ticks_usec(),randi()]

func _button(text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",18)
	button.add_theme_color_override("font_color",Color("f3e8cf"))
	button.add_theme_color_override("font_hover_color",Color("fff2cd"))
	button.add_theme_color_override("font_focus_color",Color("fff2cd"))
	button.add_theme_stylebox_override("normal",_box(Color("203a39"),Color("65736a"),6))
	button.add_theme_stylebox_override("hover",_box(Color("35524a"),Color("bba77b"),6))
	button.add_theme_stylebox_override("pressed",_box(Color("53614b"),Color("e9cd92"),6))
	button.add_theme_stylebox_override("focus",_box(Color(0,0,0,0),Color("f4d99a"),6,2))
	var plain = _paper_box("ui_button_plain")
	var selected = _paper_box("ui_button_plain_focus")
	if plain != null and selected != null:
		button.add_theme_stylebox_override("normal",plain)
		for key in ["hover","pressed","focus"]: button.add_theme_stylebox_override(key,selected)
		for key in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]: button.add_theme_color_override(key,Color("3c382b"))
	button.pressed.connect(action)
	add_child(button)
	return button

func _box(fill: Color, border: Color, radius: int, thickness: int = 1) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(thickness)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

func _paper_box(id: String) -> StyleBoxTexture:
	var texture = _texture(id)
	if texture == null: return null
	var style = StyleBoxTexture.new()
	style.texture = texture
	var margins = manifest.get("sprites",{}).get(id,{}).get("nine_slice_margins",[6,6,6,6])
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_texture_margin(side,margins[side])
	return style

func _layout():
	if pause_button == null: return
	ui_scale = clampf(minf(size.x/1280.0,size.y/720.0),0.85,2.0)
	var scale_factor = maxf(0.1,minf(size.x/960.0,size.y/540.0))
	# Use integer source-pixel scaling when it nearly fills the viewport; otherwise
	# retain the largest exact-aspect arena with nearest sampling, never half-size it.
	var integer_source_scale = floorf(scale_factor*2.0)/2.0
	if integer_source_scale > 0 and integer_source_scale/scale_factor >= 0.97: scale_factor = integer_source_scale
	field = Rect2((size-Vector2(960,540)*scale_factor)/2.0,Vector2(960,540)*scale_factor)
	menu_rect = Rect2(Vector2.ZERO,Vector2(minf(size.x-24,420*ui_scale),minf(size.y-24,128*ui_scale+4*maxf(44,46*ui_scale))))
	menu_rect.position = (size-menu_rect.size)/2.0
	var buttons = [pause_button,save_button,save_quit_button,return_button]
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		button.add_theme_font_size_override("font_size",maxi(16,roundi(18*ui_scale)))
		button.visible = _paused or i == 0
		button.disabled = not _paused and i != 0
		if _paused:
			button.position = menu_rect.position+Vector2(24*ui_scale,68*ui_scale+i*(maxf(44,46*ui_scale)+8*ui_scale))
			button.size = Vector2(menu_rect.size.x-48*ui_scale,maxf(44,46*ui_scale))
		elif i == 0:
			button.size = Vector2((78 if input_mode == "touch" else 124)*ui_scale,maxf(44,42*ui_scale))
			button.position = Vector2(size.x-button.size.x-18*ui_scale,18*ui_scale)
		button.focus_neighbor_left = button.get_path_to(buttons[(i+3)%4])
		button.focus_neighbor_right = button.get_path_to(buttons[(i+1)%4])
		button.focus_neighbor_top = button.focus_neighbor_left
		button.focus_neighbor_bottom = button.focus_neighbor_right
		button.focus_next = button.focus_neighbor_right
		button.focus_previous = button.focus_neighbor_left
	focus_neighbor_top = get_path_to(pause_button)
	focus_neighbor_right = get_path_to(pause_button)
	pause_button.text = _pause_text(_paused)
	queue_redraw()

func _pause_text(paused: bool) -> String:
	if paused: return "继续探险"
	return {"keyboard":"暂停 · Esc","gamepad":"暂停 · Start","touch":"暂停"}[input_mode]

func set_input_mode(mode: String) -> bool:
	if mode not in ["keyboard","gamepad","touch"]: return false
	if input_mode != mode:
		input_mode = mode
		_layout()
		input_mode_changed.emit(mode)
	return true

func _detect_input_mode(event: InputEvent):
	if event.device == -1: return # Do not switch on emulated mouse/touch events.
	if event is InputEventScreenTouch or event is InputEventScreenDrag: set_input_mode("touch")
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.2: set_input_mode("gamepad")
	elif event is InputEventJoypadButton and event.pressed: set_input_mode("gamepad")
	elif event is InputEventKey and event.pressed: set_input_mode("keyboard")
	elif event is InputEventMouseButton and event.pressed: set_input_mode("keyboard")
	elif event is InputEventMouseMotion and event.relative.length_squared() > 4: set_input_mode("keyboard")

func bind_session(value):
	session = value
	_exit_pending = false
	release_inputs()
	refresh()

func _feedback(events: Array):
	for event in events:
		match event.type:
			"pickup_blocked": message = event.message
			"drop_collected": message = "采得月心菇" if event.item_id == "moonheart" else "采得星火菇"
			"enemy_staggered": message = "撞桩破绽！" if event.entity_id == "deep-elite" else "撞桩硬直，趁现在施法"
			"spore_cleared": message = "风咒吹散了孢子"

func refresh():
	if session != null:
		var view: Dictionary = session.view()
		state = view.get("expedition",{})
		_update_water_ripples()
		_region_feedback()
		if _paused != view.get("paused",false):
			_paused = view.get("paused",false)
			_layout()
		if pause_button != null: pause_button.text = _pause_text(view.get("paused",false))
	queue_redraw()

func _update_water_ripples():
	if state.get("version",1) != 2 or not state.has("player"): return
	if _ripple_run_id != state.run_id:
		_ripple_run_id = state.run_id; _water_positions.clear(); _ripple_next_tick.clear(); _water_ripples.clear()
	_water_ripples = _water_ripples.filter(func(ripple): return ripple.until_tick > state.tick)
	var actors: Array = [{"id":"player","x":state.player.x,"y":state.player.y}]
	for enemy in state.enemies:
		if enemy.hp > 0: actors.append(enemy)
	for actor in actors:
		var pos = Vector2(actor.x,actor.y)
		var moved = _water_positions.has(actor.id) and pos.distance_squared_to(_water_positions[actor.id]) > 0.25
		_water_positions[actor.id] = pos
		if not moved or state.tick < _ripple_next_tick.get(actor.id,0): continue
		for water in state.terrain.water_zones:
			if _terrain_rect(water).has_point(pos):
				_water_ripples.append({"x":pos.x,"y":pos.y,"until_tick":state.tick+12})
				_ripple_next_tick[actor.id] = state.tick+12
				if _water_ripples.size() > 4: _water_ripples.pop_front()
				break

func _region_feedback():
	if state.get("version",1) != 2 or not state.has("player"): return
	if _hint_run_id != state.run_id:
		_hint_run_id = state.run_id; _hint_regions.clear(); _region_hint = ""; _region_hint_until_tick = 0
	if state.tick < _region_hint_until_tick: return
	var pos = Vector2(state.player.x,state.player.y)
	var near_shelf = false
	for node in state.resource_nodes:
		if node.id == "shelf-patch" and pos.distance_to(Vector2(node.x,node.y)) <= 115: near_shelf = true
	var near_water = false
	for water in state.terrain.water_zones:
		if _terrain_rect(water).grow(25).has_point(pos): near_water = true
	var near_deep = false
	for enemy in state.enemies:
		if enemy.encounter_id == "deep" and pos.distance_to(Vector2(enemy.x,enemy.y)) <= 200: near_deep = true
	for region in [
		["deep",near_deep,"盾菇和投手守着深处，留意破绽。"],
		["water",near_water,"浅渠会拖慢步子，风咒能吹散孢子。"],
		["shelf",near_shelf,"绕过棚架的菇桩，可以先采一点返店。"]]:
		if region[1] and not _hint_regions.has(region[0]):
			_hint_regions[region[0]] = true
			_region_hint = region[2]; _region_hint_until_tick = state.tick+60
			return

func _command(kind: String, args: Dictionary = {}):
	if session == null: return {}
	serial += 1
	var result: Dictionary = session.command(kind,args,session_prefix+"-"+str(serial))
	if not result.get("events",[]).is_empty(): action_events.emit(result.events)
	if not result.ok: message = result.message
	_feedback(result.get("events",[]))
	refresh()
	return result

func _same_input(a: Dictionary, b: Dictionary) -> bool:
	for key in EMPTY_INPUT:
		if a.get(key,EMPTY_INPUT[key]) != b.get(key,EMPTY_INPUT[key]): return false
	return true

func _clear_device_inputs():
	keys.clear()
	touches.clear()
	joy_buttons.clear()
	sticks = {"move":Vector2.ZERO,"aim":Vector2.ZERO}
	mouse_cast = false
	mouse_aim = false
	last_input = EMPTY_INPUT.duplicate()

func release_inputs():
	var prior = last_input
	_clear_device_inputs()
	# A clear is a real command only when the authoritative held input needs it.
	# In particular, repeated host release/bind/exit callbacks must not grow requests.
	if not _exit_pending and session != null:
		var view: Dictionary = session.view()
		if view.get("phase","") == "expedition":
			var held: Dictionary = view.get("expedition",{}).get("input",prior)
			if not _same_input(held,EMPTY_INPUT): _command("expedition_input",EMPTY_INPUT.duplicate())
	queue_redraw()

func _request_save_quit():
	if _exit_pending: return
	release_inputs()
	_exit_pending = true
	save_quit_requested.emit()

func cancel_save_quit():
	# The host calls this ONLY if saving failed or the user cancelled leaving.
	_exit_pending = false
	release_inputs()
	grab_focus()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: release_inputs()

func _leave():
	release_inputs()
	var result = _command("leave_expedition")
	if result.get("ok",false): returned.emit()

func _process(delta: float):
	if _exit_pending or session == null or not is_visible_in_tree(): return
	var view: Dictionary = session.view()
	if view.get("phase","") != "expedition": return
	if view.get("paused",false):
		_clear_device_inputs()
		refresh()
		return
	var input = current_input()
	if not _same_input(input,last_input):
		var result = _command("expedition_input",input)
		if result.get("ok",false): last_input = input.duplicate(true)
	# Accumulate fractional milliseconds; don't round every rendered frame.
	frame_ms += delta*1000.0
	var elapsed = int(frame_ms)
	frame_ms -= elapsed
	if elapsed > 0:
		var result: Dictionary = session.advance(mini(elapsed,60000))
		if not result.get("events",[]).is_empty(): action_events.emit(result.events)
		_feedback(result.get("events",[]))
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
			var axis = (data.position-data.origin)/touch_radius(data.kind)
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
	return {"move":Vector2(82*ui_scale,size.y-82*ui_scale),"aim":Vector2(size.x-82*ui_scale,size.y-82*ui_scale),
		"cast":Vector2(size.x-72*ui_scale,size.y-206*ui_scale),"dodge":Vector2(size.x-202*ui_scale,size.y-72*ui_scale),
		"skill":Vector2(size.x-202*ui_scale,size.y-176*ui_scale)}

func touch_radius(kind: String) -> float:
	return (52.0 if kind in ["move","aim"] else 29.0)*ui_scale

func _hits_visible_gui(viewport_point: Vector2) -> bool:
	for button in [pause_button,save_button,save_quit_button,return_button]:
		if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled: continue
		var local = button.get_global_transform_with_canvas().affine_inverse()*viewport_point
		if Rect2(Vector2.ZERO,button.size).has_point(local): return true
	return false

func _input(event: InputEvent):
	if not is_visible_in_tree() or session == null: return
	if _exit_pending:
		get_viewport().set_input_as_handled()
		return
	var view: Dictionary = session.view()
	if view.get("phase","") != "expedition": return
	_detect_input_mode(event)
	if (event is InputEventKey and event.keycode == KEY_ESCAPE) or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START):
		get_viewport().set_input_as_handled()
		if event.pressed and not (event is InputEventKey and event.echo):
			release_inputs()
			if not view.paused: pause_button.grab_focus()
			else: grab_focus()
			pause_requested.emit()
		return
	# Paused controls belong to the GUI, never to the combat held-input buffer.
	if view.get("paused",false): return
	# OS-generated mouse/touch duplicates may still serve native GUI buttons,
	# but must not turn an overlaid movement stick into an implicit cast/aim.
	if event.device == -1 and (event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag): return
	if event is InputEventKey:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_J,KEY_SPACE,KEY_K,KEY_SHIFT,KEY_L,KEY_E]:
			if not event.echo: keys[code] = event.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _hits_visible_gui(event.position):
			mouse_aim = false
			return
		pointer = get_global_transform_with_canvas().affine_inverse()*event.position
		mouse_aim = field.has_point(pointer)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local = get_global_transform_with_canvas().affine_inverse()*event.position
		if not event.pressed:
			if mouse_cast: get_viewport().set_input_as_handled()
			mouse_cast = false
		elif _hits_visible_gui(event.position):
			mouse_cast = false
			mouse_aim = false
			return
		elif field.has_point(local):
			mouse_cast = true; mouse_aim = true; pointer = local
			grab_focus()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		var amount = event.axis_value if absf(event.axis_value) >= 0.2 else 0.0
		if event.axis == JOY_AXIS_LEFT_X: sticks.move.x = amount
		elif event.axis == JOY_AXIS_LEFT_Y: sticks.move.y = amount
		elif event.axis == JOY_AXIS_RIGHT_X: sticks.aim.x = amount; mouse_aim = false
		elif event.axis == JOY_AXIS_RIGHT_Y: sticks.aim.y = amount; mouse_aim = false
		if event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y]: get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		if event.button_index in [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X]:
			joy_buttons[event.button_index] = event.pressed
			get_viewport().set_input_as_handled()
		elif event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var local = get_global_transform_with_canvas().affine_inverse()*event.position
		if not event.pressed:
			if touches.has(event.index): get_viewport().set_input_as_handled()
			touches.erase(event.index)
		else:
			var centers = _centers()
			for kind in ["skill","cast","dodge","move","aim"]:
				if local.distance_to(centers[kind]) <= touch_radius(kind)+4*ui_scale:
					touches[event.index] = {"kind":kind,"origin":centers[kind],"position":local}
					mouse_aim = false
					get_viewport().set_input_as_handled()
					break
	elif event is InputEventScreenDrag and touches.has(event.index):
		touches[event.index].position = get_global_transform_with_canvas().affine_inverse()*event.position
		get_viewport().set_input_as_handled()
	queue_redraw()

func _texture(id: String, background: bool = false) -> Texture2D:
	if textures.has(id): return textures[id]
	var path = "res://assets/pixel/"+("backgrounds/" if background else "sprites/")+id+".png"
	if not ResourceLoader.exists(path,"Texture2D"): return null
	var texture = ResourceLoader.load(path,"Texture2D") as Texture2D
	if texture == null: return null
	textures[id] = texture
	return texture

func _sprite(id: String, position: Vector2, fallback: Color, scale_value: float = 2.0, modulate: Color = Color.WHITE):
	var texture = _texture(id)
	if texture == null:
		draw_circle(position,14.0 if scale_value == 2.0 else 24.0,fallback)
		return
	var pivot = Vector2(texture.get_width()/2.0,texture.get_height()-4.0)
	if manifest.get("sprites",{}).has(id):
		var values = manifest.sprites[id].get("pivot",[pivot.x,pivot.y])
		pivot = Vector2(values[0],values[1])
	draw_texture_rect(texture,Rect2((position-pivot*scale_value).round(),texture.get_size()*scale_value),false,modulate)

func _terrain_rect(data: Dictionary) -> Rect2:
	return Rect2(Vector2(data.x,data.y)-Vector2(data.width,data.height)*0.5,Vector2(data.width,data.height))

func _draw_terrain_floor():
	if not state.has("terrain"): return
	var routes = _texture("rain_ground_routes",true)
	if routes != null: draw_texture_rect(routes,Rect2(0,0,960,540),false,WORLD_TINT)
	var canal = _texture("rain_canal_shallow",true)
	for water in state.terrain.water_zones:
		if canal != null: draw_texture_rect(canal,_terrain_rect(water),false,WORLD_TINT)
	for ripple in _water_ripples:
		var tint = WORLD_TINT
		tint.a = clampf((ripple.until_tick-state.tick)/12.0,0,1)*0.65
		_sprite("water_ripple",Vector2(ripple.x,ripple.y),Color("71b4b1"),1.0,tint)

func _stump_visual(obstacle: Dictionary) -> Dictionary:
	var pos = Vector2(obstacle.x,obstacle.y)
	if obstacle.id == "north-west-stump": return {"id":"garden_root_log_50","position":pos,"scale":1.0,"sort_y":pos.y}
	if obstacle.id == "deep-stump": return {"id":"garden_root_log_45","position":pos,"scale":1.0,"sort_y":pos.y}
	if obstacle.shape == "circle":
		return {"id":"garden_stump","position":pos+Vector2(0,roundf(obstacle.radius*0.9)),"scale":obstacle.radius/20.0,"sort_y":pos.y+obstacle.radius}
	return {"id":"garden_stump","position":pos+Vector2(0,24),"scale":1.5,"sort_y":pos.y+obstacle.height*0.5}

func _draw_stump(obstacle: Dictionary):
	var visual = _stump_visual(obstacle)
	if _texture(visual.id) != null:
		_sprite(visual.id,visual.position,Color("675240"),visual.scale,WORLD_TINT)
	elif obstacle.shape == "circle": draw_circle(Vector2(obstacle.x,obstacle.y),obstacle.radius,Color("675240"))
	else: draw_rect(_terrain_rect(obstacle),Color("675240"))

func _draw_hazards():
	# These are ground effects. Sort their foot points within the floor pass;
	# all actors draw afterwards so the cloud/fill never paints over a body.
	var hazards: Array = state.get("hazards",[]).duplicate()
	hazards.sort_custom(func(a,b): return a.y < b.y)
	for hazard in hazards:
		var pos = Vector2(hazard.x,hazard.y)
		if hazard.state == "warning":
			draw_circle(pos,hazard.radius,Color(0.88,0.54,0.29,0.10))
			draw_arc(pos,hazard.radius,0,TAU,48,Color("ffd394"),2.5)
			var progress = 1.0-hazard.remaining_ms/800.0
			draw_arc(pos,hazard.radius-5,-PI/2,-PI/2+TAU*progress,48,Color("fff0c7"),3)
			draw_line(pos-Vector2(6,0),pos+Vector2(6,0),Color("ffd394"),2)
			draw_line(pos-Vector2(0,6),pos+Vector2(0,6),Color("ffd394"),2)
		else:
			draw_circle(pos,hazard.radius,Color(0.48,0.48,0.69,0.14))
			if _texture("spore_cloud") != null: _sprite("spore_cloud",pos+Vector2(0,16),Color("c2addd"),1.25)
			draw_arc(pos,hazard.radius,0,TAU,48,Color("c7b5df"),1.5)

func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("102326"))
	if font == null or field.size.x <= 0: return
	draw_set_transform(field.position,0,field.size/Vector2(960,540))
	var background = _texture("mushroom-garden",true)
	if background != null: draw_texture_rect(background,Rect2(0,0,960,540),false,WORLD_TINT)
	else: draw_rect(Rect2(0,0,960,540),Color("273d3f"))
	_draw_terrain_floor()
	draw_rect(Rect2(15,220,30,100),Color(0.75,0.92,0.72,0.16))
	draw_line(Vector2(28,248),Vector2(20,270),Color(0.9,0.93,0.75,0.8),2)
	draw_line(Vector2(20,270),Vector2(28,292),Color(0.9,0.93,0.75,0.8),2)
	if state.has("player"):
		_draw_hazards()
		for enemy in state.enemies:
			if enemy.hp <= 0: continue
			var pos = Vector2(enemy.x,enemy.y)
			if not enemy.telegraph.is_empty():
				var warning: Dictionary = enemy.telegraph
				if warning.shape == "ring":
					draw_arc(pos,warning.radius,0,TAU,80,Color(0.12,0.1,0.08,0.8),7)
					draw_arc(pos,warning.radius,0,TAU,80,Color("ffd08a"),3)
				elif warning.shape == "spore":
					draw_arc(pos,25,0,TAU,32,Color("dfb7e6"),2)
				else:
					var direction = Vector2(warning.direction_x,warning.direction_y)
					var points = PackedVector2Array([pos])
					for i in range(9): points.append(pos+direction.rotated(deg_to_rad(-20.0+i*5.0))*warning.radius)
					draw_colored_polygon(points,Color(1,0.46,0.2,0.28))
					points.append(pos)
					draw_polyline(points,Color("ffd08a"),2.5)
			if enemy.state == "wave": draw_arc(pos,enemy.wave_radius,0,TAU,64,Color("e9b7ff"),5)
		for drop in state.drops:
			if not drop.collected:
				var drop_pos = Vector2(drop.x,drop.y)
				draw_circle(drop_pos,14,Color(1,0.85,0.42,0.16))
				draw_arc(drop_pos,14,0,TAU,24,Color("ffe594"),1.5)
				_sprite(drop.item_id,drop_pos,Color("ffe594"),1.0)
		for node in state.get("resource_nodes",[]):
			if node.collected: continue
			var node_pos = Vector2(node.x,node.y)
			draw_circle(node_pos,17,Color(0.87,0.75,0.37,0.15))
			draw_arc(node_pos,17,0,TAU,24,Color("dfcb8c"),1.5)
			_sprite(node.item_id,node_pos,Color("ffe594"),1.2)
		var actors: Array = []
		for obstacle in state.get("terrain",{}).get("obstacles",[]):
			var item: Dictionary = obstacle.duplicate()
			item.render_stump = true
			item.sort_y = _stump_visual(item).sort_y
			actors.append(item)
		for enemy in state.enemies:
			if enemy.hp > 0: actors.append(enemy)
		actors.append(state.player)
		actors.sort_custom(func(a,b): return a.get("sort_y",a.y) < b.get("sort_y",b.y))
		for actor in actors:
			var pos = Vector2(actor.x,actor.y)
			if actor.get("render_stump",false):
				_draw_stump(actor)
			elif actor.has("kind"):
				var id = "moonheart_guard" if actor.kind == "moonheart" else "sparkcap_idle"
				if actor.kind == "moonheart" and not actor.shielded: id = "moonheart_exposed"
				elif actor.kind == "sparkcap" and actor.state == "telegraph": id = "sparkcap_windup"
				elif actor.kind == "sporecaster":
					id = "sporecaster_windup" if actor.state == "spore_windup" else ("sporecaster_release" if actor.state == "spore_release" else "sporecaster_idle")
				_sprite(id,pos,Color("ef8a63"))
				draw_rect(Rect2(pos+Vector2(-16,5),Vector2(32,4)),Color("442c45"))
				draw_rect(Rect2(pos+Vector2(-16,5),Vector2(32.0*actor.hp/(4 if actor.kind == "moonheart" else 2),4)),Color("f8ad60"))
				if actor.state == "stagger":
					draw_arc(pos,24,-PI,-PI+PI*actor.stagger_remaining_ms/1200.0,24,Color("fff0a6"),3)
					draw_string(font,pos+Vector2(-15,-43),"破绽",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("ffe3a4"))
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
					draw_arc(pos,actor.get("skill_range",120.0),0,TAU,48,Color(0.6,1,0.9,0.75),3)
					_sprite("gust_large",pos,Color("a4f0cf"))
		for projectile in state.projectiles:
			var point = Vector2(projectile.x,projectile.y)
			draw_circle(point,7,Color(0.15,0.17,0.11,0.7))
			var enemy_spore = projectile.get("owner","") == "enemy"
			draw_circle(point,5.5 if enemy_spore else 4.5,Color("c4a3df") if enemy_spore else Color("ffe99b"))
			draw_circle(point,2.3,Color("f5e4ff") if enemy_spore else Color("fffbea"))
	draw_set_transform(Vector2.ZERO)
	_draw_hud()
	if input_mode == "touch" and not _paused: _draw_touch()
	if _paused: _draw_pause()

func _text(at: Vector2, value: String, points: int, color: Color = Color("f4ead2")):
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(12,roundi(points*ui_scale)),color)

func _draw_hud():
	if not state.has("player") or state.player.is_empty(): return
	var u = ui_scale
	var inset = Vector2(18,18)*u
	draw_style_box(hud_style,Rect2(inset,Vector2(228,66)*u))
	_text(inset+Vector2(14,23)*u,"第%d日 · 巷后菇圃" % state.day,15,Color("d9c896"))
	for i in range(3):
		var center = inset+Vector2(20+i*22,46)*u
		draw_circle(center,6.5*u,Color("ecc796") if i < state.player.hp else Color("455553"))
		if i < state.player.hp: draw_circle(center+Vector2(-2,-2)*u,1.5*u,Color("fff0c8"))
	if state.player.shield: draw_arc(inset+Vector2(92,46)*u,8*u,0,TAU,24,Color("b3e3cc"),2*u)
	_text(inset+Vector2(116,51)*u,"散射魔杖" if state.weapon_id == "fan_wand" else "直线魔杖",14)
	var quality = state.get("version",1) == 2
	var seconds = floori(state.elapsed_ms/1000.0) if quality else ceili(state.remaining_ms/1000.0)
	var timer_width = 144 if quality else 104
	var timer_rect = Rect2(Vector2((size.x-timer_width*u)/2.0,18*u),Vector2(timer_width,42)*u)
	draw_style_box(hud_style,timer_rect)
	if quality: _text(timer_rect.position+Vector2(12,27)*u,"用时",12,Color("c7d4c7"))
	_text(timer_rect.position+Vector2(54 if quality else 21,29)*u,"%d:%02d" % [seconds/60,seconds%60],22)
	if quality:
		var collected = state.resource_nodes.filter(func(node): return node.collected).size()+state.drops.filter(func(drop): return drop.collected).size()
		var meal = state.get("meal_effect")
		var note = "已采 %d · 可随时返店" % collected
		if meal != null: note += " · "+("轻步" if meal.effect_id == "light_step" else "清息")+("已用" if meal.used else "待用")
		var width = minf(size.x-36*u,font.get_string_size(note,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(13*u)).x+24*u)
		var box = Rect2(Vector2((size.x-width)/2,68*u),Vector2(width,26*u))
		draw_style_box(hud_style,box)
		_text(box.position+Vector2(12,18)*u,note,13,Color("d0d8bc"))
	if not _paused:
		if input_mode != "touch":
			var hint = "WASD 移动  ·  鼠标 / 方向键 瞄准  ·  J / 空格 施法  ·  K 闪避  ·  L 风咒"
			if input_mode == "gamepad": hint = "左摇杆 移动  ·  右摇杆 瞄准  ·  A 施法  ·  B 闪避  ·  X 风咒  ·  Start 暂停"
			var width = minf(size.x-36*u,font.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(14*u)).x+32*u)
			var strip = Rect2(Vector2((size.x-width)/2,size.y-48*u),Vector2(width,30*u))
			draw_style_box(hud_style,strip)
			_text(strip.position+Vector2(16,21)*u,hint,14,Color("c7d4c7"))
		var note = "清场了，靠近拾取材料" if state.status == "cleared" else message
		if state.get("tick",0) < _region_hint_until_tick: note = _region_hint
		if note != "":
			var width = minf(size.x-36*u,font.get_string_size(note,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(16*u)).x+32*u)
			var at = Vector2((size.x-width)/2,size.y-(92 if input_mode != "touch" else 44)*u)
			draw_style_box(hud_style,Rect2(at,Vector2(width,32*u)))
			_text(at+Vector2(16,23)*u,note,16,Color("f5d89d"))

func _draw_pause():
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.015,0.04,0.045,0.65))
	draw_style_box(menu_style,menu_rect)
	var ink = Color("3c382b") if _paper_available else Color("f4ddb0")
	var secondary = Color("66624c") if _paper_available else Color("aebeb1")
	_text(menu_rect.position+Vector2(24,36)*ui_scale,"歇一歇",23,ink)
	_text(menu_rect.position+Vector2(24,56)*ui_scale,"探险已暂停，月灯巷会等你。",13,secondary)
	_text(menu_rect.position+Vector2(24,menu_rect.size.y/ui_scale-15)*ui_scale,"Esc / Start 继续  ·  材料与进度可保存",12,secondary)

func _draw_touch():
	var centers = _centers()
	for kind in centers:
		var center: Vector2 = centers[kind]
		var radius = touch_radius(kind)
		var held = touches.values().any(func(data): return data.kind == kind)
		draw_circle(center,radius,Color(0.045,0.095,0.11,0.22 if not held else 0.48))
		draw_arc(center,radius,0,TAU,48,Color(0.91,0.88,0.71,0.42 if not held else 0.9),1.5*ui_scale)
		var ink = Color(0.98,0.94,0.79,0.75)
		var r = 12*ui_scale
		if kind == "move":
			draw_line(center-Vector2(r,0),center+Vector2(r,0),ink,2*ui_scale)
			draw_line(center-Vector2(0,r),center+Vector2(0,r),ink,2*ui_scale)
		elif kind == "aim":
			draw_arc(center,8*ui_scale,0,TAU,24,ink,1.5*ui_scale)
			for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]: draw_line(center+direction*10*ui_scale,center+direction*16*ui_scale,ink,1.5*ui_scale)
		elif kind == "cast":
			draw_polyline(PackedVector2Array([center+Vector2(5,-13)*ui_scale,center+Vector2(-6,1)*ui_scale,center+Vector2(3,1)*ui_scale,center+Vector2(-5,13)*ui_scale]),ink,2.5*ui_scale)
		elif kind == "dodge":
			for x in [-7,4]: draw_polyline(PackedVector2Array([center+Vector2(x-4,-8)*ui_scale,center+Vector2(x+3,0)*ui_scale,center+Vector2(x-4,8)*ui_scale]),ink,2.5*ui_scale)
		else:
			for y in [-7,0,7]: draw_line(center+Vector2(-12,y)*ui_scale,center+Vector2(10,y-3)*ui_scale,ink,2*ui_scale)
		var label = {"move":"移动","aim":"瞄准","cast":"施法","dodge":"闪避","skill":"风咒"}[kind]
		if kind == "skill" and "gust" not in state.get("skills",[]): label = "未解锁"
		var text_size = maxi(12,roundi(12*ui_scale))
		var width = font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x
		draw_string(font,center+Vector2(-width/2,radius+16*ui_scale),label,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size,ink)
		if kind in ["move","aim"]:
			for data in touches.values():
				if data.kind == kind: draw_circle(center+(data.position-data.origin).limit_length(radius*0.72),radius*0.25,Color(0.92,0.9,0.74,0.65))
		elif state.has("player"):
			var key = {"cast":"cast_cooldown_ms","dodge":"dodge_cooldown_ms","skill":"skill_cooldown_ms"}[kind]
			var cooldown = state.player[key]
			if cooldown > 0:
				var maximum = {"cast":800 if state.weapon_id == "fan_wand" else 500,"dodge":1200,"skill":3000}[kind]
				draw_arc(center,radius-3*ui_scale,-PI/2,-PI/2+TAU*cooldown/float(maximum),40,Color(0.9,0.77,0.44,0.8),2*ui_scale)
