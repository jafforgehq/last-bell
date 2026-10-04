extends "res://tests/case.gd"
## Priorities (round 25, S25.1: scripts/sim/priorities.gd, assets/data/priorities.json): the up to four things the player asks the base to put first, as ranked
## weights (3, 2, 1.5, 1) that move the seat plan, the wall line, the ammo target and a standing errand. Avatar mode in the settlement game only; nothing changes
## until a chip is tapped, a person the player moved is never moved back, and no `sim.rng` is drawn.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


# ----------------------------------------------------------------- helpers --

## A settlement game with an avatar (Ruth) and Dez (the bench), Marcus (the lookout), Ana (the infirmary) and Walt (the radio desk), on `day` at `hour`, no nights, no
## dead about, the ideas off (nothing but this module moves the jobs).
func _game(day: int = 3, hour: float = 7.0, seed_value: int = 11) -> Dictionary:
	var g := Helpers.avatar_game(seed_value, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.initiative.enabled = false
	Helpers.at(sim, day, hour)
	sim.events.clear()
	return g


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _jobs(sim) -> Dictionary:
	var out := {}
	for p in sim.people:
		out[String(p.id)] = String(sim.jobs.job_of(p))
	return out


func _policy_news(sim) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == "policy":
			out.append(String(e.text))
	return out


# ------------------------------------------------------------------- the taps --

func test_the_taps_make_the_ranks_and_four_is_the_most() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.priorities
	eq(pr.order, [], "nothing is ranked")
	for id in ["food", "defence", "rest", "water"]:
		check(bool(pr.toggle(id).ok), "%s is taken" % id)
	eq(pr.order, ["food", "defence", "rest", "water"], "the tap order is the rank")
	eq([pr.rank_of("food"), pr.rank_of("defence"), pr.rank_of("rest"), pr.rank_of("water"), pr.rank_of("scavenge")], [1, 2, 3, 4, 0], "the ranks")
	eq([pr.weight("food"), pr.weight("defence"), pr.weight("rest"), pr.weight("water"), pr.weight("scavenge")], [3.0, 2.0, 1.5, 1.0, 0.0], "the weights")
	var fifth: Dictionary = pr.toggle("scavenge")
	check(not bool(fifth.ok), "a fifth is refused")
	eq(String(fifth.why), "Four at most: tap one to drop it", "in these words")
	eq(pr.order.size(), 4, "and nothing changed")
	check(bool(pr.toggle("defence").ok), "a tap on a ranked one drops it")
	eq(pr.order, ["food", "rest", "water"], "the ones below move up")
	eq(pr.rank_of("rest"), 2, "to rank two")
	check(not bool(pr.toggle("nonsense").ok), "a priority that is not one is refused")
	check(bool(pr.set_order(["rebuild", "food", "rebuild"]).ok), "the card's one tap sets the order")
	eq(pr.order, ["rebuild", "food"], "each once")
	check(not bool(pr.set_order(["food", "bogus"]).ok) and pr.order == ["rebuild", "food"], "a bad order changes nothing")
	var told := _policy_news(sim)
	eq(told.size(), 1, "the taps within an hour are one News line")
	eq(told[0], "Priorities: Rebuilding, Food", "that says the last order")
	var heard := 0
	for e in sim.events:
		if String(e.type) == "priorities":
			heard += 1
	check(heard >= 5, "and every tap is an event")
	g.world.free()
	# no avatar: nothing is taken
	var plain := Helpers.make(3, 1, 5)
	check(not bool(plain.sim.priorities.toggle("food").ok) and plain.sim.priorities.order.is_empty(), "no avatar, no priorities")
	plain.world.free()


func test_the_shifts_are_the_plans_numbers_and_exactly_nothing_untapped() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.priorities
	eq(pr.wall_line_shift(), 0.0, "no wall line shift untapped")
	eq(pr.ammo_target_shift(), 0.0, "no ammo shift untapped")
	near(sim.tactics.repair_below(), 0.7, 1.0e-9, "the line is the slider's")
	eq(sim.workshop.target(), 300.0, "and the target")
	pr.set_order(["defence"])
	near(pr.wall_line_shift(), 0.15, 1.0e-9, "Defence first: +15%")
	near(sim.tactics.repair_below(), 0.85, 1.0e-9, "mends from 85% not 70%")
	eq(pr.ammo_target_shift(), 100.0, "the ammo target +100 at rank 1")
	eq(sim.workshop.target(), 400.0, "which the bench reads")
	pr.set_order(["food", "defence"])
	near(pr.wall_line_shift(), 0.10, 1.0e-9, "second: +10%")
	eq(pr.ammo_target_shift(), 75.0, "and 66.7 to the step of 25")
	pr.set_order(["food", "water", "defence"])
	eq(pr.ammo_target_shift(), 50.0, "third: 50")
	pr.set_order(["rebuild"])
	near(pr.wall_line_shift(), -0.15, 1.0e-9, "Rebuilding first: the line goes down to 55%")
	near(sim.tactics.repair_below(), 0.55, 1.0e-9, "the crew is on the site")
	eq(pr.ammo_target_shift(), 0.0, "and the ammo target is not touched")
	pr.set_order(["defence"])
	pr.enabled = false
	eq([pr.wall_line_shift(), pr.ammo_target_shift(), pr.weight("defence")], [0.0, 0.0, 0.0], "switched off (Orientation Day), every number is neutral")
	eq(pr.seat_plan(), {}, "and so is the plan")
	g.world.free()


# ------------------------------------------------------------------ the seats --

func test_the_seat_plan_follows_the_ranks() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.priorities
	eq(pr.seat_plan(), {}, "no priority, no plan")
	pr.set_order(["food"])
	eq(pr.seat_plan(), {"radio": 1, "watch": 1, "garden": 2}, "Food first: the desks keep a hand each and the beds get the rest")
	pr.set_order(["defence"])
	eq(pr.seat_plan(), {"radio": 1, "watch": 1, "bench": 1, "builders": 1}, "Defence first: the bench and the wall crew")
	pr.set_order(["water"])
	eq(pr.seat_plan(), {"watch": 1, "radio": 1, "infirmary": 1, "bench": 1}, "Water has no seat of its own: the hands stay where they are")
	# a need counts: with Defence second (the bench 4, the wall crew 3) a stock of food under two days lifts the beds from 1 to 4, above the wall crew
	pr.set_order(["scavenge", "defence"])
	eq(pr.seat_plan(), {"radio": 1, "watch": 1, "bench": 1, "builders": 1}, "plenty of food: the beds stay empty")
	sim.stock.food = 2.0
	eq(pr.seat_plan(), {"radio": 1, "watch": 1, "bench": 1, "garden": 1}, "food under two days: a hand goes to the beds")
	g.world.free()


func test_the_staffer_moves_people_and_never_a_pinned_one() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.priorities
	var dez = _p(sim, "dez")
	var ana = _p(sim, "ana")
	eq(_jobs(sim), {"ruth": "", "dez": "bench", "marcus": "watch", "ana": "infirmary", "walt": "radio"}, "the jobs as they were")
	var idle: Dictionary = pr.staff()
	eq(idle, {"moved": [], "filled": 0, "pinned": []}, "no priority, nothing is done")
	eq(_jobs(sim)["dez"], "bench", "and nobody moved")
	pr.set_order(["food"])
	var run: Dictionary = pr.staff()
	eq(sim.jobs.job_of(dez), "garden", "Dez goes to the beds")
	eq(sim.jobs.job_of(ana), "garden", "and Ana")
	eq(sim.jobs.job_of(_p(sim, "walt")), "radio", "Walt keeps the desk")
	eq(sim.jobs.job_of(_p(sim, "marcus")), "watch", "and Marcus the lookout")
	eq(run.moved.size(), 2, "two moved")
	eq(int(run.filled), 0, "and none filled from nothing")
	var lines := _policy_news(sim)
	check(lines.size() >= 3 and lines.size() <= 4, "told in a few lines (%d)" % lines.size())
	check(lines.has("The base moved Dez to the beds (Food)") or lines.has("The base moved Ana to the beds (Food)"), "in the words of the contract: %s" % str(lines))
	# no flip-flop: the same hour, then the next, are empty
	eq(pr.staff().moved, [], "a second run in the same hour is empty")
	sim.clock_min += 61.0
	var again: Dictionary = pr.staff()
	eq([again.moved, again.filled], [[], 0], "an hour on the plan has not changed: nobody is moved back")
	# the player moves Ana by hand: pinned
	check(sim.jobs.assign(ana, "infirmary"), "the player gives Ana the infirmary")
	eq(pr.pinned(), ["ana"], "she is pinned at once")
	sim.clock_min += 61.0
	var third: Dictionary = pr.staff()
	eq(sim.jobs.job_of(ana), "infirmary", "the staffer leaves her where the player put her")
	eq(third.pinned, ["ana"], "and says so")
	eq(pr.seat_plan(), {"radio": 1, "watch": 1, "garden": 1}, "the plan is for the others (her seat is not the plan's to give)")
	# never at night, and the dead at the wall
	var before := _jobs(sim)
	pr.set_order(["defence"])
	Helpers.at(sim, 3, 22.0)
	sim.clock_min += 200.0
	eq(pr.staff().moved, [], "nothing moves at night")
	Helpers.at(sim, 4, 9.0)
	sim.radio.alarm_on = true
	eq(pr.staff().moved, [], "nor under the alarm")
	check(_jobs(sim) == before, "the jobs are as they were")
	sim.radio.alarm_on = false
	sim.clock_min += 200.0
	pr.release_pins()
	eq(pr.pinned(), [], "Let the base decide")
	var last: Dictionary = pr.staff()
	check(last.moved.size() >= 1, "and the base does")
	check(sim.jobs.job_of(ana) != "infirmary", "Ana is the base's again")
	g.world.free()


func test_a_trip_does_not_strip_the_desks_or_call_for_a_new_plan() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.priorities
	pr.set_order(["defence"])
	pr.staff()
	eq(_jobs(sim), {"ruth": "", "dez": "bench", "marcus": "watch", "ana": "builders", "walt": "radio"}, "Defence: the bench and the wall crew, the desks kept")
	pr.look()
	var before := String(pr._sig)
	# an errand takes Dez and Ana away: they keep their seats, and the two at home are left at the desks
	_p(sim, "dez").away = {}
	_p(sim, "ana").away = {}
	check(String(pr._signature()) == before, "a trip is not a change of the crew")
	eq(pr.seat_plan(), {"radio": 1, "watch": 1}, "the plan for the two at home keeps the desks (the two away still count as hands for them)")
	sim.clock_min += 61.0
	var run: Dictionary = pr.staff()
	eq([run.moved, run.filled], [[], 0], "so nobody is moved")
	check(_jobs(sim)["walt"] == "radio" and _jobs(sim)["marcus"] == "watch", "Walt has the radio and Marcus the lookout")
	g.world.free()


func test_rest_leaves_the_weariest_out_and_water_alone_does_not_shuffle() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.priorities
	sim.policies.weary = {"dez": 55.0, "marcus": 30.0, "walt": 62.0}
	pr.set_order(["rest"])
	var plan: Dictionary = pr.seat_plan()
	eq(plan, {"watch": 1, "infirmary": 1}, "Rest first (weight 3): the two weariest (Walt, Dez) are out of the plan, the others stay")
	pr.staff()
	eq(_jobs(sim), {"ruth": "", "dez": "", "marcus": "watch", "ana": "infirmary", "walt": ""}, "they rest")
	pr.set_order(["water"])
	sim.clock_min += 61.0
	var moved: Array = pr.staff().moved
	eq(moved, [], "Water alone moves nobody")
	eq(_jobs(sim)["marcus"], "watch", "the lookout is where he was")
	g.world.free()


# ----------------------------------------------------------- the standing errand --

func test_the_standing_errand_goes_once_a_day_with_its_terms() -> void:
	var g := _game(3, 7.0)
	var sim = g.sim
	var pr = sim.priorities
	eq(pr.standing_errand(), {"sent": false, "why": ""}, "no priority, no errand")
	pr.set_order(["food"])
	var none: Dictionary = pr.standing_errand()
	check(not bool(none.sent) and String(none.why) == "No standing order", "Food with plenty of food: nothing to send for (%s)" % str(none))
	sim.stock.food = 6.0
	check(pr.errand_wish() == "food", "the base wants food")
	var sent: Dictionary = pr.standing_errand()
	check(bool(sent.sent), "an errand goes: %s" % String(sent.get("why", "")))
	check(String(sent.get("line", "")).begins_with("Standing order: ") and String(sent.line).contains(" set off for ") and String(sent.line).ends_with("(Food)"), "told as a standing order (%s)" % String(sent.get("line", "")))
	eq(sim.radio.errand_wait.size(), 1, "it is in the radio's queue: its delay, its refusals, its terms")
	check(_policy_news(sim).has(String(sent.get("line", ""))), "and in the News")
	var second: Dictionary = pr.standing_errand()
	check(not bool(second.sent), "only one a day")
	eq(pr.last_errand.get("stock", ""), "food", "the order keeps what it was for")
	g.world.free()
	# nobody can go: refused with the reason, and the day is not used up
	var h := _game(3, 7.0)
	var s2 = h.sim
	s2.priorities.set_order(["scavenge"])
	for p in s2.people:
		if not p.player:
			p.away = {}
	var refused: Dictionary = s2.priorities.standing_errand()
	check(not bool(refused.sent) and String(refused.why) != "", "nobody free: %s" % str(refused))
	eq(s2.priorities.last_why.get("day", 0), 3, "the reason is kept for the debrief")
	for p in s2.people:
		p.away = null
	Helpers.at(s2, 3, 12.0)
	check(String(s2.priorities.standing_errand().why).begins_with("Standing orders go out"), "and not at noon")
	h.world.free()


# ----------------------------------------------------------- nothing untapped --

func test_nothing_changes_untapped_and_no_dice_are_thrown() -> void:
	# two games from the same seed, three game days: with the base's management on and with it off (as Orientation Day has it): the same dice, stores and jobs
	var a := _game(1, 7.0, 21)
	var b := _game(1, 7.0, 21)
	Helpers.quiet_base(b.sim)
	for g in [a, b]:
		g.sim.waves.enabled = true
		g.sim.initiative.enabled = true
		for m in ["policies", "problems", "dilemmas"]:
			g.sim.get(m).enabled = false    # (the other three modules of the round are tested on their own)
		Helpers.run(g.sim, 3.0 * 24.0 * 20.0)
	eq(a.sim.rng.state, b.sim.rng.state, "the dice are where they were")
	eq(_jobs(a.sim), _jobs(b.sim), "the jobs are the same")
	for k in a.sim.stock:
		near(float(a.sim.stock[k]), float(b.sim.stock[k]), 1.0e-9, "the %s is the same" % k)
	for i in a.sim.people.size():
		near(a.sim.people[i].x, b.sim.people[i].x, 1.0e-9, "%s stands where it would" % a.sim.people[i].first)
	check(a.sim.briefing.current.has("day") and not b.sim.briefing.current.has("day"), "(and only the managed one has briefed)")
	a.world.free()
	b.world.free()
	# and the calls themselves draw nothing, with priorities set
	var g := _game(3, 7.0)
	var sim = g.sim
	sim.priorities.set_order(["food", "defence", "rest", "scavenge"])
	sim.stock.food = 6.0
	var state: int = sim.rng.state
	sim.priorities.seat_plan()
	sim.priorities.staff()
	sim.priorities.standing_errand()
	sim.priorities.suggested()
	sim.briefing.concerns()
	sim.briefing.facilities()
	sim.briefing.compose()
	Helpers.at(sim, 3, 18.8)
	sim.briefing.debrief()
	eq(sim.rng.state, state, "no draw from the rules' dice anywhere in the two modules")
	g.world.free()


# --------------------------------------------------------------------- save --

func test_a_save_keeps_the_order_the_pins_and_the_look_and_a_damaged_one_is_mended() -> void:
	var a := _game()
	var sim = a.sim
	sim.priorities.set_order(["food", "defence"])
	sim.priorities.staff()
	sim.jobs.assign(_p(sim, "ana"), "infirmary")    # pinned
	sim.stock.food = 6.0
	sim.priorities.standing_errand()
	var d := SaveGame.to_dict(sim)
	check(d.modules.has("priorities") and d.modules.has("briefing"), "both modules are in the save")
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads from text")
	var sb = b.sim.priorities
	var sa = sim.priorities
	eq(sb.order, ["food", "defence"], "the order")
	eq(sb.staffed, sa.staffed, "who was given what")
	eq(sb.pinned(), ["ana"], "the pin")
	eq(sb.last_errand, sa.last_errand, "the errand")
	eq(sb.seat_plan(), sa.seat_plan(), "so the same plan")
	eq(sb.save(), sa.save(), "the same state, key for key")
	# a save from before is a fresh module
	var fresh := _bare()
	var d2 := SaveGame.to_dict(sim)
	d2.modules.erase("priorities")
	d2.modules.erase("briefing")
	check(SaveGame.apply(fresh.sim, d2), "a save from before loads")
	eq(fresh.sim.priorities.order, [], "no priorities")
	eq(fresh.sim.priorities.pinned(), [], "no pins")
	# a damaged one: unknown ids, a fifth rank, numbers that are not numbers
	sb.load_state({
		"order": ["food", "bogus", "water", "defence", "rest", "rebuild", "food"], "staffed": {"dez": "garden", "nobody": "bench", "ana": "no such station"}, "pins": {"nobody": true, "walt": true},
		"acc": NAN, "last_staff": "soon", "morning_day": 9999, "hours": {"bench": 1.0e9, "moon": 3.0, "garden": -5.0},
		"last_errand": {"day": 2, "line": "x".repeat(900), "ids": ["dez", "ghost"], "place": "bakery", "stock": "food"},
	})
	eq(sb.order, ["food", "water", "defence", "rest"], "unknown ids and a fifth rank are dropped")
	eq(sb.staffed, {"dez": "garden"}, "an unknown person or station is dropped")
	eq(sb.pins, {"walt": true}, "and an unknown pin")
	eq(sb.seat_hours(), {"bench": sb.MAX_HOURS, "garden": 0.0}, "the hours are held to their range")
	check(String(sb.last_errand.line).length() <= sb.MAX_TEXT and sb.last_errand.ids == ["dez"], "the errand is cleaned")
	sb.load_state({})
	eq(sb.save().order, [], "an empty save is a fresh module")
	a.world.free()
	b.world.free()
	fresh.world.free()
