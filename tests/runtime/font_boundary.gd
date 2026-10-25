extends "res://tests/runtime/narrow_boundary.gd"
## P06: observe actual font users after real page inputs; no font/state patching.
const FONT_SHA = "faa6c9df652116dde789d351359f3d7e5d2285a2b2a1f04a2d7244df706d5ea9"
const FONT_PATH = "res://assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf"
var font_pages: Array=[]
var batch_proof: Dictionary={}

func observed_font(value: Font) -> Dictionary:
	var row={"class":value.get_class() if value!=null else "null","instance":str(value.get_instance_id()) if value!=null else "","path":value.resource_path if value!=null else ""}
	expect(value is FontFile and not value is SystemFont,"actual text consumer uses packaged FontFile")
	if not value is FontFile: return row
	var context=HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(value.data)
	row.data_sha256=context.finish().hex_encode()
	row.data_bytes=value.data.size()
	row.allow_system_fallback=value.allow_system_fallback
	row.fallback_count=value.fallbacks.size()
	var expected="0".repeat(64) if config.get("font_negative_data_sha",false) else FONT_SHA
	expect(row.data_sha256==expected,"actual FontFile data SHA matches pinned font")
	expect(row.data_bytes==8331336 and row.path==FONT_PATH,"actual FontFile bytes and resource path match pinned font")
	expect(not row.allow_system_fallback and row.fallback_count==0,"actual FontFile has no OS or resource fallbacks")
	return row

func text_bindings(node: Node, primary: Font, rows: Array):
	if (node is Label or node is Button) and node.is_visible_in_tree():
		var font=node.get_theme_font("font")
		var missing: Array=[]
		for character in node.text:
			if character.unicode_at(0)>=32 and character.unicode_at(0)!=127 and not font.has_char(character.unicode_at(0)): missing.append(character)
		expect(font==primary,"visible actual text shares Main font: "+str(node.get_path()))
		expect(missing.is_empty(),"visible text has packaged glyphs: "+str(node.get_path()))
		rows.append({"node":str(node.get_path()),"text":node.text,"font_instance":str(font.get_instance_id()),"font_path":font.resource_path,"missing_glyphs":missing,"rect":str(node.get_global_rect())})
	for child in node.get_children(): text_bindings(child,primary,rows)

func capture_page(name: String):
	await frames(3)
	# Read the font already installed by Main. Calling the provider here could
	# repair a wrong fallback setting and conceal a product binding defect.
	var primary: Font=ui.theme.default_font
	var row={"page":name,"input_sequence":input_count,"font":observed_font(primary),"bindings":[],"canvas_font":{},"buttons":[]}
	font_pages.append(row)
	if not failures.is_empty(): return
	text_bindings(ui,primary,row.bindings)
	expect(not row.bindings.is_empty(),"page contains actual visible text: "+name)
	if name.begins_with("expedition"):
		var panel=ui.battle_panel
		expect(panel.is_node_ready() and panel.is_visible_in_tree(),"actual expedition Canvas is ready and visible")
		row.canvas_font=observed_font(panel.font)
		expect(panel.font==primary,"actual expedition Canvas shares Main FontFile")
		if name=="expedition-paused":
			for id in ["pause_button","save_button","save_quit_button","return_button"]:
				var button: Button=panel.get(id)
				var font=button.get_theme_font("font")
				var item={"id":id,"text":button.text,"font_instance":str(font.get_instance_id()),"font_path":font.resource_path,"ready":button.is_node_ready(),"visible":button.is_visible_in_tree(),"enabled":not button.disabled,"inside_viewport":root.get_visible_rect().encloses(button.get_global_rect()),"rect":str(button.get_global_rect())}
				row.buttons.append(item)
				expect(font==primary and item.ready and item.visible and item.enabled and item.inside_viewport,"actual paused expedition Button is visible, reachable and font-bound: "+id)
	if not config.get("headless_diagnostic",false): expect(root.has_focus(),"font capture has actual native focus: "+name)
	if not failures.is_empty(): return
	await screenshot(mode+"-font-"+name)
	row.screenshot=screenshots.back() if not screenshots.is_empty() and not config.get("headless_diagnostic",false) else ""
	write_report()

func run():
	if config.get("headless_diagnostic",false): verification_kind="headless_navigation"
	expect(not config.get("font_negative_data_sha",false) or verification_kind=="headless_navigation","negative font expectation is headless-only")
	var dimensions=config.get("size",[1280,800])
	await fresh(Vector2i(dimensions[0],dimensions[1]),false)
	if not failures.is_empty(): return
	await capture_page("main")
	if not failures.is_empty(): return
	# Real ingredients give the recipe, menu and journal concrete dynamic text.
	# Remain in shopping so a real expedition can still be entered without a night.
	await buy_missing({"flour":1,"pumpkin":1})
	if not failures.is_empty(): return
	await capture_page("shopping")
	await open_sheet("craft")
	await activate("recipe_floating_pie")
	var count_before=action_count
	await scroll_to(ui.get_action_control("craft_floating_pie"))
	var lower_scroll=ui.scroll.scroll_vertical
	await quantity(3)
	var reached_three=ui.batch==3
	await quantity(1)
	var batch_button=ui.get_action_control("batch_1")
	batch_proof={"selected_three":reached_three,"selected_one":ui.batch==1,"economic_delta":action_count-count_before,"lower_scroll":lower_scroll,"batch_scroll":ui.scroll.scroll_vertical,"batch_inside_clip":ui.scroll.get_global_rect().encloses(batch_button.get_global_rect()),"input_sequence":input_count,"scroll_samples":scroll_samples.size()}
	expect(reached_three and ui.batch==1 and action_count==count_before and batch_proof.batch_inside_clip,"real batch inputs reach 3 then 1 without economic actions")
	if dimensions==[844,390]: expect(lower_scroll>ui.scroll.scroll_vertical and scroll_samples.size()>0,"narrow real scroll returns from recipe action to visible batch selector")
	if not failures.is_empty(): return
	await activate("craft_floating_pie")
	expect(inventory("floating_pie").bag==1,"one legitimate dish exists for actual menu text")
	await capture_page("craft")
	if not failures.is_empty(): return
	for name in ["shelf","journal","gear"]:
		await open_sheet(name)
		await capture_page(name)
		if not failures.is_empty(): return
	await activate("start_expedition")
	expect(ui.game.view().phase=="expedition","real input enters actual expedition Canvas")
	if not failures.is_empty(): return
	await capture_page("expedition-live")
	await pause_combat()
	expect(ui.game.view().paused,"real input pauses expedition for all four Buttons")
	await capture_page("expedition-paused")
	if not failures.is_empty(): return
	await activate_control(ui.battle_panel.save_button,"font-battle-save")
	expect("保存成功" in ui.feedback.text,"actual expedition save control succeeds")
	await expect_product_exit("font-complete",ui.battle_panel.save_quit_button)

func write_report():
	super.write_report()
	var path=folder+"/"+attempt+"-report.json"
	var report=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not report is Dictionary: return
	report.font_pages=font_pages
	report.batch_proof=batch_proof
	report.font_negative_data_sha=config.get("font_negative_data_sha",false)
	report.input_count=input_count
	report.scope="Targeted packaged-font consumers, page input, narrow scroll and rendered assets; not a full-night/Q06/platform/human retest."
	for source in ["tests/runtime/font_boundary.gd","game/ui/portable_font.gd","assets/fonts/font-manifest.json","assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf"]: report.source_sha256[source]=FileAccess.get_sha256("res://"+source)
	var file=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
