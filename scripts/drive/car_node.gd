## The car of the live drive (round 21, V21.1): the picture of the vehicle's kind (assets/data/vehicles.json: `art`, `w`, `h`,
## `nose`) turned to the heading it drives, in the y-sorted node the people are in. A view: it is a pure function of what the scene
## tells it (`apply`: the car's middle, heading, steer, whether it brakes, its condition and how bright the headlights are) and
## nothing here touches a rule.
##
##   - the four wheels peek out at the sides of the body, the front pair turned by the steering;
##   - the brake lights are dim while it rolls, bright while it brakes (and while it backs);
##   - a worn car is darker (under half its hp) and one nearly done has a spanner over it (under 30%), as `vehicle_actor.gd`
##     draws the gate's cars; a wreck is the same picture, still;
##   - the headlights are an additive wedge of light ahead of the nose (the scene gives it `lights`, 0 for none), drawn
##     unshaded so that the night's tint does not take them down.
## No door animation on the road.
extends Node2D

const GD := preload("res://scripts/game_data.gd")

const TILE := GD.TILE
const OBJECTS := "res://assets/objects/"
const Z_PEOPLE := 6
## A car in less than this share of its hp is darker (the more, the worse), and in less than SPANNER_BELOW has a spanner.
const WORN_BELOW := 0.5
const SPANNER_BELOW := 0.3
const WORN_TINT := Color(0.5, 0.46, 0.44)
## How far the front wheels turn at full lock (radians), and the wheels' size (tiles).
const STEER_LOCK := 0.5
const WHEEL_LEN := 0.62
const WHEEL_WID := 0.22
## The wedge of the headlights: how far it reaches (tiles) and how wide it is at the far end.
const BEAM_LEN := 15.0
const BEAM_WIDE := 5.5

var kind: Dictionary = {}
var kind_id := ""
var body: Node2D
var body_sprite: Sprite2D
var gear: Node2D            # (the wheels, under the body, in the car's own frame: x along the nose)
var lamps: Node2D           # (the brake lights, over it)
var beam: Polygon2D
var mark: Node2D
## What it was last given (for the tests and the overlay).
var pose: Dictionary = {}
var worn := 0.0

var _nose := "N"
var _size := Vector2.ONE
var _original: Texture2D
var _steer := 0.0
var _braking := false
var _lights := 0.0


## Makes the nodes of a car of `kind_data` (its record in vehicles.json); false when its picture is not there.
func setup(id: String, kind_data: Dictionary) -> bool:
	kind_id = id
	kind = kind_data
	var art := String(kind.get("art", ""))
	var path := OBJECTS + art + ".png"
	if art == "" or not ResourceLoader.exists(path):
		return false
	_original = GD.tex(path)
	_size = Vector2(_original.get_width(), _original.get_height())
	_nose = String(kind.get("nose", ""))
	if not _nose in ["N", "S", "E", "W"]:
		_nose = "E" if (_size.x > _size.y) == (float(kind.get("h", 4.0)) >= float(kind.get("w", 2.0))) else "N"
	z_as_relative = false
	z_index = Z_PEOPLE
	var w := float(kind.get("w", 2.0))
	var h := float(kind.get("h", 4.5))
	gear = Gear.new()
	gear.name = "Gear"
	gear.setup(h, w)
	add_child(gear)
	body = Node2D.new()
	body.name = "Body"
	if _nose == "E" or _nose == "W":
		body.scale = Vector2(h * TILE / _size.x, w * TILE / _size.y)
	else:
		body.scale = Vector2(w * TILE / _size.x, h * TILE / _size.y)
	add_child(body)
	body_sprite = Sprite2D.new()
	body_sprite.texture = _original
	body.add_child(body_sprite)
	lamps = Lamps.new()
	lamps.name = "Lamps"
	lamps.setup(h, w)
	add_child(lamps)
	beam = _make_beam(h)
	add_child(beam)
	mark = Mark.new()
	mark.visible = false
	add_child(mark)
	return true


## The unit vector the picture's nose points along in the picture's own pixels (y grows down).
func _nose_unit() -> Vector2:
	match _nose:
		"S":
			return Vector2(0, 1)
		"E":
			return Vector2(1, 0)
		"W":
			return Vector2(-1, 0)
	return Vector2(0, -1)


func _make_beam(length: float) -> Polygon2D:
	var p := Polygon2D.new()
	p.name = "Beam"
	var x0 := length * 0.5 * TILE
	var far := BEAM_LEN * TILE
	var wide := BEAM_WIDE * TILE
	# (the wedge is drawn from the nose: a bright centre line, the edges and the far end fade to nothing)
	p.polygon = PackedVector2Array([
		Vector2(x0, 0), Vector2(x0, -0.8 * TILE), Vector2(x0 + far, -wide), Vector2(x0 + far * 1.1, 0), Vector2(x0 + far, wide), Vector2(x0, 0.8 * TILE)])
	p.polygons = [PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 2, 3]), PackedInt32Array([0, 3, 4]), PackedInt32Array([0, 4, 5])]
	p.vertex_colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0)])
	p.z_as_relative = false
	p.z_index = 8
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	p.material = mat
	p.visible = false
	return p


## Half the box the car takes on the ground (tiles) at that heading.
func half_extent(dir: Vector2) -> Vector2:
	var a := float(kind.get("h", 4.5)) / 2.0
	var b := float(kind.get("w", 2.0)) / 2.0
	return Vector2(absf(dir.x) * a + absf(dir.y) * b, absf(dir.y) * a + absf(dir.x) * b)


## Poses the car: its middle (tiles), the heading of its nose (radians, 0 east), the steering (-1 left to 1 right), whether the brake
## lights are on, its condition (0 to 1) and how bright the headlights are (0 to 1, 0 for none).
func apply(pos: Vector2, heading: float, steer: float, braking: bool, share: float, lights: float) -> void:
	var dir := Vector2.from_angle(heading)
	var ext := half_extent(dir)
	position = Vector2(pos.x, pos.y + ext.y) * TILE
	body.position = Vector2(0.0, -ext.y * TILE)
	body.rotation = heading - _nose_unit().angle()
	gear.position = body.position
	gear.rotation = heading
	lamps.position = body.position
	lamps.rotation = heading
	beam.position = body.position
	beam.rotation = heading
	mark.position = Vector2(0.0, -ext.y * 2.0 * TILE - 12.0)
	pose = {"pos": pos, "heading": heading, "steer": steer, "braking": braking, "share": share, "lights": lights}
	_tint(share)
	if absf(steer - _steer) > 0.02 or braking != _braking:
		_steer = steer
		_braking = braking
		gear.set_state(clampf(steer, -1.0, 1.0) * STEER_LOCK)
		lamps.set_state(braking)
	if absf(lights - _lights) > 0.01:
		_lights = lights
		var a := clampf(lights, 0.0, 1.0)
		beam.visible = a > 0.01
		var colors := PackedColorArray()
		for k in [0.95, 0.5, 0.0, 0.18, 0.0, 0.5]:
			colors.append(Color(1.0, 0.93, 0.7, float(k) * a * 0.8))
		beam.vertex_colors = colors


func _tint(share: float) -> void:
	worn = clampf((WORN_BELOW - share) / WORN_BELOW, 0.0, 1.0)
	var c := Color.WHITE.lerp(WORN_TINT, worn)
	if body_sprite.modulate != c:
		body_sprite.modulate = c
	mark.visible = share < SPANNER_BELOW


## The rect the car takes in the world (tiles); empty before it is posed.
func rect() -> Rect2:
	if pose.is_empty():
		return Rect2()
	var ext := half_extent(Vector2.from_angle(float(pose.heading)))
	return Rect2(Vector2(pose.pos) - ext, ext * 2.0)


## How far the front wheels are turned now (radians), whether the brake lights are lit and how bright (for the tests).
func wheel_angle() -> float:
	return gear.front_angle if gear != null else 0.0


func brake_lit() -> bool:
	return lamps != null and lamps.braking


func lights_on() -> bool:
	return beam != null and beam.visible


## The wheels, in the car's frame: x along the nose, y to its right, in world pixels from the middle. They peek out of the body's sides.
class Gear:
	extends Node2D

	var length := 4.0
	var width := 2.0
	var front_angle := 0.0

	func setup(l: float, w: float) -> void:
		length = l
		width = w

	func set_state(angle: float) -> void:
		front_angle = angle
		queue_redraw()

	func _draw() -> void:
		var tire := Color(0.07, 0.07, 0.08, 0.95)
		var hx := length * 0.5 * TILE
		var hy := width * 0.5 * TILE
		var lw := WHEEL_LEN * TILE
		var ww := WHEEL_WID * TILE
		for spec in [[hx * 0.62, -1.0, true], [hx * 0.62, 1.0, true], [-hx * 0.62, -1.0, false], [-hx * 0.62, 1.0, false]]:
			var c := Vector2(float(spec[0]), float(spec[1]) * (hy - ww * 0.18))
			draw_set_transform(c, front_angle if bool(spec[2]) else 0.0, Vector2.ONE)
			draw_rect(Rect2(-lw / 2.0, -ww / 2.0, lw, ww), tire)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The brake lights, over the body: dim while it rolls, bright on the brake.
class Lamps:
	extends Node2D

	var length := 4.0
	var width := 2.0
	var braking := false

	func setup(l: float, w: float) -> void:
		length = l
		width = w
		queue_redraw()

	func set_state(brake: bool) -> void:
		braking = brake
		queue_redraw()

	func _draw() -> void:
		var hx := length * 0.5 * TILE
		var hy := width * 0.5 * TILE
		var level := 1.0 if braking else 0.4
		var lamp := Color(0.95, 0.12, 0.08, 0.5 + 0.5 * level)
		var glow := Color(1.0, 0.2, 0.12, 0.3 * level)
		var r := 0.09 * TILE
		for side in [-1.0, 1.0]:
			var c := Vector2(-hx * 0.97, float(side) * hy * 0.62)
			draw_circle(c, r * 2.4, glow)
			draw_circle(c, r, lamp)


## A small spanner in an amber plate over a car that is nearly worn out.
class Mark:
	extends Node2D

	func _draw() -> void:
		var plate := Color("#f1c24a")
		var ink := Color("#2b2113")
		draw_circle(Vector2.ZERO, 11.5, ink)
		draw_circle(Vector2.ZERO, 9.8, plate)
		var dir := Vector2(1, -1).normalized()
		draw_line(-dir * 6.2, dir * 3.8, ink, 3.2, true)
		draw_arc(dir * 5.4, 3.3, 0.0, TAU, 12, ink, 2.6, true)
		draw_line(dir * 5.4, dir * 7.8, plate, 3.0, true)
