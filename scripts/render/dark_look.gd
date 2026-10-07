## The dark look of the game: an overcast, cold, desaturated day, a night that is really dark, and the one full-screen grade that finishes the picture. The owner's first outside
## tester said "too bright, much darker", and the daytime was a sunny cartoon; this is the answer.
##
## HOW. Two cheap things, and no per-sprite shader anywhere:
##  - the sky's CanvasModulate (scripts/render/lighting.gd) carries the AMBIENT table below instead of the old sky: about half of today's brightness at noon, cold grey-green-blue; dusk
##    a dim amber murk; the night about 23 percent of the light, a cold moonlight blue (the lit pools are what is seen, and the open street, the walls and the doors read as faint shapes: scripts/render/dark_lights.gd). `lighting.dark`, which says when the lamps burn,
##    still comes from the old table (`Lighting.SKY`), so that nothing that waits for the dusk waits for a different one;
##  - ONE full-screen pass (scripts/render/dark_grade.gdshader) on a CanvasLayer above the world and under the glow layer: the colour drained (35 percent by day), a cold tint, deeper
##    shadows, a vignette and a very light still film grain (off with Reduce motion), and the player's Brightness. It is the only extra pass of the whole look.
## The interior is dimmer than the street by day (`INDOOR_DAY`: a blend over INDOOR_FADE seconds when the avatar steps into a house or out of one), `extra_dim` (0 to 1, smoothed: the
## rain, `lighting.set_extra_dim`) darkens and cools the whole picture a further notch, and the Brightness setting (`ui.brightness` 0.7 to 1.3, `--bright=F` for a shot) lifts or lowers the
## result at the end.
##
## Used by lighting.gd (`lighting.look`); main.gd makes it (`setup`) after the lighting and before the glow layer, so that the grade is under the glow, the marks and the HUD.
extends Node

const Prefs := preload("res://scripts/prefs.gd")
const SHADER := preload("res://scripts/render/dark_grade.gdshader")

## The ambient light by hour (what the sky's CanvasModulate says; keyframes as the old sky's, the same dawn and dusk).
const AMBIENT := [
	[0.0, Color(0.172, 0.198, 0.320)],
	[4.8, Color(0.172, 0.198, 0.320)],
	[5.6, Color(0.245, 0.228, 0.300)],
	[6.4, Color(0.400, 0.400, 0.430)],
	[7.2, Color(0.560, 0.610, 0.630)],
	[17.6, Color(0.560, 0.600, 0.620)],
	[18.4, Color(0.470, 0.400, 0.360)],
	[19.0, Color(0.330, 0.260, 0.260)],
	[19.6, Color(0.200, 0.180, 0.240)],
	[20.3, Color(0.170, 0.178, 0.275)],
	[21.0, Color(0.172, 0.198, 0.320)],
	[24.0, Color(0.172, 0.198, 0.320)],
]
## What the grade does by day and by night (the shader's uniforms; the day's are the overcast).
const DAY_DESAT := 0.36
const NIGHT_DESAT := 0.20
const DAY_TINT := Color(0.95, 1.0, 1.03)
const NIGHT_TINT := Color(0.96, 0.99, 1.05)
const DAY_SHADOW := 1.14
const NIGHT_SHADOW := 1.0
const VIGNETTE := 0.55
const VIGNETTE_FROM := 0.48
const GRAIN := 0.022
## The ambient light of a room: this much of the street's by day, this much at night (the avatar's light, the lamps and the windows light it from there).
const INDOOR_DAY := 1.05
const INDOOR_NIGHT := 0.9
const INDOOR_FADE := 0.5
## In a room the grade's deep-shadow gamma goes (to this): the floors and furniture are dark pictures and must read; the street keeps its deep shadows.
const INDOOR_SHADOW := 1.0
## `extra_dim` at 1 leaves this much of the light, takes this much of the red and green off the sky, and takes this much of the lamps' reach.
const DIM_LEFT := 0.58
## At night the dark is dark enough already: a storm's `extra_dim` of 1 leaves this much of the moonlight (a night's rain must still be played in).
const DIM_LEFT_NIGHT := 0.78
const DIM_COLD := Color(0.88, 0.95, 1.04)
const DIM_REACH := 0.14
const DIM_RATE := 0.6
## Below 100 percent the Brightness setting is this much softer in the dark of the night (0: as by day, 1: none): 70 percent at night is the grade of 85, so that the street still reads.
const NIGHT_BRIGHT_SOFT := 0.5
const BRIGHT_MIN := 0.7
const BRIGHT_MAX := 1.3

var layer: CanvasLayer
var rect: ColorRect
var mat: ShaderMaterial
## The Brightness setting (1: as the game is made), what a player set; `bright_flag` (`--bright=F`, a shot's) takes its place when it is above 0.
var brightness := 1.0
var bright_flag := -1.0
## How much indoors the avatar is now (0 outside, 1 in a house), eased towards `indoor_to`.
var indoor := 0.0
var indoor_to := 0.0
## How much the weather has darkened the picture (0 to 1), eased towards `extra_dim_to`.
var extra_dim := 0.0
var extra_dim_to := 0.0
## The title's backdrop is a milder picture (it has its own evening).
var title := false
## Reduce motion: no grain.
var calm := false

var _read_t := -10.0
var _last := {}


## Makes the grade's layer in `parent` (the game's root), in front of the world and (put there before the glow layer is made) behind it.
func setup(parent: Node, is_title: bool = false) -> void:
	title = is_title
	layer = CanvasLayer.new()
	layer.name = "Grade"
	layer.layer = 1
	parent.add_child(layer)
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	layer.add_child(rect)
	_read_prefs(0.0)
	_push(0.0, 0.0)


## The ambient light at the hour (the standard day's hour: a season's is mapped before).
static func ambient_at(hour: float) -> Color:
	for i in range(1, AMBIENT.size()):
		if hour <= AMBIENT[i][0]:
			var h0: float = AMBIENT[i - 1][0]
			var h1: float = AMBIENT[i][0]
			var c0: Color = AMBIENT[i - 1][1]
			return c0.lerp(AMBIENT[i][1], (hour - h0) / (h1 - h0))
	return AMBIENT[0][1]


## 0 by day, 1 in the dark of the night, from `lighting.dark` (the old sky's darkness: 0 by day to 0.66 at night).
static func night_of(dark: float) -> float:
	return clampf(dark / 0.62, 0.0, 1.0)


## The ambient colour of the world as it is now: the hour's, a house's, the weather's.
func world_color(hour: float, night: float) -> Color:
	var c := ambient_at(hour)
	if indoor > 0.001:
		c = c * lerpf(1.0, lerpf(INDOOR_DAY, INDOOR_NIGHT, night), indoor)
	if extra_dim > 0.001:
		c = c * lerpf(1.0, lerpf(DIM_LEFT, DIM_LEFT_NIGHT, night), extra_dim) * Color(1, 1, 1).lerp(DIM_COLD, extra_dim)
	return Color(c.r, c.g, c.b, 1.0)


## How much of its reach a lamp keeps in this weather.
func reach_k() -> float:
	return 1.0 - DIM_REACH * extra_dim


func set_extra_dim(v: float) -> void:
	extra_dim_to = clampf(v, 0.0, 1.0)


## One frame: the eased things go their way, the setting is read twice a second, the shader gets what changed. `night` is 0 by day to 1 at night.
func follow(dt: float, night: float, t: float) -> void:
	if title:
		indoor = 0.0
	elif calm:
		indoor = indoor_to
	else:
		indoor = move_toward(indoor, indoor_to, dt / INDOOR_FADE)
	if calm:
		extra_dim = extra_dim_to
	else:
		extra_dim = move_toward(extra_dim, extra_dim_to, dt * DIM_RATE)
	_read_prefs(t)
	_push(night, t)


## The Brightness setting and Reduce motion, looked at twice a second (and `--bright=F` over the setting).
func _read_prefs(t: float) -> void:
	if t - _read_t < 0.5 and t >= _read_t:
		return
	_read_t = t
	brightness = clampf(Prefs.number("ui", "brightness"), BRIGHT_MIN, BRIGHT_MAX)
	calm = Prefs.on("ui", "reduce_motion")


func current_brightness() -> float:
	return bright_flag if bright_flag > 0.0 else brightness


func _push(night: float, _t: float) -> void:
	if mat == null:
		return
	var desat := lerpf(DAY_DESAT, NIGHT_DESAT, night) + 0.14 * extra_dim
	var tint := DAY_TINT.lerp(NIGHT_TINT, night)
	if extra_dim > 0.001:
		tint = tint * Color(1, 1, 1).lerp(Color(0.95, 0.99, 1.04), extra_dim)
	var shadow := lerpf(lerpf(DAY_SHADOW, NIGHT_SHADOW, night), INDOOR_SHADOW, indoor) + 0.05 * extra_dim
	var vig := VIGNETTE + 0.08 * extra_dim
	var grain := 0.0 if calm else GRAIN
	if title:
		desat = 0.12
		tint = Color(1, 1, 1)
		shadow = 1.0
		vig = 0.38
		grain = 0.0 if calm else GRAIN * 0.7
	var b := current_brightness()
	if b < 1.0:
		b = lerpf(b, lerpf(b, 1.0, NIGHT_BRIGHT_SOFT), night)    # (a dim screen at night would take the moonlit ground with it: the low end of the slider is half as strong in the dark)
	var now := {"desat": desat, "tint": Vector3(tint.r, tint.g, tint.b), "shadow": shadow, "vig": vig, "vig_from": VIGNETTE_FROM, "grain": grain, "bright": b}
	for k in now:
		if _last.get(k) != now[k]:
			_last[k] = now[k]
			mat.set_shader_parameter(k, now[k])
