extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")


## A game at 19:00 on day 1 with the bell rung, `ammo` in the stock.
func _night(seed_value: int, ammo: float) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.stock.ammo = ammo
	sim.minutes = 19.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = true
	return g


func test_with_no_ammo_the_guns_are_silent() -> void:
	var full := _night(11, 300.0)
	Helpers.run(full.sim, 200.0)
	var dry := _night(11, 0.0)
	Helpers.run(dry.sim, 200.0)
	check(full.sim.kills >= 20, "with ammo the crew kills plenty: %d" % full.sim.kills)
	check(dry.sim.kills * 2 < full.sim.kills, "without it far fewer: %d against %d" % [dry.sim.kills, full.sim.kills])
	near(dry.sim.stock.ammo, 0.0, 0.0001, "and the stock stays at zero")
	full.world.free()
	dry.world.free()


func test_shots_spend_the_stock_and_it_never_goes_below_zero() -> void:
	var g := _night(12, 3.0)
	var sim = g.sim
	Helpers.run(sim, 200.0)
	check(sim.stock.ammo >= 0.0, "never negative: %f" % sim.stock.ammo)
	check(sim.stock.ammo < 0.35, "the three rounds' worth were spent: %f" % sim.stock.ammo)
	g.world.free()


func test_a_shot_needs_a_whole_shot_in_the_stock() -> void:
	var g := _night(13, 0.1)
	var sim = g.sim
	Helpers.run(sim, 120.0)
	near(sim.stock.ammo, 0.1, 0.0001, "a tenth of a round is not enough for a shot: nobody fired")
	g.world.free()


func test_scavenged_ammo_makes_the_guns_fire_again() -> void:
	var g := _night(14, 0.0)
	var sim = g.sim
	Helpers.run(sim, 80.0)
	var before: int = sim.kills
	sim.stock.ammo = 60.0
	Helpers.run(sim, 120.0)
	check(sim.kills >= before + 8, "with ammo again the kills climb: %d to %d" % [before, sim.kills])
	check(sim.stock.ammo < 60.0, "and it is spent")
	g.world.free()


func test_the_crew_is_told_when_the_guns_go_silent() -> void:
	var g := _night(15, 0.0)
	var sim = g.sim
	var told := false
	for i in 40 * 30:
		sim.update(1.0 / 30.0)
		if sim.alerts.has("ammo-out"):
			told = true
			break
	check(told, "an alert says the ammo is out")
	if told:
		eq(sim.alerts["ammo-out"].level, "danger", "and it is a danger")
	g.world.free()


func test_an_empty_gun_is_swung_at_what_stands_next_to_it() -> void:
	var g := _night(16, 0.0)
	var sim = g.sim
	var ruth = sim.people[0]
	# already at the post she walks to at the bell, so nothing sends her off
	ruth.x = float(ruth.def.post.x)
	ruth.y = float(ruth.def.post.y)
	var z = sim.spawn(ruth.x + 1.0, ruth.y, "wander")
	z.speed = 0.0
	z.hp = 6.0
	var start_hp: float = z.hp
	for i in 20 * 30:
		sim.update(1.0 / 30.0)
		if z.hp < start_hp or z.state == "dying" or z.state == "dead":
			break
	check(z.hp < start_hp or z.state == "dying" or z.state == "dead", "the butt of the gun hurt it")
	g.world.free()


func test_a_melee_weapon_does_not_need_ammo() -> void:
	var g := _night(17, 0.0)
	var sim = g.sim
	var hector = null
	for p in sim.people:
		if p.weapon == "pike":
			hector = p
	check(hector != null, "the crew has a pike")
	if hector == null:
		g.world.free()
		return
	hector.x = float(hector.def.post.x)
	hector.y = float(hector.def.post.y)
	var z = sim.spawn(hector.x + 1.2, hector.y, "wander")
	z.speed = 0.0
	z.hp = 6.0
	for i in 20 * 30:
		sim.update(1.0 / 30.0)
		if z.state == "dying" or z.state == "dead":
			break
	check(z.state == "dying" or z.state == "dead", "the pike killed it with no ammo in the stock")
	g.world.free()
