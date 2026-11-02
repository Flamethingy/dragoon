extends SceneTree
## Headless check of targeted attacks (TASK-54): to-hit per target against its AC (+ cover),
## natural 20 / 1, the crit house rule, resistance / immunity / vulnerability, damage applied
## at once (Auto) with undo from the card, Assist leaving an Apply, Multiattack, and the
## table's target picking.
## godot --headless --path . -s tools/test_attacks.gd

const PORT := 47795
const DIR := "user://test_attacks"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"
const ARIA := "characters/aria"

var _failed := 0


func _init() -> void:
	# --- Damage types, cover, multiattack ----------------------------------------------------------
	var troll := {"resistances": ["Slashing"], "immunities": ["poison"], "vulnerabilities": ["fire"]}
	_check(Rules.damage_after(troll, 9, "slashing") == {"amount": 4, "note": "resistant"} and Rules.damage_after(troll, 9, "poison").amount == 0
		and Rules.damage_after(troll, 9, "fire") == {"amount": 18, "note": "vulnerable"} and Rules.damage_after(troll, 9, "cold").note == "", "resistance halves, immunity 0, vulnerability doubles")
	_check(Rules.damage_after({"resistances": ["bludgeoning, piercing, and slashing from nonmagical attacks"]}, 10, "piercing").amount == 5, "a long resistance text counts its types")
	_check(Rules.cover_bonus("half") == 2 and Rules.cover_bonus("three_quarters") == 5 and Rules.cover_bonus("") == 0, "cover")
	var feats := {"bite": {"name": "Bite", "attack": {"to_hit": 5, "damage": [{"dice": "2d6+3", "type": "piercing"}]}},
		"claws": {"name": "Claws", "attack": {"to_hit": 5, "damage": [{"dice": "1d8+3", "type": "slashing"}]}},
		"multi": {"name": "Multiattack", "text": "The bear makes two attacks: one with its Bite and one with its Claws."},
		"multi2": {"name": "Multiattack", "text": "The goblin makes two attacks with its Scimitar."},
		"scim": {"name": "Scimitar", "attack": {"to_hit": 4, "damage": [{"dice": "1d6+2", "type": "slashing"}]}},
		"multi3": {"name": "Multiattack", "text": "The hydra makes three Bite attacks."}}
	_check(Dice.multiattack({"actions": ["multi", "bite", "claws"]}, feats) == ["Bite", "Claws"], "one with its Bite and one with its Claws")
	_check(Dice.multiattack({"actions": ["multi2", "scim"]}, feats) == ["Scimitar", "Scimitar"], "two attacks with its Scimitar (%s)" % [Dice.multiattack({"actions": ["multi2", "scim"]}, feats)])
	_check(Dice.multiattack({"actions": ["multi3", "bite"]}, feats) == ["Bite", "Bite", "Bite"] and Dice.multiattack({"actions": ["bite"]}, feats).is_empty(), "three Bite attacks; none without Multiattack")
	var bite := Dice.attack_of({"actions": ["bite"]}, "attack with bite", feats)
	_check(bite.name == "Bite" and bite.to_hit == 5 and bite.damage == [{"dice": "2d6+3", "type": "piercing"}], "an attack's parts")

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	var borin := tl.entry(BORIN).duplicate(true)
	borin["ac"] = 1  # always hit (but a natural 1)
	borin["resistances"] = ["slashing"]
	tl.edit_entry("characters", borin)
	var aria := tl.entry(ARIA).duplicate(true)
	aria["ac"] = 40  # only a natural 20 hits
	tl.edit_entry("characters", aria)
	tl.edit_entry("features", {"id": "multiattack-chief", "name": "Multiattack", "text": "The chief makes two attacks with its Scimitar."})
	var chief := tl.entry(CHIEF).duplicate(true)
	chief["actions"] = ["multiattack-chief", "scimitar-chief"]
	tl.edit_entry("creatures", chief)
	await process_frame
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))
	var hp0 := int(dm.sheet_for(Reveal.DM, BORIN).hp)

	# Auto: hits apply at once, resistance shown
	dm.rng.seed = 7
	var cards := dm._handle_attack(1, CHIEF, "scimitar", [BORIN, ARIA], {})
	_check(cards.size() == 1 and (cards[0].attack.targets as Array).size() == 2, "one card, a line per target")
	var rows: Array = cards[0].attack.targets
	var on_borin: Dictionary = rows[0]
	_check(on_borin.hit == (on_borin.formula != "" and not on_borin.fumble) and on_borin.ac == 1, "Borin (AC 1) is hit unless it's a natural 1 (%s)" % [on_borin])
	_check(not rows[1].hit or rows[1].crit, "Aria (AC 40): only a natural 20 hits")
	if on_borin.hit:
		_check(on_borin.damage[0].note == "resistant" and on_borin.damage[0].amount == on_borin.damage[0].rolled / 2, "slashing on resistant Borin is halved (%s)" % [on_borin.damage])
		_check(int(dm.sheet_for(Reveal.DM, BORIN).hp) == hp0 - int(on_borin.amount) and int(on_borin.applied) > 0, "applied at once as hp.changed")
		var bb := NetTable.roll_bbcode(cards[0])
		_check(bb.contains("→ Borin") and bb.contains("(resistant)") and bb.contains("[url=undo:"), "the card: per target, resistance, undo (%s)" % bb)
		_check(dm.undo_card(int(cards[0].id)) == 1 and int(dm.sheet_for(Reveal.DM, BORIN).hp) == hp0, "undo on the card gives the HP back")

	# a crit: the world's rule (max dice + roll)
	var crit := {}
	for seed in range(1, 400):
		dm.rng.seed = seed
		var s := dm.rules_settings().duplicate(true)
		var c := dm._handle_attack(1, CHIEF, "scimitar", [ARIA], {})
		if not c.is_empty() and c[0].attack.targets[0].crit:
			crit = c[0].attack.targets[0]
			break
	_check(not crit.is_empty() and crit.hit and str(crit.damage[0].formula) == "6+1d6+2", "a natural 20 hits even AC 40, damage 6+1d6+2 (%s)" % [crit])
	_check(not crit.is_empty() and int(crit.damage[0].rolled) >= 9, "max dice plus a roll")

	# cover and a chosen advantage
	dm.rng.seed = 3
	var covered := dm._handle_attack(1, CHIEF, "scimitar", [BORIN], {"cover": "three_quarters", "advantage": 1})
	_check(covered[0].attack.targets[0].ac == 6 and str(covered[0].attack.targets[0].formula).begins_with("2d20kh1"), "cover +5 and advantage before the roll")
	# conditions: restrained targets are attacked with advantage
	dm.set_condition(BORIN, "restrained")
	var vs_restrained := dm._handle_attack(1, CHIEF, "scimitar", [BORIN], {})
	_check(int(vs_restrained[0].attack.targets[0].advantage) == 1, "restrained: attackers get advantage")
	dm.set_condition(BORIN, "restrained", false)

	# Assist: an Apply on the card instead
	var s2 := dm.rules_settings().duplicate(true)
	s2["automation"] = {"damage": "assist"}
	dm.set_rules_settings(s2)
	var hp1 := int(dm.sheet_for(Reveal.DM, BORIN).hp)
	var assisted := {}
	for seed in range(1, 50):
		dm.rng.seed = seed
		var c := dm._handle_attack(1, CHIEF, "scimitar", [BORIN], {})
		if c[0].attack.targets[0].hit:
			assisted = c[0]
			break
	_check(not assisted.is_empty() and assisted.attack.targets[0].pending and int(dm.sheet_for(Reveal.DM, BORIN).hp) == hp1, "Assist: nothing taken off yet")
	_check(NetTable.roll_bbcode(assisted).contains("[url=apply:%d:%s]" % [int(assisted.id), BORIN]), "the card has an Apply")
	dm.apply_card(int(assisted.id), BORIN)
	_check(int(dm.sheet_for(Reveal.DM, BORIN).hp) == hp1 - int(assisted.attack.targets[0].amount), "Apply takes it off")
	_check(dm.apply_card(int(assisted.id), BORIN).is_empty(), "only once")
	s2["automation"] = {}
	dm.set_rules_settings(s2)

	# Multiattack: the listed attacks in a row
	var multi := dm._handle_attack(1, CHIEF, "", [BORIN], {"multi": true})
	_check(multi.size() == 2 and multi.all(func(c: Dictionary) -> bool: return c.attack.name == "Scimitar"), "Multiattack: two Scimitar cards")
	_check(dm.sheet_for(Reveal.DM, CHIEF)._multiattack and SheetPanel.to_bbcode(dm.sheet_for(Reveal.DM, CHIEF)).contains("[url=attack:multiattack]"), "the sheet has a Multiattack link")

	# the table: pick targets by clicking, then roll
	dm.begin_attack(CHIEF, "scimitar")
	var ui := dm._ui
	_check(ui.attack_bar.visible, "the attack bar asks for targets")
	dm.grid.token_clicked.emit(BORIN)
	dm.grid.token_clicked.emit(CHIEF)  # not itself
	_check(ui.attack.targets == [BORIN] and (dm.grid.tokens[BORIN].get_node("Marks") as TokenMarks).targeted, "a click picks a target (red ring) (%s, sel %s)" % [ui.attack.targets, dm.grid.selection()])
	var before := dm.rolls.size()
	ui.roll_attack()
	_check(dm.rolls.size() > before and dm.rolls[-1].has("attack") and not ui.attack_bar.visible and not (dm.grid.tokens[BORIN].get_node("Marks") as TokenMarks).targeted,
		"Roll: the card, the bar and rings go away")

	dm.queue_free()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("attacks: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
