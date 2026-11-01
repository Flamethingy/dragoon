extends SceneTree
## Screenshot of the Packages window over the compendium (not headless):
## godot --path . --resolution 1600x950 -s tools/screenshot_packages.gd -- out.png


func _init() -> void:
	var book: Compendium = load("res://scenes/compendium/compendium.tscn").instantiate()
	root.add_child(book)
	while not book.db.is_loaded:
		await process_frame
	book.open_packages()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	root.get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://packages.png")
	quit()
