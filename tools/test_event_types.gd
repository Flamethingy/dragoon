extends SceneTree
## Headless check of the event types added in TASK-17 (doc-1 "More event types"): every type
## is written to the log, survives a restart and rebuilds state with Replay.
## godot --headless --path . -s tools/test_event_types.gd

const FILE := "user://test_event_types/events.jsonl"

var _failed := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FILE).get_base_dir())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	var w := EventLog.open(FILE)
	w.start_session(4)
	var t := "characters/thalia"
	# Combat
	w.append("combat.started", "", {"map": "maps/forest-road", "order": [{"entity": "creatures/goblin-chief", "initiative": 12}]})
	w.append("initiative.rolled", t, {"total": 17, "formula": "1d20+3"})
	w.append("initiative.rolled", "creatures/dire-wolf", {"total": 12})
	w.append("combat.turn", "", {"round": 2, "turn": 1})
	# Conditions, resources, death saves, rests
	w.append("condition.applied", t, {"condition": "poisoned", "source": "creatures/giant-spider"})
	w.append("condition.applied", t, {"condition": "prone"})
	w.append("condition.removed", t, {"condition": "prone"})
	w.append("resource.used", t, {"resource": "spell_slots.1", "amount": 2})
	w.append("resource.used", t, {"resource": "second_wind"})
	w.change_hp(t, -24, 0, "spider bite")
	w.append("death_save.rolled", t, {"success": false, "roll": 1, "count": 2})
	w.append("death_save.rolled", t, {"success": true, "roll": 14})
	var state_mid := Replay.entity_state({"hp": 24}, w.effective(t))
	w.change_hp(t, 5, 5, "healing word")
	w.append("resource.restored", t, {"resource": "second_wind"})
	w.append("combat.ended", "", {"reason": "goblins fled"})
	w.append("rest.taken", t, {"kind": "short", "restores": ["ki"]})
	# Money, relationships, quests, travel, weather, party, drafts
	w.append("currency.changed", t, {"delta": {"gp": 15, "sp": -3}, "reason": "goblin loot"})
	w.append("currency.changed", t, {"delta": {"gp": -5}, "reason": "inn"})
	w.append("relationship.changed", "characters/mira", {"with": t, "from": "neutral", "to": "friendly", "reason": "saved her brother"})
	w.append("relationship.changed", "factions/red-fang-clan", {"with": "party", "from": 0, "to": -2})
	w.append("quest.updated", "quests/red-fang-road", {"status": "open", "step": 1, "text": "Found the caravan"})
	w.append("quest.updated", "quests/red-fang-road", {"step": 2, "text": "Freed the prisoner"})
	w.append("quest.updated", "quests/red-fang-road", {"status": "done"})
	w.append("party.split", "", {"groups": [[t], ["characters/aria", "characters/borin"]]})
	w.append("party.arrived", t, {"place": "places/thornwick", "map": "maps/westmarch", "at": [8, 6]})
	w.append("weather.changed", "", {"region": "places/westmarch", "weather": "heavy rain", "temperature": 9, "wind": "strong"})
	w.append("assistant.drafted", "characters/mira", {"assistant": "Tamago", "field": "description", "text": "A draft...", "status": "draft"})
	w.gain_item(t, "items/rope", 1)
	w.gain_item(t, "items/moonstone-amulet", 1)
	w.lose_item(t, "items/torch", 2)
	w.append("rest.taken", t, {"kind": "long", "hp": 24})
	w.append("party.merged", "", {"place": "places/thornwick"})

	var again := EventLog.open(FILE)  # everything from disk
	_check(again.events.size() == w.events.size(), "all new types survive a restart")

	# Mid-fight state
	_check(state_mid.get("conditions") == ["poisoned"], "conditions applied/removed (%s)" % [state_mid.get("conditions")])
	_check(state_mid.get("resources_used") == {"spell_slots.1": 2, "second_wind": 1}, "resources used (%s)" % [state_mid.get("resources_used")])
	_check(state_mid.get("death_saves") == {"failures": 2, "successes": 1}, "death saves (%s)" % [state_mid.get("death_saves")])

	var base := {"hp": 24, "temp_hp": 3, "inventory": [{"item": "items/moonstone-amulet", "qty": 1, "equipped": true}, {"item": "items/torch", "qty": 2}]}
	var s := Replay.entity_state(base, again.effective(t))
	_check(not s.has("death_saves"), "healing clears death saves")
	_check(s.hp == 24 and not s.has("temp_hp") and not s.has("resources_used"), "long rest: HP, resources and temp HP")
	_check(s.get("currency") == {"gp": 10, "sp": -3}, "currency adds up (%s)" % [s.get("currency")])
	_check(s.get("location") == "places/thornwick", "party.arrived sets the location")
	_check(s.inventory == [{"item": "items/moonstone-amulet", "qty": 2, "equipped": true}, {"item": "items/rope", "qty": 1}], "items on a list inventory keep its shape (%s)" % [s.inventory])
	_check(base.inventory.size() == 2 and base.hp == 24, "the base entity is never changed")

	# TASK-51: one slot scheme, levels in classes[]
	var old_slots := Replay.entity_state({}, [
		{"type": "sheet.changed", "data": {"path": "spell_slots_used.1", "to": 2}},
		{"type": "sheet.changed", "data": {"path": "spell_slots_used.2", "to": 1}},
		{"type": "resource.used", "data": {"resource": "spell_slots.1", "amount": 1}},
		{"type": "sheet.changed", "data": {"path": "spell_slots_used.2", "to": 0}}])
	_check(old_slots.get("resources_used") == {"spell_slots.1": 3} and not old_slots.has("spell_slots_used") and Replay.slots_used(old_slots, 1) == 3,
		"old sheet.changed slots replay as resources (%s)" % [old_slots])
	var leveled := Replay.entity_state({"classes": [{"class": "classes/wizard", "level": 3}]}, [
		{"type": "level.gained", "data": {"class": "wizard", "level": 4}},
		{"type": "level.gained", "data": {"class": "classes/fighter", "level": 1}}])
	_check(leveled.classes == [{"class": "classes/wizard", "level": 4}, {"class": "classes/fighter", "level": 1}] and not leveled.has("levels"),
		"level.gained changes classes[] (%s)" % [leveled])
	_check(CharacterHud.spell_slots(leveled) == [4, 3], "slot math follows the new level")

	var mira := Replay.entity_state({}, again.effective("characters/mira"))
	_check(mira.get("relations") == {t: "friendly"}, "relationship (%s)" % [mira.get("relations")])
	_check(Replay.entity_state({}, again.effective("factions/red-fang-clan")).relations.party == -2, "faction standing")
	var quest := Replay.entity_state({}, again.effective("quests/red-fang-road"))
	_check(quest.quest_status == "done" and quest.progress.size() == 2 and quest.progress[1].text == "Freed the prisoner", "quest progress")
	_check(mira.size() == 1, "assistant drafts change nothing (%s)" % [mira])

	var world := Replay.world_state(again.effective())
	_check(world.combat.active == false and world.combat.round == 2, "combat ended (after round 2)")
	_check(world.weather["places/westmarch"].weather == "heavy rain" and world.weather["places/westmarch"].temperature == 9, "weather")
	_check(world.party_groups.is_empty(), "the party merged again")

	# Rewind into the fight.
	var fight: Array[Dictionary] = []
	for e in again.effective():
		fight.append(e)
		if e.type == "combat.turn":
			break
	var mid := Replay.world_state(fight)
	_check(mid.combat.active and mid.combat.round == 2 and mid.combat.map == "maps/forest-road", "rewound: combat running")
	_check(mid.combat.order.map(func(c: Dictionary) -> String: return c.entity) == [t, "creatures/dire-wolf", "creatures/goblin-chief"], "initiative order (%s)" % [mid.combat.order])
	var split := []
	for e in again.effective():
		split.append(e)
		if e.type == "party.split":
			break
	_check(Replay.world_state(split).party_groups == [[t], ["characters/aria", "characters/borin"]], "party split")

	print("event types: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
