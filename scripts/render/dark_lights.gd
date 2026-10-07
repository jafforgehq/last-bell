## The lights of the dark look (scripts/render/dark_look.gd): when the night is really dark, what you see is what is lit. In a town run the map has no lights of its own, so this node makes them:
##  - THE AVATAR'S OWN LIGHT: one PointLight2D, a small warm pool of about 5 tiles that goes with her from the dusk (a lantern at her belt: it burns in a blackout too), under the real light
##    of the floodlights, the muzzle flashes and the build's lamps (those are lighting.gd's, perimeter_view.gd's and combat_fx.gd's own);
##  - THE LAMPS AND THE WINDOWS, as additive halos in the glow layer (a PointLight2D is a pass over what it touches, a halo is a texture in a batch): the street lamps in view burn with the
##    dusk (and go out in a blackout with the other lamps), the windows of the claimed house are lit warm, the standing lamps of the house she is in glow (by day a little: a warm pool in a
##    dim room) and a lit window is a warm pane;
##  - THE DEAD STAY READABLE: within the screen's reach of the avatar or of a light (full to `RIM_NEAR` tiles, `RIM_LEFT` of it beyond), each of the dead gets a cold rim (a cold halo behind the body and a pair of pale eye
##    glints); beyond that they are dark shapes, as they should be, and never invisible;
##  - and it tells the grade whether the avatar is indoors (the house view's `avatar_house`), for the dimmer air of a room by day.
## Made by main.gd after the lighting (`setup`), `update` each frame before `lighting.update`; `glow_paint` is one of the glow layer's `extras`. Cost: one PointLight2D, a few dozen halos, one
## halo and two dots for each of the dead near her.
extends Node2D

const Lighting := preload("res://scripts/render/lighting.gd")
const DarkLook := preload("res://scripts/render/dark_look.gd")
const Prefs := preload("res://scripts/prefs.gd")

const TILE := 64.0
const AVATAR_R := 5.6
const AVATAR_ENERGY := 1.0
const AVATAR_COLOR := Color8(255, 196, 128)
## How much of its strength the lantern's pool has right on her (it climbs to full by 0.3 of its radius).
const POOL_CENTER := 0.72
## A muzzle flash within FLASH_NEAR tiles of her takes this much off her lantern while it lasts.
const FLASH_NEAR := 3.0
const FLASH_DIP := 0.6
## The dead are readable from the avatar and from any light, out to the edge of the screen: full to RIM_NEAR, RIM_LEFT of it from there on, nothing past the screen's corner (the reach is the larger of RIM_END and
## the view's half diagonal plus a tile; the last two tiles fade out; tiles; a 1280 x 800 window has its corner about 12 from the avatar).
const RIM_NEAR := 6.0
const RIM_END := 13.0
const RIM_LEFT := 0.62
const RIM_COLOR := Color(0.50, 0.70, 1.0)
const GLINT_COLOR := Color(0.80, 0.92, 1.0)
const LAMP_REACH := 14.0
const LAMP_COLOR := Color8(255, 206, 140)
const WINDOW_COLOR := Color8(255, 170, 84)
const ROOM_LAMP_COLOR := Color8(255, 182, 108)

var main
var sim
var lighting
## Off (`--nodarklook`): no avatar light, no lamps, windows or rim. `--darkoff=light,glow,rim` leaves one part out (to measure it).
var enabled := true
var off_light := false
var off_glow := false
var off_rim := false
var avatar_light: PointLight2D
var radial: Texture2D
var _lamps := PackedVector2Array()
var _lamp_in: Array = []
var _windows: Array = []
var _windows_house := -2
var _src := PackedVector2Array()
var _t := 0.0
var _me = null
var _hv = null
var _halo_on := true
var _own := 0.0
var _lit := 0.0
var _indoor_house := -1
var _calm := false
var _calm_t := -10.0
var _rim_end := RIM_END


## `main_node` is main.gd (the sim, the data, the town's parts, the camera) and `light_rig` the lighting node (this is put in it, so that --nolights hides it).
func setup(main_node, light_rig) -> void:
	main = main_node
	sim = main.sim
	lighting = light_rig
	name = "DarkLights"
	lighting.add_child(self)
	avatar_light = PointLight2D.new()
	avatar_light.name = "AvatarLight"
	avatar_light.texture = _pool_texture(128)
	avatar_light.texture_scale = AVATAR_R * 2.0 * TILE / 128.0
	avatar_light.color = AVATAR_COLOR
	avatar_light.blend_mode = Light2D.BLEND_MODE_ADD
	avatar_light.energy = 0.0
	avatar_light.visible = false
	add_child(avatar_light)
	var data: Dictionary = main.data
	var objects = data.get("objects")
	if objects is Array:
		for o in objects:
			var kind := String(o.get("kind", ""))
			if kind == "streetlamp":
				_lamps.append(Vector2(float(o.cx), float(o.cy)))
			elif String(o.get("kit", "")) == "lamp_floor" and o.has("in"):
				_lamp_in.append({"at": Vector2(float(o.cx), float(o.cy)), "house": int(o.get("in", -1))})


## The picture of the avatar's pool of light: bright to a third of its reach, then a long soft fall to the dark (the lamps' own falloff, lighting.gd's, drops too early for a pool you walk in).
static func _pool_texture(size: int) -> Texture2D:
	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	var i := 0
	for v in size:
		for u in size:
			var dx := (u + 0.5) / size * 2.0 - 1.0
			var dy := (v + 0.5) / size * 2.0 - 1.0
			var k := sqrt(dx * dx + dy * dy)
			var a := pow(1.0 - smoothstep(0.04, 1.0, k), 0.85) * (POOL_CENTER + (1.0 - POOL_CENTER) * smoothstep(0.0, 0.3, k))    # (a little under full right on her: a lantern at full on her own sprite washes it out)
			bytes[i] = 255
			bytes[i + 1] = 255
			bytes[i + 2] = 255
			bytes[i + 3] = int(clampf(a, 0.0, 1.0) * 255.0)
			i += 4
	return ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes))


func _base():
	var b = sim.get("base")
	return b if b != null and bool(b.claimed) else null


## One frame, before the lighting's: the avatar's light, the grade's idea of indoors, the list of lights the dead are read by.
func update(dt: float, t: float) -> void:
	if not enabled:
		avatar_light.visible = false
		return
	_t = t
	if t - _calm_t >= 0.5 or t < _calm_t:
		_calm_t = t
		_calm = Prefs.on("ui", "reduce_motion")
	var dark: float = lighting.dark
	_own = clampf((dark - 0.08) * 4.0, 0.0, 1.0)
	_lit = float(lighting.lamp_level)
	_me = null
	var av = sim.get("avatar")
	if av != null:
		_me = av.player()
	if main.title_mode:
		_me = null
	var hv = main.town.part("house_view") if main.get("town") != null and main.town.has_method("part") else null
	_hv = hv
	_indoor_house = int(hv.avatar_house) if hv != null and _me != null else -1
	if lighting.grade != null:
		lighting.grade.indoor_to = 1.0 if _indoor_house >= 0 else 0.0
		lighting.grade.title = bool(main.title_mode)    # (the title's backdrop has a milder grade: it has its own evening)
	_avatar_light()
	_sources()


func _avatar_light() -> void:
	var on: bool = _me != null and not _me.dead and _own > 0.01 and lighting.visible and not off_light
	if not on:
		avatar_light.visible = false
		return
	var fog: float = lighting.fog
	var reach := lerpf(1.0, Lighting.FOG_LIGHT_REACH, fog)
	if lighting.grade != null:
		reach *= lighting.grade.reach_k()
	var f := 1.0
	if not _calm:
		f = 0.965 + 0.035 * sin(_t * 7.3) * sin(_t * 2.1 + 1.0)
	avatar_light.position = Vector2(_me.x, _me.y - 0.25) * TILE
	avatar_light.texture_scale = AVATAR_R * 2.0 * TILE / 128.0 * reach
	avatar_light.energy = AVATAR_ENERGY * _own * f * lerpf(1.0, Lighting.FOG_LIGHT_ENERGY, fog) * (1.0 - FLASH_DIP * _flash_near())
	avatar_light.visible = avatar_light.energy > 0.01


## How close a muzzle flash is to her now, 0 (none within FLASH_NEAR tiles) to 1 (on her): her lantern dips with it, so that the flash and the lantern do not add up to a white-out of her own sprite.
func _flash_near() -> float:
	var fx = main.get("fx")
	if fx == null:
		return 0.0
	var k := 0.0
	for fl in fx.flash_lights():
		k = maxf(k, 1.0 - Vector2(float(fl.x) - _me.x, float(fl.y) - _me.y).length() / FLASH_NEAR)
	return clampf(k, 0.0, 1.0)


## The places the dead are read from: the avatar, the lit lamps and windows near the view, the floodlights of the base.
func _sources() -> void:
	_src.clear()
	if _me == null or _own < 0.2:
		return
	_src.append(Vector2(_me.x, _me.y))
	var shown: Rect2 = main.view_rect()
	_rim_end = maxf(RIM_END, shown.size.length() * 0.5 + 1.0)
	var view: Rect2 = shown.grow(_rim_end + 2.0)
	if _lit > 0.05:
		for p in _lamps:
			if view.has_point(p):
				_src.append(p)
	var pv = main.town.part("perimeter_view") if main.get("town") != null and main.town.has_method("part") else null
	if pv != null and "_flood" in pv:
		for id in pv._flood:
			var foot: Vector2 = pv._flood[id].foot
			if view.has_point(foot):
				_src.append(foot)
	_find_windows()
	for w in _windows:
		if view.has_point(w.at):
			_src.append(w.at + w.out)


## The windows of the claimed house, made again when the claim or the house changes.
func _find_windows() -> void:
	var b = _base()
	var h := int(b.house) if b != null else -1
	if h == _windows_house:
		return
	_windows_house = h
	_windows.clear()
	if h < 0:
		return
	var houses = sim.get("houses")
	var t = houses.get("town") if houses != null else null
	var rect := Rect2()
	if t is Dictionary and not t.is_empty():
		for hd in t.houses:
			if int(hd.id) == h:
				rect = Rect2(hd.rect)
	if not rect.has_area():
		return
	var centre := rect.get_center()
	var kit = main.data.get("kit")
	if not (kit is Dictionary):
		return
	for w in kit.get("windows", []):
		if int(w.get("house", -1)) != h or String(w.get("state", "")) != "intact":
			continue
		var at := Vector2(float(w.x) + 0.5, float(w.y) + 0.5)
		var vertical := String(w.orient) == "v"
		var out := Vector2(signf(at.x - centre.x), 0.0) if vertical else Vector2(0.0, signf(at.y - centre.y))
		_windows.append({"at": at, "out": out, "vertical": vertical})


# ------------------------------------------------------------------- the glow --

## The glow layer's painter (tile units, additive): the lamps' and windows' halos and the rim of the dead. `dark` is lighting.dark.
func glow_paint(ci: CanvasItem, radial_tex: Texture2D, dark: float) -> void:
	radial = radial_tex
	if not enabled or lighting == null or not lighting.visible:
		return
	var view: Rect2 = main.view_rect().grow(_rim_end + 2.0)
	var calm := _calm
	_halo_on = not off_glow
	# her own lantern: the light on the ground is the PointLight2D's (it shows what is under it, the dark asphalt hardly), and this soft warm halo is what makes it a pool on any floor
	if _me != null and avatar_light.visible:
		var f0 := avatar_light.energy / AVATAR_ENERGY
		_halo(ci, Vector2(_me.x, _me.y - 0.25), AVATAR_R * 0.8, AVATAR_COLOR, 0.12 * f0)
		_halo(ci, Vector2(_me.x, _me.y - 0.25), 1.5, Color8(255, 214, 160), 0.05 * f0)
	# the street lamps
	if _lit > 0.02:
		for p in _lamps:
			if not view.has_point(p):
				continue
			var f := 1.0 if calm else 0.94 + 0.06 * sin(_t * 3.1 + p.x * 2.7)
			_halo(ci, p, 4.6, LAMP_COLOR, 0.30 * _lit * f)
			_halo(ci, p, 1.3, Color8(255, 226, 170), 0.34 * _lit * f)
	# the windows of the claimed house: a lit pane and the light it throws outside
	if _own > 0.02:
		for w in _windows:
			if not view.has_point(w.at):
				continue
			var f := 1.0 if calm else 0.95 + 0.05 * sin(_t * 1.7 + w.at.x * 3.1 + w.at.y)
			var out: Vector2 = w.out
			_halo(ci, w.at, 0.62, Color8(255, 190, 110), 0.34 * _own * f)
			_halo(ci, Vector2(w.at) + out * 1.2, 2.8, WINDOW_COLOR, 0.34 * _own * f)
	# the standing lamps of the house she is in, and those of the claimed one
	var base = _base()
	var base_h := int(base.house) if base != null else -2
	var indoor_k: float = lighting.grade.indoor if lighting.grade != null else 0.0
	for l in _lamp_in:
		var h := int(l.house)
		var k := 0.0
		if h == _indoor_house:
			k = lerpf(0.55, 1.0, _own) * indoor_k
		elif h == base_h:
			k = _own * 0.9
		if k > 0.02 and view.has_point(l.at):
			var f := 1.0 if calm else 0.96 + 0.04 * sin(_t * 2.3 + l.at.x * 1.9)
			_halo(ci, l.at, 3.4, ROOM_LAMP_COLOR, 0.30 * k * f)
			_halo(ci, l.at, 0.9, Color8(255, 220, 160), 0.22 * k * f)
	_halo_on = not off_rim
	_dead_rim(ci, view)


func _halo(ci: CanvasItem, at: Vector2, r: float, color: Color, alpha: float) -> void:
	if alpha <= 0.003 or not _halo_on:
		return
	color.a = alpha
	ci.draw_texture_rect(radial, Rect2(at.x - r, at.y - r, r * 2.0, r * 2.0), false, color)


## A faint cold rim on the dead near the avatar and the lights, and two pale eyes: so that a body in the dark is a shape you can count.
func _dead_rim(ci: CanvasItem, view: Rect2) -> void:
	if _src.is_empty():
		return
	var night := clampf((DarkLook.night_of(float(lighting.dark)) - 0.2) / 0.5, 0.0, 1.0)
	if night <= 0.01:
		return
	var far2 := _rim_end * _rim_end
	var far := _rim_end - 2.0
	for z in sim.zombies:
		if z.state == "dead" or z.state == "dying":
			continue
		var p := Vector2(z.x, z.y)
		if not view.has_point(p):
			continue
		# (one that is not drawn is not given away: the dead in a room she has not looked into, or in a house she is not in, keep their secret)
		if _hv != null and not _hv.pawn_visible(z):
			continue
		var best := far2
		for s in _src:
			var d2 := p.distance_squared_to(s)
			if d2 < best:
				best = d2
		if best >= far2:
			continue
		var d := sqrt(best)
		var w := (1.0 - (1.0 - RIM_LEFT) * smoothstep(RIM_NEAR, far, d)) * (1.0 - smoothstep(far, _rim_end, d))
		var a := night * w
		_halo(ci, p + Vector2(0.0, -0.4), 0.72, RIM_COLOR, 0.17 * a)
		_halo(ci, p + Vector2(-0.085, -0.6), 0.055, GLINT_COLOR, 0.62 * a)
		_halo(ci, p + Vector2(0.085, -0.6), 0.055, GLINT_COLOR, 0.62 * a)
