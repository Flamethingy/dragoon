extends SceneTree
## Screenshots of the calendar (TASK-112), not headless: the table with the date at the top
## (no timeline bar) and the calendar window after a journey and a long rest.
## godot --path . --resolution 1600x950 -s tools/screenshot_calendar.gd -- out_dir

const DIR := "user://shot_calendar"


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
	app.host(red, 47814)
	var t := app.table
	t.advance_clock(3 * 1440, "travel to Red Fang")
	t.advance_clock(480, "long rest")
	t.advance_clock(1440 + 120, "")
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("calendar_table.png"))
	var ui: TableUI = app.table_ui
	ui.open_calendar()
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	ui.calendar_view.get_texture().get_image().save_png(out.path_join("calendar_window.png"))
	app.leave()
	quit()
