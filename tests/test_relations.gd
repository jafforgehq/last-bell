extends "res://tests/case.gd"
## Relations (round 20, scripts/sim/relations.gd, assets/data/chemistry.json): who is close to whom, as one number a
## pair (-100 to 100), from the roster's bonds and from what people do together. Kinds (friend, partner, rival) begin
## and end with hysteresis and respect the caps; the player's own pairs never move; with no avatar (or on Orientation
## Day, or in the classic six start) nothing here runs. The hooks into the other modules are in
## test_relations_hooks.gd.

const Helpers := preload("res://tests/helpers.gd")
const Relations := preload("res://scripts/sim/relations.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")

const CHEMISTRY := "res://assets/data/chemistry.json"


# ----------------------------------------------------------------- helpers --

func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## A settlement game with an avatar (Ruth), everybody far from everybody (a row 9 tiles apart), nobody working, a
## quiet morning of day 3, and the other two community modules off (so that nothing else writes to the News or moves a pair).
func _game(crew: int = 6) -> Dictionary:
	var g := Helpers.make(1, 1, crew)
	var sim = g.sim
	sim.recruits.small = true    # (a classic six start has none of this)
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.initiative.enabled = false
	sim.specialists.enabled = false
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	Helpers.no_work(sim)
	_at(sim, 3, 9.0)
	_apart(sim)
	sim.events.clear()
	return g


func _at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day


func _place(p, x: float, y: float) -> void:
	p.x = x
	p.y = y
	p.moving = false
	p.path = []
	p.goal_key = ""


func _apart(sim) -> void:
	var i := 0
	for p in sim.people:
		_place(p, 4.0 + 9.0 * float(i), 10.0)
		i += 1


## `b` stands `gap` tiles to the east of `a`, still.
func _beside(a, b, gap: float = 1.5) -> void:
	_place(b, a.x + gap, a.y)


func _news_of(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


func _chemistry() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CHEMISTRY))


func _firsts(list: Array) -> Array:
	var out: Array = []
	for p in list:
		out.append(p.first)
	return out


# ------------------------------------------------------------------ the roster --

func test_a_roster_bond_starts_at_its_anchor() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	near(r.affinity("dez", "hector"), Relations.ANCHOR.friend, 0.0001, "Dez and Hector are friends")
	near(r.affinity(_p(sim, "ruth"), _p(sim, "marcus")), Relations.ANCHOR.family, 0.0001, "Ruth and Marcus are family (people or ids)")
	near(r.affinity("marcus", "ruth"), Relations.ANCHOR.family, 0.0001, "the order does not matter")
	near(r.affinity("walt", "marcus"), Relations.ANCHOR.mentor, 0.0001, "Walt is Marcus's mentor")
	near(r.affinity("ana", "ruth"), Relations.ANCHOR.friend, 0.0001, "Ana and Ruth")
	eq(r.kind("dez", "hector"), "friend", "a roster bond is a friend pair")
	eq(r.word("dez", "hector"), "friends", "and 55 reads 'friends'")
	near(r.affinity("dez", "walt"), 0.0, 0.0001, "no record, no feeling")
	eq(r.kind("dez", "walt"), "", "no kind")
	eq(r.kind("nobody", "dez"), "", "an unknown id has none")
	near(r.affinity("nobody", "dez"), 0.0, 0.0001, "and no number")
	g.world.free()


func test_a_roster_bond_never_drifts_under_its_floor_but_an_event_can_break_it() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.look()    # (the first look takes the day as it is)
	for d in range(4, 70):
		sim.day = d
		r.look()
	near(r.affinity("dez", "hector"), Relations.ANCHOR_FLOOR, 0.0001, "55 less a point a day stops at the floor")
	eq(r.kind("dez", "hector"), "friend", "still friends")
	r.add("dez", "hector", -30.0, "A bitter row")
	near(r.affinity("dez", "hector"), Relations.ANCHOR_FLOOR - 30.0, 0.0001, "an event goes through the floor")
	sim.day = 70
	r.look()
	near(r.affinity("dez", "hector"), Relations.ANCHOR_FLOOR - 31.0, 0.0001, "and the bond is broken: nothing holds it up any more")
	g.world.free()


func test_a_late_caller_brings_the_roster_bonds_with_them() -> void:
	var g := _game(5)
	var sim = g.sim
	var r = sim.relations
	eq(sim.recruits.queue.size(), 1, "Hector waits at the radio")
	r.look()
	near(r.affinity("dez", "hector"), 0.0, 0.0001, "someone who is not here has no pairs")
	var def: Dictionary = sim.recruits.queue.pop_front()
	var hector = sim.add_person(def)
	_place(hector, 60.0, 30.0)
	near(r.affinity("dez", "hector"), Relations.ANCHOR.friend, 0.0001, "he arrives with the bond the roster gives him")
	eq(r.kind("dez", "hector"), "friend", "a friend")
	eq(_news_of(sim, "bond").size(), 0, "a roster bond is no news")
	g.world.free()


# ----------------------------------------------------------------------- kinds --

func test_a_friendship_begins_at_35_and_ends_under_20() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "walt", Relations.FRIEND_AT - 1.0, "x")
	eq(r.kind("dez", "walt"), "", "34 is not yet")
	r.add("dez", "walt", 2.0, "x")
	eq(r.kind("dez", "walt"), "friend", "36 is")
	r.add("dez", "walt", -15.0, "x")
	eq(r.kind("dez", "walt"), "friend", "21 is still (it ends under 20)")
	r.add("dez", "walt", -2.0, "x")
	eq(r.kind("dez", "walt"), "", "19 is not")
	r.add("dez", "walt", 12.0, "x")
	eq(r.kind("dez", "walt"), "", "31 does not begin again (it begins at 35)")
	g.world.free()


func test_a_rivalry_begins_at_minus_35_and_ends_over_minus_20() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "walt", Relations.RIVAL_AT + 1.0, "x")
	eq(r.kind("dez", "walt"), "", "-34 is not yet")
	r.add("dez", "walt", -2.0, "x")
	eq(r.kind("dez", "walt"), "rival", "-36 is")
	r.add("dez", "walt", 15.0, "x")
	eq(r.kind("dez", "walt"), "rival", "-21 is still")
	r.add("dez", "walt", 2.0, "x")
	eq(r.kind("dez", "walt"), "", "-19 is over")
	g.world.free()


func test_a_couple_needs_85_and_five_days_of_friendship_and_ends_under_60() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "ana", 90.0, "x")
	eq(r.kind("dez", "ana"), "friend", "90 on day 3: friends first")
	sim.day = 3 + Relations.PARTNER_DAYS - 1
	r.add("dez", "ana", 1.0, "x")
	eq(r.kind("dez", "ana"), "friend", "four days is not five")
	sim.day = 3 + Relations.PARTNER_DAYS
	r.add("dez", "ana", 1.0, "x")
	eq(r.kind("dez", "ana"), "partner", "five days is (92)")
	eq(r.partner_of(_p(sim, "dez")), _p(sim, "ana"), "Ana is Dez's partner")
	eq(r.partner_of(_p(sim, "ana")), _p(sim, "dez"), "and he is hers")
	eq(r.word("dez", "ana"), "partners", "the word")
	r.add("dez", "ana", -30.0, "x")
	eq(r.kind("dez", "ana"), "partner", "62 is still a couple (it ends under 60)")
	r.add("dez", "ana", -3.0, "x")
	eq(r.kind("dez", "ana"), "friend", "59: friends again")
	check(r.partner_of(_p(sim, "dez")) == null, "no partner now")
	g.world.free()


func test_family_and_mentors_do_not_become_couples() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	sim.day = 30
	r.add("walt", "marcus", 100.0, "x")
	eq(r.kind("walt", "marcus"), "friend", "a mentor and his student stay friends however close")
	g.world.free()


func test_nobody_has_more_than_three_friends_and_a_fourth_does_not_take_a_stronger_ones_place() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	# Dez: Hector (55, the roster), then Walt 50, Marcus 45, and Ana 40 as the fourth
	r.add("dez", "walt", 50.0, "x")
	r.add("dez", "marcus", 45.0, "x")
	eq(_firsts(r.friends_of(_p(sim, "dez"))), ["Hector", "Walt", "Marcus"], "three friends, the strongest first")
	r.add("dez", "ana", 40.0, "x")
	eq(r.kind("dez", "ana"), "", "a fourth, weaker than all three, has no slot")
	eq(_firsts(r.friends_of(_p(sim, "dez"))), ["Hector", "Walt", "Marcus"], "nobody lost theirs")
	near(r.affinity("dez", "ana"), 40.0, 0.0001, "(the number is still hers)")
	r.add("dez", "ana", 10.0, "x")    # 50: stronger than Marcus, level with Walt
	eq(r.kind("dez", "ana"), "friend", "stronger than the weakest holder: she takes the slot")
	eq(r.kind("dez", "marcus"), "", "and Marcus gives it up")
	eq(_firsts(r.friends_of(_p(sim, "dez"))), ["Hector", "Ana", "Walt"], "Hector 55, then Ana and Walt at 50 (the id breaks the tie)")
	var count := 0
	for q in sim.people:
		if r.kind("dez", q) == "friend":
			count += 1
	eq(count, 3, "three, no more")
	g.world.free()


func test_nobody_has_more_than_two_rivals() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "walt", -40.0, "x")
	r.add("dez", "marcus", -45.0, "x")
	r.add("dez", "ana", -50.0, "x")
	eq(_firsts(r.rivals_of(_p(sim, "dez"))), ["Ana", "Marcus"], "the two worst, the strongest first")
	eq(r.kind("dez", "walt"), "", "the weakest lost it")
	g.world.free()


func test_a_person_has_one_partner_the_strongest() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "ana", 88.0, "x")
	r.add("walt", "ana", 95.0, "x")
	sim.day = 20
	r.add("dez", "ana", 1.0, "x")    # (re-read: Dez and Ana qualify, but Ana's strongest tie is Walt)
	r.add("walt", "ana", 1.0, "x")
	var partners := 0
	for q in sim.people:
		if r.kind("ana", q) == "partner":
			partners += 1
	eq(partners, 1, "Ana has one partner")
	eq(r.partner_of(_p(sim, "ana")), _p(sim, "walt"), "the stronger tie")
	g.world.free()


func test_after_a_loss_nobody_takes_a_new_partner_for_ten_days() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "ana", 90.0, "x")
	sim.day = 10
	r.add("dez", "ana", 1.0, "x")
	eq(r.kind("dez", "ana"), "partner", "a couple")
	sim.medical.kill(_p(sim, "dez"), "bled out")
	r.add("ana", "walt", 90.0, "x")
	sim.day = 10 + Relations.PARTNER_REST_DAYS - 1
	r.add("ana", "walt", 1.0, "x")
	check(r.kind("ana", "walt") != "partner", "nine days on she is still grieving")
	sim.day = 10 + Relations.PARTNER_REST_DAYS
	r.add("ana", "walt", 1.0, "x")
	eq(r.kind("ana", "walt"), "partner", "ten days on she may")
	g.world.free()


# ------------------------------------------------------------------- the words --

func test_the_words_follow_the_number() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "walt", -70.0, "x")
	eq(r.word("dez", "walt"), "enemies", "-70")
	r.add("dez", "walt", 30.0, "x")
	eq(r.word("dez", "walt"), "at odds", "-40")
	r.add("dez", "walt", 25.0, "x")
	eq(r.word("dez", "walt"), "wary", "-15")
	r.add("dez", "walt", 15.0, "x")
	eq(r.word("dez", "walt"), "", "0 says nothing")
	r.add("dez", "walt", 15.0, "x")
	eq(r.word("dez", "walt"), "friendly", "15")
	r.add("dez", "walt", 25.0, "x")
	eq(r.word("dez", "walt"), "friends", "40")
	r.add("dez", "walt", 30.0, "x")
	eq(r.word("dez", "walt"), "close", "70")
	g.world.free()


# ------------------------------------------------------------------ the moves --

func test_working_at_one_station_warms_a_pair() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	check(Helpers.seat(sim, _p(sim, "dez"), "bench"), "Dez at the bench")
	check(Helpers.seat(sim, _p(sim, "walt"), "bench"), "Walt at the bench")
	r.look()
	# (they sit 1.1 tiles apart and still: the shared place counts as well)
	near(r.affinity("dez", "walt"), Relations.STATION_GAIN + Relations.NEAR_GAIN, 0.0001, "a station look and a shared place")
	near(r.affinity("dez", "marcus"), 0.0, 0.0001, "nobody else moved")
	g.world.free()


func test_two_people_at_different_stations_do_not_work_together() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	check(Helpers.seat(sim, _p(sim, "dez"), "bench"), "Dez at the bench")
	check(Helpers.seat(sim, _p(sim, "walt"), "builders"), "Walt at the builders")
	r.look()
	near(r.affinity("dez", "walt"), 0.0, 0.0001, "no gain")
	g.world.free()


func test_a_pair_that_stands_still_within_2_6_tiles_warms() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	_beside(dez, walt, 2.5)
	r.look()
	near(r.affinity("dez", "walt"), Relations.NEAR_GAIN, 0.0001, "within 2.6 and still")
	walt.moving = true
	r.look()
	near(r.affinity("dez", "walt"), Relations.NEAR_GAIN, 0.0001, "walking: no more")
	walt.moving = false
	_beside(dez, walt, 2.7)
	r.look()
	near(r.affinity("dez", "walt"), Relations.NEAR_GAIN, 0.0001, "2.7 tiles apart: no more")
	g.world.free()


func test_someone_who_is_down_or_away_gains_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	_beside(dez, walt)
	walt.downed = true
	r.look()
	near(r.affinity("dez", "walt"), 0.0, 0.0001, "down")
	walt.downed = false
	walt.away = {"kind": "party", "n": 99}
	r.look()
	near(r.affinity("dez", "walt"), 0.0, 0.0001, "away")
	g.world.free()


func test_night_posts_side_by_side_warm_a_pair() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	sim.jobs.post_ids.clear()
	check(sim.jobs.set_post(dez, "north_west"), "Dez on the north wall, west")
	check(sim.jobs.set_post(walt, "barricade"), "Walt at the barricade, 4.2 tiles along")
	_at(sim, 3, 22.0)
	r.look()
	near(r.affinity("dez", "walt"), Relations.POST_GAIN, 0.0001, "posts within 5.2 tiles at night")
	check(sim.jobs.set_post(walt, "bus"), "Walt on the bus, far along")
	var before: float = r.affinity("dez", "walt")
	r.look()
	near(r.affinity("dez", "walt"), before, 0.0001, "far posts: nothing")
	_at(sim, 3, 9.0)
	check(sim.jobs.set_post(walt, "barricade"), "back beside Dez")
	r.look()
	near(r.affinity("dez", "walt"), before, 0.0001, "by day: nothing")
	g.world.free()


func test_a_meal_shared_warms_a_pair_that_sat_close() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	_beside(dez, walt)
	dez.moving = true    # (so that only the meal counts)
	_at(sim, 3, 12.8)
	r.look()
	near(r.affinity("dez", "walt"), 0.0, 0.0001, "no meal yet")
	_at(sim, 3, 13.2)
	r.look()
	near(r.affinity("dez", "walt"), Relations.MEAL_GAIN, 0.0001, "the look that crosses 13:00")
	near(r.affinity("dez", "marcus"), 0.0, 0.0001, "(and only the pair that sat together)")
	near(r.affinity("marcus", "ana"), 0.0, 0.0001, "(the others were far apart)")
	_at(sim, 3, 13.6)
	r.look()
	near(r.affinity("dez", "walt"), Relations.MEAL_GAIN, 0.0001, "once")
	g.world.free()


func test_hunger_frays_tempers_between_people_together() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	_beside(dez, walt)
	dez.moving = true
	walt.moving = true
	r.look()
	near(r.affinity("dez", "walt"), 0.0, 0.0001, "well fed and watered")
	dez.hunger_h = 20.0
	r.look()
	near(r.affinity("dez", "walt"), Relations.SCARCE_LOSS, 0.0001, "one is hungry")
	dez.hunger_h = 0.0
	walt.thirst_h = 15.0
	r.look()
	near(r.affinity("dez", "walt"), 2.0 * Relations.SCARCE_LOSS, 0.0001, "or thirsty")
	g.world.free()


func test_the_gain_shrinks_toward_the_ends() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	_beside(dez, walt)
	r.add("dez", "walt", 60.0, "x")
	r.look()
	near(r.affinity("dez", "walt"), 60.0 + Relations.NEAR_GAIN * (1.0 - 60.0 / 120.0), 0.0001, "half as much at 60")
	g.world.free()


func test_an_optimist_warms_faster_and_a_nervous_tough_pair_frays() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var chem := _chemistry()
	var warm: Dictionary = chem.warm
	check(float(warm.optimist) > 1.0 and float(warm.nervous) < 1.0, "the data: optimists warm, the nervous do not")
	var ana = _p(sim, "ana")    # triage, optimist
	var walt = _p(sim, "walt")    # steady hands, sharp eyed
	_beside(ana, walt)
	r.look()
	near(r.affinity("ana", "walt"), Relations.NEAR_GAIN * float(warm.optimist), 0.0001, "an optimist's gain is scaled")
	# Marcus is nervous, Dez is tough: the friction costs more than the shared place gives
	var marcus = _p(sim, "marcus")
	var dez = _p(sim, "dez")
	_apart(sim)
	_beside(marcus, dez)
	var per_look := 0.0
	for e in chem.friction:
		if (e.a == "nervous" and e.b == "tough") or (e.a == "tough" and e.b == "nervous"):
			per_look = float(e.per_look)
	check(per_look < 0.0, "the data has a nervous and tough friction")
	r.look()
	near(r.affinity("marcus", "dez"), Relations.NEAR_GAIN * float(warm.nervous) + per_look, 0.0001, "the friction term")
	g.world.free()


func test_a_warm_pairing_adds_its_term() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var chem := _chemistry()
	var per_look := 0.0
	for e in chem.warmth:
		if (e.a == "nervous" and e.b == "steady") or (e.a == "steady" and e.b == "nervous"):
			per_look = float(e.per_look)
	check(per_look > 0.0, "the data has a nervous and steady warmth")
	var marcus = _p(sim, "marcus")    # nervous
	var hector = _p(sim, "hector")    # tough, steady
	_apart(sim)
	_beside(marcus, hector)
	# (Marcus and Hector: nervous with tough frays, nervous with steady warms: both terms)
	var fric := 0.0
	for e in chem.friction:
		if (e.a == "nervous" and e.b == "tough") or (e.a == "tough" and e.b == "nervous"):
			fric = float(e.per_look)
	var mult := float(chem.warm.nervous) * float(chem.warm.steady)
	r.look()
	near(r.affinity("marcus", "hector"), Relations.NEAR_GAIN * mult + per_look + fric, 0.0001, "both terms")
	g.world.free()


func test_a_pair_that_never_meets_gets_no_chemistry() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.look()
	near(r.affinity("marcus", "dez"), 0.0, 0.0001, "apart: nothing, however they are made")
	g.world.free()


func test_every_pair_loses_a_point_a_day_toward_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "walt", 10.0, "x")
	r.add("marcus", "ana", -4.0, "x")
	r.add("dez", "ana", 0.4, "x")
	r.look()    # (the day is taken as it is)
	near(r.affinity("dez", "walt"), 10.0, 0.0001, "the same day")
	sim.day = 4
	r.look()
	near(r.affinity("dez", "walt"), 9.0, 0.0001, "10 becomes 9")
	near(r.affinity("marcus", "ana"), -3.0, 0.0001, "-4 becomes -3")
	near(r.affinity("dez", "ana"), 0.0, 0.0001, "0.4 becomes nothing")
	r.look()
	near(r.affinity("dez", "walt"), 9.0, 0.0001, "once a day")
	g.world.free()


func test_the_players_own_pairs_never_move() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var ruth = _p(sim, "ruth")
	var dez = _p(sim, "dez")
	var ana = _p(sim, "ana")
	_beside(ruth, dez)
	_place(ana, ruth.x, ruth.y + 1.0)
	r.add("ruth", "dez", 20.0, "x")
	near(r.affinity("ruth", "dez"), 0.0, 0.0001, "add() leaves the player's pairs alone")
	r.look()
	near(r.affinity("ruth", "dez"), 0.0, 0.0001, "so does a look")
	near(r.affinity("ruth", "ana"), Relations.ANCHOR.friend, 0.0001, "the stored value stays")
	sim.day = 6
	r.look()
	near(r.affinity("ruth", "ana"), Relations.ANCHOR.friend, 0.0001, "even through the days")
	g.world.free()


func test_trips_and_rescues_bring_people_closer() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	var ana = _p(sim, "ana")
	r.on_trip([dez, walt], [], {"result": {"hurt": {}}})
	near(r.affinity("dez", "walt"), Relations.TRIP_GAIN, 0.0001, "a trip together")
	r.on_trip([dez, ana], [], {"result": {"hurt": {"ana": "bite"}}})
	near(r.affinity("dez", "ana"), Relations.TRIP_GAIN + Relations.TRIP_HURT_GAIN, 0.0001, "with someone hurt, more")
	r.on_trip([dez], [walt], {"result": {"hurt": {}}})
	near(r.affinity("dez", "walt"), Relations.TRIP_GAIN, 0.0001, "a lone survivor has no pairs, and the lost one earns none")
	r.on_treated(ana, walt, "bandage")
	near(r.affinity("ana", "walt"), Relations.RESCUE_GAIN, 0.0001, "a bandage")
	walt.downed = true
	r.on_treated(dez, walt, "bandage")
	near(r.affinity("dez", "walt"), Relations.TRIP_GAIN + Relations.RESCUE_GAIN + Relations.RESCUE_DOWNED_GAIN, 0.0001, "and more for one who was down")
	g.world.free()


# ------------------------------------------------------------ nothing, inactive --

func test_inactive_means_nothing_moves_and_nothing_answers() -> void:
	for how in ["disabled", "no avatar", "classic start"]:
		var g := _game()
		var sim = g.sim
		var r = sim.relations
		var dez = _p(sim, "dez")
		var walt = _p(sim, "walt")
		_beside(dez, walt)
		match how:
			"disabled":
				r.enabled = false
			"no avatar":
				sim.avatar.set_player(null)
			"classic start":
				sim.recruits.small = false
		check(not r.active(), "%s: inactive" % how)
		var news: int = sim.radio.news.size()
		var trust := float(dez.trust)
		r.look()
		r.add("dez", "walt", 50.0, "x")
		r.on_trip([dez, walt], [], {"result": {"hurt": {}}})
		r.on_treated(dez, walt, "bandage")
		r.on_lost(walt, "died")
		r.on_downed(walt)
		r.on_trust_moved(dez, -6.0)
		r.update(100.0)
		eq(r.looks, 0, "%s: no looks" % how)
		near(r.affinity("dez", "walt"), 0.0, 0.0001, "%s: no pair" % how)
		eq(r.kind("dez", "hector"), "", "%s: no kind" % how)
		eq(r.word("dez", "hector"), "", "%s: no word" % how)
		eq(r.circle(dez), [], "%s: no circle" % how)
		eq(r.friends_of(dez), [], "%s: no friends" % how)
		eq(r.rivals_of(dez), [], "%s: no rivals" % how)
		check(r.partner_of(dez) == null, "%s: no partner" % how)
		check(r.voice() == null, "%s: no voice" % how)
		check(not r.is_close(dez, _p(sim, "hector")), "%s: not close" % how)
		check(r.rival_near(dez) == null, "%s: no rival near" % how)
		eq(r.company_pull(dez, "come"), 0.0, "%s: no pull" % how)
		eq(r.company_reason(dez, "come"), "", "%s: no reason" % how)
		eq(r.fit_adjust(dez, "bench"), 0.0, "%s: no fit" % how)
		eq(r.succession_bonus(dez), 0.0, "%s: no succession bonus" % how)
		eq(r.grief_mult(dez, walt), 1.0, "%s: no grief factor" % how)
		eq(r.standing(dez), 0.0, "%s: no standing" % how)
		eq(r.describe(dez), {}, "%s: no description" % how)
		eq(r.recent_loss(), {}, "%s: no loss remembered" % how)
		eq(sim.radio.news.size(), news, "%s: nothing in the News" % how)
		eq(float(dez.trust), trust, "%s: trust untouched" % how)
		g.world.free()


# ---------------------------------------------------------------------- queries --

func test_friends_rivals_and_partners_are_listed_strongest_first_and_only_the_living() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	r.add("dez", "walt", 40.0, "x")
	r.add("dez", "marcus", 60.0, "x")
	r.add("dez", "ana", -50.0, "x")
	eq(_firsts(r.friends_of(dez)), ["Marcus", "Hector", "Walt"], "Marcus 60, Hector 55, Walt 40")
	eq(_firsts(r.rivals_of(dez)), ["Ana"], "Ana")
	sim.medical.kill(_p(sim, "marcus"), "bled out")
	eq(_firsts(r.friends_of(dez)), ["Hector", "Walt"], "the dead are not friends")
	var away = _p(sim, "walt")
	away.away = {"kind": "party", "n": 5}
	eq(_firsts(r.friends_of(dez)), ["Hector", "Walt"], "someone away still is")
	g.world.free()


func test_the_circle_lists_only_what_the_roster_does_not() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	eq(r.circle(dez), [], "Dez's only friend, Hector, is in the roster")
	r.add("dez", "walt", 50.0, "x")
	var c: Array = r.circle(dez)
	eq(c.size(), 1, "Walt is new")
	eq(c[0].who, _p(sim, "walt"), "who")
	eq(c[0].role, "friend", "role")
	eq(c[0].kind, "friend", "kind")
	r.add("dez", "ana", 90.0, "x")
	sim.day = 20
	r.add("dez", "ana", 1.0, "x")
	var roles := {}
	for e in r.circle(dez):
		roles[e.who.first] = e.role
	eq(roles, {"Walt": "friend", "Ana": "partner"}, "a partner is a role of its own")
	var bonds_of: Array = sim.bonds.of(dez)
	var seen := []
	for b in bonds_of:
		seen.append(b.who.first)
	seen.sort()
	eq(seen, ["Ana", "Hector", "Walt"], "bonds.of is the roster plus the circle")
	g.world.free()


func test_the_description_for_the_views() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var marcus = _p(sim, "marcus")
	r.add("marcus", "dez", -45.0, "A row")
	var d: Dictionary = r.describe(marcus)
	var friends := []
	for f in d.friends:
		friends.append("%s:%s" % [f.first, f.kind])
	friends.sort()
	eq(friends, ["Ruth:family", "Walt:mentor"], "his roster ties, named for what they are")
	eq(d.rivals.size(), 1, "one rival")
	eq(d.rivals[0].first, "Dez", "Dez")
	eq(d.rivals[0].id, "dez", "with his id")
	eq(d.rivals[0].word, "at odds", "and the word")
	check(d.rivals[0].value < 0.0, "and the number")
	eq(d.partner, {}, "no partner")
	check(d.lines.has("At odds with Dez"), "a line for the rival: %s" % str(d.lines))
	var close := ""
	for line in d.lines:
		if String(line).begins_with("Close to"):
			close = line
	check(close.contains("Ruth (family)") and close.contains("Walt (mentor)"), "a line for the close ones: %s" % close)
	r.add("dez", "ana", 90.0, "x")
	sim.day = 20
	r.add("dez", "ana", 1.0, "x")
	var dd: Dictionary = r.describe(_p(sim, "dez"))
	eq(dd.partner.first, "Ana", "Dez's partner")
	check(dd.lines.has("Together with Ana"), "and its line: %s" % str(dd.lines))
	g.world.free()


# ---------------------------------------------------------- standing, the voice --

func test_standing_is_leading_friends_a_partner_and_warmth_less_rivals() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var walt = _p(sim, "walt")    # Leading 5, mentor of Marcus (a friend pair of 50)
	var lead := float(walt.skills.get("Leading", 0))
	near(r.standing(walt), 2.0 * lead + 12.0 + 0.3 * Relations.ANCHOR.mentor, 0.0001, "his Leading, one friend and the warmth of that tie")
	r.add("walt", "dez", 40.0, "x")
	near(r.standing(walt), 2.0 * lead + 24.0 + 0.3 * (Relations.ANCHOR.mentor + 40.0), 0.0001, "two friends")
	r.add("walt", "ana", -40.0, "x")
	near(r.standing(walt), 2.0 * lead + 24.0 + 0.3 * (Relations.ANCHOR.mentor + 40.0) - 8.0, 0.0001, "less a rival")
	r.add("walt", "hector", 90.0, "x")
	sim.day = 30
	r.add("walt", "hector", 1.0, "x")
	eq(r.kind("walt", "hector"), "partner", "a partner")
	near(r.standing(walt), 2.0 * lead + 24.0 + 10.0 + 0.3 * (Relations.ANCHOR.mentor + 40.0 + 91.0) - 8.0, 0.0001, "and ten for a partner")
	for p in sim.people:
		var s: float = r.standing(p)
		check(s >= 0.0 and s <= 100.0, "%s: %s is inside 0 to 100" % [p.first, str(s)])
	g.world.free()


func test_the_voice_is_the_best_standing_over_40_and_sticks() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var ana = _p(sim, "ana")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	r.look()
	check(r.voice() == null, "nobody stands high enough at the start")
	r.add("ana", "dez", 50.0, "x")
	r.add("ana", "marcus", 50.0, "x")
	r.look()
	check(r.standing(ana) >= Relations.VOICE_MIN, "Ana: %s" % str(r.standing(ana)))
	for p in sim.people:
		check(p == ana or p.player or r.standing(p) < r.standing(ana), "%s stands lower than Ana" % p.first)
	eq(r.voice(), ana, "Ana is who people turn to")
	# the News says so, when the day's two lines of other news have been told
	sim.day += 1
	r.look()
	var told: Array = _news_of(sim, "bond").filter(func(e): return String(e.text) == "Ana is who people turn to now")
	eq(told.size(), 1, "the News says so")
	# Ana makes a rival: Dez is ahead of her now, but not by VOICE_SWITCH. She stays
	r.add("ana", "walt", -40.0, "x")
	sim.day += 1
	r.look()
	var gap: float = r.standing(dez) - r.standing(ana)
	check(gap > 0.0 and gap < Relations.VOICE_SWITCH, "Dez is ahead by %s" % str(gap))
	check(r.standing(marcus) < r.standing(dez), "(and he is the best of the others)")
	eq(r.voice(), ana, "sticky")
	# a second rival: now he is
	r.add("ana", "hector", -40.0, "x")
	sim.day += 1
	r.look()
	check(r.standing(dez) - r.standing(ana) >= Relations.VOICE_SWITCH, "now he is far ahead: %s" % str(r.standing(dez) - r.standing(ana)))
	eq(r.voice(), dez, "the voice changes only when beaten by VOICE_SWITCH")
	sim.day += 2
	r.look()
	var again: Array = _news_of(sim, "bond").filter(func(e): return String(e.text) == "Dez is who people turn to now")
	eq(again.size(), 1, "and the News says that too")
	sim.medical.kill(dez, "bled out")
	r.look()
	eq(r.voice(), marcus, "the voice's death passes it on to the next")
	g.world.free()


func test_the_player_is_never_the_voice() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var ruth = _p(sim, "ruth")    # Leading 9, a family tie and a friend: by the numbers the best standing there is
	check(r.standing(ruth) > r.standing(_p(sim, "ana")), "Ruth's numbers are the best: %s" % str(r.standing(ruth)))
	r.look()
	check(r.voice() != ruth, "but Ruth is the leader, not the voice")
	g.world.free()


func test_community_trust_is_the_mean_trust_of_the_others() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	near(r.community_trust(), 55.0, 0.0001, "55 at the start")
	_p(sim, "ruth").trust = 0.0
	near(r.community_trust(), 55.0, 0.0001, "the player's own number is not counted")
	_p(sim, "dez").trust = 25.0
	_p(sim, "walt").trust = 95.0
	near(r.community_trust(), (25.0 + 95.0 + 55.0 * 3.0) / 5.0, 0.0001, "the mean of the five others")
	sim.medical.kill(_p(sim, "walt"), "bled out")
	near(r.community_trust(), (25.0 + 55.0 * 3.0) / 4.0, 0.0001, "the dead are not counted")
	g.world.free()


# ------------------------------------------------------------------------ news --

func test_a_new_friendship_a_couple_and_a_rift_make_news_at_most_twice_a_day() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "walt", 40.0, "They work side by side")
	r.add("marcus", "ana", -40.0, "x")
	r.add("walt", "ana", 40.0, "x")
	var first: Array = []
	for e in sim.radio.news:
		first.append("%s:%s" % [e.kind, e.text])
	eq(first, ["bond:Dez and Walt are close now", "rift:Ana and Marcus are at odds"], "two lines, the first two kinds that began (in the crew list's order)")
	eq(sim.radio.news[0].sub, "They work side by side", "the reason is the sub")
	r.look()
	eq(sim.radio.news.size(), 2, "the same day: no more")
	sim.day = 4
	r.look()
	var texts: Array = []
	for e in sim.radio.news:
		texts.append(String(e.text))
	eq(texts.slice(2, 3), ["Ana and Walt are close now"], "the next day the third is told: late but true")
	check(sim.radio.news.size() <= 4, "and at most two lines that day (the voice's too): %s" % str(texts))
	var count: int = sim.radio.news.size()
	r.look()
	eq(sim.radio.news.size(), count, "and only once")
	for day in [3, 4]:
		var n := 0
		for e in sim.radio.news:
			if int(e.day) == day:
				n += 1
		check(n <= Relations.NEWS_PER_DAY, "day %d has %d lines" % [day, n])
	g.world.free()


func test_a_couple_is_news_of_its_own() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "ana", 90.0, "x")
	sim.day = 20
	r.add("dez", "ana", 1.0, "x")
	var texts: Array = []
	for e in sim.radio.news:
		texts.append(e.text)
	check(texts.has("Dez and Ana are together now"), "News: %s" % str(texts))
	g.world.free()


# --------------------------------------------------------------------- losses --

func test_a_loss_is_remembered_and_the_last_ones_pairs_are_kept_for_the_farewell_and_then_dropped() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	check(r.recent_loss().is_empty(), "none at first")
	r.add("dez", "ana", 90.0, "x")
	sim.day = 20
	r.add("dez", "ana", 1.0, "x")
	var ana = _p(sim, "ana")
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	sim.medical.kill(dez, "bled out")
	var loss: Dictionary = r.recent_loss()
	eq(loss.id, "dez", "who")
	eq(loss.name, "Dez", "their name")
	eq(loss.day, 20, "and the day")
	near(r.grief_mult(ana, dez), 1.3, 0.0001, "the partner grieves 30% harder")
	near(r.grief_mult(_p(sim, "walt"), dez), 1.0, 0.0001, "no one else does")
	near(r.grief_mult(hector, dez), 1.0, 0.0001, "not even a friend")
	r.look()
	near(r.affinity("dez", "ana"), 91.0, 0.0001, "the pair is still known at the next look (the farewell asks who he was close to)")
	check(r.friends_of(dez).has(hector), "his friends are still his: %s" % str(_firsts(r.friends_of(dez))))
	check(sim.bonds.bonded(hector, dez), "and are still bonded to him")
	check(r.partner_of(ana) == null, "(but the living have no partner in the dead)")
	check(not r.friends_of(hector).has(dez), "nor friend")
	sim.day = 20 + Relations.LOSS_KEEP_DAYS + 1
	r.look()
	near(r.affinity("dez", "ana"), 0.0, 0.0001, "after a while the pair is closed")
	near(r.affinity("dez", "hector"), 0.0, 0.0001, "and every other")
	# a second loss takes the place of the first: the first one's pairs go at the next look
	sim.day = 30
	r.add("walt", "hector", 50.0, "x")
	sim.medical.kill(_p(sim, "walt"), "bled out")
	r.add("marcus", "hector", 50.0, "x")
	sim.medical.kill(_p(sim, "marcus"), "bled out")
	r.look()
	eq(r.recent_loss().id, "marcus", "the last is remembered")
	near(r.affinity("walt", "hector"), 0.0, 0.0001, "the one before is forgotten")
	near(r.affinity("marcus", "hector"), 50.0, 0.0001, "the last is kept")
	g.world.free()


# ----------------------------------------------------------------- the index --

func test_the_adjacency_index_matches_a_scan_of_the_pairs() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var ids := ["ruth", "dez", "marcus", "ana", "walt", "hector"]
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			r.add(ids[i], ids[j], float(((i * 7 + j * 3) % 11) - 5) * 9.0, "x")
	_beside(_p(sim, "dez"), _p(sim, "walt"))
	r.look()
	sim.day = 9
	r.look()
	sim.medical.kill(_p(sim, "ana"), "bled out")
	r.look()
	for id in ids:
		var scan := {}
		for key in r.pairs:
			var pr: Dictionary = r.pairs[key]
			if pr.a == id:
				scan[pr.b] = key
			elif pr.b == id:
				scan[pr.a] = key
		var index: Dictionary = r._adj.get(id, {})
		var a: Array = scan.keys()
		var b: Array = index.keys()
		a.sort()
		b.sort()
		eq(b, a, "%s: the same neighbours" % id)
		for other in scan:
			eq(index.get(other), scan[other], "%s to %s: the same pair" % [id, other])
	g.world.free()


func test_the_games_own_steps_warm_a_bench_crew_over_time() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	check(Helpers.seat(sim, _p(sim, "dez"), "bench"), "Dez at the bench")
	check(Helpers.seat(sim, _p(sim, "walt"), "bench"), "Walt at the bench")
	Helpers.run(sim, 65.0)
	check(r.looks >= 6, "six slow looks in 65 seconds: %d" % r.looks)
	var want := float(r.looks) * (Relations.STATION_GAIN + Relations.NEAR_GAIN)
	check(r.affinity("dez", "walt") > want * 0.9 and r.affinity("dez", "walt") <= want + 0.0001, "about %s: %s" % [str(want), str(r.affinity("dez", "walt"))])
	g.world.free()


# --------------------------------------------------------------------- the clock --

func test_the_slow_look_comes_every_ten_seconds_of_rules_time() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.update(Relations.TICK_S - 0.1)
	eq(r.looks, 0, "not yet")
	r.update(0.2)
	eq(r.looks, 1, "now")
	r.update(Relations.TICK_S - 0.5)
	eq(r.looks, 1, "not again")
	r.update(1.0)
	eq(r.looks, 2, "and again")
	g.world.free()


func test_the_rules_never_roll_the_dice() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var state: int = sim.rng.state
	_beside(_p(sim, "dez"), _p(sim, "walt"))
	r.look()
	r.add("dez", "ana", 50.0, "x")
	r.on_trust_moved(_p(sim, "dez"), -6.0)
	for i in 4:
		sim.day += 1
		r.look()
	eq(sim.rng.state, state, "the generator has not moved")
	g.world.free()


func test_two_games_stepped_the_same_way_end_the_same() -> void:
	var a := _game()
	var b := _game()
	for g in [a, b]:
		var sim = g.sim
		Helpers.seat(sim, _p(sim, "dez"), "bench")
		Helpers.seat(sim, _p(sim, "walt"), "bench")
		Helpers.run(sim, 40.0)
	var pa: Dictionary = a.sim.relations.save().pairs
	var pb: Dictionary = b.sim.relations.save().pairs
	eq(pa, pb, "the same pairs")
	check(a.sim.relations.looks >= 3, "and a few looks were made: %d" % a.sim.relations.looks)
	a.world.free()
	b.world.free()


# ---------------------------------------------------------------------- saving --

func _via_json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func test_a_save_loads_back_to_the_same_state() -> void:
	var a := _game()
	var sa = a.sim
	var ra = sa.relations
	_beside(_p(sa, "dez"), _p(sa, "walt"))
	ra.add("dez", "walt", 42.0, "Work side by side")
	ra.add("marcus", "ana", -44.0, "A row")
	for who in ["dez", "marcus", "hector"]:
		ra.add("ana", who, 60.0, "x")
	ra.look()
	sa.day = 4
	ra.look()
	check(ra.voice() != null, "(a voice to keep)")
	var voice_id: String = ra.voice().id
	var d: Dictionary = _via_json(ra.save())
	var b := _game()
	b.sim.day = 4    # (the day it is loaded on: a pair without a kind must keep the day it has, not take this one)
	var rb = b.sim.relations
	rb.load_state(d)
	var kindless := 0
	for key in ra.pairs:
		if String(ra.pairs[key].kind) == "" and int(ra.pairs[key].since) != int(b.sim.day):
			kindless += 1
	check(kindless > 0, "(some pair has no kind and a day of its own)")
	for key in ra.pairs:
		var pa: Dictionary = ra.pairs[key]
		var pb: Dictionary = rb.pairs.get(key, {})
		check(not pb.is_empty(), "%s came back" % key)
		if pb.is_empty():
			continue
		near(float(pb.v), float(pa.v), 0.0000001, "%s: the number" % key)
		eq(pb.kind, pa.kind, "%s: the kind" % key)
		eq(pb.since, pa.since, "%s: since" % key)
		eq(pb.why, pa.why, "%s: why" % key)
		eq(pb.anchor, pa.anchor, "%s: anchored" % key)
	eq(rb.pairs.size(), ra.pairs.size(), "no more, no fewer")
	check(rb.voice() != null and rb.voice().id == voice_id, "the voice")
	eq(rb._adj.size(), ra._adj.size(), "the index is rebuilt")
	a.world.free()
	b.world.free()


func test_a_save_from_before_starts_fresh() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("dez", "walt", 50.0, "x")
	r.load_state({})
	near(r.affinity("dez", "walt"), 0.0, 0.0001, "what was there is gone")
	near(r.affinity("dez", "hector"), Relations.ANCHOR.friend, 0.0001, "the roster's bonds stand")
	eq(r.kind("dez", "hector"), "friend", "as friends")
	g.world.free()


func test_a_damaged_save_is_survived() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var bad := {
		"pairs": {
			"dez|walt": {"v": 40.0, "kind": "wizard", "since": 3, "why": "x", "day": 3},
			"ana|dez": {"v": NAN, "kind": "friend"},
			"ana|marcus": {"v": INF, "kind": "friend"},
			"dez|ghost": {"v": 50.0, "kind": "friend"},
			"walt|dez": {"v": 50.0, "kind": "friend"},
			"hector|marcus": {"v": "lots", "kind": "friend"},
			"ana|walt": {"v": 5.0, "kind": "partner", "since": -40, "anchor": true},
			"marcus|walt": 7,
			"nonsense": {"v": 10.0},
			"a|b|c": {"v": 10.0},
			"hector|walt": {"v": 500.0, "kind": "rival", "since": "yesterday", "why": 12},
			7: {"v": 3.0},
		},
		"tick": NAN,
		"decay_day": "later",
		"voice": "ghost",
		"echo": {"dez>ana": "soon", "ghost>dez": 3.0},
		"loss": {"id": "ghost", "name": 5},
		"rest": {"ana": "never"},
		"news_n": 9999,
	}
	r.load_state(bad)
	near(r.affinity("dez", "walt"), 40.0, 0.0001, "a good number is kept")
	eq(r.kind("dez", "walt"), "friend", "and its kind is worked out again, not read (40 is a friend; 'wizard' is nothing)")
	near(r.affinity("ana", "dez"), 0.0, 0.0001, "NaN is dropped")
	near(r.affinity("ana", "marcus"), 0.0, 0.0001, "infinity is dropped")
	near(r.affinity("dez", "ghost"), 0.0, 0.0001, "an unknown id is dropped")
	near(r.affinity("hector", "marcus"), 0.0, 0.0001, "a word for a number is dropped")
	near(r.affinity("ana", "walt"), 5.0, 0.0001, "a small number")
	eq(r.kind("ana", "walt"), "", "its kind is not 'partner' because the file says so")
	near(r.affinity("hector", "walt"), 100.0, 0.0001, "clamped to the end")
	eq(r.kind("hector", "walt"), "friend", "a kind that fits the number, not the word")
	for key in r.pairs:
		var pr: Dictionary = r.pairs[key]
		check(is_finite(float(pr.v)) and absf(float(pr.v)) <= 100.0, "%s is a sound number" % key)
		check(not pr.anchor or ["dez|hector", "marcus|ruth", "marcus|walt", "ana|ruth"].has(key), "%s is no roster bond, so no anchor" % key)
	check(r.voice() == null or sim.people.has(r.voice()), "the voice is somebody here")
	check(r.recent_loss().is_empty() or sim.people.any(func(p): return p.id == r.recent_loss().id), "no loss of a ghost")
	r.look()    # (and it plays on)
	g.world.free()


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world}


func test_the_game_saves_and_loads_the_module_with_everything_else() -> void:
	var a := _game(5)
	var sa = a.sim
	var ra = sa.relations
	_beside(_p(sa, "dez"), _p(sa, "walt"))
	ra.add("dez", "walt", 45.0, "x")
	ra.look()
	var d := SaveGame.to_dict(sa)
	check(d.modules.has("relations"), "the sim's modules include it")
	var text := SaveGame.to_text(d)
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(text)), "it applies")
	near(b.sim.relations.affinity("dez", "walt"), ra.affinity("dez", "walt"), 0.0000001, "the pair")
	eq(b.sim.relations.kind("dez", "walt"), "friend", "its kind")
	check(b.sim.relations.active(), "and the avatar and the small start came back with it")
	# a save made by a game that had no such module loads as a fresh start
	d.modules.erase("relations")
	var c := _bare()
	check(SaveGame.apply(c.sim, SaveGame.from_text(SaveGame.to_text(d))), "a save from before applies")
	near(c.sim.relations.affinity("walt", "marcus"), Relations.ANCHOR.mentor, 0.0001, "with the roster's bonds")
	near(c.sim.relations.affinity("dez", "walt"), 0.0, 0.0001, "and nothing else")
	a.world.free()
	b.world.free()
	c.world.free()


func test_a_game_loaded_from_a_save_goes_on_the_same() -> void:
	var a := _game()
	var sa = a.sim
	check(Helpers.seat(sa, _p(sa, "dez"), "bench"), "Dez at the bench")
	check(Helpers.seat(sa, _p(sa, "walt"), "bench"), "Walt at the bench")
	sa.relations.add("ana", "marcus", 38.0, "x")
	Helpers.run(sa, 25.0)
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sa)))), "it applies")
	for sim in [sa, b.sim]:
		sim.waves.enabled = false
		sim.storyteller.enabled = false
		sim.initiative.enabled = false
		sim.specialists.enabled = false
	Helpers.run(sa, 60.0)
	Helpers.run(b.sim, 60.0)
	var pa: Dictionary = sa.relations.save().pairs
	var pb: Dictionary = b.sim.relations.save().pairs
	eq(pb, pa, "the same pairs, to the last digit")
	eq(b.sim.rng.state, sa.rng.state, "and the same dice")
	check(float(pa.get("dez|walt", {}).get("v", 0.0)) > 3.0, "(and something happened)")
	a.world.free()
	b.world.free()


func test_a_news_line_still_waiting_is_told_after_a_load() -> void:
	var a := _game()
	var sa = a.sim
	var ra = sa.relations
	ra.add("dez", "walt", 40.0, "x")
	ra.add("marcus", "ana", -40.0, "x")
	ra.add("walt", "ana", 40.0, "x")    # (the third of the day: it waits)
	var told: int = sa.radio.news.size()
	eq(told, 2, "two told")
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sa)))), "it applies")
	b.sim.day = 4
	b.sim.relations.look()
	var texts: Array = []
	for e in b.sim.radio.news:
		texts.append(String(e.text))
	check(texts.has("Ana and Walt are close now"), "the waiting line is told the next day: %s" % str(texts))
	a.world.free()
	b.world.free()


func test_a_loaded_save_keeps_the_caps() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var rows := {}
	for who in ["ana", "marcus", "walt", "hector"]:
		var key := "dez|%s" % who if "dez" < who else "%s|dez" % who
		rows[key] = {"v": 60.0 - float(rows.size()) * 5.0, "kind": "friend", "since": 1, "why": "x", "day": 3, "anchor": false, "told": true}
	r.load_state({"pairs": rows})
	var friends: Array = []
	for p in r.friends_of(_p(sim, "dez")):
		friends.append(p.first)
	eq(friends.size(), 3, "three friends, however many the file said")
	eq(r.kind("dez", "hector"), "", "the weakest (45) has none")
	eq(friends, ["Ana", "Marcus", "Walt"], "the strongest three, in order")
	g.world.free()
