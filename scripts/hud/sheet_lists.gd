class_name SheetLists
extends RefCounted
## The Inventory, Spells and Features pieces of the HUD and the sheet pages (TASK-107), in two
## views: a list (a row each: icon, name, a detail line, marks, the amount) and cards (a grid:
## icon, name, an amount badge). A toggle in the piece's header switches the view; the choice is
## kept on this computer per kind (`settings_file`); the layout's variant is the default.
## A click uses the entry like its quick button: an item is used, a spell cast (TASK-48/49).
## What is shown comes from the sheet: `inventory` + `_gear`, `spells`, the feature lists, and
## `_refs` / `_resources` (NetTable.sheet_for: names, types, levels, pictures, uses).

const KINDS := ["inventory", "spells", "features"]
const VIEWS := ["list", "cards"]
const FEATURE_LISTS := ["features", "traits", "actions", "bonus_actions", "reactions"]
const LIST_LABELS := {"features": "Features", "traits": "Traits", "actions": "Actions",
	"bonus_actions": "Bonus actions", "reactions": "Reactions"}
const ROW_H := 38.0
const ICON := 30.0
const CARD := Vector2(84, 106)

static var settings_file := "user://sheet_views.cfg"


## The view of a piece: chosen here, else the layout's variant, else the list.
static func view_of(kind: String, layout_v := "") -> String:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	var v := str(cfg.get_value("views", kind, layout_v))
	return v if v in VIEWS else "list"


static func set_view(kind: String, v: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	cfg.set_value("views", kind, v)
	cfg.save(settings_file)


# --- What is shown -----------------------------------------------------------------------------

## The entries of a piece: [{ref, use ("item" / "spell" / ""), name, detail, marks, amount,
## spent, group, icon: {image, letter, color_key, sprite}, tip}].
static func rows(kind: String, s: Dictionary) -> Array:
	match kind:
		"inventory":
			return _items(s)
		"spells":
			return _spells(s)
		"features":
			return _features(s)
	return []


static func _refs(s: Dictionary) -> Dictionary:
	return s.get("_refs", {}) if s.get("_refs") is Dictionary else {}


## A resource's {left, max} by id ("charges.items/x", "feature.y"), {} if none.
static func _resource(s: Dictionary, id: String) -> Dictionary:
	for r: Variant in s.get("_resources", []):
		if r is Dictionary and str(r.get("id", "")) == id:
			return {"left": maxi(int(r.get("max", 0)) - int(r.get("used", 0)), 0), "max": int(r.get("max", 0))}
	return {}


static func _items(s: Dictionary) -> Array:
	var out := []
	var gear: Array = s.get("_gear", []) if s.get("_gear") is Array else []
	var maxes := {}
	for it: Variant in s.get("inventory", []):
		if it is Dictionary and it.has("max"):
			maxes[str(it.get("item", ""))] = int(it.max)
	var listed := []
	for g: Variant in gear:
		if g is Dictionary:
			listed.append(str(g.get("item", "")))
	if gear.is_empty():  # no rules view yet (a creature, an old sheet): the plain inventory
		for g: Dictionary in Rules.gear(s):
			gear.append(g)
	for g: Variant in gear:
		if not g is Dictionary:
			continue
		var ref := str(g.get("item", ""))
		if ref == "":
			continue
		var info: Dictionary = _refs(s).get(ref, {})
		var name := str(info.get("name", g.get("name", HudWidgets._name_of(ref))))
		var qty := int(g.get("qty", 1))
		var bits := PackedStringArray()
		var w: Dictionary = g.get("weapon", {}) if g.get("weapon") is Dictionary else {}
		var a: Dictionary = g.get("armor", {}) if g.get("armor") is Dictionary else {}
		var bonus := int(g.get("bonus", 0))
		if not w.is_empty():
			bits.append("%s%s %s" % [str(w.get("damage", "")), " %+d" % bonus if bonus != 0 else "", str(w.get("type", ""))])
		elif not a.is_empty():
			bits.append("AC %s" % (("+%d" % int(a.get("ac", 0))) if str(a.get("category", "")) == "shield" else str(a.get("ac", ""))))
		elif str(info.get("type", "")) != "":
			bits.append(str(info.type))
		var rarity := str(info.get("rarity", ""))
		if rarity != "" and rarity.to_lower() not in ["common", "none", "mundane"]:
			bits.append(rarity)
		var charges := _resource(s, "charges." + ref)
		if not charges.is_empty():
			bits.append("%d/%d charges" % [charges.left, charges.max])
		var marks := []
		if bool(g.get("equipped", false)):
			marks.append(["E", "Equipped"])
		if bool(g.get("attuned", false)):
			marks.append(["A", "Attuned"])
		elif bool(g.get("attunement", false)):
			marks.append(["a", "Needs attunement (not attuned)"])
		var amount := "%d/%d" % [qty, int(maxes[ref])] if maxes.has(ref) else ("×%d" % qty if qty != 1 else "")
		var tip := PackedStringArray([name])
		tip.append_array(bits)
		if float(info.get("weight", 0)) > 0:
			tip.append("Weight %s" % HudWidgets._num(float(info.weight) * qty))
		out.append({"ref": ref, "use": "item", "name": name, "detail": " · ".join(bits), "marks": marks,
			"amount": amount, "spent": qty <= 0, "group": "",
			"icon": {"image": str(info.get("image", "")), "letter": name.left(1).to_upper(), "color_key": str(info.get("type", "item")),
				"sprite": item_sprite(name, str(info.get("type", "")), w, a)},
			"tip": "\n".join(tip) + "\nClick: use it"})
	return out


## The sheet sprite for an item: by what it is (weapon, armor, shield, potion, ring ...).
static func item_sprite(name: String, type: String, weapon := {}, armor := {}) -> String:
	var t := (name + " " + type).to_lower()
	var words := []  # whole words: "Adventuring Gear" is no ring
	for w: String in t.replace(",", " ").replace("(", " ").replace(")", " ").split(" ", false):
		words.append(w)
	if not armor.is_empty() and str(armor.get("category", "")) == "shield" or "shield" in t:
		return "icon_shield"
	if not weapon.is_empty() or "weapon" in t:
		return "icon_sword"
	if not armor.is_empty() or "armor" in t:
		return "icon_armor"
	for pair: Array in [["potion", "icon_potion"], ["elixir", "icon_potion"], ["ring", "ring"], ["boots", "icon_boot"],
			["helm", "icon_helmet"], ["hat", "icon_helmet"], ["gem", "gem"], ["diamond", "gem"], ["jewel", "gem"],
			["coins", "coin_gold"], ["coin", "coin_gold"], ["gold", "coin_gold"], ["potions", "icon_potion"], ["rings", "ring"]]:
		if str(pair[0]) in words:
			return str(pair[1])
	return "icon_chest"


static func _spells(s: Dictionary) -> Array:
	var out := []
	for v: Variant in s.get("spells", []):
		var ref := str(v)
		var info: Dictionary = _refs(s).get(ref, {})
		var name := str(info.get("name", HudWidgets._name_of(ref)))
		var level := int(info.get("level", 0))
		var bits := PackedStringArray(["Cantrip" if level == 0 else "Level %d" % level])
		if str(info.get("school", "")) != "":
			bits.append(str(info.school).capitalize())
		if str(info.get("casting_time", "")) != "":
			bits.append(str(info.casting_time))
		var marks := []
		if bool(info.get("concentration", false)):
			marks.append(["C", "Concentration"])
		if bool(info.get("ritual", false)):
			marks.append(["R", "Ritual"])
		var amount := HudWidgets.quick_amount("spell", ref, s)
		out.append({"ref": ref, "use": "spell", "name": name, "detail": " · ".join(bits), "marks": marks,
			"amount": amount, "spent": amount.begins_with("0/"), "group": "Cantrips" if level == 0 else "Level %d" % level, "level": level,
			"icon": {"image": str(info.get("image", "")), "letter": "C" if level == 0 else str(level), "color_key": str(info.get("school", "spell")), "sprite": ""},
			"tip": "%s\n%s%s\nClick: cast it" % [name, " · ".join(bits), "\nFree slots: " + amount if amount != "" else ""]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return [int(a.level), str(a.name)] < [int(b.level), str(b.name)])
	return out


static func _features(s: Dictionary) -> Array:
	var out := []
	var seen := {}
	for key: String in FEATURE_LISTS:
		for v: Variant in s.get(key, []):
			var ref := str(v)
			if seen.has(ref):
				continue
			seen[ref] = true
			var info: Dictionary = _refs(s).get(ref, {})
			var name := str(info.get("name", HudWidgets._name_of(ref)))
			var bits := PackedStringArray()
			if str(info.get("class", "")) != "":
				bits.append("%s %d" % [HudWidgets._name_of(info.class), int(info.get("level", 0))] if int(info.get("level", 0)) > 0 else HudWidgets._name_of(info.class))
			if bool(info.get("attack", false)):
				bits.append("Attack")
			if bool(info.get("save", false)):
				bits.append("Save")
			var uses := _resource(s, "feature." + ref)
			var amount := "%d/%d" % [uses.left, uses.max] if not uses.is_empty() else ""
			var sprite := "icon_sword" if bool(info.get("attack", false)) else "icon_shield" if bool(info.get("save", false)) else ""
			out.append({"ref": ref, "use": "", "name": name, "detail": " · ".join(bits), "marks": [],
				"amount": amount, "spent": not uses.is_empty() and int(uses.left) <= 0, "group": str(LIST_LABELS[key]),
				"icon": {"image": "", "letter": name.left(1).to_upper(), "color_key": key, "sprite": sprite},
				"tip": name + ("\n" + " · ".join(bits) if not bits.is_empty() else "") + ("\nUses left: " + amount if amount != "" else "")})
	return out


# --- Building ------------------------------------------------------------------------------------

## The piece's body: a header (title, the view toggle) over the rows in the chosen view.
static func build(kind: String, s: Dictionary, hud: CharacterHud, size: Vector2, layout_v := "") -> Control:
	var col := VBoxContainer.new()
	col.name = "Lists"
	col.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.name = "Head"
	col.add_child(head)
	var title := Label.new()
	title.text = {"inventory": "Inventory", "spells": "Spells", "features": "Features"}.get(kind, kind.capitalize())
	title.theme_type_variation = UISkin.V_HEADING
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var all := rows(kind, s)
	var count := Label.new()
	count.text = str(all.size()) if not all.is_empty() else ""
	count.theme_type_variation = UISkin.V_MUTED
	count.add_theme_font_size_override("font_size", 11)
	head.add_child(count)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var fill := func(v: String) -> void:
		for c in scroll.get_children():
			scroll.remove_child(c)
			c.queue_free()
		scroll.add_child(_cards(all, hud, size.x - 36.0) if v == "cards" else _list(all, hud, kind != "inventory"))
	var toggles := {}
	for v: String in VIEWS:
		var b := Button.new()
		b.name = "View_" + v
		b.text = "☰" if v == "list" else "▦"
		b.tooltip_text = "List: icon, details and amount" if v == "list" else "Cards"
		b.toggle_mode = true
		var off := StyleBoxEmpty.new()
		off.content_margin_left = 4
		off.content_margin_right = 4
		for st: String in ["normal", "hover", "focus"]:
			b.add_theme_stylebox_override(st, off)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, UISkin.INK_SOFT if c == "font_color" else UISkin.CREAM if "pressed" in c else UISkin.WINE)
		var on := StyleBoxFlat.new()  # the view in use: a wine chip
		on.bg_color = UISkin.WINE
		on.set_corner_radius_all(4)
		on.content_margin_left = 4
		on.content_margin_right = 4
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		head.add_child(b)
		toggles[v] = b
	var show := func(v: String) -> void:
		for key: String in toggles:
			(toggles[key] as Button).set_pressed_no_signal(key == v)
		fill.call(v)
	for v: String in VIEWS:
		(toggles[v] as Button).pressed.connect(func() -> void:
			set_view(kind, v)
			show.call(v))
	show.call(view_of(kind, layout_v))
	if all.is_empty():
		var none := Label.new()
		none.text = "—"
		none.theme_type_variation = UISkin.V_MUTED
		scroll.get_child(0).add_child(none)
	return col


## The list: a row per entry (grouped: spells by level, features by list).
static func _list(all: Array, hud: CharacterHud, grouped: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "List"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	var group := ""
	for r: Dictionary in all:
		if grouped and str(r.group) != group:
			group = str(r.group)
			var h := Label.new()
			h.text = group
			h.theme_type_variation = UISkin.V_MUTED
			h.add_theme_font_size_override("font_size", 11)
			box.add_child(h)
		box.add_child(_row(r, hud))
	return box


static func _row(r: Dictionary, hud: CharacterHud) -> Control:
	var b := Button.new()
	b.name = "Row_" + str(r.ref).validate_node_name()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = str(r.tip)
	b.set_meta("ref", str(r.ref))
	if bool(r.spent):
		b.modulate = Color(1, 1, 1, 0.55)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 2
	row.offset_right = -4
	row.add_theme_constant_override("separation", 6)
	b.add_child(row)
	var art := icon(r.icon, Vector2(ICON, ICON))
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", -2)
	row.add_child(text)
	var name := Label.new()
	name.name = "Name"
	name.text = str(r.name)
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_color_override("font_color", UISkin.INK)
	text.add_child(name)
	if str(r.detail) != "":
		var detail := Label.new()
		detail.name = "Detail"
		detail.text = str(r.detail)
		detail.clip_text = true
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail.theme_type_variation = UISkin.V_MUTED
		detail.add_theme_font_size_override("font_size", 11)
		text.add_child(detail)
	for m: Array in r.marks:
		row.add_child(_mark(str(m[0]), str(m[1])))
	if str(r.amount) != "":
		var amount := Label.new()
		amount.name = "Amount"
		amount.text = str(r.amount)
		amount.add_theme_font_size_override("font_size", 13)
		amount.add_theme_color_override("font_color", UISkin.WINE)
		row.add_child(amount)
	for c in row.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_use(b, r, hud)
	return b


## The cards: a grid, as many columns as fit.
static func _cards(all: Array, hud: CharacterHud, width: float) -> Control:
	var grid := GridContainer.new()
	grid.name = "Cards"
	grid.columns = maxi(1, int(width / (CARD.x + 6.0)))
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for r: Dictionary in all:
		grid.add_child(_card(r, hud))
	return grid


static func _card(r: Dictionary, hud: CharacterHud) -> Control:
	var b := Button.new()
	b.name = "Card_" + str(r.ref).validate_node_name()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CARD
	b.tooltip_text = str(r.tip)
	b.set_meta("ref", str(r.ref))
	b.theme_type_variation = UISkin.V_CARD
	var sb := StyleBoxFlat.new()
	sb.bg_color = UISkin.CREAM
	sb.border_color = UISkin.TAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.border_color = UISkin.WINE
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	if bool(r.spent):
		b.modulate = Color(1, 1, 1, 0.55)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 4
	col.offset_top = 4
	col.offset_right = -4
	col.offset_bottom = -4
	col.add_theme_constant_override("separation", 2)
	b.add_child(col)
	var art := icon(r.icon, Vector2(CARD.x - 8.0, CARD.y - 40.0))
	col.add_child(art)
	var name := Label.new()
	name.name = "Name"
	name.text = str(r.name)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.max_lines_visible = 2
	name.add_theme_font_size_override("font_size", 11)
	name.add_theme_color_override("font_color", UISkin.INK)
	col.add_child(name)
	if str(r.amount) != "":
		var badge := Label.new()
		badge.name = "Badge"
		badge.text = str(r.amount)
		var bs := StyleBoxFlat.new()
		bs.bg_color = UISkin.CREAM
		bs.border_color = UISkin.WINE
		bs.set_border_width_all(1)
		bs.set_corner_radius_all(7)
		bs.content_margin_left = 4
		bs.content_margin_right = 4
		badge.add_theme_stylebox_override("normal", bs)
		badge.add_theme_color_override("font_color", UISkin.INK)
		badge.add_theme_font_size_override("font_size", 11)
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_top = 3
		badge.offset_right = -3
		b.add_child(badge)
	if not (r.marks as Array).is_empty():
		var marks := HBoxContainer.new()
		marks.offset_left = 3
		marks.offset_top = 3
		for m: Array in r.marks:
			marks.add_child(_mark(str(m[0]), str(m[1])))
		b.add_child(marks)
	for c in b.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_use(b, r, hud)
	return b


## An entry's picture: its image, else a plate in its type's colour with a sprite or a letter.
static func icon(spec: Dictionary, side: Vector2) -> Control:
	var art := CardArt.new()
	art.name = "Icon"
	art.custom_minimum_size = side
	var path := str(spec.get("image", ""))
	art.show_entry({"name": str(spec.get("letter", "?")), "type": str(spec.get("color_key", "")),
		"image": path.get_file() if path != "" else "", "_dir": path.get_base_dir() if path != "" else ""})
	art.letter = str(spec.get("letter", "?"))
	if str(spec.get("sprite", "")) != "":
		art.icon = UISkin.tex(str(spec.sprite))
	return art


static func _mark(letter: String, tip: String) -> Control:
	var l := Label.new()
	l.text = letter
	l.tooltip_text = tip
	var sb := StyleBoxFlat.new()
	sb.bg_color = UISkin.WINE if letter == letter.to_upper() else UISkin.TAN
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_color_override("font_color", UISkin.CREAM)
	l.add_theme_font_size_override("font_size", 10)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


static func _connect_use(b: Button, r: Dictionary, hud: CharacterHud) -> void:
	var use := str(r.use)
	if use == "" or hud == null:
		return
	var ref := str(r.ref)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void: hud.use_quick(use, ref))
