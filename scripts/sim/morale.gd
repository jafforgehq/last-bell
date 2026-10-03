## Morale: how each person is holding up, 0 to 100, with the reasons shown (well fed,
## the dead at the wall, a friend down...). Low morale costs aim and work; very low
## is a breakdown.
##
## Each person has a value that starts at START_VALUE and drifts DRIFT_PER_HOUR points an
## hour toward a target, BASE_TARGET plus the continuous modifiers (what they have to eat
## and drink, wounds and fever, a friend near, the leader near, the dead clawing at the wall
## near them, a quiet night). Shocks (a kill, a breach, a friend down or dead, a repair
## done...) move the value at once; it then drifts back toward the target like any other
## gap, and the shock stays on the list of reasons while it fades. `explain` lists both.
##
## The mood follows the value: Inspired (everything a little better), Steady, Shaken (work
## and aim a tenth worse), Breaking (a quarter worse). Under BREAKDOWN_BELOW a person has a
## breakdown for an hour: they stop shooting, drop what they were doing and cannot be
## ordered; afterwards they sit at BREAKDOWN_AFTER. Breakdowns are off on Story and before
## day BREAKDOWN_FROM_DAY. `perf` goes into `sim.perf`.
##
## `enabled = false` (the tutorial, tests, the harness) makes it do nothing: no shocks, no
## modifiers, mood "Steady", perf 1.0, no breakdowns.
##
## Alerts: `breakdown-<id>`. Marks (`status_of`): icon "mood".
##
## From the buildings (build.gd) it reads `morale`: each standing bunk house is a steady lift for
## everyone alive, one more continuous modifier ("A proper bed", see `_modifiers`).
extends RefCounted

const Supplies := preload("res://scripts/sim/supplies.gd")

## --- the value ---
const START_VALUE := 70.0
const BASE_TARGET := 60.0
const DRIFT_PER_HOUR := 2.5
## How often (seconds of rules time) the target is worked out and the value moves.
const STEP := 0.5
## A shock that has faded to less than this is no longer listed.
const MIN_SHOWN := 0.25
## The most shocks listed for one person.
const MAX_SHOCKS := 12

## --- continuous modifiers (added to BASE_TARGET) ---
const WELL_FED := 5.0
const HUNGRY := -8.0
const STARVING := -20.0
const THIRSTY := -8.0
const PARCHED := -20.0
const BLEEDING := -6.0
const INFECTED := -8.0
const DOWNED := -15.0
## A bonded person within this many tiles lifts a person by this much.
const NEAR_BOND := 5.0
const NEAR_BOND_TILES := 6.0
## The leader (the best Leading among those who are up) within this many tiles lifts a
## person by Leading x LEADER_PER_POINT, at most LEADER_MAX.
const LEADER_TILES := 10.0
const LEADER_PER_POINT := 0.6
const LEADER_MAX := 6.0
## The dead clawing at a wall within this many tiles weigh on a person by this much each, at
## most DEAD_MAX in all, times the `dead_morale` trait.
const DEAD_TILES := 10.0
const DEAD_EACH := -0.7
const DEAD_MAX := -20.0
## After the bell, with none of the dead within this many tiles, the night is quiet: +QUIET.
const QUIET_TILES := 15.0
const QUIET := 2.0
## What the bunk houses' lift is called (the buildings' `morale` is its size).
const BED_LABEL := "A proper bed"

## --- shocks ---
## A kill lifts the one who made it, at most KILL_MAX points a night.
const KILL := 0.2
const KILL_MAX := 10.0
## A wall section falling shakes everyone.
const BREACH := -8.0
## A repair finished lifts the repairer.
const REPAIRED := 2.0
## A friend (anyone bonded) downed, or dead or turned (times the `grief` trait).
const FRIEND_DOWN := -14.0
const FRIEND_LOST := -30.0
## Anyone else dead or turned, for all the rest.
const OTHER_LOST := -12.0
## Someone sent out through the gate: for friends, and for all the rest.
const EXILE_FRIEND := -15.0
const EXILE_OTHER := -6.0

## --- moods ---
const INSPIRED_AT := 75.0
const SHAKEN_BELOW := 50.0
const BREAKING_BELOW := 30.0
const PERF_INSPIRED := 1.05
const PERF_SHAKEN := 0.9
const PERF_BREAKING := 0.75
## And the aim, on top of what `perf` does to the skill term of the hit chance (Breaking is no
## better than Shaken).
const AIM_INSPIRED := 1.05
const AIM_SHAKEN := 0.9
const AIM_BREAKING := 0.9

## --- breakdowns ---
const BREAKDOWN_BELOW := 15.0
const BREAKDOWN_HOURS := 1.0
const BREAKDOWN_AFTER := 35.0
const BREAKDOWN_FROM_DAY := 4
const STORY := 0
## Slack for clock comparisons (game minutes).
const EPS := 1.0e-6

const WARN := Color("#e8953a")
const DANGER := Color("#e0584a")

## Tests, the tutorial and the harness switch the whole system off with this.
var enabled := true
var sim
## Person id -> 0 to 100.
var levels := {}
## Person id -> sim.clock_min at which their breakdown ends.
var until := {}
## How many breakdowns this run has had (the harness reports it).
var breakdown_count := 0
## Person id -> the shocks still listed: [{"label": String, "value": float}].
var shocks := {}
var _acc := 0.0


func setup(s) -> void:
	sim = s
	_reset()


## A fresh run: everyone at the start value. (`enabled` is left as it is.)
func start() -> void:
	_reset()


## Someone joined the crew: they start as the crew did.
func person_added(p) -> void:
	levels[p.id] = START_VALUE


func _reset() -> void:
	levels = {}
	until = {}
	shocks = {}
	_acc = 0.0
	for p in sim.people:
		levels[p.id] = START_VALUE


# ------------------------------------------------------------------- stepping --

## Every step: now and then (every STEP seconds) the value moves toward its target, the
## listed shocks fade, a breakdown ends or begins.
func update(dt: float) -> void:
	if not enabled:
		return
	_acc += dt
	if _acc < STEP - 1.0e-9:
		return
	var span := _acc
	_acc = 0.0
	var hours: float = sim.game_hours(span)
	for p in sim.people:
		if p.dead or p.away != null:
			continue
		if until.has(p.id) and sim.clock_min >= float(until[p.id]) - EPS:
			_end_breakdown(p)
		_drift(p, hours)
		_fade(p, DRIFT_PER_HOUR * hours)
		_check_breakdown(p)


func _drift(p, hours: float) -> void:
	var v := value(p)
	var goal := target(p)
	var rate := DRIFT_PER_HOUR * hours
	if v < goal:
		v = minf(goal, v + rate * sim.traits.mult(p, "morale_recover"))
	elif v > goal:
		v = maxf(goal, v - rate)
	levels[p.id] = clampf(v, 0.0, 100.0)


## The listed shocks fade by `points` in all, each in proportion to its size.
func _fade(p, points: float) -> void:
	var entries: Array = shocks.get(p.id, [])
	if entries.is_empty():
		return
	var total := 0.0
	for e in entries:
		total += absf(float(e.value))
	var keep := maxf(0.0, 1.0 - points / total) if total > 0.0 else 0.0
	var left: Array = []
	for e in entries:
		e.value = float(e.value) * keep
		if absf(float(e.value)) >= MIN_SHOWN:
			left.append(e)
	if left.is_empty():
		shocks.erase(p.id)
	else:
		shocks[p.id] = left


# --------------------------------------------------------------------- reading --

## 0 to 100 (always START_VALUE while morale is off).
func value(p) -> float:
	if not enabled:
		return START_VALUE
	return float(levels.get(p.id, START_VALUE))


## Sets the value outright, with no reason listed (for the scenario and for tests).
func set_value(p, v: float) -> void:
	if not is_finite(v):
		return
	levels[p.id] = clampf(v, 0.0, 100.0)


## A word for how they are: "Inspired", "Steady", "Shaken" or "Breaking".
func mood(p) -> String:
	if not enabled:
		return "Steady"
	return _word(value(p))


func _word(v: float) -> String:
	if v >= INSPIRED_AT:
		return "Inspired"
	if v >= SHAKEN_BELOW:
		return "Steady"
	if v >= BREAKING_BELOW:
		return "Shaken"
	return "Breaking"


## How the crew is on the whole: the average value of the living, and its word.
func crew_value() -> float:
	var sum := 0.0
	var n := 0
	for p in sim.people:
		if not p.dead:
			sum += value(p)
			n += 1
	return sum / float(n) if n > 0 else START_VALUE


func crew_mood() -> String:
	return _word(crew_value()) if enabled else "Steady"


## How well morale lets them work and shoot: 1.05 inspired, 1.0, 0.9 shaken, 0.75 breaking.
func perf(p) -> float:
	match mood(p):
		"Inspired":
			return PERF_INSPIRED
		"Shaken":
			return PERF_SHAKEN
		"Breaking":
			return PERF_BREAKING
	return 1.0


## How much their mood changes how often a shot hits, on top of `perf`: 1.05 inspired, 1.0,
## 0.9 shaken or breaking.
func aim_mult(p) -> float:
	match mood(p):
		"Inspired":
			return AIM_INSPIRED
		"Shaken":
			return AIM_SHAKEN
		"Breaking":
			return AIM_BREAKING
	return 1.0


## What the value is heading for: BASE_TARGET plus the continuous modifiers.
func target(p) -> float:
	var goal := BASE_TARGET
	for m in _modifiers(p):
		goal += float(m.value)
	return goal


## What moves it, biggest first: the continuous modifiers (what they are now) and the shocks
## still fading: [{"label": String, "value": float, "recent": bool}] ("recent" for a shock).
func explain(p) -> Array:
	var out: Array = []
	if not enabled or p.dead:
		return out
	if p.away == null:
		for m in _modifiers(p):
			out.append({"label": m.label, "value": snappedf(float(m.value), 0.1), "recent": false})
	for e in shocks.get(p.id, []):
		out.append({"label": e.label, "value": snappedf(float(e.value), 0.1), "recent": true})
	out.sort_custom(func(a, b):
		var x := absf(float(a.value))
		var y := absf(float(b.value))
		if x != y:
			return x > y
		return String(a.label) < String(b.label))
	return out


## The continuous modifiers right now: [{"label", "value"}].
func _modifiers(p) -> Array:
	var out: Array = []
	if p.dead:
		return out
	# what they have to eat and drink
	var hungry: bool = p.hunger_h >= Supplies.HUNGRY_H
	var thirsty: bool = p.thirst_h >= Supplies.THIRSTY_H
	if p.hunger_h >= Supplies.STARVING_H:
		out.append({"label": "Starving", "value": STARVING})
	elif hungry:
		out.append({"label": "Hungry", "value": HUNGRY})
	if p.thirst_h >= Supplies.PARCHED_H:
		out.append({"label": "Parched", "value": PARCHED})
	elif thirsty:
		out.append({"label": "Thirsty", "value": THIRSTY})
	if not hungry and not thirsty:
		out.append({"label": "Well fed and watered", "value": WELL_FED})
	# how they are
	if p.bleeding > 0.0:
		out.append({"label": "Bleeding", "value": BLEEDING})
	if p.infected_at >= 0.0:
		out.append({"label": "Infected", "value": INFECTED})
	if p.downed:
		out.append({"label": "Down", "value": DOWNED})
	# who is near
	var friend = _near_friend(p)
	if friend != null:
		out.append({"label": "Near %s" % friend.first, "value": NEAR_BOND})
	var rival = sim.relations.rival_near(p)    # (round 20: a rival close by wears on them; null without an avatar)
	if rival != null:
		out.append({"label": "On edge near %s" % rival.first, "value": sim.relations.RIVAL_NEAR})
	var lead = _leader()
	if lead != null and lead != p and Vector2(lead.x - p.x, lead.y - p.y).length() <= LEADER_TILES:
		out.append({"label": "%s is leading" % lead.first, "value": minf(LEADER_MAX, float(lead.skills.get("Leading", 0)) * LEADER_PER_POINT)})
	# the dead
	var attacking := 0
	var any_near := false
	var dead_reach := DEAD_TILES * DEAD_TILES
	var quiet_reach := QUIET_TILES * QUIET_TILES
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var dx: float = z.x - p.x
		var dy: float = z.y - p.y
		var d2 := dx * dx + dy * dy
		if d2 <= quiet_reach:
			any_near = true
			if z.state == "attack" and d2 <= dead_reach:
				attacking += 1
	if attacking > 0:
		var scale: float = sim.traits.mult(p, "dead_morale")
		var label := "The dead at the wall"
		if scale != 1.0:
			label += " (%s)" % ", ".join(sim.traits.names_for(p, "dead_morale"))
		out.append({"label": label, "value": maxf(DEAD_MAX, DEAD_EACH * float(attacking)) * scale})
	if sim.bell_rung and not any_near:
		out.append({"label": "A quiet night", "value": QUIET})
	# a bed to sleep in (the bunk houses): a steady lift for everyone
	var bed: float = sim.build.bonus("morale")
	if bed != 0.0:
		out.append({"label": BED_LABEL, "value": bed})
	return out


## The nearest bonded person who is up and on the map within NEAR_BOND_TILES, or null.
func _near_friend(p):
	var best = null
	var best_d := NEAR_BOND_TILES
	for b in sim.bonds.of(p):
		var q = b.who
		if q.dead or q.downed or q.away != null:
			continue
		var d := Vector2(q.x - p.x, q.y - p.y).length()
		if d <= best_d:
			best_d = d
			best = q
	return best


## The leader: the best Leading among those who are alive, up and on the map.
func _leader():
	var best = null
	var best_lead := -1
	for q in sim.people:
		if q.dead or q.downed or q.away != null:
			continue
		var lead := int(q.skills.get("Leading", 0))
		if lead > best_lead:
			best_lead = lead
			best = q
	return best


## Small marks for the card and the panel (same shape as sim.status_of): while Shaken,
## Breaking or in a breakdown.
func status_of(p) -> Array:
	if not enabled or p.dead or p.away != null:
		return []
	if breakdown(p):
		return [{"icon": "mood", "color": DANGER, "tip": "Having a breakdown: cannot shoot or take orders"}]
	var v := roundi(value(p))
	match mood(p):
		"Breaking":
			return [{"icon": "mood", "color": DANGER, "tip": "Breaking (%d of 100): work %d%% and aim %d%% worse" % [v, roundi((1.0 - PERF_BREAKING) * 100.0), roundi((1.0 - AIM_BREAKING) * 100.0)]}]
		"Shaken":
			return [{"icon": "mood", "color": WARN, "tip": "Shaken (%d of 100): work and aim %d%% worse" % [v, roundi((1.0 - AIM_SHAKEN) * 100.0)]}]
	return []


# ---------------------------------------------------------------------- shocks --

## A sudden change for one person (or everyone on the map when `p` is null): the reason is
## its label. Nothing happens while morale is off.
func shock(p, delta: float, label: String) -> void:
	if not enabled or delta == 0.0 or not is_finite(delta):
		return
	if p == null:
		for q in sim.people:
			_shock_one(q, delta, label)
	else:
		_shock_one(p, delta, label)


func _shock_one(p, delta: float, label: String) -> void:
	if p.dead or p.away != null:
		return
	levels[p.id] = clampf(value(p) + delta, 0.0, 100.0)
	var entries: Array = shocks.get(p.id, [])
	var found := false
	for e in entries:
		if e.label == label:
			e.value = float(e.value) + delta
			found = true
			break
	if not found:
		entries.append({"label": label, "value": delta})
		if entries.size() > MAX_SHOCKS:
			var weakest := 0
			for i in entries.size():
				if absf(float(entries[i].value)) < absf(float(entries[weakest].value)):
					weakest = i
			entries.remove_at(weakest)
	shocks[p.id] = entries
	_check_breakdown(p)


## One of the dead was put down by `p`: a small lift, but at most KILL_MAX points a night
## (the night's kills are counted in the person's stats).
func on_kill(p) -> void:
	if float(p.stats.get("kills_night", 0)) * KILL <= KILL_MAX + 1.0e-9:
		shock(p, KILL, "Put the dead down")


## `p` finished mending a wall section.
func on_repaired(p) -> void:
	shock(p, REPAIRED, "Finished a repair")


## A wall section has just fallen.
func on_breach() -> void:
	shock(null, BREACH, "The wall was breached")


## `p` has just gone down: their friends are shaken.
func on_downed(p) -> void:
	sim.relations.on_downed(p)    # (round 20)
	if not enabled:
		return
	for b in sim.bonds.of(p):
		shock(b.who, FRIEND_DOWN, "%s is down" % p.first)


## `p` is gone for good: `how` is "died", "turned" or "left" (sent out through the gate).
## Their friends feel it most (a friend's death or turning, times the `grief` trait), the rest
## of the crew less.
func on_lost(p, how: String) -> void:
	sim.relations.on_lost(p, how)    # (round 20: the pairs of the lost one, and who mourns a partner)
	if not enabled:
		return
	for q in sim.people:
		if q == p or q.dead or q.away != null:
			continue
		var friend: bool = sim.bonds.bonded(p, q)
		if how == "left":
			shock(q, EXILE_FRIEND if friend else EXILE_OTHER, "%s left" % p.first)
		elif friend:
			shock(q, FRIEND_LOST * sim.traits.mult(q, "grief") * sim.relations.grief_mult(q, p), "%s %s" % [p.first, how])
		else:
			shock(q, OTHER_LOST, "%s %s" % [p.first, how])


# ------------------------------------------------------------------ breakdowns --

## Whether they are in a breakdown right now (they cannot shoot or be ordered).
func breakdown(p) -> bool:
	if not enabled or p.dead or not until.has(p.id):
		return false
	return sim.clock_min < float(until[p.id]) - EPS


## Breakdowns happen from day BREAKDOWN_FROM_DAY on, and not on Story.
func breakdowns_possible() -> bool:
	return sim.difficulty != STORY and sim.day >= BREAKDOWN_FROM_DAY


func _check_breakdown(p) -> void:
	if not enabled or p.dead or p.downed or p.away != null or breakdown(p):
		return
	if not breakdowns_possible() or value(p) >= BREAKDOWN_BELOW:
		return
	_start_breakdown(p)


func _start_breakdown(p) -> void:
	breakdown_count += 1
	until[p.id] = sim.clock_min + BREAKDOWN_HOURS * 60.0
	# they drop everything and stand where they are
	p.drafted = false
	p.order = null
	p.repair = null
	p.target = null
	p.moving = false
	p.path = []
	p.goal_key = ""
	p.activity = "Having a breakdown"
	sim.alert("breakdown-%s" % p.id, "danger", "%s has broken down" % p.first, "They cannot shoot or take orders for an hour", Vector2(p.x, p.y), 12.0)
	sim.barks.say(p, "breakdown")


func _end_breakdown(p) -> void:
	until.erase(p.id)
	levels[p.id] = BREAKDOWN_AFTER
	sim.alerts.erase("breakdown-%s" % p.id)


# ----------------------------------------------------------------------- save --

func save() -> Dictionary:
	var vals := {}
	for id in levels:
		vals[id] = float(levels[id])
	var ends := {}
	for id in until:
		ends[id] = float(until[id])
	var rows := {}
	for id in shocks:
		var list: Array = []
		for e in shocks[id]:
			list.append({"label": String(e.label), "value": float(e.value)})
		if not list.is_empty():
			rows[id] = list
	return {"values": vals, "until": ends, "shocks": rows, "acc": _acc}


## Restores the values, the breakdowns and the listed shocks. A save from before morale has
## none of it: everyone is at the start value. Anything that is not a sound number is ignored.
func load_state(d: Dictionary) -> void:
	_reset()
	var saved = d.get("values", {})
	if saved is Dictionary:
		for p in sim.people:
			var v = saved.get(p.id)
			if _number(v):
				levels[p.id] = clampf(float(v), 0.0, 100.0)
	var ends = d.get("until", {})
	if ends is Dictionary:
		for p in sim.people:
			var t = ends.get(p.id)
			if _number(t):
				until[p.id] = float(t)
	var rows = d.get("shocks", {})
	if rows is Dictionary:
		for p in sim.people:
			var list = rows.get(p.id)
			if not list is Array:
				continue
			var kept: Array = []
			for e in list:
				if e is Dictionary and typeof(e.get("label")) == TYPE_STRING and _number(e.get("value")):
					kept.append({"label": String(e.label), "value": float(e.value)})
			if kept.size() > MAX_SHOCKS:
				kept = kept.slice(0, MAX_SHOCKS)
			if not kept.is_empty():
				shocks[p.id] = kept
	var acc = d.get("acc", 0.0)
	_acc = clampf(float(acc), 0.0, STEP) if _number(acc) else 0.0


static func _number(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
