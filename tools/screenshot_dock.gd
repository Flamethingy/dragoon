extends SceneTree
## Screenshots of the panels around the table (TASK-37), not headless: the session log on the
## right, notes on the left, events at the bottom, the compendium in its own window.
## godot --path . --resolution 1600x950 -s tools/screenshot_dock.gd -- out_dir

const DIR := "user://shot_dock"


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
	app.host(red, 47811)
	for v: String in ["notes", "events", "compendium"]:
		app.show_view(v)
	for i in 120:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("dock_table.png"))
	var w := app.dock.panels.compendium.window as Window
	if w != null:
		w.get_texture().get_image().save_png(out.path_join("dock_compendium_window.png"))
	app.leave()
	quit()
