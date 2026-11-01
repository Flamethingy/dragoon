extends SceneTree
## Screenshots of the entry editor (TASK-21), not headless. Uses the packages folder left by
## tools/test_entry_editor.gd (run that first):
## godot --path . --resolution 1600x950 -s tools/screenshot_editor.gd -- out_dir

var book: Compendium


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	book = Compendium.new()
	book.tabs_file = ""
	book.packages_root = ProjectSettings.globalize_path("user://test_editor/packages")
	root.add_child(book)
	await book.db.loaded
	await process_frame
	var store := EntryStore.open(book.packages_root.path_join("sunken-coast"))
	book.edit_entry(store, "monsters", "goblin")
	await _shot(out.path_join("editor_monster.png"))
	var form := book.open_view(book.current_tab_key()).editor
	form.find_child("Field_actions", true, false)
	book.open_view(book.current_tab_key()).scroll_vertical = 900
	await _shot(out.path_join("editor_monster_2.png"))
	book.edit_entry(store, "npcs", "mira")
	var md := book.open_view(book.current_tab_key()).editor.find_child("Field_description", true, false)
	var text: CodeEdit = md.find_child("Text", true, false)
	text.text = "The smith of **Thornwick**. Friend of [[Gob"
	text.set_caret_column(text.get_line(0).length())
	text.text_changed.emit()
	await _shot(out.path_join("editor_npc.png"))
	quit()


func _shot(file: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("saved ", file)
