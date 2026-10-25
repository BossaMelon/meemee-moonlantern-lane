extends Control
## Presentation-only image surface. Pixel assets are supplied by A01.
## Paths are assigned by the scene; missing artwork is explicit rather than
## replaced with the rejected vector illustration.
@export_file("*.png") var shop_texture_path: String = ""
@export_file("*.png") var lane_texture_path: String = ""
var state: Dictionary = {}
var showing_lane = false
var artwork: TextureRect
var missing: Label
var caption: Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(0, 160)
	artwork = TextureRect.new()
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(artwork)
	missing = Label.new()
	missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	missing.text = "月灯巷 · 像素店景待接入"
	missing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(missing)
	caption = Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -36
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	_load_artwork()

func set_state(value: Dictionary):
	state = value
	if is_instance_valid(caption):
		caption.text = "小店正在歇一歇" if state.get("paused",false) else ("特殊咨询 · 客人正在等咩咩" if not state.get("pending",{}).is_empty() else "")

func show_lane(value: bool):
	showing_lane = value
	_load_artwork()

func _load_artwork():
	if not is_instance_valid(artwork): return
	var path = lane_texture_path if showing_lane else shop_texture_path
	artwork.texture = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null
	missing.visible = artwork.texture == null
	missing.text = "月灯巷 · 像素街景待接入" if showing_lane else "月灯巷 · 像素店景待接入"
