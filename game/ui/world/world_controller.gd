extends Control
## Main's presentation/modal/battle router. It never advances the Session.
const WorldScene = preload("res://scenes/ui/world_play.tscn")
const Books = preload("res://game/ui/world/world_books.gd")
const PortableFont = preload("res://game/ui/portable_font.gd")
const BATTLE = "res://scenes/expedition/expedition.tscn"
signal movement_requested(axis)
signal intent_requested(option)
signal book_opened(target_id)
signal book_closed
signal pause_requested
signal save_requested(exit_after)
signal load_requested
signal returned
var world
var books
var battle_host: Control
var battle_panel: Control
var modal: Control
var pause_surface: PanelContainer
var book_target = ""
var current_view: Dictionary = {}
var session: RefCounted
var save_allowed = false
var _pause_controls: Dictionary = {}

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = WorldScene.instantiate(); add_child(world)
	world.movement_requested.connect(func(axis): movement_requested.emit(axis))
	world.interaction_requested.connect(func(option): intent_requested.emit(option))
	world.book_requested.connect(func(option): book_opened.emit(str(option.target_id)))
	world.pause_requested.connect(func(): pause_requested.emit())
	battle_host = Control.new(); battle_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); battle_host.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(battle_host)
	modal = Control.new(); modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); modal.visible = false; add_child(modal)
	var veil = ColorRect.new(); veil.color = Color("12172488"); veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); modal.add_child(veil)
	books = Books.new(); modal.add_child(books); books.visible = false
	books.intent_requested.connect(func(option): intent_requested.emit(option)); books.close_requested.connect(func(): book_closed.emit())
	pause_surface = PanelContainer.new(); modal.add_child(pause_surface); pause_surface.visible = false
	var paper = StyleBoxFlat.new(); paper.bg_color = Color("e9dcb7"); paper.set_content_margin_all(16); pause_surface.add_theme_stylebox_override("panel", paper)
	var stack = VBoxContainer.new(); pause_surface.add_child(stack)
	var label = Label.new(); label.text = "灯还亮着，歇一歇"; label.add_theme_font_override("font", PortableFont.get_font()); label.add_theme_color_override("font_color", Color("463626")); stack.add_child(label)
	for row in [["resume", "继续", func(): pause_requested.emit()], ["save", "保存此刻", func(): save_requested.emit(false)], ["load", "恢复本次世界存档", func(): load_requested.emit()], ["quit", "保存并退出", func(): save_requested.emit(true)]]:
		var button = Button.new(); button.text = row[1]; button.custom_minimum_size = Vector2(48, 48); button.set_meta("action_id", row[0]); button.pressed.connect(row[2], CONNECT_DEFERRED); stack.add_child(button); _pause_controls[row[0]] = button
	resized.connect(_layout); _layout()

func _layout():
	if not is_instance_valid(books): return
	books.size = Vector2(minf(500, size.x-32), minf(360, size.y-64)); books.position = ((size-books.size)/2).round()
	pause_surface.size = Vector2(minf(360, size.x-32), minf(340, size.y-48)); pause_surface.position = ((size-pause_surface.size)/2).round()

func clear_inputs():
	world.clear_inputs()
	if is_instance_valid(battle_panel): battle_panel.release_inputs()

func open_book(target: String): book_target = target; clear_inputs()
func close_book(): book_target = ""; clear_inputs()

func present(view: Dictionary):
	current_view = view
	var battle = str(view.get("phase", "")) == "expedition"
	world.visible = not battle; battle_host.visible = battle
	if battle:
		book_target = ""
		if not is_instance_valid(battle_panel) and session != null:
			battle_panel = load(BATTLE).instantiate(); battle_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); battle_host.add_child(battle_panel); battle_panel.bind_session(session)
			battle_panel.returned.connect(func(): returned.emit(), CONNECT_DEFERRED)
			battle_panel.pause_requested.connect(func(): pause_requested.emit(), CONNECT_DEFERRED)
			battle_panel.save_requested.connect(func(): save_requested.emit(false), CONNECT_DEFERRED)
			battle_panel.save_quit_requested.connect(func(): save_requested.emit(true), CONNECT_DEFERRED)
			battle_panel.grab_focus()
		elif is_instance_valid(battle_panel): battle_panel.refresh()
	elif is_instance_valid(battle_panel):
		battle_host.remove_child(battle_panel); battle_panel.queue_free(); battle_panel = null
	if not battle and view.has("world"): world.present(view)
	world.set_controls_enabled(not battle and book_target.is_empty() and not bool(view.get("paused", false)) and save_allowed)
	books.visible = not battle and not book_target.is_empty()
	pause_surface.visible = not battle and book_target.is_empty() and bool(view.get("paused", false))
	modal.visible = books.visible or pause_surface.visible
	if books.visible: books.present(book_target, view)
	for id in ["resume", "save"]: _pause_controls[id].disabled = not save_allowed
	_pause_controls.quit.text = "保存并退出" if save_allowed else "退出，保留原存档"
	if pause_surface.visible:
		var focused = get_viewport().gui_get_focus_owner()
		if focused == null or not pause_surface.is_ancestor_of(focused):
			if save_allowed: _pause_controls.resume.grab_focus()
			else: _pause_controls.quit.grab_focus()
	_layout()

func handle_back(event: InputEvent) -> bool:
	if str(current_view.get("phase", "")) == "expedition": return false
	var back = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	var start = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START
	if back and not book_target.is_empty(): book_closed.emit(); return true
	if back or start: pause_requested.emit(); return true
	return false

func get_action_control(id: String) -> Control:
	if books.visible and books.controls.has(id): return books.controls[id]
	if pause_surface.visible and _pause_controls.has(id): return _pause_controls[id]
	return null
