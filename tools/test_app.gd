extends SceneTree
## Headless check of the app shell (TASK-33): the app starts on the start screen; a new world
## and a new timeline (fork point, players, colours) are made there; hosting opens the table
## and the views (table, compendium, notes, timeline) switch without restarting; a player
## joins from a second app and only gets table and notes; the last used world and timeline
## are preselected on the next start; leaving goes back to the start screen. TASK-38: world
## cards with their timelines (a click hosts), saved servers with a heartbeat (a click on an
## online one joins), kept in user://.
## godot --headless --path . -s tools/test_app.gd

const DIR := "user://test_app"
const PORT := 47788

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base.path_join("packages"))
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	Dock.layout_file = DIR.path_join("layout.json")
	await process_frame

	# --- First start: the example world, the start screen --------------------------------------
	var dm := _app("DM")
	await process_frame
	_check(dm.view == "" and dm.start.visible and not dm._bar.visible, "starts on the start screen")
	_check(_find(dm.start, "World_westmarch") != null and _find(dm.start, "Timeline_red-fang") is Button and _find(dm.start, "Timeline_prologue") is Button, "a world card with its timelines")
	_check(_find(dm.start, "NewWorld") != null and _find(dm.start, "NewTimeline") != null and _find(dm.start, "EditWorld") != null, "new world, new timeline, edit world")
	_check(_find(dm.start, "AddServer") != null and _find(dm.start, "OpenCompendium") != null, "servers panel and compendium")
	_check(Worlds.list(dm.worlds_root).size() == 1, "a fresh install gets the example world")

	# --- New world, new timeline -------------------------------------------------------------------
	var world := dm.start.create_world("Sunken Coast", "default")
	_check(world != "" and dm.start.world_dir() == world, "new world made and selected")
	_check(dm.start.timeline_dir().ends_with("timelines/prologue"), "its Prologue is selected")
	var pro := Timeline.new(dm.start.timeline_dir())
	pro.add_entry("items", {"name": "Storm Lantern"})
	pro.add_entry("items", {"name": "Sea Glass"})
	var form := NewTimelineForm.new()
	form.world_dir = world
	form.parent_dir = pro.folder
	dm.start.add_child(form)
	_check(form.point_pick.item_count == 4, "fork points: now, both events, start (%d)" % form.point_pick.item_count)
	form.name_edit.text = "Campaign A"
	form.point_pick.select(2)  # after the first event
	form.add_player("Ann", "#2e6e60")
	form.add_player("Bob Two", "#3a5f9a")
	form.dm_name.text = "Nico"
	var a_dir := form.create()
	form.queue_free()
	var a := Timeline.new(a_dir)
	_check(Timeline.is_timeline(a_dir) and int(a.info.fork_at) == 1 and a.info.parent == "prologue", "forked after the first event (%s)" % [a.info])
	_check(a.players().size() == 2 and str(a.players()[1].id) == "bob-two" and str(a.players()[1].color) == "#3a5f9a", "players with colours")
	_check(str(a.info.dm.name) == "Nico", "DM name")
	dm.start.refresh(world, a_dir)
	await process_frame
	_check(dm.start.timeline_dir() == a_dir and _find(dm.start, "Timeline_campaign-a") is Button, "the new timeline is on the world's card")
	_check(StartScreen.timeline_line(Timeline.list(world)[0]).contains("0 sessions"), "sessions and last played on the line")

	# --- Host and switch views ---------------------------------------------------------------------
	var west: Dictionary = Worlds.list(dm.worlds_root).filter(func(w: Dictionary) -> bool: return w.id == "westmarch")[0]
	var red := str(west._dir).path_join("timelines/red-fang")
	dm.start.port_edit.text = str(PORT)
	(_find(dm.start, "Timeline_red-fang") as Button).pressed.emit()
	_check(dm.table.is_dm() and dm.table.timeline_dir == red, "clicking a timeline hosts it")
	_check(dm.view == "table" and not dm.start.visible and dm._bar.visible, "table view after hosting")
	var views := dm.dock.get_parent() as Control  # headless: a 64 px window, give the panels room
	views.set_anchors_preset(Control.PRESET_TOP_LEFT)
	views.size = Vector2(1600, 950)
	_check(dm.dock.is_shown("session") and dm.dock.place_of("session") == "right", "the session log opens as a panel (TASK-37)")
	_check(dm.dock.has_panel("sheet") and not dm.dock.is_shown("sheet"), "the sheet panel waits for a sheet")
	var ui_sheet := dm.table_ui.sheet
	ui_sheet.show_sheet({"ref": "pcs/aria", "name": "Aria", "_editable": true, "inventory": []})
	_check(dm.dock.is_shown("sheet") and dm.dock.place_of("sheet") == "left", "a sheet opens its panel")
	_check(ui_sheet._can_drop_data(Vector2.ZERO, EntryDrag.data({"_kind": "items", "id": "rope", "name": "Rope"})), "an item can be dropped on the sheet")
	_check(not ui_sheet._can_drop_data(Vector2.ZERO, EntryDrag.data({"_kind": "monsters", "id": "goblin"})), "a monster can't")
	dm.dock.hide_panel("sheet")
	_check(not ui_sheet.visible and ui_sheet.ref == "", "closing the panel closes the sheet")
	ui_sheet.show_sheet({"ref": "pcs/aria", "name": "Aria"})
	ui_sheet.close_sheet()
	_check(not dm.dock.is_shown("sheet"), "the sheet's own close button closes the panel")
	dm.show_view("compendium")
	await process_frame
	_check(dm.book != null and dm.dock.is_shown("compendium") and dm.book.closable and dm.book.scope() == "core" and dm.book.find_child("TimelinePick", true, false) == null, "compendium view: the core book, no timeline picker")
	_check(dm.dock.free_rect().size.x > 600, "the compendium doesn't cover the map")
	var core_book := dm.book
	dm.show_view("world")
	await process_frame
	_check(dm.book.scope() == "world" and dm.book.world_dir == str(west._dir) and dm.book != core_book and dm.dock.is_shown("compendium"), "world view: the world's book, beside the core book")
	dm.show_view("timeline")
	await process_frame
	_check(dm.book.scope() == "timeline" and dm.book.timeline_dir == red and dm.book.event_log == dm.table.event_log, "timeline view: the timeline's book")
	var tl_book := dm.book
	var lantern := {"_kind": "items", "id": "storm-lantern", "name": "Storm Lantern", "weight": 2}
	_check(tl_book._can_drop_data(Vector2.ZERO, EntryDrag.data(lantern)), "a core entry can be dropped on the timeline's book")
	var before := dm.table.event_log.events.size()
	tl_book._drop_data(Vector2.ZERO, EntryDrag.data(lantern))
	_check(dm.table.timeline.entry("items/storm-lantern").get("name") == "Storm Lantern", "dropped on the timeline: the entry is in the timeline")
	_check(dm.table.event_log.events.size() == before + 1 and str(dm.table.event_log.events.back().get("type")) == "entity.created", "...as an entity.created event")
	var world_book: Compendium = dm.books.world
	_check(world_book.db.packages.all(func(m: Dictionary) -> bool: return str(m.get("kind", "")) == "world"), "the world's book shows only the world, not the core packages")
	var core_dir := PackageDB.default_root().path_join("5e-core-rules")
	var goblin := EntryStore.open(core_dir).find("monsters", "goblin")
	goblin.merge({"_kind": "monsters", "_layer": "core", "_package": "5e-core-rules", "_dir": core_dir}, true)
	var world_store := dm.table.timeline.world_store()
	var had := world_store.list("monsters").size()
	var t1 := dm.table.drop_token(goblin, Vector2i(2, 2))
	_check(t1 != "" and dm.table.timeline.world_store().list("monsters").size() == had + 1, "a core monster dropped on the map is imported into the world first (%s)" % t1)
	await process_frame
	_check(world_book.db.list("monsters").any(func(m: Dictionary) -> bool: return str(m.get("name", "")) == "Goblin"), "...and shows up in the world's book")
	var t2 := dm.table.drop_token(goblin, Vector2i(3, 2))
	_check(t2 != "" and t2 != t1 and dm.table.timeline.world_store().list("monsters").size() == had + 1, "a second one reuses the imported monster")
	dm.show_view("events")
	await process_frame
	_check(dm.dock.is_shown("events") and dm.dock.place_of("events") == "bottom" and dm.timeline_view.tree.get_root().get_child_count() == dm.table.event_log.events.size(), "events view lists the events")
	dm.show_view("encounters")
	await process_frame
	_check(dm.encounters_view != null and dm.dock.is_shown("encounters"), "encounters view")
	dm.show_view("notes")
	await process_frame
	_check(dm.dock.is_shown("notes") and dm.dock.place_of("notes") == "left" and dm.dock.is_shown("events"), "notes view, the others stay open")
	dm.table.add_note("The wolves fled north.")
	await process_frame
	dm.notes_view.refresh()
	_check(dm.notes_view.text.text.contains("wolves fled"), "notes view shows the timeline's notes")
	dm.toggle_view("notes")
	_check(not dm.dock.is_shown("notes") and not dm._view_buttons.notes.button_pressed, "the bar button closes it again")
	dm.dock.detach("events")
	dm.show_view("table")
	_check(dm.table.is_online() and not dm.dock.is_shown("compendium") and dm.view == "table", "back to the table, still hosting")
	_check(dm.dock.place_of("events") == "window", "own windows stay open")
	dm.table_ui._book_button.pressed.emit()
	_check(dm.view == "compendium" and dm.dock.is_shown("compendium"), "the table's Compendium button opens the book")
	dm.books.compendium.close_requested.emit()
	_check(dm.view == "table" and not dm.dock.is_shown("compendium"), "closing the compendium goes back to the table")
	dm.dock.save_layout()

	# --- A player joins from another app ---------------------------------------------------------
	var pl := _app("Player")
	await process_frame
	pl.table.cache_dir = DIR.path_join("cache_ann")
	_check(pl.join("127.0.0.1:%d" % PORT, "") != OK, "a name is needed to join")
	pl.start.add_server("Local table", "127.0.0.1", PORT)
	pl.start.add_server("Nobody", "127.0.0.1", PORT + 7)
	await _until(func() -> bool: return pl.start.server_state(0) == "online" and pl.start.server_state(1) == "offline", 600)
	_check(pl.start.server_state(0) == "online" and pl.start.server_state(1) == "offline", "heartbeat: online and offline (%s, %s)" % [pl.start.server_state(0), pl.start.server_state(1)])
	var probe: ServerStatus.Probe = pl.start.probes[0]
	_check(probe.info.get("world") == "The Westmarch" and probe.info.get("timeline") == "The Red Fang Road" and probe.info.get("dm") == "Nico", "status: world, timeline, DM (%s)" % [probe.info])
	var offline_join := _find(pl.start.servers_box.get_child(1), "Join") as Button
	_check(offline_join != null and offline_join.disabled, "an offline server can't be clicked")
	pl.start.name_edit.text = "Ann"
	(_find(pl.start.servers_box.get_child(0), "Join") as Button).pressed.emit()
	await _until(func() -> bool: return pl.table.my_pc == "pcs/aria")
	_check(pl.table.is_online(), "clicking an online server joins")
	var check := ServerStatus.Probe.new("127.0.0.1", PORT)
	await _until(func() -> bool: return check.poll(), 600)
	_check(check.info.get("players") == ["Ann"] and int(check.info.get("online", 0)) == 1, "players online in the status (%s)" % [check.info])
	_check(pl.view == "table" and pl._bar.visible, "player sees the table")
	_check(pl.dock.is_shown("session") and not pl.dock.is_shown("events"), "the player's panels: their saved session panel, not the DM's")
	_check(not pl._view_buttons.compendium.visible and not pl._view_buttons.timeline.visible and not pl._view_buttons.encounters.visible and pl._view_buttons.notes.visible, "player has table and notes only")
	pl.show_view("timeline")
	_check(pl.view == "table", "no timeline view for players")
	pl.leave()
	_check(pl.view == "" and pl.start.visible, "leaving goes back to the start screen")

	dm.leave()
	await process_frame
	_check(dm.view == "" and dm.start.visible and not dm.table.is_online(), "DM ends the session")

	# --- Next start: the last used ones are preselected ------------------------------------------
	var again := _app("Again")
	await process_frame
	_check(again.start.timeline_dir() == red and again.start.world_dir() == str(west._dir), "last world and timeline preselected (%s)" % again.start.timeline_dir())
	_check(again.start.name_edit.text == "Ann" and again.start.port_edit.text == str(PORT), "last player name and port")
	_check(again.start.servers.size() == 2 and again.start.servers[0].name == "Local table", "saved servers persist")
	again.start.edit_server(1, "Renamed", "localhost", PORT + 8)
	again.start.remove_server(0)
	_check(ServerStatus.load_servers().size() == 1 and ServerStatus.load_servers()[0].name == "Renamed" and int(ServerStatus.load_servers()[0].port) == PORT + 8, "servers edited and removed")
	await _until(func() -> bool: return again.start.server_state(0) == "offline", 600)
	_check(again.start.server_state(0) == "offline", "the DM is gone: offline")

	# --- Compendium without a session -----------------------------------------------------------
	var b := again.open_world(world)
	await process_frame
	_check(b.scope() == "world" and b.world_dir == world, "Edit world opens the world's book")
	b.close_requested.emit()
	b = again.open_book_alone()
	await process_frame
	_check(again.view == "compendium" and b.get_parent() is Window and again.start.visible, "compendium from the start screen: its own window, the start screen stays")
	b.close_requested.emit()
	_check(again.view == "" and again.start.visible and again.book == null, "closing it goes back to the start screen")

	print("app: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _app(branch: String) -> App:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var app := App.new()
	app.name = "App"  # the same node path on every peer, as in scenes/app.tscn
	app.worlds_root = ProjectSettings.globalize_path(DIR.path_join("worlds"))
	app.packages_root = ProjectSettings.globalize_path(DIR.path_join("packages"))
	app.minimal = false  # the full bar (the calm table is checked in test_minimal)
	holder.add_child(app)
	return app


func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)


func _until(done: Callable, frames := 400) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
