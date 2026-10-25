extends SceneTree
## Structural preview: real visible world entrances and InputEvents, no core commands.
var ui
var failures: Array[String]=[]
var trace: Array=[]
var folder="/private/tmp/p02-scene-preview"
var checks=0
var sources={}

func _initialize():
	var args=OS.get_cmdline_user_args()
	if not args.is_empty(): folder=args[0]
	if not folder.begins_with("/private/tmp/"):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(folder)
	for path in ["game/ui/main.gd","game/ui/shop_canvas.gd","game/ui/pixel_assets.gd","game/ui/checks/scene_preview.gd","game/core/game_session.gd","game/expedition/expedition_panel.gd","assets/pixel/manifest.json"]:
		sources[path]=FileAccess.get_sha256("res://"+path)
	call_deferred("run")

func expect(value: bool, text: String):
	checks+=1
	if not value:
		failures.append(text)
		push_error(text)
		write_report()
		quit(1)

func frames(count=5):
	for i in range(count): await process_frame

func click(id: String):
	var button: Button=ui.get_action_control(id)
	expect(is_instance_valid(button) and button.is_visible_in_tree(),"actual visible control "+id)
	if not is_instance_valid(button): return
	expect(not button.disabled,"enabled control "+id)
	if ui.scroll.is_ancestor_of(button):
		ui.scroll.ensure_control_visible(button)
		await frames()
	var rect=button.get_global_rect()
	expect(Rect2(Vector2.ZERO,ui.size).encloses(rect),"virtual viewport encloses "+id+" "+str(rect))
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=rect.get_center()
		event.global_position=event.position
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event,true)
		await process_frame
	await frames()
	trace.append({"id":id,"rect_virtual":str(rect),"sheet":ui.get_open_sheet(),"world":ui.get_world_view(),"phase":ui.game.view().phase})
	print("SCENE INPUT ",id," => ",ui.get_open_sheet()," ",ui.game.view().phase)

func screenshot(name: String):
	print("CAPTURE begin ",name)
	await frames()
	print("CAPTURE frames ",name)
	await RenderingServer.frame_post_draw
	print("CAPTURE rendered ",name)
	var image=root.get_texture().get_image()
	image.save_png(folder+"/"+name+".png")
	trace.append({"screenshot":name,"png_size":str(image.get_size()),"window_size":str(root.size),"virtual_ui_size":str(ui.size),"window_mode":root.mode,"display_mode":DisplayServer.window_get_mode(root.get_window_id()),"screen_size":str(DisplayServer.screen_get_size(root.current_screen)),"content_scale_size":str(root.content_scale_size),"viewport_visible_rect":str(root.get_visible_rect()),"viewport_texture_size":str(root.get_texture().get_size()),"display_server":DisplayServer.get_name(),"renderer_setting":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"adapter":RenderingServer.get_video_adapter_name()})
	write_report()

func run():
	await frames(30)
	ui=load("res://scenes/main.tscn").instantiate()
	ui.save_path=folder+"/preview-save.json"
	root.add_child(ui)
	await frames(15)
	var art=load("res://game/ui/pixel_assets.gd")
	for id in ["world_recipe_book","world_menu_board","world_order_note","world_ledger","ui_paper_panel","ui_button_plain","ui_button_plain_focus","ui_day","ui_coin","ui_pause"]:
		expect(art.sprite(id)!=null,"published A01 asset actually loaded: "+id)
	if "--windowed" not in OS.get_cmdline_args():
		expect(root.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN],"official fullscreen flag produced actual fullscreen Window mode")
	expect(ui.get_open_sheet()=="","world is the default screen")
	await screenshot("01-room-world")
	await click("world_lane")
	expect(ui.get_world_view()=="lane","actual threshold opens lane")
	await screenshot("02-lane-stall")
	await click("world_stall")
	expect(ui.get_open_sheet()=="shopping","actual stall opens purchases")
	await click("batch_3")
	await click("buy_flour")
	await click("buy_pumpkin")
	await screenshot("03-stall-paper")
	await click("primary")
	expect(ui.game.view().phase=="preparation" and ui.get_open_sheet()=="","shopping completes back in room")
	await click("world_craft")
	expect(ui.get_open_sheet()=="craft","actual prep table opens recipe book")
	await click("craft_floating_pie")
	await screenshot("04-recipe-book")
	await click("sheet_close")
	expect(root.gui_get_focus_owner()==ui.get_action_control("world_craft"),"close returns focus to actual prep table")
	await screenshot("05-cooking-world-focus")
	await click("world_menu")
	await click("display_floating_pie")
	await screenshot("06-menu-board")
	await click("sheet_close")
	await click("world_counter")
	await click("primary")
	expect(ui.game.view().phase=="trading" and ui.get_open_sheet()=="","actual counter starts business and returns world")
	await screenshot("07-trading-world")
	await click("pause")
	expect(ui.game.view().paused and ui.get_open_sheet()=="pause","pause owns save and exit controls")
	await screenshot("08-pause-sheet")
	await click("resume")
	for i in range(40):
		if not ui.game.view().pending.is_empty(): break
		await create_timer(0.1).timeout
	expect(not ui.game.view().pending.is_empty(),"real business clock reaches special guest")
	await click("world_customer")
	expect(ui.get_open_sheet()=="order","actual customer opens order paper")
	await screenshot("09-order-paper")
	await click("fulfill_floating_pie")
	expect(ui.game.view().pending.is_empty() and ui.get_open_sheet()=="","actual stocked meal fulfills request and returns world")
	await screenshot("10-served-world")
	await click("pause")
	write_report()
	ui.tree_exiting.connect(func():
		expect(FileAccess.file_exists(ui.save_path),"product save quit writes only isolated preview save")
		write_report())
	await click("quit")
	expect(false,"product save quit must close engine")

func write_report():
	var file=FileAccess.open(folder+"/preview-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"trace":trace,"source_sha256":sources,"engine":Engine.get_version_info().string,"input_claim":"InputEventMouseButton through Viewport.push_input in actual virtual viewport coordinates; not physical input certification","command_args":OS.get_cmdline_args()},"  "))
	file.close()
