class_name TimelineLine
extends Control
## The line of the timeline bar (TASK-82, Nico's sketch 2026-11-02): white boxes for the
## moments (TimelineMoments) placed by in-world time, a triangle at the line for the cursor,
## "now" at the end, sessions as light bands with their real date. Each box carries the colour
## of its map (two fights on two maps at once stay apart).
## Laid out along "u" (time) and across "v": left to right when the bar is wide, bottom to
## top when it is tall (docked at a side; Nico 2026-11-02). Text stays upright.
## Wheel: zoom around the mouse; right or middle drag (or Shift+wheel): pan. Left drag moves
## the cursor freely (the table follows in real time) and it snaps to the nearest box when let
## go; past now it is now, or for the DM (can_extend) the future: letting go there passes that
## much time. Hovering a box shows what changed; right click on a box asks for its events.

signal cursor_moved(at: int)  ## -1 = now (live)
signal list_requested(moment: Dictionary)
signal restore_requested(rewind_id: int, moments: int)  ## right click on a cut-off branch (DM, TASK-86)
signal future_requested(minutes: int)  ## DM let go of the cursor in the future: pass this much time

const MARGIN := 18.0
const BOX := Vector2(12, 18)  ## along, across
const BRANCH_UP := 17.0  ## cut-off branches float this far beside the line
const MAX_LINES := 14  ## a hover shows at most this many changes
const SNAP := 8.0  ## pixels: a click this close to a box picks it
const MIN_SPAN := 30.0  ## seconds along the line, at most zoomed in
const SHADOW := Color(0, 0, 0, 0.18)
const NOW_COLOR := Color(0.9, 0.5, 0.1)
## Steps the future snaps to (minutes), the finest one at least FUTURE_PX pixels long.
const FUTURE_STEPS := [1, 5, 10, 15, 30, 60, 120, 240, 480, 1440, 10080]
const FUTURE_PX := 10.0

var ink := Color(0.3, 0.2, 0.16)  ## the theme's text colour (set in _ready)

var data := {}
var calendar: WorldCalendar
var view_from := 0.0  ## seconds at the start of the line
var span := 3600.0  ## seconds along the line
var cursor_at := -1  ## seconds, -1 = now
var cursor_locked := false  ## the DM is showing everyone a moment (TASK-84): no scrubbing
var can_extend := false  ## the DM: dragging past now goes into the future (passes time)
var future_at := -1  ## while dragging into the future: that time in seconds
var _pan_from := Vector2.ZERO
var _pan_view := 0.0
var _panning := false
var _scrubbing := false
var _fitted := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(54, 54)
	tooltip_text = " "  # so _get_tooltip is asked
	clip_contents = true


func _ready() -> void:
	ink = get_theme_color("font_color", "Label")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_data(d: Dictionary) -> void:
	var was_at_end := _now_u() <= _len() - MARGIN + 1.0 and _now_u() >= _len() * 0.5
	data = d
	if not _fitted and not moments().is_empty():
		fit()
	elif cursor_at < 0 and was_at_end and _now_u() > _len() - MARGIN:
		view_from = now_at() - span * 0.85  # following the present: keep "now" in view
	queue_redraw()


func moments() -> Array:
	return data.get("moments", [])


func now_at() -> int:
	return int(data.get("now_at", 0))


func hours_per_day() -> int:
	return int(data.get("hours_per_day", 24))


## Everything from the first moment to now in view (the DM gets room for the future).
func fit() -> void:
	var ms := moments()
	if ms.is_empty():
		return
	var first := float(ms[0].at)
	var last := float(maxi(now_at(), int(ms.back().at)))
	span = maxf((last - first) * (1.25 if can_extend else 1.1), MIN_SPAN * 4)
	view_from = first - span * 0.04
	_fitted = true
	queue_redraw()


# --- Along and across ---------------------------------------------------------------------------

## Bottom to top when the bar is tall (docked at a side), else left to right.
func vertical() -> bool:
	return size.y > size.x * 1.3


func _len() -> float:
	return size.y if vertical() else size.x


func _thick() -> float:
	return size.x if vertical() else size.y


## The point at `u` along the line and `v` across it.
func _p(u: float, v: float) -> Vector2:
	return Vector2(v, size.y - u) if vertical() else Vector2(u, v)


## A position as (u along, v across).
func _uv(pos: Vector2) -> Vector2:
	return Vector2(size.y - pos.y, pos.x) if vertical() else pos


func _rect(u: float, v: float, du: float, dv: float) -> Rect2:
	var a := _p(u, v)
	var b := _p(u + du, v + dv)
	return Rect2(a, b - a).abs()


func _width() -> float:
	return maxf(_len() - MARGIN * 2, 1.0)


## Where time `at` (seconds) is along the line.
func x_of(at: float) -> float:
	return MARGIN + (at - view_from) / span * _width()


func at_of(u: float) -> float:
	return view_from + (u - MARGIN) / _width() * span


func _now_u() -> float:
	return x_of(now_at())


## Where the line runs across the bar.
func _line_y() -> float:
	return roundf(minf(_thick() * 0.42, 44.0))


## The moment whose box is under (or nearest within SNAP of) `u`, else -1.
func box_at(u: float) -> int:
	var best := -1
	var best_d := SNAP + BOX.x * 0.5
	for m: Dictionary in moments():
		var d := absf(x_of(float(m.at)) - u)
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
	var len := _len()
	# sessions: light bands with their real-world date
	for s: Dictionary in data.get("sessions", []):
		var x0 := x_of(float(s.start_at))
		var x1 := x_of(float(now_at() if int(s.end_at) < 0 else int(s.end_at)))
		if x1 < 0 or x0 > len:
			continue
		draw_rect(_rect(x0, 2, maxf(x1 - x0, 2.0), _thick() - 4), Color(ink, 0.06))
		draw_line(_p(x0, 2), _p(x0, _thick() - 2), Color(ink, 0.4), 1.0)
		var label := "Session %d · %s" % [int(s.session), _real_text(str(s.start_real))]
		if vertical():  # at the far edge, just above where the session starts
			draw_string(font, Vector2(4, size.y - x0 - 5), label, HORIZONTAL_ALIGNMENT_RIGHT, _thick() - 10, fs - 1, Color(ink, 0.65))
		else:
			draw_string(font, Vector2(x0 + BOX.x, 11), label, HORIZONTAL_ALIGNMENT_LEFT, maxf(x1 - x0 - 6, 60), fs - 1, Color(ink, 0.65))
	# the line, with end ticks like the sketch
	var first := clampf(x_of(float(moments()[0].at)) if not moments().is_empty() else MARGIN, MARGIN * 0.5, len)
	var right := clampf(_now_u(), 0, len - MARGIN * 0.5)
	draw_line(_p(0, y + 1), _p(len, y + 1), SHADOW, 3.0)
	draw_line(_p(0, y), _p(len, y), ink, 2.0)
	for u: float in [first, right]:
		draw_line(_p(u, y - 10), _p(u, y + 10), ink, 2.0)
	_draw_ticks(y, font, fs)
	# boxes (one per moment; neighbours closer than a few pixels share one)
	var last_u := -1000.0
	for m: Dictionary in moments():
		var u := x_of(float(m.at))
		if u < -BOX.x or u > len + BOX.x or u - last_u < 3.0:
			continue
		last_u = u
		var r := _rect(u - BOX.x * 0.5, y - BOX.y * 0.5, BOX.x, BOX.y)
		draw_rect(r.grow(1.5), ink)
		draw_rect(r, Color.WHITE if not m.get("combat", false) else Color(1, 0.86, 0.8))
		if m.get("edited", false):  # the DM changed it afterwards (TASK-85)
			draw_circle(_p(u, y - BOX.y * 0.5 - 4), 2.5, NOW_COLOR)
		var maps: Array = m.get("maps", [])
		for i in maps.size():  # the map colour(s) as a strip on the far side
			var w := BOX.x / maps.size()
			draw_rect(_rect(u - BOX.x * 0.5 + w * i, y + BOX.y * 0.5 - 4, w, 4), map_color(str(maps[i])))
	_draw_branches(y)
	# the current time: an orange triangle (Nico 2026-11-02); dragged into the future it goes
	# along, with how much time that is. Looking back: a black one at the cursor.
	var nu := x_of(float(future_at)) if future_at >= 0 else _now_u()
	if future_at >= 0:
		var text := "+" + duration_text(future_minutes())
		var at := Vector2(nu + 8, y - 8) if not vertical() else _p(nu, y + 16) + Vector2(0, 4)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1, NOW_COLOR)
	draw_colored_polygon(_triangle(nu, y), NOW_COLOR)
	if cursor_at >= 0:
		draw_colored_polygon(_triangle(x_of(float(cursor_at)), y), ink)


func _triangle(u: float, y: float) -> PackedVector2Array:
	return PackedVector2Array([_p(u, y + 11), _p(u - 6, y + 20), _p(u + 6, y + 20)])


## Cut-off branches (TASK-86): faded small boxes beside the line, from where it was set back.
func _draw_branches(y: float) -> void:
	var by := y - BRANCH_UP
	for b: Dictionary in data.get("branches", []):
		var ms: Array = b.moments
		if ms.is_empty():
			continue
		var u0 := x_of(float(b.at))
		var u1 := x_of(float(ms.back().at))
		draw_dashed_line(_p(u0, y - 2), _p(u0 + 6, by), Color(ink, 0.35), 1.0, 3.0)
		draw_dashed_line(_p(u0 + 6, by), _p(maxf(u1, u0 + 6), by), Color(ink, 0.35), 1.0, 3.0)
		for m: Dictionary in ms:
			var u := x_of(float(m.at))
			if u < -BOX.x or u > _len() + BOX.x:
				continue
			var r := _rect(u - 4, by - 5, 8, 10)
			draw_rect(r, Color(1, 1, 1, 0.45))
			draw_rect(r, Color(ink, 0.35), false, 1.0)


## The cut-off box under the local position `pos`: {rewind, moment, count} or {}.
func branch_box_at(pos: Vector2) -> Dictionary:
	var at := _uv(pos)
	if absf(at.y - (_line_y() - BRANCH_UP)) > 8:
		return {}
	for b: Dictionary in data.get("branches", []):
		for m: Dictionary in b.moments:
			if absf(x_of(float(m.at)) - at.x) <= 6:
				return {"rewind": int(b.rewind), "moment": m, "count": (b.moments as Array).size()}
	return {}


## Time labels beside the line, as fine as the zoom allows (rounds, minutes, hours, days).
func _draw_ticks(y: float, font: Font, fs: int) -> void:
	var day := hours_per_day() * 3600
	var steps := [6, 60, 600, 3600, 6 * 3600, day, 7 * day, 30 * day, 365 * day]
	var step := steps.back() as int
	for s: int in steps:
		if float(s) / span * _width() >= (60.0 if vertical() else 90.0):
			step = s
			break
	var t := floori(view_from / step) * step
	var end := view_from + span
	var n := 0
	while t <= end and n < 200:
		n += 1
		var u := x_of(t)
		if u >= 0:
			draw_line(_p(u, y + 4), _p(u, y + 8), Color(ink, 0.5), 1.0)
			var at := Vector2(u + 3, size.y - 3) if not vertical() else _p(u, y + 26) + Vector2(0, 4)
			draw_string(font, at, _tick_text(t, step, day), HORIZONTAL_ALIGNMENT_LEFT, 120, fs, Color(ink, 0.75))
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


## "2 days 3 h", "1 h 30 min", "10 min".
func duration_text(minutes: int) -> String:
	var per_day := hours_per_day() * 60
	var parts: PackedStringArray = []
	if minutes >= per_day:
		var d := minutes / per_day
		parts.append("%d day%s" % [d, "" if d == 1 else "s"])
		minutes -= d * per_day
	if minutes >= 60:
		parts.append("%d h" % (minutes / 60))
		minutes %= 60
	if minutes > 0 or parts.is_empty():
		parts.append("%d min" % minutes)
	return " ".join(parts)


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
	if lines.size() > MAX_LINES:  # a long prep: the first ones and how many more
		lines = lines.slice(0, MAX_LINES) + ["… and %d more" % (lines.size() - MAX_LINES)]
	return head + "\n" + ("\n".join(PackedStringArray(lines)) if not lines.is_empty() else "(nothing to see)")


func _get_tooltip(pos: Vector2) -> String:
	var cut := branch_box_at(pos)
	if not cut.is_empty():
		return "Cut off (the timeline was set back) · right click: bring it back\n" + moment_text(cut.moment)
	var at := _uv(pos)
	var i := box_at(at.x)
	if i < 0 or absf(at.y - _line_y()) > BOX.y:
		return ""
	return moment_text(moments()[i])


# --- Input ------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		var at := _uv(b.position)
		if b.pressed and b.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if b.shift_pressed:
				view_from += span * (0.1 if b.button_index == MOUSE_BUTTON_WHEEL_DOWN else -0.1)
				queue_redraw()
			else:
				zoom(1.0 / 1.25 if b.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25, at.x)
			accept_event()
		elif b.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if b.pressed:
				_panning = true
				_pan_from = b.position
				_pan_view = view_from
			else:
				var click := _panning and b.button_index == MOUSE_BUTTON_RIGHT and b.position.distance_to(_pan_from) < 4
				var cut := branch_box_at(b.position)
				if click and not cut.is_empty():
					restore_requested.emit(int(cut.rewind), int(cut.count))
				elif click:
					var i := box_at(at.x)
					if i >= 0:
						list_requested.emit(moments()[i])
				_panning = false
			accept_event()
		elif b.button_index == MOUSE_BUTTON_LEFT:
			if b.pressed and not cursor_locked:
				_scrubbing = true
				drag_to(at.x)
			elif not b.pressed and _scrubbing:
				_scrubbing = false
				let_go(at.x)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			view_from = _pan_view - (_uv(mm.position).x - _uv(_pan_from).x) / _width() * span
			queue_redraw()
			accept_event()
		elif _scrubbing:
			drag_to(_uv(mm.position).x)
			accept_event()


## Zooms by `factor` (< 1: in) keeping the time at `u` where it is.
func zoom(factor: float, u: float) -> void:
	var at := at_of(u)
	span = clampf(span * factor, MIN_SPAN, 400.0 * 365 * hours_per_day() * 3600)
	view_from = at - (u - MARGIN) / _width() * span
	queue_redraw()


## While dragging: the cursor follows the mouse freely (the table shows the time between two
## moments). Past now: now, or for the DM the future.
func drag_to(u: float) -> void:
	var ms := moments()
	var at := int(at_of(u))
	future_at = -1
	if ms.is_empty() or at >= now_at():
		if can_extend and not ms.is_empty() and at > now_at() and future_minutes_at(at) > 0:
			future_at = at
			queue_redraw()
		set_cursor(-1)
		return
	set_cursor(maxi(at, int(ms[0].at) - 1))


## Let go: in the future, that is the new current time (DM); in the past the cursor stays where
## it is let go (Nico 2026-11-02: no snapping back), on a box: that box.
func let_go(u: float) -> void:
	if future_at >= 0:
		var minutes := future_minutes()
		future_at = -1
		queue_redraw()
		set_cursor(-1)
		if minutes > 0:
			future_requested.emit(minutes)
		return
	if cursor_at >= 0 and box_at(u) >= 0:
		scrub_to(u)


## The minutes the future cursor stands for, snapped to a step the zoom can show.
func future_minutes() -> int:
	return future_minutes_at(future_at) if future_at >= 0 else 0


func future_minutes_at(at: int) -> int:
	var raw := float(at - now_at()) / 60.0
	var per_px := span / 60.0 / _width()
	var step := int(FUTURE_STEPS.back())
	for s: int in FUTURE_STEPS:
		if float(s) / per_px >= FUTURE_PX:
			step = s
			break
	return maxi(int(roundf(raw / step)), 1 if raw > 0 else 0) * step  # just past now: one step


## Moves the cursor to the box at `u` (or, `nearest`, the box closest to that time); past the
## last moment: now.
func scrub_to(u: float, nearest := false) -> void:
	var ms := moments()
	if ms.is_empty():
		set_cursor(-1)
		return
	var i := box_at(u)
	var at := int(at_of(u))
	if i < 0 and nearest:
		var best := INF
		for m: Dictionary in ms:
			var d := absf(float(int(m.at) - at))
			if d < best:
				best = d
				i = int(m.index)
	if i >= 0:
		at = int(ms[i].at)
	if at >= now_at() or (i < 0 and u >= _now_u() - SNAP):
		at = -1
	elif i < 0 and at < int(ms[0].at):
		at = int(ms[0].at) - 1  # before everything
	set_cursor(at)


func set_cursor(at: int) -> void:
	if at == cursor_at:
		queue_redraw()
		return
	cursor_at = at
	queue_redraw()
	cursor_moved.emit(at)
