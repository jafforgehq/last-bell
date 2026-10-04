extends "res://tests/case.gd"
## Round 24, BASE-LIFE: (1) the starting car, the avatar (settlement) game's new run begins with ONE fuelled pickup in the motor pool
## (scripts/sim/vehicles.gd `give_starting_car`, called by main.gd for a new run of the real game, `{"car": true}` in a test's run), which the
## Map's Take control and the live drive can use from day 1, and which no other game, no load and no Orientation Day is given; (2) the base's
## little life (scripts/render/base_life.gd and the nodes it makes): that each part exists and animates (the time and the wind move the cloth's
## shader, the mast's lamp blinks, the bell swings on a bell event and settles, the dog walks on open ground and sleeps by a fire at night, the
## birds flush at a shot and come back, the ripples show only in rain, two friends at rest chat), that the parts off the screen are hidden, and
## that "reduce motion" and the off switch stop it. The no-avatar promise is tests/test_nights_regression.gd's and test_round20_noavatar.gd's.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Lighting := preload("res://scripts/render/lighting.gd")
const MastNode := preload("res://scripts/render/mast_node.gd")
const DogNode := preload("res://scripts/render/dog_node.gd")
const Convoy := preload("res://scripts/sim/convoy.gd")

const STEP := 1.0 / 30.0
## The yard in view (tiles), and a patch of the map where there is none of it.
const YARD := Rect2(14.0, 10.0, 56.0, 40.0)
const ELSEWHERE := Rect2(0.0, 0.0, 6.0, 6.0)


func _game(avatar: bool = true, crew: int = 3, car: bool = true) -> Node:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = false
	var meta := {"difficulty": 1, "seed": 7, "crew": crew}
	if avatar:
		meta["avatar"] = true
		meta["car"] = car
	var main = TutorialKit.start(meta)
	main.sim.waves.enabled = false
	return main


## The life, run for `seconds` of the game's time at the pace 1 in frames of a 60th (the view: the whole yard).
func _run(life, seconds: float, view: Rect2 = YARD) -> void:
	for i in int(seconds * 60.0):
		life.update(1.0 / 60.0, 1, view)


# ------------------------------------------------------------------------------ the starting car --

func test_a_new_avatar_game_starts_with_one_fuelled_pickup_in_a_bay() -> void:
	var main := _game()
	var sim = main.sim
	eq(sim.vehicles.fleet.size(), 1, "one vehicle")
	var v: Dictionary = sim.vehicles.fleet[0]
	eq(String(v.kind), "pickup", "a pickup")
	eq(String(v.state), "parked", "parked")
	near(float(v.hp), float(sim.vehicles.kind("pickup").hp), 0.001, "in good repair: its whole hp")
	var spot := int(v.spot)
	check(spot >= 0 and spot < Convoy.spots(), "in a bay of the motor pool: %d" % spot)
	# fuel for two trips to the farthest place the Map shows on the first morning
	var worst := 0.0
	for p in sim.town.places:
		if sim.town.is_known(String(p.id)):
			worst = maxf(worst, sim.vehicles.fuel_for(String(p.id), String(v.id)))
	check(worst > 0.0, "the places have a cost: %.2f" % worst)
	near(sim.vehicles.fuel, 10.0, 0.001, "ten fuel in the tank")
	check(sim.vehicles.fuel >= 2.0 * worst and sim.vehicles.fuel < 2.0 * worst + 1.0, "two trips of the farthest (%.2f each) and no more than a unit over" % worst)
	# the news line of the first morning, and the car on the apron
	var said := false
	for e in sim.radio.news:
		if String(e.kind) == "road" and String(e.text).contains("pickup") and String(e.sub).contains("Map"):
			said = true
	check(said, "News: the pickup is fuelled, Take control on the Map")
	main.parking_view.update(1.0 / 60.0)
	check(main.parking_view.drawn_ids().has(String(v.id)), "and it is drawn in its bay")
	await TutorialKit.leave(main)


func test_no_other_game_is_given_a_car() -> void:
	# a test's own avatar game (no `car` in its run), the old yard, a loaded older save and Orientation Day have none
	var plain := _game(true, 3, false)
	check(plain.sim.vehicles.fleet.is_empty(), "an avatar game that does not ask has no car")
	check(plain.sim.vehicles.give_starting_car().size() > 0, "but the rules give it when asked")
	check(plain.sim.vehicles.give_starting_car().is_empty(), "and only once")
	await TutorialKit.leave(plain)
	var old_yard := _game(false, 6)
	check(old_yard.sim.vehicles.fleet.is_empty() and old_yard.sim.vehicles.fuel == 0.0, "the old yard has none")
	check(old_yard.sim.vehicles.give_starting_car().is_empty(), "and is not given one (no avatar, no town)")
	await TutorialKit.leave(old_yard)
	var lesson = TutorialKit.start({"tutorial": true, "avatar": true, "car": true})
	check(lesson.sim.vehicles.fleet.is_empty(), "Orientation Day has no car")
	await TutorialKit.leave(lesson)
	var path := "user://test_r24b_oldsave.json"
	var text := FileAccess.get_file_as_string("res://tests/fixtures/round17_avatar_save.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var loaded = TutorialKit.start({"load": path, "car": true})
	check(not loaded.load_failed, "the round 17 save loads")
	check(loaded.sim.vehicles.fleet.is_empty(), "and is not given a car")
	await TutorialKit.leave(loaded)


func test_the_starting_car_makes_a_trip_on_day_one_and_a_save_keeps_it() -> void:
	var main := _game()
	var sim = main.sim
	var v: Dictionary = sim.vehicles.fleet[0]
	var id := String(v.id)
	sim.town.reveal("pharmacy")
	var crew: Array = [sim.people[1]]
	eq(sim.scavenge.why_not_played(crew, "pharmacy", "loot", id), "", "Take control by the pickup is allowed from the start")
	eq(sim.vehicles.why_not_use(id, 2, "church"), "", "it can reach the farthest known place with two aboard")
	# the live drive opens with it as the Map opens it, and burns the trip's fuel at the gate
	var before: float = sim.vehicles.fuel
	var cost: float = sim.vehicles.fuel_for("houses", id)
	var scene = main.open_raid(crew, sim.town.place("houses"), id, 1.0, Callable())
	check(scene != null and scene.flow.live, "a live trip opens in the starting car")
	if scene != null:
		scene.set_process(false)
	near(sim.vehicles.fuel, before - cost, 0.001, "its fuel was burnt")
	eq(String(sim.vehicles.vehicle(id).state), "out", "the car is out")
	DriveScene.stand_ins = {}
	await TutorialKit.leave(main)
	# a new game's save keeps its car (the fuel, the repair, its bay)
	var main2 := _game()
	var path := "user://test_r24b_car_save.json"
	check(SaveGame.write(main2.sim, path), "saved")
	var tank: float = main2.sim.vehicles.fuel
	await TutorialKit.leave(main2)
	var back = TutorialKit.start({"load": path})
	eq(back.sim.vehicles.fleet.size(), 1, "the save loads with its car")
	near(back.sim.vehicles.fuel, tank, 0.001, "and its fuel")
	await TutorialKit.leave(back)


# ----------------------------------------------------------------------------------- the base's life --

func test_every_part_exists_and_the_time_and_the_wind_move_the_cloth() -> void:
	var main := _game()
	var life = main.life_view
	check(life != null and life.enabled, "the life is made and on")
	eq(life.flags.size(), 2, "two flags")
	for part in [life.mast, life.bell, life.laundry, life.dog, life.birds, life.litter, life.ripples, life.chat]:
		check(part != null, "a part exists")
	var calm_wind: float = 0.0
	main.sim.weather = "clear"
	_run(life, 4.0)
	near(life.t, 4.0, 0.05, "the clock is the game's time")
	near(float(life._flag_mat.get_shader_parameter("t")), life.t, 0.001, "and the flags' shader has it")
	calm_wind = life.wind
	check(calm_wind > 0.05 and calm_wind < 0.7, "a light wind in clear weather: %.2f" % calm_wind)
	# paused, nothing moves
	var t0: float = life.t
	for i in 30:
		life.update(1.0 / 60.0, 0, YARD)
	near(life.t, t0, 0.0001, "paused: the clock stands")
	# rain: the wind rises, the ripples show, the leaves lie
	main.sim.weather = "rain"
	_run(life, 6.0)
	check(life.wind > calm_wind + 0.3, "stronger in rain: %.2f against %.2f" % [life.wind, calm_wind])
	check(life.rain > 0.9 and life.ripples.visible, "the ripples show in rain")
	near(life.litter.fade, 0.0, 0.001, "the leaves are not drawn in rain")
	main.sim.weather = "clear"
	_run(life, 8.0)
	check(not life.ripples.visible and life.rain < 0.02, "and are gone when it clears")
	await TutorialKit.leave(main)


func test_the_mast_blinks_and_the_bell_swings_at_the_bell_and_settles() -> void:
	var main := _game()
	var life = main.life_view
	check(MastNode.lamp_lit(0.0) and not MastNode.lamp_lit(MastNode.BLINK_S * 0.7), "the lamp is lit at the start of a cycle and dark late in it")
	var lit := 0
	var dark := 0
	for i in 120:
		life.mast.tick(1.0 / 30.0, float(i) / 30.0, 0.3, true)
		if life.mast.lit > 0.5:
			lit += 1
		else:
			dark += 1
	check(lit > 20 and dark > 20, "it blinks over four seconds: lit %d, dark %d" % [lit, dark])
	life.mast.tick(0.0, 1.5, 0.3, false)
	check(life.mast.lit > 0.5, "steady under reduce motion")
	# the bell
	life.update(1.0 / 60.0, 1, YARD)
	check(not life.bell.is_ringing(), "the bell hangs still")
	life.on_event({"type": "shot", "x": 40.0, "y": 30.0, "weapon": "rifle"})
	check(not life.bell.is_ringing(), "a shot does not ring it")
	life.on_event({"type": "bell"})
	check(life.bell.is_ringing() and life.bell.amp > 0.3, "the dusk bell swings it wide")
	var widest := 0.0
	var rings_seen := false
	for i in 180:
		life.update(1.0 / 60.0, 1, YARD)
		widest = maxf(widest, absf(life.bell.angle))
		rings_seen = rings_seen or life.bell._ring_quad.visible
	check(widest > 0.12, "it swings: %.2f rad" % widest)
	check(rings_seen, "and its rings go out")
	_run(life, 9.0)
	check(not life.bell.is_ringing() and absf(life.bell.angle) < 0.06, "it settles")
	life.on_event({"type": "lure"})
	check(life.bell.is_ringing() and life.bell.amp < life.bell.FULL * 0.7, "the call to arms' bell swings it less: %.2f" % life.bell.amp)
	await TutorialKit.leave(main)


func test_the_dog_walks_on_open_ground_by_day_and_sleeps_by_a_fire_at_night() -> void:
	var main := _game()
	var life = main.life_view
	var dog = life.dog
	check(dog.edge_count() >= 8, "its walking graph has its edges: %d" % dog.edge_count())
	var solid: PackedByteArray = main.world.solid_p
	var w: int = main.world.W
	var start: Vector2 = dog.pos
	var off_ground := 0
	var clock := 0.0
	for i in 3600:    # two minutes of the game's time
		clock += 1.0 / 30.0
		dog.tick(1.0 / 30.0, clock, true, true)
		var tile: int = int(floorf(dog.pos.y)) * w + int(floorf(dog.pos.x))
		if int(solid[tile]) != 0:
			off_ground += 1
	check(dog.trips >= 1 and dog.walked > 5.0, "it set off and walked: %d trips, %.1f tiles" % [dog.trips, dog.walked])
	check(dog.pos != start or dog.trips >= 2, "it has gone somewhere")
	eq(off_ground, 0, "it never stood on a solid tile")
	# dusk: it goes to the nearest fire and lies there
	for i in 6000:
		clock += 1.0 / 30.0
		dog.tick(1.0 / 30.0, clock, false, true)
	eq(dog.state, "lie", "by night it lies down")
	var by_fire := false
	for n in DogNode.NODES:
		if n[1] and dog.pos.distance_to(n[0]) < 0.01:
			by_fire = true
	check(by_fire, "by a fire: %s" % str(dog.pos))
	# reduce motion: it stays where it lies
	var at: Vector2 = dog.pos
	for i in 900:
		clock += 1.0 / 30.0
		dog.tick(1.0 / 30.0, clock, true, false)
	check(dog.pos == at and dog.state == "lie", "under reduce motion it does not get up")
	await TutorialKit.leave(main)


func test_birds_perch_flush_at_a_shot_and_come_back_and_roost_at_dusk() -> void:
	var main := _game()
	var life = main.life_view
	var birds = life.birds
	var clock := 0.0
	var seen := false
	birds.view = YARD
	for i in 900:    # thirty seconds: the away ones come in
		clock += 1.0 / 30.0
		birds.tick(1.0 / 30.0, clock, true, true)
	check(birds.count("perched") >= 3, "birds are perched on the walls: %d" % birds.count("perched"))
	var one = null
	for b in birds.birds:
		if b.state == "perched":
			one = b
			break
	var flushed: int = birds.on_event({"type": "shot", "x": one.pos.x, "y": one.pos.y, "weapon": "rifle"})
	check(flushed >= 1 and birds.count("flying") >= 1, "a shot beside them flushes birds: %d" % flushed)
	var landings: int = birds.landings
	for i in 2400:    # eighty seconds of quiet: they come back
		clock += 1.0 / 30.0
		birds.tick(1.0 / 30.0, clock, true, true)
		seen = seen or birds.visible
	check(seen, "the node showed while they flew")
	check(birds.landings > landings and birds.count("perched") >= 3, "they land again: %d landings" % (birds.landings - landings))
	# a noise far from the roosts leaves them be, and dusk sends them off for the night
	var n: int = birds.on_event({"type": "groan", "x": 2.0, "y": 2.0, "kind": "walker"})
	eq(n, 0, "a groan far away startles nobody")
	for i in 1200:
		clock += 1.0 / 30.0
		birds.tick(1.0 / 30.0, clock, false, true)
	eq(birds.count("perched"), 0, "at night none is on a wall")
	await TutorialKit.leave(main)


func test_two_friends_at_rest_chat_and_nobody_else_does() -> void:
	var main := _game(false, 6)    # the old yard: Dez and Hector are friends (map.json's bonds)
	var life = main.life_view
	var dez = TutorialKit.person(main.sim, "dez")
	var hector = TutorialKit.person(main.sim, "hector")
	for p in [dez, hector]:
		p.work = "rest"
		p.moving = false
		p.path = []
	dez.x = 40.0
	dez.y = 41.0
	hector.x = 41.4
	hector.y = 41.0
	life.chat.look()
	eq(life.chat.pairs.size(), 1, "the friends at rest are a pair")
	life.chat.view = YARD
	life.chat.tick(0.1, 0.2, true)
	eq(life.chat.shown_count(), 1, "one bubble shows over the one who speaks")
	life.chat.tick(0.1, 2.3, true)
	eq(life.chat.shown_count(), 1, "and over the other a moment later")
	hector.x = 48.0
	life.chat.look()
	eq(life.chat.pairs.size(), 0, "not when they are far apart")
	hector.x = 41.4
	hector.work = "hammer"
	life.chat.look()
	eq(life.chat.pairs.size(), 0, "not when one is at work")
	hector.work = "rest"
	life.chat.look()
	life.chat.tick(0.1, 0.2, false)
	eq(life.chat.shown_count(), 0, "and not under reduce motion")
	await TutorialKit.leave(main)


func test_off_the_screen_is_hidden_and_the_switches_work() -> void:
	var main := _game()
	var life = main.life_view
	_run(life, 1.0, YARD)
	check(life.shown_count() >= 7, "with the yard in view the parts show: %d" % life.shown_count())
	_run(life, 1.0, ELSEWHERE)
	eq(life.shown_count(), 0, "with the camera elsewhere none of them is drawn")
	_run(life, 0.5, YARD)
	# the node count does not grow as the life runs (nothing is made in a frame)
	var nodes: int = life.get_tree().get_node_count()
	_run(life, 20.0, YARD)
	eq(life.get_tree().get_node_count(), nodes, "no node is made while it runs")
	# reduce motion: the leaves and the ripples are not drawn, the bell does not ring
	Prefs.set_value("ui", "reduce_motion", true)
	life._slow = 1.0
	life.update(1.0 / 60.0, 1, YARD)
	check(not life.animate and not life.litter.visible and not life.ripples.visible, "reduce motion stills the leaves and the ripples")
	check(not life.bell.on_event({"type": "bell"}), "and the bell")
	Prefs.set_value("ui", "reduce_motion", false)
	# the off switch
	life.set_enabled(false)
	check(not life.visible and not life.dog.visible, "off (--calm): none of it shows")
	life.set_enabled(true)
	_run(life, 0.5, YARD)
	check(life.visible and life.shown_count() >= 7, "and on again")
	await TutorialKit.leave(main)


func test_the_lanterns_gutter_at_dusk_and_burn_nearly_steady_at_night() -> void:
	var lo := 1.0
	var spread_dusk := 0.0
	var spread_night := 0.0
	var lo_n := 1.0
	var hi_n := 0.0
	for i in 400:
		var t := float(i) * 0.037
		var f_dusk := Lighting.lamp_flicker(t, 20.9, 0.05)
		var f_night := Lighting.lamp_flicker(t, 20.9, 1.0)
		lo = minf(lo, f_dusk)
		lo_n = minf(lo_n, f_night)
		hi_n = maxf(hi_n, f_night)
		check(f_dusk <= 1.0 and f_dusk >= 0.4 and f_night <= 1.0 and f_night >= 0.8, "the flicker stays in range")
	check(lo < 0.7, "at dusk the light dips a lot: %.2f" % lo)
	check(hi_n - lo_n > 0.02 and hi_n - lo_n < 0.15, "all night it still wavers a little: %.3f" % (hi_n - lo_n))
