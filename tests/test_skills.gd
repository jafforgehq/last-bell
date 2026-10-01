extends "res://tests/case.gd"
## Skills grow with use (scripts/sim/skills.gd): each person has their own copy of the
## roster's skills (`Person.skills`) and counters (`Person.stats`). Shooting +1 per 60
## kills, Melee +1 per 40 melee kills, Medicine +1 per 6 treatments, Building +1 per 400
## HP mended and +1 per 60 scrap made into ammo; at most 3 points over the start and never
## past 10; Leading does not grow; a quick learner is 1.5 times faster.

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


## A quiet day: no dead about, no nights, 09:00.
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


func _credit(sim, p, kind: String, times: int, amount: float = 1.0) -> void:
	for i in times:
		sim.skills.credit(p, kind, amount)


## Whether two lists of skills are the same numbers (the roster's are floats from JSON, a
## person's own are whole numbers).
func _same_skills(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or float(a[k]) != float(b[k]):
			return false
	return true


func _events_of(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if e.type == type:
			out.append(e)
	return out


# ------------------------------------------------------------ their own copy --

func test_each_person_has_their_own_copy_of_the_roster_skills() -> void:
	var g := _quiet()
	var sim = g.sim
	for p in sim.people:
		check(_same_skills(p.skills, p.def.skills), "%s starts with the roster's skills" % p.first)
		check(not is_same(p.skills, p.def.skills), "%s's skills are a copy, not the shared roster" % p.first)
	var marcus = _person(sim, "Marcus")
	marcus.skills.Shooting = 9
	eq(marcus.def.skills.Shooting, 8, "growing one person's skill leaves the roster alone")
	var h := _quiet()
	eq(_person(h.sim, "Marcus").skills.Shooting, 8, "and the next game starts from the roster")
	g.world.free()
	h.world.free()


func test_the_counters_start_at_nothing() -> void:
	var g := _quiet()
	for p in g.sim.people:
		eq(p.stats.keys().size(), 6, "%s has six counters" % p.first)
		for k in ["kills", "kills_night", "mended", "treated", "crafted", "shots"]:
			check(p.stats.has(k) and float(p.stats[k]) == 0.0, "%s: %s is zero" % [p.first, k])
	g.world.free()


func test_the_rules_read_the_persons_own_skills() -> void:
	var g := _quiet()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var before: float = sim.workshop.scrap_per_hour(dez)
	dez.skills.Building = 0
	check(sim.workshop.scrap_per_hour(dez) < before, "the workshop reads Building from the person")
	var ana = _person(sim, "Ana")
	var chance: float = sim.medical.cure_chance(ana)
	ana.skills.Medicine = 1
	check(sim.medical.cure_chance(ana) < chance, "the cure chance reads Medicine from the person")
	var ruth = _person(sim, "Ruth")
	var loot: float = sim.scavenge.loot_scale("houses", [ruth])
	ruth.skills.Leading = 1
	check(sim.scavenge.loot_scale("houses", [ruth]) < loot, "a trip's loot reads Leading from the person")
	g.world.free()


# ------------------------------------------------------------- the thresholds --

func test_sixty_kills_make_a_better_shot() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	_credit(sim, ruth, "kills", 59)
	eq(ruth.skills.Shooting, 5, "59 kills are not enough")
	eq(_events_of(sim, "skill_up").size(), 0, "and nothing is announced")
	sim.skills.credit(ruth, "kills", 1.0)
	eq(ruth.skills.Shooting, 6, "the 60th makes Shooting 6")
	var ups := _events_of(sim, "skill_up")
	eq(ups.size(), 1, "one skill_up event")
	if ups.size() == 1:
		eq(ups[0].who, "ruth", "for Ruth")
		eq(ups[0].skill, "Shooting", "in Shooting")
		eq(ups[0].value, 6, "now 6")
	eq(ruth.def.skills.Shooting, 5, "the roster is not touched")
	g.world.free()


func test_forty_melee_kills_make_a_better_fighter() -> void:
	var g := _quiet()
	var sim = g.sim
	var hector = _person(sim, "Hector")
	_credit(sim, hector, "melee", 39)
	eq(hector.skills.Melee, 8, "39 melee kills are not enough")
	sim.skills.credit(hector, "melee", 1.0)
	eq(hector.skills.Melee, 9, "the 40th makes Melee 9")
	eq(hector.skills.Shooting, 2, "and Shooting is not touched")
	g.world.free()


func test_six_treatments_make_a_better_healer() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	_credit(sim, ruth, "treated", 5)
	eq(ruth.skills.Medicine, 2, "five treatments are not enough")
	sim.skills.credit(ruth, "treated", 1.0)
	eq(ruth.skills.Medicine, 3, "the sixth makes Medicine 3")
	g.world.free()


func test_building_grows_from_mending_and_from_the_bench() -> void:
	var g := _quiet()
	var sim = g.sim
	var hector = _person(sim, "Hector")
	sim.skills.credit(hector, "mended", 399.0)
	eq(hector.skills.Building, 6, "399 HP mended are not enough")
	sim.skills.credit(hector, "mended", 1.0)
	eq(hector.skills.Building, 7, "400 HP mended make Building 7")
	var walt = _person(sim, "Walt")
	sim.skills.credit(walt, "crafted", 59.0)
	eq(walt.skills.Building, 3, "59 scrap made into ammo are not enough")
	sim.skills.credit(walt, "crafted", 1.0)
	eq(walt.skills.Building, 4, "60 scrap make Building 4")
	var ruth = _person(sim, "Ruth")
	sim.skills.credit(ruth, "mended", 200.0)
	sim.skills.credit(ruth, "crafted", 30.0)
	eq(ruth.skills.Building, 4, "half of each is a whole point: the two add up")
	g.world.free()


func test_leading_never_grows() -> void:
	var g := _quiet()
	var sim = g.sim
	for p in sim.people:
		var lead: int = int(p.skills.Leading)
		for kind in ["kills", "melee", "treated", "mended", "crafted"]:
			_credit(sim, p, kind, 3, 1000.0)
		eq(p.skills.Leading, lead, "%s's Leading is where it was" % p.first)
	g.world.free()


func test_at_most_three_points_over_the_start_and_never_past_ten() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	_credit(sim, ruth, "kills", 1000)
	eq(ruth.skills.Shooting, 8, "Ruth started on 5 and stops at 8")
	var marcus = _person(sim, "Marcus")
	_credit(sim, marcus, "kills", 1000)
	eq(marcus.skills.Shooting, 10, "Marcus started on 8 and stops at 10, not 11")
	var ana = _person(sim, "Ana")
	_credit(sim, ana, "treated", 100)
	eq(ana.skills.Medicine, 10, "Ana is on 10 already")
	var dez = _person(sim, "Dez")
	sim.skills.credit(dez, "mended", 100000.0)
	eq(dez.skills.Building, 10, "Dez started on 9 and stops at 10")
	check(sim.skills.gained(dez) == {"Building": 1}, "he gained one point: %s" % str(sim.skills.gained(dez)))
	g.world.free()


func test_a_quick_learner_is_one_and_a_half_times_faster() -> void:
	var g := _quiet()
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	check(sim.traits.mult(marcus, "xp") > 1.4, "Marcus is a quick learner")
	_credit(sim, marcus, "kills", 39)
	eq(marcus.skills.Shooting, 8, "39 kills are not enough even for him")
	sim.skills.credit(marcus, "kills", 1.0)
	eq(marcus.skills.Shooting, 9, "the 40th is (60 / 1.5)")
	g.world.free()


func test_gained_says_how_many_points_each_skill_has_gained() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	eq(sim.skills.gained(ruth), {}, "nothing gained at the start")
	_credit(sim, ruth, "kills", 120)
	_credit(sim, ruth, "treated", 6)
	var gained: Dictionary = sim.skills.gained(ruth)
	eq(gained.get("Shooting", 0), 2, "two points of Shooting")
	eq(gained.get("Medicine", 0), 1, "one of Medicine")
	eq(gained.get("Leading", 0), 0, "none of Leading")
	g.world.free()


func test_unknown_kinds_and_empty_amounts_change_nothing() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	sim.skills.credit(ruth, "dancing", 1000.0)
	sim.skills.credit(ruth, "kills", 0.0)
	sim.skills.credit(ruth, "kills", -5.0)
	sim.skills.credit(null, "kills", 1.0)
	check(_same_skills(ruth.skills, ruth.def.skills), "no change")
	eq(sim.skills.gained(ruth), {}, "and nothing gained")
	g.world.free()


func test_a_gain_is_announced_in_words() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	_credit(sim, ruth, "kills", 60)
	var a: Dictionary = sim.alerts.get("skill-ruth", {})
	check(not a.is_empty(), "an alert skill-ruth")
	eq(a.get("text"), "Ruth is a better shot now", "it says who and what")
	eq(a.get("sub"), "Shooting 6", "and the new value")
	_credit(sim, ruth, "treated", 6)
	eq(sim.alerts.get("skill-ruth", {}).get("text"), "Ruth is a better healer now", "Medicine is a healer")
	eq(sim.alerts.get("skill-ruth", {}).get("sub"), "Medicine 3", "and its value")
	_credit(sim, ruth, "mended", 400, 1.0)
	eq(sim.alerts.get("skill-ruth", {}).get("text"), "Ruth is a better builder now", "Building is a builder")
	_credit(sim, ruth, "melee", 40)
	eq(sim.alerts.get("skill-ruth", {}).get("text"), "Ruth is a better fighter now", "Melee is a fighter")
	g.world.free()


# ----------------------------------------------------------- credit in the rules --

func test_a_kill_is_credited_to_the_shooter_whose_shot_killed_it() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	var z = sim.spawn(marcus.x + 8.0, marcus.y, "wander")
	sim._hurt_zombie(z, 100.0, 0.0, marcus)
	eq(sim.kills, 1, "the run counts it")
	eq(marcus.stats.kills, 1, "Marcus made it")
	eq(marcus.stats.kills_night, 1, "tonight")
	var z2 = sim.spawn(marcus.x + 8.0, marcus.y, "wander")
	sim._hurt_zombie(z2, 1.0, 0.0, marcus)
	eq(marcus.stats.kills, 1, "a hit that does not kill is not a kill")
	sim._hurt_zombie(z2, 1000.0, 0.0, marcus)
	eq(marcus.stats.kills, 2, "the blow that kills it is")
	var ruth = _person(sim, "Ruth")
	eq(ruth.stats.kills, 0, "and nobody else is credited")
	sim._hurt_zombie(z2, 1000.0, 0.0, ruth)
	eq(ruth.stats.kills, 0, "nor for hitting the dead")
	g.world.free()


func test_a_kill_with_a_melee_weapon_is_a_melee_kill() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	var hector = _person(sim, "Hector")
	for i in 40:
		var z = sim.spawn(hector.x + 1.0, hector.y, "wander")
		sim._hurt_zombie(z, 1000.0, 0.0, hector, true)
	eq(hector.stats.kills, 40, "forty kills")
	eq(hector.skills.Melee, 9, "forty melee kills make Melee 9")
	eq(hector.skills.Shooting, 2, "and no Shooting")
	g.world.free()


func test_real_shooting_credits_the_shots_and_the_kills() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	sim.stock.ammo = 1000.0
	var marcus = _person(sim, "Marcus")
	# a walker standing at the wall in front of Marcus's tower
	var z = sim.spawn(marcus.x + 7.0, marcus.y + 1.0, "wander")
	z.speed = 0.0
	Helpers.run(sim, 20.0)
	check(marcus.stats.shots >= 1, "Marcus fired: %d shots" % marcus.stats.shots)
	var made := 0
	for p in sim.people:
		made += int(p.stats.kills)
	eq(made, sim.kills, "the kills the people made are the kills the run counted")
	check(sim.kills >= 1, "something was put down")
	g.world.free()


func test_a_bandage_a_stabilising_and_a_cure_count_as_treatments() -> void:
	var g := _quiet(9.0)
	var sim = g.sim
	sim.stock.meds = 20.0
	var ana = _person(sim, "Ana")
	var hector = _person(sim, "Hector")
	var marcus = _person(sim, "Marcus")
	var walt = _person(sim, "Walt")
	# a bandage
	hector.x = ana.x + 0.5
	hector.y = ana.y
	sim.medical.add_wound(hector, "scratch")
	Helpers.run(sim, 20.0)
	eq(hector.bleeding, 0.0, "Hector is bandaged")
	eq(ana.stats.treated, 1, "that was one treatment")
	# a stabilising
	marcus.x = ana.x - 0.5
	marcus.y = ana.y
	marcus.hp = 0.0
	sim.medical.on_downed(marcus, "bite")
	Helpers.run(sim, 20.0)
	check(marcus.stabilised, "Marcus is stabilised")
	eq(ana.stats.treated, 2, "that was another")
	# a cure
	walt.infected_at = sim.clock_min
	walt.turn_at = sim.clock_min + 20.0 * 60.0
	walt.x = ana.x + 0.5
	walt.y = ana.y
	sim.medical.gizmo("treat", {"kind": "person", "ref": walt})
	Helpers.run(sim, 30.0)
	check(walt.infected_at < 0.0 or sim.medical.treat_orders.is_empty(), "the treatment was given")
	eq(ana.stats.treated, 3, "and that a third")
	eq(hector.stats.treated, 0, "the patients are not credited")
	g.world.free()


func test_mending_credits_the_hit_points_put_back() -> void:
	var g := _quiet(9.0)
	var sim = g.sim
	sim.stock.scrap = 100.0
	var seg = sim.segments[4]
	sim._damage_segment(seg, 100.0)
	var hp0: float = seg.hp
	var dez = _person(sim, "Dez")
	dez.x = seg.center.x
	dez.y = seg.center.y
	sim.order_repair(dez, seg)
	Helpers.run(sim, 4.0)
	var mended: float = seg.hp - hp0
	check(mended > 20.0, "the wall was mended: %.1f" % mended)
	near(float(dez.stats.mended), mended, 0.01, "Dez is credited with exactly that")
	g.world.free()


func test_the_bench_credits_the_scrap_made_into_ammo() -> void:
	var g := _quiet(9.0)
	var sim = g.sim
	sim.stock.scrap = 40.0
	var dez = _person(sim, "Dez")
	var b: Vector2 = sim.workshop.bench()
	dez.x = b.x
	dez.y = b.y
	check(sim.workshop.order_craft(dez), "the order is taken")
	Helpers.run(sim, 20.0)
	var used: float = 40.0 - float(sim.stock.scrap)
	check(used > 3.0, "scrap was used: %.2f" % used)
	near(float(dez.stats.crafted), used, 0.01, "and he is credited with all of it")
	g.world.free()


func test_kills_of_the_night_are_counted_again_from_each_dusk() -> void:
	var g := _quiet(18.9)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	var z = sim.spawn(marcus.x + 8.0, marcus.y, "wander")
	sim._hurt_zombie(z, 1000.0, 0.0, marcus)
	eq(marcus.stats.kills_night, 1, "a kill before the bell")
	Helpers.run(sim, 10.0)
	check(sim.bell_rung, "the bell has rung")
	eq(marcus.stats.kills_night, 0, "the night's count starts again at the bell")
	eq(marcus.stats.kills, 1, "and the total is kept")
	var z2 = sim.spawn(marcus.x + 8.0, marcus.y, "wander")
	sim._hurt_zombie(z2, 1000.0, 0.0, marcus)
	eq(marcus.stats.kills_night, 1, "kills in the night are counted")
	eq(marcus.stats.kills, 2, "in the total too")
	g.world.free()


func test_a_new_run_puts_skills_and_counters_back() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	_credit(sim, ruth, "kills", 70)
	sim.skills.credit(ruth, "mended", 100.0)
	sim.start_run(1, 3)
	check(_same_skills(ruth.skills, ruth.def.skills), "Ruth is back on the roster's skills")
	eq(ruth.stats.kills, 0, "with no kills")
	eq(float(ruth.stats.mended), 0.0, "and nothing mended")
	eq(sim.skills.gained(ruth), {}, "and nothing gained")
	_credit(sim, ruth, "kills", 59)
	eq(ruth.skills.Shooting, 5, "and the progress starts again from nothing")
	g.world.free()


# --------------------------------------------------------------------- saves --

func test_skills_stats_and_progress_survive_a_save() -> void:
	var g := _quiet(10.0)
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	_credit(sim, ruth, "kills", 70)
	sim.skills.credit(ruth, "mended", 150.0)
	ruth.stats.shots = 33
	var d := SaveGame.to_dict(sim)
	var b := _bare()
	check(SaveGame.apply(b.sim, d), "it applies")
	var rb = _person(b.sim, "Ruth")
	eq(rb.skills.Shooting, 6, "the skill came back")
	eq(rb.stats.kills, 70, "and the counters")
	eq(rb.stats.shots, 33, "all of them")
	near(float(rb.stats.mended), 150.0, 0.0001, "even the HP")
	eq(b.sim.skills.gained(rb), {"Shooting": 1}, "and the gain")
	# 10 of 60 kills into the next point and 150 of 400 HP: the progress is kept
	_credit(b.sim, rb, "kills", 49)
	eq(rb.skills.Shooting, 6, "49 more kills are not yet the next point")
	b.sim.skills.credit(rb, "kills", 1.0)
	eq(rb.skills.Shooting, 7, "the 50th more is (the 10 over were kept)")
	# through JSON text too
	var c := _bare()
	check(SaveGame.apply(c.sim, SaveGame.from_text(SaveGame.to_text(d))), "it applies from text")
	var rc = _person(c.sim, "Ruth")
	eq(rc.skills.Shooting, 6, "from text as well")
	eq(typeof(rc.skills.Shooting), TYPE_INT, "as a whole number")
	eq(typeof(rc.stats.kills), TYPE_INT, "the counters are whole numbers too")
	g.world.free()
	b.world.free()
	c.world.free()


func test_an_old_save_without_skills_loads_with_the_roster_values() -> void:
	var g := _quiet(10.0)
	var sim = g.sim
	_credit(sim, _person(sim, "Ruth"), "kills", 70)
	var d := SaveGame.to_dict(sim)
	for pd in d.people:
		pd.erase("skills")
		pd.erase("stats")
	d.modules.erase("skills")
	var b := _bare()
	check(SaveGame.apply(b.sim, d), "a save from before this round still loads")
	for p in b.sim.people:
		check(_same_skills(p.skills, p.def.skills), "%s has the roster's skills" % p.first)
		eq(p.stats.get("kills"), 0, "and no kills")
		eq(p.stats.keys().size(), 6, "with all six counters")
	g.world.free()
	b.world.free()


func test_damaged_skills_in_a_save_are_refused() -> void:
	var g := _quiet(10.0)
	var good := SaveGame.to_dict(g.sim)
	var b := _bare()
	var before := SaveGame.to_dict(b.sim)
	for c in [["skills", 5], ["skills", "Shooting"], ["stats", [1, 2]], ["stats", "many"]]:
		var d: Dictionary = good.duplicate(true)
		d.people[0][c[0]] = c[1]
		eq(SaveGame.apply(b.sim, d), false, "refused: %s is %s" % [c[0], str(c[1])])
	var bad: Dictionary = good.duplicate(true)
	bad.people[1].skills = {"Shooting": "high"}
	eq(SaveGame.apply(b.sim, bad), false, "refused: a skill that is not a number")
	eq(SaveGame.to_dict(b.sim), before, "and the sim is as it was")
	var partial: Dictionary = good.duplicate(true)
	partial.people[2].skills = {"Shooting": 4.0}
	check(SaveGame.apply(b.sim, partial), "a list missing some skills is filled in, not refused")
	for k in ["Shooting", "Melee", "Building", "Medicine", "Leading"]:
		check(b.sim.people[2].skills.has(k), "the missing %s is back" % k)
	eq(b.sim.people[2].skills.Shooting, 4, "and the one that was there stays")
	g.world.free()
	b.world.free()


func test_the_same_orders_on_the_same_seed_grow_the_same_skills() -> void:
	var out: Array = []
	for i in 2:
		var g := Helpers.make(21, 1)
		var sim = g.sim
		sim.stock.ammo = 1000.0
		Helpers.run_to_hour(sim, 19.5)
		Helpers.run(sim, 90.0)
		var rows: Array = []
		for p in sim.people:
			rows.append([p.id, p.skills.duplicate(), p.stats.duplicate()])
		out.append(rows)
		g.world.free()
	eq(out[0], out[1], "the same game twice")
