extends RefCounted
const RADIUS = 12.0
const SPEED = 160.0
const EPS = 0.00001

static func object(id: String) -> Dictionary:
	for row in LAYOUT.objects:
		if row.id == id: return row
	return {}

static func geometry(region: String) -> Dictionary:
	var result = LAYOUT.regions[region].duplicate(true)
	result.objects = LAYOUT.objects.filter(func(o): return o.region_id == region).duplicate(true)
	result.portals = LAYOUT.portals.filter(func(o): return object(o.id).region_id == region).duplicate(true)
	return result

static func rect(c: Dictionary) -> Rect2:
	return Rect2(c.x-c.width/2.0,c.y-c.height/2.0,c.width,c.height)

static func clear_position(region: String, p: Vector2) -> bool:
	var g = LAYOUT.regions[region]
	if p.x < RADIUS or p.y < RADIUS or p.x > g.width-RADIUS or p.y > g.height-RADIUS: return false
	for c in g.colliders:
		var r = rect(c); var closest = p.clamp(r.position,r.end)
		if p.distance_squared_to(closest) < RADIUS*RADIUS-0.001: return false
	return true

static func clear_line(region: String, a: Vector2, b: Vector2) -> bool:
	for c in LAYOUT.regions[region].colliders:
		var r = rect(c); var low = 0.0; var high = 1.0; var delta = b-a
		for axis in range(2):
			if absf(delta[axis]) < EPS:
				if a[axis] < r.position[axis] or a[axis] > r.end[axis]: low = 2.0; break
			else:
				var t1 = (r.position[axis]-a[axis])/delta[axis]; var t2 = (r.end[axis]-a[axis])/delta[axis]
				low = maxf(low,minf(t1,t2)); high = minf(high,maxf(t1,t2))
		if low <= high: return false
	return true

static func sweep(p: Vector2, d: Vector2, r: Rect2) -> Dictionary:
	var best = {"t":1.0,"normal":Vector2.ZERO}
	for axis in range(2):
		if absf(d[axis]) < EPS: continue
		for side in [-1,1]:
			var boundary = r.position[axis]-RADIUS if side == -1 else r.end[axis]+RADIUS
			var t = (boundary-p[axis])/d[axis]; var other = 1-axis
			var hit_other = p[other]+t*d[other]; var normal = Vector2.ZERO; normal[axis] = side
			if t >= -EPS and t <= best.t and hit_other >= r.position[other] and hit_other <= r.end[other] and d.dot(normal) < 0:
				best = {"t":maxf(0,t),"normal":normal}
	for corner in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
		var relative = p-corner; var a = d.length_squared()
		if a < EPS: continue
		var b = 2*relative.dot(d); var disc = b*b-4*a*(relative.length_squared()-RADIUS*RADIUS)
		if disc < 0: continue
		var t = (-b-sqrt(disc))/(2*a)
		if t < -EPS or t > best.t: continue
		var hit = p+d*t
		if (hit.x < r.position.x or hit.x > r.end.x) and (hit.y < r.position.y or hit.y > r.end.y):
			var normal = (hit-corner).normalized()
			if d.dot(normal) < 0: best = {"t":maxf(0,t),"normal":normal}
	return best

static func move(region: String, p: Vector2, axes: Vector2, delta_ms: int = 50) -> Vector2:
	if axes.length() <= 0.2: return p
	var d = axes.limit_length(1.0)*SPEED*delta_ms/1000.0
	for iteration in range(4):
		if d.length_squared() < EPS*EPS: break
		var best = {"t":1.0,"normal":Vector2.ZERO}
		for c in LAYOUT.regions[region].colliders:
			var hit = sweep(p,d,rect(c))
			if hit.t < best.t: best = hit
		if best.normal == Vector2.ZERO:
			p += d; break
		p += d*maxf(0,best.t-EPS)
		d *= 1-best.t; d -= best.normal*minf(0,d.dot(best.normal))
	var region_data = LAYOUT.regions[region]
	return p.clamp(Vector2(RADIUS,RADIUS),Vector2(region_data.width-RADIUS,region_data.height-RADIUS))

static func facing(d: Vector2) -> String:
	return ("s" if d.y >= 0 else "n")+("e" if d.x >= 0 else "w")
## Baked world-slice layout revision 1. Runtime has no fixture dependency.
const LAYOUT = {
	"id": "moonlantern-shop-lane",
	"revision": 1,
	"coordinate_system": "orthographic ground plane; x right/y down; rect x/y are centers, actor x/y is foot point; visual three-quarter view does not change collision coordinates",
	"regions": {
		"shop": {
			"width": 1280,
			"height": 768,
			"spawn": {
				"x": 220,
				"y": 380,
				"facing": "se"
			},
			"colliders": [
				{
					"id": "shop-n",
					"shape": "rect",
					"x": 640,
					"y": 12,
					"width": 1280,
					"height": 24
				},
				{
					"id": "shop-s",
					"shape": "rect",
					"x": 640,
					"y": 756,
					"width": 1280,
					"height": 24
				},
				{
					"id": "shop-w",
					"shape": "rect",
					"x": 12,
					"y": 384,
					"width": 24,
					"height": 768
				},
				{
					"id": "shop-e-n",
					"shape": "rect",
					"x": 1268,
					"y": 260,
					"width": 24,
					"height": 520
				},
				{
					"id": "shop-e-s",
					"shape": "rect",
					"x": 1268,
					"y": 704,
					"width": 24,
					"height": 128
				},
				{
					"id": "storage-body",
					"shape": "rect",
					"x": 160,
					"y": 240,
					"width": 96,
					"height": 112
				},
				{
					"id": "prep-body",
					"shape": "rect",
					"x": 340,
					"y": 280,
					"width": 128,
					"height": 80
				},
				{
					"id": "stove-body",
					"shape": "rect",
					"x": 340,
					"y": 180,
					"width": 112,
					"height": 80
				},
				{
					"id": "pass-body",
					"shape": "rect",
					"x": 590,
					"y": 280,
					"width": 144,
					"height": 64
				},
				{
					"id": "recipe-body",
					"shape": "rect",
					"x": 430,
					"y": 430,
					"width": 40,
					"height": 32
				},
				{
					"id": "menu-body",
					"shape": "rect",
					"x": 710,
					"y": 150,
					"width": 64,
					"height": 40
				},
				{
					"id": "ledger-body",
					"shape": "rect",
					"x": 580,
					"y": 560,
					"width": 60,
					"height": 48
				},
				{
					"id": "table-1",
					"shape": "rect",
					"x": 870,
					"y": 280,
					"width": 96,
					"height": 64
				},
				{
					"id": "table-2",
					"shape": "rect",
					"x": 1060,
					"y": 280,
					"width": 96,
					"height": 64
				},
				{
					"id": "table-3",
					"shape": "rect",
					"x": 870,
					"y": 480,
					"width": 96,
					"height": 64
				},
				{
					"id": "table-4",
					"shape": "rect",
					"x": 1060,
					"y": 480,
					"width": 96,
					"height": 64
				}
			]
		},
		"lane": {
			"width": 1536,
			"height": 512,
			"spawn": {
				"x": 96,
				"y": 256,
				"facing": "se"
			},
			"colliders": [
				{
					"id": "lane-n",
					"shape": "rect",
					"x": 768,
					"y": 12,
					"width": 1536,
					"height": 24
				},
				{
					"id": "lane-s",
					"shape": "rect",
					"x": 768,
					"y": 500,
					"width": 1536,
					"height": 24
				},
				{
					"id": "lane-w",
					"shape": "rect",
					"x": 12,
					"y": 256,
					"width": 24,
					"height": 512
				},
				{
					"id": "lane-e",
					"shape": "rect",
					"x": 1524,
					"y": 256,
					"width": 24,
					"height": 512
				},
				{
					"id": "vendor-body",
					"shape": "rect",
					"x": 400,
					"y": 160,
					"width": 160,
					"height": 80
				},
				{
					"id": "lane-bench",
					"shape": "rect",
					"x": 800,
					"y": 340,
					"width": 192,
					"height": 48
				}
			]
		}
	},
	"objects": [
		{
			"id": "pantry",
			"region_id": "shop",
			"kind": "storage",
			"anchor": {
				"x": 160,
				"y": 316
			},
			"actions": [
				"take",
				"put"
			],
			"collider_id": "storage-body"
		},
		{
			"id": "prep",
			"region_id": "shop",
			"kind": "station",
			"anchor": {
				"x": 340,
				"y": 340
			},
			"actions": [
				"put",
				"cook",
				"take",
				"install",
				"uninstall"
			],
			"collider_id": "prep-body"
		},
		{
			"id": "pass",
			"region_id": "shop",
			"kind": "serving",
			"anchor": {
				"x": 590,
				"y": 332
			},
			"actions": [
				"put"
			],
			"collider_id": "pass-body"
		},
		{
			"id": "recipe-book",
			"region_id": "shop",
			"kind": "book",
			"anchor": {
				"x": 430,
				"y": 466
			},
			"actions": [
				"plan",
				"equip_weapon",
				"consume"
			],
			"collider_id": "recipe-body"
		},
		{
			"id": "menu-board",
			"region_id": "shop",
			"kind": "book",
			"anchor": {
				"x": 710,
				"y": 192
			},
			"actions": [
				"menu"
			],
			"collider_id": "menu-body"
		},
		{
			"id": "ledger",
			"region_id": "shop",
			"kind": "book",
			"anchor": {
				"x": 580,
				"y": 606
			},
			"actions": [
				"settle",
				"upgrade",
				"next_day"
			],
			"collider_id": "ledger-body"
		},
		{
			"id": "door-bell",
			"region_id": "shop",
			"kind": "bell",
			"anchor": {
				"x": 1120,
				"y": 580
			},
			"actions": [
				"open_shop",
				"start_wave"
			]
		},
		{
			"id": "shop-exit",
			"region_id": "shop",
			"kind": "portal",
			"anchor": {
				"x": 1224,
				"y": 580
			},
			"actions": [
				"enter"
			]
		},
		{
			"id": "lane-home",
			"region_id": "lane",
			"kind": "portal",
			"anchor": {
				"x": 80,
				"y": 256
			},
			"actions": [
				"enter"
			]
		},
		{
			"id": "vendor",
			"region_id": "lane",
			"kind": "book",
			"anchor": {
				"x": 400,
				"y": 224
			},
			"actions": [
				"buy",
				"recycle",
				"recover"
			],
			"collider_id": "vendor-body"
		},
		{
			"id": "garden-gate",
			"region_id": "lane",
			"kind": "portal",
			"anchor": {
				"x": 1440,
				"y": 256
			},
			"actions": [
				"enter"
			]
		},
		{
			"id": "seat-1",
			"region_id": "shop",
			"kind": "customer_anchor",
			"anchor": {
				"x": 870,
				"y": 338
			},
			"actions": [
				"serve"
			]
		},
		{
			"id": "seat-2",
			"region_id": "shop",
			"kind": "customer_anchor",
			"anchor": {
				"x": 1060,
				"y": 338
			},
			"actions": [
				"serve"
			]
		},
		{
			"id": "seat-3",
			"region_id": "shop",
			"kind": "customer_anchor",
			"anchor": {
				"x": 870,
				"y": 538
			},
			"actions": [
				"serve"
			]
		},
		{
			"id": "seat-4",
			"region_id": "shop",
			"kind": "customer_anchor",
			"anchor": {
				"x": 1060,
				"y": 538
			},
			"actions": [
				"serve"
			]
		}
	],
	"portals": [
		{
			"id": "shop-exit",
			"to_region": "lane",
			"arrival": {
				"x": 144,
				"y": 256,
				"facing": "se"
			}
		},
		{
			"id": "lane-home",
			"to_region": "shop",
			"arrival": {
				"x": 1192,
				"y": 580,
				"facing": "sw"
			}
		},
		{
			"id": "garden-gate",
			"to_region": "expedition",
			"return": {
				"region_id": "lane",
				"x": 1384,
				"y": 256,
				"facing": "sw"
			}
		}
	],
	"customer_paths": {
		"entrance": {
			"x": 1192,
			"y": 580
		},
		"corridor_x": 1160,
		"seat_ids": [
			"seat-1",
			"seat-2",
			"seat-3",
			"seat-4"
		],
		"rule": "entrance → (1160, seat.y) → seat.anchor, reverse on leaving; NPCs do not block player or one another; visible path uses actual customer state, not decorative sales text."
	}
}
