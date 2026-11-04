class_name BunnySettings
extends AcceptDialog
## The host's Table Bunny settings (TASK-95): the API key (kept in user:// only, the field
## never shows it again), the model, the token limit per session, the cooldown per player,
## the bunny's name and personality, and how many tokens this session used.

var brain: BunnyBrain
var key_edit: LineEdit
var model_pick: OptionButton
var limit: SpinBox
var cooldown: SpinBox
var name_edit: LineEdit
var personality: TextEdit
var used: Label
var mcp_on: CheckBox
var mcp_port: SpinBox
var mcp_info: LineEdit


func _init() -> void:
	name = "BunnySettings"
	title = "Table Bunny"
	ok_button_text = "Save"
	min_size = Vector2i(460, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var info := Label.new()
	info.text = "Only you (the host) need a key: the players ask the bunny through your table. The key stays on this computer."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 420
	col.add_child(info)
	key_edit = _row(col, "API key", LineEdit.new()) as LineEdit
	key_edit.name = "Key"
	key_edit.secret = true
	model_pick = _row(col, "Model", OptionButton.new()) as OptionButton
	model_pick.name = "Model"
	for m: String in BunnyBrain.MODELS:
		model_pick.add_item(m)
	limit = _row(col, "Tokens per session", SpinBox.new()) as SpinBox
	limit.name = "Limit"
	limit.min_value = 1000
	limit.max_value = 10000000
	limit.step = 1000
	cooldown = _row(col, "Seconds between a player's questions", SpinBox.new()) as SpinBox
	cooldown.name = "Cooldown"
	cooldown.max_value = 600
	name_edit = _row(col, "Name", LineEdit.new()) as LineEdit
	name_edit.name = "BunnyName"
	personality = TextEdit.new()
	personality.name = "Personality"
	personality.custom_minimum_size = Vector2(0, 70)
	personality.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var pl := Label.new()
	pl.text = "Personality"
	col.add_child(pl)
	col.add_child(personality)
	mcp_on = CheckBox.new()  # TASK-99
	mcp_on.name = "McpOn"
	mcp_on.text = "Let assistants on this computer use the table (MCP, with the DM's rights)"
	col.add_child(mcp_on)
	mcp_port = _row(col, "MCP port", SpinBox.new()) as SpinBox
	mcp_port.name = "McpPort"
	mcp_port.min_value = 1024
	mcp_port.max_value = 65535
	mcp_info = LineEdit.new()
	mcp_info.name = "McpInfo"
	mcp_info.editable = false
	mcp_info.tooltip_text = "For the assistant's MCP settings: the address and the token (Authorization: Bearer ...)"
	col.add_child(mcp_info)
	used = Label.new()
	used.name = "Used"
	used.theme_type_variation = UISkin.V_MUTED
	col.add_child(used)
	confirmed.connect(save)


func _row(col: VBoxContainer, text: String, field: Control) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 170
	row.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	col.add_child(row)
	return field


## Fills the fields from the saved settings (never the key itself).
func fill() -> void:
	key_edit.text = ""
	key_edit.placeholder_text = "saved: type a new one to replace it" if str(BunnyBrain.setting("api_key")) != "" else "sk-ant-…"
	var m := BunnyBrain.MODELS.find(str(BunnyBrain.setting("model")))
	model_pick.select(maxi(m, 0))
	limit.value = int(BunnyBrain.setting("token_limit"))
	cooldown.value = int(BunnyBrain.setting("cooldown"))
	name_edit.text = str(BunnyBrain.setting("name"))
	personality.text = str(BunnyBrain.setting("personality"))
	mcp_on.button_pressed = bool(BunnyBrain.setting("mcp_on"))
	mcp_port.value = int(BunnyBrain.setting("mcp_port"))
	mcp_info.text = "http://127.0.0.1:%d/mcp   token %s" % [int(mcp_port.value), BunnyMcp.ensure_token()]
	var spent := brain.tokens_used if brain != null else 0
	used.text = "This session: %d of %d tokens" % [spent, int(limit.value)]


func open() -> void:
	fill()
	popup_centered()


func save() -> void:
	if key_edit.text.strip_edges() != "":
		BunnyBrain.set_setting("api_key", key_edit.text.strip_edges())
		key_edit.text = ""
	BunnyBrain.set_setting("model", model_pick.get_item_text(model_pick.selected))
	BunnyBrain.set_setting("token_limit", int(limit.value))
	BunnyBrain.set_setting("cooldown", int(cooldown.value))
	BunnyBrain.set_setting("name", name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Bunny")
	BunnyBrain.set_setting("personality", personality.text.strip_edges())
	BunnyBrain.set_setting("mcp_on", mcp_on.button_pressed)
	BunnyBrain.set_setting("mcp_port", int(mcp_port.value))
	if brain != null:
		brain._set_state("sleeping" if not brain.awake() else "idle", "")
		if brain.table != null:
			brain.table.apply_bunny_mcp()
