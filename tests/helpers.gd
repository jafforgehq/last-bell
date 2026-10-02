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
