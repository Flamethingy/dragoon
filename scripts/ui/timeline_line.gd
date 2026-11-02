class_name TimelineLine
extends Control
## The line of the timeline bar (TASK-82, Nico's sketch 2026-11-02): white boxes for the
## moments (TimelineMoments) placed by in-world time, a triangle under the line for the
## cursor, "now" at the end, sessions as light bands with their real date. Each box carries
## the colour of its map (two fights on two maps at once stay apart).
## Wheel: zoom around the mouse; right or middle drag (or Shift+wheel): pan; left click/drag:
## move the cursor (snaps to a box near the mouse; past the last one it is "now").
## Hovering a box shows what changed; right click on a box asks for its events in the list.

signal cursor_moved(at: int)  ## -1 = now (live)
signal list_requested(moment: Dictionary)

const MARGIN := 18.0
const BOX := Vector2(12, 18)
const SNAP := 8.0  ## pixels: a click this close to a box picks it
const MIN_SPAN := 30.0  ## seconds across the line, at most zoomed in
const SHADOW := Color(0, 0, 0, 0.18)

var ink := Color(0.3, 0.2, 0.16)  ## the theme's text colour (set in _ready)

var data := {}
var calendar: WorldCalendar
var view_from := 0.0  ## seconds at the left end of the line
var span := 3600.0  ## seconds across the line
var cursor_at := -1  ## seconds, -1 = now
var _pan_from := Vector2.ZERO
var _pan_view := 0.0
var _panning := false
var _scrubbing := false
var _fitted := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(200, 54)
	tooltip_text = " "  # so _get_tooltip is asked
	clip_contents = true


func _ready() -> void:
	ink = get_theme_color("font_color", "Label")


func set_data(d: Dictionary) -> void:
	var was_at_end := _now_x() <= size.x - MARGIN + 1.0 and _now_x() >= size.x * 0.5
	data = d
	if not _fitted and not moments().is_empty():
		fit()
	elif cursor_at < 0 and was_at_end and _now_x() > size.x - MARGIN:
		view_from = now_at() - span * 0.9  # following the present: keep "now" in view
	queue_redraw()


func moments() -> Array:
	return data.get("moments", [])


func now_at() -> int:
	return int(data.get("now_at", 0))


func hours_per_day() -> int:
	return int(data.get("hours_per_day", 24))


## Everything from the first moment to now in view.
func fit() -> void:
	var ms := moments()
	if ms.is_empty():
		return
	var first := float(ms[0].at)
	var last := float(maxi(now_at(), int(ms.back().at)))
	span = maxf((last - first) * 1.1, MIN_SPAN * 4)
	view_from = first - span * 0.04
	_fitted = true
	queue_redraw()


func _width() -> float:
	return maxf(size.x - MARGIN * 2, 1.0)


func x_of(at: float) -> float:
	return MARGIN + (at - view_from) / span * _width()


func at_of(x: float) -> float:
	return view_from + (x - MARGIN) / _width() * span


func _now_x() -> float:
	return x_of(now_at())


func _line_y() -> float:
	return roundf(size.y * 0.42)


## The moment whose box is under (or nearest within SNAP of) `x`, else -1.
func box_at(x: float) -> int:
	var best := -1
	var best_d := SNAP + BOX.x * 0.5
	for m: Dictionary in moments():
		var d := absf(x_of(float(m.at)) - x)
		if d < best_d:
			best_d = d
			best = int(m.index)
	return best


## Colour of a map (stable: from its id).
static func map_color(map: String) -> Color:
	if map == "":
		return Color(0.75, 0.75, 0.75)
	return Color.from_hsv(float(absi(map.hash()) % 360) / 360.0, 0.6, 0.95)


# --- Drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	var y := _line_y()
	var font := get_theme_default_font()
	var fs := 11
	# sessions: light bands with their real-world date
	for s: Dictionary in data.get("sessions", []):
		var x0 := x_of(float(s.start_at))
		var x1 := x_of(float(now_at() if int(s.end_at) < 0 else int(s.end_at)))
		if x1 < 0 or x0 > size.x:
			continue
		draw_rect(Rect2(x0, 2, maxf(x1 - x0, 2.0), size.y - 4), Color(ink, 0.06))
		draw_line(Vector2(x0, 2), Vector2(x0, size.y - 2), Color(ink, 0.4), 1.0)
		var label := "Session %d · %s" % [int(s.session), _real_text(str(s.start_real))]
		draw_string(font, Vector2(x0 + BOX.x, 11), label, HORIZONTAL_ALIGNMENT_LEFT, maxf(x1 - x0 - 6, 60), fs - 1, Color(ink, 0.65))
	# the line, with end ticks like the sketch
	var left := clampf(x_of(float(moments()[0].at)) if not moments().is_empty() else MARGIN, MARGIN * 0.5, size.x)
	var right := clampf(_now_x(), 0, size.x - MARGIN * 0.5)
	draw_line(Vector2(0, y + 1), Vector2(size.x, y + 1), SHADOW, 3.0)
	draw_line(Vector2(0, y), Vector2(size.x, y), ink, 2.0)
	for x: float in [left, right]:
		draw_line(Vector2(x, y - 10), Vector2(x, y + 10), ink, 2.0)
	_draw_ticks(y, font, fs)
	# boxes (one per moment; neighbours closer than a few pixels share one)
	var last_x := -1000.0
	for m: Dictionary in moments():
		var x := x_of(float(m.at))
		if x < -BOX.x or x > size.x + BOX.x or x - last_x < 3.0:
			continue
		last_x = x
		var r := Rect2(Vector2(x - BOX.x * 0.5, y - BOX.y * 0.5), BOX)
		draw_rect(r.grow(1.5), ink)
		draw_rect(r, Color.WHITE if not m.get("combat", false) else Color(1, 0.86, 0.8))
		var maps: Array = m.get("maps", [])
		for i in maps.size():  # the map colour(s) as a strip at the bottom
			var w := BOX.x / maps.size()
			draw_rect(Rect2(r.position.x + w * i, r.end.y - 4, w, 4), map_color(str(maps[i])))
	# now, and the cursor (triangle under the line)
	var nx := _now_x()
	draw_line(Vector2(nx, y - 13), Vector2(nx, y + 13), Color(0.9, 0.5, 0.1), 2.0)
	var cx := x_of(float(cursor_at)) if cursor_at >= 0 else nx
	var tri := PackedVector2Array([Vector2(cx, y + 11), Vector2(cx - 6, y + 20), Vector2(cx + 6, y + 20)])
	draw_colored_polygon(tri, ink)


## Time labels under the line, as fine as the zoom allows (rounds, minutes, hours, days).
func _draw_ticks(y: float, font: Font, fs: int) -> void:
	var day := hours_per_day() * 3600
	var steps := [6, 60, 600, 3600, 6 * 3600, day, 7 * day, 30 * day, 365 * day]
	var step := steps.back() as int
	for s: int in steps:
		if float(s) / span * _width() >= 90.0:
			step = s
			break
	var t := floori(view_from / step) * step
	var end := view_from + span
	var n := 0
	while t <= end and n < 200:
		n += 1
		var x := x_of(t)
		if x >= 0:
			draw_line(Vector2(x, y + 4), Vector2(x, y + 8), Color(ink, 0.5), 1.0)
			draw_string(font, Vector2(x + 3, size.y - 3), _tick_text(t, step, day), HORIZONTAL_ALIGNMENT_LEFT, 120, fs, Color(ink, 0.75))
		t += step


func _tick_text(t: int, step: int, day: int) -> String:
	var d := floori(float(t) / day)
	var minutes := (t - d * day) / 60
	if calendar == null:
		return "day %d %02d:%02d" % [d, minutes / 60, minutes % 60] if step < day else "day %d" % d
	if step >= day:
		return calendar.format_day(d)
	if step < 60:
		return "%s +%ds" % [calendar.format_time(minutes), (t - d * day) % 60]
	return calendar.format_time(minutes) if minutes > 0 or step < 3600 else calendar.format_day(d)


static func _real_text(iso: String) -> String:
	# "2026-11-02T19:42:10Z" -> "2026-11-02 19:42"
	return iso.replace("T", " ").left(16) if iso != "" else ""


## The hover text of a moment: when, where, and what changed.
func moment_text(m: Dictionary) -> String:
	var head := ""
	if calendar != null:
		head = calendar.format_moment(int(m.day), int(m.time))
	else:
		head = "Day %d" % int(m.day)
	if int(m.get("round", 0)) > 0:
		head += " · Round %d" % int(m.round)
	var names: Dictionary = data.get("map_names", {})
	var maps: PackedStringArray = []
	for map: String in m.get("maps", []):
		maps.append(str(names.get(map, map)))
	if not maps.is_empty():
		head += " · " + ", ".join(maps)
	var lines: Array = m.get("lines", [])
	return head + "\n" + ("\n".join(PackedStringArray(lines)) if not lines.is_empty() else "(nothing to see)")


func _get_tooltip(at: Vector2) -> String:
	var i := box_at(at.x)
	if i < 0 or absf(at.y - _line_y()) > BOX.y:
		return ""
	return moment_text(moments()[i])


# --- Input ------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.pressed and b.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if b.shift_pressed:
				view_from += span * (0.1 if b.button_index == MOUSE_BUTTON_WHEEL_DOWN else -0.1)
			else:
				zoom(1.0 / 1.25 if b.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25, b.position.x)
			accept_event()
		elif b.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if b.pressed:
				_panning = true
				_pan_from = b.position
				_pan_view = view_from
			else:
				if _panning and b.button_index == MOUSE_BUTTON_RIGHT and b.position.distance_to(_pan_from) < 4:
					var i := box_at(b.position.x)
					if i >= 0:
						list_requested.emit(moments()[i])
				_panning = false
			accept_event()
		elif b.button_index == MOUSE_BUTTON_LEFT:
			_scrubbing = b.pressed
			if b.pressed:
				scrub_to(b.position.x)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			view_from = _pan_view - (mm.position.x - _pan_from.x) / _width() * span
			queue_redraw()
			accept_event()
		elif _scrubbing:
			scrub_to(mm.position.x)
			accept_event()


## Zooms by `factor` (< 1: in) keeping the time under `x` where it is.
func zoom(factor: float, x: float) -> void:
	var at := at_of(x)
	span = clampf(span * factor, MIN_SPAN, 400.0 * 365 * hours_per_day() * 3600)
	view_from = at - (x - MARGIN) / _width() * span
	queue_redraw()


## Moves the cursor to the box near `x` (or that time); past the last moment: now.
func scrub_to(x: float) -> void:
	var i := box_at(x)
	var at := int(moments()[i].at) if i >= 0 else int(at_of(x))
	var ms := moments()
	if ms.is_empty() or at >= now_at() or (i < 0 and x >= _now_x() - SNAP):
		at = -1
	elif i < 0 and at < int(ms[0].at):
		at = int(ms[0].at) - 1  # before everything
	set_cursor(at)


func set_cursor(at: int) -> void:
	if at == cursor_at:
		return
	cursor_at = at
	queue_redraw()
	cursor_moved.emit(at)
