class_name Schema
extends RefCounted
## Which fields the entry editor shows for each kind (TASK-21), following data-layout.md and
## package-format.md. A field is {key, type, label, options?}. Types:
## line, markdown, int, float, bool, choice (options), list (string[]), ref, refs (ref[]),
## image, stats (str..cha), speed (walk..climb, metres), bonuses ({name: int}),
## features (feature ids, monsters), cell ([x, y]), json (anything else, edited as JSON).
## Keys an entry has beyond its kind's list are added with a type guessed from the value.

const SIZES := ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const SPEEDS := ["walk", "swim", "fly", "burrow", "climb"]
const HIDDEN := ["id", "origin", "used_by", "counts"]  ## kept, not shown

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
		out.append(f)
		seen[d[0]] = true
	for k: Variant in entry:
		var key := str(k)
		if key.begins_with("_") or seen.has(key) or key in HIDDEN:
			continue
		out.append({"key": key, "type": guess(entry[k], key), "label": key.capitalize()})
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


## The empty value for a field type.
static func empty(type: String) -> Variant:
	match type:
		"int", "float":
			return 0
		"bool":
			return false
		"list", "refs", "features", "cell":
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
