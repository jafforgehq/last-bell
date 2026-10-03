## The squad of a played place (round 17, slice 1): what the people who came with the player do by themselves. Everyone who
## came follows the player unless they have been asked something else over the radio (`RaidRun.request`, which goes through
## `sim.radio.request`: willingness, trust, the delay), and the radio hands the stance over when it takes effect (`applied`).
## `RaidSim._goal_for` asks `goal_for` for every person with a stance; nothing here moves a person itself: it says where they
## should be and the colony's own walking (`Sim._update_person`, the pathfinder, `radio.speed_of`) does the rest.
##
## THE STANCES. follow (the default): stay within FOLLOW_R tiles of the player, at a slot of a formation behind them, along the
## way they walked (the heading comes from the trail the player leaves, not from the mouse), the followers spread in a fan, a
## place of their own each, in the order of the squad. A follower who is within FOLLOW_R and not on top of the player
## (FOLLOW_MIN) does not move at all; one who is outside that goes to its slot and stays when it is there, and a slot is only
## chosen again when it has moved RETARGET tiles from the one being walked to (hysteresis: no jitter). cover: COVER_BACK
## tiles behind the player's aim (the aim smoothed, so that a flick of the mouse does not send them running), side by side
## with the other covers; a cover is content anywhere COVER_NEAR to COVER_FAR from the player within COVER_CONE of behind the aim.
## hold: the spot in `stance_at`. search: the container in `stance_at` (`RaidRun.container_at`), where they search it, then they
## follow again. back: the exit rectangle, each at a place of their own, and wait there.
## IN EVERY STANCE a person with a target in sight and in reach STOPS where they stand and fires (the rules' own combat
## refuses to fire on the move), and goes on GRACE seconds after the last one was in sight. A search stops while they have one.
## A stance a person is given while they search ends the search.
##
## Only with a player (`sim.player_id != ""` in the place): with none, the squad is the old squad (orders only).
extends RefCounted

## How near the player a follower is content to be (tiles), and how close they may stand before they step aside.
const FOLLOW_R := 2.2
const FOLLOW_MIN := 0.8
## The formation: the slots are SLOT_R behind the player (every other one SLOT_STAGGER further), spread in a fan SLOT_FAN
## radians between neighbours (at most FAN_MAX in all).
const SLOT_R := 1.5
const SLOT_STAGGER := 0.5
const SLOT_FAN := 0.95
const FAN_MAX := 2.0
## A slot is walked to as it was chosen unless it has moved this far (tiles).
const RETARGET := 0.9
## A goal is reached this close (tiles).
const ARRIVE := 0.12
## The cover: where they stand and what they are content with.
const COVER_BACK := 4.5
const COVER_MIN := 3.0
const COVER_NEAR := 3.2
const COVER_FAR := 5.8
const COVER_CONE := 1.05
const COVER_APART := 0.3
## How fast the aim the cover goes by follows the mouse (a share of the way a second).
const AIM_EASE := 2.5
## An aim whose dot product with the old one is under this (turned about 162 degrees or more) is taken as it is: the easing
## cannot turn a vector exactly opposite to the one it follows.
const AIM_FLIP := -0.95
## The trail the player leaves: a point every TRAIL_STEP tiles, TRAIL_KEEP of them, the heading is the way from the point
## HEADING_BACK tiles back along it.
const TRAIL_STEP := 0.4
const TRAIL_KEEP := 40
const HEADING_BACK := 3.0
## How long after a target was last in sight a person goes on, and how often a person looks (seconds).
const GRACE := 1.0
const POLL := 0.2
## How far apart the people waiting at the exit stand.
const EXIT_SPREAD := 0.7
## The directions a slot is tried in when the first is a wall (radians off the first).
const ROTS := [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, PI]

var run
var _trail: Array = []
var _heading := Vector2.RIGHT
var _aim := Vector2.RIGHT
var _leader_id := ""
## Person id to the point they are walking to now (absent: at rest), the last stance seen of them, when a target was last in
## sight of them (the run's `elapsed`), the seconds until they next look, and the container a search began on.
var _goal := {}
var _stance_seen := {}
var _seen_t := {}
var _poll := {}
var _search_c := {}


func _init(the_run) -> void:
	run = the_run


## Whether the squad is led by a player now (else it is the old squad, orders only).
func active() -> bool:
	return String(run.sim.player_id) != "" and run.avatar() != null


# ------------------------------------------------------------------ the step --

## Called each step of the run before the people move: the player's trail, the default stance, who sees a target now, a search
## that is over.
func step(dt: float) -> void:
	if not active():
		return
	var lead = run.avatar()
	_track(lead, dt)
	for p in run.squad:
		if p == lead:
			continue
		var id := String(p.id)
		if p.dead or p.downed:
			_goal.erase(id)
			_seen_t.erase(id)
			_search_c.erase(id)
			continue
		if p.order == null and String(p.stance) == "" and run.phase == "play" and not run.sim.morale.breakdown(p):
			run.sim.radio.set_stance(p, "follow")
		if String(_stance_seen.get(id, "")) != String(p.stance):
			_stance_seen[id] = String(p.stance)
			_goal.erase(id)
			_search_c.erase(id)
		if p.order != null:
			continue
		_engage(p, dt)
		if String(p.stance) == "search":
			_search_check(p)


## The player's trail, heading and aim.
func _track(lead, dt: float) -> void:
	var at := Vector2(lead.x, lead.y)
	if String(lead.id) != _leader_id:
		_leader_id = String(lead.id)
		_trail = [at]
		_heading = _facing_dir(lead)
		_aim = _aim_dir(lead)
		return
	if _trail.is_empty() or at.distance_to(_trail[_trail.size() - 1]) >= TRAIL_STEP:
		_trail.append(at)
		while _trail.size() > TRAIL_KEEP:
			_trail.pop_front()
		_heading = _heading_from_trail(at)
	var raw := _aim_dir(lead)
	if _aim.dot(raw) < AIM_FLIP:
		# (an aim turned right round: easing between two opposite vectors goes nowhere, so the new one is taken at once)
		_aim = raw
		return
	var eased := _aim + (raw - _aim) * minf(1.0, dt * AIM_EASE)
	_aim = eased.normalized() if eased.length() > 0.2 else raw


## The way the player has been walking: from the point HEADING_BACK tiles back along the trail to where they are (the old
## heading when they have not gone that far).
func _heading_from_trail(at: Vector2) -> Vector2:
	var walked := 0.0
	var prev := at
	for i in range(_trail.size() - 1, -1, -1):
		var q: Vector2 = _trail[i]
		walked += prev.distance_to(q)
		prev = q
		if walked >= HEADING_BACK or i == 0:
			var v := at - q
			if v.length() >= 0.3:
				return v.normalized()
			break
	return _heading


## Where the player's person looks: a unit vector.
func _facing_dir(lead) -> Vector2:
	match String(lead.facing):
		"N":
			return Vector2(0.0, -1.0)
		"S":
			return Vector2(0.0, 1.0)
		"W":
			return Vector2(-1.0, 0.0)
	return Vector2(1.0, 0.0)


## Where the player aims: the mouse's point when there is one far enough, else the way they look.
func _aim_dir(lead) -> Vector2:
	var at: Vector2 = lead.input_aim
	if at != Vector2.ZERO:
		var d := at - Vector2(lead.x, lead.y)
		if d.length() > 0.3:
			return d.normalized()
	return _facing_dir(lead)


# ------------------------------------------------------------------ fighting --

## Whether this person has had a target in sight within the last GRACE seconds: they stand and fire.
func engaged(p) -> bool:
	return run.elapsed - float(_seen_t.get(String(p.id), -99.0)) < GRACE


## Every POLL seconds, looks for a target (and drops one that has gone out of sight: the rules' combat would go on shooting
## at it through a wall until it was out of reach).
func _engage(p, dt: float) -> void:
	var id := String(p.id)
	var left: float = float(_poll.get(id, 0.0)) - dt
	if left > 0.0:
		_poll[id] = left
		return
	_poll[id] = POLL
	var sim = run.sim
	var seen = null
	var tz = p.target
	if tz != null and tz.state != "dying" and tz.state != "dead":
		var from := Vector2(p.x, p.y)
		var to := Vector2(tz.x, tz.y)
		if from.distance_to(to) <= sim.reach_of(sim.gun_of(p), p) and sim.path_z.sight(sim.world.solid_z, from, to, 0.12):
			seen = tz
	if seen == null:
		p.target = null
		seen = sim._find_target(p)
	if seen != null:
		_seen_t[id] = run.elapsed


# --------------------------------------------------------------------- goals --

## What this person should do now ({"x", "y", "face", "what"}), or null when the colony's rules decide (no stance, no player).
func goal_for(p):
	if not active() or p.player or p.order != null or p.dead or p.downed:
		return null
	var stance := String(p.stance)
	if stance == "":
		return null
	var lead = run.avatar()
	if run.phase == "play" and engaged(p):
		return _stand(p, "Shooting", "")
	match stance:
		"follow":
			return _follow(p, lead)
		"cover":
			return _cover(p, lead)
		"hold":
			return _hold(p)
		"search":
			return _search(p, lead)
		"back":
			return _back(p)
	return null


func _stand(p, what: String, face: String) -> Dictionary:
	return {"x": p.x, "y": p.y, "face": face, "what": what}


func _to(at: Vector2, what: String) -> Dictionary:
	return {"x": at.x, "y": at.y, "face": "", "what": what}


func _face(p) -> String:
	return String(run.sim.facing_of(_aim.x, _aim.y, String(p.facing)))


## The people with this stance, alive and not under an order, in the squad's order (each takes a place of its own).
func _group(stance: String) -> Array:
	var out: Array = []
	for q in run.squad:
		if q.player or q.dead or q.downed or q.order != null:
			continue
		if String(q.stance) == stance:
			out.append(q)
	return out


func _follow(p, lead) -> Dictionary:
	var id := String(p.id)
	var me := Vector2(p.x, p.y)
	var pl := Vector2(lead.x, lead.y)
	var what := "Following %s" % String(lead.first)
	var goal = _goal.get(id)
	if goal != null:
		if me.distance_to(goal) <= ARRIVE:
			_goal.erase(id)
			goal = null
		else:
			var want := _slot(p, pl)
			if want.distance_to(goal) > RETARGET:
				goal = want
				_goal[id] = want
	if goal == null:
		var d := me.distance_to(pl)
		if d > FOLLOW_R or d < FOLLOW_MIN:
			goal = _slot(p, pl)
			_goal[id] = goal
		else:
			return _stand(p, what, _face(p))
	return _to(goal, what)


## The place of this follower in the formation behind the player.
func _slot(p, pl: Vector2) -> Vector2:
	var group := _group("follow")
	var n := group.size()
	var k := maxi(0, group.find(p))
	var step := minf(SLOT_FAN, FAN_MAX / float(maxi(1, n - 1))) if n > 1 else 0.0
	var angle := (float(k) - float(n - 1) * 0.5) * step
	var r := SLOT_R + (SLOT_STAGGER if k % 2 == 1 else 0.0)
	return _free_slot(pl, (-_heading).rotated(angle), r, FOLLOW_MIN + 0.1)


func _cover(p, lead) -> Dictionary:
	var id := String(p.id)
	var me := Vector2(p.x, p.y)
	var pl := Vector2(lead.x, lead.y)
	var what := "Covering %s" % String(lead.first)
	var group := _group("cover")
	var n := group.size()
	var k := maxi(0, group.find(p))
	var back := (-_aim).rotated((float(k) - float(n - 1) * 0.5) * COVER_APART)
	var goal = _goal.get(id)
	if goal != null:
		if me.distance_to(goal) <= ARRIVE:
			_goal.erase(id)
			goal = null
		else:
			var want := _free_slot(pl, back, COVER_BACK, COVER_MIN)
			if want.distance_to(goal) > RETARGET * 1.5:
				goal = want
				_goal[id] = want
	if goal == null:
		var off := me - pl
		var d := off.length()
		if d >= COVER_NEAR and d <= COVER_FAR and absf((-_aim).angle_to(off)) <= COVER_CONE:
			return _stand(p, what, _face(p))
		goal = _free_slot(pl, back, COVER_BACK, COVER_MIN)
		_goal[id] = goal
	return _to(goal, what)


func _hold(p) -> Dictionary:
	if p.stance_at == Vector2.ZERO:
		p.stance_at = Vector2(p.x, p.y)
	return _to(_open_near(p.stance_at), "Holding here")


func _search(p, lead) -> Dictionary:
	var cid := String(run.searching_of(p))
	var c: Dictionary = run.container(cid) if cid != "" else {}
	if c.is_empty():
		return _follow(p, lead)
	var at := Vector2(c.pos)
	var searching: bool = not p.moving and Vector2(p.x, p.y).distance_to(at) <= float(run.REACH)
	return _to(at, "Searching" if searching else "Going to search")


func _back(p) -> Dictionary:
	var ex: Rect2 = run.site.exit
	var i := maxi(0, run.squad.find(p))
	var at := ex.get_center() + Vector2(float(i % 3) - 1.0, float(i / 3) * 0.8) * EXIT_SPREAD
	at = _open_near(Vector2(clampf(at.x, ex.position.x + 0.3, ex.end.x - 0.3), clampf(at.y, ex.position.y + 0.3, ex.end.y - 0.3)))
	var there: bool = ex.has_point(Vector2(p.x, p.y))
	return _to(at, "Waiting at the exit" if there else "Going back")


# --------------------------------------------------------------------- search --

## A search the squad's stance began (a container found at its spot), or one that is over: the person follows again.
func _search_check(p) -> void:
	var id := String(p.id)
	var cid := String(run.searching_of(p))
	if cid != "":
		_search_c[id] = cid
		return
	if _search_c.has(id):
		_search_c.erase(id)
		run.sim.radio.set_stance(p, "follow")
		return
	var c: Dictionary = run.container_at(p.stance_at)
	if c.is_empty() or bool(c.looted) or run.searcher_of(String(c.id)) != null:
		run.sim.radio.set_stance(p, "follow")
		return
	run._searching[id] = String(c.id)
	run._helping.erase(id)
	_search_c[id] = String(c.id)


## The radio's word that a request took effect (`sim.radio.on_applied`): a stance the radio does not know ("back": the radio
## clears it and leaves the rest to the job) and the search that was asked for.
func applied(p, verb: String, at: Vector2) -> void:
	var id := String(p.id)
	_goal.erase(id)
	_search_c.erase(id)
	if verb != "search":
		run._searching.erase(id)
	run._helping.erase(id)
	if run.phase != "play":
		# (a request that was on its way when the trip turned back: they go with the rest)
		run.order_out(p)
		return
	if verb == "back":
		run.sim.radio.set_stance(p, "back")
		run.sim.events.append({"type": "stance", "who": id, "verb": verb, "stance": "back"})
	elif verb == "search":
		var c: Dictionary = run.container_at(at)
		if c.is_empty() or bool(c.looted):
			run.sim.radio.set_stance(p, "follow")
		else:
			run._searching[id] = String(c.id)
			_search_c[id] = String(c.id)


# --------------------------------------------------------------------- spots --

func _is_open(at: Vector2) -> bool:
	return not run.sim.world.is_solid(run.sim.world.solid_p, at.x, at.y)


## The point `r` tiles from `origin` toward `dir` that a person can walk to in a straight line from `origin`; when that is a
## wall, nearer (never nearer than `min_r`), then in the other directions (ROTS); and as a last resort anywhere from FOLLOW_MIN
## on. `origin` itself when there is none at all.
func _free_slot(origin: Vector2, dir: Vector2, r: float, min_r: float) -> Vector2:
	var floors: Array = [min_r]
	if min_r > FOLLOW_MIN + 0.1:
		floors.append(FOLLOW_MIN + 0.1)
	var solid: PackedByteArray = run.sim.world.solid_p
	for floor_r in floors:
		for rot in ROTS:
			var d: Vector2 = dir.rotated(float(rot))
			var rr := r
			while rr >= float(floor_r) - 0.001:
				var pt := origin + d * rr
				if _is_open(pt) and run.sim.path_p.sight(solid, origin, pt, 0.2):
					return pt
				rr -= 0.3
	return origin


## Where a person asked to hold a point would stand: the point, or the open ground nearest it, when they could walk there from
## where they are; null when they could not (the rules would walk them in a straight line through the walls).
func hold_spot(p, at: Vector2) -> Variant:
	var spot := _open_near(at)
	if not _is_open(spot):
		return null
	var sim = run.sim
	if sim.path_p.find(sim.world.solid_p, p.x, p.y, spot.x, spot.y).is_empty():
		return null
	return spot


## `at`, or the nearest open ground to it.
func _open_near(at: Vector2) -> Vector2:
	if _is_open(at):
		return at
	for r in [0.7, 1.2, 1.8, 2.5]:
		for i in 12:
			var cand := at + Vector2.from_angle(TAU * float(i) / 12.0) * float(r)
			if _is_open(cand):
				return Vector2(floorf(cand.x) + 0.5, floorf(cand.y) + 0.5)
	return at
