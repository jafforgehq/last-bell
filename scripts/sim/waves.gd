## The nights: how many of the dead come each night, of which kinds, and from
## where. At dusk the night gets a budget that grows with the day and scales with
## the difficulty; the budget becomes a plan (a queue of kinds and one or two main
## spawn points) which is spent in groups, spread over the night. The last night
## (the Big Night) is a good deal bigger.
##
## The plan comes from a generator seeded by the run's seed and the day, never from
## the rules' own dice, so it is the same whenever it is asked for: the forecast
## at 17:00 and the dusk that spends it agree, and a loaded game carries on with
## the same night (`spawned` says how far it got).
##
## Numbers are starting values, tuned with tools/balance.gd. One walker costs one
## point (see kinds.gd for the others). The rules' `spawn_t` is this module's timer
## between groups.
##
## ROUND 19, AVATAR MODE (`avatar_mode()`: a player, and the settlement's own sim): the nights are sized for a community that holds
## an ordinary night alone (`ordinary.*` of assets/data/nights.json, read through night_data.gd), and a night whose day in the
## season is a multiple of `big_every` (and not the season's last) is a Big Night: a theme (The Siege, The Rush) with a size, one
## heading, special dead and plated brutes, which the community cannot be expected to hold without the player (`big_night`). The
## season's last night is the final, as ever, now with plated brutes. `outlook(day)` says what a night will bring (pure: for the
## lookout's forecast, the day-ahead notice and the harness) and `target_sections` which walls it will break on. Without an avatar
## none of this is read: the plans, the budgets and the dice are what they were (test_nights_regression pins it).
extends RefCounted

const Kinds := preload("res://scripts/sim/kinds.gd")
const Lots := preload("res://scripts/sim/lots.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const Recruits := preload("res://scripts/sim/recruits.gd")

## Walkers on the first night at standard difficulty, and the growth per day
## after the first (0.10 means +10% of the base a day).
const BASE := 30.0
const GROWTH := 0.10
## Story, standard and brutal.
const DIFFICULTY := [0.7, 1.0, 1.4]
## The last night brings this many times its day's budget.
const BIG_FACTOR := 2.4
## A night's budget is spread over about this many seconds of rules time from
## dusk (a night lasts about 210).
const SPREAD_S := 170.0
## The average size of a group, for spreading the budget.
const AVG_GROUP := 2.2
## Most of the dead that may be alive at once, at dusk, at night and on the last
## night.
const CAP_DUSK := 30
const CAP_NIGHT := 50
const CAP_BIG := 90
## The share of the dead that come from the night's main spawn points.
const MAIN_SHARE := 0.65

var sim
## Tests and the harness switch the nights off with this.
var enabled := true
## Points still to spend tonight, and what tonight's budget was.
var budget_left := 0.0
var budget_total := 0.0
## The day whose night the budget belongs to (-1: none yet).
var night_day := -1
## How many the dead this night has brought so far (the place in the plan).
var spawned := 0
## The night whose runners have been announced (-1: none).
var runners_told_day := -1
var _plan := {}
var _plan_day := -1
## What the plan was made with besides the day: the storyteller's multiplier of tonight's budget
## (a warning of a horde), so the plan and the forecast are made again when it changes.
var _plan_mult := 1.0
## The crew's share of the night's size the plan of `_plan_day` was made with (it does not change once the bell has rung).
var _plan_scale := 1.0
## Whether the plan of `_plan_day` was made in avatar mode (a player named after it was made gets a plan made again).
var _plan_avatar := false


func setup(s) -> void:
	sim = s


func start() -> void:
	budget_left = 0.0
	budget_total = 0.0
	night_day = -1
	spawned = 0
	runners_told_day = -1
	_plan = {}
	_plan_day = -1
	_plan_avatar = false


## Whether the avatar game's rules of the nights apply: a player, and the settlement's own sim (a place's sim has no Big Nights).
func avatar_mode() -> bool:
	return sim.nights_on and sim.player_id != ""


## The budget of the night that follows `day` (day 1 is the first night), before
## the last night's bonus. In avatar mode the growth and the share are the data's (`ordinary.growth`, `ordinary.mult`).
func budget_for(day: int) -> float:
	var eff: int = sim.seasons.effective_day(day)
	if avatar_mode():
		var growth := NightData.num("ordinary.growth", GROWTH)
		var mult := NightData.num("ordinary.mult", 1.0)
		return BASE * (1.0 + growth * float(maxi(eff, 1) - 1)) * float(DIFFICULTY[clampi(sim.difficulty, 0, 2)]) * sim.seasons.mult("waves") * mult
	return BASE * (1.0 + GROWTH * float(maxi(eff, 1) - 1)) * float(DIFFICULTY[clampi(sim.difficulty, 0, 2)]) * sim.seasons.mult("waves")


## What the avatar game's nights come to, for the new-game menu's words (round 22: they said the classic game's "about 30, 3 more each night"):
## {"first": the points of the first night (about as many of the dead), "more": the points a night grows by, "big_every": the day of a
## Big Night} for a crew of `crew` people at the difficulty whose share of the dead is `dead` (`DIFFICULTY`). The same numbers `budget_for`
## and `Recruits.crew_scale` give a run that begins so (the tests check it).
static func avatar_outline(dead: float, crew: int) -> Dictionary:
	var scale := Recruits.scale_for(crew, true)
	var base := BASE * dead * NightData.num("ordinary.mult", 1.0) * scale
	return {"first": base, "more": base * NightData.num("ordinary.growth", GROWTH), "big_every": maxi(1, int(NightData.num("big_every", 10.0)))}


## Whether this night is the last one.
func is_big(day: int) -> bool:
	return day >= sim.scenario.total_days()


## The Big Night of round 19 that follows `day`, or {} when it is not one (always, without an avatar): a night whose day in the
## season is a multiple of `big_every` and not the season's last (a milestone: The Siege, The Rush by turns, counting across the
## seasons of a campaign), or the season's last night (the final). {"kind": "milestone"|"final", "id": "siege"|"rush"|"last",
## "index" (a milestone's number in the run from 0; the final's season, from 0), "name", "factor", "runners", "brutes",
## "min_brutes", "headings" (how many main spawn points at most), "main_share", "brute_at": [lo, hi] (where in the queue the brutes
## come), "cap", "blurb", "plated": true}. The final keeps the old numbers (the season's `big` factor, BIG_RUNNERS, BIG_BRUTES,
## MAIN_SHARE, CAP_BIG); only its brutes are plated and come where the data says. Any day from the first on is answered, also a day
## of a later season of a campaign.
func big_night(day: int) -> Dictionary:
	if not avatar_mode():
		return {}
	var at := _locate(day)
	if at.is_empty():
		return {}
	var every := maxi(1, int(NightData.num("big_every", 10.0)))
	var sd: int = at.day
	var length: int = at.length
	if sd == length:
		var last := NightData.theme("last")
		var final_of_all: bool = int(at.index) + 1 >= sim.seasons.count()
		return {
			"kind": "final", "id": "last", "index": int(at.index),
			"name": String(last.get("name", "The last night")) if final_of_all else "The Big Night",
			"factor": float(sim.seasons.season(int(at.index)).get("big", 2.4)),
			"runners": Kinds.BIG_RUNNERS, "brutes": Kinds.BIG_BRUTES, "min_brutes": 0, "headings": 2, "main_share": MAIN_SHARE,
			"brute_at": _range(last.get("brute_at", []), 0.4, 1.0), "cap": CAP_BIG, "blurb": "", "plated": true,
		}
	if sd < 1 or sd % every != 0:
		return {}
	var k := floori(float(sd) / float(every)) - 1
	for i in int(at.index):
		k += floori(float(int(sim.seasons.season(i).get("days", 30)) - 1) / float(every))
	var order: Array = NightData.list("order")
	var id: String = String(order[k % order.size()]) if not order.is_empty() else "siege"
	var t := NightData.theme(id)
	if not t.has("factor"):
		id = "siege"
		t = NightData.theme(id)
	return {
		"kind": "milestone", "id": id, "index": k, "name": String(t.name), "factor": maxf(float(t.factor), 1.0),
		"runners": clampf(float(t.runners), 0.0, 0.8), "brutes": clampf(float(t.brutes), 0.0, 0.8), "min_brutes": maxi(0, int(t.get("min_brutes", 0))),
		"headings": maxi(1, int(t.headings)), "main_share": clampf(float(t.main_share), 0.0, 1.0),
		"brute_at": _range(t.get("brute_at", []), 0.25, 0.6), "cap": maxi(10, int(t.cap)), "blurb": String(t.get("blurb", "")), "plated": true,
	}


## [lo, hi] from a list of two numbers of the data (a damaged one gives `lo_default`, `hi_default`): 0 to 1, lo below hi.
func _range(v, lo_default: float, hi_default: float) -> Array:
	var lo := lo_default
	var hi := hi_default
	if typeof(v) == TYPE_ARRAY and v.size() == 2 and (typeof(v[0]) == TYPE_FLOAT or typeof(v[0]) == TYPE_INT) and (typeof(v[1]) == TYPE_FLOAT or typeof(v[1]) == TYPE_INT):
		lo = float(v[0])
		hi = float(v[1])
	lo = clampf(lo, 0.0, 0.99)
	hi = clampf(hi, lo + 0.01, 1.0)
	return [lo, hi]


## Which season `day` falls in and which day of it: {"index", "day", "length"}, or {} (a day before the run began, or past the last
## season). The current season answers for its own days, a campaign's later ones for the days after it.
func _locate(day: int) -> Dictionary:
	var s = sim.seasons
	var index: int = s.index
	var length: int = s.season_length()
	var sd: int = s.season_day(day)
	if sd < 1:
		return {}
	if sd <= length:
		return {"index": index, "day": sd, "length": length}
	if not s.campaign:
		return {}
	var left: int = sd - length
	index += 1
	while index < s.count():
		length = int(s.season(index).get("days", 30))
		if left <= length:
			return {"index": index, "day": left, "length": length}
		left -= length
		index += 1
	return {}


## A spawn point, drawn with the nests' pull on it (1 each, and NEST_PULL for every point of strength).
func _lean(rng: RandomNumberGenerator, n: int) -> int:
	var weights: Array = []
	var total := 0.0
	for i in n:
		var w: float = 1.0 + sim.town.NEST_PULL * sim.town.pressure(i)
		weights.append(w)
		total += w
	var at := rng.randf() * total
	for i in n:
		at -= float(weights[i])
		if at < 0.0:
			return i
	return n - 1


## How big the crew makes tonight (small start; 1 in the classic start): as it is now, but once the bell
## has rung it is what it was when the plan was made, so that a death in the night does not remake it.
func _scale(day: int) -> float:
	if _plan_day == day and not _plan.is_empty() and (sim.bell_rung or sim.phase == "night" or sim.phase == "dawn"):
		return _plan_scale
	return sim.recruits.crew_scale()


## What the night brings in points: `budget_for`, times the bonus on the last night (in avatar mode the theme's factor on a Big
## Night).
func night_budget(day: int) -> float:
	return _budget_at(day, _scale(day))


func _budget_at(day: int, scale: float) -> float:
	var factor := 1.0
	if avatar_mode():
		var theme := big_night(day)
		if not theme.is_empty():
			factor = float(theme.factor)
	elif is_big(day):
		factor = sim.seasons.big_factor()
	return budget_for(day) * factor * sim.storyteller.budget_mult(day) * scale * sim.town.budget_mult()


## The plan of the night that follows `day`: {"day", "big", "budget", "queue" (the
## kinds in the order they come), "counts", "heading" (indices into sim.spawns of
## the main spawn points), "shown" (the number a forecast gives, off by up to 15%)}, and (round 19) "kind" ("ordinary",
## "milestone" or "final"), "id", "name", "blurb", "plated" (its brutes are), "main_share", "brute_at" ([lo, hi] of the queue, [] on an
## ordinary night) and "cap" (the most alive at once on a Big Night, 0 otherwise: the phase's).
func plan_for(day: int) -> Dictionary:
	var scale := _scale(day)
	var mult: float = sim.storyteller.budget_mult(day) * scale * sim.town.budget_mult()
	if _plan_valid(day, mult):
		return _plan
	_plan = _make_plan(day, scale, mult)
	_plan_day = day
	_plan_mult = mult
	_plan_scale = scale
	_plan_avatar = avatar_mode()
	return _plan


func _plan_valid(day: int, mult: float) -> bool:
	return _plan_day == day and not _plan.is_empty() and is_equal_approx(_plan_mult, mult) and _plan_avatar == avatar_mode()


## The plan of `day` as it is now: tonight's is `plan_for` (the one kept, or a script's: Orientation Day's), any other day's is made and
## not kept (a day ahead: the cache is today's).
func _peek_plan(day: int) -> Dictionary:
	if day == sim.day:
		return plan_for(day)
	var scale := _scale(day)
	var mult: float = sim.storyteller.budget_mult(day) * scale * sim.town.budget_mult()
	if _plan_valid(day, mult):
		return _plan
	return _make_plan(day, scale, mult)


## The plan of `day` made from the run's seed and the day (no cache writes, no draw of the rules' dice): what `plan_for` keeps.
func _make_plan(day: int, scale: float, _mult: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (sim.run_seed * 2654435761 + day * 40503 + 12345) & 0x7fffffff
	var theme := big_night(day)    # {} without an avatar and on an ordinary night
	var big: bool = (not theme.is_empty()) if avatar_mode() else is_big(day)
	var budget := _budget_at(day, scale)
	var eff: int = sim.seasons.effective_day(day)
	var counts: Dictionary
	if theme.is_empty() or String(theme.kind) == "final":
		counts = Kinds.counts(budget, eff, big, rng)
	else:
		counts = Kinds.counts(budget, eff, true, rng, {"walker": 1.0 - float(theme.runners) - float(theme.brutes), "runner": float(theme.runners), "brute": float(theme.brutes)}, {"brute": int(theme.min_brutes)})
	var queue: Array = []
	for i in int(counts.walker):
		queue.append(Kinds.WALKER)
	for i in int(counts.runner):
		queue.append(Kinds.RUNNER)
	for i in range(queue.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = queue[i]
		queue[i] = queue[j]
		queue[j] = tmp
	# the brutes come in the later part of the night (on a Big Night of the avatar game, in the middle of it)
	var lo := 0.4
	var span := 0.6
	if not theme.is_empty():
		lo = float(theme.brute_at[0])
		span = float(theme.brute_at[1]) - lo
	for i in int(counts.brute):
		queue.insert(int(float(queue.size()) * (lo + span * rng.randf())), Kinds.BRUTE)
	var heading: Array = []
	var n: int = sim.spawns.size()
	# one main spawn point, and on most nights a second one now and then (a Big Night of the avatar game has the one)
	var second: bool = theme.is_empty() or int(theme.headings) > 1
	if sim.town.on:
		# the nests (town.gd) pull the main spawn points towards them
		heading.append(_lean(rng, n))
		if second and rng.randf() < 0.4:
			var other := _lean(rng, n)
			if other != heading[0]:
				heading.append(other)
	else:
		heading.append(rng.randi() % n)
		if second and rng.randf() < 0.4:
			var other := rng.randi() % n
			if other != heading[0]:
				heading.append(other)
	var shown := roundi(float(queue.size()) * (0.85 + 0.3 * rng.randf()) / 5.0) * 5
	var plan := {"day": day, "big": big, "budget": budget, "queue": queue, "counts": counts, "heading": heading, "shown": maxi(shown, 5),
		"kind": "final" if (theme.is_empty() and big) else "ordinary", "id": "", "name": "", "blurb": "", "plated": false, "main_share": MAIN_SHARE,
		"brute_at": [], "cap": 0}
	if not theme.is_empty():
		plan["kind"] = String(theme.kind)
		plan["id"] = String(theme.id)
		plan["name"] = String(theme.name)
		plan["blurb"] = String(theme.blurb)
		plan["plated"] = true
		plan["main_share"] = float(theme.main_share)
		plan["brute_at"] = theme.brute_at
		plan["cap"] = int(theme.cap)
	return plan


## The name of the way a point lies from the middle of the compound.
static func direction_name(v: Vector2) -> String:
	var d := v - Vector2(42.0, 32.0)
	var a := fposmod(atan2(d.y, d.x) + PI / 8.0, TAU)
	var names := ["east", "south east", "south", "south west", "west", "north west", "north", "north east"]
	return names[int(a / (TAU / 8.0)) % 8]


## "north east", or "north and west" when the plan has two main spawn points.
func heading_text(plan: Dictionary) -> String:
	var names: Array = []
	for i in plan.heading:
		var nm := direction_name(sim.spawns[int(i)])
		if not names.has(nm):
			names.append(nm)
	return " and ".join(names)


# ------------------------------------------------------------------ outlook --

## How many of the dead's tiles of walking a straight line from a spawn point to a wall is worth (streets, cars and the walls of
## the lots make the way longer than the crow's).
const WALK_DETOUR := 1.2
## The estimate of when the dead reach the wall is rounded to this many hours.
const OUTLOOK_STEP_H := 0.5


## What the night that follows `day` will bring, for any day from today on (a day ahead leaves the cache of tonight's plan and the
## rules' dice alone; tonight's is the plan `plan_for` keeps); {} without an avatar. {"day", "kind": "ordinary"|"milestone"|"final",
## "id", "name", "size" (the plan's `shown`), "low", "high" (the forecast's range), "side" (`heading_text`), "sections" ([segment ids]
## it will break on), "section_text" ("the east side: the second bus, the chain-link and wire"), "runners": bool, "brutes": int,
## "plated": int, "first_at", "brute_at" (-1.0 if none), "last_at" (hours of the day, 0 to 24, to the half hour, never before the dusk
## or after the dawn begins; "first_at" is when the first small group comes, `forecast.first_k` of the dead, "brute_at" when the
## first brute does), "needs_you": bool (a Big Night), "blurb"}. The times are estimates: when each of the dead is let in (the dusk's
## single ones, then groups, as `update` spreads them) and the walk from the main spawn point to the first target section at the
## kind's mean speed. A day of a later season of a campaign is sized with the season now (its own numbers are known when its dusk
## comes).
func outlook(day: int) -> Dictionary:
	if not avatar_mode():
		return {}
	var plan := _peek_plan(day)
	var theme := big_night(day)
	var sections := target_sections(plan)
	var ids: Array = []
	var names: Array = []
	for sec in sections:
		ids.append(int(sec.id))
		names.append("the %s" % String(sec.name).to_lower())
	var side := heading_text(plan)
	var shown := int(plan.shown)
	var times := _arrival_hours(plan, sections)
	var brutes := int(plan.counts.brute)
	return {
		"day": day, "kind": String(plan.get("kind", "ordinary")), "id": String(plan.get("id", "")), "name": String(plan.get("name", "")) if not theme.is_empty() else "An ordinary night",
		"size": shown, "low": roundi(float(shown) * 0.85), "high": roundi(float(shown) * 1.15),
		"side": side, "sections": ids, "section_text": ("the %s side: %s" % [side, ", ".join(names)]) if not names.is_empty() else "",
		"runners": int(plan.counts.runner) > 0, "brutes": brutes, "plated": brutes if bool(plan.get("plated", false)) else 0,
		"first_at": float(times.first), "brute_at": float(times.brute), "last_at": float(times.last),
		"needs_you": not theme.is_empty(), "blurb": String(theme.get("blurb", "")) if not theme.is_empty() else "",
	}


## The `n` non-door sections of the compound (a wall of the lots is not one) the plan's main heading will break on, as Segments: the
## least of the distance from the main spawn point to a free place's approach point and 1.2 for each of the dead already at the section,
## which is how the dead choose (`Sim.assign_slot`) with its luck left out. The alarm counts as it does there for tonight's plan.
## Fewer than `n` when fewer have a place and a way.
func target_sections(plan: Dictionary, n := 2) -> Array:
	var headings: Array = plan.get("heading", [])
	if headings.is_empty():
		return []
	var lured = sim.tactics.lure_seg() if int(plan.get("day", -1)) == sim.day else null
	var gated: bool = sim.lots.on
	var scored: Array = []
	for s in sim.segments:
		if s.kind == sim.DOOR_KIND or int(s.id) >= Lots.FIRST_SEGMENT_ID or s.state == 3:
			continue
		var crowd := 0
		for sl in s.slots:
			if sl.who != null:
				crowd += 1
		var best := INF
		for h in headings:
			var from: Vector2 = sim.spawns[int(h)]
			var home: int = sim.region_at(from.x, from.y) if gated else 0
			for sl in s.slots:
				if sl.who != null:
					continue
				if gated and home >= 0 and sim.region_at(sl.ax, sl.ay) != home:
					continue
				var score := from.distance_to(Vector2(sl.ax, sl.ay)) + float(crowd) * 1.2
				if lured != null and s == lured:
					score -= sim.tactics.LURE_PULL
				best = minf(best, score)
		if best < INF:
			scored.append([best, s])
	scored.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and int(a[1].id) < int(b[1].id)))
	var out: Array = []
	for i in mini(n, scored.size()):
		out.append(scored[i][1])
	return out


## When each of the queue (by place in it) comes to the first target section if nothing stops it, in seconds of the rules from the
## start of the dusk: when it is let in (the first group comes at 2; the single ones of the dusk every `mean`, then groups of two
## and a half) and the walk from the main spawn point to the section's nearest approach point (the compound's middle when there is
## no section) at its kind's mean speed.
func _arrival_seconds(plan: Dictionary, sections: Array) -> Array:
	var queue: Array = plan.queue
	var size := maxi(queue.size(), 1)
	var heading: Array = plan.heading
	var from: Vector2 = sim.spawns[int(heading[0])]
	var to := Vector2(42.0, 32.0)
	if not sections.is_empty():
		var near := INF
		for sl in sections[0].slots:
			var d := from.distance_to(Vector2(sl.ax, sl.ay))
			if d < near:
				near = d
				to = Vector2(sl.ax, sl.ay)
	var walk := from.distance_to(to) * WALK_DETOUR
	var mean: float = SPREAD_S * sim.seasons.night_scale() * AVG_GROUP / float(size)
	var dusk_s: float = sim.seasons.DUSK_H * 60.0 / sim.min_per_sec
	var by_dusk := mini(size, int(maxf(dusk_s - 2.0, 0.0) / mean) + 1)
	var out: Array = []
	for i in queue.size():
		var k: Dictionary = Kinds.KINDS[String(queue[i])]
		var speed: float = (float(k.speed[0]) + float(k.speed[1])) * 0.5 * (0.94 if queue[i] == Kinds.WALKER else 1.0)
		var let_in := 2.0 + (float(i) if i < by_dusk else float(by_dusk) + float(i - by_dusk) / 2.5) * mean
		out.append(let_in + walk / speed)
	return out


## {"first", "brute", "last"}: the hours of the day the first of the dead, the first brute and the last of the night come to the
## first target section: to the half hour, from the dusk to the dawn's beginning (-1.0 for a brute that does not come).
func _arrival_hours(plan: Dictionary, sections: Array) -> Dictionary:
	var queue: Array = plan.queue
	var arrives := _arrival_seconds(plan, sections)
	var brute := INF
	var last := 0.0
	for i in queue.size():
		last = maxf(last, float(arrives[i]))
		if queue[i] == Kinds.BRUTE:
			brute = minf(brute, float(arrives[i]))
	# "the first" is the first small group (`forecast.first_k` of the dead): the guns pick off a single walker on its own, so the
	# night is on the wall when a few of them come together (measured: the first one alone was late to the wall by hours on the
	# sides the guns cover best)
	var sorted := arrives.duplicate()
	sorted.sort()
	var first: float = float(sorted[clampi(int(NightData.num("forecast.first_k", 3.0)) - 1, 0, maxi(sorted.size() - 1, 0))]) if not sorted.is_empty() else INF
	var dusk: float = sim.seasons.dusk_hour()
	var span: float = (24.0 - dusk) + sim.seasons.dawn_hour() - sim.seasons.DAWN_H
	var to_hours := func(seconds: float) -> float:
		var x: float = clampf(seconds * sim.min_per_sec / 60.0, 0.0, span)
		x = clampf(snappedf(dusk + x, OUTLOOK_STEP_H) - dusk, 0.0, span)
		return fposmod(dusk + x, 24.0)
	return {
		"first": to_hours.call(first if first < INF else 0.0),
		"brute": to_hours.call(brute) if brute < INF else -1.0,
		"last": to_hours.call(last),
	}


## "21:30" for 21.5 (a clock hour, 0 to 24).
@warning_ignore("integer_division")
static func hour_text(hour: float) -> String:
	var minutes := roundi(fposmod(hour, 24.0) * 60.0)
	return "%02d:%02d" % [(minutes / 60) % 24, minutes % 60]


## What the lookout says of a Big Night (from `outlook`): "The Siege: about 70 to 95 from the east side, 2 plated brutes after
## 23:00, the first at about 21:00".
static func outlook_text(o: Dictionary) -> String:
	var side := String(o.side)
	var where := ("the %s side" % side) if not side.contains(" and ") else ("the %s" % side)
	var text := "%s: about %d to %d %s %s" % [String(o.name), int(o.low), int(o.high), "mostly from" if String(o.kind) == "final" else "from", where]
	if bool(o.runners):
		text += ", with runners"
	var brutes := int(o.brutes)
	if brutes > 0:
		var what := "a plated brute" if (int(o.plated) == 1 and brutes == 1) else ("%d plated brutes" % brutes if int(o.plated) > 0 else ("a brute" if brutes == 1 else "%d brutes" % brutes))
		text += ", %s after %s" % [what, hour_text(float(o.brute_at))]
	return "%s, the first at about %s" % [text, hour_text(float(o.first_at))]


## Every step: a fresh plan at the start of dusk, then groups of the dead from the
## spawn points until the plan is spent.
func update(dt: float) -> void:
	if not enabled:
		return
	var dusk: bool = sim.phase == "dusk"
	if dusk and night_day != sim.day:
		night_day = sim.day
		var fresh := plan_for(sim.day)
		budget_total = float(fresh.budget)
		budget_left = budget_total
		# the stragglers of the streets still about at dusk (the settlement game) are part of the night's dead, not
		# on top of them: they come off what is spent (never more than half of it)
		if sim.town.on:
			budget_left = maxf(budget_total * 0.5, budget_total - float(sim.streets.street_dead()))
		spawned = 0
		sim.spawn_t = 2.0
		if fresh.big:
			if String(fresh.get("kind", "")) == "milestone":
				# a Big Night of the avatar game: its own name and what it asks (nights.json)
				sim.events.append({"type": "banner", "text": String(fresh.name), "sub": String(fresh.get("blurb", ""))})
				sim.alert("bignight", "danger", String(fresh.name), String(fresh.get("blurb", "")), null, 30.0)
			elif sim.seasons.is_last():
				sim.events.append({"type": "banner", "text": "The last night", "sub": "Hold until dawn: the convoy comes at first light"})
				sim.alert("bignight", "danger", "The last night", "Everything that is left is coming", null, 30.0)
			else:
				sim.events.append({"type": "banner", "text": "The Big Night", "sub": "%s ends at dawn. Hold the wall." % String(sim.seasons.current().name)})
				sim.alert("bignight", "danger", "The Big Night", "Everything the %s kept is coming" % String(sim.seasons.current().name).to_lower(), null, 30.0)
	if not (dusk or sim.phase == "night") or night_day != sim.day:
		return
	var p := plan_for(night_day)
	var queue: Array = p.queue
	if spawned >= queue.size():
		return
	sim.spawn_t -= dt
	if sim.spawn_t > 0.0:
		return
	var alive := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			alive += 1
	var night: bool = sim.phase == "night"
	var cap := int(p.get("cap", 0))
	if cap <= 0:
		cap = CAP_BIG if p.big else (CAP_NIGHT if night else CAP_DUSK)
	var room: int = cap - alive
	if room <= 0:
		sim.spawn_t = 1.0
		return
	var at: Vector2 = _pick_spawn(p)
	var group: int = (2 + sim.rng.randi() % 2) if night else 1
	group = mini(mini(group, queue.size() - spawned), room)
	for i in group:
		var kind: String = queue[spawned]
		if kind == Kinds.BRUTE and i > 0:
			break
		var z = sim.spawn(at.x + (sim.rng.randf() - 0.5) * 1.6, at.y + (sim.rng.randf() - 0.5) * 1.6, "approach", kind)
		budget_left -= float(Kinds.KINDS[kind].cost)
		spawned += 1
		if kind == Kinds.BRUTE and avatar_mode():
			z.plated = bool(p.get("plated", false))
			_draw_to_the_lure(z)
		if kind == Kinds.BRUTE:
			if z.plated:
				sim.alert("brute", "danger", "A plated brute is coming", "From the %s. Only its head is soft." % direction_name(at), at, 25.0)
			else:
				sim.alert("brute", "danger", "A brute is coming", "From the %s. It tears walls down." % direction_name(at), at, 25.0)
		elif kind == Kinds.RUNNER and runners_told_day != night_day:
			runners_told_day = night_day
			sim.alert("runners", "warn", "Runners", "Fast ones, from the %s" % direction_name(at), at, 14.0)
		if kind == Kinds.BRUTE:
			break
	var mean: float = SPREAD_S * sim.seasons.night_scale() * AVG_GROUP / maxf(float(queue.size()), 1.0)
	sim.spawn_t = mean * (0.6 + 0.8 * sim.rng.randf())


## Where the next of the dead comes in: most of them at the night's main spawn
## points, the rest anywhere.
func _pick_spawn(p: Dictionary) -> Vector2:
	if sim.rng.randf() < float(p.get("main_share", MAIN_SHARE)):
		var heading: Array = p.heading
		return sim.spawns[int(heading[sim.rng.randi() % heading.size()])]
	return sim.spawns[sim.rng.randi() % sim.spawns.size()]


## In avatar mode a brute that comes in while the alarm rings goes to the section it is set on (every brute obeys it: the player
## chooses the wall a plated brute breaks on). No place there is, no way, or no alarm: it chooses as the dead do.
func _draw_to_the_lure(z) -> void:
	var seg = sim.tactics.lure_seg()
	if seg != null and seg.state != 3:
		sim.assign_slot(z, seg)


func save() -> Dictionary:
	return {"budget_left": budget_left, "budget_total": budget_total, "night_day": night_day, "spawned": spawned, "runners_told_day": runners_told_day}


func load_state(d: Dictionary) -> void:
	budget_left = float(d.get("budget_left", 0.0))
	budget_total = float(d.get("budget_total", 0.0))
	night_day = int(d.get("night_day", -1))
	spawned = int(d.get("spawned", 0))
	runners_told_day = int(d.get("runners_told_day", -1))
	_plan = {}
	_plan_day = -1
