extends SceneTree
## Normal inputs deliberately observe the deep cast before countering it.
const Model = preload("res://game/expedition/expedition_model.gd")
const Driver = preload("res://tests/expedition/rain_driver.gd")
var checks = 0
var failures: Array = []
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize():
	for route in ["shelf","canal"]:
		var s = Model.create(1,"deep-"+route,23,"bolt_wand" if route == "shelf" else "fan_wand",["gust"],false,{"ruleset":"rain-night-v1","map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null})
		var driver = Driver.new(route,true,true)
		var events: Array = []; var track: Array = []; var pickups: Array = []
		var combined_spore = false
		var snapshots: Dictionary = {}
		for i in range(3600):
			var input = driver.next_input(s)
			Model.set_input(s,input)
			var result = Model.advance(s,50)
			events.append_array(result.events); pickups.append_array(result.pickups)
			if i % 20 == 0:
				track.append({"tick":s.tick,"x":s.player.x,"y":s.player.y,"hp":s.player.hp,"input":input})
				expect(Model.validate(s) == "","deep route snapshot valid "+route)
			for hazard in s.hazards:
				if hazard.source == "deep-caster" and s.enemies[3].hp > 0 and s.enemies[3].engaged:
					if hazard.state == "active": combined_spore = true
					if not snapshots.has(hazard.state): snapshots[hazard.state] = s.duplicate(true)
			if s.enemies[3].state == "stagger" and not snapshots.has("stagger"): snapshots.stagger = s.duplicate(true)
			if s.status == "returned": break
		expect(s.status == "returned" and s.return_reason == "entrance" and s.player.hp > 0,"deep route returns alive "+route)
		expect(pickups.any(func(p): return p.item_id == "moonheart"),"real defeated elite drop collected "+route)
		expect(combined_spore,"active deep spores actually coexist with engaged living shield elite "+route)
		expect(events.any(func(e): return e.type == "spore_cleared" and e.source == "deep-caster"),"real gust clears deep caster zone "+route)
		for name in snapshots:
			var a: Dictionary = snapshots[name].duplicate(true)
			var b: Dictionary = JSON.parse_string(JSON.stringify(a))
			Model.clear_input(a); Model.clear_input(b)
			Model.advance(a,337); Model.advance(b,337)
			expect(a == b,"combined "+name+" exact JSON continuation "+route)
		var report = {"route":route,"status":s.status,"reason":s.return_reason,"hp":s.player.hp,"elapsed_ms":s.elapsed_ms,"pickups":pickups,"events":events,"track":track,"snapshots":snapshots,"state":s}
		var file = FileAccess.open("/tmp/e02-deep-"+route+".json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  "))
		print(route," ",s.status,"/",s.return_reason," hp",s.player.hp," ms",s.elapsed_ms," pickups",pickups.size())
	print("E02 deep combination: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
