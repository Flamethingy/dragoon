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
	_check(shown == ["compendium"] and app._bar.find_child("Leave", true, false).visible, "only Compendium and Leave (%s)" % [shown])
	_check(app._bar.anchor_left == 1.0, "at the top right")
	_check(not app.table_ui._bar.visible and not app.dock.panels.keys().any(app.dock.is_shown), "no table bar, no panels")
	_check(not app.table.show_map_info, "no help line on the map")
	var button: Button = app._view_buttons.compendium
	button.pressed.emit()
	await process_frame
	_check(app.dock.place_of("compendium") == "window" and button.button_pressed, "Compendium opens its own window")
	button.pressed.emit()
	await process_frame
	_check(not app.dock.is_shown("compendium") and not button.button_pressed, "pressed again: closed")
	button.pressed.emit()
	await process_frame
	(app.dock.panels.compendium.window as Window).close_requested.emit()
	await process_frame
	_check(not app.dock.is_shown("compendium"), "closing the window closes it too")
	(app._bar.find_child("Leave", true, false) as Button).pressed.emit()
	await process_frame
	_check(app.view == "" and app.start.visible, "Leave goes back to the start screen")
	print("minimal: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
