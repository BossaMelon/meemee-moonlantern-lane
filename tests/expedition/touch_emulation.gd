extends SceneTree
## Input-only regression for touch HUD over the field. No native window required.
const Session = preload("res://game/core/game_session.gd")
const Scene = preload("res://scenes/expedition/expedition.tscn")
var g
var panel
var checks = 0
var failures: Array = []

func _initialize(): call_deferred("run")
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)

func touch(index: int, at: Vector2, down: bool):
	var event = InputEventScreenTouch.new(); event.index = index; event.position = at; event.pressed = down
	Input.parse_input_event(event)

func drag(index: int, at: Vector2):
	var event = InputEventScreenDrag.new(); event.index = index; event.position = at
	Input.parse_input_event(event)

func mouse(at: Vector2, down: bool):
	var event = InputEventMouseButton.new(); event.position = at; event.global_position = at; event.button_index = MOUSE_BUTTON_LEFT; event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0; event.pressed = down
	Input.parse_input_event(event)

func frames(): await process_frame; await process_frame

func run():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(3024,1898)
	Input.emulate_mouse_from_touch = true
	g = Session.new(23); g.command("start_expedition")
	panel = Scene.instantiate(); root.add_child(panel); panel.bind_session(g)
	await frames()
	var at: Vector2 = panel._centers().move
	touch(4,at,true); drag(4,at+Vector2(panel.touch_radius("move"),0))
	await frames()
	var held: Dictionary = g.snapshot().expedition.input
	expect(held.move_x > 0 and not held.cast,"touch movement alone never auto-casts through emulated mouse")
	expect(held.aim_x == 0 and held.aim_y == 0,"movement touch does not inject emulated mouse aim")
	touch(5,panel._centers().cast,true); await frames()
	expect(g.snapshot().expedition.input.cast,"explicit touch cast button still works")
	touch(5,panel._centers().cast,false); await frames()
	expect(not g.snapshot().expedition.input.cast and g.snapshot().expedition.input.move_x > 0,"releasing cast leaves movement without automatic attacks")
	touch(4,at,false); await frames()
	expect(g.snapshot().expedition.input.move_x == 0 and not g.snapshot().expedition.input.cast,"touch release clears actual movement and cast")
	Input.emulate_touch_from_mouse = true
	var motion = InputEventMouseMotion.new(); motion.position = at; motion.relative = Vector2(4,0); Input.parse_input_event(motion)
	mouse(at,true)
	motion = InputEventMouseMotion.new(); motion.position = at+Vector2(panel.touch_radius("move"),0); motion.relative = Vector2(panel.touch_radius("move"),0); motion.button_mask = MOUSE_BUTTON_MASK_LEFT; Input.parse_input_event(motion)
	await frames()
	expect(g.snapshot().expedition.input.cast and g.snapshot().expedition.input.move_x == 0,"physical mouse casts without activating hidden emulated touch stick")
	expect(panel.input_mode == "keyboard","emulated touch does not steal physical mouse HUD mode")
	mouse(at,false); await frames()
	expect(not g.snapshot().expedition.input.cast,"physical mouse release still stops casting")
	var file = FileAccess.open("/tmp/e01-hud-touch-emulation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"source_sha256":FileAccess.get_sha256("res://game/expedition/expedition_panel.gd"),"claims":"InputEvent-only headless check; no native/fullscreen image claim."},"\t")); file.close()
	print("E01 touch emulation: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
