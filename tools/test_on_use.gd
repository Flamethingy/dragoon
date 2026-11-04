extends SceneTree
## Headless check of "On Use" (TASK-108): the effects in plain words with coloured chips
## (Potion of Healing, Fireball, a skill-check item, follow-ups), the text fallback, the flow
## of nodes (targets, rolls, branches side by side) and that editing it writes the effects.
## godot --headless --path . -s tools/test_on_use.gd

var _failed := 0


func _init() -> void:
	var potion := {"_kind": "items", "name": "Potion of Healing", "type": ["Potion"], "rarity": "common",
		"effects": [{"heal": "2d4+2"}]}
	var fireball := {"_kind": "spells", "name": "Fireball", "level": 3, "range_m": 45.7, "effects": [
		{"roll": "save", "ability": "dex", "dc": "spell", "on_fail": {"damage": [{"dice": "8d6", "type": "fire"}]}, "on_success": "half",
			"area": {"shape": "sphere", "size_m": 6.1}, "scaling": {"per_slot": "1d6", "above": 3}}]}
	var rope := {"_kind": "items", "name": "Grappling Rope", "effects": [
		{"roll": "check", "skill": "athletics", "ability": "str", "dc": 15, "by": "self",
			"on_success": {"note": "you climb up"}, "on_fail": {"damage": [{"dice": "1d6", "type": "bludgeoning"}], "conditions": ["prone"]}}]}
	var potion_text := OnUse.plain(potion)
	_check(potion_text == "Targets [you or a creature] you [touch].\nRoll [2d4 + 2]: it [regains that many HP].", "potion (%s)" % potion_text)
	var fb := OnUse.plain(fireball)
	_check(fb.begins_with("Targets [all creatures] in a [6.1 m sphere] within [45.7 m].\nEach makes a [DEX save] against [your spell DC]. Failure: [8d6 fire]; success: [half].")
		and fb.contains("[+1d6 per slot above 3rd]"), "fireball (%s)" % fb)
	var rp := OnUse.plain(rope)
	_check(rp == "You make a [STR (Athletics) check] against [DC 15]. Success: you climb up. Failure: [1d6 bludgeoning], [prone].", "skill-check item (%s)" % rp)
	var chain := {"_kind": "spells", "range_m": 0, "effects": [{"roll": "attack", "to_hit": 5, "range": "melee", "damage": [{"dice": "1d8", "type": "piercing"}],
		"then": [{"when": "hit", "roll": "save", "ability": "con", "dc": 13, "on_fail": {"conditions": ["poisoned"]}, "on_success": "none", "duration": {"rounds": 10}}]}]}
	var ch := OnUse.plain(chain)
	_check(ch.contains("Make a [melee attack +5]. Hit: [1d8 piercing].") and ch.contains("On a hit: It makes a")
		and ch.contains("[CON save] against [DC 13]. Failure: [poisoned]; success: [nothing]. [1 minute]"), "follow-ups with when (%s)" % ch)
	_check(OnUse.plain({"effects": [{"modifier": {"target": "ac", "op": "add", "value": 5}, "duration": {"rounds": 1}}], "_kind": "spells", "range_m": 0}).contains("[+5 AC]"), "a modifier")
	var colours := OnUse.sentences(fireball)
	var kinds := []
	for s: Array in colours:
		for p: Variant in s:
			if p is Array:
				kinds.append(p[1])
	_check("target" in kinds and "roll" in kinds and "damage" in kinds and "time" in kinds, "chip kinds (%s)" % [kinds])
	_check(OnUse.color("target") == OnUse.BLUE and OnUse.color("heal") == UISkin.GREEN and OnUse.color("condition") == UISkin.ORANGE, "chip colours")

	# --- The view --------------------------------------------------------------------------------
	var v := OnUse.view(fireball)
	root.add_child(v)
	_check(v.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.get_meta("kind", "") == "damage").size() == 2
		and v.find_children("*", "HFlowContainer", true, false).size() == 2, "the view: sentences with chips")
	var none := OnUse.view({"_kind": "items", "name": "Rope"})
	_check(none.find_child("NoAutomation", true, false) != null, "no effects: the text fallback")
	var view := EntryView.new()
	root.add_child(view)
	view.setup(potion)
	_check(view.find_child("OnUse", true, false) != null, "the entry view shows On Use")
	_check(CardData.chips(potion).any(func(c: Array) -> bool: return c[1] == "Rarity") and CardData.chips(potion).any(func(c: Array) -> bool: return c[1] == "Type"), "item chips: rarity, type")

	# --- The flow --------------------------------------------------------------------------------
	var flow := OnUseFlow.new()
	root.add_child(flow)
	flow.setup(fireball.effects, fireball)
	var lines := flow.find_children("Line", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check(lines == ["All creatures · 6.1 m sphere · 45.7 m", "DEX save · spell DC", "8d6 fire", "half damage"], "fireball nodes (%s)" % [lines])
	var branches := flow.find_child("Branches", true, false)
	_check(branches is HBoxContainer and branches.get_child_count() == 2, "fail / success side by side")
	var got := []
	flow.changed.connect(func(list: Array) -> void: got.append(list.duplicate(true)))
	var plus := flow.find_child("Branch_fail", true, false).find_child("Plus", true, false) as MenuButton
	plus.get_popup().id_pressed.emit(OnUseFlow.ADD.find("Condition"))
	_check(not got.is_empty() and got[-1][0].on_fail.conditions == ["prone"], "+ condition goes into the failure (%s)" % [got])
	await process_frame
	flow.setup(potion.effects, potion)
	lines = flow.find_children("Line", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check(lines == ["You or a creature · touch", "2d4 + 2", "regains that many HP"], "potion nodes (%s)" % [lines])
	var roll := flow.find_children("Node_roll_*", "", true, false)[0] as Node
	(roll.find_child("Card", true, false) as Button).pressed.emit()
	var edit := roll.find_child("Form", true, false).find_children("*", "LineEdit", true, false)[0] as LineEdit
	edit.text = "4d4+4"
	edit.text_changed.emit("4d4+4")
	_check(got[-1][0].heal == "4d4+4" and (roll.find_child("Line", true, false) as Label).text == "4d4 + 4", "a form edits the effect and the line follows")
	(flow.find_child("AddStep", true, false) as MenuButton).get_popup().id_pressed.emit(OnUseFlow.STEP_PRESETS.keys().find("Check"))
	_check(got[-1].size() == 2 and got[-1][1].roll == "check", "+ Add a step")
	await process_frame
	var x := flow.find_children("Node_roll_*", "", true, false)[0].find_child("Remove", true, false) as Button
	x.pressed.emit()
	_check(got[-1].size() == 1 and got[-1][0].roll == "check", "× removes the step")
	await process_frame
	flow.setup(rope.effects, rope)
	lines = flow.find_children("Line", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check(lines == ["STR (Athletics) check · DC 15 · you roll", "you climb up", "1d6 bludgeoning", "Prone"], "check nodes (%s)" % [lines])

	print("ON USE: %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: " + what)
