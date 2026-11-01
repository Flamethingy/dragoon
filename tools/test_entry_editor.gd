extends SceneTree
## Headless check of the entry editor in the compendium (TASK-21): Edit in a full-view tab,
## read-only source packages (edit a copy / unlock), form fields, feature list, Markdown
## preview and [[ suggestions, save / duplicate / delete / new, all against a temporary
## packages folder (a mini source package copied from 5e-core-rules).
## godot --headless --path . -s tools/test_entry_editor.gd

const DIR := "user://test_editor"

var _failed := 0


func _init() -> void:
	var pkg_root := ProjectSettings.globalize_path(DIR + "/packages")
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(pkg_root)
	_make_mini_source(pkg_root)

	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	root.add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = pkg_root
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	_check(book.db.count() > 1, "mini source loaded (%d)" % book.db.count())

	# --- Read-only source: Edit shows the banner, Save is off -------------------------------
	var goblin := book.db.get_entry("mini-core", "monsters", "goblin")
	var view := book.open_tab(goblin)
	view.edit_requested.emit(view.entry)
	var form := view.editor
	_check(form != null and view.is_editing(), "Edit turns the tab into the editor")
	_check(form.save_button.disabled, "source package: Save is off")
	_check(form.find_child("CopyTarget", true, false) != null, "banner offers 'edit a copy'")
	_check(form.collect().has("entry"), "the form reads back")
	view.end_edit()
	_check(not view.is_editing(), "Cancel goes back to the view")

	# --- A world package, then edit a copy -------------------------------------------------------
	var world := book.new_package("Sunken Coast")
	_check(world in book.writable_stores() and not world.is_read_only(), "a new homebrew package is writable")
	_check(book.scope() == "core" and book.find_child("TimelinePick", true, false) == null, "the compendium is the core book, no timeline picker (TASK-39)")
	var quick := book.new_entry("spells")
	_check(quick != null and book.find_child("NewEntryDialog", true, false) == null and world.list("spells").size() == 1, "New in the spells overview makes a spell right away")
	if quick != null:
		quick.cancelled.emit()
	book.new_entry("packages")
	_check(book.find_child("NewEntryDialog", true, false) != null, "without a kind it asks")
	(book.find_child("NewEntryDialog", true, false) as ConfirmationDialog).queue_free()
	form = book.start_edit(view)
	_check(world in form.copy_targets, "and offered as copy target")
	form.edit_copy_in(world)
	var wkey := "sunken-coast/monsters/goblin"
	_check(book.current_tab_key() == wkey, "the copy opens in its own tab (%s)" % book.current_tab_key())
	var wview := book.open_view(wkey)
	form = wview.editor if wview else null
	_check(form != null and not form.save_button.disabled, "editing the copy, Save is on")
	if form == null:
		_done()
		return

	# Form fields.
	_line(form, "name").text = "Goblin Boss"
	(form.find_child("Field_hp", true, false) as SpinBox).value = 21
	var stats := form.find_child("Field_stats", true, false)
	(stats.get_child(0).get_child(1) as SpinBox).value = 12  # STR
	_line(form, "senses").text = "darkvision 18 m, keen smell"
	_line(form, "saves").text = "dex +4, wis +1"
	var features: FeatureList = form.find_child("Field_actions", true, false)
	var before: Array = features.ids()
	var new_id := features.add_feature("Redirect Attack")
	_check(world.has("features", new_id) and features.ids().back() == new_id, "Add creates a feature entry (%s)" % new_id)
	features.add_feature(before[0])
	_check(features.ids().size() == before.size() + 2, "existing ids are linked, not copied")
	features.move(features.ids().size() - 2, -1)
	_check(features.ids()[features.ids().size() - 3] == new_id, "move up")
	features.remove(features.ids().size() - 1)
	_check(features.ids().size() == before.size() + 1, "remove from list")

	# Markdown preview and [[ suggestions.
	var md := form.find_child("Field_description", true, false)
	var text: CodeEdit = md.find_child("Text", true, false)
	var preview: RichTextLabel = md.find_child("Preview", true, false)
	var suggest: ItemList = md.find_child("Suggestions", true, false)
	text.text = "Leads the **pack**. Friend of [[Gob"
	text.set_caret_line(0)
	text.set_caret_column(text.get_line(0).length())
	text.text_changed.emit()
	_check(preview.get_parsed_text().contains("pack") and not preview.get_parsed_text().contains("**"), "live preview renders Markdown")
	_check(suggest.visible and suggest.item_count > 0 and suggest.get_item_text(0).begins_with("Goblin"), "[[Gob suggests Goblin...")
	EntryEditor.accept_suggestion(text, "Goblin")
	_check(text.text.ends_with("[[Goblin]]"), "accepting completes the link (%s)" % text.text)
	_check(EntryEditor.link_prefix(text) == "", "no suggestions after the link is closed")

	# Bad input is refused with a message.
	_line(form, "saves").text = "dex lots"
	_check(form.save().is_empty() and form.status.text.contains("Saves"), "bad bonus refused (%s)" % form.status.text)
	_line(form, "saves").text = "dex +4, wis +1"

	var saved := form.save()
	_check(saved.get("name") == "Goblin Boss", "saved")
	var on_disk := EntryStore.open(world.folder).find("monsters", "goblin")
	_check(on_disk.hp == 21 and on_disk.stats.str == 12 and int(on_disk.saves.dex) == 4 and int(on_disk.saves.wis) == 1 and on_disk.saves.size() == 2, "fields on disk (%s %s %s)" % [on_disk.hp, on_disk.stats, on_disk.saves])
	_check(on_disk.senses == ["darkvision 18 m", "keen smell"] and on_disk.description.ends_with("[[Goblin]]"), "lists and Markdown on disk")
	_check(new_id in on_disk.actions, "feature list on disk")
	_check(not wview.is_editing() and book.db.get_entry("sunken-coast", "monsters", "goblin").name == "Goblin Boss", "back to the view, the book knows the new name")
	_check(book._tab_bar.get_tab_title(book._tab_index(wkey)) == "Goblin Boss", "tab title follows")
	_check(book.db.get_entry("mini-core", "monsters", "goblin").name == "Goblin", "the source is untouched")

	# Feature "Edit" opens the feature in its own tab.
	form = book.start_edit(wview)
	features = form.find_child("Field_actions", true, false)
	form.open_requested.emit(world, "features", new_id)
	_check(book.current_tab_key() == "sunken-coast/features/" + new_id and book.open_view(book.current_tab_key()).is_editing(), "feature opens for editing")
	var fform := book.open_view(book.current_tab_key()).editor
	(fform.find_child("Field_text", true, false).find_child("Text", true, false) as CodeEdit).text = "When a creature the boss can see targets it..."
	fform.save()
	_check(world.find("features", new_id).text.begins_with("When a creature"), "feature text saved")

	# Duplicate and delete.
	book._tab_bar.current_tab = book._tab_index(wkey)
	form.duplicate_entry()
	var dkey := book.current_tab_key()
	_check(dkey.begins_with("sunken-coast/monsters/goblin-boss") and world.has("monsters", dkey.get_file()), "duplicate opens (%s)" % dkey)
	var dform := book.open_view(dkey).editor
	dform.delete_entry()
	_check(not world.has("monsters", dkey.get_file()) and book._tab_index(dkey) < 0 and book.db.get_entry("sunken-coast", "monsters", dkey.get_file()).is_empty(), "delete removes file entry, tab and card")

	# New entry of a new kind: a draft first (TASK-30); published, a bookmark appears.
	var nform := book.create_entry(world, "npcs", "Mira")
	_check(nform != null and world.has("npcs", "mira") and "npcs" in book.db.kinds_with(true) and "npcs" not in book.db.kinds(), "new NPC in the world, as a draft")
	_check(nform.find_child("SaveDraft", true, false) != null, "a new entry offers Save as draft")
	_check(nform.find_child("Field_attitude", true, false) is TokenField, "NPC form has its own fields (attitude as tokens)")
	nform.publish()
	_check("npcs" in book.db.kinds() and not EntryStore.is_draft(world.find("npcs", "mira")), "Save publishes it")
	_check(book._tabs.get_children().any(func(b: Button) -> bool: return b.text.begins_with("Npcs")), "Npcs bookmark added")

	# Unlocking the source package.
	book._tab_bar.current_tab = book._tab_index("mini-core/monsters/goblin")
	form = book.start_edit(view)
	var unlock: Button = form.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Unlock").front()
	unlock.pressed.emit()
	_check(not form.save_button.disabled and not EntryStore.open(pkg_root.path_join("mini-core")).is_read_only(), "Unlock makes the source editable")
	_done()


func _done() -> void:
	print("entry editor: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)


func _line(form: EntryEditor, key: String) -> LineEdit:
	return form.find_child("Field_" + key, true, false) as LineEdit


## A small read-only source package: goblin (+ features) and the aboleth from 5e-core-rules.
func _make_mini_source(folder: String) -> void:
	var core := EntryStore.open(PackageDB.default_root().path_join("5e-core-rules"))
	var mini := EntryStore.create_world(folder, "mini-core")
	for id in ["goblin", "aboleth"]:
		mini.copy_entry(core, "monsters", id)
	mini.manifest["kind"] = "source"
	mini.manifest["name"] = "Mini Core"
	EntryStore._write(mini.folder.path_join("package.json"), mini.manifest)
