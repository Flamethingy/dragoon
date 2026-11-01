extends SceneTree
## Headless check of WorldCalendar with calendars/default.json:
## godot --headless --path . -s tools/test_calendar.gd

var _failed := 0


func _init() -> void:
	var c := WorldCalendar.load_file("res://calendars/default.json")
	_check(c != null, "loads default.json")
	if c == null:
		quit(1)
		return
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
	print("calendar: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _eq(got: String, want: String) -> void:
	_check(got == want, "%s == %s" % [got, want])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
