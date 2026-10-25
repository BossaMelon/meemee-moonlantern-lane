extends SceneTree
const Cases = preload("res://tests/expedition/rain_model_cases.gd")
func _initialize():
	var result = Cases.new().run()
	quit(1 if not result.failures.is_empty() else 0)
