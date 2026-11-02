class_name Rules
extends RefCounted
## The rules (TASK-53, rules-automation.md 5.1 and 5.4): derived stats computed from a sheet
## (its classes, stats, proficiencies, items and active effects) with the built-in data of the
## dragoon-core package (assets/rules/dragoon-core). Stored fields are overrides: they win,
## and `derived()` marks them. The sheet, the HUD, the dice and the table use this, so every
## place shows the same numbers.
## World settings (`settings`): {"edition": "2014" / "2024", "house_rules": {"crit": ...}};
## missing keys take the defaults (our worlds: crits = maximum dice + a normal roll).

const CORE_DIR := "res://assets/rules/dragoon-core"
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const DEFAULT_SETTINGS := {"edition": "2014", "house_rules": {"crit": "max_plus_roll", "flanking": "off", "levelling": "xp", "crowded_squares": "all"},
	"automation": {}}
## How much the table does by itself, per category (TASK-60): "off" (by hand), "assist" (posted
## for the DM to apply) or "auto" (applied at once; undo corrects it). Defaults: Nico's
## decision 1, Auto; movement only ever warns; reaction hints off.
const AUTOMATION_LEVELS := {"off": "Off", "assist": "Assist", "auto": "Auto"}
const AUTOMATION := {
	"damage": {"label": "Damage", "default": "auto", "tip": "Hits and failed saves take the damage off the target's hit points"},
	"healing": {"label": "Healing", "default": "auto", "tip": "Healing spells and potions add hit points"},
	"conditions": {"label": "Conditions", "default": "auto", "tip": "Spells and features put their conditions on the target"},
	"durations": {"label": "Durations", "default": "auto", "tip": "Effects and conditions end when their time runs out"},
	"resources": {"label": "Resources and slots", "default": "auto", "tip": "Casting spends the slot, features their uses; rests give them back"},
	"concentration": {"label": "Concentration", "default": "auto", "tip": "Damage asks for the Constitution save; a new spell ends the old one"},
	"death_saves": {"label": "Death saves", "default": "auto", "tip": "0 HP: unconscious, death saves on the turn, damage counts as failures"},
	"movement": {"label": "Movement warnings", "default": "assist", "tip": "Warns when a token moves farther than its speed (never blocks)"},
	"reactions": {"label": "Reaction hints", "default": "off", "tip": "Points out opportunity attacks and reactions like Shield"},
	"ammunition": {"label": "Ammunition", "default": "off", "tip": "A shot with a bow or crossbow uses one arrow or bolt from the inventory"},
}

static var _core := {}
static var _conditions := {}  ## id -> condition


# --- The data ------------------------------------------------------------------------------

## core.json (tables, weapons, armor, house rule options).
static func core() -> Dictionary:
	if _core.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CORE_DIR.path_join("core.json")))
		_core = data if data is Dictionary else {}
	return _core


## The conditions by id (the 15 of the rules, exhaustion, and the markers concentrating,
## dying, dead).
static func conditions() -> Dictionary:
	if _conditions.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CORE_DIR.path_join("conditions.json")))
		if data is Array:
			for c: Variant in data:
				if c is Dictionary:
					_conditions[str(c.id)] = c
	return _conditions


## A condition for an edition: {id, name, abbr, color, text, flags} ({} if unknown).
## `level`: exhaustion's level (its flags follow it).
static func condition(id: String, edition := "2014", level := 1) -> Dictionary:
	var c: Dictionary = conditions().get(id.to_lower(), {})
	if c.is_empty():
		return {}
	var eds: Dictionary = c.get("editions", {})
	var ed: Dictionary = eds.get(edition, eds.get("2014", {}))
	var out := {"id": c.id, "name": c.name, "abbr": c.get("abbr", str(c.name).left(3)), "color": c.get("color", "#666666"),
		"text": ed.get("text", ""), "flags": ed.get("flags", []), "marker": bool(c.get("marker", false))}
	if ed.has("by_level"):
		out.flags = (ed.by_level as Dictionary).get(str(clampi(level, 1, 6)), [])
	return out


## World settings with the defaults filled in.
static func settings_of(world_settings: Variant) -> Dictionary:
	var out := DEFAULT_SETTINGS.duplicate(true)
	if world_settings is Dictionary:
		for k: String in world_settings:
			if out.get(k) is Dictionary and world_settings[k] is Dictionary:
				(out[k] as Dictionary).merge(world_settings[k], true)
			else:
				out[k] = world_settings[k]
	return out


## The automation level ("off" / "assist" / "auto") of a category in the world's settings.
static func automation(settings: Dictionary, category: String) -> String:
	var auto: Dictionary = settings.get("automation", {}) if settings.get("automation") is Dictionary else {}
	var v := str(auto.get(category, ""))
	if v in AUTOMATION_LEVELS:
		return v
	return str((AUTOMATION.get(category, {}) as Dictionary).get("default", "auto"))


## The edition an entry plays by: its own (the source book), else the world's (decision 5).
static func edition_of(entry: Dictionary, settings := {}) -> String:
	var own := str(entry.get("edition", ""))
	return own if own in ["2014", "2024"] else str(settings_of(settings).edition)


# --- Levels and proficiency -----------------------------------------------------------------

## Character level: the sum of `classes[].level` (TASK-51: levels live only there).
static func level(s: Dictionary) -> int:
	var n := 0
	for c: Variant in s.get("classes", []):
		if c is Dictionary:
			n += int(c.get("level", 0))
	return n


## The level in one class ("wizard" or "classes/wizard"), 0 if none.
static func class_level(s: Dictionary, cls: String) -> int:
	for c: Variant in s.get("classes", []):
		if c is Dictionary and _class_id(str(c.get("class", ""))) == _class_id(cls):
			return int(c.get("level", 0))
	return 0


static func _class_id(cls: String) -> String:
	var id := cls.get_file().to_lower()
	for base: String in core().get("hit_dice", {}):  # "wizard-2024" is a wizard too
		if id == base or id.begins_with(base + "-"):
			return base
	return id


## Proficiency bonus: the sheet's own (override), else by level (characters) or CR.
static func proficiency(s: Dictionary) -> int:
	if s.get("proficiency_bonus") != null:
		return int(s.proficiency_bonus)
	var lvl := level(s)
	if lvl > 0:
		return int((core().proficiency_by_level as Array)[clampi(lvl, 1, 20) - 1])
	if s.has("cr"):
		var cr := _cr(s.cr)
		var out := 2
		for row: Array in core().proficiency_by_cr:
			if cr >= float(row[0]):
				out = int(row[1])
		return out
	return 2


static func _cr(v: Variant) -> float:
	var t := str(v)
	if "/" in t:
		return float(t.get_slice("/", 0)) / maxf(float(t.get_slice("/", 1)), 1.0)
	return float(v)


# --- Abilities, saves, skills ----------------------------------------------------------------

static func score(s: Dictionary, ability: String) -> int:
	var stats: Variant = s.get("stats", {})
	return int((stats as Dictionary).get(ability, 10)) if stats is Dictionary else 10


static func mod(s: Dictionary, ability: String) -> int:
	return floori((score(s, ability) - 10) / 2.0)


## A list or dictionary field "has" a key (saves {dex: 5} or ["dex"]).
static func _has(s: Dictionary, key: String, name: String) -> bool:
	var v: Variant = s.get(key)
	return (v is Dictionary and (v as Dictionary).has(name)) or (v is Array and name in v)


## A stored number in a dictionary field (the override), else null.
static func _stored(s: Dictionary, key: String, name: String) -> Variant:
	var v: Variant = s.get(key)
	if v is Dictionary and (v as Dictionary).get(name) != null:
		return int(v[name])
	return null


## A saving throw's bonus: the stored number, else modifier (+ proficiency if proficient:
## listed in `saves` without a number, or the class's saving throws).
static func save(s: Dictionary, ability: String) -> int:
	var stored: Variant = _stored(s, "saves", ability)
	if stored != null:
		return int(stored)
	var b := mod(s, ability)
	if _has(s, "saves", ability) or ability in _list(s, "save_proficiencies"):
		b += proficiency(s)
	return b + _bonus_effects(s, "save")


## A skill's bonus: stored number, else modifier + proficiency (expertise: twice, Jack of All
## Trades: half, rounded down, for the ones without proficiency).
static func skill(s: Dictionary, name: String) -> int:
	var key := name.to_lower().replace(" ", "_")
	var stored: Variant = _stored(s, "skills", key)
	if stored != null:
		return int(stored)
	var ability := str(Dice.SKILLS.get(key, "dex"))
	var b := mod(s, ability)
	var prof := proficiency(s)
	if key in _list(s, "expertise"):
		b += prof * 2
	elif _has(s, "skills", key) or key in _list(s, "prof_skills").map(func(v: Variant) -> String: return str(v).to_lower().replace(" ", "_")):
		b += prof
	elif bool(s.get("jack_of_all_trades", false)):
		b += floori(prof / 2.0)
	return b + _bonus_effects(s, "check")


## An ability check (no skill): modifier (+ half proficiency with Jack of All Trades).
static func check(s: Dictionary, ability: String) -> int:
	var b := mod(s, ability)
	if bool(s.get("jack_of_all_trades", false)):
		b += floori(proficiency(s) / 2.0)
	return b + _bonus_effects(s, "check")


## Passive score (10 + the skill); a stored passive_<skill> wins.
static func passive(s: Dictionary, name := "perception") -> int:
	var key := "passive_" + name
	if s.get(key) != null:
		return int(s[key])
	return 10 + skill(s, name)


static func initiative(s: Dictionary) -> int:
	if s.get("initiative") is int or s.get("initiative") is float:
		return int(s.initiative)
	return mod(s, "dex") + int(s.get("initiative_bonus", 0)) + (floori(proficiency(s) / 2.0) if bool(s.get("jack_of_all_trades", false)) else 0)


## Armor class: the stored `ac` (override), else from equipped armor and shield in the
## inventory (core armor table by item id), else 10 + Dex; + active AC effects.
static func ac(s: Dictionary) -> int:
	if s.get("ac") != null:
		return int(s.ac) + _bonus_effects(s, "ac")
	return armor_ac(s) + _bonus_effects(s, "ac")


## AC from what is equipped (no stored value): armor base + Dex (capped), + shield, + magic
## bonuses (+1 armor, a Ring of Protection; an item needing attunement only when attuned,
## TASK-70); no armor: Unarmored Defense (Barbarian + CON, Monk + WIS without a shield).
static func armor_ac(s: Dictionary) -> int:
	var dex := mod(s, "dex")
	var base := 10 + dex
	var shield := 0
	var extra := 0
	var armored := false
	for g: Dictionary in equipped_gear(s):
		var a: Dictionary = g.get("armor", {})
		var bonus := int(g.get("ac_bonus", 0)) if active_magic(g) else 0
		if a.is_empty():
			extra += bonus
		elif str(a.get("category", "")) == "shield":
			shield = maxi(shield, int(a.get("ac_bonus", 2)) + bonus)
		else:
			var cap := int(a.get("dex_max", 99))
			var worn := int(a.get("ac", 10)) + (0 if cap == 0 else mini(dex, cap)) + bonus  # heavy armor: no DEX, not even a minus
			base = worn if not armored else maxi(base, worn)
			armored = true
	if not armored:
		var unarmored := 0
		for c: Variant in s.get("classes", []):
			if c is Dictionary:
				match _class_id(str(c.get("class", ""))):
					"barbarian":
						unarmored = maxi(unarmored, mod(s, "con"))
					"monk":
						if shield == 0:
							unarmored = maxi(unarmored, mod(s, "wis"))
		base += unarmored
	return base + shield + extra


# --- Levelling (TASK-71) ---------------------------------------------------------------------

## XP a character level needs (1: 0, 2: 300 ...).
static func xp_for_level(lvl: int) -> int:
	var t: Array = core().get("xp_by_level", [])
	return int(t[clampi(lvl, 1, t.size()) - 1]) if not t.is_empty() else 0


## The character level that much XP reaches.
static func level_for_xp(xp: int) -> int:
	var t: Array = core().get("xp_by_level", [])
	var n := 1
	for i in t.size():
		if xp >= int(t[i]):
			n = i + 1
	return n


## A creature's XP by its CR (0.5, "1/2", 3 ...); its own `xp` wins.
static func xp_of(creature: Dictionary) -> int:
	if creature.get("xp") is int or creature.get("xp") is float:
		return int(creature.xp)
	var cr: Variant = creature.get("cr", creature.get("challenge", null))
	if cr == null:
		return 0
	var f := 0.0
	var t := str(cr).strip_edges()
	if "/" in t:
		f = float(t.get_slice("/", 0)) / maxf(float(t.get_slice("/", 1)), 1.0)
	else:
		f = float(t)
	var key := str(int(f)) if is_equal_approx(f, floorf(f)) else str(snappedf(f, 0.001))
	return int((core().get("xp_by_cr", {}) as Dictionary).get(key, 0))


## How hard a fight is (TASK-72): `party` character levels, `foes` their XP each.
## 2014: the XP times the count multiplier (fewer than 3 characters: one step up, 6 or more:
## one down) against the party's easy / medium / hard / deadly thresholds. 2024: the plain XP
## against the low / moderate / high budget. {rating, xp, adjusted, thresholds: {name: xp}}.
static func encounter_difficulty(party: Array, foes: Array, edition := "2014") -> Dictionary:
	var xp := 0
	for x: Variant in foes:
		xp += int(x)
	var out := {"xp": xp, "adjusted": xp, "rating": "none", "thresholds": {}}
	if party.is_empty() or foes.is_empty():
		return out
	var names: Array = ["low", "moderate", "high"] if edition == "2024" else ["easy", "medium", "hard", "deadly"]
	var table: Array = core().get("encounter_budget_2024" if edition == "2024" else "encounter_thresholds", [])
	var sums := []
	sums.resize(names.size())
	sums.fill(0)
	for lvl: Variant in party:
		var row: Array = table[clampi(int(lvl), 1, table.size()) - 1] if not table.is_empty() else []
		for i in mini(row.size(), names.size()):
			sums[i] = int(sums[i]) + int(row[i])
	var adjusted := float(xp)
	if edition != "2024":
		var steps: Array = core().get("encounter_multipliers", [[1, 1]])
		var at := 0
		for i in steps.size():
			if foes.size() >= int(steps[i][0]):
				at = i
		if party.size() < 3:
			at = mini(at + 1, steps.size() - 1)
		elif party.size() >= 6:
			at = maxi(at - 1, 0)
		adjusted = xp * float(steps[at][1])
		if party.size() < 3 and at == steps.size() - 1 and foes.size() >= int(steps[at][0]):
			adjusted = xp * 5.0  # one step beyond the table's last
	out.adjusted = int(adjusted)
	var rating := "trivial" if edition != "2024" else "below low"
	for i in names.size():
		out.thresholds[names[i]] = int(sums[i])
		if adjusted >= int(sums[i]):
			rating = names[i]
	out.rating = rating
	return out


## The highest CR a druid's Wild Shape takes (TASK-74): level 2 1/4, 4 1/2, 8 1; Circle of
## the Moon: 1 from level 2, then level / 3 from 6. 0: no Wild Shape.
static func wild_shape_cr(s: Dictionary) -> float:
	var lvl := class_level(s, "druid")
	if lvl < 2:
		return 0.0
	var moon := false
	for c: Variant in s.get("classes", []):
		if c is Dictionary and _class_id(str(c.get("class", ""))) == "druid" and "moon" in str(c.get("subclass", "")).to_lower():
			moon = true
	if moon:
		return maxf(1.0, floorf(lvl / 3.0)) if lvl >= 6 else 1.0
	return 1.0 if lvl >= 8 else (0.5 if lvl >= 4 else 0.25)


## A CR as written: 0.25 -> "1/4", 2.0 -> "2".
static func cr_text(cr: float) -> String:
	for pair: Array in [[0.125, "1/8"], [0.25, "1/4"], [0.5, "1/2"]]:
		if is_equal_approx(cr, float(pair[0])):
			return str(pair[1])
	return str(int(cr)) if is_equal_approx(cr, roundf(cr)) else str(cr)


## A creature's CR as a number ("1/4" -> 0.25).
static func cr_of(creature: Dictionary) -> float:
	var t := str(creature.get("cr", creature.get("challenge", "0"))).strip_edges()
	if "/" in t:
		return float(t.get_slice("/", 0)) / maxf(float(t.get_slice("/", 1)), 1.0)
	return float(t)


## A sheet in a beast's shape (TASK-74). Wild Shape: the beast's STR, DEX, CON, AC, speed,
## senses, size, defences and actions; the character keeps INT, WIS, CHA, its proficiencies
## and features. Polymorph: all of the beast's statistics, no features or spells of its own.
static func form_sheet(own: Dictionary, beast: Dictionary, kind: String) -> Dictionary:
	var out := own.duplicate(true)
	var bs: Dictionary = beast.get("stats", {}) if beast.get("stats") is Dictionary else {}
	var stats: Dictionary = (own.get("stats", {}) as Dictionary).duplicate() if own.get("stats") is Dictionary else {}
	for ab: String in (ABILITIES if kind == "polymorph" else ["str", "dex", "con"]):
		if bs.has(ab):
			stats[ab] = bs[ab]
	out["stats"] = stats
	for k: String in ["ac", "speed", "size", "senses", "resistances", "immunities", "vulnerabilities", "condition_immunities"]:
		if beast.has(k):
			out[k] = beast[k]
	for k: String in ["traits", "actions", "bonus_actions", "reactions"]:
		out[k] = beast.get(k, []) if beast.get(k) is Array else []
	if kind == "polymorph":
		for k: String in ["features", "spells", "skills", "saves"]:
			out[k] = beast.get(k, [] if k in ["features", "spells"] else {})
		out["_no_class_features"] = true
	return out


## Whose squares cost double to move through (TASK-79): "all" (5e: another creature's space
## is difficult terrain), "hostile" (only the other side's) or "off".
static func crowded_squares(settings: Dictionary) -> String:
	return str((settings_of(settings).house_rules as Dictionary).get("crowded_squares", "all"))


## "xp" or "milestone" (the world's house rule).
static func levelling(settings: Dictionary) -> String:
	return str((settings_of(settings).house_rules as Dictionary).get("levelling", "xp"))


static func hit_die(cls: String) -> int:
	return int((core().get("hit_dice", {}) as Dictionary).get(_class_id(cls), 8))


## HP for a new level: the average (half the die + 1) or a roll, + CON; at least 1.
static func hp_gain(sides: int, con_mod: int, rolled := 0) -> int:
	return maxi(1, (rolled if rolled > 0 else sides / 2 + 1) + con_mod)


## The class level its subclass is chosen at (2024: always 3).
static func subclass_level(cls: String, edition := "2014") -> int:
	if edition == "2024":
		return 3
	var t: Dictionary = core().get("subclass_levels", {})
	return int(t.get(_class_id(cls), t.get("default", 3)))


static func asi_levels(cls: String) -> Array:
	var t: Dictionary = core().get("asi_levels", {})
	return t.get(_class_id(cls), t.get("default", [4, 8, 12, 16, 19]))


## What levelling up in `cls` brings (TASK-71): {class, from, to, total, hit_die, con,
## hp_average, slots_before, slots_after, asi, subclass (to choose now), caster, after (the
## sheet with the new level, for the features)}. A class it doesn't have yet: multiclassing.
static func level_up_plan(s: Dictionary, cls: String, edition := "2014") -> Dictionary:
	var ref := cls if "/" in cls else "classes/" + cls
	var now := class_level(s, ref)
	var after := s.duplicate(true)
	var classes: Array = after.get("classes", []) if after.get("classes") is Array else []
	var found := false
	var has_sub := false
	for c: Variant in classes:
		if c is Dictionary and _class_id(str(c.get("class", ""))) == _class_id(ref):
			c["level"] = now + 1
			found = true
			has_sub = str(c.get("subclass", "")) != ""
	if not found:
		classes.append({"class": ref, "level": 1})
	after["classes"] = classes
	var to := now + 1
	var casters: Dictionary = core().get("casters", {})
	var caster := false
	for kind: String in casters:
		if _class_id(ref) in (casters[kind] as Array):
			caster = true
	var sides := hit_die(ref)
	return {"class": ref, "from": now, "to": to, "total": level(s) + 1, "hit_die": sides, "con": mod(s, "con"),
		"hp_average": hp_gain(sides, mod(s, "con")), "slots_before": slots(s), "slots_after": slots(after),
		"asi": asi_levels(ref).any(func(l: Variant) -> bool: return int(l) == to), "subclass": to >= subclass_level(ref, edition) and not has_sub, "caster": caster, "after": after}


# --- Gear (TASK-70) ----------------------------------------------------------------------------

## The inventory as [{item, qty, equipped, attuned}]: the file's list [{item, qty, equipped}] or
## Replay's {item: qty}, with the item.flagged events (`item_flags`) on top.
static func gear(s: Dictionary) -> Array:
	var flags: Dictionary = s.get("item_flags", {}) if s.get("item_flags") is Dictionary else {}
	var out := []
	var inv: Variant = s.get("inventory", [])
	if inv is Array:
		for it: Variant in inv:
			if it is Dictionary:
				out.append({"item": str(it.get("item", "")), "qty": int(it.get("qty", 1)), "equipped": bool(it.get("equipped", false)), "attuned": bool(it.get("attuned", false))})
			elif str(it) != "":
				out.append({"item": str(it), "qty": 1, "equipped": false, "attuned": false})
	elif inv is Dictionary:
		for item: Variant in inv:
			out.append({"item": str(item), "qty": int(inv[item]), "equipped": false, "attuned": false})
	for g: Dictionary in out:
		var f: Variant = flags.get(g.item)
		if f is Dictionary:
			for k: String in ["equipped", "attuned"]:
				if (f as Dictionary).has(k):
					g[k] = bool(f[k])
	return out


## What an item is at the table: {name, weapon (core row), armor (core row), bonus (+N to hit and
## damage), ac_bonus, attunement (needs it), ammunition}. From the item entry's own fields
## (weapon, armor, bonus, ac_bonus, attunement), its name and type ("+1 Longsword", "Weapon,
## Katana"), its text ("functions as a light hammer", "+1 bonus to attack and damage rolls",
## "requires attunement") and the dragoon-core weapon and armor tables.
static func item_info(item_ref: String, entry: Dictionary) -> Dictionary:
	var name := str(entry.get("name", item_ref.get_file().replace("-", " ").capitalize()))
	var text := str(entry.get("description", entry.get("text", ""))).to_lower()
	var kind := "%s %s" % [name, str(entry.get("type", ""))]
	var w := weapon(item_ref)
	var a := armor(item_ref)
	if w.is_empty() and a.is_empty():
		var m := RegEx.create_from_string("functions as an? ([a-z' -]+?)(?: with|,|\\.| that| and)").search(text)
		w = _table_row("weapons", m.get_string(1) if m != null else kind)
		if w.is_empty():
			w = _table_row("weapons", kind)
		if w.is_empty():
			a = _table_row("armor", kind)
	if entry.get("weapon") is Dictionary:
		w = w.duplicate()
		w.merge(entry.weapon, true)
	if entry.get("armor") is Dictionary:
		a = a.duplicate()
		a.merge(entry.armor, true)
	var info := {"name": name, "weapon": w, "armor": a, "bonus": 0, "ac_bonus": 0,
		"attunement": bool(entry.get("attunement", "requires attunement" in text)),
		"ammunition": "ammunition" in kind.to_lower() or RegEx.create_from_string("(?i)\\b(arrows?|bolts?|bullets?|needles?)\\b").search(name) != null}
	var plus := RegEx.create_from_string("\\+(\\d)").search(name)
	var hit := RegEx.create_from_string("\\+(\\d) bonus to attack and damage rolls").search(text)
	if entry.has("bonus"):
		info.bonus = int(entry.bonus)
	elif hit != null:
		info.bonus = int(hit.get_string(1))
	elif plus != null and not w.is_empty():
		info.bonus = int(plus.get_string(1))
	var acm := RegEx.create_from_string("\\+(\\d) bonus to (?:your )?(?:ac|armor class)").search(text)
	if entry.has("ac_bonus"):
		info.ac_bonus = int(entry.ac_bonus)
	elif acm != null:
		info.ac_bonus = int(acm.get_string(1))
	elif plus != null and not a.is_empty():
		info.ac_bonus = int(plus.get_string(1))
	return info


## The longest core weapon/armor name in `text` ("['Weapon', 'GreatAxe']" -> Greataxe).
static func _table_row(table: String, text: String) -> Dictionary:
	var hay := _squash(text)
	var best := {}
	for r: Dictionary in core().get(table, []):
		var n := _squash(str(r.name)).trim_suffix("armor")
		if n.length() >= 3 and n in hay and n.length() > _squash(str(best.get("name", ""))).length():
			best = r
	return best


static func _squash(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## An item's magic counts: it needs no attunement, or it is attuned.
static func active_magic(g: Dictionary) -> bool:
	return not bool(g.get("attunement", false)) or bool(g.get("attuned", false))


## The equipped gear with its item info (the host's `_gear`, else the core tables only).
static func equipped_gear(s: Dictionary) -> Array:
	var list: Array = s._gear if s.get("_gear") is Array else gear(s).map(func(g: Dictionary) -> Dictionary:
		var out := g.duplicate()
		out.merge(item_info(str(g.item), {}), false)
		return out)
	return list.filter(func(g: Dictionary) -> bool: return bool(g.get("equipped", false)))


## How many items are attuned, and the most allowed (3).
static func attunement(s: Dictionary) -> Dictionary:
	var list: Array = s._gear if s.get("_gear") is Array else gear(s)
	return {"count": list.filter(func(g: Dictionary) -> bool: return bool(g.get("attuned", false))).size(), "max": int(core().get("attunement_max", 3))}


## Proficient with a core weapon row: the sheet's proficiencies and its classes' (`_weapon_profs`)
## name its category ("Martial Weapons") or the weapon; with nothing known it counts as yes.
static func weapon_proficient(s: Dictionary, w: Dictionary) -> bool:
	var profs := []
	for key: String in ["proficiencies", "_weapon_profs"]:
		if s.get(key) is Array:
			profs.append_array(s[key])
	if profs.is_empty():
		return true
	var cat := "%s weapon" % str(w.get("category", "")).to_lower()
	var name := str(w.get("name", "")).to_lower()
	for p: Variant in profs:
		var t := str(p).to_lower()
		if cat in t or (name != "" and name in t):
			return true
	return false


## The equipped weapons as attack features (TASK-70): {name, attack: {to_hit, damage, kind,
## range, ammunition}, item, mastery, weapon: true}; a versatile one also two-handed (without
## a shield). To hit: STR (ranged DEX, finesse the better) + proficiency + magic bonus.
static func weapon_attacks(s: Dictionary) -> Array:
	var out := []
	var gear_on := equipped_gear(s)
	var shield := gear_on.any(func(g: Dictionary) -> bool: return str((g.get("armor", {}) as Dictionary).get("category", "")) == "shield")
	for g: Dictionary in gear_on:
		var w: Dictionary = g.get("weapon", {})
		if w.is_empty() or str(w.get("damage", "")) == "":
			continue
		var props: Array = w.get("properties", [])
		var ranged := bool(w.get("ranged", false)) or "ammunition" in props or (w.get("range") is Array and not "thrown" in props)
		var ab := "dex" if ranged else "str"
		if "finesse" in props and mod(s, "dex") > mod(s, "str"):
			ab = "dex"
		var magic := int(g.get("bonus", 0)) if active_magic(g) else 0
		var prof := proficiency(s) if weapon_proficient(s, w) else 0
		var rng: Variant = w.get("range")
		var range_text := "%s/%s m" % [MovePlans._num(float(rng[0])), MovePlans._num(float(rng[1]))] if rng is Array and (rng as Array).size() == 2 else ("3 m" if "reach" in props else "1.5 m")
		var attack := {"to_hit": mod(s, ab) + prof + magic, "kind": "Ranged Weapon Attack" if ranged else "Melee Weapon Attack",
			"damage": [{"dice": _plus(str(w.damage), mod(s, ab) + magic), "type": str(w.get("type", ""))}], "range": range_text,
			"ammunition": "ammunition" in props, "item": str(g.item), "proficient": prof > 0}
		var name := str(g.get("name", w.get("name", "Weapon")))
		out.append({"name": name, "attack": attack, "item": str(g.item), "mastery": str(w.get("mastery", "")), "weapon": true})
		if "versatile" in props and str(w.get("versatile", "")) != "" and not shield:
			var two := attack.duplicate(true)
			two.damage[0].dice = _plus(str(w.versatile), mod(s, ab) + magic)
			out.append({"name": "%s (two-handed)" % name, "attack": two, "item": str(g.item), "mastery": str(w.get("mastery", "")), "weapon": true})
	return out


static func _plus(dice: String, n: int) -> String:
	return dice if n == 0 else "%s%+d" % [dice, n]


## A core armor entry by item ref or id ("items/chain-mail"), {} if none.
static func armor(item: String) -> Dictionary:
	var id := item.get_file().to_lower()
	for a: Dictionary in core().get("armor", []):
		if str(a.id) == id:
			return a
	return {}


## A core weapon by item ref or id, {} if none.
static func weapon(item: String) -> Dictionary:
	var id := item.get_file().to_lower()
	for w: Dictionary in core().get("weapons", []):
		if str(w.id) == id:
			return w
	return {}


# --- Spellcasting -------------------------------------------------------------------------

static func casting_ability(s: Dictionary) -> String:
	var own := str(s.get("spellcasting_ability", s.get("spellcast_ability", ""))).to_lower().left(3)
	if own in ABILITIES:
		return own
	var table: Dictionary = core().get("casting_ability", {})
	for c: Variant in s.get("classes", []):
		if c is Dictionary:
			var id := _class_id(str(c.get("class", "")))
			if table.has(id):
				return str(table[id])
	var best := "int"
	for ab: String in ["wis", "cha"]:
		if mod(s, ab) > mod(s, best):
			best = ab
	return best


static func spell_attack(s: Dictionary) -> int:
	if s.get("spell_attack") != null:
		return int(s.spell_attack)
	return proficiency(s) + mod(s, casting_ability(s))


static func spell_dc(s: Dictionary) -> int:
	if s.get("spell_save_dc") != null:
		return int(s.spell_save_dc)
	return 8 + proficiency(s) + mod(s, casting_ability(s))


## Spell slots per level (level 1 first): the sheet's own `spell_slots` (override), else from
## the classes (full / half casters, warlock pact slots at their level).
static func slots(s: Dictionary) -> Array:
	if s.get("spell_slots") is Array and not (s.spell_slots as Array).is_empty():
		return (s.spell_slots as Array).map(func(n: Variant) -> int: return int(n))
	var casters: Dictionary = core().get("casters", {})
	var caster := 0.0
	var pact_level := 0
	for c: Variant in s.get("classes", []):
		if not c is Dictionary:
			continue
		var cls := _class_id(str(c.get("class", "")))
		var lvl := int(c.get("level", 0))
		if cls in casters.get("full", []):
			caster += lvl
		elif cls in casters.get("half", []):
			caster += floorf(lvl / 2.0)
		elif cls in casters.get("half_up", []):
			caster += ceilf(lvl / 2.0)
		elif cls in casters.get("pact", []):
			pact_level = lvl
	var out: Array = []
	var n := clampi(int(caster), 0, 20)
	if n > 0:
		out = (core().full_caster_slots[n - 1] as Array).map(func(v: Variant) -> int: return int(v))
	if pact_level > 0:
		var count := 1 if pact_level == 1 else (2 if pact_level < 11 else (3 if pact_level < 17 else 4))
		var at := mini((pact_level + 1) / 2, 5)
		while out.size() < at:
			out.append(0)
		out[at - 1] = int(out[at - 1]) + count
	return out


## How many dice a cantrip rolls at this character level (1 / 2 / 3 / 4).
static func cantrip_dice(s: Dictionary) -> int:
	var lvl := level(s) if level(s) > 0 else int(s.get("caster_level", 1))
	var n := 1
	for at: Variant in core().get("cantrip_scaling", [5, 11, 17]):
		if lvl >= int(at):
			n += 1
	return n


# --- Resources (class tables; features come with TASK-64 / TASK-69) --------------------------

## Class resources of the sheet: [{id, name, max, reset}] from the core class tables (a stored
## `resources` {id: max} wins).
static func resources(s: Dictionary) -> Array:
	var out := []
	var own: Dictionary = s.get("resources", {}) if s.get("resources") is Dictionary else {}
	var tables: Dictionary = core().get("class_resources", {})
	for c: Variant in s.get("classes", []):
		if not c is Dictionary:
			continue
		var lvl := int(c.get("level", 0))
		for r: Dictionary in tables.get(_class_id(str(c.get("class", ""))), []):
			var n := 0
			if r.has("by_level"):
				n = int((r.by_level as Array)[clampi(lvl, 1, 20) - 1])
			elif str(r.get("max", "")) == "cha_mod_min1":
				n = maxi(1, mod(s, "cha"))
			elif r.has("per_level"):
				n = lvl * int(r.per_level) if lvl >= int(r.get("from", 1)) else 0
			if own.has(r.id):
				n = int(own[r.id])
			if n > 0:
				var reset := str(r.get("reset", "long"))
				if r.has("short_from") and lvl >= int(r.short_from):
					reset = "short"
				out.append({"id": str(r.id), "name": str(r.name), "max": n, "reset": reset})
	for id: String in own:
		if not out.any(func(r: Dictionary) -> bool: return r.id == id):
			out.append({"id": id, "name": id.replace("_", " ").capitalize(), "max": int(own[id]), "reset": "long"})
	return out


## A feature's uses (TASK-64): {max, reset: "long" | "short"} from "3/Day", "1/Day each",
## "Recharges after a Short or Long Rest"; {} for none (and for Recharge 5-6, a turn roll).
static func feature_uses(feature: Dictionary) -> Dictionary:
	var src := ("%s %s" % [str(feature.get("uses", "")), str(feature.get("name", ""))]).to_lower()
	var m := RegEx.create_from_string("(\\d+)\\s*/\\s*day").search(src)
	if m != null:
		return {"max": int(m.get_string(1)), "reset": "long"}
	if "short or long rest" in src:
		return {"max": 1, "reset": "short"}
	if "after a long rest" in src:
		return {"max": 1, "reset": "long"}
	return {}


## An item's charges: {max, regain (a formula or a number), reset: "dawn"} from "has 7 charges
## ... regains 1d6 + 1 expended charges daily at dawn"; {} without.
static func item_charges(item: Dictionary) -> Dictionary:
	if item.get("charges") is int or item.get("charges") is float:
		return {"max": int(item.charges), "regain": str(item.get("regain", item.charges)), "reset": "dawn"}
	var t := str(item.get("description", item.get("text", ""))).to_lower()
	var m := RegEx.create_from_string("has (\\d+) charges").search(t)
	if m == null:
		return {}
	var r := RegEx.create_from_string("regains (\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?|\\d+|all)(?: expended)? charges(?: daily)? at dawn").search(t)
	var regain := m.get_string(1) if r == null or r.get_string(1) == "all" else r.get_string(1).replace(" ", "")
	return {"max": int(m.get_string(1)), "regain": regain, "reset": "dawn" if r != null else "none"}


## Hit dice back on a long rest: 2014 half the total (at least 1), 2024 all of them.
static func hit_dice_back(total: int, edition := "2014") -> int:
	return total if edition == "2024" else maxi(1, total / 2)


## Hit dice of the sheet: {sides: count} (d8 per level of a d8 class ...).
static func hit_dice(s: Dictionary) -> Dictionary:
	var out := {}
	var table: Dictionary = core().get("hit_dice", {})
	for c: Variant in s.get("classes", []):
		if c is Dictionary:
			var sides := int(table.get(_class_id(str(c.get("class", ""))), 8))
			out[sides] = int(out.get(sides, 0)) + int(c.get("level", 0))
	return out


# --- Active effects (TASK-63 fills them; conditions' flags) --------------------------------

## Flat bonuses from active effects on the sheet (`effects` [{modifier: {target, value}}]).
static func _bonus_effects(s: Dictionary, target: String) -> int:
	var n := 0
	for e: Variant in s.get("active_effects", []):
		if e is Dictionary and e.get("modifier") is Dictionary and str(e.modifier.get("target", "")) == target \
				and str(e.modifier.get("op", "add")) == "add" and not str(e.modifier.get("value", "0")).contains("d"):
			n += int(e.modifier.get("value", 0))
	return n


## Dice bonuses from active effects ("+1d4" from Bless on attacks and saves): a formula part.
static func dice_bonus(s: Dictionary, target: String) -> String:
	var out := ""
	for e: Variant in s.get("active_effects", []):
		if e is Dictionary and e.get("modifier") is Dictionary and str(e.modifier.get("target", "")) == target:
			var v := str(e.modifier.get("value", ""))
			if v.contains("d"):
				out += ("+" if not v.begins_with("-") else "") + v
	return out


## Every flag of the sheet's conditions (edition-wise; exhaustion by its level).
static func condition_flags(s: Dictionary, edition := "2014") -> Array:
	var out := []
	for c: Variant in s.get("conditions", []):
		var id := str(c)
		var lvl := int(s.get("exhaustion", 1)) if id == "exhaustion" else 1
		for f: Variant in condition(id, edition, lvl).get("flags", []):
			if f not in out:
				out.append(f)
	return out


## Advantage (+1), disadvantage (-1) or neither (0) the conditions suggest for a roll kind
## ("attack", "check", "save:dex", "attacked"). Shown as a suggestion, never forced.
static func suggested_advantage(s: Dictionary, kind: String, edition := "2014") -> int:
	var flags := condition_flags(s, edition)
	var adv := 0
	var dis := 0
	match kind.get_slice(":", 0):
		"attack":
			adv = int("attack_advantage" in flags)
			dis = int("attack_disadvantage" in flags)
		"check":
			dis = int("check_disadvantage" in flags)
		"save":
			dis = int("save_disadvantage" in flags or (kind == "save:dex" and "dex_save_disadvantage" in flags))
		"attacked":
			adv = int("attacked_advantage" in flags)
			dis = int("attacked_disadvantage" in flags)
	return signi(adv - dis)


## The names of the conditions behind suggested_advantage ("Poisoned", "Prone").
static func advantage_reasons(s: Dictionary, kind: String, edition := "2014") -> PackedStringArray:
	var out := PackedStringArray()
	for c: Variant in s.get("conditions", []):
		if suggested_advantage({"conditions": [c], "exhaustion": s.get("exhaustion", 1)}, kind, edition) != 0:
			out.append(str(condition(str(c), edition).get("name", str(c).capitalize())))
	return out


## True if the creature can't get `condition` (its condition immunities: "poisoned",
## "conditions/poisoned" or "Poisoned").
static func immune_to(s: Dictionary, condition_id: String) -> bool:
	for v: Variant in _list(s, "condition_immunities"):
		var id := str(v).get_file().to_lower().strip_edges()
		if id == condition_id.to_lower():
			return true
	return false


## Damage of `type` on the creature `s` (TASK-54): immunity makes it 0, resistance halves it
## (rounded down), vulnerability doubles it (both: they cancel). {amount, note}.
static func damage_after(s: Dictionary, amount: int, type: String) -> Dictionary:
	var t := type.to_lower().strip_edges()
	if t == "" or amount <= 0:
		return {"amount": maxi(amount, 0), "note": ""}
	if _lists_type(s, "immunities", t):
		return {"amount": 0, "note": "immune"}
	var res := _lists_type(s, "resistances", t)
	var vul := _lists_type(s, "vulnerabilities", t)
	if res and not vul:
		return {"amount": amount / 2, "note": "resistant"}
	if vul and not res:
		return {"amount": amount * 2, "note": "vulnerable"}
	return {"amount": amount, "note": ""}


static func _lists_type(s: Dictionary, key: String, type: String) -> bool:
	for v: Variant in _list(s, key):
		var text := str(v).get_file().to_lower()
		if text == type or RegEx.create_from_string("\\b%s\\b" % type).search(text) != null:
			return true
	return false


const _ABILITY_WORDS := {"strength": "str", "dexterity": "dex", "constitution": "con", "intelligence": "int", "wisdom": "wis", "charisma": "cha"}


## What a save-based feature or spell does (TASK-55): {name, ability, dc, damage: [{dice,
## type}], half, conditions, duration}. The DC: the feature's own (`save.dc`), else the
## caster's spell DC. {} if it has no save.
static func save_effect(entry: Dictionary, caster := {}, use_effects := true) -> Dictionary:
	if use_effects:  # TASK-65: the structured effects win over the text
		var structured := Effects.save_of(entry, caster)
		if not structured.is_empty():
			return structured
	var text := str(entry.get("text", entry.get("description", ""))).get_slice("**At Higher Levels", 0)
	var lower := text.to_lower()
	var save: Dictionary = entry.get("save", {}) if entry.get("save") is Dictionary else {}
	var ability := str(save.get("ability", ""))
	if ability == "":
		for w: String in _ABILITY_WORDS:
			if (w + " saving throw") in lower:
				ability = _ABILITY_WORDS[w]
				break
	if ability == "":
		return {}
	var dc := int(save.get("dc", 0))
	if dc <= 0:
		var m := RegEx.create_from_string("dc (\\d+)").search(lower)
		dc = int(m.get_string(1)) if m != null else spell_dc(caster)  # a spell: the caster's DC
	var damage := []
	if entry.get("damage") is Array:
		for d: Variant in entry.damage:
			if d is Dictionary and Dice.is_formula(str(d.get("dice", ""))):
				damage.append({"dice": str(d.dice).replace(" ", ""), "type": str(d.get("type", ""))})
	if damage.is_empty():
		var re := RegEx.create_from_string("(\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?)\\)?\\s+(\\w+)\\s+damage")
		for m: RegExMatch in re.search_all(lower):
			var t := m.get_string(2)
			damage.append({"dice": m.get_string(1).replace(" ", ""), "type": t if t in _damage_ids() else ""})
	var conds := []
	for id: String in conditions():
		if bool(conditions()[id].get("marker", false)) or id == "exhaustion":
			continue
		if RegEx.create_from_string("\\b%s\\b" % id).search(lower) != null:
			conds.append(id)
	var duration := {}
	var dm := RegEx.create_from_string("for (\\d+) (minute|round|hour)").search(lower)
	if dm != null:
		duration = {"rounds": int(dm.get_string(1)) * (10 if dm.get_string(2) == "minute" else 600 if dm.get_string(2) == "hour" else 1)}
	elif "until the end of its next turn" in lower or "until the end of your next turn" in lower:
		duration = {"rounds": 1, "ends": "turn_end"}
	elif "for the duration" in lower or "until the spell ends" in lower:  # the spell's own duration
		var sd := RegEx.create_from_string("(\\d+) (minute|round|hour)").search(str(entry.get("duration", "")).to_lower())
		if sd != null:
			duration = {"rounds": int(sd.get_string(1)) * (10 if sd.get_string(2) == "minute" else 600 if sd.get_string(2) == "hour" else 1)}
	if "repeat the saving throw at the end of each of its turns" in lower or "repeat the save at the end of each of its turns" in lower 			or RegEx.create_from_string("at the end of each of its turns, the target can make another \\w+ saving throw").search(lower) != null:
		duration["save_ends"] = true  # TASK-63: a save at the end of each of its turns ends it
	return {"name": str(entry.get("name", "")), "ability": ability, "dc": dc, "damage": damage,
		"half": "half as much" in lower or "half damage" in lower, "conditions": conds, "duration": duration}


## A spell with a spell attack (TASK-49): {name, to_hit, damage: [{dice, type}], ranged}; {}
## for none. Damage from the entry's `damage`, else its text ("3d6 fire damage").
static func spell_attack_of(entry: Dictionary, caster: Dictionary) -> Dictionary:
	var structured := Effects.attack_of(entry, caster)  # TASK-65
	if not structured.is_empty():
		return structured
	var text := str(entry.get("description", entry.get("text", ""))).get_slice("**At Higher Levels", 0)
	var lower := text.to_lower()
	if not "spell attack" in lower:
		return {}
	var damage := []
	if entry.get("damage") is Array:
		for d: Variant in entry.damage:
			if d is Dictionary and Dice.is_formula(str(d.get("dice", ""))):
				damage.append({"dice": str(d.dice).replace(" ", ""), "type": str(d.get("type", ""))})
	if damage.is_empty():
		var re := RegEx.create_from_string("(\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?)\\)?\\s+(\\w+)\\s+damage")
		for m: RegExMatch in re.search_all(lower):
			var t := m.get_string(2)
			damage.append({"dice": m.get_string(1).replace(" ", ""), "type": t if t in _damage_ids() else ""})
	return {"name": str(entry.get("name", "")), "to_hit": spell_attack(caster), "damage": damage, "ranged": "ranged spell attack" in lower}


## A range in metres (TASK-67): "1.5 m" (reach) -> {normal 1.5, long 1.5}, "24.4/97.5 m" ->
## {normal 24.4, long 97.5}, a number as it is; {} for none.
static func range_of(v: Variant) -> Dictionary:
	if v is int or v is float:
		return {"normal": float(v), "long": float(v)} if float(v) > 0 else {}
	var m := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)(?:\\s*/\\s*(\\d+(?:\\.\\d+)?))?\\s*m").search(str(v))
	if m == null:
		return {}
	var normal := float(m.get_string(1))
	return {"normal": normal, "long": float(m.get_string(2)) if m.get_string(2) != "" else normal}


## Upcasting and cantrip scaling (TASK-68): `damage` [{dice, type}] of a spell of
## `base_level` cast at `cast_level` by `caster`, with `scaling` ({per_slot, above} | {cantrip}
## | {targets_per_slot}). Returns {damage, note ("+2d6, slot 5", "2d10, level 5"), targets: extra}.
static func scaled(damage: Array, scaling: Dictionary, base_level: int, cast_level: int, caster: Dictionary) -> Dictionary:
	var out := damage.duplicate(true)
	var note := ""
	var targets := 0
	if scaling.has("per_slot") and not out.is_empty():
		var steps := cast_level - maxi(int(scaling.get("above", base_level)), base_level)
		var per := str(scaling.per_slot)
		if steps > 0 and Dice.is_formula(per):
			var m := RegEx.create_from_string("^(\\d+)d(\\d+)$").search(per)
			var first := str(out[0].dice)
			var fm := RegEx.create_from_string("^(\\d+)d(\\d+)(.*)$").search(first)
			if m != null and fm != null and fm.get_string(2) == m.get_string(2):  # same die: more of them
				out[0]["dice"] = "%dd%s%s" % [int(fm.get_string(1)) + steps * int(m.get_string(1)), fm.get_string(2), fm.get_string(3)]
			else:
				out[0]["dice"] = first + "+" + "+".join(PackedStringArray(range(steps).map(func(_i: int) -> String: return per)))
			var added := "%dd%s" % [steps * int(m.get_string(1)), m.get_string(2)] if m != null else "%d× %s" % [steps, per]
			note = "+%s, slot %d" % [added, cast_level]
	elif scaling.has("cantrip") and not out.is_empty():
		var n := cantrip_dice(caster)
		var fm := RegEx.create_from_string("^(\\d+)d(\\d+)(.*)$").search(str(out[0].dice))
		if n > 1 and fm != null:
			out[0]["dice"] = "%dd%s%s" % [int(fm.get_string(1)) * n, fm.get_string(2), fm.get_string(3)]
			note = "%dd%s, level %d" % [int(fm.get_string(1)) * n, fm.get_string(2), level(caster)]
	if scaling.has("targets_per_slot"):
		targets = maxi(0, cast_level - maxi(int(scaling.get("above", base_level)), base_level)) * int(scaling.targets_per_slot)
		if targets > 0:
			note = "+%d target%s, slot %d" % [targets, "" if targets == 1 else "s", cast_level]
	return {"damage": out, "note": note, "targets": targets}


## A spell entry's scaling: its effects', else from its text.
static func scaling_of(entry: Dictionary) -> Dictionary:
	for fx: Variant in entry.get("effects", []):
		if fx is Dictionary and fx.get("scaling") is Dictionary:
			return fx.scaling
	return Effects._scaling(str(entry.get("description", entry.get("text", ""))), int(entry.get("level", -1)))


## How a spell is cast at the table: "attack" (a spell attack: pick targets), "save" (targets
## save), else "other" (rolled into the chat).
static func spell_kind(entry: Dictionary) -> String:
	var lower := str(entry.get("description", entry.get("text", ""))).to_lower()
	if "spell attack" in lower or not Effects.attack_of(entry, {}).is_empty():
		return "attack"
	if not save_effect(entry).is_empty():
		return "save"
	return "other"


## Which action a spell or feature takes by its casting time: "bonus", "reaction" or "action".
static func casting_kind(entry: Dictionary) -> String:
	var t := str(entry.get("casting_time", "")).to_lower()
	return "bonus" if "bonus" in t else "reaction" if "reaction" in t else "action"


static func _damage_ids() -> Array:
	var out := []
	for d: Variant in core().get("damage_types", []):
		out.append(str(d.get("id", d)) if d is Dictionary else str(d))
	return out


## Walking speed in metres (TASK-62): the sheet's ("speed": 9, {"walk": 9} or "9 m"), 0 or
## half by conditions (restrained, grappled, 2014 exhaustion ...).
static func speed(s: Dictionary, edition := "2014") -> float:
	var v: Variant = s.get("speed", 9)
	var m := 9.0
	if v is Dictionary:
		m = float(v.get("walk", 9))
	elif v is float or v is int:
		m = float(v)
	else:
		var digits := RegEx.create_from_string("[\\d.]+").search(str(v))
		m = float(digits.get_string()) if digits != null else 9.0
	var flags := condition_flags(s, edition)
	if "speed_zero" in flags:
		return 0.0
	if "speed_half" in flags:
		m /= 2.0
	if edition == "2024" and "exhaustion" in (s.get("conditions", []) as Array):
		m = maxf(0.0, m - 1.5 * clampi(int(s.get("exhaustion", 1)), 1, 6))  # 2024: 5 ft per level
	return m


## A feature's recharge (TASK-63): "Recharge 5-6" -> 5, "Recharge 6" -> 6, else 0.
static func recharge_of(feature: Dictionary) -> int:
	var src := "%s %s" % [str(feature.get("uses", "")), str(feature.get("name", ""))]
	var m := RegEx.create_from_string("(?i)recharge (\\d)").search(src)
	return int(m.get_string(1)) if m != null else 0


## How many legendary actions a creature takes per round (its intro text, else 3; 0 without any).
static func legendary_count(s: Dictionary) -> int:
	if (s.get("legendary_actions", []) as Array).is_empty():
		return 0
	if s.get("legendary_count") != null and int(s.legendary_count) > 0:
		return int(s.legendary_count)
	var m := RegEx.create_from_string("(?i)take (\\d+) legendary actions").search(str(s.get("legendary_intro", "")))
	return int(m.get_string(1)) if m != null else 3


## A legendary action's cost ("Costs 2 Actions").
static func legendary_cost(feature: Dictionary) -> int:
	var m := RegEx.create_from_string("(?i)costs (\\d) actions").search("%s %s" % [str(feature.get("uses", "")), str(feature.get("name", ""))])
	return int(m.get_string(1)) if m != null else 1


## Legendary Resistance (N/Day): N, else 0.
static func legendary_resistance(features: Array) -> int:
	for f: Variant in features:
		if f is Dictionary and str(f.get("name", "")).to_lower().begins_with("legendary resistance"):
			var m := RegEx.create_from_string("(\\d+)\\s*/\\s*day").search(("%s %s" % [str(f.get("uses", "")), str(f.name)]).to_lower())
			return int(m.get_string(1)) if m != null else 3
	return 0


## Regeneration: {amount, stopped_by: "acid or fire"} from "regains N hit points at the start of its turn".
static func regeneration(features: Array) -> Dictionary:
	for f: Variant in features:
		if not f is Dictionary:
			continue
		var t := str(f.get("text", "")).to_lower()
		var m := RegEx.create_from_string("regains (\\d+) hit points at the start of its turn").search(t)
		if m != null:
			var stop := RegEx.create_from_string("takes ([a-z]+(?: or [a-z]+)?) damage").search(t)
			return {"amount": int(m.get_string(1)), "stopped_by": stop.get_string(1) if stop != null else ""}
	return {}


## The AC bonus of cover (TASK-54): "half" +2, "three_quarters" +5.
static func cover_bonus(cover: String) -> int:
	return 2 if cover == "half" else 5 if cover == "three_quarters" else 0


## Exhaustion's d20 penalty (2024: -2 per level), 0 otherwise.
static func d20_penalty(s: Dictionary, edition := "2014") -> int:
	if edition != "2024" or "exhaustion" not in (s.get("conditions", []) as Array):
		return 0
	return -2 * clampi(int(s.get("exhaustion", 1)), 1, 6)


# --- Crits (house rule) ---------------------------------------------------------------------

## A damage formula on a critical hit: rules as written doubles the dice ("2d6+3" ->
## "4d6+3"); the house rule (decision 4) adds the dice's maximum to a normal roll
## ("2d6+3" -> "12+2d6+3"). Modifiers count once.
static func crit_formula(formula: String, settings := {}) -> String:
	var rule := str((settings_of(settings).house_rules as Dictionary).get("crit", "max_plus_roll"))
	var terms := Dice.parse(formula)
	if terms.is_empty():
		return formula
	var max_dice := 0
	var out := PackedStringArray()
	for t: Dictionary in terms:
		var sign := "-" if int(t.sign) < 0 else "+"
		if t.has("value"):
			out.append(sign + str(t.value))
		else:
			var count := int(t.count)
			if rule == "double":
				count *= 2
			elif int(t.sign) > 0:
				max_dice += int(t.count) * int(t.sides)
			out.append(sign + "%dd%d" % [count, int(t.sides)])
	var text := "".join(out).trim_prefix("+")
	return ("%d+%s" % [max_dice, text]) if max_dice > 0 else text


# --- Everything at once ---------------------------------------------------------------------

## The derived numbers of a sheet: {key: {value, override}} — `override` is true where a
## stored field wins over the computed value (the sheet shows a small marker there).
static func derived(s: Dictionary) -> Dictionary:
	var out := {}
	var plain := s.duplicate()
	for k: String in ["proficiency_bonus", "ac", "spell_attack", "spell_save_dc", "passive_perception", "spell_slots"]:
		plain.erase(k)
	out["proficiency"] = {"value": proficiency(s), "override": s.get("proficiency_bonus") != null and int(s.proficiency_bonus) != proficiency(plain)}
	out["ac"] = {"value": ac(s), "override": s.get("ac") != null and int(s.ac) != armor_ac(plain)}
	out["initiative"] = {"value": initiative(s), "override": s.get("initiative") != null}
	for p: String in ["perception", "insight", "investigation"]:
		out["passive_" + p] = {"value": passive(s, p), "override": s.get("passive_" + p) != null and int(s["passive_" + p]) != 10 + skill(s, p)}
	for ab: String in ABILITIES:
		var computed := mod(s, ab) + (proficiency(s) if _has(s, "saves", ab) or ab in _list(s, "save_proficiencies") else 0)
		out["save_" + ab] = {"value": save(s, ab), "override": _stored(s, "saves", ab) != null and int(_stored(s, "saves", ab)) != computed}
	for sk: String in Dice.SKILLS:
		var no_store := s.duplicate()
		if s.get("skills") is Dictionary:
			var copy: Dictionary = (s.skills as Dictionary).duplicate()
			for k: String in copy:
				copy[k] = null
			no_store["skills"] = copy
		out["skill_" + sk] = {"value": skill(s, sk), "override": _stored(s, "skills", sk) != null and int(_stored(s, "skills", sk)) != skill(no_store, sk)}
	if not slots(plain).is_empty() or s.get("spell_slots") is Array:
		out["spell_attack"] = {"value": spell_attack(s), "override": s.get("spell_attack") != null}
		out["spell_dc"] = {"value": spell_dc(s), "override": s.get("spell_save_dc") != null}
	return out


static func _list(s: Dictionary, key: String) -> Array:
	return s.get(key) if s.get(key) is Array else []
