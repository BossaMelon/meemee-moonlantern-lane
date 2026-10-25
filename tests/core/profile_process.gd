extends SceneTree
const Session = preload("res://game/core/game_session.gd")
func _initialize():
	var args = OS.get_cmdline_user_args(); var profile = ""; var mode = ""; var report = ""
	for i in range(args.size()-1):
		if args[i] == "--profile": profile = args[i+1]
		if args[i] == "--mode": mode = args[i+1]
		if args[i] == "--report": report = args[i+1]
	if profile not in ["prototype-v1","rain-night-v1"] or mode not in ["write","restore"] or not report.is_absolute_path(): quit(2); return
	var g = Session.new(7,profile); var failures = []
	if mode == "write":
		if not g.command("buy",{"item_id":"flour","quantity":1}).ok: failures.append("buy")
		if not g.save_to().ok: failures.append("first default save")
		if not g.command("buy",{"item_id":"pumpkin","quantity":1}).ok: failures.append("second buy")
		if not g.save_to().ok: failures.append("second default save")
	else:
		if not g.load_from().ok: failures.append("default load in another process")
		if g.view().cash != 55: failures.append("restored real economy")
	var path = "user://moonlantern.json" if profile == "prototype-v1" else "user://profiles/rain-night-v1/moonlantern.json"
	var result = {"profile":profile,"mode":mode,"user_dir":OS.get_user_data_dir(),"save_path":ProjectSettings.globalize_path(path),"primary_sha256":FileAccess.get_sha256(path),"backup_sha256":FileAccess.get_sha256(path+".bak"),"snapshot":g.snapshot(),"failures":failures}
	var file = FileAccess.open(report,FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	quit(0 if failures.is_empty() else 1)
