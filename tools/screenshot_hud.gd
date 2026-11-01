extends SceneTree
## Screenshots of the character HUD (TASK-47): the default HUD, a sheet page (key 1), the HUD
## editor (F2) and the page editor (F3). A DM table (hidden) runs in the same process.
## godot --path . --resolution 1600x950 -s tools/screenshot_hud.gd -- out_folder

const DIR := "user://screenshot_hud"
var _out := "user://"


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	await process_frame
	var dm := _table("DM", false)
	var me := _table("Me", true)
	await process_frame
	for cam: Node in dm.grid.find_children("*", "Camera2D", false, false):
		(cam as Camera2D).enabled = false
	dm.grid.visible = false
	dm.host(47795)
	me.join("127.0.0.1:47795", "Ann")
	await _until(func() -> bool: return me.my_pc == "characters/aria" and me.sheets.has("characters/aria"))
	me._ui.minimal = true
	me._ui._refresh()
	var hud: CharacterHud = me._ui.hud
	await _shot("hud_default.png")
	hud.pages.open(0)
	await _shot("hud_page.png")
	hud.pages.close()
	hud.edit_hud()
	hud.editor.add("skills")
	hud.editor.add("abilities")
	await _shot("hud_editor.png")
	hud.editor.finish(true)
	await _until(func() -> bool: return hud.layout().size() == 5)
	await _shot("hud_custom.png")
	hud.edit_pages()
	await _shot("hud_page_editor.png")
	hud.editor.finish(false)
	quit()


func _table(branch: String, ui: bool) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = ui
	t.timeline_dir = DIR + "/worlds/westmarch/timelines/red-fang"
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
