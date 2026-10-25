extends RefCounted
## P05 571b7d4 public component protocol. Read controls only; never send commands.
const WORLD_ENTRANCES={"forecast":"world_journal","service":"world_counter","menu":"world_menu","meal":"world_gear","rare":"world_storage","growth":"world_journal"}
const LABELS={"forecast":["night_forecast","wave_summary_1","wave_summary_2","wave_summary_3"],"service":["service_status","service_channels"],"menu":["temperature_summary"],"meal":["meal_state","meal_source_floating_pie","meal_source_star_soup"],"rare":["rare_stock_sparkcap","rare_stock_moonheart"],"growth":["growth_income","growth_state"]}
const BUTTONS={"forecast":[],"service":[],"menu":["inventory_details_toggle","menu_priority_apply"],"meal":["consume_pie","consume_star_soup"],"rare":["recycle_sparkcap","recycle_moonheart","rare_cook_sparkcap","rare_cook_moonheart","rare_keep"],"growth":["next_morning"]}

static func observe(host: Object, section: String, view: Dictionary, selected_item: String="") -> Dictionary:
	var result={"section":section,"world_id":WORLD_ENTRANCES.get(section,""),"labels":{},"buttons":{},"collapsed_orders":[],"errors":[]}
	if not LABELS.has(section) or not is_instance_valid(host) or not host.has_method("get_action_control"):
		result.errors.append("published control lookup and known component section required")
		return result
	var service: Dictionary=view.get("service",{})
	if not service.has_all(["orders","reservations","menu_priority","held_uids","status"]) or not view.has("night"):
		result.errors.append("real rain-night typed view required; legacy view cannot satisfy this observer")
		return result
	var labels: Array=LABELS[section].duplicate()
	var buttons: Array=BUTTONS[section].duplicate()
	if section=="service":
		var completed=false
		for order in service.orders:
			var id="service_order_"+str(order.id)
			if order.status in ["delivered","left"]:
				completed=true
				if host.get_action_control(id)==null:
					result.collapsed_orders.append(order.id)
					continue
			labels.append(id)
		if completed: buttons.append("service_history_toggle")
		for row in service.reservations: labels.append("reservation_%d"%row.item_uid)
		if view.get("phase")=="intermission":
			buttons.append("start_wave"); labels.append("next_wave_summary")
		elif host.get_action_control("start_wave")!=null: result.errors.append("start_wave exists outside true intermission")
	elif section=="menu":
		for id in service.menu_priority:
			labels.append("priority_name_"+str(id))
			buttons.append("priority_up_"+str(id)); buttons.append("priority_down_"+str(id))
		for item in view.get("items",[]):
			if not selected_item.is_empty() and item.item_id!=selected_item: continue
			if item.get("prepared_wave_id")==null: continue
			var reserved=item.location=="reserved" or service.reservations.any(func(row): return row.item_uid==item.uid)
			if reserved: labels.append("dish_uid_%d"%item.uid)
	elif section=="growth":
		for upgrade in view.get("upgrades",[]):
			if upgrade.upgrade_id in ["field_kit","shelf"]: buttons.append("upgrade_"+str(upgrade.upgrade_id))
	for id in labels:
		var control=host.get_action_control(id)
		if not control is Label or not control.is_visible_in_tree():
			result.errors.append("missing visible read-only Label: "+id)
			continue
		var metadata={}
		for key in ["order_id","item_uid","prepared_wave_id"]:
			if control.has_meta(key): metadata[key]=control.get_meta(key)
		result.labels[id]={"text":control.text,"rect":str(control.get_global_rect()),"metadata":metadata}
	for id in buttons:
		var control=host.get_action_control(id)
		if not control is Button or not control.is_visible_in_tree():
			result.errors.append("missing visible Button: "+id)
			continue
		result.buttons[id]={"text":control.text,"disabled":control.disabled,"rect":str(control.get_global_rect())}
	if section=="service":
		for order in service.orders:
			var id="service_order_"+str(order.id)
			if result.labels.has(id) and result.labels[id].metadata.get("order_id")!=order.id:
				result.errors.append("order metadata differs from actual typed view: "+id)
		for row in service.reservations:
			var id="reservation_%d"%row.item_uid
			if result.labels.has(id) and (result.labels[id].metadata.get("order_id")!=row.order_id or result.labels[id].metadata.get("item_uid")!=row.item_uid):
				result.errors.append("reservation metadata does not identify the same UID/order: "+id)
	elif section=="menu":
		for item in view.get("items",[]):
			var id="dish_uid_%d"%item.uid
			if result.labels.has(id) and (result.labels[id].metadata.get("item_uid")!=item.uid or result.labels[id].metadata.get("prepared_wave_id")!=item.get("prepared_wave_id")):
				result.errors.append("dish metadata does not preserve the actual UID/source wave: "+id)
	return result
