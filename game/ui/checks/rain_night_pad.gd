extends "res://game/ui/checks/modal_back.gd"
## Real host focus/A/B around the new meal component; setup also uses GUI input.
var actions: Array=[]

func _initialize():
	super._initialize()
	for path in ["game/ui/checks/rain_night_pad.gd","game/ui/rain_night/panels.gd","game/core/rain_night_session.gd"]:
		sources[path]=FileAccess.get_sha256("res://"+path)

func reach(id: String):
	var target=ui.get_action_control(id)
	expect(target is Button and target.is_visible_in_tree() and not target.disabled,"visible enabled pad target "+id)
	for i in range(140):
		if ui.get_viewport().gui_get_focus_owner()==target: break
		await press(JOY_BUTTON_DPAD_DOWN)
	expect(ui.get_viewport().gui_get_focus_owner()==target,"host D-pad reaches "+id)

func run():
	mount_ui()
	ui.action_completed.connect(func(kind,args,result): actions.append({"kind":kind,"args":args,"result":result}))
	await frames(15)
	await click("world_lane")
	await click("world_stall")
	await click("buy_flour")
	await click("buy_pumpkin")
	await click("sheet_close")
	await click("world_home")
	await click("world_craft")
	await click("craft_floating_pie")
	await click("sheet_close")
	await reach("world_gear")
	await press(JOY_BUTTON_A)
	expect(ui.get_open_sheet()=="gear","host A opens equipment sheet with new meal component")
	await reach("consume_pie")
	var before=actions.size()
	await press(JOY_BUTTON_A)
	expect(actions.size()==before+1 and actions.back().kind=="consume" and actions.back().result.ok,"component A issues one accepted real consume command")
	var meal=ui.game.view().pending_meal_effect
	expect(meal is Dictionary and meal.effect_id=="light_step" and meal.source_item_uid>0 and not meal.used,"real one-slot effect retains consumed source UID")
	expect("轻步" in ui.get_action_control("departure_summary").text and ("#%d"%meal.source_item_uid) in ui.get_action_control("departure_summary").text,"departure summary includes actual pending meal and its source portion")
	expect(ui.get_action_control("consume_pie").disabled and ui.get_action_control("consume_star_soup").disabled,"both meal choices disable after actual slot occupation")
	var boundary: Dictionary=ui.game.snapshot()
	await press(JOY_BUTTON_B)
	expect(ui.get_open_sheet()=="" and ui.get_viewport().gui_get_focus_owner()==ui.get_action_control("world_gear"),"component B closes once and restores real world-object focus")
	expect(ui.game.snapshot()==boundary and actions.size()==before+1,"B return preserves snapshot without another economic intent")
	write_report()
	quit(0 if failures.is_empty() else 1)

func write_report():
	var file=FileAccess.open(folder+"/rain-pad-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite":"rain-night-main-host-pad","checks":checks,"failures":failures,"trace":trace,"actions":actions,"source_sha256":sources,"engine":Engine.get_version_info().string,"input_claim":"Real InputEventJoypadButton D-pad/A/B in Main, mouse setup through GUI; headless SubViewport, not physical controller certification or Q06."},"  "))
	file.close()
