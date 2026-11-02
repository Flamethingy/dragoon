class_name TimelineMoments
extends RefCounted
## The timeline bar's boxes (TASK-81): a timeline's effective events grouped into moments.
## A moment is everything that happened at one point of the world clock: a new one starts
## when something happens after the clock moved on (Nico 2026-11-02: passing time alone makes
## no box; it waits, with chat, session marks and hidden rolls, for the next story event (a
## move, a roll, an item used ...), and several steps of time are one line then); in combat
## every round is a moment of its own
## (`combat.started`, `combat.turn` with a new round). Each has
## its in-world place `at` in seconds (day, minute; rounds that share a minute follow each
## other 6 s apart, so the bar can space them out), its maps, its entities and a short
## summary of what changed, for the hover. Map-independent: one line for all maps.
## Sessions (session.started / session.ended) are markers with their real-world time.
## Only reads events: nothing is written.

const ROUND_SECONDS := 6
## Event types that are history only: they belong to a moment but say nothing in its summary.
## Not a story event: makes no box of its own after time passed (hidden rolls neither).
const WAITS := ["chat.message", "assistant.drafted", "session.started", "session.ended", "timeline.rewound"]
const QUIET := ["dice.rolled", "chat.message", "initiative.rolled", "combat.order_set", "assistant.drafted",
	"session.started", "session.ended", "timeline.rewound"]

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
var _waiting: Array[Dictionary] = []  ## time passing (and quiet events) waiting for something that matters
var _stale := {}  ## moment index -> true: its summary is to be made again (finish)
var _names := {}  ## ref -> shown name (name_of can be slow)


## Moments of `events` (EventLog.effective(): undone ones already left out, timeline order).
static func build(events: Array[Dictionary], calendar_hours := 24, names := Callable()) -> TimelineMoments:
	var m := TimelineMoments.new()
	m.hours_per_day = calendar_hours
	m.name_of = names
	for e in events:
		m.add(e)
	m.finish()
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
	var moves_on := type == "time.advanced" or (not last.is_empty() and clock > int(last.clock))
	var waits := type == "time.advanced" or type in WAITS \
		or (type == "dice.rolled" and bool((e.get("data", {}) as Dictionary).get("hidden", false)))
	if (moves_on or not _waiting.is_empty()) and waits:
		_waiting.append(e)  # no box for this alone: it waits for something that matters
		return
	var new_round := false
	if type == "combat.started":
		_in_combat = true
		_round = 1
		new_round = true
	elif type == "combat.turn" and _in_combat and int(e.data.get("round", _round)) != _round:
		_round = int(e.data.get("round", _round))
		new_round = true
	if not _waiting.is_empty():  # something happens after time passed: now it gets its box
		var held := _waiting.duplicate()
		_waiting.clear()
		_start(held[0], last)
		for w: Dictionary in held:
			_put(w, moments.back())
		last = moments.back()
		new_round = false  # a fight starting then: the same box
	var start := last.is_empty() or new_round or clock > int(last.clock) or bool(last.get("closed", false))
	if start:
		_start(e, last)
		last = moments.back()
	_put(e, last)
	if type == "combat.ended":
		_in_combat = false
		_round = 0
		last["closed"] = true  # what comes after the fight is a moment of its own


## A new moment, starting with event `e` (its time; rounds sharing a minute go 6 s apart).
func _start(e: Dictionary, last: Dictionary) -> void:
	var clock := seconds_of(int(e.day), int(e.time))
	var at := clock if last.is_empty() or clock > int(last.at) else int(last.at) + ROUND_SECONDS
	var m := {"index": moments.size(), "at": at, "clock": clock, "day": int(e.day), "time": int(e.time),
		"round": _round if _in_combat else 0, "combat": _in_combat, "maps": [], "entities": [], "events": [],
		"first_id": int(e.id), "last_id": int(e.id), "session": int(e.get("session", 0)), "lines": []}
	moments.append(m)
	_events[m.index] = []


## Puts event `e` into moment `last`.
func _put(e: Dictionary, last: Dictionary) -> void:
	var type := str(e.type)
	var clock := seconds_of(int(e.day), int(e.time))
	if clock > int(last.clock):  # held time passing: the box is where things happen
		last.clock = clock
		last.at = maxi(int(last.at), clock)
		last.day = int(e.day)
		last.time = int(e.time)
	last.events.append(int(e.id))
	last.last_id = int(e.id)
	if e.has("after"):
		last["edited"] = true  # the DM changed this moment afterwards (TASK-85)
	var map := str(e.data.get("map", ""))
	if map != "" and map not in last.maps:
		last.maps.append(map)
	var who := str(e.entity)
	if who != "" and who not in last.entities and type not in QUIET:
		last.entities.append(who)
	_events[last.index].append(e)
	_stale[last.index] = true  # summed up once in finish(): a big moment (a long prep) stays fast


## Makes the summaries of the moments that changed since the last time.
func finish() -> void:
	for i: int in _stale:
		moments[i].lines = summary(_events[i])
	_stale.clear()


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
	var times := events.filter(func(e: Dictionary) -> bool: return str(e.type) == "time.advanced")
	if not times.is_empty():
		world.append(_time_text(times[0], times.back(), times))
	for e: Dictionary in events:
		var type := str(e.type)
		var d: Dictionary = e.data
		var who := str(e.entity)
		match type:
			"time.advanced":
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
			"dice.rolled":
				var label := str(d.get("roll", d.get("formula", ""))).strip_edges()
				if who != "" and label != "" and not bool(d.get("hidden", false)) and not d.has("text"):
					if not per.has(who):
						per[who] = {}
						order.append(who)
					_list_add(per[who], "other", "rolls " + (label if label.length() <= 32 else label.left(31) + "…"))
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
	if _names.has(ref):
		return _names[ref]
	var out := _short(ref)
	if name_of.is_valid():
		var n: Variant = name_of.call(ref)
		if n != null and str(n) != "" and str(n) != ref and str(n) != ref.get_file():  # not just the id again
			out = str(n)
	_names[ref] = out
	return out


## Time passing from `first`'s start to `last`'s end, with the reasons given.
func _time_text(first: Dictionary, last: Dictionary, all: Array = []) -> String:
	var d: Dictionary = first.data
	var from := seconds_of(int(d.get("from_day", first.day)), int(d.get("from_time", first.time)))
	var minutes := (seconds_of(int(last.day), int(last.time)) - from) / 60
	var text := "Time passes"
	if minutes >= hours_per_day * 60:
		var days := minutes / (hours_per_day * 60)
		text = "%d day%s pass%s" % [days, "" if days == 1 else "s", "es" if days == 1 else ""]
	elif minutes >= 60:
		var h := minutes / 60
		text = "%d hour%s pass%s" % [h, "" if h == 1 else "s", "es" if h == 1 else ""]
	elif minutes > 0:
		text = "%d minute%s pass%s" % [minutes, "" if minutes == 1 else "s", "es" if minutes == 1 else ""]
	var whys: PackedStringArray = []
	for e: Dictionary in (all if not all.is_empty() else [first]):
		var why := str(e.data.get("reason", ""))
		if why != "" and why not in whys:
			whys.append(why)
	return text + (" (%s)" % ", ".join(whys) if not whys.is_empty() else "")


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
