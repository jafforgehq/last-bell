extends "res://tests/case.gd"
## Traits (scripts/sim/traits.gd, assets/data/traits.json): ten small quirks, two to a
## person (map.json), each changing a number the rules use. Every test here compares a
## person with the trait and the same person without it, in the same state.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Medical := preload("res://scripts/sim/medical.gd")
const Workshop := preload("res://scripts/sim/workshop.gd")
const Morale := preload("res://scripts/sim/morale.gd")
const Skills := preload("res://scripts/sim/skills.gd")

## The keys the rules ask for (see traits.gd), and the two that are added, not multiplied.
const KEYS := ["aim", "reload", "repair", "craft", "bandage", "wound", "dead_morale", "morale_recover", "grief", "xp", "cure", "bond"]
const ADDED := ["cure", "bond"]
## Who has which, from map.json.
const ROSTER := {
	"ruth": ["steady", "loyal"],
	"dez": ["tinkerer", "tough"],
	"ana": ["triage", "optimist"],
	"marcus": ["nervous", "quick_learner"],
	"walt": ["steady_hands", "sharp_eyed"],
	"hector": ["tough", "steady"],
}


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


func _ids(list: Array) -> Array:
	var out: Array = []
	for t in list:
		out.append(t.id)
	return out


## `n` of the dead clawing at the wall sections `segs`, each in a real place at the wall.
func _clawing(sim, segs: Array, n: int) -> void:
	var placed := 0
	for seg in sim.segments:
		if not segs.has(seg.id):
			continue
		for sl in seg.slots:
			if placed >= n:
				return
			if sl.who != null:
				continue
			var z = sim.spawn(sl.x, sl.y, "attack")
			z.slot = sl
			sl.who = z
			z.facing = sl.face
			placed += 1


## What the dead at the wall cost this person's morale, as a positive number.
func _dead_cost(sim, p) -> float:
	for line in sim.morale.explain(p):
		if String(line.label).begins_with("The dead at the wall"):
			return absf(float(line.value))
	return 0.0


# ------------------------------------------------------------------- the data --

func test_there_are_ten_traits_with_a_name_a_blurb_and_numbers() -> void:
	var g := _quiet()
	var all: Array = g.sim.traits.all()
	eq(all.size(), 10, "ten traits")
	var seen := {}
	var used := {}
	for t in all:
		check(not seen.has(t.id), "%s is listed once" % t.id)
		seen[t.id] = true
		check(String(t.name).length() >= 4, "%s has a name" % t.id)
		check(String(t.blurb).length() >= 30, "%s says what it does" % t.id)
		check(not t.effects.is_empty(), "%s has an effect" % t.id)
		for k in t.effects:
			check(KEYS.has(k), "%s: %s is a key the rules know" % [t.id, k])
			check(typeof(t.effects[k]) == TYPE_FLOAT or typeof(t.effects[k]) == TYPE_INT, "%s: %s is a number" % [t.id, k])
			used[k] = true
	for k in KEYS:
		check(used.has(k), "some trait uses %s" % k)
	g.world.free()


func test_everyone_has_two_traits_as_the_roster_says() -> void:
	var g := _quiet()
	var sim = g.sim
	for p in sim.people:
		var got: Array = sim.traits.of(p)
		eq(got.size(), 2, "%s has two traits" % p.first)
		eq(_ids(got), ROSTER[p.id], "%s has %s" % [p.first, str(ROSTER[p.id])])
		for t in got:
			check(t.has("id") and t.has("name") and t.has("blurb"), "a trait carries its id, name and blurb")
			check(String(t.blurb) != "", "and the blurb is words")
		eq(p.def.get("traits"), ROSTER[p.id], "map.json says the same")
	g.world.free()


func test_a_person_with_none_has_no_effects() -> void:
	var g := _quiet()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.traits.give(dez, [])
	eq(sim.traits.of(dez), [], "no traits")
	for k in KEYS:
		eq(sim.traits.mult(dez, k), 1.0, "%s: nothing multiplies" % k)
		eq(sim.traits.add(dez, k), 0.0, "%s: nothing adds" % k)
	eq(sim.traits.of(_person(sim, "Ruth")).size(), 2, "and the others keep theirs")
	g.world.free()


func test_effects_multiply_and_add_up() -> void:
	var g := _quiet()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.traits.give(dez, ["tinkerer"])
	var repair := Helpers.trait_effect("tinkerer", "repair")
	var craft := Helpers.trait_effect("tinkerer", "craft")
	near(sim.traits.mult(dez, "repair"), repair, 1e-9, "Tinkerer: repair %s" % repair)
	near(sim.traits.mult(dez, "craft"), craft, 1e-9, "Tinkerer: craft %s" % craft)
	eq(sim.traits.mult(dez, "aim"), 1.0, "and nothing else")
	sim.traits.give(dez, ["steady", "nervous"])
	var calm := Helpers.trait_effect("steady", "dead_morale")
	var jumpy := Helpers.trait_effect("nervous", "dead_morale")
	near(sim.traits.mult(dez, "dead_morale"), calm * jumpy, 1e-9, "two traits on one key multiply: %s x %s" % [calm, jumpy])
	sim.traits.give(dez, ["triage", "loyal"])
	var cure := Helpers.trait_effect("triage", "cure")
	var bond := Helpers.trait_effect("loyal", "bond")
	near(sim.traits.add(dez, "cure"), cure, 1e-9, "Triage adds %s to the cure" % cure)
	near(sim.traits.add(dez, "bond"), bond, 1e-9, "Loyal adds %s to the bond" % bond)
	sim.traits.give(dez, ["tough", "tough", "nonsense"])
	eq(_ids(sim.traits.of(dez)), ["tough"], "a trait is had once, and one that does not exist is not had")
	var wound := Helpers.trait_effect("tough", "wound")
	near(sim.traits.mult(dez, "wound"), wound, 1e-9, "Tough: wound %s" % wound)
	eq(sim.traits.mult(null, "aim"), 1.0, "nobody has no effect")
	g.world.free()


func test_names_for_lists_the_traits_that_carry_a_key() -> void:
	var g := _quiet()
	var sim = g.sim
	eq(sim.traits.names_for(_person(sim, "Marcus"), "dead_morale"), ["Nervous"], "Marcus: Nervous shakes him")
	eq(sim.traits.names_for(_person(sim, "Marcus"), "aim"), ["Nervous"], "and costs him aim in a crowd")
	eq(sim.traits.names_for(_person(sim, "Hector"), "dead_morale"), ["Steady"], "Hector: Steady")
	eq(sim.traits.names_for(_person(sim, "Hector"), "xp"), [], "nothing else")
	eq(sim.traits.names_for(null, "xp"), [], "nobody has none")
	g.world.free()


func test_giving_traits_does_not_touch_the_roster() -> void:
	var g := _quiet()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.traits.give(dez, [])
	eq(dez.def.get("traits"), ROSTER.dez, "map.json's list is as it was")
	var h := _quiet()
	eq(_ids(h.sim.traits.of(_person(h.sim, "Dez"))), ROSTER.dez, "and the next game starts from it")
	g.world.free()
	h.world.free()


# ------------------------------------------------------- each trait, its number --

func test_steady_and_nervous_scale_what_the_dead_at_the_wall_do_to_morale() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	ruth.x = 39.0
	ruth.y = 20.0
	_clawing(sim, [1, 2, 3], 10)
	sim.traits.give(ruth, [])
	# (the reasons morale lists are rounded to a tenth of a point, hence the tolerances)
	var plain := _dead_cost(sim, ruth)
	near(plain, minf(-Morale.DEAD_MAX, -Morale.DEAD_EACH * 10.0), 0.06, "ten of the dead cost %s each" % -Morale.DEAD_EACH)
	sim.traits.give(ruth, ["steady"])
	var calm := Helpers.trait_effect("steady", "dead_morale")
	near(_dead_cost(sim, ruth), plain * calm, 0.1, "Steady: %s of it" % calm)
	var tagged := false
	for line in sim.morale.explain(ruth):
		tagged = tagged or String(line.label) == "The dead at the wall (Steady)"
	check(tagged, "and the line says which trait: %s" % str(sim.morale.explain(ruth)))
	sim.traits.give(ruth, ["nervous"])
	var jumpy := Helpers.trait_effect("nervous", "dead_morale")
	near(_dead_cost(sim, ruth), plain * jumpy, 0.1, "Nervous: %s times it" % jumpy)
	g.world.free()


func test_nervous_aims_worse_among_a_crowd_of_the_dead() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	var crowd: Array = []
	for i in 6:
		crowd.append(sim.spawn(marcus.x + 5.0, marcus.y + float(i) * 0.4, "wander"))
	near(sim.traits.mult(marcus, "aim"), 0.9, 1e-9, "six of the dead within ten tiles: a tenth worse")
	near(sim.aim_factor(marcus), 0.9, 1e-9, "and the rules' aim says so")
	crowd[0].state = "dying"
	eq(sim.traits.mult(marcus, "aim"), 1.0, "one of them going down: five are not enough")
	crowd[0].state = "wander"
	near(sim.traits.mult(marcus, "aim"), 0.9, 1e-9, "back to six")
	crowd[1].x = marcus.x + 40.0
	eq(sim.traits.mult(marcus, "aim"), 1.0, "one of them far away: five within ten")
	crowd[1].x = marcus.x + 9.5
	crowd[1].y = marcus.y
	near(sim.traits.mult(marcus, "aim"), 0.9, 1e-9, "nine and a half tiles is within ten")
	sim.traits.give(marcus, [])
	eq(sim.aim_factor(marcus), 1.0, "and without the trait it never changes")
	g.world.free()


func test_tinkerer_mends_walls_faster() -> void:
	var rates: Array = []
	for with_trait in [false, true]:
		var g := _quiet(9.0)
		var sim = g.sim
		sim.stock.scrap = 200.0
		var dez = _person(sim, "Dez")
		sim.traits.give(dez, ["tinkerer"] if with_trait else [])
		var seg = sim.segments[4]
		sim._damage_segment(seg, 150.0)
		var hp0: float = seg.hp
		dez.x = seg.center.x
		dez.y = seg.center.y
		sim.order_repair(dez, seg)
		Helpers.run(sim, 3.0)
		rates.append(seg.hp - hp0)
		g.world.free()
	check(rates[0] > 30.0, "Dez mends a good deal in three seconds: %.1f" % rates[0])
	var faster := Helpers.trait_effect("tinkerer", "repair")
	near(rates[1] / rates[0], faster, 0.01, "a Tinkerer mends %d percent faster: %.1f against %.1f" % [roundi((faster - 1.0) * 100.0), rates[1], rates[0]])


func test_tinkerer_makes_ammo_faster() -> void:
	var g := _quiet()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.traits.give(dez, [])
	var plain: float = sim.workshop.scrap_per_hour(dez)
	sim.traits.give(dez, ["tinkerer"])
	var faster := Helpers.trait_effect("tinkerer", "craft")
	var more := roundi((faster - 1.0) * 100.0)
	near(sim.workshop.scrap_per_hour(dez), plain * faster, 1e-9, "%d%% more scrap an hour" % more)
	# and really: an hour at the bench
	var used: Array = []
	for with_trait in [false, true]:
		var h := _quiet(9.0)
		var s2 = h.sim
		s2.stock.scrap = 60.0
		var d2 = _person(s2, "Dez")
		s2.traits.give(d2, ["tinkerer"] if with_trait else [])
		var b: Vector2 = s2.workshop.bench()
		d2.x = b.x
		d2.y = b.y
		s2.workshop.order_craft(d2)
		Helpers.run(s2, 20.0)
		used.append(60.0 - float(s2.stock.scrap))
		h.world.free()
	near(used[1] / used[0], faster, 0.03, "an hour at the bench uses %d percent more scrap: %.2f against %.2f" % [more, used[1], used[0]])
	g.world.free()


func test_triage_bandages_faster() -> void:
	var worked: Array = []
	for with_trait in [false, true]:
		var g := _quiet(9.0)
		var sim = g.sim
		sim.stock.meds = 10.0
		var ana = _person(sim, "Ana")
		var hector = _person(sim, "Hector")
		sim.traits.give(ana, ["triage"] if with_trait else [])
		hector.x = ana.x + 0.3
		hector.y = ana.y
		sim.medical.add_wound(hector, "scratch")
		sim.medical.jobs.append({"healer": ana, "patient": hector, "kind": "bandage", "work": 0.0, "stand": null, "anchor": Vector2.ZERO})
		sim.medical._update_jobs(1.0)
		check(not sim.medical.jobs.is_empty(), "the job is still going")
		worked.append(float(sim.medical.jobs[0].work))
		g.world.free()
	near(worked[0], 3.0, 0.001, "a second of work is three game minutes")
	var faster := Helpers.trait_effect("triage", "bandage")
	near(worked[1] / worked[0], faster, 0.001, "a Triage nurse gets through a bandage %d%% faster" % roundi((faster - 1.0) * 100.0))


func test_triage_makes_a_cure_more_likely() -> void:
	var g := _quiet()
	var sim = g.sim
	var walt = _person(sim, "Walt")
	sim.traits.give(walt, [])
	var plain: float = sim.medical.cure_chance(walt)
	near(plain, Medical.CURE_BASE + 0.2, 1e-9, "Walt, Medicine 2")
	sim.traits.give(walt, ["triage"])
	var cure := Helpers.trait_effect("triage", "cure")
	var points := roundi(cure * 100.0)
	near(sim.medical.cure_chance(walt), plain + cure, 1e-9, "Triage adds %d points" % points)
	var ana = _person(sim, "Ana")
	sim.traits.give(ana, [])
	near(sim.medical.cure_chance(ana), Medical.CURE_MAX, 1e-9, "Ana's Medicine alone is capped at %d%%" % roundi(Medical.CURE_MAX * 100.0))
	sim.traits.give(ana, ["triage"])
	near(sim.medical.cure_chance(ana), minf(1.0, Medical.CURE_MAX + cure), 1e-9, "and the trait is on top of the cap (a chance is at most 1)")
	g.world.free()


## How many of `shots` shots at a walker that cannot die hit, for `p` with `traits`.
func _hits(p_id: String, traits: Array, shots: int, seed_value: int) -> int:
	var g := _quiet(22.0, seed_value)
	var sim = g.sim
	sim.stock.ammo = 100000.0
	var p = _person(sim, p_id)
	sim.traits.give(p, traits)
	var z = sim.spawn(p.x + 4.0, p.y, "wander")
	z.hp = 1.0e9
	var start_hp: float = z.hp
	var dmg: float = float(p.gun.dmg)
	for i in shots:
		p.mag = int(p.gun.mag)
		p.cooldown = 0.0
		sim._fire(p, z, 0.0)
	var hits := roundi((start_hp - z.hp) / dmg)
	g.world.free()
	return hits


func test_sharp_eyed_hits_more_often() -> void:
	var g := _quiet()
	var walt = _person(g.sim, "Walt")
	g.sim.traits.give(walt, [])
	eq(g.sim.aim_factor(walt), 1.0, "no trait, no change")
	g.sim.traits.give(walt, ["sharp_eyed"])
	var better := Helpers.trait_effect("sharp_eyed", "aim")
	var percent := roundi((better - 1.0) * 100.0)
	near(g.sim.aim_factor(walt), better, 1e-9, "Sharp-eyed: %d%% better aim" % percent)
	g.world.free()
	# really: Ana's pistol hits about half the time, so the difference shows
	var shots := 6000
	var plain := _hits("Ana", [], shots, 3)
	var sharp := _hits("Ana", ["sharp_eyed"], shots, 3)
	var gain := float(sharp) / float(plain)
	check(absf(gain - better) < 0.03, "%d percent more of the shots hit: %d against %d (x%.3f, wanted x%.3f)" % [percent, sharp, plain, gain, better])


func test_steady_hands_reload_faster() -> void:
	var times: Array = []
	for traits in [[], ["steady_hands"]]:
		var g := _quiet(22.0)
		var sim = g.sim
		sim.stock.ammo = 1000.0
		var walt = _person(sim, "Walt")
		sim.traits.give(walt, traits)
		var z = sim.spawn(walt.x + 4.0, walt.y, "wander")
		z.hp = 1.0e9
		walt.mag = 1
		walt.cooldown = 0.0
		sim._fire(walt, z, 0.0)
		times.append(walt.reloading)
		g.world.free()
	near(times[0], 2.4, 1e-9, "an M1 takes 2.4 seconds to reload")
	var quicker := Helpers.trait_effect("steady_hands", "reload")
	near(times[1], times[0] * quicker, 1e-9, "Steady hands: %s of that" % quicker)


func _scratches(id: String, traits: Array, claws: int) -> int:
	var g := _quiet(22.0, 6)
	var sim = g.sim
	var gate = sim.segments[2]
	var slot = gate.slots[3]
	var z = sim.spawn(slot.x, slot.y, "attack")
	var p = _person(sim, id)
	sim.traits.give(p, traits)
	p.x = z.x
	p.y = gate.center.y + 1.6
	p.path = []
	for i in claws:
		sim.medical.on_wall_claw(z, gate)
	var wounds: int = p.wounds
	g.world.free()
	return wounds


func test_tough_is_scratched_less_by_claws() -> void:
	var plain := _scratches("Dez", [], 4000)
	var tough := _scratches("Dez", ["tough"], 4000)
	check(plain > 300, "without it about 11 percent of claws scratch: %d of 4000" % plain)
	var factor := Helpers.trait_effect("tough", "wound")
	near(float(tough) / float(plain), factor, 0.08, "Tough: %d percent fewer wounds: %d against %d" % [roundi((1.0 - factor) * 100.0), tough, plain])
	check(tough < plain, "and fewer, not just about as many")


func test_tough_is_bitten_less_often_too() -> void:
	var counts: Array = []
	for traits in [[], ["tough"]]:
		var g := _quiet(22.0, 8)
		var sim = g.sim
		var z = sim.spawn(30.0, 30.0, "wander")
		var hector = _person(sim, "Hector")
		sim.traits.give(hector, traits)
		var wounds := 0
		for i in 2000:
			hector.wounds = 0
			hector.bleeding = 0.0
			sim.medical.after_bite(z, hector)
			wounds += hector.wounds
		counts.append(wounds)
		g.world.free()
	eq(counts[0], 2000, "a bite always wounds a person with no trait")
	var factor := Helpers.trait_effect("tough", "wound")
	near(float(counts[1]) / 2000.0, factor, 0.04, "Tough: %d bites in 100 wound: %d of 2000" % [roundi(factor * 100.0), counts[1]])


func test_optimist_recovers_faster() -> void:
	var gains: Array = []
	for traits in [[], ["optimist"]]:
		var g := _quiet(9.0)
		var sim = g.sim
		var ana = _person(sim, "Ana")
		sim.traits.give(ana, traits)
		sim.morale.shock(ana, -40.0, "A bad moment")
		var before: float = sim.morale.value(ana)
		Helpers.run(sim, 20.0)   # one game hour
		gains.append(sim.morale.value(ana) - before)
		g.world.free()
	near(gains[0], Morale.DRIFT_PER_HOUR, 0.2, "most people recover %s points an hour: %.2f" % [Morale.DRIFT_PER_HOUR, gains[0]])
	var faster := Helpers.trait_effect("optimist", "morale_recover")
	near(gains[1] / gains[0], faster, 0.05, "an Optimist recovers %s times as fast: %.2f" % [faster, gains[1]])


func test_loyal_takes_a_friends_death_harder() -> void:
	var drops: Array = []
	for traits in [[], ["loyal"]]:
		var g := _quiet(9.0)
		var sim = g.sim
		var ruth = _person(sim, "Ruth")
		var marcus = _person(sim, "Marcus")
		sim.traits.give(ruth, traits)
		var before: float = sim.morale.value(ruth)
		sim.medical.kill(marcus, "bled out")
		drops.append(before - sim.morale.value(ruth))
		g.world.free()
	near(drops[0], -Morale.FRIEND_LOST, 0.01, "a friend's death is %s points" % -Morale.FRIEND_LOST)
	var harder := Helpers.trait_effect("loyal", "grief")
	near(drops[1], -Morale.FRIEND_LOST * harder, 0.01, "to a Loyal person %s times as much" % harder)


func test_loyal_aims_better_beside_a_friend() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var marcus = _person(sim, "Marcus")
	marcus.x = ruth.x + 3.0
	marcus.y = ruth.y
	sim.traits.give(ruth, [])
	near(sim.aim_factor(ruth), 1.08, 1e-9, "beside a friend: 8% better")
	sim.traits.give(ruth, ["loyal"])
	var bond := Helpers.trait_effect("loyal", "bond")
	near(sim.aim_factor(ruth), 1.08 + bond, 1e-9, "Loyal: %d more points" % roundi(bond * 100.0))
	marcus.x = ruth.x + 30.0
	near(sim.aim_factor(ruth), 1.0, 1e-9, "and nothing when the friend is far")
	g.world.free()


func test_a_quick_learner_learns_faster_by_the_traits_factor() -> void:
	var g := _quiet()
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	var xp := Helpers.trait_effect("quick_learner", "xp")
	near(sim.traits.mult(marcus, "xp"), xp, 1e-9, "Quick learner: xp %s" % xp)
	sim.traits.give(marcus, [])
	eq(sim.traits.mult(marcus, "xp"), 1.0, "without it: 1")
	# the kills it takes for a point: anyone else's (the rules' table) and a quick learner's
	var per := ceili(float(Skills.KINDS.kills.per) - Skills.EPS)
	var quick := ceili(float(Skills.KINDS.kills.per) / xp - Skills.EPS)
	check(quick < per, "a quick learner needs fewer kills than the %d it takes anyone else" % per)
	for i in quick:
		sim.skills.credit(marcus, "kills", 1.0)
	eq(marcus.skills.Shooting, 8, "%d kills are not a point without it" % quick)
	g.world.free()


# --------------------------------------------------------------------- saves --

func test_traits_are_saved_and_an_old_save_keeps_the_roster() -> void:
	var g := _quiet()
	var sim = g.sim
	sim.traits.give(_person(sim, "Dez"), ["sharp_eyed", "optimist"])
	var d := SaveGame.to_dict(sim)
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it applies")
	eq(_ids(b.sim.traits.of(_person(b.sim, "Dez"))), ["sharp_eyed", "optimist"], "Dez has what he was given")
	eq(_ids(b.sim.traits.of(_person(b.sim, "Ruth"))), ROSTER.ruth, "the others as before")
	# a save from before traits
	d.modules.erase("traits")
	var c := _bare()
	check(SaveGame.apply(c.sim, d), "an old save loads")
	eq(_ids(c.sim.traits.of(_person(c.sim, "Dez"))), ROSTER.dez, "with the roster's traits")
	# damaged module data is ignored
	d.modules["traits"] = {"assigned": {"dez": ["nonsense"], "nobody": ["tough"], "ruth": 5}}
	var e := _bare()
	check(SaveGame.apply(e.sim, d), "damaged trait data does not refuse the save")
	eq(_ids(e.sim.traits.of(_person(e.sim, "Ruth"))), ROSTER.ruth, "the roster fills what could not be read")
	g.world.free()
	b.world.free()
	c.world.free()
	e.world.free()
