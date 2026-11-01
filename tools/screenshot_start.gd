extends SceneTree
## Screenshot of the start screen (TASK-38), not headless:
## godot --path . --resolution 1600x950 -s tools/screenshot_start.gd -- out_dir

const DIR := "user://shot_start"


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base.path_join("packages"))
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	ServerStatus.save_servers([{"name": "Thursday group", "address": "127.0.0.1", "port": 7777},
		{"name": "Old table", "address": "127.0.0.1", "port": 7790}])
	var app := App.new()
	app.name = "App"
	app.worlds_root = base.path_join("worlds")
	app.packages_root = base.path_join("packages")
	root.add_child(app)
	await process_frame
	app.start.create_world("Sunken Coast", "default")
	for i in 90:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("start_screen.png"))
	quit()
