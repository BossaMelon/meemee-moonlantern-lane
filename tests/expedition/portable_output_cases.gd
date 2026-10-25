extends SceneTree
## Negative probe: use the real runner, but occupy report.json with a directory
## after it creates its fresh output. The expected process exit is 1, never a hang.
const Cases = preload("res://tests/expedition/return_boundary_cases.gd")
class BlockedReport extends Cases:
	func components():
		super.components()
		var error = DirAccess.make_dir_absolute(output.path_join("report.json"))
		if error != OK: expect(false,"probe could not create report-open obstacle")
func _initialize():
	var runner = BlockedReport.new()
	var report = runner.run()
	var expected = report.checks == 48 and report.failures.size() == 1 and report.failures[0].begins_with("cannot open report (")
	print("E04_REPORT_OPEN_PROBE ",JSON.stringify({"expected_failure":expected,"checks":report.checks,"failures":report.failures,"output":report.output}))
	quit(1 if expected else 2)
