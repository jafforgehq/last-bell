## LAMPS (prison only): the light of the lamps at night, drawn by the game's glow layer (prison_game.gd `_draw_glow`: one additive Control over the night tint, so a pool lights the ground and
## whoever walks in it alike). No PointLight2D: every lamp is three or four soft textures in one batch.
##
## A LAMP is a warm pool on the ground with a long gentle falloff (`pool_tex`: a plateau, then a smooth tail), a small hot head, a faint halo round the head that grows in rain and fog, and on
## wet ground a sheen (a narrow bright smear under the head, as a lamp shows in a wet street). A few flicker now and then (a short stutter, a few seconds apart, seeded by the lamp).
## THE BASE. With the generator built and fuelled (prison_upgrades.gd `_lit`, and no storm blackout) the yard lamps and the towers burn electric, warm white; without power the gate pair, the
## lamp by the canteen and the towers are oil lanterns (smaller, oranger, a flame's flicker) and the two far yard lamps are dark.
## A RAID. A street lamp of the town (`streetlamp` objects of the town kit, `lamppost` of the site layouts) burns at night if its seed says so (about three in five: a solar cell, a generator left running), with the same look; the rest are dark.
extends RefCounted

const Tower := preload("res://scripts/prison/prison_tower.gd")
const Upg := preload("res://scripts/prison/prison_upgrades.gd")

const TILE := 64.0
const ELECTRIC := Color(1.0, 0.8, 0.52)
const OIL := Color(1.0, 0.6, 0.28)
## Where a lamppost picture's head is, as a share of the picture (assets/objects/243 to 249_lamppost.png): the three upright ones and the two pairs of arms.
const HEAD := {"243": Vector2(0.16, 0.62), "244": Vector2(0.16, 0.62), "245": Vector2(0.16, 0.62), "246": Vector2(0.70, 0.12), "247": Vector2(0.70, 0.12), "248": Vector2(0.09, 0.12), "249": Vector2(0.09, 0.12)}

var game
var pool_tex: GradientTexture2D
var _raid_lamps: Array = []    # [head (tiles), seed]
var _raid_seen = null


func _init(g) -> void:
	game = g
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 0.6, 0.82, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.52), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0)])
	pool_tex = GradientTexture2D.new()
	pool_tex.gradient = gr
	pool_tex.fill = GradientTexture2D.FILL_RADIAL
	pool_tex.fill_from = Vector2(0.5, 0.5)
	pool_tex.fill_to = Vector2(1.0, 0.5)
	pool_tex.width = 128
	pool_tex.height = 128


## Whether the base has electric light now.
func powered() -> bool:
	return game.upg != null and game.upg.lights_on()


## The lamps of the place in view: [head (tiles), pool radius (tiles), colour, brightness 0..1, seed, oil].
func lamps(n: float) -> Array:
	var out: Array = []
	if game.mode == "base":
		var pw := powered()
		var i := 0
		for l in game.base.lamps:
			if pw:
				out.append([Vector2(l), 5.5, ELECTRIC, 0.5 * n, i, false])
			elif i < 3:
				out.append([Vector2(l), 3.4, OIL, 0.55 * n, i, true])
			i += 1
		for t in game.base.towers:
			out.append([Tower.lamp_pos(t) / TILE, 4.0 if pw else 2.8, ELECTRIC if pw else OIL, (0.3 if pw else 0.38) * n, i, not pw])    # (dim under the floodlight cone: it washed the guard out at 0.4)
			i += 1
		if pw:
			for p in Upg.POLES:
				out.append([Vector2(float(p[0]), float(p[1]) - 0.95) + Vector2(float(p[2]), float(p[3])) * 0.18, 0.0, ELECTRIC, n, i, false])    # (the pole's pool and cone are prison_upgrades.gd's: only the head and halo here)
				i += 1
	elif game.mode == "raid" and game.world != null:
		if _raid_seen != game.world:
			_find_raid_lamps()
		for l in _raid_lamps:
			out.append([l[0], 5.5, ELECTRIC, 0.5 * n, l[1], false])
	return out


func _find_raid_lamps() -> void:
	_raid_seen = game.world
	_raid_lamps = []
	for o in game.world.d.objects:
		var kd := String(o.get("kind", ""))
		if kd != "lamppost" and kd != "streetlamp":
			continue
		var sd := int(o.get("id", 0)) * 2654435761 % 1000
		if sd % 5 >= 3:    # (two in five are dark)
			continue
		if kd == "streetlamp":    # (the town kit's: a one-tile picture seen from above, the head in the middle)
			_raid_lamps.append([Vector2(float(o.cx), float(o.cy)), sd])
			continue
		if (o.get("pieces", []) as Array).is_empty():
			continue
		var pc: Dictionary = o.pieces[0]
		var f := String(pc.get("file", "")).get_file().left(3)
		var h: Vector2 = HEAD.get(f, Vector2(0.5, 0.5))
		if bool(pc.get("flip_h", false)):
			h.x = 1.0 - h.x
		_raid_lamps.append([Vector2(float(pc.x) + h.x * float(pc.w), float(pc.y) + h.y * float(pc.h)), sd])
	if game.args.has("log"):
		print("LAMPS raid lamps lit ", _raid_lamps.size(), " at ", _raid_lamps.map(func(l): return l[0]))


## A lamp's brightness factor now (1 most of the time): oil breathes; one electric lamp in four stutters for a moment every few seconds.
static func flicker(seed_i: int, oil: bool, t: float) -> float:
	if oil:
		return 0.88 + 0.08 * sin(t * 9.0 + float(seed_i) * 1.7) + 0.04 * sin(t * 23.0 + float(seed_i))
	if seed_i % 4 != 1:
		return 1.0
	var cyc := 6.0 + float(seed_i % 5)
	var u := fposmod(t + float(seed_i) * 1.3, cyc)
	if u < 0.35:
		return 0.35 + 0.65 * float(int(u * 40.0) % 2)
	return 1.0


## Draws the lamps (in view) on the glow layer: `to_screen` turns tiles into the layer's pixels, `px` is a tile in pixels; `wet` and `haze` from prison_rain.gd.
func draw(c: CanvasItem, list: Array, to_screen: Transform2D, px: float, v: Vector2, wet: float, haze: float, t: float) -> void:
	for l in list:
		var at: Vector2 = to_screen * (Vector2(l[0]) * TILE)
		var r: float = float(l[1]) * px
		var reach := maxf(r, 1.5 * px)
		if at.x < -reach or at.y < -reach or at.x > v.x + reach or at.y > v.y + reach:
			continue
		var oil: bool = l[5]
		var k: float = float(l[3]) * flicker(int(l[4]), oil, t)
		var col: Color = l[2]
		if r > 0.0:
			c.draw_texture_rect(pool_tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col, k))
			if wet > 0.05:    # the wet ground's sheen: a narrow bright smear under the lamp
				var s := Vector2(r * 0.22, r * 0.75)
				c.draw_texture_rect(pool_tex, Rect2(at + Vector2(-s.x, -s.y * 0.35), s * 2.0), false, Color(col, 0.38 * k * wet))
		var hr := (0.9 + 0.8 * haze) * px * (0.75 if oil else 1.0)    # the halo round the head: faint on a clear night, wide in rain and fog
		c.draw_texture_rect(pool_tex, Rect2(at - Vector2(hr, hr), Vector2(hr, hr) * 2.0), false, Color(col, (0.16 + 0.32 * haze) * k))
		var hh := 0.2 * px * (0.8 if oil else 1.0)    # the head itself: small and hot
		c.draw_texture_rect(pool_tex, Rect2(at - Vector2(hh, hh), Vector2(hh, hh) * 2.0), false, Color(1.0, 0.95, 0.82, minf(1.0, 1.8 * k)))
