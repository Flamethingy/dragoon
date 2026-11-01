extends SceneTree
## Screenshots of the import window, the Drafts page and a draft with its source page in the
## editor (TASK-28/30) with the fake agent, in a scratch folder (the real data/ is not touched),
## not headless:
## godot --path . --resolution 1600x950 -s tools/screenshot_import.gd -- out_dir

const DIR := "user://screenshot_import"


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var base := ProjectSettings.globalize_path(DIR)
	var pkg_root := base.path_join("data/packages")
	Campaign._copy_tree("res://examples/packages/westmarch", pkg_root.path_join("westmarch"))
	ImportJobs.settings_file = DIR + "/settings.cfg"
	ImportJobs.set_setting("agent", ProjectSettings.globalize_path("res://tools/fake_import_agent.py"))
	var input := base.path_join("Swamp Bestiary.pdf")
	var f := FileAccess.open(input, FileAccess.WRITE)
	f.store_string("%PDF-1.4")
	f.close()
	var panel := ImportPanel.new(pkg_root)
	root.add_child(panel)
	await process_frame
	panel.set_input(input)
	var job := panel.start()
	for i in 200:
		if str(panel.jobs.status(str(job.id)).status) == "done":
			break
		await create_timer(0.05).timeout
	panel.refresh_jobs()
	await _shot(out.path_join("import_window.png"))
	panel.close()
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = pkg_root
	root.add_child(book)
	await book.db.loaded
	await process_frame
	book.open_drafts()
	await _shot(out.path_join("drafts_page.png"))
	var view := book.open_tab(book.db.get_entry("westmarch", "monsters", "bog-hag"))
	var form := book.start_edit(view)
	form.crop.selection = Rect2i(30, 40, 120, 150)
	form.crop.queue_redraw()
	view.scroll_vertical = 100000
	await _shot(out.path_join("draft_source_page.png"))
	book.show_browse()
	book.set_show_drafts(true)
	book._select_kind("monsters")
	await _shot(out.path_join("browse_show_drafts.png"))
	quit()


func _shot(file: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("saved ", file)
