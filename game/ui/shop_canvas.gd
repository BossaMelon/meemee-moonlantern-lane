extends Control
## Draws A01's real layered pixel room. It never decides economic outcomes.
const Art = preload("res://game/ui/pixel_assets.gd")
const NATIVE_SIZE = Vector2(384,256)
var state: Dictionary = {}
var showing_lane = false
var layout: Dictionary = {}
var effects: Array[Dictionary] = []
var visual_seconds = 0.0
var thank_seconds = 0.0
var missing: Label
var draw_scale = 1.0
var draw_origin = Vector2.ZERO

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = NATIVE_SIZE
	if FileAccess.file_exists(Art.ROOT+"restaurant-layout.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(Art.ROOT+"restaurant-layout.json"))
		if parsed is Dictionary: layout = parsed
	missing = Label.new()
	missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	missing.text = "像素饭店资源尚未加载"
	missing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(missing)
	queue_redraw()

func set_state(value: Dictionary):
	state = value
	queue_redraw()

func show_lane(value: bool):
	showing_lane = value
	queue_redraw()

func play_effect(effect_id: String, item_id: String, source: String):
	if effect_id.is_empty(): return
	effects.append({"effect_id":effect_id,"item_id":item_id,"source":source,"age":0.0,"duration":2.6})
	if effects.size()>8: effects.pop_front()
	queue_redraw()

func thank_guest(character_id: String):
	if character_id == "hagrid": thank_seconds = 1.0

func _process(delta):
	if state.get("paused",false): return
	visual_seconds += delta
	thank_seconds = maxf(0.0,thank_seconds-delta)
	for effect in effects: effect.age += delta
	effects = effects.filter(func(effect): return effect.age<effect.duration)
	queue_redraw()

func _point(value: Array) -> Vector2:
	return Vector2(value[0],value[1])

func _at(name: String, fallback: Vector2) -> Vector2:
	return _point(layout.get("anchors",{}).get(name,[fallback.x,fallback.y]))

func _sprite(id: String, foot: Vector2):
	var image = Art.sprite(id)
	if image == null: return
	var info = Art.entry(id)
	var pivot = _point(info.get("pivot",[0,0]))
	draw_texture(image,(foot-pivot).round())

func _installed() -> bool:
	for item in state.get("inventory",[]):
		if item.item_id == "stirring_cauldron": return item.installed>0
	return false

func _draw():
	var image = Art.background("restaurant-lane" if showing_lane else str(layout.get("background","restaurant-shell")))
	if is_instance_valid(missing): missing.visible = image == null
	if image == null: return
	# The layout reserves a native 384×256 area; no smoothing or fractional zoom.
	draw_scale = maxf(1.0,floorf(minf(size.x/NATIVE_SIZE.x,size.y/NATIVE_SIZE.y)))
	draw_origin = ((size-NATIVE_SIZE*draw_scale)/2.0).floor()
	draw_set_transform(draw_origin,0,Vector2.ONE*draw_scale)
	draw_texture(image,Vector2.ZERO)
	if showing_lane: return
	var serving = effects.any(func(effect): return effect.source == "sale")
	var stirring = effects.any(func(effect): return effect.effect_id == "self_stir")
	var trading = state.get("phase","") == "trading"
	var hagrid = state.get("pending",{}).get("character_id","") == "hagrid" or thank_seconds>0
	for layer in layout.get("draw_order",[]):
		var id = str(layer.sprite)
		var foot = _point(layer.foot)
		match str(layer.get("role","")):
			"actor":
				if id.begins_with("meemee"):
					id = "meemee_serve" if serving else ("meemee_blink" if fmod(visual_seconds,4.0)>3.85 else "meemee_idle")
				else:
					if not trading and thank_seconds<=0: continue
					id = ("hagrid_thanks" if thank_seconds>0 else "hagrid_idle") if hagrid else "student_idle"
			"cooking_overlay":
				if not _installed(): continue
				id = "cauldron_stir_right" if stirring and int(visual_seconds*4)%2 else "cauldron_stir_left"
		_sprite(id,foot)
	for effect in effects: _draw_effect(effect)

func _draw_effect(effect: Dictionary):
	var fraction = clampf(effect.age/effect.duration,0,1)
	var start = _at("serve",Vector2(236,180)) if effect.source=="sale" else _at("kitchen",Vector2(104,152))
	var end = _at("customer",Vector2(220,227))-Vector2(0,26) if effect.source=="sale" else _at("serve",Vector2(236,180))
	var at = start.lerp(end,fraction)-Vector2(0,8+sin(fraction*PI)*12)
	if effect.effect_id=="floating_delivery": _sprite("floating_plates",at+Vector2(0,10))
	_sprite(effect.item_id,at-Vector2(0,8) if effect.effect_id=="floating_delivery" else at)
	var amber = Color("edc46e")
	match str(effect.effect_id):
		"ember_aura", "self_stir":
			for n in range(5):
				var offset = Vector2(-9+n*5,-10-fmod(effect.age*10+n*4,18))
				draw_rect(Rect2((at+offset).round(),Vector2(2,3)),Color("fff3d0"))
			for n in range(8):
				var angle = n*TAU/8+effect.age
				draw_rect(Rect2((at+Vector2(cos(angle)*14,sin(angle)*5)).round(),Vector2(2,2)),amber)
		"trail_spark":
			for n in range(7):
				var previous = start.lerp(end,maxf(0,fraction-n*0.025))
				draw_rect(Rect2((previous+Vector2(n%2*3,-12)).round(),Vector2(2,2)),amber)
		"comet_orbit":
			for n in range(9):
				var angle = effect.age*4-n*0.22
				var offset = Vector2(cos(angle)*19,sin(angle)*7-11)
				draw_rect(Rect2((at+offset).round(),Vector2(3 if n==0 else 2,2)),Color("fff3d0") if n<3 else amber)
