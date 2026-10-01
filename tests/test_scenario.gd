extends "res://tests/case.gd"
## The run: how it starts, when it is lost, the day-start event, the run
## arguments, and the balance harness that plays whole games.

const Helpers := preload("res://tests/helpers.gd")
const Scenario := preload("res://scripts/sim/scenario.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const Balance := preload("res://tools/balance.gd")


func test_a_new_run_starts_right() -> void:
	var g := Helpers.make(21, 2)
	var sim = g.sim
	eq(sim.day, 1, "day 1")
	near(sim.hour, 7.0, 0.001, "at 07:00")
	eq(sim.clock_min, 0.0, "the game clock starts at zero")
	eq(sim.phase, "day", "in the daytime")
	eq(sim.over, "", "the run is on")
	eq(sim.difficulty, 2, "the chosen difficulty")
	eq(sim.run_seed, 21, "the chosen seed")
	eq(sim.weather, "clear", "clear weather")
	eq(sim.stock, Sim.START_STOCK, "the starting stocks")
	eq(sim.people.size(), 6, "six survivors")
	for p in sim.people:
		check(not p.dead and not p.downed and not p.turned and p.away == null, "%s starts well and at home" % p.first)
	eq(sim.scenario.day(), 1, "the scenario says day 1")
	eq(sim.scenario.total_days(), 30, "of thirty")
	g.world.free()


func test_defeat_is_detected_once_and_stops_the_rules() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	Helpers.run(sim, 2.0)
	eq(sim.over, "", "still on while anyone lives")
	for p in sim.people:
		p.dead = true
	Helpers.run(sim, 1.0)
	eq(sim.over, "defeat", "everyone gone: defeat")
	var overs := 0
	var banners := 0
	for e in sim.events:
		if e.type == "over":
			overs += 1
			eq(e.result, "defeat", "the event names the result")
		elif e.type == "banner" and String(e.text).to_lower().contains("gone"):
			banners += 1
	eq(overs, 1, "one over event")
	eq(banners, 1, "one banner")
	var t_before: float = sim.t
	var minutes_before: float = sim.minutes
	Helpers.run(sim, 5.0)
	eq(sim.t, t_before, "the rules stand still")
	eq(sim.minutes, minutes_before, "and so does the clock")
	sim.scenario.update(0.1)
	var overs_after := 0
	for e in sim.events:
		if e.type == "over":
			overs_after += 1
	eq(overs_after, 1, "asking again adds nothing")
	g.world.free()


func test_someone_downed_or_away_keeps_the_run_alive() -> void:
	var g := Helpers.make(2, 1)
	var sim = g.sim
	for p in sim.people:
		p.dead = true
	var last = sim.people[2]
	last.dead = false
	last.downed = true
	last.hp = 0.0
	Helpers.run(sim, 0.5)
	eq(sim.over, "", "a downed survivor who is not dead counts as alive")
	last.downed = false
	last.away = {"kind": "party"}
	Helpers.run(sim, 0.5)
	eq(sim.over, "", "a survivor away on a trip counts as alive")
	last.away = null
	last.dead = true
	Helpers.run(sim, 0.5)
	eq(sim.over, "defeat", "and when the last one dies it is over")
	g.world.free()


func test_turned_and_exiled_people_count_as_gone() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	for i in sim.people.size():
		var p = sim.people[i]
		p.dead = true
		if i % 2 == 0:
			p.turned = true
		else:
			p.away = {"kind": "exile"}
	Helpers.run(sim, 0.5)
	eq(sim.over, "defeat", "turned and exiled are gone")
	g.world.free()


func test_a_run_without_people_is_not_lost_at_once() -> void:
	var g := Helpers.make(4, 1)
	var sim = g.sim
	sim.people.clear()
	sim.scenario.update(0.1)
	eq(sim.over, "", "nobody to lose is not a defeat")
	g.world.free()


func test_the_day_start_event_fires_once_each_dawn() -> void:
	var g := Helpers.make(6, 1)
	var sim = g.sim
	var starts: Array = []
	var hours: Array = []
	eq(sim.day, 1, "the run began on day 1")
	# hop the clock to just before the dawns of day 2 and day 3
	for dawn in [1, 2]:
		sim.minutes = 6.0 * 60.0 + 20.0
		sim.phase = Sim.phase_at(sim.minutes)
		sim.clock_min = float(dawn) * 1440.0 - 420.0 + sim.minutes
		sim.events.clear()
		for i in 600:
			sim.update(1.0 / 30.0)
			for e in sim.events:
				if e.type == "day_start":
					starts.append(e.day)
					hours.append(sim.hour)
			sim.events.clear()
	eq(starts, [2, 3], "one day_start per dawn, carrying the new day")
	if hours.size() == 2:
		near(hours[0], 6.5, 0.05, "at 06:30")
	# and nothing at dusk, nightfall or the start of a run
	sim.minutes = 18.0 * 60.0 + 50.0
	sim.phase = Sim.phase_at(sim.minutes)
	sim.events.clear()
	var stray := 0
	for i in 900:
		sim.update(1.0 / 30.0)
		for e in sim.events:
			if e.type == "day_start":
				stray += 1
		sim.events.clear()
	eq(stray, 0, "no day_start through dusk and into the night")
	g.world.free()


func test_run_arguments_are_parsed() -> void:
	eq(Scenario.run_from_args([]), {}, "no arguments: no choice")
	eq(Scenario.run_from_args(["--shot=/tmp/a.png", "--hour=21"]), {}, "other flags are ignored")
	eq(Scenario.run_from_args(["--new=2", "--seed=7"]), {"difficulty": 2, "seed": 7}, "difficulty and seed")
	eq(Scenario.run_from_args(["--new=0"]), {"difficulty": 0}, "difficulty alone")
	eq(Scenario.run_from_args(["--seed=5"]), {"difficulty": 1, "seed": 5}, "a seed alone starts a standard run")
	eq(Scenario.run_from_args(["--new=9"]), {"difficulty": 2}, "too high is clamped")
	eq(Scenario.run_from_args(["--new=-3"]), {"difficulty": 0}, "too low is clamped")
	eq(Scenario.run_from_args(["--new=abc", "--seed=x"]), {}, "garbage is ignored")
	eq(Scenario.run_from_args(["--load=user://quicksave.json"]), {"load": "user://quicksave.json"}, "a save to load")
	eq(Scenario.run_from_args(["--load=/tmp/a b.json", "--new=1", "--seed=3"]), {"load": "/tmp/a b.json"}, "loading wins over a new run")
	eq(Scenario.run_from_args(["--load="]), {}, "an empty path is nothing")
	eq(Scenario.run_from_args(["--seed=-12"]), {"difficulty": 1, "seed": -12}, "a negative seed is a seed")


# ------------------------------------------------------------------ harness --

## Walls nothing breaks, so a game of the harness stays cheap to play (hunters
## inside the yard are what make a night expensive).
func _fortify(sim) -> void:
	for s in sim.segments:
		s.max_hp = 50000.0
		s.hp = 50000.0


func test_the_harness_plays_a_three_day_game() -> void:
	var r: Dictionary = Balance.play(5, 1, 3, 5.0, true, _fortify)
	var rows: Array = r.rows
	check(rows.size() >= 1, "it logs rows")
	eq(rows[0].day, 1, "the first row is day 1")
	for i in rows.size():
		var row: Dictionary = rows[i]
		for key in ["day", "food", "water", "scrap", "meds", "ammo", "alive", "dead", "turned", "wall_hp", "kills"]:
			check(row.has(key), "row %d has %s" % [i, key])
		check(row.food >= 0.0 and row.water >= 0.0 and row.scrap >= 0.0 and row.meds >= 0.0 and row.ammo >= 0.0, "no stock below zero (row %d)" % i)
		check(row.alive >= 0 and row.alive <= 6, "alive is between 0 and 6 (row %d)" % i)
		if i > 0:
			check(row.day == rows[i - 1].day + 1 or row.alive == 0, "days follow one another (row %d)" % i)
	if r.outcome == "survived":
		eq(rows.size(), 4, "three days survived: the start of days 1 to 3 and the dawn after")
		eq(r.day, 3, "three days reached")
	else:
		eq(r.outcome, "defeat", "the only other outcome")
		eq(rows[rows.size() - 1].alive, 0, "a defeat ends with nobody alive")


func test_the_harness_is_reproducible() -> void:
	var a: Dictionary = Balance.play(9, 1, 1, 5.0, true, _fortify)
	var b: Dictionary = Balance.play(9, 1, 1, 5.0, true, _fortify)
	eq(a.rows, b.rows, "the same seed plays the same game")
	check(a.rows.size() >= 1, "and it is a game")


func _job_of(sim, first: String) -> String:
	for p in sim.people:
		if p.first == first:
			return sim.jobs.job_of(p)
	return "?"


func test_the_policy_sets_the_stations_the_way_a_sensible_player_does() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	policy.tick()
	eq(float(sim.jobs.setting("bench", "ammo_target")), Balance.Policy.BENCH_TARGET, "the bench makes ammo up to the target")
	eq(float(sim.jobs.setting("bench", "scrap_reserve")), Balance.Policy.BENCH_RESERVE, "keeping scrap for the walls")
	eq(float(sim.jobs.setting("builders", "repair_below")), Balance.Policy.WALL_BELOW, "and the wall crew mends what is under the threshold")
	eq(_job_of(sim, "Ruth"), "radio", "the radio desk stays staffed")
	eq(_job_of(sim, "Marcus"), "watch", "and the lookout post")
	eq(_job_of(sim, "Ana"), "infirmary", "and the infirmary")
	for first in ["Dez", "Walt", "Hector"]:
		check(_job_of(sim, first) in ["bench", "builders", "garden"], "%s is on one of the three stations that are moved by need: %s" % [first, _job_of(sim, first)])
	eq(sim.jobs.crew_of("garden").size() + sim.jobs.crew_of("builders").size() + sim.jobs.crew_of("bench").size(), 3, "all three are placed")
	g.world.free()


## How many people are on the three stations the policy moves by need (the bench, the wall crew, the beds).
func _on_the_moving_stations(sim) -> int:
	return sim.jobs.crew_of("garden").size() + sim.jobs.crew_of("builders").size() + sim.jobs.crew_of("bench").size()


func test_the_policy_staffs_a_vacant_desk_from_the_rest_and_lets_the_radio_go_first() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	for p in sim.people:
		if p.first == "Ana":
			p.dead = true
	var policy = Balance.Policy.new(sim)
	policy.tick()
	check(sim.jobs.crew_of("infirmary").size() == 1, "someone takes the infirmary when the nurse is gone")
	eq(_job_of(sim, "Marcus"), "watch", "the lookout stays where he is")
	eq(sim.jobs.crew_of("radio").size(), 0, "with five left the radio desk is the first to go unstaffed")
	eq(_on_the_moving_stations(sim), 3, "and three hands stay on the bench, the wall crew and the beds")
	g.world.free()


func test_the_policy_keeps_no_desk_when_only_three_are_left() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	for p in sim.people:
		if p.first in ["Ana", "Marcus", "Walt"]:
			p.dead = true
	sim.stock.scrap = 40.0
	sim.stock.ammo = 100.0
	var policy = Balance.Policy.new(sim)
	policy.tick()
	for id in ["radio", "watch", "infirmary"]:
		eq(sim.jobs.crew_of(id).size(), 0, "nobody is kept at the %s with three people left" % id)
	eq(_on_the_moving_stations(sim), 3, "all three work: the bench, the wall crew and the beds")
	check(sim.jobs.crew_of("bench").size() >= 1, "and the bench has somebody to make the ammo from the scrap")
	g.world.free()


func test_the_policy_gives_the_bench_to_the_best_builder() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	sim.stock.ammo = 120.0
	sim.stock.scrap = 40.0
	sim.segments[8].hp = sim.segments[8].max_hp * 0.2    # the walls want hands too, and more than the bench does
	var policy = Balance.Policy.new(sim)
	policy.tick()
	var best = null
	for first in ["Dez", "Walt", "Hector"]:
		for p in sim.people:
			if p.first == first and (best == null or p.skills.Building > best.skills.Building):
				best = p
	eq(sim.jobs.job_of(best), "bench", "%s, the best builder of the three, makes the ammo" % best.first)
	g.world.free()


func test_the_policy_puts_two_people_on_the_beds_when_the_food_runs_short() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	sim.stock.food = 4.0
	var policy = Balance.Policy.new(sim)
	policy.tick()
	eq(sim.jobs.crew_of("garden").size(), 2, "two gardeners")
	g.world.free()


func test_the_policy_sends_the_wall_crew_where_the_walls_are_worn() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	sim.segments[8].hp = sim.segments[8].max_hp * 0.2
	sim.stock.ammo = 500.0
	var policy = Balance.Policy.new(sim)
	policy.tick()
	check(sim.jobs.crew_of("builders").size() >= 1, "the wall crew has someone")
	g.world.free()


func test_the_policy_moves_people_once_a_morning() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	policy.tick()
	var moves: int = policy.moves
	policy.tick()
	policy.tick()
	eq(policy.moves, moves, "not again the same morning")
	g.world.free()


func test_the_policy_goes_to_the_hardware_store_for_scrap_when_the_scrapyard_is_picked_over() -> void:
	var g := Helpers.make(8, 1)
	var sim = g.sim
	sim.stock = {"ammo": 200.0, "scrap": 4.0, "food": 100.0, "water": 200.0, "meds": 20.0}
	sim.scavenge.raids["scrapyard"] = [sim.day]
	var policy = Balance.Policy.new(sim)
	policy.tick()
	eq(sim.scavenge.parties.size(), 1, "a party goes")
	if sim.scavenge.parties.size() == 1:
		eq(sim.scavenge.parties[0].site, "hardware", "to the hardware store, which has scrap too")
	g.world.free()


func test_the_policy_sends_scavengers_when_a_stock_runs_low() -> void:
	var cases := [
		{"stock": "food", "value": 3.0, "site": "houses"},
		{"stock": "water", "value": 5.0, "site": "houses"},
		{"stock": "scrap", "value": 4.0, "site": "scrapyard"},
		{"stock": "ammo", "value": 20.0, "site": "hardware"},
		{"stock": "meds", "value": 1.0, "site": "pharmacy"},
	]
	for c in cases:
		var g := Helpers.make(8, 1)
		var sim = g.sim
		if not sim.scavenge.can_send():
			g.world.free()
			continue # the scavenging module is not in yet
		sim.stock = {"ammo": 200.0, "scrap": 50.0, "food": 100.0, "water": 200.0, "meds": 20.0}
		sim.stock[c.stock] = c.value
		var policy = Balance.Policy.new(sim)
		policy.tick()
		var parties: Array = sim.scavenge.parties
		eq(parties.size(), 1, "a party goes when %s is low" % c.stock)
		if parties.size() == 1:
			eq(parties[0].site, c.site, "to the site that helps with %s" % c.stock)
			eq(parties[0].members.size(), 2, "two scavengers")
		g.world.free()
