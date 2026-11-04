class_name BunnyChat
extends Window
## Talking to the Table Bunny (TASK-103), Tamago's chat window for Dragoon (tamago:
## scripts/ui/chat_window.gd): a borderless window with my conversation with the bunny above the
## input. It opens above the bunny (also out on the desktop) and the header drags it anywhere.
## The log is mine only (NetTable.bunny_log, kept on this computer per table and player): what
## the DM asks the bunny, the players never see, and the other way round. "To everyone" asks so
## that the whole table hears the answer (it then also shows in the table's chat).
## The input is multi-line: Enter sends, Shift+Enter starts a new line. Esc or the X closes it.

const WIDTH := 380
const DEFAULT_HEIGHT := 360
const MIN_SIZE := Vector2i(300, 180)
const PAGE := 20  ## entries shown at first; scrolling to the top shows this many more
const FONT_SIZE := 14
const INPUT_MAX_LINES := 6
const ON_COVER := Color(0.96, 0.9, 0.8)  ## light text and the X on the dark cover

var table: NetTable
var active_ref: Callable  ## -> my active character's ref (the bunny's context), from the table UI
var input: TextEdit
var everyone: CheckBox
var log_box: VBoxContainer
var scroll: ScrollContainer
var title_label: Label
var empty: Label
var _shown := 0
var _moving := false
var _move_from := Vector2i.ZERO
var _move_pos := Vector2i.ZERO


func _init() -> void:
	name = "BunnyChat"
	title = "Talk to the bunny"
	size = Vector2i(WIDTH, DEFAULT_HEIGHT)
	min_size = MIN_SIZE
	visible = false
	borderless = true
	transparent = true
	transparent_bg = true
	wrap_controls = false
	close_requested.connect(hide)
	window_input.connect(_on_window_input)


func _ready() -> void:
	var cover := PanelContainer.new()
	cover.name = "Cover"
	cover.theme = UISkin.theme()
	cover.theme_type_variation = UISkin.V_COVER
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	cover.add_child(column)
	# the header is the handle to move the window
	var head := HBoxContainer.new()
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	head.tooltip_text = "Drag to move"
	head.gui_input.connect(_on_head_input)
	title_label = Label.new()
	title_label.theme_type_variation = UISkin.V_PLATE_LABEL
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close := DockPanel.WindowButton.new()
	close.kind = "close"
	close.name = "Close"
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(hide)
	close.modulate = ON_COVER
	head.add_child(close)
	column.add_child(head)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	column.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 10)  # clear of the scrollbar
	scroll.add_child(pad)
	log_box = VBoxContainer.new()
	log_box.name = "Log"
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 6)
	pad.add_child(log_box)
	empty = Label.new()
	empty.text = "Say hi! Only you see this chat."
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.theme_type_variation = UISkin.V_PLATE_LABEL
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	input = TextEdit.new()
	input.name = "Input"
	input.placeholder_text = "Ask something... (Shift+Enter: new line)"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.gui_input.connect(_on_input_key)
	input.text_changed.connect(_fit_input)
	row.add_child(input)
	var side := VBoxContainer.new()
	side.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(side)
	everyone = CheckBox.new()
	everyone.name = "Everyone"
	everyone.text = "To everyone"
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		everyone.add_theme_color_override(c, ON_COVER)
	everyone.tooltip_text = "The whole table hears the answer (and sees your question)"
	side.add_child(everyone)
	var send := Button.new()
	send.name = "Send"
	send.text = "Send"
	send.pressed.connect(submit)
	side.add_child(send)
	_fit_input()
	if table != null:
		table.bunny_log_added.connect(_on_logged)
		table.bunny_status_changed.connect(_retitle)
	_retitle()
	render()


func _retitle() -> void:
	var who := table.bunny_name if table != null else "the bunny"
	title = "Talk to %s" % who
	if title_label != null:
		title_label.text = title


## Opens it with its bottom left at `bottom_left`, above the bunny: screen pixels for a window
## of its own, else the pixels of Dragoon's window it is shown in.
func open_at(bottom_left: Vector2i) -> void:
	_retitle()
	render()
	var at := bottom_left - Vector2i(0, size.y)
	var area := Rect2i(Vector2i.ZERO, Vector2i(get_parent().get_viewport().get_visible_rect().size)) if is_embedded() 		else DisplayServer.screen_get_usable_rect(DisplayServer.get_screen_from_rect(Rect2i(bottom_left, Vector2i.ONE)))
	at.x = clampi(at.x, area.position.x, maxi(area.position.x, area.end.x - size.x))
	at.y = clampi(at.y, area.position.y, maxi(area.position.y, area.end.y - size.y))
	position = at
	show()
	grab_focus()
	input.grab_focus()


# --- The log -----------------------------------------------------------------------------------

## The newest PAGE entries of my log.
func render() -> void:
	if log_box == null:
		return
	for child in log_box.get_children():
		log_box.remove_child(child)
		if child != empty:
			child.queue_free()
	var all: Array = table.bunny_log if table != null else []
	_shown = mini(PAGE, all.size())
	if _shown == 0:
		log_box.add_child(empty)
	for i in range(all.size() - _shown, all.size()):
		log_box.add_child(entry_view(all[i]))
	_scroll_to_end()


func _on_logged(entry: Dictionary) -> void:
	if log_box == null:
		return
	if empty.get_parent() == log_box:
		log_box.remove_child(empty)
	log_box.add_child(entry_view(entry))
	_shown += 1
	_scroll_to_end()


## Scrolled to the top: older entries, the view staying where it was.
func _on_scrolled(value: float) -> void:
	var all: Array = table.bunny_log if table != null else []
	if value > 0.0 or _shown >= all.size() or not visible:
		return
	var bar := scroll.get_v_scroll_bar()
	var old_max := bar.max_value
	var more := mini(PAGE, all.size() - _shown)
	var start := all.size() - _shown - more
	for i in more:
		var node := entry_view(all[start + i])
		log_box.add_child(node)
		log_box.move_child(node, i)
	_shown += more
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(bar.max_value - old_max)


func _scroll_to_end() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


## One line of the log: mine on a card (right), the bunny's on a page (left), errors muted.
func entry_view(entry: Dictionary) -> Control:
	var role := str(entry.get("role", ""))
	var text := str(entry.get("text", ""))
	if role == "error" or bool(entry.get("hint", false)):
		var note := Label.new()
		note.text = ("⚠ " if role == "error" else "") + text
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.theme_type_variation = UISkin.V_PLATE_LABEL
		note.add_theme_font_size_override("font_size", 12)
		return note
	var mine := role == "user"
	var outer := MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("margin_left" if mine else "margin_right", 36)
	var card := PanelContainer.new()
	card.theme_type_variation = UISkin.V_CARD if mine else UISkin.V_PAGE
	outer.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	if bool(entry.get("public", false)):
		var tag := Label.new()
		tag.text = "to everyone"
		tag.theme_type_variation = UISkin.V_MUTED
		tag.add_theme_font_size_override("font_size", 11)
		box.add_child(tag)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.selection_enabled = true
	body.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	body.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	body.add_theme_font_size_override("italics_font_size", FONT_SIZE)
	body.text = Markdown.to_bbcode(text) if not mine else text.replace("[", "[lb]")
	box.add_child(body)
	return outer


# --- Sending -----------------------------------------------------------------------------------

## Sends what is typed (to me only, or to everyone).
func submit() -> void:
	var text := input.text.strip_edges()
	if text == "" or table == null:
		return
	input.clear()
	_fit_input()
	var active := str(active_ref.call()) if active_ref.is_valid() else ""
	if active == "":
		active = table.my_pc
	table.ask_bunny(text, everyone.button_pressed, active)
	input.grab_focus()


func _on_input_key(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and not k.shift_pressed:
		submit()
		input.accept_event()
	elif k.keycode == KEY_ESCAPE:
		hide()
		input.accept_event()


## The input grows with long text up to INPUT_MAX_LINES (the window grows upwards with it).
func _fit_input() -> void:
	if input == null:
		return
	var lines := clampi(input.get_line_count() + input.get_total_visible_line_count() - input.get_line_count(), 1, INPUT_MAX_LINES)
	input.custom_minimum_size.y = input.get_line_height() * lines + 14


func _on_window_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		hide()


## Dragging the header moves the window (screen coordinates, so it can go anywhere).
func _on_head_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b != null and b.button_index == MOUSE_BUTTON_LEFT:
		_moving = b.pressed
		_move_from = DisplayServer.mouse_get_position()
		_move_pos = position
	elif event is InputEventMouseMotion and _moving:
		position = _move_pos + DisplayServer.mouse_get_position() - _move_from
