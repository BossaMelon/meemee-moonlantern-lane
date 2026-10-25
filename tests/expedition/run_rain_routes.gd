extends SceneTree
const Model = preload("res://game/expedition/expedition_model.gd")
const Driver = preload("res://tests/expedition/rain_driver.gd")
const OldDriver = preload("res://tests/expedition/action_driver.gd")
var failures: Array = []
var checks = 0
var traces: Array = []
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize():
	var day_value = 2 if "--day2" in OS.get_cmdline_user_args() else 1
	for route in ["shelf","canal"]:
		for seed_value in [1,7,23,99,20261025]:
			var s = Model.create(day_value,"route-%s-%d" % [route,seed_value],seed_value,"bolt_wand" if route == "shelf" else "fan_wand",["gust"],false,{"ruleset":"rain-night-v1","map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null})
			var driver = Driver.new(route,false)
			var pickups: Array = []; var events: Array = []; var track: Array = []
			for i in range(2400):
				Model.set_input(s,driver.next_input(s))
				var r = Model.advance(s,50)
				pickups.append_array(r.pickups); events.append_array(r.events)
				if i % 20 == 0: track.append({"tick":s.tick,"x":s.player.x,"y":s.player.y,"hp":s.player.hp})
				if i % 20 == 0: expect(Model.validate(s) == "","route state valid %s seed%d tick%d: %s" % [route,seed_value,s.tick,Model.validate(s)])
				if s.status == "returned": break
			expect(s.status == "returned" and s.return_reason == "entrance" and s.player.hp > 0,"normal %s route returns alive seed%d" % [route,seed_value])
			expect(pickups.size() >= (1 if route == "shelf" else 2),"normal %s route gathers finite material seed%d" % [route,seed_value])
			var summary = {"route":route,"day":day_value,"seed":seed_value,"status":s.status,"reason":s.return_reason,"elapsed_ms":s.elapsed_ms,"hp":s.player.hp,"pickups":pickups,"events":events,"track":track}
			traces.append(summary)
			print("route ",route," seed",seed_value," ",s.status,"/",s.return_reason," hp",s.player.hp," ms",s.elapsed_ms," pickups",pickups.size())
	# Honest unchanged old strategy comparison; its observed outcome is recorded, not required to fail.
	var legacy_strategy = Model.create(1,"old-strategy",23,"bolt_wand",["gust"],false,{"ruleset":"rain-night-v1","map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null})
	var old_pickups: Array = []
	for i in range(2400):
		Model.set_input(legacy_strategy,OldDriver.next_input(legacy_strategy))
		old_pickups.append_array(Model.advance(legacy_strategy,50).pickups)
		if legacy_strategy.status == "returned": break
	var old_result = {"route":"unchanged-e01-driver","elapsed_ms":legacy_strategy.elapsed_ms,"status":legacy_strategy.status,"reason":legacy_strategy.return_reason,"hp":legacy_strategy.player.hp,"pickups":old_pickups,"position":{"x":legacy_strategy.player.x,"y":legacy_strategy.player.y}}
	traces.append(old_result); print(old_result)
	var file = FileAccess.open("/tmp/e02-rain-routes-day%d.json" % day_value,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"traces":traces},"  "))
	print("E02 rain routes: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
