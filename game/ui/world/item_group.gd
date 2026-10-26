extends Node2D
## One visible stack of the same real item; all represented UIDs stay inspectable.
const Art = preload("res://game/ui/pixel_assets.gd")
const PortableFont = preload("res://game/ui/portable_font.gd")
var icon: Sprite2D
var count: Label

func _init():
	icon = Sprite2D.new(); icon.centered = false; add_child(icon)
	count = Label.new(); count.add_theme_font_override("font", PortableFont.get_font()); count.add_theme_font_size_override("font_size", 10)
	count.add_theme_color_override("font_color", Color("fff0cf")); count.add_theme_color_override("font_shadow_color", Color("171b29"))
	count.add_theme_constant_override("shadow_offset_x", 1); count.add_theme_constant_override("shadow_offset_y", 1); count.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(count)

func present(item_id: String, uids: Array, at: Vector2, icon_scale = 0.45):
	set_meta("item_uids", uids.duplicate()); position = at
	var asset = "cauldron_stir_left" if item_id == "stirring_cauldron" else item_id
	icon.texture = Art.sprite(asset); var pivot: Array = Art.entry(asset).get("pivot", [0,0])
	icon.offset = -Vector2(pivot[0],pivot[1]); icon.scale = Vector2.ONE*icon_scale
	count.text = "×"+str(uids.size()) if uids.size() > 1 else ""; count.position = Vector2(3,-1)
