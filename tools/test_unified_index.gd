extends SceneTree
## Headless check of the unified index (TASK-6, TASK-32): timeline + world + core in one PackageDB
## with priority timeline > world > core for names ([[wikilinks]]) and refs; load time with all
## packages; the compendium showing timeline entries and editing them (session edits as events).
## godot --headless --path . -s tools/test_unified_index.gd

const DIR := "user://test_index"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var campaign := Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	# The timeline's own Mira (an override of the world's entry, entity.edited).
	var tl := Timeline.new(campaign)
	var mira := tl.entry("characters/mira").duplicate(true)
	mira["description"] = "Mira, as she is in the Red Fang Road."
	tl.edit_entry("characters", mira)

	# --- All packages + the example timeline: load time -------------------------------------
	var all := PackageDB.new()
	all.timeline_dir = campaign
	var t0 := Time.get_ticks_msec()
	all.load_now()
	var msec := Time.get_ticks_msec() - t0
	print("unified index: %d entries from %d packages + timeline in %d ms" % [all.count(), all.packages.size() - 1, msec])
	_check(msec < 2000, "loads in under 2 s, no cache needed (%d ms)" % msec)
	_check(all.get_entry("red-fang", "creatures", "goblin-chief").get("_layer") == "timeline", "timeline entries are in the index")
	_check(all.get_entry("5e-core-rules", "creatures", "goblin").get("_layer") == "core", "core entries are marked core")
	_check(all.resolve("Dire Wolf").get("_layer") == "timeline", "[[Dire Wolf]]: the timeline's wolf wins over core")
	_check(all.resolve("Goblin").get("_layer") == "core", "[[Goblin]]: only in core, found there")
	_check(all.resolve_ref("creatures/dire-wolf").get("_package") == "red-fang", "ref creatures/dire-wolf -> timeline")
	_check(all.resolve_ref("core:5e-core-rules/creatures/dire-wolf").get("_layer") == "core", "core: ref skips the timeline")
	_check(not "notes" in all.kinds(), "timeline notes are not cards")
	_check(all.packages.any(func(p: Dictionary) -> bool: return p.get("kind") == "timeline"), "the timeline is listed as a source")

	# --- With the timeline's world (data/worlds next to the packages) ---------------------------
	var root := ProjectSettings.globalize_path(DIR + "/packages")
	DirAccess.make_dir_recursive_absolute(root)
	var other := EntryStore.create_world(root, "Other World")
	var other_mira := other.create("characters", "Mira")
	var db := PackageDB.new()
	db.timeline_dir = campaign
	db.load_now(root)
	_check(db.timeline_world == "westmarch", "the timeline's world")
	_check(db.packages.filter(func(p: Dictionary) -> bool: return p.get("id") == "westmarch").size() == 1, "the world is loaded from data/worlds")
	_check(db.resolve("Mira Hollowell").get("_layer") == "timeline", "[[Mira]]: timeline > world")
	_check(db.resolve_ref("world:characters/mira").get("_package") == "westmarch", "world: ref -> the timeline's world, not another")
	_check(db.resolve_ref("places/westmarch").get("_layer") == "world", "only in the world: found there")
	db.timeline_dir = ""
	db.load_now(root)
	_check(db.resolve("Mira Hollowell").get("_layer") == "world" and db.get_entry("red-fang", "characters", "mira").is_empty(), "without a timeline: worlds and core only")
	_check(other_mira.id == "mira", "(another world's Mira exists too)")

	# --- Compendium with the timeline: cards, editor, session events ----------------------------
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	root_window().add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = root
	book.timeline_dir = campaign
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	_check("characters" in book.db.kinds() and book._tabs.get_children().any(func(b: Button) -> bool: return b.text.begins_with("Characters")), "timeline kinds get bookmarks")
	var stores: Array = book.writable_stores()
	_check(stores.any(func(s: EntryStore) -> bool: return s.layer == EntryStore.TIMELINE), "the timeline is a writable store")
	_check(book.event_log != null, "standalone: the timeline's own event log")
	_check(book.db.suggest("aria w").has("Aria Windrunner"), "[[ suggestions include timeline names")
	var chief := book.db.get_entry("red-fang", "creatures", "goblin-chief")
	var view := book.open_tab(chief)
	var form := book.start_edit(view)
	_check(form != null and not form.save_button.disabled, "timeline entry opens in the editor")
	book.event_log.start_session(1)
	(form.find_child("Field_hp", true, false) as SpinBox).value = 5
	form.save()
	var ev: Dictionary = book.event_log.events.back()
	_check(ev.type == "sheet.changed" and ev.entity == "creatures/goblin-chief" and ev.data.path == "hp", "session edit -> sheet.changed (%s)" % ev)
	book.event_log.end_session()

	# The table's DM opens the compendium with the same log.
	var table := NetTable.new()
	table.name = "Table"
	table.auto_ui = false
	table.timeline_dir = campaign
	root_window().add_child(table)
	await process_frame
	table.host(47790)
	var ui := TableUI.new()
	ui.table = table
	root_window().add_child(ui)
	await process_frame
	var overlay := ui.open_compendium()
	_check(overlay.event_log == table.event_log and overlay.timeline_dir == campaign and overlay.closable, "table: compendium with the table's log")
	await overlay.db.loaded
	overlay.close_requested.emit()
	_check(not overlay.visible, "closing it hides it")
	table.multiplayer.multiplayer_peer.close()

	print("unified index: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func root_window() -> Window:
	return get_root()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
