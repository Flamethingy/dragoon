class_name Schema
extends RefCounted
## Which fields the entry editor shows for each kind (TASK-21), following data-layout.md and
## package-format.md. A field is {key, type, label, options?}. Types:
## line, markdown, int, float, bool, choice (options), list (string[]), ref, refs (ref[]),
## image, stats (str..cha), speed (walk..climb, metres), bonuses ({name: int}),
## features (feature ids, monsters), cell ([x, y]), json (anything else, edited as JSON).
## Keys an entry has beyond its kind's list are added with a type guessed from the value.
## Fields whose values repeat become tokens (TASK-29): `token` (one value), `tokens` (a list);
## with `ref_kind` they point at entries of that kind (`ref_store` "ref" = "kind/id",
## "name" = the entry's name, for fields the data keeps as names). `base` values are always offered.

const SIZES := ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const SPEEDS := ["walk", "swim", "fly", "burrow", "climb"]
const HIDDEN := ["id", "origin", "used_by", "counts", "draft", "edited", "source_page", "crop"]  ## kept, not shown
## Fields a finished entry should have filled (the Drafts page hints at empty ones).
const REQUIRED := {"monsters": ["type", "cr", "ac", "hp", "description"], "spells": ["school", "description"],
	"items": ["rarity", "description"], "features": ["text"], "tables": ["dice", "rows"], "notes": ["text"],
	"maps": ["image"]}
const SIZE_TOKENS := ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]
const ABILITY_NAMES := ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]
const DAMAGE_TYPES := ["acid", "bludgeoning", "cold", "fire", "force", "lightning", "necrotic", "piercing",
	"poison", "psychic", "radiant", "slashing", "thunder"]
const CONDITIONS := ["blinded", "charmed", "deafened", "exhaustion", "frightened", "grappled", "incapacitated",
	"invisible", "paralyzed", "petrified", "poisoned", "prone", "restrained", "stunned", "unconscious"]
const SCHOOLS := ["Abjuration", "Conjuration", "Divination", "Enchantment", "Evocation", "Illusion",
	"Necromancy", "Transmutation"]
const RARITIES := ["common", "uncommon", "rare", "very rare", "legendary", "artifact", "varies"]
const ALIGNMENTS := ["lawful good", "neutral good", "chaotic good", "lawful neutral", "neutral",
	"chaotic neutral", "lawful evil", "neutral evil", "chaotic evil", "unaligned", "any alignment"]
const DICE := ["d4", "d6", "d8", "d10", "d12", "d20", "d100"]
## Token fields: "key" or "kind.key" (wins) -> [multi, base list, ref kind, ref store].
const TOKENS := {
	"tags": [true, []],
	"size": [false, SIZE_TOKENS], "type": [false, []], "subtype": [false, []], "group": [false, []],
	"alignment": [false, ALIGNMENTS], "attitude": [false, ["friendly", "neutral", "hostile"]],
	"condition_immunities": [true, CONDITIONS], "immunities": [true, DAMAGE_TYPES],
	"resistances": [true, DAMAGE_TYPES], "vulnerabilities": [true, DAMAGE_TYPES],
	"languages": [true, []], "environments": [true, []],
	"items.rarity": [false, RARITIES], "items.type": [true, []],
	"school": [false, SCHOOLS], "subschool": [false, []], "casting_time": [false, []], "duration": [false, []],
	"spells.classes": [true, []],
	"spellcast_ability": [false, ABILITY_NAMES], "saving_throws": [true, ABILITY_NAMES],
	"prof_armor": [true, []], "prof_weapon": [true, []], "prof_skills": [true, []], "prof_tools": [true, []],
	"features.uses": [false, []], "tables.dice": [false, DICE],
	"subclasses.class": [false, [], "classes", "name"], "subraces.parent": [false, [], "races", "name"],
	"pcs.race": [false, [], "races", "ref"], "npcs.race": [false, [], "races", "name"],
	"factions": [true, [], "factions", "ref"], "location": [false, [], "places", "ref"],
}
## Field types that may become tokens (others, e.g. markdown or json, stay as they are).
const TOKENABLE := ["line", "list", "choice", "ref", "refs"]

const COMMON := [["name", "line"], ["image", "image"], ["tags", "list"], ["description", "markdown"]]
const CREATURE := [["token", "image"], ["size", "choice", SIZES], ["ac", "int", "Armor class"],
	["hp", "int", "Hit points (max)"], ["speed", "speed"], ["stats", "stats", "Ability scores"],
	["saves", "bonuses", "Saving throws"], ["skills", "bonuses"], ["passive_perception", "int"],
	["senses", "list"], ["languages", "list"]]
const KINDS := {
	"monsters": [["type", "line"], ["subtype", "line"], ["alignment", "line"], ["cr", "float", "Challenge rating"],
		["armor", "line", "Armor (text)"], ["vulnerabilities", "list"], ["resistances", "list"],
		["immunities", "list"], ["condition_immunities", "list"], ["environments", "list"], ["spells", "list"],
		["traits", "features"], ["actions", "features"], ["bonus_actions", "features"], ["reactions", "features"],
		["legendary_intro", "markdown", "Legendary actions intro"], ["legendary_actions", "features"]],
	"pcs": [["player", "line", "Player id"], ["race", "ref"], ["classes", "json"], ["background", "line"],
		["alignment", "line"], ["proficiency_bonus", "int"], ["proficiencies", "list"], ["features", "refs"],
		["spells", "refs"], ["inventory", "json"], ["factions", "refs"], ["location", "ref"]],
	"npcs": [["role", "line"], ["race", "line"], ["alignment", "line"], ["attitude", "choice", ["", "friendly", "neutral", "hostile"]],
		["location", "ref"], ["factions", "refs"], ["stat_block", "ref"]],
	"features": [["text", "markdown"], ["uses", "line"], ["cost", "line"], ["attack", "json"], ["save", "json"], ["damage", "json"]],
	"spells": [["level", "int", "Level (0 = cantrip)"], ["school", "line"], ["subschool", "line"], ["casting_time", "line"],
		["range_m", "float", "Range (m, 0 = self/touch)"], ["duration", "line"], ["concentration", "bool"], ["ritual", "bool"],
		["components", "json"], ["classes", "list"]],
	"items": [["rarity", "line"], ["type", "list"], ["gold", "float", "Price (gp)"], ["weight", "float"]],
	"places": [["type", "line"], ["parent", "ref"], ["map", "ref"], ["factions", "refs"], ["population", "int"], ["world_at", "cell"]],
	"factions": [["type", "line"], ["leader", "ref"], ["headquarters", "ref"], ["allies", "refs"], ["enemies", "refs"], ["goals", "markdown"]],
	"lore": [["category", "line"], ["related", "refs"]],
	"maps": [["kind", "choice", ["local", "world"]], ["grid", "json"], ["party_start", "cell"], ["party_token", "image"],
		["place", "ref"], ["tokens", "json"]],
	"notes": [["text", "markdown"], ["session", "int"], ["day", "int"], ["time", "int"], ["by", "line"], ["about", "ref"]],
}
## Creature kinds get CREATURE fields after COMMON.
const CREATURE_KINDS := ["monsters", "pcs", "npcs"]


## The fields to edit for an entry of `kind` (its existing extra keys included).
static func fields(kind: String, entry := {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var defs: Array = COMMON.duplicate()
	if kind == "notes" or kind == "features":
		defs = [["name", "line"]]
	if kind in CREATURE_KINDS:
		defs.append_array(CREATURE)
	defs.append_array(KINDS.get(kind, []))
	for d: Array in defs:
		var f := {"key": d[0], "type": d[1], "label": _label(d)}
		if d[1] == "choice":
			f["options"] = d[2]
		out.append(token_field(kind, f))
		seen[d[0]] = true
	for k: Variant in entry:
		var key := str(k)
		if key.begins_with("_") or seen.has(key) or key in HIDDEN:
			continue
		out.append(token_field(kind, {"key": key, "type": guess(entry[k], key), "label": key.capitalize()}))
	return out


## The field as a token field if its values repeat (TOKENS), else unchanged.
static func token_field(kind: String, f: Dictionary) -> Dictionary:
	var def: Variant = TOKENS.get(kind + "." + str(f.key), TOKENS.get(f.key))
	if def == null or str(f.type) not in TOKENABLE:
		return f
	var out := f.duplicate()
	out["type"] = "tokens" if def[0] else "token"
	out["base"] = def[1]
	if def.size() > 2:
		out["ref_kind"] = def[2]
		out["ref_store"] = def[3]
	return out


static func _label(d: Array) -> String:
	if d.size() > 2 and d[2] is String:
		return d[2]
	return str(d[0]).capitalize()


## A type for a value we have no definition for.
static func guess(v: Variant, key := "") -> String:
	if v is bool:
		return "bool"
	if v is int:
		return "int"
	if v is float:
		return "int" if v == floorf(v) else "float"
	if v is String:
		return "markdown" if "\n" in v or key in ["description", "text"] or v.length() > 80 else "line"
	if v is Array and v.all(func(x: Variant) -> bool: return x is String):
		return "list"
	return "json"


## The labels of required fields (REQUIRED, else description) that are empty in `e`.
static func missing(kind: String, e: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in REQUIRED.get(kind, ["description"]):
		var v: Variant = e.get(key)
		if v == null or (v is String and v.strip_edges() == "") or (v is Array and v.is_empty()) 				or (v is Dictionary and v.is_empty()) or ((v is int or v is float) and v == 0 and key != "cr"):
			out.append(key.replace("_", " "))
	return out


## The empty value for a field type.
static func empty(type: String) -> Variant:
	match type:
		"int", "float":
			return 0
		"bool":
			return false
		"list", "refs", "features", "cell", "tokens":
			return []
		"stats":
			var s := {}
			for a in ABILITIES:
				s[a] = 10
			return s
		"speed", "bonuses", "json":
			return {}
	return ""


## A new entry of `kind` with every field empty (id and name are set by the store).
static func blank(kind: String) -> Dictionary:
	var e := {"id": "", "name": ""}
	for f in fields(kind):
		if not e.has(f.key):
			e[f.key] = empty(f.type)
	if kind == "monsters":
		e["size"] = "Medium"
		e["speed"] = {"walk": 9}
	if kind == "maps":
		e["kind"] = "local"
		e["grid"] = {"size": 70, "offset": [0, 0]}
	if kind == "pcs":
		e["classes"] = []
		e["inventory"] = []
	if kind == "maps":
		e["tokens"] = []
	if kind in ["monsters", "spells", "items", "features"]:
		e["source"] = ""
	return e
