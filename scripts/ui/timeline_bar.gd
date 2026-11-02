class_name TimelineBar
extends DockPanel
## The timeline bar (TASK-82, Nico's sketch 2026-11-02): the timeline's moments as boxes on a
## line, by in-world time, over all maps. It behaves like the chat (DockPanel): docked at the
## top of the table at first, it can dock at a side or the bottom, float, or pop out into its
## own window (also by dragging it past the program's edge).
## The head shows the cursor's moment and "Now" to go back to the present; "Fit" shows it all.

signal cursor_changed(at: int)  ## the moment looked at, in seconds; -1 = now (live)
signal list_requested(ids: Array)  ## DM: that moment's events in the Timeline list
signal show_toggled(on: bool)  ## DM: Show everyone (TASK-84)
signal time_requested(minutes: int, reason: String)  ## DM: Pass time (the clock moves on: a new box)
signal rewind_requested(upto: int)  ## DM: set the timeline back to this moment (TASK-86), confirmed
signal restore_requested(rewind_id: int)  ## DM: bring a cut-off branch back, confirmed  ## DM: that moment's events in the Timeline list

var sync: TimelineSync
var line: TimelineLine
var when_label: Label
var now_button: Button
var show_button: Button  ## DM: everyone's timeline follows mine (TASK-84)
var shown := false  ## a player: the DM is showing me a moment (no cursor of my own)
var dm := false  ## the DM's bar: set back, restore, change the past
var back_button: Button  ## DM looking back: set the timeline back to here (TASK-86)
var time_button: MenuButton  ## DM at now: Pass time
## Pass time's choices: [text, minutes, reason]
const PASS_TIME := [["1 minute", 1, ""], ["10 minutes", 10, ""], ["1 hour", 60, ""], ["4 hours", 240, ""],
	["8 hours", 480, ""], ["1 day", 1440, ""], ["1 week", 10080, ""]]
var confirm: ConfirmationDialog
var _confirmed := Callable()


func _init() -> void:
	super()
	name = "TimelineBar"
	section = "timeline"
	window_title = "Dragoon · Timeline"
	window_min = Vector2i(600, 140)
	allow_top = true
	place = {"dock": "top", "side": 10, "bottom": 4, "top": 3, "r": [8, 3, 32, 4], "window": false}
	title_label.text = "Timeline"
	title_label.size_flags_horizontal = Control.SIZE_FILL
	when_label = Label.new()
	when_label.name = "When"
	when_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	when_label.add_theme_font_size_override("font_size", 12)
	when_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_child(when_label)
	_head.move_child(when_label, 1)
	now_button = _small_button("Now", "Back to the present (Home)", func() -> void: line.set_cursor(-1))
	now_button.visible = false
	_head.add_child(now_button)
	_head.move_child(now_button, 2)
	show_button = _small_button("Show everyone", "Every player's timeline follows yours (a flashback, a replay)", func() -> void:
		show_toggled.emit(show_button.button_pressed))
	show_button.toggle_mode = true
	show_button.visible = false
	_head.add_child(show_button)
	_head.move_child(show_button, 4)
	time_button = MenuButton.new()
	time_button.name = "PassTime"
	time_button.text = "Pass time"
	time_button.tooltip_text = "The in-world clock moves on (a new box on the timeline)"
	time_button.focus_mode = Control.FOCUS_NONE
	time_button.flat = false
	time_button.add_theme_font_size_override("font_size", 12)
	time_button.visible = false
	for i in PASS_TIME.size():
		time_button.get_popup().add_item(str(PASS_TIME[i][0]), i)
	time_button.get_popup().id_pressed.connect(func(i: int) -> void:
		time_requested.emit(int(PASS_TIME[i][1]), str(PASS_TIME[i][2])))
	_head.add_child(time_button)
	_head.move_child(time_button, 2)
	back_button = _small_button("Set back to here", "Cut off everything after this moment (it can be restored from the faded branch)", _ask_rewind)
	back_button.visible = false
	_head.add_child(back_button)
	_head.move_child(back_button, 3)
	confirm = ConfirmationDialog.new()
	confirm.name = "Confirm"
	confirm.confirmed.connect(func() -> void:
		if _confirmed.is_valid():
			_confirmed.call())
	add_child(confirm)
	var fit := _small_button("Fit", "Show the whole timeline", func() -> void: line.fit())
	_head.add_child(fit)
	_head.move_child(fit, 5)
	line = TimelineLine.new()
	line.name = "Line"
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.cursor_moved.connect(_on_cursor)
	line.list_requested.connect(func(m: Dictionary) -> void: list_requested.emit(m.get("events", [])))
	body.add_child(line)
	line.restore_requested.connect(func(id: int, cut: int) -> void:
		if dm:
			_ask("Bring back the %d cut-off moment%s? They count again, after what happened since." % [cut, "" if cut == 1 else "s"],
				func() -> void: restore_requested.emit(id)))


func _small_button(text: String, tip: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(pressed)
	return b


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
		show_button.set_pressed_no_signal(on)
		return
	shown = on
	line.cursor_locked = on
	now_button.visible = line.cursor_at >= 0 and not on
	_show_when()


func _ask(text: String, then: Callable) -> void:
	confirm.dialog_text = text
	_confirmed = then
	confirm.popup_centered(Vector2i(420, 120))


func _ask_rewind() -> void:
	var upto := cursor_event()
	if upto < 0:
		return
	_ask("Set the timeline back to %s?\nEverything after it is cut off for everyone (the clock goes back too). It stays as a faded branch you can bring back." % when_label.text.trim_prefix("looking back: ").trim_suffix(" · act at Now"),
		func() -> void: rewind_requested.emit(upto))


func _on_cursor(at: int) -> void:
	now_button.visible = at >= 0 and not shown
	back_button.visible = at >= 0 and dm
	time_button.visible = at < 0 and dm
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


func _show_when() -> void:
	var ms := line.moments()
	if line.cursor_at < 0:
		when_label.text = "The DM is showing everyone: now" if shown else "now · %d moments" % ms.size()
		return
	var i := -1
	for m: Dictionary in ms:
		if int(m.at) > line.cursor_at:
			break
		i = int(m.index)
	when_label.text = ("The DM is showing: %s" if shown else ("looking back: %s · changes go here" if dm else "looking back: %s · act at Now")) % (line.moment_text(ms[i]).get_slice("\n", 0) if i >= 0 else "before the beginning")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_HOME and is_visible_in_tree():
		if not shown:
			line.set_cursor(-1)
