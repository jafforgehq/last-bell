extends "res://tests/case.gd"
## The kinds of the dead and the night's plan: who comes when, how many, from
## where, and how each kind behaves.

const Helpers := preload("res://tests/helpers.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")


func _cost(plan: Dictionary) -> float:
	var c := 0.0
	for k in plan.queue:
		c += float(Kinds.KINDS[k].cost)
	return c


func test_each_kind_starts_when_it_should_and_the_shares_are_capped() -> void:
	var s1 := Kinds.shares(1, false)
	eq([s1.runner, s1.brute], [0.0, 0.0], "night 1 is walkers only")
	near(Kinds.shares(4, false).runner, 0.06, 0.0001, "runners start at 6% on night 4")
	near(Kinds.shares(7, false).brute, 0.0, 0.0001, "no brutes yet on night 7")
	near(Kinds.shares(8, false).brute, 0.08, 0.0001, "brutes start at 8% on night 8")
	var late := Kinds.shares(25, false)
	near(late.runner, 0.30, 0.0001, "runners are capped at 30%")
	near(late.brute, 0.20, 0.0001, "brutes at 20%")
	near(late.walker, 0.50, 0.0001, "the rest are walkers")
	var big := Kinds.shares(30, true)
	near(big.runner, 0.30, 0.0001, "the last night: 30% runners")
	near(big.brute, 0.25, 0.0001, "and 25% brutes")


func test_night_one_is_walkers_and_later_nights_bring_the_rest() -> void:
	var g := Helpers.make(1, 1)
	var w = g.sim.waves
	var p1: Dictionary = w.plan_for(1)
	eq(p1.counts.runner + p1.counts.brute, 0, "only walkers on night 1")
	eq(p1.queue.size(), 30, "thirty of them")
	var p6: Dictionary = w.plan_for(6)
	check(p6.counts.runner >= 1 and p6.counts.brute == 0, "runners and no brutes on night 6: %s" % str(p6.counts))
	var p9: Dictionary = w.plan_for(9)
	check(p9.counts.brute >= 1 and p9.counts.runner >= 1, "a brute and runners on night 9: %s" % str(p9.counts))
	g.world.free()


func test_a_plan_is_the_same_whenever_it_is_made_and_differs_between_runs() -> void:
	var a := Helpers.make(5, 1)
	var plan_a: Dictionary = a.sim.waves.plan_for(7).duplicate(true)
	var b := Helpers.make(5, 1)
	for i in 50:
		b.sim.rng.randf()
	var plan_b: Dictionary = b.sim.waves.plan_for(7)
	eq(plan_a.queue, plan_b.queue, "the same queue of kinds")
	eq(plan_a.heading, plan_b.heading, "the same main spawn points")
	eq(plan_a.shown, plan_b.shown, "the same forecast number")
	var differs := false
	for s in [6, 7, 8, 9]:
		var c := Helpers.make(s, 1)
		var pc: Dictionary = c.sim.waves.plan_for(7)
		if pc.queue != plan_a.queue or pc.heading != plan_a.heading:
			differs = true
		c.world.free()
	check(differs, "other seeds plan other nights")
	a.world.free()
	b.world.free()


func test_a_plan_costs_about_its_budget() -> void:
	var g := Helpers.make(2, 1)
	var w = g.sim.waves
	for day in [1, 4, 8, 12, 20, 29, 30]:
		var plan: Dictionary = w.plan_for(day)
		var budget: float = w.night_budget(day)
		near(_cost(plan), budget, budget * 0.12 + 4.0, "night %d costs about %d points" % [day, int(budget)])
		check(plan.heading.size() >= 1 and plan.heading.size() <= 2, "one or two main spawn points")
	g.world.free()


func test_the_last_night_is_far_bigger_and_has_brutes() -> void:
	var g := Helpers.make(3, 1)
	var w = g.sim.waves
	check(w.is_big(30) and not w.is_big(29), "night 30 is the last")
	check(w.night_budget(30) >= 2.3 * w.budget_for(30), "its budget is the day's, times the bonus")
	var plan: Dictionary = w.plan_for(30)
	check(plan.big, "the plan knows")
	check(plan.counts.brute >= 4, "several brutes: %d" % int(plan.counts.brute))
	g.world.free()


func test_each_kind_has_its_stats() -> void:
	var g := Helpers.make(4, 1)
	var sim = g.sim
	for kind in ["walker", "runner", "brute"]:
		var k: Dictionary = Kinds.KINDS[kind]
		for i in 25:
			var z = sim.spawn(30.0, 10.0, "wander", kind)
			eq(z.kind, kind, "its kind")
			check(z.hp >= k.hp[0] and z.hp <= k.hp[1], "%s hp %d" % [kind, int(z.hp)])
			check(z.speed >= k.speed[0] - 0.0001 and z.speed <= k.speed[1] + 0.0001, "%s speed %.2f" % [kind, z.speed])
			near(z.claw, float(k.claw), 0.0001, "%s claw" % kind)
			near(z.size, float(k.size), 0.0001, "%s size" % kind)
			if kind != "walker":
				check(not z.limp, "%s does not limp" % kind)
	g.world.free()


func test_a_runner_is_far_quicker_and_a_brute_far_tougher() -> void:
	var run_speed: float = Kinds.KINDS.runner.speed[0]
	check(run_speed >= 1.5 and run_speed > 1.7 * float(Kinds.KINDS.walker.speed[1]), "the slowest runner outruns the quickest walker by far")
	check(float(Kinds.KINDS.brute.hp[0]) >= 3.0 * float(Kinds.KINDS.walker.hp[1]), "a brute has several times the health")


func test_a_brute_does_several_times_the_damage_to_a_wall() -> void:
	var g := Helpers.make(6, 1)
	var sim = g.sim
	var seg = sim.segments[5]
	var totals := {}
	for kind in ["walker", "brute"]:
		var z = sim.spawn(60.0, 14.0, "wander", kind)
		z.speed = 0.0
		seg.hp = seg.max_hp
		sim._segment_state(seg)
		var before: float = seg.hp
		for i in 60:
			sim._claw(z, seg)
		totals[kind] = before - seg.hp
	check(totals.brute >= 2.8 * totals.walker, "a brute does about three and a half times a walker's damage: %.0f against %.0f" % [totals.brute, totals.walker])
	g.world.free()


func test_the_guns_pick_a_brute_before_a_nearer_walker() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	sim.zombies.clear()
	var ruth = sim.people[0]
	ruth.x = 39.0
	ruth.y = 18.8
	var near_walker = sim.spawn(39.0, 15.8, "wander", "walker")
	var far_brute = sim.spawn(39.0, 13.8, "wander", "brute")
	near_walker.speed = 0.0
	far_brute.speed = 0.0
	eq(sim._find_target(ruth), far_brute, "the brute is shot first")
	g.world.free()


func test_a_night_brings_its_brutes_and_says_so() -> void:
	var g := Helpers.make(8, 1)
	var sim = g.sim
	sim.day = 10
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	var plan: Dictionary = sim.waves.plan_for(10)
	check(plan.counts.brute >= 1, "the plan has a brute")
	var told := false
	var kinds_seen := {}
	for i in 280 * 30:
		sim.update(1.0 / 30.0)
		if sim.alerts.has("brute"):
			told = true
		for z in sim.zombies:
			kinds_seen[z.kind] = true
		if told and kinds_seen.has("runner"):
			break
	check(told, "an alert says a brute is coming")
	check(kinds_seen.has("brute") and kinds_seen.has("runner"), "and the night did bring them: %s" % str(kinds_seen.keys()))
	g.world.free()
