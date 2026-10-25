extends RefCounted
## Terrain-aware normal-input strategies. This helper never edits model state.
const Map = preload("res://game/expedition/rain_garden_map.gd")
var route = "shelf"
var stage = 0
var finished = false
var waited_ms = 0
var deep = false
var route_points: Array = []
var initialized = false
var observe_deep = false
var observed_deep_active = false
func _init(route_id: String = "shelf", include_deep: bool = false, observe_first_spore: bool = false):
	route = route_id; deep = include_deep; observe_deep = observe_first_spore
	route_points = [Vector2(225,120),Vector2(415,95)] if route == "shelf" else [Vector2(230,370),Vector2(375,395),Vector2(560,440)]
	if deep: route_points.append_array([Vector2(650,400),Vector2(825,355)])
func _pos(entity: Dictionary) -> Vector2: return Vector2(entity.x,entity.y)
func _walk(p: Vector2, goal: Vector2) -> Vector2:
	var path = Map.path(p,goal,12.0)
	for i in range(path.size()-1,-1,-1):
		var point: Vector2 = path[i]
		if p.distance_to(point) > 3.0 and Map.line_clear(p,point,12): return (point-p).normalized()
	return Vector2.ZERO
func next_input(s: Dictionary) -> Dictionary:
	if not initialized:
		initialized = true
		if route == "shelf": route_points[1] = _pos(s.resource_nodes[0])
		else:
			route_points[1] = _pos(s.resource_nodes[1]); route_points[2] = _pos(s.resource_nodes[2])
	var p = _pos(s.player)
	var goal = Vector2(28,270)
	if stage < route_points.size():
		goal = route_points[stage]
		if p.distance_to(goal) < 20:
			stage += 1
			if stage < route_points.size(): goal = route_points[stage]
	var target: Dictionary = {}
	var best = INF
	for e in s.enemies:
		if e.hp <= 0 or not e.engaged: continue
		var distance = p.distance_to(_pos(e))
		var deep_target = deep and stage >= route_points.size() and e.encounter_id == "deep"
		if not deep_target and (distance > 330 or not Map.line_clear(p,_pos(e),4)): continue
		var priority = distance-100 if e.kind == "sporecaster" else distance
		if priority < best: best = priority; target = e
	var move = _walk(p,goal)
	var aim = Vector2.RIGHT
	var dodge = false
	var skill = false
	var cast = false
	if not target.is_empty():
		var distance = p.distance_to(_pos(target))
		aim = (_pos(target)-p).normalized()
		cast = distance <= (175 if s.weapon_id == "fan_wand" else 295) and Map.line_clear(p,_pos(target),4)
		if observe_deep and not observed_deep_active and target.encounter_id == "deep": cast = false
		# At the optional deep encounter, fight before harvesting its dropped material.
		if deep and stage >= route_points.size():
			var desired = 135.0 if s.weapon_id == "fan_wand" else 225.0
			move = aim if distance > desired else (-aim if distance < 85 else aim.rotated(PI/2))
			if not Map.line_clear(p,_pos(target),4) or not Map.line_clear(p,p+move*30,12): move = _walk(p,_pos(target))
		if target.kind == "moonheart" and target.shielded and distance < 150 and s.player.skill_cooldown_ms == 0: skill = true
	for hazard in s.hazards:
		if hazard.source == "deep-caster" and hazard.state == "active": observed_deep_active = true
		var distance = p.distance_to(_pos(hazard))
		if hazard.state == "active" and distance <= 118 and s.player.skill_cooldown_ms == 0: skill = true
		if distance <= hazard.radius+26 and (hazard.state == "active" or hazard.remaining_ms <= 300):
			var escape = (p-_pos(hazard)).normalized()
			if escape == Vector2.ZERO: escape = Vector2.UP
			if Map.line_clear(p,p+escape*60,12): move = escape
			dodge = s.player.dodge_cooldown_ms == 0
	for e in s.enemies:
		if e.hp <= 0: continue
		var distance = p.distance_to(_pos(e))
		if e.state == "telegraph" and e.telegraph.shape == "cone" and e.timer_ms <= 150:
			var direction = Vector2(e.direction_x,e.direction_y)
			if distance < 190 and (p-_pos(e)).normalized().dot(direction) > 0.75:
				var escape = direction.rotated(PI/2)
				if not Map.line_clear(p,p+escape*55,12): escape = -escape
				move = escape; dodge = s.player.dodge_cooldown_ms == 0
		elif e.state == "wave" and absf(distance-e.wave_radius) < 28:
			move = (_pos(e)-p).normalized(); dodge = s.player.dodge_cooldown_ms == 0
	if deep and stage >= route_points.size():
		var elite_alive = false
		for e in s.enemies:
			if e.encounter_id == "deep" and e.hp > 0: elite_alive = true
		if not elite_alive:
			var pickup: Dictionary = {}
			var nearest = INF
			for d in s.drops:
				if not d.collected and p.distance_to(_pos(d)) < nearest: pickup = d; nearest = p.distance_to(_pos(d))
			if not pickup.is_empty(): move = _walk(p,_pos(pickup))
			else: deep = false; move = _walk(p,Vector2(28,270))
	# This observation strategy intentionally reserves its first gust for the deep zone.
	if observe_deep and not observed_deep_active: skill = false
	if s.status == "returned": finished = true
	return {"move_x":move.x,"move_y":move.y,"aim_x":aim.x,"aim_y":aim.y,"cast":cast,"dodge":dodge,"skill":skill}
