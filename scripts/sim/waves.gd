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
extends RefCounted

const Kinds := preload("res://scripts/sim/kinds.gd")

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


## The budget of the night that follows `day` (day 1 is the first night), before
## the last night's bonus.
func budget_for(day: int) -> float:
	return BASE * (1.0 + GROWTH * float(maxi(day, 1) - 1)) * float(DIFFICULTY[clampi(sim.difficulty, 0, 2)])


## Whether this night is the last one.
func is_big(day: int) -> bool:
	return day >= sim.scenario.total_days()


## What the night brings in points: `budget_for`, times the bonus on the last night.
func night_budget(day: int) -> float:
	return budget_for(day) * (BIG_FACTOR if is_big(day) else 1.0)


## The plan of the night that follows `day`: {"day", "big", "budget", "queue" (the
## kinds in the order they come), "counts", "heading" (indices into sim.spawns of
## the main spawn points), "shown" (the number a forecast gives, off by up to 15%)}.
func plan_for(day: int) -> Dictionary:
	if _plan_day == day and not _plan.is_empty():
		return _plan
	var rng := RandomNumberGenerator.new()
	rng.seed = (sim.run_seed * 2654435761 + day * 40503 + 12345) & 0x7fffffff
	var big := is_big(day)
	var budget := night_budget(day)
	var counts := Kinds.counts(budget, day, big, rng)
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
	# the brutes come in the later part of the night
	for i in int(counts.brute):
		queue.insert(int(float(queue.size()) * (0.4 + 0.6 * rng.randf())), Kinds.BRUTE)
	var heading: Array = []
	var n: int = sim.spawns.size()
	heading.append(rng.randi() % n)
	if rng.randf() < 0.4:
		var other := rng.randi() % n
		if other != heading[0]:
			heading.append(other)
	var shown := roundi(float(queue.size()) * (0.85 + 0.3 * rng.randf()) / 5.0) * 5
	_plan = {"day": day, "big": big, "budget": budget, "queue": queue, "counts": counts, "heading": heading, "shown": maxi(shown, 5)}
	_plan_day = day
	return _plan


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
		spawned = 0
		sim.spawn_t = 2.0
		if fresh.big:
			sim.events.append({"type": "banner", "text": "The last night", "sub": "Hold until dawn: the convoy comes at first light"})
			sim.alert("bignight", "danger", "The last night", "Everything that is left is coming", null, 30.0)
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
	var cap := CAP_BIG if p.big else (CAP_NIGHT if night else CAP_DUSK)
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
		sim.spawn(at.x + (sim.rng.randf() - 0.5) * 1.6, at.y + (sim.rng.randf() - 0.5) * 1.6, "approach", kind)
		budget_left -= float(Kinds.KINDS[kind].cost)
		spawned += 1
		if kind == Kinds.BRUTE:
			sim.alert("brute", "danger", "A brute is coming", "From the %s. It tears walls down." % direction_name(at), at, 25.0)
		elif kind == Kinds.RUNNER and runners_told_day != night_day:
			runners_told_day = night_day
			sim.alert("runners", "warn", "Runners", "Fast ones, from the %s" % direction_name(at), at, 14.0)
		if kind == Kinds.BRUTE:
			break
	var mean := SPREAD_S * AVG_GROUP / maxf(float(queue.size()), 1.0)
	sim.spawn_t = mean * (0.6 + 0.8 * sim.rng.randf())


## Where the next of the dead comes in: most of them at the night's main spawn
## points, the rest anywhere.
func _pick_spawn(p: Dictionary) -> Vector2:
	if sim.rng.randf() < MAIN_SHARE:
		var heading: Array = p.heading
		return sim.spawns[int(heading[sim.rng.randi() % heading.size()])]
	return sim.spawns[sim.rng.randi() % sim.spawns.size()]


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
