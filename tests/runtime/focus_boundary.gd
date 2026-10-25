extends "res://tests/runtime/rain_night_path.gd"
## Native lifecycle stimulus only. Never emits focus notifications or repairs input.
const ZERO_INPUT={"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false}
class FocusWitness extends Node:
	var events: Array=[]
	func _notification(what):
		if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_FOCUS_IN]:
			events.append({"notification":what,"elapsed_ms":Time.get_ticks_msec()})

var witness: FocusWitness
var focus_samples: Array=[]

func sample_boundary(label: String) -> Dictionary:
	var sample=observe_input_state()
	sample.boundary=label
	sample.application_notifications=witness.events.duplicate(true)
	var expedition: Dictionary=ui.game.view().expedition
	sample.expedition_status=expedition.status
	sample.player_hp=expedition.player.hp
	sample.player_position=[expedition.player.x,expedition.player.y]
	sample.tick=expedition.tick
	focus_samples.append(sample)
	write_report()
	return sample

func wait_focus(value: bool):
	var deadline=Time.get_ticks_msec()+5000
	while root.has_focus()!=value and Time.get_ticks_msec()<deadline: await process_frame
	await frames(3)
	expect(root.has_focus()==value,"native window focus becomes "+str(value))

func run():
	expect(stage=="focus" and DisplayServer.get_name()!="headless","focus boundary requires native display")
	if not failures.is_empty(): return
	witness=FocusWitness.new(); root.add_child(witness)
	var dimensions=config.get("size",[1280,800])
	await fresh(Vector2i(int(dimensions[0]),int(dimensions[1])),false)
	await wait_focus(true)
	if not failures.is_empty(): return
	await activate("start_expedition")
	expect(ui.game.view().phase=="expedition","real Main starts focus experiment combat")
	if not failures.is_empty(): return
	var requested={"move_x":0.0,"move_y":-1.0,"aim_x":1.0,"aim_y":0.0,"cast":true,"dodge":true,"skill":true}
	inject_combat(requested); await frames(12)
	var before=sample_boundary("held_before_native_minimize")
	expect(before.authoritative_input.move_y<0 and before.authoritative_input.cast,"actual held movement and cast precede focus loss")
	expect(ui.battle_panel.input_mode=={"mouse":"keyboard","pad":"gamepad","touch":"touch"}[mode],"actual held input selects expected HUD")
	await screenshot(mode+"-focus-held-before")
	# Public Window APIs change our own OS window, with no CUA/other-app access.
	# Notification presence is observed, not inferred from this request.
	root.mode=Window.MODE_MINIMIZED
	await wait_focus(false)
	if not failures.is_empty(): return
	var lost=sample_boundary("native_window_unfocused")
	# Restore before evaluating held-state assertions so a failure still leaves
	# a visible, normally exiting owned window and an engine screenshot.
	root.mode=Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()
	await wait_focus(true)
	if not failures.is_empty(): return
	var returned=sample_boundary("native_window_returned_without_input")
	await screenshot(mode+"-focus-returned")
	for observed in [before,lost,returned]:
		expect(observed.phase=="expedition" and observed.expedition_status=="active" and observed.player_hp>0 and not observed.paused,"focus boundary stays alive in active combat without automatic pause or return")
	expect(lost.input_sequence==before.input_sequence and returned.input_sequence==before.input_sequence,"no injected input during loss and return")
	expect(json_equal(lost.driver_cache,before.driver_cache) and json_equal(returned.driver_cache,before.driver_cache),"driver held caches remain unchanged through native focus boundary")
	expect(json_equal(lost.product_device_input,ZERO_INPUT) and json_equal(lost.authoritative_input,ZERO_INPUT),"product clears device and authoritative held input after actual native focus loss")
	expect(json_equal(returned.product_device_input,ZERO_INPUT) and json_equal(returned.authoritative_input,ZERO_INPUT),"return alone cannot resume stale held movement or cast")
	if not failures.is_empty(): return
	# Only now send physical releases and a genuinely new press.
	await release_combat()
	inject_combat(requested); await frames(3)
	var fresh_input=sample_boundary("new_press_after_physical_release")
	expect(fresh_input.authoritative_input.move_y<0 and fresh_input.authoritative_input.cast,"new physical press works after focus return")
	await release_combat(); await pause_combat()
	var frozen: Dictionary=ui.game.snapshot()
	await create_timer(0.3,true,false,true).timeout
	expect(json_equal(frozen,ui.game.snapshot()),"focus experiment pause freezes full state")
	await activate_control(ui.battle_panel.save_button,"battle_save")
	expect(json_equal(frozen,ui.game.snapshot()),"pause GUI cannot cast after focus return")
	await screenshot(mode+"-focus-paused-save")
	await expect_product_exit("focus-complete",ui.battle_panel.save_quit_button)

func write_report():
	super.write_report()
	var path=folder+"/"+attempt+"-report.json"
	var report=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not report is Dictionary: return
	report.focus_boundary_samples=focus_samples
	report.focus_stimulus="native owned Window minimize, restore and window_move_to_foreground; no notification injection or input replay"
	report.source_sha256["tests/runtime/focus_boundary.gd"]=FileAccess.get_sha256("res://tests/runtime/focus_boundary.gd")
	var file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
