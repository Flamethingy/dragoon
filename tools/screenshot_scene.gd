extends SceneTree
## Renders a scene for a few frames and saves a screenshot (not headless):
## godot --path . -s tools/screenshot_scene.gd -- res://scenes/table.tscn out.png


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: PackedScene = load(args[0] if args.size() > 0 else "res://scenes/table.tscn")
	root.add_child(scene.instantiate())
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := args[1] if args.size() > 1 else "user://screenshot.png"
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
