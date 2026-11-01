class_name ChatBox
extends PanelContainer
## A simple chat on the right of the calm table (TASK-46, Nico 2026-11-01): the session's
## messages and rolls in one feed (NetTable.rolls) and a line to write in. Enter sends and
## gives the keys back to the map; "/r 2d6+3" or "/r perception" rolls (for the active
## character when there is one).

var table: NetTable
var active_ref := Callable()  ## -> String: who "/r" rolls for (the HUD's active one)
var log_text: RichTextLabel
var line: LineEdit


func _init() -> void:
	name = "Chat"
	theme_type_variation = UISkin.V_PAGE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -340
	offset_right = -12
	offset_top = 56
	offset_bottom = -12
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := Label.new()
	head.text = "Chat"
	head.theme_type_variation = UISkin.V_HEADING
	col.add_child(head)
	log_text = RichTextLabel.new()
	log_text.name = "Log"
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.selection_enabled = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.meta_clicked.connect(func(meta: Variant) -> void: RollTables.handle_meta(str(meta)))
	col.add_child(log_text)
	line = LineEdit.new()
	line.name = "Line"
	line.placeholder_text = "Write something...  (/r 1d20+3 rolls)"
	line.text_submitted.connect(func(_t: String) -> void: send())
	col.add_child(line)


func _ready() -> void:
	if table != null:
		table.rolls_changed.connect(refresh)
		table.accounts_changed.connect(refresh)
	refresh()


## Sends the line: a message, or a roll with "/r".
func send() -> void:
	var text := line.text.strip_edges()
	line.text = ""
	line.release_focus()  # the map gets its keys back (WASD, Q / E)
	if text == "" or table == null:
		return
	table.say(text, str(active_ref.call()) if active_ref.is_valid() else "")


func refresh() -> void:
	if table == null:
		return
	var parts := PackedStringArray()
	for r: Dictionary in table.rolls:
		parts.append(NetTable.roll_bbcode(r, table.notes.names))
	log_text.text = "\n\n".join(parts) if not parts.is_empty() else "[color=#%s]Nothing said yet.[/color]" % Markdown.MUTED.to_html(false)
