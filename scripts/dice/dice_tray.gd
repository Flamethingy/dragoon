class_name DiceTray
extends SubViewportContainer
## 3D dice tumbling over the table (TASK-61, Nico's group never uses physical dice): every
## roll card in my feed throws its dice (Jolt physics) from the edge of the screen; each one
## lands on the host's number (Die3D swaps its face numbers, never rerolls). The roller's
## account colour; hidden DM rolls only reach the DM's feed anyway. A natural 20 glows.
## Settings (user://dice.cfg): on / off, speed, how long they stay.

const MAX_DICE := 24
const SIDES := [4, 6, 8, 10, 12, 20, 100]

static var settings_file := "user://dice.cfg"
## Headless (the tests) throws no dice unless a test asks for them.
static var force := false

var table: NetTable
var world: Node3D
var camera: Camera3D
var dice: Array[Die3D] = []
var _viewport: SubViewport
var _clear_at := 0.0
var _half := Vector2(5, 3)


func _ready() -> void:
	name = "DiceTray"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	world = Node3D.new()
	world.name = "World"
	_viewport.add_child(world)
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(0, 9, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.78, 0.72)
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)
	_build_walls()
	resized.connect(_build_walls)
	if table != null:
		table.roll_shown.connect(throw_entry)


## The floor and four walls at the edges of what the camera sees.
func _build_walls() -> void:
	if world == null:
		return
	var old := world.get_node_or_null("Walls")
	if old != null:
		old.free()
	var aspect := size.x / size.y if size.y > 0 else 16.0 / 9.0
	var half_h := camera.position.y * tan(deg_to_rad(camera.fov / 2.0)) * 0.92
	_half = Vector2(half_h * aspect, half_h)
	var walls := StaticBody3D.new()
	walls.name = "Walls"
	world.add_child(walls)
	_box(walls, Vector3(0, -0.5, 0), Vector3(_half.x * 4, 1, _half.y * 4))  # the floor
	for side: Array in [[Vector3(_half.x + 0.5, 2, 0), Vector3(1, 6, _half.y * 4)], [Vector3(-_half.x - 0.5, 2, 0), Vector3(1, 6, _half.y * 4)],
			[Vector3(0, 2, _half.y + 0.5), Vector3(_half.x * 4, 6, 1)], [Vector3(0, 2, -_half.y - 0.5), Vector3(_half.x * 4, 6, 1)]]:
		_box(walls, side[0], side[1])
	_box(walls, Vector3(0, 6, 0), Vector3(_half.x * 4, 1, _half.y * 4))  # a lid: nothing flies off


func _box(body: StaticBody3D, at: Vector3, extent: Vector3) -> void:
	var c := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = extent
	c.shape = b
	c.position = at
	body.add_child(c)


## The settings: {enabled, speed (1 normal, 1.6 fast), linger (seconds on the table)}.
static func settings() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	return {"enabled": bool(cfg.get_value("dice", "enabled", true)), "speed": float(cfg.get_value("dice", "speed", 1.0)),
		"linger": float(cfg.get_value("dice", "linger", 3.0))}


static func set_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	cfg.set_value("dice", key, value)
	cfg.save(settings_file)


## The dice of a roll card: [{sides, value, tens, glow}] (a d100 as two d10s).
static func dice_of(entry: Dictionary) -> Array:
	var out := []
	for r: Variant in entry.get("results", []):
		if not r is Dictionary:
			continue
		var terms := Dice.parse(str(r.get("formula", ""))).filter(func(t: Dictionary) -> bool: return t.has("sides"))
		var rolled: Array = r.get("dice", [])
		for i in mini(terms.size(), rolled.size()):
			var sides := int(terms[i].sides)
			for v: Variant in rolled[i]:
				var n := int(v)
				if sides == 100:
					out.append({"sides": 10, "value": (n / 10) % 10 if (n / 10) % 10 != 0 else 10, "tens": true})
					out.append({"sides": 10, "value": n % 10 if n % 10 != 0 else 10})
				elif sides in SIDES:
					out.append({"sides": sides, "value": n, "glow": sides == 20 and n == 20 and str(r.get("crit", "")) == "20"})
	return out


## Throws the dice of a roll card (if the dice are on).
func throw_entry(entry: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" and not force:
		return
	var s := settings()
	if not bool(s.enabled):
		return
	var list := dice_of(entry)
	if list.is_empty():
		return
	var color := Color(0.55, 0.12, 0.12)
	if table != null:
		var acc: Dictionary = table.accounts.get(str(entry.get("by", "")), {})
		if Color.html_is_valid(str(acc.get("color", ""))):
			color = Color.html(str(acc.color))
	throw(list.slice(0, MAX_DICE), color, float(s.speed), float(s.linger))


## Throws dice [{sides, value, tens, glow}] in `color`.
func throw(list: Array, color: Color, speed := 1.0, linger := 3.0) -> Array[Die3D]:
	clear()
	var made: Array[Die3D] = []
	var from_left := randf() < 0.5
	for i in list.size():
		var d := Die3D.new()
		d.sides = int(list[i].sides)
		d.value = int(list[i].value)
		d.tens = bool(list[i].get("tens", false))
		d.glow = bool(list[i].get("glow", false))
		d.color = color if not d.tens else color.darkened(0.25)
		var x := (-_half.x + 0.8) if from_left else (_half.x - 0.8)
		d.position = Vector3(x, 2.0 + (i % 3) * 0.6, randf_range(-_half.y * 0.6, _half.y * 0.6))
		d.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		d.gravity_scale = 2.0 * speed * speed
		world.add_child(d)
		d.linear_velocity = Vector3((1.0 if from_left else -1.0) * randf_range(7, 11), randf_range(-1, 1), randf_range(-3, 3)) * speed
		d.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20)) * speed
		d.settled.connect(_on_settled)
		dice.append(d)
		made.append(d)
	_clear_at = 0.0
	set_meta("linger", linger)
	return made


func _on_settled() -> void:
	if dice.all(func(d: Die3D) -> bool: return d.is_settled):
		_clear_at = Time.get_ticks_msec() / 1000.0 + float(get_meta("linger", 3.0))


func _process(_delta: float) -> void:
	if _clear_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _clear_at:
		clear()


## Takes the dice off the table.
func clear() -> void:
	for d in dice:
		if is_instance_valid(d):
			d.queue_free()
	dice.clear()
	_clear_at = 0.0


## True while dice are rolling or lying on the table.
func busy() -> bool:
	return not dice.is_empty()
