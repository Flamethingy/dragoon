extends SceneTree
## Screenshot of the network table with the session notes panel, as DM (not headless):
## godot --path . --resolution 1600x950 -s tools/screenshot_notes.gd -- out.png


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path("user://screenshot_campaign"))
	await process_frame
	var table: NetTable = load("res://scenes/spikes/net_table.tscn").instantiate()
	table.log_path = "user://screenshot_campaign/events.jsonl"
	root.add_child(table)
	await process_frame
	table.host(47790)
	table._lock_buttons()
	table.event_log.advance_time(400, 14 * 60 + 30, "travel")
	table.start_next_session()
	table.add_note("The party reached the **old mill** at dusk.")
	table._handle_note(2, "Ask the miller about the goblin tracks.\n- check the barn\n- buy bread", "Player 2")
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	root.get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://notes.png")
	quit()
