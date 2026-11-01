extends SceneTree
## Headless check of SessionNotes (TASK-14, notes.json since TASK-20): entries with real
## date, session number and in-world day, saved in the campaign's notes.json and read back.
## godot --headless --path . -s tools/test_session_notes.gd

const CAMPAIGN := "user://test_notes"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(CAMPAIGN))
	var cal := WorldCalendar.load_file("res://calendars/default.json")
	var notes := SessionNotes.open(CAMPAIGN, 3, cal)
	notes.names = {"dm": "Nico", "ann": "Ann"}
	_check(notes.entries.is_empty(), "new session starts empty")
	_check(notes.path.ends_with("notes.json"), "one notes.json per campaign (%s)" % notes.path)

	var a := notes.add("The party reached the **old mill**.", "dm", 400, 14 * 60 + 30, "2026-11-01T20:15")
	notes.add("Ask the miller about [[Goblin Chief]].\nTwo lines.", "ann", 400, 15 * 60, "", "npcs/mira")
	var h := notes.heading(a)
	_check(h.begins_with("2026-11-01 20:15 · Session 3 · "), "heading starts with real date and session (%s)" % h)
	_check(h.contains(cal.format_moment(400, 14 * 60 + 30)), "heading has the in-world moment")
	_check(h.ends_with(" · Nico"), "heading names the writer")
	_check(a.id == "n1", "ids count up (%s)" % a.id)

	var all := SessionNotes.read_all(notes.path)
	_check(all.size() == 2, "both in notes.json")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(notes.path))
	_check(raw is Array and raw[0].text == "The party reached the **old mill**.", "text kept as Markdown")
	for key in ["id", "text", "real", "session", "day", "time", "by", "about"]:
		_check(raw is Array and raw[0].has(key), "entry has '%s'" % key)

	var again := SessionNotes.open(CAMPAIGN, 3, cal)
	_check(again.entries.size() == 2, "entries read back (%d)" % again.entries.size())
	if again.entries.size() == 2:
		var b: Dictionary = again.entries[1]
		_check(b.text == "Ask the miller about [[Goblin Chief]].\nTwo lines.", "multi-line text read back")
		_check(b.by == "ann" and b.day == 400 and b.time == 900 and b.session == 3 and b.about == "npcs/mira", "entry data read back")
		_check(b.id == "n2" and str(b.real).length() == 16 and "T" in str(b.real), "real date defaults to now (%s)" % b.real)
	again.add("Third.", "dm", 401)
	_check(SessionNotes.open(CAMPAIGN, 3, cal).entries.size() == 3, "append after reopen")
	var next := SessionNotes.open(CAMPAIGN, 4, cal)
	_check(next.entries.is_empty(), "next session starts empty")
	var n4 := next.add("Session four.", "dm", 410)
	_check(n4.id == "n4" and SessionNotes.read_all(notes.path).size() == 4, "same file, ids go on")
	_check(not FileAccess.file_exists(notes.path + ".tmp"), "no temp file left")

	print("session notes: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
