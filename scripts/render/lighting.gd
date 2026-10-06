## Day and night. A CanvasModulate carries the sky colour; every lamp, fire
## barrel, lantern and floodlight is a PointLight2D whose texture has its
## falloff, cone and room clipping baked in (like the web version's light map).
##
## The storyteller's cards change the night (`update` is given `sim.storyteller.look()`): in a
## fog a soft veil drifts over the yard, thicker toward the edges, and every light looks shorter
## and weaker; in a blackout the generator is dead: the lamps, the lanterns and the floodlights
## go out (the fire barrels burn on) and the sky takes a cooler, darker tint. Both ease in and
## out, and under "reduce motion" they simply switch (and the fog does not drift).
##
## The seasons (round 10): in a campaign (`seasons` is set) the hour is mapped to the standard day's with the
## season's own `light_hour`, so that the keyframes above, made for a dusk at 19:00, follow Winter's early dusk
## and Summer's late one; and the day's colour is multiplied by the season's tint (Winter cold, Spring a little
## green, Summer warm). Autumn, and any game that is not a campaign, is lit exactly as it always was.
extends Node2D

const Prefs := preload("res://scripts/prefs.gd")

const TILE := 64.0
const SKY := [
	[0.0, Color8(68, 76, 116)],
	[4.8, Color8(68, 76, 116)],
	[5.6, Color8(150, 124, 150)],
	[6.4, Color8(236, 212, 198)],
	[7.2, Color8(255, 252, 246)],
	[17.6, Color8(255, 250, 240)],
	[18.4, Color8(252, 214, 172)],
	[19.0, Color8(232, 176, 146)],
	[19.6, Color8(168, 132, 148)],
	[20.3, Color8(100, 102, 142)],
	[21.0, Color8(70, 78, 118)],
	[24.0, Color8(68, 76, 116)],
]
const FLASH_POOL := 10
## A blackout multiplies the sky by this, a cooler and darker blue, as the power goes.
const BLACKOUT_TINT := Color(0.70, 0.79, 0.97)
## The colour of the fog by day, and how fast it comes and goes (a share a second); the lights in a
## fog keep this much of their energy and of their reach.
const FOG_DAY := Color(0.80, 0.83, 0.87)
const FOG_RATE := 0.35
const FOG_LIGHT_ENERGY := 0.72
const FOG_LIGHT_REACH := 0.78
## How fast the power goes out and comes back (a share a second).
const POWER_DOWN := 1.8
const POWER_UP := 0.8

## A soft, drifting veil: value noise in four octaves, stronger toward the edges of the screen.
const FOG_SHADER := "
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.8, 0.83, 0.87, 1.0);
uniform float density = 0.0;
uniform float drift = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float n = fbm(uv * vec2(3.4, 2.2) + vec2(drift * 0.020, drift * 0.007));
	float m = fbm(uv * vec2(6.5, 4.5) - vec2(drift * 0.031, -drift * 0.011) + vec2(31.0, 5.0));
	float edge = smoothstep(0.10, 0.85, distance(uv, vec2(0.5)) * 1.5);
	float a = density * (0.34 + 0.36 * n + 0.14 * m + 0.30 * edge);
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 0.88));
}
"

var modulate_node: CanvasModulate
## The dark look (scripts/render/dark_look.gd; made by main.gd): the ambient light of the day and of the night, the full-screen grade, a house's dimmer air and the weather's extra dark.
## null (a test's rig, the school's yard under `--noavatar` has it too): the sky is the old one, as it was.
var grade = null
## The rules' seasons (sim.seasons); null, or not a campaign: no mapping and no tint.
var seasons = null
var lights: Array = [] # {def, node, scale}
var flash_nodes: Array = []
var flash_tex: Texture2D
var dark := 0.0
var lamp_level := 0.0
var floods_on := false
## How thick the fog is now (0 to 1), and how much power the lamps have (1 on, 0 a blackout): both
## eased towards what the storyteller says.
var fog := 0.0
var power := 1.0
## The fog's veil (a full screen of its own, under the glow layer and over the world).
var veil_layer: CanvasLayer
var veil: ColorRect
var _veil_material: ShaderMaterial
var _last_t := -1.0
var _drift := 0.0
## Round 24: whether the player asked for less motion (looked at twice a second): the lanterns then burn steadily.
var calm := false
var _calm_looked := -10.0


## Round 24: how bright an oil lantern burns at the time `t` (a share of its light, 1 at best): `warm` is the lamp level, 0 to 1. While the
## lamps come up at dusk it gutters a lot (down to half), later only a little (about a tenth).
static func lamp_flicker(t: float, x: float, warm: float) -> float:
	var k := 0.06 + 0.34 * (1.0 - clampf(warm, 0.0, 1.0))
	return 1.0 - k * (0.5 + 0.5 * sin(t * 9.1 + x * 2.9)) - k * 0.5 * (0.5 + 0.5 * sin(t * 23.7 + x * 5.3))


## How much darker the weather has made the picture, 0 to 1 (the rain: `set_extra_dim`). It is smoothed (about a second and a half from 0 to 1; at once under Reduce motion), darkens
## and cools the scene a notch (down to about 58 percent of the light at 1), takes a little off the lamps' reach and drains a little colour. 0 (the default) is the dry day.
func set_extra_dim(v: float) -> void:
	if grade != null:
		grade.set_extra_dim(v)


## The extra dark as it is now (the smoothed one; 0 with no dark look).
func get_extra_dim() -> float:
	return float(grade.extra_dim) if grade != null else 0.0


static func sky_at(hour: float) -> Color:
	for i in range(1, SKY.size()):
		if hour <= SKY[i][0]:
			var h0: float = SKY[i - 1][0]
			var h1: float = SKY[i][0]
			var c0: Color = SKY[i - 1][1]
			return c0.lerp(SKY[i][1], (hour - h0) / (h1 - h0))
	return SKY[0][1]


func setup(data: Dictionary, canvas_modulate: CanvasModulate) -> void:
	modulate_node = canvas_modulate
	for def in data.lights:
		var node := PointLight2D.new()
		var size := 256 if float(def.r) > 8.0 else 128
		node.texture = _light_texture(def, size)
		node.texture_scale = float(def.r) * 2.0 * TILE / size
		node.position = Vector2(def.x, def.y) * TILE
		node.color = Color8(int(def.color[0]), int(def.color[1]), int(def.color[2]))
		node.blend_mode = Light2D.BLEND_MODE_ADD
		node.energy = 0.0
		node.visible = false
		add_child(node)
		lights.append({"def": def, "node": node, "scale": node.texture_scale})
	flash_tex = _light_texture({"x": 0.0, "y": 0.0, "r": 1.0}, 64)
	for i in FLASH_POOL:
		var f := PointLight2D.new()
		f.texture = flash_tex
		f.color = Color8(255, 214, 150)
		f.blend_mode = Light2D.BLEND_MODE_ADD
		f.visible = false
		add_child(f)
		flash_nodes.append(f)
	_build_veil()


## The fog's veil: a full-screen rectangle with the shader above, on a layer of its own.
func _build_veil() -> void:
	veil_layer = CanvasLayer.new()
	veil_layer.layer = 1
	add_child(veil_layer)
	veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = FOG_SHADER
	_veil_material = ShaderMaterial.new()
	_veil_material.shader = shader
	veil.material = _veil_material
	veil.visible = false
	veil_layer.add_child(veil)


## Falloff stops match the web version: 0 -> 1, 0.3 -> 0.72, 0.65 -> 0.28, 1 -> 0.
static func _falloff(k: float) -> float:
	if k >= 1.0:
		return 0.0
	if k < 0.3:
		return lerpf(1.0, 0.72, k / 0.3)
	if k < 0.65:
		return lerpf(0.72, 0.28, (k - 0.3) / 0.35)
	return lerpf(0.28, 0.0, (k - 0.65) / 0.35)


static func _light_texture(def: Dictionary, size: int) -> Texture2D:
	var r: float = def.r
	var cx: float = def.x
	var cy: float = def.y
	var clip = def.get("clip")
	var cone = def.get("cone")
	var spread: float = def.get("spread", 0.0)
	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	var i := 0
	for v in size:
		for u in size:
			var dx := ((u + 0.5) / size * 2.0 - 1.0) * r
			var dy := ((v + 0.5) / size * 2.0 - 1.0) * r
			var dist := sqrt(dx * dx + dy * dy)
			var a := 0.0
			if cone != null:
				var ang := atan2(dy, dx)
				var diff := absf(atan2(sin(ang - cone), cos(ang - cone)))
				# soft beam edges so the cone does not step at close zoom
				a = _falloff(dist / r) * smoothstep(spread + 0.05, spread - 0.05, diff)
				a += maxf(0.0, 1.0 - dist / 2.2) * 0.5
			else:
				a = _falloff(dist / r)
			if clip != null:
				var wx := cx + dx
				var wy := cy + dy
				var outside := maxf(maxf(clip[0] - wx, wx - clip[2]), maxf(clip[1] - wy, wy - clip[3]))
				a *= clampf(1.0 - (outside + 0.06) / 0.12, 0.0, 1.0)
			bytes[i] = 255
			bytes[i + 1] = 255
			bytes[i + 2] = 255
			bytes[i + 3] = int(clampf(a, 0.0, 1.0) * 255.0)
			i += 4
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)
	return ImageTexture.create_from_image(img)


## `look` is what the storyteller's cards are doing: {"fog": 0 to 1, "blackout": bool} (see
## storyteller.look()); none of it when it is empty.
func update(hour: float, bell_rung: bool, t: float, flashes: Array, look: Dictionary = {}) -> void:
	var dt := 0.0 if _last_t < 0.0 else clampf(t - _last_t, 0.0, 0.25)
	_last_t = t
	_follow(look, dt)
	# a campaign's day is the season's: its hour is mapped to the standard day's, and its tint colours the light
	var tint := Color.WHITE
	if seasons != null and seasons.campaign:
		hour = seasons.light_hour(hour)
		tint = seasons.tint()
	var sky := sky_at(hour)
	dark = 1.0 - (sky.r + sky.g + sky.b) / 3.0
	# (the dark look: what the world is multiplied by is its own table, `dark` above still says when the lamps burn; the grade's pass is told how night it is)
	var world_sky := sky
	if grade != null:
		grade.follow(dt, grade.night_of(dark), t)
		world_sky = grade.world_color(hour, grade.night_of(dark))
	var flicker := 1.0
	if power > 0.0 and power < 1.0 and not Prefs.on("ui", "reduce_motion"):
		# the lamps stutter as the power goes
		flicker = 0.62 + 0.38 * sin(t * 43.0)
	lamp_level = clampf((dark - 0.08) * 4.0, 0.0, 1.0) * power * flicker
	_set_veil(sky)
	if dark <= 0.02:
		var day := Color.WHITE if grade == null else world_sky
		modulate_node.color = (day if fog < 0.01 else _grey(day, fog * 0.12)) * tint
		for l in lights:
			l.node.visible = false
		for f in flash_nodes:
			f.visible = false
		return
	modulate_node.color = _tinted(world_sky) * tint
	floods_on = bell_rung or hour >= 20.0 or hour < 6.0
	if t - _calm_looked >= 0.5 or t < _calm_looked:
		_calm_looked = t
		calm = Prefs.on("ui", "reduce_motion")
	var energy_k := lerpf(1.0, FOG_LIGHT_ENERGY, fog)
	var reach_k := lerpf(1.0, FOG_LIGHT_REACH, fog)
	if grade != null:
		reach_k *= grade.reach_k()    # (the rain mutes the lamps' reach a little)
	for l in lights:
		var def: Dictionary = l.def
		var level := 1.0
		if def.get("fire", false):
			level = 1.0
		elif def.get("flood", false):
			level = lamp_level if floods_on else 0.0
		else:
			level = lamp_level
		var f := 1.0
		var k: float = def.get("flicker", 0.0)
		if k > 0.0:
			f = 1.0 - 0.1 * k * (0.5 + 0.5 * sin(t * 13.7 + float(def.x) * 3.1)) - 0.06 * k * sin(t * 23.3 + float(def.y))
		elif def.get("lantern", false) and not calm:
			# (round 24) the oil lanterns burn unsteadily: a lot as they come up at dusk, a little all night
			f = lamp_flicker(t, float(def.x), lamp_level)
		var energy: float = minf(1.0, float(def.get("i", 1.0)) * level * f) * energy_k
		l.node.energy = energy
		l.node.texture_scale = float(l.scale) * reach_k
		l.node.visible = energy > 0.01
	for i in flash_nodes.size():
		var node: PointLight2D = flash_nodes[i]
		if i < flashes.size():
			var fl: Dictionary = flashes[i]
			node.position = Vector2(fl.x, fl.y) * TILE
			node.texture_scale = float(fl.r) * 2.0 * TILE / 64.0
			node.energy = 1.0
			node.visible = true
		else:
			node.visible = false


## The fog and the power come and go over a second or two (at once under reduce motion).
func _follow(look: Dictionary, dt: float) -> void:
	var fog_to := clampf(float(look.get("fog", 0.0)), 0.0, 1.0)
	var dark_to := bool(look.get("blackout", false))
	if Prefs.on("ui", "reduce_motion"):
		fog = fog_to
		power = 0.0 if dark_to else 1.0
		return
	_drift += dt
	fog = move_toward(fog, fog_to, FOG_RATE * dt)
	power = maxf(0.0, power - POWER_DOWN * dt) if dark_to else minf(1.0, power + POWER_UP * dt)


## The sky as the world sees it: cooler and darker in a blackout, a little greyer in a fog.
func _tinted(sky: Color) -> Color:
	var c := sky
	if power < 1.0:
		c = c * Color(1, 1, 1).lerp(BLACKOUT_TINT, 1.0 - power)
	if fog > 0.0:
		c = _grey(c, fog * 0.3)
	return c


## `c` a share `k` of the way to grey of the same brightness (a touch blue).
func _grey(c: Color, k: float) -> Color:
	var g := (c.r + c.g + c.b) / 3.0
	return c.lerp(Color(g, g, minf(1.0, g * 1.06)), k)


## The veil: the colour of the ambient light (the fog is lit by it), thick as the fog is, a little
## thinner at night (the dark is dark enough).
func _set_veil(sky: Color) -> void:
	if veil == null:
		return
	veil.visible = fog > 0.01
	if not veil.visible:
		return
	var bright := (sky.r + sky.g + sky.b) / 3.0
	var tint := FOG_DAY * (0.30 + 0.70 * bright)
	if power < 1.0:
		tint = tint * Color(1, 1, 1).lerp(BLACKOUT_TINT, 1.0 - power)
	_veil_material.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 1.0))
	_veil_material.set_shader_parameter("density", fog * lerpf(0.95, 0.62, dark))
	_veil_material.set_shader_parameter("drift", _drift)
