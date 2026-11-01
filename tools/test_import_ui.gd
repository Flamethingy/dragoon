extends SceneTree
## Headless check of the import UI (TASK-28) against tools/fake_import_agent.py: a job runs as
## its own process with the API key only in its environment, its log and status are followed,
## drafts are cropped, accepted (origin kept, features along, read-only target unlocked),
## duplicates replace / keep both / skip, discards; the window, review, drag & drop and the
## "Import from link" button; a new world package as target.
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
	_check(job.has("id") and str(job.status) == "starting", "the job starts (%s)" % job)
	var s := await _wait_done(jobs, str(job.id))
	_check(str(s.status) == "done" and not s.running, "...and finishes (%s)" % s.get("status"))
	_check(str(s.log).contains("Reading Stat Block.png (image)") and str(s.log).contains("4 drafts ready"), "its progress log (%s)" % s.get("log"))
	_check(str(s.log).contains("API key: yes") and str(s.log).contains("Key in arguments: no"), "the key goes in by environment only")
	_check(OS.get_environment("ANTHROPIC_API_KEY") != KEY, "...and is not left in the VTT's environment")
	_check(not _tree_contains(base.path_join("data"), KEY), "the key is nowhere in data/ (job, drafts, packages)")
	_check(jobs.jobs().size() == 1 and jobs.jobs()[0].id == job.id, "the job is listed")

	# --- Drafts ---------------------------------------------------------------------------------------
	var drafts := jobs.draft_entries(str(job.id))
	_check(drafts.size() == 4 and drafts.all(func(d: Dictionary) -> bool: return d.kind == "monsters"), "4 drafts, features come with their monsters")
	var cropped := jobs.crop(str(job.id), "monsters", "bog-hag", Rect2i(50, 60, 100, 120))
	var art := jobs.job_dir(str(job.id)).path_join("art/bog-hag.jpg")
	_check(cropped.get("image") == "art/bog-hag.jpg" and FileAccess.file_exists(art), "crop writes art/<id>.jpg")
	var art_img := Image.load_from_file(art)
	_check(art_img != null and art_img.get_size() == Vector2i(100, 120), "with the dragged size")
	_check(cropped.get("crop") == [50, 60, 100, 120], "the crop is kept on the draft")
	_check(jobs.crop(str(job.id), "monsters", "bog-hag", Rect2i(500, 500, 10, 10)).is_empty(), "a crop off the page does nothing")

	var target := EntryStore.open(root.path_join("mini-source"))
	_check(target.is_read_only(), "the target starts read-only")
	var r := jobs.accept(str(job.id), "monsters", "bog-hag", target)
	var hag := target.find("monsters", "bog-hag")
	_check(r.has("merged") and not hag.is_empty(), "accept merges into the package")
	_check(not target.is_read_only(), "...unlocking the chosen source package")
	var origin: Dictionary = hag.get("origin", {})
	_check(origin.get("import") == "image" and int(origin.get("page", 0)) == 1, "the import origin is kept (%s)" % origin)
	_check(not hag.has("crop") and not hag.has("source_page"), "review-only keys are dropped")
	_check(FileAccess.file_exists(root.path_join("mini-source").path_join(str(hag.get("image", "-")))), "the picture comes along (%s)" % hag.get("image"))
	_check(not target.find("features", "bog-hag-claws").is_empty(), "and its features")
	_check(jobs.drafts(str(job.id)).find("monsters", "bog-hag").is_empty(), "the draft is gone after accepting")

	# Duplicates.
	r = jobs.accept(str(job.id), "monsters", "ogre-cook", target)
	_check(r.has("duplicate") and r.duplicate.id == "ogre-cook", "same name: asks first")
	_check(int(target.find("monsters", "ogre-cook").hp) == 59, "...and changes nothing")
	r = jobs.accept(str(job.id), "monsters", "ogre-cook", target, ImportJobs.REPLACE)
	_check(r.has("merged") and int(target.find("monsters", "ogre-cook").hp) == 60 and _named(target, "Ogre Cook") == 1, "replace keeps the id, one Ogre Cook")
	r = jobs.accept(str(job.id), "monsters", "ogre-cook-2", target, ImportJobs.KEEP_BOTH)
	_check(r.has("merged") and _named(target, "Ogre Cook") == 2, "keep both")
	r = jobs.accept(str(job.id), "monsters", "ogre-cook-3", target, ImportJobs.SKIP)
	_check(r.has("skipped") and _named(target, "Ogre Cook") == 2 and jobs.draft_entries(str(job.id)).is_empty(), "skip drops the draft")

	# --- The window --------------------------------------------------------------------------------
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	get_root().add_child(screen)
	var job2 := jobs.start(input, "mini-source")
	await _wait_done(jobs, str(job2.id))
	jobs.discard(str(job2.id), "monsters", "ogre-cook-3")
	var panel := ImportPanel.new(root)
	screen.add_child(panel)
	await process_frame
	_check(panel.key_edit.secret and panel.key_edit.text == KEY, "the key field is hidden and filled from settings")
	_check(panel.job_list.item_count == 2 and panel.job_list.get_item_text(0).contains("3 draft(s)"), "jobs with their draft counts (%s)" % panel.job_list.get_item_text(0))
	panel._select_job(str(job2.id))
	_check(panel.log_view.text.contains("4 drafts ready"), "the log of the selected job")
	var review := panel.open_review(str(job2.id))
	await process_frame
	_check(review != null and review.list.item_count == 3 and review.list.get_item_text(0).contains("Bog Hag  (in package)"), "review lists the drafts, marks names already there (%s)" % review.list.get_item_text(0))
	_check(review.crop.texture != null and review.page_label.text.contains("page 1"), "the source page beside the editor (%s)" % review.page_label.text)
	review.discard_current()
	_check(review.list.item_count == 2, "discard")
	review.accept_all()
	await process_frame
	var q := panel.find_child("Question", false, false)
	_check(q != null, "accept all asks about the duplicate")
	if q:
		(q.find_child("Choice_Skip", true, false) as Button).pressed.emit()
	await process_frame
	q = _open_question(panel)
	_check(q != null, "...for each one")
	if q:
		(q.find_child("Choice_Keep both".validate_node_name(), true, false) as Button).pressed.emit()
	await process_frame
	_check(review.list.item_count == 0 and review.status.text.contains("Everything is reviewed"), "all reviewed (%s)" % review.status.text)
	_check(_named(EntryStore.open(root.path_join("mini-source")), "Ogre Cook") == 3, "keep both added one more")
	panel.close_review()
	_check(panel._main.visible, "back to the jobs")

	# New world package as target.
	panel.set_input(input)
	panel.select_target(ImportPanel.NEW_PACKAGE)
	panel.new_name.text = "Swamp Finds"
	var job3 := panel.start()
	await _wait_done(jobs, str(job3.id))
	_check(str(job3.get("target")) == "new:Swamp Finds", "new package target")
	review = panel.open_review(str(job3.id))
	_check(review != null and review.target.layer == EntryStore.WORLD and review.target.name == "Swamp Finds", "the world package is created for the review")
	if review:
		review.accept_current()
	_check(not EntryStore.open(root.path_join("swamp-finds")).find("monsters", "bog-hag").is_empty(), "accepted into it")
	_check(str(panel.jobs.status(str(job3.id)).target) == "swamp-finds", "the job now points at it")
	var changed := [false]
	panel.changed.connect(func() -> void: changed[0] = true)
	panel.close()
	_check(changed[0], "closing after merges reloads the book")

	# Missing tool.
	ImportJobs.set_setting("agent", base.path_join("nope.py"))
	var bad := jobs.start(input, "mini-source")
	_check(str(bad.get("status")) == "failed" and str(bad.get("error")).contains("missing"), "a missing tool fails clearly")
	ImportJobs.set_setting("agent", ProjectSettings.globalize_path("res://tools/fake_import_agent.py"))

	# --- Hooks in the book -------------------------------------------------------------------------
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = root
	screen.add_child(book)
	await book.db.loaded
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
		opened.close()
	await process_frame
	book._open_packages()
	await process_frame
	var link := book.find_child("ImportLink", true, false) as Button
	_check(link != null, "Import from link in the Packages window")
	if link:
		link.pressed.emit()
	await process_frame
	_check(book.find_child("ImportPanel", false, false) != null, "...opens the import window")

	print("import ui: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _open_question(panel: Node) -> Node:
	for c in panel.get_children():
		if c.name.begins_with("Question") and not c.is_queued_for_deletion():
			return c
	return null


func _wait_done(jobs: ImportJobs, id: String) -> Dictionary:
	var s := {}
	for i in 400:
		s = jobs.status(id)
		if str(s.get("status")) in ["done", "failed"]:
			break
		await create_timer(0.05).timeout
	return s


func _named(store: EntryStore, entry_name: String) -> int:
	return store.list("monsters").filter(func(e: Dictionary) -> bool: return e.get("name") == entry_name).size()


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
		"name": "Mini Source", "kind": "source", "version": "1.0.0", "counts": {"monsters": 1}})
	EntryStore._write(folder.path_join("monsters.json"), [
		{"id": "ogre-cook", "name": "Ogre Cook", "source": "Mini", "image": "", "size": "Large", "type": "Giant", "cr": 2, "hp": 59, "ac": 11, "actions": [], "description": ""}])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
