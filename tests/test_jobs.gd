extends "res://tests/case.gd"
## Jobs and stations: who works where by day and where they hold the wall by night, the
## seats, the posts, the settings, auto-assign, the goals the rules follow and the saves.

const Helpers := preload("res://tests/helpers.gd")
const Jobs := preload("res://scripts/sim/jobs.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## A quiet game at `hour` with the nights and the radio switched off.
func _game(hour: float = 9.0) -> Dictionary:
	var g := Helpers.make(51, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.events.clear()
	return g


func _seat(sim, p) -> void:
	var at: Vector2 = sim.jobs.seat_pos(p)
	p.x = at.x
	p.y = at.y
	p.moving = false


func test_a_new_run_has_the_default_jobs_and_posts() -> void:
	var g := _game()
	var sim = g.sim
	var jobs: Dictionary = {"Ruth": "radio", "Dez": "bench", "Ana": "infirmary", "Marcus": "watch", "Walt": "builders", "Hector": "garden"}
	for first in jobs:
		eq(sim.jobs.job_of(_person(sim, first)), jobs[first], "%s's job" % first)
	var posts: Dictionary = {"Ruth": "gate", "Dez": "bus", "Ana": "west_fence", "Marcus": "tower_nw", "Walt": "tower_ne", "Hector": "barricade"}
	for first in posts:
		eq(String(sim.jobs.post_of(_person(sim, first)).id), posts[first], "%s's post" % first)
	check(sim.jobs.stations().size() >= 6, "the six stations are loaded")
	check(sim.jobs.posts().size() >= 19, "and the posts")
	g.world.free()


func test_the_stations_and_posts_are_somewhere_a_person_can_stand() -> void:
	var g := _game()
	var sim = g.sim
	for st in sim.jobs.stations():
		var at: Vector2 = st.pos
		check(not sim.world.is_solid(sim.world.solid_p, at.x, at.y), "%s is on open ground at %s" % [st.name, str(at)])
	for po in sim.jobs.posts():
		var on: Vector2 = po.pos
		check(sim.world.on_deck(on.x, on.y), "%s is on a deck at %s" % [po.name, str(on)])
	g.world.free()


func test_a_station_has_so_many_seats_and_refuses_the_rest() -> void:
	var g := _game()
	var sim = g.sim
	var walt = _person(sim, "Walt")
	var hector = _person(sim, "Hector")
	eq(sim.jobs.seats_left("bench"), 1, "the bench has two seats and Dez has one")
	check(sim.jobs.assign(hector, "bench"), "Hector takes the other")
	eq(sim.jobs.job_of(hector), "bench", "he is on it")
	eq(sim.jobs.seats_left("garden"), 2, "and left the garden's seat")
	check(not sim.jobs.assign(walt, "bench"), "the bench is full")
	eq(sim.jobs.why_not(walt, "bench"), "the Workbench is full", "and says so")
	eq(sim.jobs.job_of(walt), "builders", "Walt stays where he was")
	check(sim.jobs.assign(walt, "garden"), "a seat in the garden")
	sim.jobs.unassign(walt)
	eq(sim.jobs.job_of(walt), "", "no job")
	eq(sim.jobs.why_not(walt, "nowhere"), "there is no such job", "an unknown job")
	g.world.free()


func test_the_dead_cannot_be_given_a_job_and_do_not_hold_a_seat() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var hector = _person(sim, "Hector")
	var ana = _person(sim, "Ana")
	check(sim.jobs.assign(hector, "bench"), "the bench is full now")
	dez.dead = true
	eq(sim.jobs.seats_left("bench"), 1, "a dead person's seat is free")
	check(sim.jobs.assign(ana, "bench"), "so Ana can take it")
	ana.dead = true
	check(not sim.jobs.assign(ana, "garden"), "the dead are not given jobs")
	g.world.free()


func test_two_people_at_one_station_stand_apart() -> void:
	var g := _game()
	var sim = g.sim
	sim.jobs.assign(_person(sim, "Hector"), "bench")
	var a: Vector2 = sim.jobs.seat_pos(_person(sim, "Dez"))
	var b: Vector2 = sim.jobs.seat_pos(_person(sim, "Hector"))
	check(a.distance_to(b) >= 0.9, "their seats are a step apart: %.2f" % a.distance_to(b))
	g.world.free()


func test_the_ones_who_work_a_station_are_those_there_and_free_by_day() -> void:
	var g := _game(9.0)
	var sim = g.sim
	var hector = _person(sim, "Hector")
	hector.x -= 4.0
	eq(sim.jobs.working("garden").size(), 0, "nobody is at the garden yet")
	_seat(sim, hector)
	eq(sim.jobs.working("garden"), [hector], "Hector is, at his seat")
	eq(sim.jobs.operator("garden"), hector, "the operator")
	hector.drafted = true
	hector.order = Vector3(hector.x, hector.y, 0)
	eq(sim.jobs.working("garden").size(), 0, "not when he is under an order")
	hector.drafted = false
	hector.order = null
	hector.downed = true
	eq(sim.jobs.working("garden").size(), 0, "not when he is down")
	hector.downed = false
	hector.x += 3.0
	eq(sim.jobs.working("garden").size(), 0, "not when he is across the yard")
	hector.x -= 3.0
	sim.minutes = 22.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = true
	eq(sim.jobs.working("garden").size(), 0, "and not at night")
	g.world.free()


func test_by_day_a_person_walks_to_their_station_and_at_the_bell_to_their_post() -> void:
	var g := _game(9.0)
	var sim = g.sim
	var hector = _person(sim, "Hector")
	hector.x = 40.0
	hector.y = 35.0
	Helpers.run(sim, 14.0)
	check(Vector2(hector.x, hector.y).distance_to(sim.jobs.seat_pos(hector)) < 0.7, "Hector is at the garden: %s" % str(Vector2(hector.x, hector.y)))
	eq(hector.activity, "Tending the garden", "and says what he is doing")
	sim.minutes = 19.4 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = true
	Helpers.run(sim, 40.0)
	check(Vector2(hector.x, hector.y).distance_to(sim.jobs.post_pos(hector)) < 0.7, "and at night at his post: %s" % str(Vector2(hector.x, hector.y)))
	g.world.free()


func test_a_post_is_kept_from_night_to_night_and_goes_to_one_person() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var dez = _person(sim, "Dez")
	check(not sim.jobs.set_post(ruth, "bus"), "Dez has the bus")
	check(sim.jobs.set_post(ruth, "north_middle"), "a free post")
	eq(String(sim.jobs.post_of(ruth).id), "north_middle", "Ruth holds it")
	near(sim.jobs.post_pos(ruth).x, 43.5, 0.001, "at its place")
	check(sim.jobs.set_post(dez, "gate"), "the gate is free now")
	eq(String(sim.jobs.post_of(dez).id), "gate", "Dez holds it")
	sim.order_post(ruth)
	near(float(ruth.order.x), 43.5, 0.001, "and P sends Ruth to her new one")
	g.world.free()


func test_settings_are_kept_inside_their_range_and_step() -> void:
	var g := _game()
	var sim = g.sim
	eq(int(sim.jobs.setting("bench", "ammo_target")), 300, "the default target")
	sim.jobs.set_setting("bench", "ammo_target", 9999)
	eq(int(sim.jobs.setting("bench", "ammo_target")), 800, "never above its maximum")
	sim.jobs.set_setting("bench", "ammo_target", 137)
	eq(int(sim.jobs.setting("bench", "ammo_target")), 125, "and in steps of 25")
	sim.jobs.set_setting("builders", "repair_below", -5)
	eq(int(sim.jobs.setting("builders", "repair_below")), 30, "never under its minimum")
	g.world.free()


func test_auto_assign_fills_the_seats_by_skill() -> void:
	var g := _game()
	var sim = g.sim
	sim.jobs.clear()
	for p in sim.people:
		eq(sim.jobs.job_of(p), "", "%s has no job after Clear" % p.first)
	sim.jobs.auto_assign()
	eq(sim.jobs.job_of(_person(sim, "Dez")), "bench", "the best builder is on the bench")
	eq(sim.jobs.job_of(_person(sim, "Ana")), "infirmary", "the nurse in the infirmary")
	eq(sim.jobs.job_of(_person(sim, "Ruth")), "radio", "the best leader at the radio")
	eq(sim.jobs.job_of(_person(sim, "Marcus")), "watch", "the best shot on watch")
	for st in sim.jobs.stations():
		check(sim.jobs.crew_of(st.id).size() <= int(st.seats), "%s is not over its seats" % st.name)
	var jobless := 0
	for p in sim.people:
		if sim.jobs.job_of(p) == "":
			jobless += 1
	eq(jobless, 0, "everyone has something to do with six stations and eleven seats")
	g.world.free()


func test_the_jobs_posts_and_settings_are_saved() -> void:
	var a := _game()
	var sim_a = a.sim
	sim_a.jobs.assign(_person(sim_a, "Hector"), "bench")
	sim_a.jobs.set_post(_person(sim_a, "Ruth"), "north_middle")
	sim_a.jobs.set_setting("bench", "ammo_target", 450)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := Helpers.make(99, 0)
	check(SaveGame.apply(b.sim, d), "it applies")
	eq(b.sim.jobs.job_of(_person(b.sim, "Hector")), "bench", "Hector is on the bench")
	eq(String(b.sim.jobs.post_of(_person(b.sim, "Ruth")).id), "north_middle", "Ruth has her post")
	eq(int(b.sim.jobs.setting("bench", "ammo_target")), 450, "and the setting")
	a.world.free()
	b.world.free()


func test_a_save_from_before_jobs_gets_the_default_jobs() -> void:
	var a := _game()
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	d.modules.erase("jobs")
	var b := Helpers.make(98, 1)
	b.sim.jobs.clear()
	check(SaveGame.apply(b.sim, d), "it applies")
	eq(b.sim.jobs.job_of(_person(b.sim, "Dez")), "bench", "Dez has his default job")
	eq(String(b.sim.jobs.post_of(_person(b.sim, "Dez")).id), "bus", "and post")
	a.world.free()
	b.world.free()


func test_the_keys_toggle_the_bench_and_the_wall_crew() -> void:
	var g := _game()
	var sim = g.sim
	var hector = _person(sim, "Hector")
	var sel := {"kind": "person", "ref": hector}
	check(sim.handle_gizmo("job_bench", sel), "M takes the bench seat")
	eq(sim.jobs.job_of(hector), "bench", "Hector is on it")
	check(sim.handle_gizmo("job_bench", sel), "and pressing again")
	eq(sim.jobs.job_of(hector), "", "takes him off")
	check(sim.handle_gizmo("job_builders", sel), "B puts him on the wall crew")
	eq(sim.jobs.job_of(hector), "builders", "there")
	check(not sim.handle_gizmo("job_bench", {"kind": "segment", "ref": sim.segments[0]}), "a wall section has no job")
	g.world.free()


func test_an_empty_radio_desk_and_an_empty_lookout_post_are_said() -> void:
	var g := _game(11.0)
	var sim = g.sim
	sim.jobs.unassign(_person(sim, "Ruth"))
	var said := false
	for i in 60 * 30:
		sim.update(1.0 / 30.0)
		if sim.alerts.has("job-radio"):
			said = true
	check(said, "nobody at the radio desk by 11:30 is said")
	var g2 := _game(11.0)
	var sim2 = g2.sim
	var ruth2 = _person(sim2, "Ruth")
	ruth2.x = sim2.jobs.seat_pos(ruth2).x
	ruth2.y = sim2.jobs.seat_pos(ruth2).y
	var said2 := false
	for i in 60 * 30:
		sim2.update(1.0 / 30.0)
		if sim2.alerts.has("job-radio"):
			said2 = true
	check(not said2, "with Ruth at the desk nothing is said")
	g.world.free()
	g2.world.free()


func test_someone_with_nothing_to_do_is_idle() -> void:
	var g := _game(9.0)
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	check(not sim.jobs.idle(ruth), "the radio operator is not idle")
	sim.jobs.unassign(ruth)
	check(sim.jobs.idle(ruth), "someone with no job is")
	ruth.downed = true
	check(not sim.jobs.idle(ruth), "unless they are down")
	g.world.free()
