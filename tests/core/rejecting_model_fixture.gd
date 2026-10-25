extends RefCounted
## Failure injection only: verifies that an unsuccessful create cannot consume a meal/attempt.
static func create(_day, _run_id, _seed, _weapon, _skills, _shield, _options) -> Dictionary:
	return {}
