## Short-lived effects: muzzle flashes, tracers, blood, splinters, sparks,
## smoke and embers, plus blood that stays on the ground (as sprites, so each
## splat is lit on its own).
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const TILE := GD.TILE
const G := 9.8
const MAX_DECALS := 260

var parts: Array = []
var decals: Array = [] # {node, size, grow, age}
var tracers: Array = []
var flashes: Array = []
var decal_parent: Node2D
var blood_tex: Array = []
var puff_light: Texture2D
var puff_dark: Texture2D
var radial: Texture2D


func setup(data: Dictionary, parent: Node2D, radial_tex: Texture2D) -> void:
	decal_parent = parent
	for f in data.fx.blood:
		blood_tex.append(GD.tex(f))
	puff_light = GD.tex(data.fx.puffLight)
	puff_dark = GD.tex(data.fx.puffDark)
	radial = radial_tex


func blood(x: float, y: float, dx: float, dy: float, n: int = 10) -> void:
	var base := atan2(dy, dx)
	for i in n:
		var sp := 1.0 + randf() * 3.0
		var a := base + (randf() - 0.5) * 1.4
		parts.append({"kind": "blood", "x": x, "y": y, "z": 0.55 + randf() * 0.3, "vx": cos(a) * sp, "vy": sin(a) * sp, "vz": randf() * 2.0, "life": 2.0, "size": 0.03 + randf() * 0.04})


func decal(x: float, y: float, size: float, grow: float = 0.0) -> void:
	var s := Sprite2D.new()
	s.texture = blood_tex[randi() % blood_tex.size()]
	s.position = Vector2(x, y) * TILE
	s.rotation = randf() * TAU
	s.modulate = Color(1, 1, 1, 0.85)
	decal_parent.add_child(s)
	var dd := {"node": s, "size": size, "grow": grow, "age": 0.0}
	_scale_decal(dd)
	decals.append(dd)
	if decals.size() > MAX_DECALS:
		var old: Dictionary = decals.pop_front()
		old.node.queue_free()


func _scale_decal(dd: Dictionary) -> void:
	# the splat sprite spans three decal sizes
	var s: Sprite2D = dd.node
	var px: float = dd.size * 3.0 * TILE
	s.scale = Vector2.ONE * (px / s.texture.get_width())


func hit_material(x: float, y: float, kind: String) -> void:
	if kind == "metal":
		for i in 6:
			var a := randf() * TAU
			var sp := 2.0 + randf() * 3.0
			parts.append({"kind": "spark", "x": x, "y": y, "z": 0.6, "vx": cos(a) * sp, "vy": sin(a) * sp, "vz": 1.0 + randf() * 2.0, "life": 0.25 + randf() * 0.2, "size": 0.03})
	else:
		var cols := [Color.html("#9c7446"), Color.html("#6e5030"), Color.html("#c4a171")] if kind == "wood" else [Color.html("#a4a19a"), Color.html("#8c8983"), Color.html("#6a6660")]
		for i in 5:
			var a := randf() * TAU
			var sp := 0.6 + randf() * 1.5
			parts.append({"kind": "chip", "x": x, "y": y, "z": 0.6, "vx": cos(a) * sp, "vy": sin(a) * sp, "vz": 1.0 + randf() * 2.0, "life": 1.5, "size": 0.05 + randf() * 0.05, "color": cols[i % 3], "rot": randf() * 3.0, "vr": (randf() - 0.5) * 20.0})


func muzzle(x: float, y: float, ang: float, big: bool) -> void:
	flashes.append({"x": x, "y": y, "ang": ang, "t": 0.0, "dur": 0.08 if big else 0.06, "big": big})


func tracer(x0: float, y0: float, x1: float, y1: float) -> void:
	tracers.append({"a": Vector2(x0, y0), "b": Vector2(x1, y1), "t": 0.0, "dur": maxf(0.05, Vector2(x1 - x0, y1 - y0).length() / 70.0)})


func casing(x: float, y: float, ang: float, shell: bool) -> void:
	var a := ang + PI / 2.0 + (randf() - 0.5) * 0.6
	parts.append({"kind": "casing", "x": x, "y": y, "z": 0.5, "vx": cos(a) * 1.8, "vy": sin(a) * 1.8, "vz": 2.2, "life": 6.0, "size": 0.07 if shell else 0.045, "shell": shell, "rot": randf() * 3.0, "vr": 18.0})


func smoke(x: float, y: float, size: float, dark: bool) -> void:
	parts.append({"kind": "smoke", "x": x + (randf() - 0.5) * 0.3, "y": y + (randf() - 0.5) * 0.3, "z": 0.0, "vx": 0.35 + randf() * 0.2, "vy": -0.25 - randf() * 0.2, "life": 4.5, "max": 4.5, "size": size, "dark": dark})


func ember(x: float, y: float) -> void:
	parts.append({"kind": "ember", "x": x + (randf() - 0.5) * 0.4, "y": y, "z": 0.4, "vx": (randf() - 0.3) * 0.6, "vy": -0.4 - randf() * 0.8, "life": 0.8 + randf() * 1.2, "size": 0.03})


func update(dt: float) -> void:
	for p in parts:
		p.life -= dt
		if p.kind == "smoke":
			p.x += p.vx * dt
			p.y += p.vy * dt
			p.size += dt * 0.35
			continue
		if p.kind == "ember":
			p.x += p.vx * dt + sin(p.life * 7.0) * dt * 0.3
			p.y += p.vy * dt
			continue
		if p.get("resting", false):
			continue
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.vz -= G * dt
		p.z += p.vz * dt
		if p.has("rot"):
			p.rot += p.vr * dt
		if p.z <= 0.0:
			p.z = 0.0
			if p.kind == "blood":
				if randf() < 0.35:
					decal(p.x, p.y, 0.12 + randf() * 0.12)
				p.life = 0.0
			elif p.kind == "spark":
				p.life = minf(p.life, 0.05)
			elif p.kind == "casing" or p.kind == "chip":
				if absf(p.vz) > 1.2:
					p.vz = -p.vz * 0.35
					p.vx *= 0.5
					p.vy *= 0.5
					p.vr *= 0.5
				else:
					p.resting = true
	var kept: Array = []
	for p in parts:
		if p.life > 0.0:
			kept.append(p)
	parts = kept
	for dd in decals:
		dd.age += dt
		if dd.grow > 0.0 and dd.age < 3.0:
			dd.size += dd.grow * dt / 3.0
			_scale_decal(dd)
	for tr in tracers:
		tr.t += dt
	tracers = tracers.filter(func(tr): return tr.t < tr.dur + 0.04)
	for f in flashes:
		f.t += dt
	flashes = flashes.filter(func(f): return f.t < f.dur)


func flash_lights() -> Array:
	var out: Array = []
	for f in flashes:
		out.append({"x": f.x, "y": f.y, "r": 4.5 if f.big else 3.4})
	return out


# ---------------------------------------------------------------- drawing --
# Painters are called by nodes; they draw in tile units.

func draw_ground_bits(ci: CanvasItem) -> void:
	for p in parts:
		if (p.kind == "casing" or p.kind == "chip") and p.get("resting", false):
			_draw_bit(ci, p)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_bit(ci: CanvasItem, p: Dictionary) -> void:
	ci.draw_set_transform(Vector2(p.x, p.y - p.z * 0.6) * TILE, p.get("rot", 0.0), Vector2(TILE, TILE))
	var a := minf(1.0, p.life * 2.0)
	var s: float = p.size
	if p.kind == "casing":
		var c := Color.html("#b8352c") if p.shell else Color.html("#c9a54a")
		c.a = a
		ci.draw_rect(Rect2(-s, -s * 0.45, s * 2.0, s * 0.9), c)
		if p.shell:
			ci.draw_rect(Rect2(s * 0.4, -s * 0.45, s * 0.6, s * 0.9), Color(0.79, 0.65, 0.29, a))
	else:
		var c: Color = p.color
		c.a = a
		ci.draw_rect(Rect2(-s, -s * 0.35, s * 2.0, s * 0.7), c)


func draw_air(ci: CanvasItem) -> void:
	for p in parts:
		if p.kind == "smoke":
			var k: float = p.life / p.max
			var fade := minf(1.0, (p.max - p.life) * 2.0)
			var alpha := clampf(k * 1.3, 0.0, 1.0) * fade * (0.42 if p.dark else 0.28)
			var r: float = p.size * 1.8
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
			ci.draw_texture_rect(puff_dark if p.dark else puff_light, Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false, Color(1, 1, 1, alpha))
		elif p.kind == "blood":
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
			ci.draw_circle(Vector2(p.x, p.y - p.z * 0.6), p.size, Color.html("#5a1410"))
		elif (p.kind == "casing" or p.kind == "chip") and not p.get("resting", false):
			_draw_bit(ci, p)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Additive layer: sparks, embers, tracers, muzzle flashes.
func draw_add(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for p in parts:
		if p.kind == "spark":
			var a := Vector2(p.x, p.y - p.z * 0.6)
			ci.draw_line(a, a - Vector2(p.vx, p.vy) * 0.03, Color(1.0, 0.84, 0.47, minf(1.0, p.life * 5.0)), 0.025, true)
		elif p.kind == "ember":
			ci.draw_rect(Rect2(p.x - p.size / 2.0, p.y - p.size / 2.0, p.size, p.size), Color(1.0, (140.0 + randf() * 60.0) / 255.0, 0.24, minf(1.0, p.life)))
	for tr in tracers:
		var k: float = minf(1.0, tr.t / tr.dur)
		var k0 := maxf(0.0, k - 0.35)
		var a: Vector2 = tr.a.lerp(tr.b, k0)
		var b: Vector2 = tr.a.lerp(tr.b, k)
		if a.distance_to(b) < 0.001:
			continue
		ci.draw_polyline_colors(PackedVector2Array([a, b]), PackedColorArray([Color(1.0, 0.86, 0.59, 0.0), Color(1.0, 0.94, 0.78, 0.95)]), 0.045, true)
	for f in flashes:
		var k: float = 1.0 - f.t / f.dur
		var r: float = (0.55 if f.big else 0.4) * (0.7 + 0.3 * k)
		ci.draw_texture_rect(radial, Rect2(f.x - r, f.y - r, r * 2.0, r * 2.0), false, Color(1.0, 0.85, 0.55, k))
		ci.draw_set_transform(Vector2(f.x, f.y) * TILE, f.ang, Vector2(TILE, TILE))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -0.06), Vector2(r * 1.4, 0), Vector2(0, 0.06)]), Color(1.0, 0.93, 0.71, k))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
