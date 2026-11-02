class_name TableUI
extends CanvasLayer
## The screens around the shared table (TASK-8/14): the start screen (host a timeline as
## DM, or join with a name and address; in the app the App's StartScreen does that instead,
## `lobby` = false), the character picker for players, a top bar with the status (the DM also
## picks the map there) and the session notes on the right.

const PC_CARD := Vector2(150, 190)

var table: NetTable
## Show the built-in start screen when offline (scenes/table.tscn); the app has its own.
var lobby := true
## Called by the Compendium button instead of opening the overlay (the app switches views).
var compendium_opener := Callable()
## Packages folder ("" = data/packages).
var packages_root := ""
var map_drop: MapDrop  ## takes compendium entries dragged onto the map (TASK-37)
var map_setup: MapSetup
var _new_map_button: Button
var _grid_button: Button
var _combat_button: Button
var _turn_button: Button
var _root: Control

var _lobby: Control
var _timeline: LineEdit
var _port: LineEdit
var _name: LineEdit
var _address: LineEdit
var _lobby_status: Label

var _picker: Control
var _picker_cards: HFlowContainer

var _bar: PanelContainer
var _status: Label
var _maps: OptionButton
var _who: Label
var _color: ColorPickerButton
var _book_button: Button
var _book: Compendium
var sheet: SheetPanel
var hud: CharacterHud  ## the active character, lower left (TASK-44)
var chat: ChatBox  ## the chat on the right of the calm table (TASK-46)
var timeline_bar: TimelineBar  ## the moments of the timeline, at the top (TASK-82)
## DM: show these events of a moment in the Timeline list (the app opens it).
var timeline_list_opener := Callable()
var minimal := false  ## the app's calm table: no bar at the top (App.minimal)
var dock: Dock  ## the app's panels (TASK-37); null when the table runs on its own

var _notes_panel: PanelContainer
var _notes_title: Label
var _notes_text: RichTextLabel
var _note_edit: TextEdit
var _next_session: Button
var _rolls_text: RichTextLabel
var roll_edit: LineEdit
var _roll_hidden: CheckBox
var condition_menu: PopupMenu  ## a creature's conditions to tick (TASK-56)
var tracker: CombatTracker  ## the initiative order while a combat runs (TASK-58)
var attack_bar: PanelContainer  ## picking targets for an attack (TASK-54)
var dice_tray: DiceTray  ## 3D dice over the table (TASK-61)
var _area_button: Button
var attack := {}  ## {ref, query, multi, targets: []} while picking
var _attack_label: Label
var _cover: OptionButton
var _adv: OptionButton
var _menu_ref := ""


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UISkin.theme()
	add_child(root)
	_root = root
	map_drop = MapDrop.new()
	map_drop.name = "MapDrop"
	map_drop.table = table
	root.add_child(map_drop)
	dice_tray = DiceTray.new()  # over the map, under the panels
	dice_tray.table = table
	root.add_child(dice_tray)
	_build_bar(root)
	_build_notes(root)
	sheet = SheetPanel.new()
	sheet.table = table
	root.add_child(sheet)
	table.sheet_received.connect(func(ref: String) -> void:
		if table.sheet_wanted(ref) or (sheet.visible and sheet.ref == ref):
			sheet.show_sheet(table.sheets[ref]))
	hud = CharacterHud.new()
	hud.table = table
	root.add_child(hud)
	chat = ChatBox.new()
	chat.table = table
	chat.active_ref = func() -> String: return hud.active
	chat.visible = false
	root.add_child(chat)
	timeline_bar = TimelineBar.new()
	timeline_bar.visible = false
	root.add_child(timeline_bar)
	timeline_bar.follow(table.timeline_sync, table.notes.calendar)
	table.calendar_changed.connect(apply_calendar)
	timeline_bar.cursor_changed.connect(func(at: int) -> void:  # the table follows in real time
		var seg := timeline_bar.segment()
		table.look_back(int(seg.upto), at, int(seg.toward), float(seg.f))
		chat.follow_time(timeline_bar.happened()))
	timeline_bar.show_toggled.connect(func(on: bool) -> void: table.show_everyone(on))
	timeline_bar.time_requested.connect(func(minutes: int, reason: String) -> void: table.advance_clock(minutes, reason))
	timeline_bar.rewind_requested.connect(func(upto: int, minutes: int) -> void:  # TASK-86
		table.rewind_to(upto)
		if minutes > 0:  # the current time where the DM let go
			table.advance_clock(minutes, "")
		timeline_bar.line.set_cursor(-1))
	timeline_bar.restore_requested.connect(func(id: int) -> void: table.restore(id))
	table.showing_changed.connect(func() -> void:
		timeline_bar.set_showing(table.showing, table.is_dm())
		if not table.is_dm():
			timeline_bar.line.set_cursor(table.looking_at))
	table.past_changed.connect(func() -> void: hud.set_locked(table.looking_back >= 0))
	timeline_bar.list_requested.connect(func(ids: Array) -> void:
		if table.is_dm() and timeline_list_opener.is_valid():
			timeline_list_opener.call(ids))
	hud.pages = SheetPages.new()  # above the chat (TASK-47)
	hud.pages.hud = hud
	root.add_child(hud.pages)
	_build_attack_bar(root)
	tracker = CombatTracker.new()
	tracker.table = table
	root.add_child(tracker)
	_build_picker(root)
	_build_lobby(root)
	table.status_changed.connect(_on_status)
	table.pcs_changed.connect(_refresh)
	table.notes_changed.connect(_show_notes)
	table.table_changed.connect(_refresh)
	table.accounts_changed.connect(_refresh)
	table.rolls_changed.connect(_show_rolls)
	table.condition_menu_requested.connect(func(ref: String) -> void: open_condition_menu(ref))
	table.attack_requested.connect(begin_attack)
	table.area_placed.connect(_on_area_placed)
	table.concentration_confirm.connect(confirm_concentration)
	table.grid.token_clicked.connect(_on_target_clicked)
	RollTables.resolver = func(id: String) -> Dictionary: return table.tables.get(id, {})
	RollTables.roller = func(id: String, hidden: bool) -> void: table.roll_table(id, hidden and table.is_dm())
	RollTables.formula_roller = func(formula: String) -> void: table.roll(formula, roll_ref(), _roll_hidden.button_pressed)
	RollTables.event_log = null
	RollTables.hub.changed.connect(func(id: String) -> void:
		if table.notes.entries.any(func(e: Dictionary) -> bool: return RollTables.embeds(str(e.get("text", "")), id)):
			_show_notes()
		if sheet.visible and RollTables.embeds(str(sheet.sheet.get("description", "")), id):
			sheet.show_sheet(sheet.sheet))
	_refresh()
	_show_notes()


## The table's calendar was replaced (hosting a world, the DM's edit): the timeline bar
## shows its dates (Nico 2026-11-02).
func apply_calendar() -> void:
	timeline_bar.follow(table.timeline_sync, table.notes.calendar)


func _refresh() -> void:
	var online := table.is_online()
	var dm := table.is_dm()
	_lobby.visible = lobby and not online
	_bar.visible = online and not minimal
	_notes_panel.visible = online
	chat.visible = online and minimal  # the app's calm table; otherwise the session panel has the rolls
	timeline_bar.visible = online
	timeline_bar.show_button.visible = dm
	timeline_bar.dm = dm
	timeline_bar.line.can_extend = dm  # the DM drags into the future to pass time
	if not online:
		sheet.hide()
	_next_session.visible = dm
	_roll_hidden.visible = dm
	_maps.visible = dm
	_book_button.visible = dm
	_new_map_button.visible = dm
	_grid_button.visible = dm
	var fighting := dm and table.in_combat()
	_combat_button.visible = dm
	if _map_tools != null:
		_map_tools.visible = dm  # TASK-73
	_combat_button.text = "End combat" if fighting else "Start combat"
	if not fighting and table.is_dm():  # TASK-72: how hard the fight on this map would be
		var diff := table.encounter_difficulty()
		if str(diff.get("rating", "none")) != "none":
			_combat_button.text = "Start combat (%s)" % str(diff.rating).capitalize()
			_combat_button.tooltip_text = "XP %d (adjusted %d) · %s" % [int(diff.xp), int(diff.adjusted), " · ".join(PackedStringArray((diff.thresholds as Dictionary).keys().map(func(k: String) -> String: return "%s %d" % [k, int(diff.thresholds[k])])))]
	_turn_button.visible = fighting
	var picking := online and not dm and table.my_pc == "" and not table.pc_choices.is_empty()
	_picker.visible = picking
	if picking:
		_fill_picker()
	if dm and _maps.item_count != table.timeline.maps().size():
		_maps.clear()
		for id in table.timeline.maps():
			_maps.add_item(table.timeline.name_of(id))
			_maps.set_item_metadata(_maps.item_count - 1, id)
	if dm:
		for i in _maps.item_count:
			if _maps.get_item_metadata(i) == table.map_id:
				_maps.select(i)
	var me := table.player_name
	if dm:
		me = "DM"
	elif table.my_pc != "":
		me = "%s · %s" % [table.notes.names.get(table.my_player, table.player_name), _pc_name(table.my_pc)]
	_who.text = me
	var mine: Dictionary = table.accounts.get(table.my_account(), {})
	_color.visible = not mine.is_empty()
	if mine.has("color") and Color.html_is_valid(str(mine.color)):
		_color.color = Color.html(str(mine.color))


func _pc_name(id: String) -> String:
	for c: Dictionary in table.pc_choices:
		if c.id == id:
			return str(c.name)
	return id


func _on_status(text: String) -> void:
	_status.text = text
	_lobby_status.text = text
	_refresh()


# --- Start screen ------------------------------------------------------------------------

func _build_lobby(root: Control) -> void:
	_lobby = PanelContainer.new()
	_lobby.theme_type_variation = UISkin.V_COVER
	_lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_lobby)
	var center := CenterContainer.new()
	_lobby.add_child(center)
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	center.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	page.add_child(col)
	var plate := PanelContainer.new()
	plate.theme_type_variation = UISkin.V_PLATE
	col.add_child(plate)
	var title := Label.new()
	title.text = "Dragoon"
	title.theme_type_variation = UISkin.V_PLATE_LABEL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	col.add_child(row)

	var host := _form(row, "Host a session (DM)")
	_timeline = _field(host, "Timeline folder", table.timeline_dir)
	_timeline.placeholder_text = "empty = the example timeline (Westmarch: Red Fang)"
	_port = _field(host, "Port", str(NetTable.DEFAULT_PORT))
	var host_button := Button.new()
	host_button.text = "Host as DM"
	host_button.pressed.connect(func() -> void:
		table.timeline_dir = _timeline.text.strip_edges()
		table.host(int(_port.text) if _port.text.is_valid_int() else NetTable.DEFAULT_PORT))
	host.add_child(host_button)

	var join := _form(row, "Join a session")
	_name = _field(join, "Your player name", table.player_name)
	_address = _field(join, "Address (ip:port)", "127.0.0.1:%d" % NetTable.DEFAULT_PORT)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(func() -> void: table.join(_address.text, _name.text))
	join.add_child(join_button)
	_address.text_submitted.connect(func(_t: String) -> void: table.join(_address.text, _name.text))

	_lobby_status = Label.new()
	_lobby_status.theme_type_variation = UISkin.V_MUTED
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_lobby_status)


func _form(parent: Control, heading: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var h := Label.new()
	h.text = heading
	h.theme_type_variation = UISkin.V_HEADING
	box.add_child(h)
	return box


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	l.theme_type_variation = UISkin.V_MUTED
	parent.add_child(l)
	var edit := LineEdit.new()
	edit.text = value
	parent.add_child(edit)
	return edit


# --- Character picker ----------------------------------------------------------------------

func _build_picker(root: Control) -> void:
	_picker = ColorRect.new()
	(_picker as ColorRect).color = Color(UISkin.WINE.darkened(0.5), 0.65)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_picker)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(center)
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	page.custom_minimum_size = Vector2(560, 0)
	center.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	var h := Label.new()
	h.text = "Pick your character"
	h.theme_type_variation = UISkin.V_HEADING
	col.add_child(h)
	_picker_cards = HFlowContainer.new()
	_picker_cards.add_theme_constant_override("h_separation", 12)
	_picker_cards.add_theme_constant_override("v_separation", 12)
	col.add_child(_picker_cards)


func _fill_picker() -> void:
	for c in _picker_cards.get_children():
		c.queue_free()
	for pc: Dictionary in table.pc_choices:
		var taken: String = pc.get("taken_by", "")
		var card := Button.new()
		card.custom_minimum_size = PC_CARD
		card.theme_type_variation = UISkin.V_CARD
		card.disabled = taken != ""
		card.tooltip_text = "Played by %s" % taken if taken != "" else "Play %s" % pc.name
		card.pressed.connect(table.claim_pc.bind(str(pc.id)))
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(box)
		var art := TextureRect.new()
		art.texture = table.assets.texture(str(pc.get("image", "")))
		art.custom_minimum_size = Vector2(96, 96)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.modulate.a = 0.4 if taken != "" else 1.0
		box.add_child(art)
		for line: String in [str(pc.name), str(pc.get("class", "")), ("taken by %s" % taken) if taken != "" else ""]:
			if line == "":
				continue
			var l := Label.new()
			l.text = line
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.theme_type_variation = UISkin.V_MUTED if line != str(pc.name) else &""
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(l)
		_picker_cards.add_child(card)


# --- Concentration (TASK-59) ---------------------------------------------------------------------

var concentration_dialog: ConfirmationDialog

## A second concentration spell: ends the first one, after a yes.
func confirm_concentration(ref: String, old_name: String, new_name: String, go: Callable) -> void:
	if concentration_dialog != null:
		concentration_dialog.queue_free()
	concentration_dialog = ConfirmationDialog.new()
	concentration_dialog.name = "ConcentrationConfirm"
	concentration_dialog.title = "Concentration"
	concentration_dialog.dialog_text = "%s is concentrating on %s.\nCasting %s ends it. Go on?" % [table.timeline.name_of(ref) if table.timeline != null else ref, old_name, new_name]
	concentration_dialog.ok_button_text = "End %s" % old_name
	concentration_dialog.confirmed.connect(func() -> void: go.call())
	_root.add_child(concentration_dialog)
	concentration_dialog.popup_centered()


# --- Attacks (TASK-54) -----------------------------------------------------------------------

func _build_attack_bar(root: Control) -> void:
	attack_bar = PanelContainer.new()
	attack_bar.name = "AttackBar"
	attack_bar.theme_type_variation = UISkin.V_PAGE
	attack_bar.anchor_left = 0.5
	attack_bar.anchor_right = 0.5
	attack_bar.anchor_top = 1.0
	attack_bar.anchor_bottom = 1.0
	attack_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	attack_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	attack_bar.offset_bottom = -12
	attack_bar.visible = false
	root.add_child(attack_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	attack_bar.add_child(row)
	_attack_label = Label.new()
	_attack_label.name = "What"
	row.add_child(_attack_label)
	_cover = OptionButton.new()
	_cover.name = "Cover"
	for c: Array in [["No cover", ""], ["Half cover +2", "half"], ["Three-quarters +5", "three_quarters"]]:
		_cover.add_item(c[0])
		_cover.set_item_metadata(_cover.item_count - 1, c[1])
	_cover.tooltip_text = "The targets' cover (a toggle; nothing is measured)"
	row.add_child(_cover)
	_adv = OptionButton.new()
	_adv.name = "Advantage"
	for c: Array in [["Conditions decide", 2], ["Normal", 0], ["Advantage", 1], ["Disadvantage", -1]]:
		_adv.add_item(c[0])
		_adv.set_item_metadata(_adv.item_count - 1, c[1])
	_adv.tooltip_text = "Conditions preselect advantage or disadvantage; pick one to decide yourself"
	row.add_child(_adv)
	_area_button = Button.new()  # TASK-67: the spell's area: its tokens become the targets
	_area_button.name = "PlaceArea"
	_area_button.text = "Place area"
	_area_button.tooltip_text = "Put the area on the map; the creatures in it become the targets (click one to add or drop it)"
	_area_button.pressed.connect(func() -> void:
		var a: Dictionary = (attack.get("opts", {}) as Dictionary).get("area", {})
		if not a.is_empty():
			table.grid.areas.start_place(str(a.get("shape", "sphere")), float(a.get("size_m", 6)), float(a.get("width_m", 1.5))))
	row.add_child(_area_button)
	var go := Button.new()
	go.name = "Roll"
	go.text = "Roll"
	go.pressed.connect(roll_attack)
	row.add_child(go)
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Cancel"
	cancel.pressed.connect(cancel_attack)
	row.add_child(cancel)


## Starts an attack of `ref`: click the targets on the map (a second click drops one), then
## Roll. A creature's Multiattack (`multi`) rolls its listed attacks in a row.
func begin_attack(ref: String, query: String, multi := false, kind := "attack", opts := {}) -> void:
	cancel_attack()
	attack = {"ref": ref, "query": query, "multi": multi, "targets": [], "kind": kind, "opts": opts}
	_adv.visible = kind == "attack"  # a save: the targets' own conditions decide
	_area_button.visible = not ((opts.get("area", {}) as Dictionary).is_empty())
	attack_bar.visible = true
	_update_attack_label()


func _on_target_clicked(entity: String) -> void:
	if attack.is_empty() or entity == str(attack.ref) or not "/" in entity:
		return
	_toggle_target(entity)
	_update_attack_label()


## An area placed while picking targets: the creatures in it are the targets (TASK-67).
func _on_area_placed(t: Dictionary) -> void:
	if attack.is_empty():
		return
	for id: Variant in (attack.targets as Array).duplicate():
		_toggle_target(str(id))
	for id: String in AreaLayer.tokens_in(t, table.grid):
		if id != str(attack.ref) and "/" in id:
			_toggle_target(id)
	_update_attack_label()


func _toggle_target(id: String) -> void:
	var list: Array = attack.targets
	if id in list:
		list.erase(id)
	else:
		list.append(id)
	table.grid.set_targeted(id, id in list)


func _update_attack_label() -> void:
	var what := "Multiattack" if bool(attack.get("multi", false)) else HudWidgets._name_of(str(attack.get("query", ""))).capitalize()
	var n: int = (attack.get("targets", []) as Array).size()
	_attack_label.text = "%s: %s" % [what, "click the targets on the map" if n == 0 else "%d target%s" % [n, "" if n == 1 else "s"]]
	var reach := float((attack.get("opts", {}) as Dictionary).get("range_m", 0))  # TASK-67: a warning, nothing is blocked
	if reach > 0:
		var far := (attack.get("targets", []) as Array).filter(func(id: Variant) -> bool: return table.distance_m(str(attack.ref), str(id)) > reach + 0.01).size()
		if far > 0:
			_attack_label.text += "  (%d out of range: %s m)" % [far, MovePlans._num(reach)]


## Rolls the attack at the picked targets (cover and advantage as chosen on the bar).
func roll_attack() -> void:
	if attack.is_empty() or (attack.targets as Array).is_empty():
		return
	var opts: Dictionary = (attack.get("opts", {}) as Dictionary).duplicate()  # a spell's slot level (TASK-49)
	opts.merge({"cover": str(_cover.get_item_metadata(_cover.selected)), "multi": bool(attack.multi)}, true)
	var adv := int(_adv.get_item_metadata(_adv.selected))
	if adv != 2:
		opts["advantage"] = adv
	if str(attack.get("kind", "attack")) == "save":
		opts.erase("multi")
		table.save_action(str(attack.ref), str(attack.query), (attack.targets as Array).duplicate(), opts)
	else:
		table.attack(str(attack.ref), str(attack.query), (attack.targets as Array).duplicate(), opts)
	cancel_attack()


func cancel_attack() -> void:
	for id: Variant in attack.get("targets", []):
		table.grid.set_targeted(str(id), false)
	attack = {}
	if attack_bar != null:
		attack_bar.visible = false


# --- Conditions (TASK-56) -------------------------------------------------------------------

const _EXHAUSTION_UP := 1000
const _EXHAUSTION_DOWN := 1001

## The conditions of `ref` to tick and untick (the DM, or the player whose sheet it is), at
## the mouse. The rules text of the world's edition is each one's tooltip. null if not allowed.
func open_condition_menu(ref: String, at := Vector2(-1, -1)) -> PopupMenu:
	if ref == "" or not table.may_change(ref):
		return null
	if condition_menu == null:
		condition_menu = PopupMenu.new()
		condition_menu.name = "ConditionMenu"
		condition_menu.hide_on_checkable_item_selection = false
		condition_menu.id_pressed.connect(_on_condition_picked)
		_root.add_child(condition_menu)
	_menu_ref = ref
	var now := table.conditions_of(ref)
	var edition := str(table.rules_settings().get("edition", "2014"))
	var m := condition_menu
	m.clear()
	m.add_separator(table.timeline.name_of(ref) if table.is_dm() and table.timeline != null else "Conditions")
	var ids: Array = Rules.conditions().keys().filter(func(id: String) -> bool:
		return id != "exhaustion" and (id == "dead" or not bool(Rules.conditions()[id].get("marker", false))))
	ids.sort()
	for i in ids.size():
		var c := Rules.condition(ids[i], edition)
		m.add_check_item(str(c.name), i)
		m.set_item_metadata(m.item_count - 1, ids[i])
		m.set_item_checked(m.item_count - 1, ids[i] in now.conditions)
		m.set_item_tooltip(m.item_count - 1, str(c.text))
	m.add_separator()
	var level: int = now.exhaustion if "exhaustion" in now.conditions else 0
	m.add_item("Exhaustion +1  (now %d)" % level, _EXHAUSTION_UP)
	m.set_item_tooltip(m.item_count - 1, str(Rules.condition("exhaustion", edition, maxi(level + 1, 1)).text))
	m.add_item("Exhaustion -1", _EXHAUSTION_DOWN)
	m.set_item_disabled(m.item_count - 1, level == 0)
	var pos := at if at.x >= 0 else _root.get_viewport().get_mouse_position()
	m.popup(Rect2i(Vector2i(pos), Vector2i.ZERO))
	return m


func _on_condition_picked(id: int) -> void:
	var ref := _menu_ref
	var now := table.conditions_of(ref)
	var level: int = now.exhaustion if "exhaustion" in now.conditions else 0
	if id == _EXHAUSTION_UP:
		table.set_condition(ref, "exhaustion", true, mini(level + 1, 6))
		condition_menu.hide()
		return
	if id == _EXHAUSTION_DOWN:
		table.set_condition(ref, "exhaustion", level > 1, level - 1)
		condition_menu.hide()
		return
	var index := condition_menu.get_item_index(id)
	var cond := str(condition_menu.get_item_metadata(index))
	var on := not condition_menu.is_item_checked(index)
	condition_menu.set_item_checked(index, on)
	table.set_condition(ref, cond, on)


# --- Top bar ---------------------------------------------------------------------------------

## The DM's map tools (TASK-73): [label, id, MapLayer mode].
const MAP_TOOLS := [["Draw walls (click corners, Esc ends)", 1, "wall"], ["Draw doors (two corners)", 2, "door"],
	["Erase walls (click one)", 3, "erase"], ["Difficult terrain (click or drag)", 4, "terrain"], ["Lights (click: add / remove)", 5, "light"]]
var _map_tools: MenuButton
const AREA_PRESETS := [["Sphere 6 m (radius)", "sphere", 6.0, 0.0], ["Sphere 3 m", "sphere", 3.0, 0.0], ["Cone 4.5 m", "cone", 4.5, 0.0],
	["Cone 9 m", "cone", 9.0, 0.0], ["Line 9 m × 1.5 m", "line", 9.0, 1.5], ["Line 30 m × 1.5 m", "line", 30.0, 1.5],
	["Cube 3 m", "cube", 3.0, 0.0], ["Cube 6 m", "cube", 6.0, 0.0], ["Cylinder 6 m", "cylinder", 6.0, 0.0]]

func _build_bar(root: Control) -> void:
	_bar = PanelContainer.new()
	_bar.theme_type_variation = UISkin.V_PAGE
	_bar.position = Vector2(12, 40)
	root.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_bar.add_child(row)
	_who = Label.new()
	_who.theme_type_variation = UISkin.V_HEADING
	row.add_child(_who)
	_maps = OptionButton.new()
	_maps.tooltip_text = "Show another map to everyone"
	_maps.item_selected.connect(func(i: int) -> void: table.show_map_to_all(str(_maps.get_item_metadata(i))))
	row.add_child(_maps)
	_new_map_button = _bar_button(row, "New map...", "Add a map picture to the world and line up its grid", pick_map_picture)
	_grid_button = _bar_button(row, "Grid...", "Line up the grid of this map (drag over one square)", func() -> void: setup_map())
	_combat_button = _bar_button(row, "Start combat", "Start or end a combat on this map; an ended combat is saved as an encounter", func() -> void:
		if table.in_combat():
			table.end_combat()
		else:
			table.start_combat()
		_refresh())
	_combat_button.name = "Combat"
	_turn_button = _bar_button(row, "Next turn", "The next creature's turn (a new round after the last)", func() -> void: table.next_turn())
	_turn_button.name = "NextTurn"
	var tools := MenuButton.new()  # TASK-73: walls, doors, terrain, light, fog (DM)
	tools.name = "MapTools"
	tools.text = "Map"
	tools.flat = false
	tools.tooltip_text = "Walls, doors, difficult terrain, lights, lighting and fog of war of this map"
	for item: Array in MAP_TOOLS:
		tools.get_popup().add_item(str(item[0]), int(item[1]))
	tools.get_popup().add_separator()
	tools.get_popup().add_check_item("Fog of war", 20)
	tools.get_popup().add_radio_check_item("Lighting: bright", 21)
	tools.get_popup().add_radio_check_item("Lighting: dim", 22)
	tools.get_popup().add_radio_check_item("Lighting: dark", 23)
	tools.get_popup().about_to_popup.connect(func() -> void:
		var m := table.timeline.entry(table.map_id) if table.timeline != null else {}
		var p := tools.get_popup()
		p.set_item_checked(p.get_item_index(20), bool(m.get("fog", false)))
		for k: int in [21, 22, 23]:
			p.set_item_checked(p.get_item_index(k), str(m.get("lighting", "bright")) == ["bright", "dim", "dark"][k - 21]))
	tools.get_popup().id_pressed.connect(func(id: int) -> void:
		if id < 20:
			table.grid.map_layer.start(str(MAP_TOOLS.filter(func(t: Array) -> bool: return int(t[1]) == id)[0][2]))
		elif id == 20:
			table.edit_map({"fog": not bool(table.timeline.entry(table.map_id).get("fog", false))})
		else:
			table.edit_map({"lighting": ["bright", "dim", "dark"][id - 21]}))
	row.add_child(tools)
	_map_tools = tools
	var ruler := _bar_button(row, "Ruler", "Measure on the map: drag (metres, like moving); Esc ends it", func() -> void: table.grid.areas.start_ruler())
	ruler.name = "Ruler"
	var areas := MenuButton.new()  # TASK-67: an area template, placed by hand
	areas.name = "AreaMenu"
	areas.text = "Area"
	areas.flat = false
	areas.tooltip_text = "Put an area on the map (everyone sees it); a sphere at a grid corner, the others: origin, then aim"
	for i in AREA_PRESETS.size():
		areas.get_popup().add_item(str(AREA_PRESETS[i][0]), i)
	areas.get_popup().add_separator()
	areas.get_popup().add_item("Remove my areas (DM: all)", 100)
	areas.get_popup().id_pressed.connect(func(i: int) -> void:
		if i == 100:
			table.remove_template("")
		else:
			table.grid.areas.start_place(str(AREA_PRESETS[i][1]), float(AREA_PRESETS[i][2]), float(AREA_PRESETS[i][3])))
	row.add_child(areas)
	_book_button = Button.new()
	_book_button.text = "Compendium"
	_book_button.tooltip_text = "Core, world and this timeline's entries; edit them (session edits become events)"
	_book_button.pressed.connect(func() -> void:
		if compendium_opener.is_valid():
			compendium_opener.call()
		else:
			open_compendium())
	row.add_child(_book_button)
	_color = ColorPickerButton.new()
	_color.custom_minimum_size = Vector2(36, 28)
	_color.edit_alpha = false
	_color.tooltip_text = "My color: frames around passages only some people can see"
	_color.popup_closed.connect(func() -> void: table.set_my_color(_color.color))
	row.add_child(_color)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(320, 0)
	_status.theme_type_variation = UISkin.V_MUTED
	row.add_child(_status)


func _bar_button(row: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	row.add_child(b)
	return b


## DM: pick a picture for a new map of the world.
func pick_map_picture() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Map pictures"])
	d.file_selected.connect(func(path: String) -> void:
		setup_map(path)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered_ratio(0.6)


## DM: the map setup, for a new map from `picture` or (no picture) the grid of the current
## map. Saving writes the world's maps.json and shows the map to everyone.
func setup_map(picture := "") -> MapSetup:
	if map_setup != null:
		map_setup.queue_free()
	map_setup = MapSetup.new()
	map_setup.name = "MapSetup"
	_root.add_child(map_setup)
	var world := table.timeline.world_dir
	if picture != "":
		map_setup.new_map(world, picture)
	else:
		var e := table.timeline.world_entries("maps").get(table.map_id.get_file(), {}) as Dictionary
		if e.is_empty():
			_on_status("This map isn't one of the world's maps")
			return map_setup
		map_setup.edit_map(world, e)
	map_setup.saved.connect(func(ref: String) -> void:
		table.maps_changed(ref)
		_maps.clear()  # refilled with the new map
		_refresh())
	map_setup.popup_centered(Vector2i(980, 620))
	return map_setup


## DM: the compendium over the table, with this timeline's entries and event log (TASK-6).
func open_compendium() -> Compendium:
	if _book != null:
		_book.show()
		return _book
	_book = Compendium.new()
	_book.closable = true
	_book.timeline_dir = table.timeline_dir
	_book.event_log = table.event_log
	_book.close_requested.connect(func() -> void: _book.hide())
	_bar.get_parent().add_child(_book)
	return _book


## In the app the session log (notes and rolls) and the open sheet are panels of the dock
## (TASK-37) instead of fixed boxes over the map: dockable, tabbed or in their own window.
func use_dock(d: Dock) -> void:
	dock = d
	_notes_panel.get_parent().remove_child(_notes_panel)
	d.add_panel("session", "Session", _notes_panel, "right")
	sheet.get_parent().remove_child(sheet)
	d.add_panel("sheet", "Sheet", sheet, "left")
	# The sheet shows and hides itself (a token click, its close button); its panel follows,
	# and closing the panel closes the sheet. (Only the property counts: switching tabs hides
	# the holder, not the sheet.)
	sheet.visibility_changed.connect(func() -> void:
		if not sheet.visible and d.is_shown("sheet"):
			d.hide_panel("sheet")
		elif sheet.visible and sheet.ref != "" and not d.is_shown("sheet"):
			d.show_panel("sheet"))
	d.panel_hidden.connect(func(id: String) -> void:
		if id == "sheet" and sheet.visible:
			sheet.close_sheet())


# --- Session notes ------------------------------------------------------------------------

func _build_notes(root: Control) -> void:
	_notes_panel = PanelContainer.new()
	_notes_panel.theme_type_variation = UISkin.V_PAGE
	_notes_panel.anchor_left = 1.0
	_notes_panel.anchor_right = 1.0
	_notes_panel.anchor_bottom = 1.0
	_notes_panel.offset_left = -400
	_notes_panel.offset_right = -12
	_notes_panel.offset_top = 40
	_notes_panel.offset_bottom = -12
	root.add_child(_notes_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_notes_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_notes_title = Label.new()
	_notes_title.theme_type_variation = UISkin.V_HEADING
	_notes_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_notes_title)
	_next_session = Button.new()
	_next_session.text = "Next session"
	_next_session.tooltip_text = "Start the next session (new notes file)"
	_next_session.pressed.connect(table.start_next_session)
	head.add_child(_next_session)
	_notes_text = RichTextLabel.new()
	_notes_text.bbcode_enabled = true
	_notes_text.meta_clicked.connect(func(meta: Variant) -> void: RollTables.handle_meta(str(meta)))
	_notes_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_text.custom_minimum_size = Vector2(0, 80)
	_notes_text.scroll_following = true
	_notes_text.selection_enabled = true
	col.add_child(_notes_text)
	_note_edit = TextEdit.new()
	_note_edit.placeholder_text = "Write a note (markdown)... Ctrl+Enter adds it"
	_note_edit.custom_minimum_size = Vector2(0, 70)
	_note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and event.ctrl_pressed:
			_submit_note()
			_note_edit.accept_event())
	col.add_child(_note_edit)
	# A compendium entry dropped into the note becomes a [[link]] (TASK-37).
	_note_edit.set_drag_forwarding(Callable(), func(_at: Vector2, data: Variant) -> bool: return EntryDrag.is_entry(data),
		func(_at: Vector2, data: Variant) -> void: _note_edit.insert_text_at_caret(EntryDrag.link(EntryDrag.entry_of(data))))
	RevealPopup.attach(_note_edit, func() -> Dictionary: return table.accounts,
		func(from: int, to: int, who: PackedStringArray) -> void:
			var r := Reveal.apply(_note_edit.text, from, to, who, Reveal.next_id([_note_edit.text]))
			_note_edit.text = r.text)
	var add := Button.new()
	add.text = "Add note"
	add.size_flags_horizontal = Control.SIZE_SHRINK_END
	add.pressed.connect(_submit_note)
	col.add_child(add)

	var rolls_title := Label.new()
	rolls_title.text = "Rolls"
	rolls_title.theme_type_variation = UISkin.V_HEADING
	col.add_child(rolls_title)
	_rolls_text = RichTextLabel.new()
	_rolls_text.bbcode_enabled = true
	_rolls_text.custom_minimum_size = Vector2(0, 170)
	_rolls_text.scroll_following = true
	_rolls_text.selection_enabled = true
	col.add_child(_rolls_text)
	var roll_row := HBoxContainer.new()
	col.add_child(roll_row)
	roll_edit = LineEdit.new()
	roll_edit.placeholder_text = "Perception, Dex save, Longsword, 2d6+3"
	roll_edit.tooltip_text = "Roll by name for the open sheet (or your PC), or a formula; add \"with advantage\" / \"dis\""
	roll_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_edit.text_submitted.connect(func(_t: String) -> void: _submit_roll())
	roll_row.add_child(roll_edit)
	_roll_hidden = CheckBox.new()
	_roll_hidden.text = "Hidden"
	_roll_hidden.tooltip_text = "Only you (the DM) see this roll"
	roll_row.add_child(_roll_hidden)
	var roll_button := Button.new()
	roll_button.text = "Roll"
	roll_button.pressed.connect(_submit_roll)
	roll_row.add_child(roll_button)


## Rolls the roll box: for the open sheet if it is mine to roll (my PC, the DM: any), else
## my PC / a plain formula.
func _submit_roll() -> void:
	var text := roll_edit.text.strip_edges()
	if text == "":
		return
	table.roll(text, roll_ref(), _roll_hidden.button_pressed)
	roll_edit.text = ""


## Who the roll box rolls for: the open sheet if I may roll for it.
func roll_ref() -> String:
	if sheet.visible and bool(sheet.sheet.get("_editable", false)):
		return sheet.ref
	return ""


func _show_rolls() -> void:
	var parts := PackedStringArray()
	for r: Dictionary in table.rolls:
		parts.append(NetTable.roll_bbcode(r, table.notes.names))
	_rolls_text.text = "\n".join(parts) if not parts.is_empty() else "[color=#%s]No rolls yet.[/color]" % Markdown.MUTED.to_html(false)


func _submit_note() -> void:
	table.add_note(_note_edit.text)
	_note_edit.text = ""


func _show_notes() -> void:
	var notes := table.notes
	_notes_title.text = "Notes · %s" % ("between sessions" if notes.session <= 0 else "Session %d" % notes.session)
	var parts := PackedStringArray()
	var muted := Markdown.MUTED.to_html(false)
	for e in notes.entries:
		parts.append("[color=#%s][font_size=12]%s[/font_size][/color]\n%s" % [
			muted, Markdown.escape(notes.heading(e)), Markdown.to_bbcode(str(e.text))])
	if parts.is_empty():
		_notes_text.text = "[color=#%s]No notes yet.[/color]" % muted
	else:
		_notes_text.text = "\n\n".join(parts)
