class_name BunnySettings
extends AcceptDialog
## The host's Table Bunny settings (TASK-95): the API key (kept in user:// only, the field
## never shows it again), the model, the token limit per session, the cooldown per player,
## the bunny's name and personality, and how many tokens this session used.
## TASK-99: the MCP server for local assistants. TASK-101: its look (colours per slot of its
## art, with a live preview) and behaviour (walk speed, idle and walk times, hops), shown the
## same on every screen.

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
var preview: BunnyRig
var color_pickers := {}  ## slot -> ColorPickerButton
var palette := {}  ## slot -> Color as drawn (rig.json)
var walk_speed: SpinBox
var idle_min: SpinBox
var idle_max: SpinBox
var walk_min: SpinBox
var walk_max: SpinBox
var hop_chance: SpinBox
var hop_height: SpinBox


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
	_look_section(col)
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


## Its look and behaviour (TASK-101): colour pickers beside a live preview, then its ways.
func _look_section(col: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Look"
	col.add_child(title)
	var row := HBoxContainer.new()
	row.name = "Look"
	col.add_child(row)
	var stage := Control.new()
	stage.name = "Preview"
	stage.custom_minimum_size = Vector2(110, 120)
	stage.clip_contents = true
	row.add_child(stage)
	preview = BunnyRig.new()
	preview.height = 104.0
	preview.position = Vector2(55, 114)
	stage.add_child(preview)
	var picks := GridContainer.new()
	picks.columns = 2
	picks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picks)
	var rig: Variant = JSON.parse_string(FileAccess.get_file_as_string(BunnyRig.PART_DIR + "rig.json"))
	var drawn: Dictionary = (rig as Dictionary).get("palette", {}) if rig is Dictionary else {}
	for slot: String in drawn:
		palette[slot] = Color.html(str(drawn[slot]))
		var l := Label.new()
		l.text = slot.capitalize()
		picks.add_child(l)
		var pick := ColorPickerButton.new()
		pick.name = "Color_" + slot
		pick.custom_minimum_size = Vector2(70, 24)
		pick.edit_alpha = false
		pick.color = palette[slot]
		pick.color_changed.connect(func(_c: Color) -> void: _preview_colors())
		picks.add_child(pick)
		color_pickers[slot] = pick
	var reset := Button.new()
	reset.name = "AsDrawn"
	reset.text = "As drawn"
	reset.pressed.connect(func() -> void:
		for slot: String in color_pickers:
			(color_pickers[slot] as ColorPickerButton).color = palette[slot]
		_preview_colors())
	picks.add_child(reset)
	walk_speed = _row(col, "Walk speed (px/s)", SpinBox.new()) as SpinBox
	walk_speed.name = "WalkSpeed"
	walk_speed.max_value = 400
	var idle := _pair(col, "Rests (seconds, min-max)")
	idle_min = idle[0]
	idle_max = idle[1]
	var walk := _pair(col, "Walks (seconds, min-max)")
	walk_min = walk[0]
	walk_max = walk[1]
	hop_chance = _row(col, "Hops instead of walking (%)", SpinBox.new()) as SpinBox
	hop_chance.name = "HopChance"
	hop_height = _row(col, "Hop height (px)", SpinBox.new()) as SpinBox
	hop_height.name = "HopHeight"
	hop_height.min_value = 10
	hop_height.max_value = 200


func _pair(col: VBoxContainer, text: String) -> Array:
	var box := HBoxContainer.new()
	var out := []
	for i in 2:
		var spin := SpinBox.new()
		spin.min_value = 0.2
		spin.max_value = 120
		spin.step = 0.5
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(spin)
		out.append(spin)
	_row(col, text, box)
	return out


## The colours as picked: slot -> "#rrggbb", or "" where it stays as drawn.
func picked_colors() -> Dictionary:
	var out := {}
	for slot: String in color_pickers:
		var c: Color = (color_pickers[slot] as ColorPickerButton).color
		out[slot] = "" if c.to_html(false) == (palette[slot] as Color).to_html(false) else "#" + c.to_html(false)
	return out


func _preview_colors() -> void:
	if preview.is_inside_tree():
		preview.set_colors(picked_colors())


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
	var colors: Variant = BunnyBrain.setting("colors")
	for slot: String in color_pickers:
		var v := str((colors as Dictionary).get(slot, "")) if colors is Dictionary else ""
		(color_pickers[slot] as ColorPickerButton).color = Color.html(v) if Color.html_is_valid(v) else palette[slot]
	_preview_colors()
	var ways: Variant = BunnyBrain.setting("behaviour")
	var b := TableBunny.sanitize_behaviour(ways if ways is Dictionary else {})
	walk_speed.value = float(b.walk_speed)
	idle_min.value = float(b.idle_time[0])
	idle_max.value = float(b.idle_time[1])
	walk_min.value = float(b.walk_time[0])
	walk_max.value = float(b.walk_time[1])
	hop_chance.value = roundf(float(b.hop_chance) * 100.0)
	hop_height.value = float(b.hop_height)
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
	BunnyBrain.set_setting("colors", picked_colors())
	BunnyBrain.set_setting("behaviour", TableBunny.sanitize_behaviour({"walk_speed": walk_speed.value,
		"idle_time": [idle_min.value, idle_max.value], "walk_time": [walk_min.value, walk_max.value],
		"hop_chance": hop_chance.value / 100.0, "hop_height": hop_height.value}))
	BunnyBrain.set_setting("mcp_on", mcp_on.button_pressed)
	BunnyBrain.set_setting("mcp_port", int(mcp_port.value))
	if brain != null:
		brain._set_state("sleeping" if not brain.awake() else "idle", "")
		if brain.table != null:
			brain.table.apply_bunny_mcp()
			brain.table.share_bunny_look()
