extends SceneTree
## Headless check of the effects format (TASK-65): the parser on clear spell and feature texts
## (attack, save + half, area, At Higher Levels, cantrip scaling, conditions, save ends,
## healing), the effects winning over the text in Rules, the coverage count and the entry
## editor's effects field (presets, "From the text").
## godot --headless --path . -s tools/test_effects.gd

const DIR := "user://test_effects"

var _failed := 0


func _init() -> void:
	var fireball := {"name": "Fireball", "level": 3, "description": "Each creature in a 6.1 m-radius sphere centered on that point must make a dexterity saving throw. A target takes 8d6 fire damage on a failed save, or half as much damage on a successful one.\n\n**At Higher Levels:** When you cast this spell using a spell slot of 4th level or higher, the damage increases by 1d6 for each slot level above 3rd."}
	var fx := Effects.parse(fireball)
	_check(fx == [{"roll": "save", "ability": "dex", "dc": "spell", "on_fail": {"damage": [{"dice": "8d6", "type": "fire"}]}, "on_success": "half",
		"area": {"shape": "sphere", "size_m": 6.1}, "scaling": {"per_slot": "1d6", "above": 3}}], "Fireball (%s)" % [fx])
	fx = Effects.parse({"name": "Fire Bolt", "level": 0, "description": "Make a ranged spell attack against the target. On a hit, the target takes 1d10 fire damage.\n\n**At Higher Levels:** This spell's damage increases by 1d10 when you reach 5th level (2d10), 11th level (3d10), and 17th level (4d10)."})
	_check(fx == [{"roll": "attack", "to_hit": "spell", "range": "ranged", "damage": [{"dice": "1d10", "type": "fire"}], "scaling": {"cantrip": "1d10"}}], "Fire Bolt (%s)" % [fx])
	fx = Effects.parse({"name": "Hold Person", "level": 2, "concentration": true, "duration": "Concentration, up to 1 minute",
		"description": "The target must succeed on a wisdom saving throw or be paralyzed for the duration. At the end of each of its turns, the target can make another wisdom saving throw. On a success, the spell ends on the target."})
	_check(fx.size() == 1 and fx[0].on_fail == {"conditions": ["paralyzed"]} and fx[0].duration == {"rounds": 10, "save_ends": true} and fx[0].concentration, "Hold Person: paralyzed, 1 minute, save ends (%s)" % [fx])
	fx = Effects.parse({"name": "Cure Wounds", "level": 1, "description": "A creature you touch regains a number of hit points equal to 1d8 + your spellcasting ability modifier.\n\n**At Higher Levels:** When you cast this spell using a spell slot of 2nd level or higher, the healing increases by 1d8 for each slot level above 1st."})
	_check(fx == [{"heal": "1d8+mod", "scaling": {"per_slot": "1d8", "above": 1}}], "Cure Wounds (%s)" % [fx])
	fx = Effects.parse({"name": "Fire Breath", "text": "The dragon exhales fire in a 18.3 m cone. Each creature in that area must make a DC 21 Dexterity saving throw, taking 63 (18d6) fire damage on a failed save, or half as much damage on a successful one."})
	_check(fx.size() == 1 and fx[0].dc == 21 and fx[0].area == {"shape": "cone", "size_m": 18.3} and fx[0].on_fail.damage == [{"dice": "18d6", "type": "fire"}], "a dragon's breath (%s)" % [fx])
	fx = Effects.parse({"name": "Bite", "text": "Melee Weapon Attack: +4 to hit.", "attack": {"kind": "Melee Weapon Attack", "to_hit": 4, "damage": [{"dice": "1d6 + 2", "type": "piercing"}]}})
	_check(fx == [{"roll": "attack", "to_hit": 4, "range": "melee", "damage": [{"dice": "1d6+2", "type": "piercing"}]}], "a creature's attack (%s)" % [fx])
	_check(Effects.parse({"name": "Mage Hand", "description": "A spectral hand appears."}).is_empty(), "nothing clear: no effects (the text stays)")
	_check(Effects.area_of("a line 30.5 m long and 1.5 m wide") == {"shape": "line", "size_m": 30.5, "width_m": 1.5} and Effects.area_of("a 3 m cube").shape == "cube", "areas")

	# the effects win over the text
	var caster := {"stats": {"int": 18}, "classes": [{"class": "classes/wizard", "level": 5}]}
	var hand := {"name": "Odd Bolt", "description": "It must make a strength saving throw or take 1d4 cold damage.",
		"effects": [{"roll": "save", "ability": "con", "dc": "spell", "on_fail": {"damage": [{"dice": "3d6", "type": "acid"}]}, "on_success": "half"}]}
	var save := Rules.save_effect(hand, caster)
	_check(save.ability == "con" and save.dc == Rules.spell_dc(caster) and save.damage == [{"dice": "3d6", "type": "acid"}] and save.half, "Rules.save_effect reads the effects (%s)" % [save])
	_check(Rules.save_effect(hand, caster, false).ability == "str", "the text path still there")
	var atk := Rules.spell_attack_of({"name": "X", "description": "", "effects": [{"roll": "attack", "to_hit": "spell", "range": "melee", "damage": [{"dice": "2d8", "type": "radiant"}]}]}, caster)
	_check(atk.to_hit == Rules.spell_attack(caster) and not atk.ranged and Rules.spell_kind({"effects": [{"roll": "attack"}]}) == "attack", "a spell attack from the effects")
	var cov := Effects.coverage([fireball.merged({"effects": Effects.parse(fireball)}), {"name": "Mage Hand"}])
	_check(cov.total == 2 and cov.with == 1 and cov.save == 1 and cov.area == 1 and cov.scaling == 1, "coverage (%s)" % [cov])
	_check(Schema.fields("spells").any(func(f: Dictionary) -> bool: return f.key == "effects" and f.type == "effects")
		and Schema.fields("features").any(func(f: Dictionary) -> bool: return f.key == "effects"), "effects in the Schema")

	# the editor's effects field
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var store := EntryStore.create_world(ProjectSettings.globalize_path(DIR), "fx")
	var form := EntryEditor.new()
	root.add_child(form)
	form.setup(store, "spells", fireball.merged({"id": "fireball"}))
	await process_frame
	var field := form.find_child("Field_effects", true, false)
	_check(field != null and form.find_child("Presets", true, false) != null, "the effects field with presets")
	(form.find_child("FromText", true, false) as Button).pressed.emit()
	var got: Variant = form.collect().get("entry", {}).get("effects")
	_check(got is Array and (got as Array).size() == 1 and str(got[0].roll) == "save", "From the text fills it (%s)" % [got])
	(form.find_child("Presets", true, false) as MenuButton).get_popup().id_pressed.emit(Effects.PRESETS.keys().find("Heal"))
	got = form.collect().get("entry", {}).get("effects")
	_check(got is Array and (got as Array).size() == 2 and str(got[1].heal) == "1d8+mod", "a preset is added (%s)" % [got])
	form.free()
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("effects: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
