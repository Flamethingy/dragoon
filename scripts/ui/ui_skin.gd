class_name UISkin
## The cosy paper-and-wine UI from assets/ui_sprites.png: sprite regions, 9-slice
## styleboxes and one shared Theme. Sheet path, regions and colours live only here, so
## the skin can be swapped by editing this file.

const SHEET := "res://assets/ui_sprites.png"

const CREAM := Color8(248, 235, 222)
const PAPER := Color8(236, 214, 195)
const TAN := Color8(217, 189, 170)
const BROWN := Color8(180, 137, 120)
const WINE := Color8(102, 42, 58)
const WINE_LIGHT := Color8(138, 79, 94)
const INK := Color8(74, 34, 46)
const INK_SOFT := Color8(128, 92, 96)
const RED := Color8(190, 62, 59)
const GREEN := Color8(90, 136, 100)
const GOLD := Color8(201, 160, 95)

## name -> Rect2i on the sheet.
const R := {
	# panels (9-slice)
	"panel_lined": Rect2i(0, 67, 64, 59),
	"cover": Rect2i(0, 128, 64, 64),  # wine, tan lines top and bottom
	"page": Rect2i(0, 192, 64, 64),  # cream, ornamented frame
	"header": Rect2i(0, 259, 64, 46),  # cream with a tan top bar and a diamond
	"tile": Rect2i(0, 306, 64, 64),  # tan with a darker edge
	"card": Rect2i(65, 305, 64, 68),  # pink, wine corner frame
	"card_tan": Rect2i(130, 305, 66, 68),  # (has a + in the corner)
	"plate": Rect2i(128, 204, 96, 58),  # wine title plate with cream lines
	# pills (80 x 48 / 40)
	"pill_wine": Rect2i(272, 3, 80, 48),
	"pill_wine_hi": Rect2i(357, 3, 80, 48),
	"pill_paper": Rect2i(272, 53, 80, 48),
	"pill_paper_hi": Rect2i(357, 53, 80, 48),
	"flat_tan": Rect2i(272, 103, 80, 40),
	"flat_cream": Rect2i(357, 103, 80, 40),
	"outline_tan": Rect2i(272, 145, 80, 40),
	"outline_wine": Rect2i(357, 145, 80, 40),
	"bubble": Rect2i(116, 69, 64, 28),
	# hex badges (48 x 29)
	"hex_wine": Rect2i(66, 2, 48, 29),
	"hex_cream": Rect2i(66, 35, 48, 29),
	"hex_tan": Rect2i(66, 68, 48, 29),
	"hex_red": Rect2i(66, 101, 48, 29),
	"hex_green": Rect2i(66, 134, 48, 29),
	# bits
	"ring": Rect2i(116, 1, 64, 64),
	"coin_gold": Rect2i(66, 165, 32, 32),
	"coin_silver": Rect2i(100, 165, 32, 32),
	"gem": Rect2i(134, 160, 42, 42),
	"star": Rect2i(184, 37, 38, 37),
	"dot_cream": Rect2i(66, 204, 24, 24),
	"dot_wine": Rect2i(92, 204, 24, 24),
	"icon_armor": Rect2i(473, 5, 38, 30),
	"icon_sword": Rect2i(476, 44, 32, 32),
	"icon_shield": Rect2i(477, 81, 30, 37),
	"icon_boot": Rect2i(475, 125, 34, 30),
	"icon_helmet": Rect2i(475, 162, 34, 38),
	"icon_potion": Rect2i(131, 102, 14, 19),
	"icon_chest": Rect2i(153, 104, 18, 14),
	"icon_dagger": Rect2i(176, 102, 18, 18),
	"arrow_down": Rect2i(1, 444, 22, 16),
	"arrow_right": Rect2i(31, 438, 16, 22),
}

static var _sheet: Texture2D
static var _atlas := {}
static var _theme: Theme


static func sheet() -> Texture2D:
	if _sheet == null:
		_sheet = load(SHEET)
	return _sheet


## One sprite as an AtlasTexture (cached).
## Drafts (TASK-36): no "Draft" field or tag; the title is italic and the text grey.
const DRAFT_INK := Color8(140, 128, 124)
static var _italic: FontVariation


## A slanted version of the theme font (for draft titles).
static func italic_font() -> FontVariation:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = ThemeDB.fallback_font if theme().default_font == null else theme().default_font
		_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	return _italic


## Marks a label as a draft's title or text: italic (titles) and grey.
static func mark_draft(label: Control, title := true) -> void:
	if title:
		label.add_theme_font_override("font" if label is Label else "normal_font", italic_font())
	label.add_theme_color_override("font_color" if label is Label else "default_color", DRAFT_INK)
	if title:
		label.tooltip_text = "Draft: not in the book or shown to players until it is published"


static func tex(name: String) -> Texture2D:
	if not _atlas.has(name):
		var a := AtlasTexture.new()
		a.atlas = sheet()
		a.region = Rect2(R[name])
		_atlas[name] = a
	return _atlas[name]


## A 9-slice stylebox of a sprite: margin in sheet pixels, pad = content margins (x, y).
## The world's book has its own leather (Nico, 2026-11-01): a forest green cover instead of
## the compendium's wine red.
const FOREST := Color8(46, 92, 70)
static var _covers := {}


## The cover box re-dyed in another colour (hue and saturation of `tint`, the leather's
## light and shade kept). Cached per colour.
static func cover_box(tint: Color) -> StyleBoxTexture:
	var key := tint.to_html()
	if not _covers.has(key):
		var r := Rect2i(R["cover"])
		var img := sheet().get_image().get_region(r)
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a == 0.0:
					continue
				var v := clampf(c.v / WINE.v * tint.v, 0.0, 1.0)
				var sat := minf(c.s / maxf(WINE.s, 0.01) * tint.s, 1.0)
				img.set_pixel(x, y, Color.from_hsv(tint.h, sat, v, c.a))
		var s := box("cover", 8, Vector2(12, 12))
		s.texture = ImageTexture.create_from_image(img)
		s.region_rect = Rect2(Vector2.ZERO, img.get_size())
		_covers[key] = s
	return _covers[key]


static func box(name: String, margin: int, pad := Vector2(10, 6), modulate := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = sheet()
	s.region_rect = Rect2(R[name])
	s.set_texture_margin_all(margin)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.modulate_color = modulate
	return s


static func _flat(color: Color, radius := 4, pad := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


## Type variations for theme_type_variation.
const V_COVER := "BookCover"
const V_PAGE := "BookPage"
const V_CARD := "Card"
const V_CARD_SELECTED := "CardSelected"
const V_PLATE := "TitlePlate"
const V_PLATE_LABEL := "PlateLabel"
const V_CHIP := "Chip"
const V_TAB := "BookmarkTab"
const V_MUTED := "MutedLabel"
const V_HEADING := "HeadingLabel"


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 15

	t.set_color("font_color", "Label", INK)
	t.set_type_variation(V_MUTED, "Label")
	t.set_color("font_color", V_MUTED, INK_SOFT)
	t.set_font_size("font_size", V_MUTED, 13)
	t.set_type_variation(V_HEADING, "Label")
	t.set_font_size("font_size", V_HEADING, 22)
	t.set_type_variation(V_PLATE_LABEL, "Label")
	t.set_color("font_color", V_PLATE_LABEL, CREAM)
	t.set_font_size("font_size", V_PLATE_LABEL, 22)

	t.set_stylebox("panel", "Panel", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	for v in [V_COVER, V_PAGE, V_CARD, V_CARD_SELECTED, V_PLATE, V_CHIP]:
		t.set_type_variation(v, "PanelContainer")
	t.set_stylebox("panel", V_COVER, box("cover", 8, Vector2(12, 12)))
	t.set_stylebox("panel", V_PAGE, box("page", 14, Vector2(18, 16)))
	t.set_stylebox("panel", V_CARD, box("card", 8, Vector2(8, 8)))
	t.set_stylebox("panel", V_CARD_SELECTED, box("card", 8, Vector2(8, 8), Color(1.0, 0.86, 0.8)))
	t.set_stylebox("panel", V_PLATE, box("plate", 10, Vector2(16, 10)))
	t.set_stylebox("panel", V_CHIP, box("flat_cream", 18, Vector2(12, 4)))

	# Buttons: cream pills, tan on hover, wine when pressed / toggled on.
	var normal := box("pill_paper", 22, Vector2(16, 8))
	var hover := box("pill_paper_hi", 22, Vector2(16, 8))
	var pressed := box("pill_wine", 22, Vector2(16, 8))
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal if type == "Button" else box("outline_tan", 18, Vector2(16, 8)))
		t.set_stylebox("hover", type, hover if type == "Button" else box("outline_wine", 18, Vector2(16, 8)))
		t.set_stylebox("pressed", type, pressed if type == "Button" else box("flat_tan", 18, Vector2(16, 8)))
		t.set_stylebox("hover_pressed", type, box("pill_wine_hi", 22, Vector2(16, 8)) if type == "Button" else box("flat_tan", 18, Vector2(16, 8)))
		t.set_stylebox("disabled", type, box("flat_cream", 18, Vector2(16, 8), Color(1, 1, 1, 0.5)))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, INK)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_pressed_color", type, CREAM if type == "Button" else INK)
		t.set_color("font_hover_pressed_color", type, CREAM if type == "Button" else INK)
		t.set_color("font_disabled_color", type, Color(INK, 0.4))
	t.set_color("icon_normal_color", "OptionButton", WINE)
	t.set_constant("arrow_margin", "OptionButton", 12)

	# Bookmark tabs on the cover: tan, cream when hovered, wine pill when open.
	t.set_type_variation(V_TAB, "Button")
	t.set_stylebox("normal", V_TAB, box("flat_tan", 18, Vector2(16, 8)))
	t.set_stylebox("hover", V_TAB, box("flat_cream", 18, Vector2(16, 8)))
	t.set_stylebox("pressed", V_TAB, box("pill_paper_hi", 22, Vector2(16, 8)))
	t.set_stylebox("hover_pressed", V_TAB, box("pill_paper_hi", 22, Vector2(16, 8)))
	t.set_color("font_pressed_color", V_TAB, WINE)
	t.set_color("font_hover_pressed_color", V_TAB, WINE)

	# Document tabs (TabBar): tan, cream on hover, light paper pill when open.
	t.set_stylebox("tab_unselected", "TabBar", box("flat_tan", 18, Vector2(14, 6)))
	t.set_stylebox("tab_hovered", "TabBar", box("flat_cream", 18, Vector2(14, 6)))
	t.set_stylebox("tab_selected", "TabBar", box("pill_paper_hi", 22, Vector2(14, 6)))
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_stylebox("tab_disabled", "TabBar", box("flat_cream", 18, Vector2(14, 6), Color(1, 1, 1, 0.5)))
	t.set_stylebox("button_highlight", "TabBar", _flat(Color(WINE, 0.15), 4))
	t.set_color("font_unselected_color", "TabBar", INK)
	t.set_color("font_hovered_color", "TabBar", INK)
	t.set_color("font_selected_color", "TabBar", WINE)
	t.set_constant("h_separation", "TabBar", 6)

	# Popups (e.g. "Visible for") on paper; check boxes without the pill.
	t.set_stylebox("panel", "PopupPanel", box("page", 14, Vector2(12, 10)))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)

	# Lists (e.g. [[ suggestions): cream paper, tan selection.
	t.set_stylebox("panel", "ItemList", box("flat_cream", 18, Vector2(8, 6)))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _flat(TAN, 6, 2))
	t.set_stylebox("selected_focus", "ItemList", _flat(TAN, 6, 2))
	t.set_stylebox("hovered", "ItemList", _flat(Color(TAN, 0.5), 6, 2))
	for c in ["font_color", "font_selected_color", "font_hovered_color"]:
		t.set_color(c, "ItemList", INK)

	t.set_stylebox("normal", "LineEdit", box("flat_tan", 18, Vector2(18, 8)))
	t.set_stylebox("focus", "LineEdit", box("outline_wine", 18, Vector2(18, 8)))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.5))
	t.set_color("caret_color", "LineEdit", WINE)
	t.set_color("selection_color", "LineEdit", Color(WINE, 0.25))
	t.set_color("clear_button_color", "LineEdit", WINE)
	t.set_stylebox("normal", "TextEdit", box("flat_tan", 18, Vector2(14, 10)))
	t.set_stylebox("focus", "TextEdit", box("outline_wine", 18, Vector2(14, 10)))
	t.set_color("font_color", "TextEdit", INK)
	t.set_color("font_placeholder_color", "TextEdit", Color(INK, 0.5))
	t.set_color("caret_color", "TextEdit", WINE)
	t.set_color("selection_color", "TextEdit", Color(WINE, 0.25))
	t.set_color("background_color", "TextEdit", Color(0, 0, 0, 0))

	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("selection_color", "RichTextLabel", Color(WINE, 0.2))
	t.set_color("table_border", "RichTextLabel", Color(BROWN, 0.6))

	t.set_stylebox("panel", "PopupMenu", box("page", 14, Vector2(10, 10)))
	t.set_stylebox("hover", "PopupMenu", _flat(TAN, 6, 4))
	for c in ["font_color", "font_hover_color", "font_accelerator_color"]:
		t.set_color(c, "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", Color(INK, 0.4))
	t.set_stylebox("panel", "TooltipPanel", box("flat_cream", 18, Vector2(12, 6)))
	t.set_color("font_color", "TooltipLabel", INK)

	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _flat(Color(TAN, 0.6), 4, 3))
		t.set_stylebox("grabber", bar, _flat(BROWN, 4))
		t.set_stylebox("grabber_highlight", bar, _flat(WINE_LIGHT, 4))
		t.set_stylebox("grabber_pressed", bar, _flat(WINE, 4))
	_theme = t
	return t


## A hex badge with text on it (e.g. a CR). `color`: wine, cream, tan, red or green.
static func hex_badge(text: String, color := "tan", font_size := 13) -> Control:
	var hex := TextureRect.new()
	hex.texture = tex("hex_" + color)
	hex.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	hex.custom_minimum_size = Vector2(48, 29)
	var label := Label.new()
	label.text = text
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", CREAM if color in ["wine", "red", "green"] else INK)
	hex.add_child(label)
	return hex


## A small sprite icon, tinted (the sheet's icons are tan).
static func icon(name: String, tint := WINE, height := 22.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var s := Vector2(R[name].size)
	r.custom_minimum_size = Vector2(height * s.x / s.y, height)
	r.modulate = tint
	return r
