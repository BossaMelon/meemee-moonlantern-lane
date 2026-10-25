extends SceneTree
const Suite = preload("res://tests/core/prototype_suite.gd")

func _initialize():
	var root = "/private/tmp/moonlantern-foundation-regressions-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(root)
	var suite = Suite.new()
	suite.temp_root = root
	suite.run_case("P05",suite.test_noop_request_binding)
	suite.run_case("P09",suite.test_cost_provenance)
	var file = FileAccess.open(root+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite":"foundation-regressions","cases":suite.cases},"\t")); file.close()
	print("Focused report: "+root+"/report.json")
	var failed = false
	for row in suite.cases:
		if row.status != "passed": failed = true
	quit(1 if failed else 0)
