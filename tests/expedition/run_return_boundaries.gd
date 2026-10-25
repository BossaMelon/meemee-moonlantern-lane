extends SceneTree
const Cases = preload("res://tests/expedition/return_boundary_cases.gd")
const Session = preload("res://game/core/game_session.gd")
func _initialize():
	var args = OS.get_cmdline_user_args()
	var output = "/tmp/e02-return-boundaries"
	for i in range(args.size()-1):
		if args[i] == "--output": output = args[i+1]
	var factory = Callable() if "--component-only" in args else func(seed_value): return Session.new(seed_value)
	var result = Cases.new().run(factory,output)
	quit(1 if not result.failures.is_empty() else 0)
