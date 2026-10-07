## Short-lived effects: muzzle flashes, tracers, blood, splinters, sparks,
## smoke and embers, plus blood that stays on the ground (as sprites, so each
## splat is lit on its own).
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Combat := preload("res://scripts/render/combat_fx.gd")
const TILE := GD.TILE
const G := 9.8
## Casings on the ground and in the air at most (the oldest is gone first).
const MAX_CASINGS := 24
## FEEL: how long after the shot a pump gun's shell is thrown (the rack).
const RACK_DELAY := 0.34

var parts: Array = []
var tracers: Array = []
var decal_parent: Node2D
var blood_tex: Array = []
## The feel of a fight (scripts/render/combat_fx.gd): the muzzle flash and its light, blood, hits and kills, the splats, the camera's push, the
## sounds of a hit and a reload. This object's `muzzle`, `blood`, `decal` and the "bullet" `hit_material` are its.
var combat = Combat.new()
var _casings: Array = []
var _racks: Array = []    # {in, x, y, ang}: a pump gun's shells waiting for the rack
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
	combat.setup(blood_tex, parent, radial_tex, puff_light, puff_dark)


## Blood from a wound (the rules' bites, wounds and blows): drops that fly and fall, a puff of it (combat_fx.gd).
func blood(x: float, y: float, dx: float, dy: float, n: int = 10) -> void:
	combat.blood(x, y, dx, dy, n)


## A splat on the ground (a kill's, a drop's): it grows a little, holds, fades away in about twenty seconds and is pooled (combat_fx.gd).
func decal(x: float, y: float, size: float, grow: float = 0.0) -> void:
	combat.decal(x, y, size, grow)


## What a blow or a bullet does to a wall: `kind` "metal", "wood" or "stone" (the builders' hammer, a claw: sparks or chips, below) or "bullet"
## (a shot stopped by a wall: sparks, chips, dust and a zing, combat_fx.gd).
func hit_material(x: float, y: float, kind: String) -> void:
	if kind == "bullet":
		combat.hit_wall(x, y)
		return
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


## The flash of a shot at the muzzle (combat_fx.gd: by weapon, with its light).
func muzzle(x: float, y: float, ang: float, big: bool) -> void:
	combat.muzzle(x, y, ang, big)


func tracer(x0: float, y0: float, x1: float, y1: float) -> void:
	tracers.append({"a": Vector2(x0, y0), "b": Vector2(x1, y1), "t": 0.0, "dur": maxf(0.05, Vector2(x1 - x0, y1 - y0).length() / 70.0)})


## A casing pops out to the right of the gun, falls, bounces and lies there a few seconds (at most MAX_CASINGS at once). FEEL: a pump gun keeps its shell until the rack (about a third of a
## second after the shot, as the fore-end comes back: pawn_node.gd's pump), then throws it.
func casing(x: float, y: float, ang: float, shell: bool) -> void:
	if shell:
		if _racks.size() < 6:
			_racks.append({"in": RACK_DELAY, "x": x, "y": y, "ang": ang})
		return
	_throw_casing(x, y, ang, false)


func _throw_casing(x: float, y: float, ang: float, shell: bool) -> void:
	var a := ang + PI / 2.0 + (randf() - 0.5) * 0.7
	var sp := 1.5 + randf() * 0.8
	var p := {"kind": "casing", "x": x, "y": y, "z": 0.5, "vx": cos(a) * sp, "vy": sin(a) * sp, "vz": 2.0 + randf() * 0.5, "life": 6.0, "size": 0.085 if shell else 0.055, "shell": shell, "rot": randf() * 3.0, "vr": (14.0 + randf() * 8.0) * (1.0 if randf() < 0.5 else -1.0), "bounced": false}
	parts.append(p)
	_casings.append(p)
	if _casings.size() > MAX_CASINGS:
		var old: Dictionary = _casings.pop_front()
		old.life = 0.0


func smoke(x: float, y: float, size: float, dark: bool) -> void:
	parts.append({"kind": "smoke", "x": x + (randf() - 0.5) * 0.3, "y": y + (randf() - 0.5) * 0.3, "z": 0.0, "vx": 0.35 + randf() * 0.2, "vy": -0.25 - randf() * 0.2, "life": 4.5, "max": 4.5, "size": size, "dark": dark})


func ember(x: float, y: float) -> void:
	parts.append({"kind": "ember", "x": x + (randf() - 0.5) * 0.4, "y": y, "z": 0.4, "vx": (randf() - 0.3) * 0.6, "vy": -0.4 - randf() * 0.8, "life": 0.8 + randf() * 1.2, "size": 0.03})


func update(dt: float) -> void:
	if not _racks.is_empty():
		var waiting: Array = []
		for r in _racks:
			r.in -= dt
			if r.in <= 0.0:
				_throw_casing(r.x, r.y, r.ang, true)
			else:
				waiting.append(r)
		_racks = waiting
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
				# (FEEL: a casing bounces once and then lies; a chip as it did)
				if (p.kind == "casing" and not p.bounced) or (p.kind == "chip" and absf(p.vz) > 1.2):
					p.vz = -p.vz * 0.32
					p.vx *= 0.5
					p.vy *= 0.5
					p.vr *= 0.5
					if p.kind == "casing":
						p.bounced = true
						combat.casing_tink(p.x, p.y)
				else:
					p.resting = true
	var kept: Array = []
	for p in parts:
		if p.life > 0.0:
			kept.append(p)
	parts = kept
	if not _casings.is_empty() and _casings[0].life <= 0.0:
		_casings = _casings.filter(func(c): return c.life > 0.0)
	for tr in tracers:
		tr.t += dt
	tracers = tracers.filter(func(tr): return tr.t < tr.dur + 0.04)
	combat.update(dt)


## The lights of the muzzle flashes now, for the light rig: [{x, y, r}].
func flash_lights() -> Array:
	return combat.flash_lights()


# ---------------------------------------------------------------- drawing --
# Painters are called by nodes; they draw in tile units.

func draw_ground_bits(ci: CanvasItem) -> void:
	combat.draw_ground(ci)    # (FEEL: footstep dust, the town's, under the people)
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
	combat.draw_air(ci)


## Additive layer: sparks, embers, tracers, muzzle flashes (combat_fx.gd draws the flashes and the sparks of a hit).
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
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	combat.draw_add(ci)
