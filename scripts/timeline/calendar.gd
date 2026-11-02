class_name WorldCalendar
extends RefCounted
## Turns an in-world day number (plus minutes since midnight) into a readable date.
## Events only store the day number; a calendar is just formatting, loaded from a JSON
## definition (see calendars/default.json and backlog/docs/event-format.md), so editing
## or swapping it never breaks data. Day 0 is the first day of `first_year`.
## Negative day numbers count back before that.
## A world can have its own calendar in `<world_dir>/calendar.json`, edited from the Esc menu
## (CalendarEditor); it wins over `res://calendars/<id>.json` (for_world). Moons (Nico
## 2026-11-02): each has a cycle and the day of a new moon; moon_phase says where it stands.

const WORLD_FILE := "calendar.json"
const PHASE_NAMES := ["New", "Waxing crescent", "First quarter", "Waxing gibbous", "Full",
	"Waning gibbous", "Last quarter", "Waning crescent"]
## The keys from_dict reads; others (e.g. "comment") are kept in `extra` and saved again.
const KEYS := ["name", "hours_per_day", "first_year", "weekdays", "weekday_of_day_0", "months",
	"eras", "format", "festival_format", "festival_day_format", "moons"]

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
var moons: Array[Dictionary] = []  ## {name, cycle_days (float), offset_days (float, a new moon), color "#rrggbb"}
var days_per_year := 0
var extra := {}  ## keys of the file we don't use, kept when saving


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


## The calendar of a world: its own `calendar.json` if it has one, else the one its
## package.json names (`"calendar": "<id>"` -> res://calendars/<id>.json), else the default.
static func for_world(world_dir: String) -> WorldCalendar:
	if world_dir != "" and FileAccess.file_exists(world_file(world_dir)):
		var own := load_file(world_file(world_dir))
		if own != null:
			return own
	return load_file(builtin_path(world_dir))


## The world's own calendar file (the editor writes it).
static func world_file(world_dir: String) -> String:
	return world_dir.path_join(WORLD_FILE)


## res://calendars/<id>.json for the id in the world's package.json (the default if missing).
static func builtin_path(world_dir: String) -> String:
	var id := "default"
	if world_dir != "" and FileAccess.file_exists(world_dir.path_join("package.json")):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(world_dir.path_join("package.json")))
		if m is Dictionary and str(m.get("calendar", "")) != "":
			id = str(m.calendar)
	var path := "res://calendars/%s.json" % id
	return path if FileAccess.file_exists(path) else "res://calendars/default.json"


static func from_dict(data: Dictionary) -> WorldCalendar:
	var c := WorldCalendar.new()
	for k: Variant in data:
		if str(k) not in KEYS:
			c.extra[str(k)] = data[k]
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
	var moons_in: Variant = data.get("moons", [])  # older files have none
	for mo: Variant in moons_in if moons_in is Array else []:
		if typeof(mo) == TYPE_DICTIONARY:
			c.moons.append({"name": str(mo.get("name", "")), "cycle_days": maxf(0.01, float(mo.get("cycle_days", 30.0))),
				"offset_days": float(mo.get("offset_days", 0.0)), "color": str(mo.get("color", "#d8d8d8"))})
	if c.days_per_year == 0:
		push_error("Calendar has no months with days")
		return null
	return c


## The definition as JSON data (from_dict reads it back).
func to_dict() -> Dictionary:
	var d := extra.duplicate(true)
	var ms := []
	for m: Dictionary in months:
		var o := {"name": m.name, "days": m.days}
		if m.festival:
			o["festival"] = true
		ms.append(o)
	d.merge({"name": name, "hours_per_day": hours_per_day, "first_year": first_year,
		"weekdays": Array(weekdays), "weekday_of_day_0": weekday_of_day_0, "months": ms,
		"eras": eras.duplicate(true), "format": format, "festival_format": festival_format,
		"festival_day_format": festival_day_format, "moons": moons.duplicate(true)}, true)
	return d


## Writes the definition as JSON (the editor: world_file(world_dir)).
func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "  ", false))
	return OK


# --- Moons (Nico 2026-11-02) -------------------------------------------------------------------

## Where moon `i` is in its cycle on a day (plus minutes since midnight), in 0..1:
## 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter. 0 for an unknown moon.
func moon_phase(i: int, day: int, minutes := 0) -> float:
	if i < 0 or i >= moons.size():
		return 0.0
	var t := float(day) + float(maxi(minutes, 0)) / float(hours_per_day * 60)  # time < 0 = unknown: midnight
	var m := moons[i]
	return fposmod((t - float(m.offset_days)) / float(m.cycle_days), 1.0)


## The name of a phase (moon_phase): eight parts, each centred on its point (New around 0,
## Full around 0.5).
func phase_name(f: float) -> String:
	return PHASE_NAMES[posmod(floori(fposmod(f, 1.0) * 8.0 + 0.5), 8)]


## Moon `i`'s colour (white if unknown or unreadable).
func moon_color(i: int) -> Color:
	if i < 0 or i >= moons.size():
		return Color.WHITE
	return Color.from_string(str(moons[i].color), Color.WHITE)


## Every moon at a moment: [{name, phase (0..1), phase_name, color (Color)}].
func moons_at(day: int, minutes := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in moons.size():
		var f := moon_phase(i, day, minutes)
		out.append({"name": moons[i].name, "phase": f, "phase_name": phase_name(f), "color": moon_color(i)})
	return out


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
