extends SceneTree
## Screenshots of the shared table as a player (not headless): start screen, character
## picker, and the table with notes. A DM table (hidden) runs in the same process.
## godot --path . --resolution 1600x950 -s tools/screenshot_table.gd -- out_folder

const DIR := "user://screenshot_table"
var _out := "user://"


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	await process_frame
	var dm := _table("DM", false)
	var me := _table("Me", true)
	await process_frame
	for cam: Node in dm.grid.find_children("*", "Camera2D", false, false):
		(cam as Camera2D).enabled = false
	dm.grid.visible = false
	await _shot("table_lobby.png")

	dm.host(47791)
	dm.event_log.advance_time(400, 14 * 60 + 30, "travel")
	me.join("127.0.0.1:47791", "Ann")
	await _until(func() -> bool: return me.pc_choices.size() == 2 and me.pc_choices.all(func(c: Dictionary) -> bool: return me.assets.has(c.image)))
	await _shot("table_picker.png")

	me.claim_pc("pcs/aria")
	await _until(func() -> bool: return me.grid.tokens.has("pcs/aria"))
	me.add_note("We reached the forest road. The wolf looks **hungry**.")
	dm.add_note("A goblin horn sounds from the trees.")
	await _until(func() -> bool: return me.notes.entries.size() == 2)
	await _shot("table_player.png")

	dm.show_map_to_all("maps/world")
	await _until(func() -> bool: return me.grid.tokens.has("party"))
	me.grid.move_requested.emit("party", Vector2i(8, 6))
	await _until(func() -> bool: return me.grid.token_cell("party") == Vector2i(8, 6))
	await create_timer(1.5).timeout
	for i in 2:
		await process_frame
	await _shot("table_world.png")
	quit()


func _table(branch: String, ui: bool) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = ui
	t.log_path = DIR + "/campaign/events.jsonl"
	t.cache_dir = DIR.path_join("cache_" + branch)
	holder.add_child(t)
	return t


func _shot(file: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(file))


func _until(done: Callable, frames := 600) -> void:
	for i in frames:
		if done.call():
			return
		await process_frame
