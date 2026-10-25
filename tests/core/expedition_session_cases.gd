extends RefCounted
const Session = preload("res://game/core/game_session.gd")
var checks = 0
var failures: Array = []
var metrics: Array = []
var root = ""

func expect(condition: bool, message: String):
	checks += 1
	if not condition:
		failures.append(message)
		push_error("P16 core session: "+message)

func restore(g, label: String):
	var path = root+"/"+label+".json"
	var started = Time.get_ticks_usec()
	expect(g.save_to(path).ok,"save full action session "+label)
	var clone = Session.new(1,"prototype-v1")
	expect(clone.load_from(path).ok,"load full action session "+label)
	metrics.append({"scenario":label,"save_and_load_us":Time.get_ticks_usec()-started,"save_bytes":FileAccess.get_file_as_bytes(path).size(),"ledger_rows":g.snapshot().ledger.size()})
	return clone

func persistence():
	var g = Session.new(23,"prototype-v1")
	expect(g.command("start_expedition").ok,"start precision scenario")
	expect(g.command("expedition_input",{"move_x":0.37,"move_y":-0.21,"aim_x":0.4,"aim_y":0.9,"cast":true}).ok,"fractional axes accepted")
	expect(g.advance(137).ok,"partial fixed step accepted")
	var s = g.snapshot()
	expect(s.expedition.remainder_ms == 37,"37ms remainder actually present")
	expect(s.expedition.player.x != floor(s.expedition.player.x) and s.expedition.player.y != floor(s.expedition.player.y),"actual moving player has fractional coordinates")
	expect(not s.expedition.projectiles.is_empty() and s.expedition.projectiles[0].vx != floor(s.expedition.projectiles[0].vx),"live projectile has fractional velocity")
	var clone = restore(g,"fractional-projectile")
	g.command("expedition_input",{})
	expect(clone.snapshot() == g.snapshot(),"load clears held input and otherwise preserves every numeric value and type")
	for step in [16,34,137,63]:
		var input = {"move_x":-0.23,"move_y":0.57,"aim_x":0.8,"aim_y":0.3,"cast":true}
		g.command("expedition_input",input); clone.command("expedition_input",input)
		expect(g.advance(step) == clone.advance(step) and g.snapshot() == clone.snapshot(),"continuation preserves trajectories and remainder at frame "+str(step))
	g.set_paused(true); clone = restore(g,"paused-action")
	expect(clone.snapshot() == g.snapshot(),"paused action roundtrip exact")
	var before = clone.snapshot(); clone.advance(60000)
	expect(clone.snapshot() == before,"paused full minute changes no simulation or economy")
	clone.set_paused(false)
	expect(clone.command("leave_expedition").ok,"explicit retreat succeeds")
	g = restore(clone,"retreated-action")
	expect(g.snapshot() == clone.snapshot(),"returned input state roundtrip exact")
	expect(not g.command("start_expedition").ok,"loaded retreat cannot reset daily attempt")

func full_duration():
	var g = Session.new(7,"prototype-v1")
	expect(g.command("start_expedition").ok,"start full 180-second simulation")
	var corners = [Vector2(80,60),Vector2(880,60),Vector2(880,480),Vector2(80,480)]
	var target = 0; var frames = 0; var max_step_us = 0
	var initial_ledger = g.snapshot().ledger.size()
	var started = Time.get_ticks_usec()
	while g.view().phase == "expedition" and frames < 3600:
		var p = g.view().expedition.player; var position = Vector2(p.x,p.y)
		if position.distance_to(corners[target]) < 10: target = (target+1)%corners.size()
		var movement = (corners[target]-position).normalized()
		g.command("expedition_input",{"move_x":movement.x,"move_y":movement.y})
		var step_start = Time.get_ticks_usec(); var result = g.advance(50)
		max_step_us = maxi(max_step_us,Time.get_ticks_usec()-step_start)
		expect(result.ok,"legal full-duration motion frame")
		frames += 1
		if frames in [600,1800,3000]:
			var clone = restore(g,"duration-%d" % frames)
			g.command("expedition_input",{})
			expect(clone.snapshot() == g.snapshot(),"long-session checkpoint resumes exact simulation")
	var s = g.snapshot()
	expect(frames == 3600 and s.expedition.return_reason == "timeout" and s.expedition.remaining_ms == 0,"actual full 180-second outing ends at time limit")
	expect(s.ledger.size() == initial_ledger and s.cash == 60 and s.items.size() == 1,"7200 movement/tick commands do not create economic rows")
	expect(g.validate_snapshot(s) == "","full outing remains valid")
	metrics.append({"scenario":"full-180-second-outing","frames":frames,"simulation_ms":frames*50,"wall_us":Time.get_ticks_usec()-started,"max_advance_us":max_step_us,"ledger_rows_before":initial_ledger,"ledger_rows_after":s.ledger.size(),"action_trace_entries":g.action_trace().size(),"outcome":s.expedition.return_reason})

func pickup_resume():
	var driver = load("res://tests/expedition/action_driver.gd")
	var g = Session.new(99,"prototype-v1"); g.command("start_expedition")
	var resumed = false; var frames = 0; var max_pickup_rows = 0
	while g.view().phase == "expedition" and frames < 3600:
		g.command("expedition_input",driver.next_input(g.view().expedition)); g.advance(50); frames += 1
		if not resumed and not g.snapshot().collected_drops.is_empty() and g.view().phase == "expedition":
			var clone = restore(g,"after-first-pickup"); g.command("expedition_input",{})
			expect(clone.snapshot() == g.snapshot(),"drop identity, created UID and zero cost survive immediate save")
			g = clone; resumed = true
	var s = g.snapshot(); var rows = s.ledger.filter(func(row): return row.kind == "pickup")
	for row in rows:
		max_pickup_rows += row.created.size()
		expect(row.cash_delta == 0 and row.created.all(func(item): return item.cost == 0),"each pickup has zero cash/cost acquisition")
	expect(resumed and s.expedition.return_reason == "completed","actual resumed loot outing completes")
	expect(s.collected_drops.size() == 3 and max_pickup_rows == 3 and s.items.size() == 4,"three physical kills award exactly three distinct items across reload")
	var before = s.duplicate(true); g.advance(60000)
	expect(g.snapshot() == before,"return cannot award loot twice")
	expect(g.validate_snapshot(s) == "","resumed pickup economy validates")

func run(output_dir: String) -> Dictionary:
	root = output_dir+"/core-action-fixtures"; DirAccess.make_dir_recursive_absolute(root)
	persistence(); full_duration(); pickup_resume()
	var result = {"checks":checks,"failures":failures,"metrics":metrics}
	var file = FileAccess.open(output_dir+"/core-action-session.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	return result
