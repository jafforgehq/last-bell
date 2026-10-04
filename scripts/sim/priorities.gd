## Priorities (round 25, S25.1 of docs/superpowers/plans/2026-10-04-round-25.md): the up to four things the player asks the base to put first (food, water,
## defence, rebuilding, rest, scavenging) and the standing staffing and errand the automation makes of them. THIS FILE IS A STUB (phase 0b): every function
## has its contract's signature and returns the exact neutral value (no priority set, no shift, nobody moved), so the hooks that read it (`tactics.repair_below`,
## `workshop.target`, `jobs.fit_of`) change nothing. BRIEF-SIM replaces the bodies; the signatures, the constants and the saved variables stay.
## Nothing here may use `sim.rng`: every choice is a pure function of the state, ties by id.
extends RefCounted

const IDS := ["food", "water", "defence", "rebuild", "rest", "scavenge"]
const MAX_SET := 4
## The weight of a priority by its rank (the tap order is the rank).
const RANK_W := [3.0, 2.0, 1.5, 1.0]
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0

var sim
var enabled := true
## Saved. `order`: the ids by rank; `staffed`: person id -> the station the staffer gave them; `pins`: person id -> true (moved by someone else: never touched again).
var order: Array = []
var staffed := {}
var pins := {}


func setup(s) -> void:
	sim = s


func start() -> void:
	order = []
	staffed = {}
	pins = {}


## (Nothing is kept for a person until the staffer gives them a seat.)
func person_added(_p) -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


func update(_dt: float) -> void:
	if not active():
		return


## A tap on a chip: the first tap appends, a tap on a ranked one removes it, a fifth is refused ("Four at most: tap one to drop it"). {"ok", "why"}.
func toggle(_id) -> Dictionary:
	return {"ok": false, "why": "Priorities are not available yet"}


func set_order(_ids: Array) -> Dictionary:
	return {"ok": false, "why": "Priorities are not available yet"}


## 0 = not ranked, 1 to 4.
func rank_of(_id) -> int:
	return 0


func weight(_id) -> float:
	return 0.0


## The two ids the top concerns point at (the briefing card's "Use these").
func suggested() -> Array:
	return []


## tactics.repair_below: 0.05 * w(defence) - 0.05 * w(rebuild), clamped to +-0.15.
func wall_line_shift() -> float:
	return 0.0


## workshop.target(): 100 * min(w(defence), 3) / 3, to the station's step of 25.
func ammo_target_shift() -> float:
	return 0.0


## PURE: {station id: wanted hands}; {} while nothing is ranked.
func seat_plan() -> Dictionary:
	return {}


## Runs the staffing plan through `jobs.assign`: {"moved": [{"who", "from", "to"}], "filled": n, "pinned": [ids]}.
func staff() -> Dictionary:
	return {"moved": [], "filled": 0, "pinned": []}


func release_pins() -> void:
	pins = {}


func pinned() -> Array:
	return []


## The stock the base wants most for a standing errand ("food", "water", "scrap", "meds", "ammo" or "").
func errand_wish() -> String:
	return ""


## {"sent": bool, "why": String}.
func standing_errand() -> Dictionary:
	return {"sent": false, "why": ""}


## {station: game hours worked since the briefing}.
func seat_hours() -> Dictionary:
	return {}


func save() -> Dictionary:
	return {"order": order.duplicate(), "staffed": staffed.duplicate(), "pins": pins.duplicate()}


## Restores what `save` wrote; {} (a save from before) is a fresh module. What is not sound (an id that is not known, a fifth rank) is left out.
func load_state(d: Dictionary) -> void:
	start()
	var raw = d.get("order", [])
	if raw is Array:
		for id in raw:
			if IDS.has(str(id)) and not order.has(str(id)) and order.size() < MAX_SET:
				order.append(str(id))
	var st = d.get("staffed", {})
	if st is Dictionary:
		for k in st:
			staffed[str(k)] = str(st[k])
	var pn = d.get("pins", {})
	if pn is Dictionary:
		for k in pn:
			pins[str(k)] = true
