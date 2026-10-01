## The workshop, the work of the Workbench station (see jobs.gd): by day the people at the
## yard's worktable (`sim.jobs.working("bench")`) turn scrap into ammo. Ammo is what runs out
## first in a long run, and scrap is what the walls and the bench both eat, so every spare scrap
## is a choice between a wall and a night of shooting. Rules only; the HUD shows the mark.
##
## The bench makes ammo only while it can (`can_make`): the ammo is under the station's target
## setting (`ammo_target`) and the scrap is above the reserve it keeps for the walls
## (`scrap_reserve`). A worker with nothing to make is idle: the wall crew's chores are theirs
## (tactics.gd). Who sits at the bench is the jobs' business: `order_craft` gives someone the job,
## `stop` takes it away, and `crafting` says whether they are at work now (the old order's
## words, kept for the HUD, the harness and the tutorial).
##
## Events: {"type": "hammer", x, y} while they work, and about every two seconds
## {"type": "craft", x, y, "scrap", "ammo"} with what was made since the last one.
## Alerts: `workshop-idle` when the scrap is down to the reserve with ammo still to make (once
## for each stretch of low scrap).
extends RefCounted

## Ammo made from one scrap.
const AMMO_PER_SCRAP := 8.0
## The scrap the bench keeps in the stock for the walls to begin with. What is used is the
## Workbench's `scrap_reserve` setting (`reserve()`), which starts at this.
const RESERVE_SCRAP := 3.0
## A person works through this much scrap an hour, plus half their Building skill
## (Dez 6.5, Ruth 3.5, Marcus 2.5), times their `craft` traits (Dez, a Tinkerer: 1.2) and
## how well they are (`sim.perf`).
const BASE_SCRAP_PER_HOUR := 2.0
const BUILDING_SHARE := 0.5
## How often, in seconds of rules time, the hammer rings and a craft event goes out.
const HAMMER_EVERY := 0.9
const CRAFT_EVERY := 2.0
## A stock this close to a limit is at it (float noise).
const EPS := 1.0e-9
const MARK_COLOR := Color("#f0c24a")

var sim
## When the hammer rings and the craft events go out, for each person at work: person id to
## {"hammer": seconds to the next ring, "scrap": made since the last craft event, "since": seconds
## since it}. Only the sound and the numbers floating over the bench; nothing the rules depend on.
var _beats := {}
## The idle alert has been given for this stretch of low scrap.
var _told_idle := false


func setup(s) -> void:
	sim = s


func start() -> void:
	_beats.clear()
	_told_idle = false


## The spot where someone stands at the worktable (from the game data).
func bench() -> Vector2:
	var w = sim.d.get("workshop", null)
	if typeof(w) != TYPE_DICTIONARY:
		return Vector2.ZERO
	return Vector2(float(w.x), float(w.y))


## How much scrap this person works through in a game hour when well.
func scrap_per_hour(p) -> float:
	return (BASE_SCRAP_PER_HOUR + BUILDING_SHARE * float(p.skills.Building)) * sim.traits.mult(p, "craft")


## The ammo stock the bench makes ammo up to, and the scrap it keeps back for the walls: the
## Workbench's settings (assets/data/stations.json).
func target() -> float:
	return float(sim.jobs.setting("bench", "ammo_target"))


func reserve() -> float:
	return float(sim.jobs.setting("bench", "scrap_reserve"))


## The scrap the bench may still use (above the reserve), and the scrap that would bring the
## ammo up to the target.
func _scrap_room() -> float:
	return float(sim.stock.scrap) - reserve()


func _ammo_room() -> float:
	return (target() - float(sim.stock.ammo)) / AMMO_PER_SCRAP


## Whether there is anything to make: the ammo is under the target and the scrap is above the
## reserve. A bench worker with nothing to make is idle (see `jobs.idle`) and does chores.
func can_make() -> bool:
	return _scrap_room() > EPS and _ammo_room() > EPS


## Whether this person is making ammo right now: on the bench job, at their seat, free and by
## day, with something to make.
func crafting(p) -> bool:
	return can_make() and sim.jobs.working("bench").has(p)


func _night() -> bool:
	return sim.phase == "night" or sim.phase == "dawn" or (sim.phase == "dusk" and sim.bell_rung)


## Why this person cannot be given the bench job, or would not be making ammo if they had it
## ("" when they can and would): the jobs' reasons (gone, no seat), then the person, the hour and
## the stores.
func why_not_craft(p) -> String:
	if not sim.d.has("workshop"):
		return "there is no worktable"
	var why: String = sim.jobs.why_not(p, "bench")
	if why != "":
		return why
	if p.downed:
		return "they are down"
	if p.away != null:
		return "they are away"
	if sim.morale.breakdown(p):
		return "they cannot work right now"
	if _night():
		return "it is night: everyone is at their post"
	if float(sim.stock.scrap) < reserve() + 1.0:
		return "there is no scrap to spare"
	if float(sim.stock.ammo) >= target():
		return "the ammo is at its target"
	return ""


## Gives this person the bench job (taking them off their old one). False, and nothing changes,
## when the bench is full or they are gone.
func order_craft(p) -> bool:
	return sim.jobs.assign(p, "bench")


## Takes them off the bench job, if they are on it.
func stop(p) -> void:
	if sim.jobs.job_of(p) == "bench":
		sim.jobs.unassign(p)


## No goal of its own: the jobs take the worker to their seat at the bench.
func goal_for(_p):
	return null


func status_of(p) -> Array:
	if not crafting(p):
		return []
	return [{"icon": "ammo", "color": MARK_COLOR, "tip": "Making ammo at the worktable"}]


## Every step: the people at work at the bench (`jobs.working`) turn scrap into ammo while there
## is something to make; the crew is told once when the scrap is down to the reserve.
func update(dt: float) -> void:
	if _scrap_room() > EPS:
		_told_idle = false
	var crew: Array = sim.jobs.working("bench")
	if crew.is_empty():
		_beats.clear()
		return
	var hours: float = sim.game_hours(dt)
	var at_work := {}
	for p in crew:
		var id := String(p.id)
		at_work[id] = true
		var room := minf(_scrap_room(), _ammo_room())
		if room <= EPS:
			continue
		var want: float = scrap_per_hour(p) * sim.perf(p) * hours
		var use := minf(want, room)
		sim.stock.scrap = float(sim.stock.scrap) - use
		sim.stock.ammo = float(sim.stock.ammo) + use * AMMO_PER_SCRAP
		sim.skills.credit(p, "crafted", use)
		var st: Dictionary = _beats.get(id, {"hammer": 0.0, "scrap": 0.0, "since": 0.0})
		st.scrap = float(st.scrap) + use
		st.hammer = float(st.hammer) - dt
		st.since = float(st.since) + dt
		if st.hammer <= 0.0:
			st.hammer = HAMMER_EVERY
			sim.events.append({"type": "hammer", "x": p.x, "y": p.y})
		if st.since >= CRAFT_EVERY:
			sim.events.append({"type": "craft", "x": p.x, "y": p.y, "scrap": st.scrap, "ammo": float(st.scrap) * AMMO_PER_SCRAP})
			st.scrap = 0.0
			st.since = 0.0
		_beats[id] = st
	for id in _beats.keys():
		if not at_work.has(id):
			_beats.erase(id)
	if _scrap_room() <= EPS and _ammo_room() > EPS and not _told_idle:
		_told_idle = true
		sim.alert("workshop-idle", "info", "The worktable is idle", "Only %d scrap is left; it is kept for the walls" % int(reserve()), bench(), 10.0)


## What a save keeps: whether the crew has been told the bench is idle (so a load does not tell them
## again). The hammer's beats are only sound and numbers floating over the bench and are not kept.
func save() -> Dictionary:
	return {"told_idle": _told_idle}


func load_state(d: Dictionary) -> void:
	_beats.clear()
	_told_idle = bool(d.get("told_idle", false))
