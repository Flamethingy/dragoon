class_name HudWidgets
extends RefCounted
## The pieces a HUD (TASK-47, F2) and the sheet pages (F3) are put together from. Each is
## built for a size in pixels and arranges its contents to it (skills in 1-4 columns, ...).
## Layouts are lists of {"w": kind, "r": [x, y, w, h]} in grid cells; they live in the
## character (`hud`, `sheet_pages`), for creatures in their template in the Book.

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
	# the app's buttons (Nico, 2026-11-01: "for now" pieces too); only shown to who may use them
	"compendium": {"label": "Compendium", "size": [4, 1]},
	"book": {"label": "Book", "size": [3, 1]},
	"leave": {"label": "Leave", "size": [3, 1]},
}
## Pieces that are buttons of the app (CharacterHud.actions).
const APP_BUTTONS := ["compendium", "book", "leave"]

## Without a layout of its own (Nico, 2026-11-01): portrait, health and spell slots, lower left.
const DEFAULT_HUD := [
	{"w": "portrait", "r": [0, 19, 4, 5]},
	{"w": "hp", "r": [0, 24, 4, 1]},
	{"w": "slots", "r": [0, 25, 4, 2]},
	{"w": "compendium", "r": [37, 0, 4, 1]},
	{"w": "book", "r": [41, 0, 3, 1]},
	{"w": "leave", "r": [44, 0, 3, 1]},
]
const DEFAULT_PAGES := [
	{"name": "Sheet", "items": [
		{"w": "portrait", "r": [0, 0, 3, 4]}, {"w": "info", "r": [3, 0, 5, 3]}, {"w": "hp", "r": [3, 3, 5, 1]},
		{"w": "abilities", "r": [0, 4, 3, 6]}, {"w": "saves", "r": [3, 4, 3, 6]}, {"w": "skills", "r": [8, 0, 8, 10]},
		{"w": "slots", "r": [6, 4, 2, 6]}]},
	{"name": "Spells & gear", "items": [
		{"w": "spells", "r": [0, 0, 8, 10]}, {"w": "inventory", "r": [8, 0, 8, 5]}, {"w": "features", "r": [8, 5, 8, 5]}]},
]

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]


## A layout made clean: known kinds, whole cells inside the grid.
static func clean(items: Variant, grid: Vector2i) -> Array:
	var out := []
	if not items is Array:
		return out
	for it: Variant in items:
		if not it is Dictionary or not KINDS.has(str(it.get("w", ""))) or not it.get("r") is Array or (it.r as Array).size() != 4:
			continue
		var r: Array = it.r
		var w := clampi(int(r[2]), 1, grid.x)
		var h := clampi(int(r[3]), 1, grid.y)
		out.append({"w": str(it.w), "r": [clampi(int(r[0]), 0, grid.x - w), clampi(int(r[1]), 0, grid.y - h), w, h]})
	return out


## The widget `kind` for the sheet `s`, `size` pixels big. `hud` rolls, spends slots and
## knows the portrait. Its name is "W_<kind>".
static func build(kind: String, s: Dictionary, hud: CharacterHud, size: Vector2) -> Control:
	if kind in APP_BUTTONS:
		return _app_button(kind, hud, size)
	var panel := PanelContainer.new()
	panel.name = "W_" + kind
	panel.theme_type_variation = UISkin.V_PAGE
	panel.custom_minimum_size = Vector2.ZERO
	panel.size = size
	panel.clip_contents = true
	var body: Control
	match kind:
		"portrait":
			body = _portrait(s, hud, size)
		"hp":
			body = _hp(s, hud)
		"slots":
			body = _slots(s, hud)
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
		_:
			body = Label.new()
	panel.add_child(body)
	return panel


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


static func _portrait(s: Dictionary, hud: CharacterHud, size: Vector2) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var pic := TextureRect.new()
	pic.name = "Picture"
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.texture = hud.picture(hud.active)
	pic.tooltip_text = "Q / E: switch · F2: edit the HUD · 1-9: sheet pages · F3: edit them"
	col.add_child(pic)
	var name := Label.new()
	name.name = "Name"
	name.text = hud.label(hud.active) if s.is_empty() else str(s.get("name", hud.label(hud.active)))
	name.theme_type_variation = UISkin.V_HEADING
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_size_override("font_size", clampi(int(size.x / 9.0), 13, 22))
	col.add_child(name)
	return col


static func _hp(s: Dictionary, hud: CharacterHud) -> Control:
	var info := hud.token_info(hud.active)
	var hp := int(s.get("hp", info.get("hp", 0)))
	var hp_max := int(s.get("_hp_max", info.get("hp", hp)))
	var temp := int(s.get("temp_hp", 0))
	var known := s.has("hp") or info.has("hp")
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
	text.text = ("%d / %d" % [hp, hp_max] + (" +%d" % temp if temp > 0 else "")) if known else "HP ?"
	box.add_child(text)
	return box


static func _slots(s: Dictionary, hud: CharacterHud) -> Control:
	var rows := VBoxContainer.new()
	rows.name = "SpellSlots"
	rows.add_theme_constant_override("separation", 2)
	var max_slots := CharacterHud.spell_slots(s)
	var used: Dictionary = s.get("spell_slots_used", {}) if s.get("spell_slots_used") is Dictionary else {}
	var editable := bool(s.get("_editable", false))
	for i in max_slots.size():
		var count := int(max_slots[i])
		if count <= 0:
			continue
		var level := i + 1
		var spent := clampi(int(used.get(str(level), 0)), 0, count)
		var row := HFlowContainer.new()
		row.name = "Level%d" % level
		row.add_theme_constant_override("h_separation", 3)
		var label := Label.new()
		label.text = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"][clampi(level - 1, 0, 8)]
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
				_button(grid, hud, "%s  %d  %s" % [ab.to_upper(), score, _signed(Dice.modifier(s, ab))], "%s check" % ab, false)
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
	if s.has("ac"):
		bits.append("AC %s" % _num(s.ac))
	var speed: Variant = s.get("speed")
	if speed is Dictionary and float(speed.get("walk", 0)) > 0:
		bits.append("Speed %s m" % _num(speed.walk))
	if s.has("proficiency_bonus"):
		bits.append("Prof +%s" % _num(s.proficiency_bonus))
	if not bits.is_empty():
		lines.append(" · ".join(bits))
	return "\n".join(lines)


static func _list_bbcode(s: Dictionary, keys: Array) -> String:
	var lines := PackedStringArray()
	for key: String in keys:
		for v: Variant in s.get(key, []):
			lines.append("• " + Markdown.escape(_name_of(v)))
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
