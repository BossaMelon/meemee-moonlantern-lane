extends SceneTree
## Real input, positions and physics. Never mounts Main or creates a player save.
var world
var mode: String
var folder: String
var checks = 0
var failures: Array = []
var trace: Array = []
var inputs: Array = []

func _initialize():
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["keyboard", "pad", "touch"] or not args[1].is_absolute_path(): quit(2); return
	mode = args[0]; folder = args[1]
	if not DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(folder+"/walk-probe.json"): quit(2); return
	Engine.max_fps = 120
	call_deferred("run")

func expect(ok: bool, text: String):
	checks += 1
	if not ok: failures.append(text); print("FAIL ", text)

func frames(count = 3):
	for i in range(count): await process_frame

func record(name: String):
	var state = world.probe_state()
	state.case = name
	trace.append(state)

func key(code: int, down: bool):
	var event = InputEventKey.new(); event.physical_keycode = code; event.pressed = down
	inputs.append({"type": "key", "code": code, "pressed": down}); Input.parse_input_event(event)

func axis(index: int, value: float):
	var event = InputEventJoypadMotion.new(); event.device = 0; event.axis = index; event.axis_value = value
	inputs.append({"type": "axis", "axis": index, "value": value}); Input.parse_input_event(event)

func touch(at: Vector2, down: bool, index = 0):
	var event = InputEventScreenTouch.new(); event.position = at; event.pressed = down; event.index = index
	inputs.append({"type": "touch", "position": str(at), "pressed": down, "index": index})
	Input.parse_input_event(event.xformed_by(root.get_final_transform()))

func joy(index: int, down: bool):
	var event = InputEventJoypadButton.new(); event.device = 0; event.button_index = index; event.pressed = down
	inputs.append({"type": "joy_button", "button": index, "pressed": down}); Input.parse_input_event(event)

func movement(direction: Vector2):
	if mode == "keyboard":
		for pair in [[KEY_W, direction.y < 0], [KEY_S, direction.y > 0], [KEY_A, direction.x < 0], [KEY_D, direction.x > 0]]: key(pair[0], pair[1])
	elif mode == "pad": axis(JOY_AXIS_LEFT_X, direction.x); axis(JOY_AXIS_LEFT_Y, direction.y)
	elif direction == Vector2.ZERO: touch(world.joystick_center(), false)
	else:
		touch(world.joystick_center(), true)
		var event = InputEventScreenDrag.new(); event.index = 0
		event.position = world.joystick_center()+direction.normalized()*48; event.relative = direction.normalized()*48
		inputs.append({"type": "touch_drag", "position": str(event.position)})
		Input.parse_input_event(event.xformed_by(root.get_final_transform()))

func press_interact():
	if mode == "keyboard": key(KEY_F, true); await frames(1); key(KEY_F, false)
	elif mode == "pad": joy(JOY_BUTTON_A, true); await frames(1); joy(JOY_BUTTON_A, false)
	else: touch(world.interact_rect().get_center(), true, 1); await frames(1); touch(world.interact_rect().get_center(), false, 1)
	# Dish presentation settles on the real physics step, not render-frame count.
	await physics_frame; await process_frame; await frames(1)

func pause_input():
	if mode == "keyboard": key(KEY_ESCAPE, true); await frames(1); key(KEY_ESCAPE, false)
	elif mode == "pad": joy(JOY_BUTTON_START, true); await frames(1); joy(JOY_BUTTON_START, false)
	else: touch(world.pause_rect().get_center(), true, 2); await frames(1); touch(world.pause_rect().get_center(), false, 2)
	await frames()

func ticks(count: int):
	for i in range(count):
		await physics_frame
		if i%12 == 0: record("trajectory")
	await frames(1)

func drive(direction: Vector2, count: int):
	movement(direction); await ticks(count)
	var speed = world.player.velocity.length()
	movement(Vector2.ZERO); await frames()
	expect(speed <= world.SPEED+0.1, "physical speed never exceeds configured speed")

func mount(at = Vector2(496, 460)):
	if is_instance_valid(world): world.queue_free(); await frames()
	world = load("res://scenes/ui/walk_world_probe.tscn").instantiate()
	world.spawn_position = at # Separate initial-position fixtures, never runtime teleports.
	root.add_child(world); await frames(8)
	expect(world.asset_failures.is_empty(), "required character/prop assets load through imported resources")
	expect(world.player.position.distance_to(at) < 0.1, "fixture starts at declared position")

func run():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED; root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(844, 480)
	await mount()
	var art = load("res://game/ui/pixel_assets.gd")
	for id in ["meemee_walk_nw", "meemee_walk_ne", "meemee_walk_sw", "meemee_walk_se", "floor_wood", "floor_stone"]: expect(art.sprite(id) is Texture2D, "real imported asset "+id)
	var start: Vector2 = world.player.position
	await drive(Vector2.RIGHT, 24)
	var straight = world.player.position.distance_to(start)
	expect(straight > 80 and straight < 115, "real body position changes at expected walking pace")
	await mount()
	start = world.player.position
	await drive(Vector2(1, 1), 24)
	var diagonal = world.player.position.distance_to(start)
	expect(absf(diagonal-straight) < 10, "diagonal displacement is normalized")
	expect(world.WORLD.size.x > root.size.x*2, "authored connected world spans more than two test viewports")
	await mount(Vector2(940, 600))
	for pair in [[Vector2(-1, -1), "nw"], [Vector2(1, -1), "ne"], [Vector2(-1, 1), "sw"], [Vector2(1, 1), "se"]]:
		movement(pair[0]); await ticks(12)
		expect(world.walking_sprite == "meemee_walk_"+pair[1], "actual directional input selects existing walking pose "+pair[1])
		movement(Vector2.ZERO); await frames()
	if mode == "pad":
		start = world.player.position; axis(JOY_AXIS_LEFT_X, 0.12); await ticks(12); axis(JOY_AXIS_LEFT_X, 0)
		expect(world.player.position == start, "left-stick resting deadzone does not drift")

	await mount()
	var dish_id = world.dish.get_instance_id()
	var camera_start: Vector2 = world.camera.get_screen_center_position()
	await press_interact()
	expect(world.item_location == "carried" and world.pickup_count == 1, "actual nearby input picks up the one real dish")
	await drive(Vector2.RIGHT, 174)
	record("through_kitchen_door_with_dish")
	expect(world.player.position.x > 1150 and world.player.position.x < 1240, "body actually crosses kitchen doorway into customer room")
	expect(world.camera.get_screen_center_position().x > camera_start.x+400, "camera follows the moved body across the room boundary")
	expect(world.dish.position.distance_to(world.player.position) < 85, "carried dish follows current body position")
	await press_interact()
	expect(world.item_location == "table" and world.place_count == 1 and "谢谢" in world.response, "nearby placement puts dish on table and produces a visible response")
	var placed: Vector2 = world.dish.position
	record("placement_before_next_drive")
	await drive(Vector2.DOWN, 42)
	expect(world.dish.position == placed and world.item_location == "table", "placed item remains on the real table while the player walks away (before %s, after %s)" % [str(placed), str(world.dish.position)])
	await press_interact()
	expect(world.item_location == "table", "out-of-range input cannot take the table item")
	expect(world.dish.get_instance_id() == dish_id and world.probe_state().item_nodes == 1, "pickup/carry/placement never duplicates the dish node")

	await mount(Vector2(740, 300)); await drive(Vector2.RIGHT, 36)
	expect(world.player.position.x > 770 and world.player.position.x <= 785.1, "real collision blocks the solid kitchen partition")
	await mount(Vector2(496, 420)); await drive(Vector2.UP, 36)
	expect(world.player.position.y >= 374.9 and world.player.position.y < 390, "real furniture collision stops feet at the prep table")
	await mount(Vector2(1490, 610))
	camera_start = world.camera.get_screen_center_position()
	await drive(Vector2.RIGHT, 120)
	record("outside_shop_door")
	expect(world.player.position.x > 1900 and world.player.position.x < 2010, "real body crosses exterior door into connected alley")
	expect(world.camera.get_screen_center_position().x > camera_start.x+350, "camera follows into alley")
	await mount(Vector2(2260, 640)); await drive(Vector2.RIGHT, 36)
	expect(world.player.position.x <= 2297.1, "alley outer wall remains solid")
	expect(world.camera.get_screen_center_position().x <= world.WORLD.end.x-root.size.x/2.0+1, "camera remains within authored right boundary")
	await mount(Vector2(110, 500)); await drive(Vector2.LEFT, 24)
	expect(world.player.position.x >= 102.9, "outer left wall remains solid")
	expect(world.camera.get_screen_center_position().x >= root.size.x/2.0-1, "camera remains within authored left boundary")

	await mount(Vector2(940, 600)); await press_interact()
	expect(world.item_location == "prep" and world.pickup_count == 0, "interaction cannot take a distant item")
	await mount()
	movement(Vector2.RIGHT); await ticks(8); await pause_input()
	var frozen: Dictionary = world.probe_state()
	await ticks(18); await press_interact()
	expect(world.paused and world.player.position == frozen.position and world.clock == frozen.clock, "pause stops physical movement and world time")
	expect(world.item_location == frozen.item_location and world.pickup_count == frozen.pickups, "pause blocks pickup/place")
	await pause_input(); await ticks(12)
	expect(not world.paused and world.player.position == frozen.position, "resume clears held inputs instead of leaving stuck movement")
	await drive(Vector2.RIGHT, 12)
	expect(world.player.position.x > frozen.position.x+30, "fresh input moves again after resume")
	expect(Engine.time_scale == 1.0, "time scale remains one")
	var sources = {}
	for path in ["game/ui/walk_world_probe.gd", "game/ui/checks/walk_world_probe.gd", "scenes/ui/walk_world_probe.tscn"]: sources[path] = FileAccess.get_sha256("res://"+path)
	var file = FileAccess.open(folder+"/walk-probe.json", FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify({"mode": mode, "checks": checks, "failures": failures, "trace": trace, "inputs": inputs, "source_sha256": sources, "engine": Engine.get_version_info().string, "user_data_dir": OS.get_user_data_dir(), "claim": "Independent probe only: real InputEvents and CharacterBody2D collisions/camera/object state. Fresh pre-mount spawn fixtures, no runtime position writes, GameSession, economy, save/load, native window or physical-device claim."}, "  ")); file.close()
	print("WALK_PROBE ", mode, " ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
