extends SceneTree
## Minimal probe of actual source launcher without an existing import cache.
var output=""
func _initialize():
	output=OS.get_environment("P03_LAUNCH_OUTPUT")
	call_deferred("run")
func run():
	var scene=load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	scene.save_path=output+"/unused-isolated-save.json"
	root.add_child(scene)
	for _i in range(10): await process_frame
	await RenderingServer.frame_post_draw
	var png_error=root.get_texture().get_image().save_png(output+"/source-launch.png")
	var loaded=not scene.illustration.missing.visible
	var report={"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"main_scene":ProjectSettings.get_setting("application/run/main_scene"),"pixel_room_loaded":loaded,"screenshot_exit":png_error,"screenshot":output+"/source-launch.png","initial_phase":scene.game.view().phase,"initial_day":scene.game.view().day,"passed":loaded and png_error==OK and DisplayServer.get_name()!="headless"}
	var file=FileAccess.open(output+"/source-launch.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")); file.close()
	quit(0 if report.passed else 1)
