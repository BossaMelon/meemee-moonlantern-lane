extends Control
## Original code-drawn placeholder illustration. It reflects the live core view.
var state: Dictionary = {}
var font: Font
const INK = Color("353553")
const WOOD = Color("805344")
const GOLD = Color("e6bb76")
const CREAM = Color("fff0cb")

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300, 280)

func set_state(value: Dictionary):
	state = value
	queue_redraw()

func _process(_delta):
	queue_redraw()

func _poly(points: Array, color: Color):
	draw_colored_polygon(PackedVector2Array(points), color)
	draw_polyline(PackedVector2Array(points + [points[0]]), INK, 2.3, true)

func _line(a: Vector2, b: Vector2, color: Color = INK, width: float = 2.5):
	draw_line(a, b, color, width, true)

func _text(at: Vector2, value: String, size_px: int = 20, color: Color = CREAM):
	if font:
		draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _lamp(at: Vector2, small: bool = false):
	var s = 0.7 if small else 1.0
	draw_circle(at, 36*s, Color(1, 0.78, 0.37, 0.08))
	draw_circle(at, 26*s, Color(1, 0.78, 0.37, 0.12))
	draw_circle(at, 15*s, GOLD)
	draw_arc(at + Vector2(6,-5)*s, 13*s, 0.8, 4.6, 20, CREAM, 4*s, true)
	_line(at+Vector2(0,15)*s, at+Vector2(0,28)*s, WOOD, 4*s)
	_line(at+Vector2(-12,29)*s, at+Vector2(12,29)*s, WOOD, 4*s)

func _pen(at: Vector2):
	_line(at+Vector2(-10,14), at+Vector2(12,-19), INK, 4)
	_poly([at+Vector2(0,-1),at+Vector2(20,-23),at+Vector2(26,-2),at+Vector2(7,5)], Color("a6bcb4"))
	_line(at+Vector2(-11,15),at+Vector2(-14,22),GOLD,3)

func _charm(at: Vector2):
	_poly([at+Vector2(0,-20),at+Vector2(18,0),at+Vector2(0,22),at+Vector2(-18,0)],Color("87a898"))
	draw_arc(at, 9, 0.2, 5.6, 18, CREAM, 2, true)
	_line(at+Vector2(0,-20),at+Vector2(0,-27),GOLD,3)

func _bell(at: Vector2):
	_poly([at+Vector2(-16,9),at+Vector2(-11,-11),at+Vector2(0,-17),at+Vector2(11,-11),at+Vector2(16,9)],GOLD)
	draw_circle(at+Vector2(0,12),4,WOOD)
	_line(at+Vector2(-20,10),at+Vector2(20,10),INK)

func _person(at: Vector2, me: bool):
	# Hand drawn chibi silhouette: generous head, tiny shoes and soft outlines.
	_ellipse(Rect2(at+Vector2(-31,27),Vector2(62,16)),Color(0.12,0.12,0.2,0.20))
	draw_circle(at+Vector2(-10,28),8,INK)
	draw_circle(at+Vector2(11,28),8,INK)
	_poly([at+Vector2(-21,-8),at+Vector2(22,-8),at+Vector2(28,25),at+Vector2(-27,25)], Color("dfac78") if me else Color("8a9fb2"))
	if me:
		_poly([at+Vector2(-13,-5),at+Vector2(13,-5),at+Vector2(17,24),at+Vector2(-18,24)],Color("fff1ca"))
		draw_circle(at+Vector2(0,7),5,GOLD)
	draw_circle(at+Vector2(0,-34),32,Color("55454c") if me else Color("66535b"))
	draw_circle(at+Vector2(0,-28),26,Color("f4c5a0"))
	if me:
		for offset in [Vector2(-22,-52),Vector2(-8,-60),Vector2(7,-60),Vector2(22,-52)]:
			draw_circle(at+offset,12,CREAM)
		draw_arc(at+Vector2(-25,-37),17,1.2,4.5,20,Color("55454c"),9,true)
		draw_arc(at+Vector2(25,-37),17,-1.4,1.8,20,Color("55454c"),9,true)
	else:
		_poly([at+Vector2(-32,-53),at+Vector2(-20,-76),at+Vector2(17,-74),at+Vector2(31,-49)],Color("69748a"))
		_line(at+Vector2(-35,-49),at+Vector2(35,-49),INK,5)
		_line(at+Vector2(-24,-7),at+Vector2(22,-5),Color("d3957b"),8)
	for dx in [-9,9]:
		draw_circle(at+Vector2(dx,-29),2.7,INK)
		draw_circle(at+Vector2(dx*1.6,-20),4,Color(0.93,0.56,0.48,0.35))
	draw_arc(at+Vector2(0,-19),5,0.1,3.0,12,INK,1.5,true)

func _ellipse(rect: Rect2, color: Color):
	var points = PackedVector2Array()
	for n in range(40):
		var a = TAU*n/40
		points.append(rect.get_center()+Vector2(cos(a)*rect.size.x/2,sin(a)*rect.size.y/2))
	draw_colored_polygon(points,color)

func _draw():
	var scale_value = minf(size.x/800.0, size.y/610.0)
	draw_set_transform(Vector2((size.x-800*scale_value)/2,(size.y-610*scale_value)/2),0,Vector2.ONE*scale_value)
	# Night lane and one warm, open dollhouse room.
	_ellipse(Rect2(40,480,720,105),Color(0.09,0.11,0.21,0.18))
	_poly([Vector2(64,207),Vector2(395,85),Vector2(395,309),Vector2(64,436)],Color("b48065"))
	_poly([Vector2(395,85),Vector2(740,209),Vector2(740,437),Vector2(395,309)],Color("9a6b5d"))
	_poly([Vector2(64,436),Vector2(395,309),Vector2(740,437),Vector2(400,582)],Color("c39471"))
	for n in range(1,8):
		var f = n/8.0
		_line(Vector2(64,436).lerp(Vector2(400,582),f),Vector2(395,309).lerp(Vector2(740,437),f),Color("ab7b60"),1.5)
	_line(Vector2(64,207),Vector2(395,85),GOLD,9)
	_line(Vector2(395,85),Vector2(740,209),GOLD,9)
	# Moon window, curtains and star lights.
	_poly([Vector2(128,224),Vector2(253,178),Vector2(253,298),Vector2(128,344)],Color("343e64"))
	_line(Vector2(190,201),Vector2(190,322),WOOD,6)
	_line(Vector2(128,284),Vector2(253,238),WOOD,6)
	draw_circle(Vector2(222,218),18,GOLD)
	draw_circle(Vector2(230,210),16,Color("343e64"))
	for at in [Vector2(150,244),Vector2(233,270),Vector2(160,306)]:
		draw_circle(at,2,CREAM)
	if int(state.get("day",1)) == 3:
		for n in range(9):
			var x = 139+n*12
			var y = 240+(n*13%65)
			_line(Vector2(x,y),Vector2(x-4,y+12),Color("93b6ca"),1.4)
	_poly([Vector2(111,227),Vector2(139,219),Vector2(133,339),Vector2(110,354)],Color("786f86"))
	# Built in shelving and visible stock.
	_poly([Vector2(459,160),Vector2(674,238),Vector2(674,380),Vector2(459,302)],WOOD)
	for y in [213,273,331]:
		_line(Vector2(458,y-44),Vector2(677,y+36),Color("e0b180"),7)
	_lamp(Vector2(508,212),true)
	_charm(Vector2(562,234))
	_bell(Vector2(625,259))
	for at in [Vector2(493,271),Vector2(532,285),Vector2(608,313)]:
		draw_rect(Rect2(at,Vector2(17,24)),Color("aab5aa"))
		_line(at+Vector2(0,8),at+Vector2(17,8),GOLD,3)
	_text(Vector2(471,155),"月灯奇物",25)
	# Folded rug, shopkeeper and counter.
	_poly([Vector2(238,444),Vector2(398,384),Vector2(594,456),Vector2(432,521)],Color("8f7c83"))
	_person(Vector2(382,365),true)
	_poly([Vector2(284,391),Vector2(451,333),Vector2(591,387),Vector2(421,452)],Color("d3a376"))
	_poly([Vector2(284,391),Vector2(421,452),Vector2(421,500),Vector2(284,439)],WOOD)
	_poly([Vector2(421,452),Vector2(591,387),Vector2(591,435),Vector2(421,500)],Color("a16c53"))
	_line(Vector2(293,398),Vector2(415,445),GOLD,3)
	_lamp(Vector2(494,375))
	_pen(Vector2(390,387+sin(Time.get_ticks_msec()/600.0)*4))
	_text(Vector2(330,466),"咩咩的小店",19)
	# Plant at the entrance.
	_poly([Vector2(89,413),Vector2(125,413),Vector2(118,451),Vector2(98,451)],Color("d4a77a"))
	for n in range(5):
		var at = Vector2(107,410)
		var end = at+Vector2(-32+n*16,-35-abs(n-2)*6)
		_line(at,end,Color("687e68"),4)
		_ellipse(Rect2(end-Vector2(13,7),Vector2(26,14)),Color("91a48a"))
	var is_open = str(state.get("phase","shopping")) == "trading"
	if is_open:
		_person(Vector2(600,470),false)
		if not state.get("pending",{}).is_empty():
			draw_style_box(_speech_style(),Rect2(537,338,177,53))
			_text(Vector2(552,371),"想请咩咩帮忙…",18,INK)
	else:
		_text(Vector2(551,505),"来日方长",21,Color("6e5860"))
	if state.get("paused",false):
		_text(Vector2(298,552),"小店正在歇一歇",23,INK)

func _speech_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = CREAM
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	return style
