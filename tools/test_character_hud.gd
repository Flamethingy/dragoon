extends SceneTree
## Headless check of the active character HUD (TASK-44): portrait with HP and spell slots in
## the lower left, 10 empty hotbar slots, Q / E round robin through the tokens one controls,
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
	_check(hud._hp_text.text.begins_with("27 / 27"), "HP on the portrait (%s)" % hud._hp_text.text)
	_check(hud._name.text == "Aria Windrunner", "name under the portrait")
	_check(hud._hotbar.get_child_count() == 10 and hud.find_child("Slot10", true, false) != null, "10 hotbar slots")
	_check(hud._slots_row.get_child_count() == 1 and hud._slots_row.get_child(0).get_child_count() == 3, "ranger 3: two level 1 slots")
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
	_check(hud._name.text == "Borin Stoneshield" and hud._hp_text.text.begins_with("24 / 24"), "Borin's portrait (%s)" % hud._hp_text.text)
	_check(hud._slots_row.get_child_count() == 2, "cleric 3: level 1 and 2 slots")
	hud.cycle(1)
	_check(hud.active == "characters/aria", "round robin back to Aria")
	var q_key := e_key.duplicate() as InputEventKey
	q_key.physical_keycode = KEY_Q
	hud._input(q_key)
	_check(hud.active == "characters/borin", "Q: the other way")

	# a click selects but keeps the active one
	ann.grid.select(["characters/aria"])
	await process_frame
	_check(hud.active == "characters/borin", "selecting a token does not change the active one")

	# spend a slot: an event, the HUD follows
	hud.use_slots(1, 2)
	await _until(func() -> bool: return int(ann.sheets.get("characters/borin", {}).get("spell_slots_used", {}).get("1", 0)) == 2)
	_check(int(ann.sheets["characters/borin"].spell_slots_used["1"]) == 2, "spent slots saved as an event")
	await process_frame
	var pip: Button = hud._slots_row.get_child(0).get_node("Pip1")
	_check((pip.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == UISkin.TAN, "spent pips look empty")
	_check(not ann._ui.sheet.visible, "updates don't open the sheet panel either")
	dm.change_hp("characters/borin", -5)
	await _until(func() -> bool: return hud._hp_text.text.begins_with("19"))
	_check(hud._hp_text.text.begins_with("19 / 24"), "damage shows on the portrait (%s)" % hud._hp_text.text)

	# the DM controls everything on the map
	var dm_hud: CharacterHud = dm._ui.hud
	var all := dm_hud.controlled()
	_check("characters/aria" in all and "characters/borin" in all and all.size() == dm.grid.tokens.size(), "the DM cycles through every token (%s)" % [all])
	_check(dm_hud.active != "" and dm_hud.visible, "the DM has an active one too")

	# the sheet panel still opens by hand
	ann.open_sheet("characters/aria")
	await _until(func() -> bool: return ann._ui.sheet.visible)
	_check(ann._ui.sheet.visible and ann._ui.sheet.ref == "characters/aria", "open_sheet still shows the panel")

	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("character hud: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


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
