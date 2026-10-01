extends "res://tests/case.gd"
## The school is the last stand, not a bunker: its two north doors are wall
## sections the dead can break once the yard has fallen, and the building only
## opens to them when a door is down.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const YARD := Vector2(36.0, 40.0)
const GYM := Vector2(28.5, 52.5)


func _doors(sim) -> Array:
	var out := []
	for s in sim.segments:
		if s.kind == "door":
			out.append(s)
	return out


func _dead_path(g: Dictionary) -> Array:
	return g.sim.path_z.find(g.world.solid_z, YARD.x, YARD.y, GYM.x, GYM.y)


func _people_path(g: Dictionary) -> Array:
	return g.sim.path_p.find(g.world.solid_p, YARD.x, YARD.y, GYM.x, GYM.y)


## The yard has fallen (the pallet barricade on the north wall is down), the
## crew stands in the gym with no ammo, and five of the dead hunt in the yard.
func _siege(door_hp: float) -> Dictionary:
	var g := Helpers.make(41, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.stock.ammo = 0.0
	sim.minutes = 21.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = true
	sim._damage_segment(sim.segments[1], 1.0e6)
	var i := 0
	for p in sim.people:
		p.x = 24.5 + float(i % 3) * 3.0
		p.y = 52.5 + float(i / 3) * 3.0
		p.drafted = true
		p.order = Vector3(p.x, p.y, 0)
		i += 1
	for door in _doors(sim):
		door.hp = door_hp
		door.max_hp = maxf(door.max_hp, door_hp)
	for k in 5:
		var z = sim.spawn(33.0 + float(k) * 2.0, 38.0, "breach")
		z.speed = 0.8
	return g


func test_the_school_is_shut_to_the_dead_but_open_to_people() -> void:
	var g := Helpers.make(1, 1)
	check(_dead_path(g).is_empty(), "no way in for the dead while the doors hold")
	check(not _people_path(g).is_empty(), "the crew walks in and out")
	g.world.free()


func test_the_doors_are_wall_sections_with_slots_in_front() -> void:
	var g := Helpers.make(1, 1)
	var doors := _doors(g.sim)
	eq(doors.size(), 2, "a west door and an east door")
	for s in doors:
		eq(s.side, "S", "%s is the school's" % s.name)
		eq(s.slots.size(), 10, "ten of the dead can crowd at it")
		check(s.hp >= 100.0, "and it takes some breaking: %d" % int(s.hp))
		eq(s.state, 0, "whole")
		for sl in s.slots:
			check(sl.y < 44.0, "the slots are on the yard side")
	g.world.free()


func test_a_fallen_yard_sends_the_dead_at_the_door_of_the_school() -> void:
	var g := _siege(500.0)
	var sim = g.sim
	Helpers.run(sim, 60.0)
	var clawed := 0.0
	for s in _doors(sim):
		clawed += s.max_hp - s.hp
	check(clawed > 5.0, "the dead tore at the doors: %.1f" % clawed)
	g.world.free()


func test_the_door_breaks_and_the_dead_come_in() -> void:
	var g := _siege(40.0)
	var sim = g.sim
	var inside := false
	for i in 150 * 30:
		sim.update(1.0 / 30.0)
		for z in sim.zombies:
			if z.state != "dead" and z.state != "dying" and z.x > 21.0 and z.x < 62.0 and z.y > 46.0 and z.y < 57.0:
				inside = true
		if inside:
			break
	var down := false
	for s in _doors(sim):
		if s.state == 3:
			down = true
	check(down, "a door is down")
	check(inside, "and the dead are inside the school")
	g.world.free()


func test_the_dead_leave_the_doors_alone_while_the_yard_stands() -> void:
	var g := Helpers.make(43, 1)
	var sim = g.sim
	sim.minutes = 21.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = true
	Helpers.run(sim, 90.0)
	for s in _doors(sim):
		near(s.hp, s.max_hp, 0.0001, "%s untouched" % s.name)
		for sl in s.slots:
			check(sl.who == null, "nobody queues at it")
	g.world.free()


func test_a_breach_opens_the_building_and_a_repair_shuts_it_when_no_dead_are_inside() -> void:
	var g := Helpers.make(44, 1)
	var sim = g.sim
	var door = _doors(sim)[0]
	sim._damage_segment(door, door.hp + 1.0)
	eq(door.state, 3, "the door is down")
	sim.refresh_school()
	check(not _dead_path(g).is_empty(), "now the dead can walk to the gym")
	var inside = sim.spawn(30.5, 46.5, "wander")
	inside.speed = 0.0
	sim._repair_segment(door, door.max_hp)
	eq(door.state, 0, "repaired")
	sim.refresh_school()
	var within: Array = sim.path_z.find(g.world.solid_z, 30.5, 46.5, GYM.x, GYM.y)
	check(not within.is_empty(), "a dead one is still inside, so the inside stays open to it")
	check(_dead_path(g).is_empty(), "though nobody else can come in through the repaired door")
	inside.state = "dead"
	sim.refresh_school()
	within = sim.path_z.find(g.world.solid_z, 30.5, 46.5, GYM.x, GYM.y)
	check(within.is_empty(), "and the building shuts once nobody dead is left in it")
	check(not _people_path(g).is_empty(), "the crew can still get in")
	g.world.free()


func test_people_walk_through_the_doors_in_every_state() -> void:
	var g := Helpers.make(45, 1)
	var sim = g.sim
	for door in _doors(sim):
		for frac in [1.0, 0.5, 0.2, 0.0]:
			door.hp = door.max_hp * frac
			sim._segment_state(door)
			check(not _people_path(g).is_empty(), "%s at %d%%: people still pass" % [door.name, int(frac * 100.0)])
		sim._repair_segment(door, door.max_hp)
	g.world.free()


func test_a_saved_breach_loads_open() -> void:
	var g := Helpers.make(46, 1)
	var sim = g.sim
	var door = _doors(sim)[1]
	sim._damage_segment(door, door.hp + 1.0)
	sim.refresh_school()
	var saved := SaveGame.to_dict(sim)
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var other := Sim.new(data, world, FxNull.new())
	check(SaveGame.apply(other, saved), "the save loads")
	var path: Array = other.path_z.find(world.solid_z, YARD.x, YARD.y, GYM.x, GYM.y)
	check(not path.is_empty(), "the school is open in the loaded game too")
	world.free()
	g.world.free()
