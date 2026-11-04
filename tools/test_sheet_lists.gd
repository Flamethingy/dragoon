extends SceneTree
## Headless check of the Inventory / Spells / Features pieces (TASK-107): what a row shows
## (icon, name, detail, marks, amount), the list and the card view, the toggle kept per kind,
## a click uses an item / casts a spell.
## godot --headless --path . -s tools/test_sheet_lists.gd

var _failed := 0


class FakeHud extends CharacterHud:
	var used := []
	var opened := []
	func use_quick(kind: String, ref: String) -> void:
		used.append([kind, ref])
	func show_entry(ref: String) -> void:
		opened.append(ref)


static func click(c: Control, double := false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = double
	c.gui_input.emit(ev)


func _init() -> void:
	SheetLists.settings_file = "user://test_sheet_views.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SheetLists.settings_file))
	var s := {
		"inventory": [{"item": "items/longsword", "qty": 1, "equipped": true}, {"item": "items/torch", "qty": 3, "max": 10},
			{"item": "items/potion-of-healing", "qty": 2}, {"item": "items/wand-of-magic-missiles", "qty": 1}],
		"_gear": [{"item": "items/longsword", "qty": 1, "equipped": true, "weapon": {"damage": "1d8", "type": "slashing"}, "bonus": 1},
			{"item": "items/torch", "qty": 3}, {"item": "items/potion-of-healing", "qty": 2},
			{"item": "items/wand-of-magic-missiles", "qty": 1, "attuned": true}],
		"spells": ["spells/shield", "spells/fire-bolt", "spells/web"],
		"features": ["classes/wizard/arcane-recovery"], "actions": ["actions/second-wind"],
		"spell_slots": [2, 1], "spell_slots_used": [1, 0],
		"classes": [{"class": "classes/wizard", "level": 3}],
		"_resources": [{"id": "charges.items/wand-of-magic-missiles", "name": "Wand", "max": 7, "used": 2},
			{"id": "feature.actions/second-wind", "name": "Second Wind", "max": 1, "used": 1}],
		"_refs": {"items/longsword": {"name": "Longsword", "type": "Weapon"}, "items/torch": {"name": "Torch", "type": "Adventuring Gear"},
			"items/potion-of-healing": {"name": "Potion of Healing", "type": "Potion", "rarity": "Common"},
			"items/wand-of-magic-missiles": {"name": "Wand of Magic Missiles", "type": "Wand", "rarity": "Uncommon"},
			"spells/shield": {"name": "Shield", "level": 1, "school": "abjuration", "casting_time": "1 reaction"},
			"spells/fire-bolt": {"name": "Fire Bolt", "level": 0, "school": "evocation"},
			"spells/web": {"name": "Web", "level": 2, "school": "conjuration", "concentration": true},
			"actions/second-wind": {"name": "Second Wind"}}}
	# --- Rows ------------------------------------------------------------------------------------
	var items := SheetLists.rows("inventory", s)
	_check(items.size() == 4, "a row per item (%d)" % items.size())
	var sword: Dictionary = items[0]
	_check(sword.name == "Longsword" and str(sword.detail).begins_with("1d8 +1 slashing") and sword.icon.sprite == "icon_sword"
		and sword.marks.size() == 1 and sword.marks[0][0] == "E", "a weapon: damage, bonus, equipped, sword icon (%s)" % [sword])
	_check(items[1].amount == "3/10" and items[2].amount == "×2" and items[2].icon.sprite == "icon_potion" and not str(items[2].detail).contains("Common"),
		"amounts: 3/10, ×2; potions get the potion icon; common isn't shown")
	_check(str(items[3].detail).contains("5/7 charges") and str(items[3].detail).contains("Uncommon") and items[3].marks[0][0] == "A", "charges, rarity, attuned (%s)" % items[3].detail)
	var spells := SheetLists.rows("spells", s)
	_check(spells.map(func(r: Dictionary) -> String: return r.name) == ["Fire Bolt", "Shield", "Web"], "spells sorted by level")
	_check(spells[0].icon.letter == "C" and spells[0].group == "Cantrips" and spells[1].detail == "Level 1 · Abjuration · 1 reaction"
		and spells[2].marks[0][0] == "C", "cantrip plate, detail line, concentration mark (%s)" % spells[1].detail)
	_check(spells[1].amount == HudWidgets.quick_amount("spell", "spells/shield", s), "spell amount = free slots (%s)" % spells[1].amount)
	var feats := SheetLists.rows("features", s)
	_check(feats.size() == 2 and feats[1].name == "Second Wind" and feats[1].amount == "0/1" and feats[1].spent and feats[1].group == "Actions"
		and feats[0].use == "", "features: grouped, uses left, spent, not clickable (%s)" % [feats])
	_check(SheetLists.item_sprite("Torch", "Adventuring Gear") == "icon_chest" and SheetLists.item_sprite("Shield", "Armor") == "icon_shield" and SheetLists.item_sprite("Ring of Protection", "Ring") == "ring"
		and SheetLists.item_sprite("Rope", "") == "icon_chest", "item sprites by type")

	# --- Views -----------------------------------------------------------------------------------
	var hud := FakeHud.new()
	root.add_child(hud)
	_check(SheetLists.view_of("inventory", "") == "list" and SheetLists.view_of("inventory", "cards") == "cards", "the layout's variant is the default")
	var piece := HudWidgets.build("inventory", s, hud, Vector2(360, 300), {"w": "inventory"})
	root.add_child(piece)
	_check(piece.find_child("List", true, false) != null and piece.find_child("Cards", true, false) == null, "list view by default")
	var row := piece.find_child("Row_items_torch", true, false) as Button
	_check(row != null and (row.find_child("Amount", true, false) as Label).text == "3/10" and row.find_child("Icon", true, false) is CardArt, "a row: icon and amount")
	row.pressed.emit()
	click(row)
	_check(hud.used.is_empty(), "a click on the text does nothing (TASK-109)")
	click(row.find_child("Icon", true, false) as Control)
	_check(hud.used == [["item", "items/torch"]], "a click on the picture uses the item (%s)" % [hud.used])
	click(row, true)
	_check(hud.opened == ["items/torch"], "a double-click opens its view (%s)" % [hud.opened])
	(piece.find_child("View_cards", true, false) as Button).pressed.emit()
	_check(piece.find_child("Cards", true, false) != null and SheetLists.view_of("inventory", "list") == "cards", "the toggle shows cards and is kept")
	var card := piece.find_child("Card_items_wand-of-magic-missiles", true, false)
	_check(card != null and card.find_child("Badge", true, false) == null and (piece.find_child("Card_items_torch", true, false).find_child("Badge", true, false) as Label).text == "3/10", "cards: amount badge")
	var again := HudWidgets.build("spells", s, hud, Vector2(360, 300), {"w": "spells", "v": "cards"})
	root.add_child(again)
	var web := again.find_child("Card_spells_web", true, false) as Button
	click(web.find_child("Icon", true, false) as Control)
	_check(hud.used[-1] == ["spell", "spells/web"], "a spell card's picture casts")
	click(web, true)
	_check(hud.opened[-1] == "spells/web", "a double-click on a card opens it")
	var feat := HudWidgets.build("features", s, hud, Vector2(360, 300), {"w": "features"})
	root.add_child(feat)
	_check(feat.find_child("List", true, false).get_children().any(func(c: Node) -> bool: return c is Label and c.text == "Actions"), "feature groups have headings")
	_check(HudWidgets.clean([{"w": "spells", "v": "cards", "r": [0, 0, 8, 8]}], HudWidgets.PAGE_GRID)[0].v == "cards", "layouts keep the view")
	_check(HudWidgets.catalog(s).filter(func(c: Dictionary) -> bool: return c.w == "inventory").size() == 2, "the builder offers both")
	var second := feat.find_child("Row_actions_second-wind", true, false) as Control
	click(second, true)
	_check(hud.opened[-1] == "actions/second-wind" and (second.find_child("Icon", true, false) as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "features open on a double-click, their picture isn't a use button")
	var w := EntryWindow.show_for(root, "items/potion", {"_kind": "items", "name": "Potion of Healing", "effects": [{"heal": "2d4+2"}]})
	_check(w.title == "Potion of Healing" and w.find_child("OnUse", true, false) != null and not w.view.edit_button.visible, "the entry window: the view with On Use, no book buttons")
	_check(EntryWindow.show_for(root, "items/potion", {"_kind": "items", "name": "Potion of Healing"}) == w, "opened again: the same window")
	var empty := HudWidgets.build("inventory", {}, hud, Vector2(200, 120), {"w": "inventory"})
	root.add_child(empty)
	_check(empty.find_child("Lists", true, false) != null, "an empty inventory builds")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SheetLists.settings_file))
	print("SHEET LISTS: %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: " + what)
