class_name CalendarView
extends Window
## The calendar (TASK-112, Nico 2026-11-05): replaces the timeline bar on the main screen. A
## month of the world's calendar (its weekdays, months, festivals) with today marked and the
## story's entries on their days: sessions, time passing (travel, rests ...). Everyone sees it,
## but only the entries they may know (NetTable.calendar_for). The DM passes time in big steps
## here (hours, a long rest, days, with a reason). Entries come one kind at a time (Nico: "we'll
## add them one by one"); travel will become a route on the map later.
## Its own window (TASK-113), opened by the date at the top of the table.

const CREAM := Color("#f6eadb")
const INK := Color("#3b2a1a")
const KIND_COLORS := {"session": Color("#7c5498"), "time": Color("#46709f"), "travel": Color("#3f7a4c"), "rest": Color("#a5762f")}

var table: NetTable
var calendar: WorldCalendar
var view := {}  ## {day, time, entries: [{day, time, kind, text}]}
var shown_year := 0
var shown_month := 0

var _title: Label
var _grid: GridContainer
var _today: Label
var _dm_row: HBoxContainer
var _days: SpinBox
var _reason: LineEdit


func _init() -> void:
	name = "CalendarView"
	title = "Dragoon · Calendar"
	visible = false
	force_native = DockPanel.native_windows
	transient = true
	theme = UISkin.theme()
	size = Vector2i(980, 720)
	min_size = Vector2i(640, 480)
	close_requested.connect(hide)
	var bg := Panel.new()
	bg.theme_type_variation = UISkin.V_PAGE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 12
	box.offset_right = -16
	box.offset_bottom = -12
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(_button("‹", func() -> void: _step(-1), "Prev"))
	_title = Label.new()
	_title.name = "Month"
	_title.add_theme_font_size_override("font_size", 24)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(_button("›", func() -> void: _step(1), "Next"))
	head.add_child(_button("Today", show_today, "TodayButton"))
	_today = Label.new()
	_today.name = "Now"
	_today.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_today)
	_grid = GridContainer.new()
	_grid.name = "Days"
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_grid)
	_dm_row = HBoxContainer.new()  # DM: time passes in big steps
	_dm_row.name = "PassTime"
	box.add_child(_dm_row)
	var l := Label.new()
	l.text = "Pass time:"
	_dm_row.add_child(l)
	_dm_row.add_child(_button("+1 hour", func() -> void: _pass(60, ""), "PassHour"))
	_dm_row.add_child(_button("+8 hours (long rest)", func() -> void: _pass(480, "long rest"), "PassRest"))
	_dm_row.add_child(_button("+1 day", func() -> void: _pass(1440, ""), "PassDay"))
	_days = SpinBox.new()
	_days.name = "Days"
	_days.min_value = 1
	_days.max_value = 365
	_days.value = 3
	_days.suffix = "days"
	_dm_row.add_child(_days)
	_reason = LineEdit.new()
	_reason.name = "Reason"
	_reason.placeholder_text = "why (e.g. travel to Red Fang)"
	_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dm_row.add_child(_reason)
	_dm_row.add_child(_button("Pass", func() -> void: _pass(int(_days.value) * 1440, _reason.text.strip_edges()), "PassDays"))


## Opens it at today's month.
func open() -> void:
	refresh()
	show_today()
	if not visible:
		popup_centered()
	grab_focus()


## Takes the table's calendar and entries (the DM's own; a player asks the host).
func refresh() -> void:
	if table == null:
		return
	calendar = table.notes.calendar if table.notes != null else null
	_dm_row.visible = table.is_dm()
	if table.is_dm():
		set_view(table.calendar_for(Reveal.DM))
	else:
		table.request_calendar()


func set_view(v: Dictionary) -> void:
	var first := view.is_empty()
	view = v
	if first:
		show_today()
	else:
		_build()


func show_today() -> void:
	if calendar == null or calendar.days_per_year <= 0:
		_build()
		return
	var d := calendar.date_of(int(view.get("day", 0)))
	shown_year = int(d.year)
	shown_month = int(d.month)
	_build()


## The day number of the 1st of `month` in `year`.
static func month_start(c: WorldCalendar, year: int, month: int) -> int:
	var day := (year - c.first_year) * c.days_per_year
	for i in month:
		day += int(c.months[i].days)
	return day


## The entries of the events a player (or the DM) may see: sessions, time passing, long rests.
static func entries_of(events: Array, dm: bool) -> Array:
	var out := []
	var session := 0
	var rested := {}
	for e: Dictionary in events:
		var d: Dictionary = e.get("data", {})
		if not dm and (bool(d.get("hidden", false)) or bool(d.get("dm_only", false))):
			continue
		var s := int(e.get("session", 0))
		if s > session:
			session = s
			out.append({"day": int(e.day), "time": int(e.get("time", -1)), "kind": "session", "text": "Session %d" % s})
		match str(e.type):
			"time.advanced":
				var minutes := (int(e.day) - int(d.get("from_day", e.day))) * 1440 + maxi(int(e.get("time", 0)), 0) - maxi(int(d.get("from_time", 0)), 0)
				var reason := str(d.get("reason", "")).strip_edges()
				if minutes <= 0 or reason in ["combat", "round", "turn"]:
					continue  # the small steps of a combat aren't the story's time
				var kind := "travel" if reason.to_lower().contains("travel") else "rest" if reason.to_lower().contains("rest") else "time"
				var span := "%d day%s" % [minutes / 1440, "" if minutes / 1440 == 1 else "s"] if minutes >= 1440 else "%d h" % ceili(minutes / 60.0) if minutes >= 60 else "%d min" % minutes
				out.append({"day": int(d.get("from_day", e.day)), "time": int(d.get("from_time", -1)), "kind": kind,
					"text": "%s: %s" % [span, reason.left(1).to_upper() + reason.substr(1) if reason != "" else "time passes"]})
			"rest.taken":
				if str(d.get("kind", "long")) == "long" and not rested.has(int(e.day)):
					rested[int(e.day)] = true
					out.append({"day": int(e.day), "time": int(e.get("time", -1)), "kind": "rest", "text": "Long rest"})
	return out


func _step(by: int) -> void:
	if calendar == null or calendar.months.is_empty():
		return
	shown_month += by
	if shown_month < 0:
		shown_month = calendar.months.size() - 1
		shown_year -= 1
	elif shown_month >= calendar.months.size():
		shown_month = 0
		shown_year += 1
	_build()


func _pass(minutes: int, reason: String) -> void:
	if table == null or not table.is_dm():
		return
	table.advance_clock(minutes, reason)
	refresh()
	show_today()


func _build() -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	if calendar == null or calendar.months.is_empty():
		_title.text = "No calendar"
		return
	var today := int(view.get("day", 0))
	_today.text = "Today: %s" % calendar.format_moment(today, int(view.get("time", -1)))
	var month: Dictionary = calendar.months[shown_month]
	var era := ""
	for e: Dictionary in calendar.eras:
		if shown_year >= int(e.from_year):
			era = str(e.abbr)
	_title.text = ("%s %d %s" % [month.name, shown_year, era]).strip_edges()
	var cols := calendar.weekdays.size() if not calendar.weekdays.is_empty() and not bool(month.festival) else mini(int(month.days), 7)
	_grid.columns = maxi(cols, 1)
	var start := month_start(calendar, shown_year, shown_month)
	if not calendar.weekdays.is_empty() and not bool(month.festival):
		for w: String in calendar.weekdays:
			var h := Label.new()
			h.text = w
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_theme_color_override("font_color", INK)
			_grid.add_child(h)
		for i in posmod(start + calendar.weekday_of_day_0, calendar.weekdays.size()):  # the 1st on its weekday
			var gap := Control.new()
			gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_grid.add_child(gap)
	var by_day := {}
	for en: Dictionary in view.get("entries", []):
		by_day.get_or_add(int(en.day), []).append(en)
	for i in int(month.days):
		_grid.add_child(_day_cell(start + i, i + 1, start + i == today, by_day.get(start + i, [])))


func _day_cell(day: int, number: int, is_today: bool, entries: Array) -> Control:
	var cell := PanelContainer.new()
	cell.name = "Day%d" % number
	cell.set_meta("day", day)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, 64)
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM.darkened(0.06) if not is_today else Color("#f3d9a8")
	sb.border_color = Color("#c47a2c") if is_today else Color(INK, 0.25)
	sb.set_border_width_all(3 if is_today else 1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	cell.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	cell.add_child(col)
	var n := Label.new()
	n.text = str(number)
	n.add_theme_color_override("font_color", INK)
	col.add_child(n)
	var tip := PackedStringArray()
	for en: Dictionary in entries:
		var l := Label.new()
		l.text = str(en.text)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", KIND_COLORS.get(str(en.kind), INK))
		l.set_meta("kind", str(en.kind))
		col.add_child(l)
		tip.append(("%s  " % calendar.format_time(int(en.time)) if int(en.get("time", -1)) >= 0 else "") + str(en.text))
	cell.tooltip_text = "\n".join(tip)
	return cell


func _button(text: String, action: Callable, node_name := "") -> Button:
	var b := Button.new()
	b.text = text
	if node_name != "":
		b.name = node_name
	b.pressed.connect(action)
	return b
