extends SceneTree
## Headless check of the active character HUD (TASK-44): portrait with HP and spell slots in
## the lower left, ability / save / skill check panels next to it (a click rolls into the chat), Q / E round robin through the tokens one controls,
## clicks don't change it, the HUD's sheet does not pop up the sheet panel.
## godot --headless --path . -s tools/test_character_hud.gd

const PORT := 47787
const ADDRESS := "127.0.0.1:47787"
const DIR := "user://test_hud"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	# --- Spell slots from the classes ---------------------------------------------------------
	_check(CharacterHud.spell_slots({"classes": [{"class": "classes/wizard", "level": 5}]}) == [4, 3, 2], "wizard 5")
	_check(CharacterHud.spell_slots({"classes": [{"class": "classes/ranger", "level": 3}]}) == [2], "ranger 3: half caster")
	_check(CharacterHud.spell_slots({"classes": [{"class": "classes/paladin", "level": 1}]}) == [], "paladin 1: none yet")
	_check(CharacterHud.spell_slots({"classes": [{"class": "classes/warlock", "level": 5}]}) == [0, 0, 2], "warlock 5: pact slots at level 3")
	_check(CharacterHud.spell_slots({"classes": [{"class": "classes/wizard", "level": 1}, {"class": "classes/paladin", "level": 2}]}) == [3], "multiclass caster level")
	_check(CharacterHud.spell_slots({"spell_slots": [1, 1], "classes": [{"class": "classes/wizard", "level": 9}]}) == [1, 1], "own spell_slots win")
	_check(CharacterHud.spell_slots({"classes": [{"class": "classes/fighter", "level": 9}]}) == [], "no caster, no slots")

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	var borin := tl.entry("characters/borin").duplicate(true)
	borin.erase("player")
	borin["owners"] = ["ann", "bob"]  # Ann plays Aria and helps with Borin
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc == "characters/aria" and ann.grid.tokens.has("characters/aria") and ann.grid.tokens.has("characters/borin"))
	var hud: CharacterHud = ann._ui.hud
	await _until(func() -> bool: return hud.active == "characters/aria" and ann.sheets.has("characters/aria"))
	_check(hud.active == "characters/aria" and hud.visible, "Ann's own character is active")
	await process_frame
	_check(_hp(hud).begins_with("27 / 27"), "HP on the portrait (%s)" % _hp(hud))
	_check(_name(hud) == "Aria Windrunner", "name under the portrait")
	_check(hud.find_child("W_portrait", true, false) != null and hud.find_child("W_hp", true, false) != null and hud.find_child("W_slots", true, false) != null
		and hud.find_child("W_skills", true, false) == null, "no layout yet: portrait, health and spell slots (TASK-47)")
	# key 1: the first sheet page, with the checks
	var one := InputEventKey.new()
	one.pressed = true
	one.physical_keycode = KEY_1
	hud._input(one)
	_check(hud.pages.visible and hud.pages.current == 0, "1 opens the first sheet page")
	_check(hud.pages.find_child("W_abilities", true, false) != null and hud.pages.find_child("W_skills", true, false) != null, "the default page has the checks")
	var stealth: Button = hud.pages.find_child("stealth", true, false)
	_check(stealth != null and stealth.text == "Stealth +5", "skills with the sheet's bonus (%s)" % (stealth.text if stealth else "none"))
	var dex_save: Button = hud.pages.find_child("dex_save", true, false)
	_check(dex_save != null and dex_save.text == "DEX  +5", "saves (%s)" % (dex_save.text if dex_save else "none"))
	var str_check: Button = hud.pages.find_child("str_check", true, false)
	_check(str_check != null and str_check.text == "STR  10  +0", "abilities with score and modifier (%s)" % (str_check.text if str_check else "none"))
	stealth.pressed.emit()
	await _until(func() -> bool: return ann.rolls.size() == 1)
	_check(ann.rolls.size() == 1 and str(ann.rolls[0].who) == "Aria Windrunner" and str(ann.rolls[0].results[0].label) == "Stealth", "a click rolls it for the active one (%s)" % [ann.rolls])
	# the chat: messages and rolls in one feed
	ann._ui.minimal = true
	ann._ui._refresh()
	var chat: ChatBox = ann._ui.chat
	_check(chat.visible, "the chat on the calm table")
	chat.line.text = "Hello from Aria!"
	chat.send()
	await _until(func() -> bool: return dm.rolls.size() == 2 and ann.rolls.size() == 2)
	_check(str(dm.rolls[1].get("text", "")) == "Hello from Aria!" and dm.rolls[1].by == "ann", "the DM gets the message")
	await process_frame
	_check(chat.log_text.get_parsed_text().contains("Hello from Aria!") and chat.log_text.get_parsed_text().contains("Stealth"), "the chat shows messages and rolls")
	chat.line.text = "/r 2d6+3"
	chat.send()
	await _until(func() -> bool: return ann.rolls.size() == 3)
	_check(ann.rolls.size() == 3 and str(ann.rolls[2].results[0].formula) == "2d6+3", "/r rolls")
	dm.say("A goblin horn sounds.")
	await _until(func() -> bool: return ann.rolls.size() == 4)
	_check(ann.rolls.size() == 4 and ann.rolls[3].by == "dm", "the DM writes too")
	hud._input(one)
	_check(not hud.pages.visible, "1 again closes it")
	_check(_slots(hud).get_child_count() == 1 and _slots(hud).get_child(0).get_child_count() == 3, "ranger 3: two level 1 slots")
	_check(not ann._ui.sheet.visible, "the HUD's sheet does not open the sheet panel")
	_check(Array(hud.controlled()) == ["characters/aria", "characters/borin"], "Ann controls Aria and Borin (%s)" % [hud.controlled()])

	# Q / E round robin
	var e_key := InputEventKey.new()
	e_key.pressed = true
	e_key.physical_keycode = KEY_E
	hud._input(e_key)
	_check(hud.active == "characters/borin", "E: next one")
	await _until(func() -> bool: return ann.sheets.has("characters/borin"))
	await process_frame
	_check(_name(hud) == "Borin Stoneshield" and _hp(hud).begins_with("24 / 24"), "Borin's portrait (%s)" % _hp(hud))
	_check(_slots(hud).get_child_count() == 2, "cleric 3: level 1 and 2 slots")
	hud.cycle(1)
	_check(hud.active == "characters/aria", "round robin back to Aria")
	var q_key := e_key.duplicate() as InputEventKey
	q_key.physical_keycode = KEY_Q
	hud._input(q_key)
	_check(hud.active == "characters/borin", "Q: the other way")

	# a selection with the active one keeps it; Q / E only go through the selected ones
	ann.grid.select(["characters/borin", "characters/aria"])
	await process_frame
	_check(hud.active == "characters/borin", "a selection with the active one keeps it")
	var aria_marks: TokenMarks = ann.grid.tokens["characters/aria"].get_node("Marks")
	var borin_marks: TokenMarks = ann.grid.tokens["characters/borin"].get_node("Marks")
	_check(borin_marks.active and aria_marks.selected and not aria_marks.active, "three marks: active orange, selected white")
	_check(Array(hud.cycle_list()) == ["characters/aria", "characters/borin"], "the selected ones to cycle (%s)" % [hud.cycle_list()])
	hud.cycle(1)
	_check(hud.active == "characters/aria" and aria_marks.active and not borin_marks.active, "E goes to the next selected token, the orange ring follows")
	# a selection without the active one: its first token becomes active
	ann.grid.select(["characters/borin"])
	await process_frame
	_check(hud.active == "characters/borin", "selecting a group without the active one switches to its first")
	hud.cycle(1)
	_check(hud.active == "characters/borin", "and Q / E stay there: it's the only one selected")
	ann.grid.select([])
	_check(ann.grid.selection() == ["characters/borin"] and ann.grid.picked().is_empty(), "the active one counts as selected")
	var b_cell := ann.grid.token_cell("characters/borin")
	var dir := Vector2i(1, 0) if ann.grid.can_place("characters/borin", b_cell + Vector2i(1, 0)) else Vector2i(0, 1)
	ann.grid.step_selection(dir)
	await _until(func() -> bool: return ann.grid.token_cell("characters/borin") == b_cell + dir)
	_check(ann.grid.token_cell("characters/borin") == b_cell + dir, "WASD moves the active one without a selection")
	hud.cycle(1)
	_check(hud.active == "characters/aria", "nothing selected: all of them again")
	hud.cycle(1)  # back to Borin for the slots

	# spend a slot: an event, the HUD follows
	hud.use_slots(1, 2)
	await _until(func() -> bool: return int(ann.sheets.get("characters/borin", {}).get("spell_slots_used", {}).get("1", 0)) == 2)
	_check(int(ann.sheets["characters/borin"].spell_slots_used["1"]) == 2, "spent slots saved as an event")
	await process_frame
	var pip: Button = _slots(hud).get_child(0).get_node("Pip1")
	_check((pip.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == UISkin.TAN, "spent pips look empty")
	_check(not ann._ui.sheet.visible, "updates don't open the sheet panel either")
	dm.change_hp("characters/borin", -5)
	await _until(func() -> bool: return _hp(hud).begins_with("19"))
	_check(_hp(hud).begins_with("19 / 24"), "damage shows on the portrait (%s)" % _hp(hud))

	# F2: Ann puts Borin's HUD together; it is saved in the character, for every owner
	var f2 := InputEventKey.new()
	f2.pressed = true
	f2.physical_keycode = KEY_F2
	hud._input(f2)
	_check(hud.editor != null and not hud.visible, "F2 opens the HUD editor")
	var ed := hud.editor
	_check(ed.items().size() == 6, "it starts with the default HUD (portrait, health, slots, Compendium, Book, Leave)")
	_check(ed.find_child("Grid", false, false) != null, "with a grid to build on")
	ed.add("skills")
	ed.place(6, Rect2i(10, 18, 9, 9))
	ed.remove(2)  # no spell slots
	_check(ed.items().map(func(i: Dictionary) -> String: return i.w) == ["portrait", "hp", "compendium", "book", "leave", "skills"], "add, move, remove")
	hud._input(f2)
	_check(hud.editor == null and hud.visible, "F2 again saves and closes it")
	await _until(func() -> bool: return dm.timeline.entry("characters/borin").is_empty() == false and (Replay.entity_state(dm.timeline.entry("characters/borin"), dm.event_log.effective("characters/borin")).get("hud", []) as Array).size() == 6)
	var saved: Array = Replay.entity_state(dm.timeline.entry("characters/borin"), dm.event_log.effective("characters/borin")).get("hud", [])
	_check(saved.size() == 6 and saved[5].w == "skills" and saved[5].r == [10, 18, 9, 9], "saved in Borin as an event (%s)" % [saved])
	# a player gets Leave, not the DM's Compendium and Book
	hud.actions = {"leave": func() -> void: pass}
	hud.refresh()
	_check((hud.find_child("W_leave", true, false) as Control).visible and not (hud.find_child("W_book", true, false) as Control).visible, "app buttons only for who may use them")
	_check(hud.shows_app_buttons(), "the HUD shows the app's buttons itself")
	await process_frame
	_check(hud.find_child("W_skills", true, false) != null and hud.find_child("W_slots", true, false) == null, "the HUD shows the new layout")
	# F3: the sheet pages, like home screens
	var f3 := f2.duplicate() as InputEventKey
	f3.physical_keycode = KEY_F3
	hud._input(f3)
	_check(hud.editor != null and hud.editor.multi and hud.pages.visible, "F3 opens the page editor on the sheet")
	hud.editor.add_page()
	hud.editor.add("description")
	hud._input(f3)
	await _until(func() -> bool: return (ann.sheets.get("characters/borin", {}).get("_pages", []) as Array).size() == 3)
	_check(hud.page_list().size() == 3 and hud.page_list()[2].items[0].w == "description", "a third page with the description (%s)" % [hud.page_list().map(func(pg: Dictionary) -> String: return pg.name)])
	var three := one.duplicate() as InputEventKey
	three.physical_keycode = KEY_3
	hud.pages.close()
	hud._input(three)
	_check(hud.pages.visible and hud.pages.current == 2 and hud.pages.find_child("W_description", true, false) != null, "3 opens it")
	hud.pages.close()

	# a click on the empty map: nothing selected or active, the HUD goes away
	ann.grid.select(["characters/aria"])
	var empty := Vector2i(-1, -1)
	for y in ann.grid.grid_size.y:
		for x in ann.grid.grid_size.x:
			if empty.x < 0 and ann.grid.tokens.keys().all(func(id: String) -> bool: return ann.grid.token_cell(id).distance_to(Vector2i(x, y)) > 3):
				empty = Vector2i(x, y)
	var at := ann.grid.get_canvas_transform() * ann.grid.cell_center(empty, 1.0)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		ann.grid._unhandled_input(click)
	await process_frame
	_check(hud.active == "" and not hud.visible and ann.grid.selection().is_empty() and ann.grid.active == "", "a click into nothing deselects all and hides the HUD")
	ann.change_hp("characters/aria", -1)
	await _until(func() -> bool: return int(ann.sheets.get("characters/aria", {}).get("hp", 0)) == 26)
	await process_frame
	_check(not hud.visible, "and it stays hidden when the table changes")
	hud._input(e_key)
	_check(hud.active == "characters/aria" and hud.visible, "E brings it back (%s)" % hud.active)

	# the DM controls everything on the map
	var dm_hud: CharacterHud = dm._ui.hud
	var all := dm_hud.controlled()
	_check("characters/aria" in all and "characters/borin" in all and all.size() == dm.grid.tokens.size(), "the DM cycles through every token (%s)" % [all])
	_check(dm_hud.active != "" and dm_hud.visible, "the DM has an active one too")

	# creatures: one HUD from the template in the Book, for every copy (DM only)
	var world := EntryStore.open(ProjectSettings.globalize_path(DIR + "/worlds/westmarch"))
	world.save("creatures", {"id": "bandit", "name": "Bandit", "hp": 11, "ac": 12, "size": "Medium",
		"stats": {"str": 11, "dex": 12, "con": 12, "int": 10, "wis": 10, "cha": 10}})
	var bandit := world.find("creatures", "bandit").duplicate(true)
	bandit.merge({"_kind": "creatures", "_layer": "world", "_package": world.id, "_dir": world.folder}, true)
	dm.timeline.reload_world()
	var b1 := dm.drop_token(bandit, Vector2i(1, 1))
	var b2 := dm.drop_token(bandit, Vector2i(1, 3))
	_check(b1 != "" and b2 != "" and b1 != b2 and dm.layout_template(b1) == "creatures/bandit", "two bandit copies of one template (%s, %s)" % [b1, b2])
	dm_hud.set_active(b1)
	await _until(func() -> bool: return dm.sheets.has(b1))
	dm_hud.edit_hud()
	dm_hud.editor.add("abilities")
	dm_hud.editor.finish(true)
	_check(str(EntryStore.open(world.folder).find("creatures", "bandit").get("hud", [])).contains("abilities"), "saved in the template in the Book")
	dm_hud.set_active(b2)
	await _until(func() -> bool: return dm.sheets.has(b2))
	await process_frame
	_check(dm_hud.layout().any(func(i: Dictionary) -> bool: return i.w == "abilities") and dm_hud.find_child("W_abilities", true, false) != null, "the other bandit has it too")
	var before_hud: Variant = Replay.entity_state(dm.timeline.entry("characters/aria"), dm.event_log.effective("characters/aria")).get("hud")
	ann.save_layout(b1, "hud", [])
	await process_frame
	await process_frame
	_check(str(EntryStore.open(world.folder).find("creatures", "bandit").get("hud", [])).contains("abilities") and before_hud == null, "players can't change a creature's HUD")

	# the sheet panel still opens by hand
	ann.open_sheet("characters/aria")
	await _until(func() -> bool: return ann._ui.sheet.visible)
	_check(ann._ui.sheet.visible and ann._ui.sheet.ref == "characters/aria", "open_sheet still shows the panel")

	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("character hud: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _hp(hud: CharacterHud) -> String:
	var l := hud.find_child("HPText", true, false) as Label
	return l.text if l != null else ""


func _name(hud: CharacterHud) -> String:
	var l := hud.find_child("Name", true, false) as Label
	return l.text if l != null else ""


func _slots(hud: CharacterHud) -> Control:
	var c := hud.find_child("SpellSlots", true, false) as Control
	return c if c != null else Control.new()


func _table(branch: String, cache: String, ui := false) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = ui
	t.timeline_dir = TIMELINE
	t.cache_dir = DIR.path_join("cache_" + cache)
	holder.add_child(t)
	return t


func _until(done: Callable, frames := 400) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
