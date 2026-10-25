extends RefCounted

const ITEMS = {
	"flour": {"name":"面粉","kind":"ingredient","buy":2,"base":0,"tags":[],"effect_id":""},
	"pumpkin": {"name":"月南瓜","kind":"ingredient","buy":3,"base":0,"tags":[],"effect_id":""},
	"cream": {"name":"奶油","kind":"ingredient","buy":2,"base":0,"tags":[],"effect_id":""},
	"ember_herb": {"name":"暖焰草","kind":"ingredient","buy":3,"base":0,"tags":[],"effect_id":""},
	"sparkcap": {"name":"星火菇","kind":"ingredient","buy":0,"base":0,"tags":[],"effect_id":""},
	"moonheart": {"name":"月心菇","kind":"ingredient","buy":0,"base":0,"tags":[],"effect_id":""},
	"stirring_cauldron": {"name":"遗留自搅坩埚","kind":"device","buy":30,"base":0,"tags":[],"effect_id":"self_stir"},
	"floating_pie": {"name":"南瓜浮空饼","kind":"dish","buy":0,"base":12,"tags":["meal","quick","portable"],"effect_id":"floating_delivery"},
	"ember_soup": {"name":"暖焰汤","kind":"dish","buy":0,"base":14,"tags":["meal","warming","heat_hold","portable"],"effect_id":"ember_aura"},
	"moon_stew": {"name":"月南瓜自搅炖锅","kind":"dish","buy":0,"base":16,"tags":["meal","hearty","warming","heat_hold","portable"],"effect_id":"self_stir"},
	"star_soup": {"name":"星火暖焰汤","kind":"dish","buy":0,"base":18,"tags":["meal","warming","heat_hold","portable","trail_light"],"effect_id":"trail_spark"},
	"comet_pie": {"name":"彗星馅饼","kind":"dish","buy":0,"base":24,"tags":["meal","quick","portable","celebration"],"effect_id":"comet_orbit"}
}
const RECIPES = {
	"floating_pie": {"name":"南瓜浮空饼","inputs":{"flour":1,"pumpkin":1},"output":"floating_pie","requires_device":""},
	"ember_soup": {"name":"暖焰汤","inputs":{"pumpkin":1,"ember_herb":1},"output":"ember_soup","requires_device":""},
	"moon_stew": {"name":"月南瓜自搅炖锅","inputs":{"pumpkin":1,"cream":1},"output":"moon_stew","requires_device":"stirring_cauldron"},
	"star_soup": {"name":"星火暖焰汤","inputs":{"pumpkin":1,"ember_herb":1,"sparkcap":1},"output":"star_soup","requires_device":""},
	"comet_pie": {"name":"彗星馅饼","inputs":{"flour":1,"pumpkin":1,"moonheart":1},"output":"comet_pie","requires_device":""}
}
const UPGRADES = {
	"supply_pass": {"name":"暖焰草供货契约","cost":20,"description":"次日起稳定采购暖焰草，开放暖焰汤选择"},
	"shelf": {"name":"扩展菜单","cost":24,"description":"次日起同时供应第三道菜，减少撤菜换菜单"},
	"field_kit": {"name":"探索套装","cost":24,"description":"累计菜品收入24后可投资；次日取得散射魔杖与推退技能"}
}
const TAGS = ["meal","quick","portable","warming","heat_hold","hearty","trail_light","celebration"]
const TIERS = {"friendly":90,"standard":100,"premium":115}

static func price(item_id: String, tier: String, activity_percent: int) -> int:
	if not ITEMS.has(item_id) or not TIERS.has(tier):
		return -1
	# Positive integer half-up rounding, event contribution capped at 25%.
	return int((int(ITEMS[item_id].base) * int(TIERS[tier]) * (100 + clampi(activity_percent,0,25)) + 5000) / 10000)
