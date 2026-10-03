extends "res://tests/case.gd"
## The fixes of the round 17 review, simulation side (fixer A): a person who follows can go on a trip, and followers go back to
## work while the leader is out; the succession prefers somebody at the base; the seat an avatar leaves is filled again from
## the people at the base; the fever call's options do what they say; a full crew (six) is not an avatar game; the trust a
## place costs reaches the base; the small seams (the aim's wall cache, "hard" refusals in a place).

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const MainScript := preload("res://scripts/main.gd")
const Fakes := preload("res://tests/menu_fakes.gd")
const HudKit := preload("res://tests/hud_kit.gd")

const FIXTURE := "user://test_round17_fixes_town.json"
const DT := 1.0 / 30.0
const W := 30
const H := 16

## Home is at (50, 35); the houses are an hour away on foot.
const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
	],
	"roads": [["home", "houses"]],
	"beats": [],
}


# ----------------------------------------------------------------- helpers --

func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game of `crew` people (3 by default: Ruth, Dez, Marcus) at `hour` of day 3 with the small town above and Ruth as
## the avatar.
func _town(crew: int = 3, hour: float = 8.0, avatar: bool = true) -> Dictionary:
	_write(TOWN)
	Town.data_path = FIXTURE
	var g := Helpers.make(17, 1, crew)
	Town.data_path = Town.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	_at(sim, 3, hour)
	sim.supplies.sources_day = 3
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	if avatar:
		sim.avatar.set_player("ruth")
		sim.radio.start()
	return g


## A classic game of `crew` people (the real map, no town) with Ruth as the avatar at 09:00 of day 3.
func _yard(crew: int = 6, leader: String = "ruth") -> Dictionary:
	var g := Helpers.make(5, 1, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	_at(sim, 3, 9.0)
	check(sim.avatar.set_player(leader), "%s is the player" % leader)
	sim.radio.start()
	sim.events.clear()
	return g


func _at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _free(g: Dictionary) -> void:
	g.world.free()


## A place 30 x 16: open ground, a house with two containers, the entry on the left (as tests/test_raid_avatar.gd's).
func _site() -> Dictionary:
	var data: Dictionary = GD.load_all().duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in H:
		for x in W:
			terrain.append(1)
			var wall := (x >= 14 and x <= 24 and y >= 3 and y <= 12) and (x == 14 or x == 24 or y == 3 or y == 12) and not (x == 14 and y == 8)
			solid.append(1 if wall else 0)
	data["W"] = W
	data["H"] = H
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	data["objects"] = []
	data["walls"] = []
	data["marks"] = []
	data["lights"] = []
	data["trees"] = []
	data["segments"] = []
	data["people"] = []
	data["spawns"] = []
	return {
		"name": "A test house", "kind": "houses", "danger": 2, "size": Vector2i(W, H), "data": data,
		"entry": Vector2(3.5, 8.5), "exit": Rect2(1.0, 6.5, 5.0, 4.0), "vehicle_spot": Vector2(-1, -1),
		"containers": [
			{"id": "c1", "pos": Vector2(16.5, 6.5), "at": Vector2(16.5, 5.5), "kind": "cabinet", "loot": {"food": 10, "meds": 4}, "search_s": 4.0, "room": "hall"},
			{"id": "c2", "pos": Vector2(21.5, 9.5), "at": Vector2(21.5, 10.5), "kind": "shelf", "loot": {"scrap": 25, "ammo": 60}, "search_s": 6.0, "room": "back"},
		],
		"dead": [], "rooms": [{"name": "hall", "rect": Rect2(15, 4, 9, 8)}], "seed": 1,
	}


## A run of the colony people `who` in the place above, the first of them the player. {"run", "world", "people"}.
func _run(colony, who: Array) -> Dictionary:
	var site := _site()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(site.data)
	var people: Array = []
	for id in who:
		people.append(_p(colony, String(id)))
	var run = RaidRun.new(site, world, FxNull.new(), RaidRun.squad_of(people), 300.0)
	check(run.set_player(run.squad[0]), "the first is the player")
	return {"run": run, "world": world, "people": people}


func _step(run, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		run.update(DT)


# --------------------------------------------------- #2 asked to come, can go --

func test_a_follower_can_go_on_a_trip() -> void:
	var g := _town()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var r: Dictionary = sim.radio.request(dez, "come")
	check(r.ok, "Dez agrees: %s" % str(r))
	Helpers.run(sim, 5.0)
	eq(dez.stance, "follow", "Dez follows")
	check(dez.drafted, "which drafted him")
	check(sim.scavenge.can_go(dez, true), "a follower can go on a played trip")
	check(sim.scavenge.free_survivors(true).has(dez), "and is on the free list of a played trip")
	check(sim.scavenge.free_survivors().has(dez), "and on the Town Board's list (it asks for the free survivors, the player apart)")
	var picked: Dictionary = PlaceFlow.pick_party(sim, [dez], "")
	eq(picked.going.size(), 2, "the avatar and Dez")
	var flow := PlaceFlow.new(sim)
	check(flow.begin(picked.going, "houses", ""), "the trip begins: %s" % flow.error)
	eq(dez.stance, "", "the party opening ended his stance")
	check(not dez.drafted, "and what it drafted him for")
	check(dez.away != null, "he is out")
	_free(g)


func test_the_classic_drafts_still_keep_a_person_from_a_trip() -> void:
	var g := _town(3, 8.0, false)
	var sim = g.sim
	var dez = _p(sim, "dez")
	check(sim.scavenge.can_go(dez), "a free man can go")
	sim.toggle_draft(dez)
	check(dez.drafted, "drafted by the old control")
	check(not sim.scavenge.can_go(dez), "and a drafted one cannot, as it always was")
	sim.toggle_draft(dez)
	sim.order_post(dez)
	check(not sim.scavenge.can_go(dez), "nor one sent to the wall")
	_free(g)


func test_somebody_sent_to_the_walls_can_go_in_an_avatar_game() -> void:
	var g := _town()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var r: Dictionary = sim.radio.request(dez, "post")
	check(r.ok, "asked to the walls: %s" % str(r))
	Helpers.run(sim, 5.0)
	check(dez.order != null, "he has the post order")
	check(sim.scavenge.can_go(dez, true), "the player may take him on a trip anyway: coming is what they ask")
	var flow := PlaceFlow.new(sim)
	check(flow.begin([sim.avatar.player(), dez], "houses", ""), "the trip begins: %s" % flow.error)
	check(dez.order == null and not dez.drafted, "the order is gone with the party opening")
	_free(g)


func test_a_card_does_not_take_somebody_the_player_has_asked_for_its_errand() -> void:
	# (a player's trip may take a follower; the storyteller's errand may not)
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	var before: Array = sim.storyteller._errand_crew(6).map(func(q): return q.id)
	check(before.has("dez"), "Dez is free for an errand: %s" % str(before))
	sim.radio.set_stance(dez, "follow")
	var after: Array = sim.storyteller._errand_crew(6).map(func(q): return q.id)
	check(not after.has("dez"), "a follower is not: %s" % str(after))
	check(sim.scavenge.can_go(dez, true), "though the player can take him")
	_free(g)


func test_followers_at_the_base_go_back_to_work_while_the_leader_is_out() -> void:
	var g := _town()
	var sim = g.sim
	var ruth = _p(sim, "ruth")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	check(sim.radio.request(dez, "come").ok, "Dez comes")
	Helpers.run(sim, 5.0)
	eq(dez.stance, "follow", "following")
	var flow := PlaceFlow.new(sim)
	check(flow.begin([ruth, marcus], "houses", ""), "Ruth and Marcus go out: %s" % flow.error)
	Helpers.run(sim, 2.0)
	eq(dez.stance, "", "Dez is no follower while Ruth is away")
	check(not dez.drafted, "he is not drafted either: the day's rules have him")
	check(not String(dez.activity).begins_with("Following"), "and does not stand about 'following': %s" % dez.activity)
	_free(g)


func test_holding_stays_while_the_leader_is_out() -> void:
	var g := _town()
	var sim = g.sim
	var ruth = _p(sim, "ruth")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	check(sim.radio.request(dez, "hold").ok, "Dez holds")
	Helpers.run(sim, 5.0)
	eq(dez.stance, "hold", "holding")
	var flow := PlaceFlow.new(sim)
	check(flow.begin([ruth, marcus], "houses", ""), "out: %s" % flow.error)
	Helpers.run(sim, 2.0)
	eq(dez.stance, "hold", "a hold is a spot, not the leader: it stays")
	check(dez.drafted, "drafted for it")
	_free(g)


func test_a_cover_or_follow_ends_when_the_leader_is_dead() -> void:
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	var ana = _p(sim, "ana")
	sim.radio.set_stance(dez, "follow")
	sim.radio.set_stance(ana, "cover")
	var ruth = _p(sim, "ruth")
	# (the leader goes without the succession: nobody leads)
	sim.player_id = ""
	ruth.player = false
	sim.radio.tick(0.1)
	eq(dez.stance, "", "no leader: no follower")
	eq(ana.stance, "", "no cover either")
	check(not dez.drafted and not ana.drafted, "and nobody stays drafted for it")
	_free(g)


# ------------------------------------------------------- #4 succession at home --

func test_the_succession_prefers_somebody_at_the_base() -> void:
	var g := _town()
	var sim = g.sim
	var ruth = _p(sim, "ruth")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	dez.skills["Leading"] = 3
	marcus.skills["Leading"] = 1
	check(sim.scavenge.send([dez], "houses"), "Dez goes on a dice errand")
	var guard := 0
	while dez.away == null and guard < 4000:
		sim.update(DT)
		guard += 1
	check(dez.away != null, "he is away")
	sim.medical.kill(ruth, "bled out")
	eq(sim.player_id, "marcus", "Marcus is at home: he leads, though Dez leads better")
	check(marcus.player and marcus.away == null, "flagged and at home")
	_free(g)


func test_with_nobody_at_home_the_succession_falls_back_to_somebody_away_safely() -> void:
	var g := _town()
	var sim = g.sim
	var ruth = _p(sim, "ruth")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	dez.skills["Leading"] = 3
	check(sim.scavenge.send([dez, marcus], "houses"), "both go on a dice errand")
	sim.scavenge.parties[0].result.lost.clear()    # (round 18: an errand can lose people at a danger 1 place: this test is about the way home)
	var guard := 0
	while (dez.away == null or marcus.away == null) and guard < 6000:
		sim.update(DT)
		guard += 1
	check(dez.away != null and marcus.away != null, "both are away")
	sim.medical.kill(ruth, "bled out")
	eq(sim.player_id, "dez", "nobody is home: the best of those away leads")
	var me = sim.avatar.player()
	check(me != null and me.away != null, "and is away")
	sim.avatar.set_input(Vector2(1, 0), Vector2(60, 40), true)
	var at := Vector2(me.x, me.y)
	Helpers.run(sim, 2.0)
	near(Vector2(me.x, me.y).distance_to(at), 0.0, 0.0001, "an away player does not walk about or shoot at the base")
	var w: Dictionary = sim.radio.request(marcus, "come")
	check(not w.ok, "and cannot ask anybody to come while away")
	eq(sim.player_id, "dez", "still the player")
	# the errand ends: he is home and plays
	guard = 0
	while me.away != null and guard < 30000:
		sim.update(DT)
		guard += 1
	check(me.away == null, "he comes home")
	check(me.player, "still the player at home")
	_free(g)


# ------------------------------------------------------- #5 the seat that was left --

func test_the_radio_desk_is_staffed_again_after_the_avatar_leaves_it() -> void:
	for crew in [3, 5, 6]:
		var g := Helpers.make(5, 1, crew)
		var sim = g.sim
		sim.waves.enabled = false
		sim.zombies.clear()
		var first: String = MainScript.first_starter_id(sim.people)
		eq(sim.jobs.job_of(_p(sim, first)), "radio", "(crew %d) the first starter held the radio desk" % crew)
		check(sim.avatar.set_player(first), "(crew %d) %s is the player" % [crew, first])
		var desk: Array = sim.jobs.crew_of("radio")
		eq(desk.size(), 1, "(crew %d) the radio desk has somebody" % crew)
		check(not desk.is_empty() and desk[0].id != first, "(crew %d) somebody else than the player: %s" % [crew, str(desk.map(func(q): return q.id))])
		Helpers.run(sim, 30.0)
		check(sim.storyteller.speaker() != null, "(crew %d) the storyteller has a speaker" % crew)
		g.world.free()


func test_the_seat_is_taken_from_somebody_whose_work_can_wait() -> void:
	var g := Helpers.make(5, 1, 5)
	var sim = g.sim
	sim.avatar.set_player("ruth")
	check(sim.jobs.crew_of("infirmary").size() == 1 and sim.jobs.crew_of("infirmary")[0].id == "ana", "Ana keeps the infirmary: no desk takes a nurse")
	var desk: Array = sim.jobs.crew_of("radio")
	check(not desk.is_empty() and desk[0].id != "ana", "the desk is not Ana's")
	g.world.free()


func test_a_medic_who_becomes_the_player_is_replaced_at_the_infirmary() -> void:
	var g := _yard(5)
	var sim = g.sim
	eq(sim.jobs.job_of(_p(sim, "ana")), "infirmary", "Ana is the nurse")
	var ruth = _p(sim, "ruth")
	var ana = _p(sim, "ana")
	for q in sim.people:
		q.trust = 40.0
	ana.trust = 90.0
	sim.medical.kill(ruth, "bled out")
	eq(sim.player_id, "ana", "Ana, the most trusted, leads")
	var ward: Array = sim.jobs.crew_of("infirmary")
	check(not ward.is_empty(), "the infirmary has somebody again")
	check(not ward.is_empty() and ward[0].id != "ana", "and it is not the player")
	var desk: Array = sim.jobs.crew_of("radio")
	check(desk.is_empty() or desk[0].id != "ruth", "(the dead hold no seat)")
	_free(g)


func test_a_person_with_no_job_takes_the_empty_seat_first() -> void:
	var g := Helpers.make(5, 1, 5)
	var sim = g.sim
	sim.jobs.unassign(_p(sim, "walt"))
	sim.avatar.set_player("ruth")
	eq(sim.jobs.job_of(_p(sim, "walt")), "radio", "Walt, who had nothing to do, sits at the desk")
	eq(sim.jobs.job_of(_p(sim, "dez")), "bench", "and nobody else is moved")
	eq(sim.jobs.job_of(_p(sim, "marcus")), "watch", "not the lookout")
	g.world.free()


# -------------------------------------------------------------- #9 the fever call --

func _fever(g: Dictionary, with_meds: bool) -> Dictionary:
	var sim = g.sim
	sim.stock.meds = 6.0 if with_meds else 0.0
	var dez = _p(sim, "dez")
	dez.infected_at = sim.clock_min - 7.0 * 60.0
	Helpers.run(sim, 0.2)
	for e in sim.radio.news:
		if e.kind == "sick":
			return e
	return {}


func _ids(options: Array) -> Array:
	var out: Array = []
	for o in options:
		out.append(o.id)
	return out


func test_the_fever_call_offers_to_send_out_when_there_is_no_medicine() -> void:
	var g := _yard(6)
	var c := _fever(g, false)
	check(not c.is_empty(), "a call")
	eq(_ids(c.options), ["treat", "apart", "sendout"], "treat, keep apart, send out: with no medicine the gate is an answer")
	eq(c.default, "treat", "and the default is still the treatment, never the gate")
	_free(g)


func test_the_fever_call_has_no_send_out_while_there_is_medicine() -> void:
	var g := _yard(6)
	var c := _fever(g, true)
	eq(_ids(c.options), ["treat", "apart"], "with medicine the call is as it was")
	_free(g)


func test_keeping_a_sick_person_apart_takes_them_off_their_work_and_rests_them() -> void:
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	Helpers.seat(sim, dez, "bench")
	Helpers.run(sim, 1.0)
	check(sim.jobs.working("bench").has(dez), "Dez works the bench")
	var c := _fever(g, true)
	var before: float = sim.morale.value(dez)
	check(sim.radio.answer(int(c.id), "apart"), "keep him apart")
	check(sim.medical.is_apart(dez), "he is apart")
	check(String(c.result).contains("Dez") and String(c.result).to_lower().contains("apart"), "the news says what came of it: '%s'" % c.result)
	check(sim.morale.value(dez) < before, "and it costs him a little mood")
	Helpers.run(sim, 40.0)
	check(not sim.jobs.working("bench").has(dez), "he does not work the bench any more")
	eq(dez.activity, "Resting apart", "he rests apart")
	check(dez.infected_at >= 0.0, "the infection is still there: nothing is cured")
	check(not sim.medical.treat_orders.has("dez"), "and nothing is ordered")
	var spot: Vector2 = sim.medical.apart_spot(dez)
	check(Vector2(dez.x, dez.y).distance_to(spot) < 1.0, "he is at his place apart: %s at %s" % [str(Vector2(dez.x, dez.y)), str(spot)])
	_free(g)


func test_a_person_kept_apart_is_not_on_the_wall_at_night_either() -> void:
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	var c := _fever(g, true)
	check(sim.radio.answer(int(c.id), "apart"), "apart")
	_at(sim, 3, 22.0)
	Helpers.run(sim, 40.0)
	eq(dez.activity, "Resting apart", "at night too, not at his post")
	_free(g)


func test_deciding_to_treat_after_all_ends_the_apart() -> void:
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	var c := _fever(g, true)
	check(sim.radio.answer(int(c.id), "apart"), "apart")
	check(sim.medical.is_apart(dez), "apart")
	check(sim.medical.gizmo("treat", {"kind": "person", "ref": dez}), "treat him")
	check(not sim.medical.is_apart(dez), "he is not kept apart any more")
	_free(g)


func test_the_apart_ends_when_the_infection_is_cured_and_is_saved() -> void:
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	var c := _fever(g, true)
	check(sim.radio.answer(int(c.id), "apart"), "apart")
	var saved: Dictionary = sim.medical.save()
	check((saved.get("apart", []) as Array).has("dez"), "kept in the save: %s" % str(saved.get("apart")))
	sim.medical.apart.clear()
	sim.medical.load_state(saved)
	check(sim.medical.is_apart(dez), "and comes back with the load")
	dez.infected_at = -1.0
	Helpers.run(sim, 0.2)
	check(not sim.medical.is_apart(dez), "cured: no longer apart")
	_free(g)


func test_a_passing_fever_runs_out_faster_while_resting_apart() -> void:
	# (no medicine, so that the call's default treatment cannot cure it: only the rest does)
	var g1 := _yard(6)
	var s1 = g1.sim
	s1.stock.meds = 0.0
	s1.storyteller.enabled = true
	var d1 = _p(s1, "dez")
	s1.storyteller.sick["dez"] = s1.clock_min + 240.0
	var g2 := _yard(6)
	var s2 = g2.sim
	s2.stock.meds = 0.0
	s2.storyteller.enabled = true
	var d2 = _p(s2, "dez")
	s2.storyteller.sick["dez"] = s2.clock_min + 240.0
	check(s2.medical.keep_apart(d2), "kept apart")
	Helpers.run(s1, 60.0)
	Helpers.run(s2, 60.0)
	var left1: float = float(s1.storyteller.sick.get("dez", s1.clock_min)) - s1.clock_min
	var left2: float = float(s2.storyteller.sick.get("dez", s2.clock_min)) - s2.clock_min
	check(left2 < left1 - 30.0, "resting apart shortens the fever: %.0f min left against %.0f" % [left2, left1])
	check(d1 != null and d2 != null, "(both there)")
	_free(g1)
	_free(g2)


func test_sending_a_sick_person_out_through_the_gate_is_an_answer_of_the_call() -> void:
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	var c := _fever(g, false)
	check(sim.radio.answer(int(c.id), "sendout"), "send him out")
	check(sim.medical.sendouts.has("dez"), "he is walking to the gate")
	check(String(c.result).contains("Dez") and String(c.result).to_lower().contains("gate"), "the news says it: '%s'" % c.result)
	Helpers.run(sim, 80.0)
	check(dez.dead and dez.away != null and String(dez.away.get("kind", "")) == "exile", "and he is gone through it")
	_free(g)


func test_a_fever_that_cannot_be_sent_out_is_not_offered_the_gate() -> void:
	# (a passing fever of the storyteller's is not an infection: nobody is sent out for it)
	var g := _yard(6)
	var sim = g.sim
	sim.stock.meds = 0.0
	sim.storyteller.enabled = true
	sim.storyteller.sick["dez"] = sim.clock_min + 300.0
	Helpers.run(sim, 0.2)
	var c := {}
	for e in sim.radio.news:
		if e.kind == "sick":
			c = e
	check(not c.is_empty(), "a call for the fever")
	eq(_ids(c.options), ["treat", "apart"], "no gate for a passing fever")
	_free(g)


# --------------------------------------------------------- #10 a full crew is classic --

func test_a_full_crew_is_not_an_avatar_game() -> void:
	check(MainScript.wants_avatar([], {}, false, false, true, 5), "a crew of five is")
	check(MainScript.wants_avatar([], {}, false, false, true, 3), "so is three")
	check(not MainScript.wants_avatar([], {}, false, false, true, 6), "six, with no town to go to, is the old game")
	check(MainScript.wants_avatar([], {"avatar": true}, false, false, false, 6), "unless the run says so (a test asks)")
	check(MainScript.wants_avatar([], {}, false, false, true), "a call that names no crew is as it was")


func test_the_new_game_card_of_the_full_crew_says_there_is_no_avatar() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_new_game()
	await HudKit.settle()
	var full: String = screen.CREW_LINES[2]
	check(full.contains("No avatar"), "the card says it: %s" % full)
	check(full.contains("plays as before"), "and what it means: %s" % full)
	check(not String(screen.CREW_LINES[0]).contains("No avatar") and not String(screen.CREW_LINES[1]).contains("No avatar"), "only the full crew")
	var sub: Label = screen.crew_cards[2].get_meta("sub")
	check(sub.text.contains("No avatar"), "on the card itself: %s" % sub.text)
	# (the longer line must still fit on its card, at the room the menu gives it)
	for card in screen.crew_cards:
		var c: Control = card
		var inner: Label = c.get_meta("sub")
		check(c.get_global_rect().grow(0.5).encloses(inner.get_global_rect()), "the words of a crew card are inside it: card %s, words %s" % [str(c.get_global_rect()), str(inner.get_global_rect())])
	Fakes.free_all(ctx)


# ------------------------------------------------ #3 what a place costs in trust --

func test_insisting_in_a_place_costs_trust_at_the_base() -> void:
	var g := _town()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var ctx := _run(sim, ["ruth", "dez"])
	var run = ctx.run
	var flow := PlaceFlow.new(sim)
	check(flow.begin([_p(sim, "ruth"), dez], "houses", ""), "the trip begins: %s" % flow.error)
	var t0: float = dez.trust
	var in_place = run.squad[1]
	in_place.bleeding = 1.0
	var w: Dictionary = run.request(in_place, "cover", {"insist": true})
	check(w.ok and w.insisted, "Dez is pushed to cover though he bleeds: %s" % str(w))
	_step(run, 1.0)
	var r: Dictionary = run.result()
	near(float(r.trust.get("dez", -99.0)), -sim.radio.INSIST_COST + RaidRun.TRIP_TRUST, 0.001, "the place's count: minus six, plus two for coming home")
	flow.finish(r)
	near(dez.trust, t0 - 6.0 + 2.0, 0.001, "and the base pays it once: %.1f from %.1f" % [dez.trust, t0])
	check(sim.radio.trust_why(dez).size() > 0, "with a reason kept")
	ctx.world.free()
	_free(g)


func test_a_bite_while_following_costs_trust_in_a_place() -> void:
	var g := _town()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var ctx := _run(sim, ["ruth", "dez"])
	var run = ctx.run
	var flow := PlaceFlow.new(sim)
	check(flow.begin([_p(sim, "ruth"), dez], "houses", ""), "the trip begins: %s" % flow.error)
	var t0: float = dez.trust
	var in_place = run.squad[1]
	eq(in_place.stance, "follow", "Dez follows in the place")
	var z = run.sim.spawn(in_place.x + 0.5, in_place.y, "hunt", "walker")
	run.sim._bite(z, in_place)
	_step(run, 0.1)
	var r: Dictionary = run.result()
	near(float(r.trust.get("dez", -99.0)), -3.0 + RaidRun.TRIP_TRUST, 0.001, "three lost for being hurt following, two earned for coming home")
	flow.finish(r)
	near(dez.trust, t0 - 3.0 + 2.0, 0.001, "paid once at the base")
	ctx.world.free()
	_free(g)


func test_a_clean_trip_still_earns_two() -> void:
	var g := _town()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var ctx := _run(sim, ["ruth", "dez"])
	var run = ctx.run
	var flow := PlaceFlow.new(sim)
	check(flow.begin([_p(sim, "ruth"), dez], "houses", ""), "the trip begins: %s" % flow.error)
	var t0: float = dez.trust
	_step(run, 1.0)
	var r: Dictionary = run.result()
	near(float(r.trust.get("dez", -99.0)), 2.0, 0.001, "two")
	flow.finish(r)
	near(dez.trust, t0 + 2.0, 0.001, "and two at the base, not four")
	ctx.world.free()
	_free(g)


func test_the_succession_in_a_place_is_not_paid_twice() -> void:
	var g := _town()
	var sim = g.sim
	var ruth = _p(sim, "ruth")
	var dez = _p(sim, "dez")
	var ctx := _run(sim, ["ruth", "dez"])
	var run = ctx.run
	var flow := PlaceFlow.new(sim)
	check(flow.begin([ruth, dez], "houses", ""), "the trip begins: %s" % flow.error)
	# Ruth falls: the place's own radio loses ten for everybody (its copy), the base's succession is the scene's
	var lead = run.squad[0]
	lead.downed = true
	_step(run, 0.1)
	var r: Dictionary = run.result()
	check(float(r.trust.get("dez", -99.0)) > -5.0, "the place's succession is not in what it reports: %s" % str(r.trust))
	_free(g)
	ctx.world.free()


func test_the_radio_hands_a_hurt_following_to_whoever_reads_the_event() -> void:
	# (the yard reads the bites in `update`; the place calls `on_hurt_following` itself, once for a request)
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	sim.radio.set_stance(dez, "follow")
	var t0: float = dez.trust
	sim.radio.on_hurt_following(dez)
	sim.radio.on_hurt_following(dez)
	near(dez.trust, t0 - sim.radio.HURT_COST, 0.001, "once")
	near(float(sim.radio.trust_moved.get("dez", 0.0)), -sim.radio.HURT_COST, 0.001, "and the radio keeps count of what it moved")
	_free(g)


# ------------------------------------------------------------ #13 the small seams --

func test_the_wall_tiles_of_the_aim_are_kept_until_the_buildings_change() -> void:
	var g := _yard(6)
	var sim = g.sim
	var a = sim.avatar._low_tiles()
	var b = sim.avatar._low_tiles()
	check(is_same(a, b), "the same table for the same buildings")
	sim.build.version += 1
	var c = sim.avatar._low_tiles()
	check(not is_same(a, c), "a new one when the buildings changed")
	eq(a, c, "(with the same content for the same walls)")
	_free(g)


func test_a_refusal_of_the_place_is_hard() -> void:
	var g := _town()
	var sim = g.sim
	var ctx := _run(sim, ["ruth", "dez"])
	var run = ctx.run
	var dez = run.squad[1]
	var nothing: Dictionary = run.request(dez, "search", {"at": Vector2(5.5, 12.5)})
	check(not nothing.ok and String(nothing.why).contains("Nothing to search"), "nothing there: %s" % str(nothing))
	check(bool(nothing.get("hard", false)), "a hard refusal: no Insist")
	var wall: Dictionary = run.request(dez, "post")
	check(not wall.ok and bool(wall.get("hard", false)), "no walls to man: hard")
	run.containers[0]["looted"] = true
	var done: Dictionary = run.request(dez, "search", {"at": Vector2(16.5, 6.5)})
	check(not done.ok and String(done.why).contains("Already") and bool(done.get("hard", false)), "already searched: hard (%s)" % str(done))
	run.containers[0]["looted"] = false
	run.begin_search(run.squad[0], "c1")
	var lead = run.squad[0]
	lead.x = 16.5
	lead.y = 6.5
	check(run.begin_search(lead, "c1"), "the player is on it")
	var busy: Dictionary = run.request(dez, "search", {"at": Vector2(16.5, 6.5)})
	check(not busy.ok and String(busy.why).contains("already on it") and bool(busy.get("hard", false)), "somebody is already on it: hard (%s)" % str(busy))
	var far: Dictionary = run.request(dez, "hold", {"at": Vector2(-30, -30)})
	check(not far.ok and bool(far.get("hard", false)), "a spot nobody can reach: hard (%s)" % str(far))
	run.phase = "retreat"
	var back: Dictionary = run.request(dez, "come")
	check(not back.ok and bool(back.get("hard", false)), "when the trip turns back nothing is asked: hard")
	ctx.world.free()
	_free(g)


func test_the_radios_own_refusal_says_whether_it_is_hard() -> void:
	var g := _yard(6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.bleeding = 2.0
	var soft: Dictionary = sim.radio.request(dez, "come")
	check(not soft.ok and soft.has("hard") and not bool(soft.hard), "bleeding can be insisted away: not hard")
	dez.downed = true
	var hard: Dictionary = sim.radio.request(dez, "come")
	check(not hard.ok and bool(hard.get("hard", false)), "down cannot: hard")
	_free(g)
