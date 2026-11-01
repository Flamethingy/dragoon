extends SceneTree
## Headless check of packages as cards (TASK-23): package cards with badge, count and on/off
## switch, filters and search; switching off dims the card and hides the entries; the full
## view (own tab) with version, counts as links to Browse, documents (Add PDF), the grouped
## and searchable contents; export/import keeps docs/ and the size is known first.
## godot --headless --path . -s tools/test_package_cards.gd

const DIR := "user://test_package_cards"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var root := ProjectSettings.globalize_path(DIR + "/packages")
	Worlds.copy_tree("res://examples/worlds/westmarch", root.path_join("westmarch"))
	_mini_source(root.path_join("mini-source"))
	var manager := PackageManager.new(root)
	manager.set_enabled("westmarch", true)
	manager.set_enabled("mini-source", true)

	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	get_root().add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = root
	screen.add_child(book)
	await book.db.loaded
	await process_frame

	# --- Cards ------------------------------------------------------------------------------------
	var bookmark := book._tabs.get_node_or_null("Bookmark_packages") as Button
	_check(bookmark != null and bookmark.text == "Packages  2", "a Packages bookmark (%s)" % (bookmark.text if bookmark else "none"))
	bookmark.pressed.emit()
	await process_frame
	_check(book._matches.size() == 2 and not book._package.visible, "both packages as cards")
	var mini := book.entry_for("mini-source", "packages", "mini-source")
	_check(CardData.badge(mini) == ["S", "tan"] and CardData.subtitle(mini) == "Source · 3 entries", "badge and count (%s)" % CardData.subtitle(mini))
	_check(CardData.badge(book.entry_for("westmarch", "packages", "westmarch"))[0] == "W", "world badge")
	_type_filter(book, "World")
	_check(book._matches.size() == 1 and book._matches[0].id == "westmarch", "filter: world")
	_type_filter(book, "Has PDFs")
	_check(book._matches.size() == 1 and book._matches[0].id == "mini-source", "filter: has PDFs")
	_type_filter(book, "")
	book._search.text = "tiny homebrew"
	book._refresh_list()
	_check(book._matches.size() == 1 and book._matches[0].id == "mini-source", "search finds the description")
	book._search.text = ""
	book._refresh_list()

	# --- On / off ------------------------------------------------------------------------------------
	var card := _card(book, "westmarch")
	_check(card != null and card.find_child("Switch", true, false) != null, "the card has an on/off switch")
	(card.find_child("Switch", true, false) as CheckButton).button_pressed = false
	await book.db.loaded
	await process_frame
	_check(not manager.is_enabled("westmarch") and book.db.get_entry("westmarch", "npcs", "mira").is_empty(), "off: its entries are gone from the book")
	_check(book._kind == "packages" and _card(book, "westmarch") != null and _card(book, "westmarch").modulate.a < 1.0, "the card stays, dimmed")
	book.set_package_enabled("westmarch", true)
	await book.db.loaded
	await process_frame
	_check(not book.db.get_entry("westmarch", "npcs", "mira").is_empty(), "on again: entries are back")

	# --- Full view ---------------------------------------------------------------------------------
	mini = book.entry_for("mini-source", "packages", "mini-source")
	var view := book.open_tab(mini)
	await process_frame
	var text := _texts(view)
	_check(text.contains("version 1.2.0") and text.contains("Monsters 2") and text.contains("Imported from"), "version, counts and origin (%s)" % text.left(300))
	_check(_bbcode(view).contains("pkgkind:mini-source/monsters") and _bbcode(view).contains("pdf:mini-source/docs/Mini%20Rules.pdf"), "counts and PDF links are links")
	_check(not view.edit_button.visible and not view.send_button.visible, "no Edit / Send on a package")
	_check(view.documents_box.find_child("Doc_Mini Rules.pdf".validate_node_name(), true, false) != null and _texts(view.documents_box).contains("Mini Rules"), "the PDF is listed")
	_check(_texts(view.documents_box).contains("KB") or _texts(view.documents_box).contains("bytes"), "with its size")
	var contents := view.contents
	_check(contents != null and contents.groups.has("monsters") and contents.groups.has("features"), "contents grouped by kind")
	_check(contents.find_child("Cards_monsters", true, false).get_child_count() == 2 and contents.find_child("Cards_features", true, false) == null, "features start collapsed")
	contents.toggle("features")
	_check(contents.find_child("Cards_features", true, false) != null, "a group opens")
	contents.set_query("ogre")
	_check(contents.find_child("Cards_monsters", true, false).get_child_count() == 1 and contents.find_child("Group_features", true, false) == null, "search inside the package")
	contents.set_query("")
	var first: EntryCard = contents.find_child("Cards_monsters", true, false).get_child(0)
	first.pressed.emit(first.entry)
	_check(book.current_tab_key() == "mini-source/monsters/" + str(first.entry.id), "a card opens in its own tab")

	# Counts link to Browse filtered.
	book._follow("pkgkind:mini-source/monsters", view.entry, true)
	_check(book.current_tab_key() == "" and book._kind == "monsters" and book._matches.size() == 2 and book._matches.all(func(e: Dictionary) -> bool: return e._package == "mini-source"), "count link: Browse filtered to the package")

	# Add PDF.
	var pdf := ProjectSettings.globalize_path(DIR + "/Another Book.pdf")
	_write_bytes(pdf, "%PDF-1.4 another".to_utf8_buffer())
	var doc := book.add_pdf("mini-source", pdf)
	_check(doc.get("file") == "docs/Another Book.pdf" and FileAccess.file_exists(root.path_join("mini-source/docs/Another Book.pdf")), "Add PDF copies into docs/")
	_check(manager.documents("mini-source").size() == 2 and _texts(book.open_view(EntryView.key_of(mini)).documents_box).contains("Another Book"), "...lists it in the manifest and the view")
	_check(book.add_pdf("mini-source", pdf).get("file") == "docs/Another Book (2).pdf", "a second copy gets its own name")

	# A package tab survives a reload (tabs come back).
	book.set_package_enabled("westmarch", false)
	await book.tabs_restored
	_check(book.open_view(EntryView.key_of(mini)) != null, "the package tab is back after a reload")
	book.set_package_enabled("westmarch", true)
	await book.tabs_restored

	# --- Export / import with docs ------------------------------------------------------------------
	var size := manager.package_size("mini-source")
	_check(size > 0 and size >= 3 * 16, "size known before export (%s)" % PackageManager.size_text(size))
	var file := ProjectSettings.globalize_path(DIR + "/mini.dragoonpkg")
	_check(manager.export_package("mini-source", file) == OK, "export")
	var info := manager.inspect(file)
	_check(info.ok and "mini-source/docs/Mini Rules.pdf" in info.files and "mini-source/docs/Another Book.pdf" in info.files, "the export holds docs/ (%s)" % [info.files])
	var other := PackageManager.new(ProjectSettings.globalize_path(DIR + "/other"))
	DirAccess.make_dir_recursive_absolute(other.root)
	_check(other.install(file).ok and FileAccess.file_exists(other.root.path_join("mini-source/docs/Mini Rules.pdf")), "import unpacks docs/")
	_check(other.documents("mini-source").all(func(d: Dictionary) -> bool: return d.exists), "and the documents are there")

	print("package cards: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _mini_source(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder.path_join("docs"))
	_write_bytes(folder.path_join("docs/Mini Rules.pdf"), "%PDF-1.4 tiny test file".to_utf8_buffer())
	EntryStore._write(folder.path_join("package.json"), {"format": "dragoon-package", "format_version": 1, "id": "mini-source",
		"name": "Mini Source", "kind": "source", "version": "1.2.0", "created": "2026-11-01T12:00:00",
		"imported_from": "test", "description": "A tiny homebrew book.\n\n## PDFs\n[Mini Rules](<docs/Mini Rules.pdf>)",
		"counts": {"monsters": 2, "features": 1},
		"documents": [{"file": "docs/Mini Rules.pdf", "title": "Mini Rules", "size": 23}]})
	EntryStore._write(folder.path_join("monsters.json"), [
		{"id": "ogre-cook", "name": "Ogre Cook", "source": "Mini", "image": "", "size": "Large", "type": "Giant", "cr": 2, "hp": 59, "ac": 11, "actions": ["ladle"], "description": ""},
		{"id": "pixie-clerk", "name": "Pixie Clerk", "source": "Mini", "image": "", "size": "Tiny", "type": "Fey", "cr": 0.25, "hp": 2, "ac": 15, "actions": [], "description": ""}])
	EntryStore._write(folder.path_join("features.json"), [
		{"id": "ladle", "name": "Ladle", "source": "Mini", "text": "Melee Weapon Attack: +6 to hit.", "used_by": ["ogre-cook"]}])


func _write_bytes(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _type_filter(book: Compendium, value: String) -> void:
	var i := book._type_values.find(value)
	book._type.selected = i + 1 if i >= 0 else 0
	book._refresh_list()


func _card(book: Compendium, id: String) -> EntryCard:
	for c in book._grid.get_children():
		if (c as EntryCard).entry.get("id") == id:
			return c
	return null


func _texts(node: Node) -> String:
	var out := ""
	for c in node.find_children("*", "", true, false):
		if c is RichTextLabel:
			out += (c as RichTextLabel).get_parsed_text() + "\n"
		elif c is Label:
			out += (c as Label).text + "\n"
	return out


func _bbcode(node: Node) -> String:
	var out := ""
	for c in node.find_children("*", "RichTextLabel", true, false):
		out += (c as RichTextLabel).text
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
