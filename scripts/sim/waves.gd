## The nights: how many of the dead come each night. At dusk the night gets a
## budget that grows with the day and scales with the difficulty, and the
## budget is spent in groups from the spawn points, spread over the night.
## Round 2 adds zombie types, random events and the Big Night on top of this.
##
## Numbers are starting values, tuned with tools/balance.gd. One walker costs
## one point. The rules' `spawn_t` is this module's timer between groups.
extends RefCounted

## Walkers on the first night at standard difficulty, and the growth per day
## after the first (0.10 means +10% of the base a day).
const BASE := 30.0
const GROWTH := 0.10
## Story, standard and brutal.
const DIFFICULTY := [0.7, 1.0, 1.4]
## A night's budget is spread over about this many seconds of rules time from
## dusk (a night lasts about 210).
const SPREAD_S := 170.0
## The average size of a group, for spreading the budget.
const AVG_GROUP := 2.2
## Most of the dead that may be alive at once, at dusk and at night.
const CAP_DUSK := 30
const CAP_NIGHT := 50

var sim
## Tests and the harness switch the nights off with this.
var enabled := true
## Points still to spend tonight, and what tonight's budget was.
var budget_left := 0.0
var budget_total := 0.0
## The day whose night the budget belongs to (-1: none yet).
var night_day := -1
## How many the dead this night has brought so far.
var spawned := 0


func setup(s) -> void:
	sim = s


func start() -> void:
	budget_left = 0.0
	budget_total = 0.0
	night_day = -1
	spawned = 0


## The budget of the night that follows `day` (day 1 is the first night).
func budget_for(day: int) -> float:
	return BASE * (1.0 + GROWTH * float(maxi(day, 1) - 1)) * float(DIFFICULTY[clampi(sim.difficulty, 0, 2)])


## Every step: a fresh budget at the start of dusk, then groups of the dead
## from the spawn points until it is spent.
func update(dt: float) -> void:
	if not enabled:
		return
	var dusk: bool = sim.phase == "dusk"
	if dusk and night_day != sim.day:
		night_day = sim.day
		budget_total = budget_for(sim.day)
		budget_left = budget_total
		spawned = 0
		sim.spawn_t = 2.0
	if budget_left < 1.0 or not (dusk or sim.phase == "night"):
		return
	sim.spawn_t -= dt
	if sim.spawn_t > 0.0:
		return
	var alive := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			alive += 1
	var night: bool = sim.phase == "night"
	if alive >= (CAP_NIGHT if night else CAP_DUSK):
		sim.spawn_t = 1.0
		return
	var at: Vector2 = sim.spawns[sim.rng.randi() % sim.spawns.size()]
	var group: int = (2 + sim.rng.randi() % 2) if night else 1
	group = mini(group, int(budget_left))
	for i in group:
		sim.spawn(at.x + (sim.rng.randf() - 0.5) * 1.6, at.y + (sim.rng.randf() - 0.5) * 1.6, "approach")
	budget_left -= float(group)
	spawned += group
	var mean := SPREAD_S * AVG_GROUP / maxf(budget_total, 1.0)
	sim.spawn_t = mean * (0.6 + 0.8 * sim.rng.randf())


func save() -> Dictionary:
	return {"budget_left": budget_left, "budget_total": budget_total, "night_day": night_day, "spawned": spawned}


func load_state(d: Dictionary) -> void:
	budget_left = float(d.get("budget_left", 0.0))
	budget_total = float(d.get("budget_total", 0.0))
	night_day = int(d.get("night_day", -1))
	spawned = int(d.get("spawned", 0))
