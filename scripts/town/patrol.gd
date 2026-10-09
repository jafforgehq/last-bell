## PATROL (PH3, "people need to be moved around constantly when defending"): the crew who hold no fixed post walk the fence line by themselves and go where the dead press.
##
## WHO. Every person of the town is on PATROL unless somebody has given them a post (`jobs.PATROL`, `jobs.on_patrol`: the default; the Duty roster says "Patrol"). A person assigned
## to a post (a tower, the gate's, a stretch of fence: the player's choice, the radio's, the avatar's E) holds it exactly as before; the avatar is not on patrol at all. A person with
## another job (builder, scavenger, radio desk, medic) keeps it by day: it is only while the posts are manned (`sim.posts_manned()`: the call to arms, an attack night, a day under
## attack) that the colony sends them to their post, and so to the patrol here (`TownRules._post_duty_goal` asks `goal_for`).
##
## THE LOOP. The ring of tiles two inside the lot's border (about a tile and a half behind the fence's inner face; the posts are on the ring before it), clockwise, taken from the
## base's layout (`perimeter.layout.inner`): a point every `spacing` tiles and a point at each corner, a tile a step in or out where the ring is blocked (a tree, a prop, the house).
## The points are also the STAND points where a patroller holds and shoots. Nothing here leaves the lot: a patroller who finds themselves outside it (a rescue run, an order) walks back
## to the nearest point of the loop (`back`).
##
## THE WALK. Calm (`pace`, a share of the person's walking speed), always clockwise. Each takes a stretch: the first time they are on patrol the patrollers are spread over the loop
## (each to the nearest of n evenly spaced centres), and a small controller on the gaps (the one ahead and the one behind, the holders count as standing still) speeds up the one with
## room ahead and slows the one close behind another, so that they keep apart. At a corner they pause and look from one fence to the next; now and then at other points they stop and
## look over the fence (the goal's `face`: the pose and the eased turn are the pawn motion's own). Nothing consumes `sim.rng`.
##
## THE PRESSURE. Every `replan_s` seconds each stand point gets a number: the dead near it (a clawing one 1.0, a breaching one 2.5, one coming at the fence 0.45, one hunting a person
## 0.5; a brute counts 3.5 times, a runner 1.3; fading out between `full_r` and `dead_r` tiles) plus the sections near it that are worn (up to `w_hurt` x the share lost) or DOWN
## (`w_down`: a gap in the fence, and the defenders gather behind it), but only while some of the dead are near that section. Where the dead stand is where the pressure is; a
## section that was hurt last night and is quiet pulls nobody.
##
## THE REACTION. The free patrollers (not on a point) are sent one at a time, each pair of (point, patroller) scored `pressure / (1 + near_pen x patrollers already within near_r) -
## dist_cost x tiles`: the heaviest place first, a second one only where the pressure is heavy enough to share, the nearest patroller of two equal ones. A patroller who is sent walks
## at the person's full pace (`go`), stops at the point (`hold`), faces the fence and shoots as the colony's crew shoots (`Sim._combat`: only a person standing still fires, the ammo
## and the aim are the colony's). Anyone on the walk with a target in reach stops where they are for `engage_s` seconds and shoots too (`engaged`).
## HYSTERESIS. A patroller sent stays at least `min_stay` seconds after arriving and until the pressure at the point has fallen below `keep_min`; it moves to another point only if that
## one is worth `switch_ratio` times as much, and a point needs `start_min` to call anybody (above `keep_min`). Two patrollers never take points less than `min_gap` apart.
##
## SAVE. Nothing: the state is the walk, rebuilt in a moment on a load. `post_pos` answers the colony's questions about a person's post (the readiness line, the fields of fire).
extends RefCounted

const KNOBS := {
	"pace": 0.5, "pace_go": 1.0, "pace_back": 0.9, "spacing": 3.0, "replan_s": 0.4,
	"min_stay": 2.0, "start_min": 1.4, "keep_min": 0.6, "near_pen": 1.5, "near_r": 6.0, "min_gap": 2.2, "switch_ratio": 1.7, "dist_cost": 0.06,
	"dead_r": 13.0, "full_r": 5.0, "w_attack": 1.0, "w_approach": 0.45, "w_breach": 2.5, "w_chase": 0.5, "w_brute": 3.5, "w_runner": 1.3,
	"w_down": 14.0, "w_hurt": 5.0, "sec_r": 7.0, "active_r": 22.0, "engage_s": 1.0,
	"pause_min": 1.6, "pause_max": 3.2, "look_every": 7, "arrive": 0.9, "gap_swing": 0.5,
}
## The first segment id of the lots' own sections (not the base's).
const FIRST_LOT_SEGMENT := 100
const SIDE_NAME := {"N": "north", "E": "east", "S": "south", "W": "west"}
const INWARD := {"N": Vector2i(0, 1), "E": Vector2i(-1, 0), "S": Vector2i(0, -1), "W": Vector2i(1, 0)}

var sim
var enabled := true
## What the patrol costs (microseconds and calls, for the probe and the measurements: whoever reads them resets them).
var usec_goal := 0
var calls_goal := 0
var usec_replan := 0
var calls_replan := 0

## The lot (tiles; the border is its outer ring): inside is the base.
var _lot := Rect2()
## The loop, clockwise: the points, the side of the fence each is behind ("N", "E", "S", "W"), whether it is a corner, the arc length at each, the whole length.
var _pts: Array = []
var _side: Array = []
var _corner: Array = []
var _cum: Array = []
var _len := 0.0
var _key := ""
## Seconds of rules time since the module was made (the clock of the pauses and the stays).
var _t := 0.0
var _tick := 0.0
## Person id -> {"mode", "i", "tgt", "since", "arrive", "until", "mid", "face", "pace", "seen", "fresh", "paused_at", "n"}.
var _st := {}
var _press: Array = []
var _top := 0.0
var _kn := {}
var _knobs_t := -1.0


func setup(s) -> void:
	sim = s
	_kn = KNOBS.duplicate()


func start() -> void:
	_st.clear()
	_pts = []
	_key = ""


# --------------------------------------------------------------------- knobs --

func _k(name: String) -> float:
	return float(_kn.get(name, KNOBS[name]))


## The data's `patrol` block over the defaults (read every few seconds: the lab's `--set=patrol.pace=0.6` over the run in memory is felt).
func _read_knobs() -> void:
	if _knobs_t >= 0.0 and _t - _knobs_t < 3.0:
		return
	_knobs_t = _t
	_kn = KNOBS.duplicate()
	var sc = sim.get("scenario")
	if sc != null and sc.has_method("d"):
		var blk = sc.d().get("patrol", {})
		if blk is Dictionary:
			for key in blk:
				if KNOBS.has(String(key)) and (typeof(blk[key]) == TYPE_FLOAT or typeof(blk[key]) == TYPE_INT):
					_kn[String(key)] = float(blk[key])


# ------------------------------------------------------------------ the loop --

func _tile_open(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= sim.W or ty >= sim.H:
		return false
	return int(sim.world.solid_p[ty * sim.W + tx]) == 0


## Makes the loop from the base's layout; false while there is no base (or no lot in its layout: the fallback layout of a test).
func _ensure() -> bool:
	var per = sim.get("perimeter")
	if per == null or per.layout.is_empty():
		return false
	var plot: Rect2i = per.layout.get("plot", Rect2i())
	var inner: Rect2i = per.layout.get("inner", Rect2i())
	if plot.size.x < 8 or plot.size.y < 8 or inner.size.x < 4 or inner.size.y < 4:
		return false
	var key := "%s|%s" % [plot, inner]
	if key != _key:
		_key = key
		_build(plot, inner)
	return not _pts.is_empty()


func _build(plot: Rect2i, inner: Rect2i) -> void:
	_lot = Rect2(plot)
	_pts = []
	_side = []
	_corner = []
	_cum = []
	_len = 0.0
	var r: Rect2i = inner.grow(-1) if inner.size.x >= 6 and inner.size.y >= 6 else inner
	var dense: Array = []
	# the ring of tile centres, clockwise from the top left: the north row, the east column, the south row, the west column
	var px0 := r.position.x
	var py0 := r.position.y
	var px1 := r.end.x - 1
	var py1 := r.end.y - 1
	for x in range(px0, px1 + 1):
		_add_dense(dense, x, py0, "N", x == px0 or x == px1)
	for y in range(py0 + 1, py1 + 1):
		_add_dense(dense, px1, y, "E", y == py1)
	for x in range(px1 - 1, px0 - 1, -1):
		_add_dense(dense, x, py1, "S", x == px0)
	for y in range(py1 - 1, py0, -1):
		_add_dense(dense, px0, y, "W", false)
	if dense.size() < 4:
		return
	# thin it: a point every `spacing` tiles, every corner, and none within 2 tiles of a corner that is not one
	var spacing := _k("spacing")
	var kept: Array = []
	var last := Vector2(-1.0e9, -1.0e9)
	for e in dense:
		if bool(e.corner):
			kept.append(e)
			last = e.p
	var all: Array = []
	var lastp := Vector2(-1.0e9, -1.0e9)
	for e in dense:
		var near_corner := false
		for c in kept:
			if bool(c.corner) and c != e and (c.p as Vector2).distance_to(e.p) < spacing * 0.7:
				near_corner = true
		if bool(e.corner) or (not near_corner and (e.p as Vector2).distance_to(lastp) >= spacing - 0.001):
			all.append(e)
			lastp = e.p
	if last.x < -1.0e8 and all.is_empty():
		return
	for e in all:
		_pts.append(e.p)
		_side.append(String(e.side))
		_corner.append(bool(e.corner))
	var acc := 0.0
	for i in _pts.size():
		_cum.append(acc)
		acc += (_pts[i] as Vector2).distance_to(_pts[(i + 1) % _pts.size()])
	_len = acc
	_press.resize(_pts.size())
	_press.fill(0.0)


## A tile centre of the ring: the tile itself if it is open, else a step in, a step out or two in (a tree, a prop, the house's corner); nothing if all are shut.
func _add_dense(dense: Array, tx: int, ty: int, side: String, corner: bool) -> void:
	var inward: Vector2i = INWARD[side]
	for t in [Vector2i(tx, ty), Vector2i(tx, ty) + inward, Vector2i(tx, ty) - inward, Vector2i(tx, ty) + inward * 2]:
		if _tile_open(t.x, t.y) and _lot.has_point(Vector2(float(t.x) + 0.5, float(t.y) + 0.5)):
			dense.append({"p": Vector2(float(t.x) + 0.5, float(t.y) + 0.5), "side": side, "corner": corner})
			return


## The points of the loop (tiles), clockwise: for the views, the probe and the tests.
func points() -> Array:
	_ensure()
	return _pts


func loop_length() -> float:
	_ensure()
	return _len


func lot() -> Rect2:
	return _lot


## The index of the point nearest to `at`.
func nearest(at: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in _pts.size():
		var d: float = (_pts[i] as Vector2).distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best


## The point of the loop nearest to `at` (for the colony's questions: how far a gun reaches a section from the loop).
func stand_near(at: Vector2) -> Vector2:
	if not _ensure():
		return at
	return _pts[nearest(at)]


## The point `frac` (0 to 1) of the way round the loop.
func _index_at(frac: float) -> int:
	var want := fposmod(frac, 1.0) * _len
	var best := 0
	for i in _pts.size():
		if float(_cum[i]) <= want:
			best = i
	return best


## The clockwise distance along the loop from point `a` to point `b`.
func _arc(a: int, b: int) -> float:
	return fposmod(float(_cum[b]) - float(_cum[a]), _len)


# ------------------------------------------------------------ the colony asks --

## Whether a person is among those the patrol is working now (the posts are manned and they are on patrol and free).
func is_walking(p) -> bool:
	var s = _st.get(String(p.id))
	return s != null and _t - float(s.seen) < 1.0


## What the colony counts as this person's post (the readiness line, the fields of fire, "To the walls"): where they are on the loop while the posts are manned and they are inside the
## lot; else an even spread of the patrollers round it (their place in the order of the crew).
func post_pos(p) -> Vector2:
	if not _ensure():
		return Vector2(p.x, p.y)
	var at := Vector2(p.x, p.y)
	if sim.posts_manned() and _lot.has_point(at):
		return at
	var n := 0
	var rank := 0
	for q in sim.people:
		if q.dead or q.turned or q.player or q.away != null or not sim.jobs.on_patrol(q):
			continue
		if q == p:
			rank = n
		n += 1
	return _pts[_index_at((float(rank) + 0.5) / float(maxi(n, 1)))]


# ------------------------------------------------------------------ the goal --

func _state(p) -> Dictionary:
	var id := String(p.id)
	var s: Dictionary = _st.get(id, {})
	if s.is_empty() or _t - float(s.seen) > 2.0:
		# (new to the patrol, or away from it for a while: a medic's case, an order, a trip)
		s = {"mode": "walk", "i": nearest(Vector2(p.x, p.y)), "tgt": -1, "since": _t, "arrive": -1.0, "until": 0.0, "mid": 0.0, "face": "", "pace": 1.0, "seen": _t, "fresh": true,
			"paused_at": -1, "n": 0}
		_st[id] = s
	return s


## The calm hash in 0..1 of a person, a lap and a point (pauses and looks differ from one person to the next and from one lap to the next, and are the same on a replay).
func _hash01(p, salt: int) -> float:
	return float(absi(hash(String(p.id)) + salt * 7919) % 1000) / 1000.0


## The goal of a person on patrol while the posts are manned, shaped as the colony's goals ({"x", "y", "face", "what", "pace"}); {} when there is no loop (no base yet).
func goal_for(p) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var g := _goal_for(p)
	usec_goal += Time.get_ticks_usec() - t0
	calls_goal += 1
	return g


func _goal_for(p) -> Dictionary:
	if not _ensure():
		return {}
	_read_knobs()
	var s := _state(p)
	s.seen = _t
	var pos := Vector2(p.x, p.y)
	# outside the lot: back to the loop, at once
	if not _lot.has_point(pos):
		s.mode = "back"
		s.tgt = -1
		var k := nearest(pos)
		return {"x": _pts[k].x, "y": _pts[k].y, "face": "", "what": "Back inside the fence", "pace": _k("pace_back")}
	if s.mode == "back":
		s.mode = "walk"
		s.i = nearest(pos)
	match String(s.mode):
		"go", "hold":
			return _goal_stand(p, s, pos)
		"engaged":
			return {"x": p.x, "y": p.y, "face": "", "what": "Holding the fence", "pace": 1.0}
		"pause":
			if _t >= float(s.until):
				s.mode = "walk"
			else:
				return {"x": p.x, "y": p.y, "face": String(s.face) if _t < float(s.mid) else String(s.get("face2", s.face)), "what": "Keeping watch", "pace": 1.0}
	return _goal_walk(p, s, pos)


func _goal_stand(p, s: Dictionary, pos: Vector2) -> Dictionary:
	var k: int = clampi(int(s.tgt), 0, _pts.size() - 1)
	var at: Vector2 = _pts[k]
	var side := String(SIDE_NAME.get(_side[k], "north"))
	if pos.distance_to(at) < 0.35:
		if String(s.mode) != "hold":
			s.mode = "hold"
			s.arrive = _t
		return {"x": at.x, "y": at.y, "face": String(_side[k]), "what": "Holding the %s fence" % side, "pace": 1.0}
	return {"x": at.x, "y": at.y, "face": "", "what": "Going to the %s fence" % side, "pace": _k("pace_go")}


func _goal_walk(p, s: Dictionary, pos: Vector2) -> Dictionary:
	var m := _pts.size()
	var i: int = int(s.i) % m
	for _skip in m:
		# (a point that has since been built over, a prop put on it: the walk goes on to the next)
		if _tile_open(floori(_pts[i].x), floori(_pts[i].y)):
			break
		i = (i + 1) % m
	var at: Vector2 = _lane(p, i)
	if pos.distance_to(at) <= _k("arrive"):
		# reached it: the next, and a pause at a corner or now and then to look over the fence
		s.n = int(s.n) + 1
		var prev := (i - 1 + m) % m
		var next := (i + 1) % m
		s.i = next
		if int(s.paused_at) != i:
			var look: bool = bool(_corner[i]) or int(floor(_hash01(p, i + int(s.n) * 13) * _k("look_every"))) == 0
			if look:
				s.paused_at = i
				s.mode = "pause"
				var span := _k("pause_max") - _k("pause_min")
				var dur := _k("pause_min") + span * _hash01(p, int(s.n))
				if not _corner[i]:
					dur = _k("pause_min") * 0.7
				s.until = _t + dur
				s.mid = _t + dur * 0.5
				s.face = String(_side[prev]) if _corner[i] else String(_side[i])
				s.face2 = String(_side[next]) if _corner[i] else String(_side[i])
				return {"x": p.x, "y": p.y, "face": String(s.face), "what": "Keeping watch", "pace": 1.0}
		i = next
		at = _lane(p, i)
	return {"x": at.x, "y": at.y, "face": "", "what": "On patrol", "pace": _k("pace") * float(s.pace)}


## A point of the walk, a step towards the house when somebody stands at it (a holder, someone looking, someone shooting): the walker goes by them and not through them.
func _lane(p, i: int) -> Vector2:
	var at: Vector2 = _pts[i]
	for q in sim.people:
		if q == p or q.dead or q.turned:
			continue
		var s = _st.get(String(q.id))
		if s == null or _t - float(s.seen) > 1.0:
			continue
		var mode := String(s.mode)
		if mode != "hold" and mode != "engaged" and mode != "pause":
			continue
		if Vector2(q.x, q.y).distance_to(at) < 1.3:
			var alt: Vector2 = at + Vector2(INWARD[_side[i]]) * 1.1
			if _tile_open(floori(alt.x), floori(alt.y)):
				return alt
	return at


# ------------------------------------------------------------------- the step --

func update(dt: float) -> void:
	_t += dt
	_tick -= dt
	if _tick > 0.0:
		return
	_read_knobs()
	_tick = _k("replan_s")
	if not _ensure() or not sim.posts_manned():
		if not _st.is_empty():
			_st.clear()    # (the posts stand down: the next call to arms begins afresh, spread over the loop)
		return
	var t0 := Time.get_ticks_usec()
	_replan()
	usec_replan += Time.get_ticks_usec() - t0
	calls_replan += 1


## Who is on patrol right now: [{"p", "s"}] (seen by `goal_for` within the last second; a person on a trip, a case or an order is not).
func _entries() -> Array:
	var out: Array = []
	for p in sim.people:
		var s = _st.get(String(p.id))
		if s != null and _t - float(s.seen) < 1.0 and not p.dead and not p.turned and not p.downed and p.away == null:
			out.append({"p": p, "s": s})
	return out


func _weight(z) -> float:
	var kind := String(z.kind)
	var mult := 1.0
	if kind == "brute":
		mult = _k("w_brute")
	elif kind == "runner":
		mult = _k("w_runner")
	match String(z.state):
		"attack":
			return _k("w_attack") * mult
		"breach":
			return _k("w_breach") * mult
		"approach":
			return _k("w_approach") * mult
		"chase", "hunt":
			return _k("w_chase") * mult
	return 0.0


## The pressure at each point of the loop (see the header).
func _compute_pressure() -> void:
	var n := _pts.size()
	_press.resize(n)
	_press.fill(0.0)
	var far := _lot.grow(_k("dead_r"))
	var dead_r := _k("dead_r")
	var full_r := _k("full_r")
	var span := maxf(dead_r - full_r, 0.1)
	var hostile: Array = []
	for z in sim.zombies:
		var w := _weight(z)
		if w <= 0.0:
			continue
		var zp := Vector2(z.x, z.y)
		if not far.has_point(zp):
			continue
		hostile.append([zp, w])
		for k in n:
			var d: float = zp.distance_to(_pts[k])
			if d < dead_r:
				_press[k] += w * clampf((dead_r - d) / span, 0.0, 1.0)
	if hostile.is_empty():
		_top = 0.0
		return
	# the sections: a worn one pulls, a fallen one pulls hard, but only while some of the dead are near it
	var sec_r := _k("sec_r")
	var active_r := _k("active_r")
	for s in sim.segments:
		if int(s.id) >= FIRST_LOT_SEGMENT or String(s.kind) == sim.DOOR_KIND:
			continue
		var down: bool = int(s.state) == 3
		var lost: float = 1.0 - clampf(float(s.hp) / maxf(float(s.max_hp), 1.0), 0.0, 1.0)
		if not down and lost < 0.15:
			continue
		var near := false
		for h in hostile:
			if (h[0] as Vector2).distance_to(s.center) <= active_r:
				near = true
				break
		if not near:
			continue
		var w: float = _k("w_down") if down else _k("w_hurt") * lost
		var rect := _section_rect(s)
		for k in n:
			var d := _dist_rect(_pts[k], rect)
			if d < sec_r:
				_press[k] += w * (1.0 - d / sec_r)
	_top = 0.0
	for v in _press:
		_top = maxf(_top, float(v))


static func _section_rect(s) -> Rect2:
	if String(s.side) == "N" or String(s.side) == "S":
		return Rect2(float(s.from), s.center.y - 0.5, float(s.to) - float(s.from), 1.0)
	return Rect2(s.center.x - 0.5, float(s.from), 1.0, float(s.to) - float(s.from))


static func _dist_rect(pt: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - pt.x, pt.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - pt.y, pt.y - r.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)


func _replan() -> void:
	var entries := _entries()
	if entries.is_empty():
		return
	_spread_the_fresh(entries)
	_compute_pressure()
	var m := _pts.size()
	# the ones on the walk who have a target in reach stop and shoot (Sim._combat fires only from a standstill)
	for e in entries:
		var s: Dictionary = e.s
		var mode := String(s.mode)
		if mode == "walk" or mode == "pause" or mode == "engaged":
			var has_target: bool = sim._find_target(e.p) != null
			if has_target:
				s.mode = "engaged"
				s.until = _t + _k("engage_s")
			elif mode == "engaged" and _t >= float(s.until):
				s.mode = "walk"
	# the ones sent: keep, or let go (the hysteresis)
	var held: Array = []
	var free: Array = []
	for e in entries:
		var s: Dictionary = e.s
		var mode := String(s.mode)
		if mode == "go" or mode == "hold":
			var k: int = int(s.tgt)
			var stayed: float = (_t - float(s.arrive)) if float(s.arrive) >= 0.0 else -1.0
			var keep := true
			if stayed >= _k("min_stay"):
				keep = float(_press[k]) >= _k("keep_min")
			elif stayed < 0.0 and _t - float(s.since) >= 1.5:
				keep = float(_press[k]) >= _k("keep_min")
			if keep:
				held.append(e)
			else:
				_let_go(e)
				free.append(e)
		elif mode != "back":
			free.append(e)
	# a place elsewhere worth far more than the one they hold: they move (once they have stayed)
	for e in held.duplicate():
		var s: Dictionary = e.s
		if float(s.arrive) < 0.0 or _t - float(s.arrive) < _k("min_stay"):
			continue
		var k: int = int(s.tgt)
		var others := _assigned_stands(held, e)
		var here: float = float(_press[k]) / (1.0 + _k("near_pen") * float(_count_near(k, others)))
		var best := 0.0
		for j in m:
			if _too_close(j, others):
				continue
			var worth: float = float(_press[j]) / (1.0 + _k("near_pen") * float(_count_near(j, others)))
			best = maxf(best, worth)
		if best >= _k("start_min") and best >= _k("switch_ratio") * here:
			held.erase(e)
			_let_go(e)
			free.append(e)
	# the free ones are sent, the best place first, the nearest patroller to it
	var assigned := _assigned_stands(held, null)
	while not free.is_empty():
		var best_score := -INF
		var best_k := -1
		var best_e = null
		for k in m:
			if float(_press[k]) < _k("start_min") or _too_close(k, assigned):
				continue
			var worth: float = float(_press[k]) / (1.0 + _k("near_pen") * float(_count_near(k, assigned)))
			if worth < _k("start_min"):
				continue
			for e in free:
				var d: float = Vector2(e.p.x, e.p.y).distance_to(_pts[k])
				var score: float = worth - _k("dist_cost") * d
				if score > best_score:
					best_score = score
					best_k = k
					best_e = e
		if best_k < 0:
			break
		var s: Dictionary = best_e.s
		s.mode = "go"
		s.tgt = best_k
		s.since = _t
		s.arrive = -1.0
		assigned.append(best_k)
		free.erase(best_e)
	_space_the_walkers(entries)


## A patroller who was sent goes back to the walk, from the point of the loop nearest to where they stand.
func _let_go(e: Dictionary) -> void:
	var s: Dictionary = e.s
	s.mode = "walk"
	s.i = nearest(Vector2(e.p.x, e.p.y))
	s.tgt = -1
	s.arrive = -1.0
	s.paused_at = -1


## The stands the others hold or are going to (`except` an entry left out).
func _assigned_stands(held: Array, except) -> Array:
	var out: Array = []
	for e in held:
		if e != except:
			out.append(int(e.s.tgt))
	return out


func _too_close(k: int, stands: Array) -> bool:
	for j in stands:
		if int(j) == k or (_pts[int(j)] as Vector2).distance_to(_pts[k]) < _k("min_gap"):
			return true
	return false


func _count_near(k: int, stands: Array) -> int:
	var n := 0
	for j in stands:
		if (_pts[int(j)] as Vector2).distance_to(_pts[k]) <= _k("near_r"):
			n += 1
	return n


## The first time the patrollers walk (the call to arms, the dusk): each takes a stretch, the nearest of n evenly spaced centres round the loop.
func _spread_the_fresh(entries: Array) -> void:
	var fresh: Array = []
	for e in entries:
		if bool(e.s.fresh):
			fresh.append(e)
	if fresh.is_empty():
		return
	var n := entries.size()
	var centres: Array = []
	for j in n:
		centres.append((float(j) + 0.5) / float(n))
	# (the ones already walking keep their stretch: take the centres nearest to them off the list first)
	for e in entries:
		if bool(e.s.fresh) or centres.is_empty():
			continue
		var at := Vector2(e.p.x, e.p.y)
		var bj := 0
		var bd := INF
		for j in centres.size():
			var d: float = (_pts[_index_at(float(centres[j]))] as Vector2).distance_to(at)
			if d < bd:
				bd = d
				bj = j
		centres.remove_at(bj)
	for e in fresh:
		if centres.is_empty():
			e.s.fresh = false
			continue
		var at := Vector2(e.p.x, e.p.y)
		var bj := 0
		var bd := INF
		for j in centres.size():
			var d: float = (_pts[_index_at(float(centres[j]))] as Vector2).distance_to(at)
			if d < bd:
				bd = d
				bj = j
		e.s.i = _index_at(float(centres[bj]))
		e.s.fresh = false
		centres.remove_at(bj)


## The walkers keep apart: each speeds up if it has room ahead and slows if it is close behind the one ahead (the holders, standing, are in the ring too).
func _space_the_walkers(entries: Array) -> void:
	var ring: Array = []    # [arc, entry or null (a holder), walker?]
	for e in entries:
		var s: Dictionary = e.s
		var mode := String(s.mode)
		var at := Vector2(e.p.x, e.p.y)
		var k: int = int(s.tgt) if (mode == "go" or mode == "hold") else nearest(at)
		ring.append({"a": float(_cum[k]), "e": e, "walker": mode == "walk" or mode == "pause"})
	if ring.size() < 2:
		for e in entries:
			e.s.pace = 1.0
		return
	ring.sort_custom(func(x, y): return float(x.a) < float(y.a))
	for idx in ring.size():
		var cur = ring[idx]
		if not bool(cur.walker):
			continue
		var ahead = ring[(idx + 1) % ring.size()]
		var behind = ring[(idx - 1 + ring.size()) % ring.size()]
		var gap_ahead := fposmod(float(ahead.a) - float(cur.a), _len)
		var gap_behind := fposmod(float(cur.a) - float(behind.a), _len)
		if ring.size() == 2:
			gap_behind = _len - gap_ahead
		var total := gap_ahead + gap_behind
		var f := 1.0
		if total > 0.01:
			f = 1.0 + _k("gap_swing") * (gap_ahead - gap_behind) / total
		cur.e.s.pace = clampf(f, 0.7, 1.35)


# --------------------------------------------------------------------- views --

## What the patrol is doing, for the probe and the tests: [{"id", "mode", "at" (Vector2), "tgt" (index or -1), "i" (index of the point they walk to), "pressure" (at their stand)}].
func snapshot() -> Array:
	var out: Array = []
	for p in sim.people:
		var s = _st.get(String(p.id))
		if s == null or _t - float(s.seen) > 1.0:
			continue
		var k: int = int(s.tgt)
		out.append({"id": String(p.id), "mode": String(s.mode), "at": Vector2(p.x, p.y), "tgt": k, "i": int(s.i), "pressure": float(_press[k]) if k >= 0 and k < _press.size() else 0.0})
	return out


## The pressure at each point of the loop as the last look had it.
func pressure() -> Array:
	return _press
