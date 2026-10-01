## The workshop: by day a person at the yard's worktable turns scrap into ammo.
## Ammo is what runs out first in a long run, and scrap is what the walls and the
## bench both eat, so every spare scrap is a choice between a wall and a night of
## shooting. Rules only; the HUD offers the order (key M) and shows the mark.
##
## A person ordered to make ammo walks to the bench, works there by day and goes
## back to their jobs at the bell (or when given any other order, or when something
## takes them away). The bench keeps a few scrap back for the walls.
##
## Events: {"type": "hammer", x, y} while they work, and about every two seconds
## {"type": "craft", x, y, "scrap", "ammo"} with what was made since the last one.
## Alerts: `workshop-idle` when the scrap is down to the reserve.
extends RefCounted

## Ammo made from one scrap.
const AMMO_PER_SCRAP := 8.0
## The scrap the bench leaves in the stock, for the walls.
const RESERVE_SCRAP := 3.0
## A person works through this much scrap an hour, plus half their Building skill
## (Dez 6.5, Ruth 3.5, Marcus 2.5), times how well they are (`sim.perf`).
const BASE_SCRAP_PER_HOUR := 2.0
const BUILDING_SHARE := 0.5
## Someone is at the bench when this close to its spot.
const AT_BENCH := 0.45
## How often, in seconds of rules time, the hammer rings and a craft event goes out.
const HAMMER_EVERY := 0.9
const CRAFT_EVERY := 2.0
const MARK_COLOR := Color("#f0c24a")

var sim
## Who is on the job: person id to {"hammer": seconds to the next ring, "scrap": made
## since the last craft event, "since": seconds since it}.
var crafters := {}


func setup(s) -> void:
	sim = s


func start() -> void:
	crafters.clear()


## The spot where someone stands at the worktable (from the game data).
func bench() -> Vector2:
	var w = sim.d.get("workshop", null)
	if typeof(w) != TYPE_DICTIONARY:
		return Vector2.ZERO
	return Vector2(float(w.x), float(w.y))


## How much scrap this person works through in a game hour when well.
func scrap_per_hour(p) -> float:
	return BASE_SCRAP_PER_HOUR + BUILDING_SHARE * float(p.def.skills.Building)


func crafting(p) -> bool:
	return crafters.has(String(p.id))


func _night() -> bool:
	return sim.phase == "night" or sim.phase == "dawn" or (sim.phase == "dusk" and sim.bell_rung)


## Why this person cannot be sent to the bench ("" when they can).
func why_not_craft(p) -> String:
	if not sim.d.has("workshop"):
		return "there is no worktable"
	if p.dead:
		return "they are gone"
	if p.downed:
		return "they are down"
	if p.away != null:
		return "they are away"
	if _night():
		return "it is night: everyone is at their post"
	if float(sim.stock.scrap) < RESERVE_SCRAP + 1.0:
		return "there is no scrap to spare"
	return ""


## Sends this person to the bench, taking them off any other order. False (and
## nothing changes) when they cannot go.
func order_craft(p) -> bool:
	if why_not_craft(p) != "":
		return false
	crafters[String(p.id)] = {"hammer": 0.0, "scrap": 0.0, "since": 0.0}
	p.drafted = false
	p.order = null
	p.repair = null
	p.goal_key = ""
	return true


## Takes them off the bench (any other order calls this).
func stop(p) -> void:
	if crafters.erase(String(p.id)):
		p.goal_key = ""


## Where someone on the job should be: the duty `sim._goal_for` offers after the
## medical and scavenging duties.
func goal_for(p):
	if not crafting(p):
		return null
	var b := bench()
	return {"x": b.x, "y": b.y, "face": "N", "what": "Making ammo"}


func status_of(p) -> Array:
	if not crafting(p):
		return []
	return [{"icon": "ammo", "color": MARK_COLOR, "tip": "Making ammo at the worktable"}]


func update(dt: float) -> void:
	if crafters.is_empty():
		return
	var night := _night()
	var hours: float = sim.game_hours(dt)
	for id in crafters.keys():
		var p = _person(id)
		if p == null or p.dead or p.downed or p.away != null or p.drafted or p.order != null or night:
			_drop(id)
			continue
		var st: Dictionary = crafters[id]
		var at := Vector2(p.x, p.y)
		if p.moving or at.distance_to(bench()) > AT_BENCH:
			continue
		var spare := float(sim.stock.scrap) - RESERVE_SCRAP
		if spare <= 0.0:
			_idle(p)
			continue
		var want: float = scrap_per_hour(p) * sim.perf(p) * hours
		var use := minf(want, spare)
		sim.stock.scrap = float(sim.stock.scrap) - use
		sim.stock.ammo = float(sim.stock.ammo) + use * AMMO_PER_SCRAP
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
		if use < want or spare - use <= 0.0:
			_idle(p)


func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _drop(id: String) -> void:
	crafters.erase(id)
	var p = _person(id)
	if p != null:
		p.goal_key = ""


## The scrap is down to the reserve: they are done, and the crew is told.
func _idle(p) -> void:
	stop(p)
	sim.alert("workshop-idle", "info", "The worktable is idle", "Only %d scrap is left; it is kept for the walls" % int(RESERVE_SCRAP), bench(), 10.0)


## The orders this module owns: "craft" on a person (the same key sends them and
## calls them back).
func gizmo(id: String, sel) -> bool:
	if id != "craft" or sel.kind != "person":
		return false
	var p = sel.ref
	if crafting(p):
		stop(p)
		return true
	return order_craft(p)


func save() -> Dictionary:
	return {"crafters": crafters.duplicate(true)}


func load_state(d: Dictionary) -> void:
	crafters.clear()
	var c = d.get("crafters", {})
	if c is Dictionary:
		for id in c:
			var st = c[id]
			if st is Dictionary:
				crafters[String(id)] = {"hammer": float(st.get("hammer", 0.0)), "scrap": float(st.get("scrap", 0.0)), "since": float(st.get("since", 0.0))}
