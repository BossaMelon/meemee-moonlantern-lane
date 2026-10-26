extends SceneTree
const Cases = preload("res://tests/expedition/world_rain_cases.gd")
func _initialize():
	var args = OS.get_cmdline_user_args()
	var output = ""
	for i in range(args.size()):
		if args[i] != "--output": continue
		if i+1 >= args.size() or args[i+1].is_empty():
			push_error("--output requires a fresh absolute directory")
			quit(1); return
		output = args[i+1]
	var result = Cases.new().run(output)
	print("WORLD_RAIN_RESULT ",JSON.stringify({"checks":result.checks,"failures":result.failures,"output":result.get("output","")}))
	quit(1 if not result.failures.is_empty() else 0)
