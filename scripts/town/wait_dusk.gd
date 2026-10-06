## WAIT UNTIL DUSK (One House, PACE): the toolbar's sun-setting button and the key `.` run the colony ahead from now to the bell (BELL_BEFORE_MIN game minutes before it: 18:55 with the bell at 19:00), a few
## steps a frame (RATE_MIN_PER_S game minutes a real second within BUDGET_US microseconds a frame), so that the long afternoon of a day with nothing to do passes in a few seconds and a frame is never long. A part of the town's rules (`TownSim.PARTS` "waiter", `sim.waiter`); the button, the
## words and the confirm are scripts/ui/wait_button.gd's, which calls `advance()` every frame while `active()`. It is `Sleep`'s mechanism (`sim.fast_forward`: the effects are a sink, the sounds are dropped, the
## banners, the bell and the rest stay) with the opposite rules: sleep is for the night and ends at dawn, this is for the day and ends before the bell, and what stops it is about the DEAD and the people, not about
## being in the bed.
##
## REFUSED (`can_wait`, `begin`) with a reason: nothing claimed yet ("Claim a house first": the arrival day has its own dusk pressure), the avatar is down or away, the run is over, it is not day or it is nearly the bell,
## the avatar is at a task (`uses.busy()`), or one of the STOPS below holds already. One more is a question and not a refusal: with the attacks on (`scenario.attacks_on()`: the dead come tonight) and the Build page's
## plan not READY BY DUSK (its verdict is TIGHT or NOT YET: `PlanClock.assess`), `begin()` answers {"ok": false, "ask": "The plan is not ready. Wait anyway?"} and starts only when called again with `confirmed`.
## STOPS (`_stop_reason`, looked at after every chunk of steps; the event says why): an awake dead one within NEAR_R (25) tiles of the avatar or of the base; a shot fired in the last SHOT_S (20) seconds by anyone of
## the crew; somebody bleeding or infected; the avatar hurt (her hit points lower than the chunk before) or down; the avatar farther than OUT_R (25) tiles from the base and outside its compound (you do not skip
## time while you are out in the town); the run over; whoever calls `cancel` (the view: a card or a page that opens, a key, a click). A build FINISHED (`project_done`, `slot_built`) is not a stop but a HOLD: the
## chunks wait HOLD_MS real milliseconds (the colony goes on at its own pace meanwhile, in the frames of the game itself) so that the player sees it, and then run on; at most one hold in HOLD_COOL_MS.
## THE END is `bell`: the clock stands at BELL_BEFORE_MIN minutes before the bell (it rings a couple of real seconds later, as it always does, banner and night event with it: nothing of the bell is touched here).
##
## Events: {"type": "wait", "on": true, "goal": game minutes} and {"type": "wait", "on": false, "code": "bell" | "dead" | "shots" | "bleeding" | "infected" | "hurt" | "down" | "out" | "card" | "input" | "over",
## "why": the words ("the dead are near"), "early": bool, "minutes": game minutes waited}. Nothing is saved: a wait never goes into a save (the save is taken awake).
extends RefCounted

const PlanClock := preload("res://scripts/ui/plan_clock.gd")

const BELL_BEFORE_MIN := 5.0
const NEAR_R := 25.0
const OUT_R := 25.0
const SHOT_S := 20.0
## Steps of the colony per call of `fast_forward`, and the real microseconds a call of `advance` may take (0 gives one chunk a call: a scripted run). A step is 1/15 of a game minute in the town: 12 steps are 0.8 minutes.
const CHUNK_STEPS := 12
const BUDGET_US := 6000
## The pace of the time-lapse: game minutes a real second (75 times the game's own two): a day's 655 minutes pass in about four and a half seconds, a few milliseconds of a frame.
const RATE_MIN_PER_S := 150.0
const HOLD_MS := 2000
const HOLD_COOL_MS := 4000
## The words of the questions and the refusals that are not a stop.
const ASK_PLAN := "The plan is not ready. Wait anyway?"
const NEED_CLAIM := "Claim a house first"
const WHY := {
	"dead": "the dead are near",
	"shots": "shots were fired just now",
	"bleeding": "somebody is bleeding",
	"infected": "somebody is infected",
	"hurt": "you are hurt",
	"down": "you are down",
	"out": "you are out in the town: go home first",
	"card": "a card needs you",
	"input": "you took the wheel",
	"over": "the run is over",
	"busy": "you are at a task",
	"night": "the wait is for the day",
	"late": "it is nearly the bell",
}

var sim
var enabled := true
## Microseconds `advance` may spend (a scripted run sets 0 to take one chunk per call).
var budget_us := BUDGET_US
## How long (real milliseconds) a finished build holds the wait; 0 for a scripted run that has no wall clock to wait on.
var hold_ms := HOLD_MS
var _on := false
var _goal := 0.0
var _waited := 0.0
var _hp := 0.0
var _busy := false
var _shots := 0
var _last_shot_t := -1000.0
var _hold_until := 0
var _hold_cool_until := 0
## What the last wait ended with: {"code", "why", "early", "minutes"} (a scripted run reads it).
var last: Dictionary = {}
## How many times a build held the wait (a scripted run reads it).
var holds := 0


func setup(s) -> void:
	sim = s


func start() -> void:
	_on = false
	_busy = false
	_goal = 0.0
	_waited = 0.0
	_hold_until = 0
	_hold_cool_until = 0
	_shots = _shots_fired()
	_last_shot_t = -1000.0
	last = {}
	holds = 0


func active() -> bool:
	return _on


## A step of the rules (every step, the nested ones of a fast-forward too): when the last shot of the crew was fired.
func update(_dt: float) -> void:
	var n := _shots_fired()
	if n > _shots:
		_last_shot_t = float(sim.t)
	_shots = n


func _shots_fired() -> int:
	var n := 0
	for q in sim.people:
		n += int(q.stats.get("shots", 0))
	return n


func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


func _attacks_on() -> bool:
	var sc = sim.scenario
	return sc != null and sc.has_method("attacks_on") and bool(sc.attacks_on())


func _dusk_hour() -> float:
	var se = sim.get("seasons")
	return float(se.dusk_hour()) if se != null and se.has_method("dusk_hour") else 19.0


## Game minutes from now to the end of the wait: the bell's hour less BELL_BEFORE_MIN (negative when it is past).
func minutes_to_go() -> float:
	return _dusk_hour() * 60.0 - BELL_BEFORE_MIN - fposmod(float(sim.minutes), 1440.0)


## Is an awake dead one within `r` tiles of `at` (the sleeping ones are records, not in `sim.zombies`).
func _dead_near(at: Vector2, r: float) -> bool:
	for z in sim.zombies:
		if z.state == "dead" or z.state == "dying":
			continue
		if Vector2(z.x - at.x, z.y - at.y).length() < r:
			return true
	return false


## The code of what stops a wait now ("" nothing): see the header. The avatar's hurt is the caller's (it has the hit points of a chunk ago).
func _stop_reason(p) -> String:
	var base = sim.get("base")
	var here := Vector2(p.x, p.y)
	if _dead_near(here, NEAR_R) or (base != null and _dead_near(Vector2(base.center()), NEAR_R)):
		return "dead"
	if float(sim.t) - _last_shot_t < SHOT_S:
		return "shots"
	var infected := false
	for q in sim.people:
		if q.dead or q.turned or q.away != null:
			continue
		if float(q.bleeding) > 0.0:
			return "bleeding"
		if float(q.infected_at) >= 0.0:
			infected = true
	if infected:
		return "infected"
	if base != null and bool(base.claimed) and not base.at_base(here) and here.distance_to(Vector2(base.center())) > OUT_R:
		return "out"
	return ""


## {"ok", "why", "code"}: may the avatar wait for the bell now (what `begin` asks first). `why` is a sentence for a toast ("Claim a house first", "Cannot wait: the dead are near" is the view's).
func can_wait() -> Dictionary:
	var base = sim.get("base")
	if base == null or not bool(base.claimed):
		return {"ok": false, "why": NEED_CLAIM, "code": "claim"}
	var p = _lead()
	if p == null or p.dead or p.turned or p.downed or p.away != null:
		return {"ok": false, "why": WHY.down, "code": "down"}
	if sim.over != "":
		return {"ok": false, "why": WHY.over, "code": "over"}
	if sim.phase != "day":
		return {"ok": false, "why": WHY.night, "code": "night"}
	if minutes_to_go() < 1.0:
		return {"ok": false, "why": WHY.late, "code": "late"}
	var uses = sim.get("uses")
	if uses != null and uses.has_method("busy") and bool(uses.busy()):
		return {"ok": false, "why": WHY.busy, "code": "busy"}
	var code := _stop_reason(p)
	if code != "":
		return {"ok": false, "why": String(WHY[code]), "code": code}
	return {"ok": true, "why": "", "code": ""}


## Whether the plan on the Build page is short of READY BY DUSK with the dead coming tonight (the question `begin` asks).
func plan_not_ready() -> bool:
	if not _attacks_on() or sim.get("perimeter") == null:
		return false
	var verdict := String(PlanClock.assess(sim.perimeter.projects(), PlanClock.context(sim)).get("verdict", ""))
	return verdict == "tight" or verdict == "not_yet"


## Starts the wait: {"ok", "why", "code"} and, for the plan question, {"ok": false, "ask": the words}; call again with `confirmed` once the player has said yes.
func begin(confirmed: bool = false) -> Dictionary:
	if _on:
		return {"ok": true, "why": "", "code": "", "minutes": maxf(_goal - float(sim.clock_min), 0.0)}
	var can := can_wait()
	if not bool(can.ok):
		return can
	if not confirmed and plan_not_ready():
		return {"ok": false, "why": "", "code": "ask", "ask": ASK_PLAN}
	var p = _lead()
	var mins := minutes_to_go()
	_goal = float(sim.clock_min) + mins
	_waited = 0.0
	_hp = float(p.hp)
	_hold_until = 0
	_hold_cool_until = 0
	_on = true
	_hands_off(p)
	sim.events.append({"type": "wait", "on": true, "goal": _goal})
	return {"ok": true, "why": "", "code": "", "minutes": mins}


func _hands_off(p) -> void:
	p.input_move = Vector2.ZERO
	p.input_fire = false
	p.input_melee = false
	p.input_reload = false
	p.moving = false
	sim.avatar.sprint.wanted = false


## Ends the wait: `code` is one of WHY's keys, "bell" (the end), "input" or "card" (the view's).
func cancel(code: String = "input") -> void:
	if not _on:
		return
	_on = false
	var early := code != "bell"
	var words: String = "" if not early else String(WHY.get(code, code))
	last = {"code": code, "why": words, "early": early, "minutes": _waited}
	sim.events.append({"type": "wait", "on": false, "code": code, "why": words, "early": early, "minutes": _waited})


## One frame's worth of waiting: the colony runs ahead a chunk at a time within `budget_us`, and the wait ends when something stops it. A build finished holds it for HOLD_MS.
func advance(dt: float = -1.0) -> void:
	if not _on or _busy:
		return
	if hold_ms > 0 and Time.get_ticks_msec() < _hold_until:
		return
	_busy = true
	var t0 := Time.get_ticks_usec()
	# (with the frame's time given the pace is RATE_MIN_PER_S game minutes a real second, so that the day is a time-lapse and not a cut; none given, as fast as the budget lets it)
	var quota := INF if dt < 0.0 else RATE_MIN_PER_S * dt
	var spent := 0.0
	while _on:
		var p = _lead()
		if p == null or p.dead or p.turned or p.downed:
			cancel("down")
			break
		var left := _goal - float(sim.clock_min)
		if left <= 1.0e-6:
			cancel("bell")
			break
		_hands_off(p)
		var before := float(sim.clock_min)
		sim.fast_forward(left, CHUNK_STEPS)
		spent += float(sim.clock_min) - before
		_waited += float(sim.clock_min) - before
		if sim.over != "":
			cancel("over")
			break
		p = _lead()
		if p == null or p.dead or p.turned or p.downed:
			cancel("down")
			break
		var code := _stop_reason(p)
		if code == "" and float(p.hp) < _hp - 0.001:
			code = "hurt"
		if code != "":
			cancel(code)
			break
		_hp = float(p.hp)
		if _goal - float(sim.clock_min) <= 1.0e-6:
			cancel("bell")
			break
		if _built_now():
			holds += 1
			if hold_ms > 0:
				_hold_until = Time.get_ticks_msec() + hold_ms
				_hold_cool_until = _hold_until + HOLD_COOL_MS
				break
		if spent >= quota or Time.get_ticks_usec() - t0 >= budget_us:
			break
	_busy = false


## Whether a build was finished in the chunk just run (the events of its steps are still in the list: the game takes them next frame), and the hold is not cooling off.
func _built_now() -> bool:
	var found := false
	for e in sim.events:
		var t := String(e.get("type", ""))
		if (t == "project_done" or t == "slot_built") and not e.has("_waited"):
			e["_waited"] = true    # (counted once: the list is the game's, and the next chunk of this frame sees it again)
			found = true
	return found and Time.get_ticks_msec() >= _hold_cool_until


func save() -> Dictionary:
	return {}


## A save is taken awake and a load is awake.
func load_state(_d: Dictionary) -> void:
	start()
