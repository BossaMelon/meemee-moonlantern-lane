extends RefCounted
const Session = preload("res://game/core/game_session.gd")
const Walk = preload("res://game/core/world_walk_model.gd")
var checks = 0
var failures: Array = []
var traces: Array = []
var output_dir = "/private/tmp/p10-world-first"
var request_serial = 0

func expect(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message); push_error(message)

func act(g, target: String, action: String, payload: Dictionary = {}):
	request_serial += 1
	var result = g.command("world_interact",{"target_id":target,"action":action,"payload":payload},"test-%d" % request_serial)
	expect(result.ok,"world action %s/%s: %s" % [target,action,str(result)])
	return result

func pos(g) -> Vector2:
	var p = g.snapshot().world.player; return Vector2(p.x,p.y)

func move_to(g, target: Vector2):
	for n in range(200):
		var delta = target-pos(g)
		if delta.length() < 1.7: break
		var axis = delta/8.0 if delta.length() < 8 else delta.normalized()
		g.command("world_input",{"move_x":axis.x,"move_y":axis.y}); var result = g.advance(50)
		if not result.ok: expect(false,"movement tick succeeds"); break
	g.command("world_input",{"move_x":0,"move_y":0})
	expect(pos(g).distance_to(target) < 2,"normal movement reaches waypoint "+str(target))

func walk_to(g, id: String):
	var region = g.snapshot().world.region_id; var object = Walk.object(id); var anchor = Vector2(object.anchor.x,object.anchor.y)
	expect(object.region_id == region,"navigation stays in current region")
	if pos(g).distance_to(anchor) < 40 and Walk.clear_line(region,pos(g),anchor): return
	var start = Vector2i(roundi(pos(g).x/16),roundi(pos(g).y/16)); var queue = [start]; var came = {start:start}; var found = start; var index = 0; var reached = false
	while index < queue.size():
		var cell: Vector2i = queue[index]; index += 1; var p = Vector2(cell)*16.0
		if p.distance_to(anchor) < 28 and Walk.clear_line(region,p,anchor): found = cell; reached = true; break
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next = cell+direction
			if not came.has(next) and Walk.clear_position(region,Vector2(next)*16.0): came[next] = cell; queue.append(next)
	expect(reached,"reachable interaction anchor: "+id)
	if not reached: return
	var points = []
	while found != start: points.push_front(Vector2(found)*16.0); found = came[found]
	for p in points: move_to(g,p)
	expect(pos(g).distance_to(anchor) <= 56 and Walk.clear_line(region,pos(g),anchor),"walk reaches real action range: "+id)

func suggested(g, target: String, action: String) -> Dictionary:
	for row in g.view().interactions:
		if row.target_id == target and row.action == action: return row.payload.duplicate(true)
	return {}

func first_income_report() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(output_dir)
	for manual in [true,false]:
		var g = Session.new(1); var initial = g.snapshot()
		expect(initial.profile_id == "world-slice-v1" and initial.phase == "preparation","world is fresh default preparation")
		walk_to(g,"pantry"); act(g,"pantry","take",suggested(g,"pantry","take"))
		expect(g.snapshot().world.carried_uids.size() == 6,"default three recipes move six inherited material UIDs")
		walk_to(g,"prep"); act(g,"prep","put",suggested(g,"prep","put")); act(g,"prep","cook",{"recipe_id":"floating_pie","quantity":3})
		var job = g.snapshot().world.stations[0].job.duplicate(true)
		expect(job.output_uids.size() == 3 and job.remaining_ms == 2000,"cook creates three real in-progress output UIDs")
		g.advance(1950); expect(g.snapshot().world.stations[0].job.remaining_ms == 50,"cooking is not instant")
		g.advance(50); expect(g.snapshot().world.stations[0].job == null,"2s completes exactly once")
		act(g,"prep","take",suggested(g,"prep","take"))
		walk_to(g,"door-bell"); act(g,"door-bell","open_shop")
		if manual:
			walk_to(g,"seat-1")
			for n in range(300):
				if g.snapshot().service.orders[0].status == "waiting": break
				g.advance(50)
			var payload = suggested(g,"seat-1","serve"); var cash = g.snapshot().cash
			act(g,"seat-1","serve",payload)
			expect(g.snapshot().cash == cash and g.snapshot().service.reservations[0].remaining_ms == 50,"hand serve reserves without immediate payment")
			g.advance(50); expect(g.snapshot().cash == cash+14,"next fixed step pays base12 plus optional tip2 once")
		else:
			walk_to(g,"pass"); act(g,"pass","put",suggested(g,"pass","put"))
			for n in range(500):
				if not g.snapshot().sales.is_empty(): break
				g.advance(50)
			expect(not g.snapshot().sales.is_empty() and g.snapshot().sales[0].tip == 0 and g.snapshot().sales[0].paid_total == 12,"automatic floating delivery pays actual price with zero tip")
		var v = g.view()
		expect(g.snapshot().sales[0].uid in job.output_uids,"sale consumes an actual batch UID")
		traces.append({"manual":manual,"cash":v.cash,"sales":v.sales,"view":v,"snapshot":g.snapshot()})
		var file = FileAccess.open(output_dir+("/manual-view.json" if manual else "/automatic-view.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(v,"\t",true,true)); file.close()
	return {"checks":checks,"failures":failures,"traces":traces}
