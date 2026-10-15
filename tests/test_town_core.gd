extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const TownWorld := preload("res://scripts/town/town_world.gd")
const TownRun := preload("res://scripts/town/town_run.gd")
const TownRoofs := preload("res://scripts/town/town_roofs.gd")
const Pathfinder := preload("res://scripts/sim/pathfinder.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const PrisonArms := preload("res://scripts/prison/prison_arms.gd")

var _town: Dictionary = {}


func _make() -> Dictionary:
	if _town.is_empty():
		_town = TownGen.make(1)
	return _town


## How many of the town's dead stand in the rooms of the start house.
func _start_dead(t: Dictionary) -> int:
	var n := 0
	for r in t.dead:
		if int(r.house) == int(t.start.house) and int(r.room) >= 0:
			n += 1
	return n


func test_the_same_seed_makes_the_same_town_and_its_data_is_whole() -> void:
	var t := _make()
	var again := TownGen.make(1)
	eq(TownGen.digest(again), TownGen.digest(t), "the same seed, the same town")
	check(TownGen.digest(TownGen.make(2)) != TownGen.digest(t), "another seed, another town")
	# (a town has about 85 houses since the fields of fire were cleared round the candidates (CLEAR3: 74 to 100, none under 60: tools/town_probe.gd MIN_HOUSES))
	check(t.houses.size() >= 60 and t.houses.size() <= 250, "60 to 250 houses: %d" % t.houses.size())
	check(t.dead.size() >= 850 and t.dead.size() <= 1050, "850 to 1050 dead (700 and the street's 60 percent more, DEAD1): %d" % t.dead.size())
	var start_dead := _start_dead(t)
	check(start_dead >= 3 and start_dead <= 5, "three to five dead to clear in the (roomy) start house: %d" % start_dead)
	eq(t.rescue.size(), 12, "twelve rescue houses")
	# (a guard of two to four is what the generator tries for; a tiny cottage or shed of the town's varied buildings may have room for one: it is a guard still)
	var thin := 0
	for r in t.rescue:
		var guards: int = t.houses[int(r.house)].dead.size()
		check(guards >= 1, "a guard in rescue house %d" % int(r.house))
		if guards < 2:
			thin += 1
	check(thin <= 2, "a guard of one only in a tiny house or two: %d" % thin)
	for r in t.rescue:
		eq(TownGen.house_at(t, r.pos.x, r.pos.y), int(r.house), "the survivor is in the house")
		check(TownGen.room_at(t, r.pos.x, r.pos.y) >= 0, "and in a room")
	for h in t.houses:
		check(h.rooms.size() >= 2, "house %d has rooms" % int(h.id))
		var exterior := 0
		for d in h.doors:
			if bool(d.exterior):
				exterior += 1
			for tile in d.tiles:
				eq(int(t.data.solidZ[tile.y * 192 + tile.x]), 0, "a doorway is open")
		check(exterior >= 1, "house %d has a door to the street" % int(h.id))
	for r in t.dead:
		if int(r.room) >= 0:
			eq(TownGen.room_at(t, r.pos.x, r.pos.y), int(r.room), "a dead one's room is the room it stands in")


func test_the_doors_the_containers_and_the_survivors_can_be_walked_to_from_the_start() -> void:
	var t := _make()
	var path := Pathfinder.new(192, 192, PackedByteArray(t.data.solidP))
	var solid := PackedByteArray(t.data.solidP)
	var start: Vector2 = t.start.pos
	var lost := 0
	for h in t.houses:
		if path.find(solid, start.x, start.y, float(h.door.x) + 0.5, float(h.door.y) + 0.5).is_empty():
			lost += 1
	eq(lost, 0, "every front door has a way from the start")
	var unreachable := 0
	for c in t.containers:
		if path.find(solid, start.x, start.y, c.pos.x, c.pos.y).is_empty():
			unreachable += 1
	eq(unreachable, 0, "every container can be stood at")
	for r in t.rescue:
		check(not path.find(solid, start.x, start.y, r.pos.x, r.pos.y).is_empty(), "a way to the survivor of house %d" % int(r.house))


func test_dormant_dead_wake_near_the_avatar_sleep_far_from_it_and_a_house_can_be_cleared() -> void:
	var t := _make()
	var world = TownWorld.new()
	world.build(t.data)
	var run = TownRun.new(t, world, FxNull.new(), 30, true, true)
	var field = run.field
	var sim = run.sim
	# (a run begins at the town's entry since the arrival; this is about the dead of the start house, so she is put among them: its rooms are far apart, and only those within ten tiles wake)
	Helpers.put_among_the_dead_of_the_start_house(sim, t)
	eq(field.counts().dormant, t.dead.size(), "every one dormant at the start")
	eq(field.counts().active, 0, "and none awake")
	for i in 40:
		run.update(1.0 / 30.0)
	var c: Dictionary = field.counts()
	check(c.active >= 3 and c.active <= 30, "those near wake, never over the cap: %d" % c.active)
	var tracked := 0
	for z in sim.zombies:
		if field.rec_of.has(z):
			tracked += 1
	eq(tracked, int(c.active), "each one awake is a Sim.Zombie the field knows")
	# the dead of the start house, shot dead: the house is cleared
	var house := int(t.start.house)
	var in_house := _start_dead(t)
	check(int(field.dead_in_house(house).left) == in_house, "%d left in the start house" % in_house)
	field.wake_house(house)    # (the roomy house is wider than the wake radius: a shout wakes the rest of it, as a shot does)
	for z in sim.zombies.duplicate():
		if TownGen.house_at(t, z.x, z.y) == house:
			sim._hurt_zombie(z, 1000.0, 0.0, run.avatar_p)
	run.update(1.0 / 30.0)
	for i in 10:
		run.update(1.0 / 30.0)
	check(field.house_cleared(house), "no dead left in the start house once they are shot")
	eq(sim.kills, in_house, "and they were counted")
	# the avatar goes far away: the awake that are not after anybody go back to sleep, the killed ones stay killed
	# (the start is calm now: only those of the start house are awake, and they are killed. A far house is woken as a shout would, so that some are left behind)
	check(field.wake_house(int(t.rescue[0].house)) > 0, "a house far from the start is woken")
	run.avatar_p.x = 170.0
	run.avatar_p.y = 170.0
	for z in sim.zombies:
		if z.state == "chase":
			z.state = "wander"
	for i in 20:
		run.update(1.0 / 30.0)
	check(field.counts().killed == in_house, "the killed stay killed")
	check(field.slept_total > 0, "those left behind went to sleep")
	# the save: the same records come back
	var saved: Dictionary = field.save()
	var before: Dictionary = field.counts()
	field.sleep_all()
	field.load_state(JSON.parse_string(JSON.stringify(saved)))
	eq(field.counts().killed, before.killed, "the killed come back killed")
	world.free()


func test_the_roof_of_the_house_the_avatar_is_in_opens_and_the_others_stay_shut() -> void:
	var t := _make()
	var roofs = TownRoofs.new()
	roofs.setup(t, t.data, "house")
	roofs.update(5, 1.0)
	eq(roofs.shown, t.houses.size() - 1, "one roof open")
	check(not roofs._nodes[5].visible, "that roof is not drawn")
	check(roofs._nodes[6].visible, "the next one is")
	roofs.update(-1, 1.0)
	eq(roofs.shown, t.houses.size(), "out again, all shut")
	roofs.free()


func test_the_prison_knife_takes_two_or_three_stabs_half_a_second_apart_and_no_ammo() -> void:
	var t := _make()
	var world = TownWorld.new()
	world.build(t.data)
	var run = TownRun.new(t, world, FxNull.new(), 30, true, true)
	var sim = run.sim
	var rules = sim.avatar.melee_rules
	PrisonArms.apply_knife(rules)
	near(float(rules.cfg.cycle_s), 0.5, 0.0001, "a stab takes half a second")
	check(float(rules.cfg.noise_hit) < 6.0, "and is quiet beside a shot")
	var me = run.avatar_p
	me.mag = 0
	sim.stock.ammo = 0.0
	for hp in [4.0, 6.0]:
		var z = sim.spawn(me.x + 1.0, me.y, "wander", "walker")
		z.hp = hp
		z.limp = false
		var stabs := 0
		for k in 5:
			if z.state == "dying" or z.state == "dead":
				break
			sim.avatar.set_input(Vector2.ZERO, Vector2(me.x + 5.0, me.y), false)
			sim.avatar.melee()
			stabs += 1
			for i in 15:
				sim.update(1.0 / 30.0)
			z.x = me.x + 1.0
			z.y = me.y
		check(z.state == "dying" or z.state == "dead" or z.hp <= 0.0, "a walker of %d hp is dead" % int(hp))
		check(stabs >= 2 and stabs <= 3, "in 2 or 3 stabs (%d)" % stabs)
	world.free()
