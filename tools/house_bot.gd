## The One House bot (WP8: docs/superpowers/plans/2026-10-04-one-house-plan.md, section 3 and 5): the player that plays the whole demo arc through the hands a person has,
## so that tools/house_lab.gd can measure it headless. `HouseBot` plays by day (walk in from the town's entry to the candidate house its `candidate` policy picks, clear it, search, claim it,
## find and bring home survivors, order the perimeter, sleep the quiet nights) and hands the first attack night to `Defender` (tools/avatar_bot.gd's `AvatarBot` on the base's wall sections
## instead of the school's). Every "start house" below is the house it picked (`_start_house`).
##
## THE HANDS. Only what the player has: `sim.avatar.set_input` (walk, aim, trigger), `melee`, `reload`; E through `sim.interact.candidates()` / `use()` (the town's kinds are
## `sim.uses`: container, claim, bed, rescue...); the rescue card (`sim.rescue.talk` / `choose`); the Build page (`sim.perimeter.order`); the walking grid (`sim.path_p`). It draws no
## die from `sim.rng` (its own random source), so paired runs stay paired. It does know where the dead are (a record is data): a person sees them only through an open door; the bot
## walks to them. That shortens a clear, it does not change the fight.
##
## MISSING MODULES. A step that needs a module the sim does not have (`sim.get("name") == null`) is skipped and noted in `missing` as "<what>: missing: <module>"; the rest of the arc
## goes on. The lab prints them.
##
## THE TIMELINE. `observe()` (once per rules step, after `sim.update`) reads `sim.events` and notes each milestone (house clear, claim, each rescue, the fourth, each slot built, the
## bell of the first attack night, held or lost) with the day and the hour. The caller clears `sim.events` after it has observed.
extends RefCounted

const BotLib := preload("res://tools/avatar_bot.gd")
const Arrival := preload("res://scripts/town/arrival.gd")

## The wall sections of the base are the ids below this (the lots' are above: `Lots.FIRST_SEGMENT_ID`); the barred doors are among them.
const SECTION_IDS := 100


## The base's wall sections: the barred doors and the built fence, gate (not the lots' walls). The night's dead choose among these.
static func base_sections(sim) -> Array:
	var out: Array = []
	for s in sim.segments:
		if int(s.id) < SECTION_IDS:
			out.append(s)
	return out


# ========================================================================= the night ==

## The night's defender: `AvatarBot` with the base's sections, the street's `chase` dead counted as hostile, and the base's own post as home.
class Defender:
	extends BotLib.AvatarBot

	func _hostile(z) -> bool:
		return z.state == "chase" or super(z)

	func _class_of(z, me) -> int:
		if z.state == "chase":
			if not _live(z):
				return -1
			return 2 if String(z.hunt_id) == String(me.id) else 3
		return super(z, me)

	func _forecast_station(_me) -> Dictionary:
		return {}

	## The school's bot goes to a bed when it bleeds (the medic comes to it there); a town base has no bed that heals and a lone avatar has no medic, so it holds its wall.
	func _update_hurt(_me) -> void:
		_hurt = false

	func _home(me) -> Dictionary:
		var posts: Array = sim.jobs.posts()
		var at := Vector2(me.x, me.y)
		var base = sim.get("base")
		if base != null and base.has_method("center") and bool(base.claimed):
			at = base.center()
		if not posts.is_empty():
			var best := Vector2(posts[0].pos)
			for po in posts:
				if Vector2(po.pos).distance_to(at) < best.distance_to(at):
					best = Vector2(po.pos)
			at = best
		return {"seg": -1, "at": at, "why": "home"}

	func _choose_station(me) -> void:
		var now := float(sim.clock_min)
		for k in _called.keys():
			if now > float(_called[k]):
				_called.erase(k)
		var best = null
		var best_score := 0.0
		var scores := {}
		for seg in base_sections_of(sim):
			var sc := _threat_of(seg)
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
		elif best == null and cur >= 0 and float(scores.get(cur, 0.0)) <= 0.0 and int(station.get("seg", -1)) != -1:
			_set_station(_home(me))

	## How hard a section is pressed. The colony's `section_threat` answers 0 for a barred door (the school's doors are the last line behind its wall), but in a town the dead go for the
	## doors whenever no fence is on their side, and a door that nobody defends falls: the same sum as the colony's for a door (the dead clawing at it, the ones on their way, what it has
	## lost).
	func _threat_of(seg) -> float:
		if seg.kind != sim.DOOR_KIND:
			return float(sim.nights.section_threat(seg))
		var total := 0.0
		for z in sim.zombies:
			if z.slot == null or z.slot.seg != seg:
				continue
			if z.state == "attack":
				total += 1.0 + (4.0 if z.kind == "brute" else 0.0)
			elif z.state == "approach" and Vector2(z.x, z.y).distance_to(seg.center) <= 25.0:
				total += 0.35
		return total + 6.0 * (1.0 - clampf(float(seg.hp) / maxf(float(seg.max_hp), 1.0), 0.0, 1.0))

	## Where a gunner covers a section; for a door, in the yard a little way off the place the dead stand at (the colony's answer is inside the house, where a shot cannot pass the door).
	func _stand(seg, me) -> Vector2:
		if seg.kind == sim.DOOR_KIND and not seg.slots.is_empty():
			var sl = seg.slots[0]
			var out := Vector2(sl.ax - sl.x, sl.ay - sl.y)
			out = out.normalized() if out.length() > 0.01 else Vector2.ZERO
			var far := Vector2(sl.ax, sl.ay) + out * 1.5
			if sim.world.is_solid(sim.world.solid_p, far.x, far.y):
				far = Vector2(sl.ax, sl.ay)
			return far
		return super(seg, me)

	## The wall to mend now, as the colony's bot has it but the barred doors too (the house is what they are for).
	func _mend_wanted(me):
		if _mender() == null:
			return null
		var sid := int(station.get("seg", -1))
		if sid < 0 or float(sim.stock.scrap) < 1.0:
			return null
		var seg = _seg(sid)
		if seg == null or not (seg.state == 3 or float(seg.hp) < float(seg.max_hp) * MEND_BELOW):
			return null
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

	## (the static helper of the file, reachable from the inner class)
	static func base_sections_of(sim) -> Array:
		var out: Array = []
		for s in sim.segments:
			if int(s.id) < 100:
				out.append(s)
		return out


# ========================================================================== the bot ==

## The player of the whole arc. `mode` "bot" plays the first attack night at the wall; "idle" plays the same days and then keeps its hands off in the house from the evening of
## the first attack night (the community alone: the plan's target of at least 2 held in 8 seeds).
class HouseBot:
	extends RefCounted

	const THINK_S := 0.4
	const WAYPOINT_R := 0.3
	const REPATH_S := 1.0
	const STUCK_S := 0.6
	## Seconds of a stuck walk after which the task is given up (and not tried again for a while).
	const GIVE_UP_S := 4.0
	const BLOCK_MIN := 120.0
	## A search or a claim started this many times without finishing is given up.
	const SESSION_TRIES := 6
	## A search, a claim or a bed waits this long for the dead near to be dealt with, then goes on.
	const THREAT_WAIT_S := 10.0
	## The bandage is begun when the nearest dead one after somebody is farther than HEAL_CLEAR_R and is let go of when one comes within HEAL_BREAK_R.
	const HEAL_CLEAR_R := 5.5
	const HEAL_BREAK_R := 2.5
	const BODY := 0.3
	const AIM_JITTER := 0.03
	const JITTER_S := 0.2
	const REACT_S := 0.25
	const MELEE_R := 1.4
	const MAG_LOW := 3
	const LULL_R := 5.0
	## A dead one this near, awake, takes the hands from a search or a claim.
	const THREAT_R := 6.5
	## The dead that stand or wander farther than this are left be (a shot wakes the street); the ones after somebody are shot in reach.
	const QUIET_R := 5.5
	## The gun's reasons in the open: close enough to bite; coming for the hands that must stand still; coming for a walker's own pace (never: 2 tiles).
	const CLOSE_R := 1.8
	const STILL_FIRE_R := 7.0
	const WALK_FIRE_R := 1.8
	## At most this many of the street's dead after it within CHASE_COUNT_R tiles: it stands and shoots them (STILL_FIRE_R) instead of walking on with them behind it.
	const FEW_CHASERS := 3
	const CHASE_COUNT_R := 9.0
	const AVOID_R := 3.0
	const KITE_R := 2.6
	## The nearest of the dead after it must be this far for it to stand and shoot (else it steps back first, unless it has nowhere to go).
	const KITE_FIRE_D := 1.7
	const AVOID_GAIN := 1.8
	## The hour by which the bot is home on an ordinary day, and on the day of an attack.
	const HOME_BY := 18.3
	const HOME_BY_ATTACK := 16.5
	## Below this health (and not in a fight) it goes home and naps.
	const HURT_HP := 40.0
	## It rests (home, the bed) from HURT_HP down until the health is back to this.
	const RECOVER_UNTIL := 60.0
	## The farthest survivor it goes for, in tiles from the base (the first ring was within 28 and the second to 58: past that the trip takes the day and the dead of the way). CLEAR3: there is open ground
	## round every candidate and the houses begin 30 tiles out, the rings are 16 tiles farther (30 to 56, 56 to 84) and so is the farthest survivor it goes for (62 + 16, and a little).
	const MAX_RESCUE_R := 80.0
	## Scrap kept back from the orders for mending once an attack is on.
	const MEND_RESERVE := 8.0
	const BED_REACH := 1.5
	const SLEEP_REAL_S := 40.0

	var sim
	var mode := "bot"
	## Which candidate house it walks in to from the entry and makes its base (the arrival: scripts/town/arrival.gd): "best", "ok", "poor" (the tier of the town's candidates; the nearest to it when
	## the town has none of that tier) or "nearest" (the nearest to where it stands at the start).
	var candidate := "best"
	## Slots that must stand before it brings the fourth survivor home (0: it does not wait: the player who does not know what the fourth brings).
	var prep := 0
	## The factor of a person's pace over the bot's (the lab's --human): the milestones' `real` minutes use it.
	var human := 1.25
	## How it orders the base: "projects" (the Build page's next project, as a player who does what the page recommends: `perimeter.order_project`) or "slots" (one section at a
	## time through `perimeter.order`, the first plan's way).
	var orders := "projects"
	## What the lab reads: [{"what", "day", "hour", "min" (game minutes since the start), ...}] in the order they happened.
	var timeline: Array = []
	## "<what>: missing: <module>" for every step that was skipped for a module that is not there (once each).
	var missing: Dictionary = {}
	## What it is doing (for the lab's last line and for a person watching): {"kind", "key", ...}.
	var task: Dictionary = {}
	## Counters the lab prints.
	var stats := {"shots": 0, "kills0": 0, "bites": 0, "searched": 0, "rescue_talks": 0, "orders": 0, "naps": 0, "sleeps": 0, "heals": 0, "gave_up": 0, "hp_min": 100.0}
	## Game minutes asleep (fast-forwarded: not played at the player's pace) and how many nights.
	var slept_min := 0.0
	var defender
	## True once the avatar has fallen and the game went on with somebody else (the lab ends the run: a lost run).
	var avatar_dead := false

	var _rng := RandomNumberGenerator.new()
	var _t := 0.0
	var _think_t := 0.0
	var _start_clock := 0.0
	var _start_set := false
	var _target = null
	var _target_since := 0.0
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
	var _blocked: Dictionary = {}
	var _marks: Dictionary = {}
	var _pressed_at := -10.0
	var _fight_now := false
	var _stop_fire := false
	var _attack_day_seen := -1
	var _bell_marked := false
	var _first_attack_dusk := false
	var _idle_since := -1.0
	var _sleep_from := -1.0
	var _recovering := false
	var _last_player_id := ""
	## The house it picked (-1 until it is asked, `_start_house`).
	var _pick := -1

	func _init(s, mode_name := "bot") -> void:
		sim = s
		mode = mode_name
		_rng.seed = int(sim.run_seed) * 11 + 5
		defender = Defender.new(s, "bot")

	# -------------------------------------------------------------------- the clock --

	func _stamp() -> Dictionary:
		if not _start_set:
			_start_set = true
			_start_clock = float(sim.clock_min)
		return {"day": int(sim.day), "hour": snappedf(float(sim.hour), 0.01), "min": snappedf(float(sim.clock_min) - _start_clock, 0.1)}

	func note_start() -> void:
		_stamp()

	func mark(what: String, extra: Dictionary = {}) -> void:
		var e := _stamp()
		e["what"] = what
		# (EARLY: real minutes at a player's pace so far, for the milestones the lab reports: `human` is the lab's --human)
		e["real"] = snappedf(real_seconds(float(sim.clock_min), human) / 60.0, 0.01)
		for k in extra:
			e[k] = extra[k]
		timeline.append(e)

	func _mark_once(key: String, what: String, extra: Dictionary = {}) -> void:
		if _marks.has(key):
			return
		_marks[key] = true
		mark(what, extra)

	func has_mark(what: String) -> bool:
		for e in timeline:
			if String(e.what) == what:
				return true
		return false

	func first_of(what: String) -> Dictionary:
		for e in timeline:
			if String(e.what) == what:
				return e
		return {}

	func count_of(what: String) -> int:
		var n := 0
		for e in timeline:
			if String(e.what) == what:
				n += 1
		return n

	func _miss(what: String, module: String) -> void:
		var key := "%s: missing: %s" % [what, module]
		if not missing.has(key):
			missing[key] = true
			mark("missing", {"step": what, "module": module})

	## Real seconds the arc would take at a player's pace: the game minutes awake at `min_per_sec`, the nights in the bed at a flat SLEEP_REAL_S each.
	func real_seconds(now_clock: float, human: float = 1.0) -> float:
		var awake := maxf(now_clock - _start_clock - slept_min, 0.0)
		return awake / maxf(float(sim.min_per_sec), 0.1) * human + float(stats.sleeps) * SLEEP_REAL_S

	## What it is doing, for the lab's trace: the task, where it stands, the target, the dead of the start house.
	func debug_line() -> String:
		var me = _me()
		if me == null:
			return "no avatar"
		var pos := Vector2(me.x, me.y)
		var tgt := "-"
		if _target != null:
			tgt = "%s %.1f,%.1f d%.1f line %s" % [String(_target.state), float(_target.x), float(_target.y), pos.distance_to(Vector2(_target.x, _target.y)), str(_line_ok)]
		var near := _nearest(_dead_in_house(_start_house()), pos) if _hs() != null else pos
		var gun := "mag %d rel %.1f cd %.2f fire %s move %s" % [int(me.mag), float(me.reloading), float(me.cooldown), str(me.input_fire), str(me.input_move)]
		return "%s | %s at %.1f,%.1f house %d room %d | target %s | goal %s | stuck %.1f | path %d | start-house dead %d (nearest %.1f,%.1f)" % [gun, String(task.get("key", "-")), pos.x, pos.y, int(_hs().house_at(pos.x, pos.y)) if _hs() != null else -1, int(_hs().room_at(pos.x, pos.y)) if _hs() != null else -1, tgt, str(_path_goal), _stuck_t, _path.size(), _dead_in_house(_start_house()).size(), near.x, near.y]

	# ---------------------------------------------------------------------- events --

	## Reads the events of this step (the caller clears them after). Milestones only: the bot's own counters too (shots, kills, bites).
	func observe(_dt: float) -> void:
		_stamp()
		for e in sim.events:
			match String(e.get("type", "")):
				"entered":
					if bool(e.get("first", false)) and int(e.get("house", -1)) == _start_house():
						_mark_once("entered_start", "entered", {"house": int(e.house)})
				"house_clear":
					if int(e.get("house", -1)) == _start_house():
						_mark_once("house_clear", "house_clear", {"house": int(e.house)})
					else:
						mark("other_house_clear", {"house": int(e.get("house", -1))})
				"claimed":
					_mark_once("claimed", "claim", {"house": int(e.get("house", -1))})
				"searched":
					if not e.has("who"):    # (the avatar's own: a crew member's search names them, scripts/town/crew_search.gd)
						stats.searched = int(stats.searched) + 1
				"rescue_seen":
					mark("rescue_seen", {"id": String(e.get("id", ""))})
				"rescue_talk":
					stats.rescue_talks = int(stats.rescue_talks) + 1
				"rescue_joined":
					mark("rescue", {"id": String(e.get("id", "")), "count": int(e.get("count", 0))})
				"fourth":
					_mark_once("fourth", "fourth")
				"attacks_on":
					_mark_once("attacks_on", "attacks_on", {"from_day": int(e.get("from_day", 0))})
				"slot_ordered":
					mark("slot_ordered", {"slot": String(e.get("slot", "")), "kit": String(e.get("kit", ""))})
				"slot_built":
					mark("slot_built", {"slot": String(e.get("slot", "")), "kit": String(e.get("kit", ""))})
				"slot_lost":
					mark("slot_lost", {"slot": String(e.get("slot", ""))})
				"project_done":
					# (EARLY: the lab's 'first fence finished': the front project's last section is up)
					mark("project_done", {"project": String(e.get("project", ""))})
				"bell":
					if _attacks_on() and not _bell_marked:
						_bell_marked = true
						mark("bell")
				"held":
					_mark_once("held", "held", {"night": int(e.get("night", 0))})
				"bite":
					if String(e.get("who", "")) == _player_id():
						stats.bites = int(stats.bites) + 1
				"succession":
					# the avatar fell and somebody else is played now: the run of the person the bot plays is over
					if not avatar_dead:
						avatar_dead = true
						mark("avatar_died", {"to": String(e.get("to", ""))})
				"sleep":
					if bool(e.get("on", false)):
						_sleep_from = float(sim.clock_min)
						if _is_night():
							stats.sleeps = int(stats.sleeps) + 1
					elif _sleep_from >= 0.0:
						slept_min += float(sim.clock_min) - _sleep_from
						_sleep_from = -1.0
		if sim.over != "":
			_mark_once("over", "over", {"verdict": String(sim.over)})
		var me = _me()
		if me != null:
			stats.hp_min = minf(float(stats.hp_min), float(me.hp))

	# ------------------------------------------------------------------- small reads --

	func _me():
		if String(sim.player_id) == "":
			return null
		return sim.avatar.player()

	func _player_id() -> String:
		return String(sim.player_id)

	func _hs():
		return sim.get("houses")

	## The house the bot is making its base: the candidate its policy picks (`candidate`), chosen once, the first time it is asked, from where the run begins (the town's start house when it has
	## no candidates). Every "start house" of the bot's below is this one.
	func _start_house() -> int:
		if _pick >= 0:
			return _pick
		var hs = _hs()
		if hs == null:
			return -1
		var town: Dictionary = hs.town
		var me = _me()
		var from := Vector2(me.x, me.y) if me != null else Vector2.ZERO
		var pick := -1
		if ["best", "ok", "poor"].has(candidate):
			pick = Arrival.house_of_tier(town, candidate)
		if pick < 0 and not town.is_empty() and town.has("start"):
			pick = Arrival.nearest(town, from)
		if pick < 0:
			pick = int(hs.start_house())
		_pick = pick
		var c: Dictionary = Arrival.candidate_of(town, pick) if not town.is_empty() and town.has("start") else {}
		mark("chose", {"house": pick, "label": String(c.get("label", "the start house")), "tier": String(c.get("tier", "")), "dist": float(c.get("dist", 0.0))})
		return pick

	func _claimed() -> bool:
		var b = sim.get("base")
		return b != null and bool(b.claimed)

	func _attacks_on() -> bool:
		var sc = sim.scenario
		return sc != null and sc.has_method("attacks_on") and bool(sc.attacks_on())

	func _live(z) -> bool:
		return z.state != "dying" and z.state != "dead" and z.state != "retreat"

	func _hour() -> float:
		return float(sim.hour)

	func _is_night() -> bool:
		return String(sim.phase) != "day"

	func _crew() -> int:
		var n := 0
		for p in sim.people:
			if not (p.dead or p.turned):
				n += 1
		return n

	## The dead of the town standing where `where.call(Vector2)` says now, awake or asleep: [Vector2].
	func _dead_where(where: Callable) -> Array:
		var out: Array = []
		for z in sim.zombies:
			if _live(z):
				var at := Vector2(z.x, z.y)
				if where.call(at):
					out.append(at)
		var f = sim.get("field")
		if f != null:
			for i in f.n:
				if int(f.status[i]) == 0:    # (dormant)
					var at := Vector2(f.xs[i], f.ys[i])
					if where.call(at):
						out.append(at)
		return out

	func _dead_in_house(h: int) -> Array:
		var hs = _hs()
		return _dead_where(func(at: Vector2) -> bool: return int(hs.house_at(at.x, at.y)) == h)

	func _dead_in_room(room: int) -> Array:
		var hs = _hs()
		return _dead_where(func(at: Vector2) -> bool: return int(hs.room_at(at.x, at.y)) == room)

	func _nearest(list: Array, pos: Vector2) -> Vector2:
		var best := pos
		var best_d := INF
		for v in list:
			var d := pos.distance_to(Vector2(v))
			if d < best_d:
				best_d = d
				best = Vector2(v)
		return best

	# ---------------------------------------------------------------------- the step --

	## Once per rules step, before `sim.update`.
	func step(dt: float) -> void:
		var me = _me()
		if me == null:
			return
		if me.dead or me.turned or me.downed or me.away != null:
			sim.avatar.set_input(Vector2.ZERO, Vector2.ZERO, false)
			_target = null
			_path = []
			return
		if _player_id() != _last_player_id:
			_last_player_id = _player_id()
			_path = []
			_target = null
			task = {}
		_t += dt
		var sl = sim.get("sleep")
		if sl != null and sl.active():
			return    # (asleep: the sleep runs the colony; hands off)
		# the night of the first attack: the wall's defender plays (or nobody: idle)
		if _defending():
			if mode == "bot":
				defender.step(dt)
				return
			if _idle_since < 0.0 and Vector2(me.x, me.y).distance_to(_home_spot()) <= 1.6:
				_idle_since = _t
				mark("idle_hands_off")
			if _idle_since >= 0.0:
				sim.avatar.set_input(Vector2.ZERO, Vector2.ZERO, false)
				return
			# (an idle avatar that is still out walks home first)
		_think_t -= dt
		if _think_t <= 0.0:
			_think_t = THINK_S
			_think(me)
		_act(me, dt)

	## Whether the wall is the night's job now: the attacks are on and it is evening (from the hour of going home) to dawn.
	func _defending() -> bool:
		if not _attacks_on():
			return false
		return _is_night() or _hour() >= HOME_BY_ATTACK

	# ---------------------------------------------------------------------- thinking --

	func _think(me) -> void:
		_pick_target(me)
		_build_orders()
		_plan(me)

	func _blocked_now(key: String) -> bool:
		return _blocked.has(key) and float(_blocked[key]) > float(sim.clock_min)

	func _block(key: String, minutes: float = BLOCK_MIN) -> void:
		_blocked[key] = float(sim.clock_min) + minutes

	func _set_task(t: Dictionary) -> void:
		if not task.is_empty() and String(task.get("key", "")) == String(t.get("key", "")):
			for k in t:
				task[k] = t[k]    # (the same job: details refreshed)
			return
		task = t
		_path = []
		_holding = false
		_stuck_t = 0.0

	func _plan(me) -> void:
		var hs = _hs()
		if hs == null:
			_miss("start", "houses")
			_set_task({"kind": "wait", "key": "wait"})
			return
		var pos := Vector2(me.x, me.y)
		# a bleeding bite or an infection: the avatar's own medicine (E on "Bandage the wound", uses.gd), as soon as no dead one is on the avatar's heels (a person walks four times as fast as
		# a walker: a few seconds of walking away from the ones that follow is all a bandage asks for). Before everything else, the night too: a bite bleeds for good.
		if sim.get("uses") != null and _nearest_chaser(pos) > HEAL_CLEAR_R:
			if float(me.bleeding) > 0.0 and float(sim.stock.meds) >= float(sim.medical.BANDAGE_MEDS) and not _blocked_now("heal"):
				_set_task({"kind": "heal", "key": "heal", "id": "bandage"})
				return
			if float(me.infected_at) >= 0.0 and float(sim.stock.meds) >= float(sim.medical.CURE_MEDS) and not _blocked_now("treat"):
				_set_task({"kind": "heal", "key": "treat", "id": "cure"})
				return
		# the evening: home, to bed (a quiet night) or to wait for the dead (the attack's night is the defender's)
		if _is_night() or _hour() >= (HOME_BY_ATTACK if _attacks_on() else HOME_BY):
			_night_task(me)
			return
		# hurt: home, and a nap in the bed (sleep until an hour) until the health is back to something (nothing heals a person who stands: the bed is 4 points an hour)
		if _claimed():
			if float(me.hp) < HURT_HP:
				_recovering = true
			elif float(me.hp) >= RECOVER_UNTIL:
				_recovering = false
			if _recovering:
				if sim.get("sleep") != null and not _blocked_now("nap") and not _fight_now:
					_set_task({"kind": "nap", "key": "nap"})
				else:
					_set_task({"kind": "home", "key": "home"})
				return
		if not _claimed():
			_start_house_task(me)
			return
		if _keep_task():
			return
		# (EARLY: the first thing after the claim is the front fence, built with her own hands: E at a section that waits; and in the fortify days whatever is ordered)
		var bt := _build_task(me)
		if not bt.is_empty():
			_set_task(bt)
			return
		var r := _rescue_task(me) if _wants_rescue() else {}
		if not r.is_empty():
			_set_task(r)
			return
		var l := _loot_task(me)
		if not l.is_empty():
			_set_task(l)
			return
		_set_task({"kind": "home", "key": "home"})

	## EARLY: the section to build with her own hands, as a task ({} when there is none to build now): the sections that wait for hands (`sim.build_hands.sites()`), the nearest first, from the claim until the front fence is
	## up, and through the fortify day. A human player builds the first fence with E (the objective says so); the bot does too.
	func _build_task(me) -> Dictionary:
		var bh = sim.get("build_hands")
		var sc = sim.scenario
		if bh == null or sc == null or not sc.has_method("stage"):
			return {}
		var stage := String(sc.stage())
		var wanted: bool = stage == "fortify" or ((stage == "claimed" or stage == "growing") and not bool(sc._project_done("front")))
		if not wanted or _blocked_now("build"):
			return {}
		var pos := Vector2(me.x, me.y)
		var best := {}
		var best_d := INF
		for e in bh.sites():
			var d: float = bh.rect_dist(pos, e.rect)
			if d < best_d:
				best_d = d
				best = e
		if best.is_empty():
			return {}
		return {"kind": "build", "key": "build", "slot": String(best.slot), "rect": best.rect}

	## The tile in front of a section to stand at (a step inside it, toward the house), where E builds it.
	func _stand_at(rect: Rect2i) -> Vector2:
		var b = sim.get("base")
		var mid := Vector2(rect.position) + Vector2(rect.size) * 0.5
		var to_house: Vector2 = (b.center() - mid) if b != null and bool(b.claimed) else Vector2(0.0, -1.0)
		var dir := to_house.normalized() if to_house.length() > 0.1 else Vector2(0.0, -1.0)
		var pos := Vector2(_me().x, _me().y)
		var pt := Vector2(clampf(pos.x, float(rect.position.x) + 0.5, float(rect.end.x) - 0.5), clampf(pos.y, float(rect.position.y) + 0.5, float(rect.end.y) - 0.5))
		# (along a fence the point nearest her; across it one tile toward the house)
		return (pt + dir * 1.3).floor() + Vector2(0.5, 0.5)

	func _task_build(me, dt: float) -> Vector2:
		var bh = sim.get("build_hands")
		var uses = sim.get("uses")
		if bh == null or uses == null:
			_done("build")
			return Vector2.ZERO
		if uses.busy():
			return Vector2.ZERO
		var id := String(task.get("slot", ""))
		var site := {}
		for e in bh.sites():
			if String(e.slot) == id:
				site = e
		if site.is_empty():
			_done("build")
			return Vector2.ZERO
		var pos := Vector2(me.x, me.y)
		var at := _stand_at(site.rect)
		if bh.rect_dist(pos, site.rect) > 1.8:
			return _goto(me, at, 0.5, dt)
		var r := _press("build", id)
		if _waited(r) > GIVE_UP_S:
			_give_up("build", String(r.get("why", "no candidate")))
		return Vector2.ZERO

	## Whether it goes for another survivor: not once the attacks are on (the days are for scrap and the wall), and not the fourth until `prep` slots stand (a player who knows
	## that the fourth brings the dead; 0, the default, is the player who does not).
	func _wants_rescue() -> bool:
		if _attacks_on():
			return false
		# the fourth voice has come ("fortify": the dead will come): the day after it is for the wall, not for more survivors
		var sc = sim.scenario
		if sc != null and sc.has_method("stage") and String(sc.stage()) == "fortify":
			return false
		var rs = sim.get("rescue")
		var per = sim.get("perimeter")
		if prep > 0 and rs != null and per != null and int(rs.joined_count()) >= int(sc.d().get("attack", {}).get("from_rescue", 2)) - 1 and int(per.built_count()) < prep:
			return false
		return true

	## Whether the rescue or the far search in hand is still worth going on with (it is kept, not chosen again: the nearest one changes as the avatar walks).
	func _keep_task() -> bool:
		match String(task.get("kind", "")):
			"rescue":
				var rs = sim.get("rescue")
				var rec: Dictionary = rs.get_record(String(task.get("id", ""))) if rs != null else {}
				# (EARLY: the second voice brings the dead: a rescue on the way when it comes is dropped, the bot walks home and fortifies)
				return not rec.is_empty() and String(rec.state) != "joined" and String(rec.state) != "lost" and not _blocked_now(String(task.key)) and _wants_rescue()
			"search":
				var sr = sim.get("search")
				return sr != null and bool(task.get("far", false)) and not sr.is_looted(String(task.get("id", ""))) and not _blocked_now(String(task.key))
		return false

	# ---------------------------------------------------------------- the start house --

	func _start_house_task(me) -> void:
		var hs = _hs()
		var h := _start_house()
		var pos := Vector2(me.x, me.y)
		# 0. the way in: from the entry (or from wherever it is) to the front door of the house it picked
		if h >= 0 and not hs.town.is_empty() and hs.town.has("start") and int(hs.house_at(pos.x, pos.y)) != h:
			var door := Arrival.door_of(hs.town, h)
			if pos.distance_to(door) > 2.5 and not _blocked_now("travel_h%d" % h):
				_set_task({"kind": "travel", "key": "travel_h%d" % h, "house": h, "at": door})
				return
		# 1. the dead of the house
		var dead := _dead_in_house(h)
		if not dead.is_empty():
			_set_task({"kind": "clear", "key": "clear_h%d" % h, "house": h, "room": -1})
			return
		# 2. every room looked into (the claim needs it)
		var cl = sim.get("clearing")
		if cl == null:
			_miss("clear", "clearing")
		else:
			for r in hs.rooms_of(h):
				if not cl.is_revealed(int(r)) and not _blocked_now("reveal%d" % int(r)):
					_set_task({"kind": "reveal", "key": "reveal%d" % int(r), "room": int(r)})
					return
		# 3. the containers (EARLY: the one in hand is kept until it is searched or given up: a bot that chose the nearest again at every look went back and forth between two shelves for a day in seed 11)
		var in_hand := String(task.get("id", ""))
		if String(task.get("kind", "")) == "search" and int(task.get("house", -1)) == h and sim.get("search") != null and not sim.search.is_looted(in_hand) and not _blocked_now(String(task.get("key", ""))):
			return
		var c := _next_container(h, pos)
		if not c.is_empty():
			_set_task({"kind": "search", "key": "search_%s" % String(c.id), "id": String(c.id), "at": Vector2(c.pos), "house": h})
			return
		# 4. the claim
		if sim.get("base") == null:
			_miss("claim", "base")
			_set_task({"kind": "wait", "key": "wait_claim"})
			return
		if sim.get("uses") == null:
			_miss("claim", "uses")
			_set_task({"kind": "wait", "key": "wait_claim"})
			return
		if _blocked_now("claim"):
			_set_task({"kind": "wait", "key": "wait_claim"})
			return
		_set_task({"kind": "claim", "key": "claim", "house": h})

	## The nearest container of house `h` that is not looted (a {} when there is none or no search module).
	func _next_container(h: int, pos: Vector2) -> Dictionary:
		var sr = sim.get("search")
		if sr == null:
			_miss("search", "search")
			return {}
		var hs = _hs()
		var best := {}
		var best_d := INF
		for c in hs.containers_of(h):
			if sr.is_looted(String(c.id)) or _blocked_now("search_%s" % String(c.id)):
				continue
			var d := pos.distance_to(Vector2(c.pos))
			if d < best_d:
				best_d = d
				best = c
		return best

	# ------------------------------------------------------------------- rescue, loot --

	## The survivor to go for: the nearest not joined whose trip fits the daylight left. {} when none.
	func _rescue_task(me) -> Dictionary:
		var rs = sim.get("rescue")
		if rs == null:
			_miss("rescue", "rescue")
			return {}
		var pos := Vector2(me.x, me.y)
		var base_at := _home_spot()
		var best := {}
		var best_d := INF
		for rec in rs.list():
			if String(rec.state) == "joined" or String(rec.state) == "lost":
				continue
			if _blocked_now("rescue_%s" % String(rec.id)) or Vector2(rec.pos).distance_to(base_at) > MAX_RESCUE_R:
				continue
			var d := pos.distance_to(Vector2(rec.pos))
			if d < best_d:
				best_d = d
				best = rec
		if best.is_empty():
			return {}
		# the trip there (with the clear: a share more) and the way back must end before it is time to be home
		var tiles := best_d + Vector2(best.pos).distance_to(base_at)
		var game_min: float = tiles / sim.avatar.WALK_SPEED * float(sim.min_per_sec) * 1.6 + 25.0
		var home_by := HOME_BY_ATTACK if _attacks_on() else HOME_BY
		if _hour() + game_min / 60.0 > home_by:
			return {}
		return {"kind": "rescue", "key": "rescue_%s" % String(best.id), "id": String(best.id), "house": int(best.house), "room": int(best.room), "at": Vector2(best.pos)}

	## Search the houses near the base for scrap and stores: the nearest house with a container not looted, when scrap is short or there is nothing to rescue.
	func _loot_task(me) -> Dictionary:
		var sr = sim.get("search")
		var hs = _hs()
		if sr == null or hs == null:
			return {}
		var pos := Vector2(me.x, me.y)
		var best := {}
		var best_d := INF
		var home_by := HOME_BY_ATTACK if _attacks_on() else HOME_BY
		for h in hs.town.houses:
			var hid := int(h.id)
			var d0: float = Vector2(Rect2i(h.rect).get_center()).distance_to(pos)
			if d0 > (30.0 if _attacks_on() else 45.0):
				continue
			# the dead in the house cost a shot each and every shot draws more: the cleared houses first, and on the day of an attack only those
			var dead_n := int(hs.dead_in_house(hid))
			if _attacks_on() and dead_n > 0:
				continue
			for c in hs.containers_of(hid):
				if sr.is_looted(String(c.id)) or _blocked_now("search_%s" % String(c.id)):
					continue
				var d := pos.distance_to(Vector2(c.pos)) + 6.0 * float(dead_n)
				# medicine first when there is little: a bite bleeds for good until it is bandaged (one medicine) and may turn (two to treat)
				if float(sim.stock.meds) < 3.0 and float(c.get("loot", {}).get("meds", 0)) > 0.0:
					d -= 30.0
				if d < best_d:
					best_d = d
					best = c
		if best.is_empty():
			return {}
		var trip: float = (best_d + Vector2(best.pos).distance_to(_home_spot())) / sim.avatar.WALK_SPEED * float(sim.min_per_sec) * 1.4 + 15.0
		if _hour() + trip / 60.0 > home_by:
			return {}
		return {"kind": "search", "key": "search_%s" % String(best.id), "id": String(best.id), "at": Vector2(best.pos), "house": int(best.house), "far": true}

	func _home_spot() -> Vector2:
		var b = sim.get("base")
		if b != null and bool(b.claimed):
			var bed: Dictionary = b.prop("bed")
			if not bed.is_empty():
				return Vector2(bed.pos)
			return b.center()
		var hs = _hs()
		return Vector2(sim.get("houses").house(_start_house()).rect.get_center()) if hs != null and _start_house() >= 0 else Vector2.ZERO

	# ----------------------------------------------------------------------- the night --

	func _night_task(me) -> void:
		if not _claimed():
			# no base: it stays in the start house (a quiet corner) and fights what comes
			_set_task({"kind": "home", "key": "home"})
			return
		var sl = sim.get("sleep")
		if sl == null:
			_miss("sleep", "sleep")
			_set_task({"kind": "home", "key": "home"})
			return
		if _attacks_on():
			_set_task({"kind": "home", "key": "home"})    # (the defender takes it from here)
			return
		_set_task({"kind": "sleep", "key": "sleep"})

	## Orders what the perimeter lets it, as the plan's player does: a fence section where it is open, the gate, a tower, a floodlight, as the scrap allows; never more orders
	## waiting for builders than there are hands.
	func _build_orders() -> void:
		var per = sim.get("perimeter")
		if per == null:
			if _claimed():
				_miss("order slots", "perimeter")
			return
		if not _claimed():
			return
		var slots: Array = per.slots()
		var pending := 0
		for s in slots:
			if String(s.state) == "ordered" or String(s.state) == "building" or String(s.get("up", "")) != "":
				pending += 1
		var hands := maxi(1, _crew() - 1)
		if pending >= hands:
			return
		var reserve := MEND_RESERVE if _attacks_on() else 0.0
		if orders == "projects" and per.has_method("order_project"):
			# what the Build page's NEXT card says (a fallen section first, then the plan's order), ordered as far as the scrap goes
			# (the scrap kept back for mending is not kept from the next section: it is the cheapest thing the wall can have, as it was for the slot-wise bot)
			var next: String = per.next_project()
			if next != "":
				var r: Dictionary = per.order_project(next)
				if not bool(r.ok):
					r = per.order_affordable()    # (the NEXT project is not within reach: the page's "build everything I can afford" spends what there is on what is)
				if bool(r.ok):
					stats.orders = int(stats.orders) + int(r.ordered)
			return
		var order := ["door", "gate", "fence", "tower", "floodlight"]
		for kind in order:
			for s in slots:
				if String(s.kind) != kind or (String(s.state) != "open" and String(s.state) != "broken"):
					continue
				var pick := ""
				var pick_hp := -1.0
				var cheapest := ""
				var cheapest_cost := INF
				for k in per.kits_for(String(s.id)):
					if not bool(k.ok):
						continue
					var cost := float(k.scrap)
					if cost < cheapest_cost:
						cheapest_cost = cost
						cheapest = String(k.id)
					if cost <= float(sim.stock.scrap) - reserve and float(k.hp) > pick_hp:
						pick_hp = float(k.hp)
						pick = String(k.id)
				if pick == "":
					pick = cheapest if cheapest != "" and cheapest_cost <= float(sim.stock.scrap) else ""
				if pick == "":
					continue
				if per.order(String(s.id), pick):
					stats.orders = int(stats.orders) + 1
					return

	# ------------------------------------------------------------------------ acting --

	func _act(me, dt: float) -> void:
		var pos := Vector2(me.x, me.y)
		var reach: float = float(sim.reach_of(sim.gun_of(me), me)) - 0.3
		if _target != null and not _valid_target(_target, me, reach):
			_target = null
		_fight_now = _target != null
		# the gun
		var fire := false
		var aim := Vector2.ZERO
		if _target != null:
			aim = _aim_point(me, _target, reach, dt)
			fire = _line_ok and (_t - _target_since) >= REACT_S and float(me.reloading) <= 0.0
		# the butt of the gun is for when the gun cannot fire (a swing sets the gun's cooldown: a bot that swings at every dead one at its feet never lets the pump come back)
		var gun_ready: bool = float(me.reloading) <= 0.0 and int(me.mag) > 0 and not bool(me.gun.get("melee", false))
		if _melee_near(me) and not (gun_ready and _target != null and _line_ok):
			sim.avatar.melee()
		_reload_in_a_lull(me)
		# a dead one at the hands takes them from a search or a claim
		var uses = sim.get("uses")
		if uses != null and uses.busy():
			var heal_session: bool = String(task.get("kind", "")) == "heal"
			if (heal_session and _nearest_chaser(pos) < HEAL_BREAK_R) or (not heal_session and _threat_near(pos)):
				uses.cancel("dead")
		var move := Vector2.ZERO
		var can_fire: bool = _target != null and _line_ok and float(me.reloading) <= 0.0 and int(me.mag) > 0
		var back := _kite(me)
		var cornered := back != Vector2.ZERO and _blocked_ahead(pos, back)
		var sessioning: bool = uses != null and uses.busy()
		if sessioning:
			fire = false
			aim = Vector2.ZERO
		elif can_fire and (back == Vector2.ZERO or cornered or _nearest_chaser(pos) >= KITE_FIRE_D):
			pass    # (stands and shoots)
		else:
			# the gun is not ready (a reload, the pump) or the dead are at the feet: step back from them (they walk at a quarter of the avatar's pace), else go on with the task
			move = back if back != Vector2.ZERO else _avoid(me, _run_task(me, dt))
			if back != Vector2.ZERO:
				fire = false
		sim.avatar.set_input(move, aim, fire)

	## How far the nearest of the dead after somebody is (INF when none within KITE_R).
	func _nearest_chaser(pos: Vector2) -> float:
		var best := INF
		for z in sim.zombies:
			if _live(z) and _chasing(z):
				best = minf(best, pos.distance_to(Vector2(z.x, z.y)))
		return best

	## Whether a wall (or furniture) is within a step of the way back: nowhere to go.
	func _blocked_ahead(pos: Vector2, dir: Vector2) -> bool:
		var at := pos + dir.normalized() * 0.8
		return sim.world.is_solid(sim.world.solid_p, at.x, at.y)

	## The way away from the dead that are within KITE_R and after somebody, when there are any (zero when none).
	func _kite(me) -> Vector2:
		var pos := Vector2(me.x, me.y)
		var push := Vector2.ZERO
		var n := 0
		for z in sim.zombies:
			if not _live(z) or not _chasing(z):
				continue
			var v := pos - Vector2(z.x, z.y)
			var d := v.length()
			if d >= KITE_R or d < 0.05:
				continue
			push += v / d * ((KITE_R - d) / KITE_R)
			n += 1
		if n == 0:
			return Vector2.ZERO
		return push.normalized()

	## Whether one of the dead that is after somebody (or any, close) is awake within THREAT_R.
	func _threat_near(pos: Vector2) -> bool:
		for z in sim.zombies:
			if not _live(z):
				continue
			var d := pos.distance_to(Vector2(z.x, z.y))
			if d <= THREAT_R and (z.state == "chase" or z.state == "hunt" or z.state == "approach" or z.state == "attack" or z.state == "breach" or d <= QUIET_R * 0.6):
				return true
		return false

	## The task's walk and hands: the move direction (zero when it stands).
	func _run_task(me, dt: float) -> Vector2:
		var pos := Vector2(me.x, me.y)
		match String(task.get("kind", "")):
			"travel":
				return _goto(me, Vector2(task.at), 1.5, dt)
			"clear":
				var h := int(task.get("house", -1))
				var room := int(task.get("room", -1))
				var spots := _dead_in_house(h) if room < 0 else _dead_in_room(room)
				if spots.is_empty():
					_done("clear")
					return Vector2.ZERO
				return _goto(me, _nearest(spots, pos), 0.8, dt)
			"reveal":
				var cl = sim.get("clearing")
				var r := int(task.get("room", -1))
				if cl == null or cl.is_revealed(r):
					_done("reveal")
					return Vector2.ZERO
				var rect: Rect2i = _hs().room(r).rect
				return _goto(me, Vector2(rect.position) + Vector2(rect.size) * 0.5, 1.2, dt)
			"search":
				return _task_search(me, dt)
			"claim":
				return _task_claim(me, dt)
			"rescue":
				return _task_rescue(me, dt)
			"build":
				return _task_build(me, dt)
			"heal":
				return _task_heal(me)
			"nap":
				return _task_nap(me, dt)
			"sleep":
				return _task_sleep(me, dt)
			"home":
				return _goto(me, _home_spot(), 1.2, dt)
		return Vector2.ZERO

	func _done(why: String) -> void:
		task = {}
		_path = []
		_think_t = 0.0

	func _give_up(key: String, why: String) -> void:
		stats.gave_up = int(stats.gave_up) + 1
		_block(key)
		mark("gave_up", {"task": key, "why": why})
		task = {}
		_path = []
		_think_t = 0.0

	## E on the candidate of `kind` / `id`: {"state": "wait" (the hands are not still yet, or it was pressed a moment ago), "none" (no such candidate), "refused" (it is there and says no: "why"),
	## "ok" (used)}.
	func _press(kind: String, id: String) -> Dictionary:
		var me = _me()
		if _t - _pressed_at < 0.5 or (me != null and me.input_move.length() > 0.2):
			return {"state": "wait"}
		var in_the_way: bool = _nearest_chaser(Vector2(me.x, me.y)) < HEAL_CLEAR_R if String(task.get("kind", "")) == "heal" else _threat_near(Vector2(me.x, me.y))
		if me != null and in_the_way:
			if float(task.get("tw_since", -1.0)) < 0.0:
				task["tw_since"] = _t
			if _t - float(task.tw_since) < THREAT_WAIT_S:
				return {"state": "wait"}    # (the dead first: a search is four seconds of standing still)
		else:
			task["tw_since"] = -1.0
		var list: Array = sim.interact.candidates()
		for c in list:
			if String(c.get("kind", "")) == kind and (id == "" or String(c.get("id", "")) == id):
				_pressed_at = _t
				if not bool(c.get("ok", true)):
					return {"state": "refused", "why": String(c.get("why", ""))}
				var r: Dictionary = sim.interact.use(c)
				if bool(r.get("ok", false)):
					return {"state": "ok", "r": r}
				return {"state": "refused", "why": String(r.get("why", ""))}
		return {"state": "none"}

	## Seconds the task has been at its place without getting its press through (a refusal that does not pass is given up after GIVE_UP_S). A press that is used again and again and
	## never ends the job (the session is cancelled each time: a bleeding wound cancels it, uses.gd `update`) counts as a refusal after SESSION_TRIES.
	func _waited(r: Dictionary) -> float:
		var state := String(r.get("state", ""))
		if state == "wait":
			return 0.0
		if state == "ok":
			task["oks"] = int(task.get("oks", 0)) + 1
			if int(task.oks) >= SESSION_TRIES:
				return GIVE_UP_S + 1.0
			return 0.0
		if float(task.get("at_since", -1.0)) < 0.0:
			task["at_since"] = _t
		return _t - float(task.at_since)

	func _task_search(me, dt: float) -> Vector2:
		var uses = sim.get("uses")
		var sr = sim.get("search")
		var id := String(task.get("id", ""))
		if sr == null or uses == null:
			_miss("search", "uses")
			_done("search")
			return Vector2.ZERO
		if sr.is_looted(id):
			_done("search")
			return Vector2.ZERO
		var at: Vector2 = task.at
		var pos := Vector2(me.x, me.y)
		if pos.distance_to(at) > 0.5:
			return _goto(me, at, 0.25, dt)
		if uses.busy():
			return Vector2.ZERO
		var r := _press("container", id)
		if _waited(r) > GIVE_UP_S:
			_give_up(String(task.key), String(r.get("why", "no candidate")))
		return Vector2.ZERO

	func _task_claim(me, dt: float) -> Vector2:
		var base = sim.get("base")
		var h := int(task.get("house", -1))
		var spot: Vector2 = base.claim_spot()
		var pos := Vector2(me.x, me.y)
		if sim.get("uses").busy():
			return Vector2.ZERO
		if _claimed():
			_done("claim")
			return Vector2.ZERO
		if spot == Vector2.ZERO or pos.distance_to(spot) > 1.2:
			return _goto(me, spot, 0.8, dt)
		var r := _press("claim", "")
		if _waited(r) > GIVE_UP_S:
			var why := String(r.get("why", "no candidate"))
			mark("claim_refused", {"why": why})
			_give_up("claim", why)
		return Vector2.ZERO

	func _task_rescue(me, dt: float) -> Vector2:
		var rs = sim.get("rescue")
		var id := String(task.get("id", ""))
		var rec: Dictionary = rs.get_record(id)
		if rec.is_empty() or String(rec.state) == "joined" or String(rec.state) == "lost":
			_done("rescue")
			return Vector2.ZERO
		var pos := Vector2(me.x, me.y)
		var room := int(task.get("room", -1))
		# the survivor's room first: nobody speaks while a dead one is in it
		var dead := _dead_in_room(room)
		if not dead.is_empty():
			return _goto(me, _nearest(dead, pos), 0.8, dt)
		var at: Vector2 = task.at
		if pos.distance_to(at) > 1.3:
			return _goto(me, at, 1.0, dt)
		if rs.near(me, 1.9) != id:
			var w := _waited({"state": "none"})
			if w > GIVE_UP_S:
				_give_up(String(task.key), "not near (%s)" % String(rec.state))
			return Vector2.ZERO
		# the card: Come with me, else Stay (and not again for a while), else Take this
		var card: Dictionary = rs.talk(id)
		var come := false
		for c in card.get("choices", []):
			if String(c.id) == "come" and bool(c.ok):
				come = true
		if come:
			var r: Dictionary = rs.choose(id, "come")
			mark("rescue_asked", {"id": id, "ok": bool(r.get("ok", false))})
			_done("rescue")
		else:
			var why := ""
			for c in card.get("choices", []):
				if String(c.id) == "come":
					why = String(c.get("why", ""))
			mark("rescue_refused", {"id": id, "why": why if why != "" else String(card.get("line", ""))})
			rs.choose(id, "stay")
			_block(String(task.key), 240.0)
			_done("rescue")
		return Vector2.ZERO

	## The avatar's own medicine: E on the candidate, then stand still until the session is over (it ends when the hands move).
	func _task_heal(me) -> Vector2:
		var uses = sim.get("uses")
		var id := String(task.get("id", ""))
		var done: bool = float(me.bleeding) <= 0.0 if id == "bandage" else (float(me.infected_at) < 0.0 or float(sim.stock.meds) < float(sim.medical.CURE_MEDS))
		if done or uses == null:
			if done:
				stats.heals = int(stats.get("heals", 0)) + 1
			_done("heal")
			return Vector2.ZERO
		if uses.busy():
			return Vector2.ZERO
		var r := _press("selfcare", id)
		if _waited(r) > GIVE_UP_S:
			_give_up(String(task.key), String(r.get("why", "no candidate")))
		return Vector2.ZERO

	func _task_nap(me, dt: float) -> Vector2:
		var sl = sim.get("sleep")
		var spot := _home_spot()
		var pos := Vector2(me.x, me.y)
		if pos.distance_to(spot) > BED_REACH:
			return _goto(me, spot, 1.0, dt)
		# sleep until the hour that heals it (4 hit points an hour), at most to the evening
		var hours := clampf((100.0 - float(me.hp)) / 4.0, 1.0, 10.0)
		var until := fposmod(_hour() + hours, 24.0)
		var r: Dictionary = sl.begin("%.1f" % until)
		if bool(r.get("ok", false)):
			stats.naps = int(stats.naps) + 1
			mark("nap", {"until": snappedf(until, 0.1), "hp": snappedf(float(me.hp), 0.1)})
		else:
			_block("nap", 60.0)
		_done("nap")
		return Vector2.ZERO

	func _task_sleep(me, dt: float) -> Vector2:
		var sl = sim.get("sleep")
		var spot := _home_spot()
		var pos := Vector2(me.x, me.y)
		if pos.distance_to(spot) > BED_REACH:
			return _goto(me, spot, 1.0, dt)
		var can: Dictionary = sl.can_sleep("dawn")
		if not bool(can.ok):
			# the dead are about, a wound to see to: it stays up, and fights what comes
			task["why"] = String(can.why)
			return Vector2.ZERO
		var r := _press("bed", "")
		if _waited(r) > GIVE_UP_S:
			var b: Dictionary = sl.begin("dawn")
			if not bool(b.get("ok", false)):
				_block("sleep", 10.0)
				task["at_since"] = -1.0
		return Vector2.ZERO

	## The place of the nearest awake dead one within `r` of `at`, Vector2.ZERO when there is none.
	func _awake_hostile_near(at: Vector2, r: float) -> Vector2:
		var best := Vector2.ZERO
		var best_d := INF
		for z in sim.zombies:
			if not _live(z):
				continue
			var d := at.distance_to(Vector2(z.x, z.y))
			if d < r and d < best_d:
				best_d = d
				best = Vector2(z.x, z.y)
		return best

	# --------------------------------------------------------------------------- walking --

	## The direction to walk toward `dest` (zero within `arrive`, and standing while it is within arrive + 0.6): along the people's grid; a stuck walk gives the task up.
	func _goto(me, dest: Vector2, arrive: float, dt: float) -> Vector2:
		var pos := Vector2(me.x, me.y)
		var d := pos.distance_to(dest)
		if _holding:
			if d <= arrive + 0.6:
				return Vector2.ZERO
			_holding = false
		elif d <= arrive:
			_holding = true
			_path = []
			return Vector2.ZERO
		if pos.distance_to(_last_pos) < 0.2 * sim.avatar.WALK_SPEED * dt:
			_stuck_t += dt
		else:
			_stuck_t = 0.0
		_last_pos = pos
		if _stuck_t >= GIVE_UP_S and not task.is_empty():
			_give_up(String(task.get("key", "")), "stuck at %.1f,%.1f" % [pos.x, pos.y])
			return Vector2.ZERO
		_path_t -= dt
		if _path.is_empty() or _path_goal.distance_to(dest) > 0.5 or _path_t <= 0.0 or _stuck_t >= STUCK_S:
			_path = sim.path_p.find(sim.world.solid_p, pos.x, pos.y, dest.x, dest.y)
			if _path.is_empty():
				_path = [dest]
			_path_i = 0
			_path_goal = dest
			_path_t = REPATH_S
			if _stuck_t >= STUCK_S:
				_stuck_t = _stuck_t    # (kept: the give-up clock runs on)
		while _path_i < _path.size() - 1 and pos.distance_to(Vector2(_path[_path_i])) < WAYPOINT_R:
			_path_i += 1
		var wp := Vector2(_path[mini(_path_i, _path.size() - 1)])
		return (wp - pos).normalized()

	# ---------------------------------------------------------------------------- the fight --

	## The nearest awake dead one worth a shot with a clear line (see `_worth`).
	func _pick_target(me) -> void:
		var reach: float = float(sim.reach_of(sim.gun_of(me), me)) - 0.3
		var here := Vector2(me.x, me.y)
		var from: Vector2 = sim.avatar.shoulder(me)
		var best = null
		var best_key := INF
		# the hands are still, or a few of the dead are on its heels: a person turns and shoots two walkers rather than walk the street with them behind for an hour (a swarm is walked away from)
		var still := _stationary_wanted(here) or _chased_by_few(here)
		for z in sim.zombies:
			if not _live(z):
				continue
			var d := here.distance_to(Vector2(z.x, z.y - BODY))
			if d > reach or not _worth(z, d, still):
				continue
			var key := d - (3.0 if _chasing(z) else 0.0)
			if key < best_key:
				# a clear line (the first thing the shot meets is this one)
				var ang := (Vector2(z.x, z.y - BODY) - from).angle()
				if sim.avatar.trace(from, ang, reach + 0.3).z == z:
					best_key = key
					best = z
		if best != _target:
			_target = best
			_target_since = _t
			_aim_t = 0.0
			_line_ok = false

	func _chasing(z) -> bool:
		return z.state == "chase" or z.state == "hunt" or z.state == "approach" or z.state == "attack" or z.state == "breach"

	## Whether one to FEW_CHASERS of the street's dead are after the avatar within CHASE_COUNT_R tiles (more is a crowd, which is walked away from).
	func _chased_by_few(here: Vector2) -> bool:
		var n := 0
		for z in sim.zombies:
			if (z.state == "chase" or z.state == "hunt") and _live(z) and (String(z.hunt_id) == _player_id() or String(z.hunt_id) == "") and here.distance_to(Vector2(z.x, z.y)) <= CHASE_COUNT_R:
				n += 1
		return n >= 1 and n <= FEW_CHASERS

	## The street's rule: a shot wakes every dead one within 30 tiles and sends them after the shooter (scripts/town/dormant_dead.gd `noise`), and the avatar walks four times as fast as a
	## walker. So the gun is for what has to be put down: the dead of the room or house being cleared, whatever is close enough to bite, and (when the hands must stand still for
	## a search, a claim or a talk) whatever is coming for them. The rest is walked round.
	func _worth(z, d: float, still_wanted: bool) -> bool:
		if d <= CLOSE_R:
			return true
		if _in_clear_zone(z):
			return true
		return _chasing_me(z) and d <= (STILL_FIRE_R if still_wanted else WALK_FIRE_R)

	func _chasing_me(z) -> bool:
		if z.state == "chase" or z.state == "hunt":
			return String(z.hunt_id) == _player_id() or String(z.hunt_id) == ""
		return _chasing(z)

	## Whether the dead one stands in the house or room the task is clearing.
	func _in_clear_zone(z) -> bool:
		var hs = _hs()
		if hs == null:
			return false
		match String(task.get("kind", "")):
			"clear":
				var room := int(task.get("room", -1))
				if room >= 0:
					return int(hs.room_at(z.x, z.y)) == room
				return int(hs.house_at(z.x, z.y)) == int(task.get("house", -2))
			"rescue":
				return int(hs.room_at(z.x, z.y)) == int(task.get("room", -2))
			"reveal", "search", "claim":
				return int(hs.house_at(z.x, z.y)) == int(task.get("house", _start_house())) and int(task.get("house", _start_house())) >= 0
		return false

	## Whether the hands are about to be still (at the place of a search, a claim, a talk, a bed).
	func _stationary_wanted(pos: Vector2) -> bool:
		match String(task.get("kind", "")):
			"search":
				return pos.distance_to(Vector2(task.get("at", pos))) < 3.0
			"claim":
				return true
			"rescue":
				return pos.distance_to(Vector2(task.get("at", pos))) < 3.0
			"sleep", "nap":
				return true
		return false

	## The step away from the dead near the feet: what is awake within AVOID_R pushes the walk the other way (the near ones harder), the standing ones a little.
	func _avoid(me, move: Vector2) -> Vector2:
		if move == Vector2.ZERO:
			return move
		var pos := Vector2(me.x, me.y)
		var push := Vector2.ZERO
		for z in sim.zombies:
			if not _live(z):
				continue
			var v := pos - Vector2(z.x, z.y)
			var d := v.length()
			if d >= AVOID_R or d < 0.05:
				continue
			var w := (AVOID_R - d) / AVOID_R
			push += v / d * w * w * (1.0 if _chasing(z) or z.state == "wander" else 0.6)
		if push == Vector2.ZERO:
			return move
		var out := move.normalized() + push * AVOID_GAIN
		return out.normalized() if out.length() > 0.05 else move

	func _valid_target(z, me, reach: float) -> bool:
		if z == null or z.remove or not _live(z) or not sim.zombies.has(z):
			return false
		return Vector2(me.x, me.y).distance_to(Vector2(z.x, z.y - BODY)) <= reach

	func _aim_point(me, z, reach: float, dt: float) -> Vector2:
		var at := Vector2(z.x, z.y - BODY)
		var from: Vector2 = sim.avatar.shoulder(me)
		var base := (at - from).angle()
		_aim_t -= dt
		if _aim_t <= 0.0:
			_aim_t = JITTER_S
			_jitter = _rng.randfn(0.0, AIM_JITTER)
			_line_ok = sim.avatar.trace(from, base + _jitter, reach + 0.3).z != null
		return from + Vector2.from_angle(base + _jitter) * from.distance_to(at)

	func _melee_near(me) -> bool:
		var here := Vector2(me.x, me.y - 0.15)
		for z in sim.zombies:
			if _live(z) and here.distance_to(Vector2(z.x, z.y - BODY)) <= MELEE_R:
				return true
		return false

	func _reload_in_a_lull(me) -> void:
		if float(me.reloading) > 0.0 or me.gun.get("melee", false) or int(me.mag) > MAG_LOW or int(me.mag) >= int(me.gun.get("mag", 0)):
			return
		if float(sim.stock.ammo) < float(sim.shot_cost(me)):
			return
		var here := Vector2(me.x, me.y)
		for z in sim.zombies:
			if _live(z) and here.distance_to(Vector2(z.x, z.y)) < LULL_R and (z.state == "chase" or z.state == "hunt" or z.state == "approach" or z.state == "attack"):
				return
		sim.avatar.reload()
