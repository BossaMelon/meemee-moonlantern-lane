extends SceneTree
## Review regression: actual Main tick/delivery while mouse or pad holds a button.
const Session=preload("res://game/core/game_session.gd")
var ui
var viewport: SubViewport
var failures: Array=[]
var rows: Array=[]
var checks=0
var toggles=0
var intents=0
var folder="/private/tmp/p05-service-history-hold"

func _initialize():
	if not OS.get_cmdline_user_args().is_empty(): folder=OS.get_cmdline_user_args()[0]
	if not folder.begins_with("/private/tmp/"): quit(2); return
	DirAccess.make_dir_recursive_absolute(folder)
	Engine.max_fps=120
	call_deferred("run")

func expect(value: bool, message: String):
	checks+=1
	if not value: failures.append(message)

func frames(count=3):
	for i in range(count): await process_frame

func mouse(at: Vector2, down: bool):
	var event=InputEventMouseButton.new()
	event.position=at;event.global_position=at
	event.button_index=MOUSE_BUTTON_LEFT
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed=down
	viewport.push_input(event,true)

func joy(index: int, down: bool):
	var event=InputEventJoypadButton.new()
	event.button_index=index;event.pressed=down
	viewport.push_input(event,true)

func run_case(mode: String, delivery: bool):
	# Legal real-core fixture setup before mounting Main; no writes while holding.
	var game=Session.new(23,"rain-night-v1")
	for id in ["flour","pumpkin"]: expect(game.command("buy",{"item_id":id,"quantity":5}).ok,"fixture purchase")
	for action in [["finish_shopping",{}],["craft",{"recipe_id":"floating_pie","quantity":5}],["display",{"item_id":"floating_pie","quantity":5}],["open_shop",{}]]:
		expect(game.command(action[0],action[1]).ok,"legal fixture "+action[0])
	expect(game.advance(1750).ok,"legal pre-mount delivery fixture")
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800);root.add_child(viewport)
	ui=load("res://scenes/main.tscn").instantiate();ui.game=game
	ui.save_path=folder+"/unused-%s-%s.json"%[mode,str(delivery)]
	viewport.add_child(ui)
	ui.action_completed.connect(func(_kind,_args,_result): intents+=1)
	await frames()
	var point=ui.get_action_control("world_counter").get_global_rect().get_center()
	mouse(point,true);mouse(point,false);await frames()
	var button=ui.get_action_control("service_history_toggle")
	expect(button is Button,"real history control exists during active trading")
	if not button is Button: return
	if mode=="pad":
		for i in range(30):
			button=ui.get_action_control("service_history_toggle")
			if viewport.gui_get_focus_owner()==button: break
			joy(JOY_BUTTON_DPAD_DOWN,true);await frames(1)
			joy(JOY_BUTTON_DPAD_DOWN,false);await frames(1)
		expect(viewport.gui_get_focus_owner()==button,"real D-pad reaches history control")
	else:
		ui.scroll.ensure_control_visible(button);await frames()
	if delivery:
		var deadline=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			var remaining=game.view().service.reservations.map(func(row): return int(row.remaining_ms))
			if not remaining.is_empty() and remaining.min()<=150: break
			await process_frame
	button=ui.get_action_control("service_history_toggle")
	point=button.get_global_rect().get_center()
	var instance=button.get_instance_id()
	var button_rect=button.get_global_rect()
	var before: Dictionary=game.view()
	var before_toggles=toggles
	var before_intents=intents
	button.pressed.connect(func(): toggles+=1)
	if mode=="pad": joy(JOY_BUTTON_A,true)
	else: mouse(point,true)
	var started=Time.get_ticks_msec()
	await create_timer(0.35).timeout
	var during=ui.get_action_control("service_history_toggle")
	var during_id=during.get_instance_id() if is_instance_valid(during) else -1
	var pressed_during=during.is_pressed() if is_instance_valid(during) else false
	var rect_stable=during.get_global_rect()==button_rect if is_instance_valid(during) else false
	var focused=viewport.gui_get_focus_owner()
	var focus_during=focused.get_instance_id() if is_instance_valid(focused) else -1
	if mode=="pad": joy(JOY_BUTTON_A,false)
	else: mouse(point,false)
	await frames()
	var current=ui.get_action_control("service_history_toggle")
	var after: Dictionary=game.view()
	var row={"mode":mode,"delivery_expected":delivery,"held_ms":Time.get_ticks_msec()-started,"before_instance":instance,"during_instance":during_id,"after_instance":current.get_instance_id() if is_instance_valid(current) else -1,"pressed_during":pressed_during,"rect_stable":rect_stable,"focus_during":focus_during,"focus_after":viewport.gui_get_focus_owner().get_instance_id() if viewport.gui_get_focus_owner() else -1,"toggle_count":toggles-before_toggles,"history_open":ui.rain_panels[0].history_open,"ui_economic_intents":intents-before_intents,"before_service_ms":before.service.elapsed_ms,"after_service_ms":after.service.elapsed_ms,"sales_before":before.sales.size(),"sales_after":after.sales.size()}
	rows.append(row)
	expect(row.held_ms>=250,"actual hold crosses at least 250ms")
	expect(row.before_instance==row.during_instance and row.before_instance==row.after_instance,"tick and delivery preserve the interactive Button instance")
	expect(row.pressed_during and row.rect_stable,"live updates retain pressed state and pointer target geometry")
	expect(row.toggle_count==1 and row.history_open,"held release toggles exactly once")
	expect(row.focus_during==instance and row.focus_after==instance,"mouse/pad focus survives the entire hold and toggle")
	expect(row.ui_economic_intents==0,"history toggle sends no economic command")
	expect(row.after_service_ms>row.before_service_ms and after.phase=="trading","actual business keeps advancing during the hold")
	expect(row.sales_after>row.sales_before if delivery else row.sales_after==row.sales_before,"case covers actual delivery events" if delivery else "case covers ordinary clock updates without delivery events")
	var delivered=after.service.orders.filter(func(order): return order.status=="delivered")
	expect(("送达%d"%delivered.size()) in current.text and ui.view.cash==after.cash,"rendered delivery count and HUD view update from actual events")
	var delivered_line=ui.get_action_control("service_order_"+str(delivered.back().id))
	expect(delivered_line!=null and "已送达" in delivered_line.text,"expanded history renders current actual delivery status")
	if mode=="mouse" and delivery:
		Engine.time_scale=12.0
		var deadline=Time.get_ticks_msec()+3000
		while game.view().phase=="trading" and Time.get_ticks_msec()<deadline: await process_frame
		Engine.time_scale=1.0
		expect(game.view().phase=="intermission","real phase change still replaces the live page with intermission")
		var boundary: Dictionary=game.snapshot()
		var footer=ui.get_action_control("start_wave")
		expect(footer is Button and footer.is_visible_in_tree() and not ui.scroll.is_ancestor_of(footer),"phase boundary retains the fixed visible next-wave footer")
		expect(not ui.rain_panels[0].history_open,"new phase begins with completed history folded")
		await create_timer(0.25).timeout
		expect(game.snapshot()==boundary,"intermission remains genuinely frozen")
	viewport.queue_free();await frames()

func run():
	for mode in ["mouse","pad"]:
		for delivery in [false,true]: await run_case(mode,delivery)
	var sources={}
	for path in ["game/ui/main.gd","game/ui/rain_night/panels.gd","game/ui/checks/service_history_hold.gd","game/core/rain_night_session.gd"]: sources[path]=FileAccess.get_sha256("res://"+path)
	var file=FileAccess.open(folder+"/service-history-hold.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"engine":Engine.get_version_info().string,"source_sha256":sources,"claim":"Headless actual Main/SubViewport mouse and pad InputEvents across real clock/deliveries; legal pre-mount core fixture only, no runtime test core commands or pressed emission. After the held-input case, 12x simulation checks the real intermission boundary; no native/Q06/physical-device/human-duration claim."},"  "));file.close()
	print("HISTORY HOLD ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
