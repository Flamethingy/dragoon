class_name Encounters
extends RefCounted
## Saved encounters of a timeline (TASK-35, timelines.md "Maps and encounters"): named
## ranges of its events in encounters.json, `{id, name, map, start_event, end_event, session,
## day, participants[]}`. Made automatically from each `combat.started` ... `combat.ended`
## (sync); renaming and moving the range only change encounters.json, never the events.

const FILE := "encounters.json"
## Event types that make an entity a participant.
const PARTICIPATING := ["token.moved", "token.turned", "token.placed", "hp.changed", "condition.applied", "condition.removed",
	"initiative.rolled", "dice.rolled", "sheet.changed"]

var path := ""
var list: Array = []  ## the encounters, oldest first


static func open(timeline_folder: String) -> Encounters:
	var enc := Encounters.new()
	enc.path = timeline_folder.path_join(FILE)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(enc.path)) if FileAccess.file_exists(enc.path) else []
	if data is Array:
		enc.list = data.filter(func(x: Variant) -> bool: return x is Dictionary)
	return enc


func save() -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(list, " "))
	return OK


func get_encounter(id: String) -> Dictionary:
	for e: Dictionary in list:
		if str(e.id) == id:
			return e
	return {}


## Adds an encounter for every finished combat of the log that has none yet (matched by
## its start event). Returns the new ones. `timeline` names the maps (optional).
func sync(events_log: EventLog, timeline: Timeline = null) -> Array:
	var made := []
	var known := {}
	for e: Dictionary in list:
		known[int(e.start_event)] = true
	var start := {}
	for e: Dictionary in events_log.events:
		if events_log.is_undone(int(e.id)) or e.has("undoes"):
			continue
		if e.type == "combat.started":
			start = e
		elif e.type == "combat.ended" and not start.is_empty():
			if not known.has(int(start.id)):
				made.append(_make(events_log, start, e, timeline))
			start = {}
	if not made.is_empty():
		list.append_array(made)
		save()
	return made


func _make(events_log: EventLog, start: Dictionary, end: Dictionary, timeline: Timeline) -> Dictionary:
	var map := str(start.data.get("map", ""))
	var count := 1 + list.filter(func(x: Dictionary) -> bool: return str(x.get("map", "")) == map).size()
	var place := timeline.name_of(map) if timeline != null and map != "" else (map.get_file().capitalize() if map != "" else "the table")
	var enc := {"id": "enc-%d" % int(start.id), "name": "Fight at %s%s" % [place, "" if count == 1 else " (%d)" % count],
		"map": map, "start_event": int(start.id), "end_event": int(end.id),
		"session": int(start.session), "day": int(start.day), "time": int(start.time)}
	enc["participants"] = participants(events_log, enc)
	return enc


## The entities that took part: in the starting order or acting in the range.
static func participants(events_log: EventLog, enc: Dictionary) -> Array:
	var out := []
	for e: Dictionary in range_events(events_log, enc):
		if e.type == "combat.started":
			for c: Variant in e.data.get("order", []):
				if c is Dictionary and str(c.get("entity", "")) not in out:
					out.append(str(c.entity))
		elif e.type in PARTICIPATING and str(e.entity) != "" and not str(e.entity).begins_with("group:") and str(e.entity) not in out:
			out.append(str(e.entity))
	return out


## The events of an encounter's range (as stored, undone ones included).
static func range_events(events_log: EventLog, enc: Dictionary) -> Array[Dictionary]:
	var lo := int(enc.get("start_event", 0))
	var hi := int(enc.get("end_event", lo))
	var out: Array[Dictionary] = []
	for e: Dictionary in events_log.events:
		if int(e.id) >= lo and int(e.id) <= hi:
			out.append(e)
	return out


func rename(id: String, new_name: String) -> bool:
	var e := get_encounter(id)
	if e.is_empty() or new_name.strip_edges() == "":
		return false
	e["name"] = new_name.strip_edges()
	return save() == OK


## Moves the range (event ids, start ≤ end); participants follow.
func set_range(id: String, start_event: int, end_event: int, events_log: EventLog) -> bool:
	var e := get_encounter(id)
	if e.is_empty() or start_event > end_event or start_event < 1:
		return false
	e["start_event"] = start_event
	e["end_event"] = end_event
	var first := events_log.get_event(start_event)
	if not first.is_empty():
		e["session"] = int(first.session)
		e["day"] = int(first.day)
		e["time"] = int(first.time)
	e["participants"] = participants(events_log, e)
	return save() == OK


func remove(id: String) -> bool:
	var n := list.size()
	list = list.filter(func(x: Dictionary) -> bool: return str(x.id) != id)
	return list.size() != n and save() == OK


## The encounters grouped for a list: [[session, [encounters by in-world date]]], newest
## session first.
func by_session() -> Array:
	var groups := {}
	for e: Dictionary in list:
		groups.get_or_add(int(e.get("session", 0)), []).append(e)
	var keys := groups.keys()
	keys.sort()
	keys.reverse()
	var out := []
	for k: int in keys:
		var items: Array = groups[k]
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return [int(a.get("day", 0)), int(a.get("time", 0)), int(a.start_event)] < [int(b.get("day", 0)), int(b.get("time", 0)), int(b.start_event)])
		out.append([k, items])
	return out
