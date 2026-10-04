## Birds on the roofs and the walls (round 24, "base life"): a handful of pigeons that perch on the school's brick wall, the rail of the
## north walkway and the sandbags of the towers by day. A perched bird pecks and hops now and then; a shot, the groan of one of the dead
## close by, the bell or a crash makes the birds near it flush (`on_event` is given the rules' events by main.gd): they take off with
## a clatter of wings, fly off the screen and come back some seconds after it is quiet again, landing on a spot that is free. At dusk the
## birds go to roost (they fly away and stay away) and they come back with the day. Under "reduce motion" they only sit (no flush,
## no hop) by day and are not there by night.
##
## Seven birds, each a small state machine ("perched", "flying" to a spot or off, "away") that goes on whether or not it is seen. The picture is
## ONE MultiMesh of seven instances of one side-on bird (a shadow, a body, a head and beak, a wing) in ONE draw call: each instance's place
## and flip are its transform, and its custom data says how far it is flying (the wing beats from the vertex shader below, and the body rises
## from its shadow, which stays on the ground), the beat's phase, the lift and the peck. The instances are set at 20 Hz while one is on the
## screen; a bird that is away is a zero-size instance. No sprite, no allocation in a frame.
##
## The mesh's UV.x says what a vertex belongs to: 0 the body, 1 the wing, 2 the shadow, 3 the head.
extends MultiMeshInstance2D

const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
## Where birds sit (tiles): the school's north wall, the walkway's rail by the north wall, the sandbags of the two towers.
const PERCHES := [
	Vector2(34.2, 44.3), Vector2(37.6, 44.3), Vector2(41.0, 44.3), Vector2(46.2, 44.3), Vector2(55.3, 44.3), Vector2(58.6, 44.3),
	Vector2(28.5, 19.75), Vector2(33.4, 19.75), Vector2(45.6, 19.75), Vector2(52.5, 19.75), Vector2(56.6, 19.75),
	Vector2(18.2, 15.3), Vector2(19.8, 15.3), Vector2(64.4, 15.3), Vector2(66.0, 15.3),
]
const COUNT := 7
const FLY_SPEED := 7.5
## How far from a noise a perched bird is startled (tiles), by what made it.
const STARTLE := {"shot": 17.0, "groan": 9.0, "crash": 60.0, "bell": 60.0, "lure": 60.0, "stab": 8.0, "bite": 8.0}
## How long it must have been quiet before a bird comes back (seconds), and the pause before the first return.
const QUIET_S := 6.0
const BODY := Color("#5d5f68")
const BODY_HI := Color("#8b8e99")
const WING := Color("#474952")
const INK := Color(0.10, 0.08, 0.06, 0.85)
const BEAK := Color("#d7a64c")

const SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
void vertex() {
	float part = UV.x;
	float fly = INSTANCE_CUSTOM.x;
	float phase = INSTANCE_CUSTOM.y;
	float lift = INSTANCE_CUSTOM.z;
	float peck = INSTANCE_CUSTOM.w;
	if (part > 0.5 && part < 1.5) {
		// the wing turns about the shoulder: folded back on the body at rest, beating in flight
		float a = mix(-1.3, -0.3 + sin(t * 17.0 + phase) * 1.0, fly);
		vec2 d = VERTEX - vec2(-1.0, -7.0);
		float c = cos(a);
		float s = sin(a);
		VERTEX = vec2(-1.0, -7.0) + vec2(d.x * c - d.y * s, d.x * s + d.y * c);
		VERTEX.y -= lift;
	} else if (part > 2.5) {
		VERTEX.y += peck * 2.5 - lift;
	} else if (part < 0.5) {
		VERTEX.y -= lift;
	}
}
"


class Bird:
	extends RefCounted
	var state := "away"          # "perched" | "flying" | "away"
	var perch := -1              # the spot it sits on or is flying to (-1: flying off)
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var pos := Vector2.ZERO
	var fly_t := 0.0
	var fly_len := 1.0
	var timer := 0.0             # perched: until the next hop; away: until it may come back
	var face := 1.0
	var phase := 0.0
	var hop := 0.0
	var peck := 0.0


var birds: Array = []
var t := 0.0
var moving := true
var day := true
## The animation time of the last noise (the birds wait for QUIET_S of quiet), the view in tiles (what is drawn) and the counts for the tests.
var last_noise := -100.0
var view := Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
var flushes := 0
var landings := 0
var _rng := RandomNumberGenerator.new()
var _since := 0.0
var _drawn := false
var _mat: ShaderMaterial


func setup(seed_value: int = 11) -> void:
	z_index = 7
	name = "Birds"
	_rng.seed = seed_value
	_mat = Kit.material(SHADER)
	material = _mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _bake()
	mm.instance_count = COUNT
	multimesh = mm
	for i in COUNT:
		mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))    # (nothing is seen until a bird is written)
	for i in COUNT:
		var b := Bird.new()
		b.phase = _rng.randf() * TAU
		b.timer = _rng.randf_range(0.5, 4.0)
		birds.append(b)
		if i < 4:
			_land(b, _free_perch(), false)
		else:
			b.state = "away"
			b.timer = _rng.randf_range(3.0, 14.0)


## A spot no bird is on or going to (-1 when all are taken).
func _free_perch() -> int:
	var order: Array = range(PERCHES.size())
	for i in order.size():
		var j := _rng.randi() % order.size()
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	for spot in order:
		var taken := false
		for b in birds:
			if b.perch == spot and b.state != "away":
				taken = true
		if not taken:
			return int(spot)
	return -1


func _land(b: Bird, spot: int, fly: bool) -> void:
	if spot < 0:
		b.state = "away"
		b.timer = 5.0
		return
	b.perch = spot
	b.to = PERCHES[spot]
	b.face = 1.0 if _rng.randf() < 0.5 else -1.0
	if fly:
		# in from beyond the edge of the yard (a point 22 tiles off, up and to one side)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		b.from = b.to + Vector2(side * 24.0, -14.0 - _rng.randf() * 10.0)
		b.pos = b.from
		b.state = "flying"
		b.fly_t = 0.0
		b.fly_len = maxf(0.5, b.from.distance_to(b.to) / FLY_SPEED)
	else:
		b.state = "perched"
		b.pos = b.to
		b.timer = _rng.randf_range(1.0, 5.0)


## A bird takes off from where it sits and flies off the screen (`up`: toward the north, as the walkway and the towers have no south).
func _flush(b: Bird) -> void:
	b.state = "flying"
	b.perch = -1
	b.from = b.pos
	var dir := Vector2(_rng.randf_range(-1.0, 1.0), -1.0).normalized()
	b.to = b.pos + dir * 26.0
	b.fly_t = 0.0
	b.fly_len = 26.0 / FLY_SPEED
	b.face = 1.0 if dir.x >= 0.0 else -1.0
	flushes += 1


## The rules' events (main.gd gives each one): a noise within its reach startles the perched birds near where it was made.
func on_event(e: Dictionary) -> int:
	var kind := String(e.get("type", ""))
	if not STARTLE.has(kind) or not moving:
		return 0
	last_noise = t
	var reach: float = STARTLE[kind]
	var at := Vector2(float(e.get("x", 1.0e6)), float(e.get("y", 1.0e6)))
	var n := 0
	for b in birds:
		if b.state == "perched" and (not e.has("x") or b.pos.distance_to(at) <= reach):
			_flush(b)
			n += 1
	return n


## A person this close (tiles) to a perched bird startles it.
func shoo(people: Array, reach: float = 1.6) -> void:
	for b in birds:
		if b.state != "perched" or not moving:
			continue
		for p in people:
			if Vector2(float(p.x), float(p.y)).distance_to(b.pos) <= reach:
				_flush(b)
				break


func tick(dt: float, clock: float, is_day: bool, animate: bool) -> void:
	t = clock
	moving = animate
	var was_day := day
	day = is_day
	var any_seen := false
	for b in birds:
		match b.state:
			"perched":
				if not day or not animate:
					if not animate and not day:
						b.state = "away"
					elif not day:
						_flush(b)
				else:
					b.timer -= dt
					b.hop = maxf(0.0, b.hop - dt * 4.0)
					b.peck = maxf(0.0, b.peck - dt * 3.0)
					if b.timer <= 0.0:
						b.timer = _rng.randf_range(1.2, 5.0)
						if _rng.randf() < 0.5:
							b.hop = 1.0
							if _rng.randf() < 0.3:
								b.face = -b.face
						else:
							b.peck = 1.0
			"flying":
				b.fly_t += dt
				var k := minf(1.0, b.fly_t / b.fly_len)
				b.pos = b.from.lerp(b.to, k)
				if k >= 1.0:
					if b.perch >= 0:
						b.state = "perched"
						b.pos = b.to
						b.timer = _rng.randf_range(1.0, 4.0)
						landings += 1
					else:
						b.state = "away"
						b.timer = _rng.randf_range(6.0, 22.0)
			_:
				if day and animate:
					b.timer -= dt
					if b.timer <= 0.0 and t - last_noise >= QUIET_S and (was_day or day):
						_land(b, _free_perch(), true)
						b.timer = 0.0
		if b.state != "away" and view.has_point(b.pos):
			any_seen = true
	_since += dt
	if (any_seen or _drawn) and _since >= 0.05:
		_since = 0.0
		_drawn = any_seen
		_show()
	visible = any_seen or _drawn
	_mat.set_shader_parameter("t", t)


## Writes the seven instances: where each bird is and which way it faces, and how far it flies, its beat, its lift and its peck.
func _show() -> void:
	var mm := multimesh
	for i in birds.size():
		var b: Bird = birds[i]
		if b.state == "away" or not view.has_point(b.pos):
			mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
			continue
		var fly := 1.0 if b.state == "flying" else 0.0
		var lift := 0.0
		var face: float = b.face
		if b.state == "flying":
			var k := clampf(b.fly_t / b.fly_len, 0.0, 1.0)
			lift = 14.0 + 26.0 * sin(k * PI)
			face = 1.0 if b.to.x >= b.from.x else -1.0
		elif b.hop > 0.0:
			lift = 3.0 * sin(b.hop * PI)
		mm.set_instance_transform_2d(i, Transform2D(Vector2(face, 0.0), Vector2(0.0, 1.0), b.pos * TILE))
		mm.set_instance_custom_data(i, Color(fly, b.phase, lift, sin(b.peck * PI) if b.peck > 0.0 else 0.0))


## The one side-on bird (facing east, its feet at the origin): a shadow, a tail, the body, the head and beak, the wing.
func _bake() -> ArrayMesh:
	var b := Kit.Builder.new()
	b.add_ellipse(Vector2(0.0, 0.0), 7.0, 2.1, Color(0, 0, 0, 0.22), Vector2(2, 0), 10)
	b.add_blob(Vector2(-6.0, -5.0), 4.5, 1.8, WING, Vector2(0, 0), 1.0, 8)
	b.add_blob(Vector2(0.0, -6.5), 7.0, 4.6, BODY, Vector2(0, 0), 1.0, 10)
	b.add_ellipse(Vector2(-1.0, -7.5), 4.0, 2.4, BODY_HI, Vector2(0, 0), 8)
	b.add_blob(Vector2(6.0, -10.0), 3.2, 3.0, BODY, Vector2(3, 0), 1.0, 8)
	b.add_blob(Vector2(9.0, -9.6), 1.3, 0.9, BEAK, Vector2(3, 0), 0.8, 6)
	b.add_blob(Vector2(-1.0, -14.0), 2.8, 7.0, WING, Vector2(1, 0), 1.0, 10)
	return b.bake()


## How many birds sit on a spot now, and how many are flying (for the tests and the culling).
func count(state: String) -> int:
	var n := 0
	for b in birds:
		if b.state == state:
			n += 1
	return n


func bounds() -> Rect2:
	return Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
