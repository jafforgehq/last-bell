## The player's tools for a night and the work of two stations: the lure (an alarm on one wall
## section that draws the dead to it), the wall crew (the Wall crew station mends the walls by
## day, and anyone with nothing to do mends a badly worn one), how well the crew's guns cover each
## wall section, and the forecast the lookout post gives of tonight. Rules only; the view draws
## them.
##
## THE WALL CREW. Every second by day the people on the Wall crew job (`jobs.crew_of("builders")`)
## who are free (not on an order, not mending, not treating) are sent to the most worn wall
## section under the station's threshold (its `repair_below` setting, 70% to begin with) while the
## stock has scrap to spare. The people with nothing to do (`jobs.idle`: no job, or a bench worker
## with nothing to make) mend a section only if it is under half (CHORE_WALL_BELOW). At the bell
## they leave the wall for their posts.
##
## THE FORECAST. At 17:00 the person working the Lookout post (`jobs.operator("watch")`: there, up
## and free) tells the crew what tonight looks like; with nobody there the crew is told there is
## no forecast. The forecast, once given, is that night's: it stays after the lookout has left the
## post (and at night, when nobody works it).
##
## Events: {"type": "lure", "seg": id}. Alerts: `lure`, `forecast`.
##
## From the buildings (build.gd) it reads what changes a gun's reach (`sim.reach_at`: the floodlights by
## night, a watchtower near the post) when it counts how well the guns cover each wall section.
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
## The wall crew mends the most worn section under this share of its health by default (the
## station's `repair_below` setting is the one used), while the stock has at least this much scrap.
const AUTO_BELOW := 0.7
const AUTO_MIN_SCRAP := 5.0
## Whoever is idle mends a section under this share of its health, and no other.
const CHORE_WALL_BELOW := 0.5
## The hour the lookout tells the crew what tonight looks like.
const FORECAST_HOUR := 17.0

var sim
## The section the alarm is set on (-1: none) and when it stops (sim.clock_min).
var lure_id := -1
var lure_until := 0.0
## Whom the wall crew (or a chore) has sent to which section (id to id): they are called back
## at the bell.
var auto_jobs := {}
## Whether people with nothing to do mend a badly worn wall (the tutorial's lessons switch it off:
## nobody mends the wall unasked while the player is learning to ask). Not saved: whoever turns it
## off turns it off again.
var chores := true
## The day whose forecast has been given, and who gave it (a person's id; "" when nobody did).
var forecast_day := 0
var forecast_who := ""
var _t := 0.0


func setup(s) -> void:
	sim = s


## A fresh run: no alarm.
func start() -> void:
	lure_id = -1
	lure_until = 0.0
	forecast_day = 0
	forecast_who = ""
	auto_jobs.clear()
	_t = 0.0


func update(dt: float) -> void:
	if lure_id >= 0 and sim.clock_min >= lure_until:
		lure_id = -1
	if sim.phase == "day" and sim.hour >= FORECAST_HOUR and forecast_day != sim.day:
		forecast_day = sim.day
		_tell_the_forecast()
	_t -= dt
	if _t <= 0.0:
		_t = 1.0
		_mend_walls()


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


# --------------------------------------------------------- the wall crew --

## Whether this person is on the wall crew (the old standing order "auto-repair", now a job).
func auto_repair(p) -> bool:
	return sim.jobs.job_of(p) == "builders"


## Puts this person on the wall crew, or takes them off it.
func toggle_auto(p) -> void:
	if auto_repair(p):
		sim.jobs.unassign(p)
	else:
		sim.jobs.assign(p, "builders")


## The share of its health under which the wall crew mends a section (the station's setting).
func repair_below() -> float:
	return float(sim.jobs.setting("builders", "repair_below")) / 100.0


## Once a second: by day the wall crew goes to the most worn section under its threshold, and
## whoever is idle to one that is under half; by night they hold their posts, and whoever was
## sent to a wall is called off it, as they are when the scrap is gone (a hammer with nothing to
## pay for the blows is no work: they go back to their jobs).
func _mend_walls() -> void:
	# the sections somebody is mending (a person who is gone is not: they were never relieved)
	var taken := {}
	for q in sim.people:
		if q.repair != null and not q.dead and not q.turned:
			taken[q.repair.id] = true
	if sim.phase != "day":
		for p in sim.people:
			call_back(p)
		return
	if float(sim.stock.scrap) <= 0.0:
		for p in sim.people:
			call_back(p)
		return
	if float(sim.stock.scrap) < AUTO_MIN_SCRAP:
		return
	for p in sim.jobs.crew_of("builders"):
		_send_to_the_wall(p, repair_below(), taken)
	if not chores:
		return
	for p in sim.people:
		if sim.jobs.idle(p):
			_send_to_the_wall(p, CHORE_WALL_BELOW, taken)


## Takes `p` off the wall the crew sent them to, if they are still on it (a repair the player
## ordered, even of the same section, is not the crew's and stays).
func call_back(p) -> void:
	var id := String(p.id)
	if p.repair != null and auto_jobs.has(id) and int(p.repair.id) == int(auto_jobs[id]):
		p.repair = null
		p.goal_key = ""
	auto_jobs.erase(id)


## An order to repair (`sim.order_repair`) makes the repair the player's, not the crew's.
func forget_trip(p) -> void:
	auto_jobs.erase(String(p.id))


## Sends `p`, if they are free, to the most worn section under `below` of its health that
## nobody is mending.
func _send_to_the_wall(p, below: float, taken: Dictionary) -> void:
	if p.dead or p.downed or p.away != null or sim.morale.breakdown(p):
		return
	if p.repair != null or p.drafted or p.order != null:
		return
	if sim.medical.goal_for(p) != null:
		return
	var worst = null
	for s in sim.segments:
		if taken.has(s.id) or s.hp >= s.max_hp * below:
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
	return sim.jobs.post_pos(p)


## How many of the crew's guns reach at least half of this section's places from
## where they stand at night. The reach is the one the guns have there tonight (`sim.reach_at`: a fog, the
## floodlights, a watchtower near the post), also by day, so that this is the number to plan the night by.
func coverage_of(seg) -> int:
	var n := 0
	for p in sim.people:
		if p.dead or p.downed or p.away != null:
			continue
		var at := post_pos(p)
		var reach: float = sim.reach_at(p.gun, at, true)
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

## The person on the lookout: working the Lookout post right now (there, up and free), or null.
func lookout():
	return sim.jobs.operator("watch")


## What the lookout told about tonight, from 17:00 until dawn:
## {"given", "total", "low", "high", "heading", "spawns" (Vectors), "runners",
## "brutes", "big", "who"}; {"given": false} before 17:00 and when nobody was on watch at 17:00.
## It is the night's whoever has left the post since, and `who` is the one who reported it.
func forecast() -> Dictionary:
	if forecast_day != sim.day or forecast_who == "":
		return {"given": false}
	var who = _person(forecast_who)
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


func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _tell_the_forecast() -> void:
	var who = lookout()
	if who == null:
		forecast_who = ""
		sim.alert("forecast", "warn", "No forecast", "Nobody is watching the road", null, 12.0)
		return
	forecast_who = String(who.id)
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

## The order this module owns: "lure" on a wall section (the key for the wall crew, "auto", is
## the jobs': it puts the person on the crew or takes them off it).
func gizmo(id: String, sel) -> bool:
	if id == "lure" and sel.kind == "segment":
		return order_lure(sel.ref)
	return false


# -------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {
		"lure_id": lure_id,
		"lure_until": lure_until,
		"auto_jobs": auto_jobs.duplicate(),
		"forecast_day": forecast_day,
		"forecast_who": forecast_who,
		"t": _t,
	}


func load_state(d: Dictionary) -> void:
	lure_id = int(d.get("lure_id", -1))
	lure_until = float(d.get("lure_until", 0.0))
	forecast_day = int(d.get("forecast_day", 0))
	forecast_who = String(d.get("forecast_who", ""))
	_t = float(d.get("t", 0.0))
	if not d.has("forecast_who") and forecast_day == sim.day:
		# a save from before the lookout post: the forecast was the Lookout's, if he was up
		for p in sim.people:
			if p.def.get("role", "") == "Lookout" and not p.dead and not p.downed and p.away == null:
				forecast_who = String(p.id)
	# (the standing orders "auto" of an older save are not read: the jobs say who mends the walls)
	auto_jobs.clear()
	var j = d.get("auto_jobs", {})
	if j is Dictionary:
		for k in j:
			auto_jobs[String(k)] = int(j[k])
