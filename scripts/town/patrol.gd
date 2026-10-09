## PATROL (PH3, polished in PH4: "people need to be moved around constantly when defending"): the crew who hold no fixed post walk the fence line by themselves and go where the dead press.
##
## WHO. Every person of the town is on PATROL unless somebody has given them a post (`jobs.PATROL`, `jobs.on_patrol`: the default; the Duty roster says "Patrol"). A person assigned
## to a post (a tower, the gate's, a stretch of fence: the player's choice, the radio's, the avatar's E) holds it exactly as before; the avatar is not on patrol at all. A person with
## another job (builder, scavenger, radio desk, medic) keeps it by day: it is only while the posts are manned (`sim.posts_manned()`: the call to arms, an attack night, a day under
## attack) that the colony sends them to their post, and so to the patrol here (`TownRules._post_duty_goal` asks `goal_for`). An order (scavenge, hold here, mend), a treatment, a bed
## and a trip all come before it in `Sim._goal_for`: the person leaves the patrol for them and, when they are done, is back on the walk from the nearest point of the loop.
##
## THE LOOP. The ring of tiles two inside the lot's border (about a tile and a half behind the fence's inner face; the posts are on the ring before it), clockwise, taken from the
## base's layout (`perimeter.layout.inner`): a point every `spacing` tiles and a point at each corner, a tile a step in or out where the ring is blocked (a tree, a prop, the house).
## The lot is a rectangle in every town the generator makes (`Rect2i`: `tools/patrol_night.gd --case=audit` checks the candidates of seeds 1 to 64), and the loop is the PLANNED ring,
## not what stands: with the fence half built (the first night) they still walk two tiles inside the border, never outside it. A tile of the ring that is shut (a tree, a prop) or is the
## floor of the house (a small lot: the house takes most of the yard) is stepped round on the side of the fence first, then inward, so that the loop of a 14 by 13 yard runs round the house
## and not through it (the audit found six links of twelve cut by the house there). The points are also the STAND points where a patroller
## holds and shoots. Nothing here leaves the lot: a patroller who finds themselves outside it (a rescue run, an order) walks back to the nearest point of the loop (`back`).
##
## THE WALK. Calm (`pace`, a share of the person's walking speed), always clockwise. Each takes a stretch: the first time they are on patrol the patrollers are spread over the loop
## (each to the nearest of n evenly spaced centres), and a small controller on the gaps (the one ahead and the one behind, the holders count as standing still) speeds up the one with
## room ahead and slows the one close behind another, so that they keep apart. At a corner they pause and look from one fence to the next; now and then at other points they stop and
## look over the fence (the goal's `face`: the pose and the eased turn are the pawn motion's own). Nothing here consumes `sim.rng`.
##
## KEEPING APART (PH4). Every rules step each patroller who walks looks a step or two ahead (`avoid_r`): someone standing there (a holder, one looking, a tower's or the gate's, the
## avatar) is gone round on the side with more room, someone coming the other way keeps to their right (so the one against the clockwise walk takes the outer lane and the walkers
## the inner), someone ahead and slower is not overtaken (the walker slows behind them), and two who are on top of each other are pushed apart. A point of the walk or a stand
## point that somebody stands on is taken a step to the side (`_spot`). Nobody is moved through a fence or a wall: the step is made only onto open ground inside the lot.
##
## THE PRESSURE. Every `replan_s` seconds each stand point gets a number FOR EACH PATROLLER (PH4): the dead that this person's gun reaches from there (a clawing one 1.0, a breaching one
## 2.5, one coming at the fence 0.45, one hunting a person 0.5; a brute counts 3.5 times, a runner 1.3; full strength within 0.85 of the reach of a dead one that is clawing, fading out
## at the reach; for one still coming the pull reaches to `reach_pre` times the reach: they take their place before it arrives) plus the sections near it that are worn (up to `w_hurt`
## x the share lost) or DOWN (`w_down`: a gap in the fence, and the defenders gather behind it), but only while some of the dead are near that section. A person whose guns are the butt
## (the stores are empty) or a pike has no reach, so nothing pulls them: they go on walking. Where the dead stand is where the pressure is; a section that was hurt last night and is
## quiet pulls nobody.
##
## THE REACTION. The free patrollers (not on a point) are sent one at a time, each pair of (point, patroller) scored `pressure / (1 + near_pen x patrollers already within near_r) -
## dist_cost x tiles`: the heaviest place first, a second one only where the pressure is heavy enough to share, the nearest patroller of two equal ones. A patroller who is sent walks
## at the person's full pace (`go`), stops at the point (`hold`), faces the fence and shoots as the colony's crew shoots (`Sim._combat`: only a person standing still fires, the ammo
## and the aim are the colony's). ENGAGING (PH4): every `look_s` seconds each patroller, whatever they are doing but going back inside, looks for the nearest target in reach
## (`Sim._find_target`); a dead one that is clawing, inside the lot, or within `engage_frac` of the reach makes them stop where they are for `engage_s` seconds and shoot: the first shot is
## the aim's own ease (a tenth of a second or two) after the dead one comes in range. A far one is not worth a stop: they keep walking (or going) and the next point is nearer. Nobody
## stops while they reload (the reload goes on as they walk).
## HYSTERESIS. A patroller sent stays at least `min_stay` seconds after arriving and until the pressure at the point has fallen below `keep_min`; it moves to another point only if that
## one is worth `switch_ratio` times as much, and a point needs `start_min` to call anybody (above `keep_min`). Two patrollers never take points less than `min_gap` apart.
##
## ORDERS AND CARE (PH4). Everything that comes before the post in `Sim._goal_for` takes the person off the patrol (a search or hold order, a treatment, a bed, a trip, a repair) and the walk
## begins again from the nearest point when it lets them go. The avatar is never on it. Somebody a medic is coming to treat (`Medical.jobs`) waits where they stand and shoots from there;
## somebody under `hurt_hp` is sent to no place. "To the walls" by day (the wheel) stands a patroller at their place of the loop under an order, which the patrol lets go when the posts are
## manned, and while they are manned it is the walk again (`Sim.order_post`).
##
## SAVE. Nothing: the state is the walk, rebuilt in a moment on a load. `post_pos` answers the colony's questions about a person's post (the readiness line, the fields of fire).
extends RefCounted

const KNOBS := {
	"pace": 0.5, "pace_go": 1.0, "pace_back": 0.9, "spacing": 3.0, "replan_s": 0.4,
	"min_stay": 2.0, "start_min": 1.4, "keep_min": 0.6, "near_pen": 1.5, "near_r": 6.0, "min_gap": 2.2, "switch_ratio": 1.7, "dist_cost": 0.06,
	"dead_r": 13.0, "full_r": 5.0, "w_attack": 1.0, "w_approach": 0.45, "w_breach": 2.5, "w_chase": 0.5, "w_brute": 3.5, "w_runner": 1.3,
	"w_down": 5.0, "w_hurt": 5.0, "sec_r": 7.0, "active_r": 22.0, "engage_s": 1.0,
	"pause_min": 1.6, "pause_max": 3.2, "look_every": 7, "arrive": 0.9, "gap_swing": 0.5,
	"look_s": 0.1, "engage_frac": 0.8, "reach_pre": 1.35, "claw_full": 0.85,
	"avoid_r": 2.0, "avoid_side": 1.7, "avoid_lat": 0.85, "avoid_body": 0.5, "hurt_hp": 40.0,
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
var usec_steer := 0
var calls_steer := 0

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
## Person id -> {"mode", "i", "tgt", "since", "arrive", "until", "mid", "face", "pace", "slow", "seen", "fresh", "paused_at", "n", "eng_until", "look_t", "spot_i", "spot"}.
var _st := {}
## The pressure at each point as the most pressed patroller has it (for the views and the probes), and the top of it.
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
	var hs = sim.get("houses")
	var open := func(tx: int, ty: int) -> bool:
		# (open ground that is not the floor of a building: in a small lot the house takes most of the yard and a step "in" from the ring is a step through its wall)
		return _tile_open(tx, ty) and (hs == null or int(hs.house_at(float(tx) + 0.5, float(ty) + 0.5)) < 0)
	var made := make_loop(plot, inner, open, _k("spacing"))
	if made.is_empty():
		return
	_pts = made.pts
	_side = made.side
	_corner = made.corner
	var acc := 0.0
	for i in _pts.size():
		_cum.append(acc)
		acc += (_pts[i] as Vector2).distance_to(_pts[(i + 1) % _pts.size()])
	_len = acc
	_press.resize(_pts.size())
	_press.fill(0.0)


## The loop of a lot, clockwise from the top left, as {"pts": [Vector2], "side": ["N"...], "corner": [bool]} ({} when the ring is shut all round): `open` says whether a tile is open
## ground (the tools call it with a grid of their own: `tools/patrol_night.gd --case=audit`).
static func make_loop(plot: Rect2i, inner: Rect2i, open: Callable, spacing: float) -> Dictionary:
	var lot := Rect2(plot)
	var r: Rect2i = inner.grow(-1) if inner.size.x >= 6 and inner.size.y >= 6 else inner
	var dense: Array = []
	# the ring of tile centres, clockwise from the top left: the north row, the east column, the south row, the west column
	var px0 := r.position.x
	var py0 := r.position.y
	var px1 := r.end.x - 1
	var py1 := r.end.y - 1
	for x in range(px0, px1 + 1):
		_add_dense(dense, lot, open, x, py0, "N", x == px0 or x == px1)
	for y in range(py0 + 1, py1 + 1):
		_add_dense(dense, lot, open, px1, y, "E", y == py1)
	for x in range(px1 - 1, px0 - 1, -1):
		_add_dense(dense, lot, open, x, py1, "S", x == px0)
	for y in range(py1 - 1, py0, -1):
		_add_dense(dense, lot, open, px0, y, "W", false)
	if dense.size() < 4:
		return {}
	# thin it: a point every `spacing` tiles, every corner, and none within 2 tiles of a corner that is not one
	var kept: Array = []
	for e in dense:
		if bool(e.corner):
			kept.append(e)
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
	if all.is_empty():
		return {}
	var out := {"pts": [], "side": [], "corner": []}
	for e in all:
		out.pts.append(e.p)
		out.side.append(String(e.side))
		out.corner.append(bool(e.corner))
	return out


## A tile centre of the ring: the tile itself if it is open, else a step out (towards the fence), a step in or two in (a tree, a prop, the house's corner); nothing if all are shut. The
## step out comes first: in a small lot the house is on the other side (PH4).
static func _add_dense(dense: Array, lot: Rect2, open: Callable, tx: int, ty: int, side: String, corner: bool) -> void:
	var inward: Vector2i = INWARD[side]
	for t in [Vector2i(tx, ty), Vector2i(tx, ty) - inward, Vector2i(tx, ty) + inward, Vector2i(tx, ty) + inward * 2]:
		if bool(open.call(t.x, t.y)) and lot.has_point(Vector2(float(t.x) + 0.5, float(t.y) + 0.5)):
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
		s = {"mode": "walk", "i": nearest(Vector2(p.x, p.y)), "tgt": -1, "since": _t, "arrive": -1.0, "until": 0.0, "mid": 0.0, "face": "", "pace": 1.0, "slow": 1.0, "seen": _t, "fresh": true,
			"paused_at": -1, "n": 0, "eng_until": 0.0, "look_t": -9.0, "spot_i": -1, "spot": Vector2.ZERO}
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
	_look(p, s)
	var mode := String(s.mode)
	var md = sim.get("medical")
	if md != null and md.has_method("_job_of_patient") and md._job_of_patient(p) != null:
		# somebody is coming to bandage or treat them (the colony's own medic: `Medical.jobs`): they wait for them where they stand, and shoot if there is something to shoot
		return {"x": p.x, "y": p.y, "face": "", "what": "Waiting for the medic", "pace": 1.0}
	if _t < float(s.eng_until) and mode != "hold":
		# a dead one in reach: stand where they are and shoot (the walk, the pause and the way to a point wait; their clocks go on), a step to the side if somebody stands on that spot
		var stand := _clear_of_others(p, s, pos)
		return {"x": stand.x, "y": stand.y, "face": "", "what": "Holding the fence", "pace": 0.8}
	match mode:
		"go", "hold":
			return _goal_stand(p, s, pos)
		"pause":
			if _t >= float(s.until):
				s.mode = "walk"
			else:
				return {"x": p.x, "y": p.y, "face": String(s.face) if _t < float(s.mid) else String(s.get("face2", s.face)), "what": "Keeping watch", "pace": 1.0}
	return _goal_walk(p, s, pos)


## The look for a target (every `look_s` seconds, so the first shot waits for the aim only): the nearest dead one in reach that is worth a stop.
func _look(p, s: Dictionary) -> void:
	if _t - float(s.look_t) < _k("look_s"):
		return
	s.look_t = _t
	if p.reloading > 0.0:
		return
	var tz = sim._find_target(p)
	if tz == null:
		return
	var zp := Vector2(tz.x, tz.y)
	var st := String(tz.state)
	var reach: float = sim.reach_of(sim.gun_of(p), p)
	if _lot.has_point(zp) or st == "attack" or st == "breach" or Vector2(p.x, p.y).distance_to(zp) <= _k("engage_frac") * reach:
		s.eng_until = _t + _k("engage_s")


## Whether somebody who is not `p` stands (does not walk) within `r` of `at`.
func _occupied(p, at: Vector2, r: float) -> bool:
	for q in sim.people:
		if q == p or q.dead or q.turned or q.away != null or q.downed or q.moving:
			continue
		if Vector2(q.x, q.y).distance_to(at) < r:
			return true
	return false


## Where to stop and shoot from: here, or if somebody stands (or shoots) on this very spot, the nearest open ground a body's width off (kept while the stop lasts).
func _clear_of_others(p, s: Dictionary, pos: Vector2) -> Vector2:
	if not _occupied(p, pos, 0.95):
		s.erase("eng_spot")
		return pos
	var held = s.get("eng_spot")
	if held != null and not _occupied(p, held, 0.95):
		return held
	var k := nearest(pos)
	var inward := Vector2(INWARD[_side[k]])
	var along := Vector2(-inward.y, inward.x)
	for off in [inward, along, -along, -inward, inward + along, inward - along, -inward + along, -inward - along]:
		var c: Vector2 = pos + (off as Vector2).normalized() * 1.15
		if _lot.has_point(c) and _tile_open(floori(c.x), floori(c.y)) and not _occupied(p, c, 0.95):
			s["eng_spot"] = c
			return c
	return pos


## The place to stand or walk to for point `i`: the point itself, else a step in, out or along the fence if somebody stands on it (a holder, one looking, a tower's or the gate's, the
## avatar). The choice is kept while it is free, so the goal does not flicker between two places.
func _spot(p, s: Dictionary, i: int) -> Vector2:
	var at: Vector2 = _pts[i]
	if int(s.spot_i) == i and (not _occupied(p, s.spot, 0.8) or Vector2(p.x, p.y).distance_to(s.spot) < 0.7):
		return s.spot    # (kept while it is free, and kept when we are on it already: somebody who comes to stand by us, a medic at a bandage, does not move us)
	var inward := Vector2(INWARD[_side[i]])
	var along := Vector2(-inward.y, inward.x)
	var pick := at
	for c in [at, at + inward * 1.1, at - inward * 0.9, at + along * 1.1, at - along * 1.1, at + inward * 1.6]:
		if _lot.has_point(c) and _tile_open(floori(c.x), floori(c.y)) and not _occupied(p, c, 1.0):
			pick = c
			break
	s.spot_i = i
	s.spot = pick
	return pick


func _goal_stand(p, s: Dictionary, pos: Vector2) -> Dictionary:
	var k: int = clampi(int(s.tgt), 0, _pts.size() - 1)
	var at: Vector2 = _spot(p, s, k)
	var side := String(SIDE_NAME.get(_side[k], "north"))
	if pos.distance_to(at) < 0.35:
		if String(s.mode) != "hold":
			s.mode = "hold"
			s.arrive = _t
		return {"x": at.x, "y": at.y, "face": String(_side[k]), "what": "Holding the %s fence" % side, "pace": 1.0}
	return {"x": at.x, "y": at.y, "face": "", "what": "Going to the %s fence" % side, "pace": _k("pace_go") * float(s.slow)}


func _goal_walk(p, s: Dictionary, pos: Vector2) -> Dictionary:
	var m := _pts.size()
	var i: int = int(s.i) % m
	for _skip in m:
		# (a point that has since been built over, a prop put on it: the walk goes on to the next)
		if _tile_open(floori(_pts[i].x), floori(_pts[i].y)):
			break
		i = (i + 1) % m
	var at: Vector2 = _spot(p, s, i)
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
		at = _spot(p, s, i)
	return {"x": at.x, "y": at.y, "face": "", "what": "On patrol", "pace": _k("pace") * float(s.pace) * float(s.slow)}


# ------------------------------------------------------------------- the step --

func update(dt: float) -> void:
	_t += dt
	_tick -= dt
	var ready := _ensure()
	var manned: bool = ready and sim.posts_manned()
	if manned and not _st.is_empty():
		var t1 := Time.get_ticks_usec()
		_steer(dt)
		usec_steer += Time.get_ticks_usec() - t1
		calls_steer += 1
	if _tick > 0.0:
		return
	_read_knobs()
	_tick = _k("replan_s")
	if not manned:
		if not _st.is_empty():
			_st.clear()    # (the posts stand down: the next call to arms begins afresh, spread over the loop)
		return
	_drop_day_posts()
	var t0 := Time.get_ticks_usec()
	_replan()
	usec_replan += Time.get_ticks_usec() - t0
	calls_replan += 1


## "To the walls" by day (the wheel) stands a patroller at their place on the loop under an order; once the posts are manned that order is the patrol's own work, so it is let go: they walk
## the loop from where they stand and are not held at the one spot all night.
func _drop_day_posts() -> void:
	for p in sim.people:
		if p.player or p.order == null or float(p.order.z) < 0.5 or not sim.jobs.on_patrol(p):
			continue
		p.order = null
		p.drafted = false
		p.goal_key = ""


## Who is on patrol right now: [{"p", "s"}] (seen by `goal_for` within the last second; a person on a trip, a case or an order is not).
func _entries() -> Array:
	var out: Array = []
	for p in sim.people:
		var s = _st.get(String(p.id))
		if s != null and _t - float(s.seen) < 1.0 and not p.dead and not p.turned and not p.downed and p.away == null:
			out.append({"p": p, "s": s, "press": []})
	return out


func _is_eng(s: Dictionary) -> bool:
	return _t < float(s.eng_until)


# ---------------------------------------------------------------------- steering --

## The way a person is walking (a unit vector; zero if they stand): towards the next waypoint of their path.
static func _heading(q) -> Vector2:
	if not q.moving:
		return Vector2.ZERO
	if q.path_i < q.path.size():
		var d := Vector2(q.path[q.path_i]) - Vector2(q.x, q.y)
		if d.length() > 0.001:
			return d.normalized()
	return Vector2.ZERO


## The people who walk the patrol keep apart (see the header): a step to the side round whoever stands or comes the other way, a slower pace behind whoever is ahead and slower, a push
## off whoever they are on top of. Done every step after the colony's, onto open ground inside the lot only.
func _steer(dt: float) -> void:
	var avoid_r := _k("avoid_r")
	var lat_max := _k("avoid_lat")
	var body := _k("avoid_body")
	var all: Array = []
	for q in sim.people:
		if not (q.dead or q.turned) and q.away == null and not q.downed:
			all.append(q)
	for p in all:
		var s = _st.get(String(p.id))
		if s == null or _t - float(s.seen) > 0.5:
			continue
		s.slow = 1.0
		var mode := String(s.mode)
		if mode == "hold" or mode == "pause" or _is_eng(s) or not p.moving:
			continue
		var pos := Vector2(p.x, p.y)
		var h := _heading(p)
		if h == Vector2.ZERO:
			continue
		var right := Vector2(-h.y, h.x)
		var push := Vector2.ZERO
		var slow := 1.0
		for q in all:
			if q == p:
				continue
			var rel := Vector2(q.x, q.y) - pos
			var d := rel.length()
			if d > avoid_r:
				continue
			if d < body:
				# on top of each other: apart, SIDEWAYS (the one who walks moves, a standing one is not pushed; never back along the way: in a doorway that would hold them there for ever)
				var away := (-rel / d) if d > 0.001 else right
				var side_away := away - h * away.dot(h)
				side_away = side_away.normalized() if side_away.length() > 0.2 else right * (1.0 if away.dot(right) >= 0.0 else -1.0)
				push += side_away * (body - d) / body * 1.6
				continue
			var ahead := rel.dot(h)
			if ahead < 0.1:
				continue
			var lat := rel.dot(right)
			if absf(lat) > lat_max:
				continue
			var qh := _heading(q)
			var closing := qh.dot(h)
			var fall := 1.0 - ahead / avoid_r
			if closing > 0.3:
				# the same way, ahead: no overtaking, they slow behind
				slow = minf(slow, clampf((ahead - 0.8) / 1.1, 0.25, 1.0))
			else:
				# standing there or coming the other way: a step to the side, far enough to leave a body's width between them (`avoid_lat`); face to face (nobody to a side) both keep to their
				# right, so the one who walks against the clockwise walk takes the outer lane and the walker the inner
				var sgn := 1.0
				if absf(lat) >= 0.15:
					sgn = -signf(lat)    # (away from the side they are on: for two who come at each other that is each to a side of its own)
				push += right * sgn * clampf(lat_max - absf(lat), 0.0, 1.6) * (0.4 + 0.6 * fall) * _k("avoid_side")
				slow = minf(slow, clampf((ahead - 0.35) / 0.9, 0.4, 1.0))
		s.slow = slow
		if push.length() > 0.01:
			var step := push.limit_length(_k("avoid_side") * 1.4) * dt
			var to := pos + step
			if _lot.has_point(to) and _tile_open(floori(to.x), floori(to.y)) and _tile_open(floori(to.x), floori(pos.y)) and _tile_open(floori(pos.x), floori(to.y)):
				var clear := true
				for q in all:
					if q != p and Vector2(q.x, q.y).distance_to(to) < body * 0.8 and Vector2(q.x, q.y).distance_to(to) < Vector2(q.x, q.y).distance_to(pos):
						clear = false
						break
				if clear:
					p.x = to.x
					p.y = to.y


# ---------------------------------------------------------------------- pressure --

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


## The pressure at each point of the loop FOR EACH PATROLLER (`e.press`: what this person's gun reaches from there, see the header) and, as the most pressed of them has it, `_press`.
func _compute_pressure(entries: Array) -> void:
	var n := _pts.size()
	_press.resize(n)
	_press.fill(0.0)
	_top = 0.0
	var far := _lot.grow(_k("dead_r") + 14.0)
	var hostile: Array = []    # [position, weight, clawing]
	for z in sim.zombies:
		var w := _weight(z)
		if w <= 0.0:
			continue
		var zp := Vector2(z.x, z.y)
		if not far.has_point(zp):
			continue
		var st := String(z.state)
		hostile.append([zp, w, st == "attack" or st == "breach"])
	if hostile.is_empty():
		for e in entries:
			e.press = _zeros(n)
		return
	# the sections: a worn one pulls, a fallen one pulls hard, but only while some of the dead are near it
	var active_r := _k("active_r")
	var secs: Array = []    # [rect, weight]
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
		if near:
			secs.append([_section_rect(s), _k("w_down") if down else _k("w_hurt") * lost])
	# what a tower adds to the reach at each point
	var bonus: Array = []
	for k in n:
		bonus.append(float(sim.build.reach_bonus_at(_pts[k])))
	var pre := _k("reach_pre")
	var claw_full := _k("claw_full")
	for e in entries:
		var base_reach: float = sim.reach_at(sim.gun_of(e.p), null)
		var arr := _zeros(n)
		# (somebody badly hurt is sent nowhere: they walk the loop and the medic comes to them)
		if base_reach >= 2.5 and float(e.p.hp) >= _k("hurt_hp"):
			for k in n:
				var reach: float = base_reach + float(bonus[k])
				var v := 0.0
				var at: Vector2 = _pts[k]
				for h in hostile:
					var d: float = at.distance_to(h[0])
					# (one at the fence must be shot from here; one still coming pulls a little before it is in reach, by a few tiles at the most)
					var full: float = reach * (claw_full if bool(h[2]) else 0.9)
					var zero: float = reach if bool(h[2]) else minf(reach * pre, reach + 5.0)
					if d < zero:
						v += float(h[1]) * clampf((zero - d) / maxf(zero - full, 0.1), 0.0, 1.0)
				for sc in secs:
					var d2 := _dist_rect(at, sc[0])
					var near_r := reach * 0.9
					if d2 < near_r:
						v += float(sc[1]) * clampf((near_r - d2) / maxf(near_r * 0.5, 0.1), 0.0, 1.0)
				arr[k] = v
		e.press = arr
		for k in n:
			_press[k] = maxf(float(_press[k]), float(arr[k]))
	for v in _press:
		_top = maxf(_top, float(v))


func _zeros(n: int) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(0.0)
	return a


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
	_compute_pressure(entries)
	var m := _pts.size()
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
				keep = float(e.press[k]) >= _k("keep_min")
			elif stayed < 0.0 and _t - float(s.since) >= 1.5:
				keep = float(e.press[k]) >= _k("keep_min")
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
		var here: float = float(e.press[k]) / (1.0 + _k("near_pen") * float(_count_near(k, others)))
		var best := 0.0
		for j in m:
			if _too_close(j, others):
				continue
			var worth: float = float(e.press[j]) / (1.0 + _k("near_pen") * float(_count_near(j, others)))
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
			if _too_close(k, assigned):
				continue
			var crowd: float = 1.0 + _k("near_pen") * float(_count_near(k, assigned))
			for e in free:
				var worth: float = float(e.press[k]) / crowd
				if worth < _k("start_min"):
					continue
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
		ring.append({"a": float(_cum[k]), "e": e, "walker": (mode == "walk" or mode == "pause") and not _is_eng(s)})
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

## What the patrol is doing, for the probe and the tests: [{"id", "mode" ("engaged" when they stand shooting off their walk or their way), "at" (Vector2), "tgt" (index or -1), "i" (index of the
## point they walk to), "pressure" (at their stand, for them)}].
func snapshot() -> Array:
	var out: Array = []
	for p in sim.people:
		var s = _st.get(String(p.id))
		if s == null or _t - float(s.seen) > 1.0:
			continue
		var k: int = int(s.tgt)
		var mode := String(s.mode)
		if _is_eng(s) and mode != "hold" and mode != "back":
			mode = "engaged"
		out.append({"id": String(p.id), "mode": mode, "at": Vector2(p.x, p.y), "tgt": k, "i": int(s.i), "pressure": float(_press[k]) if k >= 0 and k < _press.size() else 0.0})
	return out


## The pressure at each point of the loop as the last look had it (the most pressed patroller's).
func pressure() -> Array:
	return _press
