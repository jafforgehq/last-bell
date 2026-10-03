extends "res://tests/case.gd"
## Work life (round 16): by day, with nothing attacking, people work and do not stand on the walls. Every seat and
## every idle and rest spot is open ground off the decks (the lookout's tower aside); the Builders build at the
## site, mend a worn wall, or sort materials at the builders' yard; a person with no job rests at a rest spot; at
## the bell, or when the dead come to the wall by day, the crew holds its posts (the lookout stays at the tower)
## and goes back to work after ten quiet game minutes; at dawn the crew goes to work as the dead turn back; each
## goal carries a `work` word and the rules set `Person.work` and `work_t` from it. The classic start is as it was.

const Helpers := preload("res://tests/helpers.gd")
const Jobs := preload("res://scripts/sim/jobs.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## A quiet settlement game (five people: Ruth, Dez, Marcus, Ana, Walt) at `hour` of day 3: no nights, no dead, the
## radio off, the bench and the beds idle so the stores stay as they are, plenty of scrap.
func _game(hour: float = 11.0, crew: int = 5) -> Dictionary:
	var g := Helpers.make(61, 1, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.stock.scrap = 100.0
	sim.jobs.set_setting("bench", "ammo_target", 0)    # (the bench makes no ammo: a test that sets the stock to 0 keeps it there)
	sim.events.clear()
	return g


func _stand(sim, plot_id: String, building_id: String) -> void:
	var pl: Dictionary = sim.build.plot(plot_id)
	pl.building = building_id
	sim.build.version += 1
	sim.build._block(pl)


## A dead man who stays where he is put (a stagger that never ends), in `state`.
func _freeze(sim, x: float, y: float, state: String):
	var z = sim.spawn(x, y, state)
	z.stagger = 1.0e6
	return z


func _at(p, spot: Vector2, tol: float = 0.6) -> bool:
	return Vector2(p.x, p.y).distance_to(spot) <= tol


func _everyone_at(sim, spot_of: Callable, tol: float = 0.6) -> bool:
	for p in sim.people:
		if not _at(p, spot_of.call(p), tol):
			return false
	return true


func _wear(sim, id: int, share: float):
	for s in sim.segments:
		if s.id == id:
			s.hp = s.max_hp * share
			sim._segment_state(s)
			return s
	return null


func _apron() -> Rect2:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/motor_pool.json"))
	var a: Array = raw.apron
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


# ------------------------------------------------------------------- the ground --

func test_every_seat_and_spot_by_day_is_open_ground_off_the_decks() -> void:
	var g := _game()
	var sim = g.sim
	var w = sim.world
	# every building that adds seats or a station, standing
	for pair in [["salvage_bench_home", "salvage_bench"], ["greenhouse_home", "greenhouse"], ["workshop_home", "workshop"]]:
		_stand(sim, pair[0], pair[1])
	var apron := _apron()
	var spots: Array = []
	for st in sim.jobs.stations():
		for i in sim.jobs.seats_of(String(st.id)):
			var at: Vector2 = Vector2(st.pos) + Vector2(Jobs.SEAT_OFFSETS[mini(i, Jobs.SEAT_OFFSETS.size() - 1)])
			spots.append({"id": "%s seat %d" % [st.id, i], "at": at, "tower": String(st.id) == "watch"})
	for i in sim.jobs.rest_spots().size():
		spots.append({"id": "rest spot %d" % i, "at": Vector2(sim.jobs.rest_spots()[i].pos), "tower": false})
	check(spots.size() >= 14, "there are seats and spots to check: %d" % spots.size())
	for sp in spots:
		var at: Vector2 = sp.at
		check(not w.is_solid(w.solid_p, at.x, at.y), "%s is open ground at %s" % [sp.id, str(at)])
		if sp.tower:
			check(w.on_deck(at.x, at.y), "%s is the tower" % sp.id)
		else:
			check(not w.on_deck(at.x, at.y), "%s is not on a deck, at %s" % [sp.id, str(at)])
		if String(sp.id).begins_with("rest") or String(sp.id).begins_with("builders"):
			check(not apron.has_point(at), "%s is off the motor pool's apron" % sp.id)
	g.world.free()


func test_the_builders_yard_and_the_rest_spots_are_by_the_junk_and_the_tables_and_reachable() -> void:
	var g := _game()
	var sim = g.sim
	var yard: Vector2 = Vector2(sim.jobs.station("builders").pos)
	check(yard.x > 22.0 and yard.x < 33.0 and yard.y > 37.0 and yard.y < 44.0, "the builders' yard is in the south-west corner by the junk: %s" % str(yard))
	eq(String(sim.jobs.station("builders").where), "the builders' yard", "and the roster says so")
	var starts := [Vector2(39.0, 22.2), Vector2(31.0, 43.0)]
	var spots: Array = [yard, yard + Jobs.SEAT_OFFSETS[1], yard + Jobs.SEAT_OFFSETS[2]]
	for sp in sim.jobs.rest_spots():
		spots.append(Vector2(sp.pos))
	var lots: Array = []
	for pl in sim.build.plots():
		lots.append(Rect2(Vector2(pl.pos) - Vector2(pl.size) / 2.0, Vector2(pl.size)))
	for at in spots:
		for start in starts:
			check(not sim.path_p.find(sim.world.solid_p, start.x, start.y, at.x, at.y).is_empty(), "%s can be walked to from %s" % [str(at), str(start)])
		for lot in lots:
			check(not lot.grow(0.2).has_point(at), "%s is not in a building's lot %s" % [str(at), str(lot)])
		# not the court (the basketball court's painted ground is x 23 to 35, y 24 to 36)
		check(not Rect2(23.0, 24.0, 12.0, 12.0).has_point(at), "%s is off the court" % str(at))
		# not the garden's beds
		check(not Rect2(51.0, 25.0, 11.0, 10.0).has_point(at), "%s is off the garden" % str(at))
	g.world.free()


func test_the_stations_have_the_work_words_of_the_contract() -> void:
	var g := _game()
	var sim = g.sim
	var words := {"bench": "bench", "builders": "hammer", "garden": "garden", "infirmary": "nurse", "radio": "radio", "watch": "watch", "salvage": "sort"}
	for id in words:
		eq(String(sim.jobs.station(id).get("work", "")), words[id], "%s's work word" % id)
	g.world.free()


# --------------------------------------------------------------- the Builders --

func test_builders_with_no_site_and_no_wall_to_mend_sort_materials_in_the_yard() -> void:
	var g := _game()
	var sim = g.sim
	var walt = _person(sim, "Walt")
	eq(sim.jobs.job_of(walt), "builders", "Walt is on the Builders")
	Helpers.run(sim, 40.0)
	var yard: Vector2 = sim.jobs.seat_pos(walt)
	check(not sim.world.on_deck(yard.x, yard.y), "his seat is not on a deck")
	check(_at(walt, yard), "he stands at the yard, at %s" % str(Vector2(walt.x, walt.y)))
	check(not sim.world.on_deck(walt.x, walt.y), "and not on a wall")
	eq(walt.activity, "Sorting materials", "he says what he is doing")
	eq(walt.work, "haul", "he hauls")
	check(walt.work_t > 5.0, "and has for a while: %.1f s" % walt.work_t)
	g.world.free()


func test_builders_with_a_site_go_to_it_and_hammer() -> void:
	var g := _game()
	var sim = g.sim
	var walt = _person(sim, "Walt")
	check(sim.build.order("workshop_home", "workshop"), "a workshop is ordered")
	Helpers.run(sim, 30.0)
	var spot: Vector2 = sim.build.work_spot(walt)
	check(_at(walt, spot), "Walt is at the site's work spot %s, not at %s" % [str(spot), str(Vector2(walt.x, walt.y))])
	eq(walt.work, "hammer", "he hammers")
	eq(walt.activity, "Building the workshop", "and says what")
	check(sim.build.progress_of("workshop_home") > 0.0, "the site goes up")
	g.world.free()


func test_builders_go_to_a_worn_wall_and_mend_it() -> void:
	var g := _game()
	var sim = g.sim
	var walt = _person(sim, "Walt")
	var seg = _wear(sim, 4, 0.3)
	var worn_at: float = seg.hp
	var saw_mend := false
	for i in 40 * 30:
		sim.update(1.0 / 30.0)
		if walt.work == "mend":
			saw_mend = true
			check(walt.repair == seg, "he is mending the section he was sent to")
			check(_at(walt, seg.center), "at its middle")
			eq(walt.activity, "Mending the wrecked sedan", "and says so")
			break
	check(saw_mend, "Walt went to the worn wall and mended it")
	Helpers.run(sim, 5.0)
	check(seg.hp > worn_at, "the wall is stronger: %.0f against %.0f" % [seg.hp, worn_at])
	g.world.free()


func test_when_the_walls_are_mended_the_builders_go_back_to_the_yard() -> void:
	var g := _game()
	var sim = g.sim
	var walt = _person(sim, "Walt")
	_wear(sim, 4, 0.6)
	Helpers.run(sim, 90.0)
	check(sim.segments[4].hp >= sim.segments[4].max_hp - 0.01, "the wall is whole")
	check(walt.repair == null, "nothing left to mend")
	check(_at(walt, sim.jobs.seat_pos(walt)), "he is back at the yard")
	eq(walt.work, "haul", "sorting materials")
	g.world.free()


# ------------------------------------------------------------------- no job --

func test_someone_with_no_job_rests_at_a_rest_spot_not_where_they_stopped() -> void:
	var g := _game()
	var sim = g.sim
	var walt = _person(sim, "Walt")
	var dez = _person(sim, "Dez")
	sim.jobs.unassign(walt)
	sim.jobs.unassign(dez)
	walt.x = 45.5
	walt.y = 18.8    # where the old Builders' seat was: on the north deck
	dez.x = 43.5
	dez.y = 29.4
	var spots: Array = sim.jobs.rest_spots()
	var want_dez := Vector2(spots[0].pos)    # (the crew list has Dez before Walt: he takes the first spot)
	var want_walt := Vector2(spots[1].pos)
	Helpers.run(sim, 40.0)
	check(_at(dez, want_dez), "Dez rests at the first spot: %s" % str(Vector2(dez.x, dez.y)))
	check(_at(walt, want_walt), "Walt at the second: %s" % str(Vector2(walt.x, walt.y)))
	check(not _at(walt, want_dez, 1.0), "they do not stand on one another")
	for p in [walt, dez]:
		check(not sim.world.on_deck(p.x, p.y), "%s is not on a wall" % p.first)
		eq(p.activity, "Resting", "%s is resting" % p.first)
		eq(p.work, "rest", "and the word is rest")
	g.world.free()


func test_the_no_job_rest_goal_is_the_rest_spot_and_the_classic_start_is_at_ease() -> void:
	var g := _game()
	var sim = g.sim
	var walt = _person(sim, "Walt")
	sim.jobs.unassign(walt)
	var goal: Dictionary = sim.jobs.goal_for(walt)
	var spot: Vector2 = sim.jobs.rest_spots()[0].pos
	check(Vector2(goal.x, goal.y).distance_to(spot) < 0.01, "the settlement's goal is a rest spot")
	eq(goal.work, "rest", "its word")
	g.world.free()
	var c := Helpers.make(61, 1, 6)
	var cs = c.sim
	var hector = _person(cs, "Hector")
	cs.jobs.unassign(hector)
	hector.x = 40.0
	hector.y = 30.0
	eq(cs.jobs.goal_for(hector), {"x": 40.0, "y": 30.0, "face": "", "what": "At ease"}, "the classic start's person with no job stands at ease where they are")
	c.world.free()


# ------------------------------------------------------------ the day's threat --

func _at_posts(sim, lookout_at_tower := true) -> bool:
	for p in sim.people:
		var want: Vector2 = sim.jobs.post_pos(p)
		if lookout_at_tower and sim.jobs.job_of(p) == "watch":
			want = Vector2(sim.jobs.station("watch").pos)
		if not _at(p, want):
			return false
	return true


func test_the_dead_at_the_wall_by_day_send_everybody_to_their_posts_and_ten_quiet_minutes_send_them_back() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.ammo = 0.0    # (the butt of the gun reaches nobody: the dead stand where they are)
	Helpers.run(sim, 40.0)
	var walt = _person(sim, "Walt")
	check(not sim.threat_by_day(), "all is quiet")
	check(_everyone_at(sim, func(p): return Vector2(sim.jobs.goal_for(p).x, sim.jobs.goal_for(p).y)), "everyone is at work")
	var z = _freeze(sim, 39.0, 8.0, "approach")    # ten tiles north of the wall, coming
	Helpers.run(sim, 0.1)
	check(sim.threat_by_day(), "an approaching dead man is a threat by day")
	check(sim.alerts.has("day-threat"), "the crew is told")
	Helpers.run(sim, 45.0)
	check(_at_posts(sim), "everybody is at their post, the lookout at the tower")
	var deck := 0
	for p in sim.people:
		if sim.world.on_deck(p.x, p.y):
			deck += 1
	check(deck >= 3, "and they are on the walls: %d" % deck)
	eq(walt.work, "", "nobody is at their work")
	# it falls: the quiet minutes begin
	z.state = "dead"
	z.stagger = 0.0
	Helpers.run(sim, 2.0)    # 6 game minutes
	check(sim.threat_by_day(), "six quiet minutes: still at the posts")
	Helpers.run(sim, 2.0)    # 12 game minutes
	check(not sim.threat_by_day(), "ten quiet minutes: the threat is over")
	Helpers.run(sim, 45.0)
	check(_everyone_at(sim, func(p): return Vector2(sim.jobs.goal_for(p).x, sim.jobs.goal_for(p).y)), "everybody has gone back to work")
	check(not sim.world.on_deck(walt.x, walt.y), "Walt is off the wall")
	g.world.free()


func test_the_lookout_stays_at_the_tower_when_the_dead_come_by_day() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.ammo = 0.0
	var marcus = _person(sim, "Marcus")
	Helpers.run(sim, 25.0)
	eq(sim.jobs.job_of(marcus), "watch", "Marcus is the lookout")
	_freeze(sim, 39.0, 8.0, "approach")
	Helpers.run(sim, 20.0)
	check(sim.threat_by_day(), "a threat")
	check(_at(marcus, Vector2(sim.jobs.station("watch").pos)), "the lookout is at the tower")
	eq(marcus.work, "watch", "and watching")
	check(sim.jobs.operator("watch") == marcus, "he still works the post (the forecast at 17:00 would be given)")
	g.world.free()


func test_the_dead_of_the_streets_that_only_wander_or_hunt_are_no_threat_to_the_crew() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.ammo = 0.0
	_freeze(sim, 39.0, 12.0, "wander")    # (right under the wall, outside)
	_freeze(sim, 15.0, 30.0, "wander")
	var hunter = _freeze(sim, 12.0, 30.0, "hunt")
	hunter.hunt_id = "dez"
	Helpers.run(sim, 40.0)
	check(not sim.threat_by_day(), "wanderers and a hunter are not a threat")
	for p in sim.people:
		var goal: Dictionary = sim._goal_for(p)
		var work: Dictionary = sim.jobs.goal_for(p)
		eq(goal.what, work.what, "%s is at work (%s)" % [p.first, String(goal.what)])
		check(not sim.world.on_deck(p.x, p.y) or sim.jobs.job_of(p) == "watch", "%s is not on a wall" % p.first)
	# but one that has come to the wall is
	_freeze(sim, 39.0, 12.0, "approach")
	Helpers.run(sim, 0.1)
	check(sim.threat_by_day(), "an approaching one is")
	g.world.free()


func test_dead_far_from_the_compound_are_no_threat() -> void:
	var g := _game()
	var sim = g.sim
	_freeze(sim, 39.0, 0.5, "approach")    # 17.5 tiles from the wall
	Helpers.run(sim, 1.0)
	check(not sim.threat_by_day(), "an approaching one so far off is not yet a threat")
	sim.zombies[0].y = 3.0
	Helpers.run(sim, 0.1)
	check(sim.threat_by_day(), "nearer than sixteen tiles it is")
	g.world.free()


func test_a_ringing_alarm_is_a_threat_by_day() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.tactics.order_lure(sim.segments[2]), "the alarm is set")
	Helpers.run(sim, 0.1)
	check(sim.threat_by_day(), "an alarm by day sends the crew to its posts")
	g.world.free()


func test_the_wall_crew_is_called_off_a_wall_when_the_dead_come_and_the_quiet_minutes_pass_before_it_goes_back() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.ammo = 0.0
	var walt = _person(sim, "Walt")
	var seg = _wear(sim, 4, 0.3)
	Helpers.run(sim, 5.0)
	check(walt.repair == seg, "Walt is on his way to mend")
	var z = _freeze(sim, 39.0, 8.0, "approach")
	Helpers.run(sim, 0.2)
	check(walt.repair == null, "the dead are at the wall: he is called off the mending at once")
	z.state = "dead"
	Helpers.run(sim, 1.0)
	check(walt.repair == null, "and sent back to it only after the quiet minutes (3 minutes in)")
	Helpers.run(sim, 4.0)
	check(walt.repair == seg, "after them he goes back to the wall")
	g.world.free()


func test_a_day_under_attack_lets_the_crew_shoot() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var z = sim.spawn(39.0, 12.0, "approach")
	sim.assign_slot(z, sim.segments[2])
	z.x = 39.0
	z.y = 14.0
	Helpers.run(sim, 20.0)
	check(sim.kills > 0 or z.state == "dying" or z.state == "dead", "the crew at its posts shot the walker coming at the gate by day (it is %s)" % z.state)
	g.world.free()


# ----------------------------------------------------------------------- dawn --

func test_at_dawn_the_crew_goes_to_work_when_the_dead_have_turned_back() -> void:
	var g := _game(5.4)
	var sim = g.sim
	sim.stock.ammo = 0.0
	var z = _freeze(sim, 39.0, 16.0, "attack")
	sim.assign_slot(z, sim.segments[2])
	z.stagger = 1.0e6
	Helpers.run(sim, 1.0)
	check(sim.phase == "night", "still the night")
	check(sim.posts_manned(), "at their posts")
	# the dawn: the dead are sent back to the city
	sim.minutes = 5.5 * 60.0
	Helpers.run(sim, 0.2)
	eq(sim.phase, "dawn", "dawn")
	eq(z.state, "retreat", "the dead turn back")
	check(not sim.posts_manned(), "the crew is released from its posts")
	var walt = _person(sim, "Walt")
	Helpers.run(sim, 40.0)
	check(sim.phase == "dawn" or sim.phase == "day", "(%s)" % sim.phase)
	check(_everyone_at(sim, func(p): return Vector2(sim.jobs.goal_for(p).x, sim.jobs.goal_for(p).y)), "everybody is at work")
	check(not sim.world.on_deck(walt.x, walt.y), "Walt is off the wall")
	g.world.free()


func test_the_night_itself_is_not_shortened() -> void:
	var g := _game(23.0)
	var sim = g.sim
	check(sim.posts_manned(), "at 23:00 the crew holds its posts")
	sim.minutes = 5.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	check(sim.posts_manned(), "and at 05:00, with the dead about or not")
	sim.minutes = 19.2 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	check(sim.posts_manned(), "and at the bell")
	g.world.free()


func test_the_dead_still_coming_at_dawn_keep_the_posts() -> void:
	var g := _game(5.4)
	var sim = g.sim
	sim.minutes = 5.6 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	var z = _freeze(sim, 39.0, 16.0, "attack")
	check(sim.posts_manned(), "the dead at the wall in the dawn: the posts")
	z.state = "retreat"
	check(not sim.posts_manned(), "turned back: work")
	g.world.free()


# --------------------------------------------------------------- the work words --

func test_each_person_at_their_seat_works_at_it_and_the_clock_counts_up() -> void:
	var g := _game()
	var sim = g.sim
	sim.jobs.assign(_person(sim, "Walt"), "garden")
	var want := {"Ruth": "radio", "Dez": "bench", "Marcus": "watch", "Ana": "nurse", "Walt": "garden"}
	for first in want:
		Helpers.seat(sim, _person(sim, first))
	Helpers.run(sim, 0.2)
	for first in want:
		var p = _person(sim, first)
		eq(p.work, want[first], "%s's work" % first)
	var t0: float = _person(sim, "Ruth").work_t
	Helpers.run(sim, 2.0)
	near(_person(sim, "Ruth").work_t - t0, 2.0, 0.1, "work_t counts the seconds")
	var ruth = _person(sim, "Ruth")
	# a new job, far away: they walk, and the word goes
	sim.jobs.assign(ruth, "garden")
	Helpers.run(sim, 0.3)
	eq(ruth.work, "", "walking is no work")
	check(ruth.moving, "(she is walking)")
	Helpers.run(sim, 40.0)
	eq(ruth.work, "garden", "and at the beds the new word")
	check(ruth.work_t < 40.0, "its clock began when the word changed: %.1f" % ruth.work_t)
	g.world.free()


func test_nobody_is_at_work_by_night_or_when_down_or_away() -> void:
	var g := _game(22.0)
	var sim = g.sim
	Helpers.run(sim, 40.0)
	for p in sim.people:
		eq(p.work, "", "%s at their post is not at work" % p.first)
	var g2 := _game()
	var s2 = g2.sim
	var dez = _person(s2, "Dez")
	Helpers.seat(s2, dez)
	Helpers.run(s2, 1.0)
	eq(dez.work, "bench", "Dez at the bench")
	dez.downed = true
	Helpers.run(s2, 0.1)
	eq(dez.work, "", "down: no work")
	g.world.free()
	g2.world.free()


func test_a_healer_treating_a_patient_nurses() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _person(sim, "Ana")
	var marcus = _person(sim, "Marcus")
	marcus.x = 46.0
	marcus.y = 40.0
	sim.medical.add_wound(marcus, "bite")
	Helpers.run(sim, 0.2)
	var goal = sim.medical.goal_for(ana)
	check(goal != null, "Ana has a patient")
	eq(String(goal.get("work", "")), "nurse", "and nurses")
	g.world.free()


# ----------------------------------------------------------------- the classic --

func test_the_classic_start_has_the_goals_it_had() -> void:
	var g := Helpers.make(61, 1, 6)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	sim.minutes = 11.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	var want := {
		"Ruth": [60.5, 46.6, "Working the radio"], "Dez": [43.9, 27.1, "At the workbench"], "Ana": [48.5, 53.5, "Sorting medicine"],
		"Marcus": [18.9, 16.9, "Keeping watch"], "Walt": [45.5, 18.8, "Walking the wall"], "Hector": [53.5, 31.5, "Tending the garden"],
	}
	for first in want:
		var p = _person(sim, first)
		var goal: Dictionary = sim._goal_for(p)
		near(goal.x, want[first][0], 0.01, "%s's x" % first)
		near(goal.y, want[first][1], 0.01, "%s's y" % first)
		eq(goal.what, want[first][2], "%s's text" % first)
	check(sim.world.on_deck(45.5, 18.8), "(the classic Builders still walk the wall)")
	check(not sim.recruits.small, "classic")
	# the dead at the wall by day change nothing there
	sim.stock.ammo = 0.0
	var z = _freeze(sim, 39.0, 8.0, "approach")
	Helpers.run(sim, 1.0)
	check(not sim.threat_by_day(), "no day threat in the classic start")
	check(not sim.posts_manned(), "the crew stays at work")
	z.state = "dead"
	# the dawn is night there as it was
	sim.minutes = 6.0 * 60.0
	sim.phase = "dawn"
	check(sim.posts_manned(), "and the dawn keeps the posts")
	g.world.free()


# ----------------------------------------------------------------------- saves --

func test_a_save_from_before_loads_and_the_threat_is_kept() -> void:
	var a := _game()
	var sim_a = a.sim
	sim_a.stock.ammo = 0.0
	_freeze(sim_a, 39.0, 8.0, "approach")
	Helpers.run(sim_a, 2.0)
	check(sim_a.threat_by_day(), "a threat when saved")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := _game()
	check(SaveGame.apply(b.sim, d), "it applies")
	check(b.sim.threat_by_day(), "the threat is still on after the load")
	# a save from before this round has no threat clock and no work: it loads as a quiet day
	var old: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	old.modules.tactics.erase("threat_until")
	for pd in old.people:
		pd.erase("work")
		pd.erase("work_t")
	var c := _game()
	check(SaveGame.apply(c.sim, old), "an older save applies")
	check(not c.sim.threat_by_day(), "and has no threat")
	Helpers.run(c.sim, 2.0)
	for p in c.sim.people:
		check(p.work == "" or p.work_t >= 0.0, "work is recomputed")
	a.world.free()
	b.world.free()
	c.world.free()
