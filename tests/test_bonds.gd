extends "res://tests/case.gd"
## Bonds (scripts/sim/bonds.gd, map.json `bonds`): who is close to whom. Ruth and Marcus
## (family), Walt and Marcus (mentor), Dez and Hector and Ana and Ruth (friends). A friend
## within six tiles makes a person aim 8 percent better (the Loyal trait adds 4 more); and
## a bonded person downed, dead, turned or gone is a shock (see morale.gd).

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


func _quiet(hour: float = 9.0, seed_value: int = 7) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.events.clear()
	return g


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


## Everyone far from everyone, in a row 20 tiles apart.
func _spread(sim) -> void:
	var x := 0.0
	for p in sim.people:
		p.x = x
		p.y = 10.0
		x += 20.0


func _names(list: Array) -> Array:
	var out: Array = []
	for b in list:
		out.append("%s:%s" % [b.who.first, b.kind])
	out.sort()
	return out


# ------------------------------------------------------------------- the list --

func test_the_roster_has_four_bonds() -> void:
	var g := _quiet()
	var sim = g.sim
	eq(sim.d.get("bonds", []).size(), 4, "map.json has four")
	eq(_names(sim.bonds.of(_person(sim, "Ruth"))), ["Ana:friend", "Marcus:family"], "Ruth: Marcus is family, Ana a friend")
	eq(_names(sim.bonds.of(_person(sim, "Marcus"))), ["Ruth:family", "Walt:mentor"], "Marcus: Ruth and Walt")
	eq(_names(sim.bonds.of(_person(sim, "Walt"))), ["Marcus:mentor"], "Walt: Marcus")
	eq(_names(sim.bonds.of(_person(sim, "Dez"))), ["Hector:friend"], "Dez: Hector")
	eq(_names(sim.bonds.of(_person(sim, "Hector"))), ["Dez:friend"], "Hector: Dez")
	eq(_names(sim.bonds.of(_person(sim, "Ana"))), ["Ruth:friend"], "Ana: Ruth")
	for b in sim.bonds.of(_person(sim, "Ruth")):
		check(b.who is Object and sim.people.has(b.who), "the other is the person, not a name")
	g.world.free()


func test_a_mentor_and_a_student_see_each_other_as_such() -> void:
	var g := _quiet()
	var sim = g.sim
	var from_marcus: Array = sim.bonds.of(_person(sim, "Marcus"))
	var from_walt: Array = sim.bonds.of(_person(sim, "Walt"))
	for b in from_marcus:
		if b.who.first == "Walt":
			eq(b.role, "mentor", "to Marcus, Walt is the mentor")
	eq(from_walt[0].role, "student", "to Walt, Marcus is the student")
	for b in sim.bonds.of(_person(sim, "Ruth")):
		eq(b.role, b.kind, "family and friends are the same both ways")
	g.world.free()


func test_a_bond_that_makes_no_sense_is_dropped() -> void:
	var g := _quiet()
	var sim = g.sim
	sim.bonds.load_state({"list": [
		{"a": "ruth", "b": "nobody", "kind": "friend"},
		{"a": "ruth", "b": "ruth", "kind": "friend"},
		{"a": "dez", "b": "walt", "kind": "enemy"},
		{"a": "dez", "b": "ana", "kind": "friend"},
		{"a": "dez", "b": "ana", "kind": "friend"},
		{"b": "ana"},
		5,
	]})
	eq(_names(sim.bonds.of(_person(sim, "Dez"))), ["Ana:friend"], "only the good one, once")
	eq(sim.bonds.of(_person(sim, "Ruth")), [], "and the roster's are replaced, not added to")
	g.world.free()


# ----------------------------------------------------------------------- near --

func test_near_is_a_bonded_person_who_is_up_and_on_the_map_within_the_distance() -> void:
	var g := _quiet()
	var sim = g.sim
	_spread(sim)
	var ruth = _person(sim, "Ruth")
	var marcus = _person(sim, "Marcus")
	var hector = _person(sim, "Hector")
	check(not sim.bonds.near(ruth, 6.0), "far apart: nobody near")
	marcus.x = ruth.x + 5.9
	marcus.y = ruth.y
	check(sim.bonds.near(ruth, 6.0), "Marcus at 5.9 tiles")
	check(sim.bonds.near(marcus, 6.0), "and Ruth is near Marcus")
	marcus.x = ruth.x + 6.1
	check(not sim.bonds.near(ruth, 6.0), "at 6.1 he is not")
	check(sim.bonds.near(ruth, 7.0), "but is within 7")
	marcus.x = ruth.x + 3.0
	hector.x = ruth.x + 1.0
	hector.y = ruth.y
	marcus.downed = true
	check(not sim.bonds.near(ruth, 6.0), "a downed friend does not count (Hector is not her friend)")
	marcus.downed = false
	marcus.away = {"kind": "party"}
	check(not sim.bonds.near(ruth, 6.0), "nor one who is away")
	marcus.away = null
	marcus.dead = true
	check(not sim.bonds.near(ruth, 6.0), "nor a dead one")
	marcus.dead = false
	marcus.turned = true
	marcus.dead = true
	check(not sim.bonds.near(ruth, 6.0), "nor one who turned")
	g.world.free()


func test_a_friend_of_a_friend_is_not_a_bond() -> void:
	var g := _quiet()
	var sim = g.sim
	_spread(sim)
	var ana = _person(sim, "Ana")
	var marcus = _person(sim, "Marcus")
	marcus.x = ana.x + 1.0
	marcus.y = ana.y
	check(not sim.bonds.near(ana, 6.0), "Ana is Ruth's friend, not Marcus's")
	check(not sim.bonds.bonded(ana, marcus), "they are not bonded")
	check(sim.bonds.bonded(ana, _person(sim, "Ruth")), "Ana and Ruth are")
	check(sim.bonds.bonded(_person(sim, "Ruth"), ana), "whichever way round")
	g.world.free()


# ------------------------------------------------------------------------ aim --

func test_a_friend_close_by_makes_a_person_aim_eight_percent_better() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	_spread(sim)
	var dez = _person(sim, "Dez")
	var hector = _person(sim, "Hector")
	sim.traits.give(dez, [])
	eq(sim.bonds.aim_bonus(dez), 0.0, "alone: nothing")
	eq(sim.aim_factor(dez), 1.0, "and the aim is as it is")
	hector.x = dez.x + 4.0
	hector.y = dez.y
	near(sim.bonds.aim_bonus(dez), 0.08, 1e-9, "Hector within six tiles: 0.08")
	near(sim.aim_factor(dez), 1.08, 1e-9, "the aim is 8 percent better")
	near(sim.aim_factor(hector), 1.0 * 1.08, 1e-9, "and so is his")
	hector.x = dez.x + 8.0
	eq(sim.bonds.aim_bonus(dez), 0.0, "eight tiles away: nothing")
	g.world.free()


func test_the_bonus_really_changes_how_often_a_shot_hits() -> void:
	var hits: Array = []
	for with_friend in [false, true]:
		var g := _quiet(22.0, 5)
		var sim = g.sim
		_spread(sim)
		sim.stock.ammo = 100000.0
		var ana = _person(sim, "Ana")
		var ruth = _person(sim, "Ruth")
		sim.traits.give(ana, [])
		ruth.x = ana.x + (3.0 if with_friend else 30.0)
		ruth.y = ana.y
		var z = sim.spawn(ana.x + 4.0, ana.y, "wander")
		z.hp = 1.0e9
		for i in 6000:
			ana.mag = int(ana.gun.mag)
			ana.cooldown = 0.0
			sim._fire(ana, z, 0.0)
		hits.append(roundi((1.0e9 - z.hp) / float(ana.gun.dmg)))
		g.world.free()
	var gain := float(hits[1]) / float(hits[0])
	check(gain > 1.03 and gain < 1.13, "8 percent more of the shots hit with a friend beside her: %d against %d (x%.3f)" % [hits[1], hits[0], gain])


# ---------------------------------------------------------------------- shocks --

func test_a_friend_going_down_shakes_those_who_are_close_to_them() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var marcus = _person(sim, "Marcus")
	var hector = _person(sim, "Hector")
	var walt = _person(sim, "Walt")
	var before := {}
	for p in sim.people:
		before[p.id] = sim.morale.value(p)
	marcus.hp = 0.0
	sim.medical.on_downed(marcus, "bite")
	near(before.ruth - sim.morale.value(ruth), 10.0, 0.001, "Ruth, his family: 10 points")
	near(before.walt - sim.morale.value(walt), 10.0, 0.001, "Walt, his mentor: 10 points")
	near(before.hector - sim.morale.value(hector), 0.0, 0.001, "Hector did not know him that well")
	near(before.marcus - sim.morale.value(marcus), 0.0, 0.001, "and the one who is down has no shock for it (his state is in his mood)")
	g.world.free()


func test_a_friend_dying_or_turning_is_a_far_bigger_shock_than_a_stranger() -> void:
	for how in ["bled out", "turned"]:
		var g := _quiet()
		var sim = g.sim
		var ruth = _person(sim, "Ruth")
		var dez = _person(sim, "Dez")
		var hector = _person(sim, "Hector")
		sim.traits.give(ruth, [])
		sim.traits.give(dez, [])
		var before_ruth: float = sim.morale.value(ruth)
		var before_dez: float = sim.morale.value(dez)
		if how == "turned":
			sim.medical._turn(_person(sim, "Ana"))
		else:
			sim.medical.kill(_person(sim, "Ana"), how)
		near(before_ruth - sim.morale.value(ruth), 25.0, 0.001, "%s: Ana's friend Ruth loses 25" % how)
		near(before_dez - sim.morale.value(dez), 8.0, 0.001, "%s: Dez, who knew her less, 8" % how)
		g.world.free()


func test_someone_sent_out_through_the_gate_is_a_smaller_shock() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var dez = _person(sim, "Dez")
	var hector = _person(sim, "Hector")
	var before_dez: float = sim.morale.value(dez)
	var before_ruth: float = sim.morale.value(ruth)
	var before_hector: float = sim.morale.value(hector)
	sim.medical._exile(hector)
	near(before_dez - sim.morale.value(dez), 15.0, 0.001, "his friend Dez: 15")
	near(before_ruth - sim.morale.value(ruth), 6.0, 0.001, "the rest: 6")
	g.world.free()


# ---------------------------------------------------------------------- saves --

func test_the_bonds_are_saved_and_an_old_save_keeps_the_roster() -> void:
	var g := _quiet()
	var sim = g.sim
	var d := SaveGame.to_dict(sim)
	check(d.modules.has("bonds"), "the module has a place in the save")
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it applies")
	eq(_names(b.sim.bonds.of(_person(b.sim, "Ruth"))), ["Ana:friend", "Marcus:family"], "the bonds are there")
	d.modules.erase("bonds")
	var c := _bare()
	check(SaveGame.apply(c.sim, d), "a save from before bonds loads")
	eq(_names(c.sim.bonds.of(_person(c.sim, "Walt"))), ["Marcus:mentor"], "with the roster's")
	g.world.free()
	b.world.free()
	c.world.free()
