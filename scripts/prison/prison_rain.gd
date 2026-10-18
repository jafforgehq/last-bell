## RAIN (prison only): the rain you see on the base and on a raid, drawn on the game's weather layer (`wx`, CanvasLayer 5 over the night tint and the lamps' glow). It is a look, not a rule: the
## only rules weather has are the old ones (the calendar's rain fills the barrels, a raid's rain covers noise a little, prison_raidx.gd and prison_arc.gd), and nothing here changes them.
##
## HOW OFTEN. The base: the calendar's rain days (assets/data/prison_story.json `weather`: days 3, 9, 13, 20 and 27, a storm on day 24, and an event card can add one) rain all day at a
## level that swells and eases with the hour; a storm day is a full storm. A raid: the raid's own weather (prison_raidx.gd, a weighted draw: rain about one raid in four). The rain sound
## (prison_audio.gd) follows `target()`, so what you hear is what you see.
## THE LOOK. Two layers of streaks slanted by the wind (a far layer, thin, short, slow and faint; a near one, longer and brighter), both lit like the world (dark blue at night); rings that
## open on the outdoor ground round the view (never on a floor under a roof); a faint grey veil that flattens the colours; a cooler, darker grade (`grade`); the ground gets wet and the lamps
## show a sheen and a halo (`wet` and `haze`, read by prison_lamps.gd). Under a roof on a raid the streaks thin to a third.
## STORMS. In a storm (level 0.95 and up) a strike every 9 to 25 seconds: two quick pulses of light (rain_view.gd's `flash_curve`) that lift the night grade and a pale veil, then the thunder,
## 1 to 3 s later (the synthesized thunders of scripts/audio/foley.gd, on the Rain bus).
## STAGING: `--baserain=0..1` rains on the base at that level (1 is a storm), `--rainflash` holds a strike at its peak for a screenshot.
extends RefCounted

const TownGen := preload("res://scripts/town/town_gen.gd")
const RainView := preload("res://scripts/render/rain_view.gd")
const Foley := preload("res://scripts/audio/foley.gd")
const Buses := preload("res://scripts/audio/buses.gd")

const TILE := 64.0
const RIP_MAX := 40
const RIP_LIFE := 0.6
## The terrain ids of open ground (scripts/prison/prison_base.gd T_*): asphalt, sidewalk, yard, grass, soil, concrete, dirt. A ring never opens on any other.
const OUTDOOR := {1: true, 2: true, 3: true, 4: true, 5: true, 12: true, 13: true}
const STORM := 0.95

var game
var level := 0.0    # the rain drawn now (0 to 1), eased toward `target()`
var wet := 0.0    # how wet the ground is (soaks in about ten seconds, dries over about a minute and a half)
var flash := 0.0    # a strike's light now (0 to 1)
var indoor := 0.0
var _clock := -1.0
var _rip: Array = []    # [pos (tiles), age 0..1, size (tiles)]
var _acc := 0.0
var _rng := RandomNumberGenerator.new()
var _next_strike := 6.0
var _strike_age := 99.0
var _strike_pow := 0.0
var _thunder_in := -1.0
var _thunder_far := 0.5
var _player: AudioStreamPlayer
var _thunders := {}


func _init(g) -> void:
	game = g
	_rng.seed = 7741


## How hard it should rain now (0 to 1).
func target() -> float:
	if game.args.has("norain"):
		return 0.0
	if game.mode == "raid":
		return 0.7 if game.raidx != null and String(game.raidx.weather) == "rain" else 0.0
	if game.args.has("baserain"):
		return clampf(float(game.args.baserain), 0.0, 1.0)
	if game.arc == null or not game.arc.active():
		return 0.0
	var k := String(game.arc.weather_now().get("kind", "clear"))
	if k == "storm":
		return 1.0
	if k == "rain":
		return 0.42 + 0.3 * (0.5 + 0.5 * sin(float(game.tod) * 0.9 + float(game.arc.day)))
	return 0.0


## The rain's share of the world's tint: a little darker and cooler, and lifted toward a cold white by a strike.
func grade(c: Color) -> Color:
	var cool := Color(1, 1, 1).lerp(Color(0.86, 0.9, 0.97), level)
	var out := Color(c.r * cool.r, c.g * cool.g, c.b * cool.b, c.a)
	if flash > 0.0:
		out = out.lerp(Color(0.92, 0.96, 1.0, c.a), flash * 0.75)
	return out


## How much the air shows a lamp's halo (rain or fog), 0 to 1.
func haze() -> float:
	var f := 0.6 if game.mode == "raid" and game.raidx != null and String(game.raidx.weather) == "fog" else 0.0
	return maxf(level, f)


func update(dt: float) -> void:
	var to := target()
	if _clock < 0.0:
		level = to
		wet = clampf(to * 1.6, 0.0, 1.0)
	_clock = float(game.clock)
	level = move_toward(level, to, 0.08 * dt)
	var wt := clampf(level * 1.6, 0.0, 1.0)
	wet = move_toward(wet, wt, (0.1 if wt > wet else 0.012) * dt)
	var inside := false
	if game.mode == "raid" and game.run != null and not game.town.is_empty():
		inside = TownGen.house_at(game.town, float(game.run.avatar_p.x), float(game.run.avatar_p.y)) >= 0
	indoor = move_toward(indoor, 1.0 if inside else 0.0, 2.0 * dt)
	_ripples(dt)
	_storm(dt)


# ------------------------------------------------------------------ the rings on the ground --

func _view_tiles() -> Rect2:
	var v: Vector2 = game._vp()
	var inv: Transform2D = game.world.get_global_transform_with_canvas().affine_inverse()
	var a: Vector2 = inv * Vector2.ZERO / TILE
	var b: Vector2 = inv * v / TILE
	return Rect2(a, b - a)


func _ripples(dt: float) -> void:
	var i := _rip.size() - 1
	while i >= 0:
		_rip[i][1] += dt / RIP_LIFE
		if float(_rip[i][1]) >= 1.0:
			_rip.remove_at(i)
		i -= 1
	if level < 0.12 or game.world == null or game.busy:
		_acc = 0.0
		return
	var w = game.world
	var view := _view_tiles()
	_acc += dt * lerpf(10.0, 70.0, level) * (1.0 - indoor)
	while _acc >= 1.0:
		_acc -= 1.0
		if _rip.size() >= RIP_MAX:
			continue
		var p := view.position + Vector2(_rng.randf(), _rng.randf()) * view.size
		var tx := int(p.x)
		var ty := int(p.y)
		if tx < 0 or ty < 0 or tx >= int(w.W) or ty >= int(w.H):
			continue
		var ix := ty * int(w.W) + tx
		if not OUTDOOR.has(int(w.terrain[ix])) or int(w.solid_p[ix]) != 0:
			continue
		_rip.append([p, 0.0, _rng.randf_range(0.18, 0.34)])


# ------------------------------------------------------------------ storms --

func _storm(dt: float) -> void:
	if game.args.has("rainflash"):
		flash = 0.8
		return
	if level >= STORM and not game.busy:
		_next_strike -= dt
		if _next_strike <= 0.0:
			_next_strike = _rng.randf_range(9.0, 25.0)
			_strike_age = 0.0
			_strike_pow = _rng.randf_range(0.45, 0.9)
			var d := _rng.randf_range(1.0, 3.0)
			_thunder_in = d
			_thunder_far = clampf((d - 1.0) / 2.0, 0.0, 1.0)
	_strike_age += dt
	flash = _strike_pow * RainView.flash_curve(_strike_age) if _strike_age < 0.9 else 0.0
	if _thunder_in >= 0.0:
		_thunder_in -= dt
		if _thunder_in < 0.0:
			_boom()


func _boom() -> void:
	var key := Foley.thunder_key(_thunder_far)
	if not _thunders.has(key):
		_thunders[key] = Foley.load_group(key)
	var list: Array = _thunders[key]
	if list.is_empty():
		return
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.bus = Buses.rain_bus()
		game.add_child(_player)
	_player.stream = list[_rng.randi() % list.size()]
	_player.pitch_scale = _rng.randf_range(0.95, 1.05)
	_player.volume_db = Foley.thunder_db(_thunder_far, indoor)
	_player.play()
	if game.args.has("log"):
		print("RAIN thunder ", key, " ", snappedf(_player.volume_db, 0.1), " dB")


# ------------------------------------------------------------------ drawing --

## The weather layer's rain (screen px): the veil, the rings, the two layers of streaks, a strike's glare.
func paint(c: CanvasItem, v: Vector2) -> void:
	if game.busy or (level < 0.01 and flash <= 0.0):
		return
	var lit: Color = game.night_rect.color    # (the layer is over the night tint: the rain is lit like the world)
	lit = Color(maxf(lit.r, 0.5), maxf(lit.g, 0.55), maxf(lit.b, 0.7), 1.0)
	var t := float(game.clock)
	var k := level * (1.0 - 0.65 * indoor)
	c.draw_rect(Rect2(Vector2.ZERO, v), Color(0.55, 0.6, 0.68, 0.08 * k) * lit)    # the veil: the colours a little flatter, the distance a little greyer
	if not _rip.is_empty():
		var xf: Transform2D = game.world.get_global_transform_with_canvas()
		var sc := xf.get_scale().x * TILE
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for r in _rip:
			var at: Vector2 = xf * (Vector2(r[0]) * TILE)
			var age: float = r[1]
			var rx: float = float(r[2]) * sc * (0.25 + 0.75 * sqrt(age))
			var col := Color(0.85, 0.9, 1.0, 0.8 * (1.0 - age)) * lit
			for s in 10:
				var a0 := TAU * float(s) / 10.0
				var a1 := TAU * float(s + 1) / 10.0
				pts.append(at + Vector2(cos(a0), sin(a0) * 0.5) * rx)
				pts.append(at + Vector2(cos(a1), sin(a1) * 0.5) * rx)
				cols.append(col)
		c.draw_multiline_colors(pts, cols, 1.5)
	var wind := 0.22 + 0.08 * sin(t * 0.4)    # the slant: x per unit of fall
	var u := v.y / 800.0    # (a big window: longer, faster, wider streaks, the same look)
	_streaks(c, v, t, int(260.0 * k), 380.0 * u, 12.0 * u, wind, Color(0.72, 0.8, 0.95, 0.3) * lit, maxf(1.0, u), 17)
	_streaks(c, v, t, int(90.0 * k), 720.0 * u, 28.0 * u, wind * 1.15, Color(0.82, 0.88, 1.0, 0.5) * lit, 1.8 * u, 53)
	if flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, v), Color(0.75, 0.82, 1.0, 0.22 * flash))


static func _streaks(c: CanvasItem, v: Vector2, t: float, n: int, speed: float, length: float, wind: float, col: Color, width: float, salt: int) -> void:
	if n <= 0:
		return
	var pts := PackedVector2Array()
	pts.resize(n * 2)
	var span := Vector2(v.x + 80.0, v.y + 60.0)
	for i in n:
		var f := float(i + salt)
		var sp := 0.8 + 0.4 * fposmod(f * 0.618, 1.0)
		var fall := t * speed * sp
		var x := fposmod(f * 97.31 + fall * wind, span.x) - 40.0
		var y := fposmod(f * 53.17 + fall, span.y) - 30.0
		var l := length * sp
		pts[i * 2] = Vector2(x, y)
		pts[i * 2 + 1] = Vector2(x - wind * l, y - l)
	c.draw_multiline(pts, col, width)
