extends SceneTree
## Screenshot of TASK-82, not headless: the calm table with the timeline bar docked at the top,
## a little history on it (travel, a fight on one map, another scene on a second map, a
## session), then zoomed into the fight and scrubbed back.
## godot --path . --resolution 1600x950 -s tools/screenshot_timeline.gd -- out_dir

const DIR := "user://shot_timeline"


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
	app.show_view("table")
	var table := app.table
	var log := table.event_log
	var map := table.grid.map_id
	var other := "maps/elsewhere"
	for m: String in table.timeline.maps():
		if m != map:
			other = m
	log.start_session(log.session + 1)
	for step in 4:  # travel: a few hours apart
		log.advance_time(log.day, maxi(log.time, 0) + 90, "travel")
		log.move_token("characters/borin", map, Vector2i(step, 2), Vector2i(step + 3, 2))
	log.advance_time(log.day, log.time + 30, "ambush")
	log.append("combat.started", "", {"map": map, "order": []})
	for r in range(1, 6):
		log.append("combat.turn", "", {"round": r, "turn": 0})
		log.change_hp("creatures/goblin-1", -3, 7 - r * 3, "axe")
		log.move_token("characters/mira", other, Vector2i(r, 1), Vector2i(r + 1, 1))  # meanwhile, elsewhere
	log.append("combat.ended", "", {})
	log.advance_time(log.day + 1, 480, "long rest")
	log.gain_item("characters/borin", "core:5e/items/potion-of-healing", 2)
	for i in 60:
		await process_frame
	var bar := app.table_ui.timeline_bar
	bar.line.fit()
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("timeline_bar.png"))
	# zoom into the fight and look back at round 3
	var ms := bar.line.moments()
	var fight: Array = ms.filter(func(m: Dictionary) -> bool: return m.combat)
	if not fight.is_empty():
		bar.line.span = 60.0
		bar.line.view_from = float(fight[0].at) - 10.0
		bar.line.set_cursor(int(fight[min(2, fight.size() - 1)].at))
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("timeline_zoom.png"))
	print("saved to %s" % out)
	quit()
