class_name HudActions
extends RefCounted
## What a spell or item quick button posts in the chat (TASK-48, Nico 2026-11-01: "for now
## just post it into the chat"). Nothing is spent yet: the usage engine (does it need a slot,
## is one free, spend it, apply effects) comes later (TASK-49). The host builds this from the
## spell / item entry and rolls what it finds: a spell attack, its first dice (damage or
## healing), the save DC.

## Spellcasting ability per class (5e).
const CASTING := {"bard": "cha", "cleric": "wis", "druid": "wis", "paladin": "cha", "ranger": "wis",
	"sorcerer": "cha", "warlock": "cha", "wizard": "int", "artificer": "int", "monk": "wis"}

static var _dice_re: RegEx


## The sheet's spellcasting ability: its own `spellcasting_ability`, else its first casting
## class's, else the best of int / wis / cha.
static func casting_ability(sheet: Dictionary) -> String:
	var own := str(sheet.get("spellcasting_ability", "")).to_lower().left(3)
	if own in HudWidgets.ABILITIES:
		return own
	for c: Variant in sheet.get("classes", []):
		if c is Dictionary:
			var cls := str(c.get("class", "")).get_file().to_lower()
			for name: String in CASTING:
				if cls == name or cls.begins_with(name + "-"):
					return str(CASTING[name])
	var best := "int"
	for ab: String in ["wis", "cha"]:
		if Dice.modifier(sheet, ab) > Dice.modifier(sheet, best):
			best = ab
	return best


static func spell_attack(sheet: Dictionary) -> int:
	if sheet.has("spell_attack"):
		return int(sheet.spell_attack)
	return int(sheet.get("proficiency_bonus", 2)) + Dice.modifier(sheet, casting_ability(sheet))


static func save_dc(sheet: Dictionary) -> int:
	if sheet.has("spell_save_dc"):
		return int(sheet.spell_save_dc)
	return 8 + spell_attack(sheet)


## The first dice formula in a text ("... takes 2d6 + 3 fire damage" -> "2d6+3"), "" if none.
static func first_dice(text: String) -> String:
	if _dice_re == null:
		_dice_re = RegEx.create_from_string("\\b(\\d*d\\d+(?:\\s*[+-]\\s*\\d+(?!\\s*d))?)")
	var m := _dice_re.search(text)
	return m.get_string(1).replace(" ", "") if m != null else ""


## Casting `spell` (its entry; empty if unknown): {"text": ..., "asked": [{label, formula}]}.
static func spell(sheet: Dictionary, spell: Dictionary, ref: String) -> Dictionary:
	var name := str(spell.get("name", HudWidgets._name_of(ref)))
	var level := int(spell.get("level", 0))
	var bits := PackedStringArray(["cantrip" if level == 0 else "level %d" % level])
	if str(spell.get("casting_time", "")) != "":
		bits.append(str(spell.casting_time))
	if float(spell.get("range_m", 0)) > 0:
		bits.append("%s m" % HudWidgets._num(spell.range_m))
	if bool(spell.get("concentration", false)):
		bits.append("concentration")
	var desc := str(spell.get("description", "")).get_slice("**At Higher Levels", 0)
	var lower := desc.to_lower()
	var text := "casts %s (%s)" % [name, " · ".join(bits)]
	var asked := []
	if "spell attack" in lower:
		asked.append({"label": "%s to hit" % name, "formula": Dice.d20(spell_attack(sheet))})
	for ab: String in ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]:
		if (ab + " saving throw") in lower:
			text += " · DC %d %s save" % [save_dc(sheet), ab.left(3).to_upper()]
			break
	var dice := first_dice(desc)
	if dice != "" and Dice.is_formula(dice):
		var what := "healing" if "regain" in lower else "damage" if "damage" in lower else ""
		asked.append({"label": ("%s %s" % [name, what]).strip_edges(), "formula": dice})
	return {"text": text, "asked": asked}


## Using `item` (its entry): {"text": ..., "asked": [...]}; its first dice are rolled.
static func item(sheet: Dictionary, item: Dictionary, ref: String) -> Dictionary:
	var name := str(item.get("name", HudWidgets._name_of(ref)))
	var held := 0
	for it: Variant in sheet.get("inventory", []):
		if it is Dictionary and str(it.get("item", "")) == ref:
			held = int(it.get("qty", 1))
	var text := "uses %s" % name + (" (%d left)" % held if held > 1 else "")
	var asked := []
	var desc := str(item.get("description", ""))
	var dice := first_dice(desc)
	if dice != "" and Dice.is_formula(dice):
		var lower := desc.to_lower()
		var what := "healing" if "regain" in lower else "damage" if "damage" in lower else ""
		asked.append({"label": ("%s %s" % [name, what]).strip_edges(), "formula": dice})
	return {"text": text, "asked": asked}
