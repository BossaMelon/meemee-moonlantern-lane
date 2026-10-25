extends RefCounted
const Model = preload("res://game/expedition/expedition_model.gd")
const ExpeditionPanel = preload("res://game/expedition/expedition_panel.gd")
const Driver = preload("res://tests/expedition/action_driver.gd")
var failures: Array = []
var checks = 0

func expect(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> Dictionary:
	var s = Model.create(1,"test",1)
	expect(Model.validate(s) == "","initial state valid: "+Model.validate(s))
	var before = s.duplicate(true)
	expect(not Model.set_input(s,{"move_x":NAN}).ok and s == before,"nonfinite input rejected atomically")
	expect(not Model.set_input(s,{"skill":true}).ok and s == before,"locked skill rejected atomically")
	Model.set_input(s,{"move_x":1.0,"move_y":1.0,"aim_x":1.0,"cast":true})
	var split = s.duplicate(true)
	Model.advance(s,1000)
	for amount in [17,33,121,79,311,89,350]: Model.advance(split,amount)
	expect(s == split,"fixed-step frame partitions equal")
	expect(Model.validate(s) == "","advanced state valid: "+Model.validate(s))
	expect(Vector2(s.player.x-80.0,s.player.y-270.0).length() < 161.0,"diagonal movement normalized")
	before = s.duplicate(true)
	Model.advance(s,60000,80,true)
	expect(s == before,"pause freezes full state and remainder")
	var copy = JSON.parse_string(JSON.stringify(s))
	expect(Model.validate(copy) == "","JSON float state roundtrip valid: "+Model.validate(copy))
	Model.clear_input(s)
	Model.clear_input(copy)
	Model.set_input(s,{"aim_x":1.0,"cast":true})
	Model.set_input(copy,{"aim_x":1.0,"cast":true})
	Model.advance(s,837)
	Model.advance(copy,837)
	if s != copy: diff(s,copy,"root")
	expect(s == copy,"JSON resume equals continuous branch after reinput")
	boundaries()
	for seed_value in [1,7,23,99,2026]:
		for day in [1,2,3]:
			var combat = Model.create(day,"seed-%d-day-%d" % [seed_value,day],seed_value,"fan_wand" if day > 1 else "bolt_wand",["gust"] if day > 1 else [],day == 3)
			var pickups: Array = []
			var events: Array = []
			while combat.status in ["active","cleared"]:
				Model.set_input(combat,Driver.next_input(combat))
				var step = Model.advance(combat,50)
				pickups.append_array(step.pickups)
				events.append_array(step.events)
				var error = Model.validate(combat)
				if error != "": expect(false,error); break
			print("seed ",seed_value," day ",day," outcome ",combat.return_reason," hp ",combat.player.hp," tick ",combat.tick," pickups ",pickups.size())
			expect(combat.return_reason == "completed","strategy completes real combat %d/%d" % [seed_value,day])
			expect(pickups.size() == (3 if day == 1 else 4),"all distinct drops picked up")
			expect(Model.advance(combat,5000).pickups.is_empty(),"returned simulation cannot grant again")
	print("E01 model: %d checks, %d failures" % [checks,failures.size()])
	return {"checks":checks,"failures":failures}

func boundaries():
	var s = Model.create(2,"boundaries",7,"fan_wand",["gust"])
	expect(Model.validate(s) == "","second-day initial state validates")
	# Controlled geometry fixtures exercise collision boundaries, never supply economy rewards.
	for e in s.enemies:
		e.x = 800; e.y = 450; e.timer_ms = 1500
	s.player.x = 400; s.player.y = 270
	var target: Dictionary = s.enemies[0]
	target.x = 450; target.y = 270
	Model.set_input(s,{"aim_x":1.0,"cast":true})
	var result = Model.advance(s,100)
	expect(target.hp == 1,"fan's three projectiles damage each enemy at most once per cast")
	expect(s.projectiles.size() <= 3,"fan emits three spatial projectiles")
	var single = Model.create(1,"range",1)
	for e in single.enemies: e.x = 700; e.y = 450; e.timer_ms = 1500
	single.player.x = 100; single.player.y = 270
	Model.set_input(single,{"aim_x":-1.0,"cast":true})
	Model.advance(single,1000)
	for e in single.enemies: expect(e.hp == 2,"missed and out-of-range shots do not damage")
	# Keep a single charge overlapping the player for several ticks.
	var attack = Model.create(1,"attack",1)
	for e in attack.enemies: e.x = 900; e.y = 500; e.timer_ms = 1500
	attack.player.x = 400; attack.player.y = 270
	var charger: Dictionary = attack.enemies[0]
	charger.x = 380; charger.y = 270; charger.state = "dash"; charger.timer_ms = 500; charger.direction_x = 1.0; charger.direction_y = 0.0
	var shielded = attack.duplicate(true)
	shielded.player.shield = true
	var evasion = attack.duplicate(true)
	Model.set_input(evasion,{"move_y":1.0,"dodge":true})
	Model.advance(attack,200)
	var shield_result = Model.advance(shielded,200)
	Model.advance(evasion,200)
	expect(attack.player.hp == 2,"same charge hits at most once across overlapping frames")
	expect(shielded.player.hp == 3 and not shielded.player.shield,"food shield absorbs one actual collision")
	expect(shield_result.events.any(func(e): return e.type == "shield_absorbed"),"shield event records actual attack")
	expect(evasion.player.hp == 3,"dodge through charge avoids actual collision")
	# A later distinct attack consumes health after the shield was spent.
	charger = shielded.enemies[0]
	charger.x = shielded.player.x-20; charger.y = shielded.player.y; charger.state = "dash"; charger.timer_ms = 500; charger.attack_hit = false
	Model.advance(shielded,50)
	expect(shielded.player.hp == 2,"shield cannot absorb a second attack")
	var elite = Model.create(3,"elite",1,"fan_wand",["gust"])
	for e in elite.enemies: e.x = 900; e.y = 500; e.timer_ms = 1500
	var boss: Dictionary = elite.enemies[3]
	elite.player.x = 400; elite.player.y = 270
	boss.x = 480; boss.y = 270; boss.direction_x = -1.0; boss.direction_y = 0.0
	Model.set_input(elite,{"aim_x":1.0,"cast":true})
	var blocked = Model.advance(elite,200)
	expect(boss.hp == 4 and blocked.events.any(func(e): return e.type == "blocked"),"elite front shield blocks actual projectiles")
	Model.set_input(elite,{"aim_x":1.0,"skill":true,"cast":true})
	result = Model.advance(elite,50)
	expect(boss.x > 550 and boss.exposed_ms > 0 and not boss.shielded,"gust pushes elite and opens shield")
	var cooldown = elite.player.skill_cooldown_ms
	result = Model.advance(elite,50)
	expect(elite.player.skill_cooldown_ms < cooldown and not result.events.any(func(e): return e.type == "skill"),"holding skill respects independent cooldown")
	# Ring persists after gust, unlike an interrupted cone warning.
	boss.x = elite.player.x+80; boss.y = elite.player.y; boss.state = "wave"; boss.timer_ms = 900; boss.telegraph = {}; boss.wave_radius = 18.0
	elite.player.skill_cooldown_ms = 0
	Model.advance(elite,50)
	expect(boss.state == "wave" and boss.wave_radius > 18,"gust does not cancel an emitted ring")
	boss.state = "telegraph"; boss.timer_ms = 800
	boss.telegraph = {"shape":"cone","direction_x":-1.0,"direction_y":0.0,"radius":165.0,"angle_degrees":40.0,"remaining_ms":800}
	boss.x = elite.player.x+80; elite.player.skill_cooldown_ms = 0
	Model.advance(elite,50)
	expect(boss.state == "idle" and boss.telegraph.is_empty(),"gust interrupts a charge telegraph")
	var rear = Model.create(3,"rear",1)
	for e in rear.enemies: e.x = 900; e.y = 500; e.timer_ms = 1500
	rear.player.x = 400; rear.player.y = 270
	var rear_boss: Dictionary = rear.enemies[3]
	rear_boss.x = 480; rear_boss.y = 270; rear_boss.direction_x = 1.0; rear_boss.direction_y = 0.0
	rear_boss.state = "telegraph"; rear_boss.timer_ms = 800
	rear_boss.telegraph = {"shape":"cone","direction_x":1.0,"direction_y":0.0,"radius":165.0,"angle_degrees":40.0,"remaining_ms":800}
	Model.set_input(rear,{"aim_x":1.0,"cast":true})
	Model.advance(rear,200)
	expect(rear_boss.hp == 3,"rear projectile bypasses elite's locked front shield")
	var wave = Model.create(3,"wave",1)
	for e in wave.enemies: e.x = 900; e.y = 500; e.timer_ms = 1500
	wave.player.x = 400; wave.player.y = 270
	var wave_boss: Dictionary = wave.enemies[3]
	wave_boss.x = 460; wave_boss.y = 270; wave_boss.state = "wave"; wave_boss.timer_ms = 1000; wave_boss.wave_radius = 36.0
	var wave_dodge = wave.duplicate(true)
	Model.set_input(wave_dodge,{"move_x":1.0,"dodge":true})
	Model.advance(wave,150); Model.advance(wave_dodge,150)
	expect(wave.player.hp == 2 and wave_dodge.player.hp == 3,"expanding wave really hits, dodge crosses it safely")
	var patterns = Model.create(3,"patterns",1)
	patterns.player.x = 12; patterns.player.y = 12
	result = Model.advance(patterns,6500)
	var boss_shapes: Array = []
	for event in result.events:
		if event.type == "telegraph" and event.entity_id == "elite": boss_shapes.append(event.shape)
	expect(boss_shapes.size() >= 2 and boss_shapes[0] == "cone" and boss_shapes[1] == "ring","elite alternates two distinct attack warnings")
	# Full-capacity pickup remains physically available; later capacity commits once.
	var clear = Model.create(1,"capacity",23)
	while clear.status == "active":
		Model.set_input(clear,Driver.next_input(clear))
		Model.advance(clear,50,0)
	expect(clear.status == "cleared" and clear.drops.size() == 3,"last defeat enters movable cleared state with last drop")
	var pickups: Array = []
	while clear.status == "cleared":
		Model.set_input(clear,Driver.next_input(clear))
		pickups.append_array(Model.advance(clear,50,80).pickups)
	expect(pickups.size() == 3 and clear.return_reason == "completed","capacity retry collects all deferred drops exactly once")
	expect(Model.leave(clear).events.is_empty(),"repeated return emits no rewards")
	var timeout = Model.create(1,"timeout",1)
	# Retreat and time boundary preserve drop state; a stationary player can really die.
	var retreat = timeout.duplicate(true)
	expect(Model.leave(retreat).returned and retreat.return_reason == "retreat","active retreat returns immediately")
	Model.advance(timeout,60000)
	expect(timeout.status == "returned" and timeout.return_reason == "defeated","actual repeated enemy attacks defeat stationary player")
	var clock = Model.create(1,"clock",1)
	clock.player.x = 20; clock.player.y = 20
	for e in clock.enemies: e.x = 900; e.y = 500
	# Use ordinary evasion input so this checks the actual 180-second limit without immunity.
	while clock.status != "returned":
		var input = Driver.next_input(clock)
		input.cast = false
		Model.set_input(clock,input)
		Model.advance(clock,50)
	expect(clock.return_reason == "timeout","180-second limit returns surviving player")

func diff(a: Variant, b: Variant, path: String):
	if a is Dictionary and b is Dictionary:
		for key in a:
			if a[key] != b.get(key): diff(a[key],b.get(key),path+"."+str(key))
	elif a is Array and b is Array and a.size() == b.size():
		for i in range(a.size()):
			if a[i] != b[i]: diff(a[i],b[i],path+"["+str(i)+"]")
	else: print(path,": ",a," vs ",b," types ",typeof(a),"/",typeof(b))
