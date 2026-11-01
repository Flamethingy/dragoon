class_name ImageCache
## Entry images from the package folders, loaded on worker threads and scaled down
## (MAX_SIDE), cached by path. request() calls back on the main thread.

const MAX_SIDE := 512

static var _done := {}  ## path -> Texture2D (null = failed)
static var _waiting := {}  ## path -> Array[Callable]


static func request(path: String, callback: Callable) -> void:
	if _done.has(path):
		if _done[path] != null:
			callback.call(_done[path])
		return
	if _waiting.has(path):
		_waiting[path].append(callback)
		return
	_waiting[path] = [callback]
	WorkerThreadPool.add_task(_load.bind(path), false, "Load image")


static func _load(path: String) -> void:
	var img := decode(FileAccess.get_file_as_bytes(path)) if FileAccess.file_exists(path) else null
	if img != null and not img.is_empty():
		var side := maxi(img.get_width(), img.get_height())
		if side > MAX_SIDE:
			var k := float(MAX_SIDE) / side
			img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
	else:
		img = null
	_finish.call_deferred(path, img)


## An image by its content, not its file name (the vault has JPEGs named .png); null for
## anything that isn't PNG, JPEG, WebP or BMP, so broken files don't reach the decoders.
static func decode(data: PackedByteArray) -> Image:
	if data.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		err = img.load_png_from_buffer(data)
	elif data[0] == 0xFF and data[1] == 0xD8:
		err = img.load_jpg_from_buffer(data)
	elif data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(data)
	elif data[0] == 0x42 and data[1] == 0x4D:
		err = img.load_bmp_from_buffer(data)
	return img if err == OK and not img.is_empty() else null


static func _finish(path: String, img: Image) -> void:
	var tex: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_done[path] = tex
	var callbacks: Array = _waiting.get(path, [])
	_waiting.erase(path)
	if tex == null:
		return
	for c: Callable in callbacks:
		if c.is_valid():
			c.call(tex)
