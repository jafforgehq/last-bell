## Priorities (round 25, S25.1 of docs/superpowers/plans/2026-10-04-round-25.md): the up to four things the player asks the base to put first (food, water,
## defence, rebuilding, rest, scavenging), ranked by the order of the taps, and what the automation makes of them. A rank is a WEIGHT (3, 2, 1.5, 1) and the
## weights move four things the base already does: the seats (`seat_plan`, carried out by `staff` through `jobs.assign` only), the line the wall crew mends
## from (`wall_line_shift`, read by tactics.repair_below), the bench's ammo target (`ammo_target_shift`, workshop.target) and a standing errand each morning
## (`standing_errand`, through the radio's own `request_errand`: its delay, its refusals, its terms). The numbers are assets/data/priorities.json.
##
## NEUTRAL: with no priority set (and inactive: no avatar, not a small start, Orientation Day) every function returns the exact neutral value (0.0, {}, [],
## false) and `update` changes nothing the rules read: the jobs stay as they are until the player taps a chip. NO `sim.rng` ANYWHERE: every choice is a pure
## function of the state, ties by id (or by crew order), so a saved game replays bit for bit.
##
## PINS. `staffed` is the station each person was given (or left at) the last time the staffer looked. A person whose `jobs.assignments` entry differs from it was
## moved by someone else (the player on the Jobs page, an idea, the old keys, the radio): PINNED, never touched again until `release_pins`. A pinned person is
## not one of the hands the plan seats, and the seat they hold is not the plan's to give. The check is pure (`_is_pinned`), so `seat_plan` and `pinned` agree at
## every moment, and `staff` writes the pins down when it runs.
##
## DEVIATION FROM THE CONTRACT, on purpose: a priority with no seat lever of its own (water, rest, scavenging: `plan.lever` is empty) does not reshuffle people. When
## no ranked priority has a lever, `seat_plan` is the staffing the hands have now (Rest alone only takes the weariest out of it): tapping Water must not move the
## infirmary's nurse to the walls. With any levered priority ranked the plan is the full formula, needs included.
extends RefCounted

const CrewLoad := preload("res://scripts/sim/crew_load.gd")
const Lots := preload("res://scripts/sim/lots.gd")

const DATA_PATH := "res://assets/data/priorities.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

const IDS := ["food", "water", "defence", "rebuild", "rest", "scavenge"]
const MAX_SET := 4
## The weight of a priority by its rank (the tap order is the rank).
const RANK_W := [3.0, 2.0, 1.5, 1.0]
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0
## "Never happened" for the clocks (game minutes since the run began).
const NEVER := -1.0e9
## The stocks a standing errand can be sent for, in the order that breaks a tie.
const STOCKS := ["food", "water", "scrap", "meds", "ammo"]
## What a save may say (a damaged one is clamped to these).
const MAX_HOURS := 1000.0
const MAX_TEXT := 240

var sim
var enabled := true
## Saved. `order`: the ids by rank; `staffed`: person id -> the station the staffer gave them ("" none); `pins`: person id -> true (moved by someone else).
var order: Array = []
var staffed := {}
var pins := {}
## Saved. What the last standing errand was: {"day", "line", "ids", "place", "stock", "names", "where"}, {} before the first; and why the last one that was tried could not go
## ({"day", "why"}), for the debrief's "Scavenging: no errand went out (nobody is free to go)".
var last_errand := {}
var last_why := {}
var _hours := {}
var _acc := 0.0
var _dirty := false
var _sig := ""
var _last_staff := NEVER
var _morning_day := 0
var _errand_day := 0
var _lines_day := 0
var _lines_n := 0
## The News entry of the last tap (not saved): taps within the hour are one line.
var _tap_news := 0
var _tap_t := NEVER


func setup(s) -> void:
	sim = s


func start() -> void:
	order = []
	staffed = {}
	pins = {}
	last_errand = {}
	last_why = {}
	_hours = {}
	_acc = 0.0
	_dirty = false
	_sig = ""
	_last_staff = NEVER
	_morning_day = 0
	_errand_day = 0
	_lines_day = 0
	_lines_n = 0
	_tap_news = 0
	_tap_t = NEVER


## (Nothing is kept for a person until the staffer gives them a seat; the signature of the hands notices the new one.)
func person_added(_p) -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


# ------------------------------------------------------------------------ data --

static func _data() -> Dictionary:
	if not _cache.has(data_path):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		_cache[data_path] = raw if raw is Dictionary else {}
	return _cache[data_path]


## The node at a dotted path of the data ({} or the fallback when it is not there).
static func _node(path: String):
	var node = _data()
	for key in path.split("."):
		if node is Dictionary and (node as Dictionary).has(key):
			node = node[key]
		else:
			return null
	return node


static func _n(path: String, fallback: float) -> float:
	var v = _node(path)
	return float(v) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) else fallback


static func _dict(path: String) -> Dictionary:
	var v = _node(path)
	return v if v is Dictionary else {}


static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## The strings of a list (a save's), each held to a length, at most eight.
static func _strings(v, limit: int) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if typeof(x) == TYPE_STRING and out.size() < 8:
				out.append(str(x).substr(0, limit))
	return out


## What a priority is called ("Rebuilding").
static func name_of(id) -> String:
	var names := _dict("names")
	return String(names.get(String(id), String(id).capitalize()))


## {"name", "blurb", "lever"}: what a priority is, for the chip's tooltip: the lever in plain numbers (the weight of its rank, 3, 2, 1.5 or 1, multiplies each).
static func describe(id) -> Dictionary:
	var key := String(id)
	var short := _dict("short")
	var lever := _dict("plan.lever").get(key, {}) as Dictionary
	var hands: Array = []
	for st in lever:
		hands.append("%s +%s" % [String(short.get(String(st), String(st))), _trim(float(lever[st]))])
	var shifts: Array = []
	var per := roundi(_n("shifts.wall_line_per_w", 0.05) * 100.0)
	if key == "defence":
		shifts.append("wall line +%d%%" % per)
		shifts.append("ammo target +%d" % roundi(_n("shifts.ammo_target_max", 100.0) / 3.0))
	elif key == "rebuild":
		shifts.append("wall line -%d%%" % per)
	var text := ""
	if not hands.is_empty():
		text += "Hands: %s. " % ", ".join(hands)
	if not shifts.is_empty():
		text += "%s%s. " % [String(shifts[0]).substr(0, 1).to_upper(), ", ".join(shifts).substr(1)]
	text = (text + "Times the weight of its rank (3, 2, 1.5, 1).") if text != "" else String(_dict("lever_text").get(key, "No hands move for it."))
	return {"name": name_of(key), "blurb": String(_dict("blurbs").get(key, "")), "lever": text}


static func _trim(x: float) -> String:
	return str(snappedf(x, 0.1)).trim_suffix(".0")


# -------------------------------------------------------------------- the order --

## A tap on a chip: the first tap appends, a tap on a ranked one removes it, a fifth is refused ("Four at most: tap one to drop it"). {"ok", "why"}.
func toggle(id) -> Dictionary:
	var key := String(id)
	if not active():
		return {"ok": false, "why": "Priorities are for the base you run"}
	if not IDS.has(key):
		return {"ok": false, "why": "That is not a priority"}
	if order.has(key):
		order.erase(key)
	elif order.size() >= MAX_SET:
		return {"ok": false, "why": "Four at most: tap one to drop it"}
	else:
		order.append(key)
	_changed()
	return {"ok": true, "why": ""}


## The whole order at once (the briefing card's "Use these"): the known ids, each once, at most four; anything else refuses and changes nothing.
func set_order(ids: Array) -> Dictionary:
	if not active():
		return {"ok": false, "why": "Priorities are for the base you run"}
	var next: Array = []
	for raw in ids:
		var key := String(raw)
		if not IDS.has(key):
			return {"ok": false, "why": "That is not a priority"}
		if not next.has(key):
			next.append(key)
	if next.size() > MAX_SET:
		return {"ok": false, "why": "Four at most: tap one to drop it"}
	order = next
	_changed()
	return {"ok": true, "why": ""}


func _changed() -> void:
	_dirty = true
	sim.events.append({"type": "priorities", "order": order.duplicate()})
	var names: Array = []
	for id in order:
		names.append(name_of(id))
	var text := ("Priorities: " + ", ".join(names)) if not names.is_empty() else "Priorities cleared: the jobs stay as they are"
	var last = sim.radio.news[sim.radio.news.size() - 1] if not sim.radio.news.is_empty() else null
	if last != null and int(last.id) == _tap_news and float(sim.clock_min) - _tap_t < 60.0:
		last["text"] = text    # (taps within the hour are one line)
		_tap_t = float(sim.clock_min)
		return
	var e: Dictionary = sim.radio.log_news("policy", text, "The base puts the first ones first", {"data": {"priorities": true}})
	_tap_news = int(e.id)
	_tap_t = float(sim.clock_min)


## 0 = not ranked, 1 to 4.
func rank_of(id) -> int:
	return order.find(String(id)) + 1


func weight(id) -> float:
	var r := rank_of(id)
	return float(RANK_W[r - 1]) if r > 0 and active() else 0.0


## The two ids the top concerns point at (the briefing card's "Use these"): the first two different priorities the ranked concerns belong to, then the base's
## own two (defence, food) for the places that are empty. Pure.
func suggested() -> Array:
	var out: Array = []
	if active() and sim.briefing != null and sim.briefing.has_method("concerns"):
		for c in sim.briefing.concerns():
			var key := String(c.get("priority", ""))
			if String(c.get("level", "")) != "ok" and IDS.has(key) and not out.has(key):
				out.append(key)
				if out.size() >= 2:
					return out
	for key in ["defence", "food", "water"]:
		if out.size() >= 2:
			break
		if not out.has(key):
			out.append(key)
	return out


# ----------------------------------------------------------------------- shifts --

## tactics.repair_below: 0.05 * w(defence) - 0.05 * w(rebuild), clamped to +-0.15 (Defence first: mends from 85% not 70%; Rebuilding first: 55%, the crew is on the site).
func wall_line_shift() -> float:
	if not active() or order.is_empty():
		return 0.0
	var per := _n("shifts.wall_line_per_w", 0.05)
	var cap := _n("shifts.wall_line_max", 0.15)
	return clampf(per * weight("defence") - per * weight("rebuild"), -cap, cap)


## workshop.target(): 100 * min(w(defence), 3) / 3, to the station's step of 25 (+100 at rank 1).
func ammo_target_shift() -> float:
	if not active() or order.is_empty():
		return 0.0
	var w := minf(weight("defence"), 3.0)
	if w <= 0.0:
		return 0.0
	return snappedf(_n("shifts.ammo_target_max", 100.0) * w / 3.0, maxf(_n("shifts.ammo_target_step", 25.0), 1.0))


# ------------------------------------------------------------------------ hands --

func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _is_player(p) -> bool:
	return p.player or String(p.id) == String(sim.player_id)


func _job(p) -> String:
	return String(sim.jobs.job_of(p))


## Whether this person was moved by someone else since the staffer last looked (or was before and nobody let them go). Pure.
func _is_pinned(p) -> bool:
	var id := String(p.id)
	if pins.has(id):
		return true
	if not staffed.has(id):
		return false
	var at := String(staffed[id])
	if at != "" and not sim.jobs.unlocked(at):
		return false    # (the building came down: the seat went with it, nobody moved them)
	return _job(p) != at


## Alive, here, up, not the player, not pinned, not kept apart: someone the plan may seat.
func _hand(p) -> bool:
	if p.dead or p.turned or p.downed or p.away != null or _is_player(p):
		return false
	if CrewLoad.on_trip(sim, p) or sim.morale.breakdown(p) or sim.medical.is_apart(p) or sim.medical.sendouts.has(p.id):
		return false
	return not _is_pinned(p)


## How many people are not planned only because they are pinned or away on a trip: they keep their seats, and they still count as hands for the floors.
func _kept_up() -> int:
	var n := 0
	for p in sim.people:
		if p.dead or p.turned or p.downed or _is_player(p) or sim.morale.breakdown(p) or sim.medical.is_apart(p):
			continue
		if _is_pinned(p) or CrewLoad.on_trip(sim, p):
			n += 1
	return n


## The hands, in the order of the crew list.
func _hands() -> Array:
	var out: Array = []
	for p in sim.people:
		if _hand(p):
			out.append(p)
	return out


## The weary hands a ranked Rest leaves without a seat: the weariest first (ties by the crew list), one from weight 1.5, two from 3.0.
func _rested(hands: Array) -> Array:
	var w := weight("rest")
	var n := 0
	if w >= _n("plan.rest.two_from", 3.0):
		n = 2
	elif w >= _n("plan.rest.one_from", 1.5):
		n = 1
	if n == 0:
		return []
	var weary = sim.policies.get("weary")
	if not (weary is Dictionary):
		return []
	var from := _n("plan.rest.weary_from", 40.0)
	var tired: Array = []
	for p in hands:
		if _num(weary.get(String(p.id), 0.0)) and float(weary.get(String(p.id), 0.0)) >= from:
			tired.append(p)
	tired.sort_custom(func(a, b):
		var wa := float(weary.get(String(a.id), 0.0))
		var wb := float(weary.get(String(b.id), 0.0))
		if not is_equal_approx(wa, wb):
			return wa > wb
		return sim.people.find(a) < sim.people.find(b))
	return tired.slice(0, n)


## The stations that exist now, in the order that breaks a tie (jobs.AUTO_ORDER, then any other).
func _stations() -> Array:
	var have: Array = []
	for st in sim.jobs.stations():
		have.append(String(st.id))
	var out: Array = []
	for id in sim.jobs.AUTO_ORDER:
		if have.has(String(id)):
			out.append(String(id))
	for id in have:
		if not out.has(id):
			out.append(id)
	return out


func _lever(id: String) -> Dictionary:
	var lv = _dict("plan.lever").get(id, {})
	return lv if lv is Dictionary else {}


## Whether a ranked priority has a seat lever.
func _levered() -> bool:
	for id in order:
		if not _lever(String(id)).is_empty():
			return true
	return false


## What the stores, the walls and the sick add to a station's wish for hands (`plan.need`).
func _needs() -> Dictionary:
	var out := {}
	var prm := _dict("plan.need")
	if sim.jobs.unlocked("garden"):
		var g: Dictionary = prm.get("garden", {})
		var days: float = sim.supplies.days_left("food")
		var add := 0.0
		if days < float(g.get("days", 4.0)):
			add += float(g.get("add", 1.5))
			if days < float(g.get("more_days", 2.0)):
				add += float(g.get("more_add", 1.5))
		out["garden"] = add
	if sim.jobs.unlocked("bench"):
		var b: Dictionary = prm.get("bench", {})
		var ammo: float = sim.stock.ammo
		var add := 0.0
		if ammo < float(b.get("ammo", 90.0)) and float(sim.stock.scrap) > float(sim.workshop.reserve()) + float(b.get("scrap_over", 3.0)):
			add += float(b.get("add", 1.5))
			if ammo < float(b.get("more_ammo", 40.0)):
				add += float(b.get("more_add", 1.5))
		out["bench"] = add
	if sim.jobs.unlocked("builders"):
		var d: Dictionary = prm.get("builders", {})
		var line: float = sim.tactics.repair_below()
		var walls := 0
		for s in sim.segments:
			if float(s.hp) < float(s.max_hp) * line:
				walls += 1
		var add := float(d.get("per_wall", 1.0)) * float(mini(walls, int(d.get("max_walls", 3))))
		if not sim.build.active_site().is_empty():
			add += float(d.get("site", 1.5))
		out["builders"] = add
	if sim.jobs.unlocked("infirmary") and _anyone_hurt():
		out["infirmary"] = float((prm.get("infirmary", {}) as Dictionary).get("patients", 2.0))
	if sim.jobs.unlocked("salvage"):
		var v: Dictionary = prm.get("salvage", {})
		if float(sim.stock.scrap) < float(v.get("scrap", 12.0)):
			out["salvage"] = float(v.get("add", 1.0))
	return out


## Anyone alive and at the base who is bleeding, down, feverish, infected or sick.
func _anyone_hurt() -> bool:
	for p in sim.people:
		if p.dead or p.turned or p.away != null:
			continue
		if p.bleeding > 0.0 or p.downed or p.infected_at >= 0.0 or String(sim.medical.infection_stage(p)) != "" or sim.storyteller.is_sick(p):
			return true
	return false


## PURE: {station id: wanted hands} for the hands the plan seats (alive, here, up, not the player, not pinned, not kept apart; the weariest left out for Rest),
## stations with no hand left out. D[s] = base[s] + sum_p w(p) * lever[p][s] + need[s]; the radio desk and the lookout post one hand each first when the
## hands are at least 4; then the seats one at a time to the station with the highest D[s] / (given[s] + 1), ties in jobs.AUTO_ORDER, never above the seats
## the pinned and the away do not hold; {} while nothing is ranked.
func seat_plan() -> Dictionary:
	if not active() or order.is_empty():
		return {}
	var hands := _hands()
	var rested := _rested(hands)
	var planned: Array = []
	for p in hands:
		if not rested.has(p):
			planned.append(p)
	return _plan_for(planned, rested)


func _plan_for(planned: Array, rested: Array) -> Dictionary:
	var plan := {}
	if not _levered():
		# (no seat lever among the ranked: the staffing the hands have now)
		for p in planned:
			var s := _job(p)
			if s != "":
				plan[s] = int(plan.get(s, 0)) + 1
		return plan
	var stations := _stations()
	var cap := {}
	for s in stations:
		var holders := 0
		for q in sim.jobs.crew_of(s):
			if not planned.has(q) and not rested.has(q):
				holders += 1
		cap[s] = maxi(0, int(sim.jobs.seats_of(s)) - holders)
	var base := _dict("plan.base")
	var need := _needs()
	var want := {}
	for s in stations:
		var d := float(base.get(s, 0.0)) + float(need.get(s, 0.0))
		for id in order:
			d += weight(String(id)) * float(_lever(String(id)).get(s, 0.0))
		want[s] = d
	var given := {}
	for s in stations:
		given[s] = 0
	var left := planned.size()
	var floors = _node("plan.floors.stations")
	if left + _kept_up() >= int(_n("plan.floors.min_hands", 4.0)) and floors is Array:    # (a pinned person, or one away on an errand, is still a hand for the floors: a pin or a trip must not take the radio desk's)
		for s in floors:
			if left > 0 and cap.has(String(s)) and int(cap[String(s)]) > 0:
				given[String(s)] = 1
				left -= 1
	while left > 0:
		var best := ""
		var best_v := 0.0
		for s in stations:
			if int(given[s]) >= int(cap[s]) or float(want[s]) <= 0.0:
				continue
			var v := float(want[s]) / float(int(given[s]) + 1)
			if v > best_v + 1.0e-9:
				best_v = v
				best = s
		if best == "":
			break
		given[best] = int(given[best]) + 1
		left -= 1
	for s in stations:
		if int(given[s]) > 0:
			plan[s] = int(given[s])
	return plan


## The priority that asks most for hands at a station ("Defence"), "" when none does.
func _driver(station: String) -> String:
	var best := ""
	var best_v := 0.0
	for id in order:
		var v := weight(String(id)) * float(_lever(String(id)).get(station, 0.0))
		if v > best_v + 1.0e-9:
			best_v = v
			best = String(id)
	return name_of(best) if best != "" else ""


# ----------------------------------------------------------------------- staffing --

## Runs the staffing plan through `jobs.assign` only: {"moved": [{"who", "from", "to"}] (people who left a seat, for another or for none), "filled": n (seats
## given to people who had none), "pinned": [ids]}. Does nothing while `order` is empty, at night, under the alarm, with the dead at the wall or within an
## hour of its last run. Pinned people are never touched. A seat is moved only when the plan differs from the staffing by a whole seat.
func staff() -> Dictionary:
	var out := {"moved": [], "filled": 0, "pinned": []}
	if not active() or order.is_empty():
		return out
	_sync_pins()
	out["pinned"] = pinned()
	if sim.phase != "day" or sim.posts_manned() or float(sim.clock_min) - _last_staff < _n("staff.gap_min", 60.0):
		return out
	_last_staff = float(sim.clock_min)
	var hands := _hands()
	var rested := _rested(hands)
	var planned: Array = []
	for p in hands:
		if not rested.has(p):
			planned.append(p)
	var plan := _plan_for(planned, rested)
	var before := {}
	for q in sim.people:
		before[String(q.id)] = _job(q)
	var moves := {}    # person id -> {"from", "to", "rest"}
	var cur := {}
	var free: Array = []
	for p in planned:
		var s := _job(p)
		if s == "":
			free.append(p)
		else:
			if not cur.has(s):
				cur[s] = []
			(cur[s] as Array).append(p)
	for p in rested:
		var s := _job(p)
		if s != "":
			sim.jobs.assign(p, "")
			moves[String(p.id)] = {"from": s, "to": "", "rest": true}
	var stations := _stations()
	for s in stations:
		var list: Array = cur.get(s, [])
		while list.size() > int(plan.get(s, 0)):
			var worst = list[0]
			for q in list:
				var fq: float = sim.jobs.fit_of(q, s)
				var fw: float = sim.jobs.fit_of(worst, s)
				if fq < fw or (is_equal_approx(fq, fw) and sim.people.find(q) > sim.people.find(worst)):
					worst = q
			list.erase(worst)
			sim.jobs.assign(worst, "")
			free.append(worst)
			moves[String(worst.id)] = {"from": s, "to": "", "rest": false}
		cur[s] = list
	var filled := 0
	for s in stations:
		var list: Array = cur.get(s, [])
		while list.size() < int(plan.get(s, 0)):
			var best = null
			var best_f := -1.0e9
			for q in free:
				if String(sim.jobs.why_not(q, s)) != "":
					continue
				var f: float = sim.jobs.fit_of(q, s)
				if best == null or f > best_f + 1.0e-9 or (is_equal_approx(f, best_f) and sim.people.find(q) < sim.people.find(best)):
					best = q
					best_f = f
			if best == null or not sim.jobs.assign(best, s):
				break
			list.append(best)
			free.erase(best)
			var id := String(best.id)
			if moves.has(id):
				moves[id]["to"] = s
			else:
				moves[id] = {"from": "", "to": s, "rest": false}
				filled += 1
		cur[s] = list
	# what is where now: the staffer's own record, so that nobody is taken for pinned because of what it did (a seat made room for by sending away someone who was on a trip)
	for q in sim.people:
		var id := String(q.id)
		var now := _job(q)
		if planned.has(q) or rested.has(q):
			staffed[id] = now
		elif staffed.has(id) and not pins.has(id) and String(before.get(id, now)) != now:
			staffed[id] = now
	var moved: Array = []
	var lines: Array = []
	for q in sim.people:
		var id := String(q.id)
		if not moves.has(id):
			continue
		var mv: Dictionary = moves[id]
		if String(mv.from) != "":
			moved.append({"who": id, "from": String(mv.from), "to": String(mv.to)})
		lines.append(_move_line(q, mv))
	out["moved"] = moved
	out["filled"] = filled
	_say_moves(lines)
	return out


## "The base moved Marcus to the beds (Food)".
func _move_line(p, mv: Dictionary) -> String:
	var short := _dict("short")
	var first := String(p.first)
	var to := String(mv.to)
	var from := String(mv.from)
	if bool(mv.get("rest", false)):
		return "The base sent %s to rest (%s)" % [first, name_of("rest")]
	var why := _driver(to)
	var tail := (" (%s)" % why) if why != "" else ""
	if to == "":
		return "The base took %s off %s" % [first, String(short.get(from, from))]
	if from == "":
		return "The base put %s at %s%s" % [first, String(short.get(to, to)), tail]
	return "The base moved %s to %s%s" % [first, String(short.get(to, to)), tail]


## The News lines of a run, at most max_lines a day (what does not fit is one more line that says how many moves were not told).
func _say_moves(lines: Array) -> void:
	if lines.is_empty():
		return
	if _lines_day != int(sim.day):
		_lines_day = int(sim.day)
		_lines_n = 0
	var room := maxi(0, int(_n("staff.max_lines", 3.0)) - _lines_n)
	if room <= 0:
		return
	if lines.size() <= room:
		for l in lines:
			sim.radio.log_news("policy", String(l), "", {"data": {"staff": true}})
		_lines_n += lines.size()
		return
	for i in room - 1:
		sim.radio.log_news("policy", String(lines[i]), "", {"data": {"staff": true}})
	var more := lines.size() - (room - 1)
	sim.radio.log_news("policy", "The base made %d more moves" % more, "The Jobs page shows who is where", {"data": {"staff": true}})
	_lines_n += room


## Writes down who has been moved by someone else.
func _sync_pins() -> void:
	for p in sim.people:
		if _is_pinned(p) and not pins.has(String(p.id)):
			pins[String(p.id)] = true


## "Let the base decide": nobody is pinned any more, and where they stand is where the staffer finds them.
func release_pins() -> void:
	pins = {}
	for id in staffed.keys():
		var p = _person(String(id))
		if p == null:
			staffed.erase(id)
		else:
			staffed[id] = _job(p)
	_dirty = true


## The ids of the people the staffer will not touch (moved by someone else), alive, in the crew's order.
func pinned() -> Array:
	var out: Array = []
	if sim == null:
		return out
	for p in sim.people:
		if not (p.dead or p.turned) and not _is_player(p) and _is_pinned(p):
			out.append(String(p.id))
	return out


# --------------------------------------------------------------------------- looks --

func update(dt: float) -> void:
	if not active():
		return
	_acc += dt
	if _acc < TICK_S:
		return
	_acc -= TICK_S
	look()


## One slow look: the hours worked, the staffing when something changed (a person lost, back or new, a building built, a priority tapped) and at the morning's
## first look, and the standing errand while its window is open.
func look() -> void:
	if not active():
		return
	for st in sim.jobs.stations():
		var n: int = sim.jobs.working(String(st.id)).size()
		if n > 0:
			_hours[String(st.id)] = float(_hours.get(String(st.id), 0.0)) + 0.5 * float(n)
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_dirty = true
	if order.is_empty():
		_dirty = false
		return
	if sim.phase == "day" and int(sim.day) != _morning_day and float(sim.hour) >= _n("errand.from_h", 6.5):
		_morning_day = int(sim.day)
		_dirty = true
	if _dirty:
		var was := _last_staff
		staff()
		if _last_staff != was:
			_dirty = false
	if _errand_day != int(sim.day):
		standing_errand()


## What changes the plan between two looks: the people (their ids: one lost or new; a trip is not a change, whoever is away keeps the seat and comes home to it)
## and the buildings.
func _signature() -> String:
	var ids: Array = []
	for p in sim.people:
		if not (p.dead or p.turned or _is_player(p)):
			ids.append(String(p.id))
	return "%d|%s" % [int(sim.build.version), ",".join(ids)]


## {station: game hours worked since the briefing}: each slow look adds 0.5 * jobs.working(id).size() (read by the debrief).
func seat_hours() -> Dictionary:
	return _hours.duplicate()


func reset_seat_hours() -> void:
	_hours = {}


# ------------------------------------------------------------------ the errand --

## The stocks the standing errand may be sent for, with how much the base wants each (best first): [{"stock", "score", "short"}]. With Scavenging ranked every stock is a
## candidate (the shortest first; when nothing is short, the one the base has least of); otherwise only food and water under three days that are ranked.
func _wishes() -> Array:
	var out: Array = []
	var any := weight("scavenge") > 0.0
	var short := _dict("errand.short")
	var cover := _dict("errand.cover")
	var days_short := _n("errand.short_days", 3.0)
	for stock in STOCKS:
		var have := 0.0
		var limit := float(short.get(stock, 1.0))
		var prio := ""
		match stock:
			"food":
				have = sim.supplies.days_left("food")
				prio = "food"
			"water":
				have = sim.supplies.days_left("water")
				prio = "water"
			"scrap":
				have = sim.stock.scrap
				prio = "rebuild"
			"meds":
				have = sim.stock.meds
			"ammo":
				have = sim.stock.ammo
				limit = minf(limit, float(sim.workshop.target()))
				prio = "defence"
		if not any:
			if not (stock == "food" or stock == "water") or weight(prio) <= 0.0 or have >= days_short:
				continue
		var lack := clampf((limit - have) / maxf(limit, 1.0e-6), 0.0, 1.0)
		var score := lack * (1.0 + 0.5 * (weight(prio) if prio != "" else 0.0))
		var is_short := score > 0.0
		if not is_short:
			# (nothing short: the stock the base has least of, so that a standing order still brings something)
			score = 1.0e-3 * (1.0 - clampf(float(have) / maxf(float(cover.get(stock, 10.0)), 1.0e-6), 0.0, 1.0))
		out.append({"stock": stock, "score": score, "short": is_short})
	out.sort_custom(func(a, b):
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) > float(b.score)
		return STOCKS.find(String(a.stock)) < STOCKS.find(String(b.stock)))
	return out


## The stock the base wants most ("food", "water", "scrap", "meds", "ammo" or "").
func errand_wish() -> String:
	if not active() or order.is_empty():
		return ""
	var w := _wishes()
	return String(w[0].stock) if not w.is_empty() else ""


## At the first slow looks from 06:30 to 09:30, once a day: when Scavenging is ranked, or Food / Water is and that stock is under 3 days, nobody is out and a trip
## can be sent, two people who agree (`radio.request_errand`: its delay, its refusals, its terms) go to a place that has what the base wants. {"sent", "why"},
## and with "sent" the "line" ("Standing order: Dez and Ana set off for the pharmacy (Scavenging)"), the "place" and the people ("going").
func standing_errand() -> Dictionary:
	var out := {"sent": false, "why": ""}
	if not active() or order.is_empty():
		return out
	if _errand_day == int(sim.day):
		out["why"] = "A standing order went out today"
		return out
	var h: float = sim.hour
	if sim.phase != "day" or h < _n("errand.from_h", 6.5) or h > _n("errand.to_h", 9.5):
		out["why"] = "Standing orders go out from 06:30 to 09:30"
		return out
	var wishes := _wishes()
	if wishes.is_empty():
		out["why"] = "No standing order"
		return out
	if sim.posts_manned() or not sim.scavenge.parties.is_empty() or not sim.radio.errand_wait.is_empty():
		return _no_errand(out, "A party is out, or the dead are at the wall")
	if not sim.scavenge.can_send():
		return _no_errand(out, String(sim.scavenge.why_not()))
	var found := {}
	var stock := ""
	for w in wishes:
		var site := _errand_site(String(w.stock), int(_n("errand.max_danger_short", 2.0)) if bool(w.short) else int(_n("errand.max_danger", 1.0)))
		if not site.is_empty():
			found = site
			stock = String(w.stock)
			break
	if found.is_empty():
		return _no_errand(out, "No place the base can reach has what it wants")
	var party := _errand_party(String(found.id))
	if party.is_empty():
		return _no_errand(out, "Nobody is free to go")
	var asked: Dictionary = sim.radio.request_errand(party, String(found.id), "loot")
	if not bool(asked.get("ok", false)):
		return _no_errand(out, String(asked.get("why", "")) if String(asked.get("why", "")) != "" else "They cannot set off")
	var ids: Array = []
	var names: Array = []
	for p in asked.going:
		ids.append(String(p.id))
		names.append(String(p.first))
	var where := String(found.get("where", found.get("name", "the place")))
	var why := _errand_driver(stock)
	var line := "Standing order: %s set off for %s%s" % [_and(names), where, (" (%s)" % why) if why != "" else ""]
	_errand_day = int(sim.day)
	last_errand = {"day": int(sim.day), "line": line, "ids": ids, "place": String(found.id), "stock": stock, "names": names, "where": where}
	sim.radio.log_news("policy", line, "Looking for %s" % stock, {"data": {"errand": true, "place": String(found.id)}})
	out["sent"] = true
	out["line"] = line
	out["place"] = String(found.id)
	out["going"] = ids
	return out


## The errand did not go: why (kept for the day's debrief).
func _no_errand(out: Dictionary, why: String) -> Dictionary:
	out["why"] = why
	last_why = {"day": int(sim.day), "why": why}
	return out


## The priority the errand is for (Scavenging if it is ranked, else the stock's own), as a name.
func _errand_driver(stock: String) -> String:
	var own := {"food": "food", "water": "water", "ammo": "defence", "scrap": "rebuild"}.get(stock, "") as String
	if own != "" and weight(own) > 0.0 and weight(own) >= weight("scavenge"):
		return name_of(own)
	return name_of("scavenge") if weight("scavenge") > 0.0 else ""


## The place to go for a stock (copied from initiative._find_errand, not called): known, not picked over, on foot, not too dangerous (`errand.max_danger`, or
## `max_danger_short` for a stock that is short, and `policies.errand_limit`), with that stock in its loot; the safest first, then the nearest.
func _errand_site(stock: String, max_danger: int) -> Dictionary:
	var found: Array = []
	for s in sim.scavenge.available_sites():
		if not bool(s.get("available", false)) or bool(s.get("needs_vehicle", false)) or int(s.get("danger", 9)) > max_danger:
			continue
		if not (s.get("actions", []) as Array).has("loot") or not (s.get("loot", {}) as Dictionary).has(stock):
			continue
		if sim.policies.has_method("errand_limit") and String(sim.policies.errand_limit(String(s.id))) != "":
			continue
		found.append(s)
	if found.is_empty():
		return {}
	found.sort_custom(func(a, b):
		if int(a.danger) != int(b.danger):
			return int(a.danger) < int(b.danger)
		if not is_equal_approx(float(a.get("hours", 0.0)), float(b.get("hours", 0.0))):
			return float(a.get("hours", 0.0)) < float(b.get("hours", 0.0))
		return String(a.id) < String(b.id))
	return found[0]


## Up to two people who would go: the ones with no seat first, then those at the stations the priorities ask least of, then the best shots; not those at the radio
## desk or the lookout post, nor the nurse with a patient; and two at least stay.
func _errand_party(place_id: String) -> Array:
	var cands: Array = []
	var hurt := _anyone_hurt()
	for p in sim.people:
		if not _hand(p) or not sim.scavenge.can_go(p) or not bool(sim.radio.reason_not(p, "go").ok):
			continue
		var s := _job(p)
		if s == "radio" or s == "watch" or (s == "infirmary" and hurt):
			continue
		cands.append(p)
	cands.sort_custom(func(a, b):
		var ja := _station_value(_job(a))
		var jb := _station_value(_job(b))
		if not is_equal_approx(ja, jb):
			return ja < jb
		var sa := int(a.skills.get("Shooting", 0))
		var sb := int(b.skills.get("Shooting", 0))
		if sa != sb:
			return sa > sb
		return sim.people.find(a) < sim.people.find(b))
	var stay := int(_n("errand.stay_min", 2.0))
	for p in cands:
		var party: Array = [p]
		for q in cands:
			if q != p and bool(sim.radio.reason_not(q, "go", [String(p.id)]).ok) and bool(sim.radio.reason_not(p, "go", [String(q.id)]).ok):
				party.append(q)
				break
		while party.size() > 0:
			if CrewLoad.stay_count(sim, party) >= stay and bool(sim.radio.errand_willingness(party, place_id, "loot").ok):
				return party
			party.pop_back()
	return []


## What the base asks of a station (its base wish plus the levers of the ranked priorities; -1 for no station): the errand takes its people from the stations the
## player cares least about.
func _station_value(station: String) -> float:
	if station == "":
		return -1.0
	var v := float(_dict("plan.base").get(station, 0.0))
	for id in order:
		v += weight(String(id)) * float(_lever(String(id)).get(station, 0.0))
	return v


static func _and(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


# ---------------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {
		"order": order.duplicate(), "staffed": staffed.duplicate(), "pins": pins.duplicate(), "acc": _acc, "dirty": _dirty, "sig": _sig,
		"last_staff": _last_staff, "morning_day": _morning_day, "errand_day": _errand_day, "lines_day": _lines_day, "lines_n": _lines_n,
		"hours": _hours.duplicate(), "last_errand": last_errand.duplicate(true), "last_why": last_why.duplicate(),
	}


## Restores what `save` wrote; {} (a save from before) is a fresh module. What is not sound (an id that is not known, a fifth rank, a number that is not finite)
## is left out or held to its range.
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
			var at := str(st[k])
			if _person(str(k)) != null and (at == "" or not sim.jobs.station(at).is_empty()):
				staffed[str(k)] = at
	var pn = d.get("pins", {})
	if pn is Dictionary:
		for k in pn:
			if _person(str(k)) != null:
				pins[str(k)] = true
	_acc = clampf(float(d.acc), 0.0, TICK_S) if _num(d.get("acc")) else 0.0
	_dirty = bool(d.get("dirty", false)) if typeof(d.get("dirty", false)) == TYPE_BOOL else false
	var sg = d.get("sig", "")
	_sig = str(sg).substr(0, 600) if typeof(sg) == TYPE_STRING else ""
	_last_staff = minf(float(d.last_staff), float(sim.clock_min)) if _num(d.get("last_staff")) else NEVER
	_morning_day = clampi(int(d.morning_day), 0, int(sim.day)) if _num(d.get("morning_day")) else 0
	_errand_day = clampi(int(d.errand_day), 0, int(sim.day)) if _num(d.get("errand_day")) else 0
	_lines_day = clampi(int(d.lines_day), 0, int(sim.day)) if _num(d.get("lines_day")) else 0
	_lines_n = clampi(int(d.lines_n), 0, 99) if _num(d.get("lines_n")) else 0
	var hrs = d.get("hours", {})
	if hrs is Dictionary:
		for k in hrs:
			if not sim.jobs.station(str(k)).is_empty() and _num(hrs[k]):
				_hours[str(k)] = clampf(float(hrs[k]), 0.0, MAX_HOURS)
	var le = d.get("last_errand", {})
	if le is Dictionary and _num(le.get("day")):
		var ids: Array = []
		var rawids = le.get("ids", [])
		if rawids is Array:
			for id in rawids:
				if _person(str(id)) != null:
					ids.append(str(id))
		last_errand = {
			"day": clampi(int(le.day), 0, int(sim.day)), "line": str(le.get("line", "")).substr(0, MAX_TEXT), "ids": ids,
			"place": str(le.get("place", "")).substr(0, 60), "stock": str(le.get("stock", "")).substr(0, 20), "names": _strings(le.get("names", []), 40), "where": str(le.get("where", "")).substr(0, 80),
		}
	var lw = d.get("last_why", {})
	if lw is Dictionary and _num(lw.get("day")):
		last_why = {"day": clampi(int(lw.day), 0, int(sim.day)), "why": str(lw.get("why", "")).substr(0, MAX_TEXT)}
