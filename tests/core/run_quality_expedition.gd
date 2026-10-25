extends SceneTree
func _initialize():
	var args = OS.get_cmdline_user_args(); var report = ""
	for i in range(args.size()-1):
		if args[i] == "--report": report = args[i+1]
	if not report.is_absolute_path(): quit(2); return
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	var result = preload("res://tests/core/quality_expedition_cases.gd").new().run(report.get_base_dir())
	var file = FileAccess.open(report,FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	print("P04 real Session: ",result.checks," checks, ",result.failures.size()," failures")
	quit(0 if result.failures.is_empty() else 1)
