extends SceneTree
## Headless check of save-based actions (TASK-55): the DC from the feature or the caster's
## spell DC, damage rolled once, the DM's creatures save at once, players get a prompt (the
## DM can roll for an absent one), fail = damage + named conditions, success = half when the
## text says so; applied as events with undo.
## godot --headless --path . -s tools/test_saves.gd

const PORT := 47797
const ADDRESS := "127.0.0.1:47797"
const DIR := "user://test_saves"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const WOLF := "creatures/dire-wolf"
const ARIA := "characters/aria"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	# --- What a feature or spell does ------------------------------------------------------------
	var breath := {"name": "Acid Breath (Recharge 5-6)", "save": {"dc": 18, "ability": "dex"},
		"text": "The dragon exhales acid in a 18.3 m line. Each creature in that line must make a DC 18 Dexterity saving throw, taking 54 (12d8) acid damage on a failed save, or half as much damage on a successful one."}
	var fx := Rules.save_effect(breath)
	_check(fx.ability == "dex" and fx.dc == 18 and fx.damage == [{"dice": "12d8", "type": "acid"}] and fx.half and fx.conditions.is_empty(), "breath: DC, damage, half (%s)" % [fx])
	var spit := Rules.save_effect({"name": "Spit", "text": "The target must succeed on a DC 12 Constitution saving throw or be poisoned for 1 minute."})
	_check(spit.ability == "con" and spit.dc == 12 and spit.conditions == ["poisoned"] and spit.duration == {"rounds": 10} and not spit.half and spit.damage.is_empty(),
		"a condition on a failed save, with its duration (%s)" % [spit])
	var wiz := {"stats": {"int": 18}, "classes": [{"class": "classes/wizard", "level": 5}]}
	var hands := Rules.save_effect({"name": "Burning Hands", "level": 1, "description": "Each creature in a 4.5 m cone must make a Dexterity saving throw. A creature takes 3d6 fire damage on a failed save, or half as much damage on a successful one."}, wiz)
	_check(hands.dc == 15 and hands.ability == "dex" and hands.damage[0].dice == "3d6" and hands.half, "a spell: the caster's spell DC (%s)" % [hands])
	_check(Rules.save_effect({"name": "Bite", "text": "Melee Weapon Attack: +4 to hit."}).is_empty(), "no save, no effect")

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("features", {"id": "fire-breath", "name": "Fire Breath", "save": {"dc": 13, "ability": "dex"},
		"text": "Each creature in a 4.5 m cone must make a DC 13 Dexterity saving throw, taking 22 (4d10) fire damage on a failed save, or half as much damage on a successful one."})
	tl.edit_entry("features", {"id": "stench", "name": "Stench", "save": {"dc": 30, "ability": "con"},
		"text": "Each creature within 3 m must succeed on a DC 30 Constitution saving throw or be poisoned for 1 minute."})
	var chief := tl.entry(CHIEF).duplicate(true)
	chief["actions"] = ["scimitar-chief", "fire-breath", "stench"]
	tl.edit_entry("creatures", chief)
	tl.edit_entry("spells", {"id": "test-burst", "name": "Test Burst", "level": 1,
		"description": "Each creature in a 6 m radius must make a Dexterity saving throw. A creature takes 3d6 fire damage on a failed save, or half as much damage on a successful one."})
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc == ARIA and ann.grid.tokens.has(WOLF))
	var wolf_hp := int(dm.sheet_for(Reveal.DM, WOLF).hp)
	var aria_hp := int(dm.sheet_for(Reveal.DM, ARIA).hp)
	_check(SheetPanel.to_bbcode(dm.sheet_for(Reveal.DM, CHIEF)).contains("[url=saveact:Fire Breath]"), "the sheet links its save actions")

	var card := dm._handle_save_action(1, CHIEF, "Fire Breath", [WOLF, ARIA, BORIN], {})
	var rows: Array = card.save.targets
	_check(rows.size() == 3 and rows[0].has("success") and rows[1].get("waiting", false) and rows[2].get("waiting", false), "the wolf saves at once, Aria and Borin wait")
	var w: Dictionary = rows[0]
	var rolled := int(card.save.damage[0].rolled)
	_check(int(w.amount) == (rolled / 2 if w.success else rolled), "fail: full damage, success: half (%s of %d)" % [w, rolled])
	_check(int(dm.sheet_for(Reveal.DM, WOLF).hp) == maxi(wolf_hp - int(w.amount), 0), "taken off the wolf at once")
	_check(NetTable.roll_bbcode(card).contains("DC 13 DEX save") and NetTable.roll_bbcode(card).contains("waiting for the save"), "the card: DC, damage, who still saves")
	# Ann's prompt
	await _until(func() -> bool: return ann.rolls.any(func(r: Dictionary) -> bool: return r.get("action") == "save_prompt"))
	var prompt: Array = ann.rolls.filter(func(r: Dictionary) -> bool: return r.get("action") == "save_prompt")
	_check(not prompt.is_empty() and NetTable.roll_bbcode(prompt[0]).contains("DEX save DC 13") and NetTable.roll_bbcode(prompt[0]).contains("[url=save:%d:%s]" % [int(card.id), ARIA]),
		"Ann gets \"DEX save DC 13 · Roll\"")
	_check(not ann.rolls.any(func(r: Dictionary) -> bool: return r.get("action") == "save_prompt" and r.ref == BORIN), "only for her own")
	ann.answer_save(int(card.id), ARIA)
	await _until(func() -> bool: return dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "dice.rolled" and e.entity == ARIA and e.data.has("save")))
	var answer: Array = dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "dice.rolled" and e.entity == ARIA and e.data.has("save"))
	var ar: Dictionary = answer[0].data.save.targets[0] if not answer.is_empty() else {}
	_check(not ar.is_empty() and answer[0].by == "ann" and int(dm.sheet_for(Reveal.DM, ARIA).hp) == maxi(aria_hp - int(ar.amount), 0), "her save, and its damage on her (%s)" % [ar])
	ann.answer_save(int(card.id), ARIA)  # twice: nothing
	ann.answer_save(int(card.id), BORIN)  # not hers
	await process_frame
	await process_frame
	_check(dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "dice.rolled" and e.data.has("save") and e.entity in [ARIA, BORIN]).size() == 1, "once, and only her own")
	dm.answer_save(int(card.id), BORIN)  # Bob is away: the DM rolls
	_check(dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "dice.rolled" and e.entity == BORIN and e.data.has("save") and e.by == "dm")
		and dm._pending_saves.is_empty(), "the DM rolls for an absent player; nothing waits any more")

	# a failed save puts the condition on (with its duration); undo takes it off again
	var stench := dm._handle_save_action(1, CHIEF, "Stench", [WOLF], {})
	_check(not stench.save.targets[0].success and "poisoned" in dm.conditions_of(WOLF).conditions, "failed: poisoned")
	_check(dm.sheet_for(Reveal.DM, WOLF).get("condition_durations", {}).get("poisoned", {}).get("rounds", 0) == 10, "for 1 minute = 10 rounds")
	dm.undo_card(int(stench.id))
	_check("poisoned" not in dm.conditions_of(WOLF).conditions, "undo on the card takes it off")

	# a spell: the caster's spell DC
	ann.save_action(ARIA, "spells/test-burst", [WOLF])
	await _until(func() -> bool: return dm.rolls.any(func(r: Dictionary) -> bool: return r.get("save") is Dictionary and r.save.name == "Test Burst"))
	var burst: Array = dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("save") is Dictionary and r.save.name == "Test Burst")
	_check(not burst.is_empty() and int(burst[0].save.dc) == Rules.spell_dc(dm.sheet_for(Reveal.DM, ARIA)), "Aria's spell uses her spell DC (%s)" % [burst[0].save.dc if not burst.is_empty() else -1])

	dm.queue_free()
	ann.queue_free()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("saves: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
