## Sleeping in the base's bed (One House, WP3, plan 1.10): E at the bed, "Sleep until dawn". The quiet nights are passed this way: the module runs the colony ahead with
## `sim.fast_forward` (the mechanism of round 17: the effects are a sink, the sounds are dropped, the rest stays) a few steps at a time, so that a frame is never long,
## until dawn (or the hour asked for), and wakes the avatar when something is near.
##
## REFUSED (`can_sleep`) with a reason: no bed yet (nothing claimed), the avatar is down or hurt and bleeding, an attack is on and it is dusk to dawn ("The dead are coming
## tonight"), by day for "dawn", a dead one is after somebody or walks about near the base, or it is nearly morning already.
## WAKES (`wake`, with the reason): a dead one comes within WAKE_R of the avatar, a shot is heard or a kill is made, the avatar is hurt, the run is over, or whoever calls `wake`
## (the sleep screen's key). It heals the avatar a little each hour (HEAL_PER_H) and keeps the street's sleeping dead asleep meanwhile (`field.pause_wake`).
## `advance()` runs one frame's worth; `update(dt)` calls it, so the sleep runs by itself under the town's own step (a nested step of the fast-forward finds the module
## busy and goes on). Another caller (the sleep screen) may call `advance()` too: it only makes the sleep quicker.
##
## Events: {"type": "sleep", "on": true, "why": ""} and {"type": "sleep", "on": false, "why": "dawn" | "Something is near" | ..., "hours": slept}.
## Candidates: kind "bed" ("Sleep until dawn"). Nothing is saved: a sleep never goes into a save (the save is taken awake).
extends RefCounted

## A dead one after somebody within THREAT_R of the base, or one that walks about within ABOUT_R of it (or stands within CLOSE_R), keeps the avatar from sleeping. The ones that stand
## farther off are not in the way: they are put back to sleep where they stand as the avatar lies down (`begin`), so that the street is quiet all night (they are woken again, as ever, by
## whoever comes near them in the morning). Without this the first night could never be slept: the dark wakes the dead far and wide, and one is always about.
const THREAT_R := 40.0
const ABOUT_R := 12.0
const CLOSE_R := 6.0
const WAKE_R := 12.0
const BED_REACH := 1.8
const HEAL_PER_H := 4.0
## Steps of the colony per call of `fast_forward`, and the real microseconds a call of `advance` may take (0 gives one chunk a call: the tests).
const CHUNK_STEPS := 12
const BUDGET_US := 10000
const NEARLY_MIN := 5.0
const DAWN := 6.5
## The sleep ends this many game minutes past the hour asked, so that the clock has crossed it (dawn is the day's start: the phase turns at the hour itself).
const PAST_MIN := 0.1

var sim
var enabled := true
## Microseconds `advance` may spend (a test sets 0 to take one chunk per call).
var budget_us := BUDGET_US
var _on := false
var _goal := 0.0
var _hours := 0.0
var _hp := 0.0
var _shots := 0
var _kills := 0
var _busy := false
var _pause0 := false


func setup(s) -> void:
	sim = s


func start() -> void:
	if _on:
		_set_pause(false)
	_on = false
	_busy = false
	_goal = 0.0
	_hours = 0.0


func active() -> bool:
	return _on


func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


func _attacks_on() -> bool:
	var sc = sim.scenario
	return sc != null and sc.has_method("attacks_on") and bool(sc.attacks_on())


func _dawn_hour() -> float:
	var se = sim.get("seasons")
	return float(se.dawn_hour()) if se != null and se.has_method("dawn_hour") else DAWN


## Game minutes from now to the hour `until` names: "dawn" (the day's start), "6:30" or "22" or "5.5" (an hour; the next time the clock shows it). -1 when it is not an hour.
func _minutes_to(until: String) -> float:
	var target := 0.0
	if until == "dawn":
		target = _dawn_hour() * 60.0
	else:
		var parts := until.split(":")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			target = float(int(parts[0])) * 60.0 + float(int(parts[1]))
		elif until.is_valid_float():
			target = float(until) * 60.0
		else:
			return -1.0
	return fposmod(target - fposmod(float(sim.minutes), 1440.0), 1440.0) + PAST_MIN


## What of the awake dead stands in the way of sleep near `at`: "" nothing, "after" one that is after somebody within THREAT_R, "about" one that walks about within ABOUT_R or stands
## within CLOSE_R.
func _in_the_way(at: Vector2) -> String:
	var about := false
	for z in sim.zombies:
		if z.state == "dead" or z.state == "dying" or z.state == "retreat":
			continue
		var d := Vector2(z.x - at.x, z.y - at.y).length()
		match String(z.state):
			"chase", "hunt", "approach", "attack", "breach":
				if d < THREAT_R:
					return "after"
			"wander":
				if d < ABOUT_R:
					about = true
			_:
				if d < CLOSE_R:
					about = true
	return "about" if about else ""


## Is a dead one awake within `r` tiles of `at` (the sleeping ones are records, not in `sim.zombies`).
func _dead_near(at: Vector2, r: float) -> bool:
	for z in sim.zombies:
		if z.state == "dead" or z.state == "dying":
			continue
		if Vector2(z.x - at.x, z.y - at.y).length() < r:
			return true
	return false


## {"ok", "why"}: may the avatar sleep now.
func can_sleep(until: String = "dawn") -> Dictionary:
	var p = _lead()
	var base = sim.get("base")
	if p == null or p.dead or p.turned or p.downed or p.away != null:
		return {"ok": false, "why": "You cannot sleep now"}
	if base == null or not bool(base.claimed):
		return {"ok": false, "why": "You have no bed yet: claim the house"}
	if sim.over != "":
		return {"ok": false, "why": "It is over"}
	if _attacks_on() and sim.phase != "day":
		return {"ok": false, "why": "The dead are coming tonight: stay awake"}
	if until == "dawn" and sim.phase == "day":
		return {"ok": false, "why": "It is too early to sleep"}
	var mins := _minutes_to(until)
	if mins < 0.0:
		return {"ok": false, "why": "Sleep until when?"}
	if mins < NEARLY_MIN:
		return {"ok": false, "why": "It is nearly morning"}
	if float(p.bleeding) > 0.0:
		return {"ok": false, "why": "You are bleeding: see to the wound first"}
	var way := _in_the_way(base.center())
	if way == "after":
		return {"ok": false, "why": "The dead are after you: you cannot sleep"}
	if way == "about":
		return {"ok": false, "why": "The dead are about: you cannot sleep"}
	return {"ok": true, "why": ""}


## Goes to sleep until `until`: {"ok", "why", "minutes"}. In the house, and not far from the bed (the E prompt is at the bed; a bot may call this from anywhere in it).
func begin(until: String = "dawn") -> Dictionary:
	if _on:
		return {"ok": true, "why": "", "minutes": maxf(_goal - float(sim.clock_min), 0.0)}
	var can := can_sleep(until)
	if not bool(can.ok):
		return can
	var p = _lead()
	var hs = sim.get("houses")
	if hs != null and int(hs.house_at(p.x, p.y)) != int(sim.base.house):
		return {"ok": false, "why": "Go to your bed first"}
	var mins := _minutes_to(until)
	_goal = float(sim.clock_min) + mins
	_hours = 0.0
	_hp = float(p.hp)
	_shots = _shots_fired()
	_kills = int(sim.kills)
	_on = true
	_set_pause(true)
	var field = sim.get("field")
	if field != null and field.has_method("sleep_all"):
		field.sleep_all()    # (the ones that stand or wander far off lie down again where they are: the street is quiet while the avatar sleeps)
	_hands_off(p)
	sim.events.append({"type": "sleep", "on": true, "why": ""})
	return {"ok": true, "why": "", "minutes": mins}


func _shots_fired() -> int:
	var n := 0
	for q in sim.people:
		n += int(q.stats.get("shots", 0))
	return n


func _hands_off(p) -> void:
	p.input_move = Vector2.ZERO
	p.input_fire = false
	p.input_melee = false
	p.input_reload = false
	p.moving = false


## While asleep nothing wakes the street's dead: the avatar is not there to be noticed.
func _set_pause(on: bool) -> void:
	var f = sim.get("field")
	if f == null or f.get("pause_wake") == null:
		return
	if on:
		_pause0 = bool(f.pause_wake)
		f.pause_wake = true
	else:
		f.pause_wake = _pause0


## Wakes the avatar (for a reason the screen shows).
func wake(why: String = "woken") -> void:
	if not _on:
		return
	_on = false
	_set_pause(false)
	sim.events.append({"type": "sleep", "on": false, "why": why, "hours": _hours})


## One frame's worth of sleep: the colony runs ahead a chunk at a time within `budget_us`, and the avatar wakes if something is near.
func advance() -> void:
	if not _on or _busy:
		return
	_busy = true
	var t0 := Time.get_ticks_usec()
	while _on:
		var p = _lead()
		if p == null or p.dead or p.turned or p.downed:
			wake("down")
			break
		var left := _goal - float(sim.clock_min)
		if left <= 1.0e-6:
			wake("dawn")
			break
		var before := float(sim.clock_min)
		_hands_off(p)
		sim.fast_forward(left, CHUNK_STEPS)
		var slept := (float(sim.clock_min) - before) / 60.0
		_hours += slept
		if sim.over != "":
			wake("over")
			break
		p = _lead()
		if p == null or p.dead or p.turned or p.downed:
			wake("down")
			break
		p.hp = minf(100.0, float(p.hp) + HEAL_PER_H * slept)
		var why := _disturbance(p)
		if why != "":
			wake(why)
			break
		_hp = float(p.hp)
		if float(_goal) - float(sim.clock_min) <= 1.0e-6:
			wake("dawn")
			break
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
	_busy = false


## What wakes the avatar now ("" nothing): a dead one within WAKE_R, a shot or a kill, a wound (hit points lower than a step ago, healing aside).
func _disturbance(p) -> String:
	if _dead_near(Vector2(p.x, p.y), WAKE_R):
		return "Something is near"
	if _shots_fired() != _shots or int(sim.kills) != _kills:
		return "A shot woke you"
	if float(p.hp) < _hp - 0.001:
		return "You are hurt"
	return ""


func update(_dt: float) -> void:
	if _on and not _busy:
		advance()


# --------------------------------------------------------------------------- E use --

## "Sleep until dawn" at the bed of a claimed base (shown with the reason when it is refused).
func candidates(p) -> Array:
	var out: Array = []
	var base = sim.get("base")
	if not enabled or base == null or not bool(base.claimed) or _on:
		return out
	var bed: Dictionary = base.prop("bed")
	if bed.is_empty():
		return out
	var d := Vector2(p.x, p.y).distance_to(Vector2(bed.pos))
	if d > BED_REACH:
		return out
	var can := can_sleep("dawn")
	out.append({"kind": "bed", "id": "bed", "label": "Sleep until dawn", "pos": Vector2(bed.pos), "dist": d, "ok": bool(can.ok), "why": String(can.why)})
	return out


func use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) != "bed":
		return {}
	var r := begin("dawn")
	return {"ok": bool(r.ok), "line": "You lie down." if bool(r.ok) else "", "why": String(r.get("why", ""))}


func save() -> Dictionary:
	return {}


## A save is taken awake and a load is awake.
func load_state(_d: Dictionary) -> void:
	start()
