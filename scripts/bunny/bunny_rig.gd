class_name BunnyRig
extends Node2D
## The Table Bunny's body (TASK-101): a port of Tamago's rig (D:/Godot/tamago,
## scripts/pet/rig.gd). Keep the two in step: see backlog doc "Bunny shared with Tamago".
## Dragoon additions are marked "Dragoon:" (the sleep pose, moods).
##
## Tamago's body: the parts of her PSD (tools/import_character.py turns it into atlas.png
## and rig.json), put together on simple bones and animated in code.
##
## Positions below are pixels on the PSD canvas, so redrawn art keeps working as long as
## the parts stay roughly where they are. The node's origin is the point between her feet;
## set `height` for her size on screen and `dir` for the way she faces.
##
## Animations: idle, walk, jump, fall, dragged (carried by the scruff), thinking (paw at
## her mouth), working (rummaging with both paws), listening (ears up), sleep (Dragoon: the
## host has no brain for it). `mood` (Dragoon: happy / sad / sleepy) colours a pose. Plus blinking,
## talking (`talking = true`) and a squash when she lands.
##
## Colours: set_colors({"fur": "#...", "hair": ...}) recolours her (shaders/recolor.gdshader);
## the slots and their drawn colours are the "palette" in rig.json.

const PART_DIR := "res://assets/bunny/"
const RECOLOR := preload("res://shaders/recolor.gdshader")
## Where her feet touch the floor, on the canvas.
const FEET := Vector2(1066, 993)
## The neck: her head turns here, and this is where she is held when carried.
const NECK := Vector2(1062, 752)

## Bones: [parent, pivot on the canvas]. Far-side bones mirror the near ones.
const BONES := {
	"root": ["", NECK],
	"hips": ["root", Vector2(1066, 930)],
	"head": ["hips", NECK],
	"ear": ["head", Vector2(988, 566)],
	"ear_far": ["head", Vector2(1136, 566)],  # mirrored about x = 1062
	"arm": ["hips", Vector2(1026, 810)],
	"arm_far": ["hips", Vector2(1134, 810)],  # about x = 1080
	"leg": ["root", Vector2(1030, 872)],
	"leg_far": ["root", Vector2(1102, 872)],  # about x = 1066
	"tail": ["hips", Vector2(990, 862)],
}

## How quickly poses blend into each other (higher = snappier).
const BLEND := 14.0

## Her height on screen in pixels (ear tips to feet).
var height := 140.0:
	set(value):
		height = value
		_update_scale()
## 1 = facing right (as drawn), -1 = facing left.
var dir := 1:
	set(value):
		dir = value
		_update_scale()
var anim := "idle"
var talking := false
var mood := "neutral"  ## Dragoon: happy wags, sad and sleepy droop the ears

var _parts := {}  ## part name -> {region: Rect2, rect: Rect2 (canvas)}
## How the parts are stacked (layout.json, shared with the dashboard's portraits), bottom to
## top: [name, part, bone, mirror about this x (0 = no), squeeze x]. The far ear, arm, leg
## and eye are the near ones mirrored (the PSD has one of each) and tinted _far_tint.
var _layers: Array = []
var _far_tint := Color(0.86, 0.87, 0.93)
var _tolerance := 0.06
var _palette := {}  ## colour slot -> Color as drawn
var _from: Array[Color] = []  ## recolouring: drawn colours (with black and white) ...
var _to: Array[Color] = []  ## ... and what they become
var _material := ShaderMaterial.new()
var _atlas_scale := 1.0
var _sprites := {}  ## layer name -> Sprite2D
var _variant := {}  ## layer name -> part currently shown (eyes and mouth change)
var _rest_rect := Rect2()
var _time := 0.0
var _rot := {}
var _pos := {}
var _scl := {}
var _t_rot := {}
var _t_pos := {}
var _t_scl := {}
var _last_anim := "idle"
var _squash := 0.0  ## landing squash, 1 -> 0
var _swing := 0.0  ## dangling angle while carried
var _swing_vel := 0.0
var _last_global := Vector2.ZERO
var _blink_in := 3.0
var _blink_t := -1.0
var _mouth_in := 0.0


func _ready() -> void:
	_load()
	for bone in BONES:
		_rot[bone] = 0.0
		_pos[bone] = Vector2.ZERO
		_scl[bone] = Vector2.ONE
	_update_scale()
	_last_global = global_position
	_apply()


func _load() -> void:
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PART_DIR + "rig.json"))
	_atlas_scale = rig.scale
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PART_DIR + "layout.json"))
	_layers = layout.layers
	_far_tint = Color(layout.far_tint[0], layout.far_tint[1], layout.far_tint[2])
	_tolerance = layout.recolor_tolerance
	for slot: String in rig.get("palette", {}):
		_palette[slot] = Color.html(rig.palette[slot])
	_material.shader = RECOLOR
	set_colors({})
	for name: String in rig.parts:
		var p: Dictionary = rig.parts[name]
		_parts[name] = {
			"region": Rect2(p.region[0], p.region[1], p.region[2], p.region[3]),
			"rect": Rect2(p.rect[0], p.rect[1], p.rect[2], p.rect[3]),
		}
	# Smooth art shown much smaller than drawn: linear filtering with mipmaps.
	var image: Image
	if ResourceLoader.exists(PART_DIR + "atlas.png"):
		image = (load(PART_DIR + "atlas.png") as Texture2D).get_image()
	else:  # not imported by the editor yet
		image = Image.load_from_file(ProjectSettings.globalize_path(PART_DIR + "atlas.png"))
	if image.is_compressed():
		image.decompress()
	image.generate_mipmaps()
	var atlas := ImageTexture.create_from_image(image)

	var rect := Rect2()
	for layer: Array in _layers:
		if not _parts.has(layer[1]):
			push_warning("The bunny's art has no part '%s'" % layer[1])
			continue
		var sprite := Sprite2D.new()
		sprite.texture = atlas
		sprite.centered = false
		sprite.region_enabled = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.material = _material
		if layer[3] != 0.0:
			sprite.modulate = _far_tint
		add_child(sprite)
		_sprites[layer[0]] = sprite
		_variant[layer[0]] = layer[1]
		# Her outline at rest, for clicking.
		var r := _part_transform(layer[1], layer[3], layer[4]) * Rect2(Vector2.ZERO, _parts[layer[1]].region.size)
		rect = r if rect.size == Vector2.ZERO else rect.merge(r)
	_rest_rect = Rect2(rect.position - FEET, rect.size)


func _update_scale() -> void:
	if _rest_rect.size.y > 0.0:
		var s := height / -_rest_rect.position.y
		scale = Vector2(s * dir, s)


## Her colours: {slot: "#rrggbb" or Color}; slots left out keep the colour as drawn.
func set_colors(colors: Dictionary) -> void:
	_from = [Color.BLACK, Color.WHITE]  # outlines and highlights stay, edges blend into them
	_to = [Color.BLACK, Color.WHITE]
	for slot: String in _palette:
		var value = colors.get(slot, "")
		_from.append(_palette[slot])
		if value is Color:
			_to.append(value)
		elif value is String and Color.html_is_valid(value):
			_to.append(Color.html(value))
		else:
			_to.append(_palette[slot])
	var from := PackedColorArray()
	var to := PackedColorArray()
	for i in 8:  # the shader's arrays have 8 places
		from.append(_from[i] if i < _from.size() else Color.BLACK)
		to.append(_to[i] if i < _to.size() else Color.BLACK)
	_material.set_shader_parameter("from_colors", from)
	_material.set_shader_parameter("to_colors", to)
	_material.set_shader_parameter("count", mini(_from.size(), 8))
	_material.set_shader_parameter("tolerance", _tolerance)


## The same recolouring for an image (e.g. her tray icon), done once on the CPU.
func recolor(image: Image) -> Image:
	var out := image.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var best := INF
			var result := c
			for i in _from.size():
				for j in range(i, _from.size()):
					var d := Vector3(_from[i].r - _from[j].r, _from[i].g - _from[j].g, _from[i].b - _from[j].b)
					var v := Vector3(c.r - _from[j].r, c.g - _from[j].g, c.b - _from[j].b)
					var s := 1.0 if i == j else clampf(v.dot(d) / maxf(d.dot(d), 1e-6), 0.0, 1.0)
					var e := (v - d * s).length()
					if e < best:
						best = e
						result = _to[j].lerp(_to[i], s)
			if best < _tolerance:
				out.set_pixel(x, y, Color(result.r, result.g, result.b, c.a))
	return out


## Her outline at rest, in this node's coordinates (origin between her feet).
func rest_rect() -> Rect2:
	return _rest_rect


## Where her neck is, in the parent's coordinates (she is carried by it).
func neck_position() -> Vector2:
	return transform * (NECK - FEET)


func _process(delta: float) -> void:
	_time += delta
	# Landing: a quick squash.
	if (_last_anim == "fall" or _last_anim == "jump") and anim != "fall" and anim != "jump" and anim != "dragged":
		_squash = 1.0
	_last_anim = anim
	_squash = maxf(_squash - delta * 5.0, 0.0)
	_update_swing(delta)
	_update_face(delta)

	for bone in BONES:
		_t_rot[bone] = 0.0
		_t_pos[bone] = Vector2.ZERO
		_t_scl[bone] = Vector2.ONE
	_pose(anim, _time)
	var w := 1.0 - exp(-BLEND * delta)
	for bone in BONES:
		_rot[bone] = lerpf(_rot[bone], _t_rot[bone], w)
		_pos[bone] = _pos[bone].lerp(_t_pos[bone], w)
		_scl[bone] = _scl[bone].lerp(_t_scl[bone], w)
	if _sprites.has("arm"):
		_sprites.arm.z_index = 1 if anim == "thinking" else 0  # paw in front of her face
	_apply()


# --- Poses ------------------------------------------------------------------------
# Rotations in radians, clockwise on screen when she faces right. Arms and legs hang
# down: negative turns them forward (towards where she looks). Ears stand up: positive
# tips them forward.

func _pose(name: String, t: float) -> void:
	match name:
		"walk":
			var w := t * 8.0
			_t_pos.hips = Vector2(0, -absf(sin(w)) * 10.0)
			_t_rot.leg = sin(w) * 0.45
			_t_rot.leg_far = -sin(w) * 0.45
			_t_rot.arm = -sin(w) * 0.35
			_t_rot.arm_far = sin(w) * 0.35
			_t_rot.head = sin(w * 2.0) * 0.03
			_t_rot.ear = -0.08 + sin(w * 2.0 - 1.0) * 0.08
			_t_rot.ear_far = -0.08 + sin(w * 2.0 - 1.4) * 0.08
			_t_rot.tail = sin(w * 2.0) * 0.25
		"jump":  # going up: stretched, paws spread, ears trailing
			_t_scl.hips = Vector2(0.93, 1.08)
			_t_rot.leg = 0.35
			_t_rot.leg_far = 0.25
			_t_rot.arm = 0.9
			_t_rot.arm_far = -1.3
			_t_rot.ear = -0.35
			_t_rot.ear_far = -0.3
			_t_rot.tail = 0.3
		"fall":  # coming down: paws flailing, ears up
			_t_rot.leg = -0.2
			_t_rot.leg_far = 0.15
			_t_rot.arm = 1.1 + sin(t * 18.0) * 0.2
			_t_rot.arm_far = -1.5 + sin(t * 18.0 + 1.5) * 0.2
			_t_rot.ear = 0.15
			_t_rot.ear_far = 0.1
			_t_rot.tail = -0.2
		"dragged":  # held by the scruff like a kitten: limp, dangling, content
			_t_scl.hips = Vector2(0.97, 1.04)
			_t_rot.head = 0.05
			_t_rot.leg = 0.08 + sin(t * 3.0) * 0.04
			_t_rot.leg_far = -0.04 + sin(t * 3.0 + 1.0) * 0.04
			_t_rot.arm = -0.25 + sin(t * 3.0 + 0.5) * 0.04
			_t_rot.arm_far = -0.18
			_t_rot.ear = -0.5
			_t_rot.ear_far = -0.35
			_t_rot.tail = -0.4
		"thinking":  # paw at her mouth, looking up, one ear wandering
			_breathe(t)
			_t_rot.arm = -2.5 + sin(t * 2.5) * 0.05
			_t_rot.head = -0.06 + sin(t * 0.8) * 0.03
			_t_rot.ear = 0.12 + sin(t * 1.1) * 0.06
			_t_rot.ear_far = -0.08
			_t_rot.tail = _wag(t) * 0.5
		"working":  # rummaging through files with both paws
			var w := t * 16.0
			_t_pos.hips = Vector2(0, -absf(sin(t * 8.0)) * 2.0)
			_t_rot.hips = 0.04
			_t_rot.arm = -1.2 + sin(w) * 0.3
			_t_rot.arm_far = -1.1 + sin(w + PI) * 0.3
			_t_rot.head = 0.1 + sin(t * 8.0) * 0.02
			_t_rot.ear = sin(t * 8.0) * 0.05
			_t_rot.ear_far = sin(t * 8.0 - 0.7) * 0.05
			_t_rot.tail = sin(t * 6.0) * 0.15
		"listening":  # ears up, head tilted
			_breathe(t)
			_t_rot.head = -0.05 + sin(t * 1.5) * 0.02
			_t_rot.ear = 0.05
			_t_rot.ear_far = -0.05
			_t_scl.ear = Vector2(1.0, 1.05)
			_t_scl.ear_far = Vector2(1.0, 1.05)
		"sleep":  # Dragoon: curled up a little, head down, ears flat, slow breaths
			var b := sin(t * 1.2)
			_t_scl.hips = Vector2(1.03 - 0.015 * b, 0.95 + 0.03 * b)
			_t_rot.head = 0.16
			_t_rot.ear = -0.55
			_t_rot.ear_far = -0.45
			_t_rot.arm = -0.35
			_t_rot.arm_far = -0.3
			_t_rot.tail = -0.15
		_:  # idle
			_breathe(t)
			_t_rot.head = sin(t * 0.9) * 0.025
			_t_rot.ear = sin(t * 1.3) * 0.05
			_t_rot.ear_far = sin(t * 1.3 - 0.6) * 0.05
			_t_rot.arm = sin(t * 2.2) * 0.03
			_t_rot.arm_far = sin(t * 2.2 + 0.4) * 0.03
			_t_rot.tail = _wag(t)
	# Dragoon: the answer's mood on top of the pose
	if mood == "happy" and name != "sleep":
		_t_rot.tail += sin(t * 12.0) * 0.2
		_t_rot.ear += 0.06
	elif mood in ["sad", "sleepy"] and name not in ["sleep", "dragged", "fall", "jump"]:
		_t_rot.ear -= 0.4
		_t_rot.ear_far -= 0.3
		_t_rot.head += 0.06


func _breathe(t: float) -> void:
	var b := sin(t * 2.2)
	_t_scl.hips = Vector2(1.0 - 0.012 * b, 1.0 + 0.02 * b)


## A little tail wag every few seconds.
func _wag(t: float) -> float:
	var phase := fmod(t, 5.0)
	return sin(phase * 14.0) * 0.25 if phase < 0.9 else 0.0


## Carried: she swings behind the cursor like a pendulum.
func _update_swing(delta: float) -> void:
	var vel := (global_position - _last_global) / maxf(delta, 0.001)
	_last_global = global_position
	var target := 0.0
	if anim == "dragged" and vel.length() < 20000.0:  # ignore jumps between screens
		target = clampf(vel.x * 0.0012, -0.7, 0.7) * dir
	_swing_vel += ((target - _swing) * 70.0 - _swing_vel * 5.0) * delta
	_swing += _swing_vel * delta


func _update_face(delta: float) -> void:
	# Blinking: half, closed, half, open. Carried she keeps her eyes half shut.
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = randf_range(2.0, 5.0)
		_blink_t = 0.0
	var eye := "eye_half_closed" if anim == "dragged" or mood == "sleepy" else "eye"
	if anim == "sleep":  # Dragoon
		_blink_t = -1.0
		eye = "eye_closed"
	if _blink_t >= 0.0:
		_blink_t += delta
		if _blink_t < 0.04 or (_blink_t >= 0.12 and _blink_t < 0.16):
			eye = "eye_half_closed"
		elif _blink_t < 0.12:
			eye = "eye_closed"
		else:
			_blink_t = -1.0
	_show("eye", eye)
	_show("eye_far", eye)
	# Talking: the mouth flaps between its three shapes.
	var mouth: String = _variant.get("mouth", "mouth_base")
	if talking or anim == "fall":
		_mouth_in -= delta
		if _mouth_in <= 0.0:
			_mouth_in = randf_range(0.07, 0.14)
			mouth = "mouth_open" if anim == "fall" else ["mouth_base", "mouth_half_closed", "mouth_open"].pick_random()
	else:
		mouth = "mouth_base"
	_show("mouth", mouth)


func _show(layer: String, part: String) -> void:
	if _sprites.has(layer) and _parts.has(part):
		_variant[layer] = part


# --- Putting it together ----------------------------------------------------------

func _apply() -> void:
	var bones := {}
	for bone: String in BONES:  # parents come first in BONES
		var parent: String = BONES[bone][0]
		var pivot: Vector2 = BONES[bone][1]
		var rot: float = _rot[bone]
		var scl: Vector2 = _scl[bone]
		if bone == "root":
			rot += _swing
		elif bone == "hips" and _squash > 0.0:
			scl *= Vector2(1.0 + 0.12 * _squash, 1.0 - 0.15 * _squash)
		var local := Transform2D(0.0, pivot + _pos[bone]) * Transform2D(rot, scl, 0.0, Vector2.ZERO) \
				* Transform2D(0.0, -pivot)
		var base: Transform2D = bones[parent] if parent != "" else Transform2D(0.0, -FEET)
		bones[bone] = base * local
	for layer: Array in _layers:
		var sprite: Sprite2D = _sprites.get(layer[0])
		if sprite == null:
			continue
		var part: String = _variant[layer[0]]
		sprite.region_rect = _parts[part].region
		sprite.transform = bones[layer[2]] * _part_transform(part, layer[3], layer[4])


## Atlas pixels -> canvas pixels for a part, mirrored and squeezed for the far side.
func _part_transform(part: String, mirror: float, squeeze: float) -> Transform2D:
	var rect: Rect2 = _parts[part].rect
	var t := Transform2D(0.0, Vector2.ONE / _atlas_scale, 0.0, rect.position)
	if mirror != 0.0:
		t = Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(2.0 * mirror, 0)) * t
		if squeeze != 1.0:
			var cx := 2.0 * mirror - rect.get_center().x
			t = Transform2D(0.0, Vector2(cx, 0)) * Transform2D(0.0, Vector2(squeeze, 1.0), 0.0, Vector2.ZERO) \
					* Transform2D(0.0, Vector2(-cx, 0)) * t
	return t
