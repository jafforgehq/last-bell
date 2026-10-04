## Dilemmas (round 25, S25.4 of docs/superpowers/plans/2026-10-04-round-25.md): the one hard choice of the base, with a timer and costs: a FEVER OUTBREAK that the
## medicine cannot cover for everyone, treat or quarantine. Avatar mode in the settlement game only (`active()`: an avatar, a small start, not Orientation Day);
## otherwise every call here answers the neutral value ({}, false, 0, []) and the game plays as it always did. NO `sim.rng` anywhere: nothing is rolled; what is
## chosen is a pure function of the state (ties by id) and the outbreak risk is an accumulator.
##
## THE CALL. On a slow look (every TICK_S seconds of rules time, 30 game minutes) from FIRST_DAY, by day, with no alarm, no dead at the wall and no other urgent
## call open (an idea or a piece of trouble may wait), at least GAP_DAYS after the last: when `trigger()` finds people sick with a passing fever (the storyteller's,
## `is_sick`) who are not kept apart and the supplies are at stake (the medicine under what treating them all costs plus MEDS_SLACK, or two or more of them), it
## raises ONE radio call (kind "dilemma", urgent: the game drops to 1x) with two answers whose labels carry the costs, a timer (TTL_MIN) and a default (quarantine).
## While the camp is deciding, or the quarantine runs, `claims(p)` keeps the plain "sick" call away from those people.
##
## THE ANSWERS, made real in the base. TREAT: each patient in turn while the medicine lasts (`medical.gizmo("treat")`: the fever breaks, one medicine each); the ones
## it could not reach are kept apart; a small lift of mood for the camp. QUARANTINE: `medical.keep_apart` each (off their jobs and posts, lying in the bunks), `closed`
## = {"until", "since", "ids"} for QUARANTINE_H hours (the sign over the bunks, `marks()`), a standing mood line for the ones apart and a lower one for the rest of
## the camp for a day (kept up on each look: `morale.shock` entries topped up to their value), the spread from the ones apart x apart_mult. It ends when none of them is
## sick (News "The fever is over") or at QUARANTINE_H.
##
## THE SPREAD AND THE RISK (the consequences of the player's own dials). Each look a healthy person within `reach` tiles of somebody sick gains exposure (a sick one lying
## apart counts a fraction); at 1.0 they have the fever too ("Marcus caught it"). And the OUTBREAK RISK: a number that grows each look by a base, a little for every person
## over five, the rations dial (half, hungry), overtime with somebody worn out (`policies.weary`) and an open leak (`problems.has_open("leak")`); at 1.0 the most worn out,
## hungriest person has a fever and it starts again. The numbers are in assets/data/dilemmas.json.
##
## Reads the other modules of the round by name and with guards (an older fake has none: no read, no error): policies (`current`, `weary`), problems (`has_open`).
##
## BEYOND THE CONTRACT'S NAMES (all neutral when inactive): `look()` (the slow look, what `update` runs every TICK_S), `can_raise()` (pure: the schedule), `quarantine()`
## ({"ids", "names", "left_h"} for the briefing's concerns and the views), `held(p)`, `debrief_lines(day)` (the evening debrief's lines about the dilemma, plain strings),
## `risk_rate()` (the outbreak risk's growth a look, pure), `tallies()` (for the probe). News lines are kind "sick" (the Fever label): "Marcus caught it", "The fever is over".
extends RefCounted

const DATA_PATH := "res://assets/data/dilemmas.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

const KINDS := ["outbreak"]
const FIRST_DAY := 4
const TTL_MIN := 180.0
const GAP_DAYS := 4
const MEDS_SLACK := 3.0
const QUARANTINE_H := 48.0
const SICK_H := 18.0
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0
## The lines the evening debrief can say about the dilemma are kept for this many entries.
const MAX_NOTES := 8
const NEVER := -999
## Slack for float comparisons.
const EPS := 1.0e-9

var sim
var enabled := true
## Saved. `closed`: the quarantine ({"until": clock_min, "since": clock_min, "ids": [...]}), {} when none; `exposure`: person id -> 0..1; `risk`: the outbreak risk
## accumulator 0..1; `last_day`: the day of the last call; `stats`: what has happened, for the probe; `notes`: [{"day", "text"}], the debrief's lines.
var closed := {}
var exposure := {}
var risk := 0.0
var last_day := NEVER
var stats := {}
var notes: Array = []
var _acc := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	closed = {}
	exposure = {}
	risk = 0.0
	last_day = NEVER
	stats = _new_stats()
	notes = []
	_acc = 0.0


func person_added(_p) -> void:
	pass


static func _new_stats() -> Dictionary:
	return {"raised": 0, "treated": 0, "meds": 0.0, "quarantined": 0, "caught": 0, "fevers": 0, "by_default": 0}


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


# ------------------------------------------------------------------------ data --

static func _data() -> Dictionary:
	if not _cache.has(data_path):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		_cache[data_path] = raw if raw is Dictionary else {}
	return _cache[data_path]


## A number of the data file (the group's key), the fallback when it is not there.
static func _cfg(group: String, key: String, fallback: float) -> float:
	var g = _data().get(group, {})
	if g is Dictionary and _num(g.get(key)):
		return float(g[key])
	return fallback


## What a template of the data file says with its placeholders filled.
static func _say(key: String, words: Dictionary = {}) -> String:
	var w = _data().get("words", {})
	return String(w.get(key, key) if w is Dictionary else key).format(words)


static func _label(key: String) -> String:
	var w = _data().get("labels", {})
	return String(w.get(key, key) if w is Dictionary else key)


# ---------------------------------------------------------------------- people --

func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _is_player(p) -> bool:
	return p.player or String(p.id) == String(sim.player_id)


## Alive and at the base (not out with a party): the ones who can be near each other.
func _alive(p) -> bool:
	return p != null and not (p.dead or p.turned) and p.away == null


func _sick(p) -> bool:
	return sim.storyteller.is_sick(p)


## The first names, "Ana", "Ana and Walt", "Ana, Walt and Dez", "Ana, Walt and 2 more".
static func _names_of(list: Array) -> String:
	var n: Array = []
	for p in list:
		n.append(String(p.first))
	match n.size():
		0:
			return ""
		1:
			return n[0]
		2:
			return "%s and %s" % [n[0], n[1]]
		3:
			return "%s, %s and %s" % [n[0], n[1], n[2]]
	return "%s, %s and %d more" % [n[0], n[1], n.size() - 2]


## "2 days", "1 day", "9 h" for a span of game hours.
static func _span_text(hours: float) -> String:
	if hours > 24.0 + EPS:
		return "%d days" % ceili(hours / 24.0 - EPS)
	if hours > 12.0:
		return "1 day"
	return "%d h" % maxi(1, ceili(hours - EPS))


func _skill(p, skill_name: String) -> int:
	var own = p.get("skills")
	if own is Dictionary and own.has(skill_name):
		return int(own[skill_name])
	return int(p.def.skills.get(skill_name, 0))


## Whether somebody other than `p` could treat a fever now (up, and with Medicine 1 or more: the storyteller's own rule).
func _has_healer_for(p) -> bool:
	for h in sim.people:
		if h != p and not (h.dead or h.downed) and h.away == null and _skill(h, "Medicine") >= 1:
			return true
	return false


## What treating one passing fever costs (the storyteller's SICK_MEDS).
func _treat_cost() -> float:
	return float(sim.storyteller.SICK_MEDS)


## Of these patients (the longest fevers first, the sooner treated the more work is saved) the ones the stores and the healers could treat now.
func _treatable(patients: Array) -> Array:
	var left := float(sim.stock.get("meds", 0.0))
	var cost := _treat_cost()
	var out: Array = []
	for p in _by_fever(patients):
		if left + EPS >= cost and _has_healer_for(p):
			out.append(p)
			left -= cost
	return out


## The patients, the longest fever first, ties by id.
func _by_fever(patients: Array) -> Array:
	var out: Array = patients.duplicate()
	out.sort_custom(func(a, b):
		var ua := float(sim.storyteller.sick.get(String(a.id), 0.0))
		var ub := float(sim.storyteller.sick.get(String(b.id), 0.0))
		if not is_equal_approx(ua, ub):
			return ua > ub
		return String(a.id) < String(b.id))
	return out


# ----------------------------------------------------------------------- policies --
# (the other modules of the round, read by name and with guards)

func _dial(dial: String) -> String:
	var m = sim.policies
	if m == null:
		return ""
	var cur = m.get("current")
	return String(cur.get(dial, "")) if cur is Dictionary else ""


func _weary_of(p) -> float:
	var m = sim.policies
	if m == null:
		return 0.0
	var w = m.get("weary")
	if w is Dictionary and _num(w.get(String(p.id))):
		return float(w[String(p.id)])
	return 0.0


func _leak_open() -> bool:
	var m = sim.problems
	return m != null and m.has_method("has_open") and bool(m.has_open("leak"))


# ------------------------------------------------------------------- the trigger --

## PURE: {"patients": [ids], "need": meds for all, "meds": stock} when the camp has a dilemma now, else {} (and the plain "sick" call goes on as it does). Patients:
## sick with a passing fever, up and here, not the leader (who is never called about), not infected (a bite is the plain call's), not kept apart, not already
## asked about in a plain call, not ordered treated or sent out.
func trigger() -> Dictionary:
	if not active():
		return {}
	var patients := _patients()
	if patients.is_empty():
		return {}
	var need := _treat_cost() * float(patients.size())
	var meds := float(sim.stock.get("meds", 0.0))
	if not (meds < need + MEDS_SLACK - EPS or patients.size() >= 2):
		return {}
	var ids: Array = []
	for p in patients:
		ids.append(String(p.id))
	return {"patients": ids, "need": need, "meds": meds}


func _patients() -> Array:
	var out: Array = []
	for p in sim.people:
		if not _alive(p) or p.downed or _is_player(p) or not _sick(p) or p.infected_at >= 0.0:
			continue
		if sim.medical.is_apart(p) or sim.medical.treat_orders.has(p.id) or sim.medical.sendouts.has(p.id) or _asked(p):
			continue
		out.append(p)
	return out


## Whether a plain "sick" call about this person waits for an answer.
func _asked(p) -> bool:
	for e in sim.radio.open_calls():
		if String(e.kind) == "sick" and String(e.data.get("who", "")) == String(p.id):
			return true
	return false


## The open dilemma call, {} when there is none.
func _open_call() -> Dictionary:
	for e in sim.radio.open_calls():
		if String(e.kind) == "dilemma":
			return e
	return {}


## Whether a call that is not an idea or a piece of trouble waits for an answer (the dilemma raises over those two, never over what the player has to decide now).
func _urgent_call_open() -> bool:
	for e in sim.radio.open_calls():
		var k := String(e.kind)
		if k != "idea" and k != "problem":
			return true
	return false


## PURE: whether the call may be raised now (the schedule; `trigger()` is whether there is one to raise): the day and by day, no alarm and no dead at the wall, nothing urgent
## open, the gap since the last, somebody to ask (the leader is alive).
func can_raise() -> bool:
	if not active() or int(sim.day) < FIRST_DAY or sim.phase != "day":
		return false
	if sim.radio.alarm_on or sim.threat_by_day() or _urgent_call_open():
		return false
	if int(sim.day) - last_day < GAP_DAYS:
		return false
	return sim.radio.leader() != null


## radio._watch_for_fever asks: the plain "sick" call is not raised for a person the dilemma holds (open, or the quarantine's, or `trigger()` claims them now and the
## schedule allows the call).
func claims(p) -> bool:
	if not active() or p == null:
		return false
	var id := String(p.id)
	var open := _open_call()
	if not open.is_empty() and (open.data.get("patients", []) as Array).has(id):
		return true
	if (closed.get("ids", []) as Array).has(id):
		return true
	if not can_raise():
		return false
	return (trigger().get("patients", []) as Array).has(id)


# ---------------------------------------------------------------------- the call --

## Raises the call (radio kind "dilemma") once on a slow look when allowed; its id, 0 when none.
func raise() -> int:
	if not can_raise():
		return 0
	var t := trigger()
	if t.is_empty():
		return 0
	var patients: Array = []
	for id in t.patients:
		patients.append(_person(String(id)))
	var n := patients.size()
	var cost := _treat_cost()
	var meds := float(t.meds)
	var need := float(t.need)
	var k := _treatable(patients).size()
	var all_word := String(patients[0].first) if n == 1 else ("both" if n == 2 else "all %d" % n)
	var words := {"names": _names_of(patients), "all": all_word, "need": _n(need), "meds": _n(meds), "k": k, "n": n, "cost": _n(cost * float(k)), "span": _span_text(QUARANTINE_H)}
	var treat_label := _say("treat", words)
	if k == 0:
		treat_label = _say("treat_none", words)
	elif k < n:
		treat_label = _say("treat_some", words)
	var options: Array = [
		{"id": "treat", "label": treat_label},
		{"id": "quarantine", "label": _say("quarantine", words)},
	]
	var first = patients[0]
	var call_id: int = sim.radio.raise_call("dilemma", _say("title", words), _say("sub_short" if k < n else "sub", words), options, "quarantine", TTL_MIN, {"patients": t.patients.duplicate(), "need": need, "meds": meds}, Vector2(first.x, first.y))
	last_day = int(sim.day)
	_count("raised")
	_note("Fever: %s" % _names_of(patients))
	return call_id


## A number as a short word: "5", "1.5".
static func _n(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")


## radio._carry_out for kind "dilemma": "treat" or "quarantine". The line the News keeps.
func carry_out(e: Dictionary, option_id: String) -> String:
	var patients: Array = []
	var raw = e.get("data", {}).get("patients", []) if e.get("data", {}) is Dictionary else []
	if raw is Array:
		for id in raw:
			var p = _person(String(id))
			if p != null and _alive(p) and _sick(p):
				patients.append(p)
	if patients.is_empty():
		return _say("done_passed")
	if bool(e.get("by_default", false)):
		_count("by_default")
	match option_id:
		"treat":
			return _treat(patients)
		"quarantine":
			return _quarantine(patients)
	return ""


func _treat(patients: Array) -> String:
	var meds_before := float(sim.stock.get("meds", 0.0))
	var treated: Array = []
	var rest: Array = []
	for p in _by_fever(patients):
		if sim.medical.gizmo("treat", {"kind": "person", "ref": p}) and not _sick(p):
			treated.append(p)
		else:
			rest.append(p)
	var spent := maxf(0.0, meds_before - float(sim.stock.get("meds", 0.0)))
	stats["treated"] = int(stats.get("treated", 0)) + treated.size()
	stats["meds"] = float(stats.get("meds", 0.0)) + spent
	if not treated.is_empty():
		sim.morale.shock(null, _cfg("mood", "treated", 1.0), _label("treated"))
	var apart_names := ""
	if not rest.is_empty():
		var kept := _keep_apart(rest)
		apart_names = _names_of(kept)
	var words := {"names": _names_of(treated), "treated": _names_of(treated), "spent": _n(spent), "apart": apart_names, "span": _span_text(QUARANTINE_H)}
	var line := ""
	if treated.is_empty():
		line = _say("done_treated_none", words) if apart_names != "" else _say("done_cannot", {"names": _names_of(rest)})
	elif apart_names == "":
		line = _say("done_treated", words)
	else:
		line = _say("done_treated_some", words)
	_note(line)
	return line


func _quarantine(patients: Array) -> String:
	var kept := _keep_apart(patients)
	if kept.is_empty():
		return _say("done_cannot", {"names": _names_of(patients)})
	var line := _say("done_quarantine", {"names": _names_of(kept), "span": _span_text(QUARANTINE_H)})
	_note(line)
	return line


## Keeps these apart (the beds of the bunks, off their work) and opens the quarantine for them; the ones it could do it for.
func _keep_apart(list: Array) -> Array:
	var kept: Array = []
	var ids: Array = (closed.get("ids", []) as Array).duplicate()
	for p in list:
		if sim.medical.keep_apart(p):
			kept.append(p)
			if not ids.has(String(p.id)):
				ids.append(String(p.id))
	if kept.is_empty():
		return kept
	var now := float(sim.clock_min)
	var since := float(closed.get("since", now)) if not closed.is_empty() else now
	closed = {"until": now + QUARANTINE_H * 60.0, "since": since, "ids": ids}
	stats["quarantined"] = int(stats.get("quarantined", 0)) + kept.size()
	_hold_mood()
	return kept


func _count(key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1


func _note(text: String) -> void:
	notes.append({"day": int(sim.day), "text": text})
	while notes.size() > MAX_NOTES:
		notes.pop_front()


# --------------------------------------------------------------------- the quarantine --

## The quarantine as the views and the briefing read it: {"ids", "names", "left_h"}; {} when there is none.
func quarantine() -> Dictionary:
	if not active() or closed.is_empty():
		return {}
	var people: Array = []
	for id in closed.ids:
		var p = _person(String(id))
		if p != null:
			people.append(p)
	return {"ids": (closed.ids as Array).duplicate(), "names": _names_of(people), "left_h": maxf(0.0, (float(closed.until) - float(sim.clock_min)) / 60.0)}


## Whether this person is held by the quarantine.
func held(p) -> bool:
	return active() and p != null and (closed.get("ids", []) as Array).has(String(p.id))


## For the views: [{"kind": "quarantine", "at": Vector2, "label": "Quarantine: 2 days", "ids", "left_h"}]; [] otherwise. The sign hangs where the first of them lies.
func marks() -> Array:
	var q := quarantine()
	if q.is_empty():
		return []
	var at := Vector2.ZERO
	var first = _person(String(q.ids[0]))
	if first != null:
		at = sim.medical.apart_spot(first) if sim.medical.is_apart(first) else Vector2(first.x, first.y)
	return [{"kind": "quarantine", "at": at, "label": _say("mark", {"span": _span_text(float(q.left_h))}), "ids": q.ids, "left_h": q.left_h}]


## The lines the evening debrief can say about the dilemma for this day (the default: today): what was decided, who caught it, how it ended, and the quarantine still on.
func debrief_lines(day: int = -1) -> Array:
	var out: Array = []
	if not active():
		return out
	var d := int(sim.day) if day < 0 else day
	for n in notes:
		if int(n.day) == d:
			out.append(String(n.text))
	var q := quarantine()
	if not q.is_empty() and d == int(sim.day):
		out.append(_say("debrief_quarantine", {"names": q.names, "span": _span_text(float(q.left_h))}))
	return out


## What has happened, for the probe: {"raised", "treated", "meds", "quarantined", "caught", "fevers", "by_default"}.
func tallies() -> Dictionary:
	return stats.duplicate()


## initiative.voice_opinion delegates for kind "dilemma": {"p": the person, "option": an option id of the call, "say": "treat them."} as `initiative._on_sick` makes it:
## the medic (else the voice) says treat when the stores cover all the patients, else quarantine. {} without a medic or a voice (or when the fever is over).
func opinion(e: Dictionary) -> Dictionary:
	if not active():
		return {}
	var data = e.get("data", {})
	if not (data is Dictionary):
		return {}
	var patients: Array = []
	var raw = data.get("patients", [])
	if raw is Array:
		for id in raw:
			var p = _person(String(id))
			if p != null and _alive(p) and _sick(p):
				patients.append(p)
	if patients.is_empty():
		return {}
	if sim.initiative == null or not sim.initiative.has_method("opinion_giver"):
		return {}
	var giver = sim.initiative.opinion_giver("medic")
	if giver != null and patients.has(giver):
		giver = sim.initiative.opinion_giver("medic", giver)
		if giver != null and patients.has(giver):
			giver = null
	if giver == null:
		return {}
	if _treatable(patients).size() == patients.size():
		return {"p": giver, "option": "treat", "say": _say("say_treat")}
	return {"p": giver, "option": "quarantine", "say": _say("say_quarantine")}


# ------------------------------------------------------------------------ the look --

func update(dt: float) -> void:
	if not active():
		return
	_acc += dt
	if _acc < TICK_S:
		return
	_acc -= TICK_S
	look()


## One slow look: the quarantine is tended, the fever spreads and the outbreak risk grows (only while the storyteller's fevers exist), the mood of the camp is held, a
## call that has nothing left to decide is closed, and the call is raised when there is one. The id of the call, 0 when none.
func look() -> int:
	if not active():
		return 0
	_tend_quarantine()
	if sim.storyteller.enabled:
		_spread()
		_grow_risk()
	_hold_mood()
	_close_stale_call()
	return raise()


## The quarantine ends when none of them is sick (they are cured, over it, or gone), or when its time is up.
func _tend_quarantine() -> void:
	if closed.is_empty():
		return
	var keep: Array = []
	for id in closed.ids:
		var p = _person(String(id))
		if p != null and _alive(p) and _sick(p):
			keep.append(String(id))
	closed["ids"] = keep
	if keep.is_empty():
		_end(_say("over"), _say("over_sub"))
	elif float(sim.clock_min) >= float(closed.until) - EPS:
		var rest: Array = []
		for id in keep:
			rest.append(_person(String(id)))
		var names := _names_of(rest)
		_end(_say("lifted"), _say("lifted_sub", {"names": names}))


func _end(text: String, sub: String) -> void:
	closed = {}
	sim.radio.log_news("sick", text, sub)
	sim.alert("dilemma-over", "info", text, sub, null, 12.0)
	_note(text)


## The call that nobody is sick for any more (they were treated by hand, or it passed) is answered with its default: nothing is decided, the card goes.
func _close_stale_call() -> void:
	var e := _open_call()
	if e.is_empty():
		return
	for id in e.data.get("patients", []):
		var p = _person(String(id))
		if p != null and _alive(p) and _sick(p):
			return
	sim.radio.answer(int(e.id), String(e.default))


# ------------------------------------------------------------------ the mood of the camp --

## The quarantine's standing lines, kept up on each look: the ones apart carry "Kept apart" at its value while they lie there, everyone else "Fever in the camp" for the
## first `camp_hours` hours. A shock fades by itself (the morale module's own drift); each look tops its entry back up to its value, so the line stands as long as
## the quarantine does and fades when it is over.
func _hold_mood() -> void:
	if closed.is_empty():
		return
	var ids: Array = closed.ids
	var camp_on := (float(sim.clock_min) - float(closed.get("since", closed.until))) / 60.0 < _cfg("mood", "camp_hours", 24.0) - EPS
	for p in sim.people:
		if not _alive(p):
			continue
		if ids.has(String(p.id)):
			_top_up(p, _label("apart"), _cfg("mood", "apart", -4.0))
		elif camp_on:
			_top_up(p, _label("camp"), _cfg("mood", "camp", -2.0))


func _top_up(p, label: String, want: float) -> void:
	var cur := 0.0
	for s in sim.morale.shocks.get(p.id, []):
		if String(s.label) == label:
			cur = float(s.value)
	if want - cur < -0.05:
		sim.morale.shock(p, want - cur, label)


# ------------------------------------------------------------- the spread and the risk --

## Each look: a healthy person near somebody who is sick gains exposure (the ones lying apart count a fraction), the others lose a little; at the catch point they have it.
func _spread() -> void:
	var reach := _cfg("spread", "reach", 3.0)
	var per := _cfg("spread", "per_look", 0.35)
	var apart_mult := _cfg("spread", "apart_mult", 0.15)
	var cap := _cfg("spread", "cap_per_look", 0.7)
	var decay := _cfg("spread", "decay_per_look", 0.1)
	var catch_at := _cfg("spread", "catch_at", 1.0)
	var sources: Array = []
	for p in sim.people:
		if _alive(p) and _sick(p):
			sources.append(p)
	for q in sim.people:
		var id := String(q.id)
		if not _alive(q) or _sick(q):
			exposure.erase(id)
			continue
		var gain := 0.0
		for s in sources:
			if Vector2(q.x - s.x, q.y - s.y).length() <= reach:
				gain += per * (apart_mult if sim.medical.is_apart(s) else 1.0)
		var v := float(exposure.get(id, 0.0))
		v = v + minf(gain, cap) if gain > 0.0 else v - decay
		if v >= catch_at - EPS:
			exposure.erase(id)
			_catch(q)
		elif v > 0.0005:
			exposure[id] = v
		else:
			exposure.erase(id)


func _catch(q) -> void:
	sim.storyteller.sick[String(q.id)] = snappedf(float(sim.clock_min) + SICK_H * 60.0, 1.0)
	_count("caught")
	var line := _say("caught", {"name": String(q.first)})
	sim.radio.log_news("sick", line, _say("caught_sub"), {"at": Vector2(q.x, q.y)})
	sim.alert("dilemma-caught-%s" % q.id, "warn", line, _say("caught_sub"), Vector2(q.x, q.y), 8.0)
	_note(line)


## How much the outbreak risk grows each look, from the state of the camp and the player's own dials; 0.0 inactive. Pure.
func risk_rate() -> float:
	if not active():
		return 0.0
	var n := 0
	for p in sim.people:
		if not (p.dead or p.turned):
			n += 1
	var rate := _cfg("risk", "base", 0.002) + _cfg("risk", "per_extra_person", 0.0005) * float(maxi(0, n - int(_cfg("risk", "free_people", 5.0))))
	for c in _causes():
		rate += _cause_rate(c)
	return rate


## What is wearing the camp down right now ("half" or "hungry" rations, "overtime" with somebody worn out, "leak"), in that order.
func _causes() -> Array:
	var out: Array = []
	var rations := _dial("rations")
	if rations == "half" or rations == "hungry":
		out.append(rations)
	if _dial("hours") == "overtime":
		var worn := _cfg("risk", "worn_at", 60.0)
		for p in sim.people:
			if _alive(p) and _weary_of(p) >= worn - EPS:
				out.append("overtime")
				break
	if _leak_open():
		out.append("leak")
	return out


func _cause_rate(cause: String) -> float:
	var risk_cfg = _data().get("risk", {})
	if not (risk_cfg is Dictionary):
		return 0.0
	if cause == "half" or cause == "hungry":
		var r = risk_cfg.get("rations", {})
		return float(r.get(cause, 0.0)) if r is Dictionary and _num(r.get(cause)) else 0.0
	return _cfg("risk", "overtime_worn" if cause == "overtime" else cause, 0.0)


func _grow_risk() -> void:
	risk = minf(1.0, risk + risk_rate())
	if risk < 1.0 - EPS:
		return
	var who = _outbreak_victim()
	if who == null:
		return    # (everyone who could has it already: the risk waits)
	risk = 0.0
	sim.storyteller.sick[String(who.id)] = snappedf(float(sim.clock_min) + _cfg("risk", "fever_h", 24.0) * 60.0, 1.0)
	_count("fevers")
	var causes := _causes()
	var names: Array = []
	var words = _data().get("causes", {})
	for c in causes:
		names.append(String(words.get(c, c)) if words is Dictionary else c)
	if names.is_empty():
		names.append(String(words.get("crowd", "a crowded camp")) if words is Dictionary else "a crowded camp")
	var line := _say("fever", {"name": String(who.first)})
	var sub := _say("fever_sub", {"causes": ", ".join(names)})
	sim.radio.log_news("sick", line, sub, {"at": Vector2(who.x, who.y)})
	sim.alert("dilemma-fever-%s" % who.id, "warn", line, sub, Vector2(who.x, who.y), 8.0)
	_note(line)


## The one who falls ill when the risk is full: the most worn out, then the hungriest, then the smaller id; not the leader, nobody who is sick already.
func _outbreak_victim():
	var best = null
	for p in sim.people:
		if not _alive(p) or _is_player(p) or _sick(p):
			continue
		if best == null:
			best = p
			continue
		var wa := _weary_of(p)
		var wb := _weary_of(best)
		if not is_equal_approx(wa, wb):
			if wa > wb:
				best = p
			continue
		if not is_equal_approx(float(p.hunger_h), float(best.hunger_h)):
			if float(p.hunger_h) > float(best.hunger_h):
				best = p
			continue
		if String(p.id) < String(best.id):
			best = p
	return best


# ---------------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {
		"closed": closed.duplicate(true), "exposure": exposure.duplicate(), "risk": risk, "acc": _acc, "last_day": last_day,
		"stats": stats.duplicate(), "notes": notes.duplicate(true),
	}


## Restores what `save` wrote; {} (a save from before) is a fresh module. What is not sound (a number that is not finite, a person who is not there, a note that is not
## text) is left out; the numbers are kept between their bounds.
func load_state(d: Dictionary) -> void:
	start()
	risk = clampf(float(d.get("risk", 0.0)), 0.0, 1.0) if _num(d.get("risk")) else 0.0
	_acc = clampf(float(d.get("acc", 0.0)), 0.0, TICK_S) if _num(d.get("acc")) else 0.0
	last_day = clampi(int(d.last_day), -9999, 100000) if _num(d.get("last_day")) else NEVER
	var ex = d.get("exposure", {})
	if ex is Dictionary:
		for k in ex:
			if _num(ex[k]) and _person(str(k)) != null:
				exposure[str(k)] = clampf(float(ex[k]), 0.0, 1.0)
	var c = d.get("closed", {})
	if c is Dictionary and _num(c.get("until")) and c.get("ids") is Array:
		var ids: Array = []
		for id in c.ids:
			if _person(str(id)) != null and not ids.has(str(id)):
				ids.append(str(id))
		if not ids.is_empty():
			var until := clampf(float(c.until), 0.0, 1.0e9)
			var since := clampf(float(c.since), 0.0, until) if _num(c.get("since")) else maxf(0.0, until - QUARANTINE_H * 60.0)
			closed = {"until": until, "since": since, "ids": ids}
	var st = d.get("stats", {})
	if st is Dictionary:
		for k in stats:
			if _num(st.get(k)):
				stats[k] = maxf(0.0, float(st[k])) if k == "meds" else maxi(0, int(st[k]))
	var nt = d.get("notes", [])
	if nt is Array:
		for n in nt:
			if n is Dictionary and _num(n.get("day")) and typeof(n.get("text")) == TYPE_STRING:
				notes.append({"day": clampi(int(n.day), 0, 100000), "text": String(n.text).left(200)})
		while notes.size() > MAX_NOTES:
			notes.pop_front()


static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
