extends RefCounted
## Automatic terminal reasons use explicit component fixtures; Session tests use
## only public commands/save/load and compare every snapshot field, including requests.
const Model = preload("res://game/expedition/expedition_model.gd")
const Rain = preload("res://game/expedition/rain_garden_model.gd")
var checks = 0
var failures: Array = []
var evidence: Array = []
var output = ""
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)
func make() -> Dictionary:
	return Model.create(1,"return-boundary",23,"bolt_wand",["gust"],false,{"ruleset":"rain-night-v1","map_id":"rain-garden-two-routes","map_revision":1,"meal_effect":null})
func component_terminal(a: Dictionary, b: Dictionary, reason: String, events_a: Array, events_b: Array):
	expect(a.status == "returned" and a.return_reason == reason and b.return_reason == reason,"component reaches actual "+reason+" terminal branch")
	expect(a.remainder_ms == 0 and b.remainder_ms == 0,"component terminal discards pending time "+reason)
	expect(a == b,"component full state equal across partitions "+reason)
	expect(events_a == events_b,"component events equal across partitions "+reason)
	expect(Model.validate(a) == "" and Model.validate(b) == "","component terminal states validate "+reason)
	var before = a.duplicate(true)
	var again = Model.advance(a,60000)
	expect(a == before and again.events.is_empty() and again.pickups.is_empty(),"later advance cannot resume terminal model "+reason)
	var repeated = Model.leave(a)
	expect(a == before and repeated.events.is_empty(),"repeated leave is idempotent "+reason)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(b))
	expect(Model.validate(restored) == "" and Rain._same(restored,b),"terminal JSON preserves complete values "+reason)
	var loaded_before = restored.duplicate(true)
	Model.advance(restored,60000,80,true); Model.advance(restored,60000)
	expect(restored == loaded_before,"restored terminal stays frozen with/without pause "+reason)
	evidence.append({"kind":"controlled-component","reason":reason,"equal":a == b,"tick":a.tick,"remainder_ms":a.remainder_ms})
func component_partition(start: Dictionary, reason: String):
	var a = start.duplicate(true); var b = start.duplicate(true)
	var result = Model.advance(a,1000)
	var split_events: Array = []
	var minimum_remainder = b.remainder_ms
	for i in range(20):
		split_events.append_array(Model.advance(b,50).events)
		minimum_remainder = mini(minimum_remainder,b.remainder_ms)
	expect(minimum_remainder >= 0 and a.remainder_ms >= 0,"pre-step decrement cannot make remainder negative "+reason)
	component_terminal(a,b,reason,result.events,split_events)
func components():
	var entrance = make()
	expect(Model.set_input(entrance,{"move_x":1.0}).ok,"component right input")
	Model.advance(entrance,500)
	expect(Model.set_input(entrance,{"move_x":-1.0}).ok,"component left input")
	component_partition(entrance,"entrance")
	# A valid controlled combat boundary: next ordinary dash hit consumes last HP.
	var defeated = make(); defeated.player.hp = 1
	var enemy: Dictionary = defeated.enemies[0]
	enemy.x = 100; enemy.y = 270; enemy.state = "dash"; enemy.timer_ms = 500
	enemy.direction_x = -1; enemy.direction_y = 0; enemy.attack_index = 1
	enemy.attack_id = "%s:%s:a1" % [defeated.run_id,enemy.id]
	expect(Model.validate(defeated) == "","controlled defeat fixture is valid")
	component_partition(defeated,"defeated")
	# A valid finite, cleared field with all materials already collected. This is
	# a component fixture, never a claim about an earned Session inventory.
	var completed = make()
	for e in completed.enemies:
		e.hp = 0; Rain._defeat(completed,e,Rain._result())
	for drop in completed.drops: drop.collected = true
	for node in completed.resource_nodes: node.collected = true
	completed.status = "cleared"
	expect(Model.validate(completed) == "","controlled completed fixture is valid")
	component_partition(completed,"completed")
	var a = make(); var b = make()
	Model.advance(a,37); Model.advance(b,10); Model.advance(b,27)
	expect(a == b and a.remainder_ms == 37,"active substep remainder is preserved before manual retreat")
	var ea = Model.leave(a); var eb = Model.leave(b)
	component_terminal(a,b,"retreat",ea.events,eb.events)
	# Pause/save-like JSON continuation retains the active 37ms; only crossing
	# the terminal boundary discards it.
	Model.advance(entrance,37)
	var before = entrance.duplicate(true)
	Model.advance(entrance,1000,80,true)
	expect(entrance == before and entrance.remainder_ms == 37,"pause preserves active pending fraction")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(entrance))
	expect(Model.validate(restored) == "","active fractional JSON validates")
	Model.clear_input(entrance); Model.clear_input(restored)
	Model.set_input(entrance,{"move_x":-1.0}); Model.set_input(restored,{"move_x":-1.0})
	Model.advance(entrance,1000)
	for i in range(20): Model.advance(restored,50)
	expect(entrance == restored and entrance.return_reason == "entrance" and entrance.remainder_ms == 0,"active paused/JSON branches converge through return boundary")
func start_session(factory: Callable):
	var g = factory.call(23)
	if g.snapshot().get("profile_id","") != "rain-night-v1":
		expect(false,"real Session regression requires the formal rain-night-v1 core; no adapter fallback")
		return null
	expect(g.command("start_expedition").ok,"real Session starts formal expedition")
	expect(g.snapshot().expedition.version == 2,"real Session holds quality model")
	expect(g.command("expedition_input",{"move_x":1.0}).ok,"real Session right input")
	expect(g.advance(500).ok,"real Session right 500ms")
	expect(g.command("expedition_input",{"move_x":-1.0}).ok,"real Session left input")
	return g
func real_sessions(factory: Callable):
	var a = start_session(factory); var b = start_session(factory)
	if a == null or b == null: return
	expect(a.snapshot() == b.snapshot(),"real Session initial complete snapshots equal")
	expect(a.advance(1000).ok,"real Session single 1000ms")
	var split_ok = true
	for i in range(20): split_ok = b.advance(50).ok and split_ok
	expect(split_ok,"real Session twenty 50ms calls")
	var sa: Dictionary = a.snapshot(); var sb: Dictionary = b.snapshot()
	expect(sa.phase == "shopping" and sa.expedition.return_reason == "entrance" and sa.expedition.tick == 25 and sa.expedition.player.x == 40,"review's exact public Session route reaches tick25/x40 entrance")
	expect(sa == sb,"review regression: every Session snapshot field equal across 1000 vs20x50")
	expect(sa.expedition.remainder_ms == 0 and sb.expedition.remainder_ms == 0,"real Session return remainders both zero")
	expect(a.validate_snapshot(sa) == "" and b.validate_snapshot(sb) == "","real Session return snapshots validate")
	evidence.append({"kind":"real-public-Session","reason":"entrance","single":sa,"split":sb,"equal":sa == sb})
	var returned_path = output+"/returned-session.json"
	var returned_save = a.save_to(returned_path)
	expect(returned_save.ok,"real Session saves returned state")
	if not returned_save.ok: return
	var loaded = factory.call(23)
	expect(loaded.load_from(returned_path).ok and loaded.snapshot() == sa,"real Session disk load keeps full returned snapshot")
	expect(loaded.advance(1000).ok and loaded.snapshot() == sa,"real Session advance cannot resume returned expedition")
	# Public pause/save/load while 37ms is pending; apply identical new held input
	# after restore as required by the load-clears-input contract.
	var live = start_session(factory)
	if live == null: return
	expect(live.advance(37).ok and live.snapshot().expedition.remainder_ms == 37,"real Session retains active 37ms")
	expect(live.command("expedition_input",{}).ok and live.set_paused(true).ok,"real Session clears held input and pauses")
	var paused: Dictionary = live.snapshot()
	expect(live.advance(1000).ok and live.snapshot() == paused,"real Session pause freezes full snapshot")
	var active_path = output+"/paused-session.json"
	var active_save = live.save_to(active_path)
	expect(active_save.ok,"real Session saves paused fractional state")
	if not active_save.ok: return
	var resumed = factory.call(23)
	expect(resumed.load_from(active_path).ok and resumed.snapshot() == paused,"real Session disk restore equals all paused snapshot fields")
	expect(live.set_paused(false).ok and resumed.set_paused(false).ok,"both real Session branches resume")
	expect(live.command("expedition_input",{"move_x":-1.0}).ok and resumed.command("expedition_input",{"move_x":-1.0}).ok,"identical public input after restore")
	live.advance(1000)
	for i in range(20): resumed.advance(50)
	expect(live.snapshot() == resumed.snapshot() and live.snapshot().expedition.remainder_ms == 0,"real Session save/resume terminal full snapshots converge")
	# Manual leave is the existing public retreat route, not a synthetic reason.
	var retreat = start_session(factory)
	if retreat == null: return
	retreat.advance(37)
	expect(retreat.command("leave_expedition").ok,"real Session public manual retreat")
	var retreat_state: Dictionary = retreat.snapshot()
	expect(retreat_state.phase == "shopping" and retreat_state.expedition.return_reason == "retreat" and retreat_state.expedition.remainder_ms == 0,"real Session retreat clears active fractional remainder")
	var retreat_path = output+"/retreat-session.json"
	var retreat_save = retreat.save_to(retreat_path)
	expect(retreat_save.ok,"real Session saves retreat")
	if not retreat_save.ok: return
	var retreat_load = factory.call(23)
	expect(retreat_load.load_from(retreat_path).ok and retreat_load.snapshot() == retreat_state,"real Session restores complete manual-retreat state")
	expect(retreat_load.advance(1000).ok and retreat_load.snapshot() == retreat_state,"manual-retreat Session remains stopped")
	evidence.append({"kind":"real-public-Session","reason":"retreat","remainder_ms":retreat_state.expedition.remainder_ms})
func prepare_output(output_dir: String) -> bool:
	output = output_dir
	if output.is_empty():
		# Use the runner's existing temporary root, then create an exclusive child.
		# A fixed /tmp path is neither portable to Windows nor safe to reuse.
		for key in ["RUNNER_TEMP","TEMP","TMP","TMPDIR"]:
			var root = OS.get_environment(key)
			if root.is_absolute_path() and DirAccess.dir_exists_absolute(root):
				output = root.path_join("moonlantern-e04-returns-%s-%s" % [OS.get_process_id(),OS.get_entropy(8).hex_encode()])
				break
	if output.is_empty() or not output.is_absolute_path() or output.begins_with("res://") or output.begins_with("user://"):
		expect(false,"output requires an absolute filesystem path or an existing runner temporary root")
		return false
	if FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output):
		expect(false,"refusing to overwrite existing output: "+output)
		return false
	if not DirAccess.dir_exists_absolute(output.get_base_dir()):
		expect(false,"output parent must already be a directory: "+output.get_base_dir())
		return false
	var error = DirAccess.make_dir_absolute(output)
	if error != OK:
		expect(false,"cannot create exclusive output directory (%s): %s" % [error,output])
		return false
	return true
func result(factory: Callable) -> Dictionary:
	return {"checks":checks,"failures":failures.duplicate(),"output":output,"real_session_requested":factory.is_valid(),"evidence":evidence.duplicate(true),"model_sha256":FileAccess.get_sha256("res://game/expedition/rain_garden_model.gd")}
func write_report(report: Dictionary):
	var path = output.path_join("report.json")
	if FileAccess.file_exists(path):
		expect(false,"refusing to overwrite existing report: "+path)
		return
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		expect(false,"cannot open report (%s): %s" % [FileAccess.get_open_error(),path])
		return
	var serialized = JSON.stringify(report,"  ")
	var expected_bytes = serialized.to_utf8_buffer()
	var stored = file.store_string(serialized)
	file.flush()
	var error = file.get_error()
	file.close()
	if not stored or error != OK:
		expect(false,"cannot write report (%s): %s" % [error,path])
		return
	# Buffered writes/flush can leave get_error() == OK after a short disk write.
	# Reopen after close and verify the complete serialized UTF-8 bytes.
	var reader = FileAccess.open(path,FileAccess.READ)
	if reader == null:
		expect(false,"cannot reopen report for readback (%s): %s" % [FileAccess.get_open_error(),path])
		return
	var actual_size = reader.get_length()
	if actual_size != expected_bytes.size():
		reader.close()
		expect(false,"report readback length mismatch (expected %s bytes, got %s): %s" % [expected_bytes.size(),actual_size,path])
		return
	var actual_bytes = reader.get_buffer(expected_bytes.size())
	var read_error = reader.get_error()
	reader.close()
	if read_error != OK or actual_bytes != expected_bytes:
		expect(false,"report readback failed or bytes differ (%s): %s" % [read_error,path])
func run(factory: Callable = Callable(), output_dir: String = "") -> Dictionary:
	checks = 0; failures.clear(); evidence.clear()
	if not prepare_output(output_dir):
		var failed = result(factory)
		print("E04_RETURN_RESULT ",JSON.stringify(failed))
		return failed
	components()
	if factory.is_valid(): real_sessions(factory)
	write_report(result(factory))
	var report = result(factory)
	print("E02 return boundaries: ",checks," checks, ",failures.size()," failures; real Session=",factory.is_valid(),"; output=",output)
	# The return value remains authoritative even when report creation failed.
	print("E04_RETURN_RESULT ",JSON.stringify({"checks":checks,"failures":report.failures,"output":output}))
	return report
