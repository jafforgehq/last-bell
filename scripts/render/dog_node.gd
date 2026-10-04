## A stray dog (round 24, "base life"): a small tan dog that has taken up with the colony. By day it trots about the quiet ground of the
## yard from one spot to the next (round the fires, the picnic tables, the south wall: the walking graph NODES / EDGES below, every edge
## kept only if the real walking grid says it is clear), stops to sniff, and lies down by a fire for a while; at dusk and at night it lies by
## the nearest fire and sleeps (it breathes). It is only drawn: it stands in the y-sorted node the people are in (so people pass in front
## of it and behind it by their feet) and nothing is solid or reads it, and a person does not know it is there.
##
## The picture is two baked meshes (a dog standing, a dog lying) drawn in ONE draw call, flipped by the way it walks; the two-frame walk (the
## diagonal pairs of legs swap about five times a second), the bob, the wagging tail, the head going down to sniff and the breathing of a
## sleeper are the vertex shader below, moved by a few numbers set each frame. The mesh is swapped only when it lies down or gets up. No sprite,
## no allocation in a frame. Its walking goes on whether it is seen or not, at 1.7 tiles a second, and the node is hidden off the screen by
## scripts/render/base_life.gd. Under "reduce motion" it lies by the fire and does not move.
##
## The meshes' UV.x says what a vertex belongs to: 0 the body, 1 and 2 the two pairs of legs (the diagonal pairs), 3 the tail, 4 the head, 5 the
## sleeper's body, 9 the shadow.
extends MeshInstance2D

const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
## The spots it goes to (tiles), and whether it lies there: the lying spots are a step from a fire barrel (the barrels are at
## (26.5, 21.1), (44.8, 21.3), (58.1, 21.1) and (36.8, 37.2)).
const NODES := [
	[Vector2(27.6, 22.7), true],
	[Vector2(24.2, 28.0), false],
	[Vector2(24.2, 36.0), false],
	[Vector2(35.3, 38.6), true],
	[Vector2(33.0, 42.2), false],
	[Vector2(43.0, 42.4), false],
	[Vector2(50.0, 41.0), false],
	[Vector2(49.6, 34.2), false],
	[Vector2(49.6, 23.5), false],
	[Vector2(46.0, 22.8), true],
	[Vector2(59.3, 22.8), true],
	[Vector2(59.4, 38.0), false],
]
const EDGES := [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8], [8, 9], [8, 10], [6, 11], [10, 9]]
const SPEED := 1.7
## The dog is drawn this much bigger than its numbers, so that it reads at the game's zoom.
const SCALE := 1.2
const COAT := Color("#a8774a")
const BELLY := Color("#d2aa72")
const EAR := Color("#5e3f24")
const NOSE := Color("#1d1712")

const SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
uniform float walk = 0.0;
uniform float sniff = 0.0;
uniform float wag = 1.0;
uniform float breathe = 1.0;
void vertex() {
	float part = UV.x;
	float step_ = floor(mod(t * 5.0, 2.0));
	float swing = (0.5 - step_) * 6.0 * walk;
	float bob = -step_ * walk;
	if (part > 0.5 && part < 1.5) {
		VERTEX.x -= swing;
	} else if (part > 1.5 && part < 2.5) {
		VERTEX.x += swing;
	} else if (part > 2.5 && part < 3.5) {
		float w = sin(t * 11.0) * 4.0 * wag;
		VERTEX.x += w * 0.4;
		VERTEX.y += bob - abs(w) * 0.3;
	} else if (part > 3.5 && part < 4.5) {
		VERTEX += sniff * vec2(2.0, 11.0);
		VERTEX.y += bob;
	} else if (part > 4.5 && part < 5.5) {
		VERTEX.y = (VERTEX.y + 6.0) * (1.0 + 0.11 * sin(t * 1.9) * breathe) - 6.0;
	} else if (part < 0.5) {
		VERTEX.y += bob;
	}
}
"

## Where it is (tiles), what it is doing ("lie", "walk", "sniff"), how long it has done it and for how long it will, and the way it faces (+1 east, -1 west).
var pos := Vector2.ZERO
var state := "lie"
var state_t := 0.0
var wait := 20.0
var face := 1.0
var t := 0.0
var moving := true
var day := true
var _at := 3
var _path: Array = []
var _adj: Array = []
var _rng := RandomNumberGenerator.new()
var _lying := true
var _mesh_stand: ArrayMesh
var _mesh_lie: ArrayMesh
var _mat: ShaderMaterial
## How many times it has set off for a new spot, and how many tiles it has walked (for the tests).
var trips := 0
var walked := 0.0


## `solid` is the world's walking grid (0 open) and `w` its width: an edge whose line crosses a solid tile is dropped (empty: all kept).
func setup(solid: PackedByteArray, w: int, seed_value: int = 7) -> void:
	z_index = 0
	name = "Dog"
	_rng.seed = seed_value
	_mat = Kit.material(SHADER)
	material = _mat
	_mesh_stand = _bake(false)
	_mesh_lie = _bake(true)
	mesh = _mesh_lie
	rewire(solid, w)
	_at = 3
	pos = NODES[_at][0]
	position = pos * TILE
	wait = _rng.randf_range(8.0, 20.0)


## Keeps the edges of the walking graph that the walking grid says are open (`solid` its grid, 0 open, `w` its width; empty: all are kept). The
## base's life asks again every few seconds with the world's own grid, so that a building put up on its path takes the path away.
func rewire(solid: PackedByteArray, w: int) -> void:
	_adj.clear()
	for i in NODES.size():
		_adj.append([])
	for e in EDGES:
		var a: Vector2 = NODES[e[0]][0]
		var b: Vector2 = NODES[e[1]][0]
		if Kit.clear_walk(solid, w, a, b):
			_adj[e[0]].append(e[1])
			_adj[e[1]].append(e[0])


## One frame: `dt` is the real time scaled by the game's pace, `clock` the animation time, `is_day` whether the bell has not rung yet.
func tick(dt: float, clock: float, is_day: bool, animate: bool) -> void:
	t = clock
	day = is_day
	moving = animate
	state_t += dt
	match state:
		"walk":
			_walk(dt)
		_:
			if state_t >= wait and moving:
				_choose()
	position = pos * TILE
	scale = Vector2(face * SCALE, SCALE)
	var lie := state == "lie"
	if lie != _lying:
		_lying = lie
		mesh = _mesh_lie if lie else _mesh_stand
	if visible:
		_mat.set_shader_parameter("t", t)
		_mat.set_shader_parameter("walk", 1.0 if state == "walk" else 0.0)
		_mat.set_shader_parameter("sniff", 1.0 if state == "sniff" else 0.0)
		_mat.set_shader_parameter("wag", 1.0 if moving else 0.0)
		_mat.set_shader_parameter("breathe", 1.0 if moving else 0.0)


## One of the dog's two meshes: standing (walking, sniffing) or lying, side on, facing east, its feet at the origin.
func _bake(lying: bool) -> ArrayMesh:
	var b := Kit.Builder.new()
	b.add_ellipse(Vector2(0.0, 2.0), 17.0, 4.5, Color(0, 0, 0, 0.22), Vector2(9, 0), 12)
	if lying:
		b.add_blob(Vector2(-3.0, -6.0), 16.0, 6.0, COAT, Vector2(5, 0))
		b.add_blob(Vector2(-12.0, -4.0), 6.0, 4.0, BELLY, Vector2(5, 0))
		b.add_blob(Vector2(-18.0, -5.0), 4.0, 2.5, COAT, Vector2(5, 0))          # the tail, curled round
		b.add_blob(Vector2(14.0, -6.0), 6.5, 5.5, COAT)                          # the head, down on the paws
		b.add_blob(Vector2(20.0, -4.5), 3.4, 2.6, BELLY)
		b.add_blob(Vector2(11.0, -9.5), 3.0, 4.0, EAR)
		b.add_blob(Vector2(23.0, -5.2), 1.2, 1.0, NOSE)
		return b.bake()
	# the legs: the far pair a shade darker; the diagonal pairs (UV.x 1 and 2) swap as it walks
	b.add_blob(Vector2(-11.0, -3.5), 2.4, 4.0, EAR, Vector2(1, 0))
	b.add_blob(Vector2(9.0, -3.5), 2.4, 4.0, EAR, Vector2(2, 0))
	b.add_blob(Vector2(-8.0, -3.5), 2.6, 4.2, COAT, Vector2(2, 0))
	b.add_blob(Vector2(12.0, -3.5), 2.6, 4.2, COAT, Vector2(1, 0))
	b.add_blob(Vector2(-19.0, -17.0), 3.2, 5.0, COAT, Vector2(3, 0))              # the tail, up
	b.add_blob(Vector2(-1.0, -13.0), 16.0, 7.5, COAT)
	b.add_ellipse(Vector2(0.0, -10.0), 11.0, 3.6, BELLY)
	# the head (up while it goes; the shader takes it down to sniff)
	b.add_blob(Vector2(17.0, -20.0), 6.5, 6.0, COAT, Vector2(4, 0))
	b.add_blob(Vector2(24.0, -18.0), 4.0, 3.0, BELLY, Vector2(4, 0))
	b.add_blob(Vector2(14.0, -24.0), 3.0, 4.2, EAR, Vector2(4, 0))
	b.add_blob(Vector2(27.5, -18.8), 1.4, 1.2, NOSE, Vector2(4, 0))
	return b.bake()


func _choose() -> void:
	var goal := -1
	if not day:
		# at night it goes to the nearest fire and stays
		var best := 1.0e9
		for i in NODES.size():
			if NODES[i][1] and not _adj[i].is_empty():
				var d := pos.distance_to(NODES[i][0])
				if d < best:
					best = d
					goal = i
		if goal == _at or goal < 0:
			_rest(60.0, 120.0)
			return
	else:
		var pool: Array = []
		for i in NODES.size():
			if i != _at and not _adj[i].is_empty():
				pool.append(i)
				if not NODES[i][1]:
					pool.append(i)
		if pool.is_empty():
			_rest(20.0, 40.0)
			return
		goal = pool[_rng.randi() % pool.size()]
	_path = _route(_at, goal)
	if _path.is_empty():
		_rest(10.0, 20.0)
		return
	state = "walk"
	state_t = 0.0
	trips += 1


## The nodes to walk through from `a` to `b` (breadth first over the graph; empty when there is no way).
func _route(a: int, b: int) -> Array:
	var came := {a: -1}
	var queue := [a]
	while not queue.is_empty():
		var n: int = queue.pop_front()
		if n == b:
			break
		for m in _adj[n]:
			if not came.has(m):
				came[m] = n
				queue.append(m)
	if not came.has(b):
		return []
	var out: Array = []
	var n := b
	while n != a:
		out.push_front(n)
		n = came[n]
	return out


func _walk(dt: float) -> void:
	if _path.is_empty():
		_arrive()
		return
	var to: Vector2 = NODES[_path[0]][0]
	var d := pos.distance_to(to)
	var step := SPEED * dt
	if absf(to.x - pos.x) > 0.05:
		face = 1.0 if to.x > pos.x else -1.0
	if d <= step:
		walked += d
		pos = to
		_at = _path.pop_front()
		if _path.is_empty():
			_arrive()
	else:
		walked += step
		pos += (to - pos) / d * step


func _arrive() -> void:
	if NODES[_at][1]:
		_rest(25.0 if day else 60.0, 70.0 if day else 120.0)
	else:
		state = "sniff"
		state_t = 0.0
		wait = _rng.randf_range(1.5, 4.0)


func _rest(lo: float, hi: float) -> void:
	state = "lie" if NODES[_at][1] else "sniff"
	state_t = 0.0
	wait = _rng.randf_range(lo, hi)


## The ground it covers (tiles), for the culling.
func bounds() -> Rect2:
	return Rect2(pos + Vector2(-0.8, -0.9), Vector2(1.6, 1.2))


## The way the walking graph is wired (for the tests): how many edges were kept.
func edge_count() -> int:
	var n := 0
	for a in _adj:
		n += a.size()
	return n / 2
