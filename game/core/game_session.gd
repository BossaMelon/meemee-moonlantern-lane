extends RefCounted
const Legacy = preload("res://game/core/legacy_session.gd")
const RainNight = preload("res://game/core/rain_night_session.gd")
var _game: RefCounted
var _profile_id: String

func _init(seed_value: int = 1, profile_id: String = "rain-night-v1"):
	_profile_id = profile_id
	if profile_id == "prototype-v1": _game = Legacy.new(seed_value)
	elif profile_id == "rain-night-v1": _game = RainNight.new(seed_value)

func _invalid() -> Dictionary:
	return {"ok":false,"code":"unsupported_profile","message":"不支持的游戏规则："+_profile_id,"events":[]}
func command(kind: String, args: Dictionary = {}, request_id: String = "") -> Dictionary:
	return _game.command(kind,args,request_id) if _game != null else _invalid()
func advance(delta_ms: int) -> Dictionary:
	return command("advance",{"delta_ms":delta_ms})
func set_paused(value: bool) -> Dictionary:
	return command("pause",{"value":value})
func snapshot() -> Dictionary:
	return _game.snapshot() if _game != null else {}
func view() -> Dictionary:
	return _game.view() if _game != null else _invalid()
func action_trace() -> Array:
	return _game.action_trace() if _game != null else []
func validate_snapshot(data: Variant) -> String:
	return _game.validate_snapshot(data) if _game != null else "不支持的游戏规则"
func save_to(path: String = "") -> Dictionary:
	if _game == null: return _invalid()
	return _game.save_to() if path.is_empty() else _game.save_to(path)
func load_from(path: String = "") -> Dictionary:
	if _game == null: return _invalid()
	return _game.load_from() if path.is_empty() else _game.load_from(path)
