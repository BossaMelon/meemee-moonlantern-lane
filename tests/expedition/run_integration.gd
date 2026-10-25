extends SceneTree
const Session = preload("res://game/core/game_session.gd")
const Cases = preload("res://tests/expedition/prototype_cases.gd")
func _initialize():
	var args = OS.get_cmdline_user_args()
	var output = "/tmp/e01-integration"
	for i in range(args.size()-1):
		if args[i] == "--output": output = args[i+1]
	var result = Cases.new().run(func(seed_value): return Session.new(seed_value),output)
	var failed = false
	for entry in result.cases:
		print(entry.id,": ",entry.status," (",entry.checks," checks)")
		if entry.status != "passed": failed = true
	var file = FileAccess.open(output+"/expedition-cases.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"schema_version":1,"cases":result.cases},"\t")); file.close()
	quit(1 if failed else 0)
