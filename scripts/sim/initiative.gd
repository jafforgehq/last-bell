## Initiative (round 20, slice 4): the community has ideas. By day, a person who has something to say about the camp's work
## comes on the radio with it, in their own words and with its price ("I could fix the east wall properly. About 20 scrap."), and
## the player says yes, later or no. An idea is an ordinary radio call (`radio.raise_call`, kind "idea"); the answer comes back
## to `carry_out` through the radio's `_carry_out`. Nothing is random and nothing is a command: what is proposed is a pure function
## of the state (ties by id), the same state brings the same ideas, and no die of the run's is ever thrown. Avatar mode in the
## settlement game only (`active()`: an avatar, a small start, not Orientation Day); otherwise every call here answers the neutral
## value, `update` returns at once and the game plays as it always did.
##
## THE TABLE. Thirteen kinds, each with its own trigger (a state read), its proposer (a specialist of the kind first, then whoever
## fits), a line with the price, and a yes that does something real through an action the game has already: `fix_wall` (an order
## to repair), `build` (an order on the Build screen), `bench_target` and `wall_line` (a station's setting), `desk` and `garden`
## (a job), `errand` (a party sent), `swap_posts` and `post_beside` (two night posts exchanged), `supper` (a shared meal),
## `quarrel` (two people kept apart), `lesson` (an hour of two people for a point of a skill), `farewell` (a few words for the
## dead). The words, the scores and the thresholds are in assets/data/ideas.json; the schedule and the costs are the constants
## below. `candidates()` is pure; `propose_now()` raises the best one; `look()` does so when the schedule allows it (the slow
## look: every TICK_S seconds of rules time, 30 game minutes, `update`).
##
## THE SCHEDULE. From day 3, by day (08:00 to 17:30, never in the radio hour), never under the alarm or with the dead at the wall;
## at most two waiting (`MAX_OPEN`), four game hours between two proposals, three days between two of a kind, two days (one for
## the voice) between two from one person, a person whose trust in the leader is under 25 brings nothing, and the whole camp is
## silent while the community's trust is under 35 (the News says so, once). A call that is not answered in six game hours takes
## "later" (nothing is paid): twice in a row on one kind and that kind is put away for a few days.
##
## THE ANSWERS. Yes: the proposer's trust and mood go up and the idea is TAKEN (it counts for their standing in
## `relations.standing`). A yes is checked again when it is given with the very predicate of the trigger: "Not now: it needs 20
## scrap" and it counts as a later. No: a little trust and mood lost; the third no in four days and the person stops bringing ideas
## for three days (the News says it), at a further cost. Later: nothing.
##
## THE VOICE. `voice_opinion(call)` is what the specialist of the matter (the marksman on an attack, the medic on a fever), else
## the one people turn to, would say about any open call: shown under it, never the default.
##
## It reads the other two modules of the round by name and through `has_method` (relations: voice, community trust, friends,
## rivals, affinity, add, the last loss; specialists: holder, title, trips); without them it still runs, with no voice, no
## titles and no friends.
extends RefCounted

const DATA_PATH := "res://assets/data/ideas.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

## The kinds, in the order that breaks a tie between two ideas of the same score.
const KINDS := ["fix_wall", "build", "bench_target", "wall_line", "desk", "garden", "errand", "swap_posts", "post_beside", "supper", "quarrel", "lesson", "farewell"]

## The slow look: every this many seconds of rules time (30 game minutes).
const TICK_S := 10.0
const FIRST_DAY := 3
const HOURS_FROM := 8.0
const HOURS_TO := 17.5
## The radio hour (the noon call): nothing is proposed in it.
const RADIO_FROM_H := 11.5
const RADIO_TO_H := 12.5
const MAX_OPEN := 2
const GAP_ALL_MIN := 240.0
const GAP_KIND_DAYS := 3
const GAP_PERSON_DAYS := 2
const GAP_VOICE_DAYS := 1
## How long a call waits (game minutes) before it takes "later".
const TTL_MIN := 360.0
## Laters in a row on one kind that put it away, and for how many days.
const MAX_LATER := 2
const SHELVE_DAYS := 6
## A person whose trust in the leader is under this brings nothing; and the whole yard is silent under this community trust.
const QUIET_TRUST := 25.0
const COMMUNITY_MIN := 35.0
const YES_TRUST := 1.5
const YES_MORALE := 3.0
const NO_TRUST := -1.0
const NO_MORALE := -2.0
## Refusals in a window of days that silence a proposer, for how long, and what the last of them costs.
const NO_STREAK := 3
const NO_WINDOW_DAYS := 4
const QUIET_DAYS := 3
const QUIET_TRUST_COST := -2.0
const QUIET_MORALE := -3.0
## What a score is made of besides the kind's base: up to this much for the skill, this for a specialist of the kind, this for the
## voice on a communal kind, and the trust over fifty divided by this.
const FIT_MAX := 3.0
const SPECIALIST_BONUS := 1.5
const VOICE_BONUS := 1.0
const TRUST_SCALE := 25.0
const NEVER := -1.0e9
## The words of a person's side of the table ("the east wall").
const SIDES := {"N": "north", "S": "south", "E": "east", "W": "west"}

var sim
var enabled := true
## Person id -> {"asked", "yes", "no", "later", "quiet_until" (a day), "last_day", "no_days" (the days of the last refusals)}.
var records := {}
## Kind -> the day of its last proposal; kind -> the day it may be proposed again (put away); kind -> laters in a row.
var last_kind := {}
var shelved := {}
var streaks := {}
## The clock (game minutes) of the last proposal of any kind.
var last_all := NEVER
## The lessons being given: [{"teacher", "student", "skill", "kind", "per", "until" (game minutes), "spot_t": [x, y], "spot_s": [x, y]}].
var doing: Array = []
## Whether the News has said that nobody brings ideas any more (until the community's trust is back).
var hushed := false
## What has happened, for the probe: raised, yes, no, later, spent {scrap, food} (the price of what was taken up), by kind.
var counts := {}
var _acc := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	_reset()


## (Nothing is kept for a person who has not been asked: the records are made at the first idea.)
func person_added(_p) -> void:
	pass


func _reset() -> void:
	records.clear()
	last_kind.clear()
	shelved.clear()
	streaks.clear()
	last_all = NEVER
	doing.clear()
	hushed = false
	counts = _new_counts()
	_acc = 0.0


static func _new_counts() -> Dictionary:
	return {"raised": 0, "yes": 0, "no": 0, "later": 0, "scrap": 0.0, "food": 0.0, "by_kind": {}}


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


# ------------------------------------------------------------------------ data --

static func _data() -> Dictionary:
	if not _cache.has(data_path):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		_cache[data_path] = raw if raw is Dictionary else {}
	return _cache[data_path]


## A kind's entry in the data file ({} when it has none: that kind is never proposed).
static func _kd(kind: String) -> Dictionary:
	var kinds = _data().get("kinds", {})
	var d = kinds.get(kind, {}) if kinds is Dictionary else {}
	return d if d is Dictionary else {}


## What one of a kind's templates says with its placeholders filled ("" when it has none).
static func _say(kind: String, key: String, words: Dictionary) -> String:
	return String(_kd(kind).get(key, "")).format(words)


# ---------------------------------------------------------------------- people --

func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _people(ids) -> Array:
	var out: Array = []
	if ids is Array:
		for id in ids:
			var p = _person(String(id))
			if p != null:
				out.append(p)
	return out


func _is_player(p) -> bool:
	return p.player or String(p.id) == String(sim.player_id)


## Alive, up and at the base.
func _here(p) -> bool:
	return p != null and not (p.dead or p.turned or p.downed) and p.away == null


## Someone who could be given a piece of work now: here, not the player, not in a breakdown, not on a stance, not on the way out
## and not at the bed of a patient or on their way to one.
func _free_to_work(p) -> bool:
	if not _here(p) or _is_player(p) or sim.morale.breakdown(p) or String(p.stance) != "":
		return false
	if sim.medical.sendouts.has(p.id) or sim.medical.goal_for(p) != null or sim.scavenge.goal_for(p) != null:
		return false
	return true


func _ids(list: Array) -> Array:
	var out: Array = []
	for p in list:
		out.append(String(p.id))
	return out


## The best of a list at a skill (higher first, then the smaller id), or null.
func _best(list: Array, skill: String):
	var best = null
	for p in list:
		if best == null:
			best = p
			continue
		var a: int = int(p.skills.get(skill, 0)) if skill != "" else 0
		var b: int = int(best.skills.get(skill, 0)) if skill != "" else 0
		if a > b or (a == b and String(p.id) < String(best.id)):
			best = p
	return best


# ---------------------------------------------------- the other modules (guarded) --

func _voice():
	var m = sim.relations
	return m.voice() if m != null and m.has_method("voice") else null


func _holder(title_id: String):
	var m = sim.specialists
	return m.holder(title_id) if m != null and m.has_method("holder") else null


## "the medic" for a title holder, "" for anyone else.
func _title_name(p) -> String:
	var m = sim.specialists
	if m == null or p == null:
		return ""
	if m.has_method("opinion_title"):
		return String(m.opinion_title(p))
	if m.has_method("title_of"):
		return String(m.title_of(p).get("name", ""))
	return ""


func _trips_of(p) -> int:
	var m = sim.specialists
	if m != null and m.has_method("record_of"):
		return int(m.record_of(p).get("trips", 0))
	return 0


## The community's trust in the leader: the relations module's, else the mean trust of the living who are not the player.
func _community() -> float:
	var m = sim.relations
	if m != null and m.has_method("community_trust"):
		return float(m.community_trust())
	var sum := 0.0
	var n := 0
	for p in sim.people:
		if not (p.dead or p.turned) and not _is_player(p):
			sum += float(p.trust)
			n += 1
	return sum / float(n) if n > 0 else 55.0


func _friends(p) -> Array:
	var m = sim.relations
	return m.friends_of(p) if m != null and m.has_method("friends_of") else []


func _rivals(p) -> Array:
	var m = sim.relations
	return m.rivals_of(p) if m != null and m.has_method("rivals_of") else []


func _affinity(a, b) -> float:
	var m = sim.relations
	return float(m.affinity(a, b)) if m != null and m.has_method("affinity") else 0.0


func _add_rel(a, b, delta: float, why: String) -> void:
	var m = sim.relations
	if m != null and m.has_method("add"):
		m.add(a, b, delta, why)


func _recent_loss() -> Dictionary:
	var m = sim.relations
	if m != null and m.has_method("recent_loss"):
		var d = m.recent_loss()
		return d if d is Dictionary else {}
	return {}


# --------------------------------------------------------------------- records --

func _rec(p) -> Dictionary:
	var id := String(p.id)
	if not records.has(id):
		records[id] = _new_record()
	return records[id]


static func _new_record() -> Dictionary:
	return {"asked": 0, "yes": 0, "no": 0, "later": 0, "quiet_until": 0, "last_day": -999, "no_days": []}


## What has come of this person's ideas: {"asked", "yes", "no", "later", "quiet_until" (a day), "last_day"}.
func record_of(p) -> Dictionary:
	var out := _new_record()
	if p != null:
		var r: Dictionary = records.get(String(p.id), {})
		for k in ["asked", "yes", "no", "later", "quiet_until", "last_day"]:
			out[k] = int(r.get(k, out[k]))
	out.erase("no_days")
	return out


## How many of their ideas have been taken up (the relations module's `standing` counts them).
func taken_of(p) -> int:
	return int(records.get(String(p.id), {}).get("yes", 0)) if p != null else 0


## The tallies for the probe: {"raised", "yes", "no", "later", "scrap", "food", "by_kind": {kind: {"raised", "yes", "no", "later"}}}.
func stats() -> Dictionary:
	return counts.duplicate(true)


func _count(kind: String, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1
	var by: Dictionary = counts.by_kind
	var row: Dictionary = by.get(kind, {"raised": 0, "yes": 0, "no": 0, "later": 0})
	row[key] = int(row.get(key, 0)) + 1
	by[kind] = row


## The lessons being given (copies).
func lessons() -> Array:
	return doing.duplicate(true)


# ------------------------------------------------------------------- the schedule --

## Whether an idea may be raised now: the day and the hour, no alarm and no dead at the wall, room on the table, the gap since the last,
## the community's trust, somebody to ask (the leader is alive).
func allowed_now() -> bool:
	if not active() or int(sim.day) < FIRST_DAY or sim.phase != "day":
		return false
	var h: float = sim.hour
	if h < HOURS_FROM or h > HOURS_TO or (h >= RADIO_FROM_H and h <= RADIO_TO_H):
		return false
	if sim.radio.alarm_on or sim.threat_by_day():
		return false
	if _open_ideas().size() >= MAX_OPEN or float(sim.clock_min) - last_all < GAP_ALL_MIN:
		return false
	if _community() < COMMUNITY_MIN:
		return false
	return sim.radio.leader() != null


func _open_ideas() -> Array:
	var out: Array = []
	for e in sim.radio.open_calls():
		if String(e.kind) == "idea":
			out.append(e)
	return out


## One slow look: raises the best idea when the schedule allows it. The id of the call, 0 when none (and the News says once when the
## camp has gone silent).
func look() -> int:
	if not active():
		return 0
	var silent: bool = int(sim.day) >= FIRST_DAY and _community() < COMMUNITY_MIN
	if silent != hushed:
		hushed = silent
		if silent:
			sim.radio.log_news("idea", "Nobody brings you ideas any more", "People do not trust the leader enough to speak")
	if not allowed_now():
		return 0
	return propose_now()


func update(dt: float) -> void:
	if not active():
		return
	if not doing.is_empty():
		_tend_lessons()
	_acc += dt
	if _acc < TICK_S:
		return
	_acc -= TICK_S
	look()


# ----------------------------------------------------------------- the candidates --

## Every idea that could be raised now, best first (a pure look: nothing is changed): [{"kind", "who" (id), "others" (ids), "score",
## "text" (with the name: "Dez: I could fix the east wall properly. About 9 scrap."), "line" (what is said, for the bubble), "sub",
## "yes_label", "cost" ({"scrap", "food"}), "args" (what the kind keeps for its yes)}]. Not what the schedule holds back (`allowed_now`):
## the hours, the caps and the gap between two proposals are `look`'s. A kind has its own gap and a proposer theirs, and an idea
## of a kind that waits for an answer is not asked again.
func candidates() -> Array:
	var out: Array = []
	if not active() or _data().is_empty():
		return out
	var ctx := _context()
	for kind in KINDS:
		if _kd(kind).is_empty() or _held_back(kind) or not has_method("_find_" + kind):
			continue
		var c: Dictionary = call("_find_" + kind, ctx)
		if c.is_empty():
			continue
		out.append(_finish(kind, c, ctx))
	out.sort_custom(func(a, b):
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) > float(b.score)
		var ia: int = KINDS.find(String(a.kind))
		var ib: int = KINDS.find(String(b.kind))
		if ia != ib:
			return ia < ib
		return String(a.who) < String(b.who))
	return out


## What the finders share: the people at the base, who may bring an idea, the voice.
func _context() -> Dictionary:
	var voice = _voice()
	var here: Array = []
	var proposers: Array = []
	for p in sim.people:
		if _is_player(p) or not _here(p):
			continue
		here.append(p)
		if _may_propose(p, voice):
			proposers.append(p)
	return {"here": here, "proposers": proposers, "voice": voice}


## Whether this person could bring an idea now: up, at the base, not in a breakdown or on a stance or out on a trip, with trust enough
## in the leader, not quiet and not asked within their gap.
func _may_propose(p, voice) -> bool:
	if not _free_to_work(p) or p.resting_bed != null or float(p.trust) < QUIET_TRUST:
		return false
	var rec: Dictionary = records.get(String(p.id), {})
	if int(sim.day) < int(rec.get("quiet_until", 0)):
		return false
	var gap := GAP_VOICE_DAYS if p == voice else GAP_PERSON_DAYS
	return int(sim.day) - int(rec.get("last_day", -999)) >= gap


## A kind that has been asked lately, put away, or is waiting for its answer.
func _held_back(kind: String) -> bool:
	if int(sim.day) - int(last_kind.get(kind, -999)) < GAP_KIND_DAYS or int(sim.day) < int(shelved.get(kind, 0)):
		return true
	for e in _open_ideas():
		if String(e.data.get("idea", "")) == kind:
			return true
	return false


## The candidate as the contract has it, from what a finder gave: {"p", "others" (people), "args", "cost", "line", "sub", "yes"}
## and optionally "skill" and "title" (what makes a proposer fit and a specialist of the kind) and "ttl" (game minutes).
func _finish(kind: String, c: Dictionary, ctx: Dictionary) -> Dictionary:
	var p = c.p
	var kd := _kd(kind)
	var skill := String(c.get("skill", kd.get("skill", "")))
	var title := String(c.get("title", kd.get("title", "")))
	var score := float(kd.get("base", 0.0))
	if skill != "":
		score += clampf(0.3 * float(p.skills.get(skill, 0)), 0.0, FIT_MAX)
	if title != "" and _holder(title) == p:
		score += SPECIALIST_BONUS
	if bool(kd.get("communal", false)) and ctx.voice == p:
		score += VOICE_BONUS
	score += (float(p.trust) - 50.0) / TRUST_SCALE
	var out := {
		"kind": kind, "who": String(p.id), "others": _ids(c.get("others", [])), "score": snappedf(score, 0.001),
		"text": "%s: %s" % [String(p.first), String(c.line)], "line": String(c.line), "sub": String(c.get("sub", "")),
		"yes_label": String(c.yes), "cost": c.get("cost", {}).duplicate(), "args": c.get("args", {}).duplicate(true),
	}
	if c.has("ttl"):
		out["ttl"] = float(c.ttl)
	return out


## Raises the best idea at once, whatever the schedule says (a look is `look`'s): the call's id, 0 when none.
func propose_now() -> int:
	var list := candidates()
	return _raise(list[0]) if not list.is_empty() else 0


func _raise(c: Dictionary) -> int:
	var p = _person(String(c.who))
	if p == null:
		return 0
	var ttl := minf(TTL_MIN, float(c.get("ttl", TTL_MIN)))
	var data := {"idea": String(c.kind), "who": String(c.who), "others": c.others.duplicate(), "args": c.args.duplicate(true), "cost": c.cost.duplicate(), "line": String(c.line)}
	var options: Array = [{"id": "yes", "label": String(c.yes_label)}, {"id": "later", "label": "Later"}, {"id": "no", "label": "No"}]
	var id: int = sim.radio.raise_call("idea", String(c.text), String(c.sub), options, "later", ttl, data, Vector2(p.x, p.y))
	var rec := _rec(p)
	rec["asked"] = int(rec.asked) + 1
	rec["last_day"] = int(sim.day)
	last_kind[String(c.kind)] = int(sim.day)
	last_all = float(sim.clock_min)
	_count(String(c.kind), "raised")
	sim.events.append({"type": "bark", "who": String(c.who), "text": String(c.line), "context": "idea"})
	return id


# --------------------------------------------------------------------- answering --

## What the radio does with an answer to an idea ("yes", "later", "no"; the time running out is "later"): the line that says what came
## of it. A module that is not active answers nothing.
func carry_out(e: Dictionary, option_id: String) -> String:
	if not active():
		return ""
	var data = e.get("data", {})
	if not (data is Dictionary):
		return ""
	var kind := String(data.get("idea", ""))
	var who = _person(String(data.get("who", "")))
	if who == null or not KINDS.has(kind):
		return ""
	match option_id:
		"yes":
			return _yes(kind, who, data)
		"no":
			return _no(kind, who, data)
	_later(kind)
	_rec(who)["later"] = int(_rec(who).later) + 1
	return ""


func _yes(kind: String, who, data: Dictionary) -> String:
	var others := _people(data.get("others", []))
	var args: Dictionary = data.get("args", {}) if data.get("args", {}) is Dictionary else {}
	var why: String = call("_why_" + kind, who, others, args) if has_method("_why_" + kind) else "that is not possible"
	if why != "":
		_later(kind)
		_rec(who)["later"] = int(_rec(who).later) + 1
		return "Not now: %s" % why
	var result: String = call("_apply_" + kind, who, others, args)
	if result.begins_with("Not now: "):
		# (it could not be done after all: the same as a yes that is checked again)
		_later(kind)
		_rec(who)["later"] = int(_rec(who).later) + 1
		return result
	var rec := _rec(who)
	rec["yes"] = int(rec.yes) + 1
	streaks.erase(kind)
	_count(kind, "yes")
	var cost: Dictionary = data.get("cost", {}) if data.get("cost", {}) is Dictionary else {}
	for k in ["scrap", "food"]:
		if _num(cost.get(k)):
			counts[k] = float(counts.get(k, 0.0)) + float(cost[k])
	sim.radio.add_trust(who, YES_TRUST, "You took up their idea")
	sim.morale.shock(who, YES_MORALE, "Their idea was taken up")
	return result


func _no(kind: String, who, data: Dictionary) -> String:
	var rec := _rec(who)
	rec["no"] = int(rec.no) + 1
	streaks.erase(kind)
	_count(kind, "no")
	sim.radio.add_trust(who, NO_TRUST, "You turned down their idea")
	sim.morale.shock(who, NO_MORALE, "Their idea was turned down")
	var others := _people(data.get("others", []))
	var args: Dictionary = data.get("args", {}) if data.get("args", {}) is Dictionary else {}
	if has_method("_refused_" + kind):
		call("_refused_" + kind, who, others, args)
	var days: Array = []
	for d in rec.no_days:
		if int(sim.day) - int(d) < NO_WINDOW_DAYS:
			days.append(int(d))
	days.append(int(sim.day))
	rec["no_days"] = days
	if days.size() >= NO_STREAK:
		rec["quiet_until"] = int(sim.day) + QUIET_DAYS
		rec["no_days"] = []
		sim.radio.add_trust(who, QUIET_TRUST_COST, "Turned down three times: they stopped bringing ideas")
		sim.morale.shock(who, QUIET_MORALE, "Turned down three times")
		sim.radio.log_news("idea", "%s has stopped bringing ideas" % String(who.first), "Turned down three times in %d days" % NO_WINDOW_DAYS)
	return ""


## A later (or a yes that could not be done): a run of them on one kind puts it away.
func _later(kind: String) -> void:
	_count(kind, "later")
	streaks[kind] = int(streaks.get(kind, 0)) + 1
	if int(streaks[kind]) >= MAX_LATER:
		streaks.erase(kind)
		shelved[kind] = int(sim.day) + SHELVE_DAYS


# ----------------------------------------------------------------- fix_wall --

## Why this section of the wall is not what the idea is about now ("" when it is): not a door, under the idea's line, nobody on it,
## and out of the Builders' own line (they would mend it themselves, under it) or with nobody on the Builders.
func _wall_not(s, prm: Dictionary) -> String:
	if String(s.kind) == sim.DOOR_KIND:
		return "a door is not mended this way"
	for q in sim.people:
		if q.repair != null and int(q.repair.id) == int(s.id) and not (q.dead or q.turned):
			return "somebody is on it already"
	var f: float = float(s.hp) / float(s.max_hp)
	if f >= float(prm.under):
		return "it does not need it now"
	var crew := 0
	for q in sim.jobs.crew_of("builders"):
		if _here(q):
			crew += 1
	if crew > 0 and f < float(sim.tactics.repair_below()):
		return "the crew will see to it"
	return ""


## The section the idea is about: the most worn of those `_wall_not` lets through (then the lower id), or null.
func _wall_to_fix(prm: Dictionary):
	var best = null
	var best_f := 2.0
	for s in sim.segments:
		if _wall_not(s, prm) != "":
			continue
		var f: float = float(s.hp) / float(s.max_hp)
		if best == null or f < best_f - 1.0e-9:
			best = s
			best_f = f
	return best


func _segment(id: int):
	for s in sim.segments:
		if int(s.id) == id:
			return s
	return null


func _wall_words(s) -> Dictionary:
	var short := String(s.name).to_lower()
	return {"short": short, "wall": "%s on the %s wall" % [short, String(SIDES.get(String(s.side), ""))], "pct": roundi(float(s.hp) / float(s.max_hp) * 100.0)}


func _scrap_for(s, prm: Dictionary) -> int:
	return ceili((float(s.max_hp) - float(s.hp)) / float(prm.per_scrap) - 1.0e-9)


func _find_fix_wall(ctx: Dictionary) -> Dictionary:
	var prm: Dictionary = _kd("fix_wall").params
	var seg = _wall_to_fix(prm)
	if seg == null:
		return {}
	var p = _holder("engineer")
	if p == null or not ctx.proposers.has(p):
		p = _best(ctx.proposers, "Building")
	if p == null:
		return {}
	var args := {"seg": int(seg.id)}
	if _why_fix_wall(p, [], args) != "":
		return {}
	var w := _wall_words(seg)
	w["scrap"] = _scrap_for(seg, prm)
	w["first"] = String(p.first)
	return {"p": p, "others": [], "args": args, "cost": {"scrap": w.scrap}, "line": _say("fix_wall", "line", w), "sub": _say("fix_wall", "sub", w), "yes": _say("fix_wall", "yes", w)}


func _why_fix_wall(p, _others: Array, args: Dictionary) -> String:
	var prm: Dictionary = _kd("fix_wall").params
	if not _free_to_work(p):
		return "%s cannot go now" % String(p.first)
	var seg = _segment(int(args.get("seg", -1)))
	if seg == null:
		return "there is no such wall"
	if sim.phase != "day" or float(sim.hour) > float(sim.seasons.dusk_hour()) - float(prm.before_dusk_h):
		return "dusk is too near"
	var why := _wall_not(seg, prm)
	if why != "":
		return why
	var need := _scrap_for(seg, prm)
	if float(sim.stock.scrap) + 1.0e-9 < float(need):
		return "it needs %d scrap" % need
	return ""


func _apply_fix_wall(p, _others: Array, args: Dictionary) -> String:
	var seg = _segment(int(args.seg))
	var prm: Dictionary = _kd("fix_wall").params
	var w := _wall_words(seg)
	w["scrap"] = _scrap_for(seg, prm)
	w["first"] = String(p.first)
	sim.order_repair(p, seg)
	return _say("fix_wall", "done", w)


# ------------------------------------------------------------------ bench_target --

func _bench_hands() -> Array:
	var out: Array = []
	for q in sim.jobs.crew_of("bench"):
		if _here(q):
			out.append(q)
	return out


## Whether the bench is about to stop at its line: the ammo within reach of it, not yet at the top, scrap enough over the reserve.
func _bench_wants_more(prm: Dictionary) -> bool:
	var t: float = sim.workshop.target()
	var ammo: float = float(sim.stock.ammo)
	return ammo >= t - float(prm.within) and ammo < float(prm.ammo_under) and t < float(prm.target_under) and float(sim.stock.scrap) >= float(sim.workshop.reserve()) + float(prm.scrap_over_reserve)


func _find_bench_target(ctx: Dictionary) -> Dictionary:
	var prm: Dictionary = _kd("bench_target").params
	var hands := _bench_hands()
	if hands.is_empty() or not _bench_wants_more(prm):
		return {}
	var p = _holder("engineer")
	if p == null or not ctx.proposers.has(p):
		var pool: Array = []
		for q in hands:
			if ctx.proposers.has(q):
				pool.append(q)
		p = _best(pool, "Building")
	if p == null:
		return {}
	var w := {"t": roundi(float(sim.workshop.target())), "to": roundi(float(sim.workshop.target()) + float(prm.step)), "first": String(p.first)}
	return {"p": p, "others": [], "args": {}, "cost": {}, "line": _say("bench_target", "line", w), "sub": _say("bench_target", "sub", w), "yes": _say("bench_target", "yes", w)}


func _why_bench_target(p, _others: Array, _args: Dictionary) -> String:
	var prm: Dictionary = _kd("bench_target").params
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	if _bench_hands().is_empty():
		return "nobody is at the bench"
	if not _bench_wants_more(prm):
		return "the bench does not need it now"
	return ""


func _apply_bench_target(_p, _others: Array, _args: Dictionary) -> String:
	var prm: Dictionary = _kd("bench_target").params
	var to: float = float(sim.workshop.target()) + float(prm.step)
	sim.jobs.set_setting("bench", "ammo_target", to)
	return _say("bench_target", "done", {"to": roundi(float(sim.workshop.target()))})


# ------------------------------------------------------------------------ shared --

static func _plain(text: String) -> String:
	var t := text.strip_edges()
	if t.ends_with("."):
		t = t.substr(0, t.length() - 1)
	return t.substr(0, 1).to_lower() + t.substr(1)


static func _capital(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


func _skill_of(p, skill: String) -> int:
	return int(p.skills.get(skill, 0)) if skill != "" else 0


func _has_trait(p, trait_id: String) -> bool:
	for t in sim.traits.of(p):
		if String(t.id) == trait_id:
			return true
	return false


## The sections somebody is on, by id.
func _mended() -> Dictionary:
	var out := {}
	for q in sim.people:
		if q.repair != null and not (q.dead or q.turned):
			out[int(q.repair.id)] = true
	return out


func _post_id(p) -> String:
	return String(sim.jobs.post_ids.get(String(p.id), ""))


func _post_at(id: String) -> Vector2:
	var po: Dictionary = sim.jobs.post(id)
	return Vector2(po.pos) if not po.is_empty() else Vector2(-1.0e6, -1.0e6)


func _post_name(id: String) -> String:
	return String(sim.jobs.post(id).get("name", "a post")).to_lower()


## Whether a post is one a watchtower helps.
func _tower_post(id: String) -> bool:
	return id != "" and float(sim.build.reach_bonus_at(_post_at(id))) > 0.0


## Alive, not the player, not in `except`: in the order of the crew list.
func _may_swap(q) -> bool:
	return q != null and not (q.dead or q.turned) and not _is_player(q)


func _station_name(id: String) -> String:
	return String(sim.jobs.station(id).get("name", id)).to_lower()


# ----------------------------------------------------------------------- build --

func _caller_waiting() -> bool:
	return int(sim.day) < int(sim.scenario.total_days()) - 1 and (not sim.recruits.queue.is_empty() or int(sim.recruits.generated) < int(sim.recruits.MAX_GENERATED))


func _need_holds(need: String, prm: Dictionary) -> bool:
	match need:
		"housing":
			return sim.recruits.housing_free() <= 0 and _caller_waiting()
		"food":
			return float(sim.supplies.days_left("food")) < float(prm.food_days)
		"ammo":
			return float(sim.stock.ammo) < float(prm.ammo)
		"scrap":
			return float(sim.stock.scrap) < float(prm.scrap)
		"mood":
			return float(sim.morale.crew_value()) < float(prm.mood)
	return false


## The first need that holds and has a building that can be ordered now (none while a site is going up): {"building", "need",
## "why"}, or {}.
func _building_wanted() -> Dictionary:
	var kd := _kd("build")
	if not sim.build.active_site().is_empty():
		return {}
	for need in kd.get("needs", []):
		if not _need_holds(String(need.id), kd.params):
			continue
		for b in need.buildings:
			if sim.build.why_not_build(String(b)) == "":
				return {"building": String(b), "need": String(need.id), "why": String(need.why)}
	return {}


func _find_build(ctx: Dictionary) -> Dictionary:
	var kd := _kd("build")
	var want := _building_wanted()
	if want.is_empty():
		return {}
	var p = _holder("engineer")
	if p == null or not ctx.proposers.has(p):
		p = ctx.voice if ctx.voice != null and ctx.proposers.has(ctx.voice) else _best(ctx.proposers, "Building")
	if p == null:
		return {}
	var b: Dictionary = sim.build.building(String(want.building))
	var w := {"the": String(kd.named.get(String(want.building), "A " + String(b.name).to_lower())), "why": want.why, "scrap": int(b.scrap), "first": String(p.first), "name": String(b.name).to_lower()}
	return {"p": p, "others": [], "args": {"building": want.building, "need": want.need}, "cost": {"scrap": int(b.scrap)}, "line": _say("build", "line", w), "sub": _say("build", "sub", w), "yes": _say("build", "yes", w)}


func _why_build(p, _others: Array, args: Dictionary) -> String:
	var kd := _kd("build")
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	if not sim.build.active_site().is_empty():
		return "something is going up already"
	if not _need_holds(String(args.get("need", "")), kd.params):
		return "it is not needed now"
	return String(sim.build.why_not_build(String(args.get("building", ""))))


func _apply_build(_p, _others: Array, args: Dictionary) -> String:
	var id := String(args.building)
	var b: Dictionary = sim.build.building(id)
	if not sim.build.order(sim.build.home_for(id), id):
		return "Not now: it cannot be ordered"
	return _say("build", "done", {"name": String(b.name).to_lower(), "scrap": int(b.scrap)})


# --------------------------------------------------------------------- wall_line --

## The section a higher line would reach: not a door, nobody on it, with its health from the crew's line up to the line plus a step
## (and inside the idea's own bounds); the most worn first. null when none.
func _wall_line_section(prm: Dictionary):
	var x: float = float(sim.jobs.setting("builders", "repair_below"))
	var lo: float = maxf(x, float(prm.from_pct) * 100.0) / 100.0
	var hi: float = minf(x + float(prm.step), float(prm.to_pct) * 100.0) / 100.0
	var mending := _mended()
	var best = null
	var best_f := 2.0
	for s in sim.segments:
		if String(s.kind) == sim.DOOR_KIND or mending.has(int(s.id)):
			continue
		var f: float = float(s.hp) / float(s.max_hp)
		if f < lo - 1.0e-9 or f >= hi - 1.0e-9:
			continue
		if best == null or f < best_f - 1.0e-9:
			best = s
			best_f = f
	return best


func _builders_here() -> Array:
	var out: Array = []
	for q in sim.jobs.crew_of("builders"):
		if _here(q):
			out.append(q)
	return out


func _wall_line_why(prm: Dictionary) -> String:
	if float(sim.jobs.setting("builders", "repair_below")) >= float(prm.below):
		return "the crew's line is high enough"
	if float(sim.stock.scrap) < float(prm.min_scrap):
		return "it needs %d scrap" % int(prm.min_scrap)
	if _builders_here().is_empty():
		return "nobody is on the Builders"
	if _wall_line_section(prm) == null:
		return "no wall needs it now"
	return ""


func _find_wall_line(ctx: Dictionary) -> Dictionary:
	var prm: Dictionary = _kd("wall_line").params
	if _wall_line_why(prm) != "":
		return {}
	var pool: Array = []
	for q in _builders_here():
		if ctx.proposers.has(q):
			pool.append(q)
	var p = _best(pool, "Building")
	if p == null:
		return {}
	var seg = _wall_line_section(prm)
	var x: int = roundi(float(sim.jobs.setting("builders", "repair_below")))
	var w := _wall_words(seg)
	w["x"] = x
	w["to"] = x + int(prm.step)
	w["first"] = String(p.first)
	return {"p": p, "others": [], "args": {}, "cost": {}, "line": _say("wall_line", "line", w), "sub": _say("wall_line", "sub", w), "yes": _say("wall_line", "yes", w)}


func _why_wall_line(p, _others: Array, _args: Dictionary) -> String:
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	return _wall_line_why(_kd("wall_line").params)


func _apply_wall_line(_p, _others: Array, _args: Dictionary) -> String:
	var prm: Dictionary = _kd("wall_line").params
	sim.jobs.set_setting("builders", "repair_below", float(sim.jobs.setting("builders", "repair_below")) + float(prm.step))
	return _say("wall_line", "done", {"to": roundi(float(sim.jobs.setting("builders", "repair_below")))})


# ------------------------------------------------------------------------- desk --

const DESK_ORDER := ["infirmary", "radio", "watch"]


## Whether this desk is empty and it is the hour to say so: nobody of its crew is at the base; the radio in the morning, the lookout
## in the afternoon, the infirmary with somebody in a bed.
func _desk_open(station: String, prm: Dictionary) -> bool:
	if not sim.jobs.unlocked(station):
		return false
	for q in sim.jobs.crew_of(station):
		if _here(q):
			return false
	var h: float = sim.hour
	match station:
		"radio":
			return h >= float(prm.radio_from) and h <= float(prm.radio_to)
		"watch":
			return h >= float(prm.watch_from) and h <= float(prm.watch_to)
		"infirmary":
			for q in sim.people:
				if not (q.dead or q.turned) and q.resting_bed != null:
					return true
	return false


## Who is free to take a desk: nobody's job, or one that can wait (the garden, the salvage bench), and a seat for them.
func _desk_pool(station: String, people: Array) -> Array:
	var out: Array = []
	for q in people:
		var job: String = sim.jobs.job_of(q)
		if (job == "" or job == "garden" or job == "salvage") and sim.jobs.why_not(q, station) == "":
			out.append(q)
	return out


func _find_desk(ctx: Dictionary) -> Dictionary:
	var kd := _kd("desk")
	for station in DESK_ORDER:
		var sd: Dictionary = kd.stations.get(station, {})
		if sd.is_empty() or not _desk_open(station, kd.params):
			continue
		var pool := _desk_pool(station, ctx.proposers)
		if pool.is_empty():
			continue
		var p = _holder(String(sd.title)) if String(sd.title) != "" else null
		if p == null or not pool.has(p):
			p = _best(pool, String(sd.skill))
		var old: String = sim.jobs.job_of(p)
		var w := {"first": String(p.first), "short": String(sd.short), "old": "the %s" % _station_name(old) if old != "" else ""}
		return {"p": p, "others": [], "args": {"station": station}, "cost": {}, "skill": String(sd.skill), "title": String(sd.title), "line": String(sd.line), "sub": _say("desk", "sub" if old != "" else "sub_free", w), "yes": _say("desk", "yes", w)}
	return {}


func _why_desk(p, _others: Array, args: Dictionary) -> String:
	var station := String(args.get("station", ""))
	if not _free_to_work(p):
		return "%s cannot go now" % String(p.first)
	if not _desk_open(station, _kd("desk").params):
		return "somebody is there already, or it is not the hour"
	return String(sim.jobs.why_not(p, station))


func _apply_desk(p, _others: Array, args: Dictionary) -> String:
	var station := String(args.station)
	sim.jobs.assign(p, station)
	return _say("desk", "done", {"first": String(p.first), "short": String(_kd("desk").stations[station].short)})


# ----------------------------------------------------------------------- garden --

## Someone to give a hand at the garden: here, free, no job, not the proposer; the one least needed elsewhere (ten minus their
## best skill), then the smaller id.
func _garden_hand(except):
	var best = null
	var best_score := -1.0e9
	for q in sim.people:
		if q == except or not _free_to_work(q) or sim.jobs.job_of(q) != "":
			continue
		var top := 0
		for k in ["Shooting", "Building", "Medicine", "Leading"]:
			top = maxi(top, int(q.skills.get(k, 0)))
		var score := float(10 - top)
		if best == null or score > best_score:
			best = q
			best_score = score
	return best


func _garden_short() -> bool:
	return sim.jobs.unlocked("garden") and float(sim.supplies.days_left("food")) < float(_kd("garden").params.food_days) and sim.jobs.seats_left("garden") > 0


func _find_garden(ctx: Dictionary) -> Dictionary:
	if not _garden_short():
		return {}
	var gardeners: Array = []
	for q in sim.jobs.crew_of("garden"):
		if ctx.proposers.has(q):
			gardeners.append(q)
	var p = _best(gardeners, "")
	if p == null:
		var farmers: Array = []
		for q in ctx.proposers:
			if String(q.def.get("role", "")) == "Farmer":
				farmers.append(q)
		p = _best(farmers, "")
	if p == null:
		return {}
	var q = _garden_hand(p)
	if q == null:
		return {}
	var w := {"helper": String(q.first), "first": String(p.first), "days": snappedf(float(sim.supplies.days_left("food")), 0.1)}
	return {"p": p, "others": [q], "args": {}, "cost": {}, "line": _say("garden", "line", w), "sub": _say("garden", "sub", w), "yes": _say("garden", "yes", w)}


func _why_garden(p, others: Array, _args: Dictionary) -> String:
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	if not _garden_short():
		return "the garden does not need it now"
	if others.is_empty() or not _free_to_work(others[0]) or sim.jobs.job_of(others[0]) != "":
		return "nobody is free to go"
	return ""


func _apply_garden(_p, others: Array, _args: Dictionary) -> String:
	sim.jobs.assign(others[0], "garden")
	return _say("garden", "done", {"helper": String(others[0].first)})


# ----------------------------------------------------------------------- errand --

## The terms of a trip the player is not on (round 18's `scavenge.errand_terms()`: about 60% of the loot, no rare finds, a worse chance
## everyone comes home). This module runs only with an avatar, and then every party the dice send is such an errand (`scavenge.is_errand`):
## `scavenge.send` below applies the terms, and the idea says so.
func _errand_terms() -> Dictionary:
	return sim.scavenge.errand_terms()


## Whether this person would go, by the same list of reasons as the radio's verbs, the Map page's chips and the Jobs page (round 18's
## `radio.reason_not`: bleeding, starving, shaken, tending a patient, staying with a hurt friend, no going with an enemy among `with`,
## the ids of who else is going): nobody offers a trip they would refuse if the player asked.
func _will_go(q, with: Array = []) -> bool:
	return sim.scavenge.can_go(q) and bool(sim.radio.reason_not(q, "go", with).ok)


## What the stores are short of, in the data's order.
func _short_stocks(prm: Dictionary) -> Array:
	var out: Array = []
	for need in _kd("errand").get("needs", []):
		var short := false
		match String(need):
			"food":
				short = float(sim.supplies.days_left("food")) < float(prm.food_days)
			"water":
				short = float(sim.supplies.days_left("water")) < float(prm.water_days)
			"meds":
				short = float(sim.stock.meds) < float(prm.meds)
			"scrap":
				short = float(sim.stock.scrap) < float(prm.scrap)
			"ammo":
				short = float(sim.stock.ammo) < float(prm.ammo)
		if short:
			out.append(String(need))
	return out


## The place to go for what is short: known, not picked over, on foot, not dangerous, with loot of the first short stock that has such
## a place (the nearest, the safest first): {"site", "covers" (the short stocks it has)} or {}.
func _errand_place(shorts: Array, prm: Dictionary) -> Dictionary:
	var sites: Array = sim.scavenge.available_sites()
	for need in shorts:
		var found: Array = []
		for s in sites:
			if not bool(s.get("available", false)) or bool(s.get("needs_vehicle", false)) or int(s.get("danger", 9)) > int(prm.max_danger):
				continue
			if not (s.get("actions", []) as Array).has("loot") or not (s.get("loot", {}) as Dictionary).has(need):
				continue
			found.append(s)
		if found.is_empty():
			continue
		found.sort_custom(func(a, b):
			if int(a.danger) != int(b.danger):
				return int(a.danger) < int(b.danger)
			if not is_equal_approx(float(a.get("hours", 0.0)), float(b.get("hours", 0.0))):
				return float(a.get("hours", 0.0)) < float(b.get("hours", 0.0))
			return String(a.id) < String(b.id))
		var covers: Array = []
		for k in shorts:
			if (found[0].loot as Dictionary).has(k):
				covers.append(k)
		return {"site": found[0], "covers": covers}
	return {}


func _joined(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


func _find_errand(ctx: Dictionary) -> Dictionary:
	var prm: Dictionary = _kd("errand").params
	var h: float = sim.hour
	if h < float(sim.scavenge.SEND_FROM_H) or h >= float(sim.scavenge.SEND_TO_H) - float(prm.window_left_h) or not sim.scavenge.can_send():
		return {}
	var found := _errand_place(_short_stocks(prm), prm)
	if found.is_empty():
		return {}
	var pool: Array = []
	for q in ctx.proposers:
		if _will_go(q):
			pool.append(q)
	var p = _holder("scout")
	if p == null or not pool.has(p):
		p = null
		var most := 0
		for q in pool:
			var trips := _trips_of(q)
			if trips > most or (trips == most and trips > 0 and p != null and String(q.id) < String(p.id)):
				most = trips
				p = q
		if p == null:
			p = _best(pool, "Shooting")
	if p == null:
		return {}
	var mate = null
	for f in _friends(p):
		if f != p and not _is_player(f) and _here(f) and _will_go(f, [String(p.id)]):
			mate = f
			break
	if mate == null:
		var rest: Array = []
		for q in sim.scavenge.free_survivors():
			if q != p and not _is_player(q) and _here(q) and _will_go(q, [String(p.id)]):
				rest.append(q)
		mate = _best(rest, "Shooting")
	var party: Array = [p, mate] if mate != null else [p]
	if sim.scavenge.why_not_errand(party, String(found.site.id), "loot") != "":
		return {}
	var terms := _errand_terms()
	var share := float(terms.get("loot", 1.0))
	var where := String(found.site.get("where", found.site.get("name", "the place")))
	var w := {
		"Where": _capital(where), "where": where, "loot": _joined(found.covers), "us": ("%s and I" % String(mate.first)) if mate != null else "I",
		"party": _joined(_ids_first(party)), "first": String(p.first),
		"less": " We'd find less without you." if share < 1.0 else "",
		"terms": ("About %d%% of the loot." % roundi(share * 100.0)) if share < 1.0 else String(prm.trip_note),
	}
	return {
		"p": p, "others": [mate] if mate != null else [], "args": {"place": String(found.site.id), "covers": found.covers.duplicate()}, "cost": {},
		"ttl": (float(sim.scavenge.SEND_TO_H) - h) * 60.0, "line": _say("errand", "line", w), "sub": _say("errand", "sub", w), "yes": _say("errand", "yes", w),
	}


func _ids_first(list: Array) -> Array:
	var out: Array = []
	for p in list:
		out.append(String(p.first))
	return out


func _why_errand(p, others: Array, args: Dictionary) -> String:
	var prm: Dictionary = _kd("errand").params
	var party: Array = [p] + others
	var ids: Array = []
	for q in party:
		ids.append(String(q.id))
	for q in party:
		if not _here(q) or _is_player(q) or not _will_go(q, ids):
			return "%s cannot go now" % String(q.first)
	if not sim.scavenge.can_send():
		return _plain(String(sim.scavenge.why_not()))
	var place := String(args.get("place", ""))
	var site: Dictionary = {}
	for s in sim.scavenge.available_sites():
		if String(s.id) == place:
			site = s
	var needed := false
	for k in _short_stocks(prm):
		if not site.is_empty() and (site.get("loot", {}) as Dictionary).has(k):
			needed = true
	if site.is_empty() or not needed:
		return "it is not needed now"
	return _plain(String(sim.scavenge.why_not_errand(party, place, "loot")))


func _apply_errand(p, others: Array, args: Dictionary) -> String:
	var party: Array = [p] + others
	var place := String(args.place)
	if not sim.scavenge.send(party, place, "loot"):
		return "Not now: they cannot set off"
	var where := String(sim.scavenge._where(place)) if sim.scavenge.has_method("_where") else "the place"
	return _say("errand", "done", {"party": _joined(_ids_first(party)), "where": where})


# --------------------------------------------------------------------- swap_posts --

func _find_swap_posts(ctx: Dictionary) -> Dictionary:
	var prm: Dictionary = _kd("swap_posts").params
	var holders: Array = []
	for q in sim.people:
		if not _may_swap(q):
			continue
		var pid := _post_id(q)
		if _tower_post(pid):
			holders.append({"q": q, "post": pid})
	if holders.is_empty():
		return {}
	var order: Array = ctx.proposers.duplicate()
	order.sort_custom(func(a, b):
		var sa := _skill_of(a, "Shooting")
		var sb := _skill_of(b, "Shooting")
		return sa > sb or (sa == sb and String(a.id) < String(b.id)))
	for p in order:
		if _tower_post(_post_id(p)):
			continue
		var best = null
		for h in holders:
			if h.q == p or _skill_of(p, "Shooting") - _skill_of(h.q, "Shooting") < int(prm.better_by):
				continue
			if best == null or _skill_of(h.q, "Shooting") < _skill_of(best.q, "Shooting") or (_skill_of(h.q, "Shooting") == _skill_of(best.q, "Shooting") and String(h.q.id) < String(best.q.id)):
				best = h
		if best == null:
			continue
		var w := {"first": String(p.first), "other": String(best.q.first), "old": _post_name(_post_id(p)), "mine": _skill_of(p, "Shooting"), "theirs": _skill_of(best.q, "Shooting")}
		return {"p": p, "others": [best.q], "args": {"post": best.post}, "cost": {}, "line": _say("swap_posts", "line", w), "sub": _say("swap_posts", "sub", w), "yes": _say("swap_posts", "yes", w)}
	return {}


func _why_swap_posts(p, others: Array, args: Dictionary) -> String:
	var prm: Dictionary = _kd("swap_posts").params
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	if others.is_empty() or not _may_swap(others[0]):
		return "he is not here"
	var q = others[0]
	var post := String(args.get("post", ""))
	if _post_id(q) != post or not _tower_post(post):
		return "the post is not %s's now" % String(q.first)
	if _tower_post(_post_id(p)):
		return "%s has a tower post already" % String(p.first)
	if _skill_of(p, "Shooting") - _skill_of(q, "Shooting") < int(prm.better_by):
		return "%s is not the better shot now" % String(p.first)
	return ""


func _apply_swap_posts(p, others: Array, args: Dictionary) -> String:
	var prm: Dictionary = _kd("swap_posts").params
	var q = others[0]
	var mine := _post_id(p)
	sim.jobs.post_ids[String(p.id)] = String(args.post)
	sim.jobs.post_ids[String(q.id)] = mine
	p.goal_key = ""
	q.goal_key = ""
	sim.morale.shock(q, float(prm.holder_morale), "Lost a post")
	_add_rel(p, q, float(prm.holder_affinity), "Took the tower post")
	return _say("swap_posts", "done", {"first": String(p.first), "other": String(q.first), "old": _post_name(mine)})


func _refused_swap_posts(p, others: Array, _args: Dictionary) -> void:
	if not others.is_empty():
		_add_rel(p, others[0], float(_kd("swap_posts").params.refused_affinity), "Turned down for the tower")


# -------------------------------------------------------------------- post_beside --

## A way for `p` to stand beside `f` on the wall: far from them now (more than the idea's `apart`), and a third person holding a post
## within `beside` tiles of theirs (the nearest of those): {"r", "post"} or {}.
func _beside(p, f) -> Dictionary:
	var prm: Dictionary = _kd("post_beside").params
	var mine := _post_id(p)
	var theirs := _post_id(f)
	if mine == "" or theirs == "" or _post_at(mine).distance_to(_post_at(theirs)) <= float(prm.apart):
		return {}
	var at := _post_at(theirs)
	var best := {}
	var best_d := 1.0e9
	for r in sim.people:
		if r == p or r == f or not _may_swap(r):
			continue
		var rid := _post_id(r)
		if rid == "":
			continue
		var d := _post_at(rid).distance_to(at)
		if d > float(prm.beside):
			continue
		if d < best_d - 1.0e-9 or (is_equal_approx(d, best_d) and String(r.id) < String(best.r.id)):
			best = {"r": r, "post": rid}
			best_d = d
	return best


func _find_post_beside(ctx: Dictionary) -> Dictionary:
	for p in ctx.proposers:
		for f in _friends(p):
			if f == p or not _may_swap(f):
				continue
			var plan := _beside(p, f)
			if plan.is_empty():
				continue
			var w := {"first": String(p.first), "friend": String(f.first), "other": String(plan.r.first), "old": _post_name(_post_id(p))}
			return {"p": p, "others": [f, plan.r], "args": {"post": plan.post, "from": _post_id(p)}, "cost": {}, "line": _say("post_beside", "line", w), "sub": _say("post_beside", "sub", w), "yes": _say("post_beside", "yes", w)}
	return {}


func _why_post_beside(p, others: Array, args: Dictionary) -> String:
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	if others.size() < 2 or not _may_swap(others[0]) or not _may_swap(others[1]):
		return "they are not here"
	var plan := _beside(p, others[0])
	if plan.is_empty() or plan.r != others[1] or String(plan.post) != String(args.get("post", "")):
		return "the posts have changed"
	return ""


func _apply_post_beside(p, others: Array, args: Dictionary) -> String:
	var prm: Dictionary = _kd("post_beside").params
	var f = others[0]
	var r = others[1]
	var mine := _post_id(p)
	sim.jobs.post_ids[String(p.id)] = String(args.post)
	sim.jobs.post_ids[String(r.id)] = mine
	p.goal_key = ""
	r.goal_key = ""
	_add_rel(p, f, float(prm.gain), "Stood together on the wall")
	return _say("post_beside", "done", {"first": String(p.first), "friend": String(f.first), "other": String(r.first), "old": _post_name(mine)})


# ----------------------------------------------------------------------- supper --

func _supper_needed(prm: Dictionary) -> bool:
	if float(sim.morale.crew_value()) < float(prm.mood_under):
		return true
	var loss := _recent_loss()
	return not loss.is_empty() and _num(loss.get("day")) and int(sim.day) - int(loss.day) <= 1


func _supper_why(prm: Dictionary) -> String:
	var h: float = sim.hour
	if h < float(prm.from) or h > float(prm.to):
		return "it is not the hour"
	if float(sim.stock.food) < float(prm.food):
		return "there is too little food"
	if not _supper_needed(prm):
		return "the camp does not need it now"
	return ""


func _find_supper(ctx: Dictionary) -> Dictionary:
	var prm: Dictionary = _kd("supper").params
	if _supper_why(prm) != "":
		return {}
	var p = ctx.voice if ctx.voice != null and ctx.proposers.has(ctx.voice) else null
	if p == null:
		var cooks: Array = []
		var cheerful: Array = []
		for q in ctx.proposers:
			if String(q.def.get("role", "")) == "Cook":
				cooks.append(q)
			if _has_trait(q, "optimist"):
				cheerful.append(q)
		p = _best(cooks, "")
		if p == null:
			p = _best(cheerful, "")
	if p == null:
		return {}
	var w := {"first": String(p.first), "mood": String(sim.morale.crew_mood()).to_lower()}
	return {"p": p, "others": [], "args": {}, "cost": {"food": int(prm.cost_food)}, "line": _say("supper", "line", w), "sub": _say("supper", "sub", w), "yes": _say("supper", "yes", w)}


func _why_supper(p, _others: Array, _args: Dictionary) -> String:
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	return _supper_why(_kd("supper").params)


func _apply_supper(_p, _others: Array, _args: Dictionary) -> String:
	var prm: Dictionary = _kd("supper").params
	sim.stock.food = maxf(0.0, float(sim.stock.food) - float(prm.cost_food))
	sim.morale.shock(null, float(prm.mood), "A shared supper")
	var here: Array = []
	for q in sim.people:
		if _here(q) and not _is_player(q):
			here.append(q)
	for i in here.size():
		for j in range(i + 1, here.size()):
			_add_rel(here[i], here[j], float(prm.bond), "A shared supper")
	return _say("supper", "done", {})


# ---------------------------------------------------------------------- quarrel --

## How two rivals are in each other's way: "station" (the same job), "post" (night posts within the idea's tiles), or "".
func _clash(a, b, prm: Dictionary) -> String:
	var job: String = sim.jobs.job_of(a)
	if job != "" and job == sim.jobs.job_of(b):
		return "station"
	var pa := _post_id(a)
	var pb := _post_id(b)
	if pa != "" and pb != "" and _post_at(pa).distance_to(_post_at(pb)) <= float(prm.tiles):
		return "post"
	return ""


## What puts them apart: {"mode": "station", "station": id} (`move` goes to another job: the one that suits them best, with a seat, not
## their rival's) or {"mode": "post", "post": id, "swap": id of whoever holds it or ""} (the post at least `far` tiles from the other's that
## is nearest their own); {} when nothing can be done.
func _apart(stay, move, mode: String, prm: Dictionary) -> Dictionary:
	if mode == "station":
		var best := ""
		var best_skill := -1
		var theirs: String = sim.jobs.job_of(stay)
		for st in sim.jobs.stations():
			var id := String(st.id)
			if id == theirs or id == sim.jobs.job_of(move) or sim.jobs.why_not(move, id) != "":
				continue
			var skill := _skill_of(move, String(st.get("skill", "")))
			if skill > best_skill:
				best = id
				best_skill = skill
		return {"mode": "station", "station": best} if best != "" else {}
	var home := _post_at(_post_id(stay))
	var mine := _post_at(_post_id(move))
	var pick := ""
	var pick_d := 1.0e9
	for po in sim.jobs.posts():
		var id := String(po.id)
		if Vector2(po.pos).distance_to(home) < float(prm.far):
			continue
		var holder = null
		for q in sim.people:
			if _may_swap(q) and _post_id(q) == id:
				holder = q
		if holder == stay:
			continue
		var d: float = Vector2(po.pos).distance_to(mine)
		if d < pick_d - 1.0e-9:
			pick = id
			pick_d = d
	if pick == "":
		return {}
	var swap := ""
	for q in sim.people:
		if _may_swap(q) and q != move and _post_id(q) == pick:
			swap = String(q.id)
	return {"mode": "post", "post": pick, "swap": swap}


## Of two rivals the one who stays (the better leader, then the smaller id) and the one who moves.
func _order_pair(a, b) -> Array:
	var la := _skill_of(a, "Leading")
	var lb := _skill_of(b, "Leading")
	if la > lb or (la == lb and String(a.id) < String(b.id)):
		return [a, b]
	return [b, a]


func _find_quarrel(ctx: Dictionary) -> Dictionary:
	var prm: Dictionary = _kd("quarrel").params
	for a in ctx.here:
		for b in _rivals(a):
			if b == a or not ctx.here.has(b) or sim.people.find(b) < sim.people.find(a):
				continue
			var mode := _clash(a, b, prm)
			if mode == "":
				continue
			var pair := _order_pair(a, b)
			var plan := _apart(pair[0], pair[1], mode, prm)
			if plan.is_empty():
				continue
			var p = ctx.voice if ctx.voice != null and ctx.proposers.has(ctx.voice) and ctx.voice != a and ctx.voice != b else null
			if p == null:
				for q in ctx.proposers:
					if q != a and q != b and _friends(q).has(a) and _friends(q).has(b):
						p = q
						break
			if p == null:
				continue
			var move_text: String = ("goes to the %s" % _station_name(String(plan.station))) if mode == "station" else ("takes the %s" % _post_name(String(plan.post)))
			var w := {"a": String(pair[0].first), "b": String(pair[1].first), "move": move_text, "reason": "They no longer work side by side." if mode == "station" else "They no longer stand side by side."}
			return {"p": p, "others": [pair[0], pair[1]], "args": {"mode": mode}, "cost": {}, "line": _say("quarrel", "line", w), "sub": _say("quarrel", "sub", w), "yes": _say("quarrel", "yes", w)}
	return {}


func _why_quarrel(p, others: Array, args: Dictionary) -> String:
	var prm: Dictionary = _kd("quarrel").params
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	if others.size() < 2 or not _here(others[0]) or not _here(others[1]):
		return "they are not both here"
	if not _rivals(others[0]).has(others[1]):
		return "they are not at odds now"
	var mode := _clash(others[0], others[1], prm)
	if mode == "":
		return "they are not in each other's way now"
	if _apart(others[0], others[1], mode, prm).is_empty():
		return "there is nowhere to put them"
	return ""


func _apply_quarrel(_p, others: Array, _args: Dictionary) -> String:
	var prm: Dictionary = _kd("quarrel").params
	var stay = others[0]
	var move = others[1]
	var plan := _apart(stay, move, _clash(stay, move, prm), prm)
	var move_text := ""
	if String(plan.mode) == "station":
		sim.jobs.assign(move, String(plan.station))
		move_text = "goes to the %s" % _station_name(String(plan.station))
	else:
		var old := _post_id(move)
		sim.jobs.post_ids[String(move.id)] = String(plan.post)
		move.goal_key = ""
		if String(plan.swap) != "":
			var r = _person(String(plan.swap))
			sim.jobs.post_ids[String(r.id)] = old
			r.goal_key = ""
		move_text = "takes the %s" % _post_name(String(plan.post))
	_add_rel(stay, move, float(prm.gain), "Put apart")
	return _say("quarrel", "done", {"b": String(move.first), "move": move_text})


# ----------------------------------------------------------------------- lesson --

## Free for a lesson: free for work, with no order and nothing to mend.
func _free_for_lesson(p) -> bool:
	return _free_to_work(p) and p.order == null and p.repair == null and not p.drafted


func _teaching(p) -> bool:
	for l in doing:
		if String(l.teacher) == String(p.id) or String(l.student) == String(p.id):
			return true
	return false


## The learner of a teacher in a skill: here, free, at that skill `student_max` or under, still able to learn, not cold to them
## (affinity 0 or more); the one who knows least, then the warmest, then the smaller id. null when none.
func _learner(teacher, skill: String, prm: Dictionary):
	var best = null
	var best_key := []
	for q in sim.people:
		if q == teacher or _is_player(q) or not _free_for_lesson(q) or _teaching(q) or _lesson_clash(q, prm):
			continue
		var have := _skill_of(q, skill)
		if have > int(prm.student_max) or have >= int(sim.skills.cap_of(q, skill)):
			continue
		var warmth := _affinity(teacher, q)
		if warmth < 0.0:
			continue
		var key := [have, -warmth]
		if best == null or key[0] < best_key[0] or (key[0] == best_key[0] and key[1] < best_key[1]):
			best = q
			best_key = key
	return best


func _lesson_hour_ok(prm: Dictionary) -> bool:
	return sim.phase == "day" and float(sim.hour) <= float(sim.seasons.dusk_hour()) - float(prm.dusk_h)


## Whether an hour at a lesson would take the person from something the day needs them for: the radio desk through the noon hour, the
## lookout through the forecast.
func _lesson_clash(p, prm: Dictionary) -> bool:
	var h: float = sim.hour
	var end: float = h + float(prm.minutes) / 60.0
	var job: String = sim.jobs.job_of(p)
	if job == "radio":
		return end >= RADIO_FROM_H and h <= RADIO_TO_H
	if job == "watch":
		var f: float = sim.tactics.forecast_hour()
		return end >= f - float(sim.radio.LOOKOUT_BEFORE_H) and h <= f
	return false


## Somebody at the base is down or bleeding: the healers are wanted (a person at a lesson is on an order, and no healer for the case).
func _emergency() -> bool:
	for q in sim.people:
		if not (q.dead or q.turned) and q.away == null and (q.downed or float(q.bleeding) > 0.0):
			return true
	return false


func _find_lesson(ctx: Dictionary) -> Dictionary:
	var kd := _kd("lesson")
	var prm: Dictionary = kd.params
	if not _lesson_hour_ok(prm) or _emergency():
		return {}
	for title in kd.titles:
		var teacher = _holder(String(title))
		var skill := String(kd.titles[title])
		if teacher == null or not ctx.proposers.has(teacher) or not _free_for_lesson(teacher) or _teaching(teacher) or _lesson_clash(teacher, prm) or _skill_of(teacher, skill) < int(prm.teacher_min):
			continue
		var student = _learner(teacher, skill, prm)
		if student == null:
			continue
		var sk: Dictionary = kd.skills[skill]
		var w := {"first": String(teacher.first), "student": String(student.first), "phrase": String(sk.phrase), "skill": skill, "have": _skill_of(student, skill), "next": _skill_of(student, skill) + 1}
		return {"p": teacher, "others": [student], "args": {"skill": skill}, "cost": {}, "title": String(title), "line": _say("lesson", "line", w), "sub": _say("lesson", "sub", w), "yes": _say("lesson", "yes", w)}
	return {}


func _why_lesson(p, others: Array, args: Dictionary) -> String:
	var kd := _kd("lesson")
	var prm: Dictionary = kd.params
	var skill := String(args.get("skill", ""))
	if others.is_empty() or not kd.skills.has(skill):
		return "there is nobody to teach"
	var student = others[0]
	if not _free_for_lesson(p) or not _free_for_lesson(student) or _teaching(p) or _teaching(student):
		return "they are not both free"
	if not _lesson_hour_ok(prm):
		return "it is too late in the day"
	if _emergency():
		return "somebody needs the healers"
	if _lesson_clash(p, prm) or _lesson_clash(student, prm):
		return "they are wanted at their posts"
	if _skill_of(p, skill) < int(prm.teacher_min) or _skill_of(student, skill) > int(prm.student_max) or _skill_of(student, skill) >= int(sim.skills.cap_of(student, skill)):
		return "there is nothing more to learn"
	if _affinity(p, student) < 0.0:
		return "they would rather not"
	return ""


func _apply_lesson(p, others: Array, args: Dictionary) -> String:
	var kd := _kd("lesson")
	var prm: Dictionary = kd.params
	var student = others[0]
	var skill := String(args.skill)
	var spots: Array = sim.jobs.rest_spots()
	if spots.is_empty():
		return "Not now: there is nowhere to sit"
	var i: int = int(sim.day) % spots.size()
	var at_t: Vector2 = spots[i].pos
	var at_s: Vector2 = spots[(i + 1) % spots.size()].pos
	if not sim.order_move(p, at_t.x, at_t.y):
		return "Not now: there is nowhere to sit"
	if not sim.order_move(student, at_s.x, at_s.y):
		p.order = null
		p.drafted = false
		return "Not now: there is nowhere to sit"
	var kind := String(kd.skills[skill].kind)
	doing.append({
		"teacher": String(p.id), "student": String(student.id), "skill": skill, "kind": kind, "per": float(sim.skills.KINDS[kind].per),
		"until": float(sim.clock_min) + float(prm.minutes), "spot_t": [at_t.x, at_t.y], "spot_s": [at_s.x, at_s.y],
	})
	return _say("lesson", "done", {"first": String(p.first), "student": String(student.first)})


## The lessons: one that has gone its hour is over (the student has a point of the skill, the two are closer, the teacher the better
## for it); one that is broken off (the alarm, the dead at the wall, the night, somebody gone or hurt) is dropped with nothing.
func _tend_lessons() -> void:
	var prm: Dictionary = _kd("lesson").params
	var rest: Array = []
	for l in doing:
		var teacher = _person(String(l.teacher))
		var student = _person(String(l.student))
		if teacher == null or student == null:
			continue
		var broken: bool = sim.phase != "day" or sim.radio.alarm_on or sim.threat_by_day() or not _here(teacher) or not _here(student)
		broken = broken or String(teacher.stance) != "" or String(student.stance) != "" or _emergency()    # (somebody asked them to come along; somebody is hurt)
		if not broken and float(sim.clock_min) < float(l.until):
			rest.append(l)
			continue
		_release(teacher, l.spot_t)
		_release(student, l.spot_s)
		if broken:
			continue
		var before: Dictionary = student.stats.duplicate()
		sim.skills.credit(student, String(l.kind), float(l.per))
		student.stats = before    # (a lesson is not practice: nobody treated or mended or shot anything)
		_add_rel(teacher, student, float(prm.gain), "A lesson")
		sim.morale.shock(teacher, float(prm.teacher_morale), "Taught a lesson")
	doing = rest


## Lets a person go from the place of their lesson, if the order they have is still that one.
func _release(p, spot) -> void:
	if p.order != null and p.order.z < 0.5 and spot is Array and spot.size() == 2 and Vector2(p.order.x, p.order.y).is_equal_approx(Vector2(float(spot[0]), float(spot[1]))):
		p.order = null
		p.drafted = false
		p.goal_key = ""


# --------------------------------------------------------------------- farewell --

## The people the dead one was close to, alive and at the base: their bonds (which include the relations' friends) and the friends the
## relations module knows.
func _circle_of(dead) -> Array:
	var out: Array = []
	if dead == null:
		return out
	for b in sim.bonds.of(dead):
		if _here(b.who) and not out.has(b.who):
			out.append(b.who)
	for f in _friends(dead):
		if _here(f) and not out.has(f):
			out.append(f)
	return out


func _farewell_why(prm: Dictionary) -> String:
	var loss := _recent_loss()
	if loss.is_empty() or not _num(loss.get("day")) or int(sim.day) - int(loss.day) > int(prm.within_days):
		return "nobody was lost lately"
	var h: float = sim.hour
	if sim.phase != "day" or h < float(prm.from) or h > float(prm.to):
		return "it is not the hour"
	return ""


func _find_farewell(ctx: Dictionary) -> Dictionary:
	var prm: Dictionary = _kd("farewell").params
	if _farewell_why(prm) != "":
		return {}
	var loss := _recent_loss()
	var dead = _person(String(loss.get("id", "")))
	var p = ctx.voice if ctx.voice != null and ctx.proposers.has(ctx.voice) and ctx.voice != dead else null
	if p == null and dead != null:
		var best_close := 0.0
		for q in ctx.proposers:
			if q == dead:
				continue
			var close := (100.0 if sim.bonds.bonded(q, dead) else 0.0) + _affinity(q, dead)
			if close > best_close + 1.0e-9:
				best_close = close
				p = q
	if p == null:
		return {}
	var name := String(dead.first) if dead != null else String(loss.get("name", "them")).split(" ")[0]
	var w := {"dead": name, "first": String(p.first)}
	return {"p": p, "others": [], "args": {"dead": String(loss.get("id", "")), "name": name}, "cost": {}, "line": _say("farewell", "line", w), "sub": _say("farewell", "sub", w), "yes": _say("farewell", "yes", w)}


func _why_farewell(p, _others: Array, _args: Dictionary) -> String:
	if not _here(p) or _is_player(p):
		return "%s cannot do it now" % String(p.first)
	return _farewell_why(_kd("farewell").params)


func _apply_farewell(_p, _others: Array, args: Dictionary) -> String:
	var prm: Dictionary = _kd("farewell").params
	var name := String(args.get("name", "them"))
	for q in _circle_of(_person(String(args.get("dead", "")))):
		sim.morale.shock(q, float(prm.circle), "Said goodbye to %s" % name)
	sim.morale.shock(null, float(prm.all), "A few words for %s" % name)
	return _say("farewell", "done", {"dead": name})


func _refused_farewell(_p, _others: Array, args: Dictionary) -> void:
	var prm: Dictionary = _kd("farewell").params
	for q in _circle_of(_person(String(args.get("dead", "")))):
		sim.morale.shock(q, float(prm.unsaid), "Nobody said a word")


# -------------------------------------------------------------------- the voice --

## What the specialist of the matter, else the one people turn to, would say about this call (any open call): {"who", "first", "title",
## "option", "line"} ("Ana, the medic: treat them."), {} when there is none to say it. An attack: the marksman (fall back under 35% of
## the wall, reinforce with four or more at it, else hold); a fever: the medic (treat with two or more medicines, else apart); an
## idea: the voice (yes when its price is under half of the stock, else later; never on their own idea).
func voice_opinion(e: Dictionary) -> Dictionary:
	if not active() or e.is_empty() or String(e.get("answered", "")) != "" or (e.get("options", []) as Array).is_empty():
		return {}
	var data = e.get("data", {})
	if not (data is Dictionary):
		return {}
	var opinion := {}
	match String(e.get("kind", "")):
		"attack":
			opinion = _on_attack(data, "marksman")
		"sick":
			opinion = _on_sick(data, "medic")
		"idea":
			opinion = _on_idea(data)
	if opinion.is_empty():
		return {}
	var has := false
	for o in e.options:
		if String(o.id) == String(opinion.option):
			has = true
	if not has:
		return {}
	var p = opinion.p
	var title := _title_name(p)
	var line: String = ("%s, %s: %s" if title != "" else "%s%s: %s") % [String(p.first), title, String(opinion.say)]
	return {"who": String(p.id), "first": String(p.first), "title": title, "option": String(opinion.option), "line": line}


## The specialist's choice, else the voice (who is up and at the base), and never the leader.
func _opinion_giver(title_id: String, not_them = null):
	var p = _holder(title_id)
	if p == null or not _here(p) or _is_player(p) or p == not_them:
		p = _voice()
		if p == null or not _here(p) or _is_player(p) or p == not_them:
			return null
	return p


func _on_attack(data: Dictionary, title_id: String) -> Dictionary:
	var seg = _segment(int(data.get("seg", -1)))
	var p = _opinion_giver(title_id)
	if seg == null or p == null:
		return {}
	var n := 0
	for sl in seg.slots:
		if sl.who != null and sl.who.state == "attack":
			n += 1
	var f := float(seg.hp) / float(seg.max_hp)
	if f < 0.35:
		return {"p": p, "option": "fall_back", "say": "fall back to the school."}
	if n >= 4:
		return {"p": p, "option": "reinforce", "say": "send reinforcements."}
	return {"p": p, "option": "hold", "say": "hold."}


func _on_sick(data: Dictionary, title_id: String) -> Dictionary:
	var patient = _person(String(data.get("who", "")))
	var p = _opinion_giver(title_id, patient)
	if p == null:
		return {}
	if float(sim.stock.meds) >= float(sim.medical.CURE_MEDS):
		return {"p": p, "option": "treat", "say": "treat them."}
	return {"p": p, "option": "apart", "say": "keep them apart."}


func _on_idea(data: Dictionary) -> Dictionary:
	var p = _voice()
	if p == null or not _here(p) or _is_player(p) or String(p.id) == String(data.get("who", "")):
		return {}
	var cost: Dictionary = data.get("cost", {}) if data.get("cost", {}) is Dictionary else {}
	var cheap := true
	for k in cost:
		if _num(cost[k]) and float(cost[k]) > float(sim.stock.get(String(k), 0.0)) * 0.5 + 1.0e-9:
			cheap = false
	if cheap:
		return {"p": p, "option": "yes", "say": "yes, we can spare it."}
	return {"p": p, "option": "later", "say": "later, the stock is thin."}


# --------------------------------------------------------------------------- save --

static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


func save() -> Dictionary:
	var rows := {}
	for id in records:
		var r: Dictionary = records[id]
		rows[id] = {"asked": int(r.asked), "yes": int(r.yes), "no": int(r.no), "later": int(r.later), "quiet_until": int(r.quiet_until), "last_day": int(r.last_day), "no_days": r.no_days.duplicate()}
	return {
		"acc": _acc, "last_all": last_all, "last_kind": last_kind.duplicate(), "shelved": shelved.duplicate(), "streaks": streaks.duplicate(),
		"records": rows, "doing": doing.duplicate(true), "hushed": hushed, "stats": counts.duplicate(true),
	}


## Restores what `save` wrote. A save from before the ideas has none of it (a fresh module); what is not sound (a number that is not
## finite, a person or a kind that is not known, an entry that is not what it should be) is left out.
func load_state(d: Dictionary) -> void:
	_reset()
	_acc = clampf(float(d.acc), 0.0, TICK_S) if _num(d.get("acc")) else 0.0
	last_all = minf(float(d.last_all), float(sim.clock_min)) if _num(d.get("last_all")) else NEVER
	for key in ["last_kind", "shelved", "streaks"]:
		var raw = d.get(key, {})
		if raw is Dictionary:
			var into: Dictionary = get(key)
			for k in raw:
				if KINDS.has(String(k)) and _num(raw[k]):
					into[String(k)] = int(raw[k])
	var rows = d.get("records", {})
	if rows is Dictionary:
		for id in rows:
			var r = rows[id]
			if not (r is Dictionary) or _person(String(id)) == null:
				continue
			var rec := _new_record()
			for k in ["asked", "yes", "no", "later"]:
				if _num(r.get(k)):
					rec[k] = maxi(0, int(r[k]))
			if _num(r.get("quiet_until")):
				rec["quiet_until"] = clampi(int(r.quiet_until), 0, 100000)
			if _num(r.get("last_day")):
				rec["last_day"] = clampi(int(r.last_day), -999, 100000)
			var days: Array = []
			if r.get("no_days") is Array:
				for x in r.no_days:
					if _num(x):
						days.append(int(x))
			rec["no_days"] = days
			records[String(id)] = rec
	hushed = bool(d.hushed) if typeof(d.get("hushed")) == TYPE_BOOL else false
	var stats = d.get("stats", {})
	if stats is Dictionary:
		for k in ["raised", "yes", "no", "later"]:
			if _num(stats.get(k)):
				counts[k] = maxi(0, int(stats[k]))
		for k in ["scrap", "food"]:
			if _num(stats.get(k)):
				counts[k] = maxf(0.0, float(stats[k]))
		var by = stats.get("by_kind", {})
		if by is Dictionary:
			for kind in by:
				if KINDS.has(String(kind)) and by[kind] is Dictionary:
					var row := {"raised": 0, "yes": 0, "no": 0, "later": 0}
					for k in row:
						if _num(by[kind].get(k)):
							row[k] = maxi(0, int(by[kind][k]))
					counts.by_kind[String(kind)] = row
	# (the lessons are read back with the lessons' own code, below)
	_load_lessons(d.get("doing", []))


func _load_lessons(raw) -> void:
	doing.clear()
	if not (raw is Array):
		return
	var skills: Dictionary = _kd("lesson").get("skills", {})
	for r in raw:
		if not (r is Dictionary):
			continue
		var skill := String(r.get("skill", ""))
		var kind := String(r.get("kind", ""))
		if _person(String(r.get("teacher", ""))) == null or _person(String(r.get("student", ""))) == null or String(r.get("teacher")) == String(r.get("student")):
			continue
		if not skills.has(skill) or not sim.skills.KINDS.has(kind) or not _num(r.get("until")) or not _num(r.get("per")):
			continue
		var at_t = r.get("spot_t")
		var at_s = r.get("spot_s")
		if not (at_t is Array and at_t.size() == 2 and _num(at_t[0]) and _num(at_t[1]) and at_s is Array and at_s.size() == 2 and _num(at_s[0]) and _num(at_s[1])):
			continue
		doing.append({
			"teacher": String(r.teacher), "student": String(r.student), "skill": skill, "kind": kind, "per": float(r.per), "until": float(r.until),
			"spot_t": [float(at_t[0]), float(at_t[1])], "spot_s": [float(at_s[0]), float(at_s[1])],
		})
