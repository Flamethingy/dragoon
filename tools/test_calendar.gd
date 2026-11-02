extends SceneTree
## Headless check of WorldCalendar with calendars/default.json, its moons (Nico 2026-11-02),
## saving and loading, a world's own calendar.json, and the calendar editor from the DM's
## Esc menu: saving it changes the table's calendar and reaches a player.
## godot --headless --path . -s tools/test_calendar.gd

const DIR := "user://test_calendar"
const PORT := 47871

var _failed := 0
var _editor_done := false  ## a script error in the editor part must not pass


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base.path_join("packages"))
	var c := WorldCalendar.load_file("res://calendars/default.json")
	_check(c != null, "loads default.json")
	if c == null:
		quit(1)
		return
	_dates(c)
	_moons(c)
	_round_trip(c)
	_world_override()
	await _editor()
	_check(_editor_done, "the editor part ran to the end")
	PackageManager._delete_tree(base)
	print("calendar: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _dates(c: WorldCalendar) -> void:
	_check(c.days_per_year == 335, "335 days per year (got %d)" % c.days_per_year)
	_eq(c.format_day(0), "Moonday, 1. Deepwinter 1 AF")
	_eq(c.format_day(6), "Sunday, 7. Deepwinter 1 AF")
	_eq(c.format_day(7), "Moonday, 8. Deepwinter 1 AF")
	_eq(c.format_day(30), "Moonday, 1. Thawing 1 AF".replace("Moonday", c.date_of(30).weekday))
	_eq(c.format_day(150), "Midsummer, 1 AF")  # 5 months x 30 days, then the festival
	_eq(c.format_day(151), "%s, 1. Goldfields 1 AF" % c.date_of(151).weekday)
	_eq(c.format_day(332), "Yearsend (day 2), 1 AF")
	_eq(c.format_day(335), "%s, 1. Deepwinter 2 AF" % c.date_of(335).weekday)
	_eq(c.format_day(-1), "Yearsend (day 4), 0")  # before the first era: no era
	_eq(c.format_time(0), "00:00")
	_eq(c.format_time(14 * 60 + 5), "14:05")
	_eq(c.format_moment(0, 9 * 60), "Moonday, 1. Deepwinter 1 AF, 09:00")


func _moons(c: WorldCalendar) -> void:
	_check(c.moons.size() >= 2 and str(c.moons[0].name) != "", "default.json has moons (%d)" % c.moons.size())
	var m := WorldCalendar.from_dict({"months": [{"name": "A", "days": 30}], "hours_per_day": 24,
		"moons": [{"name": "Eight", "cycle_days": 8, "offset_days": 2, "color": "#ff0000"}]})
	_near(m.moon_phase(0, 2), 0.0, "new on its offset day")
	_near(m.moon_phase(0, 4), 0.25, "first quarter after a quarter cycle")
	_near(m.moon_phase(0, 6), 0.5, "full after half a cycle")
	_near(m.moon_phase(0, 8), 0.75, "last quarter")
	_near(m.moon_phase(0, 10), 0.0, "new again after a cycle")
	_near(m.moon_phase(0, 2, 12 * 60), 1.0 / 16.0, "noon counts as half a day")
	_near(m.moon_phase(0, 1), 0.875, "before the offset day it wraps around")
	_near(m.moon_phase(0, -14), 0.0, "negative days")
	_near(m.moon_phase(3, 5), 0.0, "an unknown moon is 0")
	_check(m.moon_color(0) == Color.RED, "its colour")
	var half := WorldCalendar.from_dict({"months": [{"name": "A", "days": 30}], "hours_per_day": 12,
		"moons": [{"name": "Eight", "cycle_days": 8, "offset_days": 0}]})
	_near(half.moon_phase(0, 0, 6 * 60), 1.0 / 16.0, "the calendar's hours per day")
	for pair: Array in [[0.0, "New"], [0.04, "New"], [0.97, "New"], [0.125, "Waxing crescent"], [0.25, "First quarter"],
			[0.3, "First quarter"], [0.375, "Waxing gibbous"], [0.5, "Full"], [0.55, "Full"], [0.625, "Waning gibbous"],
			[0.75, "Last quarter"], [0.875, "Waning crescent"], [1.0, "New"]]:
		_eq(m.phase_name(float(pair[0])), str(pair[1]))
	var at := m.moons_at(6)
	_check(at.size() == 1 and at[0].phase_name == "Full" and at[0].name == "Eight", "moons_at (%s)" % [at])
	var old := WorldCalendar.from_dict({"months": [{"name": "A", "days": 30}]})
	_check(old != null and old.moons.is_empty() and old.moons_at(3).is_empty(), "an older calendar without moons still loads")


func _round_trip(c: WorldCalendar) -> void:
	var path := DIR.path_join("round.json")
	_check(c.save_file(path) == OK, "saves")
	var back := WorldCalendar.load_file(path)
	_check(back != null, "loads what it saved")
	if back == null:
		return
	_check(JSON.stringify(back.to_dict()) == JSON.stringify(c.to_dict()), "the same definition after a round trip")
	_check(back.moons == c.moons and back.moons.size() == c.moons.size(), "moons survive")
	_check(str(back.extra.get("comment", "")) != "", "unknown keys (the comment) are kept")
	for d in [0, 150, 332, 1000, -40]:
		_eq(back.format_day(d), c.format_day(d))
	_near(back.moon_phase(1, 77, 300), c.moon_phase(1, 77, 300), "same phases")


func _world_override() -> void:
	var w := ProjectSettings.globalize_path(DIR.path_join("world"))
	DirAccess.make_dir_recursive_absolute(w)
	_write(w.path_join("package.json"), {"kind": "world", "calendar": "default"})
	_eq(WorldCalendar.for_world(w).name, "Dragoon Reckoning")
	_write(w.path_join("package.json"), {"kind": "world", "calendar": "missing-one"})
	_eq(WorldCalendar.for_world(w).name, "Dragoon Reckoning")  # unknown id: the default
	var own := WorldCalendar.from_dict({"name": "Own", "months": [{"name": "Only", "days": 10}]})
	_check(own.save_file(WorldCalendar.world_file(w)) == OK, "a world calendar is written")
	_eq(WorldCalendar.for_world(w).name, "Own")
	_check(WorldCalendar.world_file(w) == w.path_join("calendar.json"), "it is <world>/calendar.json")
	_eq(WorldCalendar.for_world("").name, "Dragoon Reckoning")


func _editor() -> void:
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	Dock.layout_file = DIR.path_join("layout.json")
	var dm := _app("DM")
	await process_frame
	var west: Dictionary = Worlds.list(dm.worlds_root).filter(func(x: Dictionary) -> bool: return x.id == "westmarch")[0]
	var world := str(west._dir)
	var own := WorldCalendar.load_file("res://calendars/default.json")
	own.name = "Westmarch Reckoning"
	own.save_file(WorldCalendar.world_file(world))
	_check(dm.host(world.path_join("timelines/red-fang"), PORT) == OK, "DM hosts")
	_eq(dm.table.notes.calendar.name, "Westmarch Reckoning")  # the world's own wins
	_check(dm.table_ui.timeline_bar.line.calendar == dm.table.notes.calendar, "the timeline bar has the world's calendar")
	var pl := _app("Player")
	await process_frame
	pl.table.cache_dir = DIR.path_join("cache_ann")
	_check(pl.join("127.0.0.1:%d" % PORT, "Ann") == OK, "a player joins")
	await _until(func() -> bool: return pl.table.my_pc != "" and pl.table.notes.calendar.name == "Westmarch Reckoning")
	_eq(pl.table.notes.calendar.name, "Westmarch Reckoning")  # sent on joining

	# The Esc menu: Calendar for the DM only
	dm.esc_menu.open()
	var entry := dm.esc_menu.button("Calendar")
	_check(entry != null, "the DM's Esc menu has Calendar")
	pl.esc_menu.open()
	_check(pl.esc_menu.button("Calendar") == null, "a player's doesn't")
	pl.esc_menu.close()
	if entry == null:
		return
	entry.pressed.emit()
	var ed := dm.calendar_editor
	_check(ed != null and ed.visible and not dm.esc_menu.visible, "it opens the editor")
	if ed == null:
		return
	await process_frame
	for n: String in ["CalName", "Hours", "FirstYear", "Day0Weekday", "AddWeekday", "AddMonth", "AddEra", "AddMoon",
			"Format", "FestivalFormat", "FestivalDayFormat", "Save", "Cancel"]:
		_check(ed.find_child(n, true, false) != null, "the editor has %s" % n)
	_check(ed.form.find_child("Month12", false, false) != null and ed.form.find_child("Weekday6", false, false) != null, "months and weekdays listed")
	_check(ed.form.find_child("Moon1", false, false) != null and ed.form.find_child("Moon2", false, false) == null, "the two moons listed")
	var today := ed.preview.find_child("Today", true, false) as Label
	_check(today != null and today.text == dm.table.notes.calendar.format_moment(dm.table.event_log.day, dm.table.event_log.time), "preview: today on the table (%s)" % (today.text if today else ""))
	_check(ed.preview.find_child("MoonPhase1", true, false) != null, "preview: each moon's phase")

	# Edit through the controls
	var cal_name := ed.find_child("CalName", true, false) as LineEdit
	cal_name.text = "Edited Reckoning"
	cal_name.text_changed.emit(cal_name.text)
	(ed.find_child("Hours", true, false) as SpinBox).value = 20
	(ed.find_child("AddMoon", true, false) as Button).pressed.emit()
	var moon := ed.form.find_child("Moon2", false, false)
	_check(moon != null, "a third moon row")
	if moon == null:
		return
	var mn := moon.find_child("MoonName", true, false) as LineEdit
	mn.text = "Teal"
	mn.text_changed.emit(mn.text)
	(moon.find_child("Cycle", true, false) as SpinBox).value = 10.0
	(moon.find_child("Offset", true, false) as SpinBox).value = 3.0
	var pick := moon.find_child("MoonColor", true, false) as ColorPickerButton
	pick.color = Color("#00ff80")
	pick.color_changed.emit(pick.color)
	_check(ed.preview.find_child("MoonPhase2", true, false) != null, "the preview follows")
	(ed.form.find_child("Moon0", false, false).find_child("Remove", true, false) as Button).pressed.emit()
	_check((ed.data.moons as Array).size() == 2 and ed.data.moons[1].name == "Teal", "a moon removed")
	var first := str(ed.data.months[0].name)
	(ed.form.find_child("Month0", false, false).find_child("Down", true, false) as Button).pressed.emit()
	_check(str(ed.data.months[1].name) == first, "a month moved down")
	(ed.form.find_child("Month1", false, false).find_child("Up", true, false) as Button).pressed.emit()
	_check(str(ed.data.months[0].name) == first, "and up again")
	(ed.find_child("AddMonth", true, false) as Button).pressed.emit()
	var last := ed.form.find_child("Month13", false, false)
	(last.find_child("Days", true, false) as SpinBox).value = 5
	(last.find_child("Festival", true, false) as CheckBox).button_pressed = true
	(ed.find_child("AddWeekday", true, false) as Button).pressed.emit()
	(ed.form.find_child("Weekday7", false, false).find_child("Remove", true, false) as Button).pressed.emit()
	(ed.find_child("AddEra", true, false) as Button).pressed.emit()
	var era := ed.form.find_child("Era1", false, false)
	(era.find_child("FromYear", true, false) as SpinBox).value = 500
	var abbr := era.find_child("EraAbbr", true, false) as LineEdit
	abbr.text = "NE"
	abbr.text_changed.emit("NE")
	var c := ed.calendar()
	_check(c != null and c.days_per_year == 340 and c.hours_per_day == 20 and c.eras.size() == 2 and c.weekdays.size() == 7, "the edited calendar (%s)" % (c.to_dict() if c else {}))
	var keep := ed.data.duplicate(true)  # no months: can't save
	ed.data.months = []
	ed._changed()
	_check(ed.save_button.disabled and ed.save() != OK and ed.visible, "a calendar without months can't be saved")
	ed.data = keep
	ed._rebuild()

	(ed.find_child("Save", true, false) as Button).pressed.emit()
	_check(not ed.visible, "Save closes the editor")
	var saved := WorldCalendar.load_file(WorldCalendar.world_file(world))
	_check(saved != null and saved.name == "Edited Reckoning" and saved.moons.size() == 2 and saved.moons[1].name == "Teal" \
		and is_equal_approx(float(saved.moons[1].cycle_days), 10.0) and str(saved.moons[1].color) == "#00ff80", "written to <world>/calendar.json")
	_check(saved != null and saved.days_per_year == 340 and saved.months[13].festival, "with the new month")
	_eq(dm.table.notes.calendar.name, "Edited Reckoning")
	_check(dm.table_ui.timeline_bar.line.calendar == dm.table.notes.calendar, "the timeline bar uses it at once")
	_eq(WorldCalendar.for_world(world).name, "Edited Reckoning")
	await _until(func() -> bool: return pl.table.notes.calendar.name == "Edited Reckoning")
	_eq(pl.table.notes.calendar.name, "Edited Reckoning")
	_check(pl.table.notes.calendar.moons.size() == 2 and pl.table_ui.timeline_bar.line.calendar == pl.table.notes.calendar, "the player gets the moons, their bar too")
	dm.open_calendar()
	_check(ed.visible and (ed.find_child("CalName", true, false) as LineEdit).text == "Edited Reckoning", "it opens again with the saved calendar")
	(ed.find_child("Cancel", true, false) as Button).pressed.emit()
	_check(not ed.visible, "Cancel closes it")
	_check(pl.open_calendar() == null, "a player can't open it")
	pl.leave()
	dm.leave()
	_editor_done = true
	await process_frame


func _app(branch: String) -> App:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var app := App.new()
	app.name = "App"  # the same node path on every peer
	app.worlds_root = ProjectSettings.globalize_path(DIR.path_join("worlds"))
	app.packages_root = ProjectSettings.globalize_path(DIR.path_join("packages"))
	app.minimal = false
	holder.add_child(app)
	return app


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))


func _until(done: Callable, frames := 400) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _near(got: float, want: float, what: String) -> void:
	_check(absf(got - want) < 0.0001, "%s (%f, want %f)" % [what, got, want])


func _eq(got: String, want: String) -> void:
	_check(got == want, "%s == %s" % [got, want])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
