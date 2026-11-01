class_name App
extends Node
## The whole app in one scene (TASK-33): starts on the start screen (StartScreen: host as DM,
## join as player, compendium without a session). In a session the table, compendium, notes
## and timeline are views switched with the bar at the top, without restarting; leaving the
## session (or the DM closing it) goes back to the start screen.
## The last used world, timeline, name, address and port are kept in `settings_file`.

const VIEWS := ["table", "compendium", "notes", "timeline", "encounters"]
const VIEW_NAMES := {"table": "Table", "compendium": "Compendium", "notes": "Notes", "timeline": "Timeline", "encounters": "Encounters"}
const DM_VIEWS := ["compendium", "timeline", "encounters"]

static var settings_file := "user://app.cfg"

## Worlds folder ("" = data/worlds); packages folder ("" = data/packages). Tests set them.
var worlds_root := ""
var packages_root := ""
var table: NetTable
var table_ui: TableUI
var start: StartScreen
var view := ""  ## "" = start screen, else one of VIEWS
var book: Compendium
var notes_view: NotesView
var timeline_view: TimelineView
var encounters_view: EncountersView

var _layer: CanvasLayer
var _bar: PanelContainer
var _view_buttons := {}


func _ready() -> void:
	if worlds_root == "":
		Worlds.migrate_data(PackageDB.default_root().get_base_dir())  # old campaigns (TASK-32)
		worlds_root = Worlds.default_root()
	if Worlds.list(worlds_root).is_empty():
		Worlds.install_example(worlds_root)  # something to host on a fresh install
	table = NetTable.new()
	table.name = "Table"
	table.auto_ui = false
	add_child(table)
	table_ui = TableUI.new()
	table_ui.table = table
	table_ui.lobby = false
	table_ui.packages_root = packages_root
	table_ui.compendium_opener = func() -> void: show_view("compendium")
	table.add_child(table_ui)
	_layer = CanvasLayer.new()
	_layer.layer = 8
	add_child(_layer)
	var root := Control.new()
	root.name = "Views"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UISkin.theme()
	_layer.add_child(root)
	_build_bar(root)
	start = StartScreen.new()
	start.name = "Start"
	start.worlds_root = worlds_root
	root.add_child(start)
	start.host_requested.connect(host)
	start.join_requested.connect(join)
	start.compendium_requested.connect(open_book_alone)
	start.edit_world_requested.connect(open_world)
	var cfg := _settings()
	start.refresh(str(cfg.get_value("last", "world", "")), str(cfg.get_value("last", "timeline", "")))
	start.name_edit.text = str(cfg.get_value("last", "player", ""))
	start.port_edit.text = str(cfg.get_value("last", "port", start.port_edit.text))
	table.status_changed.connect(func(text: String) -> void: start.status.text = text)
	table.table_changed.connect(_on_table_changed)
	table.pcs_changed.connect(_on_table_changed)
	show_view("")


# --- Starting -------------------------------------------------------------------------------

## Hosts a timeline as DM. Returns OK or the error (the start screen shows why).
func host(timeline_dir: String, port := NetTable.DEFAULT_PORT) -> Error:
	if not Timeline.is_timeline(timeline_dir):
		start.status.text = "Pick a timeline to host."
		return ERR_FILE_NOT_FOUND
	var world := Timeline.new(timeline_dir).world_manifest()
	var cal := "res://calendars/%s.json" % str(world.get("calendar", "default"))
	table.calendar_path = cal if FileAccess.file_exists(cal) else "res://calendars/default.json"
	table.notes.calendar = WorldCalendar.load_file(table.calendar_path)
	table.timeline_dir = timeline_dir
	table.log_path = ""
	var err := table.host(port)
	if err == OK:
		_remember({"world": timeline_dir.get_base_dir().get_base_dir(), "timeline": timeline_dir, "port": port})
		show_view("table")
	return err


func join(address: String, player_name: String) -> Error:
	if player_name.strip_edges() == "":
		start.status.text = "Give your player name."
		return ERR_INVALID_PARAMETER
	_remember({"player": player_name.strip_edges(), "address": address.strip_edges()})
	var err := table.join(address, player_name)
	if err == OK:
		show_view("table")
	return err


## The compendium without a session (back to the start screen when closed).
func open_book_alone(timeline_dir := "") -> Compendium:
	_drop_book()
	book = _new_book()
	book.timeline_dir = timeline_dir
	_layer.get_node("Views").add_child(book)
	book.move_to_front()
	book.close_requested.connect(func() -> void:
		_drop_book()
		show_view(""))
	if timeline_dir != "":
		_remember({"timeline": timeline_dir, "world": timeline_dir.get_base_dir().get_base_dir()})
	view = "compendium"
	start.hide()
	_bar.hide()
	return book


## A world's own book: its NPCs, places, maps, factions and lore (from the start screen).
func open_world(world_dir: String) -> Compendium:
	return open_book_alone(Worlds.start_timeline(world_dir))


## Leaves the session: closes the connection and goes back to the start screen.
func leave() -> void:
	if table.multiplayer.multiplayer_peer != null and not table.multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		table.multiplayer.multiplayer_peer.close()
	table._go_offline()
	show_view("")


# --- Views ----------------------------------------------------------------------------------

## Shows a view of the session ("" = the start screen).
func show_view(which: String) -> void:
	if which != "" and not table.is_online():
		which = ""
	if which in DM_VIEWS and not table.is_dm():
		which = "table"  # the DM's views
	view = which
	start.visible = which == ""
	_bar.visible = which != ""
	if which == "":
		start.refresh(start.world_dir(), start.timeline_dir())
		_drop_book()
	for v: String in _view_buttons:
		(_view_buttons[v] as Button).set_pressed_no_signal(v == which)
		(_view_buttons[v] as Button).visible = table.is_dm() or v not in DM_VIEWS
	if which == "compendium":
		if book == null:
			book = _new_book()
			book.closable = true
			book.timeline_dir = table.timeline_dir
			book.event_log = table.event_log
			book.close_requested.connect(func() -> void: show_view("table"))
			_layer.get_node("Views").add_child(book)
			_bar.move_to_front()
		book.show()
	elif book != null and book.closable:
		book.hide()
	if which == "notes":
		if notes_view == null:
			notes_view = NotesView.new()
			notes_view.name = "NotesView"
			notes_view.table = table
			_place(notes_view)
		notes_view.refresh()
	if notes_view != null:
		notes_view.visible = which == "notes"
	if which == "timeline":
		if timeline_view == null or timeline_view.event_log != table.event_log:
			if timeline_view != null:
				timeline_view.queue_free()
			timeline_view = TimelineView.new()
			timeline_view.name = "TimelineView"
			timeline_view.event_log = table.event_log
			timeline_view.timeline = table.timeline
			timeline_view.calendar = table.notes.calendar
			_place(timeline_view)
		timeline_view.refresh()
	if timeline_view != null:
		timeline_view.visible = which == "timeline"
	if which == "encounters":
		if encounters_view == null or encounters_view.events_log != table.event_log:
			if encounters_view != null:
				encounters_view.queue_free()
			encounters_view = EncountersView.new()
			encounters_view.name = "EncountersView"
			encounters_view.timeline = table.timeline
			encounters_view.events_log = table.event_log
			encounters_view.calendar = table.notes.calendar
			encounters_view.assets = table.assets
			_place(encounters_view)
		encounters_view.refresh()
	if encounters_view != null:
		encounters_view.visible = which == "encounters"


func _place(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_top = 56
	c.offset_left = 12
	c.offset_right = -12
	c.offset_bottom = -12
	_layer.get_node("Views").add_child(c)
	_bar.move_to_front()


func _new_book() -> Compendium:
	var b := Compendium.new()
	b.name = "Book"
	if packages_root != "":
		b.tabs_file = ""  # tests: no saved tabs
	b.packages_root = packages_root
	return b


func _drop_book() -> void:
	if book != null:
		book.get_parent().remove_child(book)
		book.queue_free()
		book = null


func _on_table_changed() -> void:
	if not table.is_online() and view != "" and view != "compendium":
		show_view("")
	elif not table.is_online() and view == "compendium" and book != null and book.closable:
		show_view("")
	elif table.is_online():
		for v: String in _view_buttons:
			(_view_buttons[v] as Button).visible = table.is_dm() or v not in DM_VIEWS


func _build_bar(root: Control) -> void:
	_bar = PanelContainer.new()
	_bar.name = "ViewBar"
	_bar.theme_type_variation = UISkin.V_PAGE
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.offset_top = 4
	root.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bar.add_child(row)
	var group := ButtonGroup.new()
	for v: String in VIEWS:
		var b := Button.new()
		b.name = "View_" + v
		b.text = VIEW_NAMES[v]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(show_view.bind(v))
		row.add_child(b)
		_view_buttons[v] = b
	var leave_button := Button.new()
	leave_button.name = "Leave"
	leave_button.text = "Leave"
	leave_button.tooltip_text = "End the session (DM) or leave the table, back to the start screen"
	leave_button.pressed.connect(leave)
	row.add_child(leave_button)


# --- Settings --------------------------------------------------------------------------------

func _settings() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	return cfg


func _remember(values: Dictionary) -> void:
	var cfg := _settings()
	for k: String in values:
		cfg.set_value("last", k, values[k])
	cfg.save(settings_file)
