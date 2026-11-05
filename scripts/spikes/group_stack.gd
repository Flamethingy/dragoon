class_name GroupStack
extends Node2D
## TASK-115, look A (Nico 2026-11-05): a group token shows its leader's picture (the token
## itself) with the other members small and overlapping at its lower right edge and a "×N"
## badge. Hovering fans them out above the token so every face is seen. A child of the token,
## unscaled like its Marks.

const SHOWN := 3  ## faces at the edge at most (the badge tells the rest)

var radius := 35.0  ## the token's radius in pixels
var faces: Array = []  ## [{id, name, texture}], the leader first
var fanned := false:
	set(v):
		if fanned != v:
			fanned = v
			queue_redraw()


func set_faces(list: Array, r: float) -> void:
	faces = list
	radius = r
	queue_redraw()


func _draw() -> void:
	var others := faces.slice(1)
	if others.is_empty():
		return
	if fanned:  # every member in a row above the token
		var size := radius * 0.8
		var step := size * 1.05
		var x0 := -step * (others.size() - 1) * 0.5
		for i in others.size():
			_face(Vector2(x0 + step * i, -radius - size * 0.65), size * 0.5, others[i])
	else:
		var size := radius * 0.72
		var shown := mini(others.size(), SHOWN)
		for i in range(shown - 1, -1, -1):  # the first one on top
			_face(Vector2(radius * 0.66 - i * size * 0.62, radius * 0.66 - i * size * 0.1), size * 0.5, others[i])
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


## The ring a double-click on a group token opens (TASK-115): every member around the token;
## one dragged out of it leaves the group at the square it is dropped on.
class Ring:
	extends Node2D

	var group := ""
	var members: Array = []  ## [{id, name, texture, at (local position)}]
	var dragged := ""
	var drag_at := Vector2.ZERO
	var size := 50.0

	func open(gid: String, faces: Array, token_size: float) -> void:
		group = gid
		size = token_size * 0.8
		members = []
		var r := token_size * 0.55 + size * 0.6
		for i in faces.size():
			var f: Dictionary = (faces[i] as Dictionary).duplicate()
			var angle := -PI * 0.5 + TAU * i / faces.size()
			f["at"] = Vector2(cos(angle), sin(angle)) * r
			members.append(f)
		visible = true
		queue_redraw()

	func close() -> void:
		group = ""
		members = []
		dragged = ""
		visible = false
		queue_redraw()

	func is_open() -> bool:
		return group != ""

	## The member under a map position ("" = none).
	func member_at(map_pos: Vector2) -> String:
		var local := map_pos - position
		for f: Dictionary in members:
			if (f.at as Vector2).distance_to(local) <= size * 0.5:
				return str(f.id)
		return ""

	func _draw() -> void:
		if members.is_empty():
			return
		var r := (members[0].at as Vector2).length()
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(1, 0.96, 0.86, 0.5), 2.0)
		var font := ThemeDB.fallback_font
		for f: Dictionary in members:
			var at: Vector2 = drag_at - position if str(f.id) == dragged else f.at
			draw_circle(at, size * 0.5 + 3.0, Color("#3b2a1a"))
			var tex: Texture2D = f.get("texture")
			if tex != null:
				draw_texture_rect(tex, Rect2(at - Vector2.ONE * size * 0.5, Vector2.ONE * size), false)
			var name := str(f.get("name", ""))
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, at + Vector2(-w * 0.5, size * 0.5 + 15), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#fff4dc"))
