class_name EventLog
extends RefCounted
## A timeline's event log (backlog/docs/doc-1 - Event-format.md, timelines.md):
## `<timeline>/events.jsonl`, one JSON event per line, only appended to. Mistakes are
## undone by a new event with `undoes`. The one exception (TASK-88, Nico 2026-11-04): the DM
## sets the time back (set_back): everything after that moment is deleted from the file. Keeps the world clock (in-world day and minute,
## session number), which every new event is stamped with.
## A forked timeline starts with its parent's events up to the fork (`inherited`, read-only,
## never written to its file); its own ids continue after them. Several EventLog objects on
## one file stay in step: append() reloads first if the file grew behind its back.

signal appended(event: Dictionary)
signal rewritten  ## TASK-88: events were deleted (set_back): rebuild everything from the log

## Default for append()'s at_day / at_time: use the world clock.
const CLOCK := -999999999

var path := ""
var events: Array[Dictionary] = []  ## in id order
var day := 0  ## world clock: in-world day number
var time := -1  ## minutes since in-world midnight, -1 = unknown
var session := 0  ## 0 = prep between sessions

var inherited: Array[Dictionary] = []  ## the parent timeline's events up to the fork
var _next_id := 1
var _undone := {}  ## id -> id of the event that undid it
var _file_len := 0
## TASK-85, the DM acts in the past: while set, new events go right after this chain's last
## event (`after`: the chain, the event's day and time) instead of at the clock.
var insert_after: Array = []
## Which appends may go into the past while inserting (the host: only the DM's own actions,
## not the players' at now). Not set: all.
var insert_filter := Callable()
var _insert_day := 0
var _insert_time := -1
var revision := 0  ## TASK-88: counts set-backs (caches compare it)


## Opens (or creates) the log at `file` and loads it. Bad lines are skipped with a
## warning, so one damaged line never loses the rest of the campaign.
static func open(file: String, from_parent: Array[Dictionary] = []) -> EventLog:
	var elog := EventLog.new()
	elog.path = file
	elog.inherited = from_parent
	elog._load()
	return elog


func _load() -> void:
	events.clear()
	_undone.clear()
	_next_id = 1
	day = 0
	time = -1
	session = 0
	for e in inherited:
		_add(e)
	_file_len = 0
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
	if events.any(func(e: Dictionary) -> bool: return e.type == LEGACY_REWOUND):
		_migrate_rewound()
		return
	# The clock continues where the log stopped.
	for e in events:
		if _counts_for_clock(e):
			_advance_clock(e)


## JSON numbers come back as floats: make the integer fields ints again.
static func _normalize(e: Dictionary) -> Dictionary:
	for k in ["id", "day", "time", "session", "undoes"]:
		if e.has(k) and e[k] != null:
			e[k] = int(e[k])
	if e.get("after") is Array:
		e["after"] = (e.after as Array).map(func(x: Variant) -> int: return int(x))
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
	var into := not insert_after.is_empty() and undoes < 0 \
		and (not insert_filter.is_valid() or bool(insert_filter.call()))
	var e := {
		"id": _next_id,
		"type": type,
		"entity": entity,
		"day": _insert_day if into else (day if at_day == CLOCK else at_day),
		"time": _insert_time if into else (time if at_time == CLOCK else at_time),
		"real": Time.get_datetime_string_from_system(true) + "Z",
		"session": session,
		"by": by,
		"data": data,
	}
	if undoes >= 0:
		e["undoes"] = undoes
	if into:
		e["after"] = insert_after.duplicate()
	if _file_size() != _file_len:  # another EventLog on this file wrote meanwhile
		_load()
		e.id = _next_id
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		push_error("Can't write event log %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	f.seek_end()
	f.store_line(JSON.stringify(e))
	_file_len = f.get_position()
	f.close()
	_add(e)
	if into:
		insert_after = (e.after as Array) + [int(e.id)]  # the next one follows this one
	else:
		_advance_clock(e)
	appended.emit(e)
	return e


## TASK-85: new events go into the past right after event `anchor_id` (its day and time).
func insert_at(anchor_id: int) -> void:
	var a := get_event(anchor_id)
	if a.is_empty():
		stop_inserting()
		return
	insert_after = (a.get("after", []) as Array) + [int(a.id)]
	_insert_day = int(a.day)
	_insert_time = int(a.time)


func stop_inserting() -> void:
	insert_after = []


## Events put into the past don't move the clock.
func _counts_for_clock(e: Dictionary) -> bool:
	return not e.has("after")


# --- Setting the time back (TASK-88) -------------------------------------------------

## What set_back(`upto`) would do: {keep: id -> true, deleted: [ids], last_kept, day, time,
## error}. `upto` = the last event of the moment to go back to (0 = before everything).
## Kept: every event up to it in timeline order, the undo markers of kept events and the
## session marks (real-world, they stay; moved back to that moment). Inherited events (a
## fork's parent's) can't be deleted: going back before the fork is an `error`.
func set_back_plan(upto: int) -> Dictionary:
	var ordered := events.duplicate()
	ordered.sort_custom(Replay.before)
	var keep := {}
	var found := upto == 0
	if upto > 0:
		for e: Dictionary in ordered:
			keep[int(e.id)] = true
			if int(e.id) == upto:
				found = true
				break
	if not found:
		return {"error": "no event %d" % upto, "keep": {}, "deleted": [], "last_kept": 0, "day": 0, "time": -1}
	for e in events:
		var id := int(e.id)
		if e.has("undoes"):  # an undo stays with what it undid (the moment showed it undone)
			if keep.has(int(e.undoes)):
				keep[id] = true
			else:
				keep.erase(id)
		elif str(e.type).begins_with("session."):
			keep[id] = true
	var deleted := []
	var last_kept := 0
	for e in events:
		if keep.has(int(e.id)):
			last_kept = maxi(last_kept, int(e.id))
		else:
			deleted.append(int(e.id))
	var anchor := get_event(upto)
	var out := {"keep": keep, "deleted": deleted, "last_kept": last_kept,
		"day": int(anchor.get("day", 0)), "time": int(anchor.get("time", -1)), "error": ""}
	for e in inherited:
		if not keep.has(int(e.id)):
			out.error = "That is before this timeline was forked off: those events belong to the parent timeline."
			break
	return out


## Sets the time back to the moment ending with event `upto` (TASK-88): every event after it
## is deleted from the file (sessions stay, moved back there), the clock goes back. Returns
## the deleted ids ([] if nothing or an error).
func set_back(upto: int) -> Array:
	refresh()
	var plan := set_back_plan(upto)
	if str(plan.error) != "" or (plan.deleted as Array).is_empty():
		return []
	var keep: Dictionary = plan.keep
	var kept: Array[Dictionary] = []
	for e in own_events():
		if not keep.has(int(e.id)):
			continue
		if str(e.type).begins_with("session.") and Replay.later(int(e.day), int(e.time), int(plan.day), int(plan.time)):
			e.day = int(plan.day)
			e.time = int(plan.time)
		kept.append(e)
	if not _rewrite(kept):
		return []
	insert_after = []
	revision += 1
	_load()
	rewritten.emit()
	return plan.deleted


## Writes `own` as the file (a temporary file first, then swapped in).
func _rewrite(own: Array[Dictionary]) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Can't write event log %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	for e in own:
		f.store_line(JSON.stringify(e))
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("Can't replace event log %s: %s" % [path, error_string(err)])
		return false
	return true


## Before TASK-88 a set-back was a `timeline.rewound` event cutting the later events off (and
## undoing it brought them back). Such a log is turned into the new form once: cut-off events
## are deleted, restored ones stay; the old file is kept as events.jsonl.bak-rewound.
const LEGACY_REWOUND := "timeline.rewound"


func _migrate_rewound() -> void:
	var gone := {}
	for e in events:
		if e.type != LEGACY_REWOUND:
			continue
		gone[int(e.id)] = true
		if e.has("undoes") or _undone.has(int(e.id)):  # a restore, or restored: its events count again
			continue
		for x: Variant in e.data.get("ids", []):
			gone[int(x)] = true
	var own: Array[Dictionary] = []
	for e in own_events():
		if not gone.has(int(e.id)):
			own.append(e)
	DirAccess.copy_absolute(path, path + ".bak-rewound")
	if _rewrite(own):
		_load()
	else:  # can't write: at least don't loop
		events = events.filter(func(e: Dictionary) -> bool: return e.type != LEGACY_REWOUND)


func _file_size() -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


## Reloads if another EventLog on the same file appended meanwhile.
func refresh() -> void:
	if _file_size() != _file_len:
		_load()


## Events written to this timeline's own file (not the inherited ones).
func own_events() -> Array[Dictionary]:
	return events.slice(inherited.size())


# --- Convenience writers for the MVP event types -------------------------------------

## `cost`: the squares the move cost (difficult ones count twice), -1 = not known (counted
## from the straight line then).
## `trail`: the squares it went along (from .. to, TASK-83: the timeline walks it again).
func move_token(entity: String, map: String, from: Vector2i, to: Vector2i, by := "dm", group := "", facing := "", cost := -1, trail: Array = []) -> Dictionary:
	var data := {"map": map, "from": [from.x, from.y], "to": [to.x, to.y]}
	if trail.size() >= 2:
		data["trail"] = trail.map(func(c: Vector2i) -> Array: return [c.x, c.y])
	if cost >= 0:
		data["cost"] = cost
	if group != "":
		data["group"] = group
	if facing != "":
		data["facing"] = facing
	return append("token.moved", entity, data, by)


## A token turns on the spot (TASK-42): facing n, ne, e ... nw.
func turn_token(entity: String, map: String, facing: String, by := "dm") -> Dictionary:
	return append("token.turned", entity, {"map": map, "facing": facing}, by)


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


## TASK-85: corrects an event: it is undone and a copy with `data` (and `corrects`: its id)
## goes in right where it was (its day and time, just after it in timeline order). The
## original stays in the file. Returns the correction ({} if it can't be corrected).
## `to_day` / `to_time` (Nico 2026-11-02): it happened at another time; the correction goes
## there instead (by timeline order at that time; the clock follows if that is later).
func correct(id: int, data: Dictionary, by := "dm", to_day := CLOCK, to_time := CLOCK) -> Dictionary:
	var target := get_event(id)
	if target.is_empty() or target.has("undoes") or is_undone(id):
		return {}
	var moved := (to_day != CLOCK and to_day != int(target.day)) or (to_time != CLOCK and to_time != int(target.time))
	var keep := [insert_after.duplicate(), _insert_day, _insert_time, insert_filter]
	undo(id, by)
	if moved:
		stop_inserting()
	else:
		insert_at(id)
	insert_filter = Callable()
	var d := data.duplicate(true)
	d["corrects"] = id
	var e := append(str(target.type), str(target.entity), d, by, -1,
		(to_day if to_day != CLOCK else int(target.day)) if moved else CLOCK,
		(to_time if to_time != CLOCK else int(target.time)) if moved else CLOCK)
	insert_after = keep[0]
	_insert_day = keep[1]
	_insert_time = keep[2]
	insert_filter = keep[3]
	return e


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


## True while a session runs (the last session.started isn't followed by session.ended).
func in_session() -> bool:
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		if e.has("undoes") or is_undone(e.id):
			continue
		if e.type == "session.started":
			return true
		if e.type == "session.ended":
			return false
	return false


## True if the event was undone.
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
