extends SceneTree
## P09: real Main input and visibility; temporary save_path is not save/restore proof.
const Session = preload("res://game/core/game_session.gd")
var ui
var folder: String
var mode: String
var render = false
var checks = 0
var failures: Array = []
var observations: Array = []
var inputs: Array = []
var actions: Array = []
var images: Array = []

func _initialize():
	var args = OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] not in ["mouse", "touch", "pad"]:
		quit(2); return
	mode = args[0]; folder = args[1]; render = "--render" in args
	if not folder.is_absolute_path() or not DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(folder+"/phase-guidance.json"):
		quit(2); return
	Engine.max_fps = 60
	call_deferred("run")

func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); print("FAIL ", message)

func frames(count = 5):
	for i in range(count): await process_frame

func label_state(label: Label) -> Dictionary:
	return {"text": label.text, "visible": label.is_visible_in_tree(), "rect": str(label.get_global_rect()), "lines": label.get_line_count(), "mouse_filter": label.mouse_filter, "focus_mode": label.focus_mode}

func focus_id() -> String:
	var owner = root.gui_get_focus_owner()
	return str(owner.get_meta("action_id", "")) if owner != null else "none"

func observe(name: String):
	var intersections: Array = []
	for button in ui.world_buttons.values():
		if button.is_visible_in_tree() and ui.phase_hint.get_global_rect().intersects(button.get_global_rect()): intersections.append(str(button.get_meta("action_id")))
	observations.append({"case": name, "phase": ui.view.phase, "pending": ui.view.pending.get("id", ""), "focus": focus_id(), "sheet": ui.get_open_sheet(), "toast_remaining": ui.toast_remaining, "hint": label_state(ui.phase_hint), "caption": label_state(ui.focus_caption), "feedback": label_state(ui.feedback), "transparent_hint_rect_hotspot_intersections": intersections, "window_mode": root.mode, "window_size": str(root.size), "viewport_size": str(root.get_visible_rect().size), "ui_size": str(ui.size), "window_focused": root.has_focus(), "time_scale": Engine.time_scale})

func guidance(name: String, expected_focus: String):
	observe(name)
	expect(ui.phase_hint.is_visible_in_tree() and not ui.phase_hint.text.is_empty(), name+": current guidance is visible")
	expect(focus_id() == expected_focus, name+": focus remains on "+expected_focus)
	expect(ui.phase_hint.mouse_filter == Control.MOUSE_FILTER_IGNORE and ui.phase_hint.focus_mode == Control.FOCUS_NONE, name+": guidance neither captures input nor focus")
	var rect: Rect2 = ui.phase_hint.get_global_rect()
	expect(ui.get_global_rect().encloses(rect), name+": guidance stays inside Main")
	var lines = ui.phase_hint.get_line_count()
	var height = ui.phase_hint.get_theme_font("font").get_height(ui.phase_hint.get_theme_font_size("font_size"))
	expect(lines <= ui.phase_hint.max_lines_visible and height*lines <= rect.size.y, name+": current text fits without line clipping")
	if ui.focus_caption.is_visible_in_tree(): expect(not rect.intersects(ui.focus_caption.get_global_rect()), name+": object caption has separate space")

func picture(name: String):
	if not render: return
	await frames(8)
	expect(not ui.illustration.missing.is_visible_in_tree(), name+": actual pixel room resources are loaded")
	expect(root.has_focus(), name+": actual rendered window is focused")
	await RenderingServer.frame_post_draw
	var path = folder+"/"+name+".png"
	var result = root.get_texture().get_image().save_png(path)
	expect(result == OK, name+": engine viewport PNG saved")
	images.append({"path": path, "sha256": FileAccess.get_sha256(path), "window_focused": root.has_focus(), "window_mode": root.mode, "window_size": str(root.size)})

func move_mouse(at: Vector2):
	var event = InputEventMouseMotion.new(); event.position = at
	Input.parse_input_event(event.xformed_by(root.get_final_transform())); await frames()

func joy(index: int):
	inputs.append({"type": "joypad", "button": index})
	for down in [true, false]:
		var event = InputEventJoypadButton.new(); event.device = 0; event.button_index = index; event.pressed = down
		Input.parse_input_event(event); await frames(1)
	await frames()

func activate(id: String):
	var target = ui.get_action_control(id)
	expect(target is Button and target.is_visible_in_tree() and not target.disabled, "actual enabled input target "+id)
	if not target is Button: return
	if mode == "pad":
		for i in range(80):
			if root.gui_get_focus_owner() == target: break
			await joy(JOY_BUTTON_DPAD_DOWN)
		expect(root.gui_get_focus_owner() == target, "real D-pad reaches "+id)
		if root.gui_get_focus_owner() == target: await joy(JOY_BUTTON_A)
		return
	var at: Vector2 = target.get_global_rect().get_center()
	inputs.append({"type": mode, "target": id, "position": str(at)})
	if mode == "mouse": await move_mouse(at)
	for down in [true, false]:
		var event: InputEvent
		if mode == "touch":
			event = InputEventScreenTouch.new(); event.index = 0
		else:
			event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
		event.position = at; event.pressed = down
		Input.parse_input_event(event.xformed_by(root.get_final_transform())); await frames(1)
	await frames()

func mount(game = null, suffix = "fresh"):
	var unused = folder+"/unused-"+suffix+"-player.json"
	expect(not FileAccess.file_exists(unused) and not FileAccess.file_exists(unused+".bak"), "isolated unused save path before mount")
	ui = load("res://scenes/main.tscn").instantiate()
	if game != null: ui.game = game
	ui.save_path = unused
	root.add_child(ui)
	ui.action_completed.connect(func(kind, args, result): actions.append({"kind": kind, "args": args, "ok": result.ok}))
	await frames(8)

func special_fixture():
	# Legal pre-mount day-two boundary only. These are NOT GUI/input evidence.
	var game = Session.new(23, "rain-night-v1")
	for night in range(2):
		for kind in ["finish_shopping", "open_shop"]: expect(game.command(kind).ok, "pre-mount fixture "+kind)
		for wave in range(3):
			if wave > 0:
				expect(game.command("start_wave", {"wave_id": game.view().service.next_wave_id}).ok, "pre-mount fixture start wave")
				if night == 1: return game
			expect(game.advance(60000).ok, "pre-mount fixture finish empty wave")
		for kind in ["settle", "next_day"]: expect(game.command(kind).ok, "pre-mount fixture "+kind)
	return game

func run():
	if not render or root.mode == Window.MODE_WINDOWED:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED; root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(844, 390) if mode == "touch" else Vector2i(1440, 904)
	await mount()
	var before: Dictionary = ui.game.snapshot()
	guidance("initial_deferred_focus", "world_lane")
	expect(ui.phase_hint.text == "从巷口带回食材，再在备餐桌翻开菜谱。", "existing shopping guidance remains unchanged")
	await create_timer(3.2).timeout
	guidance("initial_after_wait", "world_lane")
	if mode == "mouse":
		await move_mouse(ui.get_action_control("world_lane").get_global_rect().get_center())
		await move_mouse(Vector2(4, 4)); guidance("mouse_away_from_door", "world_lane")
	elif mode == "touch":
		inputs.append({"type": "touch_empty", "position": "(4, 4)"})
		for down in [true, false]:
			var event = InputEventScreenTouch.new(); event.index = 0; event.position = Vector2(4, 4); event.pressed = down
			Input.parse_input_event(event.xformed_by(root.get_final_transform())); await frames(1)
		await frames(); guidance("touch_empty_preserves_default_focus", "world_lane")
	await picture("initial-guidance")
	await activate("world_journal")
	observe("journal_open")
	expect(ui.get_open_sheet() == "journal" and not ui.phase_hint.is_visible_in_tree(), "actual input opens journal and hides world guidance")
	if mode == "pad": await joy(JOY_BUTTON_B)
	else: await activate("sheet_close")
	guidance("journal_return", "world_journal")
	if mode == "mouse": await move_mouse(Vector2(4, 4)); guidance("mouse_away_after_return", "world_journal")
	expect(ui.game.snapshot() == before and actions.is_empty(), "navigation preserves full snapshot and sends no economic intent")
	await picture("journal-return-guidance")
	await activate("world_craft"); await activate("primary")
	expect(ui.view.phase == "preparation" and actions.size() == 1 and actions[0].kind == "finish_shopping" and actions[0].ok, "actual primary input changes phase exactly once")
	observe("phase_changed_with_feedback")
	expect(ui.feedback.is_visible_in_tree() and not ui.phase_hint.is_visible_in_tree(), "real short feedback keeps precedence")
	before = ui.game.snapshot()
	await create_timer(3.2).timeout
	guidance("feedback_expired", "world_craft")
	expect(not ui.feedback.is_visible_in_tree() and ui.phase_hint.text == "灶台备餐，墙上写菜单；准备好后到柜台开门。", "feedback expiry restores current preparation guidance")
	expect(ui.game.snapshot() == before and actions.size() == 1, "waiting changes neither focus, state nor intent count")
	await picture("preparation-guidance")
	expect(not FileAccess.file_exists(ui.save_path), "visibility check generated no player save")
	ui.queue_free(); await frames()
	await mount(special_fixture(), "special")
	expect(ui.view.pending.get("character_id", "") == "hagrid" and "海格" in ui.phase_hint.text, "real day-two fixture renders existing special-order guidance")
	before = ui.game.snapshot()
	var count = actions.size()
	await activate("world_counter")
	expect(ui.get_open_sheet() == "order" and not ui.phase_hint.is_visible_in_tree(), "actual counter input opens special order and hides guidance")
	if mode == "pad": await joy(JOY_BUTTON_B)
	else: await activate("sheet_close")
	guidance("special_order_return", "world_counter")
	await create_timer(0.2).timeout
	expect(ui.game.snapshot() == before and actions.size() == count and "海格" in ui.phase_hint.text, "pending special remains frozen without navigation economic intent")
	await picture("special-order-guidance")
	expect(not FileAccess.file_exists(ui.save_path), "special fixture generated no player save")
	expect(Engine.time_scale == 1.0, "time scale remains one")
	var sources = {}
	for path in ["game/ui/main.gd", "game/ui/checks/phase_guidance.gd", "game/ui/portable_font.gd"]: sources[path] = FileAccess.get_sha256("res://"+path)
	var report = {"checks": checks, "failures": failures, "mode": mode, "render": render, "observations": observations, "inputs": inputs, "actions": actions, "images": images, "source_sha256": sources, "engine": Engine.get_version_info().string, "claim": "Actual Main mouse/ScreenTouch/D-pad/A/B. No added grab_focus, button signal emission or runtime core command. Legal pre-mount special fixture is separate from input evidence. Temporary save_path only: not default-save/restore, native package or physical-device certification."}
	var file = FileAccess.open(folder+"/phase-guidance.json", FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify(report, "  ")); file.close()
	print("PHASE_GUIDANCE ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
