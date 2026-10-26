extends RefCounted
## Volatile input only. Host sends axes to Core; this class owns no world state.
signal movement_requested(axis)
signal interact_requested
signal pause_requested
var _keys: Dictionary = {}
var _stick = Vector2.ZERO
var _touch = Vector2.ZERO
var _touch_index = -1
var _confirm_down: Dictionary = {}
var _last_axis = Vector2.ZERO

func stick_center(size: Vector2) -> Vector2: return Vector2(84, size.y-90)
func interact_rect(size: Vector2) -> Rect2: return Rect2(size-Vector2(120, 132), Vector2(96, 88))
func pause_rect(size: Vector2) -> Rect2: return Rect2(Vector2(size.x-108, 18), Vector2(88, 44))
func touch_axis() -> Vector2: return _touch

func clear():
	_keys.clear(); _stick = Vector2.ZERO; _touch = Vector2.ZERO; _touch_index = -1; _confirm_down.clear()
	_last_axis = Vector2.ZERO; movement_requested.emit(Vector2.ZERO)

func _publish():
	var keyboard = Vector2(float(_keys.get(KEY_D, false) or _keys.get(KEY_RIGHT, false))-float(_keys.get(KEY_A, false) or _keys.get(KEY_LEFT, false)), float(_keys.get(KEY_S, false) or _keys.get(KEY_DOWN, false))-float(_keys.get(KEY_W, false) or _keys.get(KEY_UP, false)))
	var axis = (keyboard+(_stick if _stick.length() >= 0.2 else Vector2.ZERO)+_touch).limit_length()
	if axis != _last_axis: _last_axis = axis; movement_requested.emit(axis)

func _confirm(id: String, pressed: bool):
	if pressed:
		if not _confirm_down.has(id): _confirm_down[id] = true; interact_requested.emit()
	else: _confirm_down.erase(id)

func handle(event: InputEvent, size: Vector2) -> bool:
	if event is InputEventKey:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			_keys[code] = event.pressed; _publish(); return true
		if code == KEY_F:
			if not event.echo: _confirm("key:F", event.pressed)
			return true
		if code == KEY_ESCAPE and event.pressed and not event.echo: pause_requested.emit(); return true
	elif event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_LEFT_X: _stick.x = event.axis_value
		elif event.axis == JOY_AXIS_LEFT_Y: _stick.y = event.axis_value
		else: return false
		_publish(); return true
	elif event is InputEventJoypadButton:
		if event.button_index == JOY_BUTTON_A: _confirm("pad:"+str(event.device), event.pressed); return true
		if event.button_index == JOY_BUTTON_START and event.pressed: pause_requested.emit(); return true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Main enables touch-to-mouse for real GUI books. The world already handles
		# the original touch; its emulated mouse companion must not act twice.
		if event.device == -1: return false
		if not event.pressed: _confirm("mouse:F", false); return false
		if pause_rect(size).has_point(event.position): pause_requested.emit(); return true
		if interact_rect(size).has_point(event.position): _confirm("mouse:F", true); return true
	elif event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			_confirm("touch:"+str(event.index), false)
			if event.index == _touch_index: _touch_index = -1; _touch = Vector2.ZERO; _publish()
			return true
		if pause_rect(size).has_point(event.position): pause_requested.emit(); return true
		if interact_rect(size).has_point(event.position): _confirm("touch:"+str(event.index), true); return true
		if _touch_index < 0 and event.position.distance_to(stick_center(size)) <= 72:
			_touch_index = event.index; _touch = ((event.position-stick_center(size))/44.0).limit_length(); _publish(); return true
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_touch = ((event.position-stick_center(size))/44.0).limit_length(); _publish(); return true
	return false
