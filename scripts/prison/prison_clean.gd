## EXPERIMENT (prison round 5): the periodic clean-up of a secured prison. A few times a day (never at night or in a siege) four of the crew each get two extra stops (`clean_q`, taken by prison_crew.gd
## `_step_member` the way a meal is) at dirty places: rubbish piles (drawn here, they fade as they are swept), blood stains and dead bodies INSIDE the fence (the sim's blood sprites and dead).
## While a cleaner works at a stop within reach, the stains fade and the bodies are taken away: the sim's own clocks are run fast (a blood sprite's `age`, a dead one's `dead_t`), so nothing is deleted by hand and
## the pawn fades out. The pose is WorkAnim "clean" (a broom swept to and fro, dust) or the existing haul / sort poses. Nothing here changes the stores.
extends RefCounted

const Base := preload("res://scripts/prison/prison_base.gd")
const TILE := preload("res://scripts/game_data.gd").TILE
const TIMES := [9.0, 12.0, 15.0, 17.5]    # a round starts when the clock passes one of these
const REACH := 3.2
const SPEED_UP := 14.0    # the stains and bodies age this much faster under a broom
const RUBBISH := [Vector2(13.5, 46.5), Vector2(22.5, 43.5), Vector2(33.5, 45.5), Vector2(37.5, 38.0), Vector2(22.0, 22.5)]
# TRASH: the crew leaves rubbish at the places where it works, eats and sleeps (a pile = a spot with dirt over PILE). One cleaner keeps a ten-person base tidy; with none the piles grow to a cap of 1.0.
const EXTRA := [Vector2(48.0, 12.5), Vector2(43.5, 16.0), Vector2(13.5, 33.5), Vector2(11.5, 31.5), Vector2(20.0, 34.0), Vector2(33.5, 31.5), Vector2(38.5, 32.0)]
const AREA_ST := {"kitchen": "stove", "dormitory": "bed", "infirmary": "meds", "workshop": "bench1"}
const RATE := {"kitchen": 1.3, "dormitory": 1.3, "workshop": 1.2, "infirmary": 1.1, "yard": 0.5}    # how fast a place gets dirty
const PILE := 0.3
const GROW_S := 1000.0    # seconds for a rate-1 place to go from clean to full
const AFTER_BUMP := 0.12    # a raid or a night leaves this much more
const DRAG := 0.25    # morale lost a day per pile ...
const DRAG_MAX := 2.5    # ... but never more than this
const TIDY := 0.5    # morale gained a day when there is no pile
const LAUNDRY := Base.LAUNDRY
const DUMP := Vector2(23.0, 50.5)

var game
var spots: Array = []    # {at: Vector2, dirt: 0..1, area: String, by_t: when a cleaner took it}
static var pending: Dictionary = {}    # a save's piles, taken by `setup` (the save is read before the base is built)
var _tag := -1
var _qt := 0.0
var _last_tod := -1.0
var rounds := 0
var _stage_t := 0.0
var _staged := false
var _logged := -1


func _init(g) -> void:
	game = g


## Keeps the rubbish spots a person can walk to from the gate, and makes them dirty.
func setup() -> void:
	spots.clear()
	var all: Array = RUBBISH + EXTRA
	for i in all.size():
		var at: Vector2 = all[i]
		if not game.run.sim.path_p.find(game.world.solid_p, Base.SPAWN.x, Base.SPAWN.y, at.x, at.y).is_empty():
			spots.append({"at": at, "dirt": 0.1 + 0.08 * float(i % 5), "area": _area(at), "by_t": -99.0})
	if not pending.is_empty():
		from_dict(pending)
		pending = {}
	_tag = _now_tag()
	if game.args.has("log"):
		print("CLEAN spots ", spots.map(func(s): return "%s@%s" % [s.area, s.at]))
	if game.args.has("cleaner"):    # (a check: `--cleaner=owen` makes that person the cleaner, `--trash=0.9` dirties every spot)
		game.crew.set_role(String(game.args.cleaner), "cleaner", game.econ, false)
	if game.args.has("trash"):
		for s in spots:
			s.dirt = float(game.args.trash)
	_last_tod = game.tod
	if game.args.has("cleannow"):
		_last_tod = -2.0
		for at in [Vector2(34.0, 44.0), Vector2(35.5, 45.0), Vector2(16.0, 42.0)]:    # (a check: blood in the yard for the cleaners to find)
			game.fx.combat.decal(at.x, at.y, 1.2, 0.3, 0.9)


func update(dt: float) -> void:
	var crew = game.crew
	var tag := _now_tag()
	if tag != _tag:    # a raid went out or a night came: more rubbish
		_tag = tag
		for s in spots:
			s.dirt = minf(1.0, float(s.dirt) + AFTER_BUMP * float(RATE[s.area]))
	for s in spots:
		s.dirt = minf(1.0, float(s.dirt) + dt * float(RATE[s.area]) / GROW_S)
	# a siege or the night: whoever was cleaning goes back to the post or the route
	var calm: bool = not game.siege.attacking and game.tod >= 7.0 and game.tod < 19.0
	if not calm:
		for m in crew.members:
			(m as Dictionary).erase("clean_q")
			if m.has("eat") and bool(m.eat.get("clean", false)):
				m.erase("eat")
				m.state = "wait"
				m.p.work = ""
		_last_tod = game.tod
		return
	_dispatch(dt)
	if game.args.has("log") and int(game.clock) % 10 == 0 and int(game.clock) != _logged:    # --log: the trash count every ten game seconds
		_logged = int(game.clock)
		print("TRASH t=", _logged, " tod=", snappedf(game.tod, 0.1), " piles=", piles(), " dirt=", snappedf(spots.reduce(func(a, s): return a + float(s.dirt), 0.0), 0.01), " spots=", spots.size(), " ", game.crew.members.filter(func(m): return _is_cleaner(m)).map(func(m): return "%s %s %s q%d at %s,%s" % [m.def.id, m.state, String(m.eat.say) if m.has("eat") else "-", (m.get("clean_q", []) as Array).size(), snappedf(m.p.x, 0.1), snappedf(m.p.y, 0.1)]))
	if _last_tod == -2.0:    # (--cleannow, a check: two of the dead are brought into the yard and shot, then the round starts)
		_stage_t += dt
		if _stage_t >= 1.0 and not _staged:
			_staged = true
			var n := 0
			for z in game.run.sim.zombies:
				if n < 2 and z.state != "dead" and z.state != "dying":
					z.x = 70.5 + float(n) * 3.0
					z.y = 13.5
					game.run.sim._hurt_zombie(z, 999.0, 0.0, null)
					n += 1
			print("CLEAN staged ", n, " dead of ", game.run.sim.zombies.size())
		if _stage_t > 2.5:
			_start_round()
	else:
		for t in TIMES:
			if _last_tod < t and game.tod >= t and _last_tod >= 0.0:
				_start_round()
	if _last_tod != -2.0 or rounds > 0:
		_last_tod = game.tod
	for m in crew.members:
		if m.state == "work" and m.has("eat") and bool(m.eat.get("clean", false)):
			_work_at(m, dt)
			if game.args.has("log") and String(m.get("clean_seen", "")) != String(m.eat.say):
				m["clean_seen"] = String(m.eat.say)
				print("CLEAN working ", m.def.id, " ", m.eat.say, " at ", snappedf(m.p.x, 0.1), ",", snappedf(m.p.y, 0.1), " t=", snappedf(game.clock, 1.0))


func _start_round() -> void:
	rounds += 1
	var dirty := _targets()
	var plans := {
		"mia": [{"at": game.base.stations.serve, "work": "clean", "say": "sweeping the canteen"}, _pick(dirty, "clean", "mopping up")],
		"nia": [{"at": LAUNDRY, "work": "sort", "face": "N", "say": "washing the laundry"}, _pick(dirty, "clean", "sweeping up")],
		"owen": [_pick(dirty, "haul", "gathering rubbish"), {"at": DUMP, "work": "haul", "face": "S", "say": "carrying rubbish out"}],
		"ike": [_pick(dirty, "clean", "scrubbing the stains"), {"at": game.base.stations.stores_in + Vector2(0.0, 1.0), "work": "sort", "face": "N", "say": "wiping down the stores"}],
	}
	for m in game.crew.members:
		var id := String(m.def.id)
		if not plans.has(id) or m.has("down") or _is_cleaner(m):    # (the cleaner has his own queue of piles from `_dispatch`; a round must not overwrite it)
			continue
		var q: Array = []
		for st in plans[id]:
			var stop: Dictionary = (st as Dictionary).duplicate()
			stop["secs"] = 9.0
			stop["clean"] = true
			if not stop.has("face"):
				stop["face"] = "S"
			q.append(stop)
		m["clean_q"] = q
		if game.args.has("log"):
			print("CLEAN plan ", id, " ", q.map(func(x): return "%s@%s" % [x.say, x.at]))
	if game.args.has("log"):
		print("CLEAN round ", rounds, " at ", snappedf(game.tod, 0.1), " targets ", dirty.size(), " blood decals ", game.fx.combat._decals.size())


## The dirtiest places a cleaner can reach, worst first: bodies and blood inside the fence, then the rubbish piles.
func _targets() -> Array:
	var out: Array = []
	var F := Rect2(Base.FENCE).grow(-1.0)
	for z in game.run.sim.zombies:
		if z.state == "dead" and F.has_point(Vector2(z.x, z.y)):
			out.append({"at": Vector2(z.x, z.y), "w": 3.0})
	for d in game.fx.combat._decals:    # (the sim's blood sprites: in the prison they stay for minutes, until a broom comes)
		var at: Vector2 = d.node.position / TILE
		if F.has_point(at):
			out.append({"at": at, "w": 1.0})
	for s in spots:
		if float(s.dirt) > 0.3:
			out.append({"at": s.at, "w": 2.0 * float(s.dirt)})
	out.sort_custom(func(a, b): return float(a.w) > float(b.w))
	return out


## The next target (not one a stop already has), as a stop; a fixed place when nothing is dirty.
var _used: Array = []
func _pick(dirty: Array, work: String, say: String) -> Dictionary:
	for d in dirty:
		var at: Vector2 = d.at
		var taken := false
		for u in _used:
			if (u as Vector2).distance_to(at) < 6.0:
				taken = true
		if taken or game.run.sim.path_p.find(game.world.solid_p, game.run.avatar_p.x, game.run.avatar_p.y, at.x, at.y).is_empty():
			continue
		_used.append(at)
		if _used.size() > 6:
			_used.pop_front()
		return {"at": at, "work": work, "say": say}
	var fallback: Vector2 = [Vector2(34.0, 44.0), Vector2(20.0, 42.0), Vector2(30.0, 38.0)][rounds % 3]
	return {"at": fallback, "work": work, "say": say}


## A cleaner at work: stains and bodies in reach age fast and fade away, the rubbish pile shrinks.
func _work_at(m: Dictionary, dt: float) -> void:
	var c := Vector2(m.p.x, m.p.y)
	for d in game.fx.combat._decals:
		if (d.node.position / TILE).distance_to(c) < REACH:
			d.age = maxf(float(d.age), game.fx.combat.decal_hold) + dt * (game.fx.combat.decal_life - game.fx.combat.decal_hold) / 4.0    # (gone in about 4 s of sweeping)
	for z in game.run.sim.zombies:
		if z.state == "dead" and Vector2(z.x, z.y).distance_to(c) < REACH:
			z.dead_t = float(z.dead_t) + dt * SPEED_UP
			if game.args.has("log") and not z.has_meta("logged"):
				z.set_meta("logged", true)
				print("CLEAN body being cleared by ", m.def.name)
	if _is_cleaner(m):    # (only the cleaner takes the rubbish away; the others' stops tidy the stains)
		for s in spots:
			if (s.at as Vector2).distance_to(c) < REACH:
				s.dirt = maxf(0.0, float(s.dirt) - dt / 5.0)


## Drawn in the world overlay: the rubbish piles and a bucket by anyone with a broom or a mop in hand.
func paint(c: CanvasItem) -> void:
	var out := Color(0.12, 0.1, 0.09)
	for s in spots:
		var d := float(s.dirt)
		if d < 0.05:
			continue
		var p: Vector2 = s.at * TILE
		for k in int(ceil(d * 6.0)):
			var q := p + Vector2(sin(float(k) * 2.3 + p.x) * 12.0, cos(float(k) * 1.7 + p.y) * 7.0) * (0.4 + d) * 2.2
			c.draw_set_transform(q, 0.0, Vector2(2.2, 2.2))    # (the tile is 64 px)
			q = Vector2.ZERO
			match k % 4:
				0:    # a wrapper
					c.draw_rect(Rect2(q - Vector2(4, 2), Vector2(8, 5)), Color(0.88, 0.84, 0.7))
					c.draw_rect(Rect2(q - Vector2(4, 2), Vector2(8, 5)), out, false, 1.0)
					c.draw_line(q - Vector2(2, 0), q + Vector2(2, 1), Color(0.8, 0.3, 0.25), 1.0)
				1:    # a can
					c.draw_rect(Rect2(q - Vector2(2, 3), Vector2(5, 7)), Color(0.55, 0.58, 0.62))
					c.draw_rect(Rect2(q - Vector2(2, 3), Vector2(5, 2)), Color(0.82, 0.85, 0.88))
					c.draw_rect(Rect2(q - Vector2(2, 3), Vector2(5, 7)), out, false, 1.0)
				2:    # a rag
					c.draw_colored_polygon(PackedVector2Array([q + Vector2(-5, 2), q + Vector2(-1, -3), q + Vector2(5, -1), q + Vector2(3, 3)]), Color(0.52, 0.4, 0.3))
					c.draw_polyline(PackedVector2Array([q + Vector2(-5, 2), q + Vector2(-1, -3), q + Vector2(5, -1), q + Vector2(3, 3), q + Vector2(-5, 2)]), out, 1.0)
				_:    # a scrap of metal
					c.draw_colored_polygon(PackedVector2Array([q + Vector2(-3, 3), q + Vector2(-2, -3), q + Vector2(4, -1), q + Vector2(3, 3)]), Color(0.42, 0.36, 0.34))
					c.draw_polyline(PackedVector2Array([q + Vector2(-3, 3), q + Vector2(-2, -3), q + Vector2(4, -1), q + Vector2(3, 3), q + Vector2(-3, 3)]), out, 1.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for m in game.crew.members:
		if m.state == "work" and m.has("eat") and bool(m.eat.get("clean", false)) and String(m.eat.work) == "clean":
			var b := _bucket_at(Vector2(m.p.x, m.p.y)) * TILE
			c.draw_rect(Rect2(b - Vector2(6, 9), Vector2(12, 10)), Color(0.35, 0.4, 0.5))
			c.draw_rect(Rect2(b - Vector2(6, 9), Vector2(12, 3)), Color(0.45, 0.65, 0.85))


## The bucket stands on the first free tile beside the cleaner (not under a counter or a wall).
func _bucket_at(c: Vector2) -> Vector2:
	var w = game.world
	for o in [Vector2(0.8, 0.35), Vector2(-0.8, 0.35), Vector2(0.0, 0.95), Vector2(0.8, -0.5), Vector2(-0.8, -0.5)]:
		var t: Vector2 = c + o
		var i := int(t.y) * int(w.W) + int(t.x)
		if i >= 0 and i < w.solid_p.size() and w.solid_p[i] == 0:
			return t
	return c + Vector2(0.0, 0.95)


# ------------------------------------------------------------------ trash ------

func _now_tag() -> int:
	return int(game.raids) * 1000 + int(game.siege.nights_started)


## The place a spot belongs to: the nearest of kitchen, dormitory, infirmary, workshop within 9 tiles, else the yard.
func _area(at: Vector2) -> String:
	var best := "yard"
	var bd := 9.0
	for a in AREA_ST:
		var d := at.distance_to(game.base.stations[AREA_ST[a]])
		if d < bd:
			bd = d
			best = a
	return best


func _is_cleaner(m: Dictionary) -> bool:
	return String(game.econ.cfg.crew_role.get(String(m.def.id), "")) == "cleaner" and not m.def.has("stand") and not m.def.has("ally")


## Piles now (a place's, or all); the cleaner and the hints read this.
func piles(area := "") -> int:
	var n := 0
	for s in spots:
		if float(s.dirt) > PILE and (area == "" or String(s.area) == area):
			n += 1
	return n


## A free cleaner takes the three nearest piles nobody else is going to (a short stop at each, the "clean" work pose).
func _dispatch(dt: float) -> void:
	_qt += dt
	if _qt < 2.0:
		return
	_qt = 0.0
	for m in game.crew.members:
		if not _is_cleaner(m) or m.has("down") or m.has("eat") or not (m.get("clean_q", []) as Array).is_empty() or m.def.has("play"):
			continue
		var from := Vector2(m.p.x, m.p.y)
		var free: Array = spots.filter(func(s): return float(s.dirt) > PILE and game.clock - float(s.by_t) > 25.0)
		free.sort_custom(func(a, b): return (a.at as Vector2).distance_to(from) < (b.at as Vector2).distance_to(from))
		var q: Array = []
		for s in free.slice(0, 3):
			s.by_t = game.clock
			q.append({"at": s.at, "secs": 6.0, "work": "clean", "face": "S", "say": "clearing the %s" % ("rubbish" if s.area == "yard" else "%s rubbish" % s.area), "clean": true})
		if not q.is_empty():
			m["clean_q"] = q


## Ruth's E: the nearest pile within reach is cleared at once.
func prompt(me: Vector2) -> Dictionary:
	for s in spots:
		if float(s.dirt) > PILE and (s.at as Vector2).distance_to(me) < 2.2:
			return {"kind": "trash", "label": "E: clear the trash"}
	return {}


func sweep(me: Vector2) -> String:
	for s in spots:
		if float(s.dirt) > PILE and (s.at as Vector2).distance_to(me) < 2.2:
			s.dirt = 0.0
			return "Cleared a pile of trash."
	return ""


## Per day, from the economy: untidy costs a little morale, a tidy base a little gain.
func morale_delta() -> float:
	var n := piles()
	return TIDY if n == 0 else -minf(DRAG_MAX, DRAG * float(n))


## Rubbish at the kitchen spoils the food faster (x1.0 to x1.4).
func spoil_mult() -> float:
	return 1.0 + minf(0.4, 0.15 * float(piles("kitchen")))


## Once a day: a dirty dormitory or infirmary can make one person ill (the arc's `hurt`, one day off work).
func daily() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9173 + int(game.econ.day) * 31
	for s in spots:
		if (s.area == "dormitory" or s.area == "infirmary") and float(s.dirt) > 0.5 and rng.randf() < 0.05:
			var ok: Array = game.crew.members.filter(func(m): return not m.def.has("ally") and not m.def.has("play") and not game.arc.hurt_now(String(m.def.name)))
			if not ok.is_empty():
				var nm := String((ok[rng.randi() % ok.size()] as Dictionary).def.name)
				game.arc.hurt[nm] = game.arc.day
				game._say("%s is ill. The %s is dirty." % [nm, s.area], 4.0)
			return


## "Trash: 3 piles (kitchen 2, dormitory 1)", "" when none.
func report() -> String:
	var parts: Array = []
	for a in RATE:
		if piles(a) > 0:
			parts.append("%s %d" % [a, piles(a)])
	return "" if parts.is_empty() else "Trash: %d piles (%s)" % [piles(), ", ".join(parts)]


## The minimap: a brown dot for every pile.
func mini(c: CanvasItem, o: Vector2, sc: float) -> void:
	for s in spots:
		if float(s.dirt) > PILE:
			c.draw_rect(Rect2(o + (s.at as Vector2) * sc - Vector2(1.2, 1.2), Vector2(2.4, 2.4)), Color(0.75, 0.55, 0.3))


func to_dict() -> Dictionary:
	return {"spots": spots.map(func(s): return {"x": s.at.x, "y": s.at.y, "dirt": s.dirt}), "tag": _tag}


## Puts saved dirt back on the spots with the same place (the spots themselves come from the map).
func from_dict(d: Dictionary) -> void:
	for e in (d.get("spots", []) as Array):
		var at := Vector2(float(e.x), float(e.y))
		for s in spots:
			if (s.at as Vector2).distance_to(at) < 0.1:
				s.dirt = clampf(float(e.dirt), 0.0, 1.0)
