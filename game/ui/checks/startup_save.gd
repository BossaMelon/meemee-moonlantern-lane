extends "res://game/ui/checks/restaurant.gd"
## Fixture setup mirrors the independent review. Product paths use real input.
## Always pass a fresh absolute /tmp directory; never uses the player's user://.
var scenario = ""
var before_files: Dictionary = {}

func _initialize():
	super._initialize()
	var args=OS.get_cmdline_user_args()
	if args.size()!=2 or not args[0].begins_with("/private/tmp/"):
		push_error("Expected fresh /private/tmp/... directory and scenario")
		quit(2)
		return
	folder=args[0]
	scenario=args[1]
	DirAccess.make_dir_recursive_absolute(folder)
	source_hashes["game/ui/checks/startup_save.gd"]=FileAccess.get_sha256("res://game/ui/checks/startup_save.gd")

func write_json(path: String, value):
	var file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  ",true,true));file.close()

func hashes() -> Dictionary:
	var result={}
	for suffix in ["",".bak"]:
		var path=folder+"/progress.json"+suffix
		result[suffix]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return result

func run():
	selected_routes=PackedStringArray([scenario])
	mode="mouse"
	if scenario=="setup":
		var fixture=ui_session_fixture()
		expect(fixture.snapshot().day==2 and fixture.snapshot().cash==56,"independent reviewer day2/56 fixture")
		expect(fixture.save_to(folder+"/progress.json").ok,"valid primary and backup created in isolated fixture")
		write_json(folder+"/expected.json",fixture.snapshot())
		write_report()
		quit(0 if failures.is_empty() else 1)
		return
	before_files=hashes()
	root.size=Vector2i(1280,800)
	ui=Main.instantiate()
	ui.game=load("res://game/core/game_session.gd").new(7,"rain-night-v1")
	ui.save_path=folder+"/progress.json"
	root.add_child(ui)
	await frames(12)
	var protected=scenario.begins_with("invalid") or scenario.begins_with("unsupported")
	if protected:
		expect(not ui.save_writes_allowed and ui.view.paused,"failed startup cannot take ownership of existing files")
		expect(ui.get_action_control("save").disabled,"protected files cannot be overwritten by save button")
		var dialog=ui.get_node_or_null("RestoreFailure")
		expect(is_instance_valid(dialog) and dialog.visible,"startup failure has explicit visible explanation")
		if is_instance_valid(dialog):
			await RenderingServer.frame_post_draw
			dialog.get_texture().get_image().save_png(folder+"/"+scenario+"-error.png")
		await key(KEY_ENTER,true)
		await key(KEY_ENTER,false)
		await frames()
		expect("保留原档" in ui.get_action_control("quit").text,"exit action explains preservation")
	elif scenario=="blank":
		expect(ui.save_writes_allowed and ui.view.day==1,"no previous files starts a saveable new game")
	else:
		var expected=JSON.parse_string(FileAccess.get_file_as_string(folder+"/expected.json"))
		var restored=JSON.parse_string(JSON.stringify(ui.game.snapshot(),"",true,true))
		expect(restored==expected,"startup restores full day2 snapshot without clicking restore")
		expect(ui.view.day==2 and ui.view.cash==56 and ui.save_writes_allowed,"restored day2/56 owns its save")
		expect("恢复" in ui.feedback.text,"automatic restore result is visible")
		expect(hashes()==before_files,"automatic load preserves original files before exit")
	await screenshot(scenario+"-startup")
	trace.append({"action":"startup_observation","day":ui.view.day,"cash":ui.view.cash,"feedback":ui.feedback.text,"before_sha256":before_files})
	ui.tree_exiting.connect(_observe_exit)
	if scenario.ends_with("-close"):
		trace.append({"action":"simulated_WM_CLOSE_REQUEST_notification","input_claim":"runtime close notification; not an OS window interaction"})
		write_report()
		ui.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		await frames(30)
	else:
		write_report()
		await activate("quit")
		expect(false,"actual product exit must close this process")

func ui_session_fixture():
	var fixture=load("res://game/core/game_session.gd").new(7,"rain-night-v1")
	fixture.command("finish_shopping")
	fixture.command("open_shop")
	fixture.advance(3000)
	fixture.command("decline",{"order_id":fixture.view().pending.id})
	fixture.advance(4000)
	fixture.command("settle")
	fixture.command("next_day")
	return fixture

func _observe_exit():
	var after_files=hashes()
	if scenario.begins_with("invalid") or scenario.begins_with("unsupported"):
		expect(after_files==before_files,"failed or unsupported load preserves original primary and backup byte for byte after exit")
	else:
		for suffix in ["",".bak"]:
			var saved=JSON.parse_string(FileAccess.get_file_as_string(folder+"/progress.json"+suffix))
			expect(saved is Dictionary and saved.day==(1 if scenario=="blank" else 2),"product exit preserves correct day in "+suffix)
			if scenario!="blank":
				var expected=JSON.parse_string(FileAccess.get_file_as_string(folder+"/expected.json"))
				expect(saved==expected,"full restored progress survives product exit in "+suffix)
	trace.append({"action":"actual_tree_exit","after_sha256":after_files})
	write_report()
