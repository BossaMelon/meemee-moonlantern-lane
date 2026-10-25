extends SceneTree
const Suite = preload("res://tests/core/prototype_suite.gd")
func _initialize():
	var args = OS.get_cmdline_user_args()
	var report = ""
	for i in range(args.size()-1):
		if args[i] == "--report": report = args[i+1]
	if report.is_empty() or not report.is_absolute_path():
		push_error("Runner requires -- --report ABS_REPORT")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	var suite = Suite.new()
	var result = suite.run(report.get_base_dir())
	var file = FileAccess.open(report,FileAccess.WRITE)
	if file == null:
		push_error("Cannot write actual case report")
		quit(2)
		return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	var failed = false
	for test_case in result.cases:
		if test_case.status != "passed" or test_case.checks < 1: failed = true
	quit(1 if failed else 0)
