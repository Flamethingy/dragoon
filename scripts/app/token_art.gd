class_name TokenArt
extends RefCounted
## How a token looks (TASK-41, Nico 2026-11-01): a coloured border ring, a background colour
## (for transparent pictures) and the picture framed in the circle, moved and zoomed as set
## in the token editor. The settings live in the entry as `token_style`:
##   {"border": "#rrggbb", "background": "#rrggbb", "offset": [x, y], "zoom": 1.0, "faces": "right"}
## offset: where the picture's centre sits, in token diameters from the middle; zoom 1 = the
## whole picture fits in the circle; faces: which way the picture looks (the map mirrors it
## when the token looks the other way, TASK-42).

const SIZE := 256  ## pixels of a composed token
const RING := 0.07  ## ring width, part of the diameter
const DEFAULT_BORDER := {"creatures": "#8f3b3b", "characters": "#d8b45a"}
const DEFAULT_BACKGROUND := "#efe4d0"

static var _cache := {}  ## key -> ImageTexture
static var _masks := {}  ## "inner" / "ring" -> Image


## The style with every key filled in (defaults by kind).
static func style_of(style: Variant, kind := "") -> Dictionary:
	var s: Dictionary = (style as Dictionary).duplicate() if style is Dictionary else {}
	if not Color.html_is_valid(str(s.get("border", ""))):
		s["border"] = DEFAULT_BORDER.get(kind, "#8f3b3b")
	if not Color.html_is_valid(str(s.get("background", ""))):
		s["background"] = DEFAULT_BACKGROUND
	var o: Variant = s.get("offset")
	s["offset"] = [float(o[0]), float(o[1])] if o is Array and (o as Array).size() == 2 else [0.0, 0.0]
	s["zoom"] = clampf(float(s.get("zoom", 1.0)), 0.2, 6.0)
	s["faces"] = "left" if str(s.get("faces", "right")) == "left" else "right"
	return s


## The round token: ring, background, picture (null picture: just ring and background).
static func compose(picture: Texture2D, style: Variant, kind := "") -> Texture2D:
	var s := style_of(style, kind)
	var key := "%s|%s" % [picture.get_rid().get_id() if picture != null else 0, JSON.stringify(s)]
	if _cache.has(key):
		return _cache[key]
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var full := Rect2i(0, 0, SIZE, SIZE)
	var inner := _mask("inner")
	out.blend_rect_mask(_filled(Color.html(str(s.background))), inner, full, Vector2i.ZERO)
	if picture != null:
		var src := picture.get_image()
		if src != null:
			src = src.duplicate()
			if src.is_compressed():
				src.decompress()
			src.convert(Image.FORMAT_RGBA8)
			var d := SIZE * (1.0 - 2.0 * RING)  # the inner circle's diameter
			var k := d * float(s.zoom) / maxf(src.get_width(), src.get_height())
			var w := maxi(1, roundi(src.get_width() * k))
			var h := maxi(1, roundi(src.get_height() * k))
			src.resize(w, h, Image.INTERPOLATE_BILINEAR)
			var centre := Vector2(SIZE, SIZE) * 0.5 + Vector2(float(s.offset[0]), float(s.offset[1])) * d
			var layer := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
			layer.blit_rect(src, Rect2i(0, 0, w, h), Vector2i(centre - Vector2(w, h) * 0.5))
			out.blend_rect_mask(layer, inner, full, Vector2i.ZERO)
	out.blend_rect_mask(_filled(Color.html(str(s.border))), _mask("ring"), full, Vector2i.ZERO)
	var tex := ImageTexture.create_from_image(out)
	if _cache.size() > 200:
		_cache.clear()
	_cache[key] = tex
	return tex


## The picture of an entry for its token: `token`, else `image` (path in its package).
static func picture_path(e: Dictionary) -> String:
	var rel := str(e.get("token", ""))
	if rel == "":
		rel = str(e.get("image", ""))
	return "" if rel == "" else str(e.get("_dir", "")).path_join(rel)


static func _filled(c: Color) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


static func _mask(which: String) -> Image:
	if not _masks.has(which):
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var r_out := SIZE * 0.5 - 1.0
		var r_in := SIZE * (0.5 - RING)
		for y in SIZE:
			for x in SIZE:
				var dist := Vector2(x + 0.5 - SIZE * 0.5, y + 0.5 - SIZE * 0.5).length()
				var on := dist <= r_in + 0.5 if which == "inner" else dist > r_in - 0.5 and dist <= r_out
				if on:
					img.set_pixel(x, y, Color.WHITE)
		_masks[which] = img
	return _masks[which]
