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

	# --- Builder 2 (TASK-48): variants, quick buttons, what a use posts --------------------------
	var cleaned := HudWidgets.clean([{"w": "portrait", "v": "picture", "r": [0, 0, 4, 5]}, {"w": "portrait", "v": "nope", "r": [0, 0, 4, 5]},
		{"w": "spell", "ref": "spells/fire-bolt", "v": "round", "r": [5, 5, 2, 2]}, {"w": "item", "r": [1, 1, 2, 2]}], HudWidgets.HUD_GRID)
	_check(cleaned.size() == 3 and cleaned[0].v == "picture" and not cleaned[1].has("v") and cleaned[2].ref == "spells/fire-bolt" and cleaned[2].v == "round",
		"layouts keep variants and refs, a quick button needs its ref (%s)" % [cleaned])
	_check(HudActions.first_dice("takes 1d4 + 1 force damage") == "1d4+1" and HudActions.first_dice("1d8 + your modifier") == "1d8"
		and HudActions.first_dice("no dice") == "", "dice found in a description")
	var wiz := {"name": "Wiz", "stats": {"int": 16}, "proficiency_bonus": 2, "classes": [{"class": "classes/wizard", "level": 1}]}
	var bolt := HudActions.spell(wiz, {"name": "Fire Bolt", "level": 0, "casting_time": "1 action", "range_m": 36,
		"description": "Make a ranged spell attack against the target. On a hit, the target takes 1d10 fire damage."}, "spells/fire-bolt")
	_check(bolt.text == "casts Fire Bolt (cantrip · 1 action · 36 m)" and bolt.asked.size() == 2 and bolt.asked[0].formula == "1d20+5"
		and bolt.asked[1].formula == "1d10" and bolt.asked[1].label == "Fire Bolt damage", "a spell attack and its damage (%s)" % [bolt])
	var sleep := HudActions.spell(wiz, {"name": "Burning Hands", "level": 1, "description": "Each creature must make a Dexterity saving throw. A creature takes 3d6 fire damage."}, "")
	_check(str(sleep.text).ends_with("DC 13 DEX save") and sleep.asked.size() == 1, "a save spell says its DC (%s)" % sleep.text)
	var cat := HudWidgets.catalog({"spells": ["spells/fire-bolt"], "inventory": [{"item": "items/torch", "qty": 3, "max": 10}],
		"_refs": {"spells/fire-bolt": {"name": "Fire Bolt", "level": 0}}}, "round")
	var portraits := cat.filter(func(c: Dictionary) -> bool: return c.w == "portrait")
	_check(portraits.size() == 3 and cat.any(func(c: Dictionary) -> bool: return c.tab == "Spells" and c.label == "Fire Bolt" and c.v == "round")
		and cat.any(func(c: Dictionary) -> bool: return c.tab == "Items" and c.ref == "items/torch")
		and cat.any(func(c: Dictionary) -> bool: return c.tab == "Checks" and c.ref == "dex save" and c.label == "DEX save"), "the catalog: variants side by side, a card per spell, item, check")
	_check(HudWidgets.quick_amount("item", "items/torch", {"inventory": [{"item": "items/torch", "qty": 3, "max": 10}]}) == "3/10"
		and HudWidgets.quick_amount("item", "items/rope", {"inventory": []}) == "0", "item amounts on the badge")

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
	# it docks like an IDE panel, floats on the grid, pops out; its place is the player's (TASK-50)
	await process_frame
	_check(chat.place.dock == "right" and chat.position.x > chat.area().x * 0.6, "docked right at first")
	chat.dock("left")
	_check(chat.position.x < 10 and chat.size.y > chat.area().y * 0.7, "docks left")
	chat.end_move(Vector2(chat.area().x - 3, 300))
	_check(chat.place.dock == "right", "let go on the right zone: docked right")
	chat.position = Vector2(chat.cell().x * 10.2, chat.cell().y * 5.1)
	chat.end_move(Vector2(chat.area().x * 0.4, chat.area().y * 0.4))
	_check(chat.place.dock == "float" and int(chat.place.r[0]) == 10 and int(chat.place.r[1]) == 5, "anywhere else it floats, snapped to cells (%s)" % [chat.place])
	chat._resize_to(Vector2(chat.cell().x * 24, chat.cell().y * 20))
	_check(int(chat.place.r[2]) == 14 and int(chat.place.r[3]) == 15, "its corner resizes it by cells (%s)" % [chat.place.r])
	chat.save_place()
	var again := ChatBox.new()
	again.place_file = chat.place_file
	again.load_place()
	_check(again.place.dock == "float" and again.place.r == chat.place.r, "its place is saved for the player")
	again.free()
	chat.pop_out()
	_check(chat.get_parent() is Window and chat.window != null and chat.window.visible, "pops out into its own window")
	chat.dock_back()
	_check(chat.get_parent() == ann._ui.hud.get_parent() and chat.window == null and int(chat.position.x) == int(chat.cell().x * 10) + 4, "and docks back where it was")
	chat.dock("right")
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
	_check(Array(hud.cycle_list()) == ["characters/aria", "characters/borin"], "just one selected: Q / E still go through all of them")
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
	await _until(func() -> bool: return Replay.slots_used(ann.sheets.get("characters/borin", {}), 1) == 2)
	_check(Replay.slots_used(ann.sheets["characters/borin"], 1) == 2, "spent slots saved as an event")
	var slot_events := dm.event_log.events.filter(func(ev: Dictionary) -> bool: return ev.entity == "characters/borin" and ev.type == "resource.used")
	_check(slot_events.size() == 1 and slot_events[0].data.resource == "spell_slots.1" and int(slot_events[0].data.amount) == 2, "as resource.used (TASK-51)")
	await _until(func() -> bool: return dm.rolls.any(func(r: Dictionary) -> bool: return r.get("action") == "log"))
	var logged := dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("action") == "log")
	_check(not logged.is_empty() and str(logged[-1].text) == "used 2 level 1 spell slot" and logged[-1].hidden, "a player's change shows as a log line for the DM (%s)" % [logged])
	_check(not ann.rolls.any(func(r: Dictionary) -> bool: return r.get("action") == "log"), "the players don't get it")
	hud.use_slots(1, 1)
	await _until(func() -> bool: return Replay.slots_used(ann.sheets.get("characters/borin", {}), 1) == 1)
	_check(Replay.slots_used(ann.sheets["characters/borin"], 1) == 1, "giving one back: resource.restored")
	hud.use_slots(1, 2)
	await _until(func() -> bool: return Replay.slots_used(ann.sheets.get("characters/borin", {}), 1) == 2)
	# items: item.gained / lost (TASK-51)
	ann.change_item("characters/borin", "items/torch", 3)
	await _until(func() -> bool: return str(ann.sheets.get("characters/borin", {}).get("inventory", [])).contains("items/torch"))
	ann.change_item("characters/borin", "items/torch", -1)
	await _until(func() -> bool: return dm.event_log.events.any(func(ev: Dictionary) -> bool: return ev.type == "item.lost"))
	await _until(func() -> bool: return HudWidgets.quick_amount("item", "items/torch", ann.sheets.get("characters/borin", {})) == "2")  # Ann's copy follows
	var inv: Variant = ann.sheets["characters/borin"].get("inventory")
	_check(str(inv).contains("items/torch") and HudWidgets.quick_amount("item", "items/torch", ann.sheets["characters/borin"]) == "2", "items gained and lost as events (%s)" % [inv])
	ann.change_item("characters/borin", "items/torch", -2)
	await _until(func() -> bool: return not str(ann.sheets.get("characters/borin", {}).get("inventory", [])).contains("items/torch"))
	_check(not str(ann.sheets["characters/borin"].get("inventory", [])).contains("items/torch"), "all gone again")
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
	_check(ed.items().size() == 8, "it starts with the default HUD (portrait, health, slots, Combat, Rules, Compendium, Book, Leave)")
	_check(ed.find_child("Grid", true, false) != null, "with a grid to build on")
	ed.canvas = Vector2(1600, 950)  # headless: the HUD has no real screen size
	ed.size = Vector2(1600, 950)
	_check(ed.view_scale() < 0.9 and ed.preview_rect().end.y < ed.find_child("Tray", false, false).position.y, "the screen is shown smaller, the catalog below it (%s %s %s %s)" % [ed.view_scale(), ed.preview_rect(), ed.find_child("Tray", false, false).position, ed.canvas])
	_check(ed.find_child("Card_portrait_picture_", true, false) != null, "the catalog shows the portrait variants (Character tab)")
	ed.show_tab("Spells")
	_check(ed.find_child("Card_spell_square_spells/cure-wounds".validate_node_name(), true, false) != null, "a card per spell (Spells tab)")
	ed.show_tab("Items")
	_check((ed.find_child("Cards", true, false).get_child(0) is Label), "Borin carries nothing: the Items tab says so")
	# TASK-78: one editor for the HUD and the pages; 1-9 switch to a page, the same key back
	var key2 := f2.duplicate() as InputEventKey
	key2.physical_keycode = KEY_2
	_check(ed.current == 0 and ed.is_home(0) and ed.pages().size() == hud.page_list().size(), "the HUD first, then the pages, in one editor")
	hud._input(key2)
	_check(ed.current == 2 and ed.grid == HudWidgets.PAGE_GRID and hud.pages.visible and hud.pages.current == 1 and (ed.find_child("Paper", true, false) as Control).visible, "2 in edit mode: editing page 2 on paper (%d)" % ed.current)
	hud._input(key2)
	_check(ed.current == 0 and ed.grid == HudWidgets.HUD_GRID and not hud.pages.visible and not (ed.find_child("Paper", true, false) as Control).visible, "2 again: back to the HUD")
	ed.canvas = Vector2(1600, 950)
	ed.size = Vector2(1600, 950)
	ed.add("skills")
	ed.place(8, Rect2i(10, 18, 9, 9))
	ed.remove(2)  # no spell slots
	_check(ed.items().map(func(i: Dictionary) -> String: return i.w) == ["portrait", "hp", "combat", "rules", "compendium", "book", "leave", "skills"], "add, move, remove")
	ed.add_item("portrait", "small")
	ed.cycle_variant(8)
	_check(ed.items()[8].v == "token", "double-click: the next variant")
	ed.remove(8)
	hud._input(f2)
	_check(hud.editor == null and hud.visible, "F2 again saves and closes it")
	await _until(func() -> bool: return dm.timeline.entry("characters/borin").is_empty() == false and (Replay.entity_state(dm.timeline.entry("characters/borin"), dm.event_log.effective("characters/borin")).get("hud", []) as Array).size() == 8)
	var saved: Array = Replay.entity_state(dm.timeline.entry("characters/borin"), dm.event_log.effective("characters/borin")).get("hud", [])
	_check(saved.size() == 8 and saved[7].w == "skills" and saved[7].r == [10, 18, 9, 9], "saved in Borin as an event (%s)" % [saved])
	# a player gets Leave, not the DM's Compendium and Book
	hud.actions = {"leave": func() -> void: pass}
	hud.refresh()
	_check((hud.find_child("W_leave", true, false) as Control).visible and not (hud.find_child("W_book", true, false) as Control).visible, "app buttons only for who may use them")
	_check(hud.shows_app_buttons(), "the HUD shows the app's buttons itself")
	await process_frame
	_check(hud.find_child("W_skills", true, false) != null and hud.find_child("W_slots", true, false) == null, "the HUD shows the new layout")
	# F2 with a sheet page open: the page editor (one key for both)
	var f3 := f2.duplicate() as InputEventKey
	f3.physical_keycode = KEY_F3
	hud._input(f3)
	_check(hud.editor == null, "F3 is no editor key any more")
	hud._input(one)
	hud._input(f2)
	_check(hud.editor != null and hud.editor.multi and hud.pages.visible, "F2 on an open sheet page edits the pages")
	hud.editor.add_page()
	hud.editor.add("description")
	hud._input(f2)
	await _until(func() -> bool: return (ann.sheets.get("characters/borin", {}).get("_pages", []) as Array).size() == 3)
	_check(hud.page_list().size() == 3 and hud.page_list()[2].items[0].w == "description", "a third page with the description (%s)" % [hud.page_list().map(func(pg: Dictionary) -> String: return pg.name)])
	var three := one.duplicate() as InputEventKey
	three.physical_keycode = KEY_3
	hud.pages.close()
	hud._input(three)
	_check(hud.pages.visible and hud.pages.current == 2 and hud.pages.find_child("W_description", true, false) != null, "3 opens it")
	hud.pages.close()

	# quick buttons (TASK-48): Borin (cleric 3) casts, uses, rolls; it is posted in the chat
	var borin_sheet: Dictionary = ann.sheets["characters/borin"]
	var spell_ref := str((borin_sheet.get("spells", []) as Array)[0]) if not (borin_sheet.get("spells", []) as Array).is_empty() else "spells/cure-wounds"
	hud.edit_hud()
	hud.editor.add_item("spell", "round", spell_ref)
	hud.editor.add_item("check", "square", "wis save")
	hud.editor.add_item("item", "square", "items/torch")
	# select, Shift + click more, the inspector changes what they share (TASK-50)
	var ed2 := hud.editor
	var n := ed2.items().size()
	_check(ed2.selected == [n - 1], "a new piece is selected")
	ed2.select([n - 3])
	ed2.select([n - 2], true)
	var round_tick := ed2.find_child("Inspector", true, false).find_child("Round", true, false) as CheckBox
	_check(ed2.selected.size() == 2 and round_tick != null and not round_tick.button_pressed and round_tick.text.contains("mixed"), "Shift: two selected; the inspector shows Round as mixed")
	round_tick.button_pressed = true
	_check(ed2.items()[n - 3].v == "round" and ed2.items()[n - 2].v == "round", "ticking Round makes both round")
	(ed2.find_child("Inspector", true, false).find_child("W", true, false) as SpinBox).value = 3
	_check(int(ed2.items()[n - 3].r[2]) == 3 and int(ed2.items()[n - 2].r[2]) == 3, "the width goes to both")
	(ed2.find_child("Inspector", true, false).find_child("Badge", true, false) as CheckBox).button_pressed = false
	_check(ed2.items()[n - 2].get("badge", true) == false, "the badge can be switched off")
	var to_screen := func(cell: Vector2) -> Vector2: return ed2.preview_rect().position + cell * ed2.cell_size() * ed2.view_scale()
	var item_r: Array = ed2.items()[n - 1].r
	var shift_click := InputEventMouseButton.new()
	shift_click.button_index = MOUSE_BUTTON_LEFT
	shift_click.pressed = true
	shift_click.shift_pressed = true
	shift_click.position = to_screen.call(Vector2(float(item_r[0]) + 0.5, float(item_r[1]) + 0.5))
	ed2._gui_input(shift_click)
	var up := shift_click.duplicate() as InputEventMouseButton
	up.pressed = false
	ed2._gui_input(up)
	_check(ed2.selected.size() == 3, "Shift + click on the screen adds one (%s)" % [ed2.selected])
	var starts := ed2.items().slice(n - 3).map(func(it: Dictionary) -> Array: return (it.r as Array).duplicate())
	var grab := InputEventMouseButton.new()
	grab.button_index = MOUSE_BUTTON_LEFT
	grab.pressed = true
	var spell_r: Array = ed2.items()[n - 3].r
	grab.position = to_screen.call(Vector2(float(spell_r[0]) + 0.5, float(spell_r[1]) + 0.5))
	ed2._gui_input(grab)
	var move := InputEventMouseMotion.new()
	move.position = grab.position + Vector2(0, 2) * ed2.cell_size() * ed2.view_scale()
	ed2._gui_input(move)
	var let_go := grab.duplicate() as InputEventMouseButton
	let_go.pressed = false
	ed2._gui_input(let_go)
	var moved := true
	for k in 3:
		moved = moved and int(ed2.items()[n - 3 + k].r[1]) == int(starts[k][1]) + 2 and int(ed2.items()[n - 3 + k].r[0]) == int(starts[k][0])
	_check(moved and ed2.selected.size() == 3, "dragging one moves the whole selection (%s -> %s, %s)" % [starts, ed2.items().slice(n - 3).map(func(it: Dictionary) -> Array: return it.r), ed2.selected])
	hud.editor.finish(true)
	await _until(func() -> bool: return hud.find_child("W_check", true, false) != null)
	await process_frame
	_check((borin_sheet.get("_refs", {}) as Dictionary).has(spell_ref), "the sheet knows its spells' names (%s)" % [borin_sheet.get("_refs")])
	var spell_button: Control = hud.find_child("W_spell", true, false)
	_check(spell_button != null and spell_button.get_node("Button/Glyph") != null, "a spell button on the HUD")
	var torch: Control = hud.find_child("W_item", true, false)
	_check(torch != null and (torch.get_node("Button/Badge") as Label).text == "0", "an item not held shows 0")
	var rolls_before := ann.rolls.size()
	(spell_button.get_node("Button") as Button).pressed.emit()
	if hud.cast_popup != null and is_instance_valid(hud.cast_popup):  # TASK-49: a levelled spell asks for its slot level
		hud.cast_popup.id_pressed.emit(0)
	await _until(func() -> bool: return ann.rolls.size() > rolls_before)
	var cast: Dictionary = ann.rolls[ann.rolls.size() - 1] if ann.rolls.size() > rolls_before else {}
	_check(str(cast.get("action", "")) == spell_ref and str(cast.get("text", "")).begins_with("casts ") and str(cast.get("who", "")) == "Borin Stoneshield",
		"a click casts the spell: posted in the chat (%s)" % [cast])
	_check(NetTable.roll_bbcode(cast).contains("casts "), "the chat shows it")
	await _until(func() -> bool: return Replay.slots_used(ann.sheets["characters/borin"], 1) == 3)
	_check(Replay.slots_used(ann.sheets["characters/borin"], 1) == 3, "the slot is spent (TASK-49)")
	rolls_before = ann.rolls.size()
	(hud.find_child("W_check", true, false).get_node("Button") as Button).pressed.emit()
	await _until(func() -> bool: return ann.rolls.size() > rolls_before)
	_check(ann.rolls.size() > rolls_before and str(ann.rolls[ann.rolls.size() - 1].results[0].label) == "WIS save", "a check button rolls it")

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
