class_name App
extends Node
## The whole app in one scene (TASK-33): starts on the start screen (StartScreen: host as DM,
## join as player, compendium without a session). In a session the table is always there and
## the other views are panels around it (Dock, TASK-37: docked, tabbed or in their own OS
## window) toggled with the bar at the top; leaving the session (or the DM closing it) goes
## back to the start screen.
## The last used world, timeline, name, address and port are kept in `settings_file`.

const VIEWS := ["table", "session", "compendium", "world", "timeline", "events", "notes", "encounters", "rules"]
const VIEW_NAMES := {"table": "Table", "session": "Session", "compendium": "Compendium", "world": "World", "timeline": "Timeline",
	"events": "Events", "notes": "Notes", "encounters": "Encounters", "rules": "Rules"}
const DM_VIEWS := ["compendium", "world", "timeline", "events", "encounters", "rules"]
## The views that are books (TASK-39): the core compendium, the world's and the timeline's.
const BOOK_VIEWS := ["compendium", "world", "timeline"]
## Panels the table's UI brings (the session log with notes and rolls, the open sheet).
const KEEP_PANELS := ["session", "sheet"]
## The calm table's buttons: the compendium and the world's book ("Book"), each its own window.
const MINIMAL_VIEWS := ["compendium", "world", "rules"]

static var settings_file := "user://app.cfg"

## Worlds folder ("" = data/worlds); packages folder ("" = data/packages). Tests set them.
var worlds_root := ""
var packages_root := ""
var table: NetTable
var table_ui: TableUI
var start: StartScreen
var view := ""  ## "" = start screen, else one of VIEWS
var book: Compendium  ## the open book (the current book view, or the one opened from the start screen)
var books := {}  ## book view -> Compendium (in a session)
var notes_view: NotesView
var timeline_view: TimelineView
var encounters_view: EncountersView
var rules_view: RulesView  ## the world's rules page (TASK-60)

var dock: Dock  ## the panels around the table (TASK-37)
## Nico, 2026-11-01: a calm table to start with. Only the map and two buttons at the top
## right: Compendium (its own window, pressed again closes it) and Leave. No other bars or
## panels. false = the full bar with every view (the tests use it).
var minimal := true

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
	table_ui.timeline_list_opener = func(ids: Array) -> void:  # a box of the timeline bar (TASK-82)
		show_view("timeline")
		if timeline_view != null:
			timeline_view.show_moment(ids)
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
	dock = Dock.new()
	dock.name = "Dock"
	root.add_child(dock)
	table_ui.use_dock(dock)
	dock.panel_hidden.connect(func(_id: String) -> void: _sync_buttons())
	dock.panel_shown.connect(func(_id: String) -> void: _sync_buttons())
	_build_bar(root)
	if minimal:
		table_ui.minimal = true
		table.show_map_info = false
		dock.close_hides = true  # closing the compendium window closes it
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
	EntryDrag.hub.dropped_outside.connect(drop_outside)
	table.entry_imported.connect(func(_e: Dictionary) -> void:
		for v: String in ["world", "timeline"]:
			if books.has(v):
				(books[v] as Compendium).reload())
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
		_open_panels()
	return err


func join(address: String, player_name: String) -> Error:
	if player_name.strip_edges() == "":
		start.status.text = "Give your player name."
		return ERR_INVALID_PARAMETER
	_remember({"player": player_name.strip_edges(), "address": address.strip_edges()})
	var err := table.join(address, player_name)
	if err == OK:
		show_view("table")
		_open_panels()
	return err


## The compendium without a session, in its own OS window (TASK-37) beside the start screen,
## which stays usable: the core book, or a world's (`world_dir`) or a timeline's
## (`timeline_dir`) book. Closing the window closes the book.
func open_book_alone(timeline_dir := "", world_dir := "") -> Compendium:
	_drop_books()
	book = _new_book()
	book.timeline_dir = timeline_dir
	book.world_dir = world_dir
	var w := Window.new()
	w.name = "BookWindow"
	w.visible = false
	w.force_native = DisplayServer.get_name() != "headless"
	w.title = "Dragoon · %s" % ("Timeline" if timeline_dir != "" else "World" if world_dir != "" else "Compendium")
	w.theme = UISkin.theme()
	w.min_size = Vector2i(640, 480)
	w.size = Vector2i(1280, 820)
	w.position = get_window().position + Vector2i(60, 60)
	var bg := Panel.new()
	bg.theme_type_variation = UISkin.V_PAGE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(bg)
	book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(book)
	add_child(w)
	var b := book
	w.close_requested.connect(func() -> void: b.close_requested.emit())
	book.close_requested.connect(func() -> void:
		_drop_books()
		if view == "compendium":
			show_view(""))
	if timeline_dir != "":
		_remember({"timeline": timeline_dir, "world": timeline_dir.get_base_dir().get_base_dir()})
	view = "compendium"
	w.show()
	return book


## A world's own book: its NPCs, places, maps, factions and lore (Edit world on the start screen).
func open_world(world_dir: String) -> Compendium:
	return open_book_alone("", world_dir)


## Leaves the session: closes the connection and goes back to the start screen.
func leave() -> void:
	if table.multiplayer.multiplayer_peer != null and not table.multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		table.multiplayer.multiplayer_peer.close()
	table._go_offline()
	show_view("")


# --- Views ----------------------------------------------------------------------------------

## The views of a session are panels around the table (TASK-37): docked left, right or at the
## bottom, tabbed, or in their own OS window; the bar toggles them. "table" puts the docked
## ones away (map only); "" is the start screen.
func show_view(which: String) -> void:
	if which != "" and not table.is_online():
		which = ""
	if which in DM_VIEWS and not table.is_dm():
		which = "table"  # the DM's views
	view = which
	start.visible = which == ""
	_bar.visible = which != ""
	dock.visible = which != ""
	if which == "":
		start.refresh(start.world_dir(), start.timeline_dir())
		dock.hide_all()
		_drop_books()
		_drop_views()
	elif which == "table":
		for id: String in dock.panels:
			if dock.place_of(id) in Dock.AREAS:
				dock.hide_panel(id)
	else:
		_panel(which)
		dock.show_panel(which, "float" if minimal and which in MINIMAL_VIEWS else "")  # TASK-80: over the table, like the chat
		if which in BOOK_VIEWS:
			book = books[which]
		_refresh_view(which)
	_sync_buttons()


## Shows or hides a panel (the bar's buttons).
func toggle_view(which: String) -> void:
	if which != "table" and dock.has_panel(which) and dock.is_shown(which):
		dock.hide_panel(which)
		view = "table"
		_sync_buttons()
	else:
		show_view(which)


## Makes the control of a view and registers it with the dock (once per session).
func _panel(which: String) -> Control:
	if dock.has_panel(which):
		return (dock.panels[which].holder as Control).get_child(0)
	var c: Control
	match which:
		"compendium", "world", "timeline":
			var b := _new_book()
			b.name = "Book_" + which
			b.closable = true
			if which == "world":
				b.world_dir = table.timeline.world_dir
			elif which == "timeline":
				b.timeline_dir = table.timeline_dir
				b.event_log = table.event_log  # session edits become events
			b.close_requested.connect(func() -> void: toggle_view(which))
			b.token_changed.connect(func(_e: Dictionary) -> void: table.refresh_tokens())
			books[which] = b
			c = b
		"notes":
			notes_view = NotesView.new()
			notes_view.name = "NotesView"
			notes_view.table = table
			c = notes_view
		"events":
			timeline_view = TimelineView.new()
			timeline_view.name = "TimelineView"
			timeline_view.event_log = table.event_log
			timeline_view.timeline = table.timeline
			timeline_view.calendar = table.notes.calendar
			timeline_view.on_changed = table.refresh_tokens  # an undo or correction (TASK-85)
			c = timeline_view
		"encounters":
			encounters_view = EncountersView.new()
			encounters_view.name = "EncountersView"
			encounters_view.timeline = table.timeline
			encounters_view.events_log = table.event_log
			encounters_view.calendar = table.notes.calendar
			encounters_view.assets = table.assets
			c = encounters_view
		"rules":
			rules_view = RulesView.new()
			rules_view.name = "RulesView"
			rules_view.table = table
			c = rules_view
	dock.add_panel(which, "Book" if minimal and which == "world" else VIEW_NAMES[which], c, _default_place(which))
	return c


## Where a view goes the first time: the compendium is its own book window (TASK-37).
func _default_place(which: String) -> String:
	match which:
		"compendium":
			return "window" if DisplayServer.get_name() != "headless" else "right"
		"world", "timeline":
			return "right"
		"notes":
			return "left"
	return "bottom"


func _refresh_view(which: String) -> void:
	match which:
		"notes":
			notes_view.refresh()
		"events":
			timeline_view.refresh()
		"encounters":
			encounters_view.refresh()
		"rules":
			rules_view.refresh()


func _sync_buttons() -> void:
	_hud_actions()
	for v: String in _view_buttons:
		var b: Button = _view_buttons[v]
		b.set_pressed_no_signal(dock.is_shown(v) if v != "table" else view == "table")
		b.visible = (table.is_dm() or v not in DM_VIEWS) and (not minimal or v in MINIMAL_VIEWS)


## The panels of the session that was left (a new session builds new ones).
func _drop_views() -> void:
	for id: String in dock.panels.keys():
		if id in KEEP_PANELS:
			continue
		dock.remove_panel(id)
	notes_view = null
	timeline_view = null
	encounters_view = null
	rules_view = null


## A card let go outside its own window (EntryDrag): the book window under the mouse
## imports it, else the map in the main window takes it. True if something took it.
func drop_outside(e: Dictionary, screen: Vector2i, from: Viewport = null) -> bool:
	var data := EntryDrag.data(e)
	for id: String in dock.panels:
		var w: Window = dock.panels[id].window
		var f: DockPanel = dock.panels[id].get("frame")
		if f != null and f.window != null:
			w = f.window  # a floating book popped out (TASK-80)
		if w == null or w == from or dock.place_of(id) != "window" or not Rect2i(w.position, w.size).has_point(screen):
			continue
		var b := books.get(id) as Compendium
		if b != null and b._can_drop_data(Vector2.ZERO, data):
			b._drop_data(Vector2.ZERO, data)
			return true
		return false
	var main := get_window()
	if main == from or not table.is_online() or not Rect2i(main.position, main.size).has_point(screen):
		return false
	var at: Vector2 = main.get_final_transform().affine_inverse() * Vector2(screen - main.position)
	var drop := table_ui.map_drop
	if drop != null and drop._can_drop_data(at, data):
		drop._drop_data(at, data)
		return true
	return false


## After hosting or joining: the panels that were open last time (the session log at first).
func _open_panels() -> void:
	if minimal:
		_sync_buttons()
		return  # nothing opens by itself
	var allowed := ["session", "sheet", "notes"]
	if table.is_dm():
		allowed.append_array(DM_VIEWS)
	var saved: Dictionary = Dock.load_layout().get("panels", {})
	for id: String in saved:
		if id in allowed and id != "sheet" and bool((saved[id] as Dictionary).get("open", false)):
			if id in VIEWS:
				_panel(id)
			dock.show_panel(id)
	if not dock.panels.keys().any(func(id: String) -> bool: return dock.is_shown(id)):
		dock.show_panel("session")  # the first time (or all were closed): the session log
	_sync_buttons()


func _new_book() -> Compendium:
	var b := Compendium.new()
	b.name = "Book"
	if packages_root != "":
		b.tabs_file = ""  # tests: no saved tabs
	b.packages_root = packages_root
	return b


func _drop_books() -> void:
	if book != null and not book in books.values():
		var holder := book.get_parent()
		if holder is Window:
			holder.queue_free()  # the book's own window
		else:
			holder.remove_child(book)
			book.queue_free()
	for b: Compendium in books.values():
		b.get_parent().remove_child(b)
		b.queue_free()
	books.clear()
	book = null


func _on_table_changed() -> void:
	if not table.is_online() and view != "" and (view != "compendium" or not books.is_empty()):
		show_view("")
	elif table.is_online():
		_sync_buttons()


## The calm table's buttons as HUD pieces (Nico, 2026-11-01): Compendium and Book for the DM,
## Leave for everyone. While the HUD shows them, the bar at the top right steps aside.
func _hud_actions() -> void:
	var hud := table_ui.hud
	if hud == null:
		return
	var acts := {"leave": leave}
	if table.is_dm():
		acts["compendium"] = toggle_view.bind("compendium")
		acts["book"] = toggle_view.bind("world")
		acts["rules"] = toggle_view.bind("rules")
		acts["combat"] = func() -> void:  # TASK-58: start (initiative is rolled) or end it
			if table.in_combat():
				table.end_combat()
			else:
				table.start_combat()
	if hud.actions.keys() != acts.keys():
		hud.actions = acts
		hud.refresh()
	if not hud.shown.is_connected(_hud_shown):
		hud.shown.connect(_hud_shown)
	_hud_shown()


func _hud_shown() -> void:
	if _bar != null and minimal:  # TASK-77: never over the F2 editor; else only if the HUD lacks the buttons
		_bar.visible = view != "" and table_ui.hud.editor == null and not table_ui.hud.shows_app_buttons()


func _build_bar(root: Control) -> void:
	_bar = PanelContainer.new()
	_bar.name = "ViewBar"
	_bar.theme_type_variation = UISkin.V_PAGE
	_bar.anchor_left = 1.0 if minimal else 0.5
	_bar.anchor_right = _bar.anchor_left
	_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN if minimal else Control.GROW_DIRECTION_BOTH
	_bar.offset_top = 8 if minimal else 4
	_bar.offset_right = -8 if minimal else 0
	root.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bar.add_child(row)
	for v: String in VIEWS:
		var b := Button.new()
		b.name = "View_" + v
		b.text = "Book" if minimal and v == "world" else VIEW_NAMES[v]
		b.toggle_mode = true
		b.pressed.connect(toggle_view.bind(v))
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
