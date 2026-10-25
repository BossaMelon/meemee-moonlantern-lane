extends "res://tests/runtime/rain_night_path.gd"
## Replay the original real spore save and unchanged narrow-touch route.
var scroll_samples: Array=[]

func observe_scroll(button: Button, moment: String, point: Vector2=Vector2.ZERO):
	var bar=ui.scroll.get_v_scroll_bar()
	var focus=root.gui_get_focus_owner()
	var row={"elapsed_ms":Time.get_ticks_msec()-started_ms,"input_sequence":input_count,"moment":moment,"point":[point.x,point.y],"window_focused":root.has_focus(),"target_id":button.get_meta("action_id",button.name),"target_instance":button.get_instance_id(),"target_rect":str(button.get_global_rect()),"clip":str(ui.scroll.get_global_rect()),"scroll_instance":ui.scroll.get_instance_id(),"scroll_value":bar.value,"scroll_max":bar.max_value,"scroll_page":bar.page,"scroll_step":bar.step,"scrollbar_rect":str(bar.get_global_rect()),"focus_instance":focus.get_instance_id() if focus else -1,"focus_action":focus.get_meta("action_id",focus.name) if focus else "","phase":ui.game.view().phase,"selected_item":ui.selected_item}
	if moment=="touch_start":
		row.pointer_blockers=[]
		for child in ui.scroll.find_children("*","Control",true,false):
			if child.mouse_filter==Control.MOUSE_FILTER_STOP and child.is_visible_in_tree() and child.get_global_rect().has_point(point):
				row.pointer_blockers.append({"class":child.get_class(),"id":child.get_meta("action_id",child.name),"rect":str(child.get_global_rect())})
	scroll_samples.append(row)
	var file=FileAccess.open(folder+"/"+attempt+"-scroll.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(scroll_samples,"  ")); file.close()

func run():
	if config.get("headless_diagnostic",false): verification_kind="headless_navigation"
	await fresh(Vector2i(844,390),true)
	if not failures.is_empty(): return
	await restore("spore-warning")
	if not failures.is_empty(): return
	await rain_battle(1,true)
	if not failures.is_empty(): return
	await prepare_night()
	if not failures.is_empty(): return
	await wait_wave("intermission")
	if not failures.is_empty(): return
	await save_and_exit("narrow-complete")

func write_report():
	super.write_report()
	var path=folder+"/"+attempt+"-report.json"
	var report=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not report is Dictionary: return
	report.scroll_samples_path=folder+"/"+attempt+"-scroll.json"
	report.source_sha256["tests/runtime/narrow_boundary.gd"]=FileAccess.get_sha256("res://tests/runtime/narrow_boundary.gd")
	var file=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
