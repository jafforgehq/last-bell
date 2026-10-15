## RAID EXTRAS (prison only): the small raid features that are data first (`raid_extra` in assets/data/prison_raids.json).
##   TIME OF DAY   the destination map's Day or Night: the raid starts at that clock hour (the night grade, the dusk chip and the dead's night wake follow it), the shelves and the dead are scaled.
##   WEATHER       one for each raid, drawn from the run seed by weight (`forecast` is the next raid's, shown on the map before Go): clear, rain (shots and steps carry less far, a darker town, streaks on the
##                 screen) or fog (a code-drawn fog hides all but a few tiles round Ruth, the dead notice her from less far and wake nearer).
##   RETREAT       the V key: every companion runs to the nearest pickup ring and an arrow points Ruth to it (V again cancels).
##   MARKS         a place of the map marked Done or Avoid by the player (saved in the prison save, `raidx`), and the three loadout presets (saved with it). An old save has neither: both start empty.
## Owned by prison_game.gd (`raidx`).
extends RefCounted

const Loot := preload("res://scripts/prison/prison_loot.gd")
const Bal := preload("res://scripts/prison/prison_bal.gd")
const TILE := 64.0

var game
var time := ""    # the map's choice for the next raid ("day", "night"); "" = the clock decides (a staged raid)
var weather := "clear"    # this raid's
var marks := {}    # place id -> "done" | "avoid"
var presets: Array = [{}, {}, {}]    # {main, spare, kit {ammo, meds, food, water}, picked [ids]}
var retreating := false
var hour0 := -1.0    # the clock hour the raid began at when the map chose one (-1: the base clock)
var tod0 := 0.0
var _fog: GradientTexture2D


func _init(g) -> void:
	game = g
	if g.args.has("rtime"):    # staging: --rtime=night starts the first raid at the map's night hour
		time = String(g.args.rtime)


static func cfg() -> Dictionary:
	return Loot.cfg().get("raid_extra", {})


static func time_cfg(id: String) -> Dictionary:
	return (cfg().get("times", {}) as Dictionary).get(id, {})


static func weather_cfg(id: String) -> Dictionary:
	return (cfg().get("weather", {}) as Dictionary).get(id, {})


static func default_time() -> String:
	return String(cfg().get("default_time", "day"))


## The weather of the raid whose town seed is `seed_i`: a weighted draw that depends on the seed alone.
static func weather_for(seed_i: int) -> String:
	var ws: Dictionary = cfg().get("weather", {})
	var total := 0.0
	for k in ws:
		total += float(ws[k].get("w", 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = Loot._h(seed_i, 9173)
	var r := rng.randf() * total
	for k in ws:
		r -= float(ws[k].get("w", 1.0))
		if r <= 0.0:
			return String(k)
	return "clear"


## The weather the NEXT raid will have (the map shows it before Go; `--weather=rain` forces it for a check).
func forecast() -> String:
	if game.args.has("weather") and not weather_cfg(String(game.args.weather)).is_empty():
		return String(game.args.weather)
	return weather_for(Bal.derive(int(game.raids) + 1))


# ------------------------------------------------------------------ time of day --

## The clock hour out on a raid: the map's hour moving on with the base clock, else the base clock.
func hour() -> float:
	if hour0 < 0.0:
		return fposmod(float(game.tod), 24.0)
	return fposmod(hour0 + fposmod(float(game.tod) - tod0, 24.0), 24.0)


func loot_mult() -> float:
	return float(time_cfg(time).get("loot_mult", 1.0))


func dead_mult() -> float:
	return float(time_cfg(time).get("dead_mult", 1.0))


## What a container holds in this raid's time of day: every stack scaled, a share of a unit kept by a seeded chance (a stack that comes to nothing is gone).
func scale_loot(t: Dictionary, seed_i: int) -> void:
	var m := loot_mult()
	if m == 1.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Loot._h(seed_i, 5151)
	for ct in t.containers:
		var lt: Dictionary = ct.loot
		for k in lt.keys():
			var v := float(lt[k]) * m
			var n := int(floor(v)) + (1 if rng.randf() < v - floor(v) else 0)
			if n <= 0:
				lt.erase(k)
			else:
				lt[k] = n


# ------------------------------------------------------------------ a raid begins --

## After the stage is made: the weather's effects on the town's rules and the hour.
func begin(seed_i: int) -> void:
	retreating = false
	weather = forecast() if game.args.has("weather") else weather_for(seed_i)
	var tc := time_cfg(time)
	time = ""    # (used: the next raid asks the map again)
	hour0 = float(tc.hour) if not tc.is_empty() and not game.args.has("hour") else -1.0
	tod0 = float(game.tod)
	var w := weather_cfg(weather)
	var sim = game.run.sim
	if hour0 >= 0.0:
		sim.minutes = hour0 * 60.0
	if sim.field != null:
		sim.field.wake_r = float(sim.field.wake_r) * float(w.get("wake_mult", 1.0))
	sim.notice_r = float(w.get("notice_r", sim.notice_r))
	if game.args.has("log"):
		print("RAIDX time ", time if time != "" else "(clock)", " hour ", snappedf(hour(), 0.1), " weather ", weather)


## How far a noise carries (rain covers it): read by prison_noise.gd.
func noise_mult() -> float:
	return float(weather_cfg(weather).get("noise_mult", 1.0)) if game.mode == "raid" else 1.0


## How much the weather darkens the raid's world (0 to 1).
func dim() -> float:
	return float(weather_cfg(weather).get("dim", 0.0)) if game.mode == "raid" else 0.0


func vision_tiles() -> float:
	return float(weather_cfg(weather).get("vision_tiles", 0.0)) if game.mode == "raid" else 0.0


# ------------------------------------------------------------------ the retreat --

## The nearest pickup ring to a point (tiles), or Vector2.INF when the raid has none.
func nearest_exit(p: Vector2) -> Vector2:
	var best := Vector2.INF
	for e in game.exits:
		var q := Vector2(e)
		if best == Vector2.INF or q.distance_to(p) < best.distance_to(p):
			best = q
	return best


func toggle_retreat() -> void:
	if game.mode != "raid" or game.busy or game.run == null:
		return
	retreating = not retreating
	if retreating:
		game._say("RETREAT! Everybody to the pickup ring (V again: stand down).", 3.5)
		game.squad.retreat_barks()
	else:
		game._say("Stand down. The squad is with you again.", 2.5)


func key(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_V and game.mode == "raid" and not game.busy and not game.loadout.is_open and not game.squad.open:
		toggle_retreat()
		return true
	return false


# ------------------------------------------------------------------ the screen: rain, fog, the retreat's arrow --

func _fog_tex() -> GradientTexture2D:
	if _fog == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 0.82, 1.0])
		g.colors = PackedColorArray([Color(0.72, 0.76, 0.78, 0.0), Color(0.72, 0.76, 0.78, 0.0), Color(0.72, 0.76, 0.78, 0.78), Color(0.72, 0.76, 0.78, 0.94)])
		_fog = GradientTexture2D.new()
		_fog.gradient = g
		_fog.fill = GradientTexture2D.FILL_RADIAL
		_fog.fill_from = Vector2(0.5, 0.5)
		_fog.fill_to = Vector2(1.0, 0.5)
		_fog.width = 256
		_fog.height = 256
	return _fog


## The weather layer over the world (under the HUD): rain streaks, or the fog with the clear patch round Ruth.
func paint_weather(c: CanvasItem, v: Vector2) -> void:
	if game.mode != "raid" or game.run == null or game.busy:
		return
	var t: float = float(game.clock)
	if weather == "rain":
		for i in 150:
			var f := float(i)
			var sp := 0.8 + 0.5 * fposmod(f * 0.37, 1.0)
			var x := fposmod(f * 97.3 + t * 40.0, v.x + 40.0) - 20.0
			var y := fposmod(f * 53.1 + t * 560.0 * sp, v.y + 40.0) - 20.0
			c.draw_line(Vector2(x, y), Vector2(x - 4.0, y + 15.0 * sp), Color(0.78, 0.86, 1.0, 0.3), 1.2)
	var vt := vision_tiles()
	if vt > 0.0:
		var me: Vector2 = (Vector2(game.run.avatar_p.x, game.run.avatar_p.y) - game.cam_center) * game.zoom_px + v / 2.0
		var r: float = vt * game.zoom_px
		var rect := Rect2(me - Vector2(r, r), Vector2(r, r) * 2.0)
		c.draw_texture_rect(_fog_tex(), rect, false)
		var col := Color(0.72, 0.76, 0.78, 0.94)
		c.draw_rect(Rect2(0, 0, v.x, maxf(0.0, rect.position.y)), col)
		c.draw_rect(Rect2(0, rect.end.y, v.x, maxf(0.0, v.y - rect.end.y)), col)
		c.draw_rect(Rect2(0, rect.position.y, maxf(0.0, rect.position.x), rect.size.y), col)
		c.draw_rect(Rect2(rect.end.x, rect.position.y, maxf(0.0, v.x - rect.end.x), rect.size.y), col)
		for i in 9:    # (slow drifting wisps)
			var a := t * 0.05 + float(i) * 0.7
			c.draw_circle(me + Vector2(cos(a * 1.3), sin(a)) * r * (0.55 + 0.4 * fposmod(float(i) * 0.31, 1.0)), r * 0.28, Color(0.8, 0.84, 0.86, 0.1))


## The retreat's arrow, on the HUD (screen px): to the nearest pickup ring, with the distance, always while it is on.
func draw_hud(c: Control, v: Vector2) -> void:
	if not retreating or game.mode != "raid" or game.busy:
		return
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var ex := nearest_exit(me)
	if ex == Vector2.INF:
		return
	var font := ThemeDB.fallback_font
	var d := me.distance_to(ex)
	var dir := (ex - me).normalized() if d > 0.1 else Vector2.DOWN
	var pulse := 0.5 + 0.5 * sin(float(game.clock) * 8.0)
	var col := Color(1.0, 0.55 + 0.25 * pulse, 0.3)
	var at := v / 2.0 + dir * minf(150.0, d * float(game.zoom_px))
	c.draw_colored_polygon(PackedVector2Array([at + dir * 26.0, at + dir.rotated(2.45) * 20.0, at + dir.rotated(-2.45) * 20.0]), col)
	c.draw_string(font, at - Vector2(70, 26) - dir * 6.0, "RETREAT  %d tiles" % int(d), HORIZONTAL_ALIGNMENT_CENTER, 140, 15, col)


# ------------------------------------------------------------------ marks and presets (saved) --

func mark_of(id: String) -> String:
	return String(marks.get(id, ""))


## none -> done -> avoid -> none.
func cycle_mark(id: String) -> String:
	var order := ["", "done", "avoid"]
	var nxt: String = order[(order.find(mark_of(id)) + 1) % order.size()]
	if nxt == "":
		marks.erase(id)
	else:
		marks[id] = nxt
	return nxt


func to_dict() -> Dictionary:
	return {"marks": marks.duplicate(), "presets": presets.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	marks = {}
	var m = d.get("marks", {})
	if typeof(m) == TYPE_DICTIONARY:
		for k in m:
			if ["done", "avoid"].has(String(m[k])):
				marks[String(k)] = String(m[k])
	presets = [{}, {}, {}]
	var p = d.get("presets", [])
	if typeof(p) == TYPE_ARRAY:
		for i in mini(3, (p as Array).size()):
			if typeof(p[i]) == TYPE_DICTIONARY:
				presets[i] = (p[i] as Dictionary).duplicate(true)
