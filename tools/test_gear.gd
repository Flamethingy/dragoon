extends SceneTree
## Headless check of weapons and AC from the inventory (TASK-70): what an item is (core table,
## "+1" names, "functions as", attunement), equipped weapons as attacks (STR / DEX / finesse,
## proficiency, magic, versatile, ranges), AC from armor, shield, magic and Unarmored Defense,
## item.flagged events (equip, attune; a 4th attunement warned), the attack bar using a weapon
## and ammunition counted when the DM turns it on.
## godot --headless --path . -s tools/test_gear.gd

const PORT := 47815
const DIR := "user://test_gear"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	# what items are
	var ls := Rules.item_info("items/longsword", {})
	_check(str(ls.weapon.get("name", "")) == "Longsword" and int(ls.bonus) == 0 and not bool(ls.attunement), "a longsword from the core table")
	var plus := Rules.item_info("items/flame-blade", {"name": "+1 Longsword", "description": "You have a +1 bonus to attack and damage rolls made with this magic weapon."})
	_check(str(plus.weapon.get("name", "")) == "Longsword" and int(plus.bonus) == 1, "+1 Longsword (%s)" % [plus])
	var ball := Rules.item_info("items/steel-ball", {"name": "Steel Ball of Hope", "type": "['Weapon', 'Light Armor']", "description": "*Requires Attunement by a Fighter*\n\nIt functions as a light hammer with the finesse property."})
	_check(str(ball.weapon.get("name", "")) == "Light Hammer" and bool(ball.attunement), "functions as a light hammer, needs attunement (%s)" % [ball.weapon])
	var ring := Rules.item_info("items/ring-of-protection", {"name": "Ring of Protection", "description": "You gain a +1 bonus to AC and saving throws while wearing this ring. Requires attunement."})
	_check(int(ring.ac_bonus) == 1 and bool(ring.attunement), "Ring of Protection: +1 AC")
	_check(bool(Rules.item_info("items/arrows", {"name": "Arrows"}).ammunition), "arrows are ammunition")
	_check(str(Rules.item_info("items/x", {"name": "Fancy", "type": "['Weapon', 'GreatAxe']"}).weapon.get("name", "")) == "Greataxe", "type Weapon, GreatAxe")

	# attacks and AC
	var s := {"stats": {"str": 16, "dex": 14, "con": 14, "wis": 12}, "classes": [{"class": "classes/fighter", "level": 1}],
		"inventory": [{"item": "items/longsword", "qty": 1, "equipped": true}, {"item": "items/dagger", "qty": 2, "equipped": true},
			{"item": "items/longbow", "qty": 1, "equipped": true}, {"item": "items/chain-mail", "qty": 1, "equipped": true}]}
	var atk := {}
	for a: Dictionary in Rules.weapon_attacks(s):
		atk[str(a.name)] = a.attack
	_check(int(atk["Longsword"].to_hit) == 5 and atk["Longsword"].damage[0].dice == "1d8+3" and atk["Longsword"].damage[0].type == "slashing", "longsword: STR +3, prof +2 (%s)" % [atk.get("Longsword")])
	_check(atk.has("Longsword (two-handed)") and atk["Longsword (two-handed)"].damage[0].dice == "1d10+3", "versatile: two-handed without a shield")
	_check(int(atk["Dagger"].to_hit) == 5 and atk["Dagger"].damage[0].dice == "1d4+3", "dagger: finesse, STR is better here")
	_check(int(atk["Longbow"].to_hit) == 4 and atk["Longbow"].damage[0].dice == "1d8+2" and bool(atk["Longbow"].ammunition) and Rules.range_of(atk["Longbow"].range).long > 40.0, "longbow: DEX, ammunition, long range (%s)" % [atk.get("Longbow")])
	_check(Rules.ac(s) == 16, "chain mail: 16, no DEX (%d)" % Rules.ac(s))
	s.inventory.append({"item": "items/shield", "qty": 1, "equipped": true})
	_check(Rules.ac(s) == 18 and not Rules.weapon_attacks(s).any(func(a: Dictionary) -> bool: return str(a.name).ends_with("(two-handed)")), "+ shield: 18, no two-handed")
	s["proficiencies"] = ["Simple Weapons"]
	_check(int(Rules.weapon_attacks(s).filter(func(a: Dictionary) -> bool: return a.name == "Longsword")[0].attack.to_hit) == 3, "not proficient with martial weapons: no +2")
	var barb := {"stats": {"dex": 14, "con": 16}, "classes": [{"class": "classes/barbarian", "level": 1}], "inventory": []}
	_check(Rules.ac(barb) == 15, "Unarmored Defense: 10 + DEX 2 + CON 3 (%d)" % Rules.ac(barb))
	var magic := {"stats": {"dex": 10}, "_gear": [{"item": "items/r", "equipped": true, "attunement": true, "attuned": false, "ac_bonus": 1, "armor": {}, "weapon": {}}]}
	_check(Rules.ac(magic) == 10, "a ring that needs attunement: nothing until attuned")
	magic._gear[0].attuned = true
	_check(Rules.ac(magic) == 11 and int(Rules.attunement(magic).count) == 1, "attuned: +1")
	var st := Replay.entity_state({"inventory": {"items/dagger": 1}}, [{"type": "item.flagged", "data": {"item": "items/dagger", "flag": "equipped", "on": true}}])
	_check(bool(Rules.gear(st)[0].equipped), "item.flagged equips it (Replay)")

	# at the table
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	for i in 4:
		tl.edit_entry("items", {"id": "charm-%d" % i, "name": "Charm %d" % i, "description": "Requires attunement. A charm."})
	tl.edit_entry("items", {"id": "arrows", "name": "Arrows", "type": "Ammunition"})
	var borin := tl.entry(BORIN).duplicate(true)
	borin.erase("ac")
	borin["inventory"] = [{"item": "items/longbow", "qty": 1}, {"item": "items/arrows", "qty": 3}, {"item": "items/chain-mail", "qty": 1},
		{"item": "items/charm-0", "qty": 1}, {"item": "items/charm-1", "qty": 1}, {"item": "items/charm-2", "qty": 1}, {"item": "items/charm-3", "qty": 1}]
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))
	var before := Rules.ac(dm.sheet_for(Reveal.DM, BORIN))
	dm.flag_item(BORIN, "items/chain-mail", "equipped")
	dm.flag_item(BORIN, "items/longbow", "equipped")
	var sheet := dm.sheet_for(Reveal.DM, BORIN)
	_check(Rules.ac(sheet) == 16 and before != 16, "equipped chain mail: AC 16 (was %d, now %d, %s, %s)" % [before, Rules.ac(sheet), sheet.get("ac"), Rules.equipped_gear(sheet)])
	_check("Longbow" in (sheet._attacks as Array), "the longbow is an attack on the sheet (%s)" % [sheet._attacks])
	_check(SheetPanel._gear(sheet).contains("gear:equipped:off:items/longbow") and SheetPanel._gear(sheet).contains("gear:attuned:on:items/charm-0"), "the inventory has equip and attune links")
	for i in 4:
		dm.flag_item(BORIN, "items/charm-%d" % i, "attuned")
	sheet = dm.sheet_for(Reveal.DM, BORIN)
	_check(int(sheet._attunement.count) == 4 and SheetPanel._gear(sheet).contains("too many"), "a 4th attunement: allowed, but flagged")
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("attuned to 4 items")), "the DM is told")

	# shooting: ammunition off (default), then auto
	dm.begin_attack(BORIN, "Longbow")
	dm._ui._toggle_target(CHIEF)
	dm._ui.roll_attack()
	var shots: Array = dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("attack") is Dictionary and str(r.attack.get("name", "")) == "Longbow")
	_check(shots.size() == 1, "the longbow through the attack bar")
	_check(_arrows(dm) == 3, "ammunition off: no arrows counted")
	var rs := dm.rules_settings().duplicate(true)
	rs["automation"] = {"ammunition": "auto"}
	dm.set_rules_settings(rs)
	dm.begin_attack(BORIN, "Longbow")
	dm._ui._toggle_target(CHIEF)
	dm._ui.roll_attack()
	_check(_arrows(dm) == 2, "auto: one arrow used (%d left)" % _arrows(dm))
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("gear: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _arrows(dm: NetTable) -> int:
	for g: Dictionary in dm.sheet_for(Reveal.DM, BORIN)._gear:
		if g.item == "items/arrows":
			return int(g.qty)
	return 0


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
