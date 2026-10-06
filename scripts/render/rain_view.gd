## The rain you see and hear in the town (RAIN): a VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`, `on_sync_views(view)`). It reads the
## sky of the rules (`sim.skies`, scripts/town/skies.gd: the level 0 to 1, the kind, the clouds) and writes nothing in them. A game with no `sim.skies` (the school) makes none of it.
##
## THE RAIN. ONE full-screen quad (scripts/render/rain.gdshader) on a CanvasLayer over the world and the glow and under the HUD: three layers of streaks worked out from a hash of the pixel,
## no texture, a few numbers a frame (the density, the wind's slant, the clock, the pool of the avatar's light at night). Under a roof (the avatar is inside a house, her roof cut away) the
## rain fades out over half a second, and the rain bed's bus closes its low-pass: you hear it on the roof, not in the street. Under "reduce motion": about half the streaks, no near layer, a
## slower fall.
## THE SPLASHES. Up to SPLASH_MAX rings opening on the ground round the avatar (a MultiMesh, scripts/render/rain_splash.gdshader: ONE draw call), outdoors only, in a steady rain and a
## storm (a few in a drizzle).
## THE WET GROUND. While the ground is wet (it soaks over about nine seconds of rain and dries over about a minute) the meshes of the outdoor ground (lawn, road, sidewalk, dirt, gravel: a
## dozen draws that were there already) wear scripts/render/wet_ground.gdshader: darker, cooler, with puddles and a soft glint. Dry, they have no material at all.
## THE LIGHT. `lighting.set_extra_dim(v)` with 0.15 (a drizzle), 0.3 (steady) and 0.45 (a storm), eased, over whatever the day's grade is.
## LIGHTNING in a storm, every 11 to 32 seconds: two frames of white-blue over the whole screen, a dip, a second weaker flicker and a fade; thunder 1 to 3 seconds later (a far shot and a
## thud, pitched right down, on the Distant bus). "Reduce flashes" turns the flash into a slow gentle brightening.
## THE ICONS. A weather icon (scripts/ui/weather_glyph.gd) takes the place of the sun in the clock's temperature row while the sky is overcast or wet, and one sits on the minimap's rim, each
## with a tooltip.
##
## STAGING (a screenshot): `--weather=drizzle|rain|storm|clear` (main.gd: `sim.skies.force`), `--lightning` (a flash held at its brightest, no thunder), `--norain` (this part left out),
## `--rain-cost` (its CPU time per frame and the frame's draw calls, printed at frame 120).
extends RefCounted

const Access := preload("res://scripts/access.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const WeatherGlyph := preload("res://scripts/ui/weather_glyph.gd")
const RAIN_SHADER := preload("res://scripts/render/rain.gdshader")
const WET_SHADER := preload("res://scripts/render/wet_ground.gdshader")
const SPLASH_SHADER := preload("res://scripts/render/rain_splash.gdshader")

const TILE := 64.0
const SPLASH_MAX := 30
const SPLASH_LIFE := 0.55
## The ground meshes by group (TownArt.GROUNDS: lawn 0, asphalt 1, sidewalk 2, dirt path 3, gravel 4) and how much each shines.
const PAVED := {0: 0.0, 1: 1.0, 2: 1.0, 3: 0.2, 4: 0.5}
const INDOOR_FADE_S := 0.5
## How fast the ground soaks and dries (a share a second) and how fast the light follows the rain.
const WET_UP := 0.11
const WET_DOWN := 0.018
const DIM_RATE := 0.25
const BOLT_GAP := Vector2(11.0, 32.0)
## The flash by frame: the two bright ones, the dip, the second flicker; after them it fades by time.
const FLASH_FRAMES := [0.46, 0.42, 0.04, 0.02, 0.32, 0.27, 0.06, 0.22]
const FLASH_COLOR := Color(0.62, 0.74, 1.0)
const FAR_SHOT := "res://assets/audio/gunshot_far_1.wav"
const THUD := "res://assets/audio/thud_0.wav"

var main
var sim
var skies
var lighting
var layer: CanvasLayer
var rain: ColorRect
var flash: ColorRect
var rain_mat: ShaderMaterial
var splash_node: MultiMeshInstance2D
var splash_mm: MultiMesh
var hud_glyph
var mini_glyph
## What is drawn now (the tests and the shots read them): the density the shader has, how far indoors the avatar is (0 to 1), how wet the ground is, the light's extra dim.
var intensity := 0.0
var indoor := 0.0
var wet := 0.0
var dim_now := 0.0
var splashes := 0
var cost_us := 0.0
var cost_frames := 0

var _off := false
var _no_glyph := false
var _cost := false
var _hold_flash := false
var _rt := 3.7
var _view := Rect2()
var _rng := RandomNumberGenerator.new()
var _ground: Array = []
var _ground_looked := false
var _ground_t := 0.0
var _wet_mats := {}
var _wet_on := false
var _sx := PackedFloat32Array()
var _sy := PackedFloat32Array()
var _sage := PackedFloat32Array()
var _ssize := PackedFloat32Array()
var _sseed := PackedFloat32Array()
var _sacc := 0.0
var _bolt_t := 6.0
var _flash_frame := -1
var _flash_age := 0.0
var _thunder: Array = []
var _th_shot: AudioStreamPlayer
var _th_thud: AudioStreamPlayer
var _glyph_t := 0.0
var _last_muffle := -1.0
## What was last given to `lighting.set_extra_dim`.
var _dim_sent := 0.0
## The first frames draw each shader once, invisibly (a dry sky, nothing to see), so that the first rain is not a stall for the shaders to be made.
var _frames_seen := 0
var _warming := false


func on_ready(main_node) -> void:
	main = main_node
	sim = main.get("sim")
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a == "--norain":
			_off = true
		elif a == "--rain-cost":
			_cost = true
		elif a == "--lightning":
			_hold_flash = true
		elif a == "--rain-noglyph":
			_no_glyph = true
	var world = main.get("world")
	if _off or sim == null or world == null or sim.get("skies") == null:
		return
	skies = sim.skies
	lighting = main.get("lighting")
	_rng.randomize()
	# the rain: a layer of the screen between the glow and the HUD
	layer = CanvasLayer.new()
	layer.name = "RainLayer"
	layer.layer = 1
	main.add_child(layer)
	rain_mat = ShaderMaterial.new()
	rain_mat.shader = RAIN_SHADER
	rain = ColorRect.new()
	rain.name = "Rain"
	rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rain.material = rain_mat
	rain.visible = false
	layer.add_child(rain)
	flash = ColorRect.new()
	flash.name = "Lightning"
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = add
	flash.color = Color(0, 0, 0, 0)
	flash.visible = false
	layer.add_child(flash)
	_make_splashes(world)
	_make_thunder()
	if not _no_glyph:
		_attach_hud_glyph()
	if _hold_flash:
		_flash_frame = 0
	skies.snap = true


# ------------------------------------------------------------------------------ pieces --

func _make_splashes(world) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SPLASH_SHADER
	splash_mm = MultiMesh.new()
	splash_mm.transform_format = MultiMesh.TRANSFORM_2D
	splash_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	splash_mm.mesh = q
	splash_mm.instance_count = SPLASH_MAX
	splash_mm.visible_instance_count = 0
	splash_node = MultiMeshInstance2D.new()
	splash_node.name = "RainSplashes"
	splash_node.multimesh = splash_mm
	splash_node.material = mat
	splash_node.z_index = 1
	world.add_child(splash_node)
	for a in [_sx, _sy, _sage, _ssize, _sseed]:
		a.resize(SPLASH_MAX)


func _make_thunder() -> void:
	_th_shot = AudioStreamPlayer.new()
	_th_thud = AudioStreamPlayer.new()
	for p in [_th_shot, _th_thud]:
		p.bus = Buses.far_bus()
		layer.add_child(p)
	if ResourceLoader.exists(FAR_SHOT):
		_th_shot.stream = load(FAR_SHOT)
	if ResourceLoader.exists(THUD):
		_th_thud.stream = load(THUD)


func _attach_hud_glyph() -> void:
	var hud = main.get("hud")
	if hud == null or hud.get("temp_icon") == null:
		return
	var icon: Control = hud.temp_icon
	var row := icon.get_parent()
	hud_glyph = WeatherGlyph.new(16.0, false)
	hud_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hud_glyph)
	row.move_child(hud_glyph, icon.get_index())


## The minimap is another part, made before this one: its round window gets the icon on its upper left rim.
func _attach_mini_glyph() -> void:
	var town = main.get("town")
	var mm = town.part("minimap") if town != null else null
	if mm == null or mm.get("root") == null:
		return
	mini_glyph = WeatherGlyph.new(22.0, true)
	mm.root.add_child(mini_glyph)


# ------------------------------------------------------------------------------ frames --

func on_sync_views(view: Rect2) -> void:
	_view = view


func on_frame(dt: float) -> void:
	if skies == null:
		return
	var t0 := Time.get_ticks_usec()
	_frame(dt)
	cost_us += float(Time.get_ticks_usec() - t0)
	cost_frames += 1
	if _cost and cost_frames == 120:
		print("RAIN_COST ms per frame %.3f (this part's script), draw calls %d, level %.2f, wet %.2f, splashes %d" % [cost_us / float(cost_frames) / 1000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), skies.level, wet, splashes])


func _frame(dt: float) -> void:
	_frames_seen += 1
	_warming = _frames_seen >= 6 and _frames_seen <= 9 and skies.level < 0.01
	var running: bool = int(main.speed) > 0
	var calm := Prefs.on("ui", "reduce_motion")
	var gdt := dt if running else 0.0
	_rt += gdt * (0.5 if calm else 1.0)
	var level: float = skies.level
	var me = sim.avatar.player()
	var inside := false
	if me != null and sim.houses != null:
		inside = sim.houses.house_at(me.x, me.y) >= 0
	var snapped: bool = skies.snap
	if snapped:
		skies.snap = false
		indoor = 1.0 if inside else 0.0
		wet = _wet_target(level)
		dim_now = skies.dim()
	indoor = move_toward(indoor, 1.0 if inside else 0.0, dt / INDOOR_FADE_S)
	_update_rain(level, calm, me)
	_update_wet(dt, level)
	_update_splashes(gdt, level, me)
	_update_lightning(dt, gdt, level)
	_update_light(dt)
	_update_sound()
	_glyph_t -= dt
	if _glyph_t <= 0.0:
		_glyph_t = 0.2
		_update_glyphs()


## The rain quad's numbers.
func _update_rain(level: float, calm: bool, me) -> void:
	intensity = pow(level, 0.8) * (1.0 - indoor)
	var on := intensity > 0.01 or _warming
	if rain.visible != on:
		rain.visible = on
	if not on:
		return
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var gust := 0.10 * sin(_rt * 0.45) + 0.05 * sin(_rt * 1.3 + 1.0)
	rain_mat.set_shader_parameter("intensity", intensity)
	rain_mat.set_shader_parameter("wind", 0.10 + 0.30 * level + gust * level)
	rain_mat.set_shader_parameter("t", _rt)
	rain_mat.set_shader_parameter("res", vp)
	rain_mat.set_shader_parameter("dark", clampf(float(lighting.dark) * 1.6, 0.0, 1.0) if lighting != null else 0.0)
	rain_mat.set_shader_parameter("calm", 1.0 if calm else 0.0)
	rain_mat.set_shader_parameter("haze", smoothstep(0.35, 1.0, level))
	if me != null and vp.x > 1.0 and vp.y > 1.0:
		var at: Vector2 = main._tile_to_screen(Vector2(me.x, me.y))
		rain_mat.set_shader_parameter("pool", Vector2(at.x / vp.x, at.y / vp.y))
		rain_mat.set_shader_parameter("pool_r", clampf(5.0 * float(main.zoom_px) / vp.y, 0.10, 0.45))


# --------------------------------------------------------------------- the wet ground --

static func _wet_target(level: float) -> float:
	return clampf(level * 1.7, 0.0, 1.0)


func _update_wet(dt: float, level: float) -> void:
	var to := _wet_target(level)
	wet = move_toward(wet, to, (WET_UP if to > wet else WET_DOWN) * dt)
	if (wet > 0.01 or _warming) and not _ground_looked:
		_ground_t -= dt
		if _ground_t <= 0.0:
			_ground_t = 1.0
			_find_ground()
	if _ground.is_empty():
		return
	var on := wet > 0.01 or _warming
	if on != _wet_on:
		_wet_on = on
		for g in _ground:
			g.node.material = _wet_mat(float(g.paved)) if on else null
	if on:
		for k in _wet_mats:
			var m: ShaderMaterial = _wet_mats[k]
			m.set_shader_parameter("wet", wet)
			m.set_shader_parameter("t", _rt)


## The outdoor ground meshes of the town's world, found once the ground is built.
func _find_ground() -> void:
	var world = main.get("world")
	if world == null or not bool(world.get("kit")):
		_ground_looked = true
		return
	var holder = world.get_node_or_null("Ground")
	if holder == null:
		return
	_ground_looked = true
	for ch in holder.get_children():
		if not (ch is MeshInstance2D):
			continue
		var nm := String(ch.name)
		if nm == "Apron":
			_ground.append({"node": ch, "paved": 0.0})
		elif nm.begins_with("Ground"):
			var grp := int(nm.trim_prefix("Ground")) >> 2
			if PAVED.has(grp):
				_ground.append({"node": ch, "paved": float(PAVED[grp])})


func _wet_mat(paved: float) -> ShaderMaterial:
	var k := roundi(paved * 10.0)
	if not _wet_mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = WET_SHADER
		m.set_shader_parameter("paved", paved)
		_wet_mats[k] = m
	return _wet_mats[k]


# ----------------------------------------------------------------------- the splashes --

## How many drops a second land in the picture: none in a mist, a few in a drizzle, many in a steady rain, a great many in a storm.
static func splash_rate(level: float) -> float:
	if level < 0.12:
		return 0.0
	return lerpf(3.0, 26.0, clampf((level - 0.30) / 0.32, 0.0, 1.0)) if level < 0.62 else lerpf(26.0, 56.0, clampf((level - 0.62) / 0.38, 0.0, 1.0))


func _update_splashes(gdt: float, level: float, me) -> void:
	var n := splashes
	# the ones in the air age and go
	var i := 0
	while i < n:
		_sage[i] += gdt / SPLASH_LIFE
		if _sage[i] >= 1.0:
			n -= 1
			_sx[i] = _sx[n]
			_sy[i] = _sy[n]
			_sage[i] = _sage[n]
			_ssize[i] = _ssize[n]
			_sseed[i] = _sseed[n]
		else:
			i += 1
	var rate := splash_rate(level) * (1.0 - indoor)
	if rate > 0.0 and gdt > 0.0:
		_sacc += rate * gdt
		var centre := Vector2(me.x, me.y) if me != null else _view.get_center()
		var radius := clampf(_view.size.x * 0.38, 6.0, 14.0) if _view.size.x > 1.0 else 9.0
		while _sacc >= 1.0:
			_sacc -= 1.0
			if n >= SPLASH_MAX:
				continue
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * radius
			var x := centre.x + cos(a) * r
			var y := centre.y + sin(a) * r
			if sim.houses.house_at(x, y) >= 0:
				continue
			_sx[n] = x
			_sy[n] = y
			_sage[n] = 0.0
			_ssize[n] = _rng.randf_range(0.45, 0.85) * (0.8 + 0.4 * level)
			_sseed[n] = _rng.randf()
			n += 1
	else:
		_sacc = 0.0
	splashes = n
	if splash_mm == null:
		return
	if _warming and n == 0:
		# (one drop that cannot be seen: the shader is made now)
		splash_mm.visible_instance_count = 1
		splash_mm.set_instance_transform_2d(0, Transform2D(0.0, Vector2(8.0, 8.0), 0.0, Vector2(-9000.0, -9000.0)))
		splash_mm.set_instance_custom_data(0, Color(0.5, 0.0, 0.0, 0.0))
		return
	splash_mm.visible_instance_count = n
	var bright := clampf(0.35 + 0.65 * level, 0.0, 1.0)
	for k in n:
		var s := _ssize[k] * TILE
		splash_mm.set_instance_transform_2d(k, Transform2D(0.0, Vector2(s, s), 0.0, Vector2(_sx[k], _sy[k]) * TILE))
		splash_mm.set_instance_custom_data(k, Color(_sage[k], _sseed[k], bright, 0.0))


# ----------------------------------------------------------------------------- lightning --

func _update_lightning(dt: float, gdt: float, level: float) -> void:
	var storm: bool = skies.stormy() and level > 0.6
	if storm and gdt > 0.0:
		_bolt_t -= gdt
		if _bolt_t <= 0.0:
			_bolt_t = _rng.randf_range(BOLT_GAP.x, BOLT_GAP.y)
			_strike()
	elif not storm:
		_bolt_t = _rng.randf_range(4.0, 12.0)
	# the flash itself: by frame at first (two frames are two frames at any speed), then by time
	var a := 0.0
	var gentle := Access.reduce_flashes()
	if _hold_flash:
		a = 0.16 if gentle else FLASH_FRAMES[0]
	elif _flash_frame >= 0:
		if gentle:
			_flash_age += dt
			a = 0.12 * pow(sin(PI * clampf(_flash_age / 1.4, 0.0, 1.0)), 2.0)
			if _flash_age >= 1.4:
				_flash_frame = -1
		elif _flash_frame < FLASH_FRAMES.size():
			a = FLASH_FRAMES[_flash_frame]
			_flash_frame += 1
			_flash_age = 0.0
		else:
			_flash_age += dt
			a = 0.22 * exp(-_flash_age * 7.0)
			if a < 0.01:
				_flash_frame = -1
		a *= 1.0 - 0.45 * indoor
	var on := a > 0.004
	if flash.visible != on:
		flash.visible = on
	if on:
		flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, a)
	# the thunder that follows
	var i := _thunder.size() - 1
	while i >= 0:
		_thunder[i].t -= dt
		if _thunder[i].t <= 0.0:
			_boom(float(_thunder[i].far))
			_thunder.remove_at(i)
		i -= 1


func _strike() -> void:
	_flash_frame = 0
	_flash_age = 0.0
	var delay := _rng.randf_range(1.0, 3.0)
	_thunder.append({"t": delay, "far": (delay - 1.0) / 2.0})
	if _cost:
		print("RAIN lightning at game t %.1f, thunder in %.2f s" % [float(sim.t), delay])


## A flash held for a shot, or now (the tests): a strike with its thunder.
func strike() -> void:
	if skies != null:
		_strike()


func _boom(far: float) -> void:
	var vol := -1.0 - 9.0 * far - 5.0 * indoor
	if _cost:
		print("RAIN thunder: far %.2f, volume %.1f dB, shot %s, thud %s, bus %s" % [far, vol, _th_shot.stream != null, _th_thud.stream != null, _th_shot.bus])
	if _th_shot != null and _th_shot.stream != null:
		_th_shot.pitch_scale = 0.46 + 0.07 * far
		_th_shot.volume_db = vol + 8.0
		_th_shot.play()
	if _th_thud != null and _th_thud.stream != null:
		_th_thud.pitch_scale = 0.36 + 0.06 * far
		_th_thud.volume_db = vol + 2.0
		_th_thud.play()


# -------------------------------------------------------------------- light and sound --

func _update_light(dt: float) -> void:
	if lighting == null or not lighting.has_method("set_extra_dim"):
		return
	var to: float = skies.dim()
	dim_now = move_toward(dim_now, to, DIM_RATE * dt)
	if absf(dim_now - _dim_sent) > 0.001 or (dim_now == 0.0 and _dim_sent != 0.0):
		_dim_sent = dim_now
		lighting.set_extra_dim(dim_now)


func _update_sound() -> void:
	if not is_equal_approx(indoor, _last_muffle):
		_last_muffle = indoor
		Buses.set_rain_muffle(indoor)


# ----------------------------------------------------------------------------- the icons --

func _update_glyphs() -> void:
	if _no_glyph:
		return
	if _frames_seen > 30:
		WeatherGlyph.prewarm_next()    # (one picture at a time, a few frames into the run: no first rain waits for one)
	var w: String = skies.word()
	var tip: String = skies.tip()
	if hud_glyph != null:
		var shown := w != "clear"
		hud_glyph.set_word(w, tip)
		hud_glyph.visible = shown
		var hud = main.get("hud")
		if hud != null and hud.get("temp_icon") != null:
			hud.temp_icon.visible = not shown
	if mini_glyph == null and not _no_glyph:
		_attach_mini_glyph()
	if mini_glyph != null:
		mini_glyph.set_word(w, tip)
		mini_glyph.visible = w != "clear"
		var mm = main.town.part("minimap")
		if mm != null and mm.root != null:
			var s: Vector2 = mm.root.size
			mini_glyph.position = Vector2(s.x, s.y) * 0.1464 - mini_glyph.size * 0.5
