extends SceneTree
## No Main or Session is loaded. Observe Godot's resolved directory before game IO.
func _initialize():
	var args=OS.get_cmdline_user_args()
	var destination=""
	for i in range(args.size()-1):
		if args[i]=="--report": destination=args[i+1]
	if destination.is_empty(): quit(2); return
	var report={"user_dir":OS.get_user_data_dir(),"save_path":ProjectSettings.globalize_path("user://profiles/rain-night-v1/moonlantern.json"),"custom_user_dir_name":ProjectSettings.get_setting("application/config/custom_user_dir_name"),"use_custom_user_dir":ProjectSettings.get_setting("application/config/use_custom_user_dir"),"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"process_id":OS.get_process_id(),"game_loaded":false}
	var file=FileAccess.open(destination,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify(report,"  ")); file.close(); quit(0)
