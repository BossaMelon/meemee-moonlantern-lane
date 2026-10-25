extends SceneTree
const Map = preload("res://game/expedition/rain_garden_map.gd")
var checks = 0
var failures: Array = []
func expect(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize():
	var circle = [{"id":"thin-circle","shape":"circle","x":200.0,"y":200.0,"radius":5.0}]
	var box = [{"id":"thin-rect","shape":"rect","x":200.0,"y":180.0,"width":2.0,"height":40.0}]
	for obstacles in [circle,box]:
		for radius in [0.0,4.0,12.0,17.0]:
			var hit = Map.sweep(Vector2(100,200),Vector2(300,0),radius,obstacles)
			expect(hit.hit and hit.position.x < 200,"sweep catches thin body/projectile at high speed")
			expect(Map.point_clear(hit.position,radius,obstacles),"sweep leaves actor outside collider")
			expect(not Map.sweep(Vector2(100,100),Vector2(300,0),radius,obstacles).hit,"nonintersecting sweep stays free")
	var rounded = Map.sweep(Vector2(175,165),Vector2(10,0),12.0,box)
	expect(not rounded.hit,"rectangle rounded corner does not use an oversized square footprint")
	expect(Map.speed_scale(Vector2(380,390)) == 0.65,"water slows walkers")
	expect(Map.speed_scale(Vector2(380,390),[{"x":380,"y":390,"radius":45,"state":"active","speed_scale":0.65}]) == 0.65,"overlapping slows take min, never multiply")
	var terrain = Map.data(); terrain.obstacles.clear()
	expect(Map.data().obstacles.size() == 6,"geometry view is an independent copy")
	var waypoints = [Vector2(80,270),Vector2(415,95),Vector2(375,395),Vector2(560,440),Vector2(805,225),Vector2(850,380)]
	for radius in [12.0,17.0]:
		for start in waypoints:
			for goal in waypoints:
				var path = Map.path(start,goal,radius)
				expect(not path.is_empty(),"both routes, connector and deep positions are mutually reachable")
				var previous = start
				for point in path:
					expect(Map.line_clear(previous,point,radius),"every computed path segment respects body footprint")
					previous = point
	for spawn in Map.SPAWNS: expect(Map.point_clear(Vector2(spawn.x,spawn.y),17),"enemy starts outside solids")
	for node in Map.RESOURCES: expect(Map.point_clear(Vector2(node.x,node.y),12),"resource can be reached")
	print("E02 geometry: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
