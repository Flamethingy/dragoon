class_name CharacterHud
extends Control
## The active character (TASK-44, Nico 2026-11-01). Q / E go round robin through every token
## the user controls: their own characters (owners), the DM everything on the map; with
## tokens selected only through the selected ones. Marks on the map: selected (white ring),
## active (orange ring). The HUD reads the active one's sheet from the table (NetTable.open_sheet
## without showing the sheet panel) and changes go through it as events.
## What it shows is a layout (TASK-47): pieces (HudWidgets) on a grid over the screen, saved
## in the character (`hud`), for creatures in their template in the Book; without one the
## portrait, health and spell slots. Keys 1-9 open the sheet pages (SheetPages). F2 edits
## (LayoutEditor): the open sheet page, else the HUD (Nico, 2026-11-01: one key for both).
## Quick buttons cast a spell, use an item or roll a check (TASK-48).

signal active_changed(ref: String)
signal shown  ## the HUD was (re)built or hidden: the app checks whether it shows its buttons

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
var pages: SheetPages  ## the sheet pages (keys 1-9), set by TableUI
## The app's buttons as pieces: "compendium" / "book" / "leave" -> what they do (set by the
## app for what this user may use).
var actions := {}
var editor: LayoutEditor  ## the HUD / page editor while it is open
var _dismissed := false  ## a click on the empty map hid it: stays hidden until Q / E or a selection
var _pieces: Control
var _tween: Tween


func _init() -> void:
	name = "CharacterHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pieces = Control.new()
	_pieces.name = "Pieces"
	_pieces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pieces.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_pieces)
	visible = false


func _ready() -> void:
	if table == null:
		return
	table.table_changed.connect(_check_active)
	table.pcs_changed.connect(_check_active)
	if table.grid != null:
		table.grid.selection_changed.connect(_on_selection)
		table.grid.cleared.connect(dismiss)
	table.sheet_received.connect(func(ref: String) -> void:
		if ref == active:
			_fill())
	resized.connect(_fill)
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
	rest.sort_custom(func(a: String, b: String) -> bool: return label(a).naturalnocasecmp_to(label(b)) < 0)
	for ref in rest:
		if ref not in out:
			out.append(ref)
	return out


## What Q / E go through: the selected tokens one controls, or all of them if at most one
## is (Nico, 2026-11-02: with just the active one you still go through the characters).
func cycle_list() -> PackedStringArray:
	var list := controlled()
	if table == null or table.grid == null:
		return list
	var picked := table.grid.picked()
	var out := PackedStringArray()
	for ref in list:
		if ref in picked:
			out.append(ref)
	return out if out.size() > 1 else list


## Q (-1) / E (+1): the next one round robin, with the slide animation.
func cycle(step: int) -> void:
	var list := cycle_list()
	if list.is_empty():
		return
	var at := list.find(active)
	var next := list[posmod(at + step, list.size())] if at >= 0 else (list[0] if step >= 0 else list[list.size() - 1])
	if next != active or at < 0:
		set_active(next, step)


## Nothing active, the HUD hidden (a click on the empty map).
func dismiss() -> void:
	set_active("")
	_dismissed = true


func set_active(ref: String, direction := 0) -> void:
	if ref != "":
		_dismissed = false
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


## A selection without the active one makes its first token (that one controls) active
## (Nico, 2026-11-01); a selection with it keeps it.
func _on_selection() -> void:
	var picked := table.grid.picked()
	if picked.is_empty() or active in picked:
		return
	var mine := controlled()
	for ref: String in picked:
		if ref in mine:
			set_active(ref, 1)
			return


## Keeps the active one valid: the own character when there is one, else the first token.
func _check_active() -> void:
	var list := controlled()
	if active == "" and _dismissed:
		_fill()
		return
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
	if not (event is InputEventKey and event.pressed and not event.echo) or table == null or not table.is_online():
		return
	var k := event as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or _typing():
		return
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if editor != null:  # the editor is open: F2 / Esc close it (saved)
		if code in [KEY_F2, KEY_ESCAPE]:
			editor.finish(true)
			get_viewport().set_input_as_handled()
		return
	if code == KEY_Q or code == KEY_E:
		cycle(-1 if code == KEY_Q else 1)
	elif code == KEY_F2:
		edit()
	elif code >= KEY_1 and code <= KEY_9 and pages != null and active != "":
		pages.toggle(code - KEY_1)
	elif code == KEY_ESCAPE and pages != null and pages.visible:
		pages.close()
	else:
		return
	get_viewport().set_input_as_handled()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


## What the HUD shows now: the active one's sheet (or its token until the sheet comes).

## What the HUD shows now: the active one's sheet (or its token until the sheet comes), laid
## out as its layout says.
func _fill() -> void:
	visible = active != "" and table != null and table.is_online() and editor == null
	if pages != null:
		pages.refresh()
	if not visible:
		shown.emit()
		return
	for c in _pieces.get_children():
		_pieces.remove_child(c)
		c.queue_free()
	var s: Dictionary = table.sheets.get(active, {})
	var cell := cell_size()
	for it: Dictionary in layout():
		var r: Array = it.r
		var rect := Rect2(Vector2(float(r[0]), float(r[1])) * cell, Vector2(float(r[2]), float(r[3])) * cell).grow(-2)
		var w := HudWidgets.build(str(it.w), s, self, rect.size, it)
		w.position = rect.position
		w.size = rect.size
		_pieces.add_child(w)
	shown.emit()


## Builds it again (e.g. the app's buttons changed).
func refresh() -> void:
	_fill()


## True if the HUD shows the app's buttons (Compendium, Book, Leave) itself.
func shows_app_buttons() -> bool:
	return visible and layout().any(func(it: Dictionary) -> bool: return str(it.w) in HudWidgets.APP_BUTTONS and actions.has(str(it.w)))


func cell_size() -> Vector2:
	var area := size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	return area / Vector2(HudWidgets.HUD_GRID)


## The active one's HUD layout: its own, its template's (sheet `_hud`), else the default.
func layout() -> Array:
	var s: Dictionary = table.sheets.get(active, {}) if table != null else {}
	var own := HudWidgets.clean(s.get("_hud"), HudWidgets.HUD_GRID)
	return own if not own.is_empty() else HudWidgets.DEFAULT_HUD.duplicate(true)


## Its sheet pages (`_pages`), else the default ones.
func page_list() -> Array:
	var s: Dictionary = table.sheets.get(active, {}) if table != null else {}
	var out := []
	if s.get("_pages") is Array:
		for p: Variant in s._pages:
			if p is Dictionary:
				out.append({"name": str(p.get("name", "Page")), "items": HudWidgets.clean(p.get("items"), HudWidgets.PAGE_GRID)})
	return out if not out.is_empty() else HudWidgets.DEFAULT_PAGES.duplicate(true)


## May this user change the active one's layouts (owners, the DM)?
func may_edit() -> bool:
	return active != "" and bool((table.sheets.get(active, {}) as Dictionary).get("_editable", false))


## F2: edits the sheet page that is open, else the HUD.
func edit() -> void:
	if pages != null and pages.visible:
		edit_pages()
	else:
		edit_hud()


## The HUD editor: the screen, shown smaller, with the catalog around it.
func edit_hud() -> void:
	if not may_edit() or editor != null:
		return
	var ed := LayoutEditor.new()
	ed.grid = HudWidgets.HUD_GRID
	ed.sets = [{"name": "HUD", "items": layout()}]
	ed.sheet = table.sheets.get(active, {})
	ed.hud = self
	ed.canvas = size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	ed.screen_backdrop = true
	_open_editor(ed, "hud")


## The sheet page editor (the page shown, else the first).
func edit_pages() -> void:
	if not may_edit() or editor != null or pages == null:
		return
	var at := pages.current if pages.visible else 0
	pages.open(at)
	var ed := LayoutEditor.new()
	ed.grid = HudWidgets.PAGE_GRID
	ed.multi = true
	ed.sets = page_list()
	ed.current = clampi(at, 0, ed.sets.size() - 1)
	ed.sheet = table.sheets.get(active, {})
	ed.hud = self
	ed.canvas = pages.grid_rect().size
	_open_editor(ed, "sheet_pages")


func _open_editor(ed: LayoutEditor, field: String) -> void:
	editor = ed
	var ref := active
	ed.finished.connect(func(sets: Array, saved: bool) -> void:
		editor = null
		if saved:
			var value: Variant = sets[0].items if field == "hud" else sets
			var s: Dictionary = table.sheets.get(ref, {})
			s["_hud" if field == "hud" else "_pages"] = value  # right away; the table confirms
			table.save_layout(ref, field, value)
		_fill())
	get_parent().add_child(ed)
	_fill()


## Rolls a check for the active one (Shift held: advantage, Ctrl: disadvantage).
func roll_check(query: String) -> void:
	if active == "" or table == null:
		return
	var q := query
	if Input.is_key_pressed(KEY_SHIFT):
		q += " with advantage"
	elif Input.is_key_pressed(KEY_CTRL):
		q += " with disadvantage"
	table.roll(q, active)



## A quick button (TASK-48): a check rolls, a spell / an item is posted in the chat with its
## rolls (NetTable.use_action; nothing is spent yet, TASK-49).
func use_quick(kind: String, ref: String) -> void:
	if active == "" or table == null or editor != null:
		return
	if kind == "check":
		roll_check(ref)
	else:
		table.use_action(active, ref)


## Spent spell slots of a level, `spent` in all: resource.used / resource.restored
## "spell_slots.<level>" for the difference (TASK-51).
func use_slots(level: int, spent: int) -> void:
	if active == "":
		return
	var delta := spent - Replay.slots_used(table.sheets.get(active, {}), level)
	if delta != 0:
		table.use_resource(active, "spell_slots.%d" % level, delta)


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


func token_info(ref: String) -> Dictionary:
	if table.grid != null and table.grid.tokens.has(ref):
		return table.grid.tokens[ref].get_meta("info", {})
	return {}


func label(ref: String) -> String:
	var s: Dictionary = table.sheets.get(ref, {})
	if s.has("name"):
		return str(s.name)
	var info := token_info(ref)
	if info.has("name"):
		return str(info.name)
	for c: Dictionary in table.pc_choices:
		if c.get("id") == ref:
			return str(c.get("name", ref))
	return ref.get_file().capitalize()


## The token's art as it is (no frame): the "full picture" portrait. Else the token.
func art(ref: String) -> Texture2D:
	var sha := str(token_info(ref).get("image", ""))
	if sha != "" and table.assets != null:
		var tex := table.assets.texture(sha)
		if tex != null:
			return tex
	return picture(ref)


## The token's composed picture; on world maps the party token stands in for its members.
func picture(ref: String) -> Texture2D:
	var grid := table.grid
	if grid != null:
		for id: String in [ref, NetTable.PARTY]:
			if grid.tokens.has(id):
				return (grid.tokens[id] as Sprite2D).texture
	return TokenArt.compose(null, {}, ref.get_slice("/", 0))


## The new portrait pops in, turned a little the way it came from; the check panels fade in
## one after the other.


## The pieces fade in; the portrait pops, turned a little the way it came from.
func _animate(direction: int) -> void:
	if not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pieces.modulate.a = 0.0
	_tween.tween_property(_pieces, "modulate:a", 1.0, SLIDE)
	var pic := _pieces.find_child("Picture", true, false) as Control
	if pic != null:
		pic.pivot_offset = pic.size * 0.5
		pic.scale = Vector2(0.85, 0.85)
		pic.rotation = 0.12 * float(signi(direction))
		_tween.tween_property(pic, "scale", Vector2.ONE, SLIDE).set_trans(Tween.TRANS_BACK)
		_tween.tween_property(pic, "rotation", 0.0, SLIDE)
