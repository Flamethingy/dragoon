extends SceneTree
## Headless check of the token look (TASK-41): the composed token (ring, background, framed
## picture), defaults by kind, and the Token button's editor (move, zoom, colours, facing,
## save into the entry; read-only packages locked).
## godot --headless --path . -s tools/test_token_look.gd

const DIR := "user://test_token_look"

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base)

	# --- Composing -------------------------------------------------------------------------------
	var plain := TokenArt.compose(null, {}, "creatures").get_image()
	var mid := TokenArt.SIZE / 2
	_check(plain.get_width() == TokenArt.SIZE, "a %d px token" % TokenArt.SIZE)
	_check(plain.get_pixel(mid, mid).is_equal_approx(Color.html(TokenArt.DEFAULT_BACKGROUND)), "no picture: the background in the middle")
	_check(plain.get_pixel(mid, 3).is_equal_approx(Color.html(TokenArt.DEFAULT_BORDER.creatures)), "the border ring at the edge, by kind")
	_check(plain.get_pixel(1, 1).a == 0.0, "transparent outside the circle")
	var red := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var pic := ImageTexture.create_from_image(red)
	var framed := TokenArt.compose(pic, {"border": "#00ff00", "background": "#0000ff"}).get_image()
	_check(framed.get_pixel(mid, mid).is_equal_approx(Color.RED) and framed.get_pixel(mid, 40).is_equal_approx(Color.BLUE), "a wide picture in the middle, background above and below it")
	_check(framed.get_pixel(mid, 3).is_equal_approx(Color.GREEN), "own border colour")
	var moved := TokenArt.compose(pic, {"offset": [0.3, 0.0], "zoom": 0.5}).get_image()
	_check(not moved.get_pixel(mid - 30, mid).is_equal_approx(Color.RED) and moved.get_pixel(mid + 60, mid).is_equal_approx(Color.RED), "moved right and zoomed out")
	_check(TokenArt.compose(pic, {"border": "#00ff00", "background": "#0000ff"}) == TokenArt.compose(pic, {"border": "#00ff00", "background": "#0000ff"}), "cached")
	var s := TokenArt.style_of({"zoom": 99, "faces": "LEFT?"}, "characters")
	_check(float(s.zoom) == 6.0 and s.faces == "right" and s.border == TokenArt.DEFAULT_BORDER.characters, "styles are cleaned up (%s)" % [s])

	# --- The Token button in a book ------------------------------------------------------------------
	var core := EntryStore.open(PackageDB.default_root().path_join("5e-core-rules"))
	var mine := EntryStore.create_package(base, "my-creatures")
	mine.copy_entry(core, "creatures", "goblin")
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	root.add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = base
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	var goblin := book.db.get_entry(mine.id, "creatures", "goblin")
	var view := book.open_tab(goblin)
	await process_frame
	_check(view.token_button != null and view.token_button.visible and view.token_button.get_parent() == view.edit_button.get_parent(), "a Token button next to Edit")
	view.token_requested.emit(view.entry)
	var ed := book.find_child("TokenEditor", true, false) as TokenEditor
	_check(ed != null and not ed.get_ok_button().disabled and ed.preview.texture != null, "the token editor with a preview")
	if ed != null:
		ed.move_by(Vector2(30, -15))
		ed.zoom_slider.value = 1.5
		ed.border_pick.color_changed.emit(Color("#123456"))
		ed.faces_pick.select(1)
		ed.faces_pick.item_selected.emit(1)
		ed.confirmed.emit()
		var saved: Dictionary = EntryStore.open(mine.folder).find("creatures", "goblin").get("token_style", {})
		_check(saved.border == "#123456" and float(saved.zoom) == 1.5 and saved.faces == "left" and float(saved.offset[0]) > 0.1 and float(saved.offset[1]) < 0.0, "saved into the entry (%s)" % [saved])
		_check(book.open_view(view.key).entry.get("token_style", {}).get("border") == "#123456", "the book shows the new look")
	var source_mon := core.find("creatures", "aboleth")
	source_mon.merge({"_kind": "creatures", "_package": "5e-core-rules", "_dir": core.folder, "_layer": "core"}, true)
	var v2 := book.open_tab(source_mon)
	if v2 != null:
		var ed2 := book.open_token_editor(v2)
		_check(ed2.get_ok_button().disabled and ed2.note.visible, "read-only source package: locked, with a hint")
	print("token look: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
