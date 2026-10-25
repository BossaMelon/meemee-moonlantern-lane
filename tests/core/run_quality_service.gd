extends SceneTree
const Suite = preload("res://tests/core/quality_service_cases.gd")
func _initialize():
	var args = OS.get_cmdline_user_args()
	var report = ""
	for i in range(args.size()-1):
		if args[i] == "--report": report = args[i+1]
	if report.is_empty() or not report.is_absolute_path():
		push_error("focused quality service runner requires absolute report")
		quit(2); return
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	var result = Suite.new().run(report.get_base_dir())
	var file = FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	quit(0 if result.failures.is_empty() else 1)
