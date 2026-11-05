extends SceneTree
## Headless check of the calendar (TASK-112): the timeline bar is off the main screen, the date
## at the top opens the calendar; a month grid with today marked and the entries (sessions, time
## passing, travel, long rests); the DM passes time in big steps; a player gets today and only
## the entries she may see from the host.
## godot --headless --path . -s tools/test_calendar_view.gd

const PORT := 47831
const ADDRESS := "127.0.0.1:47831"
const DIR := "user://test_calendar_view"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	# --- Entries from events -------------------------------------------------------------------
	var events := [
		{"type": "note.added", "day": 10, "time": 600, "session": 1, "data": {}},
		{"type": "time.advanced", "day": 13, "time": 600, "session": 1, "data": {"from_day": 10, "from_time": 600, "reason": "travel to Red Fang"}},
		{"type": "time.advanced", "day": 13, "time": 601, "session": 1, "data": {"from_day": 13, "from_time": 600, "reason": "round"}},
		{"type": "rest.taken", "day": 13, "time": 1200, "session": 2, "data": {"kind": "long"}},
		{"type": "rest.taken", "day": 13, "time": 1200, "session": 2, "data": {"kind": "long"}},
		{"type": "rest.taken", "day": 13, "time": 900, "session": 2, "data": {"kind": "short"}},
		{"type": "time.advanced", "day": 14, "time": 120, "session": 2, "data": {"from_day": 13, "from_time": 1200, "reason": "the lich's ritual", "dm_only": true}},
	]
	var dm_entries := CalendarView.entries_of(events, true)
	var kinds := dm_entries.map(func(e: Dictionary) -> String: return e.kind)
	_check(kinds == ["session", "travel", "session", "rest", "time"], "sessions, travel, one long rest a day, no combat steps (%s)" % [kinds])
	_check(dm_entries[1].day == 10 and str(dm_entries[1].text).begins_with("3 days"), "travel starts on its first day, how long (%s)" % [dm_entries[1]])
	_check(not CalendarView.entries_of(events, false).any(func(e: Dictionary) -> bool: return str(e.text).contains("ritual")), "players don't see DM-only entries")

	# --- At the table --------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	var dm := _table("DM", "dm")
	var ann := _table("Ann", "ann")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await process_frame
	var ui := dm._ui
	_check(not ui.timeline_bar.visible, "no timeline bar on the main screen")
	_check(ui.date_button.visible and ui.date_button.text.contains(dm.notes.calendar.format_day(dm.event_log.day)), "the date at the top (%s)" % ui.date_button.text)
	ui.date_button.pressed.emit()
	var cal := ui.calendar_view
	_check(cal.visible, "a click opens the calendar")
	var month: Dictionary = dm.notes.calendar.date_of(dm.event_log.day)
	_check(cal._title.text.begins_with(str(month.month_name)), "today's month (%s)" % cal._title.text)
	var today := _cell(cal, dm.event_log.day)
	_check(today != null and (today.get_theme_stylebox("panel") as StyleBoxFlat).border_width_top == 3, "today is marked")
	var before := dm.event_log.day
	cal._days.value = 3
	cal._reason.text = "travel to Red Fang"
	(cal.find_child("PassDays", true, false) as Button).pressed.emit()
	_check(dm.event_log.day == before + 3, "the DM passes 3 days (%d -> %d)" % [before, dm.event_log.day])
	var start := _cell(cal, before)
	_check(start != null and start.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.get_meta("kind", "") == "travel"),
		"the journey is on its first day")
	_check(ui.date_button.text.contains(dm.notes.calendar.format_day(dm.event_log.day)), "the date at the top moved on")
	(cal.find_child("PassRest", true, false) as Button).pressed.emit()
	_check(cal.view.entries.any(func(e: Dictionary) -> bool: return e.kind == "rest"), "a long rest")
	var shown := cal._title.text
	(cal.find_child("Next", true, false) as Button).pressed.emit()
	_check(cal._title.text != shown, "› the next month (%s)" % cal._title.text)
	(cal.find_child("TodayButton", true, false) as Button).pressed.emit()
	_check(cal._title.text == shown, "Today goes back")

	# --- A player ------------------------------------------------------------------------------
	dm.event_log.append("time.advanced", "", {"from_day": dm.event_log.day, "from_time": dm.event_log.time, "reason": "secret", "dm_only": true})
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc != "")
	var got := []
	ann.calendar_received.connect(func(v: Dictionary) -> void: got.append(v))
	ann.request_calendar()
	await _until(func() -> bool: return not got.is_empty())
	_check(not got.is_empty() and int(got[0].day) == dm.event_log.day, "Ann gets today from the host")
	_check(not got.is_empty() and got[0].entries.any(func(e: Dictionary) -> bool: return e.kind == "travel")
		and not got[0].entries.any(func(e: Dictionary) -> bool: return str(e.text).contains("Secret")), "the journey, not the DM's secret")
	await _until(func() -> bool: return ann._ui.date_button.text.contains(dm.notes.calendar.format_day(dm.event_log.day)))
	_check(ann._ui.date_button.text.contains(dm.notes.calendar.format_day(dm.event_log.day)), "her date at the top (%s)" % ann._ui.date_button.text)
	_check(not ann._ui.calendar_view.find_child("PassTime", true, false).visible or not ann._ui.calendar_view.visible, "no Pass time for a player")
	ann._ui.open_calendar()
	await process_frame
	_check(not (ann._ui.calendar_view.find_child("PassTime", true, false) as Control).visible, "a player can't pass time")

	print("calendar view: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _cell(cal: CalendarView, day: int) -> PanelContainer:
	for c: Node in cal._grid.get_children():
		if c.has_meta("day") and int(c.get_meta("day")) == day:
			return c as PanelContainer
	return null


func _table(branch: String, cache: String) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.timeline_dir = TIMELINE
	t.cache_dir = DIR.path_join("cache_" + cache)
	holder.add_child(t)
	return t


func _until(done: Callable, frames := 400) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
