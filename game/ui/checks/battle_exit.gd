extends "res://game/ui/checks/restaurant.gd"
## Actual product save-and-quit in a live expedition, followed by a new process.
func _initialize():
	super._initialize()
	folder=ProjectSettings.globalize_path("res://output/restaurant-ui/battle-exit")
	DirAccess.make_dir_recursive_absolute(folder)
	source_hashes["game/ui/checks/battle_exit.gd"]=FileAccess.get_sha256("res://game/ui/checks/battle_exit.gd")

func run():
	selected_routes=PackedStringArray(["battle-resume" if "--resume" in OS.get_cmdline_user_args() else "battle-exit"])
	mode="touch"
	await fresh(Vector2i(844,390))
	if not failures.is_empty(): return
	if "--resume" in OS.get_cmdline_user_args():
		ui.save_path=folder+"/expedition.json"
		var expected=JSON.parse_string(FileAccess.get_file_as_string(ui.save_path))
		await activate("load")
		expect(ui.view.phase=="expedition" and is_instance_valid(ui.battle_panel),"new process restores actual expedition route")
		var restored=JSON.parse_string(JSON.stringify(ui.game.snapshot(),"",true,true))
		if restored!=expected:
			var differences={}
			for field in expected:
				if restored[field]!=expected[field]:
					differences[field]={"before":expected[field],"after":restored[field]}
			var diff_file=FileAccess.open(folder+"/restore-differences.json",FileAccess.WRITE)
			diff_file.store_string(JSON.stringify(differences,"  "));diff_file.close()
			print("RESTORE FIELDS ",differences.keys())
		expect(restored==expected,"full paused action state survives actual process exit")
		await screenshot("expedition-restarted-844")
		write_report()
		await activate_control(ui.battle_panel.save_quit_button,"product_save_quit_again")
		expect(false,"product save-and-quit closes restarted process")
		return
	await activate("tab_gear")
	await activate("start_expedition")
	expect(is_instance_valid(ui.battle_panel) and ui.battle_panel.has_signal("save_quit_requested"),"fixed E01 provides actual product exit")
	await activate_control(ui.battle_panel.pause_button,"battle_pause")
	expect(ui.game.view().paused,"actual action pause")
	var before: Dictionary=ui.game.snapshot()
	ui.save_path=folder+"/missing-"+str(Time.get_ticks_usec())+"/cannot-save.json"
	await activate_control(ui.battle_panel.save_quit_button,"product_save_quit_failure")
	var dialog=ui.get_node_or_null("SaveFailure")
	expect(is_instance_valid(dialog) and dialog.visible,"failed save leaves engine open with visible explanation")
	expect(ui.game.snapshot().cash==before.cash and ui.game.snapshot().items==before.items,"failed save preserves actual economy")
	await RenderingServer.frame_post_draw
	if is_instance_valid(dialog):
		var image=dialog.get_texture().get_image()
		if image!=null: image.save_png(folder+"/save-failure-feedback.png")
	await key(KEY_ENTER,true)
	await key(KEY_ENTER,false)
	await frames()
	expect(not is_instance_valid(dialog) or not dialog.visible,"native confirmation dismisses save failure")
	ui.save_path=folder+"/expedition.json"
	await screenshot("expedition-before-exit-844")
	trace.append({"action":"product_save_quit_requested","path":ui.save_path,"phase":ui.game.view().phase,"paused":ui.game.view().paused})
	write_report()
	print("BATTLE EXIT checks ",checks," failures ",failures.size(),"; requesting actual product quit")
	await activate_control(ui.battle_panel.save_quit_button,"product_save_quit_success")
	expect(false,"product save-and-quit closes engine only after success")
