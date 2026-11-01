class_name StartScreen
extends PanelContainer
## The app's start screen (TASK-33): host as DM (pick a world and a timeline, or make new
## ones), join as a player (name and address), or open the compendium without a session.
## The last used world, timeline, name and address are preselected (App keeps them).

signal host_requested(timeline_dir: String, port: int)
signal join_requested(address: String, player_name: String)
signal compendium_requested(timeline_dir: String)

var worlds_root := ""
var world_pick: OptionButton
var timeline_pick: OptionButton
var port_edit: LineEdit
var name_edit: LineEdit
var address_edit: LineEdit
var status: Label

var _worlds: Array[Dictionary] = []
var _timelines: Array[Dictionary] = []


func _ready() -> void:
	theme_type_variation = UISkin.V_COVER
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	center.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	page.add_child(col)
	var plate := PanelContainer.new()
	plate.theme_type_variation = UISkin.V_PLATE
	col.add_child(plate)
	var title := Label.new()
	title.text = "Dragoon"
	title.theme_type_variation = UISkin.V_PLATE_LABEL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	col.add_child(row)

	var host := _form(row, "Host as DM")
	host.add_child(_muted("World"))
	var wrow := HBoxContainer.new()
	host.add_child(wrow)
	world_pick = OptionButton.new()
	world_pick.name = "WorldPick"
	world_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_pick.item_selected.connect(func(_i: int) -> void: _fill_timelines(""))
	wrow.add_child(world_pick)
	_button(wrow, "New...", "A new world (with its start timeline, the Prologue)", _new_world_dialog).name = "NewWorld"
	host.add_child(_muted("Timeline"))
	var trow := HBoxContainer.new()
	host.add_child(trow)
	timeline_pick = OptionButton.new()
	timeline_pick.name = "TimelinePick"
	timeline_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(timeline_pick)
	_button(trow, "New...", "A new timeline: a fork of another one at a point of its history", _new_timeline_dialog).name = "NewTimeline"
	host.add_child(_muted("Port"))
	port_edit = LineEdit.new()
	port_edit.text = str(NetTable.DEFAULT_PORT)
	host.add_child(port_edit)
	_button(host, "Host as DM", "Open the table for this timeline", func() -> void:
		host_requested.emit(timeline_dir(), int(port_edit.text) if port_edit.text.is_valid_int() else NetTable.DEFAULT_PORT)).name = "Host"

	var join := _form(row, "Join as player")
	join.add_child(_muted("Your player name"))
	name_edit = LineEdit.new()
	name_edit.name = "PlayerName"
	join.add_child(name_edit)
	join.add_child(_muted("Address (ip:port)"))
	address_edit = LineEdit.new()
	address_edit.name = "Address"
	address_edit.text = "127.0.0.1:%d" % NetTable.DEFAULT_PORT
	address_edit.text_submitted.connect(func(_t: String) -> void: join_requested.emit(address_edit.text, name_edit.text))
	join.add_child(address_edit)
	_button(join, "Join", "Join the DM's table", func() -> void: join_requested.emit(address_edit.text, name_edit.text)).name = "Join"

	var book := _form(row, "Compendium")
	var hint := _muted("Books, worlds and the picked timeline's entries, without a session.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(220, 0)
	book.add_child(hint)
	_button(book, "Open the compendium", "Browse and edit without hosting", func() -> void:
		compendium_requested.emit(timeline_dir())).name = "OpenCompendium"

	status = Label.new()
	status.theme_type_variation = UISkin.V_MUTED
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(600, 0)
	col.add_child(status)


## Fills the pickers; `world_dir` / `timeline` preselect (the last used ones).
func refresh(world_dir := "", timeline := "") -> void:
	_worlds = Worlds.list(worlds_root)
	world_pick.clear()
	for w in _worlds:
		world_pick.add_item(str(w.get("name", w.get("id", ""))))
	var at := _worlds.find_custom(func(w: Dictionary) -> bool: return str(w._dir).simplify_path() == world_dir.simplify_path())
	if world_dir == "" and timeline != "":
		at = _worlds.find_custom(func(w: Dictionary) -> bool: return timeline.simplify_path().begins_with(str(w._dir).simplify_path() + "/"))
	if not _worlds.is_empty():
		world_pick.select(maxi(at, 0))
	_fill_timelines(timeline)


func _fill_timelines(select := "") -> void:
	timeline_pick.clear()
	_timelines = Timeline.list(world_dir()) if world_dir() != "" else []
	for t in _timelines:
		var parent := str(t.get("parent", ""))
		timeline_pick.add_item(str(t.get("name", t.get("id", ""))) + ("" if parent == "" else "  (fork of %s)" % parent))
	var at := _timelines.find_custom(func(t: Dictionary) -> bool: return str(t._dir).simplify_path() == select.simplify_path())
	if not _timelines.is_empty():
		timeline_pick.select(at if at >= 0 else _timelines.size() - 1 if _timelines.size() > 1 else 0)


func world_dir() -> String:
	var i := world_pick.selected
	return str(_worlds[i]._dir) if i >= 0 and i < _worlds.size() else ""


func timeline_dir() -> String:
	var i := timeline_pick.selected
	return str(_timelines[i]._dir) if i >= 0 and i < _timelines.size() else ""


# --- New world / new timeline -------------------------------------------------------------

func _new_world_dialog() -> void:
	var d := ConfirmationDialog.new()
	d.name = "NewWorldDialog"
	d.title = "New world"
	d.ok_button_text = "Create"
	var col := VBoxContainer.new()
	d.add_child(col)
	col.add_child(_muted("Name"))
	var n := LineEdit.new()
	n.name = "WorldName"
	n.custom_minimum_size = Vector2(320, 0)
	col.add_child(n)
	col.add_child(_muted("Calendar"))
	var cal := OptionButton.new()
	cal.name = "Calendar"
	for c in calendars():
		cal.add_item(c)
	col.add_child(cal)
	d.confirmed.connect(func() -> void:
		create_world(n.text, cal.get_item_text(cal.selected) if cal.selected >= 0 else "default")
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


## Makes a world (and its Prologue) and selects it. Returns the folder ("" if no name).
func create_world(world_name: String, calendar := "default") -> String:
	if world_name.strip_edges() == "":
		status.text = "Give the world a name."
		return ""
	var dir := Worlds.create(world_name.strip_edges(), calendar, worlds_root)
	refresh(dir)
	status.text = "Created %s with its start timeline, the Prologue." % world_name.strip_edges()
	return dir


## Calendar ids from res://calendars.
static func calendars() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at("res://calendars"):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	if out.is_empty():
		out.append("default")
	return out


func _new_timeline_dialog() -> void:
	if world_dir() == "":
		status.text = "Pick or create a world first."
		return
	var d := ConfirmationDialog.new()
	d.name = "NewTimelineDialog"
	d.title = "New timeline"
	d.ok_button_text = "Create"
	var form := NewTimelineForm.new()
	form.name = "Form"
	form.world_dir = world_dir()
	form.parent_dir = timeline_dir()
	d.add_child(form)
	d.confirmed.connect(func() -> void:
		var made := form.create()
		if made != "":
			_fill_timelines(made)
			status.text = "Created the timeline %s." % form.name_edit.text
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(560, 0))


func _form(parent: Control, heading: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(280, 0)
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var h := Label.new()
	h.text = heading
	h.theme_type_variation = UISkin.V_HEADING
	box.add_child(h)
	return box


func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UISkin.V_MUTED
	return l


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b
