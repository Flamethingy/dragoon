class_name TokenMarks
extends Node2D
## Drawn on top of a token (TASK-42): a small triangle at its edge where the character looks
## (8 directions) and a ring while it is selected. A child of the token's sprite, unscaled.

var radius := 35.0
var facing := ""  ## n, ne, e, se, s, sw, w, nw ("" = none yet)
var selected := false:
	set(value):
		selected = value
		queue_redraw()


func set_facing(f: String) -> void:
	facing = f
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 48, Color(1.0, 0.86, 0.35, 0.95), 4.0, true)
	if facing == "" or not TokenGrid.FACINGS.has(facing):
		return
	var dir := Vector2(TokenGrid.FACINGS[facing]).normalized()
	var side := dir.orthogonal()
	var tip := dir * (radius + 16.0)
	var base := dir * (radius + 2.0)
	var pts := PackedVector2Array([tip, base + side * 10.0, base - side * 10.0])
	draw_colored_polygon(pts, Color(0.98, 0.94, 0.85))
	draw_polyline(PackedVector2Array([tip, base + side * 10.0, base - side * 10.0, tip]), Color(0.2, 0.12, 0.1), 2.0, true)
