extends SceneTree
const Suite = preload("res://tests/core/prototype_suite.gd")
func _initialize():
	var args = OS.get_cmdline_user_args()
	var report = ""
	var selected = ""
	var suite_id = "prototype"
	for i in range(args.size()-1):
		if args[i] == "--report": report = args[i+1]
		if args[i] == "--case": selected = args[i+1]
		if args[i] == "--suite": suite_id = args[i+1]
	if report.is_empty() or not report.is_absolute_path():
		push_error("Runner requires -- --report ABS_REPORT")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	if suite_id != "prototype":
		var result = {"schema_version":1,"suite":suite_id,"cases":[]}
		if suite_id == "quality-slice":
			var service = preload("res://tests/core/quality_service_cases.gd").new().run(report.get_base_dir())
			result.cases.append({"id":"Q03","status":"passed" if service.failures.is_empty() else "failed","checks":service.checks,"failures":service.failures,"traces":service.traces})
			# These required cases remain explicit failures until the real E02 integration is ready.
			for id in ["Q01","Q02","Q04","Q05"]:
				result.cases.append({"id":id,"status":"failed","checks":0,"failures":["P04 staged service API: real E02 integration and full quality acceptance not yet complete"]})
		else: result.cases.append({"id":"runner","status":"failed","checks":1,"failures":["Unknown suite: "+suite_id]})
		_write_report(report,result)
		return
	var suite = Suite.new()
	var result = suite.run(report.get_base_dir(),selected)
	if selected == "" or selected in ["P16","P17"]:
		var path = "res://tests/expedition/prototype_cases.gd"
		if ResourceLoader.exists(path) and ResourceLoader.exists("res://game/expedition/expedition_model.gd"):
			var expedition = load(path).new()
			expedition.seeds = suite.seeds.duplicate()
			var action_result = expedition.run(func(seed_value): return preload("res://game/core/game_session.gd").new(seed_value,"prototype-v1"),report.get_base_dir())
			var session_result = preload("res://tests/core/expedition_session_cases.gd").new().run(report.get_base_dir())
			for row in action_result.cases:
				if row.id == "P16":
					row.checks += session_result.checks
					row.failures.append_array(session_result.failures)
					if not row.failures.is_empty(): row.status = "failed"
				if selected == "" or row.id == selected: result.cases.append(row)
		else:
			for id in ["P16","P17"]:
				if selected == "" or id == selected:
					result.cases.append({"id":id,"status":"failed","checks":1,"failures":["E01 real action module/cases not integrated; no simulated pass"]})
	_write_report(report,result)

func _write_report(report: String, result: Dictionary):
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
