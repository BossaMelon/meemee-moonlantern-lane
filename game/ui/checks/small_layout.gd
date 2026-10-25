extends "res://game/ui/checks/restaurant.gd"
## Reproduces P03's actual 844×390 and desktop quantity-strip failures.
func _initialize():
	super._initialize()
	folder=ProjectSettings.globalize_path("res://output/restaurant-ui/small-layout")
	DirAccess.make_dir_recursive_absolute(folder)
	source_hashes["game/ui/checks/small_layout.gd"]=FileAccess.get_sha256("res://game/ui/checks/small_layout.gd")

func shell_checks():
	for id in ["pause","save","load","quit","tab_shopping","tab_gear","tab_craft","tab_shelf","primary"]:
		var button=ui.get_action_control(id)
		expect(is_instance_valid(button) and button.is_visible_in_tree(),"visible shell control "+id)
		expect(Rect2(Vector2.ZERO,root.size).encloses(button.get_global_rect()),"viewport encloses "+id)
	expect(ui.scroll.size.y>=80,"usable scroll height "+str(ui.scroll.size.y))
	expect(not ui.illustration.missing.visible,"real pixel room loaded")
	for id in ["batch_more","batch_1","batch_3","batch_5"]:
		var button=ui.get_action_control(id)
		if not is_instance_valid(button): continue
		expect(button.size.y>=48 and button.size.y<=56,"quantity strip stays compact: "+id+" "+str(button.size))

func run():
	var pad_mode="pad" in OS.get_cmdline_user_args()
	selected_routes=PackedStringArray(["small-layout-pad" if pad_mode else "small-layout"])
	for size in [Vector2i(1280,720),Vector2i(844,390)]:
		mode="pad" if pad_mode else "touch"
		await fresh(size)
		if not failures.is_empty(): return
		shell_checks()
		await screenshot(str(size.x)+"-shopping-initial")
		await quantity(2)
		await activate("buy_flour")
		await activate("buy_pumpkin")
		await activate("batch_3")
		await activate("batch_less")
		await screenshot(str(size.x)+"-shopping-after-input")
		await activate("tab_gear")
		shell_checks()
		await screenshot(str(size.x)+"-equipment")
		await activate("primary")
		await quantity(2)
		await activate("craft_floating_pie")
		shell_checks()
		await screenshot(str(size.x)+"-preparation-after-input")
		await activate("to_shelf")
		await quantity(2)
		await activate("select_floating_pie")
		await activate("display_floating_pie")
		await activate("primary")
		await activate("pause")
		expect(ui.game.view().paused,"real trading pause input succeeds")
		shell_checks()
		await screenshot(str(size.x)+"-trading-paused")
	write_report()
	print("SMALL LAYOUT checks ",checks," failures ",failures.size())
	quit(0 if failures.is_empty() else 1)

func screenshot(name: String):
	await super.screenshot("pad-"+name if mode=="pad" else name)
