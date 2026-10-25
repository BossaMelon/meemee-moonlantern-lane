extends SceneTree
## Synthetic typed-view component checks. No Session or gameplay acceptance.
const Panels=preload("res://game/ui/rain_night/panels.gd")
var panel
var viewport: SubViewport
var scroll: ScrollContainer
var received: Array=[]
var checks=0
var failures: Array[String]=[]
var folder="/private/tmp/p05-rain-components"

func _initialize():
	var args=OS.get_cmdline_user_args()
	if not args.is_empty(): folder=args[0]
	if not folder.begins_with("/private/tmp/"):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(folder)
	call_deferred("run")

func frames():
	for i in range(4): await process_frame

func expect(ok: bool, message: String):
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func click(id: String):
	var control=panel.get_action_control(id)
	expect(control is Button and control.is_visible_in_tree(),"visible component button "+id)
	if not control is Button: return
	scroll.ensure_control_visible(control)
	await frames()
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=control.get_global_rect().get_center()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		viewport.push_input(event,true)
		await process_frame
	await frames()

func fixture() -> Dictionary:
	var commands={}
	for kind in ["start_wave","set_menu_priority","consume","recycle","upgrade","next_day"]: commands[kind]={"enabled":true,"reason":""}
	var items=[]
	for row in [[1,"moon_stew","shelf","held"],[2,"floating_pie","shelf",null],[3,"sparkcap","bag",null],[4,"star_soup","bag",null],[5,"floating_pie","bag",null]]:
		items.append({"uid":row[0],"item_id":row[1],"location":row[2],"cost":2,"prepared_wave_id":null if row[1]=="sparkcap" else "n1-w1","temperature":row[3],"intrinsic_tags":["meal"],"effect_id":"fixture"})
	var names={"moon_stew":"炖锅","floating_pie":"浮空饼","star_soup":"星火汤","sparkcap":"星火菇","moonheart":"月心菇"}
	var inventory=[]
	for id in names: inventory.append({"item_id":id,"name":names[id]})
	var orders=[]
	for index in range(1,4):
		orders.append({"id":"n1-w%d-c01"%index,"required":["meal","quick"],"budget":25,"arrival_ms":0,"patience_ms":20000,"waited_ms":0,"status":"waiting","channel":null})
	return {"phase":"intermission","paused":false,"cash":60,"night":{"day":1,"weather":"rain","event_id":"rain_return"},"pending_meal_effect":null,"expedition":{},"items":items,"inventory":inventory,"demand_board":orders,"sales":[],"available_commands":commands,"service":{"night_id":"n1","wave_id":"n1-w1","next_wave_id":"n1-w2","wave_index":1,"status":"intermission","orders":[],"reservations":[],"menu_priority":["floating_pie","moon_stew"],"held_uids":[1]},"progression":{"owned_weapons":["bolt_wand"],"pending_unlocks":[]},"dish_income":24,"upgrades":[{"upgrade_id":"field_kit","name":"散射杖投资","description":"合法次晨生效","cost":60,"owned":false,"available":true,"reason":""}]}

func run():
	viewport=SubViewport.new()
	viewport.size=Vector2i(720,720)
	root.add_child(viewport)
	scroll=ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(scroll)
	panel=Panels.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	panel.intent_requested.connect(func(kind,args): received.append({"kind":kind,"args":args}))
	var view=fixture()
	var original=view.duplicate(true)
	panel.present(view,"forecast")
	await frames()
	for index in range(1,4): expect("1位" in panel.get_action_control("wave_summary_%d"%index).text,"forecast groups actual supplied order IDs")
	expect("雨夜1" in panel.status_line(),"weather comes from night, not legacy day3")
	var partial=view.duplicate(true)
	partial.demand_board=partial.demand_board.slice(0,1)
	panel.present(partial,"forecast")
	await frames()
	expect("预报暂未提供" in panel.get_action_control("wave_summary_2").text,"missing forecast is unknown, never invented zero customers")
	panel.present(view,"service")
	await frames()
	await click("start_wave")
	expect(received.back()=={"kind":"start_wave","args":{"wave_id":"n1-w2"}},"next wave intent preserves exact supplied ID")
	expect(view==original,"request does not mutate caller or simulate a started wave")
	panel.present(view,"menu","moon_stew")
	await frames()
	expect("保温1份" in panel.get_action_control("temperature_summary").text,"temperature counts actual instances")
	await click("priority_up_moon_stew")
	await click("menu_priority_apply")
	expect(received.back()=={"kind":"set_menu_priority","args":{"item_ids":["moon_stew","floating_pie"]}},"priority submits entire unique draft")
	expect(view.service.menu_priority==["floating_pie","moon_stew"],"priority draft never writes source view")
	var trading=view.duplicate(true)
	trading.phase="trading";trading.paused=true;trading.service.status="active"
	trading.items[1].location="reserved"
	trading.service.reservations=[{"item_uid":2,"order_id":"n1-w1-c01","channel":"floating","batch_id":null,"remaining_ms":1200}]
	panel.present(trading,"menu","floating_pie")
	await frames()
	expect(panel.get_action_control("menu_priority_apply").disabled,"paused trading cannot apply priority even if stale command flag says enabled")
	var request_count=received.size()
	await click("menu_priority_apply")
	expect(received.size()==request_count,"real disabled button cannot emit a trading priority write")
	expect("正在送餐" in panel.get_action_control("dish_uid_2").text and panel.get_action_control("dish_uid_2").get_meta("item_uid")==2,"same reserved UID is read-only and explained as currently being delivered")
	panel.present(trading,"service")
	await frames()
	expect(panel.get_action_control("start_wave")==null,"paused active service is not intermission")
	expect("1.2秒" in panel.get_action_control("reservation_2").text,"delivery progress is supplied core data")
	var shopping=view.duplicate(true)
	shopping.phase="shopping"
	panel.present(shopping,"meal")
	await frames()
	await click("consume_pie")
	expect(received.back()=={"kind":"consume","args":{"item_id":"floating_pie","quantity":1}},"meal sends typed one-portion intent")
	expect(shopping.pending_meal_effect==null,"component cannot grant a pending meal")
	shopping.pending_meal_effect={"effect_id":"light_step","source_item_uid":5,"used":false}
	panel.present(shopping,"meal")
	await frames()
	expect("#5" in panel.get_action_control("meal_state").text,"pending source UID comes from view")
	expect(panel.get_action_control("consume_pie").disabled and panel.get_action_control("consume_star_soup").disabled,"mutually exclusive pending slot blocks both foods")
	panel.present(shopping,"rare")
	await frames()
	await click("recycle_sparkcap")
	expect(received.back()=={"kind":"recycle","args":{"item_id":"sparkcap","quantity":1}},"rare material sale is an intent, not revenue")
	expect(shopping.cash==60 and shopping.items.size()==5,"rare sale component does not debit inventory or credit cash")
	var settled=view.duplicate(true)
	settled.phase="settled"
	panel.present(settled,"growth")
	await frames()
	await click("upgrade_field_kit")
	expect(received.back()=={"kind":"upgrade","args":{"upgrade_id":"field_kit"}},"growth uses real upgrade command contract")
	await click("next_morning")
	expect(received.back()=={"kind":"next_day","args":{}},"next morning is legal next_day, never practice/reset")
	expect(settled.progression.owned_weapons==["bolt_wand"],"component cannot unlock weapon before core result")
	panel.present({"phase":"shopping","paused":false},"service")
	await frames()
	expect(panel.get_action_control("rain_interface_pending")!=null and panel.get_action_control("start_wave")==null,"missing new data fails closed without legacy inference")
	var file=FileAccess.open(folder+"/component-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite":"rain-night-ui-component-fixtures","checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"fixture_claim":"Synthetic typed dictionaries; no Session, core command, time simulation, save, Q06 or gameplay claim.","input_claim":"InputEventMouseButton through actual component Buttons in headless SubViewport","source_sha256":{"game/ui/rain_night/panels.gd":FileAccess.get_sha256("res://game/ui/rain_night/panels.gd"),"game/ui/checks/rain_night_components.gd":FileAccess.get_sha256("res://game/ui/checks/rain_night_components.gd")}},"  "))
	file.close()
	print("RAIN COMPONENT checks ",checks," failures ",failures.size())
	quit(0 if failures.is_empty() else 1)
