extends SceneTree
## Headless check of the calm table (Nico, 2026-11-01): after hosting only the map and two
## buttons at the top right, Compendium (its own window; pressed again, or the window
## closed, it goes away) and Leave (back to the start screen).
## godot --headless --path . -s tools/test_minimal.gd

const DIR := "user://test_minimal"

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base.path_join("packages"))
	var core := EntryStore.open(PackageDB.default_root().path_join("5e-core-rules"))
	var mini := EntryStore.create_package(base.path_join("packages"), "mini-core")
	mini.copy_entry(core, "creatures", "goblin")  # a monster card to drag
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	Dock.layout_file = DIR.path_join("layout.json")
	var app := App.new()
	app.worlds_root = base.path_join("worlds")
	app.packages_root = base.path_join("packages")
	root.add_child(app)
	await process_frame
	var red := ""
	for w: Dictionary in Worlds.list(app.worlds_root):
		red = str(w._dir).path_join("timelines/red-fang")
	_check(app.host(red, 47833) == OK, "hosted")
	await process_frame
	var shown := app._view_buttons.keys().filter(func(v: String) -> bool: return (app._view_buttons[v] as Button).visible)
	_check(not app._bar.visible, "no buttons at the top right: they are in the Esc menu")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	app._unhandled_input(esc)
	_check(app.esc_menu.visible, "Esc opens the menu")
	var names := ["Start combat", "Rules", "Compendium", "Book", "End the session"]
	_check(names.all(func(t: String) -> bool: return app.esc_menu.button(t) != null), "with combat, rules, the books and leaving")
	app._unhandled_input(esc)
	_check(not app.esc_menu.visible, "Esc again closes it")
	_check(not app.table_ui._bar.visible and not app.dock.panels.keys().any(app.dock.is_shown), "no table bar, no panels")
	_check(not app.table.show_map_info, "no help line on the map")
	var fake := LayoutEditor.new()  # TASK-77: the bar never sits over the F2 editor
	app.table_ui.hud.editor = fake
	app._hud_shown()
	_check(not app._bar.visible, "F2 editor open: no bar either")
	app.table_ui.hud.editor = null
	fake.free()
	app._hud_shown()
	var button: Button = app._view_buttons.compendium
	button.pressed.emit()
	await process_frame
	_check(app.dock.place_of("compendium") == "float" and button.button_pressed, "Compendium floats over the table, like the chat (TASK-80)")
	button.pressed.emit()
	await process_frame
	_check(not app.dock.is_shown("compendium") and not button.button_pressed, "pressed again: closed")
	button.pressed.emit()
	await process_frame
	(app.dock.panels.compendium.frame as DockPanel).pop_out()
	_check(app.dock.place_of("compendium") == "window", "popped out: its own window")
	((app.dock.panels.compendium.frame as DockPanel).window as Window).close_requested.emit()
	await process_frame
	_check(not app.dock.is_shown("compendium"), "closing the window closes it too")
	# --- TASK-80: past the program's edge it pops out, dragged back over it docks again -------
	button.pressed.emit()
	await process_frame
	var f: DockPanel = app.dock.panels.compendium.frame
	f.dock_back()
	await process_frame
	_check(app.dock.place_of("compendium") == "float", "docked back: floating over the table")
	_check(f.outside(Vector2(-5, 100)) and not f.outside(f.area() * 0.5), "past the edge counts as outside")
	f._grab = Vector2(40, 10)
	f.pull_out(Vector2i(4000, 300))
	_check(f.window != null and f._carrying and f.window.position == Vector2i(3960, 290) and app.dock.place_of("compendium") == "window", "pulled past the edge: its own window, still in the hand")
	f.carry_to(Vector2i(4100, 320))
	_check(f.window.position == Vector2i(4060, 310), "it follows the mouse")
	f.drop_at(Vector2i(4100, 320))
	_check(f.window != null and not f._carrying and int(f.place.win[0]) == 4060, "let go beside the program: it stays a window there")
	f.start_carry(Vector2i(40, 10))
	var main_win := app.get_window()
	f.drop_at(main_win.position + Vector2i(main_win.size / 2))
	_check(f.window == null and app.dock.place_of("compendium") == "float" and str(f.place.dock) == "float", "let go over the program: docked again, floating there")
	var cfg := ConfigFile.new()
	cfg.load(f.place_file)
	var saved: Dictionary = cfg.get_value("panel_compendium", "place", {})
	_check(not bool(saved.get("window", true)) and (saved.get("win", []) as Array).size() == 4 and str(saved.get("dock", "")) == "float", "where it is and its window's rect are remembered (%s)" % [saved])
	f.pop_out()
	await process_frame
	var chat: ChatBox = app.table_ui.chat
	_check(chat is DockPanel and chat.has_method("pull_out"), "the chat docks the same way (one DockPanel)")
	var popped := ConfigFile.new()
	popped.load(f.place_file)
	_check(bool((popped.get_value("panel_compendium", "place", {}) as Dictionary).get("window", false)), "popped out: next time it comes back in its own window")
	button.pressed.emit()  # closed again
	await process_frame
	# --- Dragging between the windows (Godot ends it as "not dropped") ------------------------
	button.pressed.emit()
	app._view_buttons.world.pressed.emit()
	await process_frame
	(app.dock.panels.compendium.frame as DockPanel).pop_out()
	(app.dock.panels.world.frame as DockPanel).pop_out()
	var comp_win := (app.dock.panels.compendium.frame as DockPanel).window
	var book_win := (app.dock.panels.world.frame as DockPanel).window
	var comp: Compendium = app.books.compendium
	if not comp.db.is_loaded:
		await comp.db.loaded
	for i in 5:
		await process_frame
	var card := comp.find_children("*", "EntryCard", true, false).filter(func(c: EntryCard) -> bool: return str(c.entry.get("_kind", "")) == "creatures").front() as EntryCard
	_check(card != null, "a monster card in the compendium window")
	var outside := []
	EntryDrag.hub.dropped_outside.connect(func(e: Dictionary, _at: Vector2i, from: Viewport) -> void: outside.append([e, from]))
	if card != null:
		var at := card.get_global_rect().get_center()
		_mouse(comp_win, at, true)
		for step in 6:
			await process_frame
			_motion(comp_win, at + Vector2(12 * (step + 1), 0))
		await process_frame
		_check(comp_win.gui_is_dragging(), "a real drag started in the compendium window")
		_mouse(comp_win, Vector2(-40, -40), false)  # let go outside the window
		await process_frame
		_check(outside.size() == 1 and outside[0][0] == card.entry and outside[0][1] == comp_win, "let go outside its window: the app hears about it")
		# The book window under the mouse imports it (with the dialog).
		book_win.position = Vector2i(3000, 100)
		var into_book := app.drop_outside(card.entry, Vector2i(3100, 200), comp_win)
		_check(into_book and app.books.world.find_child("ImportDialog", true, false) != null, "over the Book window: the import dialog")
		# Over the main window: a token on the map.
		book_win.position = Vector2i(5000, 100)
		comp_win.position = Vector2i(6000, 100)
		var main := app.get_window()
		var before := app.table.event_log.events.size()
		var on_map := app.drop_outside(card.entry, main.position + Vector2i(main.size / 2), comp_win)
		_check(on_map and app.table.event_log.events.size() > before, "over the main window: placed on the map")
	app.esc_menu.open()
	app.esc_menu.button("End the session").pressed.emit()
	await process_frame
	_check(app.view == "" and app.start.visible, "Leave goes back to the start screen")
	print("minimal: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _mouse(w: Window, at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	ev.global_position = at
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	w.push_input(ev)


func _motion(w: Window, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.relative = Vector2(12, 0)
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	w.push_input(ev)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
