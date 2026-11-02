class_name Die3D
extends RigidBody3D
## One 3D die (TASK-61): a physically tumbling polyhedron (d4, d6, d8, d10, d12, d20) with its
## numbers on the faces. The host's result stays authoritative: while it slows down, and once
## more when it lies still, the numbers are swapped so the face that ends up on top shows
## `value` (no reroll, no fake physics).

signal settled

const UP := Vector3.UP

var sides := 20
var value := 1  ## the host's result (d10: 1-10, shown as 0 for 10 on a percentile die)
var color := Color(0.55, 0.12, 0.12)
var tens := false  ## a d100's tens die: 00, 10 ... 90
var glow := false  ## a critical: it lights up when it lands
var faces: Array = []  ## [{normal: Vector3, center: Vector3}]
var labels: Array[Label3D] = []
var face_values: Array[int] = []
var is_settled := false
var _still := 0.0
var _age := 0.0
var _fixed := false


func _ready() -> void:
	var shape := DieShapes.shape(sides)
	faces = shape.faces
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = shape.mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.35
	mat.metallic = 0.1
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.75, 0.3)
		mat.emission_energy_multiplier = 0.0
	mesh.material_override = mat
	add_child(mesh)
	var col := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = shape.points
	col.shape = convex
	add_child(col)
	mass = 0.3
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.6
	physics_material_override = pm
	continuous_cd = true
	var ink := Color.WHITE if color.get_luminance() < 0.6 else Color(0.1, 0.08, 0.06)
	for i in faces.size():
		face_values.append(i + 1)
		var l := Label3D.new()
		l.name = "Face%d" % (i + 1)
		l.font_size = 64
		l.pixel_size = 0.0045 * shape.label_scale
		l.outline_size = 8
		l.modulate = ink
		l.outline_modulate = Color(0, 0, 0, 0.5) if ink == Color.WHITE else Color(1, 1, 1, 0.4)
		l.double_sided = false
		var c: Vector3 = faces[i].center
		var n: Vector3 = faces[i].normal
		l.position = c + n * 0.012
		var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		l.basis = Basis.looking_at(-n, up)
		add_child(l)
		labels.append(l)
	_shuffle_labels()


func _shuffle_labels() -> void:
	var vals: Array[int] = []
	for i in faces.size():
		vals.append(i + 1)
	vals.shuffle()
	for i in faces.size():
		_set_face(i, vals[i])


func _set_face(i: int, v: int) -> void:
	face_values[i] = v
	labels[i].text = _text(v)


func _text(v: int) -> String:
	if tens:
		return "%02d" % ((v % 10) * 10)
	if sides == 10:
		return str(v % 10)
	return str(v) + ("." if sides >= 8 and v in [6, 9] else "")


## The face that points up now.
func up_face() -> int:
	var best := 0
	var best_dot := -2.0
	for i in faces.size():
		var d := (global_basis * (faces[i].normal as Vector3)).normalized().dot(UP)
		if d > best_dot:
			best_dot = d
			best = i
	return best


## The value shown on top.
func value_up() -> int:
	return face_values[up_face()]


## Makes the top face show `value` (swaps two faces' numbers).
func _fix() -> void:
	var up := up_face()
	if face_values[up] == value:
		return
	var other := face_values.find(value)
	if other < 0:
		return
	_set_face(other, face_values[up])
	_set_face(up, value)


func _physics_process(delta: float) -> void:
	if is_settled:
		return
	_age += delta
	if not _fixed and _age > 0.5 and angular_velocity.length() < 3.0:
		_fix()  # while it slows down: the swap hides in the tumble
		_fixed = true
	if linear_velocity.length() < 0.06 and angular_velocity.length() < 0.08:
		_still += delta
	else:
		_still = 0.0
	if _still > 0.25 or _age > 6.0:
		_fix()  # still lying: once more, to be sure
		is_settled = true
		freeze = true
		if glow:
			_light_up()
		settled.emit()


## A crit: the die glows and a little light flashes over it.
func _light_up() -> void:
	var mat := (get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.omni_range = 2.5
	light.light_energy = 0.0
	light.position = Vector3(0, 0.8, 0)
	add_child(light)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mat, "emission_energy_multiplier", 0.6, 0.25)
	tw.tween_property(light, "light_energy", 3.0, 0.25)
	tw.chain().tween_property(light, "light_energy", 1.2, 0.6)
