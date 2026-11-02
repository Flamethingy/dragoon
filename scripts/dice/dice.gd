class_name Dice
## Dice for the table (TASK-12): formulas ("2d6+3", "d20", "4d6kh3", "2d20kl1+5") and rolls
## by name from a sheet ("Perception", "Dex save", "attack with Longsword", "initiative",
## "Stealth with advantage"), using the sheet's own bonuses, else ability modifier
## (+ proficiency for saves/skills the sheet lists without a number).

const MAX_DICE := 100
const MAX_SIDES := 1000
const ABILITY_NAMES := {"str": "str", "strength": "str", "dex": "dex", "dexterity": "dex",
	"con": "con", "constitution": "con", "int": "int", "intelligence": "int",
	"wis": "wis", "wisdom": "wis", "cha": "cha", "charisma": "cha"}
const SKILLS := {"acrobatics": "dex", "animal_handling": "wis", "arcana": "int", "athletics": "str",
	"deception": "cha", "history": "int", "insight": "wis", "intimidation": "cha",
	"investigation": "int", "medicine": "wis", "nature": "int", "perception": "wis",
	"performance": "cha", "persuasion": "cha", "religion": "int", "sleight_of_hand": "dex",
	"stealth": "dex", "survival": "wis"}

static var _term := RegEx.create_from_string(r"^(\d*)d(\d+)(?:(kh|kl)(\d+))?$")


## Parses a formula into terms [{sign, count, sides, keep, keep_high}] or [{sign, value}].
## [] if it isn't a valid formula.
static func parse(formula: String) -> Array:
	var f := formula.to_lower().replace(" ", "")
	if f == "" or f.begins_with("+") and f.length() == 1:
		return []
	var terms := []
	var dice := 0
	var i := 0
	var sign := 1
	if f[0] in ["+", "-"]:
		sign = -1 if f[0] == "-" else 1
		i = 1
	var start := i
	while i <= f.length():
		if i == f.length() or f[i] in ["+", "-"]:
			var part := f.substr(start, i - start)
			if part == "":
				return []
			if part.is_valid_int():
				terms.append({"sign": sign, "value": int(part)})
			else:
				var m := _term.search(part)
				if m == null:
					return []
				var count := int(m.get_string(1)) if m.get_string(1) != "" else 1
				var sides := int(m.get_string(2))
				if count < 1 or sides < 1 or sides > MAX_SIDES:
					return []
				dice += count
				var t := {"sign": sign, "count": count, "sides": sides}
				if m.get_string(3) != "":
					t["keep"] = clampi(int(m.get_string(4)), 1, count)
					t["keep_high"] = m.get_string(3) == "kh"
				terms.append(t)
			if i < f.length():
				sign = -1 if f[i] == "-" else 1
			start = i + 1
		i += 1
	return terms if dice <= MAX_DICE else []


static func is_formula(text: String) -> bool:
	return not parse(text).is_empty()


## Rolls a formula: {formula, total, text, dice: [[rolls of each die term]], crit: "20"/"1"/""}.
## `text` shows the dice, e.g. "1d20+5: [14] + 5 = 19". {} if the formula is invalid.
static func roll(formula: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var terms := parse(formula)
	if terms.is_empty():
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var total := 0
	var shown := PackedStringArray()
	var all_dice := []
	var crit := ""
	for t: Dictionary in terms:
		var piece := ""
		var value := 0
		if t.has("value"):
			value = int(t.value)
			piece = str(value)
		else:
			var rolls: Array[int] = []
			for n in int(t.count):
				rolls.append(rng.randi_range(1, int(t.sides)))
			var kept := rolls.duplicate()
			if t.has("keep"):
				kept.sort()
				if t.keep_high:
					kept.reverse()
				kept = kept.slice(0, int(t.keep))
			for r in kept:
				value += r
			all_dice.append(rolls)
			piece = "[%s]" % ", ".join(rolls.map(func(r: int) -> String: return str(r)))
			if t.has("keep"):
				piece += "→%d" % value
			if int(t.sides) == 20 and kept.size() == 1 and int(t.sign) > 0:
				crit = "20" if kept[0] == 20 else "1" if kept[0] == 1 else crit
		total += value * int(t.sign)
		shown.append(("- " if int(t.sign) < 0 else "+ ") + piece)
	var text := " ".join(shown).trim_prefix("+ ")
	return {"formula": formula.replace(" ", ""), "total": total, "dice": all_dice, "crit": crit,
		"text": "%s = %d" % [text, total]}


## A d20 roll with a modifier as a formula: "1d20+5", "2d20kh1-1".
static func d20(modifier: int, advantage := 0) -> String:
	var base := "1d20" if advantage == 0 else "2d20kh1" if advantage > 0 else "2d20kl1"
	return base + ("+%d" % modifier if modifier > 0 else "-%d" % -modifier if modifier < 0 else "")


static func modifier(sheet: Dictionary, ability: String) -> int:
	return Rules.mod(sheet, ability)


## What a name means for this sheet: [{label, formula}] (an attack gives to-hit and damage);
## [] if the name means nothing here. `features` = id -> feature (for attacks).
## Without an explicit "with advantage" / "with disadvantage" / "normal", the creature's
## conditions preselect it (TASK-56: poisoned -> disadvantage); the label says why. 2024
## exhaustion takes 2 per level off d20 tests. `settings` = the world's rules settings.
static func resolve(sheet: Dictionary, query: String, features := {}, settings := {}) -> Array:
	var q := query.to_lower().strip_edges()
	for prefix in ["roll ", "make a ", "make "]:
		q = q.trim_prefix(prefix)
	var advantage := 0
	var explicit := false
	for pair in [[" with advantage", 1], [" with disadvantage", -1], [" advantage", 1], [" disadvantage", -1],
			[" adv", 1], [" dis", -1], [" normal", 0], [" straight", 0]]:
		if q.ends_with(pair[0]):
			advantage = pair[1]
			explicit = true
			q = q.trim_suffix(pair[0]).strip_edges()
			break
	if q == "":
		return []
	var out := _resolve(sheet, q, features, advantage)
	if out.is_empty() or not str(out[0].formula).contains("d20"):
		return out
	var edition := Rules.edition_of(sheet, settings)
	var kind := str(out[0].get("kind", "check"))
	var penalty := Rules.d20_penalty(sheet, edition)
	if not explicit:
		var suggested := Rules.suggested_advantage(sheet, kind, edition)
		if suggested != 0:
			out[0].formula = d20(int(out[0].bonus), suggested)
			out[0].label = "%s (%s: %s)" % [out[0].label, "advantage" if suggested > 0 else "disadvantage",
				", ".join(Rules.advantage_reasons(sheet, kind, edition)).to_lower()]
	if penalty != 0:
		out[0].formula = str(out[0].formula) + "%+d" % penalty
		out[0].label = "%s (exhaustion %d)" % [out[0].label, penalty]
	for r: Dictionary in out:
		r.erase("kind")
		r.erase("bonus")
	return out


static func _resolve(sheet: Dictionary, q: String, features: Dictionary, advantage: int) -> Array:
	var words := q.replace("(", " ").replace(")", " ").replace("_", " ").split(" ", false)

	if q == "initiative" or q == "init":
		return [_d20_roll("Initiative", Rules.initiative(sheet), advantage, "check")]

	var ability := ""
	for w in words:
		if ABILITY_NAMES.has(w):
			ability = ABILITY_NAMES[w]
			break
	if ("save" in words or "saving" in words or "st" in words) and ability != "":
		return [_d20_roll("%s save" % ability.to_upper(), _bonus(sheet, "saves", ability, ability), advantage, "save:" + ability)]

	var skill := " ".join(words).trim_suffix(" check").replace(" ", "_")
	if SKILLS.has(skill):
		return [_d20_roll(skill.replace("_", " ").capitalize(), _bonus(sheet, "skills", skill, SKILLS[skill]), advantage, "check")]
	if ability != "" and words.size() <= 2:
		return [_d20_roll("%s check" % ability.to_upper(), Rules.check(sheet, ability), advantage, "check")]

	var weapon := q
	for prefix in ["attack with ", "attack ", "hit with "]:
		weapon = weapon.trim_prefix(prefix)
	var feature := _attack_feature(sheet, weapon, features)
	if not feature.is_empty():
		var attack: Dictionary = feature.attack
		var out := [_d20_roll("%s to hit" % feature.get("name", weapon), int(attack.get("to_hit", 0)), advantage, "attack")]
		for d: Variant in attack.get("damage", []):
			if d is Dictionary and is_formula(str(d.get("dice", ""))):
				out.append({"label": "%s damage%s" % [feature.get("name", weapon), " (%s)" % d.type if str(d.get("type", "")) != "" else ""],
					"formula": str(d.dice).replace(" ", "")})
		return out
	return []


## An attack of the sheet by name (TASK-54): {name, to_hit, damage: [{dice, type}]}, {} if
## it has none by that name.
static func attack_of(sheet: Dictionary, name: String, features := {}) -> Dictionary:
	var q := name.to_lower().strip_edges()
	for prefix in ["attack with ", "attack ", "hit with "]:
		q = q.trim_prefix(prefix)
	var f := _attack_feature(sheet, q, features)
	if f.is_empty():
		return {}
	var a: Dictionary = f.attack
	var dmg := []
	for d: Variant in a.get("damage", []):
		if d is Dictionary and is_formula(str(d.get("dice", ""))):
			dmg.append({"dice": str(d.dice).replace(" ", ""), "type": str(d.get("type", ""))})
	return {"name": str(f.get("name", name)), "to_hit": int(a.get("to_hit", 0)), "damage": dmg,
		"ranged": "ranged" in str(a.get("kind", "")).to_lower()}


const _COUNTS := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "twice": 2, "thrice": 3}


## The attacks a Multiattack makes ("two attacks: one with its Bite and one with its
## Claws" -> ["Bite", "Claws"]; "makes three Scimitar attacks" -> 3x). [] if none.
static func multiattack(sheet: Dictionary, features := {}) -> Array:
	var text := ""
	var attacks := []
	for key in ["features", "actions", "bonus_actions", "reactions"]:
		for id: Variant in sheet.get(key, []):
			var f: Variant = features.get(str(id), {})
			if not f is Dictionary:
				continue
			if str(f.get("name", "")).to_lower().begins_with("multiattack"):
				text = str(f.get("text", f.get("description", ""))).to_lower()
			elif f.get("attack") is Dictionary:
				attacks.append(str(f.get("name", "")))
	if text == "" or attacks.is_empty():
		return []
	var out := []
	var total_re := RegEx.create_from_string("makes (\\w+) (?:\\w+ )?attacks")
	for a: String in attacks:
		var word := a.to_lower().get_slice(" (", 0)
		var at := text.find(word.trim_suffix("s"))
		if at < 0:
			continue
		var before := text.substr(maxi(0, at - 24), mini(at, 24)).split(" ", false)
		var count := 1
		for w in before:
			if _COUNTS.has(w):
				count = _COUNTS[w]
		for i in count:
			out.append(a)
	if out.size() == 1:  # "makes two attacks with its Scimitar"
		var m := total_re.search(text)
		if m != null and _COUNTS.has(m.get_string(1)):
			for i in int(_COUNTS[m.get_string(1)]) - 1:
				out.append(out[0])
	return out


static func _d20_roll(label: String, bonus: int, advantage: int, kind: String) -> Dictionary:
	return {"label": label, "formula": d20(bonus, advantage), "kind": kind, "bonus": bonus}


## A save's or skill's bonus (TASK-53: the Rules module; a stored number wins).
static func _bonus(sheet: Dictionary, list_key: String, key: String, ability: String) -> int:
	return Rules.save(sheet, key) if list_key == "saves" else Rules.skill(sheet, key) if list_key == "skills" else Rules.mod(sheet, ability)


## The sheet's feature (features / actions / bonus_actions / reactions) with an `attack` whose
## name matches (whole name first, then the start of it).
static func _attack_feature(sheet: Dictionary, name: String, features: Dictionary) -> Dictionary:
	var found := []
	for key in ["features", "actions", "bonus_actions", "reactions"]:
		for id: Variant in sheet.get(key, []):
			var f: Variant = features.get(str(id), {})
			if f is Dictionary and f.get("attack") is Dictionary:
				found.append(f)
	for f: Dictionary in found:
		if str(f.get("name", "")).to_lower() == name:
			return f
	for f: Dictionary in found:
		if str(f.get("name", "")).to_lower().begins_with(name) or name in str(f.get("name", "")).to_lower():
			return f
	return {}
