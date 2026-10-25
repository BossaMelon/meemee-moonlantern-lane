extends "res://game/ui/checks/scene_layout.gd"
## Real controller events through the GUI; no internal navigation calls.
var intents=0

func _initialize():
	super._initialize()
	sources["game/ui/checks/modal_back.gd"]=FileAccess.get_sha256("res://game/ui/checks/modal_back.gd")

func joy(index: int, down: bool):
	var event=InputEventJoypadButton.new()
	event.button_index=index
	event.pressed=down
	ui.get_viewport().push_input(event,true)
	trace.append({"joy_button":index,"pressed":down})
	await frames(3)

func press(index: int):
	await joy(index,true)
	await joy(index,false)

func run():
	mount_ui()
	ui.action_completed.connect(func(_kind,_args,_result): intents+=1)
	await frames(15)
	var before: Dictionary=ui.game.snapshot()
	var target=ui.get_action_control("world_craft")
	for i in range(12):
		if ui.get_viewport().gui_get_focus_owner()==target: break
		await press(JOY_BUTTON_DPAD_DOWN)
	expect(ui.get_viewport().gui_get_focus_owner()==target,"real D-pad reaches visible prep table")
	await press(JOY_BUTTON_A)
	expect(ui.get_open_sheet()=="craft","real A opens actual recipe sheet")
	expect(ui.game.snapshot()==before,"opening recipe has no session intent")
	await joy(JOY_BUTTON_B,true)
	expect(ui.get_open_sheet()=="","one B press closes sheet")
	expect(ui.get_viewport().gui_get_focus_owner()==target,"B restores original world-object focus")
	await joy(JOY_BUTTON_B,false)
	expect(ui.get_open_sheet()=="" and not ui.game.view().paused,"B release does not close twice or open pause")
	expect(ui.game.snapshot()==before and intents==0,"B return preserves full snapshot and sends no economic intent")
	await press(JOY_BUTTON_B)
	expect(ui.get_open_sheet()=="pause" and ui.game.view().paused,"B from world opens pause once")
	await press(JOY_BUTTON_B)
	expect(ui.get_open_sheet()=="" and not ui.game.view().paused,"B from pause returns to world once")
	expect(ui.game.snapshot()==before and intents==0,"pause roundtrip preserves full snapshot without economic intent")
	write_report()
	quit(0 if failures.is_empty() else 1)

func write_report():
	var file=FileAccess.open(folder+"/modal-back-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite":"business-modal-controller-back","checks":checks,"failures":failures,"trace":trace,"source_sha256":sources,"engine":Engine.get_version_info().string,"economic_intents":intents,"input_claim":"real InputEventJoypadButton and MouseButton through GUI in headless SubViewport; no physical device or PNG claim"},"  "))
	file.close()
