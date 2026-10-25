extends SceneTree

const Session = preload("res://game/core/game_session.gd")
var failures: Array = []
var checks = 0

func check(value: bool, label: String):
	checks += 1
	if not value: failures.append(label)

func _initialize():
	var g = Session.new(7,"prototype-v1")
	check(g.snapshot().version == 2,"restaurant save uses v2")
	check(g.view().cash == 60,"restaurant starts with 60 coins")
	check(g.view().inventory.size() == 12,"twelve distinct restaurant SKUs")
	var devices = g.snapshot().items.filter(func(item): return item.item_id == "stirring_cauldron")
	check(devices.size() == 1 and devices[0].cost == 0,"one zero-cost inherited cauldron")
	check(g.command("recycle",{"item_id":"stirring_cauldron","quantity":1}).ok,"inherited device can be sold")
	check(g.view().cash == 78,"fixed cauldron sale is 18")
	var before = g.snapshot()
	check(not g.command("recycle",{"item_id":"stirring_cauldron","quantity":1}).ok,"cannot sell same device twice")
	check(g.snapshot() == before,"duplicate device sale atomically rejected")
	check(g.command("buy",{"item_id":"flour","quantity":2}).ok,"stable flour supply")
	check(g.command("buy",{"item_id":"pumpkin","quantity":2}).ok,"stable pumpkin supply")
	g.command("finish_shopping")
	check(g.command("craft",{"recipe_id":"floating_pie","quantity":2}).ok,"known pie batch needs no device")
	check(not g.command("craft",{"recipe_id":"moon_stew","quantity":1}).ok,"stew cannot be made without device")
	check(not g.command("display",{"item_id":"flour","quantity":1}).ok,"ingredient cannot be menu food")
	check(g.validate_snapshot(g.snapshot()).is_empty(),"new economy self-validates")
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
