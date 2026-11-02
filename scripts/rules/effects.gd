class_name Effects
extends RefCounted
## The structured `effects` of a spell, feature or item (TASK-65, rules-automation.md 5.2):
## what its buttons do. The text stays the source of truth; an entry without effects keeps the
## text fallback (Rules.save_effect / spell_attack_of read the text then).
##
##   {"roll": "attack", "to_hit": "spell" | 5, "range": "melee" | "ranged", "damage": [{dice, type}], "scaling": {...}}
##   {"roll": "save", "ability": "dex", "dc": "spell" | 15, "on_fail": {"damage": [...], "conditions": [...]},
##    "on_success": "half" | "none", "area": {shape, size_m, width_m?}, "duration": {...}, "scaling": {...}}
##   {"apply": "condition", "condition": "frightened", "duration": {"rounds": 10}, "save_ends": {ability, when}, "concentration": true}
##   {"heal": "1d8+mod", "scaling": {"per_slot": "1d8"}}
##   {"modifier": {"target": "ac", "op": "add", "value": 5}, "duration": {...}}
##   {"resource": {"id": "rage", "max": 3, "reset": "long"}}
## scaling: {"per_slot": "1d6", "above": 3} (damage or healing per slot level above), {"cantrip": "1d10"}
## (dice at levels 5, 11, 17), {"targets_per_slot": 1}.

const SHAPES := ["sphere", "cone", "line", "cube", "cylinder", "emanation"]

## Presets for the editor's effects field.
const PRESETS := {
	"Spell attack": {"roll": "attack", "to_hit": "spell", "range": "ranged", "damage": [{"dice": "1d10", "type": "fire"}]},
	"Save for half": {"roll": "save", "ability": "dex", "dc": "spell", "on_fail": {"damage": [{"dice": "8d6", "type": "fire"}]}, "on_success": "half",
		"area": {"shape": "sphere", "size_m": 6}},
	"Save or condition": {"roll": "save", "ability": "wis", "dc": "spell", "on_fail": {"conditions": ["frightened"]}, "on_success": "none",
		"duration": {"rounds": 10, "save_ends": true}},
	"Condition": {"apply": "condition", "condition": "frightened", "duration": {"rounds": 10}, "save_ends": {"ability": "wis", "when": "end_of_turn"}},
	"Heal": {"heal": "1d8+mod", "scaling": {"per_slot": "1d8", "above": 1}},
	"Modifier": {"modifier": {"target": "ac", "op": "add", "value": 2}, "duration": {"rounds": 10}},
	"Resource": {"resource": {"id": "uses", "max": 1, "reset": "long"}},
}


## The effects the text clearly says (the regex parser, TASK-65); [] when it says nothing clear.
static func parse(entry: Dictionary) -> Array:
	var text := str(entry.get("description", entry.get("text", "")))
	var main := text.get_slice("**At Higher Levels", 0)
	var lower := main.to_lower()
	var out := []
	var scaling := _scaling(text, int(entry.get("level", -1)))
	var area := area_of(lower)
	if entry.get("attack") is Dictionary:  # a creature's attack (the importer parsed it)
		var a: Dictionary = entry.attack
		out.append({"roll": "attack", "to_hit": int(a.get("to_hit", 0)), "range": "ranged" if "ranged" in str(a.get("kind", "")).to_lower() else "melee",
			"damage": _dice_list(a.get("damage", []))})
	elif "spell attack" in lower:
		var atk: Dictionary = Rules.spell_attack_of(entry, {})
		var fx := {"roll": "attack", "to_hit": "spell", "range": "ranged" if atk.ranged else "melee", "damage": atk.damage}
		if not scaling.is_empty():
			fx["scaling"] = scaling
		out.append(fx)
	var save: Dictionary = Rules.save_effect(entry, {}, false)
	if not save.is_empty():
		var fx := {"roll": "save", "ability": save.ability, "dc": "spell" if not _has_dc(entry) else int(save.dc),
			"on_fail": {}, "on_success": "half" if bool(save.half) else "none"}
		if not (save.damage as Array).is_empty():
			fx.on_fail["damage"] = save.damage
		if not (save.conditions as Array).is_empty():
			fx.on_fail["conditions"] = save.conditions
		if not (save.duration as Dictionary).is_empty():
			fx["duration"] = save.duration
		if not area.is_empty():
			fx["area"] = area
		if not scaling.is_empty():
			fx["scaling"] = scaling
		out.append(fx)
	var heal := RegEx.create_from_string("regains? (?:a number of )?hit points equal to (\\d+d\\d+)(?: \\+ your spellcasting ability modifier)?").search(lower)
	if heal == null:
		heal = RegEx.create_from_string("regains? (\\d+d\\d+(?:\\s*\\+\\s*\\d+)?) hit points").search(lower)
	if heal != null and out.is_empty():
		var f := heal.get_string(1).replace(" ", "")
		var fx := {"heal": f + ("+mod" if "spellcasting ability modifier" in heal.get_string(0) else "")}
		if not scaling.is_empty():
			fx["scaling"] = scaling
		out.append(fx)
	if bool(entry.get("concentration", false)):
		for fx: Dictionary in out:
			fx["concentration"] = true
	return out


## An area from the text: {shape, size_m, width_m?} ("6.1 m-radius sphere", "18.3 m cone",
## "a line 30.5 m long and 1.5 m wide").
static func area_of(lower: String) -> Dictionary:
	var m := RegEx.create_from_string("(\\d+(?:\\.\\d+)?) ?m-radius (sphere|cylinder|circle)").search(lower)
	if m != null:
		return {"shape": "cylinder" if m.get_string(2) == "cylinder" else "sphere", "size_m": float(m.get_string(1))}
	m = RegEx.create_from_string("line (\\d+(?:\\.\\d+)?) ?m long and (\\d+(?:\\.\\d+)?) ?m wide").search(lower)
	if m != null:
		return {"shape": "line", "size_m": float(m.get_string(1)), "width_m": float(m.get_string(2))}
	m = RegEx.create_from_string("(\\d+(?:\\.\\d+)?) ?m line that is (\\d+(?:\\.\\d+)?) ?m wide").search(lower)
	if m != null:
		return {"shape": "line", "size_m": float(m.get_string(1)), "width_m": float(m.get_string(2))}
	m = RegEx.create_from_string("(\\d+(?:\\.\\d+)?) ?m[- ](cone|cube|sphere|emanation)").search(lower)
	if m != null:
		return {"shape": m.get_string(2), "size_m": float(m.get_string(1))}
	return {}


## "At Higher Levels": dice per slot above the spell's level, a cantrip's dice at 5 / 11 / 17,
## one more target per slot.
static func _scaling(text: String, level: int) -> Dictionary:
	var higher := text.get_slice("**At Higher Levels", 1).to_lower() if "**At Higher Levels" in text else ""
	if higher == "":
		var cantrip := RegEx.create_from_string("(?i)damage increases by (\\d+d\\d+) when you reach 5th level").search(text)
		return {"cantrip": cantrip.get_string(1)} if cantrip != null else {}
	var m := RegEx.create_from_string("increases by (\\d+d\\d+) when you reach 5th level").search(higher)
	if m != null:
		return {"cantrip": m.get_string(1)}
	m = RegEx.create_from_string("increases by (\\d+d\\d+) for each slot level above (\\d)").search(higher)
	if m != null:
		return {"per_slot": m.get_string(1), "above": int(m.get_string(2))}
	m = RegEx.create_from_string("one additional (?:creature|target|humanoid|beast|undead)[a-z ]* for each slot level above (\\d)").search(higher)
	if m != null:
		return {"targets_per_slot": 1, "above": int(m.get_string(1))}
	return {}


static func _has_dc(entry: Dictionary) -> bool:
	return (entry.get("save") is Dictionary and int(entry.save.get("dc", 0)) > 0) or RegEx.create_from_string("(?i)dc \\d+").search(str(entry.get("description", entry.get("text", "")))) != null


static func _dice_list(v: Variant) -> Array:
	var out := []
	if v is Array:
		for d: Variant in v:
			if d is Dictionary and Dice.is_formula(str(d.get("dice", ""))):
				out.append({"dice": str(d.dice).replace(" ", ""), "type": str(d.get("type", ""))})
	return out


## The entry's save effect from its `effects` (Rules.save_effect's shape), {} without one.
static func save_of(entry: Dictionary, caster: Dictionary) -> Dictionary:
	for fx: Variant in entry.get("effects", []):
		if fx is Dictionary and str(fx.get("roll", "")) == "save":
			var fail: Dictionary = fx.get("on_fail", {}) if fx.get("on_fail") is Dictionary else {}
			var dc: Variant = fx.get("dc", "spell")
			return {"name": str(entry.get("name", "")), "ability": str(fx.get("ability", "dex")),
				"dc": Rules.spell_dc(caster) if str(dc) == "spell" else int(dc), "damage": _dice_list(fail.get("damage", [])),
				"half": str(fx.get("on_success", "none")) == "half", "conditions": (fail.get("conditions", []) as Array).duplicate(),
				"duration": (fx.get("duration", {}) as Dictionary).duplicate() if fx.get("duration") is Dictionary else {},
				"area": fx.get("area", {}), "scaling": fx.get("scaling", {})}
	return {}


## The entry's attack from its `effects` (Rules.spell_attack_of's shape), {} without one.
static func attack_of(entry: Dictionary, caster: Dictionary) -> Dictionary:
	for fx: Variant in entry.get("effects", []):
		if fx is Dictionary and str(fx.get("roll", "")) == "attack":
			var hit: Variant = fx.get("to_hit", "spell")
			return {"name": str(entry.get("name", "")), "to_hit": Rules.spell_attack(caster) if str(hit) == "spell" else int(hit),
				"damage": _dice_list(fx.get("damage", [])), "ranged": str(fx.get("range", "ranged")) == "ranged", "scaling": fx.get("scaling", {})}
	return {}


## How many entries got effects: {total, with, by_type: {attack, save, heal}}.
static func coverage(entries: Array) -> Dictionary:
	var out := {"total": entries.size(), "with": 0, "attack": 0, "save": 0, "heal": 0, "area": 0, "scaling": 0}
	for e: Variant in entries:
		var list: Array = (e as Dictionary).get("effects", []) if e is Dictionary else []
		if list.is_empty():
			continue
		out.with += 1
		for fx: Dictionary in list:
			if fx.has("roll"):
				out[str(fx.roll)] = int(out.get(str(fx.roll), 0)) + 1
			if fx.has("heal"):
				out.heal += 1
			if fx.has("area"):
				out.area += 1
			if fx.has("scaling"):
				out.scaling += 1
	return out
