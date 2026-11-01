extends SceneTree
## Headless check of the compendium's document tabs (TASK-22): open in a tab (no duplicates),
## full view for several kinds, links open new tabs, close / switch / Ctrl+W / Ctrl+Tab,
## scroll positions, and the tabs coming back after a restart.
## godot --headless --path . -s tools/test_compendium_tabs.gd

const TABS := "user://test_compendium_tabs.json"

var _failed := 0


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TABS))
	var book := await _book()
	_check(book.current_tab_key() == "" and book._browse.visible, "starts on Browse")

	var goblin := book.db.get_entry("5e-core-rules", "creatures", "goblin")
	var view := book.open_tab(goblin)
	_check(view != null and book.tab_keys() == PackedStringArray(["5e-core-rules/creatures/goblin"]), "goblin in its own tab")
	_check(view.visible and not book._browse.visible, "the tab is shown, the binder hidden")
	await process_frame
	await process_frame
	_check(view.size.x > 1200, "full view uses the whole width (%d)" % view.size.x)
	var texts := _texts(view)
	_check(texts.contains("Scimitar") and texts.contains("Nimble Escape") and texts.contains("Armor Class"), "stat block and features in the view")
	_check(not view.edit_button.disabled, "Edit button is enabled (TASK-21)")
	book.open_tab(goblin)
	_check(book.tab_keys().size() == 1, "opening again focuses, no duplicate")

	# Links in a full view open new tabs.
	view.link_clicked.emit("entry:5e-core-rules/features/scimitar")
	var scimitar_key := "5e-core-rules/features/scimitar"
	_check(book.tab_keys().size() == 2 and book.current_tab_key() == scimitar_key, "feature link opens a new tab (%s)" % [book.tab_keys()])
	view.link_clicked.emit("wiki:Fireball")
	_check(book.tab_keys().size() == 3 and book.current_tab_key().ends_with("/spells/fireball"), "wikilink opens a new tab (%s)" % book.current_tab_key())
	for kind in ["items", "classes", "races"]:
		var list: Array = book.db.entries.get(kind, [])
		if not list.is_empty():
			var v := book.open_tab(list[0])
			_check(v != null and _texts(v).length() > 20, "full view for %s" % kind)

	# Card gestures.
	book.show_browse()
	await process_frame
	var card: EntryCard = book._grid.get_child(0)
	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.pressed = true
	dbl.double_click = true
	card._gui_input(dbl)
	_check(book.current_tab_key() == EntryView.key_of(card.entry), "double-click on a card opens its tab")
	book.show_browse()
	await process_frame
	var mid := InputEventMouseButton.new()
	mid.button_index = MOUSE_BUTTON_MIDDLE
	mid.pressed = true
	var card2: EntryCard = book._grid.get_child(1)
	card2._gui_input(mid)
	_check(book.current_tab_key() == "" and book._tab_index(EntryView.key_of(card2.entry)) >= 0, "middle-click on a card opens its tab in the background")

	# Switching and closing.
	var n := book.tab_keys().size()
	book._tab_bar.current_tab = 0
	book._cycle_tab(-1)
	_check(book.current_tab_key() == "", "Ctrl+Shift+Tab from the first tab: Browse")
	book._cycle_tab(-1)
	_check(book.current_tab_key() == book.tab_keys()[n - 1], "and round to the last tab")
	book._cycle_tab(1)
	_check(book.current_tab_key() == "", "Ctrl+Tab from the last: Browse")
	book._tab_bar.current_tab = 1
	var keys_before := book.tab_keys()
	var ctrl_w := InputEventKey.new()
	ctrl_w.keycode = KEY_W
	ctrl_w.ctrl_pressed = true
	ctrl_w.pressed = true
	book._input(ctrl_w)
	_check(book.tab_keys().size() == n - 1 and keys_before[1] not in book.tab_keys(), "Ctrl+W closes the shown tab")
	_check(book.current_tab_key() != "", "a neighbour tab is shown")
	book.close_tab(0)
	_check(book.tab_keys().size() == n - 2 and "5e-core-rules/creatures/goblin" not in book.tab_keys(), "close button closes")
	book._tab_bar.move_tab(0, book._tab_bar.tab_count - 1)
	var order := book.tab_keys()

	# Scroll positions survive switching and a restart.
	book._tab_bar.current_tab = book._tab_index(scimitar_key) if book._tab_index(scimitar_key) >= 0 else 0
	var shown := book.open_view(book.current_tab_key())
	var long := book.db.resolve("Barbarian")  # a class: long enough to scroll
	var long_key := EntryView.key_of(long)
	book.open_tab(long)
	var gview := book.open_view(long_key)
	for i in 3:
		await process_frame
	gview.scroll_vertical = 400
	var gscroll := gview.scroll_vertical
	book.show_browse()
	book.open_tab(long)
	_check(gview.scroll_vertical == gscroll and gscroll > 0, "scroll kept when switching back (%d)" % gscroll)
	_check(shown != null, "views stay alive in the background")
	order = book.tab_keys()
	book._save_tabs()
	book.get_parent().queue_free()
	await process_frame

	var again := await _book()
	await again.tabs_restored
	_check(again.tab_keys() == order, "tabs restored in order (%s)" % [again.tab_keys()])
	_check(again.current_tab_key() == long_key, "the shown tab is restored")
	var restored := again.open_view(long_key)
	_check(restored != null and restored.scroll_vertical == gscroll, "scroll restored (%d)" % (restored.scroll_vertical if restored else -1))

	print("compendium tabs: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _book() -> Compendium:
	var book := Compendium.new()
	book.tabs_file = TABS
	var screen := SubViewport.new()  # headless windows are tiny: give the book a real screen
	screen.size = Vector2i(1600, 950)
	root.add_child(screen)
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	return book


func _texts(node: Node) -> String:
	var out := ""
	for c in node.find_children("*", "RichTextLabel", true, false):
		out += (c as RichTextLabel).get_parsed_text()
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
