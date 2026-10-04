## Briefing (round 25, S25.1 of docs/superpowers/plans/2026-10-04-round-25.md): the morning briefing (at the first slow look from 06:30, day 2 on, never pausing: the
## base's concerns, ranked), the evening debrief (what got done and what slipped, from the stores and the buildings) and the facilities' bottleneck labels.
## It reads the sim and the other modules one way (each read of a module of round 25 is guarded with `has_method`: an older fake has none, and the line is
## simply not there); nobody reads it but the priorities' `suggested`, the views and the debrief's own snapshot. Pure reads: `concerns` and `facilities` change
## nothing; `compose` and `debrief` write News and events, never a rule. NO `sim.rng`.
##
## A CONCERN is {"id", "level" ("alarm"|"warn"|"info"|"ok"), "text", "sub", "page" ("jobs"|"build"|"map"|"news"|"base"|"convoy"), "focus" (what that page is told to
## focus on), "score"}, and three more the debrief and `priorities.suggested` read: "priority" (the priority whose weight lifts it, "" when none), "still" (the
## words when it has not improved: "East wall still at 62%") and "done" (the words when it is gone). score = 10 * severity (alarm 3, warn 2, info 1, ok 0) + the
## weight of its priority (3 * w / 3): the priorities reorder within a level, never above a worse one. Ties by id. Only a line that is not "ok" is a concern,
## but for tonight's readiness, which says so when it is fine.
##
## THE NEWS ENTRIES: kind "briefing" ("Morning, day 4", sub the top line) and "debrief" ("Evening: 3 done, 2 slipped"). Both carry `data` with `lines`: an array of
## small lines {"level", "text", "sub", "page", "focus", ...}, ranked: the briefing's are the concerns, the debrief's the done ones ("ok") then the slipped ("warn").
extends RefCounted

const CrewLoad := preload("res://scripts/sim/crew_load.gd")
const Lots := preload("res://scripts/sim/lots.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const Priorities := preload("res://scripts/sim/priorities.gd")

const FIRST_DAY := 2
const BRIEF_FROM_H := 6.5
const MAX_LINES := 7
const DEBRIEF_BEFORE_DUSK_H := 0.25
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0
## The stocks the debrief counts.
const STOCKS := ["ammo", "scrap", "food", "water", "meds"]
const SEVERITY := {"alarm": 3, "warn": 2, "info": 1, "ok": 0}
const SIDES := {"N": "North", "S": "South", "E": "East", "W": "West"}
## How the concerns name a station ("Nobody at the radio desk") and the labels name a facility ("Workshop: waiting on scrap").
const STATION_NAMES := {
	"bench": "the bench", "builders": "the wall crew", "garden": "the vegetable beds", "infirmary": "the infirmary", "radio": "the radio desk",
	"watch": "the lookout post", "salvage": "the salvage bench",
}
const FACILITY_NAMES := {
	"bench": "Workshop", "builders": "Builders", "garden": "Garden", "infirmary": "Infirmary", "radio": "Radio desk", "watch": "Lookout", "salvage": "Salvage bench",
}
## The most lines of each kind a debrief keeps.
const MAX_DEBRIEF := 5
const MAX_TEXT := 240

var sim
var enabled := true
## What the briefing card shows (the latest `compose()`), {} before the first one.
var current := {}
## The latest `debrief()`, {} before the first one.
var last_debrief := {}
var _snap := {}
var _composed_day := 0
var _debriefed_day := 0
var _acc := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	current = {}
	last_debrief = {}
	_snap = {}
	_composed_day = 0
	_debriefed_day = 0
	_acc = 0.0


func person_added(_p) -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


func update(dt: float) -> void:
	if not active():
		return
	_acc += dt
	if _acc < TICK_S:
		return
	_acc -= TICK_S
	compose()
	debrief()


# ------------------------------------------------------------------- helpers --

static func _n(path: String, fallback: float) -> float:
	return Priorities._n("briefing." + path, fallback)


func _priorities():
	return sim.priorities if sim != null and sim.get("priorities") != null else null


func _and(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


static func _days_text(days: float) -> String:
	if days >= 99.0:
		return "plenty"
	if days < 1.0:
		return "under a day"
	var n := floori(days)
	return "%d day%s" % [n, "" if n == 1 else "s"]


static func _hhmm(hour: float) -> String:
	var m := roundi(fposmod(hour, 24.0) * 60.0)
	return "%02d:%02d" % [(m / 60) % 24, m % 60]


func _level_under(value: float, key: String) -> String:
	if value < _n(key + "_alarm", 0.0):
		return "alarm"
	if value < _n(key + "_warn", 0.0):
		return "warn"
	return "ok"


func _mk(id: String, level: String, text: String, sub: String, page: String, focus: String, priority: String, still := "", done := "") -> Dictionary:
	return {
		"id": id, "level": level, "text": text, "sub": sub, "page": page, "focus": focus, "score": 0.0, "priority": priority,
		"still": still if still != "" else "Still: %s" % text, "done": done if done != "" else "Settled: %s" % text,
	}


func _night() -> bool:
	return sim.phase == "night" or sim.phase == "dawn" or (sim.phase == "dusk" and bool(sim.bell_rung))


func _here(p) -> bool:
	return not (p.dead or p.turned) and p.away == null


## The compound's own walls (not the doors, not the lots' walls).
func _walls() -> Array:
	var out: Array = []
	for s in sim.segments:
		if s.kind != sim.DOOR_KIND and int(s.id) < Lots.FIRST_SEGMENT_ID:
			out.append(s)
	return out


## {"seg", "share"} of the weakest compound wall (the lowest id first on a tie), {} when there is none.
func _weakest() -> Dictionary:
	var low = null
	var share := 2.0
	for s in _walls():
		var sh := clampf(float(s.hp) / maxf(float(s.max_hp), 1.0), 0.0, 1.0)
		if sh < share - 1.0e-9:
			share = sh
			low = s
	return {} if low == null else {"seg": low, "share": share}


func _mean_weary() -> float:
	var weary = sim.policies.get("weary") if sim.get("policies") != null else null
	if not (weary is Dictionary):
		return 0.0
	var sum := 0.0
	var n := 0
	for p in sim.people:
		if _here(p) and not p.player:
			sum += clampf(float(weary.get(String(p.id), 0.0)), 0.0, 100.0)
			n += 1
	return sum / float(n) if n > 0 else 0.0


# ------------------------------------------------------------------ concerns --

## PURE, ranked: [{"id", "level", "text", "sub", "page", "focus", "score", ...}], the worst first. [] while the module is not active.
func concerns() -> Array:
	if not active():
		return []
	var pr = _priorities()
	var out: Array = []
	for c in _evaluate():
		if String(c.level) == "ok" and not bool(c.get("show_ok", false)):
			continue
		var line: Dictionary = c.duplicate()
		var w: float = pr.weight(String(c.priority)) if pr != null and pr.has_method("weight") and String(c.priority) != "" else 0.0
		line["score"] = 10.0 * float(SEVERITY.get(String(c.level), 0)) + 3.0 * w / 3.0
		out.append(line)
	out.sort_custom(func(a, b):
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) > float(b.score)
		return String(a.id) < String(b.id))
	return out


## Every check's answer, the fine ones too (the debrief asks about the ones that were not): each a concern.
func _evaluate() -> Array:
	var out: Array = []
	_c_days("water", out)
	_c_days("food", out)
	_c_ammo(out)
	_c_walls(out)
	_c_hurt(out)
	_c_sick(out)
	_c_stations(out)
	_c_scrap(out)
	_c_meds(out)
	_c_fuel(out)
	_c_beds(out)
	_c_problems(out)
	_c_quarantine(out)
	_c_weary(out)
	var outlook: Dictionary = sim.waves.outlook(int(sim.day)) if sim.waves.avatar_mode() else {}
	_c_tonight(out, outlook)
	_c_big_night(out, outlook)
	_c_convoy(out)
	if sim.is_one_house():
		return _town_words(out)
	return out


## One House: the school's words about scavenging, the walls, the radio desk's calls and tonight's wave do not fit a town of one house before the attacks begin. The concerns that
## have no meaning here are dropped (the lookout, the radio desk and tonight's readiness are about the nightly attacks and the school's callers) and the others are said in the
## town's words, with no scavenging priority behind them (nobody is sent out: the avatar goes and looks).
func _town_words(out: Array) -> Array:
	var attacks: bool = sim.scenario != null and sim.scenario.has_method("attacks_on") and bool(sim.scenario.attacks_on())
	var kept: Array = []
	for c in out:
		var id := String(c.id)
		if (id == "tonight" or id == "bignight") and not attacks:
			continue
		if id == "station:radio" or (id == "station:watch" and not attacks) or id == "beds":
			continue
		match id:
			"food":
				c["sub"] = "Search the houses for more, or put hands on the beds" if sim.jobs.unlocked("garden") else "Search the houses for more"
			"water":
				c["sub"] = "No station makes water: search the houses, or wait for rain"
				c["priority"] = ""
			"scrap":
				c["sub"] = "The fence and the bench both eat it: search the houses"
				c["priority"] = ""
			"meds":
				c["sub"] = "Treatment needs it: a house may have some"
				c["priority"] = ""
		kept.append(c)
	return kept


func _c_days(kind: String, out: Array) -> void:
	var days: float = sim.supplies.days_left(kind)
	var level := _level_under(days, "days")
	var name := kind.capitalize()
	var garden: bool = kind == "food" and sim.jobs.unlocked("garden")
	var sub := "Put hands on the vegetable beds, or send someone scavenging" if garden else ("No station makes water: send someone scavenging, or wait for rain" if kind == "water" else "Send someone scavenging")
	out.append(_mk(kind, level, "%s: %s left" % [name, _days_text(days)], sub, "jobs" if garden else "map", "garden" if garden else "", kind,
		"%s is still low: %s left" % [name, _days_text(days)], "%s is back up: %s left" % [name, _days_text(days)]))


func _c_ammo(out: Array) -> void:
	var ammo: float = sim.stock.ammo
	var target: float = sim.workshop.target()
	var level := "ok"
	if ammo < target:
		level = _level_under(ammo, "ammo")
	var short_of_scrap: bool = float(sim.stock.scrap) <= float(sim.workshop.reserve()) + 1.0
	var sub := "No scrap to spare for the bench" if short_of_scrap else "The bench makes more from scrap"
	out.append(_mk("ammo", level, "Ammo: %d" % roundi(ammo), sub, "jobs", "bench", "defence", "Ammo is still low: %d" % roundi(ammo), "Ammo is back up: %d" % roundi(ammo)))


func _c_walls(out: Array) -> void:
	var w := _weakest()
	if w.is_empty():
		return
	var share: float = w.share
	var seg = w.seg
	var side := String(SIDES.get(String(seg.side), "The"))
	var pct := floori(share * 100.0 + 1.0e-6)
	var level := _level_under(share, "wall")
	var text := ("%s wall is down" % side) if share <= 0.0 else ("%s wall at %d%%" % [side, pct])
	var still := ("%s wall is still down" % side) if share <= 0.0 else ("%s wall still at %d%%" % [side, pct])
	var crew := "Nobody is on the wall crew" if sim.jobs.crew_of("builders").is_empty() else "The wall crew mends from %d%%" % roundi(float(sim.tactics.repair_below()) * 100.0)
	out.append(_mk("walls", level, text, "The weakest is the %s. %s" % [String(seg.name).to_lower(), crew], "jobs", "builders", "defence", still, "The walls are mended: %s wall at %d%%" % [side, pct]))


func _hurt_tags() -> Array:
	var out: Array = []
	for p in sim.people:
		if not _here(p):
			continue
		var tag := ""
		if p.downed and not p.stabilised:
			tag = "down"
		elif p.downed:
			tag = "in bed"
		elif p.bleeding > 0.0:
			tag = "bleeding"
		if tag != "":
			out.append({"p": p, "tag": tag})
	return out


func _c_hurt(out: Array) -> void:
	var tags := _hurt_tags()
	if tags.is_empty():
		return
	var parts: Array = []
	var level := "info"
	for e in tags:
		parts.append("%s (%s)" % [String(e.p.first), String(e.tag)])
		if String(e.tag) == "down":
			level = "alarm"
		elif String(e.tag) == "bleeding" and level != "alarm":
			level = "warn"
	out.append(_mk("bleeding", level, "Hurt: %s" % ", ".join(parts), "The infirmary treats them first, with medicine", "jobs", String(tags[0].p.id), "", "Still hurt: %s" % ", ".join(parts), "Nobody is hurt now"))


func _c_sick(out: Array) -> void:
	var parts: Array = []
	var level := "info"
	var first := ""
	for p in sim.people:
		if not _here(p):
			continue
		var tag := ""
		var grave := false
		var stage := String(sim.medical.infection_stage(p))
		if stage != "":
			tag = stage
			grave = true
		elif p.infected_at >= 0.0:
			tag = "infected"
			grave = true
		elif sim.storyteller.is_sick(p):
			tag = "fever"
		if tag == "":
			continue
		var apart: bool = sim.medical.is_apart(p)
		parts.append("%s (%s%s)" % [String(p.first), tag, ", apart" if apart else ""])
		if first == "":
			first = String(p.id)
		if not apart:
			if grave:
				level = "alarm"
			elif level != "alarm":
				level = "warn"
	if parts.is_empty():
		return
	out.append(_mk("sick", level, "Sick: %s" % ", ".join(parts), "Treat them, keep them apart, or send them out", "jobs", first, "", "Still sick: %s" % ", ".join(parts), "Nobody is sick now"))


## The stations nobody sits at that have work waiting, with what it costs (crew_load's words).
func _c_stations(out: Array) -> void:
	var line: float = sim.tactics.repair_below()
	for st in sim.jobs.stations():
		var id := String(st.id)
		if int(sim.jobs.seats_of(id)) <= 0 or not CrewLoad.staffed_in(sim, id).is_empty():
			continue
		var level := ""
		match id:
			"radio", "watch":
				level = "warn"
			"garden":
				level = "warn" if float(sim.supplies.days_left("food")) < _n("days_warn", 4.0) else "info"
			"builders":
				var worn := false
				for s in sim.segments:
					if float(s.hp) < float(s.max_hp) * line:
						worn = true
				if worn or not sim.build.active_site().is_empty():
					level = "info"
			"bench":
				if sim.workshop.can_make():
					level = "info"
			"infirmary":
				if not _hurt_tags().is_empty():
					level = "warn"
			"salvage":
				if float(sim.stock.scrap) < _n("scrap_warn", 12.0):
					level = "info"
		if level == "":
			continue
		var text := "Nobody at %s: %s" % [String(STATION_NAMES.get(id, id)), CrewLoad.cost_of(sim, id, 0)]
		var prio := {"garden": "food", "bench": "defence", "builders": "rebuild", "salvage": "rebuild"}.get(id, "") as String
		out.append(_mk("station:" + id, level, text, "Give it to someone on the Jobs page", "jobs", id, prio, "Still: %s" % text, "%s is staffed" % String(STATION_NAMES.get(id, id)).capitalize()))


func _c_scrap(out: Array) -> void:
	var scrap: float = sim.stock.scrap
	var level := _level_under(scrap, "scrap")
	out.append(_mk("scrap", level, "Scrap: %d left" % roundi(scrap), "The walls and the bench both eat it: salvage, or scavenge", "map", "", "scavenge", "Scrap is still low: %d" % roundi(scrap), "Scrap is back up: %d" % roundi(scrap)))


func _c_meds(out: Array) -> void:
	var meds: float = sim.stock.meds
	var level := _level_under(meds, "meds")
	out.append(_mk("meds", level, "Medicine: %d left" % roundi(meds), "Treatment needs it: a pharmacy has some", "map", "", "scavenge", "Medicine is still low: %d" % roundi(meds), "Medicine is back up: %d" % roundi(meds)))


func _c_fuel(out: Array) -> void:
	var parked: Array = sim.vehicles.parked()
	if parked.is_empty():
		return
	var fuel: float = sim.vehicles.fuel
	var level := "ok" if fuel >= _n("fuel_warn", 12.0) else "info"
	out.append(_mk("fuel", level, "Fuel: %d" % roundi(fuel), "A parked %s needs it to leave" % String(sim.vehicles.name_of(String(parked[0].id))).to_lower(), "map", "", "scavenge", "Fuel is still low: %d" % roundi(fuel), "Fuel is back up: %d" % roundi(fuel)))


## A survivor would come, and there is no bed for them.
func _c_beds(out: Array) -> void:
	var rc = sim.recruits
	if not rc.small or not rc.incoming.is_empty() or int(sim.day) < int(rc.FIRST_CALL_DAY) or int(sim.day) >= int(sim.scenario.total_days()):
		return
	if rc.queue.is_empty() and int(rc.generated) >= int(rc.MAX_GENERATED):
		return
	var free: int = rc.housing_free()
	if free >= 1:
		return
	out.append(_mk("beds", "info", "No free bed: the next survivor cannot come", "A bunk house or tents give beds", "build", "bunk_house", "rebuild", "Still no free bed", "There is a bed again"))


func _c_problems(out: Array) -> void:
	var pm = sim.problems
	if pm == null or not pm.has_method("marks"):
		return
	for m in pm.marks():
		var label := String(m.get("label", ""))
		var stage := int(m.get("stage", 0))
		var kind := String(m.get("kind", ""))
		var prio := {"leak": "water", "jam": "defence", "crack": "defence"}.get(kind, "") as String
		var id := String(m.get("id", ""))
		out.append(_mk("problem:" + id, "alarm" if stage >= 2 else "warn", label, "Fix it yourself (E at the marker) or ask someone", "base", id, prio, "Still open: %s" % label, "Trouble over: %s" % label.get_slice(":", 0)))


func _c_quarantine(out: Array) -> void:
	var dm = sim.dilemmas
	if dm == null or not dm.has_method("marks"):
		return
	for m in dm.marks():
		var label := String(m.get("label", "Quarantine"))
		out.append(_mk("quarantine", "info", label, "The sick are kept apart; the bunks are closed", "base", "", "", "Still: %s" % label, "The quarantine is over"))
		return


func _c_weary(out: Array) -> void:
	var weary = sim.policies.get("weary") if sim.get("policies") != null else null
	if not (weary is Dictionary) or (weary as Dictionary).is_empty():
		return
	var names: Array = []
	var first := ""
	var spent := false
	for p in sim.people:
		if not _here(p) or p.player:
			continue
		var v := float(weary.get(String(p.id), 0.0))
		if v >= _n("weary_warn", 60.0):
			names.append(String(p.first))
			if first == "":
				first = String(p.id)
			if v >= _n("weary_alarm", 85.0):
				spent = true
	if names.is_empty():
		return
	var text := "%s %s worn out" % [_and(names), "is" if names.size() == 1 else "are"]
	out.append(_mk("weary", "alarm" if spent else "warn", text, "Rest them: a priority, or a job less", "jobs", first, "rest", "%s still worn out" % _and(names), "Nobody is worn out now"))


## Tonight, from the lookout's own numbers (`tactics.readiness`): fine or not, it is said.
func _c_tonight(out: Array, outlook: Dictionary) -> void:
	# (the walls tonight will break on, as the lookout reads them, when the nights know them; else all of the walls)
	var sections: Array = outlook.get("sections", []) if not outlook.is_empty() else []
	var r: Dictionary = sim.tactics.readiness(sections)
	var pct := floori(float(r.walls) * 100.0 + 1.0e-6)
	var head := "Tonight: posts %d of %d, walls %d%%" % [int(r.manned), int(r.posts), pct]
	if bool(r.holds):
		var fine := _mk("tonight", "ok", "%s: should hold" % head, "", "jobs", "", "defence")
		fine["show_ok"] = true
		out.append(fine)
		return
	var missing: Array = []
	if float(r.walls) < NightData.num("forecast.decent_walls", 0.7):
		missing.append("the walls are low")
	if int(r.guns) < int(NightData.num("forecast.decent_guns", 2.0)):
		missing.append("no gun reaches the target wall" if int(r.guns) <= 0 else "only %d gun%s reach the target wall" % [int(r.guns), "" if int(r.guns) == 1 else "s"])
	if int(r.manned) < int(r.posts):
		var empty := int(r.posts) - int(r.manned)
		missing.append("%d post%s empty" % [empty, " is" if empty == 1 else "s are"])
	out.append(_mk("tonight", "warn", "%s: may not hold (%s)" % [head, ", ".join(missing)], "The Jobs page sets the posts", "jobs", "", "defence", "Tonight is still not ready: %s" % ", ".join(missing), "Tonight should hold"))


## A Big Night by name, only when it asks for the player (the lookout's `needs_you`).
func _c_big_night(out: Array, o: Dictionary) -> void:
	if o.is_empty() or not bool(o.get("needs_you", false)):
		return
	var side := String(o.side)
	var where := ("the %s side comes" % side) if not side.contains(" and ") else ("the %s sides come" % side)
	out.append(_mk("bignight", "warn", "Tonight is %s: be at the wall; %s at %s" % [String(o.name), where, _hhmm(float(o.first_at))], String(o.get("blurb", "")), "jobs", "", "defence"))


## In phase 2 the convoy: how many of its seven requirements are met (from day 10).
func _c_convoy(out: Array) -> void:
	var ex = sim.get("exodus")
	if ex == null or not ex.has_method("readiness") or int(sim.day) < int(_n("convoy_from_day", 10.0)):
		return
	var r = ex.readiness()
	if not (r is Dictionary):
		return
	var text := "The convoy: %d of %d ready" % [int(r.get("met", 0)), int(r.get("of", 7))]
	var ready := bool(r.get("ready", false))
	out.append(_mk("convoy", "ok" if ready else "info", text, "", "convoy", "", "", "Still: %s" % text, "The convoy is ready"))


# ------------------------------------------------------------------- compose --

## The morning's look is due: the day phase, from FIRST_DAY, from 06:30 until BRIEF_TO_H, not under the alarm or with the dead at the wall, not while the
## player is in a place, once a day.
func _morning_due() -> bool:
	if not active() or sim.over != "" or int(sim.day) < FIRST_DAY or _composed_day == int(sim.day) or sim.phase != "day":
		return false
	var h: float = sim.hour
	if h < BRIEF_FROM_H or h > _n("brief_to_h", 12.0):
		return false
	return not (sim.radio.alarm_on or sim.threat_by_day() or not sim.scavenge.party_in_place().is_empty())


## Once a day at the first slow look at or after 06:30 in the day phase, from FIRST_DAY: {"day", "lines" (the concerns, at most MAX_LINES), "order" (the priorities
## now), "suggested" (the two the concerns point at)}; keeps a snapshot for the evening; News kind "briefing" and event "briefing". {} when it is not due.
func compose() -> Dictionary:
	if not _morning_due():
		return {}
	_composed_day = int(sim.day)
	var lines: Array = concerns().slice(0, MAX_LINES)
	if lines.is_empty():
		lines = [{"id": "calm", "level": "ok", "text": "Nothing is pressing this morning", "sub": "", "page": "", "focus": "", "score": 0.0, "priority": "", "still": "", "done": ""}]
	var pr = _priorities()
	var order: Array = (pr.order as Array).duplicate() if pr != null else []
	var suggested: Array = pr.suggested() if pr != null and pr.has_method("suggested") else []
	var data := {"day": int(sim.day), "lines": lines, "order": order, "suggested": suggested}
	current = data.duplicate(true)
	_snapshot(lines)
	if pr != null and pr.has_method("reset_seat_hours"):
		pr.reset_seat_hours()
	sim.radio.log_news("briefing", "Morning, day %d" % int(sim.day), String(lines[0].text), {"data": data.duplicate(true)})
	sim.events.append({"type": "briefing", "day": int(sim.day)})
	return data


## Person.stats summed over the crew (the dead's too: what they did stays done).
func _stat_sums() -> Dictionary:
	var out := {"mended": 0.0, "treated": 0.0, "crafted": 0.0, "kills": 0.0}
	for p in sim.people:
		for k in out:
			out[k] = float(out[k]) + float(p.stats.get(k, 0.0))
	return out


func _built_map() -> Dictionary:
	var out := {}
	for pl in sim.build.plots():
		if String(pl.building) != "":
			out[String(pl.id)] = String(pl.building)
	return out


func _snapshot(lines: Array) -> void:
	var stock := {}
	for k in STOCKS:
		stock[k] = float(sim.stock.get(k, 0.0))
	var w := _weakest()
	var cons: Array = []
	for c in lines:
		if String(c.level) != "ok":
			cons.append({"id": String(c.id), "level": String(c.level), "text": String(c.text), "priority": String(c.get("priority", "")), "done": String(c.get("done", ""))})
	var sums := _stat_sums()
	_snap = {
		"day": int(sim.day), "stock": stock, "built": _built_map(), "mended": float(sums.mended), "treated": float(sums.treated), "crafted": float(sums.crafted),
		"kills": float(sums.kills), "weary": _mean_weary(), "food_days": float(sim.supplies.days_left("food")), "water_days": float(sim.supplies.days_left("water")),
		"walls": float(w.share) if not w.is_empty() else 1.0, "ammo": float(sim.stock.ammo), "concerns": cons,
	}


# ------------------------------------------------------------------- debrief --

func _evening_due() -> bool:
	if not active() or sim.over != "" or int(sim.day) < FIRST_DAY or _debriefed_day == int(sim.day):
		return false
	if _snap.is_empty() or int(_snap.get("day", 0)) != int(sim.day):
		return false    # (no briefing this morning: nothing to compare with)
	if sim.phase != "day" and sim.phase != "dusk":
		return false
	return float(sim.hour) >= float(sim.seasons.dusk_hour()) - DEBRIEF_BEFORE_DUSK_H


## Once a day at `seasons.dusk_hour() - 0.25`: {"day", "deltas" ({stock: change since the briefing}), "built" (names), "mended" (hp), "treated", "errand" (the
## standing order's line or ""), "hours" (`priorities.seat_hours`), "done" and "slipped" (lines)}. Done and slipped come from the ranked priorities and from the
## briefing's concerns. News kind "debrief" and event "debrief". {} when it is not due.
func debrief() -> Dictionary:
	if not _evening_due():
		return {}
	_debriefed_day = int(sim.day)
	var pr = _priorities()
	var snap := _snap
	var stock0: Dictionary = snap.get("stock", {})
	var deltas := {}
	for k in STOCKS:
		deltas[k] = snappedf(float(sim.stock.get(k, 0.0)) - float(stock0.get(k, 0.0)), 0.1)
	var built: Array = []
	var before: Dictionary = snap.get("built", {})
	for pl in sim.build.plots():
		var b := String(pl.building)
		if b != "" and String(before.get(String(pl.id), "")) != b:
			built.append(String(sim.build.building(b).get("name", b)))
	var sums := _stat_sums()
	var mended := snappedf(float(sums.mended) - float(snap.get("mended", 0.0)), 0.1)
	var treated := roundi(float(sums.treated) - float(snap.get("treated", 0.0)))
	var errand := ""
	var le = pr.get("last_errand") if pr != null else null
	if le is Dictionary and int(le.get("day", 0)) == int(sim.day):
		errand = String(le.get("line", ""))
	var hours := {}
	if pr != null and pr.has_method("seat_hours"):
		var worked: Dictionary = pr.seat_hours()
		for k in worked:
			hours[k] = snappedf(float(worked[k]), 0.1)
	var done: Array = []
	var slipped: Array = []
	_grade(snap, built, mended, done, slipped)
	var out := {
		"day": int(sim.day), "deltas": deltas, "built": built, "mended": mended, "treated": treated, "errand": errand, "hours": hours,
		"done": done.slice(0, MAX_DEBRIEF), "slipped": slipped.slice(0, MAX_DEBRIEF),
	}
	last_debrief = out.duplicate(true)
	var lines: Array = []
	for t in out.done:
		lines.append({"level": "ok", "text": String(t), "sub": "", "page": "", "focus": ""})
	for t in out.slipped:
		lines.append({"level": "warn", "text": String(t), "sub": "", "page": "", "focus": ""})
	var data: Dictionary = out.duplicate(true)
	data["lines"] = lines
	sim.radio.log_news("debrief", "Evening: %d done, %d slipped" % [out.done.size(), out.slipped.size()], _deltas_text(deltas), {"data": data})
	sim.events.append({"type": "debrief", "day": int(sim.day)})
	return out


## "Food -2, Scrap +6, Ammo +40": the stocks that moved.
func _deltas_text(deltas: Dictionary) -> String:
	var parts: Array = []
	for k in STOCKS:
		var v := roundi(float(deltas.get(k, 0.0)))
		if v != 0:
			parts.append("%s %s%d" % [String(k).capitalize(), "+" if v > 0 else "-", absi(v)])
	return ", ".join(parts) if not parts.is_empty() else "The stores did not move"


func _d1(x: float) -> String:
	return "%.1f" % x


## Done and slipped lines: each ranked priority first (in rank order), then the briefing's concerns that no priority speaks for.
func _grade(snap: Dictionary, built: Array, mended: float, done: Array, slipped: Array) -> void:
	var pr = _priorities()
	var ranked: Array = (pr.order as Array).duplicate() if pr != null else []
	for id in ranked:
		match String(id):
			"food", "water":
				var kind := String(id)
				var then := float(snap.get(kind + "_days", 0.0))
				var now: float = sim.supplies.days_left(kind)
				var name := Priorities.name_of(kind)
				if now > then + 0.2 and now < 99.0:
					done.append("%s: up to %s days (was %s)" % [name, _d1(now), _d1(then)])
				elif now >= 10.0 or (now >= then - 0.2 and now >= _n("days_alarm", 2.0)):
					done.append("%s: held at %s days" % [name, _d1(now)])
				elif now >= then - 0.2:
					slipped.append("%s: still low at %s days" % [name, _d1(now)])
				else:
					slipped.append("%s: down to %s days (was %s)" % [name, _d1(now), _d1(then)])
			"defence":
				var w := _weakest()
				var share := float(w.share) if not w.is_empty() else 1.0
				var ammo: float = sim.stock.ammo
				var problems: Array = []
				var then_share := float(snap.get("walls", 1.0))
				var pct := floori(share * 100.0 + 1.0e-6)
				var side := String(SIDES.get(String(w.seg.side), "")).to_lower() if not w.is_empty() else ""
				if share < then_share - 0.005:
					problems.append("the walls fell to %d%%" % pct)
				elif share < _n("wall_alarm", 0.5) and share <= then_share + 0.005:
					problems.append("the %s wall is still %s" % [side, "down" if share <= 0.0 else "at %d%%" % pct])
				if ammo < float(snap.get("ammo", 0.0)) - 0.5:
					problems.append("ammo is down to %d" % roundi(ammo))
				if problems.is_empty():
					done.append("Defence: walls at %d%%, ammo %d" % [floori(share * 100.0 + 1.0e-6), roundi(ammo)])
				else:
					slipped.append("Defence: %s" % " and ".join(problems))
			"rebuild":
				if not built.is_empty():
					done.append("Rebuilding: finished the %s" % _and(built.map(func(n): return String(n).to_lower())))
				elif mended >= 1.0:
					done.append("Rebuilding: %d hp mended" % roundi(mended))
				else:
					var line: float = sim.tactics.repair_below()
					var worn := false
					for s in sim.segments:
						if float(s.hp) < float(s.max_hp) * line:
							worn = true
					var why := "no site is up and no wall is worn"
					if sim.jobs.crew_of("builders").is_empty():
						why = "nobody is on the wall crew"
					elif worn and float(sim.stock.scrap) < float(sim.tactics.AUTO_MIN_SCRAP):
						why = "the crew waits for scrap"
					elif worn:
						why = "the crew did not get to it"
					slipped.append("Rebuilding: nothing built or mended (%s)" % why)
			"rest":
				var then_w := float(snap.get("weary", 0.0))
				var now_w := _mean_weary()
				if now_w <= 0.5 and then_w <= 0.5:
					done.append("Rest: nobody is worn")
				elif now_w <= then_w + 0.5:
					done.append("Rest: weariness %d (was %d)" % [roundi(now_w), roundi(then_w)])
				else:
					slipped.append("Rest: weariness up to %d (was %d)" % [roundi(now_w), roundi(then_w)])
			"scavenge":
				_grade_errand(pr, done, slipped)
	var now_list := _evaluate()
	for c in snap.get("concerns", []):
		var prio := String(c.get("priority", ""))
		if prio != "" and ranked.has(prio):
			continue
		var now_c := {}
		for e in now_list:
			if String(e.id) == String(c.id):
				now_c = e
		if now_c.is_empty() or String(now_c.level) == "ok":
			done.append(String(now_c.text) if not now_c.is_empty() else String(c.get("done", c.text)))
		else:
			slipped.append(String(now_c.still))


func _grade_errand(pr, done: Array, slipped: Array) -> void:
	var le = pr.get("last_errand") if pr != null else null
	if le is Dictionary and int(le.get("day", 0)) == int(sim.day):
		var out := false
		for party in sim.scavenge.parties:
			for id in le.get("ids", []):
				if (party.get("members", []) as Array).has(id):
					out = true
		if out:
			slipped.append("Scavenging: the errand is not home yet")
		else:
			var names: Array = le.get("names", []) if le.get("names", []) is Array else []
			if names.is_empty() or String(le.get("where", "")) == "":
				done.append("Scavenging: %s and home" % String(le.get("line", "an errand went out")).trim_prefix("Standing order: "))
			else:
				done.append("Scavenging: %s went to %s and %s home" % [_and(names), String(le.where), "is" if names.size() == 1 else "are"])
		return
	var lw = pr.get("last_why") if pr != null else null
	var why := String(lw.get("why", "")) if lw is Dictionary and int(lw.get("day", 0)) == int(sim.day) else ""
	slipped.append("Scavenging: no errand went out%s" % ((" (%s)" % why.to_lower().trim_suffix(".")) if why != "" else ""))


# ----------------------------------------------------------------- facilities --

## [{"id", "name", "pos": Vector2, "ok": bool, "bottleneck", "line", "fix": {"page", "focus"}}]: what each station waits on, from the sim's own state. A line that is
## not a bottleneck says what the station is doing. [] while the module is not active.
func facilities() -> Array:
	if not active():
		return []
	var out: Array = []
	for st in sim.jobs.stations():
		var f := _facility(String(st.id), st)
		if not f.is_empty():
			out.append(f)
	return out


func _fac(id: String, st: Dictionary, ok: bool, what: String, page: String, focus: String, at = null) -> Dictionary:
	var name := String(FACILITY_NAMES.get(id, String(st.get("name", id))))
	return {
		"id": id, "name": name, "pos": Vector2(at if at != null else st.pos), "ok": ok, "bottleneck": "" if ok else what, "line": "%s: %s" % [name, what],
		"fix": {"page": page, "focus": focus},
	}


func _patients() -> Array:
	var out: Array = []
	for p in sim.people:
		if _here(p) and (p.downed or p.bleeding > 0.0 or p.infected_at >= 0.0 or String(sim.medical.infection_stage(p)) != "" or sim.storyteller.is_sick(p)):
			out.append(p)
	return out


func _facility(id: String, st: Dictionary) -> Dictionary:
	var night := _night()
	var staffed: bool = not CrewLoad.staffed_in(sim, id).is_empty()
	match id:
		"bench":
			var ammo: float = sim.stock.ammo
			var target: float = sim.workshop.target()
			var scrap_room: float = float(sim.stock.scrap) - float(sim.workshop.reserve())
			var jam := _open_of("jam")
			if night:
				return _fac(id, st, true, "closed for the night", "", "")
			if not jam.is_empty():
				return _fac(id, st, false, "the generator is jammed", "base", String(jam.get("id", "")))
			if ammo >= target:
				return _fac(id, st, true, "ammo at its target", "", "")
			if scrap_room <= 1.0e-9:
				return _fac(id, st, false, "waiting on scrap", "map", "")
			if not staffed:
				return _fac(id, st, false, "nobody at the bench", "jobs", "bench")
			return _fac(id, st, true, "making ammo", "", "")
		"builders":
			var site: Dictionary = sim.build.active_site()
			var line: float = sim.tactics.repair_below()
			var worn := false
			for s in sim.segments:
				if float(s.hp) < float(s.max_hp) * line:
					worn = true
			var at = Vector2(site.work) if not site.is_empty() else null
			if night:
				return _fac(id, st, true, "closed for the night", "", "", at)
			if not staffed:
				if site.is_empty() and not worn:
					return _fac(id, st, true, "nothing to build", "build", "", at)
				return _fac(id, st, false, "nobody on the Builders job", "jobs", "builders", at)
			if worn and float(sim.stock.scrap) < float(sim.tactics.AUTO_MIN_SCRAP) and site.is_empty():
				return _fac(id, st, false, "waiting on scrap", "map", "", at)
			if site.is_empty() and not worn:
				return _fac(id, st, true, "nothing to build", "build", "", at)
			return _fac(id, st, true, "building" if not site.is_empty() else "mending the wall", "", "", at)
		"garden":
			if night:
				return _fac(id, st, true, "closed for the night", "", "")
			if not staffed:
				return _fac(id, st, false, "nobody tending", "jobs", "garden")
			return _fac(id, st, true, "growing food", "", "")
		"infirmary":
			var patients := _patients()
			if patients.is_empty():
				return _fac(id, st, true, "no patients", "", "")
			if float(sim.stock.meds) < 1.0:
				return _fac(id, st, false, "no medicine", "map", "")
			if not staffed:
				return _fac(id, st, false, "nobody on duty", "jobs", "infirmary", null)
			return _fac(id, st, true, "treating", "", "")
		"radio":
			if night:
				return _fac(id, st, true, "closed for the night", "", "")
			if not staffed:
				return _fac(id, st, false, "nobody at the desk", "jobs", "radio")
			return _fac(id, st, true, "on the air", "", "")
		"watch":
			if night:
				return _fac(id, st, true, "watching", "", "")
			if not staffed:
				return _fac(id, st, false, "nobody on watch", "jobs", "watch")
			return _fac(id, st, true, "watching the road", "", "")
		"salvage":
			if night:
				return _fac(id, st, true, "closed for the night", "", "")
			if not staffed:
				return _fac(id, st, false, "nobody sorting", "jobs", "salvage")
			return _fac(id, st, true, "sorting scrap", "", "")
	return {}


## The first open problem of a kind ({} when there is none, and for a module without problems).
func _open_of(kind: String) -> Dictionary:
	var pm = sim.problems
	if pm == null or not pm.has_method("open"):
		return {}
	for r in pm.open():
		if String(r.get("kind", "")) == kind:
			return r
	return {}


# ---------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"current": current.duplicate(true), "last_debrief": last_debrief.duplicate(true), "snap": _snap.duplicate(true), "composed_day": _composed_day, "debriefed_day": _debriefed_day, "acc": _acc}


## Restores what `save` wrote; {} (a save from before) is a fresh module. A damaged entry is dropped, a number held to its range.
func load_state(d: Dictionary) -> void:
	start()
	current = _clean_card(d.get("current", {}))
	last_debrief = _clean_debrief(d.get("last_debrief", {}))
	var sn = d.get("snap", {})
	if sn is Dictionary and _num(sn.get("day")) and int(sn.day) <= int(sim.day):
		_snap = _clean_snap(sn)
	_composed_day = clampi(int(d.composed_day), 0, int(sim.day)) if _num(d.get("composed_day")) else 0
	_debriefed_day = clampi(int(d.debriefed_day), 0, int(sim.day)) if _num(d.get("debriefed_day")) else 0
	_acc = clampf(float(d.acc), 0.0, TICK_S) if _num(d.get("acc")) else 0.0


static func _str(v, limit := MAX_TEXT) -> String:
	return str(v).substr(0, limit) if typeof(v) == TYPE_STRING else ""


static func _strs(v, limit := 60) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if typeof(x) == TYPE_STRING:
				out.append(_str(x, limit))
	return out


## One line of the card or the News as a save may carry it: strings held to a length, a score that is a number, a level that is one.
func _clean_line(c) -> Dictionary:
	if not (c is Dictionary) or typeof(c.get("text")) != TYPE_STRING or not SEVERITY.has(str(c.get("level", ""))):
		return {}
	var out := {"level": str(c.level)}
	for k in ["id", "text", "sub", "page", "focus", "priority", "still", "done"]:
		out[k] = _str(c.get(k, ""))
	out["score"] = clampf(float(c.score), 0.0, 1000.0) if _num(c.get("score")) else 0.0
	if typeof(c.get("show_ok")) == TYPE_BOOL:
		out["show_ok"] = bool(c.show_ok)
	return out


## The card `compose` made, from a save: {} unless it is one (a day that is a number not past today, lines that are lines).
func _clean_card(raw) -> Dictionary:
	if not (raw is Dictionary) or not _num(raw.get("day")) or int(raw.day) > int(sim.day) or not (raw.get("lines") is Array):
		return {}
	var lines: Array = []
	for c in raw.lines:
		var line := _clean_line(c)
		if not line.is_empty():
			lines.append(line)
	if lines.is_empty():
		return {}
	var ids := Priorities.IDS
	var order: Array = []
	for id in _strs(raw.get("order", [])):
		if ids.has(id) and not order.has(id):
			order.append(id)
	var suggested: Array = []
	for id in _strs(raw.get("suggested", [])):
		if ids.has(id) and not suggested.has(id):
			suggested.append(id)
	return {"day": int(raw.day), "lines": lines.slice(0, MAX_LINES), "order": order.slice(0, Priorities.MAX_SET), "suggested": suggested.slice(0, 2)}


## The debrief `debrief` made, from a save: {} unless it is one.
func _clean_debrief(raw) -> Dictionary:
	if not (raw is Dictionary) or not _num(raw.get("day")) or int(raw.day) > int(sim.day):
		return {}
	var deltas := {}
	var rd = raw.get("deltas", {})
	for k in STOCKS:
		deltas[k] = clampf(float(rd[k]), -1.0e6, 1.0e6) if rd is Dictionary and _num(rd.get(k)) else 0.0
	var hours := {}
	var rh = raw.get("hours", {})
	if rh is Dictionary:
		for k in rh:
			if _num(rh[k]):
				hours[str(k).substr(0, 20)] = clampf(float(rh[k]), 0.0, 1000.0)
	return {
		"day": int(raw.day), "deltas": deltas, "built": _strs(raw.get("built", []), 80).slice(0, 12), "mended": clampf(float(raw.mended), 0.0, 1.0e6) if _num(raw.get("mended")) else 0.0,
		"treated": clampi(int(raw.treated), 0, 1000) if _num(raw.get("treated")) else 0, "errand": _str(raw.get("errand", "")), "hours": hours,
		"done": _strs(raw.get("done", []), MAX_TEXT).slice(0, MAX_DEBRIEF), "slipped": _strs(raw.get("slipped", []), MAX_TEXT).slice(0, MAX_DEBRIEF),
	}


static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## The snapshot with every number finite and every list what it should be (a damaged one gives the neutral value for what is wrong).
func _clean_snap(sn: Dictionary) -> Dictionary:
	var stock := {}
	var raw = sn.get("stock", {})
	for k in STOCKS:
		stock[k] = clampf(float(raw[k]), 0.0, 1.0e6) if raw is Dictionary and _num(raw.get(k)) else 0.0
	var built := {}
	var rb = sn.get("built", {})
	if rb is Dictionary:
		for k in rb:
			if typeof(rb[k]) == TYPE_STRING:
				built[str(k)] = String(rb[k])
	var cons: Array = []
	var rc = sn.get("concerns", [])
	if rc is Array:
		for c in rc:
			if c is Dictionary and typeof(c.get("id")) == TYPE_STRING and SEVERITY.has(str(c.get("level", ""))):
				cons.append({
					"id": str(c.id), "level": str(c.level), "text": str(c.get("text", "")).substr(0, MAX_TEXT), "priority": str(c.get("priority", "")).substr(0, 20),
					"done": str(c.get("done", "")).substr(0, MAX_TEXT),
				})
	var out := {"day": int(sn.day), "stock": stock, "built": built, "concerns": cons}
	for k in ["mended", "treated", "crafted", "kills", "weary", "food_days", "water_days", "walls", "ammo"]:
		var top := 1.0 if k == "walls" else (100.0 if k == "weary" else 1.0e6)
		out[k] = clampf(float(sn[k]), 0.0, top) if _num(sn.get(k)) else (1.0 if k == "walls" else 0.0)
	return out
