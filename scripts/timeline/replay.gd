class_name Replay
## Rebuilds state from events (doc-1 - Event-format.md): the state of an entity at a
## moment = its campaign copy (frontmatter) + all its effective events up to then.
## Sheets are never overwritten; this is how the VTT gets "current" values.


## Timeline order: (day, time, id). time -1 (unknown) counts as the start of the day.
static func before(a: Dictionary, b: Dictionary) -> bool:
	if a.day != b.day:
		return a.day < b.day
	if a.time != b.time:
		return a.time < b.time
	return a.id < b.id


## True if (day_a, time_a) is after (day_b, time_b).
static func later(day_a: int, time_a: int, day_b: int, time_b: int) -> bool:
	return day_a > day_b or (day_a == day_b and time_a > time_b)


## The entity's state: a deep copy of `base` with its events applied. Adds
## `inventory` {item: qty}, `levels` {class: level} and `token` {map, at} when events
## touch them. `hp` follows hp.changed (the event's `hp` after the change wins).
static func entity_state(base: Dictionary, events: Array) -> Dictionary:
	var s := base.duplicate(true)
	for e: Dictionary in events:
		apply(s, e)
	return s


## Applies one event to a state in place.
static func apply(s: Dictionary, e: Dictionary) -> void:
	var d: Dictionary = e.get("data", {})
	match str(e.type):
		"hp.changed":
			if d.has("hp"):
				s["hp"] = int(d.hp)
			else:
				s["hp"] = int(s.get("hp", 0)) + int(d.get("delta", 0))
			if d.has("temp"):
				s["temp_hp"] = int(d.temp)
			if int(s.get("hp", 0)) > 0:
				s.erase("death_saves")  # healed or back up: the saves start over
		"sheet.changed":
			set_path(s, str(d.get("path", "")), clean(d.get("to")))
		"item.gained", "item.lost":
			var item := str(d.get("item", ""))
			var qty := int(d.get("qty", 1)) * (1 if e.type == "item.gained" else -1)
			if s.get("inventory") is Array:  # a sheet's own list [{item, qty, ...}] keeps its shape
				_change_list_item(s.inventory, item, qty)
			else:
				var inv := _dict(s, "inventory")
				var left := int(inv.get(item, 0)) + qty
				if left > 0:
					inv[item] = left
				else:
					inv.erase(item)
		# --- TASK-17 ---
		"condition.applied":
			var list := _list(s, "conditions")
			if str(d.get("condition", "")) not in list:
				list.append(str(d.get("condition", "")))
		"condition.removed":
			_list(s, "conditions").erase(str(d.get("condition", "")))
		"resource.used":
			var used := _dict(s, "resources_used")
			var r := str(d.get("resource", ""))
			used[r] = int(used.get(r, 0)) + int(d.get("amount", 1))
		"resource.restored":
			var used := _dict(s, "resources_used")
			var r := str(d.get("resource", ""))
			var left := int(used.get(r, 0)) - int(d.get("amount", used.get(r, 0)))
			if left > 0:
				used[r] = left
			else:
				used.erase(r)
		"rest.taken":
			if d.has("hp"):
				s["hp"] = int(d.hp)
			if str(d.get("kind", "")) == "long":
				s.erase("resources_used")
				s.erase("death_saves")
				s.erase("temp_hp")
			else:
				for r: Variant in d.get("restores", []):
					_dict(s, "resources_used").erase(str(r))
		"death_save.rolled":
			if d.has("hp"):  # a natural 20: back up with this HP
				s["hp"] = int(d.hp)
				s.erase("death_saves")
			else:
				var saves := _dict(s, "death_saves")
				var key := "successes" if bool(d.get("success", false)) else "failures"
				saves[key] = mini(3, int(saves.get(key, 0)) + int(d.get("count", 1)))
		"currency.changed":
			var purse := _dict(s, "currency")
			var delta: Variant = d.get("delta", {})
			if delta is Dictionary:
				for coin: Variant in delta:
					purse[str(coin)] = int(purse.get(str(coin), 0)) + int(delta[coin])
		"relationship.changed":
			_dict(s, "relations")[str(d.get("with", ""))] = clean(d.get("to"))
		"quest.updated":
			if d.has("status"):
				s["quest_status"] = str(d.status)
			if d.has("step"):
				_list(s, "progress").append({"step": clean(d.step), "text": str(d.get("text", "")), "day": e.get("day", 0)})
		"party.arrived":
			s["location"] = str(d.get("place", ""))
		"level.gained":
			var levels: Dictionary = s.get_or_add("levels", {})
			levels[str(d.get("class", ""))] = int(d.get("level", 1))
		"token.placed":
			s["token"] = {"map": d.get("map", ""), "at": _cell(d.get("at"))}
		"token.moved":
			s["token"] = {"map": d.get("map", ""), "at": _cell(d.get("to"))}
		"token.removed":
			s.erase("token")


## World-wide state from events (TASK-17): {combat: {active, map, round, turn, order:
## [{entity, initiative}]}, weather: {region: {weather, temperature, wind}}, party_groups:
## [[pc refs]] ([] = one party)}. Pass all effective events (not one entity's).
static func world_state(events: Array) -> Dictionary:
	var w := {"combat": {"active": false, "map": "", "round": 0, "turn": 0, "order": []}, "weather": {}, "party_groups": []}
	for e: Dictionary in events:
		var d: Dictionary = e.get("data", {})
		var combat: Dictionary = w.combat
		match str(e.type):
			"combat.started":
				combat.merge({"active": true, "map": str(d.get("map", "")), "round": 1, "turn": 0, "order": []}, true)
				for c: Variant in d.get("order", []):
					if c is Dictionary:
						combat.order.append({"entity": str(c.get("entity", "")), "initiative": int(c.get("initiative", 0))})
				_sort_order(combat.order)
			"initiative.rolled":
				combat.order = combat.order.filter(func(c: Dictionary) -> bool: return c.entity != e.entity)
				combat.order.append({"entity": str(e.entity), "initiative": int(d.get("total", 0))})
				_sort_order(combat.order)
			"combat.turn":
				combat["round"] = int(d.get("round", combat.round))
				combat["turn"] = int(d.get("turn", combat.turn))
			"combat.ended":
				combat["active"] = false
			"weather.changed":
				w.weather[str(d.get("region", ""))] = {"weather": str(d.get("weather", "")),
					"temperature": clean(d.get("temperature")), "wind": str(d.get("wind", ""))}
			"party.split":
				w["party_groups"] = clean(d.get("groups", []))
			"party.merged":
				w["party_groups"] = []
	return w


static func _sort_order(order: Array) -> void:
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.initiative > b.initiative if a.initiative != b.initiative else a.entity < b.entity)


static func _dict(s: Dictionary, key: String) -> Dictionary:
	if not s.get(key) is Dictionary:
		s[key] = {}
	return s[key]


static func _list(s: Dictionary, key: String) -> Array:
	if not s.get(key) is Array:
		s[key] = []
	return s[key]


## item.gained / lost on an inventory list [{item, qty, ...}].
static func _change_list_item(list: Array, item: String, qty: int) -> void:
	for i in list.size():
		if list[i] is Dictionary and str(list[i].get("item", "")) == item:
			var left := int(list[i].get("qty", 1)) + qty
			if left > 0:
				list[i]["qty"] = left
			else:
				list.remove_at(i)
			return
	if qty > 0:
		list.append({"item": item, "qty": qty})


## Every token's position on a map at the end of the given events: entity -> Vector2i.
static func tokens_on(map: String, events: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in events:
		var d: Dictionary = e.get("data", {})
		if not str(e.type).begins_with("token.") or str(d.get("map", "")) != map:
			continue
		if e.type == "token.removed":
			out.erase(e.entity)
		else:
			out[e.entity] = _cell(d.get("at") if e.type == "token.placed" else d.get("to"))
	return out


## Sets a dotted path (stats.str, ac, speed.walk), creating dictionaries on the way.
static func set_path(s: Dictionary, path: String, value: Variant) -> void:
	if path == "":
		return
	var keys := path.split(".")
	var node := s
	for i in keys.size() - 1:
		if not node.get(keys[i]) is Dictionary:
			node[keys[i]] = {}
		node = node[keys[i]]
	node[keys[-1]] = value


## JSON numbers load as floats: whole numbers become ints again (also inside containers).
static func clean(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 1e15:
		return int(v)
	if v is Array:
		return v.map(clean)
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = clean(v[k])
		return out
	return v


static func _cell(v: Variant) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1])) if v is Array and v.size() >= 2 else Vector2i.ZERO
