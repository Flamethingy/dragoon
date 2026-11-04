class_name TableBunny
extends Control
## The Table Bunny on every client (TASK-98, design: backlog doc-3), with Tamago's body and
## ways (TASK-101): her rig (BunnyRig), recoloured and animated the same way, walking and
## hopping along the bottom of the Dragoon window, picked up by the scruff and dropped, and
## appearing and vanishing in a smoke puff (BunnyPuff). Ported from Tamago's
## scripts/pet/tamago.gd (behaviour) and bunny.gd (puffs); keep in step, see the backlog doc
## "Bunny shared with Tamago".
##
## Its brain is on the host (BunnyBrain); here it shows what the host says it is doing
## (NetTable.bunny_state, TASK-97): it thinks (paw at its mouth) or works (rummaging, with a
## badge "importing … 40%", "2 waiting"), sleeps when there is no brain, listens (ears up)
## while "/bunny" is typed in the chat, and talks in a speech bubble when it answers me (longer
## answers in a small scrolling panel); the answer's mood shows on it. A click opens the chat
## with "/bunny " typed; a right click has its settings.
## Its look (colours) and behaviour (walk speed, idle/walk times, hops) are the host's
## (NetTable.bunny_look), the same on every screen. Per client (user://, `settings_file`):
## on / off, quiet (no bubbles, the chat only), small / big.

const SIZES := {"normal": 210.0, "small": 140.0}  ## its height (ear tips to feet), pixels: normal = Tamago's
const BUBBLE_W := 300.0
const LONG := 180  ## characters: longer answers get the scrolling panel
const FLOOR_GAP := 6.0  ## its feet above the window's bottom edge (inside Dragoon; 0 on the desktop)
const FLOOR := -1  ## what it stands on: the floor, or a platform's id (Tamago: FLOOR = 0)
const MAX_JUMP := 260.0  ## Tamago's max_jump_height: up onto Dragoon's window
const GRAVITY := 1800.0
const DRAG_THRESHOLD := 5.0  ## pixels the mouse moves before a click becomes a drag
## Tamago's behaviour defaults (her profile's "behaviour"), hop height for the table.
const BEHAVIOUR := {"walk_speed": 40.0, "idle_time": [2.0, 6.0], "walk_time": [2.0, 5.0],
	"hop_chance": 0.25, "hop_height": 50.0}

static var settings_file := "user://bunny_client.cfg"

signal on_changed  ## called out or sent away (TASK-102)
signal place_changed  ## the desktop or inside Dragoon (TASK-102)

var table: NetTable
var chat: ChatBox
var anim := "idle"  ## idle / walk / talk / think / work / sleep (what it does)
var mood := "neutral"
var state := "ground"  ## ground / air (hopping or falling) / dragged
var bubble: PanelContainer
var bubble_text: RichTextLabel
var badge: Label
var rig: BunnyRig
var body: Node2D  ## holds the rig; its origin is between the feet
var behaviour := BEHAVIOUR.duplicate(true)
var floor_gap := FLOOR_GAP
## Tops it can stand on, in its parent's coordinates (BunnyDesk: Dragoon's window):
## [{id, left, y, segments: [Vector2(x1, x2)]}] (Tamago: platforms).
var platforms: Array = []
var _support := FLOOR
var _support_left := 0.0
var _menu: PopupMenu
var _rest := 2.0  ## seconds before it walks again (Tamago: _timer)
var _walk_left := 0.0
var _talk_left := 0.0
var _speak_left := 0.0  ## its mouth moves this much longer
var _facing := 1
var _vel_y := 0.0
var _press := Vector2.ZERO  ## where the left button went down (window pixels)
var _pressed := false
var _drag_offset := Vector2.ZERO
var _by_mouse := false  ## a real drag: let go when the button is up, whatever we saw
var _puffing := false
var _was_visible := false


func _init() -> void:
	name = "TableBunny"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "The Table Bunny: click to ask it something, drag to carry it"
	body = Node2D.new()
	body.name = "Body"
	add_child(body)
	rig = BunnyRig.new()
	rig.name = "Rig"
	body.add_child(rig)
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
		table.bunny_look_changed.connect(apply_look)
	apply_settings()
	apply_look()
	follow_status()
	_rest = randf_range(float(behaviour.idle_time[0]), float(behaviour.idle_time[1]))
	_was_visible = is_visible_in_tree()
	if _was_visible:
		body.visible = false
		appear.call_deferred()  # the parent may still be setting up its children


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		var now := is_visible_in_tree()
		if now == _was_visible:
			return
		_was_visible = now
		if now:
			body.visible = false
			appear.call_deferred()
		elif not _puffing:  # hidden from outside (e.g. the session went offline): a puff where it stood
			_puff.call_deferred()


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


## On the desktop (BunnyDesk, if this computer can) or inside Dragoon's window.
func wants_desktop() -> bool:
	return bool(setting("desktop", true))


func set_desktop(on: bool) -> void:
	set_setting("desktop", on)
	place_changed.emit()


func is_quiet() -> bool:
	return bool(setting("quiet", false))


func size_name() -> String:
	var s := str(setting("size", "normal"))
	return s if SIZES.has(s) else "normal"  # (the old "big" is normal now)


## On or off; it leaves in a puff.
func set_on(on: bool) -> void:
	set_setting("on", on)
	if not on and visible:
		vanish()
	else:
		apply_settings()
	on_changed.emit()


func set_quiet(on: bool) -> void:
	set_setting("quiet", on)
	if on:
		hide_bubble()


func set_size_name(s: String) -> void:
	set_setting("size", s if SIZES.has(s) else "normal")
	apply_settings()


func apply_settings() -> void:
	rig.height = SIZES.get(size_name(), SIZES.normal)
	var r := rig.rest_rect()
	var s := rig.scale.y
	# the box around it, wide enough whichever way it faces; the feet at its bottom middle
	var half := maxf(absf(r.position.x), absf(r.end.x)) * s
	custom_minimum_size = Vector2(ceilf(half * 2.0), ceilf(-r.position.y * s))
	size = custom_minimum_size
	body.position = Vector2(size.x * 0.5, size.y)
	visible = is_on() and (table == null or table.is_online())
	_place()


## The host's look and behaviour for it (NetTable.bunny_look; the same on every screen).
func apply_look() -> void:
	var look: Dictionary = table.bunny_look if table != null else {}
	rig.set_colors(look.get("colors", {}) if look.get("colors") is Dictionary else {})
	behaviour = sanitize_behaviour(look.get("behaviour", {}) if look.get("behaviour") is Dictionary else {})


## Behaviour from the host, checked: known keys, numbers in sane ranges.
static func sanitize_behaviour(b: Dictionary) -> Dictionary:
	var out := BEHAVIOUR.duplicate(true)
	out.walk_speed = clampf(float(b.get("walk_speed", out.walk_speed)), 0.0, 400.0)
	out.hop_chance = clampf(float(b.get("hop_chance", out.hop_chance)), 0.0, 1.0)
	out.hop_height = clampf(float(b.get("hop_height", out.hop_height)), 10.0, 200.0)
	for key: String in ["idle_time", "walk_time"]:
		var v: Variant = b.get(key, out[key])
		if v is Array and (v as Array).size() == 2:
			var lo := clampf(float(v[0]), 0.2, 120.0)
			out[key] = [lo, clampf(float(v[1]), lo, 120.0)]
	return out


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


## It said something to me (or to everyone): the bubble, its mood.
func hear(entry: Dictionary) -> void:
	mood = str(entry.get("mood", "neutral"))
	if not bool(entry.get("hint", false)) and table != null and table.bunny_state not in ["thinking", "working", "sleeping"]:
		anim = "talk"
		if state == "ground":
			_walk_left = 0.0
	var text := str(entry.get("text", ""))
	_talk_left = clampf(3.0 + text.length() / 25.0, 4.0, 20.0)
	_speak_left = clampf(text.length() * 0.05, 0.5, 4.0)  # Tamago: SpeechBubble.speaking_time
	if not is_quiet() and visible:
		say(text)


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


## Is someone typing to it ("/bunny ..." in a focused chat)? Then it listens.
func is_listening() -> bool:
	return chat != null and chat.is_visible_in_tree() and chat.line.text.begins_with("/bunny") and chat.line.has_focus()


# --- Puffs (Tamago: bunny.gd) ---------------------------------------------------------------------------

func _puff() -> BunnyPuff:
	var parent := get_parent()
	var center := position + size * 0.5
	return BunnyPuff.spawn(parent, center, maxf(size.x, size.y) * 1.6, (parent as Control).size.y if parent is Control else INF)


## It appears in a puff (returns when it shows).
func appear() -> void:
	if get_parent() == null:
		return
	_puffing = true
	body.visible = false
	await _puff().covered
	_puffing = false
	if is_instance_valid(self):
		body.visible = true


## It disappears in a puff, then is hidden (switched off).
func vanish() -> void:
	if get_parent() == null or not visible:
		visible = false
		return
	_puffing = true
	hide_bubble()
	await _puff().covered
	body.visible = false
	visible = false
	body.visible = true
	_puffing = false


# --- Input: click, right click, carried by the scruff (Tamago: tamago.gd) --------------------------------

func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b != null:
		if b.button_index == MOUSE_BUTTON_LEFT:
			if b.pressed:
				_pressed = true
				_press = get_global_mouse_position() if is_inside_tree() else position + b.position
				_by_mouse = true
				accept_event()
			elif _pressed:
				if state == "dragged":
					drop()
				else:
					_pressed = false
					open_chat()
				accept_event()
		elif b.button_index == MOUSE_BUTTON_RIGHT and b.pressed:
			settings_menu().popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))
			accept_event()
		return
	var m := event as InputEventMouseMotion
	if m != null and _pressed:
		var at := get_global_mouse_position()
		if state != "dragged" and at.distance_to(_press) > DRAG_THRESHOLD:
			pick_up(_press)
		if state == "dragged":
			drag_to(at)
		accept_event()


## Picked up: held by the scruff (`at`: the mouse, in the window).
func pick_up(at: Vector2) -> void:
	state = "dragged"
	_pressed = true
	_drag_offset = global_position - at
	hide_bubble()


## Carried: its neck slides onto the cursor (parent coordinates = window here).
func drag_to(at: Vector2) -> void:
	if state != "dragged":
		return
	var neck := body.position + rig.neck_position()  # in this control
	var parent := get_parent() as Control
	var local_at := at - (parent.global_position if parent != null else Vector2.ZERO)
	position = local_at - neck
	_clamp()


## Let go: it falls back down (onto Dragoon's window, if it is under it, or the floor).
func drop() -> void:
	_pressed = false
	_by_mouse = false
	if state == "dragged":
		_fall()


func _fall() -> void:
	state = "air"
	_vel_y = 0.0
	_support = FLOOR


## True while it moves too fast for a tight click-through region (Tamago: is_moving_fast).
func is_moving_fast() -> bool:
	return state != "ground"


## Its box and its bubbles' (parent coordinates), for the desktop's click-through region.
func clickable_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [get_rect()]
	for c: Control in [bubble, badge]:
		if c.visible:
			out.append(Rect2(position + c.position, c.size))
	if _menu != null and _menu.visible:
		out.clear()  # its menu is a window of its own; nothing to pass by
	return out


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
	_menu.add_item("Make it %s" % ("normal size" if size_name() == "small" else "small"), 2)
	_menu.add_item("Stay inside Dragoon" if wants_desktop() else "Walk on the desktop", 4)
	_menu.add_item("Send it away (the bunny icon brings it back)", 3)
	return _menu


func _on_menu(id: int) -> void:
	if id == 0:
		open_chat()
	elif id == 1:
		set_quiet(not is_quiet())
	elif id == 2:
		set_size_name("normal" if size_name() == "small" else "small")
	elif id == 3:
		set_on(false)
	elif id == 4:
		set_desktop(not wants_desktop())


# --- Moving (Tamago: tamago.gd, on the window's bottom instead of the taskbar) ---------------------------

## Where its top-left goes when it stands on the floor.
func floor_y() -> float:
	var parent := get_parent() as Control
	return maxf(0.0, (parent.size.y if parent != null else 720.0) - size.y - floor_gap)


## Where its top-left goes when it stands on what it stands on.
func ground_y() -> float:
	if _support != FLOOR:
		var p := _platform(_support)
		if not p.is_empty():
			return float(p.y) - size.y
	return floor_y()


func feet_x() -> float:
	return position.x + size.x * 0.5


func _platform(id: int) -> Dictionary:
	for p: Dictionary in platforms:
		if int(p.id) == id:
			return p
	return {}


func _stands_on(p: Dictionary, x: float) -> bool:
	if p.is_empty():
		return false
	for seg: Vector2 in p.segments:
		if x >= seg.x and x <= seg.y:
			return true
	return false


## The highest platform its feet pass while falling from prev to now (Tamago: _landing_between).
func _landing_between(prev_feet: float, feet: float) -> Dictionary:
	var best := {}
	for p: Dictionary in platforms:
		if float(p.y) >= prev_feet - 0.5 and float(p.y) <= feet and _stands_on(p, feet_x()):
			if best.is_empty() or float(p.y) < float(best.y):
				best = p
	return best


## Up onto a platform above it, if one is in reach (Tamago: _try_jump).
func _try_jump() -> bool:
	var targets := []
	for p: Dictionary in platforms:
		var rise := position.y + size.y - float(p.y)
		if rise > 10.0 and rise <= MAX_JUMP and _stands_on(p, feet_x()):
			targets.append(p)
	if targets.is_empty():
		return false
	var target: Dictionary = targets.pick_random()
	_fall()
	_vel_y = -sqrt(2.0 * GRAVITY * (position.y + size.y - float(target.y) + 30.0))  # clear the edge a bit
	return true


func _process(delta: float) -> void:
	if not visible:
		return
	var parent := get_parent() as Control
	var width := parent.size.x if parent != null else 800.0
	if _talk_left > 0.0:
		_talk_left -= delta
		if _talk_left <= 0.0:
			hide_bubble()
			if anim == "talk":
				anim = "idle"
				mood = "neutral"
	_speak_left = maxf(_speak_left - delta, 0.0)
	# safety net (Tamago): the button came up somewhere we never heard of
	if state == "dragged" and _by_mouse and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		drop()
	match state:
		"air":
			var prev_feet := position.y + size.y
			_vel_y += GRAVITY * delta
			position.y += _vel_y * delta
			if _vel_y > 0.0:
				var landing := _landing_between(prev_feet, position.y + size.y)
				if not landing.is_empty():
					_land(landing)
				elif position.y >= floor_y():
					_land({})
		"ground":
			if _support != FLOOR:  # on Dragoon's window: ride along, fall when it's gone
				var p := _platform(_support)
				if p.is_empty():
					_fall()
					_animate()
					_place()
					return
				position.x += float(p.left) - _support_left
				_support_left = float(p.left)
				if not _stands_on(p, feet_x()):
					_fall()
					_animate()
					_place()
					return
			position.y = ground_y()
			var hold := anim in ["talk", "think", "work", "sleep"] or is_listening()
			if anim == "walk":
				if hold:
					anim = "idle"
				else:
					position.x += _facing * float(behaviour.walk_speed) * delta
					if position.x <= 0.0 or position.x >= width - size.x:
						position.x = clampf(position.x, 0.0, maxf(0.0, width - size.x))
						_facing = -_facing
					_walk_left -= delta
					if _walk_left <= 0.0:
						anim = "idle"
						_rest = randf_range(float(behaviour.idle_time[0]), float(behaviour.idle_time[1]))
			elif anim == "idle" and not hold:
				_rest -= delta
				if _rest <= 0.0:
					if randf() < float(behaviour.hop_chance):
						if not _try_jump():
							hop()
					else:
						anim = "walk"
						_walk_left = randf_range(float(behaviour.walk_time[0]), float(behaviour.walk_time[1]))
						_facing = -1 if randf() < 0.5 else 1
	_animate()
	_place()


## A little hop on the spot (when there's no window to hop up onto).
func hop() -> void:
	if state != "ground":
		return
	var on := _support
	_fall()
	_support = on
	_vel_y = -sqrt(2.0 * GRAVITY * float(behaviour.hop_height) * randf_range(0.6, 1.0))


func _land(p: Dictionary) -> void:
	state = "ground"
	_vel_y = 0.0
	if p.is_empty():
		_support = FLOOR
		position.y = floor_y()
	else:
		_support = int(p.id)
		_support_left = float(p.left)
		position.y = float(p.y) - size.y
	_rest = randf_range(float(behaviour.idle_time[0]), float(behaviour.idle_time[1]))


## What its body shows (BunnyRig animations).
func _animate() -> void:
	rig.dir = _facing
	rig.mood = mood
	rig.talking = _speak_left > 0.0 and anim != "sleep"  # Tamago: while saying it (speaking_time)
	match state:
		"dragged":
			rig.anim = "dragged"
		"air":
			rig.anim = "jump" if _vel_y < 0.0 else "fall"
		_:
			match anim:
				"walk":
					rig.anim = "walk"
				"think":
					rig.anim = "thinking"
				"work":
					rig.anim = "working"
				"sleep":
					rig.anim = "sleep"
				_:
					rig.anim = "listening" if is_listening() else "idle"


func _clamp() -> void:
	var parent := get_parent() as Control
	if parent == null:
		return
	position.x = clampf(position.x, 0.0, maxf(0.0, parent.size.x - size.x))
	position.y = clampf(position.y, 0.0, floor_y())


## Inside the window; the bubble and the badge above it, inside too.
func _place() -> void:
	var parent := get_parent() as Control
	if parent == null:
		return
	if state == "ground":
		position.y = ground_y()
	_clamp()
	badge.size = Vector2(maxf(size.x * 3.0, 160.0), 18)
	badge.position = Vector2((size.x - badge.size.x) * 0.5, -22.0)
	if bubble.visible:
		var bs := bubble.get_combined_minimum_size()
		bubble.size = bs
		var gx := clampf(position.x + size.x * 0.5 - bs.x * 0.5, 4.0, maxf(4.0, parent.size.x - bs.x - 4.0))
		var gy := maxf(position.y - bs.y - (28.0 if badge.visible else 8.0), 4.0)
		bubble.position = Vector2(gx, gy) - position
