class_name SessionNotes
extends RefCounted
## Session notes (TASK-14): one markdown file per session in the campaign folder,
## `<campaign>/notes/session-03.md` (`prep.md` for notes between sessions, session 0).
## Every entry carries the real date and time, the session number, the in-world moment
## and who wrote it. The file is plain markdown (readable in Obsidian); each entry starts
## with an HTML comment holding its data, so the VTT can read the entries back:
##
##     <!-- note {"real":"2026-11-01 20:15","session":3,"day":4211,"time":870,"by":"DM"} -->
##     ### 2026-11-01 20:15 · Session 3 · Fireday, 12. Seedtime 1 AF, 14:30 · DM
##
##     The party reached the old mill.

const MARKER := "<!-- note "

var path := ""
var session := 0
var calendar: WorldCalendar
var entries: Array[Dictionary] = []  ## {real, session, day, time, by, text}


## The notes of one session (the file is created with the first entry).
static func open(campaign_folder: String, session_number: int, world_calendar: WorldCalendar) -> SessionNotes:
	var notes := SessionNotes.new()
	notes.session = session_number
	notes.calendar = world_calendar
	notes.path = path_for(campaign_folder, session_number)
	if FileAccess.file_exists(notes.path):
		notes.entries = parse(FileAccess.get_file_as_string(notes.path))
	return notes


static func path_for(campaign_folder: String, session_number: int) -> String:
	var file := "prep.md" if session_number <= 0 else "session-%02d.md" % session_number
	return campaign_folder.path_join("notes").path_join(file)


## Adds an entry and appends it to the file. `day`/`time` are the in-world moment
## (EventLog's clock), `real` defaults to now ("YYYY-MM-DD HH:MM").
func add(text: String, by: String, day: int, time := -1, real := "") -> Dictionary:
	if real == "":
		real = Time.get_datetime_string_from_system(false, true).left(16)
	var entry := {"real": real, "session": session, "day": day, "time": time, "by": by,
		"text": text.strip_edges()}
	entries.append(entry)
	var is_new := not FileAccess.file_exists(path)
	if is_new:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.READ_WRITE if not is_new else FileAccess.WRITE)
	if f == null:
		push_error("Can't write notes: %s" % path)
		return entry
	if is_new:
		f.store_string(_file_header())
	else:
		f.seek_end()
	f.store_string(to_markdown(entry))
	f.close()
	return entry


func _file_header() -> String:
	var title := "Between sessions" if session <= 0 else "Session %d" % session
	return "---\nsession: %d\nstarted: %s\n---\n# %s\n" % [
		session, Time.get_date_string_from_system(), title]


## One entry as markdown (marker line, heading, text).
func to_markdown(entry: Dictionary) -> String:
	var data := {"real": entry.real, "session": entry.session, "day": entry.day,
		"time": entry.time, "by": entry.by}
	return "\n%s%s -->\n### %s\n\n%s\n" % [MARKER, JSON.stringify(data), heading(entry), entry.text]


## "2026-11-01 20:15 · Session 3 · Fireday, 12. Seedtime 1 AF, 14:30 · DM"
func heading(entry: Dictionary) -> String:
	var parts := PackedStringArray([str(entry.real)])
	parts.append("Prep" if int(entry.session) <= 0 else "Session %d" % int(entry.session))
	if calendar:
		parts.append(calendar.format_moment(int(entry.day), int(entry.time)))
	else:
		parts.append("Day %d" % int(entry.day))
	if str(entry.by) != "":
		parts.append(str(entry.by))
	return " · ".join(parts)


## Reads the entries back from a notes file's text. Text outside entries (e.g. what
## someone wrote in the file by hand above the first one) is ignored.
static func parse(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var current: Dictionary = {}
	var body := PackedStringArray()
	var json := JSON.new()
	for line in text.replace("\r\n", "\n").split("\n"):
		if line.begins_with(MARKER) and line.strip_edges().ends_with("-->"):
			if not current.is_empty():
				current.text = _entry_text(body)
				out.append(current)
			current = {}
			body = PackedStringArray()
			var raw := line.strip_edges().trim_prefix(MARKER).trim_suffix("-->")
			if json.parse(raw) == OK and json.data is Dictionary:
				var d: Dictionary = json.data
				current = {"real": str(d.get("real", "")), "session": int(d.get("session", 0)),
					"day": int(d.get("day", 0)), "time": int(d.get("time", -1)), "by": str(d.get("by", ""))}
		elif not current.is_empty():
			body.append(line)
	if not current.is_empty():
		current.text = _entry_text(body)
		out.append(current)
	return out


## The lines after the marker minus the generated heading.
static func _entry_text(lines: PackedStringArray) -> String:
	var start := 0
	if lines.size() > 0 and lines[0].begins_with("### "):
		start = 1
	return "\n".join(lines.slice(start)).strip_edges()
