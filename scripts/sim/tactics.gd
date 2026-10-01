## The player's tools for a night: the lure (an alarm on one wall section that
## draws the dead to it), the standing order "auto-repair", how well the crew's
## guns cover each wall section, and the lookout's forecast of tonight. Rules only;
## the view draws them.
##
## Events: {"type": "lure", "seg": id}. Alerts: `lure`, `forecast`.
extends RefCounted

const Kinds := preload("res://scripts/sim/kinds.gd")

## The alarm costs this much scrap, rings for this many game hours and makes its
## wall section's slots score this many tiles better when the dead choose where to
## go. Of the dead already on their way (and not yet clawing) this share switch to it
## when it is set and a place is free.
const LURE_COST := 3.0
const LURE_HOURS := 3.0
const LURE_PULL := 40.0
const LURE_SWITCH := 0.7
## Auto-repair mends the most worn section under this share of its health, while
## the stock has at least this much scrap.
const AUTO_BELOW := 0.7
const AUTO_MIN_SCRAP := 5.0
## The hour the lookout tells the crew what tonight looks like.
const FORECAST_HOUR := 17.0
const LOOKOUT_ROLE := "Lookout"

var sim
## The section the alarm is set on (-1: none) and when it stops (sim.clock_min).
var lure_id := -1
var lure_until := 0.0
## Who has auto-repair on, and whom it has sent to which section (id to id).
var auto := {}
var auto_jobs := {}
## The day whose forecast has been given.
var forecast_day := 0
var _t := 0.0


func setup(s) -> void:
	sim = s


## A fresh run: no alarm, and auto-repair on for those whose entry in the roster says so.
func start() -> void:
	lure_id = -1
	lure_until = 0.0
	forecast_day = 0
	auto.clear()
	auto_jobs.clear()
	_t = 0.0
	for def in sim.d.people:
		if def.get("auto_repair", false):
			auto[String(def.id)] = true


func update(dt: float) -> void:
	if lure_id >= 0 and sim.clock_min >= lure_until:
		lure_id = -1
	if sim.phase == "day" and sim.hour >= FORECAST_HOUR and forecast_day != sim.day:
		forecast_day = sim.day
		_tell_the_forecast()
	_t -= dt
	if _t <= 0.0:
		_t = 1.0
		_auto_repairs()


# ------------------------------------------------------------------- lure --

## The section the alarm is on, or null.
func lure_seg():
	if lure_id < 0:
		return null
	for s in sim.segments:
		if s.id == lure_id:
			return s
	return null


## How long the alarm still rings, in game minutes.
func lure_left_min() -> float:
	return maxf(0.0, lure_until - sim.clock_min) if lure_id >= 0 else 0.0


## Why the alarm cannot be set on this section ("" when it can).
func why_not_lure(seg) -> String:
	if seg.kind == sim.DOOR_KIND:
		return "the dead are not drawn to the school doors"
	if seg.state == 3:
		return "that section is down"
	if lure_id >= 0:
		return "an alarm is already ringing"
	if float(sim.stock.scrap) < LURE_COST:
		return "it takes %d scrap" % int(LURE_COST)
	return ""


## Sets the alarm on a section: scrap spent, the dead on their way drawn to it.
func order_lure(seg) -> bool:
	if why_not_lure(seg) != "":
		return false
	sim.stock.scrap = maxf(0.0, float(sim.stock.scrap) - LURE_COST)
	lure_id = seg.id
	lure_until = sim.clock_min + LURE_HOURS * 60.0
	for z in sim.zombies:
		if z.state != "approach" or z.slot == null or z.slot.seg == seg:
			continue
		if sim.rng.randf() >= LURE_SWITCH:
			continue
		var old = z.slot
		old.who = null
		z.slot = null
		if not sim.assign_slot(z, seg):
			old.who = z
			z.slot = old
	sim.events.append({"type": "lure", "seg": seg.id})
	sim.alert("lure", "info", "Alarm at the %s" % seg.name.to_lower(), "The dead are drawn to it for %d hours" % int(LURE_HOURS), seg.center, 10.0)
	return true


# ------------------------------------------------------- standing orders --

func auto_repair(p) -> bool:
	return bool(auto.get(String(p.id), false))


func toggle_auto(p) -> void:
	auto[String(p.id)] = not auto_repair(p)


func _auto_repairs() -> void:
	var by_day: bool = sim.phase == "day"
	var taken := {}
	for q in sim.people:
		if q.repair != null:
			taken[q.repair.id] = true
	for p in sim.people:
		if p.dead or p.downed or p.away != null or sim.morale.breakdown(p):
			continue
		if not auto_repair(p):
			continue
		if not by_day:
			# by night they hold their post: a job they were sent on stops
			if p.repair != null and auto_jobs.has(String(p.id)):
				p.repair = null
				p.goal_key = ""
			auto_jobs.erase(String(p.id))
			continue
		if p.repair != null or p.drafted or p.order != null:
			continue
		if sim.workshop.crafting(p):
			continue
		if sim.medical.goal_for(p) != null:
			continue
		if float(sim.stock.scrap) < AUTO_MIN_SCRAP:
			continue
		var worst = null
		for s in sim.segments:
			if taken.has(s.id) or s.hp >= s.max_hp * AUTO_BELOW:
				continue
			if worst == null or s.hp / s.max_hp < worst.hp / worst.max_hp:
				worst = s
		if worst != null:
			sim.order_repair(p, worst)
			auto_jobs[String(p.id)] = worst.id
			taken[worst.id] = true


# --------------------------------------------------------------- coverage --

## Where someone stands for this purpose: the spot of their order if they are
## drafted, else their post (the night position).
func post_pos(p) -> Vector2:
	if p.drafted and p.order != null:
		return Vector2(p.order.x, p.order.y)
	return Vector2(float(p.def.post.x), float(p.def.post.y))


## How many of the crew's guns reach at least half of this section's places from
## where they stand at night.
func coverage_of(seg) -> int:
	var n := 0
	for p in sim.people:
		if p.dead or p.downed or p.away != null:
			continue
		var at := post_pos(p)
		var reach: float = sim.reach_of(p.gun)
		var within := 0
		for sl in seg.slots:
			if at.distance_to(Vector2(sl.x, sl.y)) <= reach:
				within += 1
		if within * 2 >= seg.slots.size():
			n += 1
	return n


## The coverage of every section: {section id: count}.
func coverage_map() -> Dictionary:
	var out := {}
	for s in sim.segments:
		out[s.id] = coverage_of(s)
	return out


# --------------------------------------------------------------- forecast --

## The person on the lookout, if they are here, up and alive.
func lookout():
	for p in sim.people:
		if p.def.get("role", "") == LOOKOUT_ROLE and not p.dead and not p.downed and p.away == null:
			return p
	return null


## What the lookout can tell about tonight, once it is time and while he is able:
## {"given", "total", "low", "high", "heading", "spawns" (Vectors), "runners",
## "brutes", "big", "who"}; {"given": false} before 17:00 or without a lookout.
func forecast() -> Dictionary:
	if forecast_day != sim.day:
		return {"given": false}
	var who = lookout()
	if who == null:
		return {"given": false}
	var plan: Dictionary = sim.waves.plan_for(sim.day)
	var spawns: Array = []
	for i in plan.heading:
		spawns.append(sim.spawns[int(i)])
	var shown: int = int(plan.shown)
	return {
		"given": true,
		"total": shown,
		"low": roundi(float(shown) * 0.85),
		"high": roundi(float(shown) * 1.15),
		"heading": sim.waves.heading_text(plan),
		"spawns": spawns,
		"runners": int(plan.counts.runner) > 0,
		"brutes": int(plan.counts.brute),
		"big": bool(plan.big),
		"who": String(who.first),
	}


func _tell_the_forecast() -> void:
	var who = lookout()
	if who == null:
		sim.alert("forecast", "warn", "No forecast", "Nobody is watching the road", null, 12.0)
		return
	var f := forecast()
	var text := "About %d tonight, mostly from the %s" % [int(f.total), String(f.heading)]
	if int(f.brutes) > 0:
		text += ", and %s" % ("a brute" if int(f.brutes) == 1 else "%d brutes" % int(f.brutes))
	elif bool(f.runners):
		text += ", with runners"
	if bool(f.big):
		text = "The last night: about %d, from everywhere" % int(f.total)
	sim.events.append({"type": "banner", "text": "%s reports" % String(who.first), "sub": text})
	sim.alert("forecast", "info", "Tonight's forecast", text, null, 60.0)


# ------------------------------------------------------------------ gizmos --

## The orders this module owns: "lure" on a wall section, "auto" on a person.
func gizmo(id: String, sel) -> bool:
	if id == "lure" and sel.kind == "segment":
		return order_lure(sel.ref)
	if id == "auto" and sel.kind == "person":
		toggle_auto(sel.ref)
		return true
	return false


# -------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {
		"lure_id": lure_id,
		"lure_until": lure_until,
		"auto": auto.duplicate(),
		"auto_jobs": auto_jobs.duplicate(),
		"forecast_day": forecast_day,
	}


func load_state(d: Dictionary) -> void:
	lure_id = int(d.get("lure_id", -1))
	lure_until = float(d.get("lure_until", 0.0))
	forecast_day = int(d.get("forecast_day", 0))
	auto.clear()
	var a = d.get("auto", {})
	if a is Dictionary:
		for k in a:
			auto[String(k)] = a[k] == true
	auto_jobs.clear()
	var j = d.get("auto_jobs", {})
	if j is Dictionary:
		for k in j:
			auto_jobs[String(k)] = int(j[k])
