extends "res://tests/case.gd"
## T-GOLD (round 19, slice 3, docs/superpowers/plans/2026-10-03-round-19.md): every new rule of the nights is behind avatar mode, so
## a game with no avatar plays byte for byte as it did at the round 17 commit f23eee3, and this file pins it against
## `tests/golden/harness_noavatar.json`, recorded from a clean copy of that commit:
##   - the harness (`tools/balance.gd --policy=informed --crew=5 --hz=15 --days=6`, seeds 1, 9, 21): the `rows` of each game, the
##     number for number, so any change of what a no-avatar night does, anywhere, shows up;
##   - the rules' own random source: `sim.rng.state` at 18:00 of day 4 of a harness game of seed 7 (no draw added anywhere);
##   - `waves.plan_for` and `night_budget` of every day of three runs (Autumn's 30 nights at crews 5 and 6, a campaign's 102), and the
##     same again with nights.json pointing at absurd numbers or at nothing (the data is never read without an avatar);
##   - `tactics.forecast()` and what `_tell_the_forecast` says (the alert, the banner), on five days and with nobody on watch;
##   - the stubs' hooks are neutral without an avatar (`Sim.nights`, `Waves.big_night`, `Zombie.plated`).
## The three harness games run in worker processes (the harness's own CLI, a game is about 40 s) while this process plays the seed 7
## game; a worker that leaves no result has its game played here. To re-record after an intended change of the no-avatar game, play
## the same measurements on the new commit (`measure_rng`, `measure_plans`, `measure_forecasts`, the harness `--out` JSON) and say so.

const Helpers := preload("res://tests/helpers.gd")
const Balance := preload("res://tools/balance.gd")
const NightData := preload("res://scripts/sim/night_data.gd")

const GOLDEN := "res://tests/golden/harness_noavatar.json"
const SEEDS := [1, 9, 21]
const DAYS := 6
const HZ := 15.0
const CREW := 5
const RNG_SEED := 7
const RNG_DAY := 4
const RNG_HOUR := 18.0
## A plan is made for these runs: {name, seed, crew, campaign, days}.
const PLAN_RUNS := [
	{"name": "autumn_s1_c5", "seed": 1, "crew": 5, "campaign": false, "days": 30},
	{"name": "autumn_s7_c6", "seed": 7, "crew": 6, "campaign": false, "days": 30},
	{"name": "campaign_s5_c5", "seed": 5, "crew": 5, "campaign": true, "days": 102},
]
const FORECAST_DAYS := [1, 5, 9, 14, 30]


# ---------------------------------------------------------------- measuring --

## `v` as the JSON writer and reader hand it back (every number a float, vectors and the like text), so that a recorded value and a
## fresh one compare with `==`.
static func normal(v):
	return JSON.parse_string(JSON.stringify(_plain(v), "", true, true))


static func _plain(v):
	match typeof(v):
		TYPE_VECTOR2:
			return [v.x, v.y]
		TYPE_ARRAY:
			var list: Array = []
			for e in v:
				list.append(_plain(e))
			return list
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _plain(v[k])
			return d
		TYPE_OBJECT:
			return null
	return v


## The first place where two plain values differ, as text ("" when equal): for a failure message that says which row and which key.
static func first_diff(a, b, path: String = "") -> String:
	if typeof(a) != typeof(b):
		return "%s: %s against %s" % [path, str(a), str(b)]
	if typeof(a) == TYPE_DICTIONARY:
		for k in a:
			if not b.has(k):
				return "%s.%s: only in the first" % [path, k]
			var d := first_diff(a[k], b[k], "%s.%s" % [path, k])
			if d != "":
				return d
		for k in b:
			if not a.has(k):
				return "%s.%s: only in the second" % [path, k]
		return ""
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return "%s: %d entries against %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s against %s" % [path, str(a), str(b)]


## The rules' random source at 18:00 of day 4 of a harness game of seed 7 (informed policy, crew 5, 15 Hz, the storyteller on: what
## `Balance.play` sets up and steps, stopped at that hour). Saved as text (a 64-bit state is not a JSON number).
static func measure_rng() -> Dictionary:
	var g := Helpers.make(RNG_SEED, 1, CREW, false)
	var sim = g.sim
	sim.streets.enabled = true
	sim.storyteller.enabled = true
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	policy.builds = true
	policy.lots_enabled = true
	policy.vehicles_enabled = true
	policy.build_order = []
	policy.beds_first = false
	var dt := 1.0 / HZ
	var every := roundi(HZ)
	var step := 0
	while sim.over == "" and not (sim.day == RNG_DAY and sim.hour >= RNG_HOUR):
		sim.update(dt)
		step += 1
		if step % every == 0:
			policy.tick()
	var out := {"seed": RNG_SEED, "day": sim.day, "hour": snappedf(sim.hour, 0.01), "state": str(sim.rng.state), "rng_seed": str(sim.rng.seed), "over": sim.over}
	g.world.free()
	return out


## The plan of every day of each of PLAN_RUNS from a new run, and the budget behind it: {run name: [{day, big, budget, night_budget, queue
## (w, r, b), counts, heading, shown}]}.
static func measure_plans() -> Dictionary:
	var out := {}
	for spec in PLAN_RUNS:
		var g := Helpers.make(int(spec.seed), 1, int(spec.crew), bool(spec.campaign))
		var rows: Array = []
		for day in range(1, int(spec.days) + 1):
			var p: Dictionary = g.sim.waves.plan_for(day)
			var queue := ""
			for k in p.queue:
				queue += String(k).substr(0, 1)
			rows.append({"day": day, "big": p.big, "budget": p.budget, "night_budget": g.sim.waves.night_budget(day), "queue": queue,
				"counts": p.counts, "heading": p.heading, "shown": p.shown})
		out[String(spec.name)] = normal(rows)
		g.world.free()
	return out


## What the lookout says at 17:00 of each of FORECAST_DAYS (seed 21, the classic crew: Marcus is on watch), and with nobody on watch:
## {"day N": {forecast, alert {level, text, sub}, banners [{text, sub}]}, "nobody": {...}}.
static func measure_forecasts() -> Dictionary:
	var out := {}
	for day in FORECAST_DAYS + [-1]:
		var g := Helpers.make(21, 1, 6)
		var sim = g.sim
		sim.waves.enabled = false
		if day < 0:
			for p in sim.people:
				if p.first == "Marcus":
					p.dead = true
		else:
			sim.day = day
		sim.minutes = 16.9 * 60.0
		sim.phase = sim.phase_at(sim.minutes)
		sim.events.clear()
		Helpers.run(sim, 3.0)
		var banners: Array = []
		for e in sim.events:
			if e.type == "banner":
				banners.append({"text": e.text, "sub": e.sub})
		var alert: Dictionary = sim.alerts.get("forecast", {})
		out["nobody" if day < 0 else "day %d" % day] = normal({
			"forecast": sim.tactics.forecast(),
			"alert": {"level": alert.get("level", ""), "text": alert.get("text", ""), "sub": alert.get("sub", "")},
			"banners": banners,
		})
		g.world.free()
	return out


## The golden file's data, or {} (and a failure) if it is missing or damaged.
func _golden() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN)) if FileAccess.file_exists(GOLDEN) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("%s is missing or damaged" % GOLDEN)
		return {}
	return parsed


# --------------------------------------------------------------- the tests --

func test_the_harness_without_an_avatar_plays_exactly_as_before() -> void:
	var golden := _golden()
	if golden.is_empty():
		return
	# the three games, each in a worker process (the harness's own CLI: a game is about 40 s) ...
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var scratch := ProjectSettings.globalize_path("user://")
	var workers: Array = []
	for sd in SEEDS:
		var out := scratch.path_join("test_r19_gold_%d_%d.json" % [OS.get_process_id(), sd])
		var args := ["--headless", "--path", project, "--script", "res://tools/balance.gd", "--", "--seeds=%d" % sd, "--days=%d" % DAYS,
			"--hz=%d" % int(HZ), "--policy=informed", "--crew=%d" % CREW, "--quiet", "--out=%s" % out]
		workers.append({"seed": sd, "out": out, "pid": OS.create_process(exe, args)})
	# ... while this process plays the game of seed 7 to 18:00 of day 4
	var rng_now := measure_rng()
	var rng_gold: Dictionary = golden.get("rng", {})
	eq(rng_now.day, int(rng_gold.get("day", -1)), "the seed 7 game is at day 4")
	eq(rng_now.hour, float(rng_gold.get("hour", -1.0)), "at 18:00")
	eq(rng_now.state, String(rng_gold.get("state", "")), "the rules' random state at 18:00 of day 4 (a draw was added or removed somewhere)")
	eq(rng_now.rng_seed, String(rng_gold.get("rng_seed", "")), "the same seed")
	while true:
		var running := 0
		for w in workers:
			if w.pid > 0 and OS.is_process_running(w.pid):
				running += 1
		if running == 0:
			break
		OS.delay_msec(300)
	var by_seed := {}
	for g in golden.get("games", []):
		by_seed[int(g.seed)] = g
	eq(by_seed.size(), SEEDS.size(), "the golden file has the three games")
	for w in workers:
		var game = null
		if FileAccess.file_exists(w.out):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(w.out))
			if typeof(parsed) == TYPE_DICTIONARY and parsed.get("games", []).size() == 1:
				game = parsed.games[0]
			DirAccess.remove_absolute(w.out)
		if game == null:
			# a worker that left nothing (no executable to start, a crash): the game is played here
			var was := Balance.crew_start
			Balance.crew_start = CREW
			game = Balance.play(int(w.seed), 1, DAYS, HZ, true, Callable(), false, true, true)
			Balance.crew_start = was
		var want = by_seed.get(int(w.seed))
		if want == null:
			failures.append("no golden game for seed %d" % w.seed)
			continue
		eq(String(game.outcome), String(want.outcome), "seed %d: the outcome" % w.seed)
		eq(int(game.day), int(want.day), "seed %d: the day reached" % w.seed)
		var diff := first_diff(normal(game.rows), normal(want.rows), "rows")
		check(diff == "", "seed %d: the harness rows differ from the golden numbers at %s" % [w.seed, diff])


func test_the_plans_of_the_nights_are_the_golden_ones_and_never_read_the_nights_data() -> void:
	var golden := _golden()
	if golden.is_empty():
		return
	var want: Dictionary = golden.get("plans", {})
	var now := measure_plans()
	eq(now.keys().size(), want.keys().size(), "the same runs")
	for name in want:
		var diff := first_diff(now.get(name, []), want[name], name)
		check(diff == "", "no-avatar plans: %s" % diff)
	# the data file is never read without an avatar: absurd numbers in it, or no file, change nothing
	var was: String = NightData.data_path
	var absurd := "user://test_r19_nights_absurd.json"
	var f := FileAccess.open(absurd, FileAccess.WRITE)
	f.store_string(JSON.stringify({"ordinary": {"avatar_weight": 9.0, "mult": 9.0, "growth": 5.0}, "big_every": 2,
		"themes": {"siege": {"factor": 9.0, "brutes": 0.9}, "rush": {"factor": 9.0}, "last": {"brute_at": [0.0, 0.1]}},
		"rally": {"radius": 99.0}, "plated": {"armour": 0.0}}))
	f.close()
	for path in [absurd, "user://test_r19_nights_missing.json"]:
		NightData.data_path = path
		NightData.forget()
		var other := measure_plans()
		for name in want:
			var diff := first_diff(other.get(name, []), want[name], name)
			check(diff == "", "no-avatar plans with %s: %s" % [path.get_file(), diff])
	NightData.data_path = was
	NightData.forget()
	DirAccess.remove_absolute(absurd)


func test_the_forecast_and_its_text_are_the_old_ones() -> void:
	var golden := _golden()
	if golden.is_empty():
		return
	var want: Dictionary = golden.get("forecasts", {})
	var now := measure_forecasts()
	eq(now.keys().size(), want.keys().size(), "the same days")
	for name in want:
		var diff := first_diff(now.get(name, {}), want[name], name)
		check(diff == "", "no-avatar forecast: %s" % diff)


func test_every_hook_of_the_nights_is_neutral_without_an_avatar() -> void:
	var g := Helpers.make(3, 1, 6)
	var sim = g.sim
	check(sim.nights != null, "the sim has its nights module")
	check(sim.nights_on, "the settlement's own sim has the nights' rules switched on")
	eq(sim.player_id, "", "nobody is the player")
	check(not sim.nights.active(), "so none of it is active")
	var p = sim.people[0]
	var seg = sim.segments[0]
	var z = sim.spawn(40.0, 30.0, "approach", "brute")
	eq(z.plated, false, "a brute is not plated by itself")
	z.plated = true
	var state = sim.rng.state
	check(not sim.nights.rallied(p), "nobody is rallied")
	eq(sim.nights.aim_mult(p), 1.0, "aim x 1")
	eq(sim.nights.fire_mult(p), 1.0, "fire x 1")
	eq(sim.nights.damage_to(z, 3.7, true), 3.7, "a head hit on a plated brute is the plain damage")
	eq(sim.nights.damage_to(z, 3.7, false), 3.7, "a body hit too")
	check(not sim.nights.weak_hit(z, Vector2(z.x + 5.0, z.y), Vector2(-1, 0)), "no weak point")
	check(not sim.nights.npc_weak(z), "a defender's shot has no weak point")
	check(not sim.nights.breach_hot(seg), "no hot breach")
	eq(sim.nights.repair_mult(p, seg), 1.0, "mending is as ever")
	eq(sim.nights.section_threat(seg), 0.0, "no threat is scored")
	eq(sim.nights.contested().threat, 0.0, "nothing is contested")
	eq(sim.rng.state, state, "and not one draw of the rules' dice was spent")
	for day in range(1, 31):
		eq(sim.waves.big_night(day), {}, "no Big Night of round 19 on day %d" % day)
	g.world.free()
