## BARRICADES (steam audit M16): cheap defences in front of one fence segment, bought on the board's Defence tab (the `barricades` list of assets/data/prison_projects.json). Each wears out: durability goes
## down as it works (a sandbag line takes damage off the fence, the dead tearing at it, a spike strip hurting them, a tripwire going off) and a little every night, and it is lost at once when its segment
## is overrun. So they must be bought again. Drawn in code at the segment. The siege (prison_siege.gd) calls `damage_mult`, `absorb`, `work`, `on_breach`, `night_wear`, `paint`.
extends RefCounted

const NoiseMod := preload("res://scripts/prison/prison_noise.gd")
const PATH := "res://assets/data/prison_projects.json"
static var defs := {}
static var order: Array = []

var game
var bars := {}    # segment name -> {id, dur, max, trip_t}


static func load_defs() -> void:
	if not defs.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for b in (parsed.get("barricades", []) if parsed is Dictionary else []):
		defs[String(b.id)] = b
		order.append(String(b.id))


func _init(g) -> void:
	game = g
	load_defs()


func of(s: Dictionary) -> Dictionary:
	return bars.get(String(s.name), {})


func cost_text(id: String) -> String:
	var parts: Array = []
	for k in defs[id].cost:
		parts.append("%d %s" % [int(defs[id].cost[k]), k])
	return ", ".join(parts)


## {ok, why}
func can_build(s: Dictionary, id: String) -> Dictionary:
	if not defs.has(id):
		return {"ok": false, "why": "No such barricade."}
	if game.siege.attacking:
		return {"ok": false, "why": "Not during an attack."}
	if float(s.hp) <= 0.0:
		return {"ok": false, "why": "The fence there is down."}
	if not of(s).is_empty():
		return {"ok": false, "why": "Something stands there already."}
	for k in defs[id].cost:
		if float(game.stores.get(k, 0.0)) < float(defs[id].cost[k]):
			return {"ok": false, "why": "Short of %s." % k}
	return {"ok": true, "why": ""}


func build(s: Dictionary, id: String, free := false) -> Dictionary:
	var c := {"ok": true, "why": ""} if free else can_build(s, id)
	if not bool(c.ok):
		return c
	if not free:
		for k in defs[id].cost:
			game.stores[k] = float(game.stores[k]) - float(defs[id].cost[k])
	bars[String(s.name)] = {"id": id, "dur": float(defs[id].dur), "max": float(defs[id].dur), "trip_t": 0.0}
	return c


func _lose(s: Dictionary, amount: float) -> void:
	var b: Dictionary = bars.get(String(s.name), {})
	if b.is_empty():
		return
	b.dur = float(b.dur) - amount
	if float(b.dur) <= 0.0:
		bars.erase(String(s.name))
		game._say("The %s at the %s is gone." % [String(defs[b.id].name).to_lower(), String(s.name)], 4.0)
		if game.sound != null:
			game.sound.play("crash", 0.4)


## The share of damage that still reaches the fence (1 with no barricade).
func damage_mult(s: Dictionary) -> float:
	var b := of(s)
	return 1.0 if b.is_empty() else 1.0 - float(defs[b.id].shield)


## Damage on the fence was cut by the shield: the barricade pays for the part it took.
func absorb(s: Dictionary, raw: float) -> void:
	var b := of(s)
	if not b.is_empty():
		_lose(s, raw * float(defs[b.id].shield))


## Every frame in an attack: the dead of the wave at a barricaded segment are slowed, hurt by spikes, and set the tripwire off.
func work(dt: float) -> void:
	if bars.is_empty():
		return
	for s in game.siege.segs:
		var b := of(s)
		if not b.is_empty():
			b.trip_t = maxf(0.0, float(b.trip_t) - dt)
	for w in game.siege.wave:
		var z = w.z
		var s: Dictionary = w.seg
		var b := of(s)
		if not w.has("speed0"):
			w["speed0"] = float(z.speed)
		if b.is_empty():
			z.speed = float(w.speed0)
			continue
		var d: Dictionary = defs[b.id]
		var dist := Vector2(z.x, z.y).distance_to(w.spot)
		z.speed = float(w.speed0) * (float(d.slow) if dist < 4.0 else 1.0)
		if dist >= 2.5 or not game.siege._alive(z):
			continue
		_lose(s, float(d.wear_dps) * dt)
		if of(s).is_empty():
			continue
		if float(d.get("stun", 0.0)) > 0.0 and not w.has("tripped"):
			w["tripped"] = true    # each of the dead trips on it once: down for a moment
			z.stagger = maxf(float(z.stagger), float(d.stun))
		if float(d.get("spike", 0.0)) > 0.0:
			w["spk"] = float(w.get("spk", 0.0)) + float(d.spike) * dt
			if float(w.spk) >= 1.0:
				w.spk = float(w.spk) - 1.0
				game.run.sim._hurt_zombie(z, 1.0, (-Vector2(s.out)).angle())
		if d.has("noise") and float(b.trip_t) <= 0.0:
			b.trip_t = float(d.noise.every)
			var called: int = NoiseMod.emit(w.spot, float(d.noise.loud), String(d.noise.kind), w.spot)
			if game.args.has("log"):
				print("TRIPWIRE ", s.name, " called ", called)
			_lose(s, float(d.noise.cost))


## A segment fell: what stood in front of it is lost.
func on_breach(s: Dictionary) -> void:
	bars.erase(String(s.name))


## Dawn: every barricade is a little worse.
func night_wear() -> void:
	for s in game.siege.segs:
		var b := of(s)
		if not b.is_empty():
			_lose(s, float(b.max) * float(defs[b.id].wear_night))


func summary() -> String:
	var parts: Array = []
	for s in game.siege.segs:
		var b := of(s)
		if not b.is_empty():
			parts.append("%s %d%%" % [String(defs[b.id].name), int(100.0 * float(b.dur) / float(b.max))])
	return ", ".join(parts)


func to_dict() -> Dictionary:
	var out := {}
	for k in bars:
		out[k] = {"id": bars[k].id, "dur": float(bars[k].dur)}
	return out


func from_dict(d: Dictionary) -> void:
	load_defs()
	bars.clear()
	for k in d:
		var id := String(d[k].get("id", ""))
		if defs.has(id):
			bars[String(k)] = {"id": id, "dur": float(d[k].dur), "max": float(defs[id].dur), "trip_t": 0.0}


# ------------------------------------------------------------------------------ draw --

## In the game's overlay (world pixels): a row along the segment, just outside the wire.
func paint(c: CanvasItem) -> void:
	var T: float = float(game.TILE)
	for s in game.siege.segs:
		var b := of(s)
		if b.is_empty():
			continue
		var al: Vector2 = s.along
		var out: Vector2 = s.out
		var ctr: Vector2 = Vector2(s.center) + out * 0.9
		var f := float(b.dur) / float(b.max)
		var half := 2.6
		match String(b.id):
			"sandbag":
				for k in 6:
					var at: Vector2 = (ctr + al * (float(k) - 2.5) * 0.9) * T
					var tilt := 0.5 if k % 2 == 0 else -0.5
					for row in 2:
						var o := at + out * (float(row) * 0.3 * T) + Vector2(0, -float(row) * 3.0)
						c.draw_rect(Rect2(o + Vector2(-17, -9 + tilt), Vector2(34, 18)), Color(0.58, 0.5, 0.34).darkened(0.25 * (1.0 - f)))
						c.draw_rect(Rect2(o + Vector2(-17, -9 + tilt), Vector2(34, 18)), Color(0.2, 0.15, 0.09), false, 2.0)
						c.draw_line(o + Vector2(-8, 0), o + Vector2(8, 0), Color(0.34, 0.28, 0.18), 1.5)
			"spikes":
				for k in 9:
					var at2: Vector2 = (ctr + al * (float(k) - 4.0) * 0.6) * T
					var tip := out * 16.0
					var perp := al * 9.0
					c.draw_colored_polygon(PackedVector2Array([at2 - perp, at2 + perp, at2 + tip]), Color(0.46, 0.46, 0.5).darkened(0.3 * (1.0 - f)))
					c.draw_polyline(PackedVector2Array([at2 - perp, at2 + tip, at2 + perp]), Color(0.1, 0.1, 0.12), 2.0)
				c.draw_line((ctr - al * 2.6) * T, (ctr + al * 2.6) * T, Color(0.25, 0.2, 0.15), 4.0)
			"tripwire":
				var a: Vector2 = (ctr - al * half) * T
				var e: Vector2 = (ctr + al * half) * T
				var armed := float(b.trip_t) <= 0.0
				for post in [a, e]:
					c.draw_line(post, post - out * 22.0, Color(0.25, 0.18, 0.1), 5.0)
				c.draw_line(a - out * 20.0, e - out * 20.0, Color(0.85, 0.8, 0.6, 0.9 if armed else 0.35), 1.5)
				for k in 5:
					var at3: Vector2 = a.lerp(e, (float(k) + 0.5) / 5.0) - out * 20.0
					c.draw_line(at3, at3 + out * 10.0, Color(0.6, 0.6, 0.55), 1.0)
					c.draw_rect(Rect2(at3 + out * 10.0 - Vector2(4, 4), Vector2(8, 8)), Color(0.6, 0.62, 0.66))
					c.draw_rect(Rect2(at3 + out * 10.0 - Vector2(4, 4), Vector2(8, 8)), Color(0.1, 0.1, 0.12), false, 1.5)
		if f < 0.999:
			var bc: Vector2 = (ctr + out * 0.8) * T
			c.draw_rect(Rect2(bc - Vector2(24, 3), Vector2(48, 6)), Color(0, 0, 0, 0.7))
			c.draw_rect(Rect2(bc - Vector2(24, 3), Vector2(48.0 * f, 6)), Color(0.9, 0.7, 0.3))
