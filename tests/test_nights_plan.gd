extends "res://tests/case.gd"
## The size and the shape of the nights in avatar mode (round 19, S3.1: waves.gd, kinds.gd, recruits.gd `crew_scale`, night_data.gd):
## which nights are Big, how big, what comes and from where, and the outlook of a night ahead. Without an avatar none of it applies
## (test_nights_regression pins that against the golden numbers); every number is read through NightData, none is copied here.

const Helpers := preload("res://tests/helpers.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")
const Waves := preload("res://scripts/sim/waves.gd")
const NightData := preload("res://scripts/sim/night_data.gd")


# ------------------------------------------------------------------- kinds --

func test_counts_with_the_shares_given_spend_them_and_with_none_are_as_ever() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	var c := RandomNumberGenerator.new()
	a.seed = 77
	b.seed = 77
	c.seed = 77
	var plain: Dictionary = Kinds.counts(66.0, 10, true, a)
	var same: Dictionary = Kinds.counts(66.0, 10, true, b, {})
	var explicit: Dictionary = Kinds.counts(66.0, 10, true, c, Kinds.shares(10, true))
	eq(plain, same, "an empty `shares` is the old call")
	eq(plain, explicit, "and the same shares given gives the same counts")
	eq(a.state, b.state, "with the same draws")
	eq(a.state, c.state, "in the same order")
	var d := RandomNumberGenerator.new()
	d.seed = 77
	var mine: Dictionary = Kinds.counts(100.0, 10, false, d, {"walker": 0.4, "runner": 0.35, "brute": 0.25})
	var spent: float = float(mine.brute) * float(Kinds.KINDS.brute.cost) + float(mine.runner) * float(Kinds.KINDS.runner.cost) + float(mine.walker)
	near(spent, 100.0, 4.0, "the counts cost about the budget: %s" % str(mine))
	check(int(mine.brute) >= 2 and int(mine.runner) >= 15, "and follow the shares: %s" % str(mine))
	eq(d.state, a.state, "two draws as with any shares")


func test_a_floor_of_brutes_lifts_the_count_without_a_draw_more() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 5
	b.seed = 5
	var plain: Dictionary = Kinds.counts(40.0, 10, false, a, {"walker": 0.9, "runner": 0.05, "brute": 0.05})
	var floored: Dictionary = Kinds.counts(40.0, 10, false, b, {"walker": 0.9, "runner": 0.05, "brute": 0.05}, {"brute": 3})
	eq(a.state, b.state, "the floor costs no draw")
	eq(int(floored.brute), 3, "three brutes at least")
	check(int(plain.brute) < 3, "where the shares gave fewer: %d" % int(plain.brute))
	var spent: float = float(floored.brute) * float(Kinds.KINDS.brute.cost) + float(floored.runner) * float(Kinds.KINDS.runner.cost) + float(floored.walker)
	near(spent, 40.0, 4.0, "the walkers make way for them")
	var c := RandomNumberGenerator.new()
	c.seed = 5
	var high: Dictionary = Kinds.counts(400.0, 10, false, c, {"walker": 0.5, "runner": 0.0, "brute": 0.5}, {"brute": 3})
	check(int(high.brute) > 3, "a floor never lowers a count that is above it: %d" % int(high.brute))


# ---------------------------------------------------------------- the crew --

func test_the_avatar_counts_as_part_of_a_defender_in_the_size_of_the_night() -> void:
	var g := Helpers.avatar_game(3, 5)
	var sim = g.sim
	var n: int = sim.recruits.crew_size()
	var w: float = NightData.num("ordinary.avatar_weight")
	near(sim.recruits.crew_scale(), 0.2 + 0.8 * (float(n) - 1.0 + w) / 6.0, 1e-9, "0.2 + 0.8 x (n - 1 + weight) / 6 with the avatar")
	sim.player_id = ""
	near(sim.recruits.crew_scale(), 0.2 + 0.8 * float(n) / 6.0, 1e-9, "unchanged without")
	sim.player_id = "ruth"
	sim.nights_on = false
	near(sim.recruits.crew_scale(), 0.2 + 0.8 * float(n) / 6.0, 1e-9, "and in a place's sim")
	sim.nights_on = true
	eq(sim.recruits.crew_size(), n, "the housing's count of people is not touched")
	g.world.free()


func test_the_avatar_weight_comes_from_the_data_and_a_lost_avatar_is_not_taken_off_twice() -> void:
	var g := Helpers.avatar_game(3, 5)
	var sim = g.sim
	var n: int = sim.recruits.crew_size()
	var was: String = NightData.data_path
	var path := "user://test_r19_nights_plan_weight.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"ordinary": {"avatar_weight": 0.0}}))
	f.close()
	NightData.data_path = path
	NightData.forget()
	var zero: float = sim.recruits.crew_scale()
	NightData.data_path = was
	NightData.forget()
	DirAccess.remove_absolute(path)
	near(zero, 0.2 + 0.8 * (float(n) - 1.0) / 6.0, 1e-9, "a weight of nothing: the avatar is not counted")
	# the avatar is dead and the player is still named (between one life and the next): the crew has already lost them
	sim.avatar.set_player("ruth")
	for p in sim.people:
		if String(p.id) == "ruth":
			p.dead = true
	var w: float = NightData.num("ordinary.avatar_weight")
	var left: int = sim.recruits.crew_size()
	near(sim.recruits.crew_scale(), 0.2 + 0.8 * float(left) / 6.0, 1e-9, "a dead avatar is not taken off the count again (weight %.2f)" % w)
	g.world.free()


func test_the_classic_start_has_no_crew_scale_in_avatar_mode_either() -> void:
	var g := Helpers.make(3, 1, 6)
	g.sim.avatar.set_player("ruth")
	near(g.sim.recruits.crew_scale(), 1.0, 1e-12, "six people: the night as it was")
	g.world.free()


# ------------------------------------------------------------ which nights --

func _brute_positions(plan: Dictionary) -> Array:
	var out: Array = []
	var size: int = plan.queue.size()
	for i in size:
		if plan.queue[i] == Kinds.BRUTE:
			out.append(float(i) / float(size))
	return out


func test_without_an_avatar_no_night_is_big_in_the_new_sense() -> void:
	var g := Helpers.make(1, 1, 5)
	for day in range(1, 41):
		eq(g.sim.waves.big_night(day), {}, "day %d" % day)
		eq(g.sim.waves.outlook(day), {}, "no outlook either on day %d" % day)
	check(not g.sim.waves.avatar_mode(), "not avatar mode")
	g.world.free()


func test_milestones_on_the_tenth_and_twentieth_and_the_final_on_the_thirtieth() -> void:
	var g := Helpers.avatar_game(1, 5)
	var w = g.sim.waves
	for day in range(1, 31):
		var bn: Dictionary = w.big_night(day)
		match day:
			10:
				eq(bn.get("kind"), "milestone", "night 10 is a milestone")
				eq(bn.get("id"), NightData.list("order")[0], "the first of the order")
				eq(int(bn.get("index", -1)), 0, "the first milestone of the run")
			20:
				eq(bn.get("kind"), "milestone", "night 20 is a milestone")
				eq(bn.get("id"), NightData.list("order")[1], "the second of the order")
				eq(int(bn.get("index", -1)), 1, "the second milestone of the run")
			30:
				eq(bn.get("kind"), "final", "night 30 is the final")
				eq(bn.get("id"), "last", "its theme is the last night's")
			_:
				eq(bn, {}, "night %d is an ordinary one" % day)
	var ten: Dictionary = w.big_night(10)
	var theme: Dictionary = NightData.theme(String(ten.id))
	for key in ["name", "factor", "runners", "brutes", "headings", "main_share", "cap", "blurb"]:
		eq(ten[key], theme[key], "the milestone says the theme's %s" % key)
	eq(ten.brute_at, theme.brute_at, "and where its brutes come")
	check(bool(ten.plated), "its brutes are plated")
	var final: Dictionary = w.big_night(30)
	near(float(final.factor), g.sim.seasons.big_factor(), 1e-12, "the final keeps the season's factor")
	near(float(final.runners), Kinds.BIG_RUNNERS, 1e-12, "and the old shares")
	near(float(final.brutes), Kinds.BIG_BRUTES, 1e-12, "of runners and brutes")
	eq(int(final.cap), Waves.CAP_BIG, "and its cap")
	near(float(final.main_share), Waves.MAIN_SHARE, 1e-12, "and its main share")
	eq(final.brute_at, NightData.theme("last").brute_at, "only its brutes come where the data says")
	check(bool(final.plated), "and are plated")
	eq(final.name, "The last night", "the last season's final is the last night")
	g.world.free()


func test_a_campaign_has_its_milestones_and_its_final_in_every_season() -> void:
	var g := Helpers.make(5, 1, 5, true)
	g.sim.avatar.set_player("ruth")
	var w = g.sim.waves
	var every: int = int(NightData.num("big_every"))
	var order: Array = NightData.list("order")
	# from Autumn, the days of Winter are answered too (the notice of a night ahead may cross the turn of the season)
	var winter_start := 31
	eq(w.big_night(winter_start - 1).get("kind"), "final", "Autumn's last night")
	eq(w.big_night(winter_start), {}, "Winter's first night is an ordinary one")
	eq(w.big_night(winter_start + 9).get("kind"), "milestone", "Winter's tenth night")
	eq(w.big_night(winter_start + 9).get("id"), order[2 % order.size()], "the third milestone of the run")
	eq(w.big_night(winter_start + 19).get("id"), order[3 % order.size()], "and the fourth")
	var last: Dictionary = w.big_night(winter_start + 23)
	eq(last.get("kind"), "final", "Winter's last night is its 24th")
	eq(last.get("name"), "The Big Night", "which is a Big Night, not the last of the game")
	near(float(last.factor), float(g.sim.seasons.season(1).big), 1e-12, "with Winter's factor")
	# and the same from inside Winter, and Spring after it
	for i in 3:
		g.sim.seasons.jump_to(i)
		g.sim.avatar.set_player("ruth")
		var start: int = g.sim.day
		var length: int = g.sim.seasons.season_length()
		var seen := []
		for d in range(start, start + length):
			var bn: Dictionary = w.big_night(d)
			if not bn.is_empty():
				seen.append([d - start + 1, bn.kind])
		var want := []
		var k := every
		while k < length:
			want.append([k, "milestone"])
			k += every
		want.append([length, "final"])
		eq(seen, want, "season %d: the milestones on the multiples of %d and the final on its last night" % [i, every])
	g.sim.seasons.jump_to(3)
	g.sim.avatar.set_player("ruth")
	eq(w.big_night(g.sim.seasons.end_day()).get("name"), "The last night", "Summer's final is the last night of the game")
	eq(w.big_night(g.sim.seasons.end_day() + 1), {}, "and nothing comes after it")
	g.world.free()


func test_a_damaged_data_file_still_gives_a_big_night() -> void:
	var g := Helpers.avatar_game(2, 5)
	var was: String = NightData.data_path
	var path := "user://test_r19_nights_plan_damaged.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"big_every": 0, "order": ["storm"], "themes": {"siege": {"brute_at": [0.9, 0.1], "factor": 0.5}}}))
	f.close()
	NightData.data_path = path
	NightData.forget()
	var one: Dictionary = g.sim.waves.big_night(1)
	var ten: Dictionary = g.sim.waves.big_night(10)
	NightData.data_path = was
	NightData.forget()
	DirAccess.remove_absolute(path)
	eq(one.get("kind"), "milestone", "a Big Night every night with `big_every` 0 read as 1")
	eq(ten.get("id"), "siege", "an unknown theme in the order is the Siege")
	check(float(ten.factor) >= 1.0, "a factor under one is one: %s" % str(ten.get("factor")))
	check(float(ten.brute_at[0]) < float(ten.brute_at[1]), "a range the wrong way round is set right: %s" % str(ten.get("brute_at")))
	g.world.free()


# ---------------------------------------------------------------- the plans --

func test_a_milestone_plan_is_sized_shaped_and_placed_by_its_theme() -> void:
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var g := Helpers.avatar_game(seed_value, 5)
		var sim = g.sim
		var w = sim.waves
		var bn: Dictionary = w.big_night(10)
		var plan: Dictionary = w.plan_for(10)
		var tag := "seed %d" % seed_value
		check(plan.big, "%s: the plan is a Big Night" % tag)
		eq(plan.kind, "milestone", "%s: its kind" % tag)
		eq(plan.id, bn.id, "%s: its theme" % tag)
		eq(plan.name, bn.name, "%s: its name" % tag)
		check(plan.plated, "%s: plated" % tag)
		near(float(plan.main_share), float(bn.main_share), 1e-12, "%s: its main share" % tag)
		eq(plan.brute_at, bn.brute_at, "%s: where the brutes come" % tag)
		eq(int(plan.cap), int(bn.cap), "%s: its cap" % tag)
		near(float(plan.budget), w.budget_for(10) * float(bn.factor) * sim.recruits.crew_scale(), 1e-6, "%s: the day's budget times the theme's factor and the crew's share" % tag)
		check(plan.counts.brute >= int(bn.min_brutes), "%s: at least %d brutes at crew 5: %s" % [tag, int(bn.min_brutes), str(plan.counts)])
		eq(plan.heading.size(), 1, "%s: one heading" % tag)
		var cost: float = float(plan.counts.walker) + float(plan.counts.runner) * float(Kinds.KINDS.runner.cost) + float(plan.counts.brute) * float(Kinds.KINDS.brute.cost)
		near(cost, float(plan.budget), float(plan.budget) * 0.12 + 4.0 + float(Kinds.KINDS.brute.cost), "%s: about its budget" % tag)
		var seen := 0
		var size: int = plan.queue.size()
		for pos in _brute_positions(plan):
			seen += 1
			check(pos >= float(bn.brute_at[0]) - 0.04 and pos <= float(bn.brute_at[1]) + 0.04, "%s: a brute at %.2f of the night, in %s" % [tag, pos, str(bn.brute_at)])
		eq(seen, int(plan.counts.brute), "%s: every brute is in the queue" % tag)
		check(size > 0, "%s: a queue" % tag)
		# the brutes of the plan are the share of the theme or the floor, not more than a quarter of the points
		check(float(plan.counts.brute) * float(Kinds.KINDS.brute.cost) <= float(plan.budget) * 0.45, "%s: the brutes are not all the night" % tag)
		g.world.free()


func test_a_big_night_is_bigger_than_the_ordinary_night_before_it_and_the_rush_has_the_runners() -> void:
	var g := Helpers.avatar_game(3, 5)
	var w = g.sim.waves
	var nine: Dictionary = w.plan_for(9)
	var ten: Dictionary = w.plan_for(10)
	check(float(ten.budget) > float(nine.budget) * 1.3, "night 10 is far bigger than night 9: %.0f against %.0f" % [ten.budget, nine.budget])
	eq(nine.kind, "ordinary", "night 9 is an ordinary night")
	eq(nine.cap, 0, "which has the phase's cap")
	check(not nine.plated and nine.brute_at.is_empty(), "no plating and no range of brutes")
	check(nine.heading.size() <= 2, "one or two headings as ever")
	var twenty: Dictionary = w.plan_for(20)
	var siege: Dictionary = NightData.theme("siege")
	var rush: Dictionary = NightData.theme("rush")
	check(float(rush.runners) > float(siege.runners), "the Rush has more runners than the Siege (the data)")
	var share_10: float = float(ten.counts.runner) * float(Kinds.KINDS.runner.cost) / float(ten.budget)
	var share_20: float = float(twenty.counts.runner) * float(Kinds.KINDS.runner.cost) / float(twenty.budget)
	check(share_20 > share_10 + 0.1, "and the plan has them: %.2f of the points against %.2f" % [share_20, share_10])
	g.world.free()


func test_the_final_in_avatar_mode_is_the_old_final_with_plated_brutes() -> void:
	var g := Helpers.avatar_game(3, 5)
	var w = g.sim.waves
	var plan: Dictionary = w.plan_for(30)
	check(plan.big and plan.kind == "final" and plan.plated, "the final, big and plated")
	check(plan.counts.brute >= 3, "several brutes: %d" % int(plan.counts.brute))
	eq(int(plan.cap), Waves.CAP_BIG, "its cap is the old one")
	near(float(plan.main_share), Waves.MAIN_SHARE, 1e-12, "and its main share")
	var shares := Kinds.shares(30, true)
	var cost_runner: float = float(plan.counts.runner) * float(Kinds.KINDS.runner.cost) / float(plan.budget)
	near(cost_runner, float(shares.runner), 0.06, "its shares are the old big ones")
	near(float(plan.budget), w.budget_for(30) * g.sim.seasons.big_factor() * g.sim.recruits.crew_scale(), 1e-6, "its budget the season's factor")
	var bn: Dictionary = w.big_night(30)
	for pos in _brute_positions(plan):
		check(pos >= float(bn.brute_at[0]) - 0.04 and pos <= float(bn.brute_at[1]) + 0.04, "a brute at %.2f of the night, in %s" % [pos, str(bn.brute_at)])
	g.world.free()


func test_the_ordinary_budget_follows_the_data_in_avatar_mode_only() -> void:
	var avatar := Helpers.avatar_game(4, 5)
	var plain := Helpers.make(4, 1, 5)
	var was: String = NightData.data_path
	var path := "user://test_r19_nights_plan_budget.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"ordinary": {"mult": 0.5, "growth": 0.07}}))
	f.close()
	NightData.data_path = path
	NightData.forget()
	var with_avatar: float = avatar.sim.waves.budget_for(11)
	var without: float = plain.sim.waves.budget_for(11)
	var plan_avatar: float = avatar.sim.waves.night_budget(11)
	var plan_plain: float = plain.sim.waves.night_budget(11)
	NightData.data_path = path + ".none"
	NightData.forget()
	var defaults: float = avatar.sim.waves.budget_for(11)
	NightData.data_path = was
	NightData.forget()
	DirAccess.remove_absolute(path)
	near(with_avatar, 30.0 * (1.0 + 0.07 * 10.0) * 0.5, 1e-9, "growth and share from the data with an avatar")
	near(without, 60.0, 1e-9, "the old budget without one")
	near(plan_avatar, with_avatar * avatar.sim.recruits.crew_scale(), 1e-9, "the night follows the budget")
	near(plan_plain, 60.0 * plain.sim.recruits.crew_scale(), 1e-9, "and without an avatar the old one")
	near(defaults, 30.0 * (1.0 + float(NightData.FALLBACK.ordinary.growth) * 10.0) * float(NightData.FALLBACK.ordinary.mult), 1e-9, "no file: the plan's numbers")
	avatar.world.free()
	plain.world.free()


func test_a_plan_made_before_the_player_is_named_is_made_again() -> void:
	var g := Helpers.make(6, 1, 5)
	var sim = g.sim
	var before: Dictionary = sim.waves.plan_for(10)
	check(not before.big, "no Big Night without a player")
	sim.avatar.set_player("ruth")
	var after: Dictionary = sim.waves.plan_for(10)
	check(after.big and after.kind == "milestone", "with one, the same day is a milestone")
	g.world.free()


func test_a_plan_is_the_same_whenever_it_is_made_and_changes_with_the_crew_only_before_the_bell() -> void:
	var g := Helpers.avatar_game(6, 5)
	var sim = g.sim
	var a: Dictionary = sim.waves.plan_for(10).duplicate(true)
	for i in 40:
		sim.rng.randf()
	var b: Dictionary = sim.waves.plan_for(10)
	eq(a.queue, b.queue, "the same queue")
	eq(a.heading, b.heading, "the same heading")
	var other := Helpers.avatar_game(6, 5)
	for i in 80:
		other.sim.rng.randf()
	eq(other.sim.waves.plan_for(10).queue, a.queue, "and the same in another run of the seed")
	g.world.free()
	other.world.free()


func test_the_dead_of_a_big_night_come_from_its_heading_in_most_of_the_draws() -> void:
	var g := Helpers.avatar_game(7, 5)
	var sim = g.sim
	var plan: Dictionary = sim.waves.plan_for(10)
	var main: Vector2 = sim.spawns[int(plan.heading[0])]
	var hits := 0
	for i in 1000:
		if sim.waves._pick_spawn(plan).is_equal_approx(main):
			hits += 1
	check(hits >= 800 and hits <= 900, "%d of 1000 from the main spawn point" % hits)
	var ordinary: Dictionary = sim.waves.plan_for(9)
	var from_main := 0
	var spots: Array = []
	for h in ordinary.heading:
		spots.append(sim.spawns[int(h)])
	for i in 1000:
		var at: Vector2 = sim.waves._pick_spawn(ordinary)
		for sp in spots:
			if sp.is_equal_approx(at):
				from_main += 1
				break
	check(from_main >= 600 and from_main <= 780, "an ordinary night: %d of 1000 from its main points" % from_main)
	g.world.free()


# --------------------------------------------------------------- the dead --

## Lets the night of `day` come in without anything else happening: the dusk, then the night, with each group that spawns taken off
## the field at once (the cap is the alive ones; `keep` leaves them). Returns the dead that came, in order, and leaves the events.
func _let_in(sim, day: int, keep := false) -> Array:
	Helpers.at(sim, day, 18.9)
	sim.waves.night_day = -1
	sim.events.clear()
	sim.waves.update(1.0 / 30.0)
	sim.phase = "dusk"
	sim.waves.update(1.0 / 30.0)
	sim.phase = "night"
	var came: Array = []
	var guard := 0
	var plan: Dictionary = sim.waves.plan_for(day)
	while sim.waves.spawned < plan.queue.size() and guard < 40000:
		var before: int = sim.zombies.size()
		sim.waves.update(1.0 / 30.0)
		for i in range(before, sim.zombies.size()):
			came.append(sim.zombies[i])
		if not keep:
			sim.zombies.clear()
			for s in sim.segments:
				for sl in s.slots:
					sl.who = null
		guard += 1
	return came


func test_every_brute_of_a_milestone_is_plated_and_nothing_else_is() -> void:
	var g := Helpers.avatar_game(8, 5)
	var sim = g.sim
	sim.zombies.clear()
	var came := _let_in(sim, 10)
	var brutes := 0
	var plated := 0
	var others_plated := 0
	for z in came:
		if z.kind == Kinds.BRUTE:
			brutes += 1
			if z.plated:
				plated += 1
		elif z.plated:
			others_plated += 1
	check(brutes >= 2, "brutes came: %d" % brutes)
	eq(plated, brutes, "every one of them is plated")
	eq(others_plated, 0, "and nobody else")
	check(sim.alerts.has("brute") and String(sim.alerts.brute.text).contains("plated"), "the alert says a plated brute is coming")
	g.world.free()


func test_a_brute_of_an_ordinary_night_is_not_plated_and_the_old_alert_stands() -> void:
	var g := Helpers.avatar_game(8, 5)
	var sim = g.sim
	sim.zombies.clear()
	var came := _let_in(sim, 9)
	var brutes := 0
	for z in came:
		if z.kind == Kinds.BRUTE:
			brutes += 1
			check(not z.plated, "a brute of night 9 is not plated")
	check(brutes >= 1, "night 9 brings a brute: %d" % brutes)
	eq(String(sim.alerts.brute.text), "A brute is coming", "and the old alert")
	g.world.free()


func test_a_brute_without_an_avatar_is_never_plated_even_on_a_big_plan() -> void:
	var g := Helpers.make(8, 1, 5)
	var sim = g.sim
	sim.zombies.clear()
	var came := _let_in(sim, 10)
	var brutes := 0
	for z in came:
		if z.kind == Kinds.BRUTE:
			brutes += 1
			check(not z.plated, "no plating without an avatar")
	check(brutes >= 1, "a night of 10 has brutes: %d" % brutes)
	g.world.free()


func test_the_dusk_of_a_milestone_says_its_name_and_the_final_says_what_it_always_did() -> void:
	var g := Helpers.avatar_game(8, 5)
	var sim = g.sim
	_let_in(sim, 10)
	var bn: Dictionary = sim.waves.big_night(10)
	var said := false
	for e in sim.events:
		if e.type == "banner" and e.text == bn.name and e.sub == bn.blurb:
			said = true
	check(said, "a banner with the theme's name and what it asks")
	eq(String(sim.alerts.bignight.text), String(bn.name), "and the alert has the name")
	eq(String(sim.alerts.bignight.sub), String(bn.blurb), "and the blurb")
	_let_in(sim, 30)
	var old := false
	for e in sim.events:
		if e.type == "banner" and e.text == "The last night" and String(e.sub).begins_with("Hold until dawn"):
			old = true
	check(old, "the final has its old banner")
	eq(String(sim.alerts.bignight.sub), "Everything that is left is coming", "and its old alert")
	_let_in(sim, 9)
	var banner := false
	for e in sim.events:
		if e.type == "banner":
			banner = true
	check(not banner, "an ordinary night has no banner at dusk")
	g.world.free()


func test_no_more_than_the_plans_cap_are_alive_on_a_big_night() -> void:
	var g := Helpers.avatar_game(9, 6)
	var sim = g.sim
	sim.zombies.clear()
	var plan: Dictionary = sim.waves.plan_for(20)
	check(plan.queue.size() > int(plan.cap), "the night is bigger than the cap (%d against %d), so that it binds" % [plan.queue.size(), int(plan.cap)])
	_let_in(sim, 20, true)
	var alive := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			alive += 1
	check(alive <= int(plan.cap), "at most %d alive: %d" % [int(plan.cap), alive])
	check(alive >= int(plan.cap) - 3, "and the cap is what stopped them: %d" % alive)
	g.world.free()


# ------------------------------------------------------------------ outlook --

func _seg(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


func test_the_outlook_of_a_night_ahead_changes_nothing() -> void:
	var g := Helpers.avatar_game(4, 5)
	var sim = g.sim
	Helpers.at(sim, 9, 12.0)
	var w = sim.waves
	var today: Dictionary = w.plan_for(9)
	var queue: Array = today.queue.duplicate()
	var state: int = sim.rng.state
	var cache_day: int = w._plan_day
	var o: Dictionary = w.outlook(10)
	eq(sim.rng.state, state, "not one draw of the rules' dice")
	eq(w._plan_day, cache_day, "today's plan is still the one kept")
	eq(w._plan.queue, queue, "unchanged")
	eq(w.plan_for(9).queue, queue, "and still today's")
	check(not o.is_empty(), "the outlook is there")
	eq(o.day, 10, "of night 10")
	eq(o.kind, "milestone", "a milestone")
	eq(w.outlook(10), o, "asked again it is the same")
	g.world.free()


func test_the_outlook_is_the_same_at_noon_and_at_dusk_when_nothing_changed() -> void:
	var g := Helpers.avatar_game(4, 5)
	var sim = g.sim
	Helpers.at(sim, 9, 12.0)
	var noon: Dictionary = sim.waves.outlook(10)
	Helpers.at(sim, 9, 18.5)
	var evening: Dictionary = sim.waves.outlook(10)
	Helpers.at(sim, 10, 17.0)
	var seventeen: Dictionary = sim.waves.outlook(10)
	Helpers.at(sim, 10, 19.5)
	sim.waves.plan_for(10)
	sim.waves.night_day = 10
	var dusk: Dictionary = sim.waves.outlook(10)
	eq(evening, noon, "the evening before is the noon before")
	eq(seventeen, noon, "and the lookout's hour of the day itself")
	eq(dusk, noon, "and the bell's")
	g.world.free()


func test_the_outlook_says_what_the_plan_brings_and_names_its_places() -> void:
	var g := Helpers.avatar_game(2, 5)
	var sim = g.sim
	var w = sim.waves
	for day in [3, 9, 10, 20, 30]:
		var o: Dictionary = w.outlook(day)
		var plan: Dictionary = w.plan_for(day)
		var tag := "night %d" % day
		eq(o.size, int(plan.shown), "%s: the number is the plan's `shown`" % tag)
		eq(o.low, roundi(float(plan.shown) * 0.85), "%s: its low" % tag)
		eq(o.high, roundi(float(plan.shown) * 1.15), "%s: its high" % tag)
		eq(o.side, w.heading_text(plan), "%s: the side is the heading's" % tag)
		eq(o.runners, int(plan.counts.runner) > 0, "%s: runners" % tag)
		eq(o.brutes, int(plan.counts.brute), "%s: brutes" % tag)
		eq(o.plated, int(plan.counts.brute) if plan.plated else 0, "%s: plated" % tag)
		eq(o.needs_you, day == 10 or day == 20 or day == 30, "%s: only a Big Night needs the player" % tag)
		eq(o.kind, plan.kind, "%s: the kind" % tag)
		eq(o.blurb, plan.blurb, "%s: the blurb" % tag)
		check(o.sections.size() >= 1 and o.sections.size() <= 2, "%s: one or two sections: %s" % [tag, str(o.sections)])
		for id in o.sections:
			var seg = _seg(sim, int(id))
			check(seg != null and seg.kind != sim.DOOR_KIND and int(id) < 100, "%s: section %d is a wall of the compound" % [tag, int(id)])
			check(String(o.section_text).contains(String(seg.name).to_lower()), "%s: the text names it: %s" % [tag, o.section_text])
		check(String(o.section_text).begins_with("the %s side: " % o.side), "%s: the text starts with the side: %s" % [tag, o.section_text])
	var ordinary: Dictionary = w.outlook(3)
	eq(ordinary.plated, 0, "no plated brutes on an ordinary night")
	eq(ordinary.needs_you, false, "it does not need the player")
	var final: Dictionary = w.outlook(30)
	eq(final.kind, "final", "the thirtieth is the final")
	check(final.brutes >= 3 and final.plated == final.brutes, "with brutes, all plated: %d" % final.brutes)
	g.world.free()


func test_the_times_of_the_outlook_are_inside_the_night_and_to_the_half_hour() -> void:
	for seed_value in [1, 2, 3, 4, 5]:
		var g := Helpers.avatar_game(seed_value, 5)
		var sim = g.sim
		var dusk: float = sim.seasons.dusk_hour()
		var span: float = (24.0 - dusk) + sim.seasons.dawn_hour() - sim.seasons.DAWN_H
		for day in [9, 10, 20, 30]:
			var o: Dictionary = sim.waves.outlook(day)
			var tag := "seed %d night %d" % [seed_value, day]
			var times := [float(o.first_at), float(o.last_at)]
			if float(o.brute_at) >= 0.0:
				times.append(float(o.brute_at))
			for t in times:
				near(fposmod(t * 2.0, 1.0) if fposmod(t * 2.0, 1.0) < 0.5 else fposmod(t * 2.0, 1.0) - 1.0, 0.0, 1e-9, "%s: %.2f is to the half hour" % [tag, t])
				var after: float = fposmod(t - dusk, 24.0)
				check(after >= -1e-9 and after <= span + 1e-9, "%s: %.1f is inside the night (dusk %.1f, %.1f hours of it)" % [tag, t, dusk, span])
			var f: float = fposmod(float(o.first_at) - dusk, 24.0)
			var l: float = fposmod(float(o.last_at) - dusk, 24.0)
			check(f <= l, "%s: the first is not after the last" % tag)
			if float(o.brute_at) >= 0.0:
				var b: float = fposmod(float(o.brute_at) - dusk, 24.0)
				check(f <= b + 1e-9 and b <= l + 1e-9, "%s: the first brute comes between them" % tag)
			if int(o.brutes) == 0:
				eq(float(o.brute_at), -1.0, "%s: no brute, no time for it" % tag)
		g.world.free()


func test_the_brutes_of_a_siege_come_in_the_middle_of_the_night_and_late_in_the_outlook() -> void:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	var dusk: float = sim.seasons.dusk_hour()
	var o: Dictionary = sim.waves.outlook(10)
	var first_after: float = fposmod(float(o.first_at) - dusk, 24.0)
	var brute_after: float = fposmod(float(o.brute_at) - dusk, 24.0)
	check(first_after < 4.0, "the first small group is in before 23:00: %.1f hours after dusk" % first_after)
	check(brute_after > first_after + 1.0, "the brutes are after it, as they are slow and come in the middle of the queue: %.1f against %.1f" % [brute_after, first_after])
	g.world.free()


func test_the_outlook_follows_the_season_when_the_nights_are_longer_or_later() -> void:
	var g := Helpers.make(5, 1, 5, true)
	g.sim.seasons.jump_to(3)    # Summer: dusk at 21:00
	g.sim.avatar.set_player("ruth")
	var dusk: float = g.sim.seasons.dusk_hour()
	var o: Dictionary = g.sim.waves.outlook(g.sim.day + 9)
	eq(o.kind, "milestone", "its tenth night is a milestone")
	check(float(o.first_at) >= dusk or float(o.first_at) < 6.0, "after the Summer dusk (%.1f): %.1f" % [dusk, o.first_at])
	check(fposmod(float(o.first_at) - dusk, 24.0) < 12.0, "and within the night")
	g.world.free()


func test_the_texts_of_an_outlook_say_it_the_way_the_plan_does() -> void:
	var o := {"name": "The Siege", "kind": "milestone", "low": 70, "high": 95, "side": "east", "runners": false, "brutes": 2, "plated": 2, "brute_at": 23.0, "first_at": 21.0}
	eq(Waves.outlook_text(o), "The Siege: about 70 to 95 from the east side, 2 plated brutes after 23:00, the first at about 21:00", "the plan's own words")
	o["brutes"] = 1
	o["plated"] = 1
	o["runners"] = true
	eq(Waves.outlook_text(o), "The Siege: about 70 to 95 from the east side, with runners, a plated brute after 23:00, the first at about 21:00", "a plated brute and runners")
	o["side"] = "north and west"
	o["kind"] = "final"
	o["name"] = "The last night"
	o["brutes"] = 0
	o["plated"] = 0
	eq(Waves.outlook_text(o), "The last night: about 70 to 95 mostly from the north and west, with runners, the first at about 21:00", "two sides and no brute")
	eq(Waves.hour_text(0.0), "00:00", "midnight")
	eq(Waves.hour_text(21.5), "21:30", "half past nine")
	eq(Waves.hour_text(25.0), "01:00", "past midnight")
	eq(Waves.hour_text(5.5), "05:30", "morning")


# --------------------------------------------------------- target sections --

func test_the_target_sections_are_the_nearest_walls_to_the_main_spawn_point() -> void:
	var g := Helpers.avatar_game(2, 5)
	var sim = g.sim
	var plan: Dictionary = sim.waves.plan_for(10)
	var targets: Array = sim.waves.target_sections(plan)
	eq(targets.size(), 2, "two of them")
	eq(sim.waves.target_sections(plan, 1).size(), 1, "or one")
	var walls := 0
	for s in sim.segments:
		if s.id < 100 and s.kind != sim.DOOR_KIND:
			walls += 1
	eq(sim.waves.target_sections(plan, 30).size(), walls, "never more than the compound's walls, and all of them when asked for more")
	for s in sim.waves.target_sections(plan, 30):
		check(s.kind != sim.DOOR_KIND and s.id < 100, "%s is a wall of the compound" % s.name)
	eq(sim.waves.target_sections(plan, 1)[0], targets[0], "the first is the nearest")
	# with the spawn point put by hand: the east side's sections for an east spawn point, the north's for a north one
	var east := plan.duplicate(true)
	east["heading"] = [1]    # (83.5, 9.5)
	var east_ids: Array = sim.waves.target_sections(east, 4).map(func(s): return s.side)
	check(east_ids.count("E") >= 2, "an east spawn point breaks the east wall: %s" % str(east_ids))
	var north := plan.duplicate(true)
	north["heading"] = [6]    # (29, 0.5)
	var north_sides: Array = sim.waves.target_sections(north, 3).map(func(s): return s.side)
	check(north_sides.count("N") >= 2, "a north one the north wall: %s" % str(north_sides))
	var west := plan.duplicate(true)
	west["heading"] = [8]    # (0.5, 37)
	var west_sides: Array = sim.waves.target_sections(west, 3).map(func(s): return s.side)
	check(west_sides.count("W") >= 2, "a west one the west wall: %s" % str(west_sides))
	g.world.free()


func test_a_fallen_wall_and_a_full_one_are_not_targets_and_the_alarm_is() -> void:
	var g := Helpers.avatar_game(2, 5)
	var sim = g.sim
	Helpers.at(sim, 10, 17.0)
	sim.zombies.clear()
	for s in sim.segments:
		for sl in s.slots:
			sl.who = null
	var plan: Dictionary = sim.waves.plan_for(10)
	var first = sim.waves.target_sections(plan)[0]
	first.state = 3
	check(not sim.waves.target_sections(plan, 30).has(first), "a section that has fallen is not one the dead go to")
	first.state = 0
	for sl in first.slots:
		sl.who = sim.spawn(sl.x, sl.y, "attack")
	check(not sim.waves.target_sections(plan, 30).has(first), "nor one with every place taken")
	for sl in first.slots:
		sl.who = null
	sim.zombies.clear()
	# the alarm set on the farthest wall draws tonight's dead to it
	var far = null
	for s in sim.segments:
		if s.id < 100 and s.kind != sim.DOOR_KIND and not sim.waves.target_sections(plan, 3).has(s):
			far = s
	sim.stock.scrap = 20.0
	check(sim.tactics.order_lure(far), "the alarm is set")
	eq(sim.waves.target_sections(plan)[0], far, "and it is the first target tonight")
	var tomorrow := plan.duplicate(true)
	tomorrow["day"] = sim.day + 1
	check(sim.waves.target_sections(tomorrow)[0] != far, "but not a day ahead, when it will have stopped ringing")
	g.world.free()
