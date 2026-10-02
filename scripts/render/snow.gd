## Snow (round 10, the seasons): on a snow day, in a campaign, slow wide soft flakes drift down the screen
## and sideways, and the ground wears a light white cover (all drawn in code, no art).
##
## The flakes are not rain with another colour: they fall at a fifth of the speed a rain streak would, each
## wobbles on a sway of its own, the nearer ones are bigger, softer and brighter, and a slow wind carries them
## all one way and then the other. They are drawn on the screen (a layer of their own, over the world and under
## the HUD), so each is dimmed by hand as the light fails (the world's CanvasModulate does not reach them).
## Under "reduce motion" they fall at a third of the pace and do not sway. They stop with the game (`advance` is
## given the game's time) and ease in and out in a second or two (`follow`, given real time).
##
## `follow(look, snowy_season, dark, dt)`: `look` is what the storyteller's look() says (its "snow"); the ground's
## cover is lighter all through a season that has snow (`snowy_season`) and deeper on a snow day.
## `paint_ground(ci, world)` draws the cover over the outdoor ground, to be put in a node of the world just over
## the ground and under everything else.
extends Control

const GD := preload("res://scripts/game_data.gd")
const Prefs := preload("res://scripts/prefs.gd")

const TILE := GD.TILE
## How many flakes there are at most, and the screen area (pixels) one flake has: a bigger window shows more.
const FLAKES := 480
const AREA_PER_FLAKE := 4200.0
## How fast a far flake and a near one fall, in pixels a second (a rain streak would be 600 or more).
const FALL_FAR := 24.0
const FALL_NEAR := 64.0
## The width of a flake's sway (pixels, far and near) and how fast it sways (radians a second, far and near).
const SWAY_FAR := 7.0
const SWAY_NEAR := 20.0
const SWAY_RATE_FAR := 0.7
const SWAY_RATE_NEAR := 1.5
## The wind's push on every flake (pixels a second), and how much it swings to one side and the other.
const WIND := 14.0
const GUST := 9.0
## The diameter of a flake (pixels, far and near), and how opaque it is (far and near).
const SIZE_FAR := 5.0
const SIZE_NEAR := 15.0
const ALPHA_FAR := 0.45
const ALPHA_NEAR := 0.9
## How fast the snow comes and goes (a share a second), and what pace "reduce motion" leaves it.
const EASE := 0.6
const CALM_PACE := 0.34
## A flake's colour by day, and by night (the world's own night is bluer and darker).
const DAY_FLAKE := Color(1.0, 1.0, 1.0)
const NIGHT_FLAKE := Color(0.62, 0.70, 0.88)
## The cool halo behind a flake by day (the colour, and how much of the flake's own opacity it has).
const HALO := Color(0.45, 0.58, 0.78)
const HALO_ALPHA := 0.32
## The cover on the ground at the deepest (on a snow day), by the kind of ground, and how much of it a snowy
## season's ordinary day keeps. A tile's own share of it varies a little (a hash of where it is).
const COVER_COLOR := Color(0.93, 0.96, 1.0)
const COVER_ALPHA := {"GRASS": 0.44, "YARD": 0.36, "SOIL": 0.36, "DIRT": 0.36, "SIDEWALK": 0.26, "CONCRETE": 0.24, "ASPHALT": 0.20}
const COVER_QUIET := 0.55

## How much snow there is now (0 none, 1 the whole of it) and how much cover the ground has (0 to 1).
var intensity := 0.0
var ground := 0.0
## {x, y (0 to 1 of the screen), z (0 far to 1 near), phase, rate}.
var flakes: Array = []
var _t := 0.0
var _dark := 0.0
var _tex: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 1013
	for i in FLAKES:
		var z := rng.randf()
		flakes.append({"x": rng.randf(), "y": rng.randf(), "z": z, "phase": rng.randf() * TAU, "rate": lerpf(SWAY_RATE_FAR, SWAY_RATE_NEAR, z) * rng.randf_range(0.8, 1.2)})
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	_tex = GradientTexture2D.new()
	_tex.gradient = g
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(1.0, 0.5)
	_tex.width = 32
	_tex.height = 32


## Whether there is any snow to see.
func falling() -> bool:
	return intensity > 0.01


## How many of the flakes a window of this size shows.
static func count_for(area: float) -> int:
	return clampi(int(area / AREA_PER_FLAKE), 60, FLAKES)


## How fast a flake of depth `z` falls, in pixels a second.
static func fall_speed(z: float) -> float:
	return lerpf(FALL_FAR, FALL_NEAR, z)


## A flake's diameter in pixels.
static func flake_size(z: float) -> float:
	return lerpf(SIZE_FAR, SIZE_NEAR, z)


## The colour of the snow in the light of the moment (`dark` is the lighting's: 0 by day, towards 1 at night).
static func flake_color(dark: float) -> Color:
	return DAY_FLAKE.lerp(NIGHT_FLAKE, clampf(dark * 1.6, 0.0, 1.0))


## Every frame: eases the snow and the ground's cover towards what the weather says. `look` is the storyteller's
## look() ({"snow": bool}); `snowy_season` is a season with snow in it (Winter): its ground keeps a light cover.
func follow(look: Dictionary, snowy_season: bool, dark: float, dt: float) -> void:
	var to := 1.0 if bool(look.get("snow", false)) else 0.0
	var cover := 1.0 if to > 0.0 else (COVER_QUIET if snowy_season else 0.0)
	if Prefs.on("ui", "reduce_motion"):
		intensity = to
		ground = cover
	else:
		intensity = move_toward(intensity, to, EASE * dt)
		ground = move_toward(ground, cover, EASE * dt * 0.5)
	_dark = dark
	if visible != falling():
		visible = falling()
	if visible:
		queue_redraw()


## `h` seconds of the game's time: the flakes fall and sway and the wind blows.
func advance(h: float) -> void:
	if not falling():
		return
	var calm := Prefs.on("ui", "reduce_motion")
	var pace := CALM_PACE if calm else 1.0
	_t += h * pace
	var s := size if size.x > 1.0 else Vector2(1280, 800)
	var wind := (WIND + GUST * sin(_t * 0.35)) * pace
	for f in flakes:
		f.y += fall_speed(f.z) * h * pace / s.y
		f.x += (wind * (0.4 + 0.6 * f.z)) * h / s.x
		if f.y > 1.0:
			f.y -= 1.0
		if f.x > 1.0:
			f.x -= 1.0
		elif f.x < 0.0:
			f.x += 1.0
	queue_redraw()


## Where a flake is on the screen, in pixels (its place and the sway about it).
func screen_pos(f: Dictionary) -> Vector2:
	var calm := Prefs.on("ui", "reduce_motion")
	var sway := 0.0 if calm else sin(_t * float(f.rate) + float(f.phase)) * lerpf(SWAY_FAR, SWAY_NEAR, float(f.z))
	return Vector2(float(f.x) * size.x + sway, float(f.y) * size.y)


func _draw() -> void:
	if not falling():
		return
	var n := count_for(size.x * size.y)
	var base := flake_color(_dark)
	var halo := HALO_ALPHA * (1.0 - clampf(_dark * 3.0, 0.0, 1.0))
	for i in n:
		var f: Dictionary = flakes[i]
		var d := flake_size(float(f.z))
		var c := Color(base.r, base.g, base.b, lerpf(ALPHA_FAR, ALPHA_NEAR, float(f.z)) * intensity)
		var at := screen_pos(f)
		# by day a faint cool halo behind each flake, so that it shows on the white ground as well as on the dark
		if halo > 0.0:
			var hd := d * 1.7
			draw_texture_rect(_tex, Rect2(at - Vector2(hd, hd) * 0.5, Vector2(hd, hd)), false, Color(HALO.r, HALO.g, HALO.b, halo * float(c.a)))
		draw_texture_rect(_tex, Rect2(at - Vector2(d, d) * 0.5, Vector2(d, d)), false, c)


## The ground's cover: a light white over every outdoor tile (a share of it by the kind of ground and a little
## by where the tile is), drawn in tiles. For a node of the world just over the ground.
static func paint_ground(ci, world) -> void:
	if world == null or world.d == null:
		return
	var alpha := {}
	for type_name in COVER_ALPHA:
		if world.d.terrainTypes.has(type_name):
			alpha[int(world.d.terrainTypes[type_name].id)] = float(COVER_ALPHA[type_name])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	var w: int = world.W
	var h: int = world.H
	for y in h:
		for x in w:
			var t := int(world.terrain[y * w + x])
			if not alpha.has(t):
				continue
			var hash_ := fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
			var a: float = float(alpha[t]) * (0.78 + 0.44 * hash_)
			ci.draw_rect(Rect2(float(x), float(y), 1.03, 1.03), Color(COVER_COLOR.r, COVER_COLOR.g, COVER_COLOR.b, a))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
