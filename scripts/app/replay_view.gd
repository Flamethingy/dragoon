class_name ReplayView
extends PanelContainer
## Plays an encounter back on its map (TASK-35): tokens move, HP and conditions change step
## by step. Play/pause, step per event or per round (back and forth), a speed control, and
## the event list beside the map: clicking an event jumps there. Read only (EncounterReplay).

signal close_requested

const SPEEDS := [0.5, 1.0, 2.0, 4.0]
const SECONDS_PER_STEP := 0.8

var replay: EncounterReplay
var assets: AssetCache
var step := 0
var playing := false
var speed := 1.0
var grid: TokenGrid
var events_tree: Tree
var play_button: Button
var position_label: Label
var creatures_text: RichTextLabel
var title: Label

var _clock := 0.0
var _items: Array[TreeItem] = []


func _ready() -> void:
	theme_type_variation = UISkin.V_PAGE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	title = Label.new()
	title.theme_type_variation = UISkin.V_HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := Button.new()
	back.text = "Back to the list"
	back.pressed.connect(func() -> void:
		playing = false
		close_requested.emit())
	head.add_child(back)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	col.add_child(controls)
	_button(controls, "|◀ Round", "Back to the start of the round", func() -> void: go(replay.previous_round(step)))
	_button(controls, "◀", "One event back", func() -> void: go(step - 1))
	play_button = _button(controls, "Play", "Play or pause", toggle_play)
	play_button.name = "Play"
	_button(controls, "▶", "One event on", func() -> void: go(step + 1))
	_button(controls, "Round ▶|", "On to the next round", func() -> void: go(replay.next_round(step)))
	var speed_pick := OptionButton.new()
	speed_pick.name = "Speed"
	for s: float in SPEEDS:
		speed_pick.add_item("%sx" % s)
	speed_pick.select(SPEEDS.find(1.0))
	speed_pick.item_selected.connect(func(i: int) -> void: speed = SPEEDS[i])
	controls.add_child(speed_pick)
	position_label = Label.new()
	position_label.theme_type_variation = UISkin.V_MUTED
	controls.add_child(position_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(480, 320)
	left.add_child(box)
	var vp := SubViewport.new()
	vp.handle_input_locally = true
	box.add_child(vp)
	grid = TokenGrid.new()
	grid.name = "ReplayGrid"
	grid.can_drag = func(_id: String) -> bool: return false  # read only
	vp.add_child(grid)
	creatures_text = RichTextLabel.new()
	creatures_text.name = "Creatures"
	creatures_text.bbcode_enabled = true
	creatures_text.fit_content = true
	creatures_text.custom_minimum_size = Vector2(0, 80)
	left.add_child(creatures_text)
	events_tree = Tree.new()
	events_tree.name = "Events"
	events_tree.hide_root = true
	events_tree.columns = 2
	events_tree.custom_minimum_size = Vector2(340, 0)
	events_tree.set_column_expand(0, false)
	events_tree.set_column_custom_minimum_width(0, 56)
	events_tree.item_selected.connect(func() -> void:
		var it := events_tree.get_selected()
		if it != null:
			go(int(it.get_metadata(0))))
	split.add_child(events_tree)
	if replay != null:
		open(replay)


## Shows an encounter's replay from its start.
func open(r: EncounterReplay) -> void:
	replay = r
	if grid == null:
		return
	title.text = "Replay · %s" % r.encounter.get("name", "")
	var view := r.timeline.map_view(str(r.encounter.get("map", "")))
	grid.clear()
	if not view.is_empty() and assets != null and assets.texture(str(view.image)) != null:
		grid.show_map(view, assets.texture(str(view.image)))
	events_tree.clear()
	_items = []
	var root := events_tree.create_item()
	var start := events_tree.create_item(root)
	start.set_text(0, "")
	start.set_text(1, "Before the fight")
	start.set_metadata(0, 0)
	_items.append(start)
	for i in r.steps.size():
		var e: Dictionary = r.steps[i]
		var it := events_tree.create_item(root)
		it.set_text(0, "#%d" % e.id)
		it.set_text(1, describe(r.timeline, e))
		it.set_metadata(0, i + 1)
		_items.append(it)
	playing = false
	go(0)


## Jumps to a step (0 = before the fight .. count()).
func go(to: int) -> void:
	if replay == null:
		return
	step = clampi(to, 0, replay.count())
	var s := replay.state_at(step)
	var keep := {}
	for ref: String in s.tokens:
		keep[ref] = true
		var cell: Vector2i = s.tokens[ref]
		if grid.tokens.has(ref):
			grid.set_token_cell(ref, cell)
		else:
			var t := replay.timeline.token_view(ref, "", true)
			if t.is_empty():
				continue
			var img := str(t.get("image", ""))
			var tex := assets.texture(img) if assets != null and img != "" else null
			grid.add_token_view(t, TokenArt.compose(tex, t.get("token_style"), str(t.get("kind", ""))), cell)
	for ref: String in grid.tokens.keys():
		if not keep.has(ref):
			grid.tokens[ref].queue_free()
			grid.tokens.erase(ref)
	var lines := PackedStringArray()
	for ref: String in s.creatures:
		var c: Dictionary = s.creatures[ref]
		var conds: Array = c.get("conditions", [])
		var hurt := c.hp != null and float(c.hp) < float(c.max_hp)
		lines.append("[b]%s[/b]  HP %s%s%s" % [Markdown.escape(str(c.name)), "[color=#b33]" if hurt else "", str(c.hp), "[/color]" if hurt else ""]
			+ ("" if conds.is_empty() else "  · " + ", ".join(conds)))
		if grid.tokens.has(ref):
			var info: Dictionary = grid.tokens[ref].get_meta("info", {})
			info["hp"] = c.hp
			(grid.tokens[ref] as Sprite2D).modulate = Color(0.55, 0.55, 0.55) if int(c.hp) <= 0 else Color.WHITE
	creatures_text.text = "\n".join(lines)
	position_label.text = "Round %d · step %d / %d" % [int(s.round), step, replay.count()] if s.active or step > 0 else "Before the fight · %d events" % replay.count()
	if step < _items.size():
		_items[step].select(1)
		events_tree.scroll_to_item(_items[step])
	grid.set_info(describe(replay.timeline, s.event) if not s.event.is_empty() else str(replay.encounter.get("name", "")))
	if step >= replay.count():
		playing = false
	play_button.text = "Pause" if playing else "Play"


func toggle_play() -> void:
	if replay == null:
		return
	if not playing and step >= replay.count():
		go(0)  # from the start again
	playing = not playing
	_clock = 0.0
	play_button.text = "Pause" if playing else "Play"


func _process(delta: float) -> void:
	if not playing or replay == null:
		return
	_clock += delta * speed
	if _clock >= SECONDS_PER_STEP:
		_clock = 0.0
		go(step + 1)


## A line for an event: who did what.
static func describe(tl: Timeline, e: Dictionary) -> String:
	var who := tl.name_of(str(e.entity)) if str(e.entity) != "" else ""
	var d: Dictionary = e.get("data", {})
	match str(e.type):
		"combat.started":
			return "The fight begins"
		"combat.turn":
			return "Round %d, turn %d" % [int(d.get("round", 0)), int(d.get("turn", 0)) + 1]
		"combat.ended":
			return "The fight ends" + (": %s" % d.reason if d.has("reason") else "")
		"token.moved":
			return "%s moves to %s" % [who, d.get("to", [])]
		"token.placed":
			return "%s appears at %s" % [who, d.get("at", [])]
		"hp.changed":
			var delta := int(d.get("delta", 0))
			return "%s %s %d HP (now %s)%s" % [who, "takes" if delta < 0 else "heals", absi(delta), d.get("hp", "?"),
				"" if str(d.get("reason", "")) == "" else ": " + str(d.reason)]
		"condition.applied":
			return "%s is %s" % [who, d.get("condition", "")]
		"condition.removed":
			return "%s is no longer %s" % [who, d.get("condition", "")]
		"initiative.rolled":
			return "%s rolls initiative: %s" % [who, d.get("total", "")]
		"dice.rolled":
			return "%s rolls %s: %s" % [who if who != "" else str(e.get("by", "")), d.get("formula", d.get("roll", "")), d.get("total", d.get("result", ""))]
	return "%s %s" % [who, TimelineView._what(e)]


func _button(row: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	row.add_child(b)
	return b
