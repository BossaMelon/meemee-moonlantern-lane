extends "res://game/ui/checks/rain_night_flow.gd"
## Same real GUI business flow, mounted in the actual native window for raw PNGs.
func _initialize():
	super._initialize()
	sources["game/ui/checks/rain_night_native.gd"]=FileAccess.get_sha256("res://game/ui/checks/rain_night_native.gd")

func mount_ui():
	ui=load("res://scenes/main.tscn").instantiate()
	ui.save_path=folder+"/preview-save.json"
	root.add_child(ui)

func screenshot(name: String):
	await frames(8)
	await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image()
	expect(image!=null,"actual native viewport returns pixels at "+name)
	if image==null: return
	expect(image.save_png(folder+"/"+name+".png")==OK,"raw native PNG saved at "+name)
	trace.append({"screenshot":name,"png_size":str(image.get_size()),"window_size":str(root.size),"virtual_ui_size":str(ui.size),"window_mode":root.mode,"display_mode":DisplayServer.window_get_mode(root.get_window_id()),"screen_size":str(DisplayServer.screen_get_size(root.current_screen)),"content_scale_size":str(root.content_scale_size),"viewport_visible_rect":str(root.get_visible_rect()),"viewport_texture_size":str(root.get_texture().get_size()),"display_server":DisplayServer.get_name(),"renderer_setting":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"adapter":RenderingServer.get_video_adapter_name()})
	if ui.get_open_sheet()!="":
		expect(Rect2(Vector2.ZERO,ui.size).encloses(ui.sheet_surface.get_global_rect()),"entire sheet fits actual native viewport at "+name)
	write_report()
