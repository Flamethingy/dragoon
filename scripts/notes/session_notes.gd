class_name SessionNotes
extends RefCounted
## Session notes (TASK-14, JSON since TASK-20): every note of a campaign is an entry in
## `<campaign>/notes.json` (data-layout.md):
##
##     {"id": "n3", "text": "Markdown", "real": "2026-11-01T20:15", "session": 3,
##      "day": 4211, "time": 870, "by": "ann", "about": ""}
##
## An instance shows one session: `entries` are that session's notes, oldest first.
## The VTT shows each with a heading "real date · Session N · in-world moment · writer".

const FILE := "notes.json"

var path := ""  ## notes.json ("" = only shown, never saved: player clients)
var session := 0
var calendar: WorldCalendar
var entries: Array[Dictionary] = []  ## this session's notes
## Player id -> display name for headings ("dm" shows as "DM").
var names := {}


## The notes of one session of the campaign in `campaign_folder`.
static func open(campaign_folder: String, session_number: int, world_calendar: WorldCalendar) -> SessionNotes:
	var notes := SessionNotes.new()
	notes.session = session_number
	notes.calendar = world_calendar
	notes.path = campaign_folder.path_join(FILE)
	for e in read_all(notes.path):
		if int(e.get("session", 0)) == session_number:
			notes.entries.append(e)
	return notes


## Every note in a notes.json ([] if there is none).
static func read_all(file: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(file):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if data is Array:
		for e: Variant in data:
			if e is Dictionary:
				out.append(_clean(e))
	return out


## JSON numbers come back as floats.
static func _clean(e: Dictionary) -> Dictionary:
	return {"id": str(e.get("id", "")), "text": str(e.get("text", "")), "real": str(e.get("real", "")),
		"session": int(e.get("session", 0)), "day": int(e.get("day", 0)), "time": int(e.get("time", -1)),
		"by": str(e.get("by", "")), "about": str(e.get("about", ""))}


## Adds a note and saves notes.json. `day`/`time` are the in-world moment (EventLog's
## clock), `real` defaults to now ("YYYY-MM-DDTHH:MM", local time).
func add(text: String, by: String, day: int, time := -1, real := "", about := "") -> Dictionary:
	if real == "":
		real = Time.get_datetime_string_from_system(false, false).left(16)
	var all := read_all(path) if path != "" else entries.duplicate()
	var next := 1
	for e in all:
		next = maxi(next, int(str(e.id).trim_prefix("n")) + 1)
	var entry := {"id": "n%d" % next, "text": text.strip_edges(), "real": real, "session": session,
		"day": day, "time": time, "by": by, "about": about}
	entries.append(entry)
	if path != "":
		all.append(entry)
		_save(all)
	return entry


## Writes to a temporary file first, so a crash never leaves half a notes.json.
func _save(all: Array) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		push_error("Can't write notes: %s" % path)
		return
	f.store_string(JSON.stringify(all, "  ") + "\n")
	f.close()
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(temp, path)


## "2026-11-01 20:15 · Session 3 · Fireday, 12. Seedtime 1 AF, 14:30 · Ann"
func heading(entry: Dictionary) -> String:
	var parts := PackedStringArray([str(entry.real).replace("T", " ")])
	parts.append("Prep" if int(entry.session) <= 0 else "Session %d" % int(entry.session))
	if calendar:
		parts.append(calendar.format_moment(int(entry.day), int(entry.time)))
	else:
		parts.append("Day %d" % int(entry.day))
	var by := str(entry.by)
	if by != "":
		parts.append(names.get(by, "DM" if by == "dm" else by))
	return " · ".join(parts)
