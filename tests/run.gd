extends SceneTree
const Session = preload("res://game/core/game_session.gd")
func _initialize():
	var game = Session.new(1)
	print(game.view())
	quit(0)
