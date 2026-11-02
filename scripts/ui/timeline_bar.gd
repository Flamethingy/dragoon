class_name TimelineBar
extends DockPanel
## The timeline bar (TASK-82, Nico's sketch 2026-11-02): the timeline's moments as boxes on a
## line, by in-world time, over all maps. It behaves like the chat (DockPanel): docked at the
## top of the table at first, it can dock at a side or the bottom, float, or pop out into its
## own window (also by dragging it past the program's edge).
## Nico 2026-11-02: no head, so it stays slim: dragged by its background (away from the line)
## it docks, floats or pops out; a right click away from the boxes has the menu (back to now,
## fit, Show everyone). A double click on the line (or Home) goes back to now; the DM drags
## the orange triangle, the current time (TimelineLine).

signal cursor_changed(at: int)  ## the moment looked at, in seconds; -1 = now (live)
signal list_requested(ids: Array)  ## DM: that moment's events in the Timeline list
signal show_toggled(on: bool)  ## DM: Show everyone (TASK-84)
signal time_requested(minutes: int, reason: String)  ## DM moved the current time on: time passes
## DM moved the current time back (TASK-86, Nico 2026-11-02), confirmed: everything after event
## `upto` is cut off, then `minutes` pass (to where it was let go).
signal rewind_requested(upto: int, minutes: int)
signal restore_requested(rewind_id: int)  ## DM: bring a cut-off branch back, confirmed  ## DM: that moment's events in the Timeline list

var sync: TimelineSync
var line: TimelineLine
var showing_all := false  ## DM: everyone's timeline follows mine (TASK-84)
var menu: PopupMenu  ## right click: back to now, fit, Show everyone
var shown := false  ## a player: the DM is showing me a moment (no cursor of my own)
var dm := false  ## the DM's bar: set back, restore, change the past
var confirm: ConfirmationDialog
var _confirmed := Callable()


func _init() -> void:
	super()
	name = "TimelineBar"
	section = "timeline"
	window_title = "Dragoon · Timeline"
	window_min = Vector2i(600, 140)
	allow_top = true
	place = {"dock": "top", "side": 10, "bottom": 4, "top": 2, "r": [8, 3, 32, 3], "window": false}
	thin = true  # docked at a side it is as slim as at the top
	drag_anywhere = true
	title_label.text = "Timeline"
	_head.visible = false
	menu = PopupMenu.new()
	menu.name = "Menu"
	menu.add_item("Back to now", 0)
	menu.add_item("Fit everything", 1)
	menu.add_check_item("Show everyone", 2)
	menu.id_pressed.connect(_on_menu)
	add_child(menu)
	confirm = ConfirmationDialog.new()
	confirm.name = "Confirm"
	confirm.confirmed.connect(func() -> void:
		if _confirmed.is_valid():
			_confirmed.call())
	add_child(confirm)
	line = TimelineLine.new()
	line.name = "Line"
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.cursor_moved.connect(_on_cursor)
	line.list_requested.connect(func(m: Dictionary) -> void: list_requested.emit(m.get("events", [])))
	body.add_child(line)
	line.future_requested.connect(func(minutes: int) -> void: time_requested.emit(minutes, ""))
	line.split_requested.connect(_ask_split)
	line.background_input.connect(_head_input)  # its background moves it, like a title
	line.menu_requested.connect(open_menu)
	line.restore_requested.connect(func(id: int, cut: int) -> void:
		if dm:
			_ask("Bring back the %d cut-off moment%s? They count again, after what happened since." % [cut, "" if cut == 1 else "s"],
				func() -> void: restore_requested.emit(id)))


## The bar's menu at `at` (screen position).
func open_menu(at: Vector2) -> void:
	menu.set_item_disabled(menu.get_item_index(0), line.cursor_at < 0 or shown)
	var i := menu.get_item_index(2)
	menu.set_item_checked(i, showing_all)
	menu.set_item_disabled(i, not dm)
	menu.position = Vector2i(at)
	menu.reset_size()
	menu.popup()


func _on_menu(id: int) -> void:
	match id:
		0:
			if not shown:
				line.set_cursor(-1)
		1:
			line.fit()
		2:
			if dm:
				toggle_show()


## DM: Show everyone on / off (TASK-84).
func toggle_show() -> void:
	showing_all = not showing_all
	show_toggled.emit(showing_all)


## Follows a TimelineSync (the table's) and the calendar for the dates.
func follow(s: TimelineSync, calendar: WorldCalendar) -> void:
	sync = s
	line.calendar = calendar
	if not s.changed.is_connected(_refresh):
		s.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if sync == null:
		return
	line.set_data(sync.data)
	_show_when()


## Show everyone (TASK-84): the DM's button shows it; a player's own cursor is off while on.
func set_showing(on: bool, dm: bool) -> void:
	if dm:
		showing_all = on
		_show_when()
		return
	shown = on
	line.cursor_locked = on
	_show_when()


func _ask(text: String, then: Callable) -> void:
	confirm.dialog_text = text
	_confirmed = then
	confirm.popup_centered(Vector2i(420, 120))


## The DM let go of the current time at `at`, before now: split the timeline there?
func split_at(at: int) -> Dictionary:
	var found := {}
	for m: Dictionary in line.moments():
		if int(m.at) > at:
			break
		found = m
	return found


func _ask_split(at: int) -> void:
	var m := split_at(at)
	if m.is_empty() or not dm:
		return  # before everything: nothing to keep
	var minutes := maxi(0, (at - int(m.at)) / 60)
	var when := line.calendar.format_moment(int(m.day), int(m.time)) if line.calendar != null else "day %d" % int(m.day)
	_ask("Split the timeline here (%s%s)?\nEverything after it is cut off for everyone and the current time goes back. It stays as a faded branch you can bring back." % [when, (" + " + line.duration_text(minutes)) if minutes > 0 else ""],
		func() -> void: rewind_requested.emit(int(m.last_id), minutes))


func _on_cursor(at: int) -> void:
	_show_when()
	cursor_changed.emit(at)


## The last event of the moment the cursor is on: -1 = now, 0 = before everything (TASK-83).
func cursor_event() -> int:
	if line.cursor_at < 0:
		return -1
	var found := 0
	for m: Dictionary in line.moments():
		if int(m.at) > line.cursor_at:
			break
		found = int(m.last_id)
	return found


## The cursor as a stretch between two moments, for the table in real time (Nico 2026-11-02):
## {upto: the last event of the moment at or before it (-1 now, 0 before everything), toward:
## the last event of the next one (-1: now), f: how far between them (0..1)}.
## The events that had happened by the cursor (id -> true; every moment up to it), or {}
## at now. The chat follows with it (Nico 2026-11-02).
func happened() -> Dictionary:
	var at := line.cursor_at
	if at < 0:
		return {}
	var out := {}
	for m: Dictionary in line.moments():
		if int(m.at) > at:
			break
		for id: Variant in m.get("events", []):
			out[int(id)] = true
	out[-1] = true  # not empty: something is looked back at, even before the first moment
	return out


func segment() -> Dictionary:
	var at := line.cursor_at
	var ms := line.moments()
	if at < 0 or ms.is_empty():
		return {"upto": -1, "toward": -2, "f": 0.0}
	var i := -1
	for m: Dictionary in ms:
		if int(m.at) > at:
			break
		i += 1
	if i < 0:
		return {"upto": 0, "toward": int(ms[0].last_id), "f": 0.0}
	var a: Dictionary = ms[i]
	var next_at := line.now_at()
	var toward := -1
	if i + 1 < ms.size():
		next_at = int(ms[i + 1].at)
		toward = int(ms[i + 1].last_id)
	var f := clampf(float(at - int(a.at)) / maxf(1.0, float(next_at - int(a.at))), 0.0, 1.0)
	return {"upto": int(a.last_id), "toward": toward, "f": f}


func _show_when() -> void:
	var ms := line.moments()
	if line.cursor_at < 0:
		line.hint = "The DM is showing everyone: now" if shown else ("Showing everyone" if showing_all else "")
		line.queue_redraw()
		return
	var i := -1
	for m: Dictionary in ms:
		if int(m.at) > line.cursor_at:
			break
		i = int(m.index)
	line.hint = ("The DM is showing: %s" if shown else ("Showing everyone: %s" if showing_all else "looking back: %s")) % (line.moment_text(ms[i]).get_slice("\n", 0) if i >= 0 else "before the beginning")
	line.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_HOME and is_visible_in_tree():
		if not shown:
			line.set_cursor(-1)
