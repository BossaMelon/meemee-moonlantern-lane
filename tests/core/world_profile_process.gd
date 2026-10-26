extends SceneTree
const Session = preload("res://game/core/game_session.gd")
func _initialize():
	var args = OS.get_cmdline_user_args(); var mode = ""; var report = ""
	for i in range(args.size()-1):
		if args[i] == "--mode": mode = args[i+1]
		if args[i] == "--report": report = args[i+1]
	if report.is_empty() or not report.is_absolute_path(): quit(2); return
	var failures = []; var g = Session.new(23)
	if g.snapshot().get("profile_id") != "world-slice-v1": failures.append("default profile")
	if FileAccess.file_exists("res://tests/fixtures/world-slice-scenarios.json"): failures.append("isolated player must have no fixtures")
	if mode == "write":
		g.command("world_input",{"move_x":1,"move_y":0}); g.advance(200); g.set_paused(true)
		if not g.save_to().ok: failures.append("default write")
	elif mode == "restore":
		if not g.load_from().ok: failures.append("default restore")
	else: failures.append("unknown mode")
	var path = ProjectSettings.globalize_path("user://profiles/world-slice-v1/moonlantern.json")
	var result = {"failures":failures,"user_dir":OS.get_user_data_dir(),"save_path":path,"snapshot":g.snapshot(),"primary_sha256":FileAccess.get_sha256(path),"backup_sha256":FileAccess.get_sha256(path+".bak"),"geometry":g.view().world.geometry}
	var file = FileAccess.open(report,FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	quit(0 if failures.is_empty() else 1)
