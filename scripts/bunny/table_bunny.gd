class_name TableBunny
extends Control
## The Table Bunny on every client (TASK-98, design: backlog doc-3): a small bunny walking
## along the bottom of the Dragoon window. Its brain is on the host (BunnyBrain); here it shows
## what the host says it is doing (NetTable.bunny_state, TASK-97): it thinks (dots) or works
## (with a badge "importing … 40%", "2 waiting"), sleeps when there is no brain, and talks in a
## speech bubble when it answers me (longer answers in a small scrolling panel); its face
## follows the answer's mood. A click opens the chat with "/bunny " typed; a right click has
## its settings. Per client (user://, `settings_file`): on / off, quiet (no bubbles, the chat
## only), small / big.
## The look is a placeholder drawn here (Nico decides about real sprites, e.g. PixelLab).

const SPEED := 40.0  ## pixels per second while walking
const SIZES := {"small": 56.0, "big": 88.0}
const BUBBLE_W := 300.0
const LONG := 180  ## characters: longer answers get the scrolling panel

static var settings_file := "user://bunny_client.cfg"

var table: NetTable
var chat: ChatBox
var anim := "idle"  ## idle / walk / talk / think / work / sleep
var mood := "neutral"
var bubble: PanelContainer
var bubble_text: RichTextLabel
var badge: Label
var _menu: PopupMenu
var _target_x := -1.0
var _rest := 2.0  ## seconds before it walks again
var _talk_left := 0.0
var _t := 0.0
var _facing := 1.0


func _init() -> void:
	name = "TableBunny"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "The Table Bunny: click to ask it something"
	bubble = PanelContainer.new()
	bubble.name = "Bubble"
	bubble.theme_type_variation = UISkin.V_PAGE
	bubble.visible = false
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	bubble.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			hide_bubble())
	bubble_text = RichTextLabel.new()
	bubble_text.name = "Text"
	bubble_text.bbcode_enabled = false
	bubble_text.fit_content = true
	bubble_text.scroll_active = false
	bubble_text.custom_minimum_size = Vector2(BUBBLE_W - 20, 0)
	bubble.add_child(bubble_text)
	add_child(bubble)
	badge = Label.new()
	badge.name = "Badge"
	badge.add_theme_font_size_override("font_size", 11)
	badge.theme_type_variation = UISkin.V_MUTED
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.visible = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)


func _ready() -> void:
	if table != null:
		table.bunny_status_changed.connect(follow_status)
		table.bunny_message.connect(hear)
	apply_settings()
	follow_status()


# --- Per client settings ---------------------------------------------------------------------------

static func setting(key: String, fallback: Variant) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	return cfg.get_value("bunny", key, fallback)


static func set_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	cfg.set_value("bunny", key, value)
	cfg.save(settings_file)


func is_on() -> bool:
	return bool(setting("on", true))


func is_quiet() -> bool:
	return bool(setting("quiet", false))


func size_name() -> String:
	return str(setting("size", "small"))


func set_on(on: bool) -> void:
	set_setting("on", on)
	apply_settings()


func set_quiet(on: bool) -> void:
	set_setting("quiet", on)
	if on:
		hide_bubble()


func set_size_name(s: String) -> void:
	set_setting("size", s if SIZES.has(s) else "small")
	apply_settings()


func apply_settings() -> void:
	var px: float = SIZES.get(size_name(), SIZES.small)
	custom_minimum_size = Vector2(px, px)
	size = custom_minimum_size
	visible = is_on() and (table == null or table.is_online())
	_place()
	queue_redraw()


# --- What it does ---------------------------------------------------------------------------------

## The host's word on the bunny: thinking / working / sleeping / idle.
func follow_status() -> void:
	if table == null:
		return
	visible = is_on() and table.is_online()
	match table.bunny_state:
		"thinking":
			anim = "think"
		"working":
			anim = "work"
		"sleeping":
			anim = "sleep"
		_:
			if anim in ["think", "work", "sleep"]:
				anim = "idle"
	var busy := table.bunny_state in ["thinking", "working"]
	badge.visible = busy or table.bunny_waiting > 0
	var parts := PackedStringArray()
	if busy and table.bunny_detail != "":
		parts.append(table.bunny_detail)
	if table.bunny_waiting > 0:
		parts.append("%d waiting" % table.bunny_waiting)
	badge.text = " · ".join(parts)
	_place()
	queue_redraw()


## It said something to me (or to everyone): the bubble, the face of its mood.
func hear(entry: Dictionary) -> void:
	mood = str(entry.get("mood", "neutral"))
	if not bool(entry.get("hint", false)) and table != null and table.bunny_state not in ["thinking", "working", "sleeping"]:
		anim = "talk"
	var text := str(entry.get("text", ""))
	_talk_left = clampf(3.0 + text.length() / 25.0, 4.0, 20.0)
	if not is_quiet() and visible:
		say(text)
	queue_redraw()


func say(text: String) -> void:
	bubble_text.text = text
	var long := text.length() > LONG
	bubble_text.fit_content = not long
	bubble_text.scroll_active = long
	bubble_text.custom_minimum_size = Vector2(BUBBLE_W - 20, 160 if long else 0)
	bubble.visible = true
	bubble.reset_size()
	_place()


func hide_bubble() -> void:
	bubble.visible = false


## A click: the chat, ready to ask.
func open_chat() -> void:
	if chat == null:
		return
	chat.visible = true
	if not chat.line.text.begins_with("/bunny"):
		chat.line.text = "/bunny "
	chat.line.caret_column = chat.line.text.length()
	if chat.line.is_inside_tree():
		chat.line.grab_focus()


func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b == null or not b.pressed:
		return
	if b.button_index == MOUSE_BUTTON_LEFT:
		open_chat()
		accept_event()
	elif b.button_index == MOUSE_BUTTON_RIGHT:
		settings_menu().popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))
		accept_event()


## Its right-click menu: quiet, small / big, hide.
func settings_menu() -> PopupMenu:
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.name = "BunnyMenu"
		add_child(_menu)
		_menu.id_pressed.connect(_on_menu)
	_menu.clear()
	_menu.add_item("Ask the bunny", 0)
	_menu.add_check_item("Quiet (answers only in the chat)", 1)
	_menu.set_item_checked(_menu.get_item_index(1), is_quiet())
	_menu.add_item("Make it %s" % ("big" if size_name() == "small" else "small"), 2)
	_menu.add_item("Hide the bunny (Esc menu brings it back)", 3)
	return _menu


func _on_menu(id: int) -> void:
	if id == 0:
		open_chat()
	elif id == 1:
		set_quiet(not is_quiet())
	elif id == 2:
		set_size_name("big" if size_name() == "small" else "small")
	elif id == 3:
		set_on(false)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var parent := get_parent() as Control
	var width := parent.size.x if parent != null else 800.0
	if _talk_left > 0.0:
		_talk_left -= delta
		if _talk_left <= 0.0:
			hide_bubble()
			if anim == "talk":
				anim = "idle"
				mood = "neutral"
	if anim == "idle":
		_rest -= delta
		if _rest <= 0.0:
			_target_x = randf_range(20.0, maxf(40.0, width - size.x - 20.0))
			anim = "walk"
	elif anim == "walk":
		var step := SPEED * delta
		var dx := _target_x - position.x
		_facing = signf(dx) if dx != 0.0 else _facing
		if absf(dx) <= step:
			position.x = _target_x
			anim = "idle"
			_rest = randf_range(3.0, 9.0)
		else:
			position.x += step * _facing
	_place()
	queue_redraw()


## Stays at the bottom of its parent; the bubble and the badge above it, inside the window.
func _place() -> void:
	var parent := get_parent() as Control
	if parent == null:
		return
	position.y = parent.size.y - size.y - 6.0
	position.x = clampf(position.x, 0.0, maxf(0.0, parent.size.x - size.x))
	badge.size = Vector2(maxf(size.x * 3.0, 160.0), 18)
	badge.position = Vector2((size.x - badge.size.x) * 0.5, -22.0)
	if bubble.visible:
		var bs := bubble.get_combined_minimum_size()
		bubble.size = bs
		var gx := clampf(position.x + size.x * 0.5 - bs.x * 0.5, 4.0, maxf(4.0, parent.size.x - bs.x - 4.0))
		bubble.position = Vector2(gx - position.x, -bs.y - (28.0 if badge.visible else 8.0))


# --- The placeholder look -----------------------------------------------------------------------------

func _draw() -> void:
	var s := size.x
	var fur := Color(0.97, 0.95, 0.92)
	var ink := Color(0.25, 0.2, 0.18)
	var pink := Color(0.95, 0.6, 0.65)
	var hop := 0.0
	match anim:
		"walk":
			hop = -absf(sin(_t * 9.0)) * s * 0.08
		"talk":
			hop = -absf(sin(_t * 6.0)) * s * 0.04
		"idle", "think", "work":
			hop = sin(_t * 2.0) * s * 0.015
	var c := Vector2(s * 0.5, s * 0.62 + hop)
	var r := s * 0.3
	var ear_tilt := 0.35 if anim == "sleep" else 0.0
	for side: float in [-1.0, 1.0]:  # ears
		var base := c + Vector2(side * r * 0.45, -r * 0.8)
		var tip := base + Vector2(side * (r * 0.25 + ear_tilt * r), -r * (1.3 - ear_tilt))
		draw_line(base, tip, fur, r * 0.42, true)
		draw_line(base, tip.lerp(base, 0.2), pink, r * 0.18, true)
	draw_circle(c + Vector2(0, r * 0.55), r * 0.95, fur)  # body
	draw_circle(c, r, fur)  # head
	draw_arc(c, r, 0, TAU, 32, Color(ink, 0.35), 1.0, true)
	var eye_y := c.y - r * 0.1
	for side: float in [-1.0, 1.0]:
		var e := Vector2(c.x + side * r * 0.4 + _facing * r * 0.08, eye_y)
		if anim == "sleep" or mood == "sleepy":
			draw_line(e - Vector2(r * 0.14, 0), e + Vector2(r * 0.14, 0), ink, 1.5, true)
		elif mood == "happy":
			draw_arc(e + Vector2(0, r * 0.06), r * 0.13, PI, TAU, 8, ink, 1.5, true)
		else:
			draw_circle(e, r * 0.1, ink)
	draw_circle(c + Vector2(0, r * 0.18), r * 0.08, pink)  # nose
	var mouth := c + Vector2(0, r * 0.38)
	if anim == "talk" and int(_t * 8.0) % 2 == 0:
		draw_circle(mouth, r * 0.1, ink)
	elif mood == "sad":
		draw_arc(mouth + Vector2(0, r * 0.12), r * 0.15, PI * 1.15, PI * 1.85, 8, ink, 1.2, true)
	else:
		draw_arc(mouth - Vector2(0, r * 0.08), r * 0.15, PI * 0.15, PI * 0.85, 8, ink, 1.2, true)
	if anim == "think":  # three dots above
		for i in 3:
			var on := int(_t * 3.0) % 3 >= i
			draw_circle(c + Vector2(r * (0.6 + i * 0.35), -r * (1.25 + i * 0.25)), r * (0.08 + i * 0.03), Color(ink, 0.8 if on else 0.25))
	elif anim == "work":  # a turning gear-ish ring
		draw_arc(c + Vector2(r * 1.1, -r * 1.2), r * 0.28, _t * 4.0, _t * 4.0 + PI * 1.5, 12, ink, 2.0, true)
	elif anim == "sleep":
		var f := ThemeDB.fallback_font
		draw_string(f, c + Vector2(r * 0.8, -r * (1.1 + fmod(_t, 2.0) * 0.2)), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 0.5), Color(ink, 0.7))
		draw_string(f, c + Vector2(r * 1.15, -r * (1.5 + fmod(_t + 1.0, 2.0) * 0.2)), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 0.7), Color(ink, 0.7))
