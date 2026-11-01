class_name EventLog
extends RefCounted
## A campaign's append-only event log (backlog/docs/doc-1 - Event-format.md):
## `<campaign>/events.jsonl`, one JSON event per line, never rewritten. Mistakes are
## undone by a new event with `undoes`. Keeps the world clock (in-world day and minute,
## session number), which every new event is stamped with.

signal appended(event: Dictionary)

## Default for append()'s at_day / at_time: use the world clock.
const CLOCK := -999999999

var path := ""
var events: Array[Dictionary] = []  ## in id order
var day := 0  ## world clock: in-world day number
var time := -1  ## minutes since in-world midnight, -1 = unknown
var session := 0  ## 0 = prep between sessions

var _next_id := 1
var _undone := {}  ## id -> id of the event that undid it


## Opens (or creates) the log at `file` and loads it. Bad lines are skipped with a
## warning, so one damaged line never loses the rest of the campaign.
static func open(file: String) -> EventLog:
	var elog := EventLog.new()
	elog.path = file
	elog._load()
	return elog


func _load() -> void:
	events.clear()
	_undone.clear()
	_next_id = 1
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error("Can't create event log %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	var n := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		n += 1
		if line.strip_edges() == "":
			continue
		var json := JSON.new()
		var e: Variant = json.data if json.parse(line) == OK else null
		if not e is Dictionary or not e.has("id") or not e.has("type"):
			push_warning("%s line %d: not an event, skipped" % [path, n])
			continue
		_add(_normalize(e))
	# The clock continues where the log stopped.
	for e in events:
		_advance_clock(e)


## JSON numbers come back as floats: make the integer fields ints again.
static func _normalize(e: Dictionary) -> Dictionary:
	for k in ["id", "day", "time", "session", "undoes"]:
		if e.has(k) and e[k] != null:
			e[k] = int(e[k])
	if not e.get("data") is Dictionary:
		e["data"] = {}
	return e


func _add(e: Dictionary) -> void:
	events.append(e)
	_next_id = maxi(_next_id, int(e.id) + 1)
	if e.has("undoes"):
		_undone[int(e.undoes)] = int(e.id)


func _advance_clock(e: Dictionary) -> void:
	if e.type == "time.advanced" or Replay.later(e.day, e.time, day, time):
		day = e.day
		time = e.time
	if e.type == "session.started":
		session = e.session


## Appends an event stamped with the clock (or `at_day` / `at_time` if given) and the
## real time, writes it to disk at once, and returns it.
func append(type: String, entity: String, data := {}, by := "dm", undoes := -1,
		at_day := CLOCK, at_time := CLOCK) -> Dictionary:
	var e := {
		"id": _next_id,
		"type": type,
		"entity": entity,
		"day": day if at_day == CLOCK else at_day,
		"time": time if at_time == CLOCK else at_time,
		"real": Time.get_datetime_string_from_system(true) + "Z",
		"session": session,
		"by": by,
		"data": data,
	}
	if undoes >= 0:
		e["undoes"] = undoes
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		push_error("Can't write event log %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	f.seek_end()
	f.store_line(JSON.stringify(e))
	f.close()
	_add(e)
	_advance_clock(e)
	appended.emit(e)
	return e


# --- Convenience writers for the MVP event types -------------------------------------

func move_token(entity: String, map: String, from: Vector2i, to: Vector2i, by := "dm", group := "") -> Dictionary:
	var data := {"map": map, "from": [from.x, from.y], "to": [to.x, to.y]}
	if group != "":
		data["group"] = group
	return append("token.moved", entity, data, by)


func place_token(entity: String, map: String, at: Vector2i, by := "dm") -> Dictionary:
	return append("token.placed", entity, {"map": map, "at": [at.x, at.y]}, by)


func change_hp(entity: String, delta: int, hp_after: int, reason := "", by := "dm") -> Dictionary:
	return append("hp.changed", entity, {"delta": delta, "hp": hp_after, "reason": reason}, by)


func change_sheet(entity: String, field_path: String, from: Variant, to: Variant, reason := "", by := "dm") -> Dictionary:
	return append("sheet.changed", entity, {"path": field_path, "from": from, "to": to, "reason": reason}, by)


func gain_item(entity: String, item: String, qty := 1, from := "", by := "dm") -> Dictionary:
	var data := {"item": item, "qty": qty}
	if from != "":
		data["from"] = from
	return append("item.gained", entity, data, by)


func lose_item(entity: String, item: String, qty := 1, to := "", by := "dm") -> Dictionary:
	var data := {"item": item, "qty": qty}
	if to != "":
		data["to"] = to
	return append("item.lost", entity, data, by)


## Who may see a <reveal> passage of an entity's text (reveal-visibility.md).
func change_reveal(entity: String, reveal: String, field := "description", add: Array = [], remove: Array = [], by := "dm") -> Dictionary:
	return append("reveal.changed", entity, {"reveal": reveal, "field": field, "add": add, "remove": remove}, by)


## Moves the world clock (an event, so it can be rewound too).
func advance_time(to_day: int, to_time: int, reason := "", by := "dm") -> Dictionary:
	return append("time.advanced", "", {"from_day": day, "from_time": time, "reason": reason}, by, -1, to_day, to_time)


func start_session(number: int) -> Dictionary:
	session = number
	return append("session.started", "")


func end_session() -> Dictionary:
	return append("session.ended", "")


## Cancels an earlier event (it stays in the file, replay skips it).
func undo(id: int, by := "dm") -> Dictionary:
	var target := get_event(id)
	if target.is_empty() or is_undone(id):
		return {}
	return append(target.type, target.entity, {}, by, id, target.day, target.time)


# --- Reading -------------------------------------------------------------------------

func get_event(id: int) -> Dictionary:
	var i := id - 1  # ids are sequential from 1; fall back to a search otherwise
	if i >= 0 and i < events.size() and events[i].id == id:
		return events[i]
	for e in events:
		if e.id == id:
			return e
	return {}


func is_undone(id: int) -> bool:
	return _undone.has(id)


## Events that count (not undone, not undo markers), optionally only for one entity and
## only up to a moment on the timeline, in timeline order (day, time, id).
func effective(entity := "", until_day := 1 << 40, until_time := 1 << 20) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e.has("undoes") or is_undone(e.id):
			continue
		if entity != "" and e.entity != entity:
			continue
		if Replay.later(e.day, e.time, until_day, until_time):
			continue
		out.append(e)
	out.sort_custom(Replay.before)
	return out
