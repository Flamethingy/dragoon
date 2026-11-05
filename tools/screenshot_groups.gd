extends SceneTree
## Screenshots of a group token (TASK-115): the stack, fanned out on hover, its ring.
## godot --path . --resolution 1600x950 -s tools/screenshot_groups.gd -- out_folder

const DIR := "user://screenshot_groups"
var _out := "user://"


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	await process_frame
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var dm := NetTable.new()
	dm.name = "Table"
	dm.timeline_dir = DIR + "/worlds/westmarch/timelines/red-fang"
	dm.cache_dir = DIR.path_join("cache")
	holder.add_child(dm)
	await process_frame
	dm.host(47795)
	var g := dm.grid
	var ids: Array = g.tokens.keys().filter(func(id: String) -> bool: return id != NetTable.PARTY and "/" in id)
	ids = ids.slice(0, 3)
	dm.group_tokens(ids)
	var ref: String = g.tokens.keys().filter(func(id: String) -> bool: return id.begins_with(NetTable.GROUP_PREFIX))[0]
	var cam := g._camera
	cam.position = g.tokens[ref].position
	cam.zoom = Vector2.ONE * 1.8
	await _shot("group_stack.png")
	(g.tokens[ref].get_node("Stack") as GroupStack).fanned = true
	await _shot("group_fanned.png")
	(g.tokens[ref].get_node("Stack") as GroupStack).fanned = false
	g.open_ring(ref)
	await _shot("group_ring.png")
	quit()


func _shot(file: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(file))
