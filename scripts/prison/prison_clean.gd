## EXPERIMENT (prison round 5): the periodic clean-up of a secured prison. A few times a day (never at night or in a siege) four of the crew each get two extra stops (`clean_q`, taken by prison_crew.gd
## `_step_member` the way a meal is) at dirty places: rubbish piles (drawn here, they fade as they are swept), blood stains and dead bodies INSIDE the fence (the sim's blood sprites and dead).
## While a cleaner works at a stop within reach, the stains fade and the bodies are taken away: the sim's own clocks are run fast (a blood sprite's `age`, a dead one's `dead_t`), so nothing is deleted by hand and
## the pawn fades out. The pose is WorkAnim "clean" (a broom swept to and fro, dust) or the existing haul / sort poses. Nothing here changes the stores.
extends RefCounted

const Base := preload("res://scripts/prison/prison_base.gd")
const TILE := 32.0
const TIMES := [9.0, 12.0, 15.0, 17.5]    # a round starts when the clock passes one of these
const REACH := 3.2
const SPEED_UP := 14.0    # the stains and bodies age this much faster under a broom
const RUBBISH := [Vector2(20.5, 47.5), Vector2(30.5, 45.5), Vector2(58.5, 46.5), Vector2(66.5, 41.5), Vector2(36.5, 38.5), Vector2(44.5, 44.5), Vector2(52.5, 28.5)]
const LAUNDRY := Vector2(18.5, 47.5)
const DUMP := Vector2(48.0, 50.5)

var game
var spots: Array = []    # {at: Vector2, dirt: 0..1}
var _last_tod := -1.0
var rounds := 0
var _stage_t := 0.0
var _staged := false


func _init(g) -> void:
	game = g


## Keeps the rubbish spots a person can walk to from the gate, and makes them dirty.
func setup() -> void:
	spots.clear()
	for i in RUBBISH.size():
		var at: Vector2 = RUBBISH[i]
		if not game.run.sim.path_p.find(game.world.solid_p, Base.SPAWN.x, Base.SPAWN.y, at.x, at.y).is_empty():
			spots.append({"at": at, "dirt": 0.5 + 0.1 * float(i % 5)})
	_last_tod = game.tod
	if game.args.has("cleannow"):
		_last_tod = -2.0
		for at in [Vector2(36.0, 44.0), Vector2(37.5, 45.0), Vector2(60.0, 44.0)]:    # (a check: blood in the yard for the cleaners to find)
			game.fx.combat.decal(at.x, at.y, 1.2, 0.3, 0.9)


func update(dt: float) -> void:
	var crew = game.crew
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
	for s in spots:
		s.dirt = minf(1.0, float(s.dirt) + dt / 240.0)
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
		if not plans.has(id) or m.has("down"):
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
	for d in game.fx.combat._decals:    # (the sim's blood sprites: they fade by themselves in 20 s, a broom speeds that up)
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
	var fallback: Vector2 = [Vector2(36.0, 44.0), Vector2(60.0, 44.0), Vector2(46.0, 40.0)][rounds % 3]
	return {"at": fallback, "work": work, "say": say}


## A cleaner at work: stains and bodies in reach age fast and fade away, the rubbish pile shrinks.
func _work_at(m: Dictionary, dt: float) -> void:
	var c := Vector2(m.p.x, m.p.y)
	for d in game.fx.combat._decals:
		if (d.node.position / TILE).distance_to(c) < REACH:
			d.age = float(d.age) + dt * SPEED_UP
	for z in game.run.sim.zombies:
		if z.state == "dead" and Vector2(z.x, z.y).distance_to(c) < REACH:
			z.dead_t = float(z.dead_t) + dt * SPEED_UP
			if game.args.has("log") and not z.has_meta("logged"):
				z.set_meta("logged", true)
				print("CLEAN body being cleared by ", m.def.name)
	for s in spots:
		if (s.at as Vector2).distance_to(c) < REACH:
			s.dirt = maxf(0.0, float(s.dirt) - dt / 7.0)


## Drawn in the world overlay: the rubbish piles and a bucket by anyone with a broom or a mop in hand.
func paint(c: CanvasItem) -> void:
	for s in spots:
		var d := float(s.dirt)
		if d < 0.05:
			continue
		var p: Vector2 = s.at * TILE
		for k in int(ceil(d * 7.0)):
			var o := Vector2(sin(float(k) * 2.3 + p.x) * 12.0, cos(float(k) * 1.7 + p.y) * 7.0) * (0.4 + d)
			var col: Color = [Color(0.82, 0.8, 0.7), Color(0.45, 0.4, 0.3), Color(0.6, 0.62, 0.66), Color(0.75, 0.7, 0.5)][k % 4]
			c.draw_rect(Rect2(p + o - Vector2(3, 2), Vector2(6 + (k % 3) * 2, 4)), Color(col, 0.9))
	for m in game.crew.members:
		if m.state == "work" and m.has("eat") and bool(m.eat.get("clean", false)) and String(m.eat.work) == "clean":
			var b := Vector2(m.p.x + 0.8, m.p.y + 0.35) * TILE
			c.draw_rect(Rect2(b - Vector2(6, 9), Vector2(12, 10)), Color(0.35, 0.4, 0.5))
			c.draw_rect(Rect2(b - Vector2(6, 9), Vector2(12, 3)), Color(0.45, 0.65, 0.85))
