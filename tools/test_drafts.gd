extends SceneTree
## Headless check of drafts (TASK-30): the flag (missing = published, always written), new
## entries saved as draft or published, Publish / Back to draft with their features and tables,
## drafts hidden from lists, search, links, suggestions and players; "Show drafts" in the
## binder and a package's contents with marked cards; the Drafts page grouped by package and
## kind with last edit, missing fields and its count on the bookmark.
## godot --headless --path . -s tools/test_drafts.gd

const DIR := "user://test_drafts"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var root := ProjectSettings.globalize_path(DIR + "/packages")
	var vale := root.path_join("vale")
	_package(vale)
	var camp := _timeline(vale)

	# --- The flag -------------------------------------------------------------------------------------
	var store := EntryStore.open(vale)
	_check(not EntryStore.is_draft(store.find("monsters", "goblin")) and not store.find("monsters", "goblin").has("draft"), "no flag = published")
	store.save("monsters", store.find("monsters", "goblin"))
	_check(_raw(vale, "monsters", "goblin").has("draft") and _raw(vale, "monsters", "goblin").draft == false, "saving always writes draft")
	var made := store.create("spells", "Mud Bolt")
	_check(EntryStore.is_draft(store.find("spells", made.id)) and str(store.find("spells", made.id).get("edited", "")) != "", "new entries start as drafts, with the last edit")
	_check(Schema.missing("spells", store.find("spells", made.id)) == PackedStringArray(["school", "description"]), "required fields that are empty")
	_check(Schema.fields("monsters", store.find("monsters", "hag")).all(func(f: Dictionary) -> bool: return f.key not in ["draft", "edited"]), "draft and edited are not form fields")

	# Publish / back to draft with parts.
	_check(store.draft_parts("monsters", "hag") == [["features", "hag-claws"], ["tables", "hag-moods"]], "a draft's own features and tables (%s)" % [store.draft_parts("monsters", "hag")])
	var r := store.publish("monsters", "hag")
	_check(r.has("published") and not EntryStore.is_draft(store.find("monsters", "hag")) and not store.find("monsters", "hag").has("edited"), "publish")
	_check(not EntryStore.is_draft(store.find("features", "hag-claws")) and not EntryStore.is_draft(store.find("tables", "hag-moods")), "features and tables go live with it")
	_check(EntryStore.is_draft(store.unpublish("monsters", "hag")) and not EntryStore.is_draft(store.find("features", "hag-claws")), "back to draft (parts stay)")

	# --- Hidden in the book ------------------------------------------------------------------------------
	var db := PackageDB.new()
	db.load_now(root)
	_check(db.list("monsters").size() == 1 and db.list("monsters", true).size() == 2, "drafts are out of the lists (in with drafts)")
	_check(db.resolve("Bog Hag").is_empty() and db.resolve_ref("monsters/hag").is_empty(), "wikilinks and refs don't find drafts")
	_check(not db.get_entry("vale", "monsters", "hag").is_empty(), "...but the editor can still open it by id")
	_check(not db.suggest("bog").has("Bog Hag"), "no suggestion for drafts")
	_check("spells" not in db.kinds() and "spells" in db.kinds_with(true), "a kind with only drafts has no bookmark")
	_check(db.draft_count() == 2, "draft count (%d)" % db.draft_count())

	# Players never get drafts.
	var campaign := Timeline.new(camp)
	_check(campaign.entry_view("npcs/spy", Reveal.DM).size() > 0 and campaign.entry_view("npcs/spy", "p1").is_empty(), "players don't get a draft entry")
	_check(campaign.pc_choices({}).size() == 1 and campaign.pc_choices({})[0].id == "pcs/ash", "draft PCs are not offered")

	# --- In the binder --------------------------------------------------------------------------------
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	get_root().add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = root
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	var drafts_tab := book._tabs.get_node_or_null("Bookmark_drafts") as Button
	_check(drafts_tab != null and drafts_tab.text == "Drafts  2", "Drafts bookmark with its count (%s)" % (drafts_tab.text if drafts_tab else "none"))
	book._select_kind("monsters")
	_check(book._matches.size() == 1, "drafts hidden in Browse")
	book._search.text = "hag"
	book._refresh_list()
	_check(book._matches.is_empty(), "...and in search")
	book._search.text = ""
	book.set_show_drafts(true)
	_check(book._matches.size() == 2, "Show drafts brings them in")
	var hag_card := _card(book, "hag")
	_check(hag_card != null and hag_card.find_child("DraftTag", true, false) != null, "marked as Draft")
	_check(book._tabs.get_children().any(func(b: Button) -> bool: return b.text.begins_with("Spells")), "kinds with only drafts get a bookmark while shown")
	book.set_show_drafts(false)
	_check(book._matches.size() == 1, "and leave again")

	# A package's contents.
	var pkg_view := book.open_tab(book.entry_for("vale", "packages", "vale"))
	await process_frame
	_check(pkg_view.contents.groups.monsters.size() == 1 and not pkg_view.contents.groups.has("spells"), "contents without drafts")
	(pkg_view.contents.find_child("ShowDrafts", true, false) as CheckBox).button_pressed = true
	_check(pkg_view.contents.groups.monsters.size() == 2 and pkg_view.contents.groups.has("spells"), "contents with Show drafts")

	# --- The Drafts page ------------------------------------------------------------------------------
	(book._tabs.get_node("Bookmark_drafts") as Button).pressed.emit()
	await process_frame
	var page := book.open_view("/drafts/drafts").drafts_page
	_check(page != null and page.groups.has("vale") and page.groups.vale.has("monsters") and page.groups.vale.has("spells"), "grouped by package and kind")
	var cards := page.find_child("Cards_vale_spells", true, false)
	var card := cards.get_child(0) as EntryCard if cards and cards.get_child_count() > 0 else null
	_check(card != null and _texts(card).contains("Spell · ") and _texts(card).contains("Missing: school, description"), "cards show kind, last edit, missing fields (%s)" % (_texts(card) if card else ""))
	_check(not book.open_view("/drafts/drafts").send_button.visible, "no Send on the Drafts page")

	# --- The editor ------------------------------------------------------------------------------------
	var hag_view := book.open_tab(book.db.get_entry("vale", "monsters", "hag"))
	_check(not hag_view.send_button.visible, "drafts can't be sent")
	var form := book.start_edit(hag_view)
	_check(form.find_child("Publish", true, false) != null and form.find_child("SaveDraft", true, false) == null, "a draft has Publish")
	form.publish()
	_check(not book.db.get_entry("vale", "monsters", "hag").is_empty() and not book.db.resolve("Bog Hag").is_empty(), "published: in the book again")
	_check(book._tabs.get_node("Bookmark_drafts").text == "Drafts  1" and page.groups.vale.get("monsters", []).is_empty(), "the Drafts page and count follow")
	form = book.start_edit(book.open_view(EntryView.key_of(book.db.get_entry("vale", "monsters", "hag"))))
	_check(form.find_child("BackToDraft", true, false) != null, "a published entry has Back to draft")
	form.back_to_draft()
	_check(book.db.resolve("Bog Hag").is_empty() and EntryStore.is_draft(EntryStore.open(vale).find("monsters", "hag")), "back to draft hides it again")

	# New entry: Save as draft / Save; same name asks when publishing.
	var nform := book.create_entry(EntryStore.open(vale), "monsters", "Goblin")
	_check(nform.is_new and nform.find_child("SaveDraft", true, false) != null, "new entry: Save as draft and Save")
	(nform.find_child("SaveDraft", true, false) as Button).pressed.emit()
	_check(EntryStore.is_draft(EntryStore.open(vale).find("monsters", "goblin-2")), "Save as draft keeps it a draft")
	nform = book.start_edit(book.open_view("vale/monsters/goblin-2"))
	_check(nform != null and nform.find_child("Publish", true, false) != null, "saved draft: Publish next time")
	nform.publish()
	await process_frame
	_check(nform.find_child("DuplicateQuestion", false, false) is ConfirmationDialog, "a published Goblin exists: asks")
	nform.publish(EntryStore.KEEP_BOTH)
	_check(_published_named(EntryStore.open(vale), "Goblin") == 2 and book.db.list("monsters").filter(func(e: Dictionary) -> bool: return e.name == "Goblin").size() == 2, "keep both: two Goblins in the book")

	print("drafts: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _raw(folder: String, kind: String, id: String) -> Dictionary:
	for e: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(kind + ".json"))):
		if e.id == id:
			return e
	return {}


func _published_named(store: EntryStore, entry_name: String) -> int:
	return store.list("monsters").filter(func(e: Dictionary) -> bool: return e.name == entry_name and not EntryStore.is_draft(e)).size()


func _card(book: Compendium, id: String) -> EntryCard:
	for c in book._grid.get_children():
		if (c as EntryCard).entry.get("id") == id:
			return c
	return null


func _texts(node: Node) -> String:
	var out := ""
	for c in node.find_children("*", "Label", true, false):
		out += (c as Label).text + "\n"
	return out


func _package(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	EntryStore._write(folder.path_join("package.json"), {"format": "dragoon-package", "format_version": 1, "id": "vale",
		"name": "Vale", "kind": "world", "version": "0.1.0"})
	EntryStore._write(folder.path_join("monsters.json"), [
		{"id": "goblin", "name": "Goblin", "type": "Humanoid", "cr": 0.25, "hp": 7, "ac": 15, "actions": [], "description": "Small."},
		{"id": "hag", "name": "Bog Hag", "type": "Fey", "cr": 3, "hp": 45, "ac": 14, "actions": ["hag-claws"], "description": "Mire.",
			"draft": true, "edited": "2026-11-01T14:30:00"}])
	EntryStore._write(folder.path_join("features.json"), [
		{"id": "hag-claws", "name": "Claws", "text": "Melee Weapon Attack: +5 to hit.", "draft": true}])
	EntryStore._write(folder.path_join("tables.json"), [
		{"id": "hag-moods", "name": "Hag Moods", "dice": "d4", "rows": [{"min": 1, "max": 4, "cells": ["Grumpy"]}],
			"parent": "monsters/hag", "draft": true}])


func _timeline(world: String) -> String:
	var dir := Timeline.create(world, "Camp")
	var tl := Timeline.new(dir)
	tl.add_entry("npcs", {"id": "spy", "name": "Spy", "description": "Secret.", "draft": true})
	tl.add_entry("pcs", {"id": "ash", "name": "Ash"})
	tl.add_entry("pcs", {"id": "wip", "name": "Not Ready", "draft": true})
	return dir


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
