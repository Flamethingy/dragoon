class_name WorldCalendar
extends RefCounted
## Turns an in-world day number (plus minutes since midnight) into a readable date.
## Events only store the day number; a calendar is just formatting, loaded from a JSON
## definition (see calendars/default.json and backlog/docs/event-format.md), so editing
## or swapping it never breaks data. Day 0 is the first day of `first_year`.
## Negative day numbers count back before that.

var name := ""
var hours_per_day := 24
var first_year := 1
var weekdays: PackedStringArray = []
var weekday_of_day_0 := 0
var months: Array[Dictionary] = []  ## {name, days, festival}
var eras: Array[Dictionary] = []  ## {from_year, name, abbr}, sorted by from_year
var format := "{day}. {month} {year}"
var festival_format := "{month}, {year}"
var festival_day_format := "{month} (day {day}), {year}"
var days_per_year := 0


## Loads a calendar definition; null (with an error) if the file is missing or invalid.
static func load_file(path: String) -> WorldCalendar:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Calendar not found: %s" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Calendar is not a JSON object: %s" % path)
		return null
	return from_dict(data)


static func from_dict(data: Dictionary) -> WorldCalendar:
	var c := WorldCalendar.new()
	c.name = str(data.get("name", ""))
	c.hours_per_day = maxi(1, int(data.get("hours_per_day", 24)))
	c.first_year = int(data.get("first_year", 1))
	for w: Variant in data.get("weekdays", []):
		c.weekdays.append(str(w))
	c.weekday_of_day_0 = int(data.get("weekday_of_day_0", 0))
	for m: Variant in data.get("months", []):
		if typeof(m) == TYPE_DICTIONARY and int(m.get("days", 0)) > 0:
			c.months.append({"name": str(m.get("name", "")), "days": int(m["days"]),
				"festival": bool(m.get("festival", false))})
			c.days_per_year += int(m["days"])
	for e: Variant in data.get("eras", []):
		if typeof(e) == TYPE_DICTIONARY:
			c.eras.append({"from_year": int(e.get("from_year", c.first_year)),
				"name": str(e.get("name", "")), "abbr": str(e.get("abbr", e.get("name", "")))})
	c.eras.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.from_year < b.from_year)
	c.format = str(data.get("format", c.format))
	c.festival_format = str(data.get("festival_format", c.festival_format))
	c.festival_day_format = str(data.get("festival_day_format", c.festival_day_format))
	if c.days_per_year == 0:
		push_error("Calendar has no months with days")
		return null
	return c


## The parts of a day number: year, month index (0-based), month name, day of month
## (1-based), weekday name, era abbreviation, festival flag.
func date_of(day: int) -> Dictionary:
	var year := first_year + floori(float(day) / days_per_year)
	var in_year := posmod(day, days_per_year)
	var month := 0
	while in_year >= int(months[month].days):
		in_year -= int(months[month].days)
		month += 1
	var era := {}
	for e: Dictionary in eras:
		if year >= e.from_year:
			era = e
	return {
		"year": year,
		"month": month,
		"month_name": months[month].name,
		"day": in_year + 1,
		"weekday": weekdays[posmod(day + weekday_of_day_0, weekdays.size())] if not weekdays.is_empty() else "",
		"era": era.get("abbr", ""),
		"era_name": era.get("name", ""),
		"festival": months[month].festival,
	}


## E.g. "Fireday, 12. Seedtime 1 AF". Festival months use festival_format (or
## festival_day_format when the festival lasts more than one day).
func format_day(day: int) -> String:
	var d := date_of(day)
	var pattern := format
	if d.festival:
		pattern = festival_day_format if int(months[d.month].days) > 1 else festival_format
	return pattern.format({"weekday": d.weekday, "day": d.day, "month": d.month_name,
		"year": d.year, "era": d.era, "era_name": d.era_name}).strip_edges()


## Minutes since midnight as "HH:MM" (with the calendar's hours per day).
func format_time(minutes: int) -> String:
	var m := posmod(minutes, hours_per_day * 60)
	return "%02d:%02d" % [m / 60, m % 60]


## Day plus optional time (time < 0 = unknown, left out).
func format_moment(day: int, time := -1) -> String:
	return format_day(day) if time < 0 else "%s, %s" % [format_day(day), format_time(time)]
