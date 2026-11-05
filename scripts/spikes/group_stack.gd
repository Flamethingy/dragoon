class_name GroupStack
extends Node2D
## TASK-115, look A (Nico 2026-11-05): a group token shows its leader's picture (the token
## itself) with the other members small and overlapping at its lower right edge and a "×N"
## badge. Hovering fans them out above the token so every face is seen. A child of the token,
## unscaled like its Marks.

const SHOWN := 3  ## faces at the edge at most (the badge tells the rest)
const GROW := 1.15  ## a fanned face under the mouse grows to this (TASK-116)
const GRACE := 0.3  ## seconds the fan stays open after the mouse left it

var radius := 35.0  ## the token's radius in pixels
var faces: Array = []  ## [{id, name, texture}], the leader first
var fanned := false:
	set(v):
		if fanned != v:
			fanned = v
			if not v:
				hot = ""
			queue_redraw()
## The fanned face under the mouse ("" = none): it grows a little, eased (TASK-116).
var hot := "":
	set(v):
		if hot != v:
			hot = v
			set_process(true)
var grow := {}  ## member -> its scale now (1.0 .. GROW)
var lifted := "":  ## the member being dragged out (not drawn in the fan meanwhile)
	set(v):
		lifted = v
		queue_redraw()
var _ticket := 0  ## the pending close_soon (a newer open / close cancels it)


func _ready() -> void:
	set_process(false)


## Fans the members out (and keeps them out: a pending close is dropped).
func open() -> void:
	_ticket += 1
	fanned = true


## Closes the fan after GRACE seconds, unless the mouse comes back first.
func close_soon() -> void:
	_ticket += 1
	var t := _ticket
	if not is_inside_tree():
		fanned = false
		return
	get_tree().create_timer(GRACE).timeout.connect(_close_if.bind(t))  # a method, not a lambda: dropped if freed


func _close_if(ticket: int) -> void:
	if ticket == _ticket:
		fanned = false


func _process(delta: float) -> void:
	var busy := false
	for f: Dictionary in faces:
		var id := str(f.get("id", ""))
		var target := GROW if id == hot and fanned else 1.0
		var now: float = grow.get(id, 1.0)
		now = lerpf(now, target, 1.0 - exp(-delta * 16.0))  # eased towards the target
		if absf(now - target) < 0.002:
			now = target
		else:
			busy = true
		grow[id] = now
	queue_redraw()
	if not busy:
		set_process(false)


func set_faces(list: Array, r: float) -> void:
	faces = list
	radius = r
	queue_redraw()


## Where the other members' faces are (local, in map pixels): [{face, at, r}], the top one last.
func spots() -> Array:
	var others := faces.slice(1)
	var out := []
	if fanned:  # every member in a row above the token
		var size := radius * 0.8
		var step := size * 1.05
		var x0 := -step * (others.size() - 1) * 0.5
		for i in others.size():
			out.append({"face": others[i], "at": Vector2(x0 + step * i, -radius - size * 0.6), "r": size * 0.5})
	else:
		var size := radius * 0.72
		for i in range(mini(others.size(), SHOWN) - 1, -1, -1):  # the first one on top
			out.append({"face": others[i], "at": Vector2(radius * 0.66 - i * size * 0.62, radius * 0.66 - i * size * 0.1), "r": size * 0.5})
	return out


## The member whose face is at `local` ("" = none; the top one wins).
func face_at(local: Vector2) -> String:
	var hit := ""
	for s: Dictionary in spots():
		if (s.at as Vector2).distance_to(local) <= float(s.r) + 3.0:
			hit = str(s.face.get("id", ""))
	return hit


## Fanned out: the row of faces and the gap down to the token keep the fan open (TASK-115 fix:
## it closed on the way up to the faces and flickered).
func in_fan(local: Vector2) -> bool:
	if not fanned or faces.size() < 2:
		return false
	var size := radius * 0.8
	var width := maxf(size * 1.05 * (faces.size() - 1), radius * 2.0) + 8.0
	return Rect2(-width * 0.5, -radius - size * 1.15, width, size * 1.15 + radius * 0.3).has_point(local)


func _draw() -> void:
	if faces.size() < 2:
		return
	for s: Dictionary in spots():
		if str(s.face.get("id", "")) == lifted:
			continue
		if str(s.face.get("id", "")) != hot or not fanned:
			_face(s.at, s.r, s.face)
	for s: Dictionary in spots():  # the hot one on top
		if str(s.face.get("id", "")) == hot and fanned and hot != lifted:
			_face(s.at, float(s.r) * float(grow.get(hot, 1.0)), s.face)
	var badge := Vector2(radius * 0.78, -radius * 0.72)
	var font := ThemeDB.fallback_font
	var text := "×%d" % faces.size()
	var fs := int(maxf(radius * 0.36, 10.0))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(badge - Vector2(w * 0.5 + 4, fs * 0.6), Vector2(w + 8, fs * 1.2))
	draw_style_box(_pill(), box)
	draw_string(font, Vector2(box.position.x + 4, box.position.y + fs * 0.95), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#fff4dc"))


func _face(at: Vector2, r: float, face: Dictionary) -> void:
	draw_circle(at, r + 2.0, Color("#3b2a1a"))
	var tex: Texture2D = face.get("texture")
	if tex != null:
		draw_texture_rect(tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false)
	else:
		draw_circle(at, r, Color("#8a7458"))


static var _pill_box: StyleBoxFlat

static func _pill() -> StyleBoxFlat:
	if _pill_box == null:
		_pill_box = StyleBoxFlat.new()
		_pill_box.bg_color = Color("#7a3b1e")
		_pill_box.border_color = Color("#fff4dc")
		_pill_box.set_border_width_all(1)
		_pill_box.set_corner_radius_all(8)
	return _pill_box


## A member dragged out of the fan (TASK-116): its face follows the mouse until let go.
class MemberDrag:
	extends Node2D

	var group := ""
	var member := ""
	var face := {}
	var r := 25.0

	func _draw() -> void:
		draw_circle(Vector2.ZERO, r + 3.0, Color("#3b2a1a"))
		var tex: Texture2D = face.get("texture")
		if tex != null:
			draw_texture_rect(tex, Rect2(-Vector2.ONE * r, Vector2.ONE * r * 2.0), false)
		var font := ThemeDB.fallback_font
		var text := str(face.get("name", ""))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(-w * 0.5, r + 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#fff4dc"))


## Letting go here groups (TASK-116): a gold ring and a "+" on the token under a dragged one.
class JoinHint:
	extends Node2D

	var r := 35.0

	func _draw() -> void:
		draw_arc(Vector2.ZERO, r + 4.0, 0, TAU, 48, Color("#f0c24b"), 4.0)
		var at := Vector2(r * 0.72, -r * 0.72)
		draw_circle(at, r * 0.32, Color("#f0c24b"))
		draw_circle(at, r * 0.32, Color("#3b2a1a"), false, 2.0)
		var w := r * 0.18
		draw_line(at - Vector2(w, 0), at + Vector2(w, 0), Color("#3b2a1a"), 3.0)
		draw_line(at - Vector2(0, w), at + Vector2(0, w), Color("#3b2a1a"), 3.0)
