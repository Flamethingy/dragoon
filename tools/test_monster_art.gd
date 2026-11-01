extends SceneTree
## Headless check of monster pictures (TASK-26): the entry's image when it loads (also JPEGs
## named .png), else the creature type icon (unknown.svg for other types), missing or broken
## files fall back quietly; the icon credits are in the app.
## godot --headless --path . -s tools/test_monster_art.gd

const DIR := "user://test_monster_art"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir.path_join("assets"))

	# --- Type icons ---------------------------------------------------------------------------------
	var icon := func(t: String) -> String:
		var tex := CardArt.type_icon({"type": t})
		return tex.resource_path.get_file() if tex else ""
	_check(icon.call("Humanoid") == "humanoid.svg" and icon.call("Monstrosity (Titan)") == "monstrosity.svg", "types map to icons")
	_check(icon.call("swarm of Tiny beasts") == "beast.svg", "swarms use their creature type")
	_check(icon.call("Abomination") == "unknown.svg" and icon.call("") == "unknown.svg", "other types: unknown.svg")
	for t in CardArt.TYPES:
		_check(icon.call(t) == t + ".svg", "%s has its icon" % t)

	# --- Decoding by content ------------------------------------------------------------------------
	var img := Image.create(40, 30, false, Image.FORMAT_RGB8)
	img.fill(Color.ORANGE)
	img.save_jpg(dir.path_join("assets/really-a-jpeg.png"))
	img.save_png(dir.path_join("assets/ogre.png"))
	_check(ImageCache.decode(FileAccess.get_file_as_bytes(dir.path_join("assets/really-a-jpeg.png"))) != null, "a JPEG named .png loads")
	var junk := FileAccess.open(dir.path_join("assets/broken.png"), FileAccess.WRITE)
	junk.store_string("<html>not an image</html>")
	junk.close()
	_check(ImageCache.decode(FileAccess.get_file_as_bytes(dir.path_join("assets/broken.png"))) == null, "a broken file is no image (quietly)")
	_check(ImageCache.decode(PackedByteArray()) == null, "an empty file too")

	# --- Cards ----------------------------------------------------------------------------------------
	var with_image := _art({"_kind": "monsters", "name": "Ogre", "type": "Giant", "image": "assets/ogre.png", "_dir": dir})
	var misnamed := _art({"_kind": "monsters", "name": "Pot", "type": "Construct", "image": "assets/really-a-jpeg.png", "_dir": dir})
	var missing := _art({"_kind": "monsters", "name": "Ghost", "type": "Undead", "image": "assets/nope.png", "_dir": dir})
	var broken := _art({"_kind": "monsters", "name": "Blob", "type": "Ooze", "image": "assets/broken.png", "_dir": dir})
	var none := _art({"_kind": "monsters", "name": "Thing", "type": "Abomination", "image": "", "_dir": dir})
	var spell := _art({"_kind": "spells", "name": "Fireball", "image": ""})
	for i in 60:
		await process_frame
		if with_image.texture != null and misnamed.texture != null:
			break
	_check(with_image.texture != null and misnamed.texture != null, "monsters with an image show it")
	_check(missing.texture == null and missing.icon != null and missing.icon.resource_path.ends_with("undead.svg"), "missing file: the type icon")
	_check(broken.texture == null and broken.icon.resource_path.ends_with("ooze.svg"), "broken file: the type icon")
	_check(none.icon.resource_path.ends_with("unknown.svg"), "no image, odd type: unknown icon")
	_check(spell.icon == null, "other kinds keep the initial")

	# --- Credits --------------------------------------------------------------------------------------
	var credits := Compendium.credits_text()
	_check(credits.contains("game-icons.net") and credits.contains("CC BY 3.0") and credits.contains("delapouite"), "credits text")
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	root.add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	screen.add_child(book)
	await book.db.loaded
	_check(book.find_child("Credits", true, false) is Button, "a Credits button on the cover")
	var dialog := book.show_credits()
	await process_frame
	_check(dialog.visible and _dialog_text(dialog).contains("CC BY 3.0"), "the credits dialog shows them")

	print("monster art: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _art(e: Dictionary) -> CardArt:
	var art := CardArt.new()
	art.size = Vector2(150, 118)
	root.add_child(art)
	art.show_entry(e)
	return art


func _dialog_text(dialog: AcceptDialog) -> String:
	for c in dialog.find_children("*", "RichTextLabel", true, false):
		return (c as RichTextLabel).get_parsed_text()
	return ""


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
