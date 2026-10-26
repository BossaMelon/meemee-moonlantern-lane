extends RefCounted
const Session = preload("res://game/core/game_session.gd")

func run(h):
	zero_cash(h)
	late_cooking(h)

func saved(h, g, label: String):
	var state = g.snapshot(); var path = h.output_dir.path_join("WR-"+label+".json")
	var result = g.save_to(path)
	h.expect(result.ok,"review boundary saves "+label+": "+str(result))
	if not result.ok: return g
	var restored = Session.new(99); var loaded = restored.load_from(path)
	h.expect(loaded.ok and restored.snapshot() == state,"review boundary restores exact state "+label)
	h.audit(restored,label)
	h.traces.append({"scenario":"WR-saved-boundary","label":label,"path":path,"snapshot":state})
	return restored

func ledger_action(h, g, action: String, label: String):
	var args = {"target_id":"ledger","action":action,"payload":{}}
	var request = "WR-"+label+"-"+action
	h.expect(g.command("world_interact",args,request).ok,"review legal "+action+" "+label)
	g = saved(h,g,label+"-"+action)
	var after = g.snapshot()
	h.expect(g.command("world_interact",args,request).code == "duplicate" and g.snapshot() == after,"restored same request cannot repeat "+action)
	h.reject(g,"world_interact",args,request+"-new")
	return g

func zero_cash(h):
	var g = Session.new(7); h.buy(g,{"flour":12,"pumpkin":12})
	for wave in range(3): h.open_wave(g); h.complete_wave(g)
	h.walk_to(g,"ledger"); var before = g.snapshot()
	h.expect(before.cash == 0 and g.validate_snapshot(before) == "","WR-01 real purchases and three waves reach valid zero-cash closing")
	g = ledger_action(h,g,"settle","zero")
	var settled = g.snapshot(); var rows = settled.ledger.filter(func(r): return r.kind == "settle")
	h.expect(rows.size() == 1 and rows[0].cash_delta == 0 and settled.summaries.size() == 1 and settled.summaries[0].fee == 0,"WR-01 zero-fee day retains exactly one explicit settlement row")
	h.expect(settled.items == before.items and settled.next_uid == before.next_uid and settled.cash == 0,"zero-fee settlement neither consumes nor creates UIDs/cash")
	if rows.size() == 1:
		var duplicate = settled.duplicate(true); var row = rows[0].duplicate(true); row.index = duplicate.ledger.size(); duplicate.ledger.append(row)
		h.expect(g.validate_snapshot(duplicate) == "重复日结流水","duplicate zero-fee settlement ledger remains rejected")
		var missing = settled.duplicate(true); missing.ledger.pop_back()
		h.expect(g.validate_snapshot(missing) == "日结数量不一致","missing zero-fee settlement ledger remains rejected")
	g = ledger_action(h,g,"next_day","zero")
	h.expect(g.snapshot().day == 2 and g.snapshot().cash == 0 and g.snapshot().items == before.items,"zero-cash next day preserves all original UID ownership")
	h.travel(g,"lane"); h.walk_to(g,"vendor"); h.act(g,"vendor","recover")
	h.expect(g.snapshot().cash == 12 and g.view().dish_income == 0,"zero-cash recovery still works after restored next day")
	h.reject(g,"world_interact",{"target_id":"vendor","action":"recover","payload":{}},"WR-recover-new")
	saved(h,g,"zero-recovered")

func late_origin(h, quantity: int):
	var g = Session.new(1)
	for wave in range(2): h.open_wave(g); h.complete_wave(g)
	var basket = {"cream":quantity}
	if quantity > 3: basket["pumpkin"] = quantity-3
	h.buy(g,basket)
	h.walk_to(g,"recipe-book"); h.act(g,"recipe-book","plan",{"recipe_id":"moon_stew","quantity":quantity})
	h.walk_to(g,"pantry"); h.act(g,"pantry","take",h.suggested(g,"pantry","take"))
	h.walk_to(g,"prep"); h.act(g,"prep","put",h.suggested(g,"prep","put"))
	h.open_wave(g); h.walk_to(g,"prep")
	for tick in range(2000):
		var state = g.snapshot()
		if state.service.orders.back().status == "waiting" and state.service.orders.back().waited_ms == 59000: break
		g.advance(50)
	h.expect(g.snapshot().service.orders.back().waited_ms == 59000,"last real customer has exactly 1000ms patience")
	h.act(g,"prep","cook",{"recipe_id":"moon_stew","quantity":quantity}); g.advance(1000)
	var closing = g.snapshot()
	h.expect(closing.phase == "closing" and closing.world.stations[0].job.remaining_ms == 1000,"WR-02 final wave ends with a real half-finished job")
	return saved(h,g,"late-%d-cooking" % quantity)

func finish_day(h, g, label: String, held_count: int):
	h.walk_to(g,"ledger"); var before = g.snapshot()
	h.expect(before.world.stations[0].job == null,"actual walking finishes pending two-second job before ledger")
	g = ledger_action(h,g,"settle",label)
	var settled = g.snapshot(); g = ledger_action(h,g,"next_day",label); var after = g.snapshot()
	h.expect(after.day == 2 and g.validate_snapshot(after) == "","WR-02 next-day retained meals validate: "+label)
	var unchanged_items = after.items.duplicate(true)
	for i in range(unchanged_items.size()): unchanged_items[i].temperature = before.items[i].temperature
	h.expect(unchanged_items == before.items and after.next_uid == before.next_uid,"day transition preserves UIDs, costs, locations and preparation identity: "+label)
	h.expect(after.ledger == settled.ledger and after.sales == settled.sales and after.summaries == settled.summaries and after.cash == settled.cash,"heat transition does not change service/economic accounts: "+label)
	h.expect(after.service.held_uids.size() == held_count and after.items.filter(func(i): return i.item_id == "moon_stew" and i.temperature == "hot").is_empty(),"only existing pot capacity carries heat overnight: "+label)
	for item in after.items:
		if item.item_id == "moon_stew": h.expect(item.temperature == ("held" if item.uid in after.service.held_uids else "cooled"),"retained meal heat matches ownership: "+label)
	return g

func late_cooking(h):
	var unfinished = late_origin(h,1)
	# These branches load actual saved command-produced states; no fixture edits.
	var ready = Session.new(99); h.expect(ready.load_from(h.output_dir.path_join("WR-late-1-cooking.json")).ok,"reload original unfinished job")
	ready.advance(1000)
	h.expect(ready.snapshot().items.filter(func(i): return i.item_id == "moon_stew" and i.location == "ready" and i.temperature == "hot" and i.prepared_wave_id == "n1-w3").size() == 1,"original late completion is hot in closing and stamped n1-w3")
	ready = saved(h,ready,"late-ready"); finish_day(h,ready,"late-ready",0)
	# Saving while unfinished, then walking normally, must also preserve the output.
	finish_day(h,unfinished,"late-unfinished",0)
	var batch = late_origin(h,4); batch.advance(1000); batch = saved(h,batch,"late-batch-ready")
	for location in ["carried","shelf"]:
		var branch = Session.new(99); h.expect(branch.load_from(h.output_dir.path_join("WR-late-batch-ready.json")).ok,"reload real four-portion output")
		h.act(branch,"prep","take",h.suggested(branch,"prep","take"))
		if location == "shelf":
			h.walk_to(branch,"pass"); h.act(branch,"pass","put",h.suggested(branch,"pass","put"))
		branch = saved(h,branch,"late-"+location)
		finish_day(h,branch,"late-"+location,3 if location == "shelf" else 0)
	# Existing wave-end held meals retain their established overnight allowance.
	var held = Session.new(1); h.open_wave(held); h.complete_wave(held)
	h.buy(held,{"pumpkin":3,"cream":6}); h.cook_batch(held,"moon_stew",6)
	h.open_wave(held); h.complete_wave(held); h.open_wave(held); h.complete_wave(held)
	var held_uids = held.snapshot().service.held_uids.duplicate()
	h.expect(not held_uids.is_empty(),"ordinary real service leaves existing held meals")
	held = finish_day(h,held,"already-held",held_uids.size())
	h.expect(held.snapshot().service.held_uids == held_uids,"existing evening held UID selection survives next day")
