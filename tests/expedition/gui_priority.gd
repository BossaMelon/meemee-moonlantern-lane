extends SceneTree
## Real headless Viewport mouse routing; no native window or player save writes.
const Session = preload("res://game/core/game_session.gd")
const Scene = preload("res://scenes/expedition/expedition.tscn")
var g
var panel
var checks = 0
var failures: Array = []
var pauses = 0
var saves = 0
var events: Array = []
var output = "/tmp/e01-gui-priority.json"

func _initialize():
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i] == "--output": output = args[i+1]
	call_deferred("run")

func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)

func frames(): await process_frame; await process_frame

func motion(at: Vector2, held: bool = false):
	var event = InputEventMouseMotion.new(); event.position = at; event.global_position = at; event.device = 0; event.relative = Vector2(4,0)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event,true)

func mouse(at: Vector2, down: bool):
	var event = InputEventMouseButton.new(); event.position = at; event.global_position = at; event.device = 0
	event.button_index = MOUSE_BUTTON_LEFT; event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0; event.pressed = down
	root.push_input(event,true)

func escape(down: bool):
	var event = InputEventKey.new(); event.keycode = KEY_ESCAPE; event.physical_keycode = KEY_ESCAPE; event.pressed = down
	root.push_input(event,true)

func run():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	Input.emulate_mouse_from_touch = false; Input.emulate_touch_from_mouse = false
	g = Session.new(23); g.command("start_expedition")
	panel = Scene.instantiate(); root.add_child(panel); panel.bind_session(g)
	panel.pause_requested.connect(func(): pauses += 1; g.set_paused(not g.view().paused); panel.refresh())
	panel.save_requested.connect(func(): saves += 1)
	panel.action_events.connect(func(rows): events.append_array(rows))
	await frames()
	var at: Vector2 = panel.pause_button.get_global_rect().get_center()
	expect(panel.field.has_point(at),"regression actually overlaps GUI with full arena")
	motion(at); mouse(at,true); await frames()
	expect(not g.snapshot().expedition.input.cast and not events.any(func(e): return e.type == "cast"),"pause mouse-down never starts combat casting")
	mouse(at,false); await frames()
	expect(g.view().paused and pauses == 1,"pause press/release reaches native GUI exactly once")
	if not g.view().paused: finish(); return
	var before: Dictionary = g.snapshot()
	at = panel.save_button.get_global_rect().get_center()
	motion(at); mouse(at,true); await frames(); mouse(at,false); await frames()
	expect(saves == 1 and g.view().paused,"visible paused save GUI still receives actual press/release")
	expect(g.snapshot() == before,"paused GUI does not mutate state or requests")
	escape(true); await frames(); escape(false); await frames()
	expect(not g.view().paused and pauses == 2,"keyboard pause/resume remains valid")
	at = panel.field.position+panel.field.size*Vector2(0.45,0.55)
	motion(at); mouse(at,true)
	await create_timer(0.08).timeout
	expect(g.snapshot().expedition.input.cast and events.any(func(e): return e.type == "cast"),"ordinary field press still performs actual cast")
	var pause_at: Vector2 = panel.pause_button.get_global_rect().get_center()
	motion(pause_at,true); await frames(); mouse(pause_at,false); await frames()
	expect(not g.snapshot().expedition.input.cast,"field press released over GUI still clears casting")
	expect(not g.view().paused and pauses == 2,"release over GUI cannot click a button that did not receive the press")
	finish()

func finish():
	var file = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"pauses":pauses,"saves":saves,"events":events,"state":g.snapshot(),"source_sha256":FileAccess.get_sha256("res://game/expedition/expedition_panel.gd"),"claims":"Headless real Viewport input, no native-render claim; complete requests retained."},"\t")); file.close()
	print("E01 GUI priority: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
