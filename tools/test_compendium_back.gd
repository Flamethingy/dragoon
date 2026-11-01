extends SceneTree
## Headless check of TASK-24: background tabs (middle-click), the back arrow / Alt+Left /
## mouse back button with tab history (closing the tab it leaves, or not), the tab context
## menu, and the quick card always showing the full text.
## godot --headless --path . -s tools/test_compendium_back.gd

var _failed := 0
var book: Compendium


func _init() -> void:
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	root.add_child(screen)
	book = Compendium.new()
	book.tabs_file = ""
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	var e := func(name: String) -> Dictionary: return book.db.resolve(name)
	var key := func(name: String) -> String: return EntryView.key_of(book.db.resolve(name))

	# --- Background tabs ------------------------------------------------------------------
	book.open_tab(e.call("Goblin"))
	book.open_tab(e.call("Fireball"))
	book._tab_bar.current_tab = 0  # Goblin
	book._on_tab_changed(0)
	var view := book.open_view(key.call("Goblin"))
	view.link_background.emit("wiki:Aboleth")
	view.link_background.emit("wiki:Shield")
	_check(book.current_tab_key() == key.call("Goblin"), "middle-click keeps the current tab")
	_check(book.tab_keys() == PackedStringArray([key.call("Goblin"), key.call("Aboleth"), key.call("Shield"), key.call("Fireball")]),
		"background tabs line up after the current one (%s)" % [book.tab_keys()])
	_check(book.highlighted.has(key.call("Shield")) and book._tab_bar.get_tab_title(2).begins_with("✦"), "new background tab highlighted")
	var tabs_before := book.tab_keys().size()
	view.link_background.emit("wiki:Fireball")
	_check(book.tab_keys().size() == tabs_before and book.current_tab_key() == key.call("Goblin"), "already open: no duplicate, no switch")
	_check(book.highlighted.has(key.call("Fireball")), "the open tab is highlighted instead")
	book.show_browse()
	await process_frame
	var card: EntryCard = book._grid.get_child(0)
	card.background_requested.emit(card.entry)
	_check(book.current_tab_key() == "" and EntryView.key_of(card.entry) in book.tab_keys(), "middle-click on a card: background tab")

	# --- Back with history ------------------------------------------------------------------
	book.open_tab(e.call("Goblin"))  # Browse -> Goblin
	book.open_tab(e.call("Aboleth"))  # Goblin -> Aboleth
	book.open_tab(e.call("Fireball"))  # Aboleth -> Fireball
	_check(not book.open_view(key.call("Fireball")).back_button.disabled, "back arrow enabled with history")
	book.go_back_tab()
	_check(book.current_tab_key() == key.call("Aboleth") and book._tab_index(key.call("Fireball")) < 0, "Back closes Fireball, shows Aboleth")
	var alt_left := InputEventKey.new()
	alt_left.keycode = KEY_LEFT
	alt_left.alt_pressed = true
	alt_left.pressed = true
	book._unhandled_key_input(alt_left)
	_check(book.current_tab_key() == key.call("Goblin") and book._tab_index(key.call("Aboleth")) < 0, "Alt+Left: same, to Goblin")
	book.open_tab(e.call("Shield"))
	book.close_tab(book._tab_index(key.call("Goblin")))  # a closed tab in the history is skipped
	book.open_tab(e.call("Aboleth"))
	var mouse_back := InputEventMouseButton.new()
	mouse_back.button_index = MOUSE_BUTTON_XBUTTON1
	mouse_back.pressed = true
	book._input(mouse_back)
	_check(book.current_tab_key() == key.call("Shield"), "mouse back button, closed tabs skipped (%s)" % book.current_tab_key())
	book.back_closes_tab = false
	book.open_tab(e.call("Fireball"))
	book.go_back_tab()
	_check(book.current_tab_key() == key.call("Shield") and book._tab_index(key.call("Fireball")) >= 0, "setting off: Back only switches")
	book.back_closes_tab = true
	book.show_browse()
	book.go_back_tab()
	_check(book.current_tab_key() == "", "nothing happens on Browse")

	# --- Context menu -------------------------------------------------------------------------
	book._close_all_tabs()
	for n in ["Goblin", "Aboleth", "Fireball", "Shield", "Orc"]:
		book.open_tab(e.call(n))
	var menu := book.open_tab_menu(2)
	_check(menu.item_count >= 5 and menu.get_item_text(0) == "Close", "right-click menu (%d items)" % menu.item_count)
	book._on_tab_menu(3, 2)  # close to the right of Fireball
	_check(book.tab_keys() == PackedStringArray([key.call("Goblin"), key.call("Aboleth"), key.call("Fireball")]), "close to the right")
	book._on_tab_menu(2, 2)  # close to the left
	_check(book.tab_keys() == PackedStringArray([key.call("Fireball")]), "close to the left")
	menu = book.open_tab_menu(0)
	_check(menu.is_item_disabled(menu.get_item_index(2)) and menu.is_item_disabled(menu.get_item_index(3)), "left/right disabled when nothing is there")
	book._on_tab_menu(4, 0)
	_check(not book.back_closes_tab, "the menu toggles 'Back closes the tab'")
	book._on_tab_menu(1, 0)
	_check(book.tab_keys().is_empty() and book.current_tab_key() == "", "close all, Browse stays")

	# --- Quick card shows everything --------------------------------------------------------------
	book._show(e.call("Aboleth"))
	var texts := ""
	for c in book._detail_box.find_children("*", "RichTextLabel", true, false):
		texts += (c as RichTextLabel).get_parsed_text()
	_check(texts.contains("Legendary Actions"), "quick card has the full text")
	_check(book._detail_box.find_children("*", "Button", true, false).all(func(b: Button) -> bool: return b.text != "Full text"), "no 'Full text' fold")

	print("compendium back: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
