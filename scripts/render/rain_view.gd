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
## LIGHTNING (LOOK2: the owner never noticed any). In a storm every 11 to 32 seconds, in a STEADY rain every 30 to 75 (weaker, farther, softer thunder), none in a drizzle; the schedule is the
## rules' (scripts/town/skies.gd `strikes_between`: a pure function of the run's seed and the game clock, so a save reloads the same sky) and this part shows and sounds a strike as the clock
## passes it: a VISIBLE FORKED BOLT (one mesh, one draw call: a bright jagged stroke from the top of the view to a ground point in it, never on the avatar, with one or two short branches and a
## halo where it lands, alive 0.12 s and fading), the world LIT in two pulses (the grade lifts the scene's own colours by a cold white-blue, `lighting.grade.set_flash`, so that the shapes of
## the night show; a veil adds the glare), and the thunder (1 to 3 s later in a storm by how far it is, 2.5 to 4.5 in steady rain; about one storm bolt in eight is NEAR: a heavy flash and the
## crack within 0.3 s). Now and then a dim DISTANT SHEET flash, no bolt and no sound. "Reduce flashes": no bolt and no lift, only the slow gentle brightening there always was; "Reduce motion":
## about half the strikes and no sheet flashes.
## THE ICONS. A weather icon (scripts/ui/weather_glyph.gd) takes the place of the sun in the clock's temperature row while the sky is overcast or wet, and one sits on the minimap's rim, each
## with a tooltip.
##
## STAGING (a screenshot): `--weather=drizzle|rain|storm|clear` (main.gd: `sim.skies.force`), `--lightning` (a strike held at its brightest, bolt and all, no thunder; `--lightning=near|far|sheet`
## says which, `--lightning-age=S` holds it S seconds into its life instead of at the peak, `--lightning=off` leaves the lightning out), `--norain` (this part left out),
## `--rain-cost` (its CPU time per frame and the frame's draw calls, printed at frame 120).
extends RefCounted

const Access := preload("res://scripts/access.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Foley := preload("res://scripts/audio/foley.gd")
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
## Indoors the rain keeps this share of its streaks (the yard is still in view through the open house: a storm seen from inside is still a storm; the splashes and the sound go as they did).
const INDOOR_RAIN_LEFT := 0.35
## How fast the ground soaks and dries (a share a second) and how fast the light follows the rain.
const WET_UP := 0.11
const WET_DOWN := 0.018
const DIM_RATE := 0.25
const FLASH_COLOR := Color(0.62, 0.74, 1.0)
## The veil's alpha at a strike's brightest (power 1), and the share of it kept when the grade lights the scene itself (the veil is then only the glare).
const VEIL_PEAK := 0.46
const VEIL_WITH_GRADE := 0.5
## How long each kind of strike lives (seconds): a bolt's flash, a sheet flash, the gentle brightening.
const STRIKE_LIFE := 0.9
const SHEET_LIFE := 0.6
const GENTLE_LIFE := 1.4
const BOLT_LIFE := 0.12
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
## The bolt: one mesh (rebuilt for each strike) on the rain's layer, over the veil.
var bolt: MeshInstance2D
var bolt_mesh: ArrayMesh
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
var _hold_kind := ""
var _hold_age := 0.0
var _hold_built := false
var _lightning_off := false
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
## The clock (game hours) the strike schedule was last looked at, the strike being shown (`skies.strikes_between`'s dictionary; empty: none) and its age in seconds, and how bright the scene is lit by it now.
var _clock_prev := -1.0
var _strike := {}
var _strike_age := 99.0
var flash_now := 0.0
var _thunder: Array = []
var _th_shot: AudioStreamPlayer
## The thunders loaded so far (scripts/audio/foley.gd: key -> streams), on the first strike of each kind.
var _thunders := {}
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
		elif a.begins_with("--lightning="):
			var lv := a.trim_prefix("--lightning=")
			if lv == "off":
				_lightning_off = true
			else:
				_hold_flash = true
				_hold_kind = lv
		elif a.begins_with("--lightning-age="):
			_hold_age = maxf(0.0, float(a.trim_prefix("--lightning-age=")))
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
	bolt_mesh = ArrayMesh.new()
	bolt = MeshInstance2D.new()
	bolt.name = "Bolt"
	bolt.mesh = bolt_mesh
	bolt.material = add
	bolt.visible = false
	layer.add_child(bolt)
	_make_splashes(world)
	_make_thunder()
	if not _no_glyph:
		_attach_hud_glyph()
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
	_update_lightning(dt, snapped)
	_update_light(dt)
	_update_sound()
	_glyph_t -= dt
	if _glyph_t <= 0.0:
		_glyph_t = 0.2
		_update_glyphs()


## The rain quad's numbers.
func _update_rain(level: float, calm: bool, me) -> void:
	intensity = pow(level, 0.8) * (1.0 - (1.0 - INDOOR_RAIN_LEFT) * indoor)
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

## The flash's brightness (0 to 1) `age` seconds into a bolt's strike: a bright first pulse, a dip, a weaker second pulse, a fade (it is over by 0.9 s). Two pulses are what the eye reads as lightning.
static func flash_curve(age: float) -> float:
	if age < 0.0:
		return 0.0
	if age < 0.07:
		return lerpf(1.0, 0.85, age / 0.07)
	if age < 0.11:
		return lerpf(0.85, 0.08, (age - 0.07) / 0.04)
	if age < 0.13:
		return lerpf(0.08, 0.62, (age - 0.11) / 0.02)
	if age < 0.18:
		return lerpf(0.62, 0.50, (age - 0.13) / 0.05)
	if age < 0.22:
		return lerpf(0.50, 0.15, (age - 0.18) / 0.04)
	return 0.15 * exp(-(age - 0.22) * 5.0)


## A distant sheet flash: one soft swell and fall over about half a second, with a faint flicker.
static func sheet_curve(age: float) -> float:
	if age < 0.0 or age > SHEET_LIFE:
		return 0.0
	return pow(sin(PI * age / SHEET_LIFE), 2.0) * (0.86 + 0.14 * sin(age * 41.0))


## The bolt's own brightness (0 to 1) at that age: full for 0.04 s, then it fades out by BOLT_LIFE (0.12 s).
static func bolt_alpha(age: float) -> float:
	if age < 0.04:
		return 1.0
	if age < BOLT_LIFE:
		return lerpf(0.85, 0.2, (age - 0.04) / (BOLT_LIFE - 0.04))
	return 0.0


## One frame of the lightning: the strikes the game's clock passed over since the last frame start (the rules' schedule), the strike in hand is lit and drawn by its age, the thunder that follows.
func _update_lightning(dt: float, snapped: bool) -> void:
	var gentle := Access.reduce_flashes()
	if _hold_flash:
		_hold_strike(gentle)
	elif not _lightning_off:
		var h := float(sim.clock_min) / 60.0
		if snapped or _clock_prev < 0.0 or h < _clock_prev or h - _clock_prev > 0.4:
			_clock_prev = h    # (a jump of the clock, a load, a new run: nothing that was passed over is struck now)
		elif h > _clock_prev:
			if not _warming and (skies.kind == "storm" or skies.kind == "steady"):
				var calm := Prefs.on("ui", "reduce_motion")
				for e in skies.strikes_between(_clock_prev, h):
					_start_strike(e, gentle, calm)
			_clock_prev = h
		if not _strike.is_empty():
			_strike_age += dt    # (real time: a flash is a flash at any game speed, and a pause does not freeze it lit)
	# the strike's light, glare and bolt
	var lift := 0.0
	var veil := 0.0
	var bolt_a := 0.0
	if not _strike.is_empty():
		var sheet: bool = _strike.sheet
		var power: float = _strike.power
		var life := GENTLE_LIFE if gentle else (SHEET_LIFE if sheet else STRIKE_LIFE)
		if _strike_age >= life and not _hold_flash:
			_strike = {}
		elif gentle:
			veil = 0.12 * clampf(power / 0.6, 0.45, 1.0) * pow(sin(PI * clampf(_strike_age / GENTLE_LIFE, 0.0, 1.0)), 2.0)
			if _hold_flash:
				veil = 0.16
		else:
			var k := sheet_curve(_strike_age) if sheet else flash_curve(_strike_age)
			lift = power * k
			var graded: bool = lighting != null and lighting.get("grade") != null
			veil = lift * VEIL_PEAK * (VEIL_WITH_GRADE if graded else 1.0)
			if not sheet:
				bolt_a = bolt_alpha(_strike_age)
	var through := 1.0 - 0.45 * indoor    # (under a roof the flash comes through the windows: less of it)
	lift *= through
	veil *= through
	bolt_a *= through
	flash_now = lift
	var on := veil > 0.004
	if flash.visible != on:
		flash.visible = on
	if on:
		flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, veil)
	var bolt_on := bolt_a > 0.01
	if bolt.visible != bolt_on:
		bolt.visible = bolt_on
	if bolt_on:
		bolt.modulate = Color(1.0, 1.0, 1.0, bolt_a)
	if lighting != null and lighting.get("grade") != null:
		lighting.grade.set_flash(lift)
	# the thunder that follows
	var i := _thunder.size() - 1
	while i >= 0:
		_thunder[i].t -= dt
		if _thunder[i].t <= 0.0:
			_boom(float(_thunder[i].far))
			_thunder.remove_at(i)
		i -= 1


## A strike of the schedule begins (or, `strike()`, now): the thunder is queued, the bolt built (a sheet flash has neither: it is too far to hear). Reduce motion leaves about half the bolts and all the
## sheet flashes out; Reduce flashes has no bolt (the gentle brightening takes its place).
func _start_strike(e: Dictionary, gentle: bool, calm: bool) -> void:
	if calm and bool(e.calm):
		return
	_strike = e
	_strike_age = 0.0
	if not bool(e.sheet):
		_thunder.append({"t": float(e.delay), "far": float(e.far)})
		if not gentle:
			_build_bolt(e)
	if _cost:
		print("RAIN lightning (%s%s, power %.2f) at game t %.1f, thunder in %.2f s" % [String(e.kind), " sheet" if bool(e.sheet) else (" NEAR" if bool(e.near) else ""), float(e.power), float(sim.t), float(e.delay)])


## A strike held for a shot (`--lightning`): the same bolt every frame at the age asked for (`--lightning-age=`, the peak by default); no thunder.
func _hold_strike(gentle: bool) -> void:
	if _hold_built or _frames_seen < 40:    # (the view and the avatar are in place by the fortieth frame: the bolt lands where the picture will be)
		return
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	if vp.x < 8.0:
		return
	_hold_built = true
	var steady: bool = skies.kind == "steady"
	var near := _hold_kind == "near" or (_hold_kind == "" and not steady)
	var sheet := _hold_kind == "sheet"
	var power := 1.0 if near else (0.7 if _hold_kind == "far" else (0.35 if steady else 0.7))
	if sheet:
		power = 0.22
	_strike = {"h": 0.0, "sheet": sheet, "near": near, "kind": "steady" if steady else "storm", "power": power, "u": 0.62, "v": 0.5, "seed": 11, "delay": 0.0, "far": 0.0, "calm": false}
	_strike_age = 0.28 if sheet and _hold_age <= 0.0 else _hold_age    # (a sheet flash swells from nothing: its peak is a quarter of a second in)
	if not sheet and not gentle:
		_build_bolt(_strike)


## A strike now (the tests, a hand-made one): with its thunder, near or far.
func strike(near: bool = false) -> void:
	if skies == null:
		return
	var d := _rng.randf_range(0.05, 0.30) if near else _rng.randf_range(1.0, 3.0)
	_start_strike({"h": 0.0, "sheet": false, "near": near, "kind": "storm", "power": 1.0 if near else 0.7, "u": _rng.randf(), "v": _rng.randf(), "seed": _rng.randi() & 0xFFFF,
		"delay": d, "far": clampf((d - 1.0) / 2.0, 0.0, 1.0), "calm": false}, Access.reduce_flashes(), false)


# ---------------------------------------------------------------------------- the bolt --

## A ground point of the view that is not within `min_d` of the avatar (`at`, in the view's pixels): `g` if it is clear, else the nearest place round her that is.
static func _clear_of(g: Vector2, at: Vector2, min_d: float, vp: Vector2) -> Vector2:
	if g.distance_to(at) >= min_d:
		return g
	var lo := Vector2(vp.x * 0.06, vp.y * 0.30)
	var hi := Vector2(vp.x * 0.94, vp.y * 0.88)
	var dir := g - at
	dir = Vector2.RIGHT if dir.length() < 1.0 else dir.normalized()
	for k in 8:
		var cand := at + dir.rotated(float(k) * PI * 0.25) * min_d * 1.15
		cand = Vector2(clampf(cand.x, lo.x, hi.x), clampf(cand.y, lo.y, hi.y))
		if cand.distance_to(at) >= min_d:
			return cand
	return Vector2(clampf(at.x + min_d * 1.2 if at.x < vp.x * 0.5 else at.x - min_d * 1.2, lo.x, hi.x), clampf(vp.y * 0.5, lo.y, hi.y))


## A jagged line from `a` to `b`: the middle of each piece pushed sideways (midpoint displacement), `levels` times, the push growing smaller as the pieces do.
static func _jag(a: Vector2, b: Vector2, rng: RandomNumberGenerator, levels: int, sway: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a, b])
	var amp := a.distance_to(b) * sway
	for l in levels:
		var nxt := PackedVector2Array()
		for i in pts.size() - 1:
			var p := pts[i]
			var q := pts[i + 1]
			var d := q - p
			var n := Vector2(-d.y, d.x).normalized()
			nxt.append(p)
			nxt.append((p + q) * 0.5 + n * rng.randf_range(-1.0, 1.0) * amp)
		nxt.append(pts[pts.size() - 1])
		pts = nxt
		amp *= 0.55
	return pts


## A soft ribbon along `pts`: half-width `hw` (thinning to `tail` of it at the far end), `c0` at its middle and `c1` at its edges, as triangles on the arrays.
static func _ribbon(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, pts: PackedVector2Array, hw: float, tail: float, c0: Color, c1: Color) -> void:
	var n := pts.size()
	var base := verts.size()
	for i in n:
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var w := hw * lerpf(1.0, tail, float(i) / float(maxi(n - 1, 1)))
		verts.append(pts[i] - nrm * w)
		verts.append(pts[i])
		verts.append(pts[i] + nrm * w)
		cols.append(c1)
		cols.append(c0)
		cols.append(c1)
	for i in n - 1:
		var a := base + i * 3
		var b := a + 3
		idx.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b, a + 1, a + 2, b + 1, a + 2, b + 2, b + 1]))


## A soft round (an ellipse, `ry` over `rx`) of light at `at`: a fan from a bright middle out to nothing.
static func _spot(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, at: Vector2, rx: float, ry: float, c0: Color) -> void:
	var base := verts.size()
	verts.append(at)
	cols.append(c0)
	var segs := 18
	var c1 := Color(c0.r, c0.g, c0.b, 0.0)
	for k in segs:
		var an := TAU * float(k) / float(segs)
		verts.append(at + Vector2(cos(an) * rx, sin(an) * ry))
		cols.append(c1)
	for k in segs:
		idx.append_array(PackedInt32Array([base, base + 1 + k, base + 1 + (k + 1) % segs]))


## The bolt of a strike, built once: a main stroke from above the top edge of the view to a ground point in it (never on the avatar), one or two short branches, a bright halo where it lands. Everything
## is one mesh with vertex colours on one additive material (one draw call); `bolt.modulate` fades it. The shape is the strike's own seed's, so a reloaded sky has the same bolts.
func _build_bolt(e: Dictionary) -> void:
	if bolt_mesh == null or main == null:
		return
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	if vp.x < 8.0 or vp.y < 8.0:
		return
	var near: bool = e.near
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e.seed) * 7919 + 13
	var sc := vp.y / 800.0
	var ground := Vector2(vp.x * lerpf(0.08, 0.92, float(e.u)), vp.y * lerpf(0.34, 0.86, float(e.v)))
	var me = sim.avatar.player()
	if me != null:
		ground = _clear_of(ground, main._tile_to_screen(Vector2(me.x, me.y)), 0.24 * vp.y, vp)
	var top := Vector2(clampf(ground.x + (rng.randf() - 0.5) * 0.30 * vp.x, vp.x * 0.02, vp.x * 0.98), -8.0)
	var stroke := _jag(top, ground, rng, 5, 0.12)
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var glow := Color(0.60, 0.76, 1.0, 0.0)
	var core_w := (2.5 if near else 1.7) * sc
	var glow_w := (16.0 if near else 9.0) * sc
	# the branches first (under the main stroke): from a point a third to two thirds of the way down, outwards and down
	var branches := 2 if near else (1 + (1 if rng.randf() < 0.5 else 0))
	var span := top.distance_to(ground)
	for b in branches:
		var k := int(lerpf(0.28, 0.72, rng.randf()) * float(stroke.size() - 1))
		var from := stroke[k]
		var dir := (ground - top).normalized().rotated((0.38 + 0.4 * rng.randf()) * (1.0 if rng.randf() < 0.5 else -1.0))
		var to := from + dir * span * rng.randf_range(0.13, 0.24)
		to.y = minf(to.y, vp.y * 0.96)
		var br := _jag(from, to, rng, 3, 0.16)
		_ribbon(verts, cols, idx, br, glow_w * 0.5, 0.4, Color(0.60, 0.76, 1.0, 0.30), glow)
		_ribbon(verts, cols, idx, br, core_w * 0.55, 0.35, Color(1.0, 1.0, 1.0, 0.95), Color(0.85, 0.92, 1.0, 0.25))
	_ribbon(verts, cols, idx, stroke, glow_w, 0.55, Color(0.60, 0.76, 1.0, 0.34), glow)
	_ribbon(verts, cols, idx, stroke, core_w, 0.6, Color(1.0, 1.0, 1.0, 1.0), Color(0.85, 0.92, 1.0, 0.30))
	# the halo where it lands: a wide soft one (a ground seen from above is an ellipse) and a hot small one
	var rx := (170.0 if near else 95.0) * sc
	_spot(verts, cols, idx, ground, rx, rx * 0.5, Color(0.62, 0.78, 1.0, 0.50))
	_spot(verts, cols, idx, ground, rx * 0.28, rx * 0.15, Color(1.0, 1.0, 1.0, 0.95))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	bolt_mesh.clear_surfaces()
	bolt_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _boom(far: float) -> void:
	# (the SOUND pass: a thunder of its own, near, mid or far by the strike's distance, on the Rain bus, so that a roof muffles it as it does the rain; the far gunshot and the thud below are the fallback when the files are not there)
	var key := Foley.thunder_key(far)
	if not _thunders.has(key):
		_thunders[key] = Foley.load_group(key)
	var list: Array = _thunders[key]
	if not list.is_empty() and _th_shot != null:
		_th_shot.bus = Buses.rain_bus()
		_th_shot.stream = list[_rng.randi() % list.size()]
		_th_shot.pitch_scale = _rng.randf_range(0.96, 1.04)
		_th_shot.volume_db = Foley.thunder_db(far, indoor)
		_th_shot.play()
		if _cost:
			print("RAIN thunder: far %.2f, %s, volume %.1f dB, bus %s" % [far, key, _th_shot.volume_db, _th_shot.bus])
		return
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
