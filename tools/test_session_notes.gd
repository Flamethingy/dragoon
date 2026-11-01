extends SceneTree
## Headless check of SessionNotes (TASK-14): entries with real date, session number and
## in-world date, saved as markdown and read back.
## godot --headless --path . -s tools/test_session_notes.gd

const CAMPAIGN := "user://test_notes"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(CAMPAIGN))
	var cal := WorldCalendar.load_file("res://calendars/default.json")
	var notes := SessionNotes.open(CAMPAIGN, 3, cal)
	_check(notes.entries.is_empty(), "new session starts empty")
	_check(notes.path.ends_with("notes/session-03.md"), "file per session (%s)" % notes.path)
	_check(SessionNotes.path_for(CAMPAIGN, 0).ends_with("notes/prep.md"), "session 0 = prep.md")

	var a := notes.add("The party reached the **old mill**.", "DM", 400, 14 * 60 + 30, "2026-11-01 20:15")
	notes.add("Ask the miller about [[goblin-chief]].\nTwo lines.", "Player 2", 400, 15 * 60)
	var h := notes.heading(a)
	_check(h.begins_with("2026-11-01 20:15 · Session 3 · "), "heading starts with real date and session (%s)" % h)
	_check(h.contains(cal.format_moment(400, 14 * 60 + 30)), "heading has the in-world moment")
	_check(h.ends_with(" · DM"), "heading names the writer")

	var text := FileAccess.get_file_as_string(notes.path)
	var fm := Frontmatter.parse(text)
	_check(int(fm.frontmatter.get("session", 0)) == 3, "frontmatter has the session")
	_check(fm.body.begins_with("# Session 3"), "file has a title")
	_check(text.contains("### " + h), "markdown heading in the file")
	_check(text.contains("The party reached the **old mill**."), "text kept as markdown")

	var again := SessionNotes.open(CAMPAIGN, 3, cal)
	_check(again.entries.size() == 2, "entries read back (%d)" % again.entries.size())
	if again.entries.size() == 2:
		var b: Dictionary = again.entries[1]
		_check(b.text == "Ask the miller about [[goblin-chief]].\nTwo lines.", "multi-line text read back (%s)" % b.text)
		_check(b.by == "Player 2" and b.day == 400 and b.time == 900 and b.session == 3, "entry data read back")
		_check(str(b.real).length() == 16, "real date defaults to now (%s)" % b.real)
	# Appending after reopening keeps the old entries.
	again.add("Third.", "DM", 401)
	_check(SessionNotes.open(CAMPAIGN, 3, cal).entries.size() == 3, "append after reopen")
	_check(SessionNotes.open(CAMPAIGN, 4, cal).entries.is_empty(), "next session has its own file")

	print("session notes: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
