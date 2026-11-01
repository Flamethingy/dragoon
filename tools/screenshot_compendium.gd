extends SceneTree
## Screenshots of the compendium with document tabs (TASK-22), not headless:
## godot --path . --resolution 1600x950 -s tools/screenshot_compendium.gd -- out_dir


var book: Compendium


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	book = Compendium.new()
	book.tabs_file = ""
	root.add_child(book)
	await book.db.loaded
	await process_frame  # the book's own _on_loaded runs after this await resumes
	book.open_tab(book.db.get_entry("5e-core-rules", "monsters", "goblin"))
	book.open_tab(book.db.resolve("Fireball"))
	book.open_tab(book.db.resolve("Aboleth"))
	await _shot(out.path_join("compendium_tab_monster.png"))
	book._tab_bar.current_tab = 1
	await _shot(out.path_join("compendium_tab_spell.png"))
	book.show_browse()
	await _shot(out.path_join("compendium_tab_browse.png"))
	book.open_tab(book.db.resolve_ref("spells/confusion"))
	RollTables.set_result("confusion-behavior", 4, 1)
	await _shot(out.path_join("compendium_table_embed.png"))
	book.open_tab(book.db.resolve_ref("tables/confusion-behavior"))
	await _shot(out.path_join("compendium_table.png"))
	quit()


func _shot(file: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("saved ", file)
