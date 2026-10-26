extends RefCounted
## Presentation only. A blocked input cannot advance the walk cycle.
const Art = preload("res://game/ui/pixel_assets.gd")
var phase_ms = 0.0
var frame_id = "meemee_idle"
var _foot = Vector2.ZERO
var _region = ""
var _facing = "se"

func reset():
	_region = ""; phase_ms = 0.0; frame_id = "meemee_idle"

func observe(region: String, player: Dictionary, paused: bool) -> Dictionary:
	var foot = Vector2(float(player.x), float(player.y))
	var facing = str(player.facing)
	if region != _region:
		_region = region; _foot = foot; _facing = facing
		frame_id = "meemee_idle" if facing == "se" else "meemee_walk_"+facing
	elif not paused:
		var distance = foot.distance_to(_foot)
		if distance > 0.001:
			# Normal160px/s maps80 traveled pixels to the authored500ms cycle.
			phase_ms = fmod(phase_ms+distance*1000.0/160.0, 500.0)
		if distance > 0.001 or facing != _facing:
			# A real Core turn may change direction, but never advances the phase.
			_facing = facing
			var clip: Dictionary = Art.manifest().get("animations", {}).get("meemee_walk_"+facing+"_cycle", {})
			var frames: Array = clip.get("frames", [])
			var durations: Array = clip.get("duration_ms", [])
			var elapsed = phase_ms
			for i in range(frames.size()):
				if i >= durations.size(): break
				if elapsed < float(durations[i]): frame_id = str(frames[i]); break
				elapsed -= float(durations[i])
	_foot = foot
	var info = Art.entry(frame_id)
	var pivot: Array = info.get("pivot", [24, 59])
	return {"frame_id": frame_id, "texture": Art.sprite(frame_id), "pivot": Vector2(pivot[0], pivot[1]), "foot": foot, "phase_ms": phase_ms}
