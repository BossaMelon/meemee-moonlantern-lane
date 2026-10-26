extends RefCounted
## World-only context adapter, not a second combat simulation.
## Saved version 3 uses campaign day; encounter_day selects Rain v2 day 1/2.
## Core must select this module explicitly and pass world-slice-v1 options.
## Rain drop IDs remain opaque; canonical nN-expedition run IDs scope campaign
## pickup ledgers. Never rewrite drop IDs or credit inventory in this adapter.
const Rain = preload("res://game/expedition/rain_garden_model.gd")
const VERSION = 3
const PROFILE_ID = "world-slice-v1"
const MAX_DAY = 2147483647

static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"code":"invalid_world_expedition","message":message,"events":[],"pickups":[],"returned":false,"reason":""}

static func create(day: Variant, run_id: Variant, seed_value: int = 1, weapon_id: String = "bolt_wand", skills: Array = [], shield: bool = false, options: Variant = {}) -> Dictionary:
	if not _whole(day,1,MAX_DAY) or not run_id is String or run_id != "n%d-expedition" % int(day): return {}
	if not options is Dictionary or options.size() != 4 or not options.has_all(["ruleset","map_id","map_revision","meal_effect"]) or options.ruleset != PROFILE_ID: return {}
	var rain_options = options.duplicate(true)
	rain_options.ruleset = "rain-night-v1"
	var encounter_day = mini(int(day),2)
	var s = Rain.create(encounter_day,run_id,seed_value,weapon_id,skills,shield,rain_options)
	if s.is_empty(): return {}
	s.version = VERSION; s.ruleset = PROFILE_ID; s.day = int(day); s.encounter_day = encounter_day
	return s

static func _context_error(value: Variant) -> String:
	if not value is Dictionary or not value.has_all(["version","ruleset","day","encounter_day","run_id"]): return "世界探索上下文缺失"
	if not _whole(value.version,VERSION,VERSION) or not value.ruleset is String or value.ruleset != PROFILE_ID: return "世界探索版本或规则非法"
	if not _whole(value.day,1,MAX_DAY) or not _whole(value.encounter_day,1,2) or value.encounter_day != mini(int(value.day),2): return "世界探索日期或遭遇配置非法"
	if not value.run_id is String or value.run_id != "n%d-expedition" % int(value.day): return "世界探索身份与日期不一致"
	return ""

static func _rain_state(s: Dictionary) -> Dictionary:
	var raw = s.duplicate(true)
	raw.version = 2; raw.ruleset = "rain-night-v1"; raw.day = int(s.encounter_day)
	raw.erase("encounter_day")
	return raw

static func _commit(s: Dictionary, raw: Dictionary):
	raw.version = VERSION; raw.ruleset = PROFILE_ID; raw.day = int(s.day); raw.encounter_day = int(s.encounter_day)
	s.clear(); s.merge(raw)

static func set_input(s: Dictionary, args: Dictionary) -> Dictionary:
	var error = _context_error(s)
	if error != "": return _failure(error)
	var raw = _rain_state(s)
	var result = Rain.set_input(raw,args)
	if result.ok: _commit(s,raw)
	return result

static func clear_input(s: Dictionary):
	if _context_error(s) != "": return
	var raw = _rain_state(s)
	Rain.clear_input(raw); _commit(s,raw)

static func advance(s: Dictionary, delta_ms: int, free_capacity: int = 80, paused: bool = false) -> Dictionary:
	var error = _context_error(s)
	if error != "": return _failure(error)
	var raw = _rain_state(s)
	var result = Rain.advance(raw,delta_ms,free_capacity,paused)
	if result.ok: _commit(s,raw)
	return result

static func leave(s: Dictionary, reason: String = "retreat") -> Dictionary:
	var error = _context_error(s)
	if error != "": return _failure(error)
	if reason not in ["retreat","entrance","defeated","completed"]: return _failure("世界探索返程原因非法")
	var raw = _rain_state(s)
	var result = Rain.leave(raw,reason)
	if result.ok: _commit(s,raw)
	return result

static func view(s: Dictionary) -> Dictionary:
	var v = s.duplicate(true)
	v.attempts_remaining = 0
	return v

static func validate(value: Variant) -> String:
	var error = _context_error(value)
	if error != "": return error
	var raw = _rain_state(value)
	var template = Rain.create(1,"schema",1,"bolt_wand",[],false,{"ruleset":"rain-night-v1","map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null})
	# Never erase/ignore unexpected context fields when projecting a saved state.
	if raw.size() != template.size(): return "世界探索快照字段数量非法"
	for key in raw:
		if not template.has(key): return "世界探索快照含未知字段"
	return Rain.validate(raw)
