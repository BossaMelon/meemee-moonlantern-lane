extends RefCounted
const Model = preload("res://game/expedition/expedition_model.gd")
const Rain = preload("res://game/expedition/rain_garden_model.gd")
const Map = preload("res://game/expedition/rain_garden_map.gd")
const ReturnBoundaries = preload("res://tests/expedition/return_boundary_cases.gd")
var checks = 0
var failures: Array = []
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)
func options(meal: Variant = null) -> Dictionary:
	return {"ruleset":"rain-night-v1","map_id":Map.MAP_ID,"map_revision":1,"meal_effect":meal}
func make(meal: Variant = null, day: int = 1) -> Dictionary:
	return Model.create(day,"rain-test",23,"bolt_wand",["gust"],false,options(meal))
func hold(s: Dictionary, args: Dictionary = {}):
	expect(Model.set_input(s,args).ok,"input accepted")
func valid(s: Dictionary, label: String):
	var error = Model.validate(s)
	expect(error == "",label+": "+error)
func events(result: Dictionary, type: String) -> Array:
	return result.events.filter(func(e): return e.type == type)
func freeze(s: Dictionary):
	for e in s.enemies: e.engaged = false
func run() -> Dictionary:
	var s = make()
	valid(s,"new quality state")
	expect(s.version == 2 and s.remaining_ms == null and s.elapsed_ms == 0 and s.meal_effect == null,"typed quality public state")
	expect(Model.create(1,"old").version == 1,"empty options retain legacy model")
	for bad in [null,[],true,{"ruleset":"rain-night-v1"}]: expect(Model.create(1,"bad",1,"bolt_wand",["gust"],false,bad).is_empty(),"invalid options reject without state")
	for field in ["map_revision","ruleset","map_id","meal_effect"]:
		var bad = options(); bad[field] = true
		expect(Model.create(1,"bad",1,"bolt_wand",["gust"],false,bad).is_empty(),"invalid typed option rejects "+field)
	for meal in [{"effect_id":"light_step","source_item_uid":1,"used":true},{"effect_id":"clear_breath","source_item_uid":true,"used":false},{"effect_id":"wrong","source_item_uid":1,"used":false}]: expect(make(meal).is_empty(),"invalid meal rejected")
	var observed: Array = []
	for i in range(45):
		observed.append_array(Model.advance(s,50).events)
		valid(s,"entry simulation step %d" % i)
	var stagger = observed.filter(func(e): return e.type == "enemy_staggered")
	expect(stagger.size() == 1 and stagger[0].obstacle_id == "entry-stump","natural entry rush hits stump once")
	expect(s.enemies[0].state == "idle" and s.enemies[0].attack_index == 1,"stagger expires without repeated refresh")
	var records = s.collision_records.filter(func(e): return e.entity_id == "entry-rush" and e.motion == "dash")
	expect(records.size() == 1,"stable one collision identity per blocked dash")
	# Continuous body sweeps through public advance: walking and dodge both stop.
	s = make(); freeze(s); s.player.x = 210.0
	hold(s,{"move_x":1.0}); Model.advance(s,500)
	expect(s.player.x <= 223.0001 and Map.point_clear(Vector2(s.player.x,s.player.y),12),"walk cannot penetrate stump")
	hold(s,{"move_x":1.0,"dodge":true}); Model.advance(s,250)
	expect(s.player.x <= 223.0001 and s.player.dodge_remaining_ms == 0,"dodge stops at stump")
	valid(s,"body collision snapshot")
	# Water and spores slow walking equally, while dodge speed stays unchanged.
	var dry = make(); freeze(dry); dry.player.x = 380; dry.player.y = 320
	var wet = make(); freeze(wet); wet.player.x = 380; wet.player.y = 390
	hold(dry,{"move_x":1.0}); hold(wet,{"move_x":1.0})
	Model.advance(dry,50); Model.advance(wet,50)
	expect(absf(dry.player.x-388) < 0.001 and absf(wet.player.x-385.2) < 0.001,"water changes real walk distance")
	hold(dry,{"move_x":1.0,"dodge":true}); hold(wet,{"move_x":1.0,"dodge":true})
	var dx = dry.player.x; var wx = wet.player.x
	Model.advance(dry,50); Model.advance(wet,50)
	expect(absf(dry.player.x-dx-15) < 0.001 and absf(wet.player.x-wx-15) < 0.001,"water does not slow dodge")
	# A live caster locks a warning then activates after exactly 800ms.
	s = make(); s.player.x = 635; s.player.y = 405
	var caster = s.enemies[2]; caster.engaged = true; caster.timer_ms = 0
	var result = Model.advance(s,450)
	expect(s.hazards.size() == 1 and s.hazards[0].state == "warning" and s.hazards[0].remaining_ms == 800,"spore warning and flight created together")
	valid(s,"flying spore snapshot")
	var hpos = Vector2(s.hazards[0].x,s.hazards[0].y)
	hold(s,{"move_y":-1.0}); Model.advance(s,750)
	expect(s.hazards[0].state == "warning" and s.hazards[0].remaining_ms == 50 and Vector2(s.hazards[0].x,s.hazards[0].y) == hpos,"warning remains locked despite player movement")
	Model.advance(s,50)
	expect(s.hazards[0].state == "active" and s.hazards[0].remaining_ms == 3000,"warning activates at exact boundary")
	valid(s,"active spore snapshot")
	# One zone hurts once across leaving/re-entry. Other enemies stay unengaged in isolated fixture.
	freeze(s); s.player.x = hpos.x; s.player.y = hpos.y; hold(s)
	var hp = s.player.hp; Model.advance(s,50)
	expect(s.player.hp == hp-1 and s.hazards[0].hit_player,"spore consumes one contact")
	s.player.y -= 100; Model.advance(s,50); s.player.y += 100; Model.advance(s,50)
	expect(s.player.hp == hp-1,"leaving and reentering zone cannot repeat damage")
	# Gust clears active only and reports real IDs, leaving warnings/projectiles intact.
	var clear_id = s.hazards[0].id
	Rain._throw_spore(s,caster,Rain._result())
	var warning_id = s.hazards[-1].id; var projectile_count = s.projectiles.size()
	result = Rain._result(); Rain._gust(s,result)
	expect(s.hazards.size() == 1 and s.hazards[0].id == warning_id and s.projectiles.size() == projectile_count,"gust keeps warning and emitted projectile")
	expect(events(result,"spore_cleared").size() == 1 and events(result,"spore_cleared")[0].hazard_id == clear_id,"gust identifies cleared active zone")
	valid(s,"gust mixed state snapshot")
	# Elite collision opens a 1200ms window; ordinary push does not apply stagger.
	s = make(); freeze(s)
	var elite = s.enemies[3]; elite.engaged = true; elite.x = 670; elite.y = 250
	elite.state = "dash"; elite.timer_ms = 500; elite.direction_x = 1; elite.direction_y = 0
	elite.attack_index = 1; elite.attack_id = "%s:%s:a1" % [s.run_id,elite.id]
	result = Model.advance(s,100)
	expect(elite.state == "stagger" and elite.stagger_remaining_ms == 1200 and not elite.shielded,"elite dash into rect breaks shield for exact stagger")
	expect(events(result,"enemy_staggered").size() == 1,"elite stagger event emitted once")
	valid(s,"elite stagger snapshot")
	var saved_stagger: Dictionary = JSON.parse_string(JSON.stringify(s))
	Model.advance(s,357); Model.advance(saved_stagger,357)
	expect(s == saved_stagger and elite.stagger_remaining_ms == 850,"stagger continuation preserves identity/time")
	s = make(); freeze(s); s.player.x = 180
	var pushed = s.enemies[0]; pushed.x = 210; pushed.y = 270
	result = Rain._result(); Rain._gust(s,result)
	expect(pushed.x <= 218.001 and pushed.state != "stagger" and events(result,"enemy_staggered").is_empty(),"gust push stops at stump without dash stagger")
	# An emitted elite wave survives gust and does not restart its radius/timer.
	s = make(); freeze(s); elite = s.enemies[3]; elite.x = 800; elite.y = 350; elite.state = "wave"; elite.timer_ms = 800; elite.wave_radius = 36
	elite.attack_index = 2; elite.attack_id = "%s:%s:a2" % [s.run_id,elite.id]
	s.player.x = 840; s.player.y = 350
	result = Rain._result(); Rain._gust(s,result)
	expect(elite.state == "wave" and elite.timer_ms == 800 and elite.wave_radius == 36,"gust leaves emitted elite ring active")
	# Both projectile owners are blocked before reaching an actor/landing behind a stump.
	s = make(); freeze(s); s.player.x = 200; s.player.y = 270
	var rush = s.enemies[0]; rush.x = 330
	hold(s,{"aim_x":1.0,"cast":true}); result = Model.advance(s,500)
	expect(rush.hp == 2 and events(result,"obstacle_hit").any(func(e): return e.motion == "bolt"),"stump blocks player projectile before enemy")
	s = make(); freeze(s); caster = s.enemies[2]; caster.x = 330; caster.y = 270; s.player.x = 200
	result = Rain._result(); Rain._throw_spore(s,caster,result)
	Model.advance(s,800)
	expect(s.hazards.is_empty() and s.projectiles.is_empty(),"stump cancels enemy projectile landing without active spores")
	valid(s,"blocked enemy projectile state")
	# Real idle movement takes the same water scale; dash is independent of water.
	var e_dry = make(); var e_wet = make(); freeze(e_dry); freeze(e_wet)
	for pair in [[e_dry,480.0],[e_wet,365.0]]:
		var entity: Dictionary = pair[0].enemies[0]
		entity.engaged = true; entity.x = 380; entity.y = pair[1]; entity.timer_ms = 1500
		pair[0].player.x = 650; pair[0].player.y = pair[1]
	Model.advance(e_dry,50); Model.advance(e_wet,50)
	expect(absf(e_dry.enemies[0].x-381.75) < 0.001 and absf(e_wet.enemies[0].x-381.1375) < 0.001,"enemy walking respects water speed")
	for model in [e_dry,e_wet]:
		model.enemies[0].state = "dash"; model.enemies[0].timer_ms = 500; model.enemies[0].direction_x = 1; model.enemies[0].direction_y = 0
	dx = e_dry.enemies[0].x; wx = e_wet.enemies[0].x
	Model.advance(e_dry,50); Model.advance(e_wet,50)
	expect(absf(e_dry.enemies[0].x-dx-11) < 0.001 and absf(e_wet.enemies[0].x-wx-11) < 0.001,"enemy dash ignores water")
	s = make(); freeze(s); s.player.x = 223; s.player.y = 270
	s.enemies[0].engaged = true; s.enemies[0].timer_ms = 1500; s.enemies[0].x = 500; s.enemies[0].y = 400
	Model.advance(s,50)
	expect(not s.enemies[0].path.is_empty(),"larger enemy can navigate toward player hugging smaller footprint boundary")
	valid(s,"wall-hug navigation state")
	# Food extends the first valid action, never a request in cooldown.
	s = make({"effect_id":"light_step","source_item_uid":42,"used":false}); freeze(s)
	s.player.dodge_cooldown_ms = 100
	hold(s,{"move_y":-1.0,"dodge":true}); Model.advance(s,50)
	expect(not s.meal_effect.used,"cooldown dodge does not consume meal")
	result = Model.advance(s,50)
	expect(s.meal_effect.used and s.player.dodge_remaining_ms == 250 and events(result,"dodge")[0].duration_ms == 300,"first valid dodge uses 300ms food")
	Model.advance(s,1200)
	expect(s.player.dodge_remaining_ms <= 150,"later dodge uses ordinary duration")
	valid(s,"food action snapshot")
	s = make({"effect_id":"clear_breath","source_item_uid":43,"used":false}); freeze(s)
	hold(s,{"skill":true}); result = Model.advance(s,50)
	expect(s.meal_effect.used and events(result,"skill")[0].range == 160 and s.player.skill_range == 160,"first gust consumes range food")
	var flash_restored: Dictionary = JSON.parse_string(JSON.stringify(s))
	valid(flash_restored,"food flash JSON state")
	expect(Model.view(flash_restored).player.skill_range == 160 and flash_restored.player.skill_flash_ms > 0,"resumed first gust retains actual visual radius")
	result = Model.advance(s,3000)
	expect(events(result,"skill").size() == 1 and events(result,"skill")[0].range == 120 and s.player.skill_range == 120,"later gust returns to normal range")
	# Finite pickup identities/capacity and save/load prohibit regeneration.
	s = make(); freeze(s); s.player.x = 415; s.player.y = 95
	result = Model.advance(s,50,0)
	expect(result.pickups.is_empty() and not s.resource_nodes[0].collected,"full inventory leaves node available")
	result = Model.advance(s,50,1)
	expect(result.pickups.size() == 1 and result.pickups[0].drop_id == "resource:shelf-patch" and s.resource_nodes[0].collected,"resource uses typed stable pickup identity")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(s))
	valid(loaded,"JSON resource state")
	expect(Model.advance(loaded,50).pickups.is_empty(),"restored collected node does not duplicate")
	# No 180-second return in an isolated safe fixture; elapsed is statistics.
	s = make(); freeze(s)
	for i in range(4): Model.advance(s,60000)
	expect(s.status == "active" and s.elapsed_ms == 240000 and s.remaining_ms == null,"quality has no legacy timeout")
	valid(s,"long elapsed state")
	# Deterministic continuation and fixed-step remainder across five prescribed seeds.
	for seed_value in [1,7,23,99,20261025]:
		for day in [1,2]:
			var a = Model.create(day,"deterministic",seed_value,"bolt_wand",["gust"],false,options())
			var b = a.duplicate(true)
			hold(a,{"move_y":-1.0,"aim_x":1.0,"cast":true})
			hold(b,a.input)
			Model.advance(a,1237)
			for ms in [13,41,89,7,1087]: Model.advance(b,ms)
			expect(a == b,"same fixed-step state across frame partition seed %d day%d" % [seed_value,day])
			var restored: Dictionary = JSON.parse_string(JSON.stringify(a))
			valid(restored,"JSON deterministic seed%d day%d" % [seed_value,day])
			Model.advance(a,713); Model.advance(restored,713)
			expect(a == restored,"JSON continuation exact seed%d day%d" % [seed_value,day])
			var before = a.duplicate(true); Model.advance(a,1000,80,true)
			expect(a == before,"pause freezes full state")
			for field in ["map_id","map_revision","terrain","meal_effect","elapsed_ms"]:
				var bad = a.duplicate(true); bad[field] = false
				expect(Model.validate(bad) != "","corrupt state rejected "+field)
	# Every persisted primitive/container has a type rejection before arithmetic.
	var fixtures: Array = [make()]
	var flying = make(); flying.player.x = 635; flying.player.y = 405; flying.enemies[2].engaged = true; flying.enemies[2].timer_ms = 0
	Model.advance(flying,450); fixtures.append(flying)
	for model in fixtures:
		for section in ["", "player", "enemies", "hazards", "projectiles", "resource_nodes"]:
			var source: Dictionary = model if section == "" else (model[section] if section == "player" else (model[section][0] if not model[section].is_empty() else {}))
			for field in source:
				if source[field] == null: continue
				var bad = model.duplicate(true)
				var target: Dictionary = bad if section == "" else (bad[section] if section == "player" else bad[section][0])
				target[field] = null if source[field] is bool else false
				expect(Model.validate(bad) != "","malformed persisted type rejected %s.%s" % [section,field])
	var boundaries = ReturnBoundaries.new().run(Callable(),"/tmp/e02-rain-model-returns")
	checks += boundaries.checks
	failures.append_array(boundaries.failures)
	print("E02 rain model: ",checks," checks, ",failures.size()," failures")
	return {"checks":checks,"failures":failures.duplicate()}
