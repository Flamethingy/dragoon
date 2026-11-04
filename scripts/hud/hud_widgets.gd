class_name HudWidgets
extends RefCounted
## The pieces a HUD and the sheet pages are put together from (TASK-47, F2). Each is built
## for a size in pixels and arranges its contents to it (skills in 1-4 columns, ...).
## Layouts are lists of {"w": kind, "r": [x, y, w, h]} in grid cells, with "v" a variant
## (portrait as token / picture / small, ...) and "ref" what a quick button is for (TASK-48:
## a spell, an item, a check); they live in the character (`hud`, `sheet_pages`), for
## creatures in their template in the Book.

const HUD_GRID := Vector2i(48, 27)  ## the screen in cells
const PAGE_GRID := Vector2i(16, 10)  ## a sheet page in cells

## kind -> label and default size in cells.
const KINDS := {
	"portrait": {"label": "Portrait", "size": [4, 5]},
	"hp": {"label": "Health", "size": [4, 1]},
	"slots": {"label": "Spell slots", "size": [4, 2]},
	"info": {"label": "Info", "size": [5, 3]},
	"abilities": {"label": "Abilities", "size": [3, 6]},
	"saves": {"label": "Saves", "size": [3, 6]},
	"skills": {"label": "Skills", "size": [7, 9]},
	"description": {"label": "Description", "size": [6, 5]},
	"features": {"label": "Features", "size": [5, 5]},
	"spells": {"label": "Spells", "size": [5, 5]},
	"inventory": {"label": "Inventory", "size": [5, 5]},
	"turn": {"label": "Turn", "size": [5, 1]},  # TASK-62: action economy and movement
	# the app's buttons (Nico, 2026-11-01: "for now" pieces too); only shown to who may use them
	"combat": {"label": "Combat", "size": [3, 1]},
	"rules": {"label": "Rules", "size": [3, 1]},
	"compendium": {"label": "Compendium", "size": [4, 1]},
	"book": {"label": "Book", "size": [3, 1]},
	"leave": {"label": "Leave", "size": [3, 1]},
	# quick buttons (TASK-48): one spell, item or check each ("ref"), square or round
	"spell": {"label": "Spell", "size": [2, 2]},
	"item": {"label": "Item", "size": [2, 2]},
	"check": {"label": "Check", "size": [2, 2]},
}
## How big a piece may be, in pixels (TASK-75): `min` (smaller and its content no longer
## fits), `fit` (its size when added: just its content) and `max` (bigger only adds empty
## space; lists that scroll have none). "kind:variant" overrides the kind. The grid's cells
## differ (the HUD: about 33 px, a sheet page: about 70 px), so the cells follow from these.
const LIMITS := {
	"portrait": {"min": [64, 72], "fit": [132, 170], "max": [420, 520]},
	"portrait:small": {"min": [120, 36], "fit": [200, 50], "max": [420, 100]},
	"hp": {"min": [90, 22], "fit": [132, 33], "max": [520, 64]},
	"slots": {"min": [80, 30], "fit": [132, 66], "max": [420, 260]},
	"info": {"min": [150, 60], "fit": [220, 100], "max": [640, 140]},
	"abilities": {"min": [90, 150], "fit": [100, 200], "max": [320, 330]},
	"saves": {"min": [90, 150], "fit": [100, 200], "max": [320, 330]},
	"skills": {"min": [150, 200], "fit": [230, 300]},
	"description": {"min": [150, 80], "fit": [200, 165]},
	"features": {"min": [150, 80], "fit": [165, 165]},
	"spells": {"min": [150, 80], "fit": [165, 165]},
	"inventory": {"min": [150, 80], "fit": [165, 165]},
	"turn": {"min": [150, 28], "fit": [165, 33], "max": [420, 64]},
	"combat": {"min": [60, 26], "fit": [100, 33], "max": [260, 64]},
	"rules": {"min": [60, 26], "fit": [100, 33], "max": [260, 64]},
	"compendium": {"min": [90, 26], "fit": [132, 33], "max": [300, 64]},
	"book": {"min": [60, 26], "fit": [100, 33], "max": [260, 64]},
	"leave": {"min": [60, 26], "fit": [100, 33], "max": [260, 64]},
	"spell": {"min": [40, 40], "fit": [66, 66], "max": [170, 170]},
	"item": {"min": [40, 40], "fit": [66, 66], "max": [170, 170]},
	"check": {"min": [40, 40], "fit": [66, 66], "max": [170, 170]},
}

## Kinds with variants: the first is the default.
const VARIANTS := {
	"portrait": ["token", "picture", "small"],
	"hp": ["bar", "number"],
	"slots": ["pips", "count"],
	"spell": ["square", "round"],
	"item": ["square", "round"],
	"check": ["square", "round"],
}
const VARIANT_LABELS := {"token": "token", "picture": "full picture", "small": "small", "bar": "bar",
	"number": "number", "pips": "pips", "count": "count", "square": "square", "round": "round"}
## Quick buttons: they need a "ref".
const QUICK := ["spell", "item", "check"]
## The builder's catalog tabs (LayoutEditor).
const TABS := ["Character", "Checks", "Spells", "Items", "App"]
## Pieces that are buttons of the app (CharacterHud.actions).
const APP_BUTTONS := ["combat", "rules", "compendium", "book", "leave"]

## Without a layout of its own (Nico, 2026-11-01): portrait, health and spell slots, lower left.
const DEFAULT_HUD := [
	{"w": "portrait", "r": [0, 19, 4, 5]},
	{"w": "hp", "r": [0, 24, 4, 1]},
	{"w": "slots", "r": [0, 25, 4, 2]},
]
const DEFAULT_PAGES := [
	{"name": "Sheet", "items": [
		{"w": "portrait", "r": [0, 0, 3, 4]}, {"w": "info", "r": [3, 0, 5, 2]}, {"w": "hp", "r": [3, 2, 5, 1]},
		{"w": "slots", "r": [3, 3, 5, 1]}, {"w": "abilities", "r": [0, 4, 3, 5]}, {"w": "saves", "r": [3, 4, 3, 5]},
		{"w": "skills", "r": [8, 0, 8, 10]}]},
	{"name": "Spells & gear", "items": [
		{"w": "spells", "r": [0, 0, 8, 10]}, {"w": "inventory", "r": [8, 0, 8, 5]}, {"w": "features", "r": [8, 5, 8, 5]}]},
]

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]


## A piece's limits in pixels: {min, fit, max (absent: none)}.
static func limits(kind: String, v := "") -> Dictionary:
	return LIMITS.get(kind + ":" + v, LIMITS.get(kind, {"min": [1, 1], "fit": [66, 66]}))


## The smallest size in cells on a grid with cells of `cell` pixels (at least 1 x 1).
static func min_cells(kind: String, v: String, cell: Vector2) -> Vector2i:
	var m: Array = limits(kind, v).min
	return Vector2i(maxi(1, ceili(float(m[0]) / maxf(cell.x, 1.0) - 0.05)), maxi(1, ceili(float(m[1]) / maxf(cell.y, 1.0) - 0.05)))


## The biggest size in cells (the grid if it has no maximum; never below the minimum).
static func max_cells(kind: String, v: String, cell: Vector2, grid: Vector2i) -> Vector2i:
	var l := limits(kind, v)
	var lo := min_cells(kind, v, cell)
	if not l.has("max"):
		return Vector2i(maxi(lo.x, grid.x), maxi(lo.y, grid.y))
	var m: Array = l.max
	return Vector2i(maxi(lo.x, floori(float(m[0]) / maxf(cell.x, 1.0) + 0.05)), maxi(lo.y, floori(float(m[1]) / maxf(cell.y, 1.0) + 0.05)))


## The size a new piece gets: its content's (rounded to cells), inside its limits and the grid.
static func fit_cells(kind: String, v: String, cell: Vector2, grid: Vector2i) -> Vector2i:
	if not _real(cell):  # no real screen yet (headless): the kind's cells on the HUD
		var k: Array = KINDS.get(kind, {"size": [2, 2]}).size
		return Vector2i(clampi(int(k[0]), 1, grid.x), clampi(int(k[1]), 1, grid.y))
	var f: Array = limits(kind, v).fit
	var want := Vector2i(roundi(float(f[0]) / maxf(cell.x, 1.0)), roundi(float(f[1]) / maxf(cell.y, 1.0)))
	return clamp_cells(kind, v, want, cell, grid)


## Cells of a real screen or page (a few pixels: no size known yet, the limits wait).
static func _real(cell: Vector2) -> bool:
	return cell.x >= 12.0 and cell.y >= 12.0


## `size` (cells) kept between the piece's minimum and maximum and inside the grid.
static func clamp_cells(kind: String, v: String, size: Vector2i, cell: Vector2, grid: Vector2i) -> Vector2i:
	if not _real(cell):
		return Vector2i(clampi(size.x, 1, grid.x), clampi(size.y, 1, grid.y))
	var lo := min_cells(kind, v, cell)
	var hi := max_cells(kind, v, cell, grid)
	return Vector2i(clampi(clampi(size.x, lo.x, hi.x), 1, grid.x), clampi(clampi(size.y, lo.y, hi.y), 1, grid.y))


## A layout made clean: known kinds, whole cells inside the grid; with `cell` (pixels of a
## cell) each piece also kept within its size limits (TASK-75: old layouts get clamped).
static func clean(items: Variant, grid: Vector2i, cell := Vector2.ZERO) -> Array:
	var out := []
	if not items is Array:
		return out
	for it: Variant in items:
		if not it is Dictionary or not KINDS.has(str(it.get("w", ""))) or not it.get("r") is Array or (it.r as Array).size() != 4:
			continue
		var kind := str(it.w)
		if kind in QUICK and str(it.get("ref", "")) == "":
			continue
		var r: Array = it.r
		var w := clampi(int(r[2]), 1, grid.x)
		var h := clampi(int(r[3]), 1, grid.y)
		var v := str(it.get("v", "")) if VARIANTS.has(kind) and str(it.get("v", "")) in VARIANTS[kind] else ""
		if _real(cell):
			var sz := clamp_cells(kind, variant({"w": kind, "v": v}), Vector2i(w, h), cell, grid)
			w = sz.x
			h = sz.y
		var item := {"w": kind, "r": [clampi(int(r[0]), 0, grid.x - w), clampi(int(r[1]), 0, grid.y - h), w, h]}
		if v != "":
			item["v"] = v
		if kind in QUICK:
			item["ref"] = str(it.ref)
		for flag: String in ["name", "badge"]:  # the inspector's ticks (TASK-50), kept only when off
			if it.get(flag, true) == false:
				item[flag] = false
		out.append(item)
	return out


## The variant of a layout item (its own, else the kind's first).
static func variant(it: Dictionary) -> String:
	var kind := str(it.get("w", ""))
	if not VARIANTS.has(kind):
		return ""
	var v := str(it.get("v", ""))
	return v if v in VARIANTS[kind] else str(VARIANTS[kind][0])


## What the builder offers for the sheet `s` (TASK-48): [{tab, w, v, ref, label}], every
## variant of a piece side by side, one quick button per spell, item and check.
static func catalog(s: Dictionary, shape := "square") -> Array:
	var out := []
	for kind: String in ["portrait", "hp", "slots", "info", "description", "features", "spells", "inventory"]:
		var label := str(KINDS[kind].label)
		if kind == "spells":
			label = "Spell list"
		elif kind == "inventory":
			label = "Inventory list"
		for v: String in VARIANTS.get(kind, [""]):
			out.append({"tab": "Character", "w": kind, "v": v, "ref": "",
				"label": label + (" · " + str(VARIANT_LABELS[v]) if v != "" else "")})
	for kind: String in ["abilities", "saves", "skills"]:
		out.append({"tab": "Checks", "w": kind, "v": "", "ref": "", "label": str(KINDS[kind].label)})
	var checks := []
	for ab: String in ABILITIES:
		checks.append("%s check" % ab)
	for ab: String in ABILITIES:
		checks.append("%s save" % ab)
	var skills: Array = Dice.SKILLS.keys()
	skills.sort()
	for sk: String in skills:
		checks.append(sk.replace("_", " "))
	for q: String in checks:
		out.append({"tab": "Checks", "w": "check", "v": shape, "ref": q, "label": quick_name("check", q, s)})
	for v: Variant in s.get("spells", []):
		out.append({"tab": "Spells", "w": "spell", "v": shape, "ref": str(v), "label": quick_name("spell", str(v), s)})
	for it: Variant in s.get("inventory", []):
		var r := str(it.get("item", "")) if it is Dictionary else str(it)
		if r != "":
			out.append({"tab": "Items", "w": "item", "v": shape, "ref": r, "label": quick_name("item", r, s)})
	return out  # the app's buttons are in the Esc menu now (Nico, 2026-11-02)


## A quick button's name: the spell's / item's (the sheet's `_refs`), a check's ("DEX save").
static func quick_name(kind: String, ref: String, s: Dictionary) -> String:
	if kind == "check":
		var words := ref.split(" ")
		if words.size() == 2 and words[0] in ABILITIES:
			return "%s %s" % [words[0].to_upper(), words[1]]
		return ref.capitalize()
	var refs: Dictionary = s.get("_refs", {}) if s.get("_refs") is Dictionary else {}
	return str((refs.get(ref, {}) as Dictionary).get("name", _name_of(ref)))


## The widget `kind` for the sheet `s`, `size` pixels big. `hud` rolls, spends slots and
## knows the portrait. Its name is "W_<kind>".
static func build(kind: String, s: Dictionary, hud: CharacterHud, size: Vector2, it := {}) -> Control:
	if kind in APP_BUTTONS:
		return _app_button(kind, hud, size)
	var v := variant({"w": kind, "v": it.get("v", "")})
	if kind in QUICK:
		return _hide_parts(_quick(kind, str(it.get("ref", "")), v, s, hud, size), it)
	var panel := PanelContainer.new()
	panel.name = "W_" + kind
	panel.theme_type_variation = UISkin.V_PAGE
	panel.custom_minimum_size = Vector2.ZERO
	panel.size = size
	panel.clip_contents = true
	var body: Control
	match kind:
		"portrait":
			body = _portrait(s, hud, size, v)
			if v == "picture":
				panel.add_theme_stylebox_override("panel", _frame())
		"hp":
			body = _hp(s, hud, v)
		"slots":
			body = _slots(s, hud, v)
		"info":
			body = _text(_info_bbcode(s))
		"abilities":
			body = _checks(s, hud, "abilities", size)
		"saves":
			body = _checks(s, hud, "saves", size)
		"skills":
			body = _checks(s, hud, "skills", size)
		"description":
			body = _text(Markdown.to_bbcode(str(s.get("description", ""))), "Description")
		"features":
			body = _text(_list_bbcode(s, ["features", "traits", "actions", "bonus_actions", "reactions"]), "Features")
		"spells":
			body = _text(_list_bbcode(s, ["spells"]), "Spells")
		"inventory":
			body = _text(_inventory_bbcode(s), "Inventory")
		"turn":
			body = _turn(hud)
		_:
			body = Label.new()
	var fit := FitBox.new()  # content bigger than the piece shrinks into it instead of growing the frame
	fit.name = "Fit"
	fit.add_child(body)
	panel.add_child(fit)
	if kind == "portrait" and s.get("concentration") is Dictionary:  # TASK-59
		var conc := Label.new()
		conc.name = "Concentration"
		conc.text = "◆ %s" % str(s.concentration.get("name", "concentrating"))
		conc.tooltip_text = "Concentrating on %s" % str(s.concentration.get("name", ""))
		conc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		conc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		conc.add_theme_font_size_override("font_size", 12)
		conc.add_theme_color_override("font_color", UISkin.WINE)
		conc.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_child(conc)
	return _hide_parts(panel, it)


## The active creature's turn (TASK-62): Action, Bonus, Reaction, Object pips (a click marks /
## unmarks one), the metres moved of its speed and Dash. Only in a combat; display only.
static func _turn(hud: CharacterHud) -> Control:
	var row := HBoxContainer.new()
	row.name = "Turn"
	row.add_theme_constant_override("separation", 4)
	var usage := {}
	if hud.table != null:
		for c: Dictionary in hud.table.combat_view().get("order", []):
			if c.get("usage") is Dictionary and (c.entity == hud.active or (c.get("members", []) as Array).any(func(m: Dictionary) -> bool: return m.entity == hud.active)):
				usage = c.usage
	if usage.is_empty():
		var l := Label.new()
		l.text = "No combat"
		l.theme_type_variation = UISkin.V_MUTED
		row.add_child(l)
		return row
	for pair: Array in [["action", "A", "Action"], ["bonus", "B", "Bonus action"], ["reaction", "R", "Reaction"], ["object", "O", "Object interaction"]]:
		var b := Button.new()
		b.name = "Pip_" + str(pair[0])
		b.text = str(pair[1])
		b.toggle_mode = true
		b.button_pressed = bool(usage.get(pair[0], false))
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s%s (a click marks it; nothing is blocked)" % [pair[2], " used" if b.button_pressed else ""]
		b.custom_minimum_size = Vector2(24, 0)
		var kind := str(pair[0])
		b.toggled.connect(func(on: bool) -> void: hud.table.mark_action(hud.active, kind, on))
		row.add_child(b)
	var move := Label.new()
	move.name = "Move"
	move.text = "%s / %s m" % [MovePlans._num(float(usage.moved)), MovePlans._num(float(usage.speed))]
	if float(usage.moved) > float(usage.speed) + 0.01:
		move.add_theme_color_override("font_color", UISkin.RED)
	row.add_child(move)
	var dash := Button.new()
	dash.name = "Dash"
	dash.text = "Dash"
	dash.toggle_mode = true
	dash.button_pressed = bool(usage.get("dash", false))
	dash.focus_mode = Control.FOCUS_NONE
	dash.tooltip_text = "Dash: uses the action, doubles the movement"
	dash.toggled.connect(func(on: bool) -> void: hud.table.mark_action(hud.active, "action", on, "dash"))
	row.add_child(dash)
	return row


## The inspector's ticks (TASK-50): "name": false hides the name (portrait, quick button),
## "badge": false the amount badge.
static func _hide_parts(w: Control, it: Dictionary) -> Control:
	for part: Array in [["name", "Name"], ["name", "Caption"], ["badge", "Badge"]]:
		if it.get(part[0], true) == false:
			var c := w.find_child(str(part[1]), true, false) as Control
			if c != null:
				c.visible = false
				if c.get_parent() is ColorRect:  # the full picture's shade behind the name
					(c.get_parent() as Control).visible = false
	return w


## Compendium / Book / Leave: the app's button (hidden when this user can't use it, e.g. a
## player has no Book; the editor still shows it, dimmed).
static func _app_button(kind: String, hud: CharacterHud, size: Vector2) -> Control:
	var b := Button.new()
	b.name = "W_" + kind
	b.text = str(KINDS[kind].label)
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	var action: Callable = hud.actions.get(kind, Callable())
	if action.is_valid():
		b.pressed.connect(func() -> void: action.call())
	elif hud.editor == null:
		b.visible = false
	else:
		b.modulate.a = 0.5
	return b


## A thin frame around the full picture (no paper behind it).
static func _frame() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UISkin.INK
	sb.border_color = UISkin.TAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb


## The portrait: "token" (the token, the name under it), "picture" (the full art, the name
## over its lower edge) or "small" (a little token, name and class beside it).
static func _portrait(s: Dictionary, hud: CharacterHud, size: Vector2, v := "token") -> Control:
	var full_name := hud.label(hud.active) if s.is_empty() else str(s.get("name", hud.label(hud.active)))
	if v == "picture":
		var box := Control.new()
		box.clip_contents = true
		var art := TextureRect.new()
		art.name = "Picture"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.texture = hud.art(hud.active)
		box.add_child(art)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.5)
		shade.anchor_top = 1.0
		shade.anchor_right = 1.0
		shade.anchor_bottom = 1.0
		shade.offset_top = -26
		box.add_child(shade)
		var label := Label.new()
		label.name = "Name"
		label.text = full_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", UISkin.CREAM)
		label.add_theme_font_size_override("font_size", clampi(int(size.x / 11.0), 12, 20))
		label.clip_text = true
		shade.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return box
	if v == "small":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var pic := TextureRect.new()
		pic.name = "Picture"
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2.ONE * clampf(size.y - 12, 16, 96)
		pic.texture = hud.picture(hud.active)
		row.add_child(pic)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var label := Label.new()
		label.name = "Name"
		label.text = full_name
		label.theme_type_variation = UISkin.V_HEADING
		label.add_theme_font_size_override("font_size", clampi(int(size.y / 4.0), 12, 20))
		label.clip_text = true
		col.add_child(label)
		var sub := str(s.get("_class", ""))
		if sub != "":
			var cls := Label.new()
			cls.text = sub
			cls.clip_text = true
			cls.add_theme_font_size_override("font_size", 12)
			cls.add_theme_color_override("font_color", UISkin.INK_SOFT)
			col.add_child(cls)
		return row
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var pic := TextureRect.new()
	pic.name = "Picture"
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.texture = hud.picture(hud.active)
	pic.tooltip_text = "Q / E: switch · 1-9: sheet pages · F2: edit the HUD (or the open page)"
	col.add_child(pic)
	var name := Label.new()
	name.name = "Name"
	name.text = full_name
	name.theme_type_variation = UISkin.V_HEADING
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_size_override("font_size", clampi(int(size.x / 9.0), 13, 22))
	col.add_child(name)
	return col


static func _hp(s: Dictionary, hud: CharacterHud, v := "bar") -> Control:
	var info := hud.token_info(hud.active)
	var hp := int(s.get("hp", info.get("hp", 0)))
	var hp_max := int(s.get("_hp_max", info.get("hp", hp)))
	var temp := int(s.get("temp_hp", 0))
	var known := s.has("hp") or info.has("hp")
	var hp_text := ("%d / %d" % [hp, hp_max] + (" +%d" % temp if temp > 0 else "")) if known else "HP ?"
	if v == "number":  # big numbers, red when low
		var big := Label.new()
		big.name = "HPText"
		big.text = hp_text
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		big.theme_type_variation = UISkin.V_HEADING
		big.add_theme_font_size_override("font_size", 20)
		big.add_theme_color_override("font_color", UISkin.RED if known and hp * 2 <= hp_max else UISkin.INK)
		return big
	var box := Control.new()
	box.custom_minimum_size = Vector2(40, 18)
	var bar := ProgressBar.new()
	bar.name = "HP"
	bar.show_percentage = false
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UISkin.RED
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = UISkin.TAN
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bar.max_value = maxi(hp_max, 1)
	bar.value = hp if known else 0
	box.add_child(bar)
	var text := Label.new()
	text.name = "HPText"
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_color_override("font_color", UISkin.CREAM)
	text.add_theme_font_size_override("font_size", 13)
	text.text = hp_text
	box.add_child(text)
	return box


static func _slots(s: Dictionary, hud: CharacterHud, v := "pips") -> Control:
	var rows := VBoxContainer.new()
	rows.name = "SpellSlots"
	rows.add_theme_constant_override("separation", 2)
	var max_slots := CharacterHud.spell_slots(s)
	var editable := bool(s.get("_editable", false))
	for i in max_slots.size():
		var count := int(max_slots[i])
		if count <= 0:
			continue
		var level := i + 1
		var spent := clampi(Replay.slots_used(s, level), 0, count)
		if v == "count":  # "II  1 / 3"
			var line := Label.new()
			line.name = "Level%d" % level
			line.text = "%s   %d / %d" % [_roman_of(level), count - spent, count]
			line.add_theme_font_size_override("font_size", 13)
			line.add_theme_color_override("font_color", UISkin.INK if spent < count else UISkin.INK_SOFT)
			rows.add_child(line)
			continue
		var row := HFlowContainer.new()
		row.name = "Level%d" % level
		row.add_theme_constant_override("h_separation", 3)
		var label := Label.new()
		label.text = _roman_of(level)
		label.custom_minimum_size.x = 30
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", UISkin.INK)
		row.add_child(label)
		for p in count:
			var pip := Button.new()
			pip.name = "Pip%d" % (p + 1)
			pip.focus_mode = Control.FOCUS_NONE
			pip.custom_minimum_size = Vector2(14, 14)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.tooltip_text = "Level %d slot: %s" % [level, "used" if p < spent else "free"]
			var sb := StyleBoxFlat.new()
			sb.bg_color = UISkin.TAN if p < spent else UISkin.WINE
			sb.border_color = UISkin.WINE
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(7)
			for st in ["normal", "hover", "pressed", "disabled", "focus"]:
				pip.add_theme_stylebox_override(st, sb)
			pip.disabled = not editable
			var to := p if p < spent else p + 1  # a free pip spends up to it, a used one gives back
			pip.pressed.connect(func() -> void: hud.use_slots(level, to))
			row.add_child(pip)
		rows.add_child(row)
	if rows.get_child_count() == 0:
		var none := Label.new()
		none.text = "No spell slots"
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", UISkin.INK_SOFT)
		rows.add_child(none)
	return rows


static func _roman_of(level: int) -> String:
	return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"][clampi(level - 1, 0, 8)]


## A quick button (TASK-48): a spell, item or check, square or round, its initials big, the
## name under them when there is room, the amount on a badge (free slots of the spell's level,
## items held, a check's bonus). A click casts / uses / rolls it (CharacterHud.use_quick).
static func _quick(kind: String, ref: String, shape: String, s: Dictionary, hud: CharacterHud, size: Vector2) -> Control:
	var root := Control.new()
	root.name = "W_" + kind
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := maxf(minf(size.x, size.y), 8.0)
	var b := Button.new()
	b.name = "Button"
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	if shape == "round":
		b.anchor_left = 0.5
		b.anchor_right = 0.5
		b.anchor_top = 0.5
		b.anchor_bottom = 0.5
		b.offset_left = -side / 2
		b.offset_right = side / 2
		b.offset_top = -side / 2
		b.offset_bottom = side / 2
	else:
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var colour: Color = {"spell": UISkin.WINE, "item": Color("4f6b3c"), "check": UISkin.INK}[kind]
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = colour.lightened(0.15) if st == "hover" else colour.darkened(0.15) if st == "pressed" else colour
		sb.border_color = UISkin.TAN
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(side / 2) if shape == "round" else 8)
		b.add_theme_stylebox_override(st, sb)
	root.add_child(b)
	var name := quick_name(kind, ref, s)
	var glyph := Label.new()
	glyph.name = "Glyph"
	glyph.text = _check_glyph(ref) if kind == "check" else _initials(name)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.add_theme_color_override("font_color", UISkin.CREAM)
	glyph.add_theme_font_size_override("font_size", clampi(int(side * 0.34), 10, 40))
	b.add_child(glyph)
	if side >= 64:
		glyph.offset_bottom = -14
		var caption := Label.new()
		caption.name = "Caption"
		caption.text = name
		caption.clip_text = true
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.anchor_top = 1.0
		caption.anchor_right = 1.0
		caption.anchor_bottom = 1.0
		caption.offset_top = -22 if shape == "square" else -30
		caption.offset_bottom = -4 if shape == "square" else -12
		caption.add_theme_color_override("font_color", UISkin.CREAM)
		caption.add_theme_font_size_override("font_size", 11)
		b.add_child(caption)
	var amount := quick_amount(kind, ref, s)
	if amount != "":
		var badge := Label.new()
		badge.name = "Badge"
		badge.text = amount
		var sb := StyleBoxFlat.new()
		sb.bg_color = UISkin.CREAM
		sb.border_color = colour
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(7)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		badge.add_theme_stylebox_override("normal", sb)
		badge.add_theme_color_override("font_color", UISkin.INK)
		badge.add_theme_font_size_override("font_size", 11)
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_top = 2 if shape == "square" else side * 0.08
		badge.offset_right = -2 if shape == "square" else -side * 0.08
		b.add_child(badge)
		if amount.begins_with("0"):
			b.modulate = Color(1, 1, 1, 0.55)  # none left (still usable: nothing is spent yet)
	for c in b.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var verb: String = {"spell": "cast", "item": "use", "check": "roll"}[kind]
	b.tooltip_text = "%s%s\nClick: %s it%s" % [name, " (%s)" % amount if amount != "" else "", verb,
		" (Shift: advantage, Ctrl: disadvantage)" if kind == "check" else " · posts it in the chat"]
	b.pressed.connect(func() -> void: hud.use_quick(kind, ref))
	return root


## The amount on a quick button: a spell's free slots of its level ("2/4", none for cantrips),
## the items held ("3", "3/10" with a `max`), a check's bonus ("+5").
static func quick_amount(kind: String, ref: String, s: Dictionary) -> String:
	match kind:
		"spell":
			var refs: Dictionary = s.get("_refs", {}) if s.get("_refs") is Dictionary else {}
			var level := int((refs.get(ref, {}) as Dictionary).get("level", 0))
			if level <= 0:
				return ""
			var slots := CharacterHud.spell_slots(s)
			var count := int(slots[level - 1]) if level <= slots.size() else 0
			return "%d/%d" % [maxi(count - Replay.slots_used(s, level), 0), count]
		"item":
			for it: Variant in s.get("inventory", []):
				if it is Dictionary and str(it.get("item", "")) == ref:
					var qty := int(it.get("qty", 1))
					return "%d/%d" % [qty, int(it.max)] if it.has("max") else str(qty)
			return "0"
		"check":
			if not bool(s.get("_full", false)):
				return ""
			var words := ref.split(" ")
			if words.size() == 2 and words[0] in ABILITIES:
				return _signed(Rules.save(s, words[0]) if words[1] == "save" else Rules.check(s, words[0]))
			var sk := ref.replace(" ", "_")
			return _signed(Rules.skill(s, sk))
	return ""


## A check's glyph: the ability ("DEX" for a DEX save or check), a skill's first letters.
static func _check_glyph(ref: String) -> String:
	var first := ref.get_slice(" ", 0)
	return first.to_upper() if first in ABILITIES else ref.left(4).capitalize().strip_edges()


static func _initials(name: String) -> String:
	var words := name.replace("'", "").split(" ", false)
	if words.is_empty():
		return "?"
	if words.size() == 1:
		return words[0].left(3).capitalize() if words[0].length() > 3 else words[0]
	return (words[0].left(1) + words[1].left(1)).to_upper()


## Abilities (score, modifier: an ability check), saves or skills, a button each that rolls
## it for the active one. Columns follow the width.
static func _checks(s: Dictionary, hud: CharacterHud, which: String, size: Vector2) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var head := Label.new()
	head.text = which.capitalize()
	head.theme_type_variation = UISkin.V_HEADING
	head.add_theme_font_size_override("font_size", 14)
	col.add_child(head)
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 1)
	col.add_child(grid)
	var stats: Variant = s.get("stats")
	if not bool(s.get("_full", false)) or not stats is Dictionary:
		var none := Label.new()
		none.text = "…"
		grid.add_child(none)
		return col
	var cell_width := 150.0 if which == "skills" else 105.0
	grid.columns = clampi(int(size.x / cell_width), 1, 4 if which == "skills" else 3)
	if which == "skills":
		var names: Array = Dice.SKILLS.keys()
		names.sort()
		for skill: String in names:
			var bonus := Dice._bonus(s, "skills", skill, str(Dice.SKILLS[skill]))
			_button(grid, hud, "%s %s" % [skill.replace("_", " ").capitalize(), _signed(bonus)], skill.replace("_", " "), _lists(s, "skills", skill))
	else:
		for ab: String in ABILITIES:
			if which == "abilities":
				var score := int((stats as Dictionary).get(ab, 10))
				_button(grid, hud, "%s  %d  %s" % [ab.to_upper(), score, _signed(Rules.check(s, ab))], "%s check" % ab, false)
			else:
				_button(grid, hud, "%s  %s" % [ab.to_upper(), _signed(Dice._bonus(s, "saves", ab, ab))], "%s save" % ab, _lists(s, "saves", ab))
	return col


static func _button(parent: Control, hud: CharacterHud, text: String, query: String, proficient: bool) -> void:
	var b := Button.new()
	b.text = text
	b.name = query.replace(" ", "_")
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 12)
	var ink := UISkin.WINE if proficient else UISkin.INK
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, ink)
	b.tooltip_text = "Roll %s%s (Shift: advantage, Ctrl: disadvantage)" % [query, " · proficient" if proficient else ""]
	b.pressed.connect(func() -> void: hud.roll_check(query))
	parent.add_child(b)


static func _text(bbcode: String, title := "") -> Control:
	var col := VBoxContainer.new()
	if title != "":
		var head := Label.new()
		head.text = title
		head.theme_type_variation = UISkin.V_HEADING
		head.add_theme_font_size_override("font_size", 14)
		col.add_child(head)
	var t := RichTextLabel.new()
	t.name = "Text"
	t.bbcode_enabled = true
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("normal_font_size", 13)
	t.text = bbcode if bbcode.strip_edges() != "" else "[color=#%s]—[/color]" % Markdown.MUTED.to_html(false)
	col.add_child(t)
	return col


static func _info_bbcode(s: Dictionary) -> String:
	var lines := PackedStringArray(["[b]%s[/b]" % Markdown.escape(str(s.get("name", "")))])
	var sub := str(s.get("_class", ""))
	if sub == "":
		sub = " ".join(PackedStringArray([str(s.get("size", "")), str(s.get("type", ""))])).strip_edges()
	var race := str(s.get("race", "")).get_file().replace("-", " ").capitalize()
	if race != "":
		sub = (race + " " + sub).strip_edges()
	if sub != "":
		lines.append(Markdown.escape(sub))
	var bits := PackedStringArray()
	if s.has("ac") or s.has("stats"):
		bits.append("AC %d" % Rules.ac(s))
	var speed: Variant = s.get("speed")
	if speed is Dictionary and float(speed.get("walk", 0)) > 0:
		bits.append("Speed %s m" % _num(speed.walk))
	if s.has("stats"):
		bits.append("Prof +%d" % Rules.proficiency(s))
	if not bits.is_empty():
		lines.append(" · ".join(bits))
	return "\n".join(lines)


static func _list_bbcode(s: Dictionary, keys: Array) -> String:
	var lines := PackedStringArray()
	for key: String in keys:
		for v: Variant in s.get(key, []):
			var ref: Variant = (s.get("_refs", {}) as Dictionary).get(str(v)) if s.get("_refs") is Dictionary else null
			lines.append("• " + Markdown.escape(str(ref.name) if ref is Dictionary and ref.has("name") else _name_of(v)))
	return "\n".join(lines)


static func _inventory_bbcode(s: Dictionary) -> String:
	var lines := PackedStringArray()
	for it: Variant in s.get("inventory", []):
		if it is Dictionary:
			var qty := int(it.get("qty", 1))
			lines.append("• %s%s%s" % ["%d× " % qty if qty > 1 else "", Markdown.escape(_name_of(it.get("item", ""))), " (equipped)" if it.get("equipped", false) else ""])
		else:
			lines.append("• " + Markdown.escape(_name_of(it)))
	return "\n".join(lines)


static func _name_of(v: Variant) -> String:
	if v is Dictionary:
		return str(v.get("name", v.get("id", "?")))
	return str(v).get_file().replace("-", " ").capitalize()


## 15.0 -> "15", 7.5 -> "7.5".
static func _num(v: Variant) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(f)


static func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


static func _lists(s: Dictionary, key: String, name: String) -> bool:
	var list: Variant = s.get(key)
	return (list is Dictionary and (list as Dictionary).has(name)) or (list is Array and name in list)


## Holds a piece's content (Nico 2026-11-04: pieces drawn bigger than their frame): it asks for
## no size of its own, so the frame stays the piece's size; content that needs more room is
## scaled down to fit (never up).
class FitBox extends Container:
	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN:
			return
		for c in get_children():
			if c is Control and (c as Control).visible:
				var m := (c as Control).get_combined_minimum_size()
				var k := minf(1.0, minf(size.x / maxf(m.x, 1.0), size.y / maxf(m.y, 1.0)))
				k = maxf(k, 0.05)
				fit_child_in_rect(c, Rect2(Vector2.ZERO, size / k))
				(c as Control).scale = Vector2(k, k)
