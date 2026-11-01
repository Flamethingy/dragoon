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
		"sheet.changed":
			set_path(s, str(d.get("path", "")), clean(d.get("to")))
		"item.gained", "item.lost":
			var inv: Dictionary = s.get_or_add("inventory", {})
			var item := str(d.get("item", ""))
			var qty := int(d.get("qty", 1)) * (1 if e.type == "item.gained" else -1)
			var left := int(inv.get(item, 0)) + qty
			if left > 0:
				inv[item] = left
			else:
				inv.erase(item)
		"level.gained":
			var levels: Dictionary = s.get_or_add("levels", {})
			levels[str(d.get("class", ""))] = int(d.get("level", 1))
		"token.placed":
			s["token"] = {"map": d.get("map", ""), "at": _cell(d.get("at"))}
		"token.moved":
			s["token"] = {"map": d.get("map", ""), "at": _cell(d.get("to"))}
		"token.removed":
			s.erase("token")


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
