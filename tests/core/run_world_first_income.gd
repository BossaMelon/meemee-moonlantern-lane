extends SceneTree
const Session = preload("res://game/core/game_session.gd")
var failures = []
var checks = 0
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize():
	var g = Session.new(1,"world-slice-v1")
	expect(g.snapshot().get("profile_id") == "world-slice-v1","world profile must be implemented")
	if failures.is_empty():
		var suite = load("res://tests/core/world_session_cases.gd").new()
		suite.output_dir = "/private/tmp/p10-world-first-%d" % OS.get_process_id()
		var result = suite.first_income_report()
		checks += result.checks; failures.append_array(result.failures)
		var file = FileAccess.open(suite.output_dir+"/first-income-report.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
		print(JSON.stringify({"checks":result.checks,"failures":result.failures,"report":suite.output_dir+"/first-income-report.json"}))
	print("%d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
