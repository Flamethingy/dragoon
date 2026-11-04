class_name EntryView
extends ScrollContainer
## The full view of one compendium entry in its own tab (TASK-22): the whole width, picture,
## chips, every field and the complete Markdown text. Monsters get two columns (stat block
## and features left, picture and description right); other kinds picture + chips left,
## the full text right. Links (wikilinks, feature ids) are passed on as `link_clicked`; the
## compendium opens them in new tabs. The Edit button waits for the entity editor (TASK-21).

signal link_clicked(meta: String)
signal edit_requested(entry: Dictionary)
signal token_requested(entry: Dictionary)  ## the Token button (TASK-41)
signal back_requested  ## the back arrow next to the title (TASK-24)
signal send_requested(entry: Dictionary)  ## "Promote to world": a timeline entry goes into the world (TASK-32)
## A link middle-clicked: open it in a background tab (TASK-24).
signal link_background(meta: String)

const ART_HEIGHT := 300
const SIDE_WIDTH := 340
const ON_USE_KINDS := ["spells", "items", "features"]

var entry: Dictionary
var key := ""  ## package/kind/id
var edit_button: Button
var token_button: Button  ## creatures only (TASK-41)
var back_button: Button
var send_button: Button
var _hovered_meta := ""
var editor: EntryEditor  ## while editing (TASK-21)
## The book (set before setup): packages need it for their contents, PDFs and switch.
var book: Compendium
var contents: PackageContents
var drafts_page: DraftsPage
var documents_box: VBoxContainer


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
	if e.get("_kind") == "packages":
		_setup_package(e, box)
		return
	if e.get("_kind") == Compendium.DRAFTS:
		edit_button.visible = false
		if book:
			drafts_page = DraftsPage.new()
			drafts_page.name = "DraftsPage"
			drafts_page.setup(book.db)
			drafts_page.open_requested.connect(func(x: Dictionary) -> void: book.open_tab(x))
			drafts_page.background_requested.connect(func(x: Dictionary) -> void: book.open_tab(x, true))
			drafts_page.publish_all_requested.connect(book.publish_all)
			drafts_page.publish_requested.connect(book.publish_draft)  # TASK-66
			drafts_page.discard_requested.connect(book.discard_draft)
			box.add_child(drafts_page)
		return
	var monster: bool = e.get("_kind") == "creatures"
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
		if str(e.get("_kind", "")) in ON_USE_KINDS:  # TASK-108: what using it does, in plain words
			right.add_child(OnUse.view(e))
		right.add_child(_text(StatBlock.to_bbcode(e)))


## A package (TASK-23): picture, chips, on/off and Export on the left; text, documents and
## the contents overview on the right.
func _setup_package(e: Dictionary, box: VBoxContainer) -> void:
	edit_button.visible = false
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	box.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	cols.add_child(left)
	left.add_child(_art(e))
	left.add_child(_chips(e))
	var id := str(e.get("id", ""))
	var on := CheckButton.new()
	on.name = "PackageSwitch"
	on.text = "Shown in the book"
	on.button_pressed = bool(e.get("_enabled", true))
	on.toggled.connect(func(pressed: bool) -> void:
		if book:
			book.set_package_enabled(id, pressed))
	left.add_child(on)
	var export_button := Button.new()
	export_button.name = "Export"
	export_button.text = "Export..."
	export_button.tooltip_text = "Save the package (with its PDFs) as one file"
	export_button.pressed.connect(func() -> void:
		if book:
			book.export_package_dialog(id))
	left.add_child(export_button)
	if book and book.manager != null:
		if EntryStore.open(book.manager.folder_of(id)).is_read_only():
			var unlock := Button.new()
			unlock.name = "Unlock"
			unlock.text = "Unlock for editing"
			unlock.tooltip_text = "Let its entries be changed in place (source packages are read only)"
			unlock.pressed.connect(func() -> void: book.unlock_package(id))
			left.add_child(unlock)
		var remove := Button.new()
		remove.name = "Remove"
		remove.text = "Remove..."
		remove.tooltip_text = "Move the package to data/removed"
		remove.pressed.connect(func() -> void: book.remove_package_dialog(id))
		left.add_child(remove)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_text(StatBlock.package(e)))
	documents_box = VBoxContainer.new()
	documents_box.name = "Documents"
	right.add_child(documents_box)
	_fill_documents(e)
	if book:
		contents = PackageContents.new()
		contents.name = "Contents"
		contents.setup(book.db, id)
		contents.open_requested.connect(func(entry_to_open: Dictionary) -> void: book.open_tab(entry_to_open))
		contents.background_requested.connect(func(entry_to_open: Dictionary) -> void: book.open_tab(entry_to_open, true))
		box.add_child(contents)


func _fill_documents(e: Dictionary) -> void:
	for c in documents_box.get_children():
		documents_box.remove_child(c)
		c.queue_free()
	var id := str(e.get("id", ""))
	var head := HBoxContainer.new()
	documents_box.add_child(head)
	var title := Label.new()
	title.text = "Documents"
	title.theme_type_variation = UISkin.V_HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var add := Button.new()
	add.name = "AddPdf"
	add.text = "Add PDF..."
	add.tooltip_text = "Copy a PDF into the package's docs/ folder"
	add.pressed.connect(func() -> void:
		if book:
			book.add_pdf_dialog(id))
	head.add_child(add)
	var docs: Array = book.manager.documents(id) if book and book.manager else []
	if docs.is_empty():
		var none := Label.new()
		none.theme_type_variation = UISkin.V_MUTED
		none.text = "No PDFs in this package."
		documents_box.add_child(none)
	for d: Dictionary in docs:
		var row := HBoxContainer.new()
		row.name = "Doc_" + str(d.file).get_file().validate_node_name()
		row.add_theme_constant_override("separation", 8)
		documents_box.add_child(row)
		var name_label := Label.new()
		name_label.text = str(d.get("title", d.file))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = str(d.file)
		row.add_child(name_label)
		var size_label := Label.new()
		size_label.theme_type_variation = UISkin.V_MUTED
		size_label.text = PackageManager.size_text(int(d.get("size", 0))) + ("" if d.exists else " · missing")
		if d.get("pages") != null:
			size_label.text += " · %d pages" % int(d.pages)
		row.add_child(size_label)
		var open_button := Button.new()
		open_button.text = "Open"
		open_button.disabled = not d.exists
		open_button.pressed.connect(func() -> void: book.open_document(id, str(d.file)))
		row.add_child(open_button)
		var folder := Button.new()
		folder.text = "Show in folder"
		folder.disabled = not d.exists
		folder.pressed.connect(func() -> void: book.show_document(id, str(d.file)))
		row.add_child(folder)


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
	if EntryStore.is_draft(e):
		UISkin.mark_draft(title)
	if e.get("_kind") == Compendium.DRAFTS:
		sub.text = "Unfinished entries of every package and the timeline"
	sub.add_theme_color_override("font_color", UISkin.TAN)
	sub.add_theme_font_size_override("font_size", 14)
	col.add_child(sub)
	send_button = Button.new()
	send_button.text = "Promote to world"
	send_button.name = "Promote"
	send_button.tooltip_text = "Put this entry, made in the timeline, into the world package so every timeline can use it"
	send_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	send_button.visible = false
	send_button.pressed.connect(func() -> void: send_requested.emit(entry))
	row.add_child(send_button)
	edit_button = Button.new()
	edit_button.text = "Edit"
	edit_button.tooltip_text = "Edit this entry here (source packages: edit a copy or unlock)"
	edit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit_button.pressed.connect(func() -> void: edit_requested.emit(entry))
	row.add_child(edit_button)
	token_button = Button.new()
	token_button.name = "Token"
	token_button.text = "Token"
	token_button.tooltip_text = "How this creature's token looks on the map"
	token_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	token_button.visible = str(e.get("_kind", "")) in Timeline.CREATURES
	token_button.pressed.connect(func() -> void: token_requested.emit(entry))
	row.add_child(token_button)
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
		var tag := Compendium.chip("", "", t)
		tag.custom_minimum_size = Vector2(120, 0)  # keeps "Concentration" on one line
		flow.add_child(tag)
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
	if EntryStore.is_draft(entry):
		UISkin.mark_draft(text, false)
	return text
