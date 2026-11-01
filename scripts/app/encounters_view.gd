class_name EncountersView
extends PanelContainer
## The encounters of a timeline (TASK-35, DM): by session (newest first) and in-world date.
## Pick one to rename it or move its range (event ids), or to replay it on its map.

var timeline: Timeline
var events_log: EventLog
var calendar: WorldCalendar
var assets: AssetCache
var encounters: Encounters
var tree: Tree
var name_edit: LineEdit
var start_spin: SpinBox
var end_spin: SpinBox
var replay_view: ReplayView
var _list_box: VBoxContainer
var _selected := ""


func _ready() -> void:
	theme_type_variation = UISkin.V_PAGE
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 8)
	add_child(_list_box)
	var head := Label.new()
	head.text = "Encounters"
	head.theme_type_variation = UISkin.V_HEADING
	_list_box.add_child(head)
	var hint := Label.new()
	hint.text = "Each ended combat is saved here. Pick one to rename it, change its range or replay it."
	hint.theme_type_variation = UISkin.V_MUTED
	_list_box.add_child(hint)
	tree = Tree.new()
	tree.name = "Encounters"
	tree.hide_root = true
	tree.columns = 3
	tree.column_titles_visible = true
	for i in 3:
		tree.set_column_title(i, ["Encounter", "When", "Events"][i])
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(func() -> void:
		var it := tree.get_selected()
		if it != null and it.get_metadata(0) != null:
			select(str(it.get_metadata(0))))
	tree.item_activated.connect(func() -> void:
		if _selected != "":
			replay(_selected))
	_list_box.add_child(tree)
	var edit := HBoxContainer.new()
	edit.add_theme_constant_override("separation", 6)
	_list_box.add_child(edit)
	name_edit = LineEdit.new()
	name_edit.name = "EncounterName"
	name_edit.placeholder_text = "Name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t: String) -> void: apply())
	edit.add_child(name_edit)
	edit.add_child(_muted("events"))
	start_spin = _spin(edit)
	edit.add_child(_muted("to"))
	end_spin = _spin(edit)
	_button(edit, "Save", "Rename / change the range (the events stay as they are)", apply)
	_button(edit, "Replay", "Play it back on its map", func() -> void:
		if _selected != "":
			replay(_selected)).name = "Replay"
	refresh()


## Reads encounters.json (after adding any finished combat that is missing) and fills the list.
func refresh() -> void:
	if tree == null or timeline == null:
		return
	encounters = Encounters.open(timeline.folder)
	if events_log != null:
		encounters.sync(events_log, timeline)
	tree.clear()
	var root := tree.create_item()
	for group: Array in encounters.by_session():
		var s := tree.create_item(root)
		s.set_text(0, "Between sessions" if int(group[0]) <= 0 else "Session %d" % int(group[0]))
		s.set_selectable(0, false)
		s.set_selectable(1, false)
		s.set_selectable(2, false)
		for e: Dictionary in group[1]:
			var it := tree.create_item(s)
			it.set_text(0, str(e.name))
			it.set_text(1, calendar.format_moment(int(e.get("day", 0)), int(e.get("time", 0))) if calendar != null else "day %d" % int(e.get("day", 0)))
			it.set_text(2, "#%d – #%d" % [int(e.start_event), int(e.end_event)])
			it.set_metadata(0, str(e.id))
			if str(e.id) == _selected:
				it.select(0)
	if root.get_child_count() == 0:
		var none := tree.create_item(root)
		none.set_text(0, "No encounters yet: start and end a combat at the table.")
		none.set_selectable(0, false)


func select(id: String) -> void:
	_selected = id
	var e := encounters.get_encounter(id)
	name_edit.text = str(e.get("name", ""))
	var top := float(events_log.events.back().id) if events_log != null and not events_log.events.is_empty() else 1.0
	for s: SpinBox in [start_spin, end_spin]:
		s.max_value = maxf(top, 1.0)
	start_spin.value = int(e.get("start_event", 1))
	end_spin.value = int(e.get("end_event", 1))


## Saves the name and range of the selected encounter.
func apply() -> bool:
	if _selected == "":
		return false
	var ok := encounters.rename(_selected, name_edit.text)
	var e := encounters.get_encounter(_selected)
	if int(start_spin.value) != int(e.start_event) or int(end_spin.value) != int(e.end_event):
		ok = encounters.set_range(_selected, int(start_spin.value), int(end_spin.value), events_log) and ok
	refresh()
	return ok


## Replays an encounter in place of the list.
func replay(id: String) -> ReplayView:
	var e := encounters.get_encounter(id)
	if e.is_empty():
		return null
	if replay_view == null:
		replay_view = ReplayView.new()
		replay_view.name = "Replay"
		replay_view.assets = assets
		replay_view.close_requested.connect(func() -> void:
			replay_view.hide()
			_list_box.show())
		add_child(replay_view)
	_list_box.hide()
	replay_view.show()
	replay_view.open(EncounterReplay.new(timeline, events_log, e))
	return replay_view


func _spin(row: Control) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 1
	s.max_value = 1
	s.step = 1
	s.custom_minimum_size = Vector2(90, 0)
	row.add_child(s)
	return s


func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UISkin.V_MUTED
	return l


func _button(row: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	row.add_child(b)
	return b
