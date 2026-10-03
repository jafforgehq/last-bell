extends "res://tests/case.gd"
## The leader's presence (round 19, slice 3, scripts/sim/nights.gd `rallied`, `aim_mult`, `fire_mult`; docs/superpowers/plans/2026-10-03-round-19.md,
## S3.2): with the avatar up, at the base and within `rally.radius` tiles of a defender, that defender aims better (`Sim.aim_factor`) and
## fires faster (`Sim._fire`'s cooldown). It is "a boon on any night": the avatar himself never gets it, and it needs an avatar, a base
## (not a place's sim) and a leader who can stand. Without one the hooks are neutral and draw nothing. The numbers are read through NightData.

const Helpers := preload("res://tests/helpers.gd")
const NightData := preload("res://scripts/sim/night_data.gd")


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## A game with Ruth as the avatar at (40.5, 30.5) and Dez `gap` tiles east of her, at night, nobody else about.
func _game(gap: float = 3.0) -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.zombies.clear()
	Helpers.at(sim, 3, 21.0)
	var lead = sim.avatar.player()
	lead.x = 40.5
	lead.y = 30.5
	var dez = _p(sim, "dez")
	dez.x = lead.x + gap
	dez.y = lead.y
	g["lead"] = lead
	g["dez"] = dez
	return g


func _radius() -> float:
	return NightData.num("rally.radius")


# ------------------------------------------------------------------- who is rallied --

func test_a_defender_inside_the_radius_is_rallied() -> void:
	var g := _game(_radius() - 0.5)
	check(g.sim.nights.rallied(g.dez), "inside the radius")
	near(g.sim.nights.aim_mult(g.dez), 1.0 + NightData.num("rally.aim"), 1.0e-9, "the aim")
	near(g.sim.nights.fire_mult(g.dez), NightData.num("rally.fire"), 1.0e-9, "the cooldown")
	g.world.queue_free()


func test_a_defender_outside_the_radius_is_not() -> void:
	var g := _game(_radius() + 0.5)
	check(not g.sim.nights.rallied(g.dez), "outside the radius")
	near(g.sim.nights.aim_mult(g.dez), 1.0, 1.0e-9, "no aim bonus")
	near(g.sim.nights.fire_mult(g.dez), 1.0, 1.0e-9, "no fire bonus")
	g.world.queue_free()


func test_the_numbers_are_the_plans_unless_the_data_says_otherwise() -> void:
	near(_radius(), 9.0, 1.0e-9, "the radius")
	near(NightData.num("rally.aim"), 0.15, 1.0e-9, "the aim")
	near(NightData.num("rally.fire"), 0.85, 1.0e-9, "the fire")


func test_the_avatar_himself_is_never_rallied() -> void:
	var g := _game()
	check(not g.sim.nights.rallied(g.lead), "not him")
	near(g.sim.nights.aim_mult(g.lead), 1.0, 1.0e-9, "his own aim is his own")
	near(g.sim.nights.fire_mult(g.lead), 1.0, 1.0e-9, "and his own rate")
	g.world.queue_free()


func test_the_dead_the_gone_and_the_away_are_not_rallied() -> void:
	var g := _game()
	g.dez.dead = true
	check(not g.sim.nights.rallied(g.dez), "a dead one")
	g.dez.dead = false
	g.dez.turned = true
	check(not g.sim.nights.rallied(g.dez), "one who turned")
	g.dez.turned = false
	g.dez.away = {"party": true}
	check(not g.sim.nights.rallied(g.dez), "one away on a trip")
	g.dez.away = null
	check(g.sim.nights.rallied(g.dez), "back at the base again")
	g.world.queue_free()


func test_nobody_is_rallied_while_the_leader_cannot_lead() -> void:
	var g := _game()
	check(g.sim.nights.rallied(g.dez), "to begin with")
	g.lead.downed = true
	check(not g.sim.nights.rallied(g.dez), "the avatar is down")
	g.lead.downed = false
	g.lead.turned = true
	check(not g.sim.nights.rallied(g.dez), "the avatar has turned")
	g.lead.turned = false
	g.lead.dead = true
	check(not g.sim.nights.rallied(g.dez), "the avatar is dead")
	g.lead.dead = false
	g.lead.away = {"party": true}
	check(not g.sim.nights.rallied(g.dez), "the avatar is away on a trip")
	near(g.sim.nights.aim_mult(g.dez), 1.0, 1.0e-9, "and so no aim bonus")
	near(g.sim.nights.fire_mult(g.dez), 1.0, 1.0e-9, "and no fire bonus")
	g.lead.away = null
	check(g.sim.nights.rallied(g.dez), "up again")
	g.world.queue_free()


func test_with_no_avatar_nobody_is_rallied() -> void:
	var g := _game()
	check(g.sim.avatar.set_player(null), "the avatar is given up")
	check(not g.sim.nights.active(), "nothing of the nights applies")
	check(not g.sim.nights.rallied(g.dez), "nobody is rallied")
	near(g.sim.nights.aim_mult(g.dez), 1.0, 1.0e-9, "no aim bonus")
	near(g.sim.nights.fire_mult(g.dez), 1.0, 1.0e-9, "no fire bonus")
	g.world.queue_free()


func test_in_a_places_sim_nobody_is_rallied() -> void:
	var g := _game()
	g.sim.nights_on = false
	check(not g.sim.nights.rallied(g.dez), "a place has no rally")
	near(g.sim.nights.aim_mult(g.dez), 1.0, 1.0e-9, "no aim bonus")
	near(g.sim.nights.fire_mult(g.dez), 1.0, 1.0e-9, "no fire bonus")
	g.world.queue_free()


# --------------------------------------------------------------------- the effects --

func test_aim_factor_carries_the_rally() -> void:
	var g := _game(2.0)
	var sim = g.sim
	var rallied: float = sim.aim_factor(g.dez)
	var lead_with: float = sim.aim_factor(g.lead)
	sim.nights_on = false
	var plain: float = sim.aim_factor(g.dez)
	var lead_without: float = sim.aim_factor(g.lead)
	sim.nights_on = true
	near(rallied, plain * (1.0 + NightData.num("rally.aim")), 1.0e-9, "aim_factor x (1 + rally.aim)")
	near(lead_with, lead_without, 1.0e-9, "the avatar's own aim is not helped")
	g.dez.x = g.lead.x + _radius() + 2.0
	near(sim.aim_factor(g.dez), plain, 1.0e-9, "out of the radius: the plain factor")
	g.world.queue_free()


## One shot of Dez at a walker 6 tiles away, with the dice seeded the same: the cooldown it leaves and the dice it used.
func _shot_cooldown(g: Dictionary) -> Dictionary:
	var sim = g.sim
	var z = sim.spawn(g.dez.x + 6.0, g.dez.y, "wander")
	z.hp = 1000.0
	g.dez.mag = 10
	g.dez.cooldown = 0.0
	g.dez.reloading = 0.0
	sim.stock.ammo = 100.0
	sim.rng.seed = 4242
	sim._fire(g.dez, z, 0.0)
	var out := {"cooldown": float(g.dez.cooldown), "state": sim.rng.state}
	sim.zombies.erase(z)
	return out


func test_a_rallied_defender_fires_faster_and_throws_no_extra_die() -> void:
	var g := _game(2.0)
	var sim = g.sim
	var near_him := _shot_cooldown(g)
	sim.nights_on = false
	var alone := _shot_cooldown(g)
	check(float(alone.cooldown) > 0.0, "a shot leaves a cooldown")
	near(float(near_him.cooldown), float(alone.cooldown) * NightData.num("rally.fire"), 1.0e-9, "cooldown x rally.fire")
	eq(near_him.state, alone.state, "the same dice were thrown")
	g.world.queue_free()


func test_a_defender_out_of_reach_of_the_leader_fires_as_ever() -> void:
	var g := _game(_radius() + 3.0)
	var sim = g.sim
	var far := _shot_cooldown(g)
	sim.nights_on = false
	var alone := _shot_cooldown(g)
	eq(far.cooldown, alone.cooldown, "the same cooldown")
	eq(far.state, alone.state, "the same dice")
	g.world.queue_free()


func test_a_rallied_defender_who_fights_a_whole_night_shoots_more() -> void:
	# structure, not outcome: the same fight twice, near the leader and far from him, the dice seeded alike; the rallied one has fired more
	var shots := []
	for near_him in [true, false]:
		var g := _game(2.0 if near_him else _radius() + 4.0)
		var sim = g.sim
		sim.stock.ammo = 400.0
		g.dez.mag = 20
		var z = sim.spawn(g.dez.x + 5.0, g.dez.y, "wander")
		z.hp = 100000.0
		z.stagger = 1.0e9
		sim.rng.seed = 99
		g.dez.cooldown = 0.0
		for i in 600:
			sim._combat(g.dez, 1.0 / 30.0)
		shots.append(int(g.dez.stats.shots))
		g.world.queue_free()
	check(shots[0] > shots[1], "near the leader %d shots, far from him %d" % [shots[0], shots[1]])
