extends SceneTree
## Headless check of the Rules module and the dragoon-core data (TASK-53): derived stats,
## overrides, conditions per edition, crits by house rule, world settings.
## godot --headless --path . -s tools/test_rules.gd

var _failed := 0


func _init() -> void:
	# --- dragoon-core -------------------------------------------------------------------------
	var conds := Rules.conditions()
	var fifteen := ["blinded", "charmed", "deafened", "frightened", "grappled", "incapacitated", "invisible", "paralyzed",
		"petrified", "poisoned", "prone", "restrained", "stunned", "unconscious", "exhaustion"]
	_check(fifteen.all(func(c: String) -> bool: return conds.has(c)), "the 15 conditions and exhaustion")
	_check("attack_disadvantage" in Rules.condition("poisoned").flags and Rules.condition("poisoned", "2024").text != "", "flags and text per edition")
	_check("breaks_concentration" in Rules.condition("incapacitated", "2024").flags and "breaks_concentration" not in Rules.condition("incapacitated", "2014").flags,
		"2024 differs where the rules do")
	_check("hp_max_half" in Rules.condition("exhaustion", "2014", 4).flags and "hp_max_half" not in Rules.condition("exhaustion", "2014", 2).flags, "exhaustion by level")
	_check(Rules.core().damage_types.size() == 13 and Rules.weapon("items/longsword").damage == "1d8" and Rules.armor("chain-mail").ac == 16, "damage types, weapons, armor")
	_check(Rules.core().proficiency_by_level.size() == 20 and Rules.core().xp_by_cr.has("0.25"), "level and XP tables")

	# --- Derived stats ------------------------------------------------------------------------
	var rogue := {"stats": {"str": 10, "dex": 16, "con": 12, "int": 13, "wis": 14, "cha": 8},
		"classes": [{"class": "classes/rogue", "level": 5}], "saves": ["dex", "int"], "skills": ["stealth", "perception"],
		"expertise": ["stealth"]}
	_check(Rules.level(rogue) == 5 and Rules.proficiency(rogue) == 3, "proficiency by level")
	_check(Rules.save(rogue, "dex") == 6 and Rules.save(rogue, "str") == 0, "saves with proficiency")
	_check(Rules.skill(rogue, "stealth") == 9 and Rules.skill(rogue, "perception") == 5 and Rules.skill(rogue, "arcana") == 1, "skills: expertise, proficient, plain")
	_check(Rules.passive(rogue, "perception") == 15, "passive Perception")
	var bard := {"stats": {"cha": 16, "dex": 12}, "classes": [{"class": "classes/bard", "level": 3}], "jack_of_all_trades": true}
	_check(Rules.skill(bard, "athletics") == 1 and Rules.initiative(bard) == 2, "Jack of All Trades: half proficiency")
	_check(Rules.spell_dc(bard) == 13 and Rules.spell_attack(bard) == 5 and Rules.casting_ability(bard) == "cha", "spell DC and attack")
	_check(Rules.slots(bard) == [4, 2] and Rules.slots({"classes": [{"class": "classes/warlock", "level": 5}]}) == [0, 0, 2], "slot tables")
	var goblin := {"cr": "1/4", "stats": {"dex": 14}}
	_check(Rules.proficiency(goblin) == 2 and Rules.proficiency({"cr": 9}) == 4, "proficiency by CR")
	# overrides: a stored value wins and is marked
	var stored := rogue.duplicate(true)
	stored["skills"] = {"stealth": 12, "perception": null}
	stored["proficiency_bonus"] = 3
	stored["ac"] = 17
	var d := Rules.derived(stored)
	_check(d.skill_stealth.value == 12 and d.skill_stealth.override and d.skill_perception.value == 5 and not d.skill_perception.override,
		"a stored skill overrides and is marked (%s, %s)" % [d.skill_stealth, d.skill_perception])
	_check(not d.proficiency.override and d.ac.value == 17 and d.ac.override, "a stored value equal to the computed one is no override")
	# AC from equipped armor
	var knight := {"stats": {"dex": 16}, "inventory": [{"item": "items/chain-mail", "equipped": true}, {"item": "items/shield", "equipped": true},
		{"item": "items/leather", "equipped": false}]}
	_check(Rules.ac(knight) == 18 and Rules.ac({"stats": {"dex": 16}, "inventory": [{"item": "items/hide", "equipped": true}]}) == 14, "AC from armor (Dex capped) and shield")
	# resources and hit dice from the class tables
	var monk := {"stats": {"wis": 14}, "classes": [{"class": "classes/monk", "level": 4}, {"class": "classes/fighter", "level": 2}]}
	var res := Rules.resources(monk)
	_check(res.any(func(r: Dictionary) -> bool: return r.id == "ki" and r.max == 4 and r.reset == "short")
		and res.any(func(r: Dictionary) -> bool: return r.id == "action_surge" and r.max == 1), "class resources (%s)" % [res])
	_check(Rules.hit_dice(monk) == {8: 4, 10: 2}, "hit dice")
	_check(Rules.cantrip_dice({"classes": [{"class": "classes/wizard", "level": 5}]}) == 2 and Rules.cantrip_dice({"classes": [{"class": "classes/wizard", "level": 17}]}) == 4, "cantrip scaling")

	# --- Conditions suggest advantage, never force --------------------------------------------
	var poisoned := {"conditions": ["poisoned"]}
	_check(Rules.suggested_advantage(poisoned, "attack") == -1 and Rules.suggested_advantage(poisoned, "check") == -1
		and Rules.suggested_advantage({"conditions": ["restrained"]}, "save:dex") == -1 and Rules.suggested_advantage({"conditions": ["prone", "invisible"]}, "attack") == 0,
		"conditions suggest advantage / disadvantage")
	_check(Rules.d20_penalty({"conditions": ["exhaustion"], "exhaustion": 2}, "2024") == -4 and Rules.d20_penalty({"conditions": ["exhaustion"], "exhaustion": 2}, "2014") == 0,
		"2024 exhaustion: -2 per level on d20 tests")

	# --- Crits: the house rule (decision 4) ------------------------------------------------------
	_check(Rules.crit_formula("2d6+3") == "12+2d6+3", "house rule: max dice + a normal roll (%s)" % Rules.crit_formula("2d6+3"))
	_check(Rules.crit_formula("2d6+3", {"house_rules": {"crit": "double"}}) == "4d6+3", "rules as written: double dice")
	_check(Rules.crit_formula("1d8+1d6-1") == "14+1d8+1d6-1", "several dice terms")

	# --- World settings --------------------------------------------------------------------------
	_check(Rules.settings_of({}).edition == "2014" and Rules.settings_of({}).house_rules.crit == "max_plus_roll", "defaults: 2014, our crit rule")
	_check(Rules.settings_of({"edition": "2024", "house_rules": {"flanking": "advantage"}}).house_rules.crit == "max_plus_roll", "settings merge with the defaults")
	_check(Rules.edition_of({"edition": "2024"}, {"edition": "2014"}) == "2024" and Rules.edition_of({}, {"edition": "2024"}) == "2024", "an entry's own edition wins")
	var dir := ProjectSettings.globalize_path("user://test_rules")
	PackageManager._delete_tree(dir)
	Worlds.install_example(dir)
	var tl := Timeline.new(dir.path_join("westmarch/timelines/red-fang"))
	_check(tl.rules_settings().house_rules.crit == "max_plus_roll", "the example world has our crit rule")
	tl.set_rules_settings({"edition": "2024"})
	_check(Timeline.new(dir.path_join("westmarch/timelines/red-fang")).rules_settings().edition == "2024", "the world keeps its edition")
	PackageManager._delete_tree(dir)

	# --- Automation levels (TASK-60) --------------------------------------------------------------
	var defaults := Rules.settings_of({})
	_check(["damage", "healing", "conditions", "durations", "resources", "concentration", "death_saves"].all(func(c: String) -> bool: return Rules.automation(defaults, c) == "auto")
		and Rules.automation(defaults, "reactions") == "off" and Rules.automation(defaults, "movement") == "assist", "automation defaults as decided")
	_check(Rules.automation(Rules.settings_of({"automation": {"damage": "off", "healing": "bogus"}}), "damage") == "off"
		and Rules.automation(Rules.settings_of({"automation": {"healing": "bogus"}}), "healing") == "auto", "a world's level wins, junk falls back")

	# --- Dice use the Rules module --------------------------------------------------------------
	_check(Dice.resolve(rogue, "stealth")[0].formula == "1d20+9" and Dice.resolve(bard, "athletics")[0].formula == "1d20+1", "dice roll with the derived bonuses")

	print("rules: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
