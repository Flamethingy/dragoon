extends SceneTree
## Screenshots of TASK-80, not headless: the calm table with the Compendium and the Book
## floating over the map like the chat (docked right), then the Book docked at the bottom.
## godot --path . --resolution 1600x950 -s tools/screenshot_float.gd -- out_dir

const DIR := "user://shot_float"


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
	app.host(red, 47812)
	app.show_view("compendium")
	for i in 90:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("float_compendium.png"))
	app.show_view("world")
	(app.dock.panels.world.frame as DockPanel).dock("bottom")
	(app.dock.panels.compendium.frame as DockPanel).dock("float", Rect2i(2, 2, 20, 14))
	for i in 60:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("float_book_bottom.png"))
	app.leave()
	quit()
