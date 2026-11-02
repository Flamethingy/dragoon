extends SceneTree
## Headless check of the AI effects pass's review side (TASK-66), without the API: the tool's
## "fake" mode writes proposals as drafts next to their entries (draft_of), the estimate comes
## first, answers are checked against the format, and the Drafts page shows now vs proposed;
## Publish writes them into the entry, Discard throws one away.
## godot --headless --path . -s tools/test_ai_effects.gd

const DIR := "user://test_ai_effects"
const PROBE := "import sys\nsys.path.insert(0, r'%s')\nimport ai_effects as a\nprint(a.parse_answer('x {\"effects\": [{\"heal\": \"1d4\"}, {\"roll\": \"dance\"}, 5], \"notes\": \"ok\"} y'))\n"

var _failed := 0


func _init() -> void:
	var pkg_root := ProjectSettings.globalize_path(DIR + "/packages")
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(pkg_root)
	var store := EntryStore.create_world(pkg_root, "mini")
	store.manifest["kind"] = "source"  # the compendium's book shows source packages
	EntryStore._write(store.folder.path_join("package.json"), store.manifest)
	store.save("spells", {"id": "glow", "name": "Glow", "level": 1, "description": "A creature glows softly.", "draft": false})
	store.save("spells", {"id": "spark", "name": "Spark", "level": 0, "description": "A spark leaps.", "draft": false})
	store.save("spells", {"id": "bolt", "name": "Bolt", "level": 0, "description": "Make a ranged spell attack. On a hit it takes 1d10 fire damage.",
		"effects": [{"roll": "attack", "to_hit": "spell", "damage": [{"dice": "1d10", "type": "fire"}]}], "draft": false})
	var py := ProjectSettings.globalize_path("res://tools/ai_effects.py")
	var out := []
	OS.execute("python", [py, "estimate", "--packages", pkg_root, "--package", "mini", "--kind", "spells"], out, true)
	_check(str(out).contains("2 entries") and str(out).contains("Batch API"), "the estimate first: 2 entries without effects (%s)" % [out])
	out.clear()
	OS.execute("python", [py, "run", "--packages", pkg_root, "--package", "mini", "--kind", "spells"], out, true)
	_check(str(out).contains("not sent"), "nothing is sent without --yes")
	out.clear()
	var probe := ProjectSettings.globalize_path(DIR + "/probe.py")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	f.store_string(PROBE % py.get_base_dir())
	f.close()
	OS.execute("python", [probe], out, true)
	_check(not out.is_empty() and str(out[0]).contains("[{'heal': '1d4'}], 'ok'"), "answers are checked against the format (%s)" % [out])
	out.clear()
	OS.execute("python", [py, "fake", "--packages", pkg_root, "--package", "mini", "--kind", "spells"], out, true)
	_check(str(out).contains("wrote 2"), "fake proposals written (%s)" % [out])
	var again := EntryStore.open(pkg_root.path_join("mini"))
	var draft := again.find("spells", "glow--effects")
	_check(EntryStore.is_draft(draft) and draft.draft_of == "glow" and draft.effects == [{"heal": "1d4"}] and again.find("spells", "bolt--effects").is_empty(), "drafts next to their entries; Bolt had effects")

	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	root.add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = pkg_root
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	var page := book.open_drafts().drafts_page
	var row := page.find_child("Proposal_glow--effects", true, false)
	_check(row != null, "the Drafts page shows the proposal")
	if row != null:
		var diff := (row.get_node("Diff") as RichTextLabel).text
		_check(diff.contains("now:") and diff.contains("none (text only)") and diff.contains("heal 1d4"), "now vs proposed (%s)" % diff)
		(row.get_node("Publish") as Button).pressed.emit()
		await process_frame
	again = EntryStore.open(pkg_root.path_join("mini"))
	var glow := again.find("spells", "glow")
	_check(glow.get("effects") == [{"heal": "1d4"}] and str(glow.get("effects_source", "")) == "ai" and again.find("spells", "glow--effects").is_empty(), "Publish writes the effects into the entry (%s)" % [glow])
	_check(book.db.get_entry("mini", "spells", "glow").get("effects") == [{"heal": "1d4"}], "the book has it too")
	page = book.open_drafts().drafts_page
	row = page.find_child("Proposal_spark--effects", true, false)
	var found := row != null
	if found:
		(row.get_node("Discard") as Button).pressed.emit()
		await process_frame
	again = EntryStore.open(pkg_root.path_join("mini"))
	_check(found and again.find("spells", "spark--effects").is_empty() and not again.find("spells", "spark").has("effects"), "Discard throws it away, the entry stays as it was")
	_check(DraftsPage.summary([{"roll": "save", "ability": "dex", "dc": "spell", "on_fail": {"damage": [{"dice": "8d6", "type": "fire"}]}, "on_success": "half", "area": {"shape": "sphere", "size_m": 6}}])
		== "save DEX (DC spell): 8d6 fire · half · sphere 6 m", "the one-line summary")
	screen.queue_free()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("ai_effects: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
