extends SceneTree
func _initialize():
	var args = OS.get_cmdline_user_args(); var report = ""
	for i in range(args.size()-1):
		if args[i] == "--report": report = args[i+1]
	if report.is_empty() or not report.is_absolute_path(): quit(2); return
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	var suite = preload("res://tests/core/world_session_cases.gd").new()
	var result = suite.run_adapter(report.get_base_dir())
	var file = FileAccess.open(report,FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	quit(1 if result.cases.any(func(c): return c.status != "passed" or c.checks < 1) else 0)
