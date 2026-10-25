extends SceneTree
## Source/imported-resource and actual Main binding gate; no native/layout claim.
var folder="/private/tmp/p07-portable-font"
var failures: Array=[]
var checks=0
var bindings: Array=[]
var fonts: Array=[]
var missing: Array=[]
var required: Dictionary={}
var ui
var viewport: SubViewport
var primary: Font

func _initialize():
	if not OS.get_cmdline_user_args().is_empty(): folder=OS.get_cmdline_user_args()[0]
	if not folder.begins_with("/private/tmp/"): quit(2); return
	DirAccess.make_dir_recursive_absolute(folder)
	call_deferred("run")

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
	for child in node.get_children(): inspect_bindings(child)

func run():
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
	viewport=SubViewport.new();viewport.size=Vector2i(1440,904);root.add_child(viewport)
	ui=load("res://scenes/main.tscn").instantiate();ui.save_path=folder+"/unused-player-save.json";viewport.add_child(ui)
	await frames();inspect_bindings(ui)
	for entry in ["world_journal","world_craft","world_menu","world_gear"]:
		await click(entry);inspect_bindings(ui);await click("sheet_close")
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
	var sources={}
	for path in ["game/ui/portable_font.gd","game/ui/main.gd","game/ui/checks/portable_font.gd","assets/fonts/font-manifest.json","assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf.import"]:
		sources[path]=FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "not-in-this-fixture-or-export"
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"fonts":fonts,"missing":missing,"required_characters":required.size(),"required_han":han,"bindings":bindings,"source_sha256":sources,"engine":Engine.get_version_info().string,"claim":"Actual imported FontFile data hash and actual Main Label/Button font bindings via GUI InputEvents in headless SubViewport. Corpus conservatively includes production source comments; no OS fallback, native pixels, export or platform claim."},"  "));file.close()
	print("PORTABLE FONT ",checks," checks, missing glyphs ",missing.size(),", failures ",failures.size())
	quit(0 if failures.is_empty() else 1)
