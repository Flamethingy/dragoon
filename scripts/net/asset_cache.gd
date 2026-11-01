class_name AssetCache
extends RefCounted
## Images sent over the table (TASK-7), keyed by the SHA-256 of their bytes.
## Host: `register(path)` gives a file's sha (recomputed only when the file changed) and
## `bytes(sha)` its content. Client: files received are stored in `folder` as
## `<sha>.<ext>`, so a map or token is only sent again when its content changed, also
## across sessions.

const CHUNK := 48 * 1024  ## bytes per RPC message

var folder := "user://cache/assets"

var _by_hash := {}  ## sha -> source path (host)
var _by_path := {}  ## path -> {sha, modified, size}
var _incoming := {}  ## sha -> {parts: Array, got: int, ext}
var _textures := {}  ## sha -> Texture2D


func _init(cache_folder := "") -> void:
	if cache_folder != "":
		folder = cache_folder


# --- Host ----------------------------------------------------------------------------

## The sha of a file ("" if it can't be read).
func register(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("Asset not found: %s" % path)
		return ""
	var modified := FileAccess.get_modified_time(path)
	var known: Dictionary = _by_path.get(path, {})
	if not known.is_empty() and known.modified == modified:
		return known.sha
	var sha := FileAccess.get_sha256(path)
	_by_path[path] = {"sha": sha, "modified": modified}
	_by_hash[sha] = path
	return sha


func source_path(sha: String) -> String:
	return _by_hash.get(sha, "")


func bytes(sha: String) -> PackedByteArray:
	var path := source_path(sha)
	return FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()


## The file split into CHUNK sized parts.
func chunks(sha: String) -> Array[PackedByteArray]:
	var data := bytes(sha)
	var out: Array[PackedByteArray] = []
	var i := 0
	while i < data.size():
		out.append(data.slice(i, i + CHUNK))
		i += CHUNK
	return out


func extension(sha: String) -> String:
	return source_path(sha).get_extension().to_lower()


# --- Client --------------------------------------------------------------------------

func cached_path(sha: String, ext := "png") -> String:
	return folder.path_join("%s.%s" % [sha, ext])


func has(sha: String) -> bool:
	if _textures.has(sha) or source_path(sha) != "":
		return true
	for ext in ["png", "webp", "jpg", "jpeg"]:
		if FileAccess.file_exists(cached_path(sha, ext)):
			return true
	return false


## Collects one part; true when the file is complete, checked and stored.
func receive(sha: String, ext: String, index: int, count: int, part: PackedByteArray) -> bool:
	var entry: Dictionary = _incoming.get(sha, {})
	if entry.is_empty():
		var parts := []
		parts.resize(count)
		entry = {"parts": parts, "got": 0}
		_incoming[sha] = entry
	if index < 0 or index >= entry.parts.size() or entry.parts[index] != null:
		return false
	entry.parts[index] = part
	entry.got += 1
	if entry.got < entry.parts.size():
		return false
	_incoming.erase(sha)
	var data := PackedByteArray()
	for p: PackedByteArray in entry.parts:
		data.append_array(p)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	if ctx.finish().hex_encode() != sha:
		push_error("Asset %s arrived damaged, dropped" % sha)
		return false
	if not ext in ["png", "webp", "jpg", "jpeg"]:
		ext = "png"
	DirAccess.make_dir_recursive_absolute(folder)
	var f := FileAccess.open(cached_path(sha, ext), FileAccess.WRITE)
	if f == null:
		push_error("Can't write the asset cache: %s" % folder)
		return false
	f.store_buffer(data)
	f.close()
	return true


## The image as a texture (host: from its source file, client: from the cache).
func texture(sha: String) -> Texture2D:
	if _textures.has(sha):
		return _textures[sha]
	var path := source_path(sha)
	if path == "":
		for ext in ["png", "webp", "jpg", "jpeg"]:
			if FileAccess.file_exists(cached_path(sha, ext)):
				path = cached_path(sha, ext)
				break
	if path == "":
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	var tex := ImageTexture.create_from_image(image)
	_textures[sha] = tex
	return tex
