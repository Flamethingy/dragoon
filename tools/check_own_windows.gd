extends SceneTree
## TASK-113, not headless (own OS windows don't exist in a headless run): the app's panels open
## straight in their own borderless window (owned by the program's window), closing hides them,
## they reopen where they were (kept on a screen), dragging over the program never docks them;
## the chat still docks inside the program.
## godot --path . --resolution 1600x950 -s tools/check_own_windows.gd -- out_dir

const DIR := "user://check_own_windows"

var _failed := 0


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base)
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	Dock.layout_file = DIR.path_join("layout.json")
	var app := App.new()
	app.name = "App"
	app.worlds_root = base.path_join("worlds")
	root.add_child(app)
	await process_frame
	var red := ""
	for w: Dictionary in Worlds.list(app.worlds_root):
		red = str(w._dir).path_join("timelines/red-fang")
	app.host(red, 47813)
	for i in 30:
		await process_frame
	_check(DockPanel.native_windows, "own windows in a real run")
	for view: String in ["compendium", "notes", "rules"]:
		app.show_view(view)
		for i in 20:
			await process_frame
		var f: DockPanel = app.dock.panels[view].get("frame")
		_check(f != null and f.window != null and f.window.visible and f.window.transient and f.window.borderless,
			"%s opens in its own borderless window, owned by the program's" % view)
		_check(app.dock.place_of(view) == "window", "%s: place 'window' (%s)" % [view, app.dock.place_of(view)])
	var f: DockPanel = app.dock.panels.compendium.frame
	f.window.position = DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen()).position + Vector2i(130, 120)
	f.window.size = Vector2i(1000, 700)
	await process_frame
	f.window.get_texture().get_image().save_png(out.path_join("own_window_compendium.png"))
	var was := Rect2i(f.window.position, f.window.size)
	f.close_window()
	await process_frame
	_check(not app.dock.is_shown("compendium") and not f.window.visible, "closing its window hides it")
	app.show_view("compendium")
	for i in 10:
		await process_frame
	_check(f.window != null and f.window.visible and Rect2i(f.window.position, f.window.size) == was,
		"it reopens where it was (%s, %s)" % [Rect2i(f.window.position, f.window.size) if f.window else "none", was])
	var main := root
	f.start_carry(Vector2i(40, 10))
	f.drop_at(main.position + main.size / 2)  # let go over the program: stays a window
	await process_frame
	_check(f.window != null and app.dock.place_of("compendium") == "window", "dropped over the program it stays a window")
	f.dock_back()
	await process_frame
	_check(f.window != null and not f.visible, "it never docks back (closes instead)")
	# a place on no screen any more (a monitor unplugged): it comes back on the program's screen
	var back := f._on_a_screen(Rect2i(-40000, -40000, 900, 600))
	var on := false
	for i in DisplayServer.get_screen_count():
		on = on or DisplayServer.screen_get_usable_rect(i).has_point(back + Vector2i(10, 10))
	_check(on, "a lost place comes back onto a screen (%s)" % [back])
	var chat := app.table._ui.chat if app.table != null and app.table._ui != null else null
	_check(chat == null or not chat.always_window, "the chat still docks")
	root.get_texture().get_image().save_png(out.path_join("own_window_main.png"))
	app.leave()
	print("own windows: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
