extends SceneTree
const Session = preload("res://game/core/game_session.gd")
func _initialize():
	var args = OS.get_cmdline_user_args(); var report = ""; var source_report = ""
	for i in range(args.size()-1):
		if args[i] == "--report": report = args[i+1]
		if args[i] == "--restore-report": source_report = args[i+1]
	if report.is_empty() or not report.is_absolute_path(): quit(2); return
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	var h = preload("res://tests/core/world_session_cases.gd").new()
	h.output_dir = report.get_base_dir().path_join("day-boundary"); DirAccess.make_dir_recursive_absolute(h.output_dir)
	var cases = []
	if source_report != "":
		if not source_report.is_absolute_path(): quit(2); return
		var source = JSON.parse_string(FileAccess.get_file_as_string(source_report)); var count = 0
		for test_case in source.cases:
			for trace in test_case.traces:
				if trace.scenario != "WR-saved-boundary": continue
				if not trace.path.begins_with(source_report.get_base_dir()+"/"): quit(2); return
				var g = Session.new(77); var loaded = g.load_from(trace.path)
				# Compare both sides in JSON's numeric domain; parsing reports makes ints floats.
				var restored = JSON.parse_string(JSON.stringify(g.snapshot(),"",true,true))
				h.expect(loaded.ok and restored == trace.snapshot,"independent process restores exact "+trace.label)
				h.audit(g,trace.label)
				h.expect(g.save_to(h.output_dir.path_join(trace.label+"-resaved.json")).ok,"independent process can resave "+trace.label)
				count += 1
		h.expect(count > 0,"independent process restored saved day boundaries")
		cases.append({"id":"WR-independent-restore","status":"passed" if h.failures.is_empty() else "failed","checks":h.checks,"failures":h.failures})
	else:
		var tests = preload("res://tests/core/world_day_boundary_cases.gd").new()
		for entry in [["WR-01",tests.zero_cash],["WR-02",tests.late_cooking]]:
			h.checks = 0; h.failures = []; h.traces = []; entry[1].call(h)
			cases.append({"id":entry[0],"status":"passed" if h.failures.is_empty() else "failed","checks":h.checks,"failures":h.failures.duplicate(),"traces":h.traces.duplicate(true)})
	var result = {"schema_version":1,"suite":"world-day-boundary-targeted","cases":cases}
	var file = FileAccess.open(report,FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	for test_case in cases: print("%s: %s (%d checks)" % [test_case.id,test_case.status,test_case.checks])
	quit(1 if cases.any(func(c): return c.status != "passed" or c.checks < 1) else 0)
