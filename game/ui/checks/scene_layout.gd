extends "res://game/ui/checks/scene_preview.gd"
## Geometry regression in a 1440x904 SubViewport; no native-window size claim.
## Same real visible InputEvents as the rendered preview; produces no PNG claim.
func _initialize():
	super._initialize()
	sources["game/ui/checks/scene_layout.gd"]=FileAccess.get_sha256("res://game/ui/checks/scene_layout.gd")

func mount_ui():
	var viewport=SubViewport.new()
	viewport.size=Vector2i(844,390) if "--small" in OS.get_cmdline_user_args() else Vector2i(1440,904)
	root.add_child(viewport)
	ui=load("res://scenes/main.tscn").instantiate()
	ui.save_path=folder+"/preview-save.json"
	viewport.add_child(ui)

func screenshot(name: String):
	await frames(8)
	var geometry={"layout_checkpoint":name,"virtual_ui_size":str(ui.size),"sheet":ui.get_open_sheet(),"surface_rect":str(ui.sheet_surface.get_global_rect()),"surface_minimum":str(ui.sheet_surface.get_combined_minimum_size()),"scroll_rect":str(ui.scroll.get_global_rect()),"scroll_minimum":str(ui.scroll.get_combined_minimum_size()),"body_minimum":str(ui.body.get_combined_minimum_size()),"caption_rect":str(ui.order_caption.get_global_rect()),"caption_minimum":str(ui.order_caption.get_combined_minimum_size())}
	trace.append(geometry)
	write_report()
	if ui.get_open_sheet()!="":
		expect(Rect2(Vector2.ZERO,ui.size).encloses(ui.sheet_surface.get_global_rect()),"entire sheet fits actual viewport at "+name+": "+str(ui.sheet_surface.get_global_rect()))
	write_report()
