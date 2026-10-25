extends RefCounted
const Rain = preload("res://game/expedition/rain_garden_model.gd")
## Pure fixed-step simulation. The owning session commits pickups with its inventory.
const STEP = 50
const WIDTH = 960.0
const HEIGHT = 540.0
const LIMIT = 180000
const PLAYER_RADIUS = 12.0
const ENEMY_RADIUS = 17.0

static func _result(ok: bool = true, code: String = "ok", message: String = "") -> Dictionary:
	return {"ok":ok,"code":code,"message":message if message != "" else code,"events":[],"pickups":[],"returned":false,"reason":""}

static func _input() -> Dictionary:
	return {"move_x":0.0,"move_y":0.0,"aim_x":0.0,"aim_y":0.0,"cast":false,"dodge":false,"skill":false}

static func create(day: int, run_id: String, seed_value: int = 1, weapon_id: String = "bolt_wand", skills: Array = [], shield: bool = false, options: Variant = {}) -> Dictionary:
	if not options is Dictionary: return {}
	if not options.is_empty(): return Rain.create(day,run_id,seed_value,weapon_id,skills,shield,options)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var s = {"version":1,"status":"active","day":day,"run_id":run_id,"remaining_ms":LIMIT,"remainder_ms":0,"tick":0,
		"rng_state":"","weapon_id":weapon_id,"skills":skills.duplicate(),"input":_input(),"next_projectile":1,"next_cast":1,
		"entrance_armed":false,"return_reason":"","player":{"x":80.0,"y":270.0,"hp":3,"shield":shield,"aim_x":1.0,"aim_y":0.0,
		"cast_cooldown_ms":0,"dodge_cooldown_ms":0,"skill_cooldown_ms":0,"dodge_remaining_ms":0,"dodge_x":1.0,"dodge_y":0.0,
		"hurt_ms":0,"skill_flash_ms":0},"enemies":[],"projectiles":[],"drops":[]}
	var positions = [Vector2(410,170),Vector2(600,360),Vector2(760,170),Vector2(800,420)]
	var count = 4 if day == 2 else 3
	for i in range(count):
		var p = positions[i] + Vector2(rng.randi_range(-20,20),rng.randi_range(-20,20))
		s.enemies.append(_enemy("m%d" % i,"sparkcap",p,2,800 + i*200))
	if day == 3: s.enemies.append(_enemy("elite","moonheart",Vector2(780,350),4,1000))
	s.rng_state = str(rng.state)
	_canonical(s)
	return s

static func _enemy(id: String, kind: String, p: Vector2, hp: int, wait: int) -> Dictionary:
	return {"id":id,"kind":kind,"x":p.x,"y":p.y,"hp":hp,"state":"idle","telegraph":{},"shielded":kind == "moonheart",
		"timer_ms":wait,"exposed_ms":0,"direction_x":-1.0,"direction_y":0.0,"attack_index":0,"attack_hit":false,
		"wave_radius":0.0,"hit_casts":[],"drop_spawned":false}

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
	if s.get("version") == 2: return Rain.leave(s,reason)
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
	_event(s,result,"expedition_returned",{"reason":reason,"abandoned_drop_ids":abandoned})
	return result

static func advance(s: Dictionary, delta_ms: int, free_capacity: int = 80, paused: bool = false) -> Dictionary:
	if s.get("version") == 2: return Rain.advance(s,delta_ms,free_capacity,paused)
	if delta_ms < 0 or delta_ms > 60000 or free_capacity < 0: return _result(false,"invalid_delta","推进时间或容量非法")
	var result = _result()
	if paused or s.status not in ["active","cleared"]: return result
	s.remainder_ms += delta_ms
	while s.remainder_ms >= STEP and s.status in ["active","cleared"]:
		s.remainder_ms -= STEP
		_step(s,result,free_capacity-result.pickups.size())
	return result

static func _step(s: Dictionary, result: Dictionary, capacity: int):
	s.tick += 1
	s.remaining_ms -= STEP
	var was_cleared = s.status == "cleared"
	var p: Dictionary = s.player
	for key in ["cast_cooldown_ms","dodge_cooldown_ms","skill_cooldown_ms","hurt_ms","skill_flash_ms"]:
		p[key] = maxi(0,int(p[key])-STEP)
	var input: Dictionary = s.input
	var aim = Vector2(input.aim_x,input.aim_y)
	if aim.length_squared() > 0.000001:
		aim = aim.normalized()
		p.aim_x = aim.x
		p.aim_y = aim.y
	else: aim = Vector2(p.aim_x,p.aim_y)
	var movement = Vector2(input.move_x,input.move_y)
	if input.dodge and p.dodge_cooldown_ms == 0:
		var direction = movement.normalized() if movement.length_squared() > 0.000001 else aim
		p.dodge_x = direction.x
		p.dodge_y = direction.y
		p.dodge_remaining_ms = 200
		p.dodge_cooldown_ms = 1200
		_event(s,result,"dodge",{"entity_id":"player","x":p.x,"y":p.y})
	var dodging = p.dodge_remaining_ms > 0
	if dodging:
		_place(p,_pos(p)+Vector2(p.dodge_x,p.dodge_y)*300.0*0.05)
	else: _place(p,_pos(p)+movement*160.0*0.05)
	if p.x > 140.0: s.entrance_armed = true
	if input.skill and p.skill_cooldown_ms == 0: _gust(s,result)
	if input.cast and p.cast_cooldown_ms == 0: _cast(s,result,aim)
	for enemy in s.enemies:
		if enemy.hp > 0: _enemy_step(s,enemy,result,dodging)
	_projectiles(s,result)
	# Pickups are emitted once and only after capacity is reserved in this advance.
	for drop in s.drops:
		if drop.collected or _pos(drop).distance_to(_pos(p)) > 28.0: continue
		if capacity <= 0:
			if not drop.blocked:
				drop.blocked = true
				_event(s,result,"pickup_blocked",{"drop_id":drop.id,"message":"储藏已满，材料仍留在地上"})
			continue
		drop.collected = true
		drop.blocked = false
		capacity -= 1
		result.pickups.append({"drop_id":drop.id,"item_id":drop.item_id,"quantity":1,"cost":0})
		_event(s,result,"drop_collected",{"drop_id":drop.id,"item_id":drop.item_id,"quantity":1})
	var alive = false
	for enemy in s.enemies:
		if enemy.hp > 0: alive = true
	if not alive: s.status = "cleared"
	p.dodge_remaining_ms = maxi(0,int(p.dodge_remaining_ms)-STEP)
	var reason = ""
	if p.hp <= 0: reason = "defeated"
	elif s.remaining_ms <= 0: reason = "timeout"
	elif s.entrance_armed and p.x <= 44.0 and absf(p.y-270.0) <= 55.0: reason = "entrance"
	elif was_cleared:
		var outstanding = false
		for drop in s.drops:
			if not drop.collected: outstanding = true
		if not outstanding: reason = "completed"
	if reason != "":
		var ended = leave(s,reason)
		result.events.append_array(ended.events)
		result.returned = true
		result.reason = reason
	# JSON's default precision must preserve a resumed simulation bit-for-bit.
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
		var start = _pos(s.player)+direction*14.0
		s.projectiles.append({"id":s.next_projectile,"cast_id":cast_id,"x":start.x,"y":start.y,"vx":direction.x*360.0,"vy":direction.y*360.0,
			"remaining":180.0 if fan else 300.0})
		s.next_projectile += 1
	_event(s,result,"cast",{"entity_id":"player","weapon_id":s.weapon_id,"cast_id":cast_id,"projectile_count":3 if fan else 1})

static func _gust(s: Dictionary, result: Dictionary):
	s.player.skill_cooldown_ms = 3000
	s.player.skill_flash_ms = 250
	var affected: Array = []
	for enemy in s.enemies:
		if enemy.hp <= 0 or _pos(enemy).distance_to(_pos(s.player)) > 120.0: continue
		var direction = (_pos(enemy)-_pos(s.player)).normalized()
		if direction == Vector2.ZERO: direction = Vector2(s.player.aim_x,s.player.aim_y)
		_place(enemy,_pos(enemy)+direction*80.0,ENEMY_RADIUS)
		if enemy.state == "telegraph" and enemy.telegraph.shape != "ring":
			enemy.state = "idle"
			enemy.timer_ms = 1500
			enemy.telegraph = {}
		if enemy.kind == "moonheart": enemy.exposed_ms = 1000
		enemy.shielded = enemy.kind == "moonheart" and enemy.exposed_ms == 0
		affected.append(enemy.id)
	_event(s,result,"skill",{"entity_id":"player","skill_id":"gust","affected_ids":affected})

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

static func _enemy_step(s: Dictionary, e: Dictionary, result: Dictionary, dodging: bool):
	e.exposed_ms = maxi(0,int(e.exposed_ms)-STEP)
	e.shielded = e.kind == "moonheart" and e.exposed_ms == 0
	var toward = (_pos(s.player)-_pos(e)).normalized()
	if toward == Vector2.ZERO: toward = Vector2(-1,0)
	e.timer_ms = maxi(0,int(e.timer_ms)-STEP)
	match e.state:
		"idle":
			e.direction_x = toward.x
			e.direction_y = toward.y
			if _pos(s.player).distance_to(_pos(e)) > 150.0: _place(e,_pos(e)+toward*35.0*0.05,ENEMY_RADIUS)
			if e.timer_ms == 0:
				var ring = e.kind == "moonheart" and e.attack_index % 2 == 1
				e.state = "telegraph"
				e.timer_ms = 1000 if ring else (800 if e.kind == "moonheart" else 600)
				e.telegraph = {"shape":"ring" if ring else "cone","direction_x":toward.x,"direction_y":toward.y,
					"radius":180.0 if ring else 165.0,"angle_degrees":360.0 if ring else 40.0,"remaining_ms":e.timer_ms}
				_event(s,result,"telegraph",{"entity_id":e.id,"shape":e.telegraph.shape})
		"telegraph":
			e.telegraph.remaining_ms = e.timer_ms
			if e.timer_ms == 0:
				e.state = "wave" if e.telegraph.shape == "ring" else "dash"
				e.timer_ms = 1000 if e.state == "wave" else 500
				e.attack_index += 1
				e.attack_hit = false
				e.wave_radius = 0.0
				e.telegraph = {}
		"dash":
			var before = _pos(e)
			_place(e,before+Vector2(e.direction_x,e.direction_y)*(270.0 if e.kind == "moonheart" else 220.0)*0.05,ENEMY_RADIUS)
			if Geometry2D.get_closest_point_to_segment(_pos(s.player),before,_pos(e)).distance_to(_pos(s.player)) <= PLAYER_RADIUS+ENEMY_RADIUS:
				_damage(s,e,result,dodging)
			if e.timer_ms == 0:
				e.state = "idle"
				e.timer_ms = 1500
				if e.kind == "moonheart": e.exposed_ms = 1000; e.shielded = false
		"wave":
			var distance = _pos(s.player).distance_to(_pos(e))
			var previous = e.wave_radius
			e.wave_radius += 180.0*0.05
			if distance >= previous-PLAYER_RADIUS and distance <= e.wave_radius+PLAYER_RADIUS: _damage(s,e,result,dodging)
			if e.timer_ms == 0:
				e.state = "idle"
				e.timer_ms = 1500

static func _projectiles(s: Dictionary, result: Dictionary):
	var kept: Array = []
	for projectile in s.projectiles:
		var before = _pos(projectile)
		var travel = minf(18.0,projectile.remaining)
		var direction = Vector2(projectile.vx,projectile.vy).normalized()
		var after = before+direction*travel
		projectile.x = after.x
		projectile.y = after.y
		projectile.remaining = maxf(0.0,projectile.remaining-travel)
		var struck = false
		# Choose the first spatial collision, independent of array ordering.
		var target: Dictionary = {}
		var nearest = INF
		for enemy in s.enemies:
			if enemy.hp <= 0: continue
			var closest = Geometry2D.get_closest_point_to_segment(_pos(enemy),before,after)
			if closest.distance_to(_pos(enemy)) <= ENEMY_RADIUS+4.0 and before.distance_squared_to(closest) < nearest:
				target = enemy
				nearest = before.distance_squared_to(closest)
		if not target.is_empty():
			struck = true
			var facing = Vector2(target.direction_x,target.direction_y)
			var front = (-direction).dot(facing) >= cos(deg_to_rad(60.0))
			if target.shielded and front:
				_event(s,result,"blocked",{"entity_id":target.id,"cast_id":projectile.cast_id,"reason":"front_shield"})
			elif projectile.cast_id not in target.hit_casts:
				target.hit_casts.append(projectile.cast_id)
				target.hp -= 1
				_event(s,result,"hit",{"entity_id":target.id,"cast_id":projectile.cast_id,"damage":1,"hp":target.hp})
				if target.hp == 0:
					target.state = "defeated"
					target.telegraph = {}
					target.shielded = false
					if not target.drop_spawned:
						target.drop_spawned = true
						var id = "%d:%s:%s" % [s.day,s.run_id,target.id]
						s.drops.append({"id":id,"enemy_id":target.id,"item_id":target.kind,"x":target.x,"y":target.y,"collected":false,"blocked":false})
						_event(s,result,"enemy_defeated",{"entity_id":target.id,"drop_id":id,"item_id":target.kind})
		if not struck and projectile.remaining > 0.0 and after.x >= 0 and after.x <= WIDTH and after.y >= 0 and after.y <= HEIGHT: kept.append(projectile)
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
	if value is Dictionary and Rain._integer(value.get("version"),2,2): return Rain.validate(value)
	if value is Dictionary and not Rain._integer(value.get("version"),1,1): return "动作版本非法"
	if not value is Dictionary: return "动作状态须为对象"
	var s: Dictionary = value
	if not s.has_all(["version","status","day","run_id","remaining_ms","remainder_ms","tick","rng_state","weapon_id","skills","input","next_projectile","next_cast","entrance_armed","return_reason","player","enemies","projectiles","drops"]): return "动作状态缺少字段"
	if s.version != 1 or s.status not in ["active","cleared","returned"] or not _integer(s.day,1,3): return "动作版本/阶段/日期非法"
	if not s.run_id is String or s.run_id.is_empty() or not s.rng_state is String or not s.rng_state.is_valid_int(): return "动作身份或随机状态非法"
	if not _integer(s.remaining_ms,0,LIMIT) or not _integer(s.remainder_ms,0,60049) or not _integer(s.tick,0,3600) or s.remaining_ms != LIMIT-s.tick*STEP: return "动作时钟非法"
	if s.status != "returned" and s.remainder_ms >= STEP: return "固定步余数非法"
	if not _integer(s.next_cast,1,1000000) or not _integer(s.next_projectile,1,1000000): return "弹体序号非法"
	if s.weapon_id not in ["bolt_wand","fan_wand"] or not s.skills is Array or s.skills.size() > 1 or (s.skills.size() == 1 and s.skills[0] != "gust"): return "动作装备非法"
	if not s.entrance_armed is bool or not s.return_reason is String or (s.status == "returned") != (s.return_reason in ["retreat","completed","defeated","timeout","entrance"]): return "返程状态非法"
	if s.status != "returned" and s.return_reason != "": return "尚未返程却有返程原因"
	if not s.player is Dictionary or not s.input is Dictionary: return "玩家或输入非法"
	var p: Dictionary = s.player
	if not p.has_all(["x","y","hp","shield","aim_x","aim_y","cast_cooldown_ms","dodge_cooldown_ms","skill_cooldown_ms","dodge_remaining_ms","dodge_x","dodge_y","hurt_ms","skill_flash_ms"]): return "玩家状态不完整"
	if not _coordinates(p) or not _integer(p.hp,0,3) or not p.shield is bool: return "玩家生命或位置非法"
	if (p.hp == 0) != (s.status == "returned" and s.return_reason == "defeated"): return "玩家生命与返程状态不一致"
	for key in ["aim_x","aim_y","dodge_x","dodge_y"]:
		if not _finite_axis(p[key]): return "玩家方向非法"
	for key in ["cast_cooldown_ms","dodge_cooldown_ms","skill_cooldown_ms","dodge_remaining_ms","hurt_ms","skill_flash_ms"]:
		if not _integer(p[key],0,3000): return "玩家冷却非法"
	if not s.input.has_all(_input().keys()): return "保持输入不完整"
	var input_check = s.duplicate(true)
	if not set_input(input_check,s.input).ok: return "保持输入非法"
	if not s.enemies is Array or not s.projectiles is Array or not s.drops is Array: return "动作实体数组非法"
	if s.enemies.size() != (3 if s.day == 1 else 4) or s.projectiles.size() > 32 or s.drops.size() > s.enemies.size(): return "动作实体数量非法"
	var enemies = {}
	var expected_ids = ["m0","m1","m2","m3"] if s.day == 2 else (["m0","m1","m2","elite"] if s.day == 3 else ["m0","m1","m2"])
	for e in s.enemies:
		if not e is Dictionary or not e.has_all(["id","kind","x","y","hp","state","telegraph","shielded","timer_ms","exposed_ms","direction_x","direction_y","attack_index","attack_hit","wave_radius","hit_casts","drop_spawned"]): return "敌人状态不完整"
		if not e.id is String or e.id not in expected_ids or enemies.has(e.id) or not _coordinates(e) or e.kind not in ["sparkcap","moonheart"]: return "敌人身份非法"
		if (e.kind == "moonheart") != (s.day == 3 and e.id == "elite"): return "精英配置非法"
		if not _integer(e.hp,0,4 if e.kind == "moonheart" else 2) or e.state not in ["idle","telegraph","dash","wave","defeated"] or (e.hp == 0) != (e.state == "defeated"): return "敌人生命/阶段非法"
		if not e.shielded is bool or not e.attack_hit is bool or not e.drop_spawned is bool or e.drop_spawned != (e.hp == 0): return "敌人掉落/护盾非法"
		if e.shielded != (e.kind == "moonheart" and e.hp > 0 and e.exposed_ms == 0): return "精英护盾不一致"
		if not _integer(e.timer_ms,0,1500) or not _integer(e.exposed_ms,0,1000) or not _integer(e.attack_index,0,10000) or not _number(e.wave_radius,0,180): return "敌人计时非法"
		if not _finite_axis(e.direction_x) or not _finite_axis(e.direction_y) or not e.hit_casts is Array: return "敌人方向/碰撞记录非法"
		var hits = {}
		for cast_id in e.hit_casts:
			if not _integer(cast_id,1,int(s.next_cast)-1) or hits.has(str(cast_id)): return "重复施法命中身份"
			hits[str(cast_id)] = true
		if not e.telegraph is Dictionary: return "敌人预警非法"
		if e.state == "telegraph":
			var t: Dictionary = e.telegraph
			if not t.has_all(["shape","direction_x","direction_y","radius","angle_degrees","remaining_ms"]) or t.shape not in ["cone","ring"]: return "敌人预警缺字段"
			if not _finite_axis(t.direction_x) or not _finite_axis(t.direction_y) or not _number(t.radius,0,180) or not _number(t.angle_degrees,0,360) or t.remaining_ms != e.timer_ms: return "预警与攻击不一致"
		elif not e.telegraph.is_empty(): return "非预警阶段保留预警"
		enemies[e.id] = e
	var projectile_ids = {}
	for b in s.projectiles:
		if not b is Dictionary or not b.has_all(["id","cast_id","x","y","vx","vy","remaining"]): return "弹体缺少字段"
		if not _integer(b.id,1,int(s.next_projectile)-1) or projectile_ids.has(str(b.id)) or not _integer(b.cast_id,1,int(s.next_cast)-1) or not _coordinates(b): return "弹体身份/位置非法"
		if not _number(b.vx,-360,360) or not _number(b.vy,-360,360) or not _number(b.remaining,0,300): return "弹体运动非法"
		projectile_ids[str(b.id)] = true
	var drop_ids = {}
	for d in s.drops:
		if not d is Dictionary or not d.has_all(["id","enemy_id","item_id","x","y","collected","blocked"]): return "掉落缺少字段"
		if not d.enemy_id is String or not enemies.has(d.enemy_id) or not d.collected is bool or not d.blocked is bool or not _coordinates(d): return "掉落属性非法"
		if d.id != "%d:%s:%s" % [s.day,s.run_id,d.enemy_id] or drop_ids.has(d.id) or enemies[d.enemy_id].hp != 0 or d.item_id != enemies[d.enemy_id].kind: return "掉落身份或来源非法"
		drop_ids[d.id] = true
	for e in s.enemies:
		if e.drop_spawned and not drop_ids.has("%d:%s:%s" % [s.day,s.run_id,e.id]): return "击败敌人缺少掉落"
	if s.status == "cleared":
		for e in s.enemies:
			if e.hp > 0: return "未击败全部敌人却已清场"
	return ""
