extends RefCounted
## Revisioned geometry fact source. Artwork consumes these footprints, not vice versa.
const MAP_ID = "rain-garden-two-routes"
const REVISION = 1
const SIZE = Vector2(960,540)
const EPSILON = 0.0001
const GRID = 32
const OBSTACLES = [
	{"id":"entry-stump","shape":"circle","x":265.0,"y":270.0,"radius":30.0},
	{"id":"north-west-stump","shape":"rect","x":370.0,"y":140.0,"width":50.0,"height":95.0},
	{"id":"north-east-stump","shape":"circle","x":585.0,"y":150.0,"radius":35.0},
	{"id":"crossing-stump","shape":"rect","x":505.0,"y":275.0,"width":60.0,"height":45.0},
	{"id":"canal-stump","shape":"circle","x":450.0,"y":430.0,"radius":28.0},
	{"id":"deep-stump","shape":"rect","x":705.0,"y":215.0,"width":45.0,"height":95.0}
]
const WATER = [{"id":"south-canal","shape":"rect","x":340.0,"y":335.0,"width":340.0,"height":120.0,"speed_scale":0.65}]
const SPAWNS = [
	{"id":"entry-rush","kind":"sparkcap","x":335.0,"y":270.0,"encounter_id":"entry"},
	{"id":"shelf-rush","kind":"sparkcap","x":540.0,"y":100.0,"encounter_id":"fork"},
	{"id":"canal-caster","kind":"sporecaster","x":610.0,"y":405.0,"encounter_id":"fork"},
	{"id":"deep-elite","kind":"moonheart","x":805.0,"y":225.0,"encounter_id":"deep"},
	{"id":"deep-caster","kind":"sporecaster","x":850.0,"y":380.0,"encounter_id":"deep"}
]
const RESOURCES = [
	{"id":"shelf-patch","item_id":"sparkcap","quantity":1,"x":415.0,"y":95.0,"collected":false},
	{"id":"canal-west-patch","item_id":"sparkcap","quantity":1,"x":375.0,"y":395.0,"collected":false},
	{"id":"canal-east-patch","item_id":"sparkcap","quantity":1,"x":560.0,"y":440.0,"collected":false}
]
static var _graphs: Dictionary = {}

static func data() -> Dictionary:
	return {"map_id":MAP_ID,"map_revision":REVISION,"width":960,"height":540,"entry":{"x":80.0,"y":270.0},
		"obstacles":OBSTACLES.duplicate(true),"water_zones":WATER.duplicate(true),"spawns":SPAWNS.duplicate(true),"resource_nodes":RESOURCES.duplicate(true),
		"routes":{"dry":[[80,270],[230,130],[460,95],[650,110],[820,180]],
			"wet":[[80,270],[230,365],[365,385],[520,375],[670,405],[820,365]],"connector":[[460,95],[470,260],[520,375]]}}

static func _rect(o: Dictionary) -> Rect2:
	return Rect2(o.x,o.y,o.width,o.height)

static func point_clear(p: Vector2, radius: float, obstacles: Array = OBSTACLES) -> bool:
	if p.x < radius or p.y < radius or p.x > SIZE.x-radius or p.y > SIZE.y-radius: return false
	for o in obstacles:
		if o.shape == "circle":
			if p.distance_squared_to(Vector2(o.x,o.y)) < pow(radius+o.radius-EPSILON,2): return false
		else:
			var box = _rect(o)
			var nearest = Vector2(clampf(p.x,box.position.x,box.end.x),clampf(p.y,box.position.y,box.end.y))
			if box.has_point(p) or p.distance_squared_to(nearest) < pow(maxf(0,radius-EPSILON),2): return false
	return true

static func _circle_hit(start: Vector2, delta: Vector2, center: Vector2, radius: float) -> Dictionary:
	var offset = start-center
	var square = offset.length_squared()-radius*radius
	if square <= EPSILON:
		var normal = offset.normalized() if offset.length_squared() > EPSILON else -delta.normalized()
		if delta.dot(normal) < -EPSILON: return {"t":0.0,"normal":normal}
		return {}
	var a = delta.length_squared()
	if a <= EPSILON: return {}
	var b = 2.0*offset.dot(delta)
	var discriminant = b*b-4.0*a*square
	if discriminant < 0: return {}
	var t = (-b-sqrt(discriminant))/(2.0*a)
	if t < 0 or t > 1: return {}
	return {"t":t,"normal":(start+delta*t-center).normalized()}

static func _rect_hit(start: Vector2, delta: Vector2, box: Rect2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	# Four straight faces plus rounded corners: an exact swept circle/AABB test.
	for face in [
		[0,box.position.x-radius,Vector2.LEFT,box.position.y,box.end.y],
		[0,box.end.x+radius,Vector2.RIGHT,box.position.y,box.end.y],
		[1,box.position.y-radius,Vector2.UP,box.position.x,box.end.x],
		[1,box.end.y+radius,Vector2.DOWN,box.position.x,box.end.x]]:
		var axis: int = face[0]
		if absf(delta[axis]) < EPSILON or delta.dot(face[2]) >= 0: continue
		var t = (face[1]-start[axis])/delta[axis]
		if t < -EPSILON or t > 1: continue
		var other = (start+delta*maxf(0,t))[1-axis]
		if other >= face[3]-EPSILON and other <= face[4]+EPSILON and (best.is_empty() or t < best.t): best = {"t":maxf(0,t),"normal":face[2]}
	if radius > 0:
		for corner in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
			var hit = _circle_hit(start,delta,corner,radius)
			if not hit.is_empty() and (best.is_empty() or hit.t < best.t): best = hit
	return best

static func sweep(start: Vector2, delta: Vector2, radius: float, obstacles: Array = OBSTACLES) -> Dictionary:
	var best = {"t":1.0,"normal":Vector2.ZERO,"obstacle_id":""}
	for o in obstacles:
		var hit = _circle_hit(start,delta,Vector2(o.x,o.y),radius+o.radius) if o.shape == "circle" else _rect_hit(start,delta,_rect(o),radius)
		if not hit.is_empty() and (best.obstacle_id == "" or hit.t < best.t-EPSILON):
			best = {"t":hit.t,"normal":hit.normal,"obstacle_id":o.id}
	for wall in [[0,radius,Vector2.RIGHT,"boundary-left"],[0,SIZE.x-radius,Vector2.LEFT,"boundary-right"],
		[1,radius,Vector2.DOWN,"boundary-top"],[1,SIZE.y-radius,Vector2.UP,"boundary-bottom"]]:
		var axis: int = wall[0]
		if absf(delta[axis]) < EPSILON or delta.dot(wall[2]) >= 0: continue
		var t = (wall[1]-start[axis])/delta[axis]
		if t >= -EPSILON and t <= 1 and (best.obstacle_id == "" or t < best.t): best = {"t":maxf(0,t),"normal":wall[2],"obstacle_id":wall[3]}
	var hit = best.obstacle_id != ""
	var safe_t = maxf(0.0,best.t-EPSILON/maxf(delta.length(),EPSILON)) if hit else 1.0
	return {"position":start+delta*safe_t,"hit":hit,"t":best.t,"normal":best.normal,"obstacle_id":best.obstacle_id}

static func move(start: Vector2, delta: Vector2, radius: float, slide: bool = true) -> Dictionary:
	var position = start
	var remaining = delta
	var collisions: Array = []
	for i in range(3 if slide else 1):
		var hit = sweep(position,remaining,radius)
		position = hit.position
		if not hit.hit: break
		if hit.obstacle_id not in collisions: collisions.append(hit.obstacle_id)
		if not slide: break
		remaining *= 1.0-hit.t
		remaining -= hit.normal*minf(0.0,remaining.dot(hit.normal))
		if remaining.length_squared() < EPSILON: break
	return {"position":position,"hit":not collisions.is_empty(),"obstacle_ids":collisions}

static func line_clear(start: Vector2, end: Vector2, radius: float = 0.0) -> bool:
	return not sweep(start,end-start,radius).hit

static func speed_scale(p: Vector2, hazards: Array = []) -> float:
	var scale_value = 1.0
	for zone in WATER:
		if _rect(zone).has_point(p): scale_value = minf(scale_value,zone.speed_scale)
	for zone in hazards:
		if zone.state == "active" and p.distance_squared_to(Vector2(zone.x,zone.y)) <= zone.radius*zone.radius: scale_value = minf(scale_value,zone.speed_scale)
	return scale_value

static func _graph(radius: float) -> Dictionary:
	var key = str(radius)
	if _graphs.has(key): return _graphs[key]
	var points = {}
	for y in range(17):
		for x in range(30):
			var p = Vector2(x*GRID+16,y*GRID+16)
			if point_clear(p,radius): points[Vector2i(x,y)] = p
	var links = {}
	for cell in points:
		links[cell] = []
		for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
			var next: Vector2i = cell+direction
			if points.has(next) and line_clear(points[cell],points[next],radius): links[cell].append(next)
	_graphs[key] = {"points":points,"links":links}
	return _graphs[key]

static func _nearest_visible(p: Vector2, graph: Dictionary, radius: float) -> Vector2i:
	var best = Vector2i(-1,-1)
	var distance = INF
	for cell in graph.points:
		var next = p.distance_squared_to(graph.points[cell])
		if next < distance and line_clear(p,graph.points[cell],radius): best = cell; distance = next
	return best

static func path(start: Vector2, goal: Vector2, radius: float = 17.0) -> Array:
	if not point_clear(start,radius) or not point_clear(goal,radius): return []
	if line_clear(start,goal,radius): return [goal]
	var graph = _graph(radius)
	var first = _nearest_visible(start,graph,radius)
	var last = _nearest_visible(goal,graph,radius)
	if first == Vector2i(-1,-1) or last == Vector2i(-1,-1): return []
	var queue: Array = [first]
	var parents = {first:first}
	var cursor = 0
	while cursor < queue.size() and not parents.has(last):
		var cell: Vector2i = queue[cursor]; cursor += 1
		for next in graph.links[cell]:
			if not parents.has(next): parents[next] = cell; queue.append(next)
	if not parents.has(last): return []
	var out: Array = [goal]
	var cell = last
	while cell != first:
		out.push_front(graph.points[cell]); cell = parents[cell]
	out.push_front(graph.points[first])
	return out
