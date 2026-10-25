extends SceneTree
const Model = preload("res://game/expedition/expedition_model.gd")
var failures: Array = []
var checks = 0

func expect(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize():
	var s = Model.create(1,"test",1)
	expect(Model.validate(s) == "","initial state valid: "+Model.validate(s))
	var before = s.duplicate(true)
	expect(not Model.set_input(s,{"move_x":NAN}).ok and s == before,"nonfinite input rejected atomically")
	expect(not Model.set_input(s,{"skill":true}).ok and s == before,"locked skill rejected atomically")
	Model.set_input(s,{"move_x":1.0,"move_y":1.0,"aim_x":1.0,"cast":true})
	var split = s.duplicate(true)
	Model.advance(s,1000)
	for amount in [17,33,121,79,311,89,350]: Model.advance(split,amount)
	expect(s == split,"fixed-step frame partitions equal")
	expect(Model.validate(s) == "","advanced state valid: "+Model.validate(s))
	expect(Vector2(s.player.x-80.0,s.player.y-270.0).length() < 161.0,"diagonal movement normalized")
	before = s.duplicate(true)
	Model.advance(s,60000,80,true)
	expect(s == before,"pause freezes full state and remainder")
	var copy = JSON.parse_string(JSON.stringify(s))
	expect(Model.validate(copy) == "","JSON float state roundtrip valid: "+Model.validate(copy))
	Model.clear_input(s)
	Model.clear_input(copy)
	Model.set_input(s,{"aim_x":1.0,"cast":true})
	Model.set_input(copy,{"aim_x":1.0,"cast":true})
	Model.advance(s,837)
	Model.advance(copy,837)
	if s != copy: diff(s,copy,"root")
	expect(s == copy,"JSON resume equals continuous branch after reinput")
	print("E01 model: %d checks, %d failures" % [checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)

func diff(a: Variant, b: Variant, path: String):
	if a is Dictionary and b is Dictionary:
		for key in a:
			if a[key] != b.get(key): diff(a[key],b.get(key),path+"."+str(key))
	elif a is Array and b is Array and a.size() == b.size():
		for i in range(a.size()):
			if a[i] != b[i]: diff(a[i],b[i],path+"["+str(i)+"]")
	else: print(path,": ",a," vs ",b," types ",typeof(a),"/",typeof(b))
