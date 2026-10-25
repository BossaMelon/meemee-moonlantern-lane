extends RefCounted
## Deterministic rain-night-v1 model. Legacy behavior stays in expedition_model.gd.
const Map = preload("res://game/expedition/rain_garden_map.gd")
const STEP = 50
const WIDTH = 960.0
const HEIGHT = 540.0
const PLAYER_RADIUS = 12.0
const ENEMY_RADIUS = 17.0

static func _result(ok: bool = true, code: String = "ok", message: String = "") -> Dictionary:
	return {"ok":ok,"code":code,"message":message if message != "" else code,"events":[],"pickups":[],"returned":false,"reason":""}

static func _input() -> Dictionary:
	return {"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false}

static func options_valid(options: Dictionary) -> bool:
	return options.size() == 4 and options.has_all(["ruleset","map_id","map_revision","meal_effect"]) and options.ruleset is String and options.ruleset == "rain-night-v1" and options.map_id is String and options.map_id == Map.MAP_ID and _integer(options.map_revision,1,1) and _meal_valid(options.meal_effect,false)

static func _meal_valid(value: Variant, allow_used: bool = true) -> bool:
	if value == null: return true
	return value is Dictionary and value.size() == 3 and value.has_all(["effect_id","source_item_uid","used"]) and value.effect_id in ["light_step","clear_breath"] and _integer(value.source_item_uid,1,2147483647) and value.used is bool and (allow_used or not value.used)

static func _resources(day: int) -> Array:
	var nodes = Map.RESOURCES.duplicate(true)
	if day == 2:
		# A finite second-night arrangement; never respawn a collected node.
		nodes[0].x = 650.0; nodes[0].y = 95.0
		nodes[1].x = 380.0; nodes[1].y = 365.0
		nodes[2].x = 625.0; nodes[2].y = 435.0
	return nodes

static func create(day: int, run_id: String, seed_value: int, weapon_id: String, skills: Array, shield: bool, options: Dictionary) -> Dictionary:
	if not options_valid(options) or day < 1 or day > 2 or run_id.is_empty() or weapon_id not in ["bolt_wand","fan_wand"] or skills.size() > 1 or (skills.size() == 1 and skills[0] != "gust"): return {}
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var s = {"version":2,"ruleset":"rain-night-v1","map_id":Map.MAP_ID,"map_revision":Map.REVISION,
		"terrain":Map.data(),"hazards":[],"resource_nodes":_resources(day),"collision_records":[],"next_collision":1,"next_hazard":1,"next_skill":1,
		"meal_effect":options.meal_effect.duplicate(true) if options.meal_effect != null else null,
		"status":"active","day":day,"run_id":run_id,"remaining_ms":null,"elapsed_ms":0,"remainder_ms":0,"tick":0,
		"rng_state":str(rng.state),"weapon_id":weapon_id,"skills":skills.duplicate(),"input":_input(),"next_projectile":1,"next_cast":1,
		"entrance_armed":false,"return_reason":"","player":{"x":80.0,"y":270.0,"hp":3,"shield":shield,"aim_x":1.0,"aim_y":0.0,
		"cast_cooldown_ms":0,"dodge_cooldown_ms":0,"skill_cooldown_ms":0,"dodge_remaining_ms":0,"dodge_x":1.0,"dodge_y":0.0,
		"hurt_ms":0,"skill_flash_ms":0,"skill_range":120,"last_contact":"","dodge_id":""},"enemies":[],"projectiles":[],"drops":[]}
	for spawn in Map.SPAWNS:
		var enemy = _enemy(spawn.id,spawn.kind,Vector2(spawn.x,spawn.y),4 if spawn.kind == "moonheart" else 2,0 if spawn.id == "entry-rush" else 800)
		enemy.encounter_id = spawn.encounter_id
		s.enemies.append(enemy)
	_canonical(s)
	return s

static func _enemy(id: String, kind: String, p: Vector2, hp: int, wait: int) -> Dictionary:
	return {"id":id,"kind":kind,"x":p.x,"y":p.y,"hp":hp,"state":"idle","telegraph":{},"shielded":kind == "moonheart",
		"timer_ms":wait,"exposed_ms":0,"direction_x":-1.0,"direction_y":0.0,"attack_index":0,"attack_hit":false,
		"wave_radius":0.0,"hit_casts":[],"drop_spawned":false,"attack_id":"","stagger_remaining_ms":0,"stagger_attack_id":"","last_contact":"",
		"engaged":id == "entry-rush","path":[],"path_index":0,"path_target":"","path_refresh_ms":0,"cast_cooldown_ms":0,"target_x":0.0,"target_y":0.0}

static func _finite_axis(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v)) and absf(float(v)) <= 1.0

static func set_input(s: Dictionary, args: Dictionary) -> Dictionary:
	var next = _input()
	for key in ["move_x","move_y","aim_x","aim_y"]:
		var value = args.get(key,0.0)
		if not _finite_axis(value): return _result(false,"invalid_axis","方向必须是 [-1,1] 内的有限数")
		next[key] = float(value)
	for key in ["cast","dodge","skill"]:
		if not args.get(key,false) is bool: return _result(false,"invalid_input","动作须为布尔值")
		next[key] = args.get(key,false)
	if next.skill and "gust" not in s.skills: return _result(false,"skill_locked","尚未取得推退风咒")
	for prefix in ["move","aim"]:
		var axis = Vector2(next[prefix+"_x"],next[prefix+"_y"])
		if axis.length_squared() > 1.0: axis = axis.normalized()
		next[prefix+"_x"] = axis.x
		next[prefix+"_y"] = axis.y
	_canonical(next)
	s.input = next
	return _result()

static func clear_input(s: Dictionary):
	if not s.is_empty(): s.input = _input()

static func _pos(entity: Dictionary) -> Vector2:
	return Vector2(entity.x,entity.y)

static func _place(entity: Dictionary, p: Vector2, radius: float = PLAYER_RADIUS):
	entity.x = clampf(p.x,radius,WIDTH-radius)
	entity.y = clampf(p.y,radius,HEIGHT-radius)

static func _event(s: Dictionary, result: Dictionary, type: String, data: Dictionary = {}):
	var event = data.duplicate(true)
	event.type = type
	event.tick = s.tick
	event.run_id = s.run_id
	result.events.append(event)

static func leave(s: Dictionary, reason: String = "retreat") -> Dictionary:
	var result = _result()
	if s.status == "returned": return result
	s.status = "returned"
	s.return_reason = reason
	clear_input(s)
	result.returned = true
	result.reason = reason
	var abandoned: Array = []
	for drop in s.drops:
		if not drop.collected: abandoned.append(drop.id)
	for node in s.resource_nodes:
		if not node.collected: abandoned.append("resource:%s" % node.id)
	_event(s,result,"expedition_returned",{"reason":reason,"abandoned_drop_ids":abandoned})
	return result

static func advance(s: Dictionary, delta_ms: int, free_capacity: int = 80, paused: bool = false) -> Dictionary:
	if delta_ms < 0 or delta_ms > 60000 or free_capacity < 0: return _result(false,"invalid_delta","推进时间或容量非法")
	var result = _result()
	if paused or s.status not in ["active","cleared"]: return result
	s.remainder_ms += delta_ms
	while s.remainder_ms >= STEP and s.status in ["active","cleared"]:
		s.remainder_ms -= STEP
		_step(s,result,free_capacity-result.pickups.size())
	return result

static func _motion(s: Dictionary, actor: Dictionary, entity_id: String, delta: Vector2, radius: float, motion: String, result: Dictionary, slide: bool = true) -> Dictionary:
	var moved = Map.move(_pos(actor),delta,radius,slide)
	_place(actor,moved.position,radius)
	var contact = "|".join(moved.obstacle_ids) + ":" + motion if moved.hit else ""
	if moved.hit and actor.last_contact != contact:
		for obstacle_id in moved.obstacle_ids:
			_collision(s,result,entity_id,obstacle_id,int(actor.get("attack_index",0)),motion)
	actor.last_contact = contact
	return moved

static func _collision(s: Dictionary, result: Dictionary, entity_id: String, obstacle_id: String, attack_index: int, motion: String):
	var record = {"collision_id":"%s:c%d" % [s.run_id,s.next_collision],"entity_id":entity_id,"obstacle_id":obstacle_id,"attack_index":attack_index,"motion":motion,"tick":s.tick}
	s.next_collision += 1
	s.collision_records.append(record.duplicate(true))
	if s.collision_records.size() > 128: s.collision_records.pop_front()
	_event(s,result,"obstacle_hit",record)

static func _consume_meal(s: Dictionary, effect_id: String, result: Dictionary) -> bool:
	if s.meal_effect == null or s.meal_effect.used or s.meal_effect.effect_id != effect_id: return false
	s.meal_effect.used = true
	_event(s,result,"meal_effect_used",{"effect_id":effect_id,"source_item_uid":s.meal_effect.source_item_uid})
	return true

static func _step(s: Dictionary, result: Dictionary, capacity: int):
	s.tick += 1
	s.elapsed_ms += STEP
	var was_cleared = s.status == "cleared"
	var p: Dictionary = s.player
	for key in ["cast_cooldown_ms","dodge_cooldown_ms","skill_cooldown_ms","hurt_ms","skill_flash_ms"]:
		p[key] = maxi(0,int(p[key])-STEP)
	var input: Dictionary = s.input
	var aim = Vector2(input.aim_x,input.aim_y)
	if aim.length_squared() > 0.000001:
		aim = aim.normalized(); p.aim_x = aim.x; p.aim_y = aim.y
	else: aim = Vector2(p.aim_x,p.aim_y)
	var movement = Vector2(input.move_x,input.move_y)
	if input.dodge and p.dodge_cooldown_ms == 0:
		var direction = movement.normalized() if movement.length_squared() > 0.000001 else aim
		p.dodge_x = direction.x; p.dodge_y = direction.y
		p.dodge_remaining_ms = 300 if _consume_meal(s,"light_step",result) else 200
		p.dodge_cooldown_ms = 1200
		p.dodge_id = "%s:d%d" % [s.run_id,s.tick]
		_event(s,result,"dodge",{"entity_id":"player","action_id":p.dodge_id,"duration_ms":p.dodge_remaining_ms,"x":p.x,"y":p.y})
	var dodging = p.dodge_remaining_ms > 0
	if dodging:
		var moved = _motion(s,p,"player",Vector2(p.dodge_x,p.dodge_y)*15.0,PLAYER_RADIUS,"dodge",result,false)
		if moved.hit: p.dodge_remaining_ms = 0
	else: _motion(s,p,"player",movement*8.0*Map.speed_scale(_pos(p),s.hazards),PLAYER_RADIUS,"walk",result)
	if p.x > 140.0: s.entrance_armed = true
	if input.skill and p.skill_cooldown_ms == 0: _gust(s,result)
	if input.cast and p.cast_cooldown_ms == 0: _cast(s,result,aim)
	for enemy in s.enemies:
		if enemy.hp > 0: _enemy_step(s,enemy,result,dodging)
	_projectiles(s,result)
	_hazards(s,result,dodging)
	# Resource identities are stable within run; core scopes the pickup ledger by run_id.
	for node in s.resource_nodes:
		if node.collected or _pos(node).distance_to(_pos(p)) > 28.0: continue
		if capacity < node.quantity: continue
		node.collected = true
		capacity -= node.quantity
		var id = "resource:%s" % node.id
		result.pickups.append({"drop_id":id,"item_id":node.item_id,"quantity":node.quantity,"cost":0})
		_event(s,result,"drop_collected",{"drop_id":id,"resource_id":node.id,"item_id":node.item_id,"quantity":node.quantity})
	for drop in s.drops:
		if drop.collected or _pos(drop).distance_to(_pos(p)) > 28.0: continue
		if capacity <= 0:
			if not drop.blocked:
				drop.blocked = true
				_event(s,result,"pickup_blocked",{"drop_id":drop.id,"message":"储藏已满，材料仍留在地上"})
			continue
		drop.collected = true; drop.blocked = false; capacity -= 1
		result.pickups.append({"drop_id":drop.id,"item_id":drop.item_id,"quantity":1,"cost":0})
		_event(s,result,"drop_collected",{"drop_id":drop.id,"item_id":drop.item_id,"quantity":1})
	var alive = false
	for enemy in s.enemies:
		if enemy.hp > 0: alive = true
	if not alive: s.status = "cleared"
	p.dodge_remaining_ms = maxi(0,int(p.dodge_remaining_ms)-STEP)
	var reason = ""
	if p.hp <= 0: reason = "defeated"
	elif s.entrance_armed and p.x <= 44.0 and absf(p.y-270.0) <= 55.0: reason = "entrance"
	elif was_cleared:
		var outstanding = false
		for drop in s.drops:
			if not drop.collected: outstanding = true
		for node in s.resource_nodes:
			if not node.collected: outstanding = true
		if not outstanding: reason = "completed"
	if reason != "":
		var ended = leave(s,reason)
		result.events.append_array(ended.events); result.returned = true; result.reason = reason
	_canonical(s)

static func _canonical(value: Variant):
	if value is Dictionary:
		for key in value:
			if value[key] is float: value[key] = _decimal(value[key])
			elif value[key] is Dictionary or value[key] is Array: _canonical(value[key])
	elif value is Array:
		for i in range(value.size()):
			if value[i] is float: value[i] = _decimal(value[i])
			elif value[i] is Dictionary or value[i] is Array: _canonical(value[i])

static func _decimal(value: float) -> Variant:
	var rounded = float(String.num(value,6))
	return int(rounded) if rounded == floor(rounded) else rounded

static func _cast(s: Dictionary, result: Dictionary, aim: Vector2):
	var fan = s.weapon_id == "fan_wand"
	s.player.cast_cooldown_ms = 800 if fan else 500
	var cast_id = s.next_cast
	s.next_cast += 1
	for degrees in ([-20,0,20] if fan else [0]):
		var direction = aim.rotated(deg_to_rad(float(degrees)))
		s.projectiles.append({"id":s.next_projectile,"cast_id":cast_id,"owner":"player","x":s.player.x,"y":s.player.y,"vx":direction.x*360.0,"vy":direction.y*360.0,"remaining":180.0 if fan else 300.0})
		s.next_projectile += 1
	_event(s,result,"cast",{"entity_id":"player","weapon_id":s.weapon_id,"cast_id":cast_id,"projectile_count":3 if fan else 1})

static func _gust(s: Dictionary, result: Dictionary):
	s.player.skill_cooldown_ms = 3000
	s.player.skill_flash_ms = 250
	var radius = 160.0 if _consume_meal(s,"clear_breath",result) else 120.0
	s.player.skill_range = radius
	var affected: Array = []
	for enemy in s.enemies:
		if enemy.hp <= 0 or _pos(enemy).distance_to(_pos(s.player)) > radius: continue
		var direction = (_pos(enemy)-_pos(s.player)).normalized()
		if direction == Vector2.ZERO: direction = Vector2(s.player.aim_x,s.player.aim_y)
		_motion(s,enemy,enemy.id,direction*80.0,ENEMY_RADIUS,"push",result,false)
		# Emitted rings and spores survive. A pending directional attack can be interrupted.
		if enemy.state in ["telegraph","dash","spore_windup"] and enemy.telegraph.get("shape","") != "ring":
			enemy.state = "idle"; enemy.timer_ms = 1500; enemy.telegraph = {}
		if enemy.kind == "moonheart": enemy.exposed_ms = maxi(enemy.exposed_ms,1000)
		enemy.shielded = enemy.kind == "moonheart" and enemy.exposed_ms == 0
		affected.append(enemy.id)
	var kept: Array = []
	var cleared: Array = []
	for hazard in s.hazards:
		if hazard.state == "active" and _pos(hazard).distance_to(_pos(s.player)) <= radius:
			cleared.append(hazard.id)
			_event(s,result,"spore_cleared",{"hazard_id":hazard.id,"source":hazard.source,"reason":"gust"})
		else: kept.append(hazard)
	s.hazards = kept
	var skill_id = "%s:g%d" % [s.run_id,s.next_skill]
	s.next_skill += 1
	_event(s,result,"skill",{"entity_id":"player","skill_id":"gust","action_id":skill_id,"range":radius,"affected_ids":affected,"cleared_hazard_ids":cleared})

static func _damage(s: Dictionary, enemy: Dictionary, result: Dictionary, dodging: bool):
	if enemy.attack_hit: return
	# One attack is consumed even by a successful dodge or the food shield.
	enemy.attack_hit = true
	if dodging:
		_event(s,result,"hit",{"entity_id":"player","source_id":enemy.id,"damage":0,"avoided":"dodge"})
	elif s.player.shield:
		s.player.shield = false
		_event(s,result,"shield_absorbed",{"entity_id":"player","source_id":enemy.id,"damage":0})
	else:
		s.player.hp = maxi(0,s.player.hp-1)
		s.player.hurt_ms = 250
		_event(s,result,"hit",{"entity_id":"player","source_id":enemy.id,"damage":1,"hp":s.player.hp})

static func _walk_enemy(s: Dictionary, e: Dictionary, result: Dictionary):
	var goal = _pos(s.player)
	# The player is smaller: an enemy still approaches a player hugging a wall.
	if not Map.point_clear(goal,ENEMY_RADIUS):
		var nearest = INF
		var reachable_goal = goal
		for point in Map._graph(ENEMY_RADIUS).points.values():
			var distance = point.distance_squared_to(goal)
			if distance < nearest: nearest = distance; reachable_goal = point
		goal = reachable_goal
	var target_key = "%d:%d" % [int(goal.x/32),int(goal.y/32)]
	e.path_refresh_ms = maxi(0,e.path_refresh_ms-STEP)
	if e.path_refresh_ms == 0 or e.path_target != target_key:
		e.path = []
		for point in Map.path(_pos(e),goal,ENEMY_RADIUS): e.path.append({"x":point.x,"y":point.y})
		e.path_index = 0; e.path_target = target_key; e.path_refresh_ms = 250
	while e.path_index < e.path.size() and _pos(e).distance_to(_pos(e.path[e.path_index])) < 2.0: e.path_index += 1
	if e.path_index >= e.path.size(): return
	var delta = _pos(e.path[e.path_index])-_pos(e)
	var travel = 35.0*0.05*Map.speed_scale(_pos(e),s.hazards)
	_motion(s,e,e.id,delta.limit_length(travel),ENEMY_RADIUS,"walk",result)

static func _enemy_step(s: Dictionary, e: Dictionary, result: Dictionary, dodging: bool):
	if not e.engaged:
		var threshold = 675.0 if e.encounter_id == "deep" else 350.0
		if s.player.x < threshold: return
		e.engaged = true
		_event(s,result,"encounter_engaged",{"entity_id":e.id,"encounter_id":e.encounter_id})
	e.exposed_ms = maxi(0,int(e.exposed_ms)-STEP)
	e.shielded = e.kind == "moonheart" and e.exposed_ms == 0
	e.cast_cooldown_ms = maxi(0,int(e.cast_cooldown_ms)-STEP)
	var toward = (_pos(s.player)-_pos(e)).normalized()
	if toward == Vector2.ZERO: toward = Vector2.LEFT
	e.timer_ms = maxi(0,int(e.timer_ms)-STEP)
	match e.state:
		"stagger":
			e.stagger_remaining_ms = maxi(0,int(e.stagger_remaining_ms)-STEP)
			if e.stagger_remaining_ms == 0: e.state = "idle"; e.timer_ms = 1500
		"idle":
			e.direction_x = toward.x; e.direction_y = toward.y
			var distance = _pos(s.player).distance_to(_pos(e))
			var sight = Map.line_clear(_pos(e),_pos(s.player),4.0)
			if e.kind == "sporecaster":
				if distance > 320.0 or not sight: _walk_enemy(s,e,result)
				elif e.timer_ms == 0 and e.cast_cooldown_ms == 0:
					e.state = "spore_windup"; e.timer_ms = 400
					e.telegraph = {"shape":"spore","remaining_ms":400}
			else:
				# Entry attack deliberately locks before walking: the stump teaches the rule.
				if e.timer_ms == 0 and distance <= 330.0:
					var ring = e.kind == "moonheart" and e.attack_index % 2 == 1
					e.state = "telegraph"; e.timer_ms = 1000 if ring else (800 if e.kind == "moonheart" else 600)
					e.telegraph = {"shape":"ring" if ring else "cone","direction_x":toward.x,"direction_y":toward.y,"radius":180.0 if ring else 165.0,"angle_degrees":360.0 if ring else 40.0,"remaining_ms":e.timer_ms}
					_event(s,result,"telegraph",{"entity_id":e.id,"shape":e.telegraph.shape})
				elif distance > 150.0: _walk_enemy(s,e,result)
		"telegraph":
			e.telegraph.remaining_ms = e.timer_ms
			if e.timer_ms == 0:
				e.state = "wave" if e.telegraph.shape == "ring" else "dash"
				e.timer_ms = 1000 if e.state == "wave" else 500
				e.attack_index += 1; e.attack_id = "%s:%s:a%d" % [s.run_id,e.id,e.attack_index]
				e.attack_hit = false; e.wave_radius = 0.0; e.telegraph = {}; e.last_contact = ""
		"dash":
			var before = _pos(e)
			var moved = _motion(s,e,e.id,Vector2(e.direction_x,e.direction_y)*(270.0 if e.kind == "moonheart" else 220.0)*0.05,ENEMY_RADIUS,"dash",result,false)
			if Geometry2D.get_closest_point_to_segment(_pos(s.player),before,_pos(e)).distance_to(_pos(s.player)) <= PLAYER_RADIUS+ENEMY_RADIUS: _damage(s,e,result,dodging)
			var stump = ""
			for obstacle_id in moved.obstacle_ids:
				if not obstacle_id.begins_with("boundary-"): stump = obstacle_id; break
			if stump != "" and e.stagger_attack_id != e.attack_id:
				e.stagger_attack_id = e.attack_id; e.state = "stagger"; e.timer_ms = 0; e.stagger_remaining_ms = 1200
				if e.kind == "moonheart": e.exposed_ms = 1200; e.shielded = false
				_event(s,result,"enemy_staggered",{"entity_id":e.id,"obstacle_id":stump,"attack_index":e.attack_index,"attack_id":e.attack_id,"duration_ms":1200})
			elif moved.hit or e.timer_ms == 0:
				e.state = "idle"; e.timer_ms = 1500
				if e.kind == "moonheart": e.exposed_ms = 1000; e.shielded = false
		"wave":
			var distance = _pos(s.player).distance_to(_pos(e))
			var previous = e.wave_radius
			e.wave_radius += 9.0
			if distance >= previous-PLAYER_RADIUS and distance <= e.wave_radius+PLAYER_RADIUS: _damage(s,e,result,dodging)
			if e.timer_ms == 0: e.state = "idle"; e.timer_ms = 1500
		"spore_windup":
			e.telegraph.remaining_ms = e.timer_ms
			if e.timer_ms == 0:
				e.telegraph = {}; e.state = "spore_release"; e.timer_ms = 150; e.cast_cooldown_ms = 2500
				e.attack_index += 1; e.attack_id = "%s:%s:a%d" % [s.run_id,e.id,e.attack_index]
				_throw_spore(s,e,result)
		"spore_release":
			if e.timer_ms == 0: e.state = "idle"; e.timer_ms = 0

static func _throw_spore(s: Dictionary, e: Dictionary, result: Dictionary):
	e.target_x = s.player.x; e.target_y = s.player.y
	var id = "%s:h%d" % [s.run_id,s.next_hazard]
	s.next_hazard += 1
	s.hazards.append({"id":id,"source":e.id,"x":e.target_x,"y":e.target_y,"radius":45,"state":"warning","remaining_ms":800,"hit_player":false,"speed_scale":0.65,"born_tick":s.tick})
	var velocity = (Vector2(e.target_x,e.target_y)-_pos(e))/0.8
	s.projectiles.append({"id":s.next_projectile,"cast_id":0,"owner":"enemy","source":e.id,"hazard_id":id,"x":e.x,"y":e.y,"vx":velocity.x,"vy":velocity.y,"remaining_ms":800,"born_tick":s.tick})
	s.next_projectile += 1
	_event(s,result,"spore_spawned",{"hazard_id":id,"source":e.id,"state":"warning","x":e.target_x,"y":e.target_y})

static func _hazards(s: Dictionary, result: Dictionary, dodging: bool):
	var kept: Array = []
	for h in s.hazards:
		if h.born_tick != s.tick:
			h.remaining_ms = maxi(0,h.remaining_ms-STEP)
			if h.state == "warning" and h.remaining_ms == 0:
				h.state = "active"; h.remaining_ms = 3000
				_event(s,result,"spore_active",{"hazard_id":h.id,"source":h.source})
		if h.state == "active" and not h.hit_player and _pos(h).distance_to(_pos(s.player)) <= h.radius+PLAYER_RADIUS and not dodging:
			h.hit_player = true
			var source = {"id":h.source,"attack_hit":false}
			_damage(s,source,result,false)
			_event(s,result,"spore_contact",{"hazard_id":h.id,"source":h.source})
		if h.remaining_ms > 0: kept.append(h)
	s.hazards = kept

static func _defeat(s: Dictionary, target: Dictionary, result: Dictionary):
	target.state = "defeated"; target.telegraph = {}; target.shielded = false; target.stagger_remaining_ms = 0
	if target.drop_spawned: return
	target.drop_spawned = true
	var id = "%d:%s:%s" % [s.day,s.run_id,target.id]
	var item = "moonheart" if target.kind == "moonheart" else "sparkcap"
	s.drops.append({"id":id,"enemy_id":target.id,"item_id":item,"x":target.x,"y":target.y,"collected":false,"blocked":false})
	_event(s,result,"enemy_defeated",{"entity_id":target.id,"drop_id":id,"item_id":item})

static func _projectiles(s: Dictionary, result: Dictionary):
	var kept: Array = []
	for b in s.projectiles:
		if b.owner == "enemy" and b.born_tick == s.tick: kept.append(b); continue
		var before = _pos(b)
		var direction = Vector2(b.vx,b.vy).normalized()
		var delta = Vector2(b.vx,b.vy)*0.05 if b.owner == "enemy" else direction*minf(18.0,b.remaining)
		var wall = Map.sweep(before,delta,4.0)
		if b.owner == "enemy":
			b.remaining_ms = maxi(0,b.remaining_ms-STEP)
			if wall.hit:
				_collision(s,result,"projectile:%d" % b.id,wall.obstacle_id,0,"spore")
				for i in range(s.hazards.size()-1,-1,-1):
					if s.hazards[i].id == b.hazard_id: s.hazards.remove_at(i)
			else:
				b.x = wall.position.x; b.y = wall.position.y
				if b.remaining_ms > 0: kept.append(b)
			continue
		var target: Dictionary = {}
		var nearest = wall.t if wall.hit else 2.0
		for enemy in s.enemies:
			if enemy.hp <= 0: continue
			var hit = Map._circle_hit(before,delta,_pos(enemy),ENEMY_RADIUS+4.0)
			if not hit.is_empty() and hit.t < nearest:
				target = enemy; nearest = hit.t
		b.x = wall.position.x; b.y = wall.position.y
		b.remaining = maxf(0.0,b.remaining-delta.length())
		if not target.is_empty():
			if not target.engaged:
				target.engaged = true
				_event(s,result,"encounter_engaged",{"entity_id":target.id,"encounter_id":target.encounter_id})
			var facing = Vector2(target.direction_x,target.direction_y)
			var front = (-direction).dot(facing) >= cos(deg_to_rad(60.0))
			if target.shielded and front: _event(s,result,"blocked",{"entity_id":target.id,"cast_id":b.cast_id,"reason":"front_shield"})
			elif b.cast_id not in target.hit_casts:
				target.hit_casts.append(b.cast_id); target.hp -= 1
				_event(s,result,"hit",{"entity_id":target.id,"cast_id":b.cast_id,"damage":1,"hp":target.hp})
				if target.hp == 0: _defeat(s,target,result)
		elif wall.hit: _collision(s,result,"projectile:%d" % b.id,wall.obstacle_id,0,"bolt")
		elif b.remaining > 0: kept.append(b)
	s.projectiles = kept

static func view(s: Dictionary) -> Dictionary:
	var v = s.duplicate(true)
	v.attempts_remaining = 0
	return v

static func _number(v: Variant, low: float, high: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v >= low and v <= high

static func _integer(v: Variant, low: int, high: int) -> bool:
	return _number(v,low,high) and float(v) == floor(float(v))

static func _coordinates(e: Dictionary) -> bool:
	return e.has_all(["x","y"]) and _number(e.x,0,WIDTH) and _number(e.y,0,HEIGHT)

static func validate(value: Variant) -> String:
	if not value is Dictionary: return "动作状态须为对象"
	var s: Dictionary = value
	var template = create(1,"shape",1,"bolt_wand",["gust"],false,{"ruleset":"rain-night-v1","map_id":Map.MAP_ID,"map_revision":Map.REVISION,"meal_effect":null})
	if not _shape(s,template): return "雨园字段类型非法"
	if not s.has_all(["version","ruleset","map_id","map_revision","terrain","hazards","resource_nodes","collision_records","next_collision","next_hazard","next_skill","meal_effect","status","day","run_id","remaining_ms","elapsed_ms","remainder_ms","tick","rng_state","weapon_id","skills","input","next_projectile","next_cast","entrance_armed","return_reason","player","enemies","projectiles","drops"]): return "雨园状态缺少字段"
	if not _integer(s.version,2,2) or not s.ruleset is String or s.ruleset != "rain-night-v1" or not s.map_id is String or s.map_id != Map.MAP_ID or not _integer(s.map_revision,Map.REVISION,Map.REVISION): return "雨园版本或地图不匹配"
	if not _same(s.terrain,Map.data()): return "地图revision几何不匹配"
	if s.status not in ["active","cleared","returned"] or not _integer(s.day,1,2): return "动作阶段或日期非法"
	if not s.run_id is String or s.run_id.is_empty() or s.run_id.length() > 200 or not s.rng_state is String or not s.rng_state.is_valid_int(): return "动作身份或随机状态非法"
	if s.remaining_ms != null or not _integer(s.tick,0,2147483647) or not _integer(s.elapsed_ms,0,107374182350) or s.elapsed_ms != s.tick*STEP or not _integer(s.remainder_ms,0,60049): return "雨园时钟非法"
	if s.status != "returned" and s.remainder_ms >= STEP: return "固定步余数非法"
	for key in ["next_cast","next_projectile","next_collision","next_hazard","next_skill"]:
		if not _integer(s[key],1,2147483647): return "动作序号非法"
	if not _meal_valid(s.meal_effect): return "餐前效果非法"
	if s.weapon_id not in ["bolt_wand","fan_wand"] or not s.skills is Array or s.skills.size() > 1 or (s.skills.size() == 1 and s.skills[0] != "gust"): return "动作装备非法"
	if not s.entrance_armed is bool or not s.return_reason is String or (s.status == "returned") != (s.return_reason in ["retreat","completed","defeated","entrance"]): return "返程状态非法"
	if s.status != "returned" and s.return_reason != "": return "尚未返程却有返程原因"
	if not s.player is Dictionary or not s.input is Dictionary: return "玩家或输入非法"
	var p: Dictionary = s.player
	if not p.has_all(["x","y","hp","shield","aim_x","aim_y","cast_cooldown_ms","dodge_cooldown_ms","skill_cooldown_ms","dodge_remaining_ms","dodge_x","dodge_y","hurt_ms","skill_flash_ms","last_contact","dodge_id"]): return "玩家状态不完整"
	if not _coordinates(p) or not Map.point_clear(_pos(p),PLAYER_RADIUS) or not _integer(p.hp,0,3) or not p.shield is bool or not p.last_contact is String or not p.dodge_id is String: return "玩家生命或位置非法"
	if (p.hp == 0) != (s.status == "returned" and s.return_reason == "defeated"): return "玩家生命与返程状态不一致"
	for key in ["aim_x","aim_y","dodge_x","dodge_y"]:
		if not _finite_axis(p[key]): return "玩家方向非法"
	for key in ["cast_cooldown_ms","dodge_cooldown_ms","skill_cooldown_ms","hurt_ms","skill_flash_ms"]:
		if not _integer(p[key],0,3000): return "玩家冷却非法"
	if not _integer(p.dodge_remaining_ms,0,300): return "闪避计时非法"
	if not (_integer(p.skill_range,120,120) or _integer(p.skill_range,160,160)): return "风咒范围非法"
	if not s.input.has_all(_input().keys()): return "保持输入不完整"
	var checked = s.duplicate(true)
	if not set_input(checked,s.input).ok: return "保持输入非法"
	if not s.enemies is Array or not s.projectiles is Array or not s.drops is Array or not s.hazards is Array or not s.resource_nodes is Array or not s.collision_records is Array: return "动作实体数组非法"
	if s.enemies.size() != Map.SPAWNS.size() or s.projectiles.size() > 64 or s.hazards.size() > 16 or s.drops.size() > s.enemies.size() or s.resource_nodes.size() != Map.RESOURCES.size() or s.collision_records.size() > 128: return "动作实体数量非法"
	var enemies = {}
	for i in range(s.enemies.size()):
		var e = s.enemies[i]
		var spawn: Dictionary = Map.SPAWNS[i]
		var enemy_template = _enemy("shape","sparkcap",Vector2.ZERO,2,0)
		enemy_template.encounter_id = "entry"
		if not _shape(e,enemy_template): return "敌人字段类型非法"
		if not e is Dictionary or not e.has_all(["id","kind","encounter_id","engaged","x","y","hp","state","telegraph","shielded","timer_ms","exposed_ms","direction_x","direction_y","attack_index","attack_id","attack_hit","wave_radius","hit_casts","drop_spawned","stagger_remaining_ms","stagger_attack_id","last_contact","path","path_index","path_target","path_refresh_ms","cast_cooldown_ms","target_x","target_y"]): return "敌人状态不完整"
		if e.id != spawn.id or e.kind != spawn.kind or e.encounter_id != spawn.encounter_id or not e.engaged is bool or not _coordinates(e) or not Map.point_clear(_pos(e),ENEMY_RADIUS): return "敌人身份或位置非法"
		if not _integer(e.hp,0,4 if e.kind == "moonheart" else 2) or e.state not in ["idle","telegraph","dash","wave","stagger","spore_windup","spore_release","defeated"] or (e.hp == 0) != (e.state == "defeated"): return "敌人生命或阶段非法"
		if e.kind == "sporecaster" and e.state in ["telegraph","dash","wave"]: return "投手攻击阶段非法"
		if e.kind != "sporecaster" and e.state in ["spore_windup","spore_release"]: return "冲刺怪攻击阶段非法"
		if not e.shielded is bool or not e.attack_hit is bool or not e.drop_spawned is bool or e.drop_spawned != (e.hp == 0): return "敌人掉落或护盾非法"
		if e.shielded != (e.kind == "moonheart" and e.hp > 0 and e.exposed_ms == 0): return "精英护盾不一致"
		if not _integer(e.timer_ms,0,1500) or not _integer(e.exposed_ms,0,1200) or not _integer(e.stagger_remaining_ms,0,1200) or not _integer(e.cast_cooldown_ms,0,2500) or not _integer(e.attack_index,0,2147483647) or not _number(e.wave_radius,0,180): return "敌人计时非法"
		if (e.state == "stagger") != (e.stagger_remaining_ms > 0): return "硬直阶段与时钟不一致"
		var attack_id = "%s:%s:a%d" % [s.run_id,e.id,e.attack_index] if e.attack_index > 0 else ""
		if e.attack_id != attack_id or not e.stagger_attack_id is String or not e.last_contact is String: return "攻击身份非法"
		if e.stagger_attack_id != "":
			var prefix = "%s:%s:a" % [s.run_id,e.id]
			if not e.stagger_attack_id.begins_with(prefix) or not e.stagger_attack_id.trim_prefix(prefix).is_valid_int() or not _integer(int(e.stagger_attack_id.trim_prefix(prefix)),1,e.attack_index): return "硬直攻击身份非法"
		if not _finite_axis(e.direction_x) or not _finite_axis(e.direction_y) or not e.hit_casts is Array: return "敌人方向或命中记录非法"
		var hits = {}
		for cast_id in e.hit_casts:
			if not _integer(cast_id,1,int(s.next_cast)-1) or hits.has(str(cast_id)): return "重复施法命中身份"
			hits[str(cast_id)] = true
		if not e.telegraph is Dictionary: return "敌人预警非法"
		if e.state == "telegraph":
			var t: Dictionary = e.telegraph
			if not _shape(t,{"shape":"cone","direction_x":0,"direction_y":0,"radius":0,"angle_degrees":0,"remaining_ms":0}): return "预警字段类型非法"
			if not t.has_all(["shape","direction_x","direction_y","radius","angle_degrees","remaining_ms"]) or t.shape not in ["cone","ring"]: return "敌人预警缺字段"
			if not _finite_axis(t.direction_x) or not _finite_axis(t.direction_y) or not _number(t.radius,0,180) or not _number(t.angle_degrees,0,360) or t.remaining_ms != e.timer_ms: return "预警与攻击不一致"
		elif e.state == "spore_windup":
			if not _shape(e.telegraph,{"shape":"spore","remaining_ms":0}): return "投孢预警字段类型非法"
			if not e.telegraph.has_all(["shape","remaining_ms"]) or e.telegraph.shape != "spore" or e.telegraph.remaining_ms != e.timer_ms: return "投孢预警非法"
		elif not e.telegraph.is_empty(): return "非预警阶段保留预警"
		if not e.path is Array or e.path.size() > 600 or not _integer(e.path_index,0,e.path.size()) or not e.path_target is String or not _integer(e.path_refresh_ms,0,250) or not _number(e.target_x,0,WIDTH) or not _number(e.target_y,0,HEIGHT): return "导航状态非法"
		for point in e.path:
			if not point is Dictionary or not _coordinates(point) or not Map.point_clear(_pos(point),ENEMY_RADIUS): return "导航点非法"
		enemies[e.id] = e
	var hazard_ids = {}
	for h in s.hazards:
		if not _shape(h,{"id":"","source":"","x":0,"y":0,"radius":0,"state":"","remaining_ms":0,"hit_player":false,"speed_scale":0,"born_tick":0}): return "孢子区字段类型非法"
		if not h is Dictionary or not h.has_all(["id","source","x","y","radius","state","remaining_ms","hit_player","speed_scale","born_tick"]): return "孢子区缺字段"
		if not _sequence_id(h.id,"%s:h" % s.run_id,s.next_hazard) or hazard_ids.has(h.id) or not h.source is String or not enemies.has(h.source) or enemies[h.source].kind != "sporecaster": return "孢子区身份非法"
		if not _coordinates(h) or h.radius != 45 or h.speed_scale != 0.65 or h.state not in ["warning","active"] or not h.hit_player is bool or not _integer(h.remaining_ms,1,800 if h.state == "warning" else 3000) or not _integer(h.born_tick,0,s.tick): return "孢子区属性非法"
		if h.state == "warning" and h.hit_player: return "未形成孢子区却已命中"
		hazard_ids[h.id] = h
	var projectile_ids = {}
	var warning_projectiles = {}
	for b in s.projectiles:
		if not _shape(b,{"id":0,"cast_id":0,"owner":"","x":0,"y":0,"vx":0,"vy":0}): return "弹体字段类型非法"
		if not b is Dictionary or not b.has_all(["id","cast_id","owner","x","y","vx","vy"]): return "弹体缺字段"
		if not _integer(b.id,1,int(s.next_projectile)-1) or projectile_ids.has(str(b.id)) or not _coordinates(b) or not Map.point_clear(_pos(b),4.0) or b.owner not in ["player","enemy"] or not _number(b.vx,-1200,1200) or not _number(b.vy,-675,675): return "弹体身份或运动非法"
		if b.owner == "player":
			if not _shape(b,{"remaining":0}): return "玩家弹体字段类型非法"
			if not b.has("remaining") or not _integer(b.cast_id,1,int(s.next_cast)-1) or not _number(b.remaining,0,300): return "玩家弹体非法"
		else:
			if not _shape(b,{"source":"","hazard_id":"","remaining_ms":0,"born_tick":0}): return "飞行孢子字段类型非法"
			if not b.has_all(["source","hazard_id","remaining_ms","born_tick"]) or b.cast_id != 0 or not b.hazard_id is String or not hazard_ids.has(b.hazard_id) or warning_projectiles.has(b.hazard_id): return "飞行孢子身份非法"
			var h: Dictionary = hazard_ids[b.hazard_id]
			if b.source != h.source or h.state != "warning" or not _integer(b.remaining_ms,1,800) or b.remaining_ms != h.remaining_ms or b.born_tick != h.born_tick: return "飞行孢子与预警不一致"
			warning_projectiles[b.hazard_id] = true
		projectile_ids[str(b.id)] = true
	for id in hazard_ids:
		if hazard_ids[id].state == "warning" and not warning_projectiles.has(id): return "落点预警缺少飞行孢子"
	var nodes = _resources(s.day)
	for i in range(nodes.size()):
		var node = s.resource_nodes[i]
		if not node is Dictionary or not node.has("collected") or not node.collected is bool: return "资源领取状态非法"
		var expected: Dictionary = nodes[i].duplicate(true)
		expected.collected = node.collected
		if not _same(node,expected): return "资源revision配置非法"
	var drop_ids = {}
	for d in s.drops:
		if not _shape(d,{"id":"","enemy_id":"","item_id":"","x":0,"y":0,"collected":false,"blocked":false}): return "掉落字段类型非法"
		if not d is Dictionary or not d.has_all(["id","enemy_id","item_id","x","y","collected","blocked"]): return "掉落缺字段"
		if not d.enemy_id is String or not enemies.has(d.enemy_id) or not d.collected is bool or not d.blocked is bool or not _coordinates(d): return "掉落属性非法"
		var e: Dictionary = enemies[d.enemy_id]
		if d.id != "%d:%s:%s" % [s.day,s.run_id,e.id] or drop_ids.has(d.id) or e.hp != 0 or d.item_id != ("moonheart" if e.kind == "moonheart" else "sparkcap") or d.x != e.x or d.y != e.y or (d.collected and d.blocked): return "掉落身份或来源非法"
		drop_ids[d.id] = true
	for e in s.enemies:
		if e.drop_spawned and not drop_ids.has("%d:%s:%s" % [s.day,s.run_id,e.id]): return "击败敌人缺少掉落"
		if s.status == "cleared" and e.hp > 0: return "尚有敌人却已清场"
	var collision_ids = {}
	for record in s.collision_records:
		if not _shape(record,{"collision_id":"","entity_id":"","obstacle_id":"","attack_index":0,"motion":"","tick":0}): return "碰撞记录字段类型非法"
		if not record is Dictionary or not record.has_all(["collision_id","entity_id","obstacle_id","attack_index","motion","tick"]): return "碰撞记录缺字段"
		if not _sequence_id(record.collision_id,"%s:c" % s.run_id,s.next_collision) or collision_ids.has(record.collision_id) or not record.entity_id is String or not record.obstacle_id is String or record.motion not in ["walk","dodge","dash","push","bolt","spore"] or not _integer(record.attack_index,0,2147483647) or not _integer(record.tick,0,s.tick): return "碰撞记录非法"
		var known_obstacle = record.obstacle_id in ["boundary-left","boundary-right","boundary-top","boundary-bottom"]
		for obstacle in Map.OBSTACLES:
			if obstacle.id == record.obstacle_id: known_obstacle = true
		if not known_obstacle: return "碰撞菇桩身份非法"
		collision_ids[record.collision_id] = true
	return ""

static func _sequence_id(value: Variant, prefix: String, next: int) -> bool:
	if not value is String or not value.begins_with(prefix): return false
	var suffix = value.trim_prefix(prefix)
	return suffix.is_valid_int() and _integer(int(suffix),1,next-1) and value == prefix+str(int(suffix))

# JSON parses numbers as floats; structural equality must preserve numeric values,
# accept integral JSON numbers, and reject bool/number or container substitutions.
static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and a == b
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _same(a[i],b[i]): return false
		return true
	return a == b

static func _shape(value: Variant, template: Variant) -> bool:
	if template == null: return true # Nullable meal has its own exact three-field check.
	if template is int or template is float: return (value is int or value is float) and is_finite(float(value))
	if typeof(value) != typeof(template): return false
	if template is Dictionary:
		for key in template:
			if not value.has(key) or not _shape(value[key],template[key]): return false
	return true # Array elements use their own identity/relationship checks above.
