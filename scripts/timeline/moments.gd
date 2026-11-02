class_name TimelineMoments
extends RefCounted
## The timeline bar's boxes (TASK-81): a timeline's effective events grouped into moments.
## A moment is everything that happened at one point of the world clock: a new one starts
## whenever the clock moves on (`time.advanced`, or events stamped later); in combat every
## round is a moment of its own (`combat.started`, `combat.turn` with a new round). Each has
## its in-world place `at` in seconds (day, minute; rounds that share a minute follow each
## other 6 s apart, so the bar can space them out), its maps, its entities and a short
## summary of what changed, for the hover. Map-independent: one line for all maps.
## Sessions (session.started / session.ended) are markers with their real-world time.
## Only reads events: nothing is written.

const ROUND_SECONDS := 6
## Event types that are history only: they belong to a moment but say nothing in its summary.
const QUIET := ["dice.rolled", "chat.message", "initiative.rolled", "combat.order_set", "assistant.drafted",
	"session.started", "session.ended"]

## [{index, at (s), day, time, round (0 = not in combat), maps [], entities [], events [ids],
##   first_id, last_id, session, lines [String] (the summary), combat (bool)}], in order.
var moments: Array[Dictionary] = []
## [{session, start_real, end_real ("" while running), start_at, end_at (-1 while running)}]
var sessions: Array[Dictionary] = []
var hours_per_day := 24
## ref -> shown name (e.g. from the entries); without it the ref's last part, tidied up.
var name_of := Callable()

var _in_combat := false
var _round := 0
var _events := {}  ## moment index -> its events (for summaries)


## Moments of `events` (EventLog.effective(): undone ones already left out, timeline order).
static func build(events: Array[Dictionary], calendar_hours := 24, names := Callable()) -> TimelineMoments:
	var m := TimelineMoments.new()
	m.hours_per_day = calendar_hours
	m.name_of = names
	for e in events:
		m.add(e)
	return m


## Seconds since day 0, 00:00 of an in-world (day, time); time -1 = the start of the day.
func seconds_of(day: int, time: int) -> int:
	return (day * hours_per_day * 60 + maxi(time, 0)) * 60


## Adds one event after the ones so far (live: new events come in at the end).
func add(e: Dictionary) -> void:
	var type := str(e.type)
	if type == "session.started" or type == "session.ended":
		_session_marker(e)
		return
	var clock := seconds_of(int(e.day), int(e.time))
	var last: Dictionary = moments.back() if not moments.is_empty() else {}
	var new_round := false
	if type == "combat.started":
		_in_combat = true
		_round = 1
		new_round = true
	elif type == "combat.turn" and _in_combat and int(e.data.get("round", _round)) != _round:
		_round = int(e.data.get("round", _round))
		new_round = true
	var start := last.is_empty() or new_round or type == "time.advanced" \
		or clock > int(last.clock) or bool(last.get("closed", false))
	if start:
		var at := clock if last.is_empty() or clock > int(last.at) else int(last.at) + ROUND_SECONDS
		last = {"index": moments.size(), "at": at, "clock": clock, "day": int(e.day), "time": int(e.time),
			"round": _round if _in_combat else 0, "combat": _in_combat, "maps": [], "entities": [], "events": [],
			"first_id": int(e.id), "last_id": int(e.id), "session": int(e.get("session", 0)), "lines": []}
		moments.append(last)
		_events[last.index] = []
	last.events.append(int(e.id))
	last.last_id = int(e.id)
	var map := str(e.data.get("map", ""))
	if map != "" and map not in last.maps:
		last.maps.append(map)
	var who := str(e.entity)
	if who != "" and who not in last.entities and type not in QUIET:
		last.entities.append(who)
	_events[last.index].append(e)
	if type == "combat.ended":
		_in_combat = false
		_round = 0
		last["closed"] = true  # what comes after the fight is a moment of its own
	last.lines = summary(_events[last.index])


## The moment `id` belongs to (-1 if none).
func moment_of_event(id: int) -> int:
	for m in moments:
		if id >= int(m.first_id) and id <= int(m.last_id) and id in m.events:
			return int(m.index)
	return -1


## The last moment at or before `at` seconds (-1 before the first).
func moment_at(at: int) -> int:
	var found := -1
	for m in moments:
		if int(m.at) > at:
			break
		found = int(m.index)
	return found


func _session_marker(e: Dictionary) -> void:
	var at := seconds_of(int(e.day), int(e.time))
	if not moments.is_empty():
		at = maxi(at, int(moments.back().at))
	if str(e.type) == "session.started":
		sessions.append({"session": int(e.get("session", 0)), "start_real": str(e.get("real", "")), "end_real": "",
			"start_at": at, "end_at": -1})
	elif not sessions.is_empty() and str(sessions.back().end_real) == "":
		sessions.back().end_real = str(e.get("real", ""))
		sessions.back().end_at = at


# --- Summaries ------------------------------------------------------------------------

## What changed in a list of events, as short lines: world things first ("8 hours pass (long
## rest)", "Combat starts, round 1"), then one line per entity ("Borin: moves 6 squares,
## takes 7 damage, +1 Potion of Healing").
func summary(events: Array) -> Array:
	var world: Array = []
	var per: Dictionary = {}  ## entity -> {key: value} sums, in first-seen order of keys
	var order: Array = []
	for e: Dictionary in events:
		var type := str(e.type)
		var d: Dictionary = e.data
		var who := str(e.entity)
		match type:
			"time.advanced":
				world.append(_time_text(e))
				continue
			"combat.started":
				world.append("Combat starts")
				continue
			"combat.turn":
				if int(d.get("turn", 0)) == 0:
					world.append("Round %d" % int(d.get("round", 1)))
				continue
			"combat.ended":
				world.append("Combat ends")
				continue
			"door.toggled":
				world.append("A door %s" % ("opens" if d.get("open", true) else "closes"))
				continue
		if type in QUIET or who == "":
			continue
		if not per.has(who):
			per[who] = {}
			order.append(who)
		var s: Dictionary = per[who]
		match type:
			"token.moved":
				s["moved"] = int(s.get("moved", 0)) + _squares(d)
			"token.placed":
				s["placed"] = true
			"token.removed":
				s["removed"] = true
			"hp.changed":
				s["hp"] = int(s.get("hp", 0)) + int(d.get("delta", 0))
				s["hp_after"] = int(d.get("hp", 1))
			"condition.applied":
				_list_add(s, "conditions", "+" + str(d.get("condition", "?")))
			"condition.removed":
				_list_add(s, "conditions", "−" + str(d.get("condition", "?")))
			"item.gained":
				_list_add(s, "items", "+%s %s" % [_qty(d), _short(str(d.get("item", "")))])
			"item.lost":
				_list_add(s, "items", "−%s %s" % [_qty(d), _short(str(d.get("item", "")))])
			"resource.used":
				_list_add(s, "used", _short(str(d.get("resource", "")).replace("spell_slots.", "spell slot ")))
			"level.gained":
				_list_add(s, "other", "reaches level %d" % int(d.get("level", 0)))
			"rest.taken":
				_list_add(s, "other", "%s rest" % str(d.get("kind", "")))
			"death_save.rolled":
				_list_add(s, "other", "death save %s" % ("✓" if d.get("success", false) else "✗"))
			"xp.awarded":
				_list_add(s, "other", "+%d XP" % int(d.get("xp", d.get("amount", 0))))
			"sheet.changed":
				_list_add(s, "other", "%s → %s" % [str(d.get("path", "")), str(d.get("to", ""))])
			_:
				_list_add(s, "other", type.replace(".", " "))
	var lines: Array = world.duplicate()
	for who: String in order:
		var s: Dictionary = per[who]
		var parts: PackedStringArray = []
		if s.get("placed", false):
			parts.append("appears")
		if int(s.get("moved", 0)) > 0:
			parts.append("moves %d square%s" % [s.moved, "" if s.moved == 1 else "s"])
		if s.has("hp"):
			var hp := int(s.hp)
			if hp < 0:
				parts.append("takes %d damage" % -hp)
			elif hp > 0:
				parts.append("heals %d" % hp)
			if int(s.get("hp_after", 1)) <= 0:
				parts.append("drops to 0 HP")
		for key in ["conditions", "items", "used", "other"]:
			for t: String in s.get(key, []):
				parts.append(("uses " + t) if key == "used" else t)
		if s.get("removed", false):
			parts.append("leaves the map")
		if not parts.is_empty():
			lines.append("%s: %s" % [display_name(who), ", ".join(parts)])
	return lines


func display_name(ref: String) -> String:
	if name_of.is_valid():
		var n: Variant = name_of.call(ref)
		if n != null and str(n) != "" and str(n) != ref and str(n) != ref.get_file():  # not just the id again
			return str(n)
	return _short(ref)


func _time_text(e: Dictionary) -> String:
	var d: Dictionary = e.data
	var from := seconds_of(int(d.get("from_day", e.day)), int(d.get("from_time", e.time)))
	var minutes := (seconds_of(int(e.day), int(e.time)) - from) / 60
	var text := "Time passes"
	if minutes >= hours_per_day * 60:
		var days := minutes / (hours_per_day * 60)
		text = "%d day%s pass%s" % [days, "" if days == 1 else "s", "es" if days == 1 else ""]
	elif minutes >= 60:
		var h := minutes / 60
		text = "%d hour%s pass%s" % [h, "" if h == 1 else "s", "es" if h == 1 else ""]
	elif minutes > 0:
		text = "%d minute%s pass%s" % [minutes, "" if minutes == 1 else "s", "es" if minutes == 1 else ""]
	var why := str(d.get("reason", ""))
	return text + (" (%s)" % why if why != "" else "")


static func _squares(d: Dictionary) -> int:
	if d.has("cost") and int(d.cost) >= 0:
		return int(d.cost)
	var a: Array = d.get("from", [0, 0])
	var b: Array = d.get("to", [0, 0])
	return maxi(absi(int(b[0]) - int(a[0])), absi(int(b[1]) - int(a[1])))


static func _qty(d: Dictionary) -> String:
	return str(int(d.get("qty", 1)))


static func _list_add(s: Dictionary, key: String, text: String) -> void:
	if not s.has(key):
		s[key] = []
	s[key].append(text)


## "core:5e-core-rules/items/potion-of-healing" -> "Potion of healing"
static func _short(ref: String) -> String:
	var last := ref.get_slice(":", ref.get_slice_count(":") - 1).get_file()
	last = last.replace("-", " ").replace("_", " ").strip_edges()
	return last.capitalize() if last == last.to_lower() and " " not in last else (last.left(1).to_upper() + last.substr(1))
