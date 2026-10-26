extends Node2D
## A01 kit projection only. Footprints come from Core, never become colliders.
const Art = preload("res://game/ui/pixel_assets.gd")
const PortableFont = preload("res://game/ui/portable_font.gd")
var ground_rect = Rect2()
var collider_ids: Array = []
var wall = false
var module = ""
var elevation = 0
var _drawn: Array = []

static func core_rect(value: Dictionary) -> Rect2:
	return Rect2(Vector2(value.x-value.width/2.0,value.y-value.height/2.0),Vector2(value.width,value.height))

static func wall_pieces(geometry: Dictionary) -> Array:
	var horizontal: Array = []; var vertical: Array = []; var pieces: Array = []
	for collider in geometry.colliders:
		if int(collider.height) == 24: horizontal.append(collider)
		elif int(collider.width) == 24: vertical.append(collider)
	# Each true overlap belongs to one corner; strips exclude that overlap.
	for h in horizontal:
		var rect = core_rect(h); var left = rect.position.x; var right = rect.end.x
		for v in vertical:
			var overlap = rect.intersection(core_rect(v))
			if not overlap.has_area(): continue
			pieces.append({"rect":overlap,"ids":[str(h.id),str(v.id)],"module":"world_wall_corner"})
			if is_equal_approx(overlap.position.x,left): left = overlap.end.x
			elif is_equal_approx(overlap.end.x,right): right = overlap.position.x
		if right > left: pieces.append({"rect":Rect2(left,rect.position.y,right-left,rect.size.y),"ids":[str(h.id)],"module":"world_wall_h"})
	for v in vertical:
		var rect = core_rect(v); var top = rect.position.y; var bottom = rect.end.y
		for h in horizontal:
			var overlap = rect.intersection(core_rect(h))
			if not overlap.has_area(): continue
			if is_equal_approx(overlap.position.y,top): top = overlap.end.y
			elif is_equal_approx(overlap.end.y,bottom): bottom = overlap.position.y
		if bottom > top: pieces.append({"rect":Rect2(rect.position.x,top,rect.size.x,bottom-top),"ids":[str(v.id)],"module":"world_wall_v"})
	return pieces

func configure(rect: Rect2, ids: Array, wall_module = "", caption = ""):
	ground_rect = rect; collider_ids = ids.duplicate(); wall = wall_module != ""; module = wall_module
	elevation = int(Art.entry(module if wall else "world_wood_front").construction.elevation_px)
	position = Vector2(rect.get_center().x,rect.end.y)
	set_meta("core_collider_ids", collider_ids)
	if caption != "":
		var label = Label.new(); label.text = caption; label.position = Vector2(-rect.size.x/2,-elevation+4); label.size = Vector2(rect.size.x,16); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font",PortableFont.get_font()); label.add_theme_font_size_override("font_size",10); label.add_theme_color_override("font_color",Color("fff0cf")); label.add_theme_color_override("font_shadow_color",Color("332d36")); label.add_theme_constant_override("shadow_offset_y",1); label.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(label)
	queue_redraw()

func surface_anchor() -> Vector2:
	return ground_rect.get_center()-Vector2(0,elevation)

func place_book(asset: String):
	var book = Sprite2D.new(); book.texture = Art.sprite(asset); book.centered = false; book.scale = Vector2.ONE*0.5
	var entry = Art.entry(asset); var pivot: Array = entry.pivot; var size: Array = entry.size
	book.offset = -Vector2(pivot[0],pivot[1])
	book.position = surface_anchor()-position-Vector2(size[0],size[1])*0.25+Vector2(pivot[0],pivot[1])*0.5
	add_child(book)

func observe_foot(foot: Vector2):
	if not wall: return
	# A raised foreground wall may project across a real opening. Reveal the
	# actor there; this is opacity only and never changes the walkable geometry.
	var projected = Rect2(ground_rect.position-Vector2(0,elevation),ground_rect.size+Vector2(0,elevation))
	modulate.a = 0.32 if projected.grow_individual(48,0,48,0).has_point(foot) and not ground_rect.grow(12).has_point(foot) else 1.0

func _tile(asset: String, source: Rect2, destination: Rect2, plane: String):
	var texture = Art.sprite(asset)
	if texture == null or source.size.x <= 0 or source.size.y <= 0: push_error("Building kit region unavailable: "+asset); return
	for y in range(0,int(destination.size.y),int(source.size.y)):
		for x in range(0,int(destination.size.x),int(source.size.x)):
			var size = Vector2(minf(source.size.x,destination.size.x-x),minf(source.size.y,destination.size.y-y))
			var target = Rect2(destination.position+Vector2(x,y),size)
			var crop = Rect2(source.position,size)
			draw_texture_rect_region(texture,target,crop)
			_drawn.append({"asset":asset,"plane":plane,"source":[crop.position.x,crop.position.y,size.x,size.y],"target":[target.position.x+position.x,target.position.y+position.y,size.x,size.y]})

func _region(value: Array) -> Rect2: return Rect2(value[0],value[1],value[2],value[3])

func _draw():
	_drawn.clear()
	var rect = Rect2(ground_rect.position-position,ground_rect.size)
	if wall:
		var construction: Dictionary = Art.entry(module).construction
		_tile(module,_region(construction.cap_region),Rect2(rect.position-Vector2(0,elevation),rect.size),"cap")
		_tile(module,_region(construction.face_region),Rect2(rect.position+Vector2(0,rect.size.y-elevation),Vector2(rect.size.x,elevation)),"wall_face")
	else:
		_tile("world_wood_top",_region(Art.entry("world_wood_top").content_region),Rect2(rect.position-Vector2(0,elevation),rect.size),"top")
		var front = Rect2(rect.position+Vector2(0,rect.size.y-elevation),Vector2(rect.size.x,elevation))
		_tile("world_wood_front",_region(Art.entry("world_wood_front").content_region),front,"front")
		var post = "world_wood_foot" if "storage-body" in collider_ids else "world_wood_end"
		var source = _region(Art.entry(post).content_region)
		for x in [front.position.x,front.end.x-source.size.x]: _tile(post,source,Rect2(Vector2(x,front.position.y),source.size),"support")

func construction_bindings() -> Dictionary:
	return {"collider_ids":collider_ids.duplicate(),"wall":wall,"elevation":elevation,"ground":[ground_rect.position.x,ground_rect.position.y,ground_rect.size.x,ground_rect.size.y],"draws":_drawn.duplicate(true)}
