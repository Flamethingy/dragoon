extends SceneTree
## Headless check of casting and using (TASK-49): a spell's slot spent (upcast from the HUD's
## menu, none left = cast anyway with a DM line, cantrips and rituals free), a spell attack and
## a save spell through the attack bar, a concentration spell handing over to TASK-59, an
## item's charge and a potion drunk (one less, it heals).
## godot --headless --path . -s tools/test_casting.gd

const PORT := 47809
const DIR := "user://test_casting"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	_check(Rules.spell_kind({"description": "Make a ranged spell attack. On a hit it takes 3d6 fire damage."}) == "attack"
		and Rules.spell_kind({"description": "It must make a Dexterity saving throw, taking 2d6 thunder damage."}) == "save"
		and Rules.spell_kind({"description": "It sheds light."}) == "other", "how a spell is cast")
	_check(Rules.casting_kind({"casting_time": "1 bonus action"}) == "bonus" and Rules.casting_kind({"casting_time": "1 reaction, which you take when"}) == "reaction"
		and Rules.casting_kind({"casting_time": "1 action"}) == "action", "casting times")
	var ray := Rules.spell_attack_of({"name": "Ray", "description": "Make a ranged spell attack against the target. On a hit, the target takes 3d6 fire damage."}, {"stats": {"wis": 16}, "classes": [{"class": "classes/cleric", "level": 3}]})
	_check(ray.damage == [{"dice": "3d6", "type": "fire"}] and ray.ranged and int(ray.to_hit) == 5, "a spell attack: +5 (WIS 16, prof 2), 3d6 fire (%s)" % [ray])

	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("spells", {"id": "test-ray", "name": "Test Ray", "level": 1, "casting_time": "1 action", "description": "Make a ranged spell attack against the target. On a hit, the target takes 3d6 fire damage."})
	tl.edit_entry("spells", {"id": "test-burst", "name": "Test Burst", "level": 1, "casting_time": "1 action", "description": "Each creature must make a Dexterity saving throw, taking 2d6 thunder damage on a failed save, or half as much damage on a successful one."})
	tl.edit_entry("spells", {"id": "test-hold", "name": "Test Hold", "level": 2, "concentration": true, "casting_time": "1 action", "description": "The target must succeed on a Wisdom saving throw or be paralyzed for 1 minute."})
	tl.edit_entry("spells", {"id": "test-light", "name": "Test Light", "level": 0, "casting_time": "1 action", "description": "The object sheds bright light."})
	tl.edit_entry("spells", {"id": "test-alarm", "name": "Test Alarm", "level": 1, "ritual": true, "casting_time": "1 minute", "description": "You set an alarm."})
	tl.edit_entry("items", {"id": "wand-test", "name": "Wand of Testing", "description": "This wand has 3 charges. It regains 1d3 expended charges daily at dawn."})
	tl.edit_entry("items", {"id": "potion-test", "name": "Potion of Testing", "type": "Potion", "description": "You regain 2d4 + 2 hit points when you drink this potion."})
	var borin := tl.entry(BORIN).duplicate(true)
	borin["spells"] = ["spells/test-ray", "spells/test-burst", "spells/test-hold", "spells/test-light", "spells/test-alarm"]
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))
	dm.open_sheet(BORIN, false)
	var refs: Dictionary = dm.sheets[BORIN]._refs
	_check(refs["spells/test-ray"].cast == "attack" and refs["spells/test-burst"].cast == "save" and refs["spells/test-light"].cast == "other" and refs["spells/test-alarm"].ritual, "the sheet knows how each is cast")
	_check(Rules.slots(dm.sheets[BORIN]) == [4, 2], "a 3rd level cleric: 4 + 2 slots")

	# the HUD's cast menu: levels with slots (upcast), a ritual
	var hud := CharacterHud.new()
	hud.table = dm
	root.add_child(hud)
	hud.active = BORIN
	var menu := hud.cast_menu("spells/test-burst")
	_check(menu != null and menu.item_count == 2 and menu.get_item_text(1).contains("Level 2 (upcast)"), "Test Burst: level 1 or upcast at 2")
	menu = hud.cast_menu("spells/test-alarm")
	_check(menu.item_count == 3 and menu.get_item_text(2).begins_with("As a ritual"), "Test Alarm: level 1, 2 or as a ritual")
	_check(hud.cast_menu("spells/test-light") == null and _last(dm).contains("casts Test Light") and _used(dm, 1) == 0, "a cantrip is cast at once, free")

	# a spell attack through the attack bar
	dm.cast(BORIN, "spells/test-ray")
	_check(dm._ui.attack.get("kind") == "attack" and dm._ui.attack.opts.level == 1, "a spell attack picks its targets")
	dm._ui._toggle_target(CHIEF)
	dm._ui.roll_attack()
	_check(_used(dm, 1) == 1 and dm.rolls.any(func(r: Dictionary) -> bool: return r.get("attack") is Dictionary and str(r.attack.get("name", "")) == "Test Ray"), "Test Ray: a level 1 slot, an attack card")

	# a save spell, upcast
	menu = hud.cast_menu("spells/test-burst")
	menu.id_pressed.emit(1)
	_check(dm._ui.attack.get("kind") == "save" and dm._ui.attack.opts.level == 2, "upcast from the menu: a save at level 2")
	dm._ui._toggle_target(CHIEF)
	dm._ui.roll_attack()
	_check(_used(dm, 2) == 1 and _used(dm, 1) == 1 and dm.rolls.any(func(r: Dictionary) -> bool: return r.get("save") is Dictionary and str(r.save.name) == "Test Burst"), "the level 2 slot is spent")

	# concentration
	dm.cast(BORIN, "spells/test-hold")
	dm._ui._toggle_target(CHIEF)
	dm._ui.roll_attack()
	_check(_used(dm, 2) == 2 and str((dm.concentration_of(BORIN) as Dictionary).get("spell", "")) == "spells/test-hold", "Test Hold: concentration via TASK-59 (%s)" % [dm.concentration_of(BORIN)])

	# a ritual, then no slot left
	dm.cast(BORIN, "spells/test-alarm", 1, true)
	_check(_used(dm, 1) == 1 and _last(dm).contains("as a ritual"), "a ritual spends nothing")
	dm.use_resource(BORIN, "spell_slots.1", 3)
	var lines := dm.rolls.size()
	dm.cast(BORIN, "spells/test-alarm", 1)
	_check(dm.rolls.slice(lines).any(func(r: Dictionary) -> bool: return "no level 1 slot left" in str(r.get("text", ""))) and _last(dm).contains("casts Test Alarm"), "none left: cast anyway, the DM is told")

	# items
	dm.change_item(BORIN, "items/wand-test", 1)
	dm.change_item(BORIN, "items/potion-test", 2)
	dm.use_action(BORIN, "items/wand-test")
	var res := {}
	for r: Dictionary in dm.resources_of(dm.sheet_for(Reveal.DM, BORIN)):
		res[r.id] = r
	_check(res["charges.items/wand-test"].used == 1, "the wand: a charge")
	dm._handle_hp(1, BORIN, -10, "test")
	var hp0 := int(dm.sheet_for(Reveal.DM, BORIN).hp)
	dm.use_action(BORIN, "items/potion-test")
	var s := dm.sheet_for(Reveal.DM, BORIN)
	_check(HudWidgets.quick_amount("item", "items/potion-test", s) == "1", "the potion: one less (%s)" % [s.inventory])
	_check(int(s.hp) >= hp0 + 4 and int(s.hp) <= hp0 + 10, "it heals its drinker (%d → %d)" % [hp0, int(s.hp)])
	hud.free()
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("casting: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _used(dm: NetTable, level: int) -> int:
	return Replay.slots_used(dm.sheet_for(Reveal.DM, BORIN), level)


func _last(dm: NetTable) -> String:
	for i in range(dm.rolls.size() - 1, -1, -1):
		if str(dm.rolls[i].get("action", "")).begins_with("spells/"):
			return str(dm.rolls[i].get("text", ""))
	return ""


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
