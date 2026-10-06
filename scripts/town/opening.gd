## The scripted OPENING of the One House run (TUTOR): the first minute of a run that begins on the road in, made the same for the same town, so that a stranger learns to walk, aim, fire and
## reload before anything can hurt her. The rules' side only (scripts/town/one_house.gd makes it, calls `update` every step and saves it; scripts/ui/tutor_cues.gd draws what it says).
##
## THE BEAT SHEET (the numbers are the data's, `opening` in assets/data/one_house.json; the way is the walking grid's from the entry to the nearest house's door):
##   at the start   the magazine holds `mag` (3) rounds of the six (the spare stock is untouched: the first stores line reads 3 / 40), so that a reload is natural after a shot or two. (With two the
##                  second shot empties it and the gun reloads itself, so the key would never be taught; with three one round or two are left when the walker is down.)
##   `trigger`      about `trigger_tiles` (12: the walk in is short, EARLY) tiles along the way (less when the first house is near: the walker is never put within `margin` tiles of its door) she passes the point
##                  `walker_ahead` (10) tiles short of a parked car (the car nearest that place that stands near the way; none: a point of the road): ONE walker steps out from behind it
##                  and walks at her, state `chase`, at `walker_speed` (a walker's pace, never a runner's). It is a real one of the field's records (added at the start, woken here), so the
##                  kill is counted as any. It does not bite: for `grace_s` seconds or until she has put one down it holds `hold_r` tiles off her and its claw is kept back.
##   the box        an AMMO BOX lies `box_ahead` (6) tiles past the trigger point on the pavement to her right (`box_side` tiles off the way): E takes the shells (`box_loot`) in `take_s`
##                  seconds, into the stores. It is a provider of `sim.uses` (kind "container", id "opening_ammo"), so the E prompt, the ring and the sounds are the ones of every other thing to use.
##   the lessons    `shoot` is offered when the walker is `shoot_r` (12) tiles off (scripts/town/one_house.gd, the guide's `when`), then `reload` when the gun is low, then `find`.
## A town with no road in (the start is inside a house), no free place for the box or a way that cannot be walked builds nothing: `built` stays false and the run falls back to the old lone
## dead one (`OneHouse._place_lone_dead`).
## SAVED: where the pieces are and which have happened (the field's own save holds the dead one, the stores the shells).
extends RefCounted

const Arrival := preload("res://scripts/town/arrival.gd")

## (kind "container": the interact module ranks the kinds it knows, `Interact.RANK`, and a container is a thing to search: the shells in a box are one. The id is no house's container.)
const KIND := "container"
const BOX_ID := "opening_ammo"
## How near the box she must stand for E, and how far a street object may stand from the way and still be the car the walker comes out from.
const REACH := 1.3
const CAR_SIDE_MAX := 7.0
const CAR_KITS := ["car", "car_h", "car_v", "car_wreck"]

var sim
var scenario
## Whether the opening was made for this run, and where its pieces are (tiles; INF: none).
var built := false
var route: Array = []
var route_len := 0.0
var trigger_s := 0.0
var trigger_at := Vector2.INF
var spawn_at := Vector2.INF
var car_at := Vector2.INF
## Whether the thing the walker comes out from is a car (else a smaller solid thing of the street).
var cover_big := true
var box_at := Vector2.INF
var box_taken := false
var box_loot := {}
## The walker's record in the field, whether it has stepped out, when (the rules' time), and the real one (null before it, and after it is gone).
var rec := -1
var released := false
var release_t := -1.0
var dead_t := -1.0
var zombie = null
var _cum: Array = []
var _base_speed := 0.62


func setup(s, owner) -> void:
	sim = s
	scenario = owner


func start() -> void:
	built = false
	route = []
	route_len = 0.0
	trigger_s = 0.0
	trigger_at = Vector2.INF
	spawn_at = Vector2.INF
	car_at = Vector2.INF
	cover_big = true
	box_at = Vector2.INF
	box_taken = false
	box_loot = {}
	rec = -1
	released = false
	release_t = -1.0
	dead_t = -1.0
	zombie = null
	_cum = []


func _cfg(path: String, fallback = null):
	return scenario._cfg("opening." + path, fallback)


# ------------------------------------------------------------------------ making it --

## Makes the opening for a run that has just begun (the avatar at the entry, the street's dead calmed): the way, the walker's record, the box, the magazine. False when it cannot be
## made (see the header): nothing is changed then.
func begin() -> bool:
	start()
	if not bool(_cfg("enabled", true)):
		return false
	var field = sim.get("field")
	var houses = sim.get("houses")
	var town: Dictionary = scenario._town()
	if field == null or houses == null or town.is_empty() or not town.has("start") or not field.has_method("add_record"):
		return false
	var spawn := Arrival.spawn(town)
	var first := Arrival.nearest(town, spawn.pos)
	if first < 0 or int(houses.house_at(spawn.pos.x, spawn.pos.y)) == first:
		return false
	var goal := Arrival.door_of(town, first)
	var way: Array = sim.path_p.find(sim.world.solid_p, spawn.pos.x, spawn.pos.y, goal.x, goal.y)
	if way.is_empty():
		return false
	route = [Vector2(spawn.pos)]
	for wp in way:
		route.append(Vector2(wp))
	_cum = [0.0]
	for i in range(1, route.size()):
		_cum.append(float(_cum[i - 1]) + (route[i] as Vector2).distance_to(route[i - 1]))
	route_len = float(_cum[_cum.size() - 1])
	var ahead := float(_cfg("walker_ahead", 14.0))
	var margin := float(_cfg("margin", 8.0))
	var want := float(_cfg("trigger_tiles", 25.0))
	# the car the walker comes out from: the one nearest where it would be, never the entry's own, never at the door of the house; none: another solid thing of the street (a bush, a mailbox)
	var want_s := minf(want + ahead, route_len - margin)
	var s_car := -1.0
	for cars_only in [true, false]:
		var best := INF
		for o in town.data.objects:
			var kit := String(o.get("kit", o.get("kind", "")))
			var is_car := CAR_KITS.has(kit)
			if cars_only:
				if not is_car:
					continue
			elif is_car or not bool(o.get("solid", false)) or int(o.get("in", -1)) >= 0 or kit == "":
				continue
			if not (o.has("cx") and o.has("cy")):
				continue
			var p := Vector2(float(o.cx), float(o.cy))
			var near := _nearest_on_route(p)
			if float(near.lat) > (CAR_SIDE_MAX if cars_only else 4.5) or float(near.s) < ahead + 3.0 or float(near.s) > route_len - margin:
				continue
			if absf(float(near.s) - want_s) < best:
				best = absf(float(near.s) - want_s)
				s_car = float(near.s)
				car_at = p
				cover_big = cars_only
		if s_car >= 0.0:
			break
	var s_walker := s_car if s_car >= 0.0 else want_s
	trigger_s = clampf(s_walker - ahead, 4.0, route_len)
	trigger_at = _point_at(trigger_s).pos
	spawn_at = _hidden_spot(s_walker, trigger_at)
	if spawn_at == Vector2.INF:
		return false
	box_at = _box_spot(trigger_s + float(_cfg("box_ahead", 6.0)))
	if box_at == Vector2.INF:
		return false
	var loot = _cfg("box_loot", {"ammo": 8})
	box_loot = (loot as Dictionary).duplicate() if loot is Dictionary else {"ammo": 8}
	rec = field.add_record(spawn_at, "walker", true)
	var me = sim.avatar.player()
	var full: int = int(me.gun.get("mag", 0)) if me != null else 0
	var mag := int(_cfg("mag", 2))
	if me != null and mag > 0 and mag < full and not bool(me.gun.get("melee", false)):
		me.mag = mag
	_base_speed = float(_cfg("walker_speed", 0.62))
	built = true
	var uses = sim.get("uses")
	if uses != null and uses.has_method("register"):
		uses.register(self)
	return true


## {"pos", "dir"}: the point of the way `s` tiles from the entry, and the way it runs there.
func _point_at(s: float) -> Dictionary:
	s = clampf(s, 0.0, route_len)
	for i in range(1, route.size()):
		if s <= float(_cum[i]) or i == route.size() - 1:
			var a: Vector2 = route[i - 1]
			var b: Vector2 = route[i]
			var seg := maxf(float(_cum[i]) - float(_cum[i - 1]), 0.0001)
			return {"pos": a.lerp(b, clampf((s - float(_cum[i - 1])) / seg, 0.0, 1.0)), "dir": (b - a).normalized()}
	return {"pos": route[0], "dir": Vector2.RIGHT}


## {"s": tiles along the way, "lat": how far off it} of the point of the way nearest `p`.
func _nearest_on_route(p: Vector2) -> Dictionary:
	var best_lat := INF
	var best_s := 0.0
	for i in range(1, route.size()):
		var a: Vector2 = route[i - 1]
		var b: Vector2 = route[i]
		var c := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(c)
		if d < best_lat:
			best_lat = d
			best_s = float(_cum[i - 1]) + a.distance_to(c)
	return {"s": best_s, "lat": best_lat}


func _free(p: Vector2) -> bool:
	if sim.world.is_solid(sim.world.solid_p, p.x, p.y) or sim.world.is_solid(sim.world.solid_z, p.x, p.y):
		return false
	var houses = sim.get("houses")
	return houses == null or int(houses.house_at(p.x, p.y)) < 0


## Where the walker waits: just beyond the car (the side away from her), on a free tile of the street; the way's own point when there is no car or no room.
func _hidden_spot(s: float, from: Vector2) -> Vector2:
	var on_way: Vector2 = _point_at(s).pos
	if car_at != Vector2.INF:
		var away := (car_at - from).normalized()
		var side := Vector2(-away.y, away.x)
		for reach in ([2.7, 3.2, 2.2, 3.7] if cover_big else [1.5, 2.0, 2.5]):
			for lat in [0.0, 0.8, -0.8, 1.6, -1.6]:
				var p: Vector2 = car_at + away * reach + side * lat
				p = Vector2(floorf(p.x) + 0.5, floorf(p.y) + 0.5)
				if _free(p) and p.distance_to(from) > float(_cfg("walker_ahead", 14.0)) - 3.0:
					return p
	var q := Vector2(floorf(on_way.x) + 0.5, floorf(on_way.y) + 0.5)
	return q if _free(q) else Vector2.INF


## The box's place: `s` tiles along the way and then to her right (the way's right hand: for a way running west, north), on the pavement when there is one within the data's `box_side`
## tiles, else the first free tile of the street; the left hand when the right has none.
func _box_spot(s: float) -> Vector2:
	# (the road's own axis, the way she faces at the entry, and the lane she stands in: the way to the house cuts across the road to a pavement, so the pavement "on the right" is the road's)
	var town: Dictionary = scenario._town()
	var spawn := Arrival.spawn(town)
	var axis: Vector2 = Vector2.from_angle(float(spawn.angle))
	var right := Vector2(-axis.y, axis.x)
	var pos: Vector2 = _point_at(s).pos
	var lane: Vector2 = Vector2(spawn.pos) + axis * (pos - Vector2(spawn.pos)).dot(axis)
	var span = _cfg("box_side", [2.5, 8.0])
	var lo := float(span[0]) if span is Array and span.size() > 1 else 2.5
	var hi := float(span[1]) if span is Array and span.size() > 1 else 8.0
	var q: Vector2 = lane + right * minf(lo + 1.0, hi)
	var walk_id := _ground_id("SIDEWALK")
	var road_id := _ground_id("ASPHALT")
	var best := Vector2.INF
	var best_score := INF
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var p := Vector2(floorf(q.x) + 0.5 + float(dx), floorf(q.y) + 0.5 + float(dy))
			if not (_free(p) and _free(p + Vector2(1, 0)) and _free(p + Vector2(-1, 0)) and _free(p + Vector2(0, 1)) and _free(p + Vector2(0, -1))):
				continue
			var lat := (p - lane).dot(right)
			if absf(lat) < lo * 0.8 or absf(lat) > hi + 2.0:
				continue
			var ground := _ground_at(p)
			var score := p.distance_to(q) + (0.0 if lat > 0.0 else 6.0) + (0.0 if (walk_id >= 0 and ground == walk_id) else (4.0 if ground != road_id else 12.0))
			if score < best_score:
				best_score = score
				best = p
	return best


func _ground_id(name: String) -> int:
	var town: Dictionary = scenario._town()
	var types = town.get("data", {}).get("terrainTypes", {})
	if types is Dictionary and (types as Dictionary).has(name):
		return int(types[name].id)
	return -1


func _ground_at(p: Vector2) -> int:
	var w = sim.world
	var tx := floori(p.x)
	var ty := floori(p.y)
	if tx < 0 or ty < 0 or tx >= w.W or ty >= w.H:
		return -1
	return int(w.terrain[ty * w.W + tx])


# ------------------------------------------------------------------------ every step --

## Every rules step: she passes the trigger point and the walker steps out; the walker is kept as the beat wants it.
func update(_dt: float) -> void:
	if not built:
		return
	var me = sim.avatar.player()
	if me == null:
		return
	if not released:
		# (she is near the walker's car, or a house to claim has come near: the walker is never left for after the house)
		if scenario.walked() >= 6.0 and (Vector2(me.x, me.y).distance_to(spawn_at) <= float(_cfg("walker_ahead", 14.0)) or scenario._near_candidate() <= float(_cfg("release_near", 10.0))):
			release()
		return
	_step_walker(me)


## Whether the opening has had its say: there is none, or the walker has stepped out and is down (or gone). The lesson of finding a house waits for it, so that the walker comes first.
func settled() -> bool:
	return not built or (released and not walker_alive())


## The walker steps out: its record wakes as the real one and goes after her, slowly.
func release() -> void:
	if released or not built:
		return
	released = true
	release_t = float(sim.t)
	var field = sim.get("field")
	var me = sim.avatar.player()
	if field == null or me == null or rec < 0:
		return
	var state := int(field.status[rec])
	if state == 0:
		zombie = field._wake(rec, null)
	elif state == 1:
		zombie = field.active_of.get(rec)    # (the field woke it by itself first: a shot, or another way in)
	if zombie == null:
		return
	zombie.limp = false
	zombie.speed = _base_speed
	zombie.hp = int(_cfg("walker_hp", 5))
	sim.start_chase(zombie, me)
	if "pause_wake" in field:
		field.pause_wake = true    # (the scenario keeps it: `holds_the_street`)


## Whether the walker is up and about (stepped out, not yet down).
func walker_alive() -> bool:
	return zombie != null and not _gone(zombie)


## Whether the street's sleeping dead are to be left asleep now (`OneHouse._apply_flags` puts it on the field): from the walker's step out until a few seconds after it is down, at most
## `grace_s` and a little more, so that the shots of the lesson wake nobody from the houses and nothing else bites her while she learns the gun. Not a rule of the game: the opening's.
func holds_the_street() -> bool:
	if not built or not released:
		return false
	var since := float(sim.t) - release_t
	if since > float(_cfg("grace_s", 45.0)) + 15.0:
		return false
	return walker_alive() or zombie != null or (dead_t >= 0.0 and float(sim.t) - dead_t < float(_cfg("calm_tail_s", 3.0)))


func _gone(z) -> bool:
	return String(z.state) == "dying" or String(z.state) == "dead" or bool(z.remove)


## The walker's pace and its manners: a walker's pace, back on her trail should it lose it, and no bite while she has not yet had her chance (`grace_s`, or a kill).
func _step_walker(me) -> void:
	var field = sim.get("field")
	if zombie == null:
		if field != null and rec >= 0 and field.active_of.has(rec):
			zombie = field.active_of[rec]    # (a loaded run: the real one is found again by its record)
		else:
			return
	var z = zombie
	if _gone(z):
		zombie = null
		dead_t = float(sim.t)
		return
	var grace: bool = int(sim.kills) < 1 and float(sim.t) - release_t < float(_cfg("grace_s", 45.0))
	var d := Vector2(me.x, me.y).distance_to(Vector2(z.x, z.y))
	z.limp = false
	if grace:
		z.attack_t = maxf(float(z.attack_t), 0.8)
		z.speed = 0.0 if d < float(_cfg("hold_r", 3.0)) else _base_speed
	else:
		z.speed = _base_speed
	if String(z.state) != "chase" and String(z.state) != "dying" and not bool(z.remove):
		sim.start_chase(z, me)


# ------------------------------------------------------------------------ the box --

## The shells on the pavement: "Take the shells" within REACH (a session of `take_s` seconds, so the ring and the sounds are the search's).
func candidates(p) -> Array:
	var out: Array = []
	if not built or box_taken or box_at == Vector2.INF:
		return out
	var d := Vector2(p.x, p.y).distance_to(box_at)
	if d > REACH:
		return out
	var uses = sim.get("uses")
	var stop: bool = uses != null and uses.in_session(KIND, BOX_ID)
	out.append({"kind": KIND, "id": BOX_ID, "label": "Stop" if stop else "Take the shells", "pos": box_at, "dist": d, "ok": true, "why": "", "session": true})
	return out


func use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) != KIND or box_taken:
		return {}
	var uses = sim.get("uses")
	var p = sim.avatar.player()
	if uses == null or p == null:
		return {"ok": false, "line": "", "why": "You are not here", "session": true}
	if uses.in_session(KIND, BOX_ID):
		uses.cancel("stopped")
		return {"ok": true, "line": "Stopped.", "why": "", "session": true, "stopped": true}
	var secs := float(_cfg("take_s", 1.2))
	var r: Dictionary = uses.begin_session(KIND, BOX_ID, "Taking the shells", secs, box_at, REACH + 0.3, Callable(self, "_taken"))
	if not bool(r.get("ok", false)):
		return {"ok": false, "line": "", "why": String(r.get("why", "")), "session": true}
	return {"ok": true, "line": "Taking the shells", "why": "", "session": true, "seconds": secs}


## The session ran its course: the shells go into the stores and the box is empty. The event is the search's own (`searched`, the loot popping up to the stores), with no container of a house.
func _taken() -> void:
	if box_taken:
		return
	box_taken = true
	var loot := {}
	for k in box_loot:
		var n := float(box_loot[k])
		if n > 0.0 and sim.stock.has(k):
			sim.stock[k] = float(sim.stock[k]) + n
			loot[String(k)] = int(n)
	sim.events.append({"type": "supply_taken", "id": BOX_ID, "loot": loot, "at": box_at})


# ------------------------------------------------------------------------ the save --

func save() -> Dictionary:
	if not built:
		return {"built": false}
	return {
		"built": true, "route": _vecs(route), "trigger_s": trigger_s, "trigger_at": [trigger_at.x, trigger_at.y], "spawn_at": [spawn_at.x, spawn_at.y],
		"car_at": [car_at.x, car_at.y] if car_at != Vector2.INF else [], "box_at": [box_at.x, box_at.y], "taken": box_taken, "loot": box_loot, "rec": rec, "released": released, "release_t": release_t,
	}


func load_state(d: Dictionary) -> void:
	start()
	if not bool(d.get("built", false)):
		return
	var r = d.get("route", [])
	if not (r is Array) or (r as Array).size() < 2:
		return
	for v in r:
		route.append(Vector2(float(v[0]), float(v[1])))
	_cum = [0.0]
	for i in range(1, route.size()):
		_cum.append(float(_cum[i - 1]) + (route[i] as Vector2).distance_to(route[i - 1]))
	route_len = float(_cum[_cum.size() - 1])
	trigger_s = float(d.get("trigger_s", 0.0))
	trigger_at = _vec(d.get("trigger_at", []))
	spawn_at = _vec(d.get("spawn_at", []))
	car_at = _vec(d.get("car_at", []))
	box_at = _vec(d.get("box_at", []))
	box_taken = bool(d.get("taken", false))
	var loot = d.get("loot", {})
	box_loot = (loot as Dictionary).duplicate() if loot is Dictionary else {}
	rec = int(d.get("rec", -1))
	released = bool(d.get("released", false))
	release_t = float(d.get("release_t", -1.0))
	_base_speed = float(_cfg("walker_speed", 0.62))
	built = box_at != Vector2.INF
	var uses = sim.get("uses")
	if built and uses != null and uses.has_method("register"):
		uses.register(self)


static func _vecs(list: Array) -> Array:
	var out: Array = []
	for v in list:
		out.append([(v as Vector2).x, (v as Vector2).y])
	return out


static func _vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and (a as Array).size() >= 2 else Vector2.INF


# ------------------------------------------------------------------------ staging --

## For the screenshots (`--lesson=`) and the scripted run: the avatar on the way `s` tiles from the entry, facing along it.
func put_avatar(s: float) -> void:
	var me = sim.avatar.player()
	if me == null or not built:
		return
	var at: Dictionary = _point_at(s)
	me.x = float(at.pos.x)
	me.y = float(at.pos.y)
	me.path = []
	me.moving = false
	var dir: Vector2 = at.dir
	me.aim = dir.angle()
	me.facing = "E" if absf(dir.x) >= absf(dir.y) and dir.x > 0.0 else ("W" if absf(dir.x) >= absf(dir.y) else ("S" if dir.y > 0.0 else "N"))


## The walker steps out (as at the trigger) and is then put `gap` tiles ahead of the avatar on the way, for a picture.
func stage_walker(gap: float) -> void:
	release()
	if zombie == null:
		return
	var me = sim.avatar.player()
	var here: Vector2 = Vector2(me.x, me.y)
	var along := _nearest_on_route(here)
	var p: Vector2 = _point_at(float(along.s) + gap).pos
	zombie.x = p.x
	zombie.y = p.y
	zombie.path = []
