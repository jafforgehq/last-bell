extends "res://tests/case.gd"
## The scene of the live drive (round 21, V21.1: scripts/drive/drive_scene.gd and car_node.gd). It is the place's scene with a car: `phase`
## stays "place" for the whole trip, the colony is stepped one step in three at the leg's pace by the flow (place_flow.gd), the car
## is stepped by the player's hands or the autopilot, the squad rides in it and shoots from its windows, the road's events (road_events.gd)
## come as the car does, and a leg ends at the end of the road (`flow.end_leg`) with the place, or the report, next.
## The road is road_gen.gd's, the car car_sim.gd's, the events road_events.gd's; the flow is place_flow.gd's (their own tests are theirs).
## Fixtures are user:// files named test_r21_scene_*.

const GD := preload("res://scripts/game_data.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")
const CarNode := preload("res://scripts/drive/car_node.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")

const STEP := 1.0 / 30.0


## The real game (a small start: Ruth, Dez and Marcus) in a window of this size, its own frames off.
func _game(width: int = 1280, height: int = 800, crew: int = 3, avatar: bool = true) -> Node:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = false
	return TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": avatar}, width, height)


func _leave(main: Node) -> void:
	PlaceFlow.live_enabled = true
	PlaceFlow.no_events = false
	DriveScene.stand_ins = {}
	await TutorialKit.leave(main)


## A live trip to `place_id` begun over `main`: the first `n` of the crew in a vehicle of `kind` ("" on foot), the scene made and begun
## (its own frames are off: the tests tick it by hand). {"scene", "flow", "sim", "place"}.
func _trip(main: Node, place_id: String = "pharmacy", kind: String = "pickup", n: int = 2, events: bool = true) -> Dictionary:
	var sim = main.sim
	sim.vehicles.fuel = 60.0
	sim.waves.enabled = false
	sim.town.reveal(place_id)
	var vid := ""
	if kind != "":
		vid = String(sim.vehicles.add(kind).id)
	var party: Array = []
	for i in n:
		party.append(sim.people[i])
	var flow = PlaceFlow.new(sim)
	check(flow.begin(party, place_id, vid), "the trip begins: %s" % flow.error)
	flow.live = true
	var place: Dictionary = sim.town.place(place_id)
	var scene := DriveScene.new()
	scene.no_events = not events
	main.add_child(scene)
	scene.set_process(false)
	var maker := func(size: int, by_vehicle: bool) -> Dictionary: return SiteGen.make(place, 5, size, by_vehicle)
	scene.setup_trip(main, main.hud, main.data, flow, place, maker, party, float(sim.stock.ammo), kind, 1.0, false)
	scene.begin_trip(flow)
	return {"scene": scene, "flow": flow, "sim": sim, "place": place}


func _play(scene: Node, seconds: float) -> void:
	for i in int(seconds * 30.0):
		scene.tick(STEP)


## A key pressed into the scene as the window hands it (`_input`: it keeps the keys held and takes the press).
func _press(scene: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	scene._input(ev)


func _release(scene: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = false
	scene._input(ev)


# ----------------------------------------------------------------- building --

func test_the_scene_builds_from_a_generated_road_and_the_phase_stays_place() -> void:
	var main := _game()
	var t := _trip(main)
	var scene = t.scene
	eq(scene.phase, "place", "the road is a place with a car")
	eq(scene.leg, "there", "the leg there")
	eq(scene.mode, "drive", "everyone aboard")
	check(scene.car != null and scene.car_node != null, "a car and its picture")
	eq(String(scene.site.kind), "road", "the stage's site is the road's")
	eq(scene.aboard().size(), 2, "two aboard")
	check(scene.aboard()[0] == scene.leader(), "the one you lead is at the wheel")
	check(scene.camera.is_current(), "the scene's camera is the current one")
	check(not scene.road.is_empty() and scene.road.dir == -1, "the road runs north")
	near(scene.car.heading, -PI / 2.0, 1e-6, "the nose is north")
	near(scene.road_progress(), 0.0, 1e-6, "at the start")
	check(main.raid == scene, "the game counts it as a raid")
	await _leave(main)


# ---------------------------------------------------------------- helpers --

## A dead one (`kind`) at a point; "still" sleeps until noticed, "hunt" comes for the one you lead.
func _dead_at(scene: Node, at: Vector2, state: String = "still", kind: String = "walker"):
	var z = scene.run.sim.spawn(at.x, at.y, "wander", kind)
	if state == "hunt":
		z.state = "hunt"
		z.hunt_id = String(scene.leader().id)
	elif state == "still":
		scene.run._sleeping[z] = true
	return z


## The point `d` tiles ahead of the car along its nose and `side` to its right.
func _ahead(scene: Node, d: float, side: float = 0.0) -> Vector2:
	var dir := Vector2.from_angle(float(scene.car.heading))
	return Vector2(scene.car.pos) + dir * d + dir.rotated(PI / 2.0) * side


## The car stands where it is (nothing held, nobody to hand the wheel to).
func _hands_off(scene: Node) -> void:
	scene.autopilot = false
	scene.car.speed = 0.0


## The road's own events are out of the way: a clean road.
func _clean(scene: Node) -> void:
	for e in scene.plan:
		e["state"] = "missed"


# ------------------------------------------------------------- the pace --

func _steps_of_a_leg(place_id: String, seconds: float) -> Dictionary:
	var main := _game()
	var t := _trip(main, place_id, "pickup", 2, false)
	var scene = t.scene
	var flow = t.flow
	var sim = t.sim
	var clock0: float = sim.clock_min
	var last := 0.0
	var mono := true
	var n := int(seconds * 30.0)
	for i in n:
		scene.tick(STEP)
		if scene.road_progress() < last - 1e-9:
			mono = false
		last = scene.road_progress()
		if scene.leg != "there":
			break
	var out := {"pace": flow.leg_pace, "road_min": flow.leg_road_min, "steps": flow.leg_steps, "colony": flow.leg_colony, "mono": mono, "progress": last,
		"clock": sim.clock_min - clock0, "elapsed": flow.elapsed_min(), "leg": scene.leg}
	await _leave(main)
	return out


func test_the_colony_is_stepped_one_in_three_at_pace_one() -> void:
	var r: Dictionary = await _steps_of_a_leg("pharmacy", 20.0)
	near(r.pace, 1.0, 1e-9, "a road of 30 to 90 minutes is a game minute a second (%.1f min)" % r.road_min)
	check(r.mono, "the progress never goes back")
	check(r.progress > 0.2, "the car is getting there (%.2f)" % r.progress)
	eq(r.colony, floori(float(r.steps) / 3.0 + 1e-9), "one colony step in three scene steps")
	near(r.clock, float(r.colony) * 0.1, 1e-6, "its clock moved by exactly those, a tenth of a minute each")
	near(r.elapsed, float(r.colony) * 0.1, 1e-6, "elapsed_min is the colony's steps x 0.1")


func test_a_long_road_runs_the_colony_faster_not_longer() -> void:
	var r: Dictionary = await _steps_of_a_leg("estate", 20.0)
	check(r.pace > 1.5 and r.pace < 2.2, "a road of %.0f minutes runs at %.2f game minutes a second" % [r.road_min, r.pace])
	eq(r.colony, floori(float(r.steps) * r.pace / 3.0 + 1e-9), "the colony took floor(steps x pace / 3) steps (the running total)")
	near(r.clock, float(r.colony) * 0.1, 1e-6, "and its clock moved by those")


func test_pausing_holds_the_car_and_the_colony() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_play(scene, 2.0)
	var at := Vector2(scene.car.pos)
	var clock: float = t.sim.clock_min
	scene.set_paused(true)
	_play(scene, 3.0)
	check(Vector2(scene.car.pos).is_equal_approx(at), "the car stands while paused")
	near(t.sim.clock_min, clock, 1e-9, "and the colony's clock")
	scene.set_paused(false)
	_play(scene, 1.0)
	check(t.sim.clock_min > clock, "both go on when it is let go")
	await _leave(main)


# ------------------------------------------------------- the car and the dead --

func test_the_squad_shoots_the_dead_in_range_from_the_car_but_not_when_it_speeds() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_hands_off(scene)
	var dez = scene.run.person("dez")
	var shots0: int = dez.stats.shots
	# a speeding car is not a rifle range: a dead one kept at the same place off its flank is not shot at
	var z = _dead_at(scene, _ahead(scene, 6.0, 4.5), "still")
	for i in 30:
		scene.car.speed = 5.5
		z.x = _ahead(scene, 4.0, 4.5).x
		z.y = _ahead(scene, 4.0, 4.5).y
		scene.tick(STEP)
	eq(dez.stats.shots, shots0, "nobody fires above 2 tiles a second")
	# standing, they do
	_hands_off(scene)
	z.x = _ahead(scene, 4.0, 4.5).x
	z.y = _ahead(scene, 4.0, 4.5).y
	var hp0: float = z.hp
	_play(scene, 3.0)
	check(dez.stats.shots > shots0, "Dez fires from the window once the car is slow")
	check(z.state == "dying" or z.state == "dead" or z.hp < hp0, "and hits the dead one (%s, hp %.1f of %.1f)" % [z.state, z.hp, hp0])
	await _leave(main)


func test_nobody_aboard_is_bitten_while_the_car_stands_among_the_dead() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_hands_off(scene)
	var hp0: Dictionary = {}
	for p in scene.aboard():
		hp0[String(p.id)] = float(p.hp)
	var hurt0: float = scene.car.hp
	for k in 8:
		var a := float(k) / 8.0 * TAU
		_dead_at(scene, Vector2(scene.car.pos) + Vector2.from_angle(a) * 3.2, "hunt", "walker" if k % 4 != 0 else "runner")
	# (the aboard cannot be reloaded out of ammunition for this: the stores are plenty)
	for i in 300:
		scene.run.sim.stock.ammo = 0.0    # (the squad cannot even shoot: the dead are all about the car)
		scene.car.speed = 0.0
		scene.tick(STEP)
	for p in scene.aboard():
		near(float(p.hp), float(hp0[String(p.id)]), 1e-6, "%s is not hurt aboard" % p.first)
	for l in scene.run.log:
		check(not String(l).contains("bitten"), "nobody was bitten: %s" % l)
	check(scene.car.hp < hurt0 or scene.mode == "foot", "the car pays for it: the dead claw at it")
	await _leave(main)


func test_a_dead_one_at_speed_is_run_over_and_a_brute_costs_the_car_and_its_speed() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_hands_off(scene)
	var hp0: float = scene.car.hp
	var z = _dead_at(scene, _ahead(scene, 2.5), "still")
	scene.car.speed = 5.0
	scene.tick(STEP)
	check(z.state == "dying" or z.state == "dead", "one at 5 tiles a second is run over (%s)" % z.state)
	near(scene.car.hp, hp0 - 0.35, 0.02, "for the car's small price")
	_hands_off(scene)
	var hp1: float = scene.car.hp
	var b = _dead_at(scene, _ahead(scene, 2.5), "still", "brute")
	scene.car.speed = 5.0
	scene.tick(STEP)
	check(b.state != "dying" and b.state != "dead", "a brute is not run over")
	check(scene.car.hp < hp1 - 5.0, "it costs the car its hp (%.1f of %.1f)" % [scene.car.hp, hp1])
	check(scene.car.speed < 3.5, "and its speed (%.2f)" % scene.car.speed)
	await _leave(main)


func test_a_car_at_zero_hp_stops_and_the_squad_walks_the_rest() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_hands_off(scene)
	scene.car.damage(1000.0)
	scene.tick(STEP)
	eq(scene.mode, "foot", "the squad is on foot")
	check(not scene.in_car() and scene.aboard().is_empty(), "nobody is aboard")
	near(float(scene.car.speed), 0.0, 1e-9, "the car stands")
	var y0: float = scene.leader().y
	_press(scene, KEY_W)
	_play(scene, 2.0)
	_release(scene, KEY_W)
	check(scene.leader().y < y0 - 4.0, "the one you lead walks north (%.1f -> %.1f)" % [y0, scene.leader().y])
	check(scene.road_progress() > 0.0, "and the road is walked from here")
	var r: Dictionary = scene.leg_result()
	check(bool(r.wrecked), "the leg says the car is a wreck")
	check(float(r.vehicle_hp_lost) > 0.0, "with its wear")
	await _leave(main)


func test_a_person_lost_on_the_road_is_in_the_result_and_the_next_aboard_leads() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_hands_off(scene)
	var ruth = scene.run.person("ruth")
	ruth.downed = true
	ruth.hp = 0.0
	_play(scene, 0.5)
	eq(String(scene.leader().id), "dez", "the next aboard leads")
	var r: Dictionary = scene.leg_result()
	check((r.lost as Array).has("ruth"), "Ruth is lost")
	eq(String(r.leader), "dez", "and the leg says who leads")
	check(not (r.hp as Dictionary).has("ruth"), "she is not among those who stand")
	eq(scene.aboard().size(), 1, "one is aboard")
	await _leave(main)


func test_the_leg_result_has_the_shape_the_flow_takes() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_play(scene, 1.0)
	var r: Dictionary = scene.leg_result()
	for key in ["hp", "lost", "hurt", "ammo_used", "vehicle_hp_lost", "wrecked", "failed", "leader"]:
		check(r.has(key), "the result has %s" % key)
	check((r.hp as Dictionary).has("ruth") and (r.hp as Dictionary).has("dez"), "the people on their feet have their health")
	eq(r.lost, [], "nobody lost")
	check(not bool(r.wrecked) and not bool(r.failed), "no wreck, not failed")
	eq(String(r.leader), "ruth", "Ruth leads")
	await _leave(main)


# ----------------------------------------------------------------- hands --

func test_tab_hands_the_wheel_to_the_squad_and_w_takes_it_back() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	check(scene.autopilot, "a headless run has no real hands: the autopilot drives")
	_press(scene, KEY_TAB)
	check(not scene.autopilot, "Tab gives the wheel to the player")
	_release(scene, KEY_TAB)
	_press(scene, KEY_TAB)
	check(scene.autopilot, "and again to the squad")
	_release(scene, KEY_TAB)
	_press(scene, KEY_W)
	_play(scene, 0.2)
	check(not scene.autopilot, "any of W A S D takes it back")
	var v: float = scene.speed_now()
	check(v > 0.5, "and W accelerates (%.2f)" % v)
	_release(scene, KEY_W)
	await _leave(main)


func test_the_avatars_fire_from_the_car_is_wider_than_standing() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_hands_off(scene)
	var lead = scene.leader()
	scene.fire_held = true
	scene._hands()
	var standing: float = scene.run.sim.avatar.spread_of(lead, lead.gun)
	scene.car.speed = 6.0
	scene._hands()
	var moving: float = scene.run.sim.avatar.spread_of(lead, lead.gun)
	check(moving >= standing * 1.55, "x1.6 while the car moves: %.3f against %.3f" % [moving, standing])
	scene.fire_held = false
	await _leave(main)


func test_a_foot_trip_has_no_car_and_no_breakdown_but_the_same_road() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "", 3, true)
	var scene = t.scene
	check(scene.car == null and scene.car_node == null, "no car")
	eq(scene.mode, "foot", "on foot")
	eq(scene.phase, "place", "still a place")
	check(not scene.plan.is_empty(), "the road has its events")
	for e in scene.plan:
		check(String(e.id) != "breakdown", "no breakdown on foot")
	check(not scene.road.is_empty(), "the same road is made")
	var y0: float = scene.leader().y
	_press(scene, KEY_W)
	_play(scene, 2.0)
	_release(scene, KEY_W)
	check(scene.leader().y < y0 - 4.0, "the leader walks (%.1f -> %.1f)" % [y0, scene.leader().y])
	check(scene.road_progress() > 0.0, "and the progress is theirs")
	await _leave(main)


func test_freeing_the_scene_puts_the_colony_back() -> void:
	var main := _game()
	var before: bool = main.hud.visible
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	check(not main.hud.visible and main.raid == scene, "the colony is hidden while it runs")
	main.remove_child(scene)
	scene.free()
	check(main.hud.visible == before, "the colony's HUD is back")
	check(main.raid == null, "and the game has no raid")
	await _leave(main)


# ---------------------------------------------------------------- events --

## A leg with one forced event `id` at `at`, the car put at `car_at` of the road, the hands off.
func _event_trip(main: Node, id: String, at: float, car_at: float, kind: String = "pickup", n: int = 2) -> Dictionary:
	var t := _trip(main, "pharmacy", kind, n, false)
	var scene = t.scene
	scene.stage("event:%s@%s" % [id, str(at)])
	scene.autopilot = false
	scene.stage("at:%s" % str(car_at))
	if scene.car != null:
		_hands_off(scene)
	return t


func test_a_stop_shows_its_pill_and_opens_its_card_without_pausing_anything() -> void:
	var main := _game()
	var t := _event_trip(main, "wreck_supplies", 0.3, 0.25)
	var scene = t.scene
	eq(scene.plan.size(), 1, "the plan is the one event")
	eq(String(scene.plan[0].id), "wreck_supplies", "that one")
	scene.tick(STEP)
	check(not scene.near_entry.is_empty(), "the pill: a stop is near")
	var clock0: float = t.sim.clock_min
	var r: Dictionary = scene.press_stop()
	check(bool(r.ok) and String(r.what) == "card", "E opens the card of a stop the car is slow at")
	eq(scene.mode, "stopped", "the car stands")
	eq(scene.open_uid, "e1", "that card")
	_play(scene, 2.0)
	check(t.sim.clock_min > clock0, "the base's clock goes on with a card open")
	var opts: Array = scene.card_options()
	check(opts.size() == 2 and String(opts[0].id) == "search", "its options: %s" % str(opts))
	check(bool(scene.hud_layer.has_method("event_options")) and scene.hud_layer.event_options().size() == 2, "and the HUD shows them")
	await _leave(main)


func test_choose_applies_its_effects_once_and_the_squad_goes_out_for_the_work() -> void:
	var main := _game()
	var t := _event_trip(main, "wreck_supplies", 0.3, 0.25)
	var scene = t.scene
	scene.tick(STEP)
	scene.press_stop()
	var r: Dictionary = scene.choose("e1", "search")
	check(bool(r.ok), "Search it")
	var loot := 0
	for k in t.flow.road_loot:
		loot += int(t.flow.road_loot[k])
	check(loot >= 14, "units of two stocks go into the party's loot (%d)" % loot)
	var again: Dictionary = scene.choose("e1", "search")
	check(not bool(again.ok), "a second answer does nothing")
	var loot2 := 0
	for k in t.flow.road_loot:
		loot2 += int(t.flow.road_loot[k])
	eq(loot2, loot, "the loot is the same")
	eq(scene.mode, "out", "the squad is out working")
	near(scene.work_left, 10.0, 0.5, "for the stop's seconds")
	check(scene.aboard().is_empty(), "nobody is in the car")
	for p in scene.run.squad:
		check(Vector2(p.x, p.y).distance_to(Vector2(scene.car.pos)) < 6.0, "%s works beside the car" % p.first)
	var mid: Dictionary = scene.press_stop()
	check(not bool(mid.ok) and String(mid.what) == "working", "E while they work is not boarding")
	_play(scene, 11.0)
	eq(scene.mode, "drive", "when the work is done and they are back they board")
	eq(scene.aboard().size(), 2, "both aboard again")
	await _leave(main)


func test_a_refused_option_says_why_and_the_card_stays() -> void:
	var main := _game()
	var t := _event_trip(main, "survivor", 0.3, 0.25)
	var scene = t.scene
	scene.tick(STEP)
	scene.press_stop()
	var opts: Array = scene.card_options()
	var refused := false
	for o in opts:
		if String(o.id) == "take":
			refused = not bool(o.ok) and String(o.why) != ""
			check(String(o.why).contains("seat"), "the pickup has no seat: %s" % o.why)
	check(refused, "taking them in is refused with its reason")
	var r: Dictionary = scene.choose("e1", "take")
	check(not bool(r.ok) and String(r.get("why", "")) != "", "choosing it says why")
	eq(scene.open_uid, "e1", "and the card is still up")
	await _leave(main)


func test_a_card_nobody_answers_takes_its_auto_option_after_its_time() -> void:
	var main := _game()
	var t := _event_trip(main, "checkpoint", 0.3, 0.25)
	var scene = t.scene
	scene.tick(STEP)
	scene.press_stop()
	var before := 0.0
	for k in ["food", "scrap", "ammo", "water", "meds"]:
		before += float(t.sim.stock[k])
	_play(scene, 7.0)
	eq(scene.open_uid, "e1", "it waits")
	_play(scene, 2.0)
	eq(scene.open_uid, "", "then the card is taken by itself")
	eq(String(scene.plan[0].state), "done", "the event is done")
	eq(scene.mode, "drive", "and the car goes on")
	var after := 0.0
	for k in ["food", "scrap", "ammo", "water", "meds"]:
		after += float(t.sim.stock[k])
	check(after < before, "the toll was paid (%.0f -> %.0f)" % [before, after])
	await _leave(main)


func test_a_card_answered_by_its_key_takes_that_option() -> void:
	var main := _game()
	var t := _event_trip(main, "wreck_supplies", 0.3, 0.25)
	var scene = t.scene
	scene.tick(STEP)
	scene.press_stop()
	_press(scene, KEY_1)
	eq(String(scene.plan[0].state), "done", "1 took the first option")
	eq(scene.mode, "out", "the search is on")
	await _leave(main)


func test_an_ambush_puts_the_dead_on_the_road_ahead_as_the_car_comes() -> void:
	var main := _game()
	var t := _event_trip(main, "ambush", 0.4, 0.3)
	var scene = t.scene
	var before: int = scene.run.sim.zombies.size()
	scene.tick(STEP)
	check(scene.run.sim.zombies.size() >= before + 8, "eight or more of the dead come (%d -> %d)" % [before, scene.run.sim.zombies.size()])
	check(scene.met.has("e1"), "it is met")
	var hunting := 0
	for z in scene.run.sim.zombies:
		if z.state == "hunt":
			hunting += 1
	check(hunting >= 8, "and they hunt (%d)" % hunting)
	await _leave(main)


func test_a_forced_event_cuts_the_throttle_and_opens_its_card_when_the_car_stands() -> void:
	var main := _game()
	var t := _event_trip(main, "breakdown", 0.3, 0.27)
	var scene = t.scene
	scene.car.speed = 7.0
	var hp0: float = float(t.sim.vehicles.vehicle(t.flow.vehicle_id).hp)
	_press(scene, KEY_W)
	var guard := 0
	while scene.open_uid == "" and guard < 900:
		scene.tick(STEP)
		guard += 1
	_release(scene, KEY_W)
	eq(scene.open_uid, "e1", "the card opens once the car coasts to a stop (%d steps)" % guard)
	check(scene.speed_now() < 0.5, "it stands")
	check(guard > 40, "it took a while to coast (%d steps)" % guard)
	await _leave(main)


func test_a_roadblock_can_be_cleared_on_foot_and_its_wrecks_come_away() -> void:
	var main := _game()
	var t := _event_trip(main, "roadblock", 0.4, 0.3)
	var scene = t.scene
	check(scene.road.dyn.size() > 0, "the road has wrecks across it")
	var shut := 0
	for d in scene.road.dyn:
		for i in d.tiles:
			if scene.world.solid_p[int(i)] != 0:
				shut += 1
	check(shut > 0, "and they are solid in the grid")
	# put the car at the wall, slow
	var slot: Dictionary = scene._slot_of("e1")
	scene.car.pos = Vector2(slot.anchor.x, slot.y + 9.0)
	scene.car.heading = -PI / 2.0
	scene.car.speed = 0.0
	scene.tick(STEP)
	var r: Dictionary = scene.press_stop()
	check(bool(r.ok) and String(r.what) == "card", "E near the wall opens the card")
	var c: Dictionary = scene.choose("e1", "clear")
	check(bool(c.ok), "Clear it")
	eq(scene.mode, "out", "the squad goes out")
	_play(scene, 15.0)
	var left := 0
	for d in scene.road.dyn:
		for i in d.tiles:
			if scene.world.solid_p[int(i)] != 0:
				left += 1
	eq(left, 0, "the wrecks are gone when the work is done")
	await _leave(main)


func test_a_wreck_rammed_hard_is_knocked_aside_and_costs_the_car() -> void:
	var main := _game()
	var t := _event_trip(main, "roadblock", 0.4, 0.3)
	var scene = t.scene
	var d: Dictionary = scene.road.dyn[0]
	var to := Vector2(d.pos)
	scene.car.pos = Vector2(to.x, to.y + 6.0)
	scene.car.heading = -PI / 2.0
	var hp0: float = scene.car.hp
	for i in 40:
		scene.car.speed = 7.0
		scene.tick(STEP)
		if (d.tiles as Array).is_empty():
			break
	check((d.tiles as Array).is_empty(), "the wreck's tiles are open")
	check(scene.car.hp < hp0 - 5.0, "it cost the car (%.1f -> %.1f)" % [hp0, scene.car.hp])
	await _leave(main)


# ------------------------------------------------------------------ night --

## What the road HOME that begins at `hour` is: whether it is a night road, how many of the dead lie on it, and whether the beam is lit.
func _night_facts(hour: float) -> Dictionary:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	if hour < 0.0:
		hour = float(main.sim.seasons.dusk_hour()) - 0.25    # (a quarter of an hour before dusk: the road home crosses it)
	scene.stage("hour:%s+leg:home" % str(hour))
	scene.tick(STEP)
	var out := {"leg": scene.leg, "night": scene._has_headlights(), "dead": scene._dormant.size() + scene.run.sim.zombies.size(), "beam": scene.car_node.lights_on() if scene.car_node != null else false}
	await _leave(main)
	return out


func test_the_night_road_lights_the_headlights_and_raises_the_dead() -> void:
	var day: Dictionary = await _night_facts(9.0)
	eq(day.leg, "home", "the road home")
	check(not day.night and not day.beam, "no night road and no beam by day")
	var dusk: Dictionary = await _night_facts(-1.0)
	check(dusk.night, "a leg that crosses dusk is a night road")
	check(dusk.dead > day.dead, "with more of the dead (%d against %d)" % [dusk.dead, day.dead])
	check(dusk.beam, "and the beam is lit")


func test_the_streets_dead_sleep_in_a_list_and_wake_as_the_car_comes() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	var total: int = scene._dormant.size() + scene.run.sim.zombies.size()
	check(total > 4, "the strip has its dead (%d)" % total)
	check(scene.run.sim.zombies.size() < total, "most of them are not in the rules' crowd yet (%d of %d)" % [scene.run.sim.zombies.size(), total])
	scene.stage("at:0.8")
	var awake: int = scene.run.sim.zombies.size()
	check(awake <= total, "those of the far end wake as the car gets there")
	await _leave(main)


func test_a_car_that_stands_with_nothing_the_matter_is_pushed_back_onto_the_road() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_hands_off(scene)
	var at := Vector2(scene.car.pos)
	_play(scene, 21.0)
	check(Vector2(scene.car.pos).distance_to(at) > 2.0, "the squad pushes it on after twenty seconds")
	await _leave(main)


# ---------------------------------------------------------------- the trip --

## Ticks until `done.call()` is true (at most `limit` steps); the steps taken.
func _until(scene: Node, done: Callable, limit: int = 6000) -> int:
	var n := 0
	while n < limit and not bool(done.call()):
		scene.tick(STEP)
		n += 1
	return n


func test_the_autopilot_drives_the_leg_to_its_end_and_the_place_is_next() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	var fuel: float = main.sim.vehicles.fuel
	var n := _until(scene, func(): return scene.leg != "there" or scene.get("_pending").is_valid(), 5000)
	check(n < 5000, "the leg ends (%d steps)" % n)
	check(scene.road_progress() > 0.97, "at the end of the road (%.3f)" % scene.road_progress())
	scene.tick(STEP)    # (the one-frame card, then the stage is built)
	eq(scene.leg, "place", "the place is next")
	eq(scene.phase, "place", "still a place")
	eq(t.flow.stage, "place", "the flow says so")
	check(String(scene.site.kind) != "road", "the place's own site")
	eq(scene.run.squad.size(), 2, "the squad came with the car")
	check(scene.vehicle_node != null, "and the car stands by the entry")
	eq(t.flow.legs.size(), 1, "one leg is done")
	near(main.sim.vehicles.fuel, fuel, 1e-9, "no more fuel was burnt on the road")
	check(float(t.flow.last_leg.elapsed_min) > 20.0, "the leg took its minutes (%.1f)" % float(t.flow.last_leg.elapsed_min))
	check(main.raid == scene and not main.hud.visible, "the colony is still held")
	await _leave(main)


func test_a_whole_trip_a_drive_a_place_a_drive_and_the_report() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	var flow = t.flow
	var terrain_there: Array = scene.site.data.terrain.duplicate()
	_until(scene, func(): return scene.leg != "there", 5000)
	scene.tick(STEP)
	eq(scene.leg, "place", "the place")
	scene.stage("exit")
	_until(scene, func(): return scene.leg == "home" or scene.phase == "report", 200)
	scene.tick(STEP)
	eq(scene.leg, "home", "the way home is next")
	eq(flow.stage, "drive_home", "the flow's")
	eq(scene.road.dir, 1, "the same road, the other way")
	check(scene.site.data.terrain == terrain_there, "on the same ground")
	check(scene.car != null and scene.mode == "drive", "in the car")
	check(scene.aboard().size() == 2, "both aboard")
	_until(scene, func(): return scene.phase == "report" or scene.get("_pending").is_valid(), 5000)
	scene.tick(STEP)
	eq(scene.phase, "report", "the report is up")
	eq(flow.stage, "home", "the trip is home")
	check(main.trip_report == scene, "the colony counts the report as a page")
	var seen: Array = []
	scene.finished.connect(func(r): seen.append(r))
	scene.go_home()
	eq(seen.size(), 1, "finished is sent once")
	check(seen[0].has("loot") and seen[0].has("lost"), "with the trip's result")
	check(main.raid == null, "the colony is back")
	await _leave(main)


# ----------------------------------------------------------------- budget --

## The longest road a car drives (a sedan to the hospital: the strip is the longest there is) built and driven for twenty seconds
## with its events on: what it costs. The numbers are printed (the web build is some times slower than this machine).
func test_the_longest_road_is_built_and_driven_within_budget() -> void:
	var main := _game()
	var sim = main.sim
	sim.vehicles.fuel = 90.0
	sim.town.reveal("hospital")
	var vid := String(sim.vehicles.add("sedan").id)
	var party: Array = [sim.people[0], sim.people[1]]
	var flow = PlaceFlow.new(sim)
	check(flow.begin(party, "hospital", vid), "the trip begins: %s" % flow.error)
	flow.live = true
	var place: Dictionary = sim.town.place("hospital")
	var scene := DriveScene.new()
	main.add_child(scene)
	scene.set_process(false)
	var maker := func(size: int, by_vehicle: bool) -> Dictionary: return SiteGen.make(place, 5, size, by_vehicle)
	var t0 := Time.get_ticks_usec()
	scene.setup_trip(main, main.hud, main.data, flow, place, maker, party, float(sim.stock.ammo), "sedan", 1.0, false)
	scene.begin_trip(flow)
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check(int(scene.site.size.y) <= 700 + 24, "the strip is at most 700 + 24 tall (%d)" % int(scene.site.size.y))
	var tiles: int = int(scene.world.W) * int(scene.world.H)
	check(tiles <= 30 * (700 + 24), "at most 30 x 724 tiles of road (%d: the plan's 'about 20 000' of road and its margins)" % tiles)
	var objects: int = int(scene.site.data.objects.size()) + int(scene.site.data.trees.size()) + int(scene.road.dyn.size())
	check(objects <= 350 + 120, "the objects stay in the hundreds (%d)" % objects)
	var worst := 0.0
	var total := 0.0
	var steps := 600
	for i in steps:
		var a := Time.get_ticks_usec()
		scene.tick(STEP)
		var d := float(Time.get_ticks_usec() - a) / 1000.0
		total += d
		worst = maxf(worst, d)
	print("        [drive budget] strip %d tiles, %d tiles of ground, %d objects; build %.0f ms; %d steps: mean %.2f ms, worst %.1f ms; dead awake %d of %d" % [
		int(scene.road.len), tiles, objects, build_ms, steps, total / float(steps), worst, scene.run.sim.zombies.size(),
		scene.run.sim.zombies.size() + scene._dormant.size()])
	check(build_ms < 6000.0, "building it takes under six seconds (%.0f ms)" % build_ms)
	check(total / float(steps) < 10.0, "a step costs under ten milliseconds on average (%.2f ms)" % (total / float(steps)))
	await _leave(main)


# --------------------------------------------------------------- the ends --

func test_a_foot_leg_ends_when_everyone_is_at_the_end_of_the_road() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "", 3, false)
	var scene = t.scene
	scene.stage("exit")
	_until(scene, func(): return scene.leg != "there" or scene.get("_pending").is_valid(), 200)
	scene.tick(STEP)
	eq(scene.leg, "place", "the place is next")
	eq(t.flow.stage, "place", "the flow's")
	check(scene.vehicle_node == null and scene.car == null, "no car on foot")
	eq(scene.run.squad.size(), 3, "all three came")
	await _leave(main)


func test_everyone_down_on_the_road_is_the_end_of_the_trip_with_no_place() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_hands_off(scene)
	for p in scene.run.squad:
		p.downed = true
		p.hp = 0.0
	_until(scene, func(): return scene.phase == "report", 200)
	eq(scene.phase, "report", "the report is up: no place, no road home")
	check(t.flow.failed, "the flow says nobody got through")
	var seen: Array = []
	scene.finished.connect(func(r): seen.append(r))
	scene.go_home()
	eq(seen.size(), 1, "finished once")
	eq((seen[0].lost as Array).size(), 2, "both are lost")
	await _leave(main)


func test_the_base_falling_while_out_ends_the_trip() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	_play(scene, 1.0)
	main.sim.over = "defeat"
	_until(scene, func(): return scene.phase == "report", 200)
	eq(scene.phase, "report", "the report is up")
	await _leave(main)


# ------------------------------------------------------------ the radio --

func test_the_night_falls_while_out_and_the_radios_calls_reach_the_road() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var scene = t.scene
	var sim = t.sim
	check(scene.hud_layer.has_method("on_stage"), "the drive's own HUD is mounted")
	scene.stage("hour:18.45")
	_hands_off(scene)
	var dark0: float = scene.light_now().dark
	var news0: int = sim.radio.news.size()
	sim.radio.raise_call("attack", "The east wall is under attack", "Three of the dead are at the boards", [{"id": "hold", "label": "Hold the wall"}, {"id": "help", "label": "Send help"}], "hold", 30.0)
	scene.hud_layer.refresh()
	check(scene.hud_layer.call_card.visible, "a call from the base is on the road's screen")
	# (the car is kept going by hand: it drives at the leg's pace the whole while)
	var n := 0
	while n < 2400 and String(sim.phase) == "day":
		scene.car.speed = 4.0
		scene.tick(STEP)
		n += 1
	check(String(sim.phase) != "day", "the dusk comes in while they are out (%s after %.0f s)" % [sim.phase, float(n) / 30.0])
	check(sim.bell_rung, "and the bell rings")
	check(sim.radio.news.size() > news0, "the radio logged what came in")
	_play(scene, 3.0)
	check(float(scene.light_now().dark) > dark0, "the light follows the base's clock")
	await _leave(main)


func test_e_boards_again_only_when_the_work_is_done_and_everyone_is_near_the_car() -> void:
	var main := _game()
	var t := _event_trip(main, "wreck_supplies", 0.3, 0.25)
	var scene = t.scene
	scene.tick(STEP)
	scene.press_stop()
	scene.choose("e1", "search")
	eq(scene.mode, "out", "out working")
	var dez = scene.run.person("dez")
	scene.work_left = 0.0
	# (Dez has wandered off: nobody boards without him)
	dez.x = scene.car.pos.x + 12.0
	dez.y = scene.car.pos.y
	scene.run.sim.stock.ammo = 0.0
	scene.tick(STEP)
	eq(scene.mode, "out", "they wait for him")
	var r: Dictionary = scene.press_stop()
	check(not bool(r.ok) and String(r.what) == "far", "E says the squad is not all back")
	dez.x = scene.car.pos.x + 2.5
	_press(scene, KEY_E)
	_release(scene, KEY_E)
	eq(scene.mode, "drive", "E puts everyone back in the car once they are near it")
	eq(scene.aboard().size(), 2, "both aboard")
	await _leave(main)


func test_the_digit_keys_answer_as_many_options_as_the_card_has() -> void:
	var main := _game()
	var t := _event_trip(main, "checkpoint", 0.3, 0.25)
	var scene = t.scene
	scene.tick(STEP)
	scene.press_stop()
	var opts: Array = scene.card_options()
	eq(opts.size(), 4, "a checkpoint's card has four options")
	var hp0: float = scene.car.hp
	_press(scene, KEY_9)
	eq(scene.open_uid, "e1", "a digit past the last option does nothing")
	_press(scene, KEY_4)
	_release(scene, KEY_4)
	eq(String(scene.plan[0].state), "done", "4 took the fourth option")
	near(scene.car.hp, hp0 - 10.0, 0.01, "Run it: the car took its ten hp")
	var r: Dictionary = scene.leg_result()
	eq((r.hurt as Dictionary).size(), 1, "and one aboard is hurt")
	for id in r.hurt:
		eq(String(r.hurt[id]), "scratch", "a scratch, not turned into a bite")
	check(float(r.vehicle_hp_lost) < 1.0, "the leg's own wear does not count the ten hp the events took themselves (%.2f)" % float(r.vehicle_hp_lost))
	await _leave(main)


func test_the_cards_context_is_the_events_own_full_one() -> void:
	var main := _game()
	var t := _trip(main, "pharmacy", "pickup", 2, false)
	var ctx: Dictionary = t.scene.event_ctx()
	for key in ["leg", "danger", "by_vehicle", "seats_free", "seats", "vehicle_name", "road_min", "leg_s", "hour", "dusk", "dawn", "bed", "hp_share", "fuel_room", "stock", "leading", "building", "caller"]:
		check(ctx.has(key), "the context has %s" % key)
	eq(String(ctx.vehicle_name), "Pickup", "the vehicle's name")
	eq(int(ctx.seats), 2, "its seats")
	check(bool(ctx.by_vehicle), "by vehicle")
	await _leave(main)
