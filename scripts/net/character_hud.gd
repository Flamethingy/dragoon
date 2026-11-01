class_name CharacterHud
extends Control
## The active character (TASK-44, Nico 2026-11-01): a big portrait in the lower left corner
## with HP and spell slots, and a hotbar of 10 slots next to it (empty for now; the player
## fills them later, never automatically). Q / E go round robin through every token the
## user controls: their own characters (owners), the DM everything on the map; with tokens
## selected only through the selected ones (Nico, 2026-11-01). Three marks on the map:
## none, selected (white ring), active (orange ring). Clicking or selecting a token does not
## change the active one (you can move a fellow player's token and stay in your character). The HUD reads the active one's sheet from the table
## (NetTable.open_sheet without showing the sheet panel) and changes go through it as events.

signal active_changed(ref: String)

const SLOTS := 10
const PORTRAIT := 132.0
const SLOT := 52.0
const SLIDE := 0.18  ## seconds of the change animation
## Spell slots per character level of a full caster (5e), level 1 slots first.
const FULL_CASTER := [[2], [3], [4, 2], [4, 3], [4, 3, 2], [4, 3, 3], [4, 3, 3, 1], [4, 3, 3, 2],
	[4, 3, 3, 3, 1], [4, 3, 3, 3, 2], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1, 1],
	[4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 1, 1, 1, 1], [4, 3, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 3, 2, 2, 1, 1]]
const FULL := ["bard", "cleric", "druid", "sorcerer", "wizard"]
const HALF := ["paladin", "ranger"]
const HALF_UP := ["artificer"]

var table: NetTable
var active := ""  ## the active entity's ref ("" = none)

var _box: HBoxContainer
var _card: PanelContainer
var _portrait: TextureRect
var _name: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _slots_row: VBoxContainer
var _hotbar: HBoxContainer
var _tween: Tween


func _init() -> void:
	name = "CharacterHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 12
	offset_top = -12
	offset_bottom = -12
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box = HBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.add_theme_constant_override("separation", 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_box)

	_card = PanelContainer.new()
	_card.name = "Portrait"
	_card.theme_type_variation = UISkin.V_PAGE
	_box.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_card.add_child(col)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.pivot_offset = Vector2(PORTRAIT, PORTRAIT) * 0.5
	_portrait.tooltip_text = "Q / E: switch between the tokens you control"
	_portrait.size = Vector2(PORTRAIT, PORTRAIT)
	var holder := Control.new()  # not a container: the animation may scale and turn the picture
	holder.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	holder.add_child(_portrait)
	col.add_child(holder)
	_name = Label.new()
	_name.theme_type_variation = UISkin.V_HEADING
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.add_theme_font_size_override("font_size", 17)
	_name.custom_minimum_size.x = PORTRAIT
	col.add_child(_name)
	var hp := Control.new()
	hp.custom_minimum_size = Vector2(PORTRAIT, 20)
	col.add_child(hp)
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HP"
	_hp_bar.show_percentage = false
	_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UISkin.RED
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = UISkin.TAN
	back.set_corner_radius_all(4)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	_hp_bar.add_theme_stylebox_override("background", back)
	hp.add_child(_hp_bar)
	_hp_text = Label.new()
	_hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.add_theme_color_override("font_color", UISkin.CREAM)
	_hp_text.add_theme_font_size_override("font_size", 13)
	hp.add_child(_hp_text)
	_slots_row = VBoxContainer.new()
	_slots_row.name = "SpellSlots"
	_slots_row.add_theme_constant_override("separation", 2)
	col.add_child(_slots_row)

	var bar := PanelContainer.new()
	bar.name = "Hotbar"
	bar.theme_type_variation = UISkin.V_PAGE
	bar.size_flags_vertical = Control.SIZE_SHRINK_END
	_box.add_child(bar)
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 4)
	bar.add_child(_hotbar)
	for i in SLOTS:
		var slot := Panel.new()
		slot.name = "Slot%d" % (i + 1)
		slot.custom_minimum_size = Vector2(SLOT, SLOT)
		slot.pivot_offset = Vector2(SLOT, SLOT) * 0.5
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UISkin.TAN, 0.55)
		sb.border_color = UISkin.BROWN
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		slot.add_theme_stylebox_override("panel", sb)
		slot.tooltip_text = "Slot %d (empty)" % (i + 1)
		var key := Label.new()
		key.text = str((i + 1) % 10)
		key.position = Vector2(5, 2)
		key.add_theme_color_override("font_color", UISkin.INK_SOFT)
		key.add_theme_font_size_override("font_size", 12)
		slot.add_child(key)
		_hotbar.add_child(slot)
	visible = false


func _ready() -> void:
	if table == null:
		return
	table.table_changed.connect(_check_active)
	table.pcs_changed.connect(_check_active)
	table.sheet_received.connect(func(ref: String) -> void:
		if ref == active:
			_fill())
	_check_active()


## Every token the user controls, their own character first: owners of a character move it,
## the DM controls everything on the map (party members too, on world maps).
func controlled() -> PackedStringArray:
	var out := PackedStringArray()
	if table == null or not table.is_online():
		return out
	var dm := table.is_dm()
	if table.my_pc != "":
		out.append(table.my_pc)
	var rest: Array[String] = []
	for ref: String in table.owners:
		if dm or table.owns(table.my_player, ref):
			rest.append(ref)
	if table.grid != null:
		for ref: String in table.grid.tokens:
			if ref == NetTable.PARTY:
				continue
			var info: Dictionary = table.grid.tokens[ref].get_meta("info", {})
			if dm or table.my_player in (info.get("owners", []) as Array):
				rest.append(ref)
	rest.sort_custom(func(a: String, b: String) -> bool: return _label(a).naturalnocasecmp_to(_label(b)) < 0)
	for ref in rest:
		if ref not in out:
			out.append(ref)
	return out


## What Q / E go through: the selected tokens one controls, or all of them if none is.
func cycle_list() -> PackedStringArray:
	var list := controlled()
	if table == null or table.grid == null:
		return list
	var picked := table.grid.picked()
	var out := PackedStringArray()
	for ref in list:
		if ref in picked:
			out.append(ref)
	return out if not out.is_empty() else list


## Q (-1) / E (+1): the next one round robin, with the slide animation.
func cycle(step: int) -> void:
	var list := cycle_list()
	if list.is_empty():
		return
	var at := list.find(active)
	var next := list[posmod(at + step, list.size())] if at >= 0 else (list[0] if step >= 0 else list[list.size() - 1])
	if next != active or at < 0:
		set_active(next, step)


func set_active(ref: String, direction := 0) -> void:
	if ref == active:
		return
	var before := active
	active = ref
	table.hud_ref = ref
	if table.grid != null:
		table.grid.set_active(ref)
	if before != "" and not (table.sheets.has(before) and _panel_shows(before)):
		table.close_sheet(before)
	if ref != "":
		table.open_sheet(ref, false)
	_fill()
	_animate(direction)
	active_changed.emit(ref)


func _panel_shows(ref: String) -> bool:
	var ui := get_parent()
	while ui != null and not ui is TableUI:
		ui = ui.get_parent()
	return ui is TableUI and (ui as TableUI).sheet.visible and (ui as TableUI).sheet.ref == ref


## Keeps the active one valid: the own character when there is one, else the first token.
func _check_active() -> void:
	var list := controlled()
	if active == "" or active not in list:
		var pick := ""
		if table != null and table.my_pc != "" and table.my_pc in list:
			pick = table.my_pc
		elif not list.is_empty():
			pick = list[0]
		if pick != active:
			set_active(pick)
			return
	_fill()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or not visible:
		return
	var k := event as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or _typing():
		return
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if code == KEY_Q or code == KEY_E:
		cycle(-1 if code == KEY_Q else 1)
		get_viewport().set_input_as_handled()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


## What the HUD shows now: the active one's sheet (or its token until the sheet comes).
func _fill() -> void:
	visible = active != "" and table != null and table.is_online()
	if not visible:
		return
	var s: Dictionary = table.sheets.get(active, {})
	var info := _token_info(active)
	_name.text = _label(active)
	_portrait.texture = _picture(active)
	var hp := int(s.get("hp", info.get("hp", 0)))
	var hp_max := int(s.get("_hp_max", info.get("hp", hp)))
	var temp := int(s.get("temp_hp", 0))
	var known := s.has("hp") or info.has("hp")
	_hp_bar.max_value = maxi(hp_max, 1)
	_hp_bar.value = hp if known else 0
	_hp_text.text = ("%d / %d" % [hp, hp_max] + (" +%d" % temp if temp > 0 else "")) if known else "HP ?"
	_fill_slots(s)


func _fill_slots(s: Dictionary) -> void:
	for c in _slots_row.get_children():
		c.queue_free()
	var max_slots := spell_slots(s)
	var used: Dictionary = s.get("spell_slots_used", {}) if s.get("spell_slots_used") is Dictionary else {}
	var editable := bool(s.get("_editable", false))
	for i in max_slots.size():
		var count := int(max_slots[i])
		if count <= 0:
			continue
		var level := i + 1
		var spent := clampi(int(used.get(str(level), 0)), 0, count)
		var row := HBoxContainer.new()
		row.name = "Level%d" % level
		row.add_theme_constant_override("separation", 3)
		var label := Label.new()
		label.text = _roman(level)
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
			pip.pressed.connect(func() -> void: use_slots(level, to))
			row.add_child(pip)
		_slots_row.add_child(row)


## Spent spell slots of a level, as a sheet.changed event (spell_slots_used.<level>).
func use_slots(level: int, spent: int) -> void:
	if active != "":
		table.change_field(active, "spell_slots_used.%d" % level, spent)


## Spell slots per level (level 1 first): the sheet's own `spell_slots` list, else from
## its classes (full casters, half casters; warlock pact slots added at their level).
static func spell_slots(s: Dictionary) -> Array:
	if s.get("spell_slots") is Array and not (s.spell_slots as Array).is_empty():
		return (s.spell_slots as Array).map(func(n: Variant) -> int: return int(n))
	var caster := 0.0
	var pact_level := 0
	for c: Variant in s.get("classes", []):
		if not c is Dictionary:
			continue
		var cls := str(c.get("class", "")).get_file().to_lower()
		var lvl := int(c.get("level", 0))
		if _is(cls, FULL):
			caster += lvl
		elif _is(cls, HALF):
			caster += floorf(lvl / 2.0)
		elif _is(cls, HALF_UP):
			caster += ceilf(lvl / 2.0)
		elif _is(cls, ["warlock"]):
			pact_level = lvl
	var out: Array = []
	var n := clampi(int(caster), 0, 20)
	if n > 0:
		out = (FULL_CASTER[n - 1] as Array).duplicate()
	if pact_level > 0:
		var count := 1 if pact_level == 1 else (2 if pact_level < 11 else (3 if pact_level < 17 else 4))
		var at := mini((pact_level + 1) / 2, 5)
		while out.size() < at:
			out.append(0)
		out[at - 1] = int(out[at - 1]) + count
	return out


static func _is(cls: String, names: Array) -> bool:
	return names.any(func(n: String) -> bool: return cls == n or cls.begins_with(n + "-"))


static func _roman(n: int) -> String:
	return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"][clampi(n - 1, 0, 8)]


func _token_info(ref: String) -> Dictionary:
	if table.grid != null and table.grid.tokens.has(ref):
		return table.grid.tokens[ref].get_meta("info", {})
	return {}


func _label(ref: String) -> String:
	var s: Dictionary = table.sheets.get(ref, {})
	if s.has("name"):
		return str(s.name)
	var info := _token_info(ref)
	if info.has("name"):
		return str(info.name)
	for c: Dictionary in table.pc_choices:
		if c.get("id") == ref:
			return str(c.get("name", ref))
	return ref.get_file().capitalize()


## The token's composed picture; on world maps the party token stands in for its members.
func _picture(ref: String) -> Texture2D:
	var grid := table.grid
	if grid != null:
		for id: String in [ref, NetTable.PARTY]:
			if grid.tokens.has(id):
				return (grid.tokens[id] as Sprite2D).texture
	return TokenArt.compose(null, {}, ref.get_slice("/", 0))


## Slide the new portrait in from the side it came from, the slots pop.
func _animate(direction: int) -> void:
	if not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_card.modulate.a = 0.0
	_portrait.scale = Vector2(0.85, 0.85)
	_portrait.rotation = 0.12 * float(signi(direction))
	_tween.tween_property(_card, "modulate:a", 1.0, SLIDE)
	_tween.tween_property(_portrait, "scale", Vector2.ONE, SLIDE).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_portrait, "rotation", 0.0, SLIDE)
	var i := 0
	for slot in _hotbar.get_children():
		var c := slot as Control
		c.scale = Vector2(1, 0.2)
		_tween.tween_property(c, "scale", Vector2.ONE, SLIDE).set_delay(0.015 * i)
		i += 1
