class_name TableUI
extends CanvasLayer
## The screens around the shared table (TASK-8/14): the start screen (host a campaign as
## DM, or join with a name and address), the character picker for players, a top bar with
## the status (the DM also picks the map there) and the session notes on the right.

const PC_CARD := Vector2(150, 190)

var table: NetTable

var _lobby: Control
var _campaign: LineEdit
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

var _notes_panel: PanelContainer
var _notes_title: Label
var _notes_text: RichTextLabel
var _note_edit: TextEdit
var _next_session: Button


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UISkin.theme()
	add_child(root)
	_build_bar(root)
	_build_notes(root)
	_build_picker(root)
	_build_lobby(root)
	table.status_changed.connect(_on_status)
	table.pcs_changed.connect(_refresh)
	table.notes_changed.connect(_show_notes)
	table.table_changed.connect(_refresh)
	_refresh()
	_show_notes()


func _refresh() -> void:
	var online := table.is_online()
	var dm := table.is_dm()
	_lobby.visible = not online
	_bar.visible = online
	_notes_panel.visible = online
	_next_session.visible = dm
	_maps.visible = dm
	var picking := online and not dm and table.my_pc == "" and not table.pc_choices.is_empty()
	_picker.visible = picking
	if picking:
		_fill_picker()
	if dm and _maps.item_count != table.campaign.maps().size():
		_maps.clear()
		for id in table.campaign.maps():
			_maps.add_item(table.campaign.name_of(id))
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
	_campaign = _field(host, "Campaign folder", table.campaign_dir)
	_campaign.placeholder_text = "empty = the example campaign"
	_port = _field(host, "Port", str(NetTable.DEFAULT_PORT))
	var host_button := Button.new()
	host_button.text = "Host as DM"
	host_button.pressed.connect(func() -> void:
		table.campaign_dir = _campaign.text.strip_edges()
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


# --- Top bar ---------------------------------------------------------------------------------

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
	_status = Label.new()
	_status.custom_minimum_size = Vector2(320, 0)
	_status.theme_type_variation = UISkin.V_MUTED
	row.add_child(_status)


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
	_notes_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_text.scroll_following = true
	_notes_text.selection_enabled = true
	col.add_child(_notes_text)
	_note_edit = TextEdit.new()
	_note_edit.placeholder_text = "Write a note (markdown)... Ctrl+Enter adds it"
	_note_edit.custom_minimum_size = Vector2(0, 90)
	_note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and event.ctrl_pressed:
			_submit_note()
			_note_edit.accept_event())
	col.add_child(_note_edit)
	var add := Button.new()
	add.text = "Add note"
	add.size_flags_horizontal = Control.SIZE_SHRINK_END
	add.pressed.connect(_submit_note)
	col.add_child(add)


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
