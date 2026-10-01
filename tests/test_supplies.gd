## Tests for the supplies rules: meals, hunger and thirst, the dawn sources, what
## repairs cost, the low-stock alerts, the marks on the cards and the save.
## Most tests keep the other rule modules out of the way (see `_calm`), so they
## see only the supplies module; the last one runs everything together.
extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const Sim := preload("res://scripts/sim/sim.gd")

const WARN := Color("#e8953a")
const DANGER := Color("#e0584a")


## Stands in for the other rule modules: every hook the rules call, doing nothing.
class Quiet:
	extends RefCounted

	func setup(_s) -> void:
		pass

	func start() -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func perf(_p) -> float:
		return 1.0

	func goal_for(_p):
		return null

	func after_bite(_z, _p) -> void:
		pass

	func on_wall_claw(_z, _seg) -> void:
		pass

	func on_downed(_p, _cause: String) -> void:
		pass

	func add_wound(_p, _kind: String) -> void:
		pass

	func kill(_p, _cause: String) -> void:
		pass

	func status_of(_p) -> Array:
		return []

	func gizmo(_id: String, _sel) -> bool:
		return false

	func lure_seg():
		return null

	func total_days() -> int:
		return 30

	func save() -> Dictionary:
		return {}

	func load_state(_d: Dictionary) -> void:
		pass


## Records whom the supplies module brings down, and for what.
class MedSpy:
	extends Quiet
	var downed_calls: Array = []

	func on_downed(p, cause: String) -> void:
		downed_calls.append([p.id, cause])
		p.downed = true


## A new run (day 1, 07:00) with none of the dead about, no night spawning and
## the other modules silenced, so that only the supplies rules move. Free
## `g.world` at the end of the test.
func _calm(seed_value: int = 1, difficulty: int = 1) -> Dictionary:
	var g := Helpers.make(seed_value, difficulty)
	var sim = g.sim
	sim.zombies.clear()
	sim.spawn_t = 1.0e9
	sim.waves.enabled = false
	sim.medical = MedSpy.new()
	sim.scavenge = Quiet.new()
	sim.scenario = Quiet.new()
	sim.tactics = Quiet.new()
	return g


## Sets the clock to `hour` of the current day: a jump, as the screenshot flags do.
func _at(sim, hour: float) -> void:
	sim.minutes = hour * 60.0
	sim.phase = Sim.phase_at(sim.minutes)


## Steps the rules for `seconds` in steps of `dt` (the game itself steps at most 1/30).
func _run(sim, seconds: float, dt: float = 0.1) -> void:
	for i in int(seconds / dt + 0.5):
		sim.update(dt)


## Steps until the clock is within a hundredth of a game hour of `hour` (0 to 24),
## this day or the next.
func _run_to_hour(sim, hour: float, dt: float = 0.1) -> void:
	var guard := 0
	while absf(fposmod(sim.hour - hour + 12.0, 24.0) - 12.0) > 0.01 and guard < 100000:
		sim.update(dt)
		guard += 1


## How many banners with this title the rules have raised.
func _banners(sim, text: String) -> int:
	var n := 0
	for e in sim.events:
		if e.type == "banner" and e.text == text:
			n += 1
	return n


# ------------------------------------------------------------------- meals --

func test_a_new_run_starts_fed_and_the_first_meal_is_at_one() -> void:
	var g := _calm()
	var sim = g.sim
	_run(sim, 5.0)
	near(sim.stock.food, Sim.START_STOCK.food, 1e-9, "nothing is eaten at the start")
	near(sim.stock.water, Sim.START_STOCK.water, 1e-9, "nothing is drunk at the start")
	for p in sim.people:
		near(p.hunger_h, 0.25, 0.01, "%s has gone a quarter hour without food" % p.first)
	g.world.free()


func test_each_meal_takes_a_third_of_a_food_and_half_a_water_a_person() -> void:
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	var food: float = sim.stock.food
	var water: float = sim.stock.water
	for meal_hour in [13.0, 19.0, 7.0]:
		_run_to_hour(sim, meal_hour - 0.1)
		near(sim.stock.food, food, 1e-9, "nothing is eaten before %d:00" % int(meal_hour))
		near(sim.stock.water, water, 1e-9, "nothing is drunk before %d:00" % int(meal_hour))
		_run(sim, 4.0)
		food -= 6.0 / 3.0
		water -= 6.0 * 0.5
		near(sim.stock.food, food, 1e-6, "six people eat a third each at %d:00" % int(meal_hour))
		near(sim.stock.water, water, 1e-6, "six people drink half each at %d:00" % int(meal_hour))
		for p in sim.people:
			near(p.hunger_h, 0.1, 0.05, "%s just ate" % p.first)
			near(p.thirst_h, 0.1, 0.05, "%s just drank" % p.first)
	g.world.free()


func test_a_meal_is_served_once_however_the_steps_fall() -> void:
	# 07:00 on day 1 to 07:30 on day 3: past two midnights and two turns of the day
	# at 06:30. The meals are 13:00 and 19:00 on day 1, three on day 2, 07:00 on day 3.
	# (12, 20 and 30 seconds are 36, 60 and 90 game minutes: one step can cross 06:30 and 07:00 together)
	for dt in [0.1, 0.25, 1.0, 4.0, 8.0, 12.0, 20.0, 30.0]:
		var g := _calm()
		var sim = g.sim
		sim.supplies.sources_on = false
		var food: float = sim.stock.food
		var water: float = sim.stock.water
		var guard := 0
		while sim.clock_min < 48.5 * 60.0 and guard < 100000:
			sim.update(dt)
			guard += 1
		eq(sim.day, 3, "day 3 at step %s" % dt)
		near(food - sim.stock.food, 6.0 * 2.0, 1e-6, "six meals of food at step %s" % dt)
		near(water - sim.stock.water, 6.0 * 3.0, 1e-6, "six meals of water at step %s" % dt)
		g.world.free()


func test_a_meal_is_served_once_at_the_steps_of_the_game() -> void:
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	var food: float = sim.stock.food
	for i in int(24.5 * 20.0 * 30.0):
		sim.update(1.0 / 30.0)
	near(food - sim.stock.food, 3.0 * 2.0, 1e-6, "13:00, 19:00 and 07:00 at 30 steps a second")
	g.world.free()


func test_each_meal_time_is_crossed_exactly_once_at_awkward_step_sizes() -> void:
	# Steps that land exactly on a meal time (0.1 s is 0.3 game minutes), steps
	# that straddle it, and odd ones: from just before each meal to just after.
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 5
	var steps: Array = [0.1, 0.05, 0.2, 0.3, 1.0 / 30.0, 1.0 / 15.0, 0.5, 1.0]
	for i in 24:
		steps.append(rnd.randf_range(0.01, 1.0))
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	for dt in steps:
		for meal_hour in [7.0, 13.0, 19.0]:
			_at(sim, meal_hour - 0.05)
			var food: float = sim.stock.food
			var guard := 0
			while sim.hour < meal_hour + 0.05 and guard < 100000:
				sim.update(dt)
				guard += 1
			near(food - sim.stock.food, 2.0, 1e-6, "one meal at %d:00 with steps of %s" % [int(meal_hour), str(dt)])
			sim.stock.food = 100.0
	g.world.free()


func test_setting_the_clock_does_not_serve_meals_but_the_next_one_is_on_time() -> void:
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	var food: float = sim.stock.food
	_at(sim, 21.0)
	_run(sim, 2.0)
	near(sim.stock.food, food, 1e-9, "a jump past three meal times serves none of them")
	_run_to_hour(sim, 6.9)
	_run(sim, 4.0)
	near(sim.stock.food, food - 2.0, 1e-6, "07:00 is served on time")
	_at(sim, 20.0)
	_run(sim, 1.0)
	near(sim.stock.food, food - 2.0, 1e-6, "jumping over 13:00 and 19:00 serves neither")
	_at(sim, 8.0)                    # and back: the day's later meals are ahead again
	_run_to_hour(sim, 12.9)
	_run(sim, 4.0)
	near(sim.stock.food, food - 4.0, 1e-6, "set back to the morning, 13:00 is on time")
	g.world.free()


func test_a_short_stock_feeds_the_first_people_and_leaves_the_rest_hungry() -> void:
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	_run_to_hour(sim, 12.9)
	sim.stock.food = 0.6
	sim.stock.water = 1.0
	_run(sim, 4.0)
	eq(sim.stock.food, 0.0, "the food is all gone")
	eq(sim.stock.water, 0.0, "the water is all gone")
	for i in sim.people.size():
		var p = sim.people[i]
		if i < 2:
			check(p.hunger_h < 0.3, "%s was fed (the second with what was left)" % p.first)
			check(p.thirst_h < 0.3, "%s was given water" % p.first)
		else:
			check(p.hunger_h > 6.0, "%s went without food" % p.first)
			check(p.thirst_h > 6.0, "%s went without water" % p.first)
	g.world.free()


func test_a_serving_under_a_quarter_of_a_share_does_not_count_as_a_meal() -> void:
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	_run_to_hour(sim, 12.9)
	sim.stock.food = 2.0 / 3.0 + 0.05   # the third person gets 0.05, under 1/12
	sim.stock.water = 1.0 + 0.05        # and 0.05 of a half share: under 1/8
	_run(sim, 4.0)
	check(sim.people[1].hunger_h < 0.3, "the second person was fed in full")
	check(sim.people[2].hunger_h > 6.0, "a mouthful of food is not a meal")
	check(sim.people[2].thirst_h > 6.0, "a mouthful of water is not a drink")
	eq(sim.stock.food, 0.0, "but the mouthful is taken")
	g.world.free()
	var h := _calm()
	var sim2 = h.sim
	sim2.supplies.sources_on = false
	_run_to_hour(sim2, 12.9)
	sim2.stock.food = 2.0 / 3.0 + 0.1   # 0.1 is over a quarter of a third
	sim2.stock.water = 1.0 + 0.2        # 0.2 is over a quarter of a half
	_run(sim2, 4.0)
	check(sim2.people[2].hunger_h < 0.3, "a serving over a quarter of the share is a meal")
	check(sim2.people[2].thirst_h < 0.3, "and so is over a quarter of the water share")
	h.world.free()


func test_the_away_and_the_dead_are_not_fed_but_the_downed_are() -> void:
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	sim.people[0].away = {"kind": "test"}
	sim.people[1].dead = true
	sim.people[2].downed = true
	_run_to_hour(sim, 12.9)
	var food: float = sim.stock.food
	var water: float = sim.stock.water
	_run(sim, 4.0)
	near(food - sim.stock.food, 4.0 / 3.0, 1e-6, "four people eat: not the away, not the dead")
	near(water - sim.stock.water, 4.0 * 0.5, 1e-6, "four people drink")
	check(sim.people[2].hunger_h < 0.3, "a person lying downed still eats")
	near(sim.people[0].hunger_h, 0.0, 1e-9, "the away one's hunger holds still")
	near(sim.people[1].hunger_h, 0.0, 1e-9, "the dead one's too")
	g.world.free()


func test_the_meal_banner_comes_once_per_shortage() -> void:
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	_run_to_hour(sim, 12.9)
	_run(sim, 4.0)
	eq(_banners(sim, "Short rations"), 0, "a full meal raises no banner")
	sim.stock.food = 1.0
	_run_to_hour(sim, 18.9)
	_run(sim, 4.0)
	eq(_banners(sim, "Short rations"), 1, "the first short meal raises one")
	var sub := ""
	for e in sim.events:
		if e.type == "banner" and e.text == "Short rations":
			sub = e.sub
	check(sub.contains("food") and not sub.contains("water"), "it names the food: " + sub)
	sim.stock.food = 0.0
	_run_to_hour(sim, 6.9)
	_run(sim, 4.0)
	eq(_banners(sim, "Short rations"), 1, "the next short meal adds none")
	sim.stock.food = 10.0
	_run_to_hour(sim, 12.9)
	_run(sim, 4.0)
	eq(_banners(sim, "Short rations"), 1, "a full meal again raises none")
	sim.stock.water = 0.5
	_run_to_hour(sim, 18.9)
	_run(sim, 4.0)
	eq(_banners(sim, "Short rations"), 2, "a new shortage raises a new banner")
	g.world.free()


# ----------------------------------------------------- hunger and thirst --

func test_hunger_and_thirst_grow_with_game_time_but_not_for_the_away_or_the_dead() -> void:
	var g := _calm()
	var sim = g.sim
	sim.people[1].away = {"kind": "test"}
	sim.people[2].dead = true
	_run(sim, 20.0)   # one game hour: 07:00 to 08:00
	for i in sim.people.size():
		var p = sim.people[i]
		var held: bool = i == 1 or i == 2
		near(p.hunger_h, 0.0 if held else 1.0, 0.01, "%s hunger" % p.first)
		near(p.thirst_h, 0.0 if held else 1.0, 0.01, "%s thirst" % p.first)
	g.world.free()


func test_hunger_and_thirst_cost_a_fifth_of_performance_after_18_and_14_hours() -> void:
	var g := _calm()
	var sim = g.sim
	var p = sim.people[0]
	near(sim.supplies.perf(p), 1.0, 1e-9, "a fed person works at full rate")
	p.hunger_h = 17.99
	near(sim.supplies.perf(p), 1.0, 1e-9, "just under 18 hours of hunger")
	p.hunger_h = 18.0
	near(sim.supplies.perf(p), 0.8, 1e-9, "18 hours without food")
	p.hunger_h = 0.0
	p.thirst_h = 13.99
	near(sim.supplies.perf(p), 1.0, 1e-9, "just under 14 hours of thirst")
	p.thirst_h = 14.0
	near(sim.supplies.perf(p), 0.8, 1e-9, "14 hours without water")
	p.hunger_h = 30.0
	near(sim.supplies.perf(p), 0.8, 1e-9, "both at once is still a fifth, not more")
	near(sim.perf(p), 0.8, 1e-9, "and the rules' perf sees it")
	g.world.free()


func test_starving_costs_a_health_point_an_hour() -> void:
	var g := _calm()
	var sim = g.sim
	sim.people[0].hunger_h = 36.0    # starving
	sim.people[1].thirst_h = 24.0    # parched
	sim.people[2].hunger_h = 40.0    # both at once
	sim.people[2].thirst_h = 30.0
	sim.people[3].hunger_h = 34.0    # not yet
	sim.people[3].thirst_h = 20.0
	_run(sim, 20.0)           # one game hour
	near(sim.people[0].hp, 99.0, 0.01, "36 hours without food: a health point an hour")
	near(sim.people[1].hp, 99.0, 0.01, "24 hours without water: a health point an hour")
	near(sim.people[2].hp, 99.0, 0.01, "starving and parched is still one an hour")
	near(sim.people[3].hp, 100.0, 1e-9, "under 36 and 24 hours costs nothing")
	near(sim.people[4].hp, 100.0, 1e-9, "a fed person loses nothing")
	g.world.free()


func test_health_loss_starts_at_36_hours_of_hunger_and_24_of_thirst() -> void:
	var g := _calm()
	var sim = g.sim
	sim.people[0].hunger_h = 35.99    # one step of 1/30 s takes it to 35.9917: still fine
	sim.people[1].hunger_h = 35.999   # one step takes it over 36
	sim.people[2].thirst_h = 23.99
	sim.people[3].thirst_h = 23.999
	sim.update(1.0 / 30.0)
	eq(sim.people[0].hp, 100.0, "just under 36 hours of hunger costs nothing")
	check(sim.people[1].hp < 100.0, "36 hours of hunger costs health")
	eq(sim.people[2].hp, 100.0, "just under 24 hours of thirst costs nothing")
	check(sim.people[3].hp < 100.0, "24 hours of thirst costs health")
	g.world.free()


func test_starvation_that_reaches_zero_health_goes_to_the_medical_module() -> void:
	var g := _calm()
	var sim = g.sim
	var spy: MedSpy = sim.medical
	sim.people[0].hunger_h = 40.0
	sim.people[0].hp = 0.6
	sim.people[1].thirst_h = 30.0
	sim.people[1].hp = 0.3
	sim.people[2].hunger_h = 40.0    # both: thirst is further gone (30 of 24, 40 of 36)
	sim.people[2].thirst_h = 30.0
	sim.people[2].hp = 0.2
	sim.people[3].hunger_h = 40.0    # already down: nothing more to call
	sim.people[3].hp = 0.0
	sim.people[3].downed = true
	_run(sim, 20.0)
	eq(spy.downed_calls.size(), 3, "three people went down, each once")
	check(["ruth", "hunger"] in spy.downed_calls, "Ruth from hunger")
	check(["dez", "thirst"] in spy.downed_calls, "Dez from thirst")
	check(["ana", "thirst"] in spy.downed_calls, "Ana from the worse of the two")
	eq(sim.people[0].hp, 0.0, "health stops at zero")
	g.world.free()


func test_the_dead_do_not_starve() -> void:
	var g := _calm()
	var sim = g.sim
	var spy: MedSpy = sim.medical
	sim.people[0].dead = true
	sim.people[0].hunger_h = 40.0
	sim.people[0].hp = 50.0
	sim.people[1].away = {"kind": "test"}
	sim.people[1].thirst_h = 30.0
	sim.people[1].hp = 50.0
	_run(sim, 20.0)
	eq(sim.people[0].hp, 50.0, "a dead person's health is left alone")
	eq(sim.people[1].hp, 50.0, "an away person's too: they are on trip rations")
	eq(spy.downed_calls.size(), 0, "nobody was brought down")
	g.world.free()


# ----------------------------------------------------------------- sources --

func test_the_beds_and_barrels_pay_out_once_a_day_at_dawn() -> void:
	var g := _calm(4)
	var sim = g.sim
	var food: float = sim.stock.food
	var water: float = sim.stock.water
	_run_to_hour(sim, 6.4)    # the night of day 1: two meals eaten, day not turned yet
	eq(sim.day, 1, "still day 1 at 06:24")
	near(sim.stock.food, food - 4.0, 1e-6, "before dawn only two meals are gone")
	near(sim.stock.water, water - 6.0, 1e-6, "and two meals of water")
	_run(sim, 6.0)            # past 06:30
	eq(sim.day, 2, "day 2 has begun")
	var rain: bool = sim.weather == "rain"
	near(sim.stock.food, food - 4.0 + 3.0, 1e-6, "the vegetable beds gave 3 food")
	near(sim.stock.water, water - 6.0 + (10.0 if rain else 2.0), 1e-6, "the barrels gave 2 water, 10 in the rain")
	var weather: String = sim.weather
	_run(sim, 100.0)          # five more hours, with the 07:00 meal in them
	eq(sim.weather, weather, "the weather holds all day")
	near(sim.stock.food, food - 4.0 + 3.0 - 2.0, 1e-6, "no second payout in the same day")
	near(sim.stock.water, water - 6.0 + (10.0 if rain else 2.0) - 3.0, 1e-6, "nor for the water")
	g.world.free()


func test_a_rainy_dawn_says_so() -> void:
	var g := _calm()
	var sim = g.sim
	var found_rain := false
	var found_clear := false
	for s in range(1, 60):
		sim.rng.seed = s
		sim.alerts.clear()
		sim.supplies.roll_dawn()
		if sim.weather == "rain":
			found_rain = true
			check(sim.alerts.has("rain"), "rain at seed %d is reported" % s)
		else:
			found_clear = true
			check(not sim.alerts.has("rain"), "a clear day is not reported")
	check(found_rain and found_clear, "both kinds of day came up in 59 seeds")
	g.world.free()


func test_without_anyone_on_the_map_the_beds_and_barrels_give_nothing() -> void:
	var g := _calm()
	var sim = g.sim
	for p in sim.people:
		p.away = {"kind": "test"}
	var food: float = sim.stock.food
	var water: float = sim.stock.water
	sim.supplies.roll_dawn()
	eq(sim.stock.food, food, "everyone away: nobody tends the garden")
	eq(sim.stock.water, water, "nor the barrels")
	for p in sim.people:
		p.away = null
		p.dead = true
	sim.supplies.roll_dawn()
	eq(sim.stock.food, food, "everyone dead: nobody tends the garden")
	sim.people[3].dead = false       # one living person on the map is enough
	sim.supplies.roll_dawn()
	near(sim.stock.food, food + 3.0, 1e-9, "one person tends the garden")
	check(sim.stock.water >= water + 2.0 - 1e-9, "and the barrels")
	g.world.free()


func test_rain_is_about_one_day_in_three() -> void:
	var g := _calm()
	var sim = g.sim
	var rain := 0
	for s in range(1, 401):
		sim.rng.seed = s
		var water: float = sim.stock.water
		var food: float = sim.stock.food
		sim.supplies.roll_dawn()
		var wet: bool = sim.weather == "rain"
		if wet:
			rain += 1
		near(sim.stock.food - food, 3.0, 1e-9, "the garden gives 3 (seed %d)" % s)
		near(sim.stock.water - water, 10.0 if wet else 2.0, 1e-9, "the barrels give 10 in the rain, else 2 (seed %d)" % s)
	check(rain >= 105 and rain <= 162, "about a third of 400 seeds are rainy, got %d" % rain)
	# one stream of days, as a run sees them
	sim.rng.seed = 77
	rain = 0
	for i in 900:
		sim.supplies.roll_dawn()
		if sim.weather == "rain":
			rain += 1
	check(rain >= 255 and rain <= 345, "about a third of 900 days are rainy, got %d" % rain)
	g.world.free()


func test_the_weather_comes_from_the_seed() -> void:
	var seqs: Array = []
	for seed_value in [7, 7, 8]:
		var g := _calm(seed_value)
		var sim = g.sim
		var seq := ""
		for i in 30:
			sim.supplies.roll_dawn()
			seq += "r" if sim.weather == "rain" else "c"
		seqs.append(seq)
		g.world.free()
	eq(seqs[0], seqs[1], "the same seed gives the same weather")
	check(seqs[0] != seqs[2], "another seed gives another")


# ----------------------------------------------------------------- repairs --

func test_repairs_cost_one_scrap_per_ten_points() -> void:
	var g := _calm()
	var sim = g.sim
	sim.stock.scrap = 24.0
	near(sim.supplies.repair_budget(10.0), 10.0, 1e-9, "ten points are allowed")
	near(sim.stock.scrap, 23.0, 1e-9, "and cost one scrap")
	near(sim.supplies.repair_budget(25.0), 25.0, 1e-9, "twenty-five points are allowed")
	near(sim.stock.scrap, 20.5, 1e-9, "and cost two and a half")
	near(sim.supplies.repair_budget(0.3), 0.3, 1e-9, "a step's worth of repair")
	near(sim.stock.scrap, 20.47, 1e-9, "costs its share")
	near(sim.supplies.repair_budget(0.0), 0.0, 1e-9, "nothing wanted, nothing spent")
	near(sim.stock.scrap, 20.47, 1e-9, "and no scrap goes")
	check(not sim.alerts.has("no-scrap"), "there is scrap, so there is no alert")
	g.world.free()


func test_repairs_stop_with_the_last_scrap_and_say_why() -> void:
	var g := _calm()
	var sim = g.sim
	sim.stock.scrap = 1.5
	near(sim.supplies.repair_budget(30.0), 15.0, 1e-9, "only what the scrap pays for")
	eq(sim.stock.scrap, 0.0, "all the scrap is used and never more")
	check(sim.alerts.has("no-scrap"), "the alert is raised when the scrap hits zero")
	var a: Dictionary = sim.alerts["no-scrap"]
	eq(a.text, "No scrap: repairs stopped", "the alert's words")
	eq(a.level, "warn", "a warning")
	near(a.ttl, 8.0, 1e-9, "for eight seconds")
	sim.alerts.clear()
	eq(sim.supplies.repair_budget(5.0), 0.0, "with no scrap, no repairs")
	eq(sim.stock.scrap, 0.0, "and the stock stays at zero")
	check(sim.alerts.has("no-scrap"), "and the alert is there again while someone tries")
	g.world.free()


func test_a_person_repairing_a_wall_pays_for_it_in_scrap() -> void:
	var g := _calm()
	var sim = g.sim
	var seg = sim.segments[4]
	sim._damage_segment(seg, 100.0)
	var hp0: float = seg.hp
	var p = sim.people[1]
	p.x = seg.center.x
	p.y = seg.center.y
	sim.stock.scrap = 2.0
	sim.order_repair(p, seg)
	_run(sim, 10.0)           # 90 points of hammering, 20 of them paid for
	near(seg.hp, hp0 + 20.0, 0.05, "two scrap mend twenty points")
	eq(sim.stock.scrap, 0.0, "the scrap is spent")
	check(sim.alerts.has("no-scrap"), "and the crew are told why the hammering has stopped")
	sim.stock.scrap = 3.0
	_run(sim, 10.0)
	near(seg.hp, hp0 + 50.0, 0.05, "three more scrap mend thirty more")
	eq(sim.stock.scrap, 0.0, "and are spent")
	g.world.free()


func test_a_hungry_person_repairs_slower_but_the_scrap_per_point_is_the_same() -> void:
	var g := _calm()
	var sim = g.sim
	var seg = sim.segments[4]
	sim._damage_segment(seg, 100.0)
	var hp0: float = seg.hp
	var p = sim.people[1]
	p.hunger_h = 20.0                # hungry: works at 0.8
	p.x = seg.center.x
	p.y = seg.center.y
	sim.stock.scrap = 100.0
	sim.order_repair(p, seg)
	_run(sim, 5.0)
	var mended: float = seg.hp - hp0
	near(mended, 5.0 * (Sim.REPAIR_BASE + float(p.def.skills.Building)) * 0.8, 0.5, "a hungry person mends at 0.8 of the rate")
	near(100.0 - sim.stock.scrap, mended / 10.0, 1e-6, "and pays one scrap per ten points mended")
	g.world.free()


# --------------------------------------------------------------- days left --

func test_days_left_is_the_stock_over_the_living_crews_daily_use() -> void:
	var g := _calm()
	var sim = g.sim
	sim.stock.food = 30.0
	sim.stock.water = 45.0
	near(sim.supplies.days_left("food"), 5.0, 1e-9, "30 food, six eating 1 a day")
	near(sim.supplies.days_left("water"), 5.0, 1e-9, "45 water, six drinking 1.5 a day")
	sim.people[0].dead = true
	near(sim.supplies.days_left("food"), 6.0, 1e-9, "one fewer mouth")
	near(sim.supplies.days_left("water"), 6.0, 1e-9, "and one fewer to drink")
	sim.people[1].away = {"kind": "test"}
	near(sim.supplies.days_left("food"), 6.0, 1e-9, "the away are still counted: they come back hungry")
	sim.stock.food = 0.0
	eq(sim.supplies.days_left("food"), 0.0, "no food is no days")
	sim.stock.food = 5000.0
	eq(sim.supplies.days_left("food"), 99.0, "never more than 99")
	eq(sim.supplies.days_left("ammo"), 99.0, "a thing nobody eats lasts for ever")
	for p in sim.people:
		p.dead = true
	eq(sim.supplies.days_left("food"), 99.0, "nobody alive: 99")
	eq(sim.supplies.days_left("water"), 99.0, "nobody alive: 99 for water too")
	g.world.free()


# ------------------------------------------------------------------ status --

func test_the_marks_on_a_card_follow_hunger_and_thirst() -> void:
	var g := _calm()
	var sim = g.sim
	var p = sim.people[0]
	eq(sim.supplies.status_of(p), [], "a fed person has no marks")
	p.hunger_h = 17.9
	p.thirst_h = 13.9
	eq(sim.supplies.status_of(p), [], "nor just before the limits")
	p.hunger_h = 18.0
	var marks: Array = sim.supplies.status_of(p)
	eq(marks.size(), 1, "hunger is one mark")
	eq(marks[0].icon, "hungry", "the hungry icon")
	eq(marks[0].color, WARN, "in orange")
	eq(marks[0].tip, "Hungry", "with its tip")
	p.hunger_h = 36.0
	marks = sim.supplies.status_of(p)
	eq(marks[0].icon, "starving", "the starving icon")
	eq(marks[0].color, DANGER, "in red")
	eq(marks[0].tip, "Starving", "and its tip")
	p.hunger_h = 0.0
	p.thirst_h = 14.0
	marks = sim.supplies.status_of(p)
	eq(marks.size(), 1, "thirst is one mark")
	eq(marks[0].icon, "thirsty", "the thirsty icon")
	eq(marks[0].color, WARN, "in orange")
	eq(marks[0].tip, "Thirsty", "and its tip")
	p.thirst_h = 24.0
	marks = sim.supplies.status_of(p)
	eq(marks[0].icon, "thirsty", "severe thirst keeps the icon")
	eq(marks[0].color, DANGER, "but turns red")
	eq(marks[0].tip, "Parched", "and its tip")
	p.hunger_h = 20.0
	eq(sim.supplies.status_of(p).size(), 2, "hungry and parched: two marks")
	p.dead = true
	eq(sim.supplies.status_of(p), [], "the dead have no marks")
	p.dead = false
	p.away = {"kind": "test"}
	eq(sim.supplies.status_of(p), [], "nor the away")
	g.world.free()


# ------------------------------------------------------------------ alerts --

func test_a_low_stock_raises_an_alert_no_more_often_than_every_game_hour() -> void:
	var g := _calm()
	var sim = g.sim
	_run(sim, 1.0)
	check(not sim.alerts.has("low-food"), "plenty of food: no alert")
	check(not sim.alerts.has("low-water"), "plenty of water: no alert")
	sim.stock.food = 7.0             # 1.2 days for six
	_run(sim, 0.5)
	check(sim.alerts.has("low-food"), "under two days of food: an alert")
	check(not sim.alerts.has("low-water"), "the water is fine")
	sim.alerts.erase("low-food")
	_run(sim, 10.0)           # half a game hour
	check(not sim.alerts.has("low-food"), "not raised again within the hour")
	_run(sim, 11.0)           # past the hour
	check(sim.alerts.has("low-food"), "raised again after the hour")
	sim.stock.food = 100.0
	_run(sim, 0.5)
	check(not sim.alerts.has("low-food"), "gone once the stock is back")
	g.world.free()


func test_the_low_stock_alerts_say_how_bad_it_is() -> void:
	var cases := [
		[11.0, "warn", "about 1 day left"],       # 1.83 days: whole days, rounded down
		[7.0, "warn", "about 1 day left"],        # 1.17 days
		[3.0, "danger", "less than a day left"],  # half a day
		[0.0, "danger", "none left"],
	]
	for c in cases:
		var g := _calm()
		var sim = g.sim
		sim.stock.food = c[0]
		_run(sim, 0.5)
		var a: Dictionary = sim.alerts.get("low-food", {})
		eq(a.get("text", ""), "Food is running out", "the words at %s food" % str(c[0]))
		eq(a.get("level", ""), c[1], "the level at %s food" % str(c[0]))
		eq(a.get("sub", ""), c[2], "the days left at %s food" % str(c[0]))
		g.world.free()
	var g := _calm()
	var sim = g.sim
	sim.stock.water = 15.0           # 1.7 days for six drinking 1.5 each
	_run(sim, 0.5)
	var w: Dictionary = sim.alerts.get("low-water", {})
	eq(w.get("text", ""), "Water is running out", "the water's words")
	eq(w.get("sub", ""), "about 1 day left", "the water's days")
	check(w.get("at") is Vector2 and absf(w.at.x - 60.9) < 1.0, "the alert points at the rain barrels")
	check(not sim.alerts.has("low-food"), "with food to spare there is no food alert")
	g.world.free()


func test_the_days_left_line_counts_whole_days_rounded_down() -> void:
	var g := _calm()
	var sup = g.sim.supplies
	eq(sup._days_text(0.0), "none left", "no days")
	eq(sup._days_text(0.4), "less than a day left", "under a day")
	eq(sup._days_text(1.0), "about 1 day left", "one day")
	eq(sup._days_text(1.99), "about 1 day left", "just under two days is still one")
	eq(sup._days_text(2.0), "about 2 days left", "two days")
	eq(sup._days_text(5.7), "about 5 days left", "five and a bit")
	g.world.free()


func test_no_low_stock_alert_when_nobody_is_left_to_eat() -> void:
	var g := _calm()
	var sim = g.sim
	for p in sim.people:
		p.dead = true
	sim.stock.food = 0.0
	sim.stock.water = 0.0
	_run(sim, 1.0)
	check(not sim.alerts.has("low-food"), "nobody to feed: no alert")
	check(not sim.alerts.has("low-water"), "nobody to give water: no alert")
	g.world.free()


# -------------------------------------------------------------------- fuzz --

## "" if the books are straight, else what is wrong.
func _bad_state(sim) -> String:
	for k in sim.stock:
		var v: float = sim.stock[k]
		if is_nan(v) or is_inf(v) or v < 0.0:
			return "stock %s is %s" % [k, str(v)]
	for p in sim.people:
		for v in [p.hunger_h, p.thirst_h, p.hp]:
			if is_nan(v) or is_inf(v) or v < 0.0:
				return "%s has a bad number: %s" % [p.first, str(v)]
	var sup = sim.supplies
	if sup.meals_done < 0 or sup.meals_done > 3:
		return "meals_done is %d" % sup.meals_done
	return ""


func test_stocks_never_go_negative_in_random_five_day_runs() -> void:
	for s in range(1, 21):
		var g := _calm(s, s % 3)
		var sim = g.sim
		var rnd := RandomNumberGenerator.new()
		rnd.seed = 9000 + s
		var bad := ""
		var guard := 0
		while sim.clock_min < 5.0 * 24.0 * 60.0 and bad == "" and guard < 200000:
			guard += 1
			if rnd.randf() < 0.004:
				var p = sim.people[rnd.randi() % 6]
				p.away = null if p.away != null else {"kind": "fuzz"}
			if rnd.randf() < 0.0005:
				sim.people[1 + rnd.randi() % 5].dead = true
			if rnd.randf() < 0.004:
				sim.stock.food += rnd.randf_range(0.0, 14.0)
			if rnd.randf() < 0.004:
				sim.stock.water += rnd.randf_range(0.0, 20.0)
			if rnd.randf() < 0.004:
				sim.stock.scrap += rnd.randf_range(0.0, 20.0)
			if rnd.randf() < 0.002:
				sim.stock.food = 0.0
			if rnd.randf() < 0.05:
				sim.supplies.repair_budget(rnd.randf_range(0.0, 3.0))
			var held: Array = []
			for p in sim.people:
				held.append(p.dead or p.away != null)
			var before: Array = []
			for p in sim.people:
				before.append(p.hunger_h)
			sim.update(rnd.randf_range(0.1, 3.0))
			for i in sim.people.size():
				if held[i] and sim.people[i].hunger_h != before[i]:
					bad = "%s's hunger moved while they were away or dead" % sim.people[i].first
			if bad == "":
				bad = _bad_state(sim)
		eq(bad, "", "the books at seed %d" % s)
		check(guard < 200000, "the five days ended at seed %d" % s)
		g.world.free()


# -------------------------------------------------------------------- save --

func test_save_and_load_round_trip_through_json() -> void:
	var g := _calm(5)
	var sim = g.sim
	_at(sim, 14.0)
	sim.supplies.roll_dawn()
	sim.stock.food = 5.0
	_run(sim, 1.0)            # the low-food alert is raised and timed
	sim.supplies.short_of.food = true
	var d: Dictionary = sim.supplies.save()
	var text := JSON.stringify(d, "", true, true)   # full precision: the default prints 0.30000000000000004 as 0.3
	var parsed = JSON.parse_string(text)
	check(typeof(parsed) == TYPE_DICTIONARY, "the save is JSON")
	var h := _calm(5)
	h.sim.supplies.load_state(parsed)
	eq(h.sim.supplies.save(), d, "the round trip through JSON gives the same state")
	var sup = h.sim.supplies
	eq(sup.meal_day, sim.supplies.meal_day, "the meal day comes back")
	eq(sup.meals_done, 2, "the meals done today come back (13:00 is behind at 14:00)")
	eq(sup.sources_day, sim.supplies.sources_day, "the day of the last dawn roll comes back")
	eq(sup.short_of, {"food": true, "water": false}, "the shortage flags come back")
	near(sup.low_alert_min.food, sim.supplies.low_alert_min.food, 1e-12, "the time of the last low-food alert comes back")
	check(sup.low_alert_min.food > -1000.0, "and it is a real time, not 'never'")
	h.sim.supplies.load_state({})
	check(h.sim.supplies.meals_done >= 0, "an empty save does no harm")
	g.world.free()
	h.world.free()


func test_a_saved_state_plays_out_the_same() -> void:
	for save_hour in [9.0, 12.98, 18.98, 6.48]:
		var a := _calm(6)
		var b := _calm(6)
		var sa = a.sim
		var sb = b.sim
		_at(sa, save_hour)
		_run(sa, 1.0)
		sa.stock.food = 9.0          # lowish, so the alert timers matter
		# what the save game keeps, copied onto the second run
		sb.minutes = sa.minutes
		sb.clock_min = sa.clock_min
		sb.day = sa.day
		sb.phase = sa.phase
		sb.t = sa.t
		sb.bell_rung = sa.bell_rung
		sb.weather = sa.weather
		sb.stock = sa.stock.duplicate()
		sb.rng.state = sa.rng.state
		for i in sa.people.size():
			sb.people[i].hunger_h = sa.people[i].hunger_h
			sb.people[i].thirst_h = sa.people[i].thirst_h
			sb.people[i].hp = sa.people[i].hp
		sb.supplies.load_state(JSON.parse_string(JSON.stringify(sa.supplies.save(), "", true, true)))
		var rnd := RandomNumberGenerator.new()
		rnd.seed = 31
		for i in 2000:
			var dt := rnd.randf_range(0.05, 0.4)
			sa.update(dt)
			sb.update(dt)
		eq(sb.stock, sa.stock, "the stocks agree after a day from %s" % save_hour)
		eq(sb.weather, sa.weather, "the weather agrees")
		eq(sb.supplies.save(), sa.supplies.save(), "the module state agrees")
		eq(sb.supplies.meals_done, sa.supplies.meals_done, "the meal counters agree")
		eq(sb.supplies.sources_day, sa.supplies.sources_day, "the dawn days agree")
		eq(sb.supplies.short_of, sa.supplies.short_of, "the shortage flags agree")
		eq(sb.supplies.low_alert_min, sa.supplies.low_alert_min, "the alert times agree")
		var alerts_a: Array = sa.alerts.keys()
		var alerts_b: Array = sb.alerts.keys()
		alerts_a.sort()
		alerts_b.sort()
		eq(alerts_b, alerts_a, "the same alerts are up")
		for i in sa.people.size():
			near(sb.people[i].hunger_h, sa.people[i].hunger_h, 1e-9, "hunger agrees")
			near(sb.people[i].thirst_h, sa.people[i].thirst_h, 1e-9, "thirst agrees")
		a.world.free()
		b.world.free()


# ----------------------------------------------------------------- balance --

func test_an_unmanaged_crew_goes_short_about_a_week_in_and_income_alone_does_not_carry_them() -> void:
	# No income at all: the stores alone. The first hungry or thirsty person.
	var g := _calm()
	var sim = g.sim
	sim.supplies.sources_on = false
	var first_day := 0
	var guard := 0
	while first_day == 0 and sim.day < 20 and guard < 100000:
		sim.update(1.0)
		guard += 1
		for p in sim.people:
			if p.hunger_h >= 18.0 or p.thirst_h >= 14.0:
				first_day = sim.day
	check(first_day >= 5 and first_day <= 8, "with no income someone is hungry or thirsty on day 5 to 8, got day %d" % first_day)
	g.world.free()
	# The garden and the barrels but no trips: the stores still run dry.
	var h := _calm()
	var sim2 = h.sim
	var dry_day := 0
	guard = 0
	while dry_day == 0 and sim2.day < 30 and guard < 100000:
		sim2.update(1.0)
		guard += 1
		if sim2.stock.food <= 0.0 or sim2.stock.water <= 0.0:
			dry_day = sim2.day
	check(dry_day >= 8 and dry_day <= 20, "income alone runs dry between day 8 and 20, got day %d" % dry_day)
	h.world.free()


# ------------------------------------------------------------- integration --

func test_a_day_and_a_half_with_every_module_keeps_the_books_straight() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	sim.zombies.clear()
	sim.spawn_t = 1.0e9
	sim.waves.enabled = false
	var food: float = sim.stock.food
	var bad := ""
	var guard := 0
	while sim.clock_min < 36.0 * 60.0 and bad == "" and guard < 100000:
		sim.update(0.2)
		guard += 1
		bad = _bad_state(sim)
	eq(bad, "", "no negative stock with the real modules")
	check(sim.stock.food < food + 3.0 - 4.0, "the crew ate: 13:00, 19:00 and 07:00 against a dawn's 3 food")
	g.world.free()
