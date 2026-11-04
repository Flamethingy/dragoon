class_name TimelineLine
extends Control
## The line of the timeline bar (TASK-82, Nico's sketch 2026-11-02): white boxes for the
## moments (TimelineMoments) placed by in-world time, a triangle at the line for the cursor,
## "now" at the end, sessions as light bands with their real date. Each box carries the colour
## of its map (two fights on two maps at once stay apart).
## Laid out along "u" (time) and across "v": left to right when the bar is wide, bottom to
## top when it is tall (docked at a side; Nico 2026-11-02). Text stays upright.
## Wheel: zoom around the mouse; right or middle drag (or Shift+wheel): pan. Left click or
## drag on the line moves the black cursor (below it) at once: the table follows in real time;
## it stays where let go, and stops at now. Nico 2026-11-02: the DM drags the orange triangle
## (above the line), the current time: let go later on, that much time passes; earlier, the
## DM is asked to split the timeline there. A double click goes back to now. The rest of the
## bar (away from the line) moves the panel. Hovering a box shows what changed; right click
## on a box asks for its events, elsewhere for the bar's menu (fit, show everyone, now).

signal cursor_moved(at: int)  ## -1 = now (live)
signal list_requested(moment: Dictionary)
signal restore_requested(rewind_id: int, moments: int)  ## right click on a cut-off branch (DM, TASK-86)
signal future_requested(minutes: int)  ## DM let go of the current time later on: pass this much time
signal split_requested(at: int)  ## DM let go of the current time in the past: split the timeline there (asks first)
signal background_input(event: InputEvent)  ## a left drag away from the line: the panel moves (DockPanel)
signal menu_requested(at: Vector2)  ## right click away from the boxes (screen position)

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
var future_at := -1  ## while the current time is held: where it would go, in seconds
var now_drag := false  ## the DM drags the current time (the orange triangle)
var hint := ""  ## a short text in the corner (looking back, the DM showing ...)
var _moving_panel := false
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
	for k: Dictionary in moon_marks():  # the moons (Nico 2026-11-02): full ones filled, new ones a ring
		var c: Color = calendar.moon_color(int(k.moon))
		var at := _p(float(k.u), y + 15.0)
		if k.full:
			draw_circle(at, 3.2, c)
			draw_arc(at, 3.2, 0, TAU, 12, Color(ink, 0.6), 1.0)
		else:
			draw_arc(at, 3.0, 0, TAU, 12, c, 1.5)
	# the current time: an orange triangle (Nico 2026-11-02); dragged into the future it goes
	# along, with how much time that is. Looking back: a black one at the cursor.
	var nu := x_of(float(now_at() + future_minutes() * 60)) if now_drag else _now_u()
	if now_drag:
		var fm := future_minutes()
		var text := ("+" + duration_text(fm)) if fm >= 0 else ("−%s · split here?" % duration_text(-fm))
		var at := Vector2(nu + 8, y - 8) if not vertical() else _p(nu, y + 16) + Vector2(0, 4)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1, NOW_COLOR)
	draw_colored_polygon(_triangle(nu, y, -1.0, 1.25 if now_drag else 1.0), NOW_COLOR)  # above the line
	if cursor_at >= 0:  # TASK-89: a hairline across the line too, so it doesn't drown in the dates
		var cu := x_of(float(cursor_at))
		draw_line(_p(cu, y - 12.0), _p(cu, y + 12.0), ink, 2.0)
		draw_colored_polygon(_triangle(cu, y, 1.0, 1.3), ink)
	if hint != "":
		var hs := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1)
		var hp := Vector2(size.x - hs.x - 6, size.y - 4) if not vertical() else Vector2(4, 12)
		draw_string(font, hp, hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, fs - 1, Color(ink, 0.6))


## A triangle pointing at the line from below (`side` 1) or above (-1).
func _triangle(u: float, y: float, side: float, scale := 1.0) -> PackedVector2Array:
	var tip := y + 11.0 * side
	var base := tip + 9.0 * scale * side
	return PackedVector2Array([_p(u, tip), _p(u - 6 * scale, base), _p(u + 6 * scale, base)])


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
	var room := _thick() - (y + 24.0) - 2.0  # beside the line, past the black triangle (vertical)
	for k: Dictionary in ticks(font, fs):
		var u: float = k.u
		draw_line(_p(u, y + 4), _p(u, y + 8), Color(ink, 0.5), 1.0)
		if str(k.text) == "":
			continue
		var at := Vector2(u + 3, size.y - 3) if not vertical() else _p(u, y + 24) + Vector2(0, 4)
		draw_string(font, at, str(k.text), HORIZONTAL_ALIGNMENT_LEFT, 160.0 if not vertical() else maxf(room, 1.0), fs, Color(ink, 0.75))


## The ticks in view: [{u, text}], the finest step whose labels have room (Nico 2026-11-02:
## zoomed out nothing overlapped any more); a label that would still run into the one before
## is left out (its tick stays).
func ticks(font: Font = null, fs := 11) -> Array:
	if font == null:
		font = get_theme_default_font()
	var day := hours_per_day() * 3600
	var year := (calendar.days_per_year if calendar != null and calendar.days_per_year > 0 else 365) * day
	var steps := [6, 60, 600, 3600, 6 * 3600, day, 7 * day, 30 * day, year, 10 * year, 100 * year, 1000 * year]
	var step := steps.back() as int
	for s: int in steps:
		var gap := float(s) / span * _width()
		var need := fs + 10.0 if vertical() else font.get_string_size(_tick_text(floori(view_from / s) * s, s, day), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
		if gap >= maxf(need, 40.0):
			step = s
			break
	var out := []
	var t := floori(view_from / step) * step
	var end := view_from + span
	var free_from := -INF  # where the next label may start along the line
	while t <= end and out.size() < 200:
		var u := x_of(t)
		t += step
		if u < 0 or u > _len():
			continue
		var text := _tick_text(t - step, step, day)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if not vertical() else fs + 2.0
		var from := u + 3.0 if not vertical() else u - w * 0.5
		if from < free_from or (not vertical() and from + w > _len()):
			text = ""
		else:
			free_from = from + w + 8.0
		out.append({"u": u, "text": text})
	return out


func _tick_text(t: int, step: int, day: int) -> String:
	var d := floori(float(t) / day)
	var minutes := (t - d * day) / 60
	if calendar == null:
		return "day %d %02d:%02d" % [d, minutes / 60, minutes % 60] if step < day else "day %d" % d
	if step >= 30 * day:  # zoomed far out: the month or the year is enough
		var dt := calendar.date_of(d)
		var era := (" " + str(dt.era)) if str(dt.era) != "" else ""
		return ("%d%s" % [int(dt.year), era]) if step >= 300 * day else "%s %d" % [str(dt.month_name), int(dt.year)]
	if step >= day:
		var dd := calendar.date_of(d)
		return "%d. %s" % [int(dd.day), str(dd.month_name)]
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


## Full and new moons in view: [{u, moon (index), full (bool), day (float)}]; a moon whose
## cycle is too short for the zoom is left out.
func moon_marks() -> Array:
	var out := []
	if calendar == null or calendar.moons.is_empty():
		return out
	var day_s := float(hours_per_day() * 3600)
	var d0 := view_from / day_s
	var d1 := (view_from + span) / day_s
	for i in calendar.moons.size():
		var m: Dictionary = calendar.moons[i]
		var cycle := float(m.get("cycle_days", 0.0))
		if cycle <= 0.0 or cycle * day_s / span * _width() < 14.0:
			continue
		var k := floori((d0 - float(m.get("offset_days", 0.0))) / cycle)
		while out.size() < 400:
			var new_day := float(m.get("offset_days", 0.0)) + k * cycle
			if new_day > d1:
				break
			for half in 2:
				var d := new_day + cycle * 0.5 * half
				if d >= d0 and d <= d1:
					out.append({"u": x_of(d * day_s), "moon": i, "full": half == 1, "day": d})
			k += 1
	return out


## The moons at a time (seconds), as one line: "Silvermoon: Full · Ember: Waxing crescent".
func moons_text(at: int) -> String:
	if calendar == null or calendar.moons.is_empty():
		return ""
	var day_s := hours_per_day() * 3600
	var parts: PackedStringArray = []
	for mo: Dictionary in calendar.moons_at(floori(float(at) / day_s), posmod(at, day_s) / 60):
		parts.append("%s: %s" % [mo.name, mo.phase_name])
	return " · ".join(parts)


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
	var moons := moons_text(int(m.get("clock", m.at)))
	return head + ("\n☾ " + moons if moons != "" else "") + "\n" + ("\n".join(PackedStringArray(lines)) if not lines.is_empty() else "(nothing to see)")


func _get_tooltip(pos: Vector2) -> String:
	if _scrubbing or now_drag:
		return ""  # a tooltip popping up while the mouse is held still takes the press away (the hold)
	var cut := branch_box_at(pos)
	if not cut.is_empty():
		return "Cut off (the timeline was set back) · right click: bring it back\n" + moment_text(cut.moment)
	var at := _uv(pos)
	if absf(at.y - (_line_y() + 15.0)) <= 6.0:  # a moon mark
		for k: Dictionary in moon_marks():
			if absf(float(k.u) - at.x) <= 5.0:
				return "%s: %s moon\n%s" % [calendar.moons[int(k.moon)].name, "full" if k.full else "new", calendar.format_day(floori(float(k.day)))]
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
				var i := box_at(at.x) if absf(at.y - _line_y()) <= BOX.y else -1
				if click and not cut.is_empty():
					restore_requested.emit(int(cut.rewind), int(cut.count))
				elif click and i >= 0:
					list_requested.emit(moments()[i])
				elif click:
					menu_requested.emit(get_screen_transform() * b.position)  # fit, show everyone, now
				_panning = false
			accept_event()
		elif b.button_index == MOUSE_BUTTON_LEFT:
			if b.pressed and b.double_click and not cursor_locked:
				_scrubbing = false
				now_drag = false
				future_at = -1
				set_cursor(-1)
			elif b.pressed and can_extend and on_now_handle(b.position):
				_scrubbing = true  # the orange triangle: the current time (DM)
				now_drag = true
				drag_now(at.x)
			elif b.pressed and on_track(b.position) and not cursor_locked:
				_scrubbing = true
				drag_to(at.x)  # the black cursor goes there at once
			elif b.pressed:
				_moving_panel = true  # the bar's background: it moves the panel
				background_input.emit(event)
			elif _moving_panel:
				_moving_panel = false
				background_input.emit(event)
			elif _scrubbing:
				_scrubbing = false
				let_go(at.x)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _moving_panel:
			background_input.emit(event)
		elif _panning:
			view_from = _pan_view - (_uv(mm.position).x - _uv(_pan_from).x) / _width() * span
			queue_redraw()
			accept_event()
		elif _scrubbing:
			if now_drag:
				drag_now(_uv(mm.position).x)
			else:
				drag_to(_uv(mm.position).x)
			accept_event()
		else:
			var hand := can_extend and on_now_handle(mm.position)
			mouse_default_cursor_shape = (Control.CURSOR_VSIZE if vertical() else Control.CURSOR_HSIZE) if hand \
				else Control.CURSOR_ARROW if on_track(mm.position) else Control.CURSOR_MOVE


## On the orange triangle, the current time (beside the line, on the far side from the cursor).
func on_now_handle(pos: Vector2) -> bool:
	var uv := _uv(pos)
	var y := _line_y()
	return absf(uv.x - _now_u()) <= 10.0 and uv.y >= y - 26.0 and uv.y <= y - 4.0


## On the line's strip (boxes, the black cursor); the rest of the bar moves the panel.
func on_track(pos: Vector2) -> bool:
	var v := _uv(pos).y
	var y := _line_y()
	return v >= y - 26.0 and v <= y + 24.0


## The DM drags the current time (the orange triangle): to `u`, not before the first moment.
func drag_now(u: float) -> void:
	var ms := moments()
	var at := int(at_of(u))
	if not ms.is_empty():
		at = maxi(at, int(ms[0].at))
	future_at = at
	queue_redraw()


## Zooms by `factor` (< 1: in) keeping the time at `u` where it is.
func zoom(factor: float, u: float) -> void:
	var at := at_of(u)
	span = clampf(span * factor, MIN_SPAN, 400.0 * 365 * hours_per_day() * 3600)
	view_from = at - (u - MARGIN) / _width() * span
	queue_redraw()


## While dragging: the cursor follows the mouse freely (the table shows the time between two
## moments). Past now: now.
func drag_to(u: float) -> void:
	var ms := moments()
	var at := int(at_of(u))
	if ms.is_empty() or at >= now_at():
		set_cursor(-1)
		return
	set_cursor(maxi(at, int(ms[0].at) - 1))


## Let go: in the future, that is the new current time (DM); in the past the cursor stays where
## it is let go (Nico 2026-11-02: no snapping back), on a box: that box.
func let_go(u: float) -> void:
	if now_drag:
		var minutes := future_minutes()
		now_drag = false
		future_at = -1
		queue_redraw()
		set_cursor(-1)
		if minutes > 0:
			future_requested.emit(minutes)
		elif minutes < 0:
			split_requested.emit(now_at() + minutes * 60)
		return
	if cursor_at >= 0 and box_at(u) >= 0:
		scrub_to(u)


## The minutes the future cursor stands for, snapped to a step the zoom can show.
func future_minutes() -> int:
	return future_minutes_at(future_at) if now_drag else 0


func future_minutes_at(at: int) -> int:
	var raw := float(at - now_at()) / 60.0
	var per_px := span / 60.0 / _width()
	var step := int(FUTURE_STEPS.back())
	for s: int in FUTURE_STEPS:
		if float(s) / per_px >= FUTURE_PX:
			step = s
			break
	var n := int(roundf(raw / step))
	if raw > 0:
		n = maxi(n, 1)  # just past now: one step
	elif raw < 0:
		n = mini(n, -1)
	return n * step


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
