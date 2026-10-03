## The harness's avatar (round 19, slice 3: docs/superpowers/plans/2026-10-03-round-19.md, H3.1 to H3.3): the bot that plays the
## player's person (`AvatarBot`), the rows of what a night did (`NightStats`) and the tables made of them (`aggregate`, `table_lines`).
## The harness (tools/balance.gd, `--avatar=none|idle|bot`) and the night lab (tools/night_lab.gd) use all three; the tests are
## tests/test_avatar_bot.gd and tests/test_night_lab.gd.
##
## Nothing here draws from `sim.rng` (the bot has its own random source, the stats read and never write), so a game with the bot, with an
## idle avatar and with none play the same dice: paired runs stay paired.
extends RefCounted

const NightData := preload("res://scripts/sim/night_data.gd")

## Where an idle avatar stands: deep in the school gym (the harness's `Policy.KEEP_SPOTS[5]`; a test pins that they agree).
const SAFE_SPOT := Vector2(30.5, 55.5)
## The compound's wall sections are the ones below this id (`Lots.FIRST_SEGMENT_ID`: the walls of the streets are above it).
const COMPOUND_IDS := 100


## The wall sections of the compound a night can break: not the school's doors, not the walls of the streets.
class Sections:
	extends RefCounted

	static func compound(sim) -> Array:
		var out: Array = []
		for s in sim.segments:
			if s.kind != sim.DOOR_KIND and int(s.id) < COMPOUND_IDS:
				out.append(s)
		return out


# ========================================================================= the bot ==

## A decent player at the wall, not an aimbot: steps once per rules step before `sim.update`, and through `sim.avatar` only (the same
## hands a person has: where to walk, where the mouse is, the trigger, R, F, E, and the radio's answers). The plan's H3.1 in code:
##   WHERE. By day the gate post. From the lookout's forecast (17:00) `stand_for` the first wall the night will break on. From the bell,
##          every THINK_S, the wall with the highest `nights.section_threat` (plus CALL_BONUS for one it said it was coming to), kept
##          until another beats it by SWITCH_GAIN x + 1. It walks the people's grid (`sim.path_p`), re-pathed every second and when it has
##          not moved for STUCK_S.
##   FIGHT. A plated brute (aimed at its head), then any brute, then the dead in `breach` near a person, then the dead clawing at its
##          station, then the ones coming to it. It fires only along a clear line (`avatar.trace`), after REACT_S on a new target, standing
##          still, with the mouse AIM_JITTER radians off; it swings at what is in arm's reach; it reloads in a lull; it mends the wall it
##          holds with E when it is down or under MEND_BELOW and no dead is near.
##   HURT. Below HURT_HP (or bleeding below SAFE_HP) it goes to the nearest bed and stays until SAFE_HP and no bleeding.
##   CALLS. `going` -> coming (reinforce when away), `brute` -> coming if plated else watch, `breach` -> close (and it goes to mend),
##          `attack` -> hold, `night` -> hold; a call is read for ANSWER_S first; the rest are left to their own clocks.
class AvatarBot:
	extends RefCounted

	const THINK_S := 0.5
	const ARRIVE_R := 0.5
	const STAND_R := 1.0
	const SWITCH_GAIN := 1.5
	const HURT_HP := 45.0
	const SAFE_HP := 75.0
	const MAG_LOW := 3
	const LULL_R := 8.0
	const MEND_BELOW := 0.5
	## Radians, normal: how far off a hand puts the mouse; drawn again every JITTER_S seconds (and the line to the target is looked at then).
	const AIM_JITTER := 0.03
	const JITTER_S := 0.2
	## A new target is not fired at for this long (the eye finds it, the hand follows).
	const REACT_S := 0.25
	## A call is read for this long before it is answered (a person reads, then reaches for the button).
	const ANSWER_S := 1.0
	## Within this many tiles of a dead one the bot swings at it; it mends only with none of the dead within MEND_CLEAR of where it works.
	const MELEE_R := 1.4
	const MEND_CLEAR := 3.0
	## The dead in `breach` that count are within this many tiles of any person.
	const BREACH_R := 6.0
	## Farther than this from its station the bot is on its way and holds its fire.
	const TRAVEL_R := 4.0
	## What a wall it said it was coming to is worth in the scoring.
	const CALL_BONUS := 3.0
	## How long that lasts when the data does not say (`calls.coming_window_min`), game minutes.
	const COMING_MIN := 15.0
	const HOME_POST := "gate"
	const REPATH_S := 1.0
	const STUCK_S := 0.5
	const WAYPOINT_R := 0.3
	## The middle of a body above its feet (avatar.gd's BODY).
	const BODY := 0.3
	## E is pressed at most this often (seconds).
	const MEND_GAP_S := 2.0

	var sim
	var mode := "bot"
	## Where it is going to stand: {"seg": segment id (-1: none), "at": Vector2, "why": "call" | "brute" | "threat" | "forecast" | "home"}.
	var station: Dictionary = {}
	## Where it is walking to now (the station, a bed, the place a wall is mended from).
	var destination := Vector2.ZERO
	## A test hands in its own mender (anything with `candidates()`, `use(cand)` and `working`); else it uses what the game has (`_mender`).
	var interact_override = null
	## What it has done: calls answered, times it set to mending a wall.
	var answered := 0
	var mends := 0

	var _rng := RandomNumberGenerator.new()
	var _t := 0.0
	var _think_t := 0.0
	var _aim_t := 0.0
	var _jitter := 0.0
	var _line_ok := false
	var _path: Array = []
	var _path_i := 0
	var _path_goal := Vector2(-999.0, -999.0)
	var _path_t := 0.0
	var _stuck_t := 0.0
	var _last_pos := Vector2(-999.0, -999.0)
	var _holding := false
	var _target = null
	var _target_class := 99
	var _target_since := -10.0
	var _hurt := false
	var _seen: Dictionary = {}
	var _called: Dictionary = {}
	var _mend_t := -10.0
	var _player_id := ""

	func _init(s, mode_name := "bot") -> void:
		sim = s
		mode = mode_name
		_rng.seed = int(sim.run_seed) * 7 + 13
		if mode == "idle":
			put_at(SAFE_SPOT)

	## Puts the avatar where it stands, still (an idle avatar: the safe spot, for the rest of the game).
	func put_at(at: Vector2) -> void:
		var me = sim.avatar.player()
		if me == null:
			return
		me.x = at.x
		me.y = at.y
		me.moving = false
		me.path = []
		me.goal_key = ""

	## The one it is shooting at, or null.
	func target():
		return _target

	## Once per rules step, before `sim.update`.
	func step(dt: float) -> void:
		if mode != "bot":
			return    # (idle: hands off. Nothing is asked of the avatar and no hand moves)
		var me = sim.avatar.player()
		if me == null:
			return
		if me.dead or me.turned or me.downed or me.away != null:
			sim.avatar.set_input(Vector2.ZERO, Vector2.ZERO, false)    # (nothing in the hands of a person on the ground or on a trip)
			_target = null
			_path = []
			return
		if String(me.id) != _player_id:
			# (the first step, or a succession: a new person is played from here)
			_player_id = String(me.id)
			_path = []
			_target = null
			_hurt = false
			_think_t = 0.0
		_t += dt
		_think_t -= dt
		if _think_t <= 0.0:
			_think_t = THINK_S
			_think(me)
		_act(me, dt)

	# ------------------------------------------------------------------------ thinking --

	func _think(me) -> void:
		_answer_calls(me)
		_update_hurt(me)
		_choose_station(me)
		_pick_target(me)

	## What mends a wall for it: a hand-in (`interact_override`: a test's), the E key of round 18 (`sim.interact`) when it is in the game,
	## else the nights' own hands (`sim.nights.wall_candidates()` and `mend_wall()`). null when there is none.
	func _mender():
		if interact_override != null:
			return interact_override
		var it = sim.get("interact")
		if it != null:
			return it
		var n = sim.nights
		return n if n != null and n.has_method("wall_candidates") and n.has_method("mend_wall") else null

	func _seg(id: int):
		for s in sim.segments:
			if int(s.id) == id:
				return s
		return null

	## A dead one that is about: not falling, not gone, not going home.
	func _live(z) -> bool:
		return z.state != "dying" and z.state != "dead" and z.state != "retreat"

	## A dead one that is after the compound or a person (not a straggler wandering).
	func _hostile(z) -> bool:
		return z.state == "approach" or z.state == "attack" or z.state == "breach" or z.state == "hunt"

	# ---------------------------------------------------------------------------- calls --

	func _answer_calls(me) -> void:
		for e in sim.radio.open_calls():
			var id := int(e.id)
			if not _seen.has(id):
				_seen[id] = _t
				continue
			if _t - float(_seen[id]) < ANSWER_S:
				continue
			var option := _option_for(e)
			if option == "":
				continue    # (a fever, a card: left to the colony's own clock)
			if not sim.radio.answer(id, option):
				continue
			answered += 1
			var seg_id := int((e.data as Dictionary).get("seg", -1))
			var seg = _seg(seg_id) if seg_id >= 0 else null
			if seg == null:
				continue
			if option == "coming":
				_called[seg_id] = float(sim.clock_min) + NightData.num("calls.coming_window_min", COMING_MIN)
				_set_station({"seg": seg_id, "at": _stand(seg, me), "why": "call"})
			elif option == "close":
				_called[seg_id] = float(sim.clock_min) + NightData.num("calls.coming_window_min", COMING_MIN)
				_set_station({"seg": seg_id, "at": sim.repair_spot(seg), "why": "call"})

	## The option the plan says for this call, "" when the bot does not answer it.
	func _option_for(e: Dictionary) -> String:
		var has := {}
		for o in e.options:
			has[String(o.id)] = true
		match String(e.kind):
			"going":
				return "coming" if has.has("coming") else ("reinforce" if has.has("reinforce") else "")
			"brute":
				var plated := bool((e.data as Dictionary).get("plated", false)) or String(e.text).to_lower().contains("plated")
				if plated:
					return "coming" if has.has("coming") else ("reinforce" if has.has("reinforce") else ("watch" if has.has("watch") else ""))
				return "watch" if has.has("watch") else ""
			"breach":
				return "close" if has.has("close") else ("coming" if has.has("coming") else ("hold" if has.has("hold") else ""))
			"attack", "night":
				return "hold" if has.has("hold") else ""
		return ""

	# ----------------------------------------------------------------------------- hurt --

	func _update_hurt(me) -> void:
		if not _hurt:
			if float(me.hp) < HURT_HP or (float(me.bleeding) > 0.0 and float(me.hp) < SAFE_HP):
				_hurt = true
		elif float(me.hp) >= SAFE_HP and float(me.bleeding) <= 0.0:
			_hurt = false

	func _bed_for(pos: Vector2) -> Vector2:
		var best := pos
		var best_d := INF
		for b in sim.medical.beds:
			var d := pos.distance_to(Vector2(b.pos))
			if d < best_d:
				best_d = d
				best = Vector2(b.pos)
		return best

	# -------------------------------------------------------------------------- station --

	func _set_station(s: Dictionary) -> void:
		if not station.is_empty() and int(station.get("seg", -2)) == int(s.seg) and Vector2(station.at).distance_to(Vector2(s.at)) < 0.01 and String(station.why) == String(s.why):
			return
		station = s
		_path = []
		_holding = false

	func _stand(seg, me) -> Vector2:
		return sim.nights.stand_for(seg, me.gun)

	## By day, the gate post of the wall.
	func _home(me) -> Dictionary:
		var po: Dictionary = sim.jobs.post(HOME_POST)
		if po.is_empty() and not sim.jobs.posts().is_empty():
			po = sim.jobs.posts()[0]
		var at := Vector2(po.pos) if not po.is_empty() else Vector2(me.x, me.y)
		return {"seg": -1, "at": at, "why": "home"}

	## The lookout's forecast has been given: the first of the walls the night will break on, where a gunner covers it.
	func _forecast_station(me) -> Dictionary:
		if float(sim.hour) < float(sim.tactics.forecast_hour()):
			return {}
		if not bool(sim.tactics.forecast().get("given", false)):
			return {}
		var plan: Dictionary = sim.waves.plan_for(sim.day)
		var seg = _first_target(plan)
		if seg == null:
			return {}
		return {"seg": int(seg.id), "at": _stand(seg, me), "why": "forecast"}

	func _first_target(plan: Dictionary):
		if sim.waves.has_method("target_sections"):
			var list: Array = sim.waves.target_sections(plan, 2)
			if not list.is_empty():
				var first = list[0]
				return first if typeof(first) == TYPE_OBJECT else _seg(int(first))
		# (no rules of the targets yet: the wall whose places are nearest the main spawn point)
		var heading: Array = plan.get("heading", [])
		if heading.is_empty():
			return null
		var from: Vector2 = sim.spawns[int(heading[0])]
		var best = null
		var best_d := INF
		for s in Sections.compound(sim):
			for sl in s.slots:
				var d := from.distance_to(Vector2(sl.ax, sl.ay))
				if d < best_d:
					best_d = d
					best = s
		return best

	func _choose_station(me) -> void:
		var night: bool = sim.bell_rung or sim.phase != "day"
		if not night:
			var fc := _forecast_station(me)
			_set_station(fc if not fc.is_empty() else _home(me))
			return
		var now := float(sim.clock_min)
		for k in _called.keys():
			if now > float(_called[k]):
				_called.erase(k)
		var best = null
		var best_score := 0.0
		var scores := {}
		for seg in Sections.compound(sim):
			var sc := float(sim.nights.section_threat(seg))
			if _called.has(int(seg.id)):
				sc += CALL_BONUS
			scores[int(seg.id)] = sc
			if sc > best_score:
				best_score = sc
				best = seg
		if station.is_empty():
			_set_station(_home(me))
		var cur := int(station.get("seg", -1))
		var cur_score := float(scores.get(cur, 0.0)) if cur >= 0 else 0.0
		if best != null and int(best.id) != cur and best_score > SWITCH_GAIN * cur_score + 1.0:
			var why := "call" if _called.has(int(best.id)) else ("brute" if _brute_at(best) else "threat")
			_set_station({"seg": int(best.id), "at": _stand(best, me), "why": why})

	func _brute_at(seg) -> bool:
		for z in sim.zombies:
			if z.kind == "brute" and _live(z) and z.slot != null and z.slot.seg == seg:
				return true
		return false

	# -------------------------------------------------------------------------- targets --

	## How much this one of the dead is worth shooting now: 0 a plated brute, 1 a brute, 2 one of the breach near a person (or hunting
	## the avatar), 3 one at its station's wall, 4 one on its way there, then (what a player in reach of them would not leave be, but the
	## plan does not list) 5 one clawing at another wall and 6 one on its way to another; -1 for none of those.
	func _class_of(z, me) -> int:
		if not _live(z) or not _hostile(z):
			return -1
		if z.kind == "brute" and z.state != "hunt":
			return 0 if bool(z.get("plated")) else 1
		if z.state == "breach":
			for p in sim.people:
				if p.dead or p.turned or p.away != null:
					continue
				if Vector2(p.x, p.y).distance_to(Vector2(z.x, z.y)) <= BREACH_R:
					return 2
			return -1
		if z.state == "hunt":
			return 2 if String(z.hunt_id) == String(me.id) else -1
		var sid := int(station.get("seg", -1))
		var mine: bool = sid < 0 or (z.slot != null and int(z.slot.seg.id) == sid)
		if z.state == "attack":
			return 3 if mine else 5
		if z.state == "approach":
			return 4 if mine else 6
		return -1

	func _target_point(z) -> Vector2:
		if bool(z.get("plated")):
			return Vector2(z.x, z.y - NightData.num("plated.head", 0.62) * float(z.size))
		return Vector2(z.x, z.y - BODY)

	func _valid_target(z, me, reach: float) -> bool:
		if z == null or z.remove or not _live(z) or not sim.zombies.has(z):
			return false
		return Vector2(me.x, me.y).distance_to(Vector2(z.x, z.y - BODY)) <= reach and _class_of(z, me) >= 0

	## Keeps its target while it is a fair one; takes a better class when one comes; else the nearest of the best class.
	func _pick_target(me) -> void:
		var reach: float = float(sim.reach_of(sim.gun_of(me), me)) - 0.3
		var here := Vector2(me.x, me.y)
		var best = null
		var best_key := INF
		for z in sim.zombies:
			var c := _class_of(z, me)
			if c < 0:
				continue
			var d := here.distance_to(Vector2(z.x, z.y - BODY))
			if d > reach:
				continue
			var key := float(c) * 1000.0 + d
			if key < best_key:
				best_key = key
				best = z
		var keep: bool = _valid_target(_target, me, reach)
		if keep and (best == null or int(best_key / 1000.0) >= _target_class):
			return
		if best != _target:
			_target = best
			_target_class = int(best_key / 1000.0) if best != null else 99
			_target_since = _t
			_aim_t = 0.0

	# ------------------------------------------------------------------------- the step --

	func _act(me, dt: float) -> void:
		var pos := Vector2(me.x, me.y)
		var reach: float = float(sim.reach_of(sim.gun_of(me), me)) - 0.3
		if _target != null and not _valid_target(_target, me, reach):
			_target = null
			_target_class = 99
			_pick_target(me)
		# where to: a bed when hurt, else the wall to mend, else the station
		var mend_seg = null if _hurt else _mend_wanted(me)
		var dest: Vector2
		if _hurt:
			dest = _bed_for(pos)
		elif mend_seg != null:
			dest = sim.repair_spot(mend_seg)
		else:
			dest = Vector2(station.at) if not station.is_empty() else pos
		destination = dest
		var travelling := pos.distance_to(dest) > TRAVEL_R
		# the gun
		var fire := false
		var aim := Vector2.ZERO
		if _target != null and not _hurt:
			aim = _aim_point(me, _target, reach, dt)
			fire = not travelling and _line_ok and (_t - _target_since) >= REACT_S and float(me.reloading) <= 0.0
		if _in_arms_reach(me):
			sim.avatar.melee()
		_reload_in_a_lull(me)
		# the feet
		var move := Vector2.ZERO
		var working := _working_wall()
		if not fire and not working:
			move = _walk(me, dest, dt)
			if move == Vector2.ZERO and mend_seg != null:
				_mend(mend_seg)
		sim.avatar.set_input(move, aim, fire)

	## The point the mouse is at: the target's head (a plated brute) or body, off by the hand's jitter, held for JITTER_S; the line is
	## looked at when the jitter is drawn again.
	func _aim_point(me, z, reach: float, dt: float) -> Vector2:
		var at := _target_point(z)
		var from: Vector2 = sim.avatar.shoulder(me)
		var base := (at - from).angle()
		_aim_t -= dt
		if _aim_t <= 0.0:
			_aim_t = JITTER_S
			_jitter = _rng.randfn(0.0, AIM_JITTER)
			_line_ok = sim.avatar.trace(from, base + _jitter, reach + 0.3).z != null
		return from + Vector2.from_angle(base + _jitter) * from.distance_to(at)

	func _in_arms_reach(me) -> bool:
		var here := Vector2(me.x, me.y - 0.15)
		for z in sim.zombies:
			if _live(z) and _hostile(z) and here.distance_to(Vector2(z.x, z.y - BODY)) <= MELEE_R:
				return true
		return false

	## R when the magazine is nearly empty and none of the dead is within LULL_R.
	func _reload_in_a_lull(me) -> void:
		if float(me.reloading) > 0.0 or me.gun.get("melee", false) or int(me.mag) > MAG_LOW or int(me.mag) >= int(me.gun.get("mag", 0)):
			return
		if float(sim.stock.ammo) < float(sim.shot_cost(me)):
			return
		var here := Vector2(me.x, me.y)
		for z in sim.zombies:
			if _live(z) and _hostile(z) and here.distance_to(Vector2(z.x, z.y)) < LULL_R:
				return
		sim.avatar.reload()

	# ------------------------------------------------------------------------- mending --

	## The wall to mend now: the one it holds, when it is down or under MEND_BELOW, there is scrap, something to mend with and none of the
	## dead is within MEND_CLEAR of the place (or of the avatar), at the wall or on its way to it, and nothing else to shoot.
	func _mend_wanted(me):
		if _mender() == null:
			return null
		var sid := int(station.get("seg", -1))
		if sid < 0 or float(sim.stock.scrap) < 1.0:
			return null
		var seg = _seg(sid)
		if seg == null or seg.kind == sim.DOOR_KIND:
			return null
		if not (seg.state == 3 or float(seg.hp) < float(seg.max_hp) * MEND_BELOW):
			return null
		# (a wall the dead are at is held with the gun, not with the hammer: the place a wall is mended from is under the claws)
		if _target != null:
			return null
		var spot: Vector2 = sim.repair_spot(seg)
		var here := Vector2(me.x, me.y)
		for z in sim.zombies:
			if not _live(z):
				continue
			var zp := Vector2(z.x, z.y)
			if zp.distance_to(spot) < MEND_CLEAR or zp.distance_to(here) < MEND_CLEAR:
				return null
			if z.slot != null and z.slot.seg == seg and (z.state == "attack" or z.state == "approach"):
				return null
		return seg

	## Whether its hands are at a wall now (the session is the nights' module's, or a handed-in mender's).
	func _working_wall() -> bool:
		for m in [interact_override, sim.nights]:
			if m != null:
				var w = m.get("working")
				if typeof(w) == TYPE_STRING and String(w) == "wall":
					return true
		return false

	## E on the wall candidate of `seg`, if it is there to be used (not more than once in MEND_GAP_S).
	func _mend(seg) -> void:
		var m = _mender()
		if m == null or _t - _mend_t < MEND_GAP_S:
			return
		var list: Array = m.candidates() if m.has_method("candidates") else m.wall_candidates()
		for c in list:
			if String(c.get("kind", "")) == "wall" and String(c.get("id", "")) == str(seg.id) and bool(c.get("ok", true)):
				_mend_t = _t
				mends += 1
				if m.has_method("use"):
					m.use(c)
				else:
					m.mend_wall(int(seg.id))
				return

	# ------------------------------------------------------------------------- walking --

	## The direction to walk (unit length), zero when it is where it is going (within ARRIVE_R; it walks on again when it is more than
	## STAND_R away): along the people's grid, a path made again every REPATH_S and when it has not moved for STUCK_S.
	func _walk(me, dest: Vector2, dt: float) -> Vector2:
		var pos := Vector2(me.x, me.y)
		var d := pos.distance_to(dest)
		if _holding:
			if d <= STAND_R:
				return Vector2.ZERO
			_holding = false
		elif d <= ARRIVE_R:
			_holding = true
			_path = []
			return Vector2.ZERO
		if pos.distance_to(_last_pos) < 0.2 * sim.avatar.WALK_SPEED * dt:
			_stuck_t += dt
		else:
			_stuck_t = 0.0
		_last_pos = pos
		_path_t -= dt
		if _path.is_empty() or _path_goal.distance_to(dest) > 0.5 or _path_t <= 0.0 or _stuck_t >= STUCK_S:
			_path = sim.path_p.find(sim.world.solid_p, pos.x, pos.y, dest.x, dest.y)
			if _path.is_empty():
				_path = [dest]
			_path_i = 0
			_path_goal = dest
			_path_t = REPATH_S
			_stuck_t = 0.0
		while _path_i < _path.size() - 1 and pos.distance_to(Vector2(_path[_path_i])) < WAYPOINT_R:
			_path_i += 1
		var wp := Vector2(_path[mini(_path_i, _path.size() - 1)])
		return (wp - pos).normalized()


# ================================================================== the night's row ==

## One row for each night, from dusk to the first step of the day: what the walls lost, who fell, whether the avatar was where the
## pressure was. Read-only: `observe(dt)` once per rules step, after `sim.update`; it writes nothing into the game (but a mark on the
## events it has counted) and draws no die. Rows are plain data (numbers, text, booleans, arrays, dictionaries): they go to JSON.
class NightStats:
	extends RefCounted

	## The presence is sampled this often (rules seconds); a wall is pressed from this threat on (`Nights.contested`'s own).
	const SAMPLE_S := 0.5
	const PRESSED := 2.0
	## The readiness the HUD gives is noted at this hour of the day before the night (the lookout's word has been out for an hour).
	const READY_HOUR := 18.5
	## The mark on an event this has counted.
	const MARK := "_ns"

	var sim
	var mode := "none"
	## The nights that are over, oldest first.
	var rows: Array = []

	var _cur: Dictionary = {}
	var _closed_day := -1
	var _ready: Dictionary = {}
	var _hp: Dictionary = {}
	var _state: Dictionary = {}
	var _down: Dictionary = {}
	var _gone: Dictionary = {}
	var _brutes: Dictionary = {}
	var _plated: Dictionary = {}
	var _calls: Dictionary = {}
	var _targets: Array = []
	var _sample_t := 0.0
	var _since_start := 0.0
	var _av = null
	var _av_shots := 0
	var _av_kills := 0
	var _av_was_down := false

	func _init(s, mode_name := "none") -> void:
		sim = s
		mode = mode_name

	## The night in progress as a row (what it is so far), or the last night that ended ({} when there has been none).
	func row() -> Dictionary:
		if not _cur.is_empty():
			return _snapshot(false)
		return rows[rows.size() - 1] if not rows.is_empty() else {}

	## Once per rules step, after `sim.update`.
	func observe(dt: float) -> void:
		_count_events()
		if _cur.is_empty():
			if sim.phase == "day":
				_note_readiness()
			elif _closed_day != int(sim.day):
				_begin()
			if _cur.is_empty():
				return
		if sim.phase == "day" and int(sim.day) != int(_cur.day):
			_close(false)
			return
		_since_start += dt
		_look(dt)
		if sim.over != "":
			_close(true)

	## The game ends in the night: the row is closed as it stands.
	func finish() -> void:
		if not _cur.is_empty():
			_close(sim.over != "")

	# ------------------------------------------------------------------ the night begins --

	## 18:30 of the day: whether the community expects to hold (`tactics.readiness().holds`, the HUD's own answer), once for each day.
	func _note_readiness() -> void:
		var day := int(sim.day)
		if _ready.has(day) or float(sim.hour) < READY_HOUR:
			return
		var known: bool = sim.tactics.has_method("readiness")
		var holds := false
		if known:
			var r: Dictionary = sim.tactics.readiness(_target_ids_for(day))
			holds = bool(r.get("holds", false))
		_ready[day] = {"holds": holds, "known": known}

	func _target_ids_for(day: int) -> Array:
		if sim.waves.has_method("target_sections"):
			var out: Array = []
			for s in sim.waves.target_sections(sim.waves.plan_for(day)):
				out.append(s)
			return out
		return []

	## How many sections of the compound are down now (a section that is down at dusk is not a fall of the night: it fell in an earlier one).
	func _down_now() -> int:
		var down := 0
		for s in Sections.compound(sim):
			if int(s.state) == 3:
				down += 1
		return down

	func _begin() -> void:
		var day := int(sim.day)
		var plan: Dictionary = sim.waves.plan_for(day)
		var kind := "ordinary"
		var big: Dictionary = sim.waves.big_night(day)
		if not big.is_empty():
			kind = String(big.get("kind", "milestone"))
		elif bool(plan.get("big", false)):
			kind = "final"
		var outlook: Dictionary = sim.waves.outlook(day)
		_targets = []
		for v in outlook.get("sections", []):
			_targets.append(int(v))
		var alive := 0
		for p in sim.people:
			if not (p.dead or p.turned):
				alive += 1
		var ready: Dictionary = _ready.get(day, {})
		_cur = {
			"day": day, "kind": kind, "mode": mode, "size": (plan.get("queue", []) as Array).size(), "plated": 0,
			"sections_fell": 0, "fell": [], "walls_fell": 0, "down_at_dusk": _down_now(), "down_at_dawn": 0, "hp_lost": 0.0, "hp_by_seg": {}, "min_wall": 1.0,
			"died": 0, "downed": 0, "bites": 0, "held": true, "over": false,
			"ready": bool(ready.get("holds", false)), "ready_known": bool(ready.get("known", false)),
			"people": alive, "stock_ammo0": snappedf(float(sim.stock.ammo), 0.1), "stock_ammo": 0.0,
			"first_at": float(outlook.get("first_at", -1.0)), "targets": _targets.duplicate(), "first_claw_at": -1.0,
			"avatar": {"present": 0.0, "threat_steps": 0, "present_steps": 0, "shots": 0, "kills": 0, "hp_min": 100.0, "downed": 0, "died": 0, "ammo": 0.0},
			"calls": {"raised": 0, "answered_by_player": 0, "by_default": 0, "mean_s": 0.0},
			"brute_s": [],
		}
		_since_start = 0.0
		_sample_t = 0.0
		_hp = {}
		_state = {}
		for s in sim.segments:
			_hp[s.id] = float(s.hp)
			_state[s.id] = int(s.state)
		_down = {}
		_gone = {}
		for p in sim.people:
			_down[p.id] = bool(p.downed)
			_gone[p.id] = bool(p.dead)
		_brutes = {}
		_plated = {}
		_calls = {}
		for e in sim.radio.news:
			if not (e.options as Array).is_empty():
				_calls[int(e.id)] = {"seen": true, "answered": String(e.answered) != "", "at": -1.0, "raised": -1.0, "done": -1.0}
		_av = sim.avatar.player()
		_av_shots = int(_av.stats.get("shots", 0)) if _av != null else 0
		_av_kills = int(_av.stats.get("kills", 0)) if _av != null else 0
		_av_was_down = bool(_av.downed) if _av != null else false

	# --------------------------------------------------------------------- every step --

	func _count_events() -> void:
		var bites := 0
		for i in range(sim.events.size() - 1, -1, -1):
			var e: Dictionary = sim.events[i]
			if e.has(MARK):
				break
			e[MARK] = true
			if String(e.get("type", "")) == "bite":
				bites += 1
		if bites > 0 and not _cur.is_empty():
			_cur["bites"] = int(_cur.bites) + bites

	func _look(dt: float) -> void:
		var c := _cur
		# the walls: what the dead took, a section that fell (the compound's, not a door and not a wall of the streets), the lowest
		var lowest := float(c.min_wall)
		for s in sim.segments:
			var was_hp: float = float(_hp.get(s.id, s.hp))
			if float(s.hp) < was_hp - 1.0e-9:
				c["hp_lost"] = float(c.hp_lost) + (was_hp - float(s.hp))
				var by: Dictionary = c.hp_by_seg
				by[str(s.id)] = float(by.get(str(s.id), 0.0)) + (was_hp - float(s.hp))
			_hp[s.id] = float(s.hp)
			var was_state: int = int(_state.get(s.id, s.state))
			_state[s.id] = int(s.state)
			if s.kind != sim.DOOR_KIND:
				if int(s.id) < COMPOUND_IDS:
					lowest = minf(lowest, float(s.hp) / maxf(float(s.max_hp), 1.0))
				if int(s.state) == 3 and was_state != 3:
					if int(s.id) < COMPOUND_IDS:
						c["sections_fell"] = int(c.sections_fell) + 1
						(c.fell as Array).append({"seg": int(s.id), "at_hour": snappedf(float(sim.hour), 0.01)})
					else:
						c["walls_fell"] = int(c.walls_fell) + 1
		c["min_wall"] = lowest
		# the people: down, dead
		for p in sim.people:
			if bool(p.downed) and not bool(_down.get(p.id, false)) and not p.dead:
				c["downed"] = int(c.downed) + 1
			_down[p.id] = bool(p.downed)
			if bool(p.dead) and not bool(_gone.get(p.id, false)):
				if not (p.away is Dictionary and String(p.away.get("kind", "")) == "exile"):
					c["died"] = int(c.died) + 1
			_gone[p.id] = bool(p.dead)
		# the dead: plated ones, the first claw on a target wall, a brute from its first claw to its fall
		var now := float(sim.t)
		var av_killed := false
		var me = sim.avatar.player()
		if me != null and int(me.stats.get("kills", 0)) > _av_kills and me == _av:
			av_killed = true
		for z in sim.zombies:
			var key: int = z.get_instance_id()
			if bool(z.get("plated")) and not _plated.has(key):
				_plated[key] = true
				c["plated"] = int(c.plated) + 1
			if z.state == "attack" and z.slot != null:
				if float(c.first_claw_at) < 0.0 and _targets.has(int(z.slot.seg.id)):
					c["first_claw_at"] = snappedf(float(sim.hour), 0.01)
				if z.kind == "brute" and not _brutes.has(key):
					_brutes[key] = {"from": now, "plated": bool(z.get("plated")), "done": false}
			if z.kind == "brute" and _brutes.has(key) and not bool(_brutes[key].done) and (z.state == "dying" or z.state == "dead"):
				_brutes[key]["done"] = true
				(c.brute_s as Array).append({"s": snappedf(now - float(_brutes[key].from), 0.1), "plated": bool(_brutes[key].plated), "by": "avatar" if av_killed else "crew"})
		# the avatar: shots, kills, health, down, dead
		var av: Dictionary = c.avatar
		if me != _av:
			_av = me    # (a succession: the new player is the one counted from now)
			_av_shots = int(me.stats.get("shots", 0)) if me != null else 0
			_av_kills = int(me.stats.get("kills", 0)) if me != null else 0
			_av_was_down = bool(me.downed) if me != null else false
		if _av != null:
			var shots := int(_av.stats.get("shots", 0))
			if shots > _av_shots:
				av["shots"] = int(av.shots) + (shots - _av_shots)
				av["ammo"] = float(av.ammo) + float(shots - _av_shots) * float(sim.shot_cost(_av))
			_av_shots = shots
			var kills := int(_av.stats.get("kills", 0))
			if kills > _av_kills:
				av["kills"] = int(av.kills) + (kills - _av_kills)
			_av_kills = kills
			av["hp_min"] = minf(float(av.hp_min), float(_av.hp))
			if bool(_av.downed) and not _av_was_down:
				av["downed"] = int(av.downed) + 1
			_av_was_down = bool(_av.downed)
			if _av.dead and not bool(av.get("_dead", false)):
				av["_dead"] = true
				av["died"] = int(av.died) + 1
		# the calls the radio raised, and who answered them
		for e in sim.radio.news:
			if (e.options as Array).is_empty():
				continue
			var id := int(e.id)
			if not _calls.has(id):
				_calls[id] = {"seen": true, "answered": false, "at": float(sim.t), "raised": float(sim.t), "done": -1.0}
				(c.calls as Dictionary)["raised"] = int(c.calls.raised) + 1
			var rec: Dictionary = _calls[id]
			if not bool(rec.answered) and String(e.answered) != "":
				rec["answered"] = true
				rec["done"] = float(sim.t)
				if float(rec.raised) >= 0.0:
					if bool(e.by_default):
						c.calls["by_default"] = int(c.calls.by_default) + 1
					else:
						c.calls["answered_by_player"] = int(c.calls.answered_by_player) + 1
						c.calls["_sum"] = float(c.calls.get("_sum", 0.0)) + (float(sim.t) - float(rec.raised))
		# the presence: of the samples with a wall pressed, the share the avatar stood within the rally's reach of the most pressed one
		_sample_t += dt
		if _sample_t >= SAMPLE_S:
			_sample_t -= SAMPLE_S
			if sim.nights.has_method("contested"):
				var hot: Dictionary = sim.nights.contested()
				if hot.get("seg") != null and float(hot.get("threat", 0.0)) >= PRESSED:
					av["threat_steps"] = int(av.threat_steps) + 1
					if me != null and not (me.dead or me.downed or me.turned) and me.away == null:
						if Vector2(me.x, me.y).distance_to(hot.seg.center) <= NightData.num("rally.radius", 9.0):
							av["present_steps"] = int(av.present_steps) + 1

	# --------------------------------------------------------------------- the night ends --

	func _snapshot(final: bool) -> Dictionary:
		var out: Dictionary = _cur.duplicate(true)
		out["down_at_dawn"] = _down_now()
		out["stock_ammo"] = snappedf(float(sim.stock.ammo), 0.1)
		out["over"] = final or sim.over != ""
		out["held"] = int(out.sections_fell) == 0 and int(out.died) == 0
		var av: Dictionary = out.avatar
		var steps := int(av.threat_steps)
		av["present"] = snappedf(float(av.present_steps) / float(steps), 0.001) if steps > 0 else 0.0
		av.erase("_dead")
		av["hp_min"] = snappedf(float(av.hp_min), 0.1)
		av["ammo"] = snappedf(float(av.ammo), 0.1)
		var calls: Dictionary = out.calls
		var n := int(calls.answered_by_player)
		calls["mean_s"] = snappedf(float(calls.get("_sum", 0.0)) / float(n), 0.1) if n > 0 else 0.0
		calls.erase("_sum")
		out["hp_lost"] = snappedf(float(out.hp_lost), 0.1)
		out["min_wall"] = snappedf(float(out.min_wall), 0.001)
		for k in (out.hp_by_seg as Dictionary).keys():
			out.hp_by_seg[k] = snappedf(float(out.hp_by_seg[k]), 0.1)
		return out

	func _close(final: bool) -> void:
		var out := _snapshot(final)
		rows.append(out)
		_closed_day = int(_cur.day)
		_cur = {}
		_ready.erase(int(out.day))


# ============================================================================ the table ==

## Which cell of the table a night belongs to: "big" (a milestone or the last night), "1-9" or "11+" (the ordinary nights of the first
## nine days, and after).
static func group_of(row: Dictionary) -> String:
	if String(row.get("kind", "ordinary")) != "ordinary":
		return "big"
	return "1-9" if int(row.get("day", 0)) <= 9 else "11+"


## The numbers of a cell: `rows` is any list of night rows. Shares are 0..1 (-1 when there is nothing to take a share of), the rest are
## means for a night; the presence is pooled over the samples of all the nights (a night with no wall pressed adds none).
static func aggregate(rows: Array) -> Dictionary:
	var n := rows.size()
	var out := {"n": n, "held": 0.0, "held_ready": -1.0, "n_ready": 0, "held_not": -1.0, "n_not": 0, "fell": 0.0, "died": 0.0, "downed": 0.0,
		"bites": 0.0, "hp_lost": 0.0, "presence": 0.0, "shots": 0.0, "ammo": 0.0, "raised": 0.0, "answered": 0.0, "by_default": 0.0,
		"av_downed": 0.0, "av_died": 0.0, "lost_games": 0.0, "size": 0.0, "min_wall": 0.0, "stock_ammo": 0.0}
	if n == 0:
		return out
	var held := 0
	var ready_n := 0
	var ready_held := 0
	var not_n := 0
	var not_held := 0
	var steps := 0
	var near := 0
	for r in rows:
		var h := bool(r.get("held", false))
		held += 1 if h else 0
		if bool(r.get("ready_known", false)):
			if bool(r.get("ready", false)):
				ready_n += 1
				ready_held += 1 if h else 0
			else:
				not_n += 1
				not_held += 1 if h else 0
		out["fell"] = float(out.fell) + float(r.get("sections_fell", 0))
		out["died"] = float(out.died) + float(r.get("died", 0))
		out["downed"] = float(out.downed) + float(r.get("downed", 0))
		out["bites"] = float(out.bites) + float(r.get("bites", 0))
		out["hp_lost"] = float(out.hp_lost) + float(r.get("hp_lost", 0.0))
		out["size"] = float(out.size) + float(r.get("size", 0))
		out["min_wall"] = float(out.min_wall) + float(r.get("min_wall", 1.0))
		out["stock_ammo"] = float(out.stock_ammo) + float(r.get("stock_ammo", 0.0))
		out["lost_games"] = float(out.lost_games) + (1.0 if bool(r.get("over", false)) else 0.0)
		var av: Dictionary = r.get("avatar", {})
		steps += int(av.get("threat_steps", 0))
		near += int(av.get("present_steps", 0))
		out["shots"] = float(out.shots) + float(av.get("shots", 0))
		out["ammo"] = float(out.ammo) + float(av.get("ammo", 0.0))
		out["av_downed"] = float(out.av_downed) + float(av.get("downed", 0))
		out["av_died"] = float(out.av_died) + float(av.get("died", 0))
		var calls: Dictionary = r.get("calls", {})
		out["raised"] = float(out.raised) + float(calls.get("raised", 0))
		out["answered"] = float(out.answered) + float(calls.get("answered_by_player", 0))
		out["by_default"] = float(out.by_default) + float(calls.get("by_default", 0))
	for k in ["fell", "died", "downed", "bites", "hp_lost", "shots", "ammo", "raised", "answered", "by_default", "av_downed", "av_died", "size", "min_wall", "stock_ammo"]:
		out[k] = float(out[k]) / float(n)
	out["held"] = float(held) / float(n)
	out["lost_games"] = float(out.lost_games) / float(n)
	out["presence"] = float(near) / float(steps) if steps > 0 else 0.0
	out["n_ready"] = ready_n
	out["n_not"] = not_n
	if ready_n > 0:
		out["held_ready"] = float(ready_held) / float(ready_n)
	if not_n > 0:
		out["held_not"] = float(not_held) / float(not_n)
	return out


## The header of the table of cells (`cell_line`).
static func table_header() -> String:
	return "cell        mode    nights | held%  ready/not | fell  died downed  bites hp lost | present | shots  ammo | calls ans def | av down died | lost%"


static func _pct(v: float) -> String:
	return "  - " if v < 0.0 else "%3.0f%%" % (100.0 * v)


## One line of the table: a cell is a group of nights of one mode.
static func cell_line(label: String, mode: String, rows: Array) -> String:
	var a := aggregate(rows)
	return "%-11s %-7s %6d | %s  %s/%s | %4.2f %5.2f %5.2f %6.2f %7.0f | %6.2f | %5.1f %5.1f | %5.1f %3.1f %3.1f | %4.2f %4.2f | %4.0f%%" % [
		label, mode, int(a.n), _pct(float(a.held)), _pct(float(a.held_ready)), _pct(float(a.held_not)), float(a.fell), float(a.died), float(a.downed),
		float(a.bites), float(a.hp_lost), float(a.presence), float(a.shots), float(a.ammo), float(a.raised), float(a.answered), float(a.by_default),
		float(a.av_downed), float(a.av_died), 100.0 * float(a.lost_games)]


## The table of a list of rows (any modes): a line for each group of days and each mode, groups in the order 1-9, 11+, big.
static func table_lines(rows: Array) -> Array:
	var lines: Array = [table_header()]
	var cells := {}
	var modes: Array = []
	for r in rows:
		var key := "%s|%s" % [group_of(r), String(r.get("mode", "none"))]
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(r)
		if not modes.has(String(r.get("mode", "none"))):
			modes.append(String(r.get("mode", "none")))
	for group in ["1-9", "11+", "big"]:
		for m in ["none", "idle", "bot"]:
			var key := "%s|%s" % [group, m]
			if cells.has(key):
				lines.append(cell_line(group, m, cells[key]))
	return lines
