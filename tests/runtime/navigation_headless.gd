extends "res://tests/runtime/critical_path.gd"
## Input routing diagnostic only. This cannot satisfy the rendered supervisor.

func _initialize():
	verification_kind="headless_navigation"
	super._initialize()

func screenshot(_name: String):
	pass # No image or rendered-asset assertion is claimed by this separate suite.

func run():
	expect(DisplayServer.get_name()=="headless","navigation diagnostic requires --headless")
	expect(stage=="navigation","headless diagnostic is limited to navigation")
	if not failures.is_empty(): return
	var size=Vector2i(1280,800)
	if config.has("size"): size=Vector2i(config.size[0],config.size[1])
	await fresh(size)
	if config.has("logical_size"):
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_size=Vector2i(config.logical_size[0],config.logical_size[1])
		await frames(6)
	if not failures.is_empty(): return
	await navigation_checks()
	if not failures.is_empty(): return
	checkpoint="navigation-complete"
	write_report()
	quit(0)
