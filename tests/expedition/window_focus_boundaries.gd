extends SceneTree
## Headless signal-boundary logic evidence. It does not simulate native OS focus.
const Model = preload("res://game/expedition/expedition_model.gd")
const Scene = preload("res://scenes/expedition/expedition.tscn")
var checks = 0
var failures: Array = []
var input_sequence = 0
var samples: Array = []
var panel
var adapter
var output = "/tmp/e02-window-focus"
class Adapter extends RefCounted:
	var phase = "expedition"
	var paused = false
	var input_commands: Array = []
	var state = Model.create(1,"window-focus",23,"bolt_wand",["gust"],false,{"ruleset":"rain-night-v1","map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null})
	func view() -> Dictionary: return {"phase":phase,"paused":paused,"expedition":Model.view(state)}
	func command(kind: String, args: Dictionary = {}, _id: String = "") -> Dictionary:
		if kind == "expedition_input":
			input_commands.append(args.duplicate(true)); return Model.set_input(state,args)
		if kind == "leave_expedition": phase = "shopping"; return Model.leave(state)
		return {"ok":false,"message":"unsupported component command","events":[]}
	func advance(ms: int) -> Dictionary:
		var result = Model.advance(state,ms,80,paused)
		if result.returned: phase = "shopping"
		return result
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)
func zero(value: Dictionary) -> bool:
	for axis in ["move_x","move_y","aim_x","aim_y"]:
		if value[axis] != 0: return false
	return not value.cast and not value.dodge and not value.skill
func send(event: InputEvent):
	input_sequence += 1
	panel.get_window().push_input(event,true)
func key(code: int):
	var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
	send(event)
func arm(mode: String):
	if mode in ["keyboard","mouse"]:
		key(KEY_W); key(KEY_K); key(KEY_L)
		if mode == "keyboard": key(KEY_RIGHT); key(KEY_J)
		else:
			var at = panel.field.position+Vector2(200,300)/Vector2(960,540)*panel.field.size
			var motion = InputEventMouseMotion.new(); motion.position = at; motion.global_position = at; motion.relative = Vector2(4,0); send(motion)
			var button = InputEventMouseButton.new(); button.position = at; button.global_position = at; button.button_index = MOUSE_BUTTON_LEFT; button.pressed = true; button.button_mask = MOUSE_BUTTON_MASK_LEFT; send(button)
	elif mode == "gamepad":
		for pair in [[JOY_AXIS_LEFT_Y,-1.0],[JOY_AXIS_RIGHT_X,1.0]]:
			var event = InputEventJoypadMotion.new(); event.axis = pair[0]; event.axis_value = pair[1]; send(event)
		for index in [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X]:
			var event = InputEventJoypadButton.new(); event.button_index = index; event.pressed = true; send(event)
	else:
		var index = 0
		for kind in ["move","aim","cast","dodge","skill"]:
			var center: Vector2 = panel._centers()[kind]
			var touch = InputEventScreenTouch.new(); touch.index = index; touch.pressed = true; touch.position = center; send(touch)
			if kind in ["move","aim"]:
				var drag = InputEventScreenDrag.new(); drag.index = index; drag.position = center+(Vector2.UP if kind == "move" else Vector2.RIGHT)*panel.touch_radius(kind); send(drag)
			index += 1
	panel._process(0.05)
func _initialize():
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i] == "--output": output = args[i+1]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")
func run():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED; root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(1280,720)
	root.gui_embed_subwindows = true
	Input.emulate_mouse_from_touch = false; Input.emulate_touch_from_mouse = false
	expect(root.has_signal("focus_exited") and root.has_signal("focus_entered"),"effective engine exposes documented Window focus signals")
	panel = Scene.instantiate(); root.add_child(panel); panel.set_process(false)
	expect(panel.get_window() == root,"Node.get_window resolves actual containing Window")
	for mode in ["keyboard","mouse","touch","gamepad"]:
		adapter = Adapter.new(); panel.bind_session(adapter)
		arm(mode)
		expect(adapter.state.input.move_y < 0 and adapter.state.input.cast and adapter.state.input.dodge and adapter.state.input.skill,"real InputEvents arm device and model "+mode)
		var held = adapter.state.input.duplicate(true)
		panel.focus_exited.emit() # A Control focus change must not be mistaken for Window focus.
		expect(adapter.state.input == held and not zero(panel.current_input()),"Control focus alone does not clear actions "+mode)
		var sequence = input_sequence; var command_count = adapter.input_commands.size(); var tick = adapter.state.tick
		root.focus_exited.emit() # Explicit signal boundary fixture, not an OS notification.
		expect(zero(panel.current_input()) and zero(adapter.state.input),"containing Window signal immediately clears local and authoritative input "+mode)
		expect(panel.keys.is_empty() and panel.touches.is_empty() and panel.joy_buttons.is_empty() and panel.sticks.move == Vector2.ZERO and panel.sticks.aim == Vector2.ZERO and not panel.mouse_cast and not panel.mouse_aim,"all device hold caches clear "+mode)
		expect(adapter.input_commands.size() == command_count+1,"only one required authoritative release command "+mode)
		expect(adapter.phase == "expedition" and not adapter.paused and adapter.state.tick == tick,"focus clear leaves phase/pause/time semantics unchanged "+mode)
		root.focus_exited.emit(); root.focus_entered.emit()
		panel._process(0.05)
		expect(input_sequence == sequence and zero(panel.current_input()) and zero(adapter.state.input),"focus return without any new input never replays holds "+mode)
		expect(adapter.input_commands.size() == command_count+1 and adapter.state.tick == tick+1 and not adapter.paused,"duplicate focus release does not spam; unpaused clock continues "+mode)
		arm(mode)
		expect(input_sequence > sequence and not zero(adapter.state.input),"fresh input works after focus return "+mode)
		root.focus_exited.emit()
		samples.append({"mode":mode,"input_sequence":input_sequence,"authoritative_input":adapter.state.input.duplicate(true),"product_device_input":panel.current_input(),"phase":adapter.phase,"paused":adapter.paused})
	# An inactive returned panel may still exist in the tree. Focus must not send
	# a new gameplay command into the shopping phase.
	adapter = Adapter.new(); panel.bind_session(adapter); arm("keyboard")
	adapter.command("leave_expedition")
	var count = adapter.input_commands.size()
	root.focus_exited.emit()
	expect(zero(panel.current_input()) and adapter.phase == "shopping" and adapter.input_commands.size() == count,"returned panel clears local cache without phase-invalid commands")
	# Removing/reparenting binds to the new actual Window, never the old one.
	root.remove_child(panel)
	expect(not root.focus_exited.is_connected(Callable(panel,"release_inputs")),"leaving tree disconnects owned Window handler")
	var other = Window.new(); other.size = Vector2i(1280,720); root.add_child(other); other.show(); other.add_child(panel); panel.set_process(false)
	adapter = Adapter.new(); panel.bind_session(adapter); arm("keyboard")
	expect(panel.get_window() == other,"re-entered panel resolves its new containing Window")
	var held = adapter.state.input.duplicate(true)
	root.focus_exited.emit()
	expect(adapter.state.input == held and not zero(panel.current_input()),"old Window no longer controls reparented panel")
	other.focus_exited.emit()
	expect(zero(panel.current_input()) and zero(adapter.state.input),"new containing Window owns release")
	other.remove_child(panel)
	expect(not other.focus_exited.is_connected(Callable(panel,"release_inputs")),"new Window handler also disconnects on exit")
	panel.free(); other.queue_free()
	var report = {"kind":"headless-window-signal-component","scope":"Signal-boundary logic, not native OS minimize/restore or complete Q06. Actual native recheck belongs to P06.","engine":Engine.get_version_info(),"checks":checks,"failures":failures,"samples":samples,"input_sequence":input_sequence,"source_sha256":FileAccess.get_sha256("res://game/expedition/expedition_panel.gd"),"official_contract":["https://docs.godotengine.org/en/4.7/classes/class_window.html#class-window-signal-focus-exited","https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-method-get-window"]}
	var file = FileAccess.open(output+"/report.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  "))
	print("E02 Window focus signals: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
