## Specialists (round 20, slice 4: "a community with ideas"): the camp comes to know who is good at what. A title (the medic,
## the engineer, the marksman, the scout) is earned by skill and practice, held by one person at a time, and gives a small
## bonus on exactly that work, first call for the seat, and a name the radio can ask. The contract is in
## docs/superpowers/plans/2026-10-03-round-20.md (S4.2); the data is assets/data/titles.json.
##
## ELIGIBLE: the skill is at least the title's `min_skill` (6; the scout has no skill floor) and the practice is at least its
## `need`. The practice comes from `Person.stats` (the medic: `treated`; the engineer: `mended / 10 + crafted`; the marksman:
## `kills`) and, for the scout, from this module's own `record`: the trips each person came home from (`on_trip`, called by
## scavenge.gd for every party, the dice's errands and the ones the player led alike). The scout must also have more trips than
## anyone else alive. SCORE = skill + min(2.0, practice / need). A vacant title goes to the best score at once; its holder is
## displaced only by a score at least SWITCH_MARGIN higher (no flip-flop); someone who is away on a trip is named when they are home.
## Nobody holds two titles (the best score wins them, ties by
## title and then by id). The player may hold one: they shoot, mend and lead trips like anyone.
##
## LOOKS: `update` begins `if not active(): return`, adds `dt`, and evaluates every TICK_S seconds of rules time (30 game minutes:
## "the slow look") and at the dawn. Nothing here uses `sim.rng`: every choice is a pure function of the state, ties by id, so a
## saved game replays bit for bit.
##
## BECOMING is told in the News (kind "title": "Ana is the camp's medic now", sub "Medicine 10, 8 treated"), by an alert for a
## minute and by a bark. LOSING (the holder dies, turns, leaves through the gate, or has been away more than AWAY_DAYS days) is
## told ("Ana was the medic. The camp has no medic now."), gives everyone at the base a shock (`morale.shock`, SHOCK), takes the
## bonus away, and is listed by `gaps()` until an heir is named or GAP_DAYS pass. When an heir is named at the very look the title
## was lost at, the camp never was without: the News says who it was, with no shock and no gap. The first look after a load of a
## save with no module data (a save from before) names the titles silently.
##
## THE BONUS reaches every site through `traits.mult` / `traits.add` (one hook each: the bench, the hammer, the bandage, the cure,
## the aim), so "on that work" is automatic; the scout's through `party_mult` (scavenge.loot_scale) and the seat through
## `fit_bonus` (jobs._fit). Inactive (`active()` false: no avatar, not a small start, Orientation Day) every one of them is exactly
## neutral: 1.0, 0.0, null, {} or [].
extends RefCounted

const DATA_PATH := "res://assets/data/titles.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

## The slow look: rules seconds between two evaluations (30 game minutes).
const TICK_S := 10.0
## A holder is displaced only by a score this much higher.
const SWITCH_MARGIN := 1.0
## What the practice adds to the score, at most.
const PRACTICE_CAP := 2.0
## A lost title is listed (`gaps`) for this many days; a holder away this many days loses it.
const GAP_DAYS := 6
const AWAY_DAYS := 3
## Everyone at the base is shaken by the loss of a title nobody can take up (`morale.shock`).
const SHOCK := -3.0
## How long the alert for a new title stays up (seconds of rules time).
const ALERT_TTL := 60.0
## Limits for what a save may say.
const MAX_TRIPS := 100000
const MAX_DAY := 100000
const EPS := 1.0e-9

var sim
var enabled := true
## The titles by id and their ids in the order of the file; what a seat is worth to its holder; the words of a bonus.
var _defs := {}
var _order: Array = []
var _fit_value := 1.5
var _words := {}
## Title id -> the id of the person who holds it; title id -> the day it began; person id -> title id (derived).
var _holders := {}
var _since := {}
var _held := {}
## Person id -> {"trips": how many trips they came home from}.
var _records := {}
## Titles lost and not yet taken up again: title id -> {"day", "was": person id}.
var _lost := {}
## Holders who are away on a trip: person id -> the game minute they were first seen away.
var _away := {}
var _acc := 0.0
var _phase := ""
## The next look names the titles without telling (a save from before has no data of this module).
var _silent := false


func setup(s) -> void:
	sim = s
	_load()


func start() -> void:
	_reset()


func _reset() -> void:
	_holders = {}
	_since = {}
	_held = {}
	_records = {}
	_lost = {}
	_away = {}
	_acc = 0.0
	_phase = ""
	_silent = false


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and sim.recruits.small


# ----------------------------------------------------------------------- data --

func _load() -> void:
	if not _cache.has(data_path):
		_cache[data_path] = _parse(data_path)
	var c: Dictionary = _cache[data_path]
	_defs = c.defs
	_order = c.order
	_fit_value = float(c.fit)
	_words = c.words


static func _parse(path: String) -> Dictionary:
	var out := {"defs": {}, "order": [], "fit": 1.5, "words": {}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Could not read the titles from %s" % path)
		return out
	var fit := _num(parsed.get("fit_bonus"))
	if not is_nan(fit):
		out.fit = fit
	var words = parsed.get("effect_words", {})
	if words is Dictionary:
		for k in words:
			out.words[String(k)] = String(words[k])
	var list = parsed.get("titles", [])
	if not list is Array:
		return out
	for raw in list:
		if not raw is Dictionary:
			continue
		var id := String(raw.get("id", ""))
		if id == "" or out.defs.has(id):
			continue
		var effects = raw.get("effects", {})
		if not effects is Dictionary:
			effects = {}
		var need := _num(raw.get("need"))
		var party := _num(effects.get("party_loot"))
		var seats: Array = []
		if raw.get("seats") is Array:
			for st in raw.seats:
				seats.append(String(st))
		out.defs[id] = {
			"id": id,
			"name": String(raw.get("name", id)),
			"short": String(raw.get("short", id)),
			"skill": String(raw.get("skill", "")),
			"min_skill": 0.0 if is_nan(_num(raw.get("min_skill"))) else _num(raw.get("min_skill")),
			"need": 1.0 if is_nan(need) or need <= 0.0 else need,
			"practice": String(raw.get("practice", "")),
			"practice_text": String(raw.get("practice_text", "%d")),
			"seats": seats,
			"mult": _numbers(effects.get("mult")),
			"add": _numbers(effects.get("add")),
			"party_loot": 1.0 if is_nan(party) or party <= 0.0 else party,
			"blurb": String(raw.get("blurb", "")),
			"bark": String(raw.get("bark", "")),
		}
		out.order.append(id)
	return out


static func _numbers(raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for k in raw:
			var v := _num(raw[k])
			if not is_nan(v):
				out[String(k)] = v
	return out


## `v` as a float, or NAN when it is not a finite number.
static func _num(v) -> float:
	if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v)):
		return float(v)
	return NAN


static func _pid(p) -> String:
	if p == null:
		return ""
	if typeof(p) == TYPE_STRING or typeof(p) == TYPE_STRING_NAME:
		return String(p)
	return String(p.id)


func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


# ------------------------------------------------------------------ the looks --

## Every step: the slow look, and the dawn.
func update(dt: float) -> void:
	if not active():
		return
	var dawn := false
	if String(sim.phase) != _phase:
		dawn = String(sim.phase) == "dawn" and _phase != ""
		_phase = String(sim.phase)
	_acc += dt
	var slow := _acc >= TICK_S
	if slow:
		_acc = fmod(_acc, TICK_S)
	if slow or dawn:
		look()


## One evaluation at once: who has lost a title, who has earned one. (The slow look and the dawn do this; so do the tests.)
func look() -> void:
	if not active():
		return
	var silent := _silent
	_silent = false
	var vacated: Array = _lose()
	var named: Array = _name_titles()
	_prune()
	if silent:
		return
	for v in vacated:
		_tell_loss(v)
	for n in named:
		_tell_title(n.p, String(n.title))


## Takes the title off every holder who is gone (dead, turned, left) or has been away too long. Returns [{"title", "id"}].
func _lose() -> Array:
	var vacated: Array = []
	var still_away := {}
	for tid in _order:
		var pid := String(_holders.get(tid, ""))
		if pid == "":
			continue
		var p = _person(pid)
		var gone: bool = p == null or p.dead or p.turned
		if not gone and p.away != null:
			var first: float = minf(float(_away.get(pid, sim.clock_min)), float(sim.clock_min))
			still_away[pid] = first
			gone = float(sim.clock_min) - first > float(AWAY_DAYS) * 1440.0 + EPS
		if gone:
			vacated.append({"title": tid, "id": pid})
			still_away.erase(pid)
	_away = still_away
	for v in vacated:
		_holders.erase(v.title)
		_since.erase(v.title)
	_rebuild_held()
	return vacated


## Gives the vacant titles, and the ones a clearly better person can take, to the best scores. Returns [{"title", "p"}] in the order
## they were named.
func _name_titles() -> Array:
	var cands: Array = []
	for ti in _order.size():
		var tid: String = _order[ti]
		var now = _person(String(_holders.get(tid, ""))) if _holders.has(tid) else null
		var to_beat := -1.0e9
		if now != null:
			to_beat = score(now, tid) + SWITCH_MARGIN - EPS
		for p in sim.people:
			if p.dead or p.turned or p.away != null or _held.has(String(p.id)):
				continue    # (the one to call is at the base: someone away is named when they are home)
			if not eligible(p, tid):
				continue
			var s := score(p, tid)
			if now != null and s < to_beat:
				continue
			cands.append({"score": s, "ti": ti, "id": String(p.id), "p": p})
	cands.sort_custom(func(a, b):
		if a.score != b.score:
			return a.score > b.score
		if a.ti != b.ti:
			return a.ti < b.ti
		return a.id < b.id)
	var named: Array = []
	var title_done := {}
	var person_done := {}
	for c in cands:
		var tid: String = _order[c.ti]
		if title_done.has(tid) or person_done.has(c.id):
			continue
		title_done[tid] = true
		person_done[c.id] = true
		_holders[tid] = c.id
		_since[tid] = int(sim.day)
		_lost.erase(tid)
		named.append({"title": tid, "p": c.p})
	if not named.is_empty():
		_rebuild_held()
	return named


func _rebuild_held() -> void:
	_held = {}
	for tid in _holders:
		_held[String(_holders[tid])] = String(tid)


## Forgets what is stale: gaps older than GAP_DAYS, and the dead's absences.
func _prune() -> void:
	for tid in _lost.keys():
		if _holders.has(tid) or int(sim.day) - int(_lost[tid].day) >= GAP_DAYS or _lost[tid].day > sim.day:
			_lost.erase(tid)


func _base(tid: String) -> String:
	return String(_defs[tid].name).trim_prefix("the ")


func _tell_loss(v: Dictionary) -> void:
	var tid := String(v.title)
	var p = _person(String(v.id))
	var first: String = p.first if p != null else String(v.id).capitalize()
	var text := "%s was %s." % [first, String(_defs[tid].name)]
	if _holders.has(tid):
		sim.radio.log_news("title", text, "", {"data": {"who": String(v.id), "title": tid, "lost": true}})
		return
	text += " The camp has no %s now." % _base(tid)
	sim.radio.log_news("title", text, "", {"data": {"who": String(v.id), "title": tid, "lost": true}})
	_lost[tid] = {"day": int(sim.day), "was": String(v.id)}
	sim.morale.shock(null, SHOCK, "No %s: %s is gone" % [_base(tid), first])


func _tell_title(p, tid: String) -> void:
	var text := "%s is the camp's %s now" % [p.first, _base(tid)]
	var sub := practice_line(p, tid)
	sim.radio.log_news("title", text, sub, {"data": {"who": String(p.id), "title": tid}})
	var at = Vector2(p.x, p.y) if p.away == null else null
	sim.alert("title-%s" % tid, "info", text, sub, at, ALERT_TTL)
	var line := String(_defs[tid].bark)
	if line != "" and p.away == null and not p.downed and not p.dead and sim.over == "":
		sim.events.append({"type": "bark", "who": p.id, "text": line, "context": "title"})


# ------------------------------------------------------------ skill, practice --

func _skill(p, skill: String) -> float:
	var v := _num(p.skills.get(skill, 0))
	return 0.0 if is_nan(v) else v


func _stat(p, key: String) -> float:
	var v := _num(p.stats.get(key, 0))
	return 0.0 if is_nan(v) else maxf(0.0, v)


func _trips(p) -> int:
	return int(_records.get(String(p.id), {}).get("trips", 0))


## How much work this person has done of the kind the title is for (the medic: treatments; the engineer: a tenth of the HP
## mended and the scrap made into ammo; the marksman: kills; the scout: trips home).
func practice_of(p, tid: String) -> float:
	if p == null or not _defs.has(tid):
		return 0.0
	match String(_defs[tid].practice):
		"treated":
			return _stat(p, "treated")
		"mended_crafted":
			return _stat(p, "mended") / 10.0 + _stat(p, "crafted")
		"kills":
			return _stat(p, "kills")
		"trips":
			return float(_trips(p))
	return 0.0


## The skill and the practice the title asks for (nothing about anyone else).
func _meets(p, tid: String) -> bool:
	var d: Dictionary = _defs[tid]
	var skill := String(d.skill)
	if skill != "" and _skill(p, skill) + EPS < float(d.min_skill):
		return false
	return practice_of(p, tid) + EPS >= float(d.need)


## Whether this person may take the title: the skill, the practice, and for the scout more trips than anyone else alive.
func eligible(p, tid: String) -> bool:
	if p == null or not _defs.has(tid) or p.dead or p.turned or not _meets(p, tid):
		return false
	if String(_defs[tid].practice) == "trips":
		var mine := _trips(p)
		for q in sim.people:
			if q != p and not q.dead and not q.turned and _trips(q) >= mine:
				return false
	return true


## The skill plus what the practice adds (up to PRACTICE_CAP, over the need): the number titles are given by.
func score(p, tid: String) -> float:
	if p == null or not _defs.has(tid):
		return 0.0
	var d: Dictionary = _defs[tid]
	var skill := String(d.skill)
	var base := _skill(p, skill) if skill != "" else 0.0
	return base + minf(PRACTICE_CAP, practice_of(p, tid) / float(d.need))


## "Medicine 10, 8 treated": what earned the title, for the News and the tooltips.
func practice_line(p, tid: String) -> String:
	var d: Dictionary = _defs[tid]
	var prac: String = String(d.practice_text) % int(practice_of(p, tid))
	var skill := String(d.skill)
	if skill == "":
		return prac
	return "%s %d, %s" % [skill, roundi(_skill(p, skill)), prac]


## What a title gives, in words: "Bandages 25% faster, cures 8% more often".
func bonus_text(tid: String) -> String:
	if not _defs.has(tid):
		return ""
	var d: Dictionary = _defs[tid]
	var parts: Array = []
	for k in d.mult:
		parts.append(_phrase(String(k), absf(float(d.mult[k]) - 1.0)))
	for k in d.add:
		parts.append(_phrase(String(k), absf(float(d.add[k]))))
	if float(d.party_loot) != 1.0:
		parts.append(_phrase("party_loot", absf(float(d.party_loot) - 1.0)))
	var text := ", ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1)


func _phrase(key: String, amount: float) -> String:
	var word := String(_words.get(key, key + " {n}%"))
	return word.replace("{n}", str(roundi(amount * 100.0)))


# ------------------------------------------------------------------- queries --

## The person who holds the title (alive, not left), or null: the one to call.
func holder(title_id: String):
	if not active():
		return null
	var pid := String(_holders.get(title_id, ""))
	if pid == "":
		return null
	var p = _person(pid)
	if p == null or p.dead or p.turned:
		return null
	return p


## This person's title: {"id", "name" ("the medic"), "short" ("Medic"), "since_day"} and, for the views, "skill", "blurb", "bonus" (what
## it gives, in words), "practice" ("Medicine 10, 8 treated") and "score"; {} with none.
func title_of(p) -> Dictionary:
	if _held.is_empty() or not active():
		return {}
	var person = p if typeof(p) != TYPE_STRING and typeof(p) != TYPE_STRING_NAME else _person(String(p))
	if person == null or person.dead or person.turned:
		return {}
	var tid := String(_held.get(String(person.id), ""))
	if tid == "":
		return {}
	var d: Dictionary = _defs[tid]
	return {
		"id": tid, "name": String(d.name), "short": String(d.short), "since_day": int(_since.get(tid, sim.day)),
		"skill": String(d.skill), "blurb": String(d.blurb), "bonus": bonus_text(tid), "practice": practice_line(person, tid),
		"score": score(person, tid),
	}


## The titles lost in the last GAP_DAYS days that nobody has taken up: [{"id", "name", "since_day" (the day it was lost), "was": id}].
func gaps() -> Array:
	var out: Array = []
	if not active():
		return out
	for tid in _order:
		if _holders.has(tid) or not _lost.has(tid):
			continue
		var e: Dictionary = _lost[tid]
		if int(sim.day) - int(e.day) >= GAP_DAYS:
			continue
		out.append({"id": tid, "name": String(_defs[tid].name), "since_day": int(e.day), "was": String(e.was)})
	return out


## What `traits.mult` multiplies in for this key on top of the person's traits: 1.0 when they have no title that carries it (and
## exactly 1.0 when the module is off).
func mult(p, key: String) -> float:
	if _held.is_empty() or p == null or not active():
		return 1.0
	var tid := String(_held.get(_pid(p), ""))
	if tid == "":
		return 1.0
	return float(_defs[tid].mult.get(key, 1.0))


## What `traits.add` sums in for this key (0.0 with no such title, and exactly 0.0 when the module is off).
func add(p, key: String) -> float:
	if _held.is_empty() or p == null or not active():
		return 0.0
	var tid := String(_held.get(_pid(p), ""))
	if tid == "":
		return 0.0
	return float(_defs[tid].add.get(key, 0.0))


## `jobs._fit`: what the seat is worth to the person whose title it is for (the medic in the infirmary), 0.0 anywhere else.
func fit_bonus(p, station_id: String) -> float:
	if _held.is_empty() or p == null or not active():
		return 0.0
	var tid := String(_held.get(_pid(p), ""))
	if tid == "" or not (_defs[tid].seats as Array).has(station_id):
		return 0.0
	return _fit_value


## `scavenge.loot_scale`: what a party's loot is multiplied by for the titles in it (the scout: 1.12), else 1.0.
func party_mult(people: Array) -> float:
	var m := 1.0
	if _held.is_empty() or not active():
		return m
	var counted := {}
	for p in people:
		var tid := String(_held.get(_pid(p), ""))
		if tid == "" or counted.has(tid):
			continue
		counted[tid] = true
		var f: float = float(_defs[tid].party_loot)
		if f != 1.0:
			m *= f
	return m


## `scavenge._come_back`: every one of those who came home has one trip more.
func on_trip(came: Array, _lost_people: Array, _party: Dictionary) -> void:
	if not active():
		return
	for p in came:
		var pid := _pid(p)
		if pid == "":
			continue
		var row: Dictionary = _records.get(pid, {"trips": 0})
		row["trips"] = mini(MAX_TRIPS, int(row.get("trips", 0)) + 1)
		_records[pid] = row


## {"trips": how many trips they came home from, "since": {title id: the day it began}} (the title they hold now, if any).
func record_of(p) -> Dictionary:
	var pid := _pid(p)
	var mine := {}
	var tid := String(_held.get(pid, ""))
	if tid != "":
		mine[tid] = int(_since.get(tid, 0))
	return {"trips": int(_records.get(pid, {}).get("trips", 0)), "since": mine}


## "the medic" for someone who holds a title, else "": the words the radio puts beside their opinion.
func opinion_title(p) -> String:
	if _held.is_empty() or not active():
		return ""
	var tid := String(_held.get(_pid(p), ""))
	return String(_defs[tid].name) if tid != "" else ""


## Someone joined the crew: a title is earned, not given, so nothing is done.
func person_added(_p) -> void:
	pass


# ---------------------------------------------------------------------- save --

func save() -> Dictionary:
	var rec := {}
	for id in _records:
		rec[id] = {"trips": int(_records[id].trips)}
	var lost := {}
	for tid in _lost:
		lost[tid] = {"day": int(_lost[tid].day), "was": String(_lost[tid].was)}
	return {
		"v": 1, "holders": _holders.duplicate(), "since": _since.duplicate(), "records": rec, "lost": lost,
		"away": _away.duplicate(), "acc": _acc, "phase": _phase,
	}


## Restores the state from `d` and checks every part of it: a number is finite and clamped, an unknown title or person and a
## malformed entry are dropped, and a holder must be alive and meet the title's floor (the names and bonuses are the data's, never
## the file's). `{}` is a save from before this module: it starts fresh and its first look names the titles without telling.
## (Does not ask `active()`: the avatar's own state is loaded after this module's.)
func load_state(d: Dictionary) -> void:
	_reset()
	_phase = String(sim.phase)
	if d.is_empty():
		_silent = true
		return
	var rec = d.get("records", {})
	if rec is Dictionary:
		for id in rec:
			var row = rec[id]
			if _person(String(id)) == null or not row is Dictionary:
				continue
			var n := _num(row.get("trips"))
			if is_nan(n):
				continue
			var trips := roundi(clampf(n, 0.0, float(MAX_TRIPS)))
			if trips > 0:
				_records[String(id)] = {"trips": trips}
	var days = d.get("since", {})
	var held = d.get("holders", {})
	if held is Dictionary:
		for tid in held:
			if not _defs.has(String(tid)) or typeof(held[tid]) != TYPE_STRING:
				continue
			var p = _person(String(held[tid]))
			if p == null or p.dead or p.turned or _held.has(String(p.id)) or not _meets(p, String(tid)):
				continue
			_holders[String(tid)] = String(p.id)
			_held[String(p.id)] = String(tid)
			var day := _num(days.get(tid)) if days is Dictionary else NAN
			_since[String(tid)] = sim.day if is_nan(day) else clampi(roundi(clampf(day, 1.0, float(MAX_DAY))), 1, MAX_DAY)
	var lost = d.get("lost", {})
	if lost is Dictionary:
		for tid in lost:
			var e = lost[tid]
			if not _defs.has(String(tid)) or _holders.has(String(tid)) or not e is Dictionary:
				continue
			var day := _num(e.get("day"))
			if is_nan(day) or typeof(e.get("was")) != TYPE_STRING or _person(String(e.was)) == null:
				continue
			_lost[String(tid)] = {"day": clampi(roundi(clampf(day, 1.0, float(MAX_DAY))), 1, MAX_DAY), "was": String(e.was)}
	var away = d.get("away", {})
	if away is Dictionary:
		for id in away:
			var at := _num(away[id])
			if not is_nan(at) and _held.has(String(id)):
				_away[String(id)] = minf(at, float(sim.clock_min))
	var acc := _num(d.get("acc"))
	_acc = 0.0 if is_nan(acc) else clampf(acc, 0.0, TICK_S)
	if typeof(d.get("phase")) == TYPE_STRING:
		_phase = String(d.phase)
