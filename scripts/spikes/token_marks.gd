class_name TokenMarks
extends Node2D
## Drawn on top of a token (TASK-42): a small triangle at its edge where the character looks
## (8 directions) and a ring: white while it is selected, orange while it is the active one
## (TASK-44: the HUD's character). A child of the token's sprite, unscaled.

const SELECTED := Color(1.0, 1.0, 1.0, 0.95)
const ACTIVE := Color(1.0, 0.55, 0.1, 1.0)

var radius := 35.0
var facing := ""  ## n, ne, e, se, s, sw, w, nw ("" = none yet)
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var active := false:
	set(value):
		active = value
		queue_redraw()
## An attack's target (TASK-54): a red ring.
var targeted := false:
	set(value):
		targeted = value
		queue_redraw()
## The conditions on it (TASK-56): [{abbr, color, name}], drawn as small discs along its rim.
var conditions: Array = []:
	set(value):
		conditions = value
		queue_redraw()


func set_facing(f: String) -> void:
	facing = f
	queue_redraw()


func _draw() -> void:
	if active or selected:  # one ring: orange when active, white when only selected
		draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 48, ACTIVE if active else SELECTED, 4.0, true)
	if targeted:
		draw_arc(Vector2.ZERO, radius + 9.0, 0, TAU, 48, Color(0.85, 0.12, 0.1), 3.0, true)
	_draw_conditions()
	if facing == "" or not TokenGrid.FACINGS.has(facing):
		return
	var dir := Vector2(TokenGrid.FACINGS[facing]).normalized()
	var side := dir.orthogonal()
	var tip := dir * (radius + 16.0)
	var base := dir * (radius + 2.0)
	var pts := PackedVector2Array([tip, base + side * 10.0, base - side * 10.0])
	draw_colored_polygon(pts, Color(0.98, 0.94, 0.85))
	draw_polyline(PackedVector2Array([tip, base + side * 10.0, base - side * 10.0, tip]), Color(0.2, 0.12, 0.1), 2.0, true)


## Discs from the lower left round to the lower right: its short name on its colour.
func _draw_conditions() -> void:
	if conditions.is_empty():
		return
	var font := ThemeDB.fallback_font
	var r := clampf(radius * 0.28, 9.0, 16.0)
	var step := (r * 2.1) / maxf(radius, 1.0)
	var start := PI * 0.5 + step * (conditions.size() - 1) * 0.5
	for i in conditions.size():
		var c: Dictionary = conditions[i]
		var a := start - step * i
		var at := Vector2(cos(a), sin(a)) * radius
		draw_circle(at, r + 1.5, Color(0.12, 0.08, 0.06))
		draw_circle(at, r, c.get("color", Color.GRAY))
		var text := str(c.get("abbr", "?"))
		var fs := int(r * 0.95)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, at + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
