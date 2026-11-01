class_name EntryView
extends ScrollContainer
## The full view of one compendium entry in its own tab (TASK-22): the whole width, picture,
## chips, every field and the complete Markdown text. Monsters get two columns (stat block
## and features left, picture and description right); other kinds picture + chips left,
## the full text right. Links (wikilinks, feature ids) are passed on as `link_clicked`; the
## compendium opens them in new tabs. The Edit button waits for the entity editor (TASK-21).

signal link_clicked(meta: String)
signal edit_requested(entry: Dictionary)
signal back_requested  ## the back arrow next to the title (TASK-24)
## A link middle-clicked: open it in a background tab (TASK-24).
signal link_background(meta: String)

const ART_HEIGHT := 300
const SIDE_WIDTH := 340

var entry: Dictionary
var key := ""  ## package/kind/id
var edit_button: Button
var back_button: Button
var _hovered_meta := ""
var editor: EntryEditor  ## while editing (TASK-21)


static func key_of(e: Dictionary) -> String:
	return "%s/%s/%s" % [e.get("_package", ""), e.get("_kind", ""), e.get("id", "")]


func setup(e: Dictionary) -> void:
	entry = e
	key = key_of(e)
	name = "View_" + key.validate_node_name()
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(page)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	page.add_child(box)
	box.add_child(_header(e))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	box.add_child(cols)
	var monster: bool = e.get("_kind") == "monsters"
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	cols.add_child(right)
	if monster:
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.4
		left.add_child(_text(StatBlock.monster(e, false)))
		right.add_child(_art(e))
		right.add_child(_chips(e))
		var desc := str(e.get("description", "")).strip_edges()
		if desc != "":
			right.add_child(_text(StatBlock._heading("Description").strip_edges(true, false) + StatBlock._md(desc)))
		right.add_child(_text(StatBlock._footer(e).strip_edges()))
	else:
		left.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
		left.add_child(_art(e))
		left.add_child(_chips(e))
		right.add_child(_text(StatBlock.to_bbcode(e)))


## Swaps the view for the editor (same tab); end_edit() swaps back.
func begin_edit(form: EntryEditor) -> void:
	end_edit()
	editor = form
	for c in get_children():
		c.hide()
	var page := PanelContainer.new()
	page.name = "EditPage"
	page.theme_type_variation = UISkin.V_PAGE
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(form)
	add_child(page)
	scroll_vertical = 0


func end_edit() -> void:
	if editor == null:
		return
	var page := editor.get_parent()
	remove_child(page)
	page.queue_free()
	editor = null
	for c in get_children():
		c.show()


func is_editing() -> bool:
	return editor != null


func _header(e: Dictionary) -> Control:
	var plate := PanelContainer.new()
	plate.theme_type_variation = UISkin.V_PLATE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	plate.add_child(row)
	back_button = Button.new()
	back_button.icon = Compendium.flipped(UISkin.tex("arrow_right"))
	back_button.tooltip_text = "Back to the previous tab (Alt+Left, mouse back button)"
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func() -> void: back_requested.emit())
	row.add_child(back_button)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var title := Label.new()
	title.theme_type_variation = UISkin.V_PLATE_LABEL
	title.add_theme_font_size_override("font_size", 28)
	title.text = str(e.get("name", "?"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var sub := Label.new()
	sub.text = "%s  ·  %s" % [CardData.subtitle(e), e.get("_package_name", "")]
	sub.add_theme_color_override("font_color", UISkin.TAN)
	sub.add_theme_font_size_override("font_size", 14)
	col.add_child(sub)
	edit_button = Button.new()
	edit_button.text = "Edit"
	edit_button.tooltip_text = "Edit this entry here (source packages: edit a copy or unlock)"
	edit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit_button.pressed.connect(func() -> void: edit_requested.emit(entry))
	row.add_child(edit_button)
	return plate


func _art(e: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.theme_type_variation = UISkin.V_CARD
	var art := CardArt.new()
	art.custom_minimum_size = Vector2(0, ART_HEIGHT)
	art.show_entry(e)
	frame.add_child(art)
	var b := CardData.badge(e)
	if not b.is_empty():
		var hex := UISkin.hex_badge(b[0], b[1], 15)
		hex.tooltip_text = CardData.badge_label(e)
		hex.position = Vector2(-2, -2)
		hex.scale = Vector2(1.3, 1.3)
		art.add_child(hex)
	return frame


func _chips(e: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for t in CardData.tags(e):
		flow.add_child(Compendium.chip("", "", t))
	for c: Array in CardData.chips(e):
		var chip := Compendium.chip(c[0], c[1], c[2])
		chip.custom_minimum_size = Vector2(150, 0)
		flow.add_child(chip)
	return flow


func _text(bb: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.selection_enabled = true
	text.meta_underlined = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("paragraph_separation", 4)
	text.meta_clicked.connect(func(meta: Variant) -> void: link_clicked.emit(str(meta)))
	text.meta_hover_started.connect(func(meta: Variant) -> void: _hovered_meta = str(meta))
	text.meta_hover_ended.connect(func(_meta: Variant) -> void: _hovered_meta = "")
	text.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE and _hovered_meta != "":
			link_background.emit(_hovered_meta)
			text.accept_event())
	text.text = bb
	return text
