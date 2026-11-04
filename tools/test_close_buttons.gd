extends SceneTree
## Headless check of the close buttons inside the program (TASK-100): the Book and the
## Compendium (floating or docked) have the window bar's X at the top right, it closes them and
## reopening brings them back where they were; the character sheet and the sheet pages have
## the same X.
## godot --headless --path . -s tools/test_close_buttons.gd

const DIR := "user://test_close_buttons"

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base.path_join("packages"))
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	Dock.layout_file = DIR.path_join("layout.json")
	root.size = Vector2i(1280, 720)
	var app := App.new()
	app.worlds_root = base.path_join("worlds")
	app.packages_root = base.path_join("packages")
	root.add_child(app)
	await process_frame
	var red := ""
	for w: Dictionary in Worlds.list(app.worlds_root):
		red = str(w._dir).path_join("timelines/red-fang")
	_check(app.host(red, 47847) == OK, "hosted")
	await process_frame

	for id: String in ["compendium", "world"]:
		var button: Button = app._view_buttons[id]
		button.pressed.emit()
		await process_frame
		var f: DockPanel = app.dock.panels[id].frame
		var x := f.find_child("PanelClose", true, false) as Button
		_check(x != null and x.visible and x is DockPanel.WindowButton and (x as DockPanel.WindowButton).kind == "close", "%s: an X like the window bar's" % id)
		_check(x != null and x.get_parent() == f._head and x.get_index() == f._head.get_child_count() - 1, "%s: at the top right" % id)
		f.dock("left")  # docked inside the program
		await process_frame
		x.pressed.emit()
		await process_frame
		_check(not app.dock.is_shown(id) and not button.button_pressed, "%s: the X closes it" % id)
		button.pressed.emit()
		await process_frame
		_check(app.dock.is_shown(id) and str(f.place.dock) == "left" and f.visible, "%s: reopened where it was (%s)" % [id, f.place.dock])
		f.pop_out()
		_check(not x.visible and f.window.find_child("Close", true, false) != null, "%s: popped out, the window's own buttons instead" % id)
		f.dock_back()
		_check(x.visible, "%s: back inside, the X again" % id)
		f.dock("float")
		x.pressed.emit()
		await process_frame
		_check(not app.dock.is_shown(id), "%s: floating, the X closes it too" % id)

	# the character sheet and the sheet pages
	var sheet: SheetPanel = app.table_ui.sheet
	sheet.show()
	var sx := sheet.find_child("Close", true, false)
	_check(sx is DockPanel.WindowButton, "the sheet: the same X")
	(sx as Button).pressed.emit()
	_check(not sheet.visible, "the sheet: the X closes it")
	var hud: CharacterHud = app.table_ui.hud
	await _until(func() -> bool: return hud.active != "")
	hud.pages.open(0)
	await process_frame
	var px := hud.pages.find_child("Close", true, false)
	_check(px is DockPanel.WindowButton and hud.pages.visible, "the sheet pages: the same X")
	if px is Button:
		(px as Button).pressed.emit()
	_check(not hud.pages.visible, "the sheet pages: the X closes them")

	app.esc_menu.open()
	app.esc_menu.button("End the session").pressed.emit()
	await process_frame
	PackageManager._delete_tree(base)
	print("close buttons: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _until(done: Callable, frames := 300) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
