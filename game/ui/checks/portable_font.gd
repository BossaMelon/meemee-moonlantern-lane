extends SceneTree
## Source/imported-resource and actual Main binding gate; no native/layout claim.
var folder=""
var requested_output=""
var output_root=""
var probe_started=false
var path_cases: Array=[]
var failures: Array=[]
var checks=0
var bindings: Array=[]
var layouts: Array=[]
var fonts: Array=[]
var missing: Array=[]
var required: Dictionary={}
var ui
var viewport: SubViewport
var primary: Font

func _initialize():
	var args=OS.get_cmdline_user_args()
	if args.is_empty(): reject_output("explicit_output_required");return
	folder=args[0]
	requested_output=folder
	for flag in args.slice(1):
		if flag not in ["--small","--missing-glyph","--path-tests"]: reject_output("unknown_argument");return
	var reason=prepare_output()
	if not reason.is_empty(): reject_output(reason);return
	call_deferred("run")

func reject_output(reason: String):
	printerr("PORTABLE_FONT_PATH_ERROR "+JSON.stringify({"protocol":1,"error":reason,"requested_output":requested_output,"font_probe_ran":probe_started}))
	quit(2)

func syntax_error(path: String, windows: bool) -> String:
	if path.is_empty() or path!=path.strip_edges(): return "invalid_absolute_path"
	for character in path:
		if character.unicode_at(0)<32: return "control_character_in_path"
	var value=path.replace("\\","/") if windows else path
	if windows:
		# Runner TEMP uses drive-absolute paths; device/UNC and drive-relative paths are rejected.
		if value.length()<4 or value.substr(1,2)!=":/" or value[0].to_upper() not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ": return "drive_absolute_path_required"
		value=value.substr(3)
	else:
		if not value.begins_with("/") or "\\" in value or ":" in value: return "absolute_filesystem_path_required"
		value=value.substr(1)
	if value.is_empty() or value.ends_with("/") or "//" in value: return "nonempty_leaf_required"
	for part in value.split("/"):
		if part in [".",".."]: return "path_traversal_rejected"
		if windows:
			if part.ends_with(".") or part.ends_with(" "): return "windows_path_alias_rejected"
			for character in '<>:"|?*':
				if character in part: return "invalid_windows_path_component"
			var name=part.get_slice(".",0).to_upper()
			if name in ["CON","PRN","AUX","NUL"] or (name.length()==4 and name.substr(0,3) in ["COM","LPT"] and name[3] in "123456789"): return "windows_device_name_rejected"
	return ""

func native_path(path: String) -> String:
	var value=path.replace("\\","/") if OS.get_name()=="Windows" else path
	# Resolve the standard macOS aliases before checking for links below a temp root.
	if OS.get_name()=="macOS":
		if value=="/tmp" or value.begins_with("/tmp/"): value="/private/tmp"+value.substr(4)
		elif value=="/var" or value.begins_with("/var/"): value="/private/var"+value.substr(4)
	return value.trim_suffix("/")

func within(path: String, root_path: String, windows: bool) -> bool:
	var value=path.replace("\\","/").trim_suffix("/")
	var base=root_path.replace("\\","/").trim_suffix("/")
	if windows: value=value.to_lower();base=base.to_lower()
	return value==base or value.begins_with(base+"/")

func matching_root(path: String, roots: Array, player_root: String, windows: bool) -> String:
	if not syntax_error(path,windows).is_empty() or within(path,player_root,windows): return ""
	for base in roots:
		if within(path,base,windows) and not within(base,path,windows): return base
	return ""

func has_link(path: String) -> bool:
	var cursor=path
	while cursor.length()>1:
		var parent=cursor.get_base_dir()
		if parent==cursor or parent.is_empty() or parent.ends_with(":"): break
		var directory=DirAccess.open(parent)
		if directory!=null and directory.is_link(cursor.get_file()): return true
		cursor=parent
	return false

func prepare_output() -> String:
	var windows=OS.get_name()=="Windows"
	var reason=syntax_error(folder,windows)
	if not reason.is_empty(): return reason
	folder=native_path(folder)
	var player=native_path(ProjectSettings.globalize_path("user://"))
	if within(folder,player,windows): return "player_directory_rejected"
	var roots: Array=[]
	for name in ["RUNNER_TEMP","TMPDIR","TEMP","TMP"]:
		var root_path=native_path(OS.get_environment(name))
		if not syntax_error(root_path,windows).is_empty(): continue
		if DirAccess.dir_exists_absolute(root_path) and not has_link(root_path) and not within(root_path,player,windows): roots.append(root_path)
	if not windows:
		for root_path in ["/private/tmp","/tmp"]:
			var canonical=native_path(root_path)
			if DirAccess.dir_exists_absolute(canonical) and not has_link(canonical): roots.append(canonical)
	var ignored_output=false
	if FileAccess.file_exists("res://.gitignore"):
		for line in FileAccess.get_file_as_string("res://.gitignore").split("\n"):
			if line.strip_edges() in ["output/","/output/"]: ignored_output=true
	if ignored_output:
		var project_output=native_path(ProjectSettings.globalize_path("res://output"))
		if DirAccess.dir_exists_absolute(project_output) and not has_link(project_output): roots.append(project_output)
	output_root=matching_root(folder,roots,player,windows)
	if output_root.is_empty(): return "outside_allowed_temp_or_ignored_output"
	if not DirAccess.dir_exists_absolute(folder.get_base_dir()): return "output_parent_must_exist"
	if has_link(folder): return "symlink_or_junction_rejected"
	if DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(folder): return "output_already_exists"
	# Single atomic mkdir: never reuse an existing directory or create parents.
	if DirAccess.make_dir_absolute(folder)!=OK: return "fresh_output_creation_failed"
	return ""

func path_tests():
	var cases=[
		["C:\\Runner Temp\\font-one",true,true], ["c:/runner temp/字体-two",true,true],
		["C:relative",true,false], ["C:/Runner Temp/../player",true,false],
		["C:/Runner Temp-extra/font",true,false], ["C:/Runner Temp/NUL",true,false],
		["C:/Runner Temp/name.",true,false], ["\\\\server\\share\\font",true,false],
		["C:/Runner Temp/player/new",true,false],
		["/tmp/font-one",false,true], ["relative/font",false,false],
		["/tmp/../player",false,false], ["/tmp-extra/font",false,false],
		["/tmp/player/new",false,false]]
	for row in cases:
		var roots=["C:/Runner Temp"] if row[1] else ["/tmp"]
		var player="C:/Runner Temp/player" if row[1] else "/tmp/player"
		var accepted=not matching_root(row[0],roots,player,row[1]).is_empty()
		expect(accepted==row[2],"path policy lexical case: "+row[0])
		path_cases.append({"path":row[0],"windows_syntax":row[1],"expected":row[2],"accepted":accepted,"lexical_only":true})

func expect(ok: bool, message: String):
	checks+=1
	if not ok: failures.append(message)

func sha(data: PackedByteArray) -> String:
	var context=HashingContext.new()
	context.start(HashingContext.HASH_SHA256);context.update(data)
	return context.finish().hex_encode()

func scan(path: String):
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".gd") or file.ends_with(".tscn") or file.ends_with(".tres"): add_text(FileAccess.get_file_as_string(path+"/"+file))
	for child in DirAccess.get_directories_at(path):
		if path=="res://game/ui" and child=="checks": continue
		scan(path+"/"+child)

func add_text(value: String):
	for character in value:
		var code=character.unicode_at(0)
		if code>=32 and code!=127: required[code]=true

func font_chain(font: Font, manifest: Dictionary):
	expect(font is FontFile and not font is SystemFont,"font chain only contains packaged FontFile resources")
	if not font is FontFile: return
	expect(not font.allow_system_fallback,"font chain disables OS fallback")
	var expected={}
	for row in [manifest.primary]+manifest.fallbacks: expected[row.path]=row
	expect(expected.has(font.resource_path),"font resource path is in the pinned manifest")
	var data_sha=sha(font.data)
	if expected.has(font.resource_path): expect(data_sha==expected[font.resource_path].sha256,"imported font data matches pinned original bytes")
	fonts.append({"path":font.resource_path,"instance":font.get_instance_id(),"sha256":data_sha,"class":font.get_class(),"family":font.get_font_name(),"weight":font.get_font_weight(),"allow_system_fallback":font.allow_system_fallback})
	for fallback in font.fallbacks: font_chain(fallback,manifest)

func frames():
	for i in range(5): await process_frame

func click(id: String):
	var button=ui.get_action_control(id)
	expect(button is Button and button.is_visible_in_tree(),"actual Main control "+id)
	if not button is Button: return
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=button.get_global_rect().get_center();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		viewport.push_input(event,true);await process_frame
	await frames()

func inspect_bindings(node: Node):
	if node is Label or node is Button:
		var font=node.get_theme_font("font")
		expect(font==primary,"actual Main text uses shared packaged font: "+str(node.get_path()))
		bindings.append({"node":str(node.get_path()),"font_path":font.resource_path,"font_instance":font.get_instance_id(),"text":node.text})
		add_text(node.text)
	if node.has_method("canvas_text_bindings"):
		var actual: Array = node.canvas_text_bindings()
		expect(not actual.is_empty(), "actual Canvas draw consumers were observed")
		for i in range(actual.size()):
			var row: Dictionary = actual[i]; var font: Font = row.font
			expect(font == primary, "actual Canvas draw uses shared packaged FontFile")
			bindings.append({"node":str(node.get_path())+"/CanvasText["+str(i)+"]","consumer":"CanvasItem.draw_string","actual_draw":true,"font_path":font.resource_path,"font_instance":font.get_instance_id(),"text":str(row.text)})
			add_text(str(row.text))
	for child in node.get_children(): inspect_bindings(child)

func world_axes(axis: Vector2):
	for pair in [[JOY_AXIS_LEFT_X,axis.x],[JOY_AXIS_LEFT_Y,axis.y]]:
		var event=InputEventJoypadMotion.new();event.device=0;event.axis=pair[0];event.axis_value=pair[1]
		viewport.push_input(event,true)

func world_foot() -> Vector2:
	var player: Dictionary=ui.game.view().world.player
	return Vector2(player.x,player.y)

func world_walk(target: Vector2) -> bool:
	var deadline=Time.get_ticks_msec()+15000
	while world_foot().distance_to(target)>8 and Time.get_ticks_msec()<deadline:
		var delta=target-world_foot();world_axes((delta/8.0).limit_length());await process_frame
	world_axes(Vector2.ZERO);await frames()
	var arrived=world_foot().distance_to(target)<=8
	expect(arrived,"real joypad InputEvents reach World object at "+str(target))
	return arrived

func world_anchor(id: String) -> Vector2:
	for object in ui.game.view().world.geometry.objects:
		if object.id==id:return Vector2(object.anchor.x,object.anchor.y)
	expect(false,"Core geometry contains "+id);return world_foot()

func world_f():
	for down in [true,false]:
		var event=InputEventKey.new();event.physical_keycode=KEY_F;event.pressed=down
		viewport.push_input(event,true);await process_frame
	await frames()

func inspect_book(target: String, setup: String):
	await world_f()
	expect(ui.get_open_sheet()==target,"real F opens nearby production book "+target)
	inspect_bindings(ui)
	var book=ui.world_controller.books
	expect(Rect2(Vector2.ZERO,ui.size).encloses(book.get_global_rect()),"font metrics keep actual World book inside viewport: "+target)
	expect(book.scroll.size.y>=80,"font metrics leave usable World book scroll area: "+target)
	layouts.append({"entry":target,"setup":setup,"ui_size":str(ui.size),"sheet_rect":str(book.get_global_rect()),"scroll_rect":str(book.scroll.get_global_rect()),"body_minimum":str(book.content.get_combined_minimum_size())})
	await click("book_close")

func closing_fixture():
	# Font/layout fixture only, before mounting Main. This is NOT WS07 or a
	# runtime night-completion claim: legal real-Core movement/time builds state.
	var game=load("res://game/core/game_session.gd").new(23,"world-slice-v1")
	for point in [Vector2(1160,364),Vector2(1160,580),Vector2(1120,580)]: fixture_walk(game,point)
	for wave in range(3):
		var action="open_shop" if wave==0 else "start_wave"
		var payload={} if wave==0 else {"wave_id":game.view().service.next_wave_id}
		var result=game.command("world_interact",{"target_id":"door-bell","action":action,"payload":payload},"font-fixture-wave-"+str(wave))
		expect(result.ok,"legal pre-mount font fixture starts real wave")
		for n in range(4):
			if game.view().phase!="trading":break
			expect(game.advance(60000).ok,"legal pre-mount font fixture advances actual empty service")
	expect(game.view().phase=="closing","ledger layout fixture reaches real closing phase")
	fixture_walk(game,Vector2(580,606))
	return game

func fixture_walk(game, target: Vector2):
	for n in range(400):
		var player: Dictionary=game.view().world.player
		var delta=target-Vector2(player.x,player.y)
		if delta.length()<1:break
		var axis=(delta/8.0).limit_length()
		expect(game.command("world_input",{"move_x":axis.x,"move_y":axis.y}).ok,"pre-mount font fixture held axes")
		expect(game.advance(50).ok,"pre-mount font fixture real movement step")
	game.command("world_input",{"move_x":0.0,"move_y":0.0})

func run():
	probe_started=true
	if "--path-tests" in OS.get_cmdline_user_args(): path_tests()
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/fonts/font-manifest.json"))
	expect(manifest is Dictionary,"font manifest is available")
	if not manifest is Dictionary: finish();return
	var available=ResourceLoader.exists(manifest.primary.path,"FontFile")
	expect(available,"font loads through Godot imported-resource path, including export remapping")
	if not available: finish();return
	var provider=load("res://game/ui/portable_font.gd")
	expect(provider is Script and provider.can_instantiate(),"shared font provider compiles")
	if not provider is Script or not provider.can_instantiate(): finish();return
	primary=provider.get_font()
	font_chain(primary,manifest)
	for row in [manifest.primary]+manifest.fallbacks:
		expect(FileAccess.file_exists(row.license_path) and FileAccess.get_sha256(row.license_path)==row.license_sha256,"original OFL license is included unchanged")
		if row.has("notice_path"): expect(FileAccess.file_exists(row.notice_path) and FileAccess.get_sha256(row.notice_path)==row.notice_sha256,"original font copyright notice is included")
	scan("res://game");scan("res://scenes");add_text(FileAccess.get_file_as_string("res://project.godot"))
	viewport=SubViewport.new();viewport.size=Vector2i(844,390) if "--small" in OS.get_cmdline_user_args() else Vector2i(1440,904);root.add_child(viewport)
	ui=load("res://scenes/main.tscn").instantiate();ui.save_path=folder+"/unused-player-save.json";viewport.add_child(ui)
	await frames();inspect_bindings(ui)
	expect(is_instance_valid(ui.world_controller) and ui.game.view().has("world"),"default Main consumes actual production world profile")
	if not is_instance_valid(ui.world_controller) or not ui.game.view().has("world"):finish();return
	# Exercise actual loaded/job/ready labels as well as the four books. These
	# physical operations use real UI events, never direct Core commands.
	if await world_walk(world_anchor("pantry")+Vector2(0,24)):
		await world_f();inspect_bindings(ui)
	if await world_walk(world_anchor("prep")+Vector2(0,24)):
		await world_f();inspect_bindings(ui)
		await world_f();inspect_bindings(ui)
	if await world_walk(world_anchor("recipe-book")+Vector2(0,24)):await inspect_book("recipe-book","fresh Main, actual input movement")
	if await world_walk(world_anchor("menu-board")+Vector2(0,24)):await inspect_book("menu-board","fresh Main, actual input movement")
	var lane_reached=await world_walk(Vector2(1160,364)) and await world_walk(Vector2(1160,580)) and await world_walk(world_anchor("shop-exit"))
	if lane_reached:
		await world_f();expect(ui.game.view().world.region_id=="lane","real F crosses shop portal")
		if ui.game.view().world.region_id=="lane" and await world_walk(world_anchor("vendor")+Vector2(0,24)):await inspect_book("vendor","fresh Main, actual input portal and movement")
	ui.queue_free();await frames()
	var fixture=closing_fixture()
	ui=load("res://scenes/main.tscn").instantiate();ui.game=fixture;ui.save_path=folder+"/unused-ledger-player-save.json";viewport.add_child(ui);await frames()
	await inspect_book("ledger","legal real-Core closing fixture before Main mount; F/button input is actual, no runtime-night claim")
	expect(layouts.size()==4,"all four actual near-object World books completed layout checks")
	if "--missing-glyph" in OS.get_cmdline_user_args(): required[0x10ffff]=true
	for code in required:
		if not primary.has_char(code): missing.append({"codepoint":"U+%04X"%code,"character":String.chr(code)})
	expect(missing.is_empty(),"all required production characters exist in the packaged chain")
	finish()

func finish():
	var han=0
	for code in required:
		if code>=0x3400 and code<=0x9fff: han+=1
	var file=FileAccess.open(folder+"/font-report.json",FileAccess.WRITE)
	if file==null: reject_output("report_write_failed");return
	var sources={}
	for path in ["game/ui/portable_font.gd","game/ui/main.gd","game/ui/checks/portable_font.gd","assets/fonts/font-manifest.json","assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf.import","game/ui/world_play.gd","game/ui/world/world_input.gd","game/ui/world/world_books.gd","game/ui/world/world_controller.gd"]:
		sources[path]=FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "not-in-this-fixture-or-export"
	file.store_string(JSON.stringify({"protocol":1,"output_directory":folder,"output_policy":{"fresh":true,"accepted_root":output_root},"path_cases":path_cases,"checks":checks,"failures":failures,"fonts":fonts,"missing":missing,"required_characters":required.size(),"required_han":han,"bindings":bindings,"layouts":layouts,"source_sha256":sources,"engine":Engine.get_version_info().string,"claim":"Actual imported FontFile data hash and actual production Main Label/Button/Canvas draw consumers via InputEvents in headless SubViewport. Four real near-object books; ledger uses legal real-Core pre-mount closing fixture, not runtime-night/WS07 proof. Corpus conservatively includes production source comments. No OS fallback, native pixels, export or platform claim."},"  "));file.close()
	print("PORTABLE_FONT_RESULT "+JSON.stringify({"protocol":1,"report":folder+"/font-report.json","checks":checks,"failures":failures.size(),"exit_code":0 if failures.is_empty() else 1}))
	quit(0 if failures.is_empty() else 1)
