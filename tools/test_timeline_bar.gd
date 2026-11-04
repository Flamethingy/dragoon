extends SceneTree
## Headless check of the timeline bar (TASK-82): the host's moments reach the player (without
## what happened under fog of war), new events and undos update them live, the bar docks at
## the top (pushing a side dock down), zooms, pans, shows a box's changes on hover, scrubs
## and asks for a moment's events.
## godot --headless --path . -s tools/test_timeline_bar.gd

const PORT := 47833
const ADDRESS := "127.0.0.1:47833"
const DIR := "user://test_timeline_bar"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	var dm := _table("DM", "dm")
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.my_pc == BORIN and not bob.timeline_sync.data.is_empty())
	var start := (dm.timeline_sync.data.moments as Array).size()
	_check(start == (bob.timeline_sync.data.moments as Array).size(), "Bob got the moments when he joined (%d)" % start)

	# new events: a clock step and a move -> a new moment everywhere
	var log := dm.event_log
	log.advance_time(log.day, maxi(log.time, 0) + 60, "test hour")
	log.move_token(BORIN, dm.grid.map_id, Vector2i(1, 1), Vector2i(3, 1))
	await _until(func() -> bool: return (bob.timeline_sync.data.moments as Array).size() == start + 1)
	var last: Dictionary = (bob.timeline_sync.data.moments as Array).back()
	_check(" ".join(last.lines).contains("moves 2 squares"), "Bob sees the new moment's summary (%s)" % [last.lines])
	_check(" ".join(last.lines).contains("1 hour passes (test hour)"), "and the time passing")
	_check(int(bob.timeline_sync.data.now_at) >= int(last.at), "now is at (or after) the last moment")

	# fog of war: a creature on a fogged map shows to the DM only
	dm.edit_map({"fog": true})
	await _frames(5)
	log.advance_time(log.day, log.time + 10, "sneaking")
	log.move_token("creatures/test-spy", dm.grid.map_id, Vector2i(5, 5), Vector2i(6, 6))
	await _frames(10)
	var dm_last: Dictionary = (dm.timeline_sync.data.moments as Array).back()
	var bob_last: Dictionary = (bob.timeline_sync.data.moments as Array).back()
	_check(" ".join(dm_last.lines).contains("Test spy"), "the DM sees the spy (%s)" % [dm_last.lines])
	_check(not " ".join(bob_last.lines).contains("Test spy"), "Bob doesn't (%s)" % [bob_last.lines])
	dm.edit_map({"fog": false})

	# an undo rebuilds
	var hit := log.change_hp(BORIN, -4, 8, "trap")
	await _frames(5)
	_check(" ".join(((dm.timeline_sync.data.moments as Array).back()).lines).contains("takes 4 damage"), "the hit is there")
	log.undo(int(hit.id))
	await _frames(5)
	_check(not " ".join(((dm.timeline_sync.data.moments as Array).back()).lines).contains("takes 4 damage"), "after the undo it's gone")

	# the bar: docked at the top, a side panel below it
	var home := Control.new()
	home.size = Vector2(1600, 900)
	root.add_child(home)
	var side := DockPanel.new()
	side.place_file = DIR + "/panels.cfg"
	side.section = "side"
	side.place = {"dock": "right", "side": 10, "bottom": 7, "top": 3, "r": [30, 6, 12, 16], "window": false}
	home.add_child(side)
	var side_top := side.position.y
	var bar := TimelineBar.new()
	bar.place_file = DIR + "/panels.cfg"
	home.add_child(bar)
	bar.follow(dm.timeline_sync, dm.notes.calendar)
	await _frames(3)
	var cell := bar.cell()
	_check(bar.place.dock == "top" and absf(bar.position.y - DockPanel.TOP * cell.y) < 6 and bar.size.x > 1500, "the bar is docked at the top, full width (%s %s)" % [bar.position, bar.size])
	_check(side.position.y > side_top + cell.y * 1.5, "the side dock moved below it (%d -> %d)" % [side_top, side.position.y])
	bar.dock("float", Rect2i(8, 6, 30, 4))
	await _frames(2)
	_check(absf(side.position.y - side_top) < 2, "floating, the side dock gets its room back")
	bar.dock("top")
	await _frames(2)

	# the line: fit, boxes by time, hover, zoom, scrub, list
	var line := bar.line
	line.size = Vector2(1500, 60)
	line.fit()
	var ms := line.moments()
	_check(ms.size() >= 3, "the bar has the moments (%d)" % ms.size())
	var a: Dictionary = ms[ms.size() - 3]
	var b: Dictionary = ms[ms.size() - 2]
	_check(line.x_of(b.at) > line.x_of(a.at), "later moments sit further right")
	var tip := line._get_tooltip(Vector2(line.x_of(b.at), line._line_y()))
	_check(tip.contains("Borin") or tip.contains("hour"), "hovering a box shows what changed (%s)" % tip.replace("\n", " | "))
	var span := line.span
	line.zoom(0.5, line.x_of(b.at))
	_check(absf(line.span - span * 0.5) < 1.0 and absf(line.x_of(b.at) - line.x_of(b.at)) < 0.01, "zooming in keeps the time under the mouse")
	var seen := []
	bar.cursor_changed.connect(func(at: int) -> void: seen.append(at))
	line.scrub_to(line.x_of(a.at) + 2)
	_check(not seen.is_empty() and int(seen.back()) == int(a.at), "scrubbing snaps to a box (%s)" % [seen])
	_check(bar.line.hint.begins_with("looking back"), "the bar says we look back (%s)" % bar.line.hint)
	_check(not bar._head.visible, "no head: the bar stays slim")
	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.pressed = true
	dbl.double_click = true
	dbl.position = line._p(line.x_of(a.at) + 40, line._line_y())
	line._gui_input(dbl)
	_check(int(seen.back()) == -1 and line.cursor_at == -1, "a double click goes back to now")
	var asked := []
	bar.list_requested.connect(func(ids: Array) -> void: asked.append(ids))
	line.list_requested.emit(b)
	_check(asked.size() == 1 and asked[0] == b.events, "a box asks for its events in the list")

	# dragging: the cursor follows freely (the table between two moments), let go: it snaps
	line.size = Vector2(1500, 60)
	line.fit()
	ms = line.moments()
	var a2: Dictionary = ms[ms.size() - 3]
	var b2: Dictionary = ms[ms.size() - 2]
	var mid := (float(a2.at) + float(b2.at)) * 0.5
	line.drag_to(line.x_of(mid))
	_check(absi(line.cursor_at - int(mid)) <= 1, "dragging, the cursor isn't snapped (%d / %d)" % [line.cursor_at, int(mid)])
	var seg := bar.segment()
	_check(int(seg.upto) == int(a2.last_id) and int(seg.toward) == int(b2.last_id) and absf(float(seg.f) - 0.5) < 0.05, "it stands halfway between two moments (%s)" % [seg])
	line.let_go(line.x_of(mid + (float(b2.at) - float(a2.at)) * 0.3))
	var dropped := int(mid)  # where the last drag left it
	_check(line.cursor_at != int(b2.at) and line.cursor_at != int(a2.at) and absi(line.cursor_at - dropped) <= 1, "let go: it stays there (%d / %d)" % [line.cursor_at, dropped])
	line.let_go(line.x_of(float(b2.at)))
	_check(line.cursor_at == int(b2.at), "let go on a box: that box")
	line.set_cursor(-1)

	# a click moves the black cursor at once; the DM drags the orange current time (above the line)
	bar.dm = true
	line.can_extend = true
	bar.time_requested.connect(func(minutes: int, reason: String) -> void: dm.advance_clock(minutes, reason))
	var boxes := (dm.timeline_sync.data.moments as Array).size()
	var clock := log.day * 1440 + maxi(log.time, 0)
	line.span = 4 * 3600.0
	line.view_from = float(line.now_at()) - 3600.0
	var nu := line.x_of(float(line.now_at()))
	var looked := []
	bar.cursor_changed.connect(func(at: int) -> void: looked.append(at))
	_mouse(line, true, nu - 30)
	_mouse(line, false, nu - 30)
	_check(line.cursor_at >= 0 and not line.now_drag, "a click in the past: the black cursor goes there")
	_check(not looked.is_empty() and int(looked.back()) >= 0 and int(looked.back()) < line.now_at(), "and the bar tells the table a past time (TASK-89: %s)" % [looked])
	# TASK-89: a click on the black triangle itself (below the line) moves it too, and Home is now
	var cu := line.x_of(float(line.cursor_at))
	_mouse_at(line, true, cu - 60, line._line_y() + 16)
	_mouse_at(line, false, cu - 60, line._line_y() + 16)
	_check(line.cursor_at >= 0 and int(looked.back()) == line.cursor_at, "a click by the black triangle moves it there")
	var home_key := InputEventKey.new()
	home_key.keycode = KEY_HOME
	home_key.pressed = true
	bar._unhandled_key_input(home_key)
	_check(line.cursor_at == -1 and int(looked.back()) == -1, "Home: back to now")
	# the same docked at a side (vertical)
	var wide := line.size
	line.size = Vector2(160, 900)
	line.span = 4 * 3600.0
	line.view_from = float(line.now_at()) - 3600.0
	var vu := line.x_of(float(line.now_at())) - 30
	_mouse(line, true, vu)
	_mouse(line, false, vu)
	_check(line.vertical() and line.cursor_at >= 0 and int(looked.back()) == line.cursor_at, "docked at a side: a click looks back too")
	line.set_cursor(-1)
	line.size = wide
	_mouse(line, true, nu - 30)
	_motion(line, nu + 200)
	_check(line.cursor_at == -1 and not line.now_drag and line.future_minutes() == 0, "dragging the black one stops at now")
	_mouse(line, false, nu + 200)
	_check(log.day * 1440 + log.time == clock, "and no time passes")
	_check(line.on_now_handle(line._p(nu, line._line_y() - 15)) and not line.on_now_handle(line._p(nu, line._line_y() + 15)), "the orange handle is above the line")
	_handle(line, true, nu)
	_check(line.now_drag, "pressed on the orange triangle: the current time is picked up")
	_motion(line, line.x_of(float(line.now_at()) + 3600.0))
	_check(line.future_minutes() == 60, "moved on an hour (+%d min)" % line.future_minutes())
	_handle(line, false, line.x_of(float(line.now_at()) + 3600.0))
	await _frames(5)
	_check(log.day * 1440 + log.time == clock + 60, "let go: an hour passes")
	_check((dm.timeline_sync.data.moments as Array).size() == boxes, "no box yet: nothing happened (%d -> %d)" % [boxes, (dm.timeline_sync.data.moments as Array).size()])
	_check(int(dm.timeline_sync.data.now_at) >= (log.day * 1440 + log.time) * 60 - 1, "but now moved on")
	log.move_token(BORIN, dm.grid.map_id, Vector2i(3, 1), Vector2i(4, 1))
	await _frames(5)
	_check((dm.timeline_sync.data.moments as Array).size() == boxes + 1, "something happens: a new box")
	# the background (away from the line) moves the panel
	var moved_panel := []
	line.background_input.connect(func(e: InputEvent) -> void: moved_panel.append(e))
	_mouse_at(line, true, nu - 200, line.size.y - 2)
	_mouse_at(line, false, nu - 200, line.size.y - 2)
	_check(moved_panel.size() == 2 and line.cursor_at == -1, "a press on the background goes to the panel, not the cursor")
	# held and moved back: split the timeline (asked first)
	var splits := []
	bar.rewind_requested.connect(func(upto: int, minutes: int) -> void: splits.append([upto, minutes]))
	line.view_from = float(line.now_at()) - 3 * 3600.0
	var back_to: Dictionary = line.moments()[line.moments().size() - 2]
	_handle(line, true, line.x_of(float(line.now_at())))
	_motion(line, line.x_of(float(back_to.at) + 600.0))
	_handle(line, false, line.x_of(float(back_to.at) + 600.0))
	_check(bar.confirm.visible and bar.confirm.dialog_text.begins_with("Split the timeline"), "back in time: the DM is asked first (%s)" % bar.confirm.dialog_text)
	bar.confirm.confirmed.emit()
	_check(splits.size() == 1 and int(splits[0][0]) == int(back_to.last_id) and int(splits[0][1]) == 10, "yes: cut after that moment, the current time 10 min later (%s)" % [splits])
	bar.confirm.hide()
	line.can_extend = false
	nu = line.x_of(float(line.now_at()))
	_handle(line, true, nu)
	_check(not line.now_drag, "players can't move the current time")
	_handle(line, false, nu)

	# docked at a side: bottom to top
	line.size = Vector2(300, 900)
	line.fit()
	_check(line.vertical(), "tall: vertical")
	var mv: Dictionary = line.moments()[0]
	var u := line.x_of(float(mv.at))
	var p := line._p(u, line._line_y())
	_check(absf(p.y - (900.0 - u)) < 0.01 and absf(p.x - line._line_y()) < 0.01, "time runs from the bottom up (%s)" % p)
	_check(line._get_tooltip(p) != "", "hovering a box there works too")
	line.size = Vector2(1500, 60)
	_check(not line.vertical(), "wide: horizontal")

	# zoomed far out: the dates don't overlap (Nico 2026-11-02)
	for zoom_out in [1.0, 50.0, 2000.0, 100000.0]:
		line.fit()
		line.span *= zoom_out
		var font := line.get_theme_default_font()
		var ends := -INF
		var overlap := false
		var labels := 0
		for k: Dictionary in line.ticks(font, 11):
			if str(k.text) == "":
				continue
			labels += 1
			if float(k.u) + 3.0 < ends:
				overlap = true
			ends = float(k.u) + 3.0 + font.get_string_size(str(k.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_check(not overlap and labels >= 2, "zoomed out x%d: %d labels, none overlap" % [int(zoom_out), labels])
	line.fit()
	# the moons: full and new ones on the line when they have room, their phase in the hover
	var cal := WorldCalendar.for_world("")
	cal.moons = [{"name": "Silver", "cycle_days": 4.0, "offset_days": 0.0, "color": "#dddddd"}]
	var old_cal := line.calendar
	line.calendar = cal
	line.view_from = 0.0
	line.span = 20.0 * line.hours_per_day() * 3600.0
	var marks := line.moon_marks()
	_check(marks.size() >= 9 and marks.any(func(k: Dictionary) -> bool: return k.full and absf(float(k.day) - 2.0) < 0.01), "full moons every 4 days, half way (%d marks)" % marks.size())
	var tipm := line._get_tooltip(line._p(float(marks[1].u), line._line_y() + 15.0))
	_check(tipm.begins_with("Silver:"), "hovering a moon names it (%s)" % tipm.replace("\n", " | "))
	_check(line.moons_text(2 * line.hours_per_day() * 3600) == "Silver: Full", "the phase at a time (%s)" % line.moons_text(2 * line.hours_per_day() * 3600))
	line.span *= 1000.0
	_check(line.moon_marks().is_empty(), "zoomed far out the moons step aside")
	line.calendar = old_cal
	line.fit()
	# docked at a side the bar stays slim, the side panel sits beside it
	bar.dock("right")
	await _frames(2)
	_check(bar.size.x < cell.x * 3.5 and bar.size.y > 600, "at the right: slim and tall (%s)" % bar.size)
	_check(side.position.x + side.size.x <= bar.position.x + 1, "the other right panel sits beside it (%d / %d)" % [side.position.x + side.size.x, bar.position.x])
	bar.dock("top")
	await _frames(2)
	_check(side.position.x + side.size.x > bar.size.x - cell.x, "back at the top: the side panel gets its place back")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("timeline bar: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _mouse(line: TimelineLine, down: bool, u: float) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = line._p(u, line._line_y())
	line._gui_input(e)


func _mouse_at(line: TimelineLine, down: bool, u: float, v: float) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = line._p(u, v)
	line._gui_input(e)


## On the orange triangle (above the line).
func _handle(line: TimelineLine, down: bool, u: float) -> void:
	_mouse_at(line, down, u, line._line_y() - 15)


func _motion(line: TimelineLine, u: float) -> void:
	var e := InputEventMouseMotion.new()
	e.position = line._p(u, line._line_y())
	line._gui_input(e)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
