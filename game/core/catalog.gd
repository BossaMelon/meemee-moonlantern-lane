extends RefCounted

const ITEMS = {
	"feather": {"name":"打盹羽毛", "buy":3, "base":5, "tags":["material"]},
	"ink": {"name":"清醒墨水", "buy":1, "base":2, "tags":["material"]},
	"timber": {"name":"月木", "buy":6, "base":9, "tags":["material"]},
	"moss": {"name":"雨光苔", "buy":3, "base":5, "tags":["material"]},
	"pen": {"name":"自写笔", "buy":7, "base":12, "tags":["writing"]},
	"lamp": {"name":"暖月灯", "buy":10, "base":17, "tags":["home","light"]},
	"charm": {"name":"防潮护符", "buy":6, "base":11, "tags":["waterproof"]},
	"bell": {"name":"避雨铃", "buy":18, "base":28, "tags":["home","device"]}
}
const RECIPES = {
	"pen": {"name":"自写笔", "inputs":{"feather":1,"ink":1}, "output":"pen"},
	"lamp": {"name":"暖月灯", "inputs":{"timber":1}, "output":"lamp"},
	"charm": {"name":"防潮护符", "inputs":{"moss":1}, "output":"charm"}
}
const UPGRADES = {
	"shelf": {"name":"展开折叠货架", "cost":24, "description":"下一日可同时陈列第三种商品"},
	"supply_pass": {"name":"巷口直送证", "cost":28, "description":"下一日稳定直购已知成品，减少补货制作操作"}
}
const TIERS = {"friendly":90,"standard":100,"premium":115}

static func price(item_id: String, tier: String, activity_percent: int) -> int:
	if not ITEMS.has(item_id) or not TIERS.has(tier):
		return -1
	# Positive integer half-up rounding, event contribution capped at 25%.
	return int((int(ITEMS[item_id].base) * int(TIERS[tier]) * (100 + clampi(activity_percent,0,25)) + 5000) / 10000)
