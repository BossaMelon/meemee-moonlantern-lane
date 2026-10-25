extends SceneTree
## Headless public-component preparation using an actual default Session view.
## No economic commands, manufactured state, main-scene or Q06/QH pass claim.
const Session=preload("res://game/core/game_session.gd")
const PANELS_PATH="res://game/ui/rain_night/panels.gd"
const Observer=preload("res://tests/runtime/quality_controls.gd")
var folder=""
var mode="mouse"
var panel
var game
var checks=0
var failures: Array=[]
var observations: Array=[]
var input_events: Array=[]
var intents: Array=[]
var world_requests: Array=[]
var focus_observations: Array=[]

func _initialize():
	var args=OS.get_cmdline_user_args()
	if args.size()!=2 or not args[0].is_absolute_path() or args[1] not in ["mouse","touch","pad"]:
		quit(2); return
	folder=args[0]; mode=args[1]
	DirAccess.make_dir_recursive_absolute(folder)
	call_deferred("run")

func expect(value: bool, message: String):
	checks+=1
	if not value: failures.append(message); push_error(message)

func frames(count: int=4):
	for _i in range(count): await process_frame

func unavailable(reason: String):
	expect(false,reason)
	var file=FileAccess.open(folder+"/component-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"kind":"quality-components-real-initial-view","checks":checks,"failures":failures,"component_checks_passed":false,"runtime_verified":false,"passed":false,"human_status":"not_assessed"},"  ")); file.close()
	quit(2)

func send(event: InputEvent):
	input_events.append({"type":event.get_class(),"event":event.as_text(),"pressed":event.is_pressed()})
	Input.parse_input_event(event)

func press_pad(button: JoyButton):
	for down in [true,false]:
		var event=InputEventJoypadButton.new(); event.button_index=button; event.pressed=down
		send(event); await process_frame

func activate(id: String):
	var button=panel.get_action_control(id)
	expect(button is Button and button.is_visible_in_tree() and not button.disabled,"actual enabled component control: "+id)
	if not button is Button or button.disabled: return
	if mode=="pad":
		# Directional controller events establish and navigate actual focus.
		# No programmatic grab_focus or keyboard shortcut on the pad route.
		if root.gui_get_focus_owner()==null: await press_pad(JOY_BUTTON_DPAD_DOWN)
		focus_observations.append({"target":id,"when":"after_initial_direction","focus_id":str(root.gui_get_focus_owner().get_meta("action_id","")) if root.gui_get_focus_owner()!=null else null})
		var attempts=0
		while root.gui_get_focus_owner()!=button and attempts<30:
			await press_pad(JOY_BUTTON_DPAD_DOWN); attempts+=1
		expect(root.gui_get_focus_owner()==button,"controller focus reached "+id)
		focus_observations.append({"target":id,"when":"after_directional_search","attempts":attempts,"focus_id":str(root.gui_get_focus_owner().get_meta("action_id","")) if root.gui_get_focus_owner()!=null else null})
		if root.gui_get_focus_owner()!=button: return
		await press_pad(JOY_BUTTON_A)
	else:
		var point=button.get_global_rect().get_center()
		expect(root.get_visible_rect().has_point(point),"component pointer lies inside logical viewport")
		for down in [true,false]:
			if mode=="mouse":
				var event=InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down
				send(event.xformed_by(root.get_final_transform()))
			else:
				var event=InputEventScreenTouch.new(); event.index=0; event.position=point; event.pressed=down
				send(event.xformed_by(root.get_final_transform()))
			await process_frame
	await frames()

func run():
	expect(DisplayServer.get_name()=="headless","component probe does not allocate a native viewport")
	if DisplayServer.get_name()!="headless": unavailable("headless component diagnostic only"); return
	if not FileAccess.file_exists(PANELS_PATH): unavailable("published P05 component dependency is not installed"); return
	root.size=Vector2i(1200,1100)
	Input.emulate_touch_from_mouse=(mode=="touch")
	game=Session.new()
	var original: Dictionary=game.snapshot()
	expect(original.get("version")==3 and original.get("profile_id")=="rain-night-v1","actual default Session is rain-night v3")
	if not failures.is_empty(): unavailable("actual default rain-night Session dependency is not installed"); return
	panel=load(PANELS_PATH).new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)
	panel.intent_requested.connect(func(kind,args): intents.append({"kind":kind,"args":args}))
	panel.world_requested.connect(func(id): world_requests.append(id))
	for section in ["forecast","service","menu","meal","rare","growth"]:
		var view: Dictionary=game.view()
		panel.present(view,section)
		await frames()
		var observation=Observer.observe(panel,section,view)
		observations.append(observation)
		expect(observation.errors.is_empty(),"published "+section+" controls accept the actual initial view: "+str(observation.errors))
		expect(game.snapshot()==original,"presenting "+section+" does not mutate the Session")
		if section=="forecast":
			for index in range(1,4):
				expect("预报暂未提供" not in panel.get_action_control("wave_summary_%d"%index).text,"actual forecast contains wave "+str(index))
		if section=="service": expect(panel.get_action_control("start_wave")==null,"shopping is not an intermission")
		if section=="meal": expect(panel.get_action_control("consume_pie").disabled and panel.get_action_control("consume_star_soup").disabled,"initial empty bag cannot grant a meal")
		if section=="rare":
			expect(panel.get_action_control("recycle_sparkcap").disabled and panel.get_action_control("recycle_moonheart").disabled,"initial missing rare ingredients cannot be sold")
			await activate("rare_keep")
			expect(world_requests==["world_storage"] and intents.is_empty(),"real keep input emits only the published world request")
		if section=="menu":
			var before=panel.get_action_control("inventory_details_toggle").text
			await activate("inventory_details_toggle")
			expect(panel.get_action_control("inventory_details_toggle").text!=before,"real detail toggle changes component presentation")
			expect(intents.is_empty() and game.snapshot()==original,"presentation toggle emits no economic intent")
	# Missing published controls must fail the observer, not fall back to legacy UI.
	var mismatch=Observer.observe(panel,"forecast",game.view())
	expect(not mismatch.errors.is_empty(),"wrong visible page fails published label lookup")
	expect(game.snapshot()==original and intents.is_empty(),"all inputs leave full initial state and requests untouched")
	var hashes={}
	for path in ["game/core/game_session.gd","game/core/rain_night_session.gd","game/ui/rain_night/panels.gd","tests/runtime/quality_controls.gd","tests/runtime/quality_components_probe.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	var bindings={}
	for action in ["ui_down","ui_up","ui_accept"]:
		bindings[action]=[]
		for event in InputMap.action_get_events(action): bindings[action].append({"event":event.as_text(),"device":event.device})
	var report={"kind":"quality-components-real-initial-view","mode":mode,"checks":checks,"failures":failures,"observations":observations,"input_events":input_events,"world_requests":world_requests,"economic_intents":intents,"focus_observations":focus_observations,"input_bindings":bindings,"initial_snapshot":original,"final_snapshot":game.snapshot(),"source_sha256":hashes,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"runtime_verified":false,"passed":false,"component_checks_passed":failures.is_empty(),"human_status":"not_assessed","limits":["Actual default Session initial view only; no economic progression, map route, save/restore or main-scene acceptance.","Standalone components do not install the main scene's focus chain or input bindings; pad failures here do not establish a main-scene regression.","Headless component inputs do not satisfy Q06/QH or native/device validation."]}
	var file=FileAccess.open(folder+"/component-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
	print("P06 ",mode," component checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
