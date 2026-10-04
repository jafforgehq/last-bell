## Builds a headless game for tests: the data, the 2D world (only for its walk
## grids) and the rules, with no drawing. Free `world` when the test is done.
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")


## {"sim", "world", "data"}: a new run (day 1, 07:00) with the given seed and
## difficulty (0 story, 1 standard, 2 brutal). The storyteller is off (no card at noon, no
## assembly at dawn), so that a test of something else is not changed by the radio's news: the
## tests of the storyteller, and the harness, switch it on (`sim.storyteller.enabled = true`).
static func make(seed_value: int = 1, difficulty: int = 1, crew: int = 6, campaign: bool = false) -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	sim.crew_start = crew    # 6: the classic start; 3: a small start (recruits come over the radio)
	sim.seasons.campaign = campaign    # false: Autumn, the 30-night game; true: the long game of four seasons
	sim.start_run(difficulty, seed_value)
	sim.storyteller.enabled = false
	return {"sim": sim, "world": world, "data": data}


## Steps the rules for `seconds` of real time at 30 steps a second (one game
## hour is 20 seconds).
static func run(sim, seconds: float) -> void:
	for i in int(seconds * 30.0):
		sim.update(1.0 / 30.0)


## Steps until the clock reaches `hour` (0 to 24) of the current or next day.
static func run_to_hour(sim, hour: float) -> void:
	var guard := 0
	while absf(fposmod(sim.hour - hour + 12.0, 24.0) - 12.0) > 0.01 and guard < 100000:
		sim.update(1.0 / 30.0)
		guard += 1


## Puts `p` at their seat at their station, still, so that the station's work starts at once with
## no walk to it (the radio desk for Ruth, the bench for Dez...). With `station_id` they are given
## that job first (false, and nobody is moved, when the station is full).
static func seat(sim, p, station_id: String = "") -> bool:
	if station_id != "" and not sim.jobs.assign(p, station_id):
		return false
	var at: Vector2 = sim.jobs.seat_pos(p)
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.goal_key = ""
	return true


## Takes the people off the jobs that change the stores by themselves (the bench turns scrap into
## ammo, the beds grow food), so that a test that measures the stores sees only what it does itself.
## The wall crew, the radio desk, the lookout post and the infirmary are left as they are.
static func idle_stores(sim) -> void:
	for p in sim.people:
		var id: String = sim.jobs.job_of(p)
		if id == "bench" or id == "garden":
			sim.jobs.unassign(p)


## Nobody works: no jobs and no chores, so nobody makes ammo, grows food or mends a wall unasked.
static func no_work(sim) -> void:
	sim.jobs.clear()
	sim.tactics.chores = false


## The number the trait `id` carries for `key` in assets/data/traits.json: its multiplier (or, for
## `cure` and `bond`, the amount it adds). A test that quotes what a trait does asks here, so that a
## retune of the data does not break it. Read from the file itself, not from the rules' copy of it.
static func trait_effect(id: String, key: String) -> float:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/traits.json"))
	for t in parsed.get("traits", []):
		if String(t.get("id", "")) == id:
			return float(t.effects[key])
	push_error("assets/data/traits.json has no trait '%s'" % id)
	return NAN


## --------------------------------------------------------------- round 19 (nights) --

## A game with an avatar (round 19): `make` (day 1, 07:00, the storyteller off), then Ruth is the player (`sim.player_id == "ruth"`).
## `crew` 5 is the harness's small-start crew (`make`'s own default is 6). Free `world` when the test is done.
static func avatar_game(seed_value: int = 1, crew: int = 5) -> Dictionary:
	var g := make(seed_value, 1, crew)
	if not g.sim.avatar.set_player("ruth"):
		push_error("avatar_game: Ruth cannot be the player")
	g.sim.storyteller.enabled = false
	return g


## The base the way it was before round 25 (the older avatar tests that count News entries or calls call it): the briefing, the priorities, the dials, the problems
## and the dilemma are switched off, as Orientation Day does. A sim that has none of them (an older fake) is left as it is.
static func quiet_base(sim) -> void:
	for m in ["briefing", "priorities", "policies", "problems", "dilemmas"]:
		var mod = sim.get(m)
		if mod != null:
			mod.enabled = false


## The clock at `hour` (0 to 24) of `day`, as test_radio's `_at`: the day, the minutes, the game minutes since the start (day 1, 07:00 is 0), the
## phase, the bell (rung from 19:00 to 06:00) and the supplies' day, so that nothing is waiting to happen "again".
static func at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day


## `n` of the dead clawing at the wall section `seg_id` (at most as many as it has places), each at a place of it, about to strike
## (as test_radio's `_attack`). Returns them.
static func attack(sim, seg_id: int, n: int) -> Array:
	var out: Array = []
	for s in sim.segments:
		if s.id != seg_id:
			continue
		for i in mini(n, s.slots.size()):
			var sl = s.slots[i]
			var z = sim.spawn(sl.x, sl.y, "attack")
			z.slot = sl
			sl.who = z
			z.facing = sl.face
			z.attack_t = 0.0
			out.append(z)
	return out


## A plated brute (`z.plated`, round 19) clawing at the wall section `seg_id`, at its first free place (null if there is none or no such
## section). A plain one when the rules do not read `plated` yet.
static func plated_brute(sim, seg_id: int):
	for s in sim.segments:
		if s.id != seg_id:
			continue
		for sl in s.slots:
			if sl.who != null:
				continue
			var z = sim.spawn(sl.x, sl.y, "attack", "brute")
			z.plated = true
			z.slot = sl
			sl.who = z
			z.facing = sl.face
			z.attack_t = 0.0
			return z
	return null
