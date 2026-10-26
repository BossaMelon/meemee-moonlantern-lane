extends RefCounted
const Session = preload("res://game/core/game_session.gd")
const Driver = preload("res://tests/expedition/rain_driver.gd")

func campaign(h) -> Dictionary:
	var evidence = {"starts":{},"boundaries":[],"returned":{}}
	var g = h.normal_night(23,"quick","standard")
	# This night funds the campaign probe; keep it separate from the canonical
	# five-seed/two-route/two-price economic matrix rather than adding a duplicate.
	evidence.funding_night = h.simulations.pop_back()
	h.act(g,"ledger","upgrade",{"upgrade_id":"field_kit"}); h.act(g,"ledger","next_day")
	h.walk_to(g,"recipe-book"); h.act(g,"recipe-book","equip_weapon",{"weapon_id":"fan_wand"})
	var first_node_uids = []
	for day in range(2,7):
		h.progress("campaign-day-"+str(day))
		h.expect(g.snapshot().day == day and g.snapshot().phase == "preparation","campaign day comes from actual next_day: "+str(day))
		if day == 3:
			h.buy(g,{"flour":1,"pumpkin":1}); h.cook_batch(g,"floating_pie",1,false)
			h.act(g,"prep","take",h.suggested(g,"prep","take")); h.walk_to(g,"pantry"); h.act(g,"pantry","put",h.suggested(g,"pantry","put"))
			h.walk_to(g,"recipe-book"); h.act(g,"recipe-book","consume",{"item_id":"floating_pie","quantity":1})
		h.travel(g,"lane"); h.walk_to(g,"garden-gate")
		var before = g.snapshot()
		if day == 3:
			h.expect(before.pending_meal_effect != null,"create failure carries a real consumed-food effect")
			g._game._model = preload("res://tests/core/rejecting_model_fixture.gd")
			h.reject(g,"world_interact",{"target_id":"garden-gate","action":"enter","payload":{}},"failed-campaign-start")
			h.expect(g.snapshot() == before,"failed adapter create preserves meal, attempts, requests, RNG and all world state")
			g._game._model = null
		var entered = h.act(g,"garden-gate","enter")
		var start_request = "test-%d" % h.request_serial
		if not entered.ok: return evidence
		var start = g.snapshot(); var world_before = start.world.duplicate(true)
		h.expect(start.expedition.version == 3 and start.expedition.ruleset == "world-slice-v1" and start.expedition.day == day and start.expedition.get("encounter_day") == 2 and start.expedition.run_id == "n%d-expedition" % day,"World adapter owns actual campaign context day"+str(day))
		h.expect(start.pending_meal_effect == null and start.expedition_meals[start.expedition.run_id] == before.pending_meal_effect,"successful start transfers the original meal exactly once")
		if day in [3,6]: evidence.starts[str(day)] = start
		var driver = Driver.new("shelf",true); var restored = []; var captured = {}; var cast_seen = false
		var observed = g.snapshot()
		for tick in range(5000):
			if observed.phase != "expedition": break
			var input = driver.next_input(observed.expedition)
			h.expect(g.command("expedition_input",input).ok,"campaign real action input")
			var advanced = g.advance(50); h.expect(advanced.ok,"campaign single E tick")
			if advanced.events.any(func(e): return e.type == "cast" and e.weapon_id == "fan_wand" and e.projectile_count == 3): cast_seen = true
			for branch in restored:
				h.expect(branch.command("expedition_input",input).ok and branch.advance(50).ok,"restored campaign follows identical action inputs")
			observed = g.snapshot(); var s = observed
			if day in [3,6] and s.phase == "expedition":
				var boundary = ""
				if tick == 30: boundary = "combat_in_progress"
				elif s.expedition.drops.any(func(d): return not d.collected): boundary = "drop_available_before_pickup"
				elif s.expedition.drops.any(func(d): return d.collected): boundary = "drop_collected"
				if boundary != "" and not captured.has(boundary):
					captured[boundary] = true; restored.append(h.roundtrip(g,"campaign-%d-%s" % [day,boundary]))
					evidence.boundaries.append({"day":day,"boundary":boundary,"snapshot":s})
		var returned = g.snapshot()
		h.expect(returned.phase == "preparation" and returned.world.region_id == "lane" and returned.world.player == {"x":1384,"y":256,"facing":"sw"},"campaign returns to the saved physical lane pose day"+str(day))
		h.expect(returned.world.tick == world_before.tick and returned.world.remainder_ms == world_before.remainder_ms,"campaign exploration freezes world tick owner")
		h.expect(cast_seen and returned.expedition.enemies.any(func(e): return e.kind == "moonheart" and e.hp == 0),"earned fan actually defeats the existing elite on day"+str(day))
		var key = "n%d-expedition|resource:shelf-patch" % day
		h.expect(returned.collected_drops.has(key),"same resource remains collectible on later campaign run: "+key)
		if returned.collected_drops.has(key):
			for uid in returned.collected_drops[key].uids:
				h.expect(uid not in first_node_uids,"cross-day pickup creates a new UID without overwriting past rewards"); first_node_uids.append(uid)
		for branch in restored: h.expect(branch.snapshot() == returned,"saved combat/pickup continuation equals original full state and reward ledger")
		if day in [3,6]:
			for boundary in h.fixture_data.configuration.campaign_expedition_cases.save_boundaries:
				if boundary != "returned_to_saved_lane_pose": h.expect(captured.has(boundary),"actually observed required campaign save boundary "+boundary)
			g = h.roundtrip(g,"campaign-%d-returned_to_saved_lane_pose" % day)
			evidence.returned[str(day)] = g.snapshot()
			evidence.boundaries.append({"day":day,"boundary":"returned_to_saved_lane_pose","snapshot":g.snapshot()})
		var already_returned = g.snapshot()
		var repeated = g.command("world_interact",{"target_id":"garden-gate","action":"enter","payload":{}},start_request)
		h.expect(repeated.code == "duplicate" and g.snapshot() == already_returned,"original start request cannot restart or pay again after return day"+str(day))
		h.walk_to(g,"garden-gate"); h.reject(g,"world_interact",{"target_id":"garden-gate","action":"enter","payload":{}},"second-entry-%d" % day)
		h.audit(g,"campaign day"+str(day))
		if day < 6:
			h.travel(g,"shop")
			for wave in range(3): h.open_wave(g); h.complete_wave(g)
			h.walk_to(g,"ledger"); h.act(g,"ledger","settle"); h.act(g,"ledger","next_day")
	h.expect(g.snapshot().daily_recovery == 0,"six-day context loop uses no recovery or injected inventory")
	h.traces.append({"scenario":"actual-next-day-campaign-through-six","evidence":evidence})
	return evidence

func contexts(h, evidence: Dictionary):
	if not evidence.get("starts",{}).has_all(["3","6"]):
		h.expect(false,"actual day3/day6 checkpoints required before context tests"); return
	var contexts = h.fixture_data.configuration.campaign_expedition_cases.invalid_contexts
	h.expect(contexts.size() == 17,"frozen seventeen invalid campaign contexts are all exercised")
	for mutation in contexts:
		var source = evidence.starts[str(int(mutation.get("world_day",3)))]; var bad = source.duplicate(true)
		for field in mutation.get("remove",[]): bad.expedition.erase(field)
		for field in mutation.get("patch",{}): bad.expedition[field] = mutation.patch[field]
		var g = h.fixture(source,"valid-campaign-before-"+mutation.id); var before = g.snapshot()
		var path = h.output_dir+"/invalid-campaign-"+mutation.id+".json"
		var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(bad,"\t",true,true)); file.close()
		var digest = FileAccess.get_sha256(path); var result = g.load_from(path)
		h.expect(g.validate_snapshot(bad) != "" and not result.ok and g.snapshot() == before and FileAccess.get_sha256(path) == digest,"invalid campaign context rejected atomically: "+mutation.id)
	# Keep the adapter's own context valid while breaking its outer-world linkage.
	var mismatched = evidence.starts["6"].duplicate(true); mismatched.expedition.day = 3; mismatched.expedition.run_id = "n3-expedition"
	h.expect(Session.new(1).validate_snapshot(mismatched) != "","valid adapter context must still equal its enclosing world day/run")
	for day in [3,6]:
		var source = evidence.boundaries.filter(func(b): return b.day == day and b.boundary == "drop_collected")[0].snapshot
		var g = h.fixture(source,"real-collected-before-manual-return-%d" % day); var drops = g.snapshot().collected_drops.duplicate(true)
		h.expect(g.command("leave_expedition",{},"return-once").ok,"manual return after actual pickup succeeds day"+str(day))
		g = h.roundtrip(g,"manual-return-with-receipt-%d" % day); var returned = g.snapshot()
		h.expect(g.command("leave_expedition",{},"return-once").code == "duplicate" and g.snapshot() == returned,"restored same return request is a true no-op day"+str(day))
		h.reject(g,"leave_expedition",{},"new-return-request")
		h.expect(g.snapshot().collected_drops == drops,"manual, duplicate and new return requests do not alter real reward receipts")
