extends "res://game/ui/checks/restaurant.gd"
## This script is started in a NEW engine process after a real completed route.
func _initialize():
	super._initialize()
	if "--advanced" in OS.get_cmdline_user_args(): folder=ProjectSettings.globalize_path("res://output/restaurant-ui/advanced")
	source_hashes["game/ui/checks/restart.gd"]=FileAccess.get_sha256("res://game/ui/checks/restart.gd")

func run():
	selected_routes=PackedStringArray(["restart"])
	mode="mouse"
	var path=folder+"/mouse-restaurant-save.json"
	expect(FileAccess.file_exists(path),"previous engine process wrote a real restaurant save")
	if not FileAccess.file_exists(path): return
	var expected=JSON.parse_string(FileAccess.get_file_as_string(path))
	await fresh(Vector2i(640,960) if "--portrait" in OS.get_cmdline_user_args() else Vector2i(1280,720))
	if not failures.is_empty(): return
	await activate("load")
	var restored=JSON.parse_string(JSON.stringify(ui.game.snapshot(),"",true,true))
	expect(restored==expected,"new engine process restores full restaurant, quest, growth and expedition state")
	expect(ui.view.finished,"new process restores the completed third day")
	var labels=ui.body.find_children("*","Label",true,false)
	expect(labels.any(func(label): return "海格巡护带餐：已完成" in label.text),"restored Hagrid completion is visible in persistent UI")
	await screenshot("restaurant-restarted-portrait" if "--portrait" in OS.get_cmdline_user_args() else "restaurant-restarted")
	var before: Dictionary=ui.game.snapshot()
	await activate("primary")
	expect(ui.game.snapshot()==before,"saving completed restaurant cannot settle or reward twice")
	trace.append({"action":"save_and_quit_requested","path":path,"phase":ui.view.phase,"cash":ui.view.cash})
	write_report()
	print("RESTART checks ",checks," failures ",failures.size(),"; requesting actual save-and-quit")
	await activate("quit")
	expect(false,"save-and-quit must close the engine")
