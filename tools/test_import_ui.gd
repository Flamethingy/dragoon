extends SceneTree
## Headless check of the import UI (TASK-28, drafts flow TASK-30) against
## tools/fake_import_agent.py: a job runs as its own process with the API key only in its
## environment, its log and status are followed; a finished job lands in the target package as
## drafts (features, pictures and source pages along, ids that are taken renamed, read-only
## target unlocked, a new world package created); crop from the source page; publishing asks
## about same names (replace / keep both / skip); the window, drag & drop, "Import from link",
## "Show drafts" and "Publish all" per import job in the book.
## godot --headless --path . -s tools/test_import_ui.gd

const DIR := "user://test_import"
const KEY := "sk-ant-test-0123456789"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var base := ProjectSettings.globalize_path(DIR)
	var root := base.path_join("data/packages")
	DirAccess.make_dir_recursive_absolute(root)
	_mini_source(root.path_join("mini-source"))
	ImportJobs.settings_file = DIR + "/settings.cfg"
	ImportJobs.set_setting("api_key", KEY)
	ImportJobs.set_setting("python", "python")
	ImportJobs.set_setting("agent", ProjectSettings.globalize_path("res://tools/fake_import_agent.py"))
	var input := base.path_join("Stat Block.png")
	Image.create(20, 20, false, Image.FORMAT_RGB8).save_png(input)

	# --- Inputs ---------------------------------------------------------------------------------
	_check(ImportJobs.input_kind("a/B.PDF") == "pdf" and ImportJobs.input_kind("x.webp") == "image"
		and ImportJobs.input_kind("https://example.com/hag") == "url" and ImportJobs.input_kind("notes.txt") == "", "input kinds")
	var jobs := ImportJobs.new(root)
	_check(jobs.imports_root == base.path_join("data/imports"), "jobs live in data/imports")
	_check(jobs.start(base.path_join("notes.txt"), "mini-source").has("error"), "other files are refused")
	_check(jobs.start(base.path_join("missing.pdf"), "mini-source").has("error"), "a missing file is refused")

	# --- A job --------------------------------------------------------------------------------------
	var job := jobs.start(input, "mini-source")
	var job_id := str(job.get("id", ""))
	_check(job.has("id") and str(job.status) == "starting", "the job starts (%s)" % job)
	var s := await _wait_done(jobs, job_id)
	_check(str(s.status) == "done" and not s.running, "...and finishes (%s)" % s.get("status"))
	_check(str(s.log).contains("Reading Stat Block.png (image)") and str(s.log).contains("4 drafts ready"), "its progress log (%s)" % s.get("log"))
	_check(str(s.log).contains("API key: yes") and str(s.log).contains("Key in arguments: no"), "the key goes in by environment only")
	_check(OS.get_environment("ANTHROPIC_API_KEY") != KEY, "...and is not left in the VTT's environment")
	_check(jobs.jobs().size() == 1 and jobs.jobs()[0].id == job_id, "the job is listed")

	# --- Merged as drafts -------------------------------------------------------------------------------
	var target := EntryStore.open(root.path_join("mini-source"))
	_check(target.is_read_only(), "the target starts read-only")
	var m := jobs.merge(job_id)
	target = EntryStore.open(root.path_join("mini-source"))
	_check(m.get("package") == "mini-source" and int(m.get("count", 0)) == 5, "a finished job lands in the package (%s)" % m)
	_check(not target.is_read_only(), "...unlocking the chosen source package")
	var hag := target.find("creatures", "bog-hag")
	_check(EntryStore.is_draft(hag) and hag.origin.get("job") == job_id and hag.origin.get("import") == "image", "as drafts with origin and job (%s)" % hag.get("origin"))
	_check(EntryStore.is_draft(target.find("features", "bog-hag-claws")), "features come along as drafts")
	var page_rel := str(hag.get("source_page", ""))
	_check(page_rel == "imports/%s/pages/1.png" % job_id and FileAccess.file_exists(root.path_join("mini-source").path_join(page_rel)), "the source page is copied (%s)" % page_rel)
	var cooks := target.list("creatures").filter(func(e: Dictionary) -> bool: return e.name == "Ogre Cook")
	_check(cooks.size() == 4 and not EntryStore.is_draft(target.find("creatures", "ogre-cook")) and int(target.find("creatures", "ogre-cook").hp) == 59, "a taken id gets a new one, the old entry stays")
	_check(bool(jobs.status(job_id).merged) and int(jobs.merge(job_id).get("count", -1)) == 0, "merged once only")
	_check(str(jobs.status(job_id).log).contains("5 draft(s) put into Mini Source"), "the log says so")
	_check(not _tree_contains(base.path_join("data"), KEY), "the key is nowhere in data/ (job, drafts, packages)")

	# Crop from the page.
	var cropped := target.crop_picture("creatures", "bog-hag", Rect2i(50, 60, 100, 120))
	var art_img := Image.load_from_file(root.path_join("mini-source/art/bog-hag.jpg"))
	_check(cropped.get("image") == "art/bog-hag.jpg" and art_img != null and art_img.get_size() == Vector2i(100, 120), "crop writes art/<id>.jpg with the dragged size")
	_check(target.crop_picture("creatures", "bog-hag", Rect2i(500, 500, 10, 10)).is_empty(), "a crop off the page does nothing")

	# Publishing.
	var r := target.publish("creatures", "bog-hag")
	_check(r.has("published") and not EntryStore.is_draft(target.find("creatures", "bog-hag")), "publish")
	_check(not EntryStore.is_draft(target.find("features", "bog-hag-claws")), "...with its features")
	var draft_ids: Array = cooks.filter(func(e: Dictionary) -> bool: return EntryStore.is_draft(e)).map(func(e: Dictionary) -> String: return str(e.id))
	r = target.publish("creatures", draft_ids[0])
	_check(r.has("duplicate") and r.duplicate.id == "ogre-cook", "same name: asks first")
	r = target.publish("creatures", draft_ids[0], EntryStore.REPLACE)
	_check(r.has("published") and int(target.find("creatures", "ogre-cook").hp) == 60 and target.find("creatures", draft_ids[0]).is_empty(), "replace takes the old id")
	r = target.publish("creatures", draft_ids[1], EntryStore.KEEP_BOTH)
	_check(r.has("published") and _published(target, "Ogre Cook") == 2, "keep both")
	r = target.publish("creatures", draft_ids[2], EntryStore.SKIP)
	_check(r.has("skipped") and target.find("creatures", draft_ids[2]).is_empty() and _published(target, "Ogre Cook") == 2, "skip throws the draft away")

	# --- The window --------------------------------------------------------------------------------
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	get_root().add_child(screen)
	var job2 := jobs.start(input, "mini-source")
	await _wait_done(jobs, str(job2.id))
	var panel := ImportPanel.new(root)
	screen.add_child(panel)
	await process_frame
	_check(panel.key_edit.secret and panel.key_edit.text == KEY, "the key field is hidden and filled from settings")
	_check(panel.job_list.item_count == 2 and panel.job_list.get_item_text(0).contains("5 draft(s) in mini-source"), "the window merges finished jobs (%s)" % panel.job_list.get_item_text(0))
	panel._select_job(str(job2.id))
	_check(panel.log_view.text.contains("put into Mini Source"), "the log of the selected job")
	var asked := [false]
	panel.drafts_requested.connect(func() -> void: asked[0] = true)
	(panel.find_child("ShowDrafts", true, false) as Button).pressed.emit()
	_check(asked[0], "Show drafts asks for the Drafts page")

	# New world package as target.
	panel = ImportPanel.new(root)
	screen.add_child(panel)
	await process_frame
	panel.set_input(input)
	panel.select_target(ImportPanel.NEW_PACKAGE)
	panel.new_name.text = "Swamp Finds"
	var job3 := panel.start()
	_check(str(job3.get("target")) == "new:Swamp Finds", "new package target")
	await _wait_done(jobs, str(job3.id))
	panel.refresh_jobs()
	var swamp := EntryStore.open(PackageManager.new(root).folder_of("swamp-finds"))
	_check(swamp != null and swamp.layer == EntryStore.SOURCE and not swamp.is_read_only() and EntryStore.is_draft(swamp.find("creatures", "bog-hag")), "a new editable book package gets the drafts (TASK-39)")
	_check(str(jobs.status(str(job3.id)).target) == "swamp-finds", "the job now points at it")
	var changed := [false]
	panel.changed.connect(func() -> void: changed[0] = true)
	panel.close()
	_check(changed[0], "closing after merges reloads the book")

	# Missing tool.
	ImportJobs.set_setting("agent", base.path_join("nope.py"))
	var bad := jobs.start(input, "mini-source")
	_check(str(bad.get("status")) == "failed" and str(bad.get("error")).contains("missing"), "a missing tool fails clearly")
	ImportJobs.set_setting("agent", ProjectSettings.globalize_path("res://tools/fake_import_agent.py"))

	# --- In the book -------------------------------------------------------------------------------
	var job4 := jobs.start(input, "swamp-finds")
	await _wait_done(jobs, str(job4.id))  # finished while the book was closed
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = root
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	_check(bool(jobs.status(str(job4.id)).get("merged", false)), "the book merges jobs that finished while it was closed")
	var pdf := base.path_join("Book.pdf")
	var f := FileAccess.open(pdf, FileAccess.WRITE)
	f.store_string("%PDF-1.4")
	f.close()
	book._on_files_dropped(PackedStringArray([base.path_join("notes.txt")]))
	_check(book.find_child("ImportPanel", false, false) == null, "dropping other files does nothing")
	book._on_files_dropped(PackedStringArray([pdf]))
	var opened := book.find_child("ImportPanel", false, false) as ImportPanel
	_check(opened != null and opened.input_edit.text == pdf, "dropping a PDF opens the import window with it")
	if opened:
		opened.show_drafts()
	await process_frame
	await process_frame
	_check(book.current_tab_key() == "/drafts/drafts", "Show drafts opens the Drafts page (%s)" % book.current_tab_key())
	book.open_packages()
	await process_frame
	var link := book.find_child("ImportLink", true, false) as Button
	_check(link != null and link.is_visible_in_tree(), "Import from link over the package cards")
	if link:
		link.pressed.emit()
	await process_frame
	_check(book.find_child("ImportPanel", false, false) != null, "...opens the import window")
	(book.find_child("ImportPanel", false, false) as ImportPanel).close()

	# The editor shows the source page of an imported draft.
	var draft_hag: Dictionary = book.db.get_entry("swamp-finds", "creatures", "bog-hag")
	var view := book.open_tab(draft_hag)
	var form := book.start_edit(view)
	_check(form != null and form.find_child("SourcePage", true, false) is CropView and form.crop.texture != null, "the editor shows the source page")
	form.crop.selection = Rect2i(10, 10, 60, 80)
	form.apply_crop()
	_check(str(EntryStore.open(PackageManager.new(root).folder_of("swamp-finds")).find("creatures", "bog-hag").get("image")) == "art/bog-hag.jpg", "and crops the picture")
	form.cancelled.emit()

	# Publish all from one import job (no clashes in the new package for job3's own copies).
	var drafts_page := book.open_drafts().drafts_page
	var job_button := drafts_page.find_child("PublishJob_" + str(job3.id).validate_node_name(), true, false) as Button
	_check(job_button != null, "Publish all per import job on the Drafts page")
	if job_button:
		job_button.pressed.emit()
	await process_frame
	var q := book.find_child("DuplicateQuestion", false, false) as ConfirmationDialog
	_check(q != null, "publishing the second Ogre Cook asks")
	var guard := 0
	while q != null and guard < 5:
		q.custom_action.emit(&"keep")
		await process_frame
		q = book.find_child("DuplicateQuestion", false, false) as ConfirmationDialog
		guard += 1
	var swamp_after := EntryStore.open(PackageManager.new(root).folder_of("swamp-finds"))
	var left := swamp_after.list("creatures").filter(func(e: Dictionary) -> bool: return EntryStore.is_draft(e) and e.origin.get("job") == str(job3.id))
	_check(left.is_empty() and _published(swamp_after, "Ogre Cook") == 3, "every draft of that job is published (%s left)" % [left.map(func(e: Dictionary) -> String: return str(e.id))])
	_check(swamp_after.list("creatures").any(func(e: Dictionary) -> bool: return EntryStore.is_draft(e) and e.origin.get("job") == str(job4.id)), "the other job's drafts stay drafts")

	print("import ui: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _wait_done(jobs: ImportJobs, id: String) -> Dictionary:
	var s := {}
	for i in 400:
		s = jobs.status(id)
		if str(s.get("status")) in ["done", "failed"]:
			break
		await create_timer(0.05).timeout
	return s


func _published(store: EntryStore, entry_name: String) -> int:
	return store.list("creatures").filter(func(e: Dictionary) -> bool: return e.get("name") == entry_name and not EntryStore.is_draft(e)).size()


func _tree_contains(folder: String, text: String) -> bool:
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() in ["json", "log", "md", "cfg", "txt"] and FileAccess.get_file_as_string(folder.path_join(file)).contains(text):
			return true
	for sub in DirAccess.get_directories_at(folder):
		if _tree_contains(folder.path_join(sub), text):
			return true
	return false


func _mini_source(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	EntryStore._write(folder.path_join("package.json"), {"format": "dragoon-package", "format_version": 1, "id": "mini-source",
		"name": "Mini Source", "kind": "source", "version": "1.0.0", "counts": {"creatures": 1}})
	EntryStore._write(folder.path_join("creatures.json"), [
		{"id": "ogre-cook", "name": "Ogre Cook", "source": "Mini", "image": "", "size": "Large", "type": "Giant", "cr": 2, "hp": 59, "ac": 11, "actions": [], "description": ""}])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
