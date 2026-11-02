class_name Replay
## Rebuilds state from events (doc-1 - Event-format.md): the state of an entity at a
## moment = its entry (world or timeline) + all its effective events up to then.
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
## `inventory` {item: qty} (a sheet's own list keeps its shape), `resources_used`
## {resource: n} (spell slots: "spell_slots.<level>") and `token` {map, at} when events
## touch them; level.gained changes the class in `classes` (TASK-51). `hp` follows hp.changed (the event's `hp` after the change wins).
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
			var path := str(d.get("path", ""))
			if path == "spell_slots_used" or path.begins_with("spell_slots_used."):
				_old_slots(s, path, clean(d.get("to")))  # before TASK-51: slots were a sheet field
			else:
				set_path(s, path, clean(d.get("to")))
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
			var cond := str(d.get("condition", ""))
			var list := _list(s, "conditions")
			if cond not in list:
				list.append(cond)
			if cond == "exhaustion":  # TASK-56: its level (1-6)
				s["exhaustion"] = clampi(int(d.get("level", 1)), 1, 6)
			if d.get("duration") is Dictionary:  # optional (Phase 2 ends it)
				_dict(s, "condition_durations")[cond] = d.duration
			if cond == "concentrating":  # TASK-59: on which spell
				s["concentration"] = {"spell": str(d.get("spell", "")), "name": str(d.get("name", ""))}
		"condition.removed":
			var cond := str(d.get("condition", ""))
			_list(s, "conditions").erase(cond)
			if cond == "exhaustion":
				s.erase("exhaustion")
			if cond == "concentrating":
				s.erase("concentration")
			if s.get("condition_durations") is Dictionary:
				(s.condition_durations as Dictionary).erase(cond)
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
		"level.gained":  # the class in classes[] (TASK-51: levels only live there)
			var cls := str(d.get("class", ""))
			var classes := _list(s, "classes")
			var found := false
			for c: Variant in classes:
				if c is Dictionary and _same_class(str(c.get("class", "")), cls):
					c["level"] = int(d.get("level", 1))
					found = true
					break
			if not found and cls != "":
				classes.append({"class": cls if "/" in cls else "classes/" + cls, "level": int(d.get("level", 1))})
		"token.placed":
			s["token"] = {"map": d.get("map", ""), "at": _cell(d.get("at"))}
		"token.moved":
			s["token"] = {"map": d.get("map", ""), "at": _cell(d.get("to"))}
		"token.removed":
			s.erase("token")


## World-wide state from events (TASK-17): {combat: {active, map, round, turn, order:
## [{entity, initiative, rolled, dex, (group:) name, members}], current, surprised, manual}, weather: {region: {weather, temperature, wind}}, party_groups:
## [[pc refs]] ([] = one party)}. Pass all effective events (not one entity's).
static func world_state(events: Array) -> Dictionary:
	var w := {"combat": {"active": false, "map": "", "round": 0, "turn": 0, "order": [], "current": "", "surprised": [], "manual": false},
		"weather": {}, "party_groups": []}
	for e: Dictionary in events:
		var d: Dictionary = e.get("data", {})
		var combat: Dictionary = w.combat
		match str(e.type):
			"combat.started":
				combat.merge({"active": true, "map": str(d.get("map", "")), "round": 1, "turn": 0, "order": [], "current": "",
					"surprised": (clean(d.get("surprised", [])) as Array) if d.get("surprised") is Array else [], "manual": false}, true)
				for c: Variant in d.get("order", []):
					if c is Dictionary:
						combat.order.append({"entity": str(c.get("entity", "")), "initiative": int(c.get("initiative", 0)),
							"rolled": bool(c.get("rolled", int(c.get("initiative", 0)) != 0)), "dex": int(c.get("dex", 0))})
				_sort_order(combat.order)
			"initiative.rolled":  # TASK-58: a creature's or a group's roll; a late joiner is sorted in
				var old: Array = combat.order.filter(func(c: Dictionary) -> bool: return c.entity == e.entity)
				combat.order = combat.order.filter(func(c: Dictionary) -> bool: return c.entity != e.entity)
				var entry := {"entity": str(e.entity), "initiative": int(d.get("total", 0)), "rolled": true, "dex": int(d.get("dex", 0))}
				if not old.is_empty() and (old[0] as Dictionary).has("members"):
					entry["members"] = old[0].members
					entry["name"] = old[0].get("name", "")
				_place(combat, entry)
			"combat.surprise":
				var list: Array = combat.surprised
				list.erase(str(e.entity))
				if bool(d.get("surprised", true)):
					list.append(str(e.entity))
			"combat.joined":  # mid-combat: in the order, waiting for its roll
				if not (combat.order as Array).any(func(c: Dictionary) -> bool: return c.entity == e.entity):
					combat.order.append({"entity": str(e.entity), "initiative": 0, "rolled": false, "dex": 0})
			"combat.order_set":  # the DM's order (dragged); later rolls are sorted in
				var by_id := {}
				for c: Dictionary in combat.order:
					by_id[c.entity] = c
				var out := []
				for id: Variant in d.get("order", []):
					if by_id.has(str(id)):
						out.append(by_id[str(id)])
						by_id.erase(str(id))
				for c: Dictionary in combat.order:
					if by_id.has(c.entity):
						out.append(c)
				combat["order"] = out
				combat["manual"] = true
				_fix_turn(combat)
			"combat.grouped":  # creatures share one roll and one turn
				var members: Array = (clean(d.get("members", [])) as Array) if d.get("members") is Array else []
				combat.order = combat.order.filter(func(c: Dictionary) -> bool: return c.entity not in members and c.entity != str(d.get("group", "")))
				combat.order.append({"entity": str(d.get("group", "")), "name": str(d.get("name", "")), "members": members,
					"initiative": 0, "rolled": false, "dex": 0})
				_fix_turn(combat)
			"combat.ungrouped":
				var group: Array = combat.order.filter(func(c: Dictionary) -> bool: return c.entity == str(d.get("group", "")))
				combat.order = combat.order.filter(func(c: Dictionary) -> bool: return c.entity != str(d.get("group", "")))
				if not group.is_empty():
					for m: Variant in group[0].get("members", []):
						combat.order.append({"entity": str(m), "initiative": 0, "rolled": false, "dex": 0})
				_fix_turn(combat)
			"combat.turn":
				combat["round"] = int(d.get("round", combat.round))
				combat["turn"] = int(d.get("turn", combat.turn))
				var order: Array = combat.order
				combat["current"] = str(order[combat.turn].entity) if combat.turn >= 0 and combat.turn < order.size() else ""
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


## "classes/wizard", "wizard" and "Wizard" are one class.
static func _same_class(a: String, b: String) -> bool:
	return a.get_file().to_lower() == b.get_file().to_lower()


## Old sheet.changed spell slots (`spell_slots_used.<level>` = n, or the whole dictionary)
## as resources used: "spell_slots.<level>".
static func _old_slots(s: Dictionary, path: String, to: Variant) -> void:
	var used := _dict(s, "resources_used")
	var values := {}
	if path == "spell_slots_used":
		values = to if to is Dictionary else {}
		for k: String in used.keys():
			if k.begins_with("spell_slots."):
				used.erase(k)
	else:
		values[path.get_slice(".", 1)] = to
	for level: Variant in values:
		var n := int(values[level]) if values[level] != null else 0
		if n > 0:
			used["spell_slots.%s" % level] = n
		else:
			used.erase("spell_slots.%s" % level)


## Spent spell slots of a level (resources_used "spell_slots.<level>").
static func slots_used(s: Dictionary, level: int) -> int:
	var used: Variant = s.get("resources_used")
	return int((used as Dictionary).get("spell_slots.%d" % level, 0)) if used is Dictionary else 0


## Highest initiative first; ties: higher Dex, then by name (the DM drags them if they like);
## not rolled yet at the end.
static func _sort_order(order: Array) -> void:
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _before(a, b))


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.get("rolled", true)) != bool(b.get("rolled", true)):
		return bool(a.get("rolled", true))
	if int(a.initiative) != int(b.initiative):
		return int(a.initiative) > int(b.initiative)
	if int(a.get("dex", 0)) != int(b.get("dex", 0)):
		return int(a.get("dex", 0)) > int(b.get("dex", 0))
	return str(a.entity) < str(b.entity)


## A rolled entry into the order: sorted, or (after the DM ordered it by hand) put in front of
## the first one it beats, so the DM's order stays. The current turn stays with its creature.
static func _place(combat: Dictionary, entry: Dictionary) -> void:
	var order: Array = combat.order
	if not bool(combat.get("manual", false)):
		order.append(entry)
		_sort_order(order)
	else:
		var at := order.size()
		for i in order.size():
			if _before(entry, order[i]):
				at = i
				break
		order.insert(at, entry)
	_fix_turn(combat)


static func _fix_turn(combat: Dictionary) -> void:
	var cur := str(combat.get("current", ""))
	if cur == "":
		return
	for i in (combat.order as Array).size():
		if str(combat.order[i].entity) == cur:
			combat["turn"] = i
			return
	combat["turn"] = clampi(int(combat.turn), 0, maxi((combat.order as Array).size() - 1, 0))


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


## Where every token on a map looks at the end of the given events (TASK-42): entity ->
## n, ne, e ... nw (token.turned, and token.moved with a facing).
static func facings_on(map: String, events: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in events:
		var d: Dictionary = e.get("data", {})
		if str(e.type) in ["token.turned", "token.moved"] and str(d.get("map", "")) == map and str(d.get("facing", "")) != "":
			out[e.entity] = str(d.facing)
	return out


## Every token's position on a map at the end of the given events: entity -> Vector2i.
static func tokens_on(map: String, events: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in events:
		var d: Dictionary = e.get("data", {})
		if not str(e.type).begins_with("token.") or str(d.get("map", "")) != map or e.type == "token.turned":
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
