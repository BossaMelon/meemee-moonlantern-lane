extends RefCounted
## Component evidence only: real public inputs, no invented Session inventory.
const Model = preload("res://game/expedition/world_rain_model.gd")
const Rain = preload("res://game/expedition/rain_garden_model.gd")
const Legacy = preload("res://game/expedition/expedition_model.gd")
const Driver = preload("res://tests/expedition/rain_driver.gd")
const Output = preload("res://tests/expedition/return_boundary_cases.gd")
const CombatPanel = preload("res://game/expedition/expedition_panel.gd")
var checks = 0
var failures: Array = []
var traces: Array = []
var output = ""
var boundaries_complete = false

func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)

func options(profile: String = "world-slice-v1") -> Dictionary:
	return {"ruleset":profile,"map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null}

func make(day: Variant) -> Dictionary:
	return Model.create(day,"n%d-expedition" % int(day),23,"fan_wand",["gust"],false,options())

func roundtrip(s: Dictionary, label: String):
	var path = output.path_join(label+".json")
	var file = FileAccess.open(path,FileAccess.WRITE)
	expect(file != null,"open fresh component snapshot "+label)
	if file == null: return
	var stored = file.store_string(JSON.stringify(s)); file.close()
	expect(stored,"write component snapshot "+label)
	var reader = FileAccess.open(path,FileAccess.READ)
	expect(reader != null,"reopen component snapshot "+label)
	if reader == null: return
	var loaded = JSON.parse_string(reader.get_as_text()); reader.close()
	expect(Model.validate(loaded) == "" and Rain._same(loaded,s),"disk/JSON preserves complete World context and combat "+label)
	if not loaded is Dictionary: return
	var a = s.duplicate(true)
	Model.clear_input(a); Model.clear_input(loaded)
	Model.set_input(a,s.input); Model.set_input(loaded,s.input)
	var single = Model.advance(a,137)
	var first = Model.advance(loaded,50); var second = Model.advance(loaded,87)
	var split_pickups: Array = first.pickups+second.pickups
	expect(Rain._same(a,loaded) and single.pickups == split_pickups,"restored fixed-step continuation equals partitioned original "+label)
	var collected = []
	for drop in s.drops:
		if drop.collected: collected.append(drop.id)
	for node in s.resource_nodes:
		if node.collected: collected.append("resource:"+node.id)
	for pickup in split_pickups:
		expect(pickup.drop_id not in collected,"restored continuation never re-awards a collected identity "+label)

func boundaries():
	for day in [1,2]:
		var old = Rain.create(day,"old-%d" % day,23,"fan_wand",["gust"],false,options("rain-night-v1"))
		expect(not old.is_empty() and Rain.validate(old) == "","original Rain day%d remains valid" % day)
	expect(Rain.create(3,"old-3",23,"fan_wand",["gust"],false,options("rain-night-v1")).is_empty(),"original Rain day3 creation remains forbidden")
	var old_bad = Rain.create(2,"old-3",23,"fan_wand",["gust"],false,options("rain-night-v1")); old_bad.day = 3
	expect(Rain.validate(old_bad) != "","original Rain day3 snapshot remains forbidden")
	expect(Legacy.create(3,"legacy-3").version == 1,"legacy prototype retains its separate original day3 model")
	for day in [0,-1,1.5,NAN,INF,true,"3",[]]:
		expect(Model.create(day,"n3-expedition",23,"fan_wand",["gust"],false,options()).is_empty(),"bad campaign day rejects: "+str(day))
	expect(Model.create(3,"n2-expedition",23,"fan_wand",["gust"],false,options()).is_empty(),"campaign and run identity must agree")
	for bad in [options("rain-night-v1"),{},true,{"ruleset":"world-slice-v1","map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null,"campaign_day":3}]:
		expect(Model.create(3,"n3-expedition",23,"fan_wand",["gust"],false,bad).is_empty(),"mixed/missing/unversioned creation context rejects")
	for field in ["map_id","map_revision","meal_effect"]:
		var bad = options(); bad[field] = true
		expect(Model.create(3,"n3-expedition",23,"fan_wand",["gust"],false,bad).is_empty(),"invalid World option rejects "+field)
	var valid = make(3)
	for field in ["version","ruleset","day","encounter_day","run_id"]:
		for value in [null,true,{},3.5,"wrong"]:
			var bad = valid.duplicate(true); bad[field] = value
			expect(Model.validate(bad) != "","malformed World context rejects "+field+" "+str(value))
	for field in ["version","ruleset","encounter_day"]:
		var bad = valid.duplicate(true); bad[field] = 2 if field == "version" else ("rain-night-v1" if field == "ruleset" else 1)
		expect(Model.validate(bad) != "","old schema or lower encounter cannot masquerade as World: "+field)
	var extra = valid.duplicate(true); extra.campaign_day = 3
	expect(Model.validate(extra) != "","unrecognized campaign metadata is not silently erased")
	extra = valid.duplicate(true); extra.erase("encounter_day")
	expect(Model.validate(extra) != "","missing encounter context rejects")
	var lower = make(1); lower.day = 3; lower.encounter_day = 2; lower.run_id = "n3-expedition"
	expect(Model.validate(lower) != "","World day3 cannot reuse first-day resource configuration")
	expect(Model.validate(Rain.create(2,"n2-expedition",23,"fan_wand",["gust"],false,options("rain-night-v1"))) != "","raw Rain snapshots cannot load as World")
	expect(Rain.validate(valid) != "","World snapshots cannot load as old Rain")
	var panel = CombatPanel.new()
	for s in [make(1),make(2),make(3),make(6)]:
		panel.state = Model.view(s)
		expect(panel._is_rain_view() and panel.state.day == s.day and panel.state.remaining_ms == null,"existing panel selects elapsed-time World presentation day%d" % s.day)
	panel.state = Legacy.view(Legacy.create(3,"legacy-3"))
	expect(not panel._is_rain_view(),"legacy countdown presentation remains unchanged")
	panel.free()
	var retreat = make(6); Model.advance(retreat,37)
	var paused = retreat.duplicate(true); Model.advance(retreat,1000,80,true)
	expect(retreat == paused and retreat.remainder_ms == 37,"World pause retains full state and substep")
	expect(Model.leave(retreat).ok and retreat.remainder_ms == 0 and retreat.day == 6,"manual World return discards remainder and retains campaign day")
	roundtrip(retreat,"manual-day6")
	var before = retreat.duplicate(true); var again = Model.leave(retreat)
	expect(retreat == before and again.pickups.is_empty(),"manual World return is idempotent")
	boundaries_complete = true

func natural_route(day: int, ledger: Dictionary):
	var s = make(day)
	expect(not s.is_empty() and Model.validate(s) == "","World campaign initializes day%d" % day)
	if s.is_empty(): return
	var encounter_day = mini(day,2)
	var expected = Rain.create(encounter_day,s.run_id,23,"fan_wand",["gust"],false,options("rain-night-v1"))
	var projected = s.duplicate(true); projected.version = 2; projected.ruleset = "rain-night-v1"; projected.day = encounter_day; projected.erase("encounter_day")
	expect(projected == expected,"World day%d uses exact highest known Rain configuration" % day)
	roundtrip(s,"initial-day%d" % day)
	var driver = Driver.new("canal",true,true)
	var pickups: Array = []; var events: Array = []; var positions: Array = []
	var saved_pickup = false
	for i in range(3600):
		var accepted = Model.set_input(s,driver.next_input(s))
		var result = Model.advance(s,50)
		if not accepted.ok or not result.ok:
			expect(false,"public World input/advance failed day%d" % day); break
		pickups.append_array(result.pickups); events.append_array(result.events)
		for pickup in result.pickups:
			var key = s.run_id+"|"+pickup.drop_id
			expect(not ledger.has(key),"pickup identity is unique across campaigns/reloads: "+key)
			ledger[key] = {"campaign_day":day,"drop_id":pickup.drop_id}
		if not saved_pickup and not result.pickups.is_empty():
			roundtrip(s,"after-pickup-day%d" % day); saved_pickup = true
		if i == 100: roundtrip(s,"active-day%d" % day)
		if i % 20 == 0:
			expect(Model.validate(s) == "","natural World snapshot validates day%d tick%d" % [day,s.tick])
			positions.append({"tick":s.tick,"x":s.player.x,"y":s.player.y})
		if s.status == "returned": break
	expect(s.status == "returned" and s.return_reason == "entrance" and s.player.hp > 0,"natural World campaign route returns alive day%d" % day)
	expect(events.any(func(e): return e.type == "cast") and events.any(func(e): return e.type == "skill"),"natural World route actually casts and uses gust day%d" % day)
	expect(events.any(func(e): return e.type == "enemy_defeated") and pickups.any(func(p): return p.item_id == "moonheart"),"natural defeat and elite material pickup day%d" % day)
	expect(saved_pickup,"actual pickup was saved and restored day%d" % day)
	expect(s.day == day and s.encounter_day == encounter_day and Model.view(s).day == day,"campaign display/context survives complete combat day%d" % day)
	roundtrip(s,"returned-day%d" % day)
	var before = s.duplicate(true); var result = Model.advance(s,60000); Model.leave(s)
	expect(s == before and result.pickups.is_empty(),"returned World run cannot resume or award again day%d" % day)
	traces.append({"campaign_day":day,"encounter_day":encounter_day,"state":s,"pickups":pickups,"events":events,"positions":positions})

func run(output_dir: String = "") -> Dictionary:
	var io = Output.new()
	if not io.prepare_output(output_dir): return {"checks":io.checks,"failures":io.failures}
	output = io.output
	boundaries()
	expect(boundaries_complete,"all required boundary cases completed")
	var ledger: Dictionary = {}
	for day in [1,2,3,6]: natural_route(day,ledger)
	expect(traces.size() == 4,"all four actual campaign routes completed")
	var report = {"checks":checks,"failures":failures.duplicate(),"output":output,"kind":"World adapter component evidence; not a complete World Session","traces":traces,"pickup_ledger":ledger}
	io.write_report(report)
	checks += io.checks; failures.append_array(io.failures)
	report.checks = checks; report.failures = failures.duplicate()
	return report
