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

var table: NetTable
var active := ""  ## the active entity's ref ("" = none)
var pages: SheetPages  ## the sheet pages (keys 1-9), set by TableUI
## The app's buttons as pieces: "compendium" / "book" / "leave" -> what they do (set by the
## app for what this user may use).
var actions := {}
var editor: LayoutEditor  ## the HUD / page editor while it is open
var _dismissed := false  ## a click on the empty map hid it: stays hidden until Q / E or a selection
var _pieces: Control
var locked := false  ## looking back on the timeline (TASK-83): the pieces show but can't be used
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
	table.table_changed.connect(func() -> void:  # TASK-62: the turn piece follows the combat
		if visible and editor == null and layout().any(func(it: Dictionary) -> bool: return str(it.w) == "turn"):
			_fill())
	table.pcs_changed.connect(_check_active)
	if table.grid != null:
		table.grid.selection_changed.connect(_on_selection)
		table.grid.cleared.connect(dismiss)
	table.sheet_received.connect(func(ref: String) -> void:
		if ref == active:
			_fill())
	resized.connect(_fill)
	EntryDrag.accept_on(self, table, func() -> String: return active)  # TASK-94: drop items etc. on the HUD
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
	if editor != null:  # the editor is open: F2 / Esc close it (saved), 1-9 edit that page (TASK-78)
		if code in [KEY_F2, KEY_ESCAPE]:
			editor.finish(true)
			get_viewport().set_input_as_handled()
		elif code >= KEY_1 and code <= KEY_9:
			editor.show_page(code - KEY_1)
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
		if str(it.w) in HudWidgets.APP_BUTTONS:
			continue  # old layouts: these moved to the Esc menu
		var r: Array = it.r
		var rect := Rect2(Vector2(float(r[0]), float(r[1])) * cell, Vector2(float(r[2]), float(r[3])) * cell).grow(-2)
		var w := HudWidgets.build(str(it.w), s, self, rect.size, it)
		w.position = rect.position
		w.size = rect.size
		_pieces.add_child(w)
	_lock_pieces()
	shown.emit()


## Looking back (TASK-83): the HUD shows the character as it is now but can't be used.
func set_locked(on: bool) -> void:
	if on == locked:
		return
	locked = on
	_lock_pieces()


func _lock_pieces() -> void:
	for w: Node in _pieces.get_children():
		var block := w.get_node_or_null("PastLock") as Control
		if locked and block == null and w is Control:
			block = Control.new()
			block.name = "PastLock"
			block.set_anchors_preset(Control.PRESET_FULL_RECT)
			block.mouse_filter = Control.MOUSE_FILTER_STOP
			block.tooltip_text = "You're looking back in time: go back to Now (Home) to act"
			w.add_child(block)
		elif not locked and block != null:
			block.queue_free()
		if w is Control:
			(w as Control).modulate.a = 0.55 if locked else 1.0


## Builds it again (e.g. the app's buttons changed).
func refresh() -> void:
	_fill()


## True if the HUD shows the app's buttons (Compendium, Book, Leave) itself.
func shows_app_buttons() -> bool:
	return false  # they moved to the Esc menu (Nico, 2026-11-02)


func cell_size() -> Vector2:
	var area := size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	return area / Vector2(HudWidgets.HUD_GRID)


## The active one's HUD layout: its own, its template's (sheet `_hud`), else the default.
func layout() -> Array:
	var s: Dictionary = table.sheets.get(active, {}) if table != null else {}
	var own := HudWidgets.clean(s.get("_hud"), HudWidgets.HUD_GRID, cell_size())  # TASK-75: within the pieces' limits
	return own if not own.is_empty() else HudWidgets.clean(HudWidgets.DEFAULT_HUD, HudWidgets.HUD_GRID, cell_size())


## Its sheet pages (`_pages`), else the default ones.
func page_list() -> Array:
	var s: Dictionary = table.sheets.get(active, {}) if table != null else {}
	var out := []
	if s.get("_pages") is Array:
		for p: Variant in s._pages:
			if p is Dictionary:
				out.append({"name": str(p.get("name", "Page")), "items": HudWidgets.clean(p.get("items"), HudWidgets.PAGE_GRID, page_cell())})
	if out.is_empty():
		for p: Dictionary in HudWidgets.DEFAULT_PAGES:
			out.append({"name": p.name, "items": HudWidgets.clean(p.items, HudWidgets.PAGE_GRID, page_cell())})
	return out


## A sheet page's cell in pixels.
func page_cell() -> Vector2:
	var area := pages.grid_rect().size if pages != null else (size if size.x > 0 else get_viewport_rect().size) * Vector2(0.72, 0.78)
	return area / Vector2(HudWidgets.PAGE_GRID)


## May this user change the active one's layouts (owners, the DM)?
func may_edit() -> bool:
	return active != "" and bool((table.sheets.get(active, {}) as Dictionary).get("_editable", false))


## F2: edit mode on (TASK-78): one editor for the HUD and the sheet pages, on the page that
## is open, else on the HUD. In it, 1-9 switch pages (the same key again: the HUD), F2 ends it.
func edit() -> void:
	open_editor(pages.current + 1 if pages != null and pages.visible else 0)


## The editor on the HUD.
func edit_hud() -> void:
	open_editor(0)


## The editor on the sheet page shown (else the first).
func edit_pages() -> void:
	open_editor(1 + (pages.current if pages != null and pages.visible else 0))


## The editor: set 0 is the HUD (the screen behind it, shown smaller), then the pages (paper).
func open_editor(at := 0) -> void:
	if not may_edit() or editor != null:
		return
	var screen := size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	var page_canvas := pages.grid_rect().size if pages != null else screen * Vector2(0.72, 0.78)
	var sets: Array = [{"name": "HUD", "items": layout(), "home": true, "grid": HudWidgets.HUD_GRID, "canvas": screen, "backdrop": true}]
	for p: Dictionary in page_list():
		sets.append({"name": p.name, "items": p.items, "grid": HudWidgets.PAGE_GRID, "canvas": page_canvas, "backdrop": false})
	var ed := LayoutEditor.new()
	ed.multi = true
	ed.sets = sets
	ed.current = clampi(at, 0, sets.size() - 1)
	ed.sheet = table.sheets.get(active, {})
	ed.hud = self
	_show_behind(ed.current)
	ed.set_shown.connect(_show_behind)
	_open_editor(ed)


## Behind the editor: the page being edited, or nothing for the HUD.
func _show_behind(index: int) -> void:
	if pages == null:
		return
	if index <= 0:
		pages.close()
	else:
		pages.open(index - 1)


func _open_editor(ed: LayoutEditor) -> void:
	editor = ed
	var ref := active
	var hud_before: Array = layout().duplicate(true)
	var pages_before: Array = page_list().duplicate(true)
	ed.finished.connect(func(sets: Array, saved: bool) -> void:
		editor = null
		if saved:
			var s: Dictionary = table.sheets.get(ref, {})
			var new_hud: Array = []
			var new_pages: Array = []
			for one: Dictionary in sets:
				if bool(one.get("home", false)):
					new_hud = one.items
				else:
					new_pages.append({"name": str(one.get("name", "Page")), "items": one.items})
			if new_hud != hud_before:
				s["_hud"] = new_hud  # right away; the table confirms
				table.save_layout(ref, "hud", new_hud)
			if new_pages != pages_before:
				s["_pages"] = new_pages
				table.save_layout(ref, "sheet_pages", new_pages)
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
## rolls (NetTable.use_action); a spell is cast through cast_menu (TASK-49).
func use_quick(kind: String, ref: String) -> void:
	if active == "" or table == null or editor != null:
		return
	if kind == "check":
		roll_check(ref)
	elif kind == "spell":
		cast_menu(ref)
	else:
		table.use_action(active, ref)


var _waiting_entry := ""  ## a player asked the host for this entry's view (TASK-109)


## Opens a spell's, item's or feature's view in a window (TASK-109: a double-click in a sheet
## list). Package entries are read here; a player asks the host for the timeline's own.
func show_entry(ref: String) -> void:
	if table == null or ref == "":
		return
	var e := table.lookup_entry(ref)
	if not e.is_empty():
		EntryWindow.show_for(self, ref, e)
		return
	if table.is_dm() or not table.is_online():
		return
	_waiting_entry = ref
	if not table.entry_received.is_connected(_on_entry_received):
		table.entry_received.connect(_on_entry_received)
	table.open_entry(ref)


func _on_entry_received(ref: String) -> void:
	if ref != _waiting_entry or not table.entries.get(ref) is Dictionary:
		return
	_waiting_entry = ""
	var e: Dictionary = (table.entries[ref] as Dictionary).duplicate()
	if not e.has("_kind"):
		e["_kind"] = NetTable.entry_kind(ref)
	EntryWindow.show_for(self, ref, e)


var cast_popup: PopupMenu

## Casting a spell (TASK-49): a cantrip at once; a levelled spell at its level, or a menu of
## the levels with slots (upcast) and "as a ritual" when there is a choice.
func cast_menu(spell: String) -> PopupMenu:
	var s: Dictionary = table.sheets.get(active, {})
	var info: Dictionary = (s.get("_refs", {}) as Dictionary).get(spell, {}) if s.get("_refs") is Dictionary else {}
	var base := int(info.get("level", 0))
	var options := []  # [label, level, ritual]
	if base > 0:
		var slots := Rules.slots(s)
		for lvl in range(base, slots.size() + 1):
			var left := int(slots[lvl - 1]) - Replay.slots_used(s, lvl)
			if int(slots[lvl - 1]) > 0 and (left > 0 or lvl == base):
				options.append(["Level %d%s (%d left)" % [lvl, " (upcast)" if lvl > base else "", maxi(left, 0)], lvl, false])
		if bool(info.get("ritual", false)):
			options.append(["As a ritual (no slot, +10 minutes)", base, true])
	if options.size() <= 1:
		table.cast(active, spell, base)
		return null
	if cast_popup != null:
		cast_popup.queue_free()
	cast_popup = PopupMenu.new()
	cast_popup.name = "CastMenu"
	add_child(cast_popup)
	for i in options.size():
		cast_popup.add_item(str(options[i][0]), i)
	var who := active
	cast_popup.id_pressed.connect(func(i: int) -> void: table.cast(who, spell, int(options[i][1]), bool(options[i][2])))
	cast_popup.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))
	return cast_popup


## Spent spell slots of a level, `spent` in all: resource.used / resource.restored
## "spell_slots.<level>" for the difference (TASK-51).
func use_slots(level: int, spent: int) -> void:
	if active == "":
		return
	var delta := spent - Replay.slots_used(table.sheets.get(active, {}), level)
	if delta != 0:
		table.use_resource(active, "spell_slots.%d" % level, delta)


## Spell slots per level (level 1 first): Rules.slots (TASK-53).
static func spell_slots(s: Dictionary) -> Array:
	return Rules.slots(s)




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
