## The LIFE of the town (WORLD3, "add more life to the world"): small things that move, none of them a rule of the game. A view part of the town facade (scripts/town/town_game.gd VIEW_PARTS): it
## makes its nodes in `main.world`, is given the frame, the camera's view and the rules' events, and never touches the sim: nobody reads what it draws, nothing is solid, no dice of the rules
## is rolled (its own random generator is seeded from the town's seed).
##
##   crows       a flock of dark birds on the roofs (the ridge of a gable, the edge of a flat one) that pace and peck; they take off when Ruth comes within a few tiles, at a shot, at a groan, fly off the
##               screen and come back some seconds later to another roof; gone at dusk and in heavy rain. One MultiMesh (one draw call), the wings flap in the vertex shader.
##   leaves      leaves and paper drifting on the wind across the whole view: a MultiMesh of 56 quads that the vertex shader moves and wraps round the camera (each one fixed in the world), one draw call.
##   smoke       a thread of smoke from some chimneys (the ones the facade drew) and a thick dark one from the roof of a house that burnt; a MultiMesh of puffs the shader moves, one draw call.
##   a dog       a stray that trots about the streets of the edge of the town, sniffs, lies down and runs from Ruth (the base's dog mesh: scripts/render/dog_node.gd).
##   rats        a dozen rats by the rubbish and the bins, that scatter when somebody comes near. One MultiMesh.
##   the night   flickering shop signs and insects round the street lamps, drawn into the glow layer (`glow.extras`, additive, a handful of textured quads a frame).
##
## "Reduce motion" (Settings): the crows only sit, the leaves and the insects are not shown, the signs burn steady, the smoke is thin and slow, the dog and the rats keep still. `--nolife` (a flag of
## the screenshot and benchmark runs) makes none of it. COST: about five draw calls and no allocation in a frame; the crows, the dog and the rats are looked at when they are near the view.
extends RefCounted

const Kit := preload("res://scripts/render/life_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")
const DogNode := preload("res://scripts/render/dog_node.gd")

const TILE := 64.0
const CROWS := 26
const LEAVES := 56
const SMOKERS := 10
const PUFFS := 7
const RATS := 14
## How near Ruth a crow lets her come, and how far a shot or a groan is heard by the birds (tiles).
const SHOO_R := 5.5
const HEAR := {"shot": 24.0, "groan": 9.0, "crash": 40.0}
## The margin of the leaves' window beyond the view (pixels).
const MARGIN := 160.0

const CROW_SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
varying float alpha;
void vertex() {
	alpha = INSTANCE_CUSTOM.w;
	float fly = INSTANCE_CUSTOM.x;
	float ph = INSTANCE_CUSTOM.y;
	float part = UV.x;
	if (part > 0.5 && part < 2.5) {
		VERTEX.x *= 0.34 + 0.66 * fly;
		VERTEX.y += sin(t * 21.0 + ph) * 4.0 * fly;
	} else if (part > 8.5) {
		VERTEX += fly * vec2(9.0, 15.0);
		VERTEX *= 1.0 + fly * 0.2;
	} else if (part > 2.5 && part < 3.5) {
		VERTEX.y += INSTANCE_CUSTOM.z * 5.0;
	}
}
void fragment() {
	COLOR.a *= alpha;
}
"

const LEAF_SHADER := "
shader_type canvas_item;
uniform float drift = 0.0;
uniform vec2 cam_tl = vec2(0.0);
uniform vec2 area = vec2(2200.0, 1400.0);
uniform vec2 wind_dir = vec2(1.0, 0.25);
uniform float fade = 1.0;
varying vec3 tint;
varying float edge;
vec3 palette(float k) {
	if (k < 0.2) return vec3(0.86, 0.46, 0.15);
	if (k < 0.4) return vec3(0.90, 0.72, 0.22);
	if (k < 0.6) return vec3(0.50, 0.33, 0.19);
	if (k < 0.8) return vec3(0.70, 0.26, 0.16);
	return vec3(0.86, 0.85, 0.80);
}
void vertex() {
	float s = INSTANCE_CUSTOM.x;
	float v = 0.55 + INSTANCE_CUSTOM.y * 0.9;
	float size = INSTANCE_CUSTOM.z;
	vec2 base = vec2(fract(s * 91.7), fract(s * 37.3 + 0.37)) * 8192.0;
	vec2 p = base + wind_dir * drift * 64.0 * v + vec2(sin(drift * 1.3 * v + s * 50.0) * 22.0, cos(drift * 0.9 * v + s * 40.0) * 14.0);
	vec2 rel = mod(p - cam_tl, area);
	float rot = drift * 2.4 * v + s * 30.0;
	vec2 c = vec2(cos(rot), sin(rot));
	vec2 q = VERTEX * vec2(size, size * 0.6);
	q = vec2(q.x * c.x - q.y * c.y, q.x * c.y + q.y * c.x);
	VERTEX = rel - area * 0.5 + q;
	edge = clamp(min(min(rel.x, area.x - rel.x), min(rel.y, area.y - rel.y)) / 120.0, 0.0, 1.0);
	tint = palette(INSTANCE_CUSTOM.w);
}
void fragment() {
	float d = length((UV - vec2(0.5)) * vec2(1.0, 1.4)) * 2.0;
	COLOR = vec4(tint, smoothstep(1.0, 0.55, d) * 0.85 * edge * fade);
}
"

const SMOKE_SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.2);
uniform float amount = 1.0;
varying float a;
varying vec3 tint;
void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float dark = INSTANCE_CUSTOM.y;
	float on = INSTANCE_CUSTOM.z;
	float age = fract(t * 0.11 * (1.0 - 0.4 * dark) + seed);
	float size = mix(20.0, 84.0 + 40.0 * dark, age);
	vec2 off = wind_dir * age * (110.0 + 80.0 * length(wind_dir)) + vec2(sin(t * 0.7 + seed * 9.0) * 8.0, -age * 36.0);
	VERTEX = VERTEX * size + off;
	a = (1.0 - age * age) * smoothstep(0.0, 0.1, age) * (0.8 + 0.12 * dark) * on * amount;
	tint = mix(vec3(0.84, 0.84, 0.82), vec3(0.12, 0.11, 0.11), dark);
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	COLOR = vec4(tint, smoothstep(1.0, 0.25, d) * a);
}
"

var main
var sim
var world
var enabled := true
var _view := Rect2()
var _seeded := false
var _t := 0.0
var _clock_t := 0.0
var _drift := 0.0
var _wind := 0.3
var _gust := 0.0
var _rng := RandomNumberGenerator.new()
var _root: Node2D
var _calm := false
var _night := 0.0
var _rain := 0.0
var _hour := 12.0
var _me := Vector2(-1000.0, -1000.0)
var _houses: Array = []
var _size := 192
var _solid := PackedByteArray()
# crows
var _crow_mm: MultiMesh
var _crow_node: MultiMeshInstance2D
var _crow_mat: ShaderMaterial
var _crows: Array = []
var _perches: Array = []
# leaves
var _leaf_mm: MultiMesh
var _leaf_node: MultiMeshInstance2D
var _leaf_mat: ShaderMaterial
# smoke
var _smoke_mm: MultiMesh
var _smoke_node: MultiMeshInstance2D
var _smoke_mat: ShaderMaterial
var _smokers: Array = []
var _smoke_t := 0.0
# rats
var _rat_mm: MultiMesh
var _rat_node: MultiMeshInstance2D
var _rats: Array = []
var _rat_t := 0.0
# the dog
var _dog: MeshInstance2D
var _dog_mat: ShaderMaterial
var _dog_stand: ArrayMesh
var _dog_lie: ArrayMesh
var _dog_pos := Vector2.ZERO
var _dog_goal := Vector2.ZERO
var _dog_state := "lie"
var _dog_wait := 5.0
var _dog_face := 1.0
var _dog_lying := true
var _dog_home := Vector2.ZERO
# the night
var _signs: Array = []
var _lamps: Array = []
## What the tests and the shots read.
var stats := {"crows_up": 0, "flushes": 0, "smokers": 0}


func on_ready(main_node) -> void:
	main = main_node
	sim = main.get("sim")
	world = main.get("world")
	if "--nolife" in OS.get_cmdline_user_args() or "--calm" in OS.get_cmdline_user_args():
		enabled = false
	if sim == null or world == null or sim.get("houses") == null:
		enabled = false
		return
	var t = sim.houses.get("town")
	if not (t is Dictionary) or t.is_empty():
		enabled = false
		return
	_houses = t.houses
	_size = int(t.size.x)
	_solid = world.get("solid_p") if world.get("solid_p") != null else PackedByteArray()
	_rng.seed = int(t.get("seed", 1)) * 7717 + 31
	_root = Node2D.new()
	_root.name = "TownLife"
	world.add_child(_root)
	_make_crows()
	_make_leaves()
	_make_smoke()
	_make_rats()
	_make_dog()
	_collect_night()
	var glow = main.get("glow")
	if glow != null and glow.get("extras") != null:
		glow.extras.append(Callable(self, "glow_paint"))


func on_sync_views(view: Rect2) -> void:
	_view = view


func on_event(e: Dictionary) -> void:
	if not enabled or _calm:
		return
	var kind := String(e.get("type", ""))
	if not HEAR.has(kind):
		return
	var at := Vector2(float(e.get("x", 1.0e6)), float(e.get("y", 1.0e6)))
	for c in _crows:
		if c.state == "perch" and c.pos.distance_to(at) <= float(HEAR[kind]):
			_flush(c, at)


func on_frame(dt: float) -> void:
	if not enabled:
		return
	var running: bool = int(main.speed) > 0
	_calm = Prefs.on("ui", "reduce_motion")
	var gdt := dt if running else 0.0
	_t += dt
	_clock_t += gdt
	if not _seeded and _view.has_area():
		# (the first look at the view: the crows that were put on any roof of the town are put on roofs near it)
		_seeded = true
		for c in _crows:
			if String(c.state) == "perch" and not _perches.is_empty():
				_perch(c)
	_hour = float(sim.hour) if sim.get("hour") != null else 12.0
	_night = _night_of(_hour)
	var sk = sim.get("skies")
	_rain = float(sk.level) if sk != null else 0.0
	var me = sim.avatar.player() if sim.get("avatar") != null else null
	_me = Vector2(me.x, me.y) if me != null else Vector2(-1000.0, -1000.0)
	_gust = 0.5 + 0.5 * sin(_t * 0.23) * sin(_t * 0.071 + 1.3)
	_wind = 0.22 + 0.5 * _rain + 0.35 * _gust
	_drift += _wind * gdt * 0.9
	_update_leaves()
	_update_crows(gdt)
	_smoke_t -= dt
	if _smoke_t <= 0.0:
		_smoke_t = 0.25
		_update_smokers()
	_smoke_mat.set_shader_parameter("t", _clock_t)
	_smoke_mat.set_shader_parameter("amount", 0.55 if _calm else 1.0)
	_smoke_mat.set_shader_parameter("wind_dir", Vector2(0.55 + _wind, 0.15 + 0.2 * _gust))
	_update_rats(gdt)
	_update_dog(gdt)


static func _night_of(hour: float) -> float:
	if hour >= 19.5 or hour < 5.5:
		return 1.0
	if hour >= 17.5:
		return smoothstep(17.5, 19.5, hour)
	if hour < 7.0:
		return 1.0 - smoothstep(5.5, 7.0, hour)
	return 0.0


# ================================================================================== crows ==

func _make_crows() -> void:
	var b := Kit.Builder.new()
	var ink := Kit.INK
	var body := Color("#28282e")
	var hi := Color("#454550")
	b.add_ellipse(Vector2(0, 3), 6.5, 11.0, Color(0, 0, 0, 0.24), Vector2(9, 0), 10)
	for side in [-1.0, 1.0]:
		var uvx: float = 1.0 if side < 0.0 else 2.0
		var pts := PackedVector2Array([Vector2(side * 3, -4), Vector2(side * 25, -7), Vector2(side * 23, 7), Vector2(side * 4, 8)])
		b.add_fan(Vector2(side * 10, 0), hi, pts, PackedColorArray([body, body, body, body]), Vector2(uvx, 0))
	b.add_ellipse(Vector2(0, 1), 7.4, 12.2, ink, Vector2(0, 0), 10)
	b.add_ellipse(Vector2(0, 1), 6.0, 11.0, body, Vector2(0, 0), 10)
	b.add_ellipse(Vector2(-1.5, -2), 2.8, 5.0, hi, Vector2(0, 0), 8)
	b.add_fan(Vector2(0, 11), body, PackedVector2Array([Vector2(-4, 10), Vector2(-5, 21), Vector2(0, 19), Vector2(5, 21), Vector2(4, 10)]), PackedColorArray(), Vector2(0, 0))
	b.add_ellipse(Vector2(0, -11), 4.6, 4.4, ink, Vector2(3, 0), 8)
	b.add_ellipse(Vector2(0, -11), 3.6, 3.4, body, Vector2(3, 0), 8)
	b.add_fan(Vector2(0, -16), Color("#6a5a38"), PackedVector2Array([Vector2(-1.8, -14), Vector2(0, -19), Vector2(1.8, -14)]), PackedColorArray(), Vector2(3, 0))
	_crow_mm = MultiMesh.new()
	_crow_mm.transform_format = MultiMesh.TRANSFORM_2D
	_crow_mm.use_custom_data = true
	_crow_mm.mesh = b.bake()
	_crow_mm.instance_count = CROWS
	_crow_mat = Kit.material(CROW_SHADER)
	_crow_node = MultiMeshInstance2D.new()
	_crow_node.name = "Crows"
	_crow_node.multimesh = _crow_mm
	_crow_node.material = _crow_mat
	_crow_node.z_index = 9
	_root.add_child(_crow_node)
	# the places a crow may sit: the ridge of a gable or a hip (along it), the edge of a flat roof, a chimney's shoulder
	_perches.clear()
	for h in _houses:
		if not bool(h.get("main", true)) or String(h.get("type", "")) == "outbuilding":
			continue
		var fac: Dictionary = h.get("facade", {})
		var parts: Array = h.get("parts", [])
		if parts.is_empty():
			continue
		var pq: Rect2i = parts[0]
		var style := String(fac.get("style", "gable"))
		var along_x := pq.size.x >= pq.size.y
		for k in 3:
			var p := Vector2.ZERO
			if style in ["gable", "hip"]:
				var f := _rng.randf_range(0.15, 0.85)
				p = Vector2(float(pq.position.x) + float(pq.size.x) * f, float(pq.position.y) + float(pq.size.y) * 0.5) if along_x else Vector2(float(pq.position.x) + float(pq.size.x) * 0.5, float(pq.position.y) + float(pq.size.y) * f)
			else:
				var f2 := _rng.randf_range(0.1, 0.9)
				match _rng.randi() % 4:
					0:
						p = Vector2(float(pq.position.x) + float(pq.size.x) * f2, float(pq.position.y) + 0.5)
					1:
						p = Vector2(float(pq.position.x) + float(pq.size.x) * f2, float(pq.end.y) - 0.5)
					2:
						p = Vector2(float(pq.position.x) + 0.5, float(pq.position.y) + float(pq.size.y) * f2)
					_:
						p = Vector2(float(pq.end.x) - 0.5, float(pq.position.y) + float(pq.size.y) * f2)
			_perches.append({"p": p, "house": int(h.id)})
	_crows.clear()
	for i in CROWS:
		var c := {"i": i, "state": "away", "t": _rng.randf_range(0.0, 12.0), "pos": Vector2.ZERO, "perch": -1, "head": 0.0, "fly": 0.0, "vel": Vector2.ZERO, "peck": 0.0, "wait": 2.0, "to": Vector2.ZERO}
		_crows.append(c)
		_hide_crow(i)
	# the first ones are already on their roofs
	for c in _crows:
		if _perches.is_empty():
			break
		if int(c.i) < CROWS * 2 / 3:
			_perch(c)


func _hide_crow(i: int) -> void:
	_crow_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))


func _perch(c: Dictionary) -> void:
	if _perches.is_empty():
		return
	# a roof near the view if there is one (a crow is a thing you see), else any
	var pick := -1
	for k in 24:
		var j := _rng.randi() % _perches.size()
		var p: Vector2 = _perches[j].p
		if _view.has_area() and not _view.grow(14.0).has_point(p):
			continue
		pick = j
		break
	if pick < 0:
		pick = _rng.randi() % _perches.size()
	c.perch = pick
	c.pos = _perches[pick].p
	c.state = "perch"
	c.fly = 0.0
	c.head = _rng.randf() * TAU
	c.wait = _rng.randf_range(1.5, 6.0)
	c.peck = 0.0


func _flush(c: Dictionary, from: Vector2) -> void:
	c.state = "fly"
	c.t = 0.0
	var away: Vector2 = (c.pos - from)
	if away.length() < 0.1:
		away = Vector2.from_angle(_rng.randf() * TAU)
	away = away.normalized().rotated(_rng.randf_range(-0.6, 0.6))
	c.vel = away * _rng.randf_range(2.5, 4.0)
	c.head = away.angle() + PI / 2.0
	stats.flushes += 1


func _update_crows(gdt: float) -> void:
	var gone: bool = _night > 0.55 or _rain > 0.5
	var up := 0
	var hv = main.get("town").part("house_view") if main.get("town") != null else null
	var in_house := int(hv.avatar_house) if hv != null and hv.get("avatar_house") != null else -1
	for c in _crows:
		var i: int = c.i
		match String(c.state):
			"perch":
				if gone:
					_flush(c, c.pos + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)))
					continue
				var d: float = (c.pos as Vector2).distance_to(_me)
				var house_id: int = int(_perches[c.perch].house)
				if not _calm and (d < SHOO_R or house_id == in_house):
					_flush(c, _me)
					continue
				if not _calm:
					c.wait -= gdt
					if c.wait <= 0.0:
						c.wait = _rng.randf_range(1.2, 5.0)
						if _rng.randf() < 0.55:
							c.peck = 1.0
						else:
							c.head += _rng.randf_range(-1.2, 1.2)
					c.peck = maxf(0.0, c.peck - gdt * 3.0)
				if _view.has_area() and not _view.grow(3.0).has_point(c.pos):
					_hide_crow(i)
					continue
				up += 1
				_crow_mm.set_instance_transform_2d(i, Transform2D(c.head, Vector2(1.3, 1.3), 0.0, (c.pos as Vector2) * TILE))
				_crow_mm.set_instance_custom_data(i, Color(0.0, float(i) * 1.7, c.peck, 1.0))
			"fly":
				c.t += gdt
				c.fly = minf(1.0, c.fly + gdt * 4.0)
				c.vel = (c.vel as Vector2) * (1.0 + gdt * 0.8)
				c.pos = (c.pos as Vector2) + (c.vel as Vector2) * gdt
				if c.t > 3.6:
					c.state = "away"
					c.t = 0.0
					c.wait = _rng.randf_range(10.0, 24.0)
					_hide_crow(i)
					continue
				if _view.has_area() and not _view.grow(6.0).has_point(c.pos):
					_hide_crow(i)
					continue
				up += 1
				var a := clampf(1.0 - maxf(0.0, c.t - 2.6), 0.0, 1.0)
				_crow_mm.set_instance_transform_2d(i, Transform2D(float((c.vel as Vector2).angle()) + PI / 2.0, Vector2(1.15, 1.15), 0.0, (c.pos as Vector2) * TILE))
				_crow_mm.set_instance_custom_data(i, Color(c.fly, float(i) * 1.7, 0.0, a))
			"land":
				c.t += gdt
				var f: float = clampf(c.t / 1.1, 0.0, 1.0)
				var tgt: Vector2 = _perches[c.perch].p
				c.pos = (c.to as Vector2).lerp(tgt, f * f * (3.0 - 2.0 * f))
				c.fly = 1.0 - f
				if f >= 1.0:
					c.state = "perch"
					c.fly = 0.0
					c.pos = tgt
					continue
				if _view.has_area() and not _view.grow(6.0).has_point(c.pos):
					_hide_crow(i)
					continue
				up += 1
				var dirv: Vector2 = tgt - (c.to as Vector2)
				_crow_mm.set_instance_transform_2d(i, Transform2D(dirv.angle() + PI / 2.0, Vector2(1.1, 1.1), 0.0, (c.pos as Vector2) * TILE))
				_crow_mm.set_instance_custom_data(i, Color(c.fly, float(i) * 1.7, 0.0, minf(1.0, f * 3.0)))
			_:
				# away: come back after a while, once the roofs are quiet, by day
				if gone:
					continue
				c.wait -= gdt
				if c.wait <= 0.0:
					_perch(c)
					if c.state == "perch" and (c.pos as Vector2).distance_to(_me) > SHOO_R * 2.0 and not _calm:
						# it lands from a few tiles off
						c.to = (c.pos as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * 9.0
						c.state = "land"
						c.t = 0.0
					elif c.state == "perch" and (c.pos as Vector2).distance_to(_me) <= SHOO_R * 2.0:
						c.state = "away"
						c.wait = _rng.randf_range(4.0, 9.0)
	stats.crows_up = up


# ================================================================================== leaves ==

func _make_leaves() -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_leaf_mm = MultiMesh.new()
	_leaf_mm.transform_format = MultiMesh.TRANSFORM_2D
	_leaf_mm.use_custom_data = true
	_leaf_mm.mesh = q
	_leaf_mm.instance_count = LEAVES
	for i in LEAVES:
		_leaf_mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
		var k := _rng.randf()
		_leaf_mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), _rng.randf_range(9.0, 15.0) if k < 0.8 else _rng.randf_range(12.0, 20.0), k if k < 0.8 else 0.9))
	_leaf_mat = Kit.material(LEAF_SHADER)
	_leaf_node = MultiMeshInstance2D.new()
	_leaf_node.name = "Leaves"
	_leaf_node.multimesh = _leaf_mm
	_leaf_node.material = _leaf_mat
	_leaf_node.z_index = 5
	_root.add_child(_leaf_node)


func _update_leaves() -> void:
	var show := not _calm and _rain < 0.35 and _view.has_area()
	_leaf_node.visible = show
	if not show:
		return
	var tl := _view.position * TILE - Vector2(MARGIN, MARGIN) * 0.5
	var area := _view.size * TILE + Vector2(MARGIN, MARGIN)
	_leaf_node.position = tl + area * 0.5
	_leaf_mat.set_shader_parameter("cam_tl", tl)
	_leaf_mat.set_shader_parameter("area", area)
	_leaf_mat.set_shader_parameter("drift", _drift)
	_leaf_mat.set_shader_parameter("wind_dir", Vector2(1.0, 0.22 + 0.3 * _gust).normalized())
	_leaf_mat.set_shader_parameter("fade", clampf(1.0 - _rain * 2.5, 0.0, 1.0) * (1.0 - 0.7 * _night))


# ================================================================================== smoke ==

func _make_smoke() -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_smoke_mm = MultiMesh.new()
	_smoke_mm.transform_format = MultiMesh.TRANSFORM_2D
	_smoke_mm.use_custom_data = true
	_smoke_mm.mesh = q
	_smoke_mm.instance_count = SMOKERS * PUFFS
	for i in SMOKERS * PUFFS:
		_smoke_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
		_smoke_mm.set_instance_custom_data(i, Color(float(i % PUFFS) / float(PUFFS), 0.0, 0.0, 0.0))
	_smoke_mat = Kit.material(SMOKE_SHADER)
	_smoke_node = MultiMeshInstance2D.new()
	_smoke_node.name = "Smoke"
	_smoke_node.multimesh = _smoke_mm
	_smoke_node.material = _smoke_mat
	_smoke_node.z_index = 9
	_root.add_child(_smoke_node)
	# the chimneys that smoke: about a third of the ones the facades drew (by a hash of the house), and a burnt house's roof
	_smokers.clear()
	for h in _houses:
		var fac: Dictionary = h.get("facade", {})
		if fac.is_empty():
			continue
		var hid := int(h.id)
		if String(fac.get("state", "")) == "burnt":
			var holes: Array = fac.get("holes", [])
			if not holes.is_empty() and (hid * 7 + 3) % 100 < 70:
				var hc: Vector2i = holes[0]
				_smokers.append({"p": Vector2(float(hc.x) + 0.5, float(hc.y) + 0.5), "dark": 1.0, "house": hid})
			continue
		var chims: Array = fac.get("chimneys", [])
		if not chims.is_empty() and (hid * 13 + 5) % 100 < 36:
			_smokers.append({"p": Vector2(chims[0]) + Vector2(0.1, -0.1), "dark": 0.0, "house": hid})


func _update_smokers() -> void:
	var hv = main.get("town").part("house_view") if main.get("town") != null else null
	var in_house := int(hv.avatar_house) if hv != null and hv.get("avatar_house") != null else -1
	var centre := _view.get_center() if _view.has_area() else _me
	var near: Array = []
	for s in _smokers:
		if int(s.house) == in_house:
			continue
		var d: float = (s.p as Vector2).distance_to(centre)
		if _view.has_area() and not _view.grow(10.0).has_point(s.p):
			continue
		near.append([d, s])
	near.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var limit := mini(near.size(), 3 if _calm else SMOKERS)
	for k in SMOKERS:
		for j in PUFFS:
			var idx := k * PUFFS + j
			if k < limit:
				var s: Dictionary = near[k][1]
				_smoke_mm.set_instance_transform_2d(idx, Transform2D(0.0, Vector2.ONE, 0.0, (s.p as Vector2) * TILE))
				_smoke_mm.set_instance_custom_data(idx, Color(float(j) / float(PUFFS) + float(int(s.house) % 7) * 0.013, float(s.dark), 1.0, 0.0))
			else:
				_smoke_mm.set_instance_transform_2d(idx, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
	stats.smokers = limit


# =================================================================================== rats ==

func _make_rats() -> void:
	var b := Kit.Builder.new()
	var fur := Color("#3a322c")
	b.add_stroke(Vector2(0, 5), Vector2(1.5, 14), 1.4, Color("#6a5a54"))
	b.add_blob(Vector2(0, 0), 3.4, 6.2, fur, Vector2.ZERO, 0.9, 8)
	b.add_blob(Vector2(0, -6.4), 2.4, 2.8, fur, Vector2.ZERO, 0.9, 8)
	b.add_ellipse(Vector2(-2.2, -8.2), 1.1, 1.3, Color("#5a4a44"), Vector2.ZERO, 6)
	b.add_ellipse(Vector2(2.2, -8.2), 1.1, 1.3, Color("#5a4a44"), Vector2.ZERO, 6)
	_rat_mm = MultiMesh.new()
	_rat_mm.transform_format = MultiMesh.TRANSFORM_2D
	_rat_mm.mesh = b.bake()
	_rat_mm.instance_count = RATS
	_rat_node = MultiMeshInstance2D.new()
	_rat_node.name = "Rats"
	_rat_node.multimesh = _rat_mm
	_rat_node.z_index = 5
	_root.add_child(_rat_node)
	# the rubbish they live in: the bin bags, the debris, the trolleys and the bodies of the town (the dressing's objects)
	var spots: Array = []
	var d = world.get("d")
	if d is Dictionary:
		for o in d.get("objects", []):
			var k := String(o.get("kit", ""))
			if k in ["bin_bag", "debris", "cart_fallen", "rubble", "pallet", "bin"]:
				spots.append(Vector2(float(o.cx), float(o.cy)))
	_rats.clear()
	for i in RATS:
		var home := Vector2(-1000.0, -1000.0)
		if not spots.is_empty():
			home = spots[_rng.randi() % spots.size()]
		_rats.append({"home": home, "pos": home + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4)), "goal": home, "head": _rng.randf() * TAU, "wait": _rng.randf_range(0.5, 6.0), "state": "sit", "gone": 0.0})
		_rat_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))


func _update_rats(gdt: float) -> void:
	for i in RATS:
		var r: Dictionary = _rats[i]
		var home: Vector2 = r.home
		if home.x < -500.0:
			continue
		var visible_now := not _view.has_area() or _view.grow(4.0).has_point(r.pos)
		var dme: float = (r.pos as Vector2).distance_to(_me)
		if _calm:
			if visible_now and String(r.state) != "gone":
				_rat_mm.set_instance_transform_2d(i, Transform2D(r.head, Vector2.ONE, 0.0, (r.pos as Vector2) * TILE))
			else:
				_rat_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
			continue
		match String(r.state):
			"gone":
				r.gone -= gdt
				if r.gone <= 0.0 and dme > 9.0:
					r.state = "sit"
					r.pos = home + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
					r.wait = _rng.randf_range(1.0, 5.0)
			"run":
				var to: Vector2 = (r.goal as Vector2) - (r.pos as Vector2)
				var stepv: float = 4.4 * gdt
				if to.length() <= stepv:
					r.pos = r.goal
					r.state = "sit"
					r.wait = _rng.randf_range(1.5, 7.0)
				else:
					var nxt: Vector2 = (r.pos as Vector2) + to.normalized() * stepv
					r.pos = nxt
					r.head = to.angle() + PI / 2.0
			_:
				if dme < 3.2:
					# the person comes: into the rubbish and gone for a while
					r.state = "gone"
					r.gone = _rng.randf_range(15.0, 40.0)
				else:
					r.wait -= gdt
					if r.wait <= 0.0:
						var g: Vector2 = home + Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6))
						if Kit.clear_walk(_solid, _size, r.pos, g):
							r.goal = g
							r.state = "run"
						else:
							r.wait = _rng.randf_range(1.0, 3.0)
		if String(r.state) == "gone" or not visible_now:
			_rat_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
		else:
			_rat_mm.set_instance_transform_2d(i, Transform2D(r.head, Vector2(1.0, 1.0), 0.0, (r.pos as Vector2) * TILE))


# ==================================================================================== dog ==

func _make_dog() -> void:
	var proto := DogNode.new()
	_dog_stand = proto._bake(false)
	_dog_lie = proto._bake(true)
	proto.free()
	_dog_mat = Kit.material(DogNode.SHADER)
	_dog = MeshInstance2D.new()
	_dog.name = "StrayDog"
	_dog.mesh = _dog_lie
	_dog.material = _dog_mat
	var ents = main.get("entities")
	if ents != null:
		ents.add_child(_dog)
	else:
		_root.add_child(_dog)
	# its home: a street corner of the edge of the town, far from the start
	var entry := Vector2(-1000.0, -1000.0)
	var arr = sim.houses.get("town").get("entry") if sim.houses.get("town") != null else null
	if arr is Dictionary and not (arr as Dictionary).is_empty() and arr.get("pos") is Vector2:
		entry = arr.pos
	var best := -1.0
	var roads: Array = sim.houses.get("town").get("streets", {}).get("roads", [])
	for k in 14:
		var rd: Dictionary = roads[_rng.randi() % roads.size()] if not roads.is_empty() else {}
		if rd.is_empty():
			break
		var rr: Rect2i = rd.rect
		var p := Vector2(float(rr.position.x + _rng.randi() % maxi(1, rr.size.x)) + 0.5, float(rr.position.y + _rng.randi() % maxi(1, rr.size.y)) + 0.5)
		var score := p.distance_to(entry) + _rng.randf() * 10.0
		if score > best and p.distance_to(entry) > 35.0:
			best = score
			_dog_home = p
	if _dog_home == Vector2.ZERO:
		_dog_home = Vector2(float(_size) * 0.3, float(_size) * 0.55)
	_dog_pos = _dog_home
	_dog_goal = _dog_home
	_dog.position = _dog_pos * TILE
	_dog_wait = _rng.randf_range(4.0, 14.0)


func _set_dog_lying(lying: bool) -> void:
	if lying != _dog_lying:
		_dog_lying = lying
		_dog.mesh = _dog_lie if lying else _dog_stand


func _update_dog(gdt: float) -> void:
	var near := not _view.has_area() or _view.grow(6.0).has_point(_dog_pos)
	var dme := _dog_pos.distance_to(_me)
	var walk := 0.0
	var sniff := 0.0
	var moving := false
	if _calm:
		_set_dog_lying(true)
	elif _night > 0.7 or _rain > 0.6:
		_dog_state = "lie"
		_set_dog_lying(true)
	else:
		match _dog_state:
			"lie", "sniff":
				if dme < 7.0:
					_dog_flee()
				else:
					_dog_wait -= gdt
					sniff = 0.6 if _dog_state == "sniff" else 0.0
					if _dog_wait <= 0.0:
						_dog_pick()
			_:
				if dme < 5.0 and _dog_state != "flee":
					_dog_flee()
				var to := _dog_goal - _dog_pos
				var speed := 3.6 if _dog_state == "flee" else 1.7
				var stepv := speed * gdt
				_set_dog_lying(false)
				if to.length() <= stepv:
					_dog_pos = _dog_goal
					_dog_state = "sniff" if _rng.randf() < 0.55 else "lie"
					_dog_wait = _rng.randf_range(3.0, 9.0) if _dog_state == "sniff" else _rng.randf_range(10.0, 26.0)
					_set_dog_lying(_dog_state == "lie")
				else:
					_dog_pos += to.normalized() * stepv
					_dog_face = 1.0 if to.x >= 0.0 else -1.0
					walk = 1.0
					moving = true
	if not near:
		_dog.visible = false
		return
	_dog.visible = true
	_dog.position = _dog_pos * TILE
	_dog.scale = Vector2(_dog_face * 1.2, 1.2)
	_dog_mat.set_shader_parameter("t", _t)
	_dog_mat.set_shader_parameter("walk", walk)
	_dog_mat.set_shader_parameter("sniff", sniff)
	_dog_mat.set_shader_parameter("wag", 0.4 if _dog_state == "flee" else 1.0)
	_dog_mat.set_shader_parameter("breathe", 1.0)


func _dog_pick() -> void:
	for k in 8:
		var g := _dog_pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4.0, 12.0)
		if g.distance_to(_dog_home) > 26.0:
			g = _dog_home + (g - _dog_home).normalized() * 18.0
		if Kit.clear_walk(_solid, _size, _dog_pos, g):
			_dog_goal = g
			_dog_state = "walk"
			_set_dog_lying(false)
			return
	_dog_wait = 4.0


func _dog_flee() -> void:
	var best := _dog_pos
	var best_d := 0.0
	for k in 8:
		var g := _dog_pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(8.0, 14.0)
		if Kit.clear_walk(_solid, _size, _dog_pos, g) and g.distance_to(_me) > best_d:
			best_d = g.distance_to(_me)
			best = g
	_dog_goal = best
	_dog_state = "flee"
	_set_dog_lying(false)


# ============================================================================== the night ==

func _collect_night() -> void:
	_signs.clear()
	for h in _houses:
		var fac: Dictionary = h.get("facade", {})
		var sg: Dictionary = fac.get("sign", {})
		if sg.is_empty():
			continue
		var hid := int(h.id)
		if (hid * 17 + 9) % 100 < 45:
			var icon := String(sg.icon)
			var c := Color8(255, 170, 90)
			match icon:
				"cross":
					c = Color8(110, 255, 160)
				"fuel", "coin", "film":
					c = Color8(255, 90, 80)
				"cup", "mug", "bread":
					c = Color8(255, 190, 90)
				"drop", "plug", "book":
					c = Color8(110, 190, 255)
				"scissors", "hanger":
					c = Color8(220, 130, 255)
			_signs.append({"p": Vector2(float(sg.x), float(sg.y)), "c": c, "seed": float(hid)})
	_lamps.clear()
	var d = world.get("d")
	if d is Dictionary:
		for o in d.get("objects", []):
			if String(o.get("kit", "")) == "streetlamp":
				_lamps.append(Vector2(float(o.cx), float(o.cy)))


## The painter of the glow layer's `extras`: `ci` the canvas item (tile units), `radial` the soft disc, `dark` how dark it is (0 to 1).
func glow_paint(ci: CanvasItem, radial: Texture2D, dark: float) -> void:
	if not enabled or dark < 0.15 or not _view.has_area():
		return
	var view := _view.grow(3.0)
	for s in _signs:
		var p: Vector2 = s.p
		if not view.has_point(p):
			continue
		var flick := 1.0
		if not _calm:
			var w := sin(_t * 31.0 + float(s.seed) * 5.0) * sin(_t * 7.3 + float(s.seed))
			flick = 1.0 if w > -0.82 else 0.25
			flick *= 0.85 + 0.15 * sin(_t * 3.0 + float(s.seed))
		var col: Color = s.c
		col.a = 0.42 * dark * flick
		ci.draw_texture_rect(radial, Rect2(p.x - 1.2, p.y - 1.2, 2.4, 2.4), false, col)
	if _calm or _rain > 0.3 or dark < 0.5:
		return
	# insects round the street lamps
	for lp in _lamps:
		var l: Vector2 = lp
		if not view.has_point(l):
			continue
		for k in 4:
			var a := _t * (1.3 + float(k) * 0.37) + float(k) * 1.9 + l.x
			var rr := 0.28 + 0.16 * float(k) + 0.08 * sin(_t * 0.9 + l.y + float(k))
			var p2 := l + Vector2(cos(a) * rr, sin(a * 1.3) * rr * 0.7 - 0.1)
			ci.draw_texture_rect(radial, Rect2(p2.x - 0.05, p2.y - 0.05, 0.1, 0.1), false, Color(1.0, 0.96, 0.75, 0.7 * dark))
