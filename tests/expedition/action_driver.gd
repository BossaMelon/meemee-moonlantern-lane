extends RefCounted
## Deterministic test strategy: reads public positions, submits ordinary inputs only.
static func next_input(s: Dictionary) -> Dictionary:
	var p = Vector2(s.player.x,s.player.y)
	var target: Dictionary = {}
	var nearest = INF
	for e in s.enemies:
		if e.hp <= 0: continue
		var distance = p.distance_to(Vector2(e.x,e.y))
		if distance < nearest: nearest = distance; target = e
	var move = Vector2.ZERO
	var aim = Vector2(1,0)
	var dodge = false
	var skill = false
	var cast = not target.is_empty()
	if target.is_empty():
		for d in s.drops:
			if d.collected: continue
			var distance = p.distance_to(Vector2(d.x,d.y))
			if distance < nearest: nearest = distance; target = d
		if not target.is_empty(): move = (Vector2(target.x,target.y)-p).normalized()
	else:
		aim = (Vector2(target.x,target.y)-p).normalized()
		var desired = 160.0 if s.weapon_id == "fan_wand" else 220.0
		if target.kind == "moonheart" and "gust" in s.skills and target.shielded: desired = 95.0
		if nearest > desired+10: move = aim
		elif nearest < desired-30: move = -aim
		if "gust" in s.skills and nearest <= 118.0 and s.player.skill_cooldown_ms == 0:
			skill = true
		if target.kind == "moonheart" and target.shielded and nearest < 125.0:
			move = aim.rotated(PI/2)
		# Dodge sideways across a locked charge; a ring requires radial movement.
		for e in s.enemies:
			if e.hp <= 0: continue
			var ep = Vector2(e.x,e.y)
			var distance = p.distance_to(ep)
			if e.state == "telegraph" and e.telegraph.shape != "ring" and e.timer_ms <= 150:
				var toward_player = p-ep
				var direction = Vector2(e.direction_x,e.direction_y)
				if distance < 210 and toward_player.normalized().dot(direction) > 0.7:
					move = direction.rotated(PI/2)
					dodge = s.player.dodge_cooldown_ms == 0
			elif e.state == "wave" and absf(distance-e.wave_radius) < 32:
				move = (ep-p).normalized()
				dodge = s.player.dodge_cooldown_ms == 0
	# Avoid being trapped in the edge/exit while kiting.
	if p.x < 65 and move.x < 0: move.x = 1
	if p.x > 895 and move.x > 0: move.x = -1
	if p.y < 65 and move.y < 0: move.y = 1
	if p.y > 475 and move.y > 0: move.y = -1
	move = move.limit_length(1.0)
	return {"move_x":move.x,"move_y":move.y,"aim_x":aim.x,"aim_y":aim.y,"cast":cast,"dodge":dodge,"skill":skill}
