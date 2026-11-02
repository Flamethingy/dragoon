class_name TimelineView
extends PanelContainer
## The Timeline view in a session (TASK-33, DM): the timeline's history as a list of events,
## newest at the bottom, with the session, the in-world moment, who did it and what; events
## inherited from the parent before the fork are marked, undone ones struck through.
## A filter box narrows it by type, entity or writer. The DM can undo an event or correct its
## values (TASK-85): the original stays in the log, struck through; the correction takes
## its place in the timeline.

var event_log: EventLog
var timeline: Timeline
var calendar: WorldCalendar
var tree: Tree
var filter_edit: LineEdit
var heading: Label
## Only events with ids in this range (a moment of the timeline bar, TASK-82); (0, 0) = all.
var id_range := Vector2i.ZERO
var id_set := {}  ## or only these ids (a moment's events, TASK-85); empty = no such filter
var on_changed := Callable()  ## after an undo or a correction (the table shows it)
var undo_button: Button
var edit_button: Button
var editor: ConfirmationDialog
var _fields := {}  ## data key -> LineEdit while correcting
var _editing := 0
var _range_button: Button


func _ready() -> void:
	theme_type_variation = UISkin.V_PAGE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	heading = Label.new()
	heading.theme_type_variation = UISkin.V_HEADING
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	filter_edit = LineEdit.new()
	filter_edit.name = "Filter"
	filter_edit.placeholder_text = "Filter: hp, characters/aria, ann ..."
	filter_edit.custom_minimum_size = Vector2(260, 0)
	filter_edit.text_changed.connect(func(_t: String) -> void: refresh())
	head.add_child(filter_edit)
	_range_button = Button.new()
	_range_button.name = "AllEvents"
	_range_button.text = "Show all"
	_range_button.visible = false
	_range_button.pressed.connect(func() -> void: show_moment([]))
	head.add_child(_range_button)
	tree = Tree.new()
	tree.name = "Events"
	tree.columns = 6
	tree.hide_root = true
	tree.column_titles_visible = true
	for i in 6:
		tree.set_column_title(i, ["#", "Session", "When", "By", "What", "About"][i])
		tree.set_column_expand(i, i >= 4)
	tree.set_column_custom_minimum_width(0, 50)
	tree.set_column_custom_minimum_width(1, 70)
	tree.set_column_custom_minimum_width(2, 170)
	tree.set_column_custom_minimum_width(3, 80)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tree)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	undo_button = Button.new()
	undo_button.name = "Undo"
	undo_button.text = "Undo event"
	undo_button.tooltip_text = "The event stops counting (it stays in the log, struck through)"
	undo_button.pressed.connect(undo_selected)
	actions.add_child(undo_button)
	edit_button = Button.new()
	edit_button.name = "Edit"
	edit_button.text = "Correct values…"
	edit_button.tooltip_text = "Change what happened: a correction takes its place in the timeline"
	edit_button.pressed.connect(edit_selected)
	actions.add_child(edit_button)
	editor = ConfirmationDialog.new()
	editor.name = "Correct"
	editor.title = "Correct the event"
	editor.ok_button_text = "Correct"
	editor.confirmed.connect(_save_correction)
	add_child(editor)
	tree.item_selected.connect(_update_actions)
	if event_log != null:
		event_log.appended.connect(func(_e: Dictionary) -> void:
			if is_visible_in_tree():
				refresh())
	refresh()


func refresh() -> void:
	if tree == null:
		return
	tree.clear()
	var root := tree.create_item()
	if event_log == null:
		heading.text = "Timeline"
		return
	var info := timeline.info if timeline != null else {}
	var parent := str(info.get("parent", ""))
	heading.text = "Timeline · %s%s · %d events" % [info.get("name", ""), ("" if parent == "" else "  (fork of %s after #%d)" % [parent, int(info.get("fork_at", 0))]), event_log.events.size()]
	var f := filter_edit.text.strip_edges().to_lower()
	var own_from := event_log.inherited.size()
	for i in event_log.events.size():
		var e: Dictionary = event_log.events[i]
		if id_range != Vector2i.ZERO and (int(e.id) < id_range.x or int(e.id) > id_range.y):
			continue
		if not id_set.is_empty() and not id_set.has(int(e.id)):
			continue
		var about := str(e.entity)
		if timeline != null and "/" in about:
			about = "%s (%s)" % [timeline.name_of(about), about]
		var when := calendar.format_moment(int(e.day), int(e.time)) if calendar != null else "day %d" % e.day
		var cells := [str(e.id), "prep" if int(e.session) <= 0 else str(e.session), when, str(e.get("by", "")), _what(e), about]
		if f != "" and not " ".join(cells).to_lower().contains(f):
			continue
		var item := tree.create_item(root)
		item.set_metadata(0, int(e.id))
		for c in cells.size():
			item.set_text(c, cells[c])
		var muted := i < own_from or e.has("undoes") or event_log.is_undone(int(e.id))
		if muted:
			for c in cells.size():
				item.set_custom_color(c, Markdown.MUTED)
		if i < own_from:
			item.set_tooltip_text(0, "From the parent timeline, before the fork")
		elif event_log.is_undone(int(e.id)):
			item.set_tooltip_text(4, "Undone")
	var last := root.get_child(root.get_child_count() - 1) if root.get_child_count() > 0 else null
	if last != null:
		tree.scroll_to_item(last)
	_update_actions()


## The selected event's id (0 = none).
func selected_id() -> int:
	var it := tree.get_selected() if tree != null else null
	return int(it.get_metadata(0)) if it != null else 0


func _may_change(id: int) -> bool:
	if id <= 0 or event_log == null or id <= event_log.inherited.size():
		return false
	var e := event_log.get_event(id)
	return not e.is_empty() and not e.has("undoes") and not event_log.is_undone(id) and str(e.type) != "timeline.rewound"


func _update_actions() -> void:
	if undo_button == null:
		return
	var ok := _may_change(selected_id())
	undo_button.disabled = not ok
	edit_button.disabled = not ok or (event_log.get_event(selected_id()).get("data", {}) as Dictionary).is_empty()


## DM: the selected event stops counting.
func undo_selected() -> void:
	var id := selected_id()
	if _may_change(id):
		event_log.undo(id)
		_changed()


## DM: a form with the event's values to correct.
func edit_selected() -> void:
	var id := selected_id()
	if not _may_change(id):
		return
	_editing = id
	var e := event_log.get_event(id)
	for c in editor.get_children():
		if c is GridContainer:
			editor.remove_child(c)
			c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	_fields.clear()
	var data: Dictionary = e.data
	for key: String in data:
		if key == "corrects":
			continue
		var label := Label.new()
		label.text = key
		grid.add_child(label)
		var edit := LineEdit.new()
		edit.name = key
		edit.custom_minimum_size = Vector2(260, 0)
		edit.text = JSON.stringify(data[key]) if not data[key] is String else str(data[key])
		grid.add_child(edit)
		_fields[key] = edit
	editor.add_child(grid)
	editor.dialog_text = "#%d %s" % [id, _what(e)]
	editor.popup_centered(Vector2i(460, 0))


## The form's values: numbers stay numbers (ints where they were), lists and objects as JSON.
func correction_data() -> Dictionary:
	var old: Dictionary = event_log.get_event(_editing).get("data", {})
	var out := old.duplicate(true)
	out.erase("corrects")
	for key: String in _fields:
		var text := (_fields[key] as LineEdit).text
		var was: Variant = old.get(key)
		if was is String:
			out[key] = text
			continue
		var v: Variant = JSON.parse_string(text)
		if v == null and text.strip_edges() != "null":
			v = text
		if was is int and v is float:
			v = int(v)
		elif was is Array and v is Array:
			v = (v as Array).map(func(x: Variant) -> Variant: return int(x) if x is float and is_equal_approx(x, roundf(x)) else x)
		out[key] = v
	return out


func _save_correction() -> void:
	if _may_change(_editing):
		event_log.correct(_editing, correction_data())
		_changed()


func _changed() -> void:
	refresh()
	if on_changed.is_valid():
		on_changed.call()


## Shows only these events (a moment of the timeline bar); [] = all again.
func show_moment(ids: Array) -> void:
	id_set.clear()
	for x: Variant in ids:
		id_set[int(x)] = true
	id_range = Vector2i.ZERO
	if _range_button != null:
		_range_button.visible = not id_set.is_empty()
		_range_button.text = "Show all (now %d events of one moment)" % id_set.size() if not id_set.is_empty() else "Show all"
	refresh()


## Shows only the events first..last (a moment of the timeline bar); 0, 0 = all again.
func show_range(first: int, last: int) -> void:
	id_range = Vector2i(first, last)
	if _range_button != null:
		_range_button.visible = id_range != Vector2i.ZERO
		_range_button.text = "Show all (now #%d–#%d)" % [first, last] if id_range != Vector2i.ZERO else "Show all"
	refresh()


## A short text for an event: its type and the data that matters.
static func _what(e: Dictionary) -> String:
	var d: Dictionary = e.get("data", {})
	match str(e.type):
		"hp.changed":
			return "HP %+d → %d" % [int(d.get("delta", 0)), int(d.get("hp", 0))]
		"token.moved":
			return "moved to %s on %s" % [d.get("to", []), d.get("map", "")]
		"token.placed":
			return "placed at %s on %s" % [d.get("at", []), d.get("map", "")]
		"token.turned":
			return "turned %s on %s" % [str(d.get("facing", "")).to_upper(), d.get("map", "")]
		"sheet.changed":
			return "%s: %s → %s" % [d.get("path", ""), d.get("from"), d.get("to")]
		"dice.rolled":
			return "rolled %s: %s" % [d.get("roll", d.get("formula", "")), d.get("result", "")]
		"entity.created":
			return "created"
	return str(e.type)
