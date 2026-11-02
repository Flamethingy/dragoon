class_name CalendarEditor
extends Control
## The world's calendar, edited from the Esc menu (Nico 2026-11-02): name, hours per day,
## first year, weekdays, months (festivals), eras, the date formats and the moons, with a
## live preview of today's date on the table and each moon's phase. Save writes
## `<world>/calendar.json` (it wins over res://calendars) and the table uses it at once,
## the players too (NetTable.save_calendar). Esc or Cancel leaves without saving.

signal saved(calendar: WorldCalendar)
signal closed

const FORMAT_HINT := "{weekday} {day} {month} {year} {era} {era_name}"
const MOON_COLORS := ["#e8e4d8", "#d0603a", "#7fa8d8", "#9ad07f", "#c88fd8"]

var table: NetTable
var world_dir := ""  ## where Save writes calendar.json (taken from the table when there is one)
var data := {}  ## the calendar being edited, as WorldCalendar.to_dict()
var day := 0  ## the preview's moment (the table's now)
var time := -1
var form: VBoxContainer
var preview: VBoxContainer
var status: Label
var save_button: Button
var day0_pick: OptionButton


## A moon's phase as a small disk: the lit part in its colour.
class MoonDisk extends Control:
	var phase := 0.0
	var color := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5 - 1.0
		var c := size * 0.5
		draw_circle(c, r, Color(0.12, 0.12, 0.16))
		var k := cos(TAU * phase)  # the terminator's width: 1 = new, -1 = full
		if k > 0.98:
			return
		if k < -0.98:
			draw_circle(c, r, color)
		else:
			var s := 1.0 if phase < 0.5 else -1.0  # waxing: lit on the right
			var pts := PackedVector2Array()
			for j in 17:
				var a := -PI / 2 + PI * j / 16.0
				pts.append(c + Vector2(s * r * cos(a), r * sin(a)))
			for j in 17:
				var a := PI / 2 - PI * j / 16.0
				pts.append(c + Vector2(s * k * r * cos(a), r * sin(a)))
			draw_colored_polygon(pts, color)
		draw_arc(c, r, 0, TAU, 32, color.darkened(0.3), 1.0)


func _init() -> void:
	name = "CalendarEditor"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = UISkin.V_PAGE
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	var title := Label.new()
	title.text = "Calendar"
	title.theme_type_variation = UISkin.V_HEADING
	outer.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	outer.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(620, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	form = VBoxContainer.new()
	form.name = "Form"
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)
	var side := PanelContainer.new()
	side.theme_type_variation = UISkin.V_CARD
	side.custom_minimum_size = Vector2(260, 0)
	cols.add_child(side)
	preview = VBoxContainer.new()
	preview.name = "Preview"
	preview.add_theme_constant_override("separation", 6)
	side.add_child(preview)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(buttons)
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = UISkin.V_MUTED
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(status)
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Cancel"
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	save_button = Button.new()
	save_button.name = "Save"
	save_button.text = "Save"
	save_button.pressed.connect(func() -> void: save())
	buttons.add_child(save_button)


## Shows the editor with a copy of `c` (null: the default calendar), today from the table.
func open(c: WorldCalendar) -> void:
	if c == null:
		c = WorldCalendar.load_file("res://calendars/default.json")
	data = c.to_dict()
	if table != null and table.timeline != null:
		world_dir = table.timeline.world_dir
	if table != null and table.event_log != null:
		day = table.event_log.day
		time = table.event_log.time
	status.text = ""
	_build_form()
	_changed()
	visible = true
	move_to_front()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## The calendar as edited; null if it can't be one (no month with days).
func calendar() -> WorldCalendar:
	if not (data.get("months", []) as Array).any(func(m: Dictionary) -> bool: return int(m.get("days", 0)) > 0):
		return null
	return WorldCalendar.from_dict(data)


## Writes the world's calendar.json and uses it on the table (and the players' screens).
func save() -> Error:
	var c := calendar()
	if c == null:
		status.text = "A calendar needs at least one month with days."
		return ERR_INVALID_DATA
	var err: Error
	if table != null and table.is_dm():
		err = table.save_calendar(c)
	elif world_dir != "":
		err = c.save_file(WorldCalendar.world_file(world_dir))
	else:
		err = ERR_FILE_BAD_PATH
	if err != OK:
		status.text = "Could not save: %s" % error_string(err)
		return err
	saved.emit(c)
	close()
	return OK


# --- Changes (the buttons call these) ------------------------------------------------------------

func add_weekday(weekday := "") -> void:
	(data.weekdays as Array).append(weekday if weekday != "" else "Day %d" % ((data.weekdays as Array).size() + 1))
	_rebuild()


func remove_weekday(i: int) -> void:
	(data.weekdays as Array).remove_at(i)
	data.weekday_of_day_0 = clampi(int(data.weekday_of_day_0), 0, maxi((data.weekdays as Array).size() - 1, 0))
	_rebuild()


func add_month(month := "", days := 30, festival := false) -> void:
	var m := {"name": month if month != "" else "Month %d" % ((data.months as Array).size() + 1), "days": days}
	if festival:
		m["festival"] = true
	(data.months as Array).append(m)
	_rebuild()


func remove_month(i: int) -> void:
	(data.months as Array).remove_at(i)
	_rebuild()


## Moves month `i` up (by -1) or down (by 1).
func move_month(i: int, by: int) -> void:
	var ms: Array = data.months
	var j := i + by
	if i < 0 or i >= ms.size() or j < 0 or j >= ms.size():
		return
	var m: Variant = ms[i]
	ms[i] = ms[j]
	ms[j] = m
	_rebuild()


func add_era(era := "", from_year := 1, abbr := "") -> void:
	(data.eras as Array).append({"from_year": from_year, "name": era if era != "" else "New era", "abbr": abbr})
	_rebuild()


func remove_era(i: int) -> void:
	(data.eras as Array).remove_at(i)
	_rebuild()


func add_moon(moon := "", cycle_days := 28.0, offset_days := 0.0, color := "") -> void:
	var n := (data.moons as Array).size()
	(data.moons as Array).append({"name": moon if moon != "" else "Moon %d" % (n + 1), "cycle_days": cycle_days,
		"offset_days": offset_days, "color": color if color != "" else MOON_COLORS[n % MOON_COLORS.size()]})
	_rebuild()


func remove_moon(i: int) -> void:
	(data.moons as Array).remove_at(i)
	_rebuild()


func _rebuild() -> void:
	_build_form()
	_changed()


## After every edit: the preview, and Save only for a usable calendar.
func _changed() -> void:
	var c := calendar()
	save_button.disabled = c == null
	for ch in preview.get_children():
		preview.remove_child(ch)
		ch.queue_free()
	preview.add_child(_label("Preview", UISkin.V_HEADING))
	if c == null:
		preview.add_child(_label("Needs at least one month with days.", UISkin.V_MUTED))
		return
	preview.add_child(_label("Today on the table", UISkin.V_MUTED))
	var today := _label(c.format_moment(day, time))
	today.name = "Today"
	today.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(today)
	preview.add_child(_label("%d days a year, %d hours a day" % [c.days_per_year, c.hours_per_day], UISkin.V_MUTED))
	if c.moons.is_empty():
		return
	preview.add_child(_label("Moons", UISkin.V_MUTED))
	var i := 0
	for m: Dictionary in c.moons_at(day, maxi(time, 0)):
		var row := HBoxContainer.new()
		row.name = "MoonPhase%d" % i
		var disk := MoonDisk.new()
		disk.phase = float(m.phase)
		disk.color = m.color
		row.add_child(disk)
		var l := _label("%s: %s (%d%%)" % [m.name, m.phase_name, roundi(float(m.phase) * 100.0)])
		l.name = "Phase"
		row.add_child(l)
		preview.add_child(row)
		i += 1


# --- The form ----------------------------------------------------------------------------------

func _build_form() -> void:
	for ch in form.get_children():
		form.remove_child(ch)
		ch.queue_free()
	for k: String in ["weekdays", "months", "eras", "moons"]:
		if not data.get(k) is Array:
			data[k] = []
	_section("General")
	var name_edit := _line("CalName", str(data.get("name", "")), func(t: String) -> void: data.name = t)
	_row("Name", name_edit)
	_row("Hours per day", _spin("Hours", float(data.get("hours_per_day", 24)), 1, 240, 1,
		func(v: float) -> void: data.hours_per_day = int(v)))
	_row("First year", _spin("FirstYear", float(data.get("first_year", 1)), -99999, 99999, 1,
		func(v: float) -> void: data.first_year = int(v)))
	day0_pick = OptionButton.new()
	day0_pick.name = "Day0Weekday"
	for w: Variant in data.weekdays:
		day0_pick.add_item(str(w))
	if not (data.weekdays as Array).is_empty():
		day0_pick.select(clampi(int(data.get("weekday_of_day_0", 0)), 0, (data.weekdays as Array).size() - 1))
	day0_pick.item_selected.connect(func(i: int) -> void:
		data.weekday_of_day_0 = i
		_changed())
	_row("Weekday of day 0", day0_pick)

	_section("Weekdays")
	for i in (data.weekdays as Array).size():
		var row := _list_row("Weekday%d" % i)
		row.add_child(_line("WeekdayName", str(data.weekdays[i]), func(t: String) -> void:
			data.weekdays[i] = t
			day0_pick.set_item_text(i, t), true))
		row.add_child(_button("Remove", remove_weekday.bind(i)))
	form.add_child(_button("Add weekday", func() -> void: add_weekday(), "AddWeekday"))

	_section("Months")
	for i in (data.months as Array).size():
		var m: Dictionary = data.months[i]
		var row := _list_row("Month%d" % i)
		row.add_child(_line("MonthName", str(m.get("name", "")), func(t: String) -> void: m.name = t, true))
		row.add_child(_spin("Days", float(m.get("days", 30)), 1, 999, 1, func(v: float) -> void: m.days = int(v)))
		var fest := CheckBox.new()
		fest.name = "Festival"
		fest.text = "Festival"
		fest.tooltip_text = "Festival days between the months: the date shows the festival's name (festival formats)"
		fest.button_pressed = bool(m.get("festival", false))
		fest.toggled.connect(func(on: bool) -> void:
			m.festival = on
			_changed())
		row.add_child(fest)
		row.add_child(_button("Up", move_month.bind(i, -1)))
		row.add_child(_button("Down", move_month.bind(i, 1)))
		row.add_child(_button("Remove", remove_month.bind(i)))
	form.add_child(_button("Add month", func() -> void: add_month(), "AddMonth"))

	_section("Eras")
	for i in (data.eras as Array).size():
		var e: Dictionary = data.eras[i]
		var row := _list_row("Era%d" % i)
		var from := _spin("FromYear", float(e.get("from_year", 1)), -99999, 99999, 1, func(v: float) -> void: e.from_year = int(v))
		from.tooltip_text = "From year"
		row.add_child(from)
		row.add_child(_line("EraName", str(e.get("name", "")), func(t: String) -> void: e.name = t, true))
		var abbr := _line("EraAbbr", str(e.get("abbr", "")), func(t: String) -> void: e.abbr = t)
		abbr.placeholder_text = "Abbr."
		abbr.custom_minimum_size = Vector2(70, 0)
		row.add_child(abbr)
		row.add_child(_button("Remove", remove_era.bind(i)))
	form.add_child(_button("Add era", func() -> void: add_era(), "AddEra"))

	_section("Date formats")
	form.add_child(_label(FORMAT_HINT, UISkin.V_MUTED))
	_row("Day", _line("Format", str(data.get("format", "")), func(t: String) -> void: data.format = t, true))
	_row("Festival", _line("FestivalFormat", str(data.get("festival_format", "")), func(t: String) -> void: data.festival_format = t, true))
	_row("Festival days", _line("FestivalDayFormat", str(data.get("festival_day_format", "")), func(t: String) -> void: data.festival_day_format = t, true))

	_section("Moons")
	for i in (data.moons as Array).size():
		var mo: Dictionary = data.moons[i]
		var row := _list_row("Moon%d" % i)
		row.add_child(_line("MoonName", str(mo.get("name", "")), func(t: String) -> void: mo.name = t, true))
		var cycle := _spin("Cycle", float(mo.get("cycle_days", 28.0)), 0.1, 100000, 0.01, func(v: float) -> void: mo.cycle_days = v)
		cycle.suffix = "d"
		cycle.tooltip_text = "Days from one new moon to the next"
		row.add_child(cycle)
		var offset := _spin("Offset", float(mo.get("offset_days", 0.0)), -100000, 100000, 0.01, func(v: float) -> void: mo.offset_days = v)
		offset.tooltip_text = "The day of a new moon"
		row.add_child(offset)
		var pick := ColorPickerButton.new()
		pick.name = "MoonColor"
		pick.edit_alpha = false
		pick.custom_minimum_size = Vector2(40, 0)
		pick.color = Color.from_string(str(mo.get("color", "#d8d8d8")), Color.WHITE)
		pick.color_changed.connect(func(col: Color) -> void:
			mo.color = "#" + col.to_html(false)
			_changed())
		row.add_child(pick)
		row.add_child(_button("Remove", remove_moon.bind(i)))
	form.add_child(_button("Add moon", func() -> void: add_moon(), "AddMoon"))


func _section(text: String) -> void:
	var l := _label(text, UISkin.V_HEADING)
	form.add_child(l)


func _row(text: String, field: Control) -> void:
	var row := HBoxContainer.new()
	row.name = text.validate_node_name().replace(" ", "") + "Row"
	var l := _label(text, UISkin.V_MUTED)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	form.add_child(row)


func _list_row(row_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	form.add_child(row)
	return row


func _label(text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	return l


func _line(node_name: String, text: String, set_value: Callable, expand := false) -> LineEdit:
	var e := LineEdit.new()
	e.name = node_name
	e.text = text
	if expand:
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(func(t: String) -> void:
		set_value.call(t)
		_changed())
	return e


func _spin(node_name: String, value: float, lo: float, hi: float, step: float, set_value: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.name = node_name
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.allow_greater = true
	s.allow_lesser = lo < 0
	s.value = value
	s.value_changed.connect(func(v: float) -> void:
		set_value.call(v)
		_changed())
	return s


func _button(text: String, action: Callable, node_name := "") -> Button:
	var b := Button.new()
	b.name = node_name if node_name != "" else text
	b.text = text
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(action)
	return b
