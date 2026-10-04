## Problems (round 25, S25.3 of docs/superpowers/plans/2026-10-04-round-25.md): the small trouble the base throws up, a world marker with a timer that
## the player fixes in person (E) or hands to someone over the radio; left alone it gets worse. Four kinds (assets/data/problems.json holds every number
## and word of them):
##   leak     a rain barrel: the water drains 0.6 an hour while it is open (the stock never goes under 0); Building 6 s, 1 scrap
##   jam      the generator by the workbench: no ammo is made (`blocks("bench")`) and the floodlights, if built, are dark (`blocks("floodlights")`);
##            Building 9 s, 1 scrap
##   quarrel  two people with a rift: each works at x0.85 (`perf_mult`), a standing mood line, the pair's relation sinks a little each slow look;
##            fixed by hearing them out (Leading 7 s: settled, "they keep apart" or no luck by a score) or by `separate` (one of them to another seat or
##            the farthest post, no roll, no gain)
##   crack    a compound wall section (never a door or the gate): it loses 1.5% of its strength an hour down to a quarter of it; Building 8 s, 2 scrap
##            (the crack only stops widening: the wall's hit points are mended by the crew or by E as ever)
##
## THE TIMELINE of a problem: raised at stage 1 (News "problem", a bark, event `problem raised`); at half of its time stage 2 (event `problem stage2` and ONE
## call, kind "problem", "Send <name> (72%)" or "Leave it", raised in the day and not under the alarm, the first look that may); past its time it
## ESCALATES once (the leak drains twice as fast and loses 8 water, the generator is wrecked: 3 scrap and double the time and a "No power" blow to
## every mood, the quarrel makes rivals of the two and costs each 5 mood, the crack takes a fifth of the wall's strength, never below a tenth) and stays
## open. A stage, once reached, stays. A failed hearing of a quarrel gives it six more hours.
##
## THE RATE is deterministic: `gap_h(day)` hours between two (about one every 1.5 days in the first week), spread by a hash of the run's seed, the
## day and the count (`_h`), raised only inside `allowed_now()` (from day 3, 07:30 to two hours before dusk, not in the radio hour, never under the
## alarm or with the dead at the wall by day, nor with an urgent call open, at most MAX_OPEN open); the kind is a pure rotation (`pick_kind`). NO `sim.rng`
## draw anywhere in this module: the one "roll" (a delegate's success) is `fix_roll`, a hash of the problem, the person and the run's seed, so a saved
## game replays bit for bit. A person who has failed a problem is not asked for it again (the same roll would give the same answer).
##
## IN PERSON (`candidates`, `use`, interact.gd): E within FIX_REACH of the marker starts the avatar's own hands (`fixing`): the seconds are the kind's
## `base_s` over (0.7 + 0.08 x skill) x the traits' 'repair' (the engineer's title and overtime among them) x how well they are, Building for the
## three works, Leading for the quarrel. Walking, the trigger, a wound, a fall, the dusk bell, the dead at their back or the scrap gone end it; the
## scrap is paid when the work is done. `Person.work` "hammer" shows the pose.
## BY RADIO (`fix_willingness`, `request_fix`, radio.gd): the radio's own reasons come first (`reason_not(p, "work")`, hard or soft, Insist at the usual
## cost and mood blow), then what the problem asks (night, someone on it, one who has tried, one of the pair, the scrap, a skill floor), then a tone's line,
## a delay (the radio's by trust, plus the walk), a chance by skill and trust (and the title) and the work hours. They are ordered to the marker after
## the delay, work there (paying the scrap when they begin) and `fix_roll < chance` decides: success resolves it; failure keeps the problem and the scrap
## spent. Anything that takes them off the order (another order, the dusk, a fall) ends it with a line in the News.
##
## Everything is behind avatar mode in the settlement game (`active()`): with no avatar, on Orientation Day, in the classic six start and in the harness
## every hook below returns its neutral value (nothing open, nothing blocked, 1.0, [], false) and nothing is raised or drained.
##
## A problem is a record {"id": "p<n>", "kind", "day", "t0" (clock_min), "ttl_h", "at": Vector2, "label", "ids": [people], "seg": id, "stage" 1|2,
## "fixer": id, "state": "idle"|"walking"|"working", "cost": {"scrap": n}} and what the module keeps of it: "late" (the damage is done), "call" (the stage-2
## call's id, 0 none), "tried" (who has failed it), "wait" / "ord" / "left" / "walked" / "chance" (the delegate's delay, spot, work seconds, time on the
## way and chance). Saved.
## Events: {"type": "problem", "state": "raised"|"stage2"|"fixed"|"failed"|"escalated", "id", "kind"} ("fixed" also says "how": fixed | settled | apart),
## {"type": "fix_work", "on": bool, "id", "who", ...} (a person's hands at it begin or end: `why`, `line`, `warn` when they end), "hammer" at each stroke,
## "radio_line" (the delegate's answer) and "bark". News kind "problem": raised, fixed, failed, escalated, the delegates' lines.
extends RefCounted

const Lots := preload("res://scripts/sim/lots.gd")

const DATA_PATH := "res://assets/data/problems.json"
const KINDS := ["leak", "jam", "quarrel", "crack"]
const FIRST_DAY := 3
const MAX_OPEN := 2
const TTL_H := {"leak": 18.0, "jam": 12.0, "quarrel": 24.0, "crack": 14.0}
const FIX_REACH := 1.8
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0
## A problem is raised from this hour to DUSK_MARGIN_H before dusk.
const FROM_H := 7.5
const DUSK_MARGIN_H := 2.0
## The stage-2 call waits this long (game minutes) before it takes "Leave it".
const CALL_TTL_MIN := 240.0
## The first problem comes within this many game minutes of the morning of FIRST_DAY.
const FIRST_WINDOW_MIN := 240.0
## Seconds between two strokes of a hammer, and how close to its spot a person must stand to be at work.
const HAMMER_EVERY := 0.45
const ARRIVE := 0.6
const EPS := 1.0e-6
## A save holds at most this many records.
const MAX_RECORDS := 4
const STATES := ["idle", "walking", "working"]
const NO_PROBLEM := "Nothing here to fix"

var sim
var enabled := true
## Saved. The open problems (records), how many have been raised, the game minute before which none is raised (0: not scheduled yet), and the kinds of
## the last two raised (never three of a kind running).
var records: Array = []
var count := 0
var next_at := 0.0
var recent: Array = []
## What the avatar's own hands are fixing now: {"id", "left" (rules seconds), "total", "who", "kind", "hp0", "hammer"}, {} when nothing. Never resumed
## from a save.
var fixing := {}

var _acc := 0.0
var _data: Dictionary = {}
var _barrels: Array = []
var _barrels_read := false


func setup(s) -> void:
	sim = s


func start() -> void:
	records = []
	count = 0
	next_at = 0.0
	recent = []
	fixing = {}
	_acc = 0.0


func person_added(_p) -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


# ------------------------------------------------------------------------- the data --

func _data_all() -> Dictionary:
	if not _data.is_empty():
		return _data
	if not FileAccess.file_exists(DATA_PATH):
		push_error("Could not find %s" % DATA_PATH)
		return _data
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("Could not read the problems from %s" % DATA_PATH)
	return _data


func _kd(kind: String) -> Dictionary:
	var ks = _data_all().get("kinds", {})
	if ks is Dictionary:
		var k = (ks as Dictionary).get(kind, {})
		return k if k is Dictionary else {}
	return {}


## A number of a kind (`fallback` when the file has none).
func _kf(kind: String, key: String, fallback: float = 0.0) -> float:
	var v = _kd(kind).get(key, fallback)
	return float(v) if _num(v) else fallback


func _ks(kind: String, key: String) -> String:
	return String(_kd(kind).get(key, ""))


## A number of a group of the file ("speed", "delegate", "pair").
func _gf(group: String, key: String, fallback: float) -> float:
	var g = _data_all().get(group, {})
	if g is Dictionary:
		var v = (g as Dictionary).get(key, fallback)
		return float(v) if _num(v) else fallback
	return fallback


## The deterministic dice of the schedule: 0.0 to 0.999 from the run's seed and two numbers. No `sim.rng`.
func _h(tag: String, a: int, b: int) -> float:
	return float(("%s|%d|%d|%d" % [tag, int(sim.run_seed), a, b]).hash() % 1000) / 1000.0


# ------------------------------------------------------------------------ the people --

func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## Alive, up and at the base.
func _here(p) -> bool:
	return p != null and not (p.dead or p.turned or p.downed) and p.away == null


func _is_player(p) -> bool:
	return p.player or String(p.id) == String(sim.player_id)


func _first(id: String) -> String:
	var p = _person(id)
	return String(p.first) if p != null else id


## Why the avatar cannot use its hands now ("" when it can).
func _cannot(p) -> String:
	if p.dead or p.turned:
		return "You are gone"
	if p.downed:
		return "You are down"
	if p.away != null:
		return "You are away"
	return ""


# ----------------------------------------------------------------------------- time --

## The game minute (`clock_min`) of `hour` on `day` (day 1, 07:00 is 0).
static func _day_clock(day: int, hour: float) -> float:
	return float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)


func _elapsed_h(r: Dictionary) -> float:
	return maxf(0.0, (float(sim.clock_min) - float(r.t0)) / 60.0)


## Why nothing can be done at a problem now ("" when it can): the night (from the bell to the day), or the dead at the wall by day.
func _blocked_now() -> String:
	if String(sim.phase) != "day" or bool(sim.bell_rung):
		return "it is night"
	if sim.radio.alarm_on or sim.threat_by_day():
		return "the dead are at the wall"
	return ""


# ----------------------------------------------------------------------------- stepping --

func update(dt: float) -> void:
	if not active():
		if not fixing.is_empty():
			fixing = {}
		return
	if not fixing.is_empty():
		_fix_step(dt)
	if not records.is_empty():
		_walk_step(dt)
		_effects(dt)
	_acc += dt
	if _acc < TICK_S:
		return
	_acc -= TICK_S
	look()


## What an open problem does every step: a leak drains the barrels, a crack widens.
func _effects(dt: float) -> void:
	var hours: float = sim.game_hours(dt)
	for r in records:
		match String(r.kind):
			"leak":
				var rate := _kf("leak", "drain_h") * (_kf("leak", "late_drain_mult", 1.0) if bool(r.late) else 1.0)
				sim.stock.water = maxf(0.0, float(sim.stock.water) - rate * hours)
			"crack":
				var seg = _segment(int(r.seg))
				if seg == null or int(seg.state) == 3:
					continue
				var floor_hp: float = _kf("crack", "floor_pct") * float(seg.max_hp)
				if float(seg.hp) > floor_hp:
					sim._damage_segment(seg, minf(float(seg.hp) - floor_hp, _kf("crack", "widen_pct") * float(seg.max_hp) * hours))


## One slow look (30 game minutes): the people and sections that are gone, each problem's age (stage 2, past its time, a quarrel's drift), the stage-2
## calls that are due, and a new problem when the schedule allows one.
func look() -> void:
	if not active():
		return
	_tidy()
	for r in records.duplicate():
		_age(r)
	_call_ups()
	if next_at <= 0.0:
		next_at = _first_at()
	if allowed_now():
		raise_problem(pick_kind())


## The first problem of a run comes within FIRST_WINDOW_MIN of the morning of FIRST_DAY (a game that begins after it: within that of now).
func _first_at() -> float:
	return maxf(float(sim.clock_min), _day_clock(FIRST_DAY, FROM_H)) + FIRST_WINDOW_MIN * _h("first", FIRST_DAY, 0)


## Problems whose people are gone, or whose wall is down, end quietly.
func _tidy() -> void:
	for r in records.duplicate():
		var gone := false
		if String(r.kind) == "quarrel":
			for id in r.ids:
				var q = _person(String(id))
				if q == null or q.dead or q.turned:
					gone = true
		elif String(r.kind) == "crack":
			var seg = _segment(int(r.seg))
			gone = seg == null or int(seg.state) == 3
		if gone:
			_release(r)
			_remove(r)
			_close_call(r, "It is over")


func _age(r: Dictionary) -> void:
	var el := _elapsed_h(r)
	var ttl := float(r.ttl_h)
	if int(r.stage) < 2 and el >= ttl * 0.5:
		r.stage = 2
		sim.events.append({"type": "problem", "state": "stage2", "id": String(r.id), "kind": String(r.kind)})
	if not bool(r.late) and el >= ttl:
		_escalate(r)
	if String(r.kind) == "quarrel" and r.ids.size() == 2:
		sim.relations.add(_person(String(r.ids[0])), _person(String(r.ids[1])), _kf("quarrel", "drift"), "They are quarrelling")


## Past its time: the damage of its kind, once. The problem stays open.
func _escalate(r: Dictionary) -> void:
	r.late = true
	var kind := String(r.kind)
	var sub := _ks(kind, "late_sub")
	match kind:
		"leak":
			sim.stock.water = maxf(0.0, float(sim.stock.water) - _kf("leak", "late_water"))
		"jam":
			r.cost = {"scrap": int(_kf("jam", "late_scrap"))}
			sim.morale.shock(null, _kf("jam", "late_mood"), _ks("jam", "late_mood_label"))
		"quarrel":
			var a = _person(String(r.ids[0]))
			var b = _person(String(r.ids[1]))
			sim.relations.add(a, b, _kf("quarrel", "late_rift"), "The quarrel went too far")
			sim.morale.shock(a, _kf("quarrel", "late_mood"), _ks("quarrel", "late_mood_label"))
			sim.morale.shock(b, _kf("quarrel", "late_mood"), _ks("quarrel", "late_mood_label"))
			sub = sub % [String(a.first), String(b.first)]
		"crack":
			var seg = _segment(int(r.seg))
			if seg != null:
				var floor_hp: float = _kf("crack", "late_floor_pct") * float(seg.max_hp)
				var cut: float = minf(_kf("crack", "late_pct") * float(seg.max_hp), maxf(0.0, float(seg.hp) - floor_hp))
				sim._damage_segment(seg, cut)
				sub = sub % String(seg.name).to_lower()
			else:
				sub = ""
	sim.radio.log_news("problem", _ks(kind, "late_news"), sub, {"data": {"problem": String(r.id), "kind": kind}, "at": _at_of(r)})
	sim.events.append({"type": "problem", "state": "escalated", "id": String(r.id), "kind": kind})


# --------------------------------------------------------------------------- the rate --

## Game hours between two problems on this day: about one every 1.5 days in the first week, one a day by day 18.
func gap_h(day: int) -> float:
	return clampf(36.0 - 1.2 * float(day - 3), 18.0, 36.0)


## Whether a problem may be raised now: from FIRST_DAY, from 07:30 to two hours before dusk, not in the radio's noon hour, never under the alarm,
## with the dead at the wall by day, in the night, with an urgent call open (a call of any kind but "idea" and "problem"), with MAX_OPEN open, or
## before `next_at`.
func allowed_now() -> bool:
	if not active() or int(sim.day) < FIRST_DAY or String(sim.phase) != "day":
		return false
	var h: float = sim.hour
	if h < FROM_H or h > float(sim.seasons.dusk_hour()) - DUSK_MARGIN_H:
		return false
	if h >= float(sim.radio.RADIO_FROM_H) and h <= float(sim.radio.RADIO_TO_H):
		return false
	if sim.radio.alarm_on or sim.threat_by_day() or _urgent_call_open():
		return false
	return records.size() < MAX_OPEN and float(sim.clock_min) >= next_at


func _urgent_call_open() -> bool:
	for e in sim.radio.open_calls():
		var kind := String(e.kind)
		if kind != "idea" and kind != "problem":
			return true
	return false


## PURE rotation: the kinds in order starting at (day x 5 + count x 3) mod 4, the first eligible, never the same kind three times running. "" when none.
func pick_kind() -> String:
	var start := posmod(int(sim.day) * 5 + count * 3, KINDS.size())
	for i in KINDS.size():
		var kind: String = KINDS[(start + i) % KINDS.size()]
		if recent.size() >= 2 and String(recent[recent.size() - 1]) == kind and String(recent[recent.size() - 2]) == kind:
			continue
		if _eligible(kind):
			return kind
	return ""


func _eligible(kind: String) -> bool:
	match kind:
		"leak":
			return not has_open("leak") and float(sim.stock.water) > 0.0 and not _barrel_spots().is_empty()
		"jam":
			return not has_open("jam") and String(sim.storyteller.blackout_state()) == ""
		"quarrel":
			return not quarrel_pair().is_empty()
		"crack":
			return _crack_target() != null
	return false


## The rain barrels, where the water leaks from (`rainbarrel` objects of the map).
func _barrel_spots() -> Array:
	if not _barrels_read:
		_barrels_read = true
		for o in sim.d.objects:
			if String(o.kind) == "rainbarrel":
				_barrels.append(Vector2(float(o.cx), float(o.cy)))
	return _barrels


func _segment(id: int):
	if id < 0 or id >= Lots.FIRST_SEGMENT_ID:
		return null
	for s in sim.segments:
		if int(s.id) == id:
			return s
	return null


func _cracked(seg_id: int) -> bool:
	for r in records:
		if String(r.kind) == "crack" and int(r.seg) == seg_id:
			return true
	return false


## The wall section the next crack is in: the compound's own sections that are not a door or the gate, still standing and sound, not already cracked,
## (day x 7 + count) mod n of them. null when none.
func _crack_target():
	var list: Array = []
	for s in sim.segments:
		if int(s.id) >= Lots.FIRST_SEGMENT_ID or String(s.kind) == String(sim.DOOR_KIND) or String(s.kind) == "gate" or int(s.state) == 3:
			continue
		if float(s.hp) < _kf("crack", "min_hp_pct", 0.7) * float(s.max_hp) or _cracked(int(s.id)):
			continue
		list.append(s)
	if list.is_empty():
		return null
	return list[posmod(int(sim.day) * 7 + count, list.size())]


## The best pair for a quarrel, the one who stays (the better leader, then the smaller id) first, or [] when none reaches the score. S = max(0, 15 -
## affinity) + 10 (the same station) + 5 (night posts within 6 tiles) + 8 (a friction pair of chemistry.json) + 6 (either is hungry or thirsty); the best
## S of 30 or more among the living at the base who are not the player and not in a quarrel already, ties by ids. Pure.
func quarrel_pair() -> Array:
	var best: Array = []
	var best_s := _gf("pair", "need", 30.0) - 1.0
	var here: Array = []
	for q in sim.people:
		if _here(q) and not _is_player(q) and not _in_quarrel(String(q.id)):
			here.append(q)
	here.sort_custom(func(a, b): return String(a.id) < String(b.id))
	for i in here.size():
		for j in range(i + 1, here.size()):
			var s := _pair_score(here[i], here[j])
			if s > best_s + 1.0e-9:
				best_s = s
				best = [here[i], here[j]]
	if best.is_empty():
		return best
	var la := int(best[0].skills.get("Leading", 0))
	var lb := int(best[1].skills.get("Leading", 0))
	if lb > la:
		best = [best[1], best[0]]
	return best


func _in_quarrel(id: String) -> bool:
	for r in records:
		if String(r.kind) == "quarrel" and (r.ids as Array).has(id):
			return true
	return false


func _pair_score(a, b) -> float:
	var s := maxf(0.0, _gf("pair", "affinity_base", 15.0) - float(sim.relations.affinity(a, b)))
	var job: String = sim.jobs.job_of(a)
	if job != "" and job == sim.jobs.job_of(b):
		s += _gf("pair", "station", 10.0)
	var pa: Dictionary = sim.jobs.post(String(sim.jobs.post_ids.get(String(a.id), "")))
	var pb: Dictionary = sim.jobs.post(String(sim.jobs.post_ids.get(String(b.id), "")))
	if not pa.is_empty() and not pb.is_empty() and Vector2(pa.pos).distance_to(Vector2(pb.pos)) <= _gf("pair", "post_tiles", 6.0):
		s += _gf("pair", "post", 5.0)
	if sim.relations.has_method("_chem_terms") and float(sim.relations._chem_terms(a, b).get("d", 0.0)) < 0.0:
		s += _gf("pair", "friction", 8.0)
	if _wanting(a) or _wanting(b):
		s += _gf("pair", "hungry", 6.0)
	return s


func _wanting(p) -> bool:
	return p.hunger_h >= sim.supplies.HUNGRY_H or p.thirst_h >= sim.supplies.THIRSTY_H


# -------------------------------------------------------------------------- raising --

## Raises a problem of this kind now (no schedule: the look's own `raise_problem(pick_kind())` and the tests' way in). The id of the record, or "" when it
## cannot be (the module is not active, the kind is not eligible, a record too many).
func raise_problem(kind: String) -> String:
	if not active() or not KINDS.has(kind) or records.size() >= MAX_RECORDS:
		return ""
	var r := _make(kind)
	if r.is_empty():
		return ""
	count += 1
	records.append(r)
	recent.append(kind)
	while recent.size() > 2:
		recent.pop_front()
	var day := int(sim.day)
	next_at = float(sim.clock_min) + gap_h(day) * 60.0 * (_gf("gap", "from", 0.7) + _gf("gap", "span", 0.4) * _h("gap", day, count))
	var words := _raise_words(r)
	sim.radio.log_news("problem", String(words.text), String(words.sub), {"data": {"problem": String(r.id), "kind": kind}, "at": _at_of(r)})
	sim.events.append({"type": "problem", "state": "raised", "id": String(r.id), "kind": kind})
	_bark(r)
	return String(r.id)


## The record of a new problem of this kind ({} when it cannot be made). Does not change the module.
func _make(kind: String) -> Dictionary:
	var r := {
		"id": "p%d" % (count + 1), "kind": kind, "day": int(sim.day), "t0": float(sim.clock_min), "ttl_h": float(TTL_H[kind]), "at": Vector2.ZERO,
		"label": _ks(kind, "name"), "ids": [], "seg": -1, "stage": 1, "fixer": "", "state": "idle", "cost": {}, "late": false, "call": 0,
		"tried": [], "wait": 0.0, "left": 0.0, "chance": 0.0, "walked": 0.0, "ord": [],
	}
	var scrap := int(_kf(kind, "scrap"))
	if scrap > 0:
		r.cost = {"scrap": scrap}
	match kind:
		"leak":
			var spots := _barrel_spots()
			if spots.is_empty():
				return {}
			r.at = spots[posmod(int(sim.day) + count, spots.size())]
		"jam":
			r.at = sim.storyteller.GENERATOR
		"quarrel":
			var pair := quarrel_pair()
			if pair.size() < 2:
				return {}
			r.ids = [String(pair[0].id), String(pair[1].id)]
			r.at = (Vector2(pair[0].x, pair[0].y) + Vector2(pair[1].x, pair[1].y)) * 0.5
		"crack":
			var seg = _crack_target()
			if seg == null:
				return {}
			r.seg = int(seg.id)
			r.at = sim.repair_spot(seg)
			r.label = "the cracked %s" % String(seg.name).to_lower()
	return r


## The News line of a new problem and its second line (where, and how long it can wait).
func _raise_words(r: Dictionary) -> Dictionary:
	var kind := String(r.kind)
	var text := _ks(kind, "raise")
	var where := _ks(kind, "where")
	match kind:
		"quarrel":
			text = text % [_first(String(r.ids[0])), _first(String(r.ids[1]))]
		"crack":
			var seg = _segment(int(r.seg))
			text = text % (String(seg.name).to_lower() if seg != null else "wall")
		"jam":
			if sim.build.built("floodlights"):
				where += ", and the floodlights are dark"
	return {"text": text, "sub": "%s. It can wait about %d hours." % [where, roundi(float(r.ttl_h))]}


## Somebody near it says so: the nearest person who is up (a quarrel: the one who moves, about the other).
func _bark(r: Dictionary) -> void:
	var kind := String(r.kind)
	var who = null
	var text := _ks(kind, "bark")
	if kind == "quarrel":
		who = _person(String(r.ids[1]))
		text = text % _first(String(r.ids[0]))
	else:
		var best_d := 1.0e9
		for q in sim.people:
			if not _here(q) or _is_player(q):
				continue
			var d := Vector2(q.x, q.y).distance_to(_at_of(r))
			if d < best_d - 1.0e-9:
				best_d = d
				who = q
	if who != null and text != "":
		sim.events.append({"type": "bark", "who": String(who.id), "text": text, "context": "problem"})


## The stage-2 call, once, for each problem that has reached stage 2 with nobody on it: in the day and not under the alarm.
func _call_ups() -> void:
	if _blocked_now() != "":
		return
	for r in records:
		if int(r.stage) >= 2 and int(r.call) == 0 and String(r.fixer) == "":
			_raise_call(r)


func _raise_call(r: Dictionary) -> void:
	var kind := String(r.kind)
	var id := String(r.id)
	var opts: Array = []
	var best = best_for(id)
	if best != null:
		var w := _willing(best, r, false)
		opts.append({"id": "send", "label": "Send %s (%d%%)" % [String(best.first), roundi(float(w.chance) * 100.0)]})
	if kind == "quarrel":
		opts.append({"id": "apart", "label": "Keep them apart"})
	opts.append({"id": "leave", "label": "Leave it"})
	var left_min := maxf(60.0, (float(r.ttl_h) - _elapsed_h(r)) * 60.0)
	var sub := _ks(kind, "worse_sub")
	if kind == "quarrel":
		sub = sub % [_first(String(r.ids[0])), _first(String(r.ids[1]))]
	elif kind == "crack":
		var seg = _segment(int(r.seg))
		sub = sub % (String(seg.name).to_lower() if seg != null else "wall")
	r.call = sim.radio.raise_call("problem", _ks(kind, "worse"), sub, opts, "leave", minf(left_min, CALL_TTL_MIN), {"problem": id, "kind": kind}, _at_of(r))


## Settles the stage-2 call of a problem that is over, if it still waits, with what became of it.
func _close_call(r: Dictionary, result: String) -> void:
	var cid := int(r.get("call", 0))
	if cid <= 0:
		return
	for e in sim.radio.open_calls():
		if int(e.id) == cid:
			sim.radio.answer(cid, "leave")
			e["result"] = result
			return


# ---------------------------------------------------------------------------- reading --

## The open problems (copies), [] when the module is not active.
func open() -> Array:
	if records.is_empty() or not active():
		return []
	return records.duplicate(true)


## The record of this problem (a copy), {} when there is none.
func record(id) -> Dictionary:
	var r := _rec(id)
	return r.duplicate(true) if not r.is_empty() else {}


## The live record (never a copy), {} when there is none.
func _rec(id) -> Dictionary:
	for r in records:
		if String(r.id) == String(id):
			return r
	return {}


func has_open(kind) -> bool:
	if records.is_empty() or not active():
		return false
	for r in records:
		if String(r.kind) == String(kind):
			return true
	return false


## Where the marker is: a quarrel's is the middle of the two, as they stand now.
func _at_of(r: Dictionary) -> Vector2:
	if String(r.kind) == "quarrel":
		var pts: Array = []
		for id in r.ids:
			var q = _person(String(id))
			if _here(q):
				pts.append(Vector2(q.x, q.y))
		if pts.size() == 2:
			return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
		if pts.size() == 1:
			return pts[0]
	return Vector2(r.at)


## For the views: [{"id", "kind", "at", "label" ("Leak: 11 h left"), "stage", "pct" (the time used, 0 to 1), "state"}] and what else they may want
## ("ids", "fixer", "late", "glyph"). [] when the module is not active.
func marks() -> Array:
	var out: Array = []
	if records.is_empty() or not active():
		return out
	for r in records:
		var kind := String(r.kind)
		var el := _elapsed_h(r)
		var ttl := float(r.ttl_h)
		var left := ttl - el
		var label := ("%s: %d h left" % [_ks(kind, "short"), ceili(left)]) if left > 0.0 else "%s: %s" % [_ks(kind, "short"), _ks(kind, "late_label")]
		var state := "working" if String(fixing.get("id", "")) == String(r.id) else String(r.state)
		out.append({
			"id": String(r.id), "kind": kind, "at": _at_of(r), "label": label, "stage": int(r.stage), "pct": clampf(el / maxf(ttl, 1.0), 0.0, 1.0),
			"state": state, "ids": (r.ids as Array).duplicate(), "fixer": String(r.fixer), "late": bool(r.late), "glyph": _ks(kind, "glyph"),
		})
	return out


## How far the avatar's own hands have got (0 to 1), 0.0 when they are at nothing.
func fix_pct() -> float:
	if fixing.is_empty():
		return 0.0
	return clampf(1.0 - float(fixing.left) / maxf(float(fixing.total), EPS), 0.0, 1.0)


# --------------------------------------------------------------------- in person (E) --

## interact.candidates(): [{"kind": "problem", "id", "label" ("Fix the leak", "Clear the jam", "Shore up the crack", "Hear them out"), "pos", "dist", "ok",
## "why"}] for each problem whose marker is within FIX_REACH of the avatar's feet; the one in hand is "Stop ...". [] when nothing is in reach.
func candidates() -> Array:
	var out: Array = []
	if records.is_empty() or not active():
		return out
	var p = _lead()
	if p == null or _cannot(p) != "":
		return out
	var me := Vector2(p.x, p.y)
	for r in records:
		var at := _at_of(r)
		var d := me.distance_to(at)
		if d > FIX_REACH:
			continue
		var kind := String(r.kind)
		var id := String(r.id)
		if String(fixing.get("id", "")) == id:
			out.append({"kind": "problem", "id": id, "label": _ks(kind, "stop"), "pos": at, "dist": d, "ok": true, "why": ""})
			continue
		var why := _why_not_hands(p, r, false)
		out.append({"kind": "problem", "id": id, "label": _ks(kind, "verb"), "pos": at, "dist": d, "ok": why == "", "why": why})
	out.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	return out


## Why the avatar cannot start on this problem now ("" when it can). `strict` adds what only a press of the key asks: a hand on the keys or the trigger,
## and the dead at its back.
func _why_not_hands(p, r: Dictionary, strict: bool) -> String:
	var gone := _cannot(p)
	if gone != "":
		return gone
	var kind := String(r.kind)
	var blocked := _blocked_now()
	if blocked != "":
		return blocked
	var fixer := String(r.fixer)
	if fixer != "" and String(r.state) != "idle":
		return "%s is on it" % _first(fixer)
	var at := _at_of(r)
	if Vector2(p.x, p.y).distance_to(at) > FIX_REACH:
		return "Too far away"
	if kind == "quarrel":
		for id in r.ids:
			if not _here(_person(String(id))):
				return "They are not both here"
	else:
		var level: String = sim.levels.why_not(p, at)
		if level != "":
			return level
	var scrap := int((r.cost as Dictionary).get("scrap", 0))
	if scrap > 0 and float(sim.stock.scrap) < float(scrap):
		return "needs %d scrap" % scrap
	if strict:
		if p.input_move.length() > sim.interact.HANDS_ON or p.input_fire:
			return "Stand still to work"
		if kind != "quarrel" and sim.nights != null and sim.nights.has_method("_danger_near") and sim.nights._danger_near(p):
			return "One of the dead is on you"
	return ""


## E at a problem: starts the avatar's own hands at it, or stops them (E again). {"ok", "line", "why", "seconds"} (and "stopped").
func use(cand := {}) -> Dictionary:
	if not active():
		return {"ok": false, "line": "", "why": NO_PROBLEM}
	var p = _lead()
	if p == null:
		return {"ok": false, "line": "", "why": "You are not here"}
	var id := String(cand.get("id", ""))
	if id == "":
		var list := candidates()
		id = String(list[0].id) if not list.is_empty() else ""
	var r := _rec(id)
	if r.is_empty():
		return {"ok": false, "line": "", "why": NO_PROBLEM}
	var kind := String(r.kind)
	if String(fixing.get("id", "")) == id:
		_end_fix("stopped")
		return {"ok": true, "line": "Stopped: %s." % _ks(kind, "doing").to_lower(), "why": "", "stopped": true}
	var why := _why_not_hands(p, r, true)
	if why != "":
		return {"ok": false, "line": "", "why": why}
	if not fixing.is_empty():
		_end_fix("stopped")
	# the hands are at one thing: a bench session in hand and a wall being mended stop
	if String(sim.interact.working) == "bench":
		sim.interact.stop_work("stopped")
	if sim.nights != null and String(sim.nights.working) == "wall":
		sim.nights.stop_mend("stopped")
	var secs := _work_s(p, r)
	fixing = {"id": id, "left": secs, "total": secs, "who": String(p.id), "kind": kind, "hp0": float(p.hp), "hammer": 0.0}
	p.work = _ks(kind, "pose")
	p.work_t = 0.0
	p.activity = _ks(kind, "doing")
	sim.events.append({"type": "fix_work", "on": true, "id": id, "who": String(p.id)})
	return {"ok": true, "line": "%s." % _ks(kind, "doing"), "why": "", "seconds": secs}


## Rules seconds a person's hands need at this problem: the kind's seconds over their skill's speed (and the traits', the title's, how well they are).
## A wrecked generator takes twice as long.
func _work_s(p, r: Dictionary) -> float:
	var kind := String(r.kind)
	var skill_name := _ks(kind, "skill")
	var speed := _gf("speed", "base", 0.7) + _gf("speed", "per_skill", 0.08) * float(p.skills.get(skill_name, 0))
	if skill_name == "Building":
		speed *= float(sim.traits.mult(p, "repair"))
	speed *= clampf(float(sim.perf(p)), 0.3, 1.0)
	speed = clampf(speed, _gf("speed", "min", 0.25), _gf("speed", "max", 1.6))
	var secs := _kf(kind, "base_s", 6.0) / speed
	if bool(r.late) and kind == "jam":
		secs *= _kf("jam", "late_time_mult", 1.0)
	return secs


## One step of the avatar's hands, after the people have moved (the people loop has cleared the pose).
func _fix_step(dt: float) -> void:
	var p = _lead()
	var r := _rec(String(fixing.id))
	if p == null or r.is_empty():
		_end_fix("the problem is gone" if p != null else "no avatar")
		return
	if String(fixing.who) != String(p.id):
		_end_fix("another player")
		return
	var gone := _cannot(p)
	if gone != "":
		_end_fix(gone)
		return
	fixing["hp0"] = maxf(float(fixing.hp0), float(p.hp))
	var kind := String(r.kind)
	var why := ""
	if p.input_move.length() > sim.interact.HANDS_ON or Vector2(p.x, p.y).distance_to(_at_of(r)) > FIX_REACH + 0.5:
		why = "moved"
	elif p.input_fire:
		why = "fired"
	elif float(p.hp) < float(fixing.hp0) - 0.001:
		why = "hurt"
	elif _blocked_now() != "":
		why = "night" if _blocked_now() == "it is night" else "alarm"
	elif kind != "quarrel" and sim.nights != null and sim.nights.has_method("_danger_near") and sim.nights._danger_near(p):
		why = "danger"
	elif kind == "quarrel" and (not _here(_person(String(r.ids[0]))) or not _here(_person(String(r.ids[1])))):
		why = "gone"
	elif int((r.cost as Dictionary).get("scrap", 0)) > 0 and float(sim.stock.scrap) < float((r.cost as Dictionary).scrap):
		why = "no scrap"
	if why != "":
		_end_fix(why)
		return
	fixing["left"] = float(fixing.left) - dt
	if kind != "quarrel":
		fixing["hammer"] = float(fixing.hammer) - dt
		if float(fixing.hammer) <= 0.0:
			fixing["hammer"] = HAMMER_EVERY
			sim.events.append({"type": "hammer", "x": p.x, "y": p.y})
	if float(fixing.left) <= EPS:
		_finish_own(p, r)
		return
	p.work = _ks(kind, "pose")
	p.work_t = float(fixing.total) - float(fixing.left)
	p.activity = _ks(kind, "doing")
	var to := _at_of(r) - Vector2(p.x, p.y)
	if to.length() > 0.3:
		p.facing = sim.facing_of(to.x, to.y, String(p.facing))


## The avatar's hands have done: the scrap is paid and the problem is resolved (a quarrel by its score: settled, "they keep apart", or no luck).
func _finish_own(p, r: Dictionary) -> void:
	var kind := String(r.kind)
	var scrap := int((r.cost as Dictionary).get("scrap", 0))
	if scrap > 0:
		if float(sim.stock.scrap) < float(scrap):
			_end_fix("no scrap")
			return
		sim.stock.scrap = float(sim.stock.scrap) - float(scrap)
	_end_fix("done")
	if kind != "quarrel":
		_credit(p, kind)
		_resolve(r, "fixed", p)
		return
	var a = _person(String(r.ids[0]))
	var b = _person(String(r.ids[1]))
	var score := _quarrel_score(p, a, b)
	if score >= _gf_score("settle"):
		_settle(r, a, b, p)
	elif score >= _gf_score("apart"):
		_keep_apart(r, a, b, p)
	else:
		r.ttl_h = float(r.ttl_h) + _kf("quarrel", "fail_hours")
		sim.radio.add_trust(a, _kf("quarrel", "fail_trust"), "You could not settle their quarrel")
		sim.radio.add_trust(b, _kf("quarrel", "fail_trust"), "You could not settle their quarrel")
		sim.radio.log_news("problem", _ks("quarrel", "fail") % String(p.first), "%s and %s would not hear it. They have six more hours." % [String(a.first), String(b.first)], {"data": {"problem": String(r.id), "kind": kind}, "at": _at_of(r)})
		sim.events.append({"type": "problem", "state": "failed", "id": String(r.id), "kind": kind})


func _gf_score(key: String) -> float:
	var sc = _kd("quarrel").get("score", {})
	return float((sc as Dictionary).get(key, 1.0)) if sc is Dictionary else 1.0


## How well a hearing goes: 0.1 x the listener's Leading, the two's trust in the leader over 100, and 0.2 when they share a friend. 1.0 settles it, 0.6
## keeps them apart, less is no luck.
func _quarrel_score(listener, a, b) -> float:
	var sc = _kd("quarrel").get("score", {})
	var per_leading := float((sc as Dictionary).get("per_leading", 0.1)) if sc is Dictionary else 0.1
	var per_trust := float((sc as Dictionary).get("per_trust", 0.01)) if sc is Dictionary else 0.01
	var friend := float((sc as Dictionary).get("friend", 0.2)) if sc is Dictionary else 0.2
	var s := per_leading * float(listener.skills.get("Leading", 0)) + per_trust * (float(a.trust) + float(b.trust)) * 0.5
	if _share_friend(a, b):
		s += friend
	return s


func _share_friend(a, b) -> bool:
	for f in sim.relations.friends_of(a):
		if f != b and sim.relations.friends_of(b).has(f):
			return true
	return false


func _settle(r: Dictionary, a, b, by) -> void:
	sim.relations.add(a, b, _kf("quarrel", "settle_gain"), "They talked it out")
	_resolve(r, "settled", by, _ks("quarrel", "done") + " (%s)" % String(by.first), _ks("quarrel", "done_sub") % [String(a.first), String(b.first)])


## "They keep apart": the second of the pair is moved away from the first; no gain between them, a small blow to each mood. Ends the problem.
func _keep_apart(r: Dictionary, a, b, by) -> String:
	var plan := _apart_plan(a, b)
	var line := _apply_apart(plan, a, b)
	var label := _ks("quarrel", "apart_label")
	sim.morale.shock(a, _kf("quarrel", "apart_mood"), label)
	sim.morale.shock(b, _kf("quarrel", "apart_mood"), label)
	_resolve(r, "apart", by, "Kept apart: %s and %s" % [String(a.first), String(b.first)], line)
	return line


## Ends the avatar's hands (the key again, walking, the trigger, a wound, the dusk, the scrap gone, the end of the seconds): says why.
func _end_fix(why: String) -> void:
	if fixing.is_empty():
		return
	var id := String(fixing.id)
	var kind := String(fixing.kind)
	var p = _lead()
	fixing = {}
	if p != null and (p.work == "hammer" or String(p.activity) == _ks(kind, "doing")):
		p.work = ""
		p.work_t = 0.0
	var words := _stop_words(why, kind)
	sim.events.append({"type": "fix_work", "on": false, "id": id, "why": why, "line": String(words.line), "warn": bool(words.warn)})


## What to tell the player when the hands have left a problem: {"line", "warn"}.
func _stop_words(why: String, kind: String) -> Dictionary:
	var doing := _ks(kind, "doing").to_lower()
	match why:
		"moved":
			return {"line": "You moved: stopped %s" % doing, "warn": false}
		"fired":
			return {"line": "Stopped %s to shoot" % doing, "warn": false}
		"hurt":
			return {"line": "Hurt: stopped %s" % doing, "warn": true}
		"danger":
			return {"line": "The dead are on you: stopped %s" % doing, "warn": true}
		"night":
			return {"line": "Night has fallen: stopped %s" % doing, "warn": false}
		"alarm":
			return {"line": "The dead are at the wall: stopped %s" % doing, "warn": true}
		"no scrap":
			return {"line": "No scrap left: stopped %s" % doing, "warn": true}
		"gone":
			return {"line": "They have gone: stopped %s" % doing, "warn": false}
		"You are down", "You are gone", "You are away":
			return {"line": "%s: stopped %s" % [why, doing], "warn": true}
	return {"line": "", "warn": false}


## A fix is a little practice: a Building fix counts toward a point of Building; the counters of what was mended are not touched.
func _credit(p, kind: String) -> void:
	if p == null or _ks(kind, "skill") != "Building":
		return
	var before: Dictionary = p.stats.duplicate()
	sim.skills.credit(p, "mended", 20.0)
	p.stats = before


## The problem is over: it goes, the News says so, every mood lifts a little (a "settled" and a "fixed"; "apart" has its own blows), the stage-2 call
## is closed. `text` and `sub` default to the kind's.
func _resolve(r: Dictionary, how: String, by = null, text := "", sub := "") -> void:
	var kind := String(r.kind)
	var id := String(r.id)
	_release(r)
	_remove(r)
	if text == "":
		text = _ks(kind, "done")
		if by != null:
			text += " (%s)" % String(by.first)
	if sub == "":
		sub = _ks(kind, "done_sub")
		if kind == "quarrel":
			sub = sub % [_first(String(r.ids[0])), _first(String(r.ids[1]))]
	sim.radio.log_news("problem", text, sub, {"data": {"problem": id, "kind": kind}, "at": _at_of(r)})
	sim.events.append({"type": "problem", "state": "fixed", "id": id, "kind": kind, "how": how})
	if how != "apart":
		var lift = _data_all().get("fixed_mood", 1.0)
		sim.morale.shock(null, float(lift) if _num(lift) else 1.0, _ks(kind, "done"))
	_close_call(r, text)


func _remove(r: Dictionary) -> void:
	var i := records.size() - 1
	while i >= 0:
		if String(records[i].id) == String(r.id):
			records.remove_at(i)
		i -= 1


# -------------------------------------------------------------------------- by radio --

## Whether this person would go and fix this problem: {"ok", "why" (the reason, "" when ok), "hard" (nobody can argue with it), "line" (what they say), "tone"
## ("willing", "grudging", "doubtful" or "refused"), "delay_s" (the radio's delay by their trust, plus the walk), "chance", "cost" ({"scrap": n}), "eta_h" (the
## work, game hours, at their skill)}. The radio's own reasons first (`reason_not(p, "work")`: the same words as everywhere), then what the problem asks.
## Pure.
func fix_willingness(p, problem_id) -> Dictionary:
	var r := _rec(problem_id)
	if r.is_empty() or not active():
		return _refusal(NO_PROBLEM, "", true)
	return _willing(p, r, false)


func _refusal(why: String, line: String, hard: bool) -> Dictionary:
	return {"ok": false, "why": why, "hard": hard, "line": line, "tone": "refused", "delay_s": 0.0, "chance": 0.0, "cost": {}, "eta_h": 0.0}


## `force`: a soft reason of the radio is pushed past (an Insist): they go with a doubtful word.
func _willing(p, r: Dictionary, force: bool) -> Dictionary:
	if p == null:
		return _refusal("Nobody answers", "", true)
	var rn: Dictionary = sim.radio.reason_not(p, "work")
	var pushed := false
	if not bool(rn.ok):
		if bool(rn.hard) or not force:
			return _refusal(String(rn.why), String(rn.line), bool(rn.hard))
		pushed = true
	var kind := String(r.kind)
	var first := String(p.first)
	var blocked := _blocked_now()
	if blocked != "":
		return _refusal("%s: %s" % [first, blocked], "", true)
	var fixer := String(r.fixer)
	if fixer != "" and fixer != String(p.id):
		return _refusal("%s is on it" % _first(fixer), "", true)
	if (r.tried as Array).has(String(p.id)):
		return _refusal("%s already tried" % first, "I did what I could.", true)
	if (r.ids as Array).has(String(p.id)):
		return _refusal("%s: it is their own quarrel" % first, "That is between us.", true)
	var scrap := int((r.cost as Dictionary).get("scrap", 0))
	if scrap > 0 and float(sim.stock.scrap) < float(scrap):
		return _refusal("needs %d scrap" % scrap, "", true)
	var skill_name := _ks(kind, "skill")
	var need := int(_kf(kind, "min_skill"))
	if int(p.skills.get(skill_name, 0)) < need and not (kind == "quarrel" and _friend_of_both(p, r)):
		return _refusal("%s: needs %s %d" % [first, skill_name, need], "I would not know where to start.", true)
	var trust: float = sim.radio.trust_of(p)
	var tone: String = "doubtful" if pushed else String(sim.radio.tone_of(p))
	var spot := _at_of(r)
	var walk := Vector2(p.x, p.y).distance_to(spot) / maxf(_gf("delegate", "walk_speed", 3.0), 0.5)
	return {
		"ok": true, "why": "", "hard": false, "line": String(sim.radio.WORK_LINES[tone]), "tone": tone,
		"delay_s": float(sim.radio.delay_for(trust)) + walk, "chance": _chance(p, r), "cost": (r.cost as Dictionary).duplicate(),
		"eta_h": sim.game_hours(_work_s(p, r)),
	}


func _friend_of_both(p, r: Dictionary) -> bool:
	if (r.ids as Array).size() < 2:
		return false
	return sim.relations.is_close(p, _person(String(r.ids[0]))) and sim.relations.is_close(p, _person(String(r.ids[1])))


## 0.35 + 0.07 x skill + (trust - 50) / 250, and 0.1 for the title that fits (the engineer for the three works, the one the camp turns to for a quarrel),
## kept between 0.2 and 0.95.
func _chance(p, r: Dictionary) -> float:
	var kind := String(r.kind)
	var skill := float(p.skills.get(_ks(kind, "skill"), 0))
	var c := _gf("delegate", "base", 0.35) + _gf("delegate", "per_skill", 0.07) * skill + (float(sim.radio.trust_of(p)) - 50.0) / _gf("delegate", "trust_div", 250.0)
	if _title_fits(p, kind):
		c += _gf("delegate", "title", 0.1)
	return clampf(c, _gf("delegate", "min", 0.2), _gf("delegate", "max", 0.95))


func _title_fits(p, kind: String) -> bool:
	if kind == "quarrel":
		var v = sim.relations.voice()
		return v != null and String(v.id) == String(p.id)
	var h = sim.specialists.holder("engineer")
	return h != null and String(h.id) == String(p.id)


## radio.request_fix delegates here: asks this person to go and fix this problem. {"ok", "line", "why", "hard", "tone", "insisted", "chance"}. A soft refusal
## can be pushed past with `args.insist` (at the radio's cost of trust and a blow to the mood); a hard one cannot. On ok they go to the marker after the
## delay and work there; `fix_roll` against the chance decides the end.
func request_fix(problem_id, p, args := {}) -> Dictionary:
	var out := {"ok": false, "line": "", "why": NO_PROBLEM, "hard": true, "tone": "refused", "insisted": false, "chance": 0.0}
	if not active():
		return out
	var r := _rec(problem_id)
	if r.is_empty():
		return out
	if p == null or sim.radio.leader() == null:
		out.why = "Nobody is on the radio" if sim.radio.leader() == null else "Nobody answers"
		return out
	var w := _willing(p, r, false)
	var insisted := false
	if not bool(w.ok):
		if not (bool(args.get("insist", false)) and not bool(w.hard)):
			_say(p, false, String(w.line), "refused")
			out.line = String(w.line)
			out.why = String(w.why)
			out.hard = bool(w.hard)
			return out
		w = _willing(p, r, true)
		if not bool(w.ok):
			out.why = String(w.why)
			out.hard = bool(w.hard)
			return out
		insisted = true
	# another who was on it is let go: one hand at a time
	var old := String(r.fixer)
	if old != "" and old != String(p.id):
		_release(r)
	if String(p.stance) != "":
		sim.radio.clear_stance(p)
	if insisted:
		sim.radio.add_trust(p, -float(sim.radio.INSIST_COST), "You pushed them to fix it when they could not")
		sim.morale.shock(p, float(sim.radio.INSIST_MORALE), "Pushed to fix it when they could not")
	r.fixer = String(p.id)
	r.state = "walking"
	r.wait = float(sim.radio.delay_for(float(sim.radio.trust_of(p))))
	r.ord = []
	r.walked = 0.0
	r.left = 0.0
	r.chance = float(w.chance)
	_say(p, true, String(w.line), String(w.tone))
	out.ok = true
	out.line = String(w.line)
	out.why = ""
	out.hard = false
	out.tone = String(w.tone)
	out.insisted = insisted
	out.chance = float(w.chance)
	return out


func _say(p, ok: bool, line: String, tone: String) -> void:
	if line == "":
		return
	sim.events.append({"type": "radio_line", "who": String(p.id), "verb": "fix", "ok": ok, "line": line, "tone": tone})


## The only "dice": a pure function of the state (no `sim.rng`), 0.0 to 0.999. The same person at the same problem always gets the same number.
func fix_roll(problem_id, person_id) -> float:
	return float(("%s|%s|%d" % [problem_id, person_id, int(sim.run_seed)]).hash() % 1000) / 1000.0


## The willing person with the best chance (ties by id): what the stage-2 call's "Send <name>" uses; null when nobody.
func best_for(problem_id) -> Variant:
	var r := _rec(problem_id)
	if r.is_empty() or not active():
		return null
	var best = null
	var best_c := -1.0
	for p in sim.people:
		var w := _willing(p, r, false)
		if not bool(w.ok):
			continue
		var c := float(w.chance)
		if best == null or c > best_c + 1.0e-9 or (absf(c - best_c) <= 1.0e-9 and String(p.id) < String(best.id)):
			best = p
			best_c = c
	return best


## radio._carry_out for kind "problem": "send" asks the best person, "apart" (a quarrel) keeps the two apart, "leave" (the default) does nothing. The line
## the News keeps.
func carry_out(e: Dictionary, option_id: String) -> String:
	var data = e.get("data", {})
	var id := String((data as Dictionary).get("problem", "")) if data is Dictionary else ""
	match option_id:
		"send":
			if _rec(id).is_empty():
				return "It is already settled"
			var p = best_for(id)
			if p == null:
				return "Nobody is free to go"
			var a := request_fix(id, p)
			return "%s is on it" % String(p.first) if bool(a.ok) else String(a.why)
		"apart":
			var s := separate(id)
			return String(s.line) if bool(s.ok) else String(s.why)
	return "Left alone for now"


## Every step, for the problems somebody has been sent to: the delay, the walk, the work, the end.
func _walk_step(dt: float) -> void:
	for r in records.duplicate():
		if String(r.fixer) != "":
			_tend_fixer(r, dt)


func _tend_fixer(r: Dictionary, dt: float) -> void:
	var p = _person(String(r.fixer))
	var kind := String(r.kind)
	var what := _ks(kind, "name")
	if p == null or p.dead or p.turned or p.downed or p.away != null or p.player or sim.morale.breakdown(p):
		_drop_fixer(r, "%s was called away from %s" % [_first(String(r.fixer)), what])
		return
	var blocked := _blocked_now()
	if blocked != "":
		_drop_fixer(r, "%s left %s: %s" % [String(p.first), what, blocked])
		return
	var ord: Array = r.ord
	if ord.is_empty():
		# the delay: they are on it when it is up
		r.wait = float(r.wait) - dt
		if float(r.wait) > 0.0:
			return
		var spot := _stand_near(r)
		if not sim.order_move(p, spot.x, spot.y):
			_drop_fixer(r, "%s could not get to %s" % [String(p.first), what])
			return
		r.ord = [spot.x, spot.y]
		return
	if not _still_ordered(p, r):
		_drop_fixer(r, "%s was taken off %s" % [String(p.first), what])
		return
	var spot2 := Vector2(float(ord[0]), float(ord[1]))
	if String(r.state) == "walking":
		r.walked = float(r.walked) + dt
		if Vector2(p.x, p.y).distance_to(spot2) <= ARRIVE and not p.moving:
			_begin_work(r, p)
		elif float(r.walked) > _gf("delegate", "walk_limit_s", 45.0):
			_drop_fixer(r, "%s could not get to %s" % [String(p.first), what])
		return
	# working
	r.left = float(r.left) - dt
	if float(r.left) <= EPS:
		_finish_work(r, p)
		return
	p.work = _ks(kind, "pose")
	p.work_t += dt
	p.activity = _ks(kind, "doing")
	if kind != "quarrel":
		r["hammer"] = float(r.get("hammer", 0.0)) - dt
		if float(r.hammer) <= 0.0:
			r["hammer"] = HAMMER_EVERY
			sim.events.append({"type": "hammer", "x": p.x, "y": p.y})
	var to := _at_of(r) - Vector2(p.x, p.y)
	if to.length() > 0.3:
		p.facing = sim.facing_of(to.x, to.y, String(p.facing))


## They are there: the scrap is paid (and stays spent whatever comes of it), the work begins.
func _begin_work(r: Dictionary, p) -> void:
	var scrap := int((r.cost as Dictionary).get("scrap", 0))
	if scrap > 0:
		if float(sim.stock.scrap) < float(scrap):
			_drop_fixer(r, "%s could not start on %s: no scrap" % [String(p.first), _ks(String(r.kind), "name")])
			return
		sim.stock.scrap = float(sim.stock.scrap) - float(scrap)
	r.state = "working"
	r.left = _work_s(p, r)
	p.work = _ks(String(r.kind), "pose")
	p.work_t = 0.0
	sim.events.append({"type": "fix_work", "on": true, "id": String(r.id), "who": String(p.id)})


## The work is done: the dice say.
func _finish_work(r: Dictionary, p) -> void:
	var kind := String(r.kind)
	var id := String(r.id)
	sim.events.append({"type": "fix_work", "on": false, "id": id, "who": String(p.id), "why": "done", "line": "", "warn": false})
	if fix_roll(id, String(p.id)) < float(r.chance):
		if kind == "quarrel":
			var a = _person(String(r.ids[0]))
			var b = _person(String(r.ids[1]))
			_settle(r, a, b, p)
			return
		_credit(p, kind)
		_resolve(r, "fixed", p)
		return
	(r.tried as Array).append(String(p.id))
	if kind == "quarrel":
		r.ttl_h = float(r.ttl_h) + _kf("quarrel", "fail_hours")
	_release(r)
	sim.radio.log_news("problem", _ks(kind, "fail") % String(p.first), "It is still there.", {"data": {"problem": id, "kind": kind}, "at": _at_of(r)})
	sim.events.append({"type": "problem", "state": "failed", "id": id, "kind": kind})


func _still_ordered(p, r: Dictionary) -> bool:
	var ord: Array = r.ord
	if ord.size() != 2 or p.order == null:
		return false
	return Vector2(p.order.x, p.order.y).distance_to(Vector2(float(ord[0]), float(ord[1]))) < 0.6


## The delegate gives up (another order, the night, a fall, no scrap, no way there): a line in the News, the problem is open as before.
func _drop_fixer(r: Dictionary, line: String) -> void:
	_release(r)
	sim.radio.log_news("problem", line, "It is still there.", {"data": {"problem": String(r.id), "kind": String(r.kind)}, "at": _at_of(r)})


## Lets the person who was sent go: their order is theirs again if it is still ours, the problem is nobody's.
func _release(r: Dictionary) -> void:
	var p = _person(String(r.fixer)) if String(r.fixer) != "" else null
	if p != null:
		if _still_ordered(p, r):
			p.order = null
			p.drafted = false
			p.goal_key = ""
		if p.work == _ks(String(r.kind), "pose") and p.work != "":
			p.work = ""
			p.work_t = 0.0
	r.fixer = ""
	r.state = "idle"
	r.ord = []
	r.wait = 0.0
	r.left = 0.0
	r.walked = 0.0


## The open ground nearest the marker where a person can stand to work at it (the barrel and the generator are solid).
func _stand_near(r: Dictionary) -> Vector2:
	var at := _at_of(r)
	var kind := String(r.kind)
	if kind == "jam":
		return sim.storyteller.work_spot()
	for radius in [0.0, 0.8, 1.2, 1.6, 2.0]:
		var steps := 1 if float(radius) == 0.0 else 8
		for i in steps:
			var a := TAU * float(i) / 8.0
			var pt := at + Vector2(cos(a), sin(a)) * float(radius)
			if not sim.world.is_solid(sim.world.solid_p, pt.x, pt.y) and not sim.world.on_deck(pt.x, pt.y):
				return pt
	return at


# ---------------------------------------------------------------------- keep apart --

## Keeps a quarrel's two apart (no roll, no one's gain): the second of the pair goes to another station with a seat (when they share one) or to the
## farthest night post from the other's; a small blow to each mood. Ends the problem. {"ok", "line", "why"}.
func separate(problem_id) -> Dictionary:
	var r := _rec(problem_id)
	if r.is_empty() or not active() or String(r.kind) != "quarrel":
		return {"ok": false, "line": "", "why": "Nothing here to settle"}
	var a = _person(String(r.ids[0]))
	var b = _person(String(r.ids[1]))
	if not _here(a) or not _here(b):
		return {"ok": false, "line": "", "why": "They are not both here"}
	var by = _lead()
	var line := _keep_apart(r, a, b, by)
	return {"ok": true, "line": line, "why": ""}


## What puts the second apart from the first: {"mode": "station", "station": id} (they share a job: another with a seat, the one the second is best at)
## or {"mode": "post", "post": id, "swap": id of whoever holds it or ""} (the night post farthest from the first's, not the player's).
func _apart_plan(stay, move) -> Dictionary:
	var shared: String = sim.jobs.job_of(stay)
	if shared != "" and shared == sim.jobs.job_of(move):
		var best := ""
		var best_skill := -1
		for st in sim.jobs.stations():
			var id := String(st.id)
			if id == shared or sim.jobs.why_not(move, id) != "":
				continue
			var skill := int(move.skills.get(String(st.get("skill", "")), 0))
			if skill > best_skill:
				best = id
				best_skill = skill
		if best != "":
			return {"mode": "station", "station": best}
	var home := _post_pos(stay)
	var pick := ""
	var far := -1.0
	for po in sim.jobs.posts():
		var pid := String(po.id)
		var holder = _post_holder(pid)
		if holder != null and (holder == stay or _is_player(holder)):
			continue
		var d := Vector2(po.pos).distance_to(home)
		if d > far + 1.0e-9:
			pick = pid
			far = d
	if pick == "":
		return {}
	var hold = _post_holder(pick)
	return {"mode": "post", "post": pick, "swap": String(hold.id) if hold != null and hold != move else ""}


func _post_pos(p) -> Vector2:
	var po: Dictionary = sim.jobs.post(String(sim.jobs.post_ids.get(String(p.id), "")))
	return Vector2(po.pos) if not po.is_empty() else Vector2(p.x, p.y)


func _post_holder(post_id: String):
	for q in sim.people:
		if not (q.dead or q.turned) and String(sim.jobs.post_ids.get(String(q.id), "")) == post_id:
			return q
	return null


## Does it: the second to the other station or post. The sentence for the News.
func _apply_apart(plan: Dictionary, _stay, move) -> String:
	if plan.is_empty():
		return "%s keeps to themself" % String(move.first)
	if String(plan.mode) == "station":
		sim.jobs.assign(move, String(plan.station))
		return "%s goes to the %s" % [String(move.first), String(sim.jobs.station(String(plan.station)).get("name", plan.station)).to_lower()]
	var old := String(sim.jobs.post_ids.get(String(move.id), ""))
	if String(plan.post) == old:
		return "%s keeps to the %s" % [String(move.first), String(sim.jobs.post(old).get("name", "post")).to_lower()]
	sim.jobs.post_ids[String(move.id)] = String(plan.post)
	move.goal_key = ""
	if String(plan.swap) != "":
		var other = _person(String(plan.swap))
		if other != null:
			sim.jobs.post_ids[String(other.id)] = old
			other.goal_key = ""
	return "%s takes the %s" % [String(move.first), String(sim.jobs.post(String(plan.post)).get("name", "post")).to_lower()]


# ------------------------------------------------------------------------ the hooks --

## workshop.update and `_why_not_work` (a jam stops the bench) and build.factor (the floodlights): `what` is "bench" or "floodlights". Neutral false.
func blocks(what: String) -> bool:
	if records.is_empty() or not active():
		return false
	if what != "bench" and what != "floodlights":
		return false
	for r in records:
		if String(r.kind) == "jam":
			return sim.build.built("floodlights") if what == "floodlights" else true
	return false


## sim.perf: x0.85 for each of a quarrelling pair, else 1.0.
func perf_mult(p) -> float:
	if records.is_empty() or p == null or not active():
		return 1.0
	for r in records:
		if String(r.kind) == "quarrel" and (r.ids as Array).has(String(p.id)):
			return _kf("quarrel", "perf", 0.85)
	return 1.0


## morale._modifiers: [{"label", "value"}]: the quarrel's standing blow, for each of the two. [] inactive.
func mood_lines(p) -> Array:
	var out: Array = []
	if records.is_empty() or p == null or not active():
		return out
	for r in records:
		if String(r.kind) != "quarrel" or not (r.ids as Array).has(String(p.id)):
			continue
		var other := String(r.ids[1]) if String(r.ids[0]) == String(p.id) else String(r.ids[0])
		out.append({"label": _ks("quarrel", "mood_label") % _first(other), "value": _kf("quarrel", "mood", -3.0)})
	return out


# ------------------------------------------------------------------------------ save --

func save() -> Dictionary:
	var rows: Array = []
	for r in records:
		var row: Dictionary = (r as Dictionary).duplicate(true)
		var at: Vector2 = r.at
		row["at"] = [at.x, at.y]
		rows.append(row)
	return {"records": rows, "count": count, "next_at": next_at, "recent": recent.duplicate(), "fixing": {}}


## Restores what `save` wrote; {} (a save from before) is a fresh module with nothing open. Numbers are finite and clamped, a record that names a person
## or a wall that is not there is dropped, and the avatar's hands are never resumed.
func load_state(d: Dictionary) -> void:
	start()
	if d.is_empty() or sim == null:
		return
	var clock := float(sim.clock_min)
	var raw = d.get("records", [])
	var seen := {}
	var top := 0
	if raw is Array:
		for e in raw:
			if records.size() >= MAX_RECORDS:
				break
			var r := _record_in(e, clock)
			if r.is_empty() or seen.has(String(r.id)):
				continue
			seen[String(r.id)] = true
			records.append(r)
			top = maxi(top, int(String(r.id).substr(1)))
	count = maxi(clampi(int(d.get("count", 0)), 0, 100000) if _num(d.get("count")) else 0, top)
	if _num(d.get("next_at")):
		next_at = clampf(float(d.next_at), 0.0, clock + 36.0 * 1.2 * 60.0 + 1.0)
	var rec = d.get("recent", [])
	if rec is Array:
		for k in rec:
			if KINDS.has(String(k)) and recent.size() < 2:
				recent.append(String(k))


## One saved record, checked: {} when it cannot be.
func _record_in(e, clock: float) -> Dictionary:
	if not e is Dictionary:
		return {}
	var kind := String(e.get("kind", ""))
	var id := String(e.get("id", ""))
	if not KINDS.has(kind) or not id.begins_with("p") or not id.substr(1).is_valid_int() or int(id.substr(1)) < 1 or int(id.substr(1)) > 100000:
		return {}
	var r := {
		"id": id, "kind": kind, "day": 1, "t0": 0.0, "ttl_h": float(TTL_H[kind]), "at": Vector2.ZERO, "label": _ks(kind, "name"), "ids": [], "seg": -1,
		"stage": 1, "fixer": "", "state": "idle", "cost": {}, "late": false, "call": 0, "tried": [], "wait": 0.0, "left": 0.0, "chance": 0.0,
		"walked": 0.0, "ord": [],
	}
	r.day = clampi(int(e.get("day", 1)), 1, 100000) if _num(e.get("day")) else 1
	r.t0 = clampf(float(e.get("t0", clock)), 0.0, maxf(clock, 0.0)) if _num(e.get("t0")) else clock
	r.ttl_h = clampf(float(e.get("ttl_h", r.ttl_h)), 1.0, 400.0) if _num(e.get("ttl_h")) else r.ttl_h
	r.stage = clampi(int(e.get("stage", 1)), 1, 2) if _num(e.get("stage")) else 1
	r.late = bool(e.get("late", false)) if typeof(e.get("late", false)) == TYPE_BOOL else false
	r.call = clampi(int(e.get("call", 0)), 0, 1000000000) if _num(e.get("call")) else 0
	var cost = e.get("cost", {})
	if cost is Dictionary and _num((cost as Dictionary).get("scrap")):
		var n := clampi(int(cost.scrap), 0, 50)
		if n > 0:
			r.cost = {"scrap": n}
	var at = e.get("at")
	var pt := Vector2.ZERO
	if at is Array and (at as Array).size() == 2 and _num(at[0]) and _num(at[1]):
		pt = Vector2(clampf(float(at[0]), 0.0, float(sim.W)), clampf(float(at[1]), 0.0, float(sim.H)))
	elif typeof(at) == TYPE_VECTOR2 and is_finite((at as Vector2).x) and is_finite((at as Vector2).y):
		pt = Vector2(clampf((at as Vector2).x, 0.0, float(sim.W)), clampf((at as Vector2).y, 0.0, float(sim.H)))
	else:
		return {}
	r.at = pt
	match kind:
		"jam":
			r.at = sim.storyteller.GENERATOR
		"quarrel":
			var ids = e.get("ids", [])
			if not ids is Array or (ids as Array).size() != 2 or String(ids[0]) == String(ids[1]):
				return {}
			for x in ids:
				var q = _person(String(x))
				if q == null or q.dead or q.turned:
					return {}
			r.ids = [String(ids[0]), String(ids[1])]
		"crack":
			var seg = _segment(int(e.get("seg", -1))) if _num(e.get("seg")) else null
			if seg == null:
				return {}
			r.seg = int(seg.id)
			r.label = "the cracked %s" % String(seg.name).to_lower()    # (as `_make` names it: a record loaded must be the one that was saved, to its label)
	var tried = e.get("tried", [])
	if tried is Array:
		for x in tried:
			if _person(String(x)) != null and (r.tried as Array).size() < 20 and not (r.tried as Array).has(String(x)):
				(r.tried as Array).append(String(x))
	# a delegate: kept only when the person is there and the state is one of ours; the order is checked at the next step
	var fixer := String(e.get("fixer", ""))
	var state := String(e.get("state", "idle"))
	if fixer != "" and _person(fixer) != null and STATES.has(state) and state != "idle":
		r.fixer = fixer
		r.state = state
		r.wait = clampf(float(e.get("wait", 0.0)), 0.0, 60.0) if _num(e.get("wait")) else 0.0
		r.left = clampf(float(e.get("left", 0.0)), 0.0, 600.0) if _num(e.get("left")) else 0.0
		r.walked = clampf(float(e.get("walked", 0.0)), 0.0, 600.0) if _num(e.get("walked")) else 0.0
		r.chance = clampf(float(e.get("chance", 0.0)), 0.0, 1.0) if _num(e.get("chance")) else 0.0
		var ord = e.get("ord", [])
		if ord is Array and (ord as Array).size() == 2 and _num(ord[0]) and _num(ord[1]):
			r.ord = [clampf(float(ord[0]), 0.0, float(sim.W)), clampf(float(ord[1]), 0.0, float(sim.H))]
	return r


static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
