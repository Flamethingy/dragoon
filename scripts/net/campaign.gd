class_name Campaign
extends RefCounted
## The DM's campaign folder on the host (TASK-7/8): entity files, maps, player characters,
## and the compact, player-safe views of them that are sent to the table. Players only get
## whitelisted fields (never bodies or DM-only keys, see Secrets); images go by hash
## through the AssetCache.

const MAP_FIELDS := ["name"]
## Token fields every player sees; PC owners also get OWNER_FIELDS of their own PC.
const TOKEN_FIELDS := ["name", "size", "type"]
const OWNER_FIELDS := ["hp", "ac", "class"]

var folder := ""
var assets: AssetCache
var _entities := {}  ## id -> {"frontmatter", "body"}


func _init(campaign_folder: String, asset_cache: AssetCache) -> void:
	folder = campaign_folder
	assets = asset_cache


## An entity file ({} if missing). Ids are paths without .md, e.g. "pcs/aria".
func entity(id: String) -> Dictionary:
	if not _entities.has(id):
		var path := folder.path_join(id + ".md")
		if not FileAccess.file_exists(path):
			return {}
		_entities[id] = Frontmatter.load_file(path)
	return _entities[id]


func frontmatter(id: String) -> Dictionary:
	var e := entity(id)
	return e.get("frontmatter", {}) if e.get("frontmatter") is Dictionary else {}


## Entity ids of one type ("map", "pc", ...) found in the campaign's sub folders.
func ids_of_type(type: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(folder):
		for f in DirAccess.get_files_at(folder.path_join(sub)):
			if f.get_extension() == "md":
				var id := sub.path_join(f.get_basename())
				if str(frontmatter(id).get("type", "")) == type:
					out.append(id)
	out.sort()
	return out


func maps() -> PackedStringArray:
	return ids_of_type("map")


func pcs() -> PackedStringArray:
	return ids_of_type("pc")


func name_of(id: String) -> String:
	return str(frontmatter(id).get("name", id.get_file()))


## Hash of an image named in a file (relative to the campaign folder); "" if none.
func image_hash(rel: String) -> String:
	return assets.register(folder.path_join(rel)) if rel != "" else ""


# --- Player views ----------------------------------------------------------------------

## A map for the table: {id, name, image, grid: {size, offset}, party_start, tokens: {id: [x, y]}}.
func map_view(id: String) -> Dictionary:
	var fm := frontmatter(id)
	if fm.is_empty():
		return {}
	var grid: Dictionary = fm.get("grid", {}) if fm.get("grid") is Dictionary else {}
	var off: Variant = grid.get("offset", [0, 0])
	var tokens := {}
	for t: Variant in fm.get("tokens", []):
		if t is Dictionary:
			var at: Variant = t.get("at", [0, 0])
			tokens[str(t.get("entity", ""))] = _cell(at)
	return {"id": id, "name": str(fm.get("name", id)), "image": image_hash(str(fm.get("image", ""))),
		"grid": {"size": float(grid.get("size", 70)), "offset": _vec(off)},
		"party_start": _cell(fm.get("party_start", [1, 1])), "tokens": tokens}


## A token as players see it: {id, image, name, size, type, owner, (own PC: hp, ac, class)}.
func token_view(id: String, owner := "", for_owner := false) -> Dictionary:
	var fm := frontmatter(id)
	if fm.is_empty():
		return {}
	var view := {"id": id, "image": image_hash(str(fm.get("token", ""))), "owner": owner}
	for key in TOKEN_FIELDS + (OWNER_FIELDS if for_owner else []):
		if fm.has(key) and not Secrets.is_secret_key(key):
			view[key] = fm[key]
	return view


## The PCs for the lobby picker: [{id, name, class, image, taken_by}].
func pc_choices(owners: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in pcs():
		var fm := frontmatter(id)
		out.append({"id": id, "name": str(fm.get("name", id)), "class": str(fm.get("class", "")),
			"image": image_hash(str(fm.get("token", ""))), "taken_by": str(owners.get(id, ""))})
	return out


static func _cell(v: Variant) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1])) if v is Array and v.size() == 2 else Vector2i.ZERO


static func _vec(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() == 2 else Vector2.ZERO
