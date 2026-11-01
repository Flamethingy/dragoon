class_name CardArt
extends Control
## The picture on a compendium card: the entry's image (loaded in the background by
## ImageCache), or, without one (or if the file is missing or broken), a coloured plate:
## monsters with their creature type icon (TASK-26, game-icons.net, see CREDITS), everything
## else with a ring and the name's initial.

var color := Color8(102, 42, 58)
var letter := "?"
var icon: Texture2D  ## the creature type icon (monsters without a picture)

const TYPE_ICONS := "res://assets/creature_types/"
const TYPES := ["aberration", "beast", "celestial", "construct", "dragon", "elemental", "fey",
	"fiend", "giant", "humanoid", "monstrosity", "ooze", "plant", "undead"]
static var _icons := {}
var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()

var _path := ""


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows an entry: its image if it has one (async), else the fallback.
func show_entry(e: Dictionary) -> void:
	color = CardData.art_color(e)
	var name := str(e.get("name", "?")).strip_edges()
	letter = name.substr(0, 1).to_upper() if name != "" else "?"
	texture = null
	icon = type_icon(e) if e.get("_kind") == "creatures" else null
	_path = CardData.image_path(e)
	if _path != "":
		ImageCache.request(_path, _on_image.bind(_path))
	queue_redraw()


func _on_image(tex: Texture2D, path: String) -> void:
	if path == _path and is_instance_valid(self):
		texture = tex


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if texture != null:
		draw_rect(r, UISkin.CREAM)
		var ts := texture.get_size()
		var k := minf(size.x / ts.x, size.y / ts.y)
		var s := ts * k
		draw_texture_rect(texture, Rect2((size - s) * 0.5, s), false)
		return
	draw_rect(r, color.lerp(UISkin.PAPER, 0.25))
	if icon != null:  # a monster without a picture: its type's glyph, tinted
		draw_rect(Rect2(0, size.y * 0.78, size.x, size.y * 0.22), Color(color.darkened(0.25), 0.5))
		var side := minf(size.x, size.y) * 0.66
		draw_texture_rect(icon, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), false, color.darkened(0.35))
		return
	# A soft vignette band and the ring with the initial.
	draw_rect(Rect2(0, size.y * 0.78, size.x, size.y * 0.22), Color(color.darkened(0.25), 0.5))
	var ring := UISkin.tex("ring")
	var d := minf(size.x, size.y) * 0.72
	var ring_rect := Rect2((size - Vector2(d, d)) * 0.5, Vector2(d, d))
	draw_texture_rect(ring, ring_rect, false, Color(1, 1, 1, 0.9))
	var font := get_theme_default_font()
	var fs := int(d * 0.42)
	var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2((size.x - w.x) * 0.5, size.y * 0.5 + font.get_ascent(fs) * 0.36)
	draw_string(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color.darkened(0.2))


## The icon for a monster's type ("Monstrosity (Titan)", "swarm of Tiny beasts" ...);
## unknown.svg for types without one.
static func type_icon(e: Dictionary) -> Texture2D:
	var t := str(e.get("type", "")).to_lower()
	var key := "unknown"
	for name: String in TYPES:
		if t.contains(name):
			key = name
			break
	if not _icons.has(key):
		var path := TYPE_ICONS + key + ".svg"
		_icons[key] = load(path) if ResourceLoader.exists(path) else null
	return _icons[key]
