extends SceneTree
## Screenshots of a group token (TASK-115/116): the stack, fanned out on hover with the face
## under the mouse grown, a member dragged out of the fan, the + hint of a drop onto a token.
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
	var st := g.tokens[ref].get_node("Stack") as GroupStack
	g._hover(g.tokens[ref].position)
	g._hover(g.tokens[ref].position + st.spots()[0].at)
	await _shot("group_fanned.png")
	g._member_grab(g.tokens[ref].position + st.spots()[0].at)
	g.member_drag.position = g.tokens[ref].position + Vector2(g.cell * 1.6, g.cell * 1.4)
	await _shot("group_member_drag.png")
	g.member_drag.visible = false
	var single: Array = g.tokens.keys().filter(func(id: String) -> bool: return not id.begins_with(NetTable.GROUP_PREFIX) and "/" in id)
	if not single.is_empty():
		g._show_join_hint(ref)
		await _shot("group_join_hint.png")
	quit()


func _shot(file: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(file))
