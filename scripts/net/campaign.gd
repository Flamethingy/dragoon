class_name Campaign
extends RefCounted
## A campaign folder on the DM's host (data-layout.md): campaign.json (name, world, calendar,
## players with their colors, dm), one JSON array per kind (pcs.json, npcs.json,
## monsters.json, maps.json ...), events.jsonl, notes.json and assets/.
## Entries are addressed by ref "<kind>/<id>" (e.g. "pcs/aria"). The table only gets the
## compact player views from here (map_view / token_view): whitelisted fields, never
## descriptions; images go by hash through the AssetCache.

const FORMAT := "dragoon-campaign"
const EXAMPLE := "res://examples/campaigns/red-fang"
## Kinds that can stand on a map.
const CREATURES := ["pcs", "npcs", "monsters"]
## Token fields every player sees; owners also get OWNER_FIELDS of their own PC.
const TOKEN_FIELDS := ["name", "size"]
const OWNER_FIELDS := ["hp", "ac"]

var folder := ""
var assets: AssetCache
var info := {}  ## campaign.json
var _kinds := {}  ## kind -> {id -> entry}


func _init(campaign_folder: String, asset_cache: AssetCache) -> void:
	folder = campaign_folder
	assets = asset_cache
	var file := folder.path_join("campaign.json")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file)) if FileAccess.file_exists(file) else null
	info = data if data is Dictionary else {}


## The folder holding all campaigns: data/campaigns next to data/packages.
static func default_root() -> String:
	return PackageDB.default_root().get_base_dir().path_join("campaigns")


## True if the folder has a readable campaign.json of our format.
static func is_campaign(path: String) -> bool:
	if not FileAccess.file_exists(path.path_join("campaign.json")):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("campaign.json")))
	return data is Dictionary and str(data.get("format", "")) == FORMAT


## Copies the example campaign to `target` (if there is no campaign there yet), so the
## table has something to host on a fresh install. Returns the folder.
static func install_example(target: String) -> String:
	if is_campaign(target):
		return target
	_copy_tree(EXAMPLE, target)
	return target


static func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for d in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(d), to.path_join(d))


func id() -> String:
	return str(info.get("id", folder.get_file()))


func events_path() -> String:
	return folder.path_join("events.jsonl")


# --- Entries -------------------------------------------------------------------------

## All entries of a kind as id -> entry (loaded once).
func entries(kind: String) -> Dictionary:
	if not _kinds.has(kind):
		var by_id := {}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(kind + ".json"))) \
			if FileAccess.file_exists(folder.path_join(kind + ".json")) else []
		if data is Array:
			for e: Variant in data:
				if e is Dictionary and e.has("id"):
					by_id[str(e.id)] = e
		_kinds[kind] = by_id
	return _kinds[kind]


## An entry by ref "<kind>/<id>" ({} if there is none).
func entry(ref: String) -> Dictionary:
	var kind := ref.get_slice("/", 0)
	var id_part := ref.get_slice("/", 1)
	return entries(kind).get(id_part, {}) if "/" in ref else {}


func refs(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id_part: String in entries(kind):
		out.append("%s/%s" % [kind, id_part])
	out.sort()
	return out


func maps() -> PackedStringArray:
	return refs("maps")


func pcs() -> PackedStringArray:
	return refs("pcs")


func name_of(ref: String) -> String:
	return str(entry(ref).get("name", ref.get_file()))


# --- Players -----------------------------------------------------------------------------

## [{id, name, color}] from campaign.json.
func players() -> Array:
	return info.get("players", []) if info.get("players") is Array else []


## The player id for a login name (matches id or name, any case); "" if unknown.
func player_id(login: String) -> String:
	var l := login.strip_edges().to_lower()
	for p: Dictionary in players():
		if str(p.get("id", "")).to_lower() == l or str(p.get("name", "")).to_lower() == l:
			return str(p.id)
	return ""


func player_name(player: String) -> String:
	for p: Dictionary in players():
		if p.get("id") == player:
			return str(p.get("name", player))
	return "DM" if player == "dm" else player


## Every account with its display name and color: players by id, the DM as "dm".
## {id: {name, color: "#rrggbb"}} (TASK-19).
func accounts() -> Dictionary:
	var out := {}
	for p: Dictionary in players():
		out[str(p.get("id", ""))] = {"name": str(p.get("name", p.get("id", ""))), "color": str(p.get("color", ""))}
	var dm: Dictionary = info.get("dm", {}) if info.get("dm") is Dictionary else {}
	out["dm"] = {"name": str(dm.get("name", "DM")), "color": str(dm.get("color", ""))}
	return out


## Sets an account's color ("#rrggbb") and saves campaign.json. False if unknown/invalid.
func set_color(account: String, color: String) -> bool:
	if not Color.html_is_valid(color):
		return false
	var hex := "#" + Color.html(color).to_html(false)
	if account == "dm":
		var dm: Dictionary = info.get("dm", {}) if info.get("dm") is Dictionary else {}
		dm["color"] = hex
		info["dm"] = dm
	else:
		var found := false
		for p: Dictionary in players():
			if str(p.get("id", "")) == account:
				p["color"] = hex
				found = true
		if not found:
			return false
	return EntryStore._write(folder.path_join("campaign.json"), info) == OK


## Who plays which PC, from pcs.json (`player`); PCs without one are left out.
func owners() -> Dictionary:
	var out := {}
	for ref in pcs():
		var player := str(entry(ref).get("player", ""))
		if player != "":
			out[ref] = player
	return out


## Hash of an image path relative to the campaign folder; "" if none.
func image_hash(rel: String) -> String:
	return assets.register(folder.path_join(rel)) if rel != "" else ""


# --- Player views ----------------------------------------------------------------------

## A map for the table: {id, name, image, grid: {size, offset}, kind ("world" or "local"),
## party_token, party_start, tokens: {ref: Vector2i}}.
func map_view(ref: String) -> Dictionary:
	var m := entry(ref)
	if m.is_empty():
		return {}
	var grid: Dictionary = m.get("grid", {}) if m.get("grid") is Dictionary else {}
	var tokens := {}
	for t: Variant in m.get("tokens", []):
		if t is Dictionary:
			tokens[str(t.get("entity", ""))] = _cell(t.get("at", [0, 0]))
	return {"id": ref, "name": str(m.get("name", ref)), "image": image_hash(str(m.get("image", ""))),
		"grid": {"size": float(grid.get("size", 70)), "offset": _vec(grid.get("offset", [0, 0]))},
		"kind": str(m.get("kind", "local")), "party_token": image_hash(str(m.get("party_token", ""))),
		"party_start": _cell(m.get("party_start", [1, 1])), "tokens": tokens}


## A token as players see it: {id, image, name, size, kind, owner, (owner only: hp, ac, class)}.
func token_view(ref: String, owner := "", for_owner := false) -> Dictionary:
	var e := entry(ref)
	if e.is_empty() or ref.get_slice("/", 0) not in CREATURES:
		return {}
	var token := str(e.get("token", ""))
	var view := {"id": ref, "image": image_hash(token if token != "" else str(e.get("image", ""))),
		"kind": ref.get_slice("/", 0), "owner": owner}
	for key: String in TOKEN_FIELDS:
		if e.has(key):
			view[key] = e[key]
	if for_owner:
		for key: String in OWNER_FIELDS:
			if e.has(key):
				view[key] = e[key]
		if e.has("classes"):
			view["class"] = class_text(e)
	return view


## A whole entry as `viewer` (player id or "dm") may see it at a moment: <reveal> passages
## and %% comments they may not see are cut out (Reveal), with the reveal.changed events
## in `events` (e.g. EventLog.effective(ref, day, time)) applied. {} if there is none.
func entry_view(ref: String, viewer: String, events: Array = []) -> Dictionary:
	var e := entry(ref)
	if e.is_empty():
		return {}
	var view := Reveal.filter_entry(e, viewer, Reveal.grants_from(events, ref))
	view["ref"] = ref
	return view


## "Ranger 3" or "Fighter 2 / Wizard 1" from a PC's classes.
func class_text(pc: Dictionary) -> String:
	var parts := PackedStringArray()
	for c: Variant in pc.get("classes", []):
		if c is Dictionary:
			var cls := str(c.get("class", "")).get_file().replace("-", " ").capitalize()
			parts.append("%s %d" % [cls, int(c.get("level", 1))])
	return " / ".join(parts)


## The PCs for the lobby picker: [{id, name, class, image, player, taken_by}].
## `taken_by` is the player's display name ("" = free to pick).
func pc_choices(owner_map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ref in pcs():
		var e := entry(ref)
		var token := str(e.get("token", ""))
		var owner: String = owner_map.get(ref, "")
		out.append({"id": ref, "name": str(e.get("name", ref)), "class": class_text(e),
			"image": image_hash(token if token != "" else str(e.get("image", ""))),
			"player": owner, "taken_by": player_name(owner) if owner != "" else ""})
	return out


static func _cell(v: Variant) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1])) if v is Array and v.size() == 2 else Vector2i.ZERO


static func _vec(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() == 2 else Vector2.ZERO
