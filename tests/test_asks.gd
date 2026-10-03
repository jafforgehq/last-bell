extends "res://tests/case.gd"
## Asking for work over the radio (round 18, slice 2, S2.1: scripts/sim/radio.gd, section "ASKING FOR WORK"; `jobs.fill_empty`). The
## player asks, the community answers: an errand (people sent to a place without the player), a day job, a night post, "fill the empty
## seats", an order for a building. Every refusal is for a visible reason that the panel pages show in the sim's own words
## (`reason_not`, `errand_willingness`, `job_willingness`, `post_willingness`, `fill_willingness`, `build_willingness`); trust sets
## the tone and the delay; insisting overrides a soft refusal at INSIST_COST. A roster change is a plan, answered at once; an errand
## leaves after the radio's delay. Everything is behind avatar mode.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Town := preload("res://scripts/sim/town.gd")

const FIXTURE := "user://test_r18_errands_asks_town.json"
const LEADER_AT := Vector2(34.5, 32.5)

const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
		{"id": "pharmacy", "name": "The pharmacy", "kind": "pharmacy", "pos": [41, 35], "blurb": "Boarded up.", "danger": 2, "known": true,
			"loot": {"meds": [6, 11]}, "extra": {}},
		{"id": "far", "name": "The far depot", "kind": "depot", "pos": [140, 35], "blurb": "Across the river.", "danger": 2, "known": true,
			"loot": {"scrap": [20, 30]}, "extra": {}, "needs_vehicle": true},
	],
	"roads": [["home", "houses"], ["home", "pharmacy"], ["home", "far"]],
	"beats": [],
}


# ----------------------------------------------------------------- helpers --

## The classic start (Ruth, Dez, Ana, Marcus, Walt, Hector) with Ruth as the player, in the yard at 09:00 of day 3, quiet.
func _game(leader_id: String = "ruth") -> Dictionary:
	var g := Helpers.make(1, 1, 6)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player(leader_id), "%s is the player" % leader_id)
	var lead = _p(sim, leader_id)
	lead.x = LEADER_AT.x
	lead.y = LEADER_AT.y
	lead.path = []
	_at(sim, 3, 9.0)
	sim.events.clear()
	return g


## The settlement game (Ruth, Dez, Marcus) with the small town above, Ruth the player, at 09:00 of day 3.
func _town(hour: float = 8.0) -> Dictionary:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(TOWN))
	f.close()
	Town.data_path = FIXTURE
	var g := Helpers.make(17, 1, 3)
	Town.data_path = Town.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	_at(sim, 3, hour)
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	return g


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


func _free(g: Dictionary) -> void:
	g.world.free()


func _news(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


## Ana is on a case (a nurse with a patient: Hector).
func _tend(sim) -> void:
	sim.medical.jobs.append({"healer": _p(sim, "ana"), "patient": _p(sim, "hector"), "kind": "bandage", "work": 0.0, "stand": null, "anchor": Vector2.ZERO})


func _ids(people: Array) -> Array:
	var out: Array = []
	for p in people:
		out.append(String(p.id))
	return out


func _first_event(sim, type: String) -> Dictionary:
	for e in sim.events:
		if e.type == type:
			return e
	return {}


## What `willingness(p, "come")` says in the words of an errand ("can't go").
func _as_go(why: String) -> String:
	return why.replace(", can't come", ", can't go")


# ---------------------------------------------------------------- reason_not --

## Puts one condition on Dez and says what it is; `_clear` takes it off again.
func _condition(sim, dez, which: String) -> void:
	match which:
		"leader":
			pass
		"downed":
			dez.downed = true
		"dead":
			dez.dead = true
		"turned":
			dez.dead = true
			dez.turned = true
		"away":
			dez.away = {"kind": "trip"}
		"breakdown":
			sim.morale.until[dez.id] = sim.clock_min + 60.0
		"leaving":
			sim.medical.sendouts[dez.id] = {"left": 100.0}
		"party":
			sim.scavenge.parties.append({"kind": "party", "n": 99, "members": [dez.id], "site": "houses", "state": "out", "return_at": 1.0e9, "result": {}})
		"patient":
			sim.medical.jobs.append({"healer": dez, "patient": _p(sim, "hector"), "kind": "bandage", "work": 0.0, "stand": null, "anchor": Vector2.ZERO})
		"bleeding":
			dez.bleeding = 4.0
			dez.wounds = 1
		"fever":
			dez.infected_at = sim.clock_min - 7.0 * 60.0
		"starving":
			dez.hunger_h = 40.0
		"parched":
			dez.thirst_h = 30.0
		"shaken":
			sim.morale.set_value(dez, 40.0)


func _clear(sim, dez) -> void:
	dez.downed = false
	dez.dead = false
	dez.turned = false
	dez.away = null
	dez.bleeding = 0.0
	dez.wounds = 0
	dez.infected_at = -1.0
	dez.hunger_h = 0.0
	dez.thirst_h = 0.0
	sim.morale.until.erase(dez.id)
	sim.morale.set_value(dez, 70.0)
	sim.medical.jobs.clear()
	sim.medical.sendouts.erase(dez.id)
	sim.scavenge.parties.clear()


const CONDITIONS := ["downed", "dead", "turned", "away", "breakdown", "leaving", "party", "patient", "bleeding", "fever", "starving", "parched", "shaken"]


func test_reason_not_go_is_exactly_the_reasons_of_come() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var radio = sim.radio
	for which in CONDITIONS:
		_condition(sim, dez, which)
		var w: Dictionary = radio.willingness(dez, "come")
		var r: Dictionary = radio.reason_not(dez, "go")
		eq(r.ok, w.ok, "ok, as for 'come' (%s)" % which)
		eq(r.hard, w.hard, "hard, as for 'come' (%s)" % which)
		eq(String(r.why), _as_go(String(w.why)), "the same words, 'can't go' for 'can't come' (%s)" % which)
		check(not r.ok, "and %s is a reason (%s)" % [which, str(r)])
		_clear(sim, dez)
	var ok: Dictionary = radio.reason_not(dez, "go")
	check(ok.ok and ok.why == "" and not ok.hard, "nothing against Dez: %s" % str(ok))
	# the leader
	var lead: Dictionary = radio.reason_not(_p(sim, "ruth"), "go")
	check(not lead.ok and lead.hard, "the player is asked nothing")
	_free(g)


func test_the_hard_reasons_and_the_soft_ones_are_told_apart() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var hard := ["downed", "dead", "turned", "away", "breakdown", "leaving", "party"]
	for which in CONDITIONS:
		_condition(sim, dez, which)
		var r: Dictionary = sim.radio.reason_not(dez, "go")
		eq(r.hard, hard.has(which), "%s is %s" % [which, "a hard reason" if hard.has(which) else "a soft one"])
		_clear(sim, dez)
	_free(g)


func test_the_words_of_a_busy_nurse_and_the_noon_radio_hour() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	eq(String(sim.radio.reason_not(_p(sim, "ana"), "go").why), "Ana: tending a patient, can't go", "the plan's own example")
	sim.medical.jobs.clear()
	sim.jobs.assign(_p(sim, "dez"), "radio")    # (Hector holds the desk: the room is made for Dez)
	_at(sim, 3, 12.0)
	var why: String = sim.radio.reason_not(_p(sim, "hector"), "go").why
	check(why.contains("radio") and why.contains("can't go"), "the radio desk at noon: %s" % why)
	_free(g)


func test_taking_someone_off_a_job_is_refused_only_by_the_hard_reasons() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	for which in CONDITIONS:
		_condition(sim, dez, which)
		var to_station: Dictionary = sim.radio.reason_not(dez, "work")
		var off: Dictionary = sim.radio.job_willingness(dez, "")
		var is_hard: bool = sim.radio.reason_not(dez, "go").hard
		check(not to_station.ok, "a change to a station is refused (%s)" % which)
		eq(off.ok, not is_hard, "taking someone off their job is refused only when the reason is hard (%s)" % which)
		_clear(sim, dez)
	check(sim.radio.reason_not(dez, "work").ok and String(sim.radio.reason_not(dez, "work").why) == "", "and nothing is refused with nothing the matter")
	_tend(sim)
	var why: String = sim.radio.reason_not(_p(sim, "ana"), "work").why
	eq(why, "Ana: tending a patient, can't take a job now", "the work words")
	_free(g)


# ------------------------------------------------------ errand_willingness --

func test_errand_willingness_lists_each_refusal_in_the_words_of_the_verbs() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	_p(sim, "hector").downed = true
	var w: Dictionary = sim.radio.errand_willingness([_p(sim, "ana"), _p(sim, "hector"), _p(sim, "marcus")], "houses")
	check(w.ok, "Marcus can go: %s" % str(w.why))
	eq(_ids(w.going), ["marcus"], "only he goes")
	eq(w.refused.size(), 2, "two are refused")
	var by_id := {}
	for r in w.refused:
		by_id[String(r.id)] = r
	check(by_id.has("ana") and by_id.has("hector"), "Ana and Hector")
	eq(String(by_id.ana.name), "Ana", "the first name")
	eq(String(by_id.ana.why), _as_go(String(sim.radio.willingness(_p(sim, "ana"), "come").why)), "Ana's words are the verb's")
	eq(by_id.ana.hard, false, "Ana, on a case, can be pushed")
	eq(String(by_id.hector.why), "Hector is down", "Hector is down")
	eq(by_id.hector.hard, true, "and cannot be")
	_free(g)


func test_nobody_can_go_names_who_and_why() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	_p(sim, "hector").downed = true
	var w: Dictionary = sim.radio.errand_willingness([_p(sim, "ana"), _p(sim, "hector")], "houses")
	check(not w.ok, "nobody goes")
	eq(String(w.why), "Nobody can go: Ana is tending a patient, Hector is down", "the plan's example")
	check(w.going.is_empty() and w.refused.size() == 2, "and the two are listed")
	var none: Dictionary = sim.radio.errand_willingness([], "houses")
	check(not none.ok and String(none.why) != "", "with nobody asked there is a word for that too: %s" % str(none.why))
	_free(g)


func test_the_trips_own_refusal_comes_first() -> void:
	var g := _game()
	var sim = g.sim
	_at(sim, 3, 22.0)
	var w: Dictionary = sim.radio.errand_willingness([_p(sim, "dez"), _p(sim, "walt")], "houses")
	check(not w.ok, "nobody goes out after dark")
	eq(String(w.why), String(sim.scavenge.why_not_errand([_p(sim, "dez"), _p(sim, "walt")], "houses")), "in the trip's own words")
	check(String(w.why).begins_with("Nobody goes out after dark"), w.why)
	_at(sim, 3, 9.0)
	var three: Dictionary = sim.radio.errand_willingness([_p(sim, "dez"), _p(sim, "walt"), _p(sim, "hector")], "houses")
	check(not three.ok and String(three.why).contains("room for 2"), "a classic party is two at most: %s" % str(three.why))
	check(not sim.radio.errand_willingness([_p(sim, "dez")], "nowhere").ok, "no such place")
	sim.scavenge.raids["houses"] = [3]
	var picked: Dictionary = sim.radio.errand_willingness([_p(sim, "dez")], "houses")
	eq(String(picked.why), "Picked over.", "a place raided today")
	# nobody can go, and it is also the wrong hour: the hour is what is said
	_at(sim, 3, 22.0)
	_p(sim, "dez").downed = true
	var both: Dictionary = sim.radio.errand_willingness([_p(sim, "dez")], "houses")
	check(String(both.why).begins_with("Nobody goes out after dark"), "the hour first: %s" % str(both.why))
	_free(g)


func test_the_settlement_games_trip_refusals_the_vehicle_and_the_road() -> void:
	var g := _town()
	var sim = g.sim
	var pair: Array = [_p(sim, "dez"), _p(sim, "marcus")]
	var far: Dictionary = sim.radio.errand_willingness(pair, "far")
	eq(String(far.why), "Too far to go on foot: take a vehicle.", "a place across the river")
	var v: Dictionary = sim.vehicles.add("pickup")
	check(not v.is_empty(), "a pickup in the pool")
	sim.vehicles.fuel = 0.0
	var dry: Dictionary = sim.radio.errand_willingness(pair, "far", "loot", String(v.id))
	check(not dry.ok and String(dry.why).begins_with("It needs"), "no fuel: %s" % str(dry.why))
	sim.vehicles.fuel = 100.0
	check(sim.radio.errand_willingness(pair, "far", "loot", String(v.id)).ok, "with fuel it goes")
	var unknown: Dictionary = sim.radio.errand_willingness(pair, "far", "loot", "nope")
	check(not unknown.ok, "an unknown vehicle is refused: %s" % str(unknown.why))
	var with_player: Dictionary = sim.radio.errand_willingness([_p(sim, "dez"), _p(sim, "marcus"), _p(sim, "ruth")], "far", "loot", String(v.id))
	check(with_player.ok and _ids(with_player.going) == ["dez", "marcus"], "the player is not one of the people to send")
	eq(String(with_player.refused[0].id), "ruth", "and is listed as refused")
	var newcomer = sim.add_person(sim.recruits.make_def(0))
	var crowd: Dictionary = sim.radio.errand_willingness([_p(sim, "dez"), _p(sim, "marcus"), newcomer], "far", "loot", String(v.id))
	check(not crowd.ok, "three do not fit in a pickup")
	eq(String(crowd.why), "There is room for 2.", "in the trip's words")
	_free(g)


func test_an_errand_by_vehicle_leaves_with_it() -> void:
	var g := _town()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	sim.vehicles.fuel = 100.0
	var r: Dictionary = sim.radio.request_errand([_p(sim, "dez"), _p(sim, "marcus")], "far", "loot", String(v.id))
	check(r.ok, "the errand is asked: %s" % str(r.why))
	eq(String(sim.radio.errand_wait[0].vehicle), String(v.id), "the vehicle waits with it")
	Helpers.run(sim, 6.0)
	eq(sim.scavenge.parties.size(), 1, "the party is made")
	eq(String(sim.scavenge.parties[0].vehicle), String(v.id), "in the pickup")
	check(bool(sim.scavenge.parties[0].result.get("errand", false)), "an errand")
	_free(g)


func test_the_slowest_going_sets_the_delay_and_the_least_willing_the_tone() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	dez.trust = 85.0
	walt.trust = 25.0
	var w: Dictionary = sim.radio.errand_willingness([dez, walt], "houses")
	check(w.ok, "they can go")
	near(float(w.delay_s), sim.radio.delay_for(25.0), 0.0001, "the slow one's delay")
	eq(String(w.tone), "doubtful", "and the doubtful tone")
	var fast: Dictionary = sim.radio.errand_willingness([dez], "houses")
	near(float(fast.delay_s), 0.5, 0.0001, "Dez alone is quick")
	eq(String(fast.tone), "willing", "and willing")
	var gone: Dictionary = sim.radio.errand_willingness([_p(sim, "ana"), _p(sim, "marcus")], "far")
	near(float(gone.delay_s), 0.0, 0.0001, "a refused errand has no delay")
	_free(g)


func test_the_terms_and_the_note_are_the_scavenge_modules() -> void:
	var g := _game()
	var sim = g.sim
	var w: Dictionary = sim.radio.errand_willingness([_p(sim, "dez")], "houses")
	eq(w.terms, sim.scavenge.errand_terms(), "the terms")
	eq(String(w.loot_note), "Without you: about 60% of the loot, no rare finds, no rescue, a worse chance everyone comes home", "the plan's note")
	_free(g)


func test_errand_willingness_is_pure() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	var trust: Array = []
	for p in sim.people:
		trust.append(p.trust)
	var news := str(sim.radio.news)
	sim.radio.errand_willingness([_p(sim, "ana"), _p(sim, "dez")], "houses")
	sim.radio.job_willingness(_p(sim, "ana"), "garden")
	sim.radio.post_willingness(_p(sim, "ana"), "gate")
	sim.radio.fill_willingness()
	sim.radio.build_willingness("workshop")
	var after: Array = []
	for p in sim.people:
		after.append(p.trust)
	eq(after, trust, "trust is untouched")
	eq(str(sim.radio.news), news, "the log too")
	check(sim.radio.errand_wait.is_empty() and sim.radio.pending.is_empty(), "nothing is queued")
	check(sim.scavenge.parties.is_empty(), "nobody left")
	check(sim.events.is_empty(), "no line was said")
	_free(g)


# --------------------------------------------------------- request_errand --

func test_an_errand_asked_for_leaves_after_the_radios_delay() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	var r: Dictionary = sim.radio.request_errand([dez, walt], "houses")
	check(r.ok, "agreed: %s" % str(r))
	eq(_ids(r.going), ["dez", "walt"], "both go")
	eq(r.refused, [], "none refused")
	eq(r.insisted, false, "nobody was pushed")
	eq(String(r.line), "I'll go.", "Dez says it, in a willing voice (trust 55)")
	near(float(r.delay_s), sim.radio.delay_for(55.0), 0.0001, "the delay is the radio's")
	var said := _first_event(sim, "radio_line")
	eq(String(said.get("who", "")), "dez", "Dez says the line")
	eq(String(said.get("line", "")), "I'll go.", "aloud")
	eq(sim.radio.errand_wait.size(), 1, "the errand waits")
	eq(sim.radio.errand_wait[0].ids, ["dez", "walt"], "for the two")
	eq(String(sim.radio.errand_wait[0].place), "houses", "to the place")
	check(sim.scavenge.parties.is_empty(), "nobody has left yet")
	Helpers.run(sim, float(r.delay_s) - 0.2)
	check(sim.scavenge.parties.is_empty(), "still waiting just before the delay")
	Helpers.run(sim, 0.5)
	eq(sim.scavenge.parties.size(), 1, "the party is made after the delay")
	eq(sim.scavenge.parties[0].members, ["dez", "walt"], "with the two")
	check(bool(sim.scavenge.parties[0].result.get("errand", false)), "and it is an errand")
	check(sim.radio.errand_wait.is_empty(), "nothing waits any more")
	_free(g)


func test_the_tone_of_the_first_going_is_the_line() -> void:
	var g := _game()
	var sim = g.sim
	for case in [[85.0, "I'll go."], [40.0, "Fine. I'll go."], [10.0, "...if you say so."]]:
		sim.radio.errand_wait.clear()
		var dez = _p(sim, "dez")
		dez.trust = case[0]
		var r: Dictionary = sim.radio.request_errand([dez], "houses")
		eq(String(r.line), String(case[1]), "trust %s" % str(case[0]))
	_free(g)


func test_a_soft_refusal_can_be_insisted_for_six_trust_and_takes_the_nurse_off_her_case() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	var ana = _p(sim, "ana")
	var dez = _p(sim, "dez")
	var r: Dictionary = sim.radio.request_errand([ana, dez], "houses")
	check(r.ok, "Dez can go and Ana is left out")
	eq(_ids(r.going), ["dez"], "Dez alone")
	eq(r.refused.size(), 1, "Ana's refusal is listed")
	near(ana.trust, 55.0, 0.0001, "asking costs nothing")
	sim.radio.errand_wait.clear()
	var pushed: Dictionary = sim.radio.request_errand([ana, dez], "houses", "loot", "", {"insist": true})
	check(pushed.ok, "pushed: both go")
	eq(pushed.insisted, true, "and it says so")
	eq(_ids(pushed.going), ["ana", "dez"], "Ana is one of them")
	near(ana.trust, 49.0, 0.0001, "insisting costs six trust")
	near(dez.trust, 55.0, 0.0001, "only the one who was pushed pays")
	eq(pushed.refused, [], "nobody is left refused")
	check(sim.morale.value(ana) < 70.0, "and it was a blow to the mood: %s" % str(sim.morale.value(ana)))
	Helpers.run(sim, 5.0)
	eq(sim.scavenge.parties.size(), 1, "the party leaves")
	eq(sim.scavenge.parties[0].members, ["ana", "dez"], "with Ana in it")
	var healing := false
	for j in sim.medical.jobs:
		healing = healing or j.healer == ana
	check(not healing, "and she is no longer on the case")
	_free(g)


func test_a_soft_refusal_is_said_aloud_and_a_hard_one_is_only_listed() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	var r: Dictionary = sim.radio.request_errand([_p(sim, "ana")], "houses")
	check(not r.ok and not r.refused[0].hard, "Ana refuses softly")
	eq(String(r.why), "Nobody can go: Ana is tending a patient", "the summary")
	var said := _first_event(sim, "radio_line")
	eq(String(said.get("who", "")), "ana", "Ana says it")
	eq(String(said.get("line", "")), "Tending a patient, can't go.", "in her words")
	eq(said.get("ok", true), false, "a refusal")
	check(sim.radio.errand_wait.is_empty(), "nothing is queued")
	_free(g)


func test_a_nurse_pushed_to_go_alone_goes_though_nobody_else_is_free() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	for id in ["dez", "marcus", "walt", "hector"]:
		_p(sim, id).downed = true
	var r: Dictionary = sim.radio.request_errand([_p(sim, "ana")], "houses", "loot", "", {"insist": true})
	check(r.ok and r.insisted, "Ana is pushed and goes alone: %s" % str(r))
	Helpers.run(sim, 5.0)
	eq(sim.scavenge.parties.size(), 1, "she is off")
	eq(sim.scavenge.parties[0].members, ["ana"], "alone")
	_free(g)


func test_a_hard_refusal_cannot_be_insisted() -> void:
	var g := _game()
	var sim = g.sim
	var hector = _p(sim, "hector")
	hector.downed = true
	var r: Dictionary = sim.radio.request_errand([hector], "houses", "loot", "", {"insist": true})
	check(not r.ok, "Hector is down: no")
	eq(r.insisted, false, "nothing was pushed")
	near(hector.trust, 55.0, 0.0001, "and it costs nothing")
	check(sim.radio.errand_wait.is_empty(), "nothing is queued")
	check(String(r.why).contains("Hector is down"), "the reason: %s" % str(r.why))
	_free(g)


func test_insisting_on_an_errand_that_cannot_go_costs_nothing() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	_at(sim, 3, 22.0)
	var ana = _p(sim, "ana")
	var r: Dictionary = sim.radio.request_errand([ana], "houses", "loot", "", {"insist": true})
	check(not r.ok, "nobody goes out after dark")
	near(ana.trust, 55.0, 0.0001, "so nobody paid for being pushed")
	check(not sim.medical.jobs.is_empty(), "and the nurse is still on her case")
	_free(g)


func test_an_errand_that_cannot_start_when_the_delay_is_up_says_so() -> void:
	var g := _game()
	var sim = g.sim
	_at(sim, 3, 9.95)    # 09:57: the delay (2.1 s of rules time, 6 game minutes) carries the clock past the ten o'clock limit
	var r: Dictionary = sim.radio.request_errand([_p(sim, "dez")], "houses")
	check(r.ok, "it is agreed to in time")
	Helpers.run(sim, 6.0)
	check(sim.scavenge.parties.is_empty(), "but the hour has passed: no party")
	check(sim.radio.errand_wait.is_empty(), "and nothing is waiting")
	var told := _news(sim, "errand")
	eq(told.size(), 1, "the radio logs it: %s" % str(told))
	check(String(told[0].text).begins_with("The errand could not start: "), "in the plan's words: %s" % str(told[0].text))
	check(String(told[0].text).to_lower().contains("late"), "with the hour as the reason: %s" % str(told[0].text))
	_free(g)


func test_an_errand_whose_people_were_lost_meanwhile_starts_with_who_is_left() -> void:
	var g := _game()
	var sim = g.sim
	var r: Dictionary = sim.radio.request_errand([_p(sim, "dez"), _p(sim, "walt")], "houses")
	check(r.ok, "agreed")
	_p(sim, "walt").downed = true
	Helpers.run(sim, 5.0)
	eq(sim.scavenge.parties.size(), 1, "the errand leaves")
	eq(sim.scavenge.parties[0].members, ["dez"], "without Walt, who is down")
	_free(g)


func test_an_errand_with_nobody_left_could_not_start() -> void:
	var g := _game()
	var sim = g.sim
	sim.radio.request_errand([_p(sim, "dez")], "houses")
	_p(sim, "dez").downed = true
	Helpers.run(sim, 5.0)
	check(sim.scavenge.parties.is_empty(), "nobody goes")
	var told := _news(sim, "errand")
	eq(told.size(), 1, "it is logged")
	check(String(told[0].text).begins_with("The errand could not start: "), str(told[0].text))
	_free(g)


func test_the_errand_takes_people_off_their_stance_and_pending_verbs() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	sim.radio.set_stance(dez, "follow")
	check(sim.radio.request(dez, "hold").ok, "a verb is asked first")
	eq(sim.radio.pending.size(), 1, "and waits")
	var r: Dictionary = sim.radio.request_errand([dez], "houses")
	check(r.ok, "then the errand (it replaces the verb)")
	eq(sim.radio.pending.size(), 0, "the verb is dropped")
	Helpers.run(sim, 5.0)
	eq(sim.scavenge.parties.size(), 1, "Dez is off")
	eq(String(dez.stance), "", "with no stance")
	_free(g)


func test_a_second_errand_for_the_same_person_replaces_the_first() -> void:
	var g := _town()    # (two parties may be out: the classic start's one would refuse the second errand at the asking)
	var sim = g.sim
	check(sim.radio.request_errand([_p(sim, "dez"), _p(sim, "marcus")], "houses").ok, "the first is asked")
	check(sim.radio.request_errand([_p(sim, "dez")], "pharmacy").ok, "and the second")
	eq(sim.radio.errand_wait.size(), 2, "two entries")
	eq(sim.radio.errand_wait[0].ids, ["marcus"], "Dez is taken out of the first")
	eq(sim.radio.errand_wait[1].ids, ["dez"], "and is in the second")
	_free(g)


func test_with_no_avatar_an_errand_is_refused_and_nothing_waits() -> void:
	var g := Helpers.make(1, 1, 6)
	var sim = g.sim
	var r: Dictionary = sim.radio.request_errand([_p(sim, "dez")], "houses")
	check(not r.ok, "nobody is on the radio")
	check(sim.radio.errand_wait.is_empty(), "and nothing is queued")
	for what in [sim.radio.request_job(_p(sim, "dez"), "garden"), sim.radio.request_post(_p(sim, "dez"), "gate"), sim.radio.request_fill(), sim.radio.request_build("workshop")]:
		check(not what.ok, "no request is taken with no player: %s" % str(what))
	_free(g)


func test_the_errand_wait_survives_a_save_and_a_bad_entry_is_dropped() -> void:
	var a := _game()
	var sim = a.sim
	var r: Dictionary = sim.radio.request_errand([_p(sim, "dez"), _p(sim, "walt")], "houses", "loot")
	check(r.ok, "an errand waits")
	# (the classic start's one party refuses a second errand at the asking: the entry is put in by hand, as a game with two parties would have it)
	check(not sim.radio.request_errand([_p(sim, "hector")], "pharmacy", "loot").ok, "a second errand is refused at the asking in the classic start")
	sim.radio.errand_wait.append({"ids": ["hector"], "place": "pharmacy", "action": "loot", "vehicle": "", "left": 2.0})
	var d := SaveGame.to_dict(sim)
	var saved: Dictionary = d.modules.radio
	check(saved.has("errand_wait"), "the radio saves it")
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads")
	var wait: Array = b.sim.radio.errand_wait
	eq(wait.size(), 2, "both entries are back")
	eq(wait[0].ids, ["dez", "walt"], "the ids")
	eq(String(wait[0].place), "houses", "the place")
	eq(String(wait[0].action), "loot", "the action")
	eq(String(wait[1].place), "pharmacy", "and the second's place")
	near(float(wait[0].left), float(sim.radio.errand_wait[0].left), 0.0001, "the time left")
	# the loaded game carries on: the party leaves after the delay (the classic start has one party out at a time: the second could not start)
	_at(b.sim, 3, 9.0)
	Helpers.run(b.sim, 6.0)
	eq(b.sim.scavenge.parties.size(), 1, "the errand that was waiting leaves after the load")
	eq(b.sim.scavenge.parties[0].members, ["dez", "walt"], "the first one")
	var late: Array = []
	for e in b.sim.radio.news:
		if e.kind == "errand" and String(e.text).begins_with("The errand could not start"):
			late.append(e)
	eq(late.size(), 1, "the second says it could not start (a party is already out): %s" % str(late))
	# a damaged file: bad entries are dropped, good ones kept
	var bad: Dictionary = saved.duplicate(true)
	bad["errand_wait"] = [
		{"ids": ["dez"], "place": "houses", "action": "loot", "vehicle": "", "left": 1.0},
		{"ids": "dez", "place": "houses", "action": "loot", "vehicle": "", "left": 1.0},
		{"ids": ["dez"], "place": 5, "action": "loot", "vehicle": "", "left": 1.0},
		{"ids": ["dez"], "place": "houses", "action": "juggle", "vehicle": "", "left": 1.0},
		{"ids": ["dez"], "place": "houses", "action": "loot", "vehicle": "", "left": "soon"},
		{"ids": ["nobody"], "place": "houses", "action": "loot", "vehicle": "", "left": 1.0},
		{"ids": ["walt", "nobody"], "place": "pharmacy", "action": "loot", "vehicle": "", "left": 2.0},
		"junk",
		{"place": "houses"},
	]
	var c := _bare()
	var dd := SaveGame.to_dict(sim)
	dd.modules.radio = bad
	check(SaveGame.apply(c.sim, dd), "a damaged radio still loads")
	eq(c.sim.radio.errand_wait.size(), 2, "two sound entries are kept: %s" % str(c.sim.radio.errand_wait))
	eq(c.sim.radio.errand_wait[1].ids, ["walt"], "an unknown id is dropped from an entry")
	# a save from before has none
	var old: Dictionary = saved.duplicate(true)
	old.erase("errand_wait")
	var e := _bare()
	var de := SaveGame.to_dict(sim)
	de.modules.radio = old
	check(SaveGame.apply(e.sim, de), "a save from round 17 loads")
	check(e.sim.radio.errand_wait.is_empty(), "with nothing waiting")
	for x in [a, b, c, e]:
		_free(x)


func test_the_errand_wait_keeps_its_action_and_vehicle_through_a_save() -> void:
	var g := _town()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	sim.vehicles.fuel = 100.0
	check(sim.radio.request_errand([_p(sim, "dez")], "houses", "scout").ok, "a scouting errand")
	check(sim.radio.request_errand([_p(sim, "marcus")], "far", "loot", String(v.id)).ok, "and one by pickup")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.radio.save()))
	sim.radio.errand_wait.clear()
	sim.radio.load_state(saved)
	eq(sim.radio.errand_wait.size(), 2, "both are back")
	eq(String(sim.radio.errand_wait[0].action), "scout", "the action")
	eq(String(sim.radio.errand_wait[1].vehicle), String(v.id), "the vehicle")
	eq(String(sim.radio.errand_wait[1].place), "far", "the place")
	_free(g)


# ----------------------------------------------------------------- the jobs --

func test_job_willingness_says_yes_in_the_tone_of_trust() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	for case in [[85.0, "willing", "Right away."], [40.0, "grudging", "Fine. I'll do it."], [10.0, "doubtful", "...if you say so."]]:
		ana.trust = case[0]
		var w: Dictionary = sim.radio.job_willingness(ana, "garden")
		check(w.ok and not w.hard and w.why == "", "Ana will tend the garden: %s" % str(w))
		eq(String(w.tone), String(case[1]), "the tone at trust %s" % str(case[0]))
		eq(String(w.line), String(case[2]), "the line")
		near(float(w.delay_s), 0.0, 0.0001, "a roster change is answered at once")
	_free(g)


func test_job_willingness_refuses_for_each_reason_in_words() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var hard := ["downed", "dead", "turned", "away", "breakdown", "leaving", "party"]
	for which in CONDITIONS:
		_condition(sim, dez, which)
		var w: Dictionary = sim.radio.job_willingness(dez, "garden")
		check(not w.ok, "%s: no job (%s)" % [which, str(w)])
		eq(w.hard, hard.has(which), "%s is %s" % [which, "hard" if hard.has(which) else "soft"])
		eq(String(w.why), String(sim.radio.reason_not(dez, "work").why), "%s: the reason is `reason_not`'s" % which)
		check(String(w.why) != "", "with words")
		eq(w.tone, "refused", "the tone")
		_clear(sim, dez)
	var ana_why: String = ""
	_tend(sim)
	ana_why = sim.radio.job_willingness(_p(sim, "ana"), "bench").why
	eq(ana_why, "Ana: tending a patient, can't take a job now", "the example of the plan")
	_free(g)


func test_a_full_station_names_its_crew_and_cannot_be_insisted() -> void:
	var g := _game()
	var sim = g.sim
	sim.jobs.assign(_p(sim, "walt"), "bench")    # the bench has two seats: Dez and Walt
	var w: Dictionary = sim.radio.job_willingness(_p(sim, "hector"), "bench")
	check(not w.ok and w.hard, "no seat left")
	eq(String(w.why), "no free seat at the Workbench: Dez and Walt hold it", "the crew is named")
	# the radio desk has one seat and Hector holds it (he took Ruth's when she became the player)
	eq(sim.jobs.job_of(_p(sim, "hector")), "radio", "Hector is at the radio desk")
	var one: Dictionary = sim.radio.job_willingness(_p(sim, "ana"), "radio")
	eq(String(one.why), "no free seat at the Radio desk: Hector holds it", "a single holder, singular")
	var ana = _p(sim, "ana")
	ana.bleeding = 4.0
	ana.wounds = 1
	var both: Dictionary = sim.radio.job_willingness(ana, "radio")
	check(not both.ok and both.hard and String(both.why).begins_with("no free seat"), "a bleeding person asking for a full seat is told the seat is full (insisting cannot help): %s" % str(both))
	var r: Dictionary = sim.radio.request_job(ana, "radio", {"insist": true})
	check(not r.ok, "insisting does not make a seat")
	near(ana.trust, 55.0, 0.0001, "and costs nothing")
	eq(sim.jobs.job_of(ana), "infirmary", "and she keeps her job")
	_free(g)


func test_a_station_that_is_not_built_says_so() -> void:
	var g := _game()
	var sim = g.sim
	var w: Dictionary = sim.radio.job_willingness(_p(sim, "dez"), "salvage")
	check(not w.ok and w.hard, "no salvage bench yet")
	eq(String(w.why), "the salvage bench is not built yet", "in the jobs module's words: %s" % str(w.why))
	check(not sim.radio.job_willingness(_p(sim, "dez"), "nothing").ok, "no such job")
	_free(g)


func test_the_player_is_never_given_a_seat() -> void:
	var g := _game()
	var sim = g.sim
	var w: Dictionary = sim.radio.job_willingness(_p(sim, "ruth"), "garden")
	check(not w.ok and w.hard, "the player has no seat")
	eq(String(w.why), "You: no seat, you are the player", "in the plan's words")
	var p: Dictionary = sim.radio.post_willingness(_p(sim, "ruth"), "barricade")
	check(not p.ok and p.hard, "nor a post of the radio's giving")
	check(not sim.radio.request_job(_p(sim, "ruth"), "garden").ok, "and nothing is set")
	eq(String(sim.jobs.job_of(_p(sim, "ruth"))), "", "she has none")
	_free(g)


func test_request_job_gives_the_job_after_asking_and_says_it() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var r: Dictionary = sim.radio.request_job(ana, "garden")
	check(r.ok, "agreed: %s" % str(r))
	eq(String(r.line), "Right away.", "willing")
	eq(String(sim.jobs.job_of(ana)), "garden", "the job is hers")
	eq(r.insisted, false, "no push")
	var said := _first_event(sim, "radio_line")
	eq(String(said.get("who", "")), "ana", "she says it")
	var seat_events := 0
	for e in sim.events:
		if e.type == "assigned":
			seat_events += 1
	eq(seat_events, 1, "the roster says so too")
	near(ana.trust, 55.0, 0.0001, "asking costs nothing")
	# already on the job: not an error
	check(sim.radio.request_job(ana, "garden").ok, "the same job again")
	_free(g)


func test_request_job_soft_refusal_and_insisting() -> void:
	var g := _game()
	var sim = g.sim
	_tend(sim)
	var ana = _p(sim, "ana")
	var r: Dictionary = sim.radio.request_job(ana, "garden")
	check(not r.ok and not r.hard, "refused softly")
	eq(String(r.why), "Ana: tending a patient, can't take a job now", "with the reason")
	eq(String(sim.jobs.job_of(ana)), "infirmary", "the job did not change")
	eq(r.insisted, false, "not pushed")
	var pushed: Dictionary = sim.radio.request_job(ana, "garden", {"insist": true})
	check(pushed.ok and pushed.insisted, "pushed")
	eq(String(pushed.line), "...if you say so.", "grudgingly")
	eq(String(sim.jobs.job_of(ana)), "garden", "and the job is hers")
	near(ana.trust, 49.0, 0.0001, "six trust")
	_free(g)


func test_request_job_hard_refusal_cannot_be_pushed() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.downed = true
	var r: Dictionary = sim.radio.request_job(dez, "garden", {"insist": true})
	check(not r.ok and r.hard, "down: no")
	eq(String(sim.jobs.job_of(dez)), "bench", "the job is unchanged")
	near(dez.trust, 55.0, 0.0001, "and nothing is paid")
	_free(g)


func test_taking_someone_off_their_job_passes_the_soft_reasons() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.bleeding = 4.0
	dez.wounds = 1
	var w: Dictionary = sim.radio.job_willingness(dez, "")
	check(w.ok, "a bleeding man can be taken off the bench: %s" % str(w))
	check(sim.radio.request_job(dez, "").ok, "and is")
	eq(String(sim.jobs.job_of(dez)), "", "no job")
	dez.downed = true
	check(not sim.radio.job_willingness(dez, "").ok, "but not one who is down")
	_free(g)


func test_trust_sets_the_line_of_a_job() -> void:
	var g := _game()
	var sim = g.sim
	var lines := {}
	for t in [90.0, 40.0, 5.0]:
		var ana = _p(sim, "ana")
		ana.trust = t
		sim.jobs.assign(ana, "infirmary")
		lines[t] = String(sim.radio.request_job(ana, "garden").line)
	eq(lines[90.0], "Right away.", "willing")
	eq(lines[40.0], "Fine. I'll do it.", "grudging")
	eq(lines[5.0], "...if you say so.", "doubtful")
	_free(g)


# ----------------------------------------------------------------- the posts --

func test_a_post_held_by_someone_else_names_the_holder() -> void:
	var g := _game()
	var sim = g.sim
	var w: Dictionary = sim.radio.post_willingness(_p(sim, "ana"), "bus")
	check(not w.ok and w.hard, "Dez holds the bus post")
	eq(String(w.why), "Dez holds that post", "named")
	var mine: Dictionary = sim.radio.post_willingness(_p(sim, "ana"), "west_fence")
	check(mine.ok, "her own post is hers to take again")
	check(sim.radio.post_willingness(_p(sim, "ana"), "north_west_end").ok, "a free post")
	var lead: Dictionary = sim.radio.post_willingness(_p(sim, "ana"), "gate")
	check(not lead.ok and lead.hard and String(lead.why) == "You hold that post", "the player's post is the player's: %s" % str(lead.why))
	check(not sim.radio.post_willingness(_p(sim, "ana"), "nowhere").ok, "no such post")
	var dead_holder = _p(sim, "dez")
	dead_holder.dead = true
	check(sim.radio.post_willingness(_p(sim, "ana"), "bus").ok, "a dead man's post is free")
	_free(g)


func test_request_post_applies_after_asking() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	ana.trust = 90.0
	var r: Dictionary = sim.radio.request_post(ana, "north_west_end")
	check(r.ok, "agreed: %s" % str(r))
	eq(String(r.line), "Right away.", "in the tone of trust")
	eq(String(sim.jobs.post_of(ana).id), "north_west_end", "the post is hers")
	var no: Dictionary = sim.radio.request_post(ana, "bus")
	check(not no.ok and no.hard, "a held post is refused")
	eq(String(sim.jobs.post_of(ana).id), "north_west_end", "and nothing changes")
	# a soft reason can be insisted, a held post not
	ana.bleeding = 4.0
	ana.wounds = 1
	var soft: Dictionary = sim.radio.request_post(ana, "west_south")
	check(not soft.ok and not soft.hard, "bleeding: a soft refusal")
	eq(String(soft.why), "Ana: bleeding, can't take a post now", "the post words")
	var pushed: Dictionary = sim.radio.request_post(ana, "west_south", {"insist": true})
	check(pushed.ok and pushed.insisted, "pushed")
	near(ana.trust, 84.0, 0.0001, "six trust")
	var held: Dictionary = sim.radio.request_post(ana, "bus", {"insist": true})
	check(not held.ok, "insisting does not take a held post")
	near(ana.trust, 84.0, 0.0001, "and costs nothing")
	_free(g)


# ------------------------------------------------------------ fill empty seats --

func test_fill_empty_fills_by_skill_never_clears_and_skips_the_player() -> void:
	var g := _game()
	var sim = g.sim
	sim.jobs.clear()
	for case in [["ana", "infirmary"], ["marcus", "watch"], ["walt", "builders"], ["hector", "radio"]]:
		check(sim.jobs.assign(_p(sim, case[0]), case[1]), "%s is given the %s" % [case[0], case[1]])
	var kept := {}
	for p in sim.people:
		kept[p.id] = sim.jobs.job_of(p)
	eq(String(kept.dez), "", "Dez (Building 9) has no job")
	# one more with no job: Walt (Building 3) leaves the Builders, so that two with no job meet the seats
	sim.jobs.unassign(_p(sim, "walt"))
	kept.walt = ""
	var filled: int = sim.jobs.fill_empty()
	check(filled >= 2, "the empty seats are filled (%d)" % filled)
	eq(String(sim.jobs.job_of(_p(sim, "dez"))), "bench", "the best builder (Dez, Building 9) has the bench, first in the order")
	check(String(sim.jobs.job_of(_p(sim, "walt"))) != "", "Walt has a seat")
	for id in ["ana", "marcus", "hector"]:
		eq(String(sim.jobs.job_of(_p(sim, id))), String(kept[id]), "%s keeps their job" % id)
	eq(String(sim.jobs.job_of(_p(sim, "ruth"))), "", "the player is never given a seat")
	eq(sim.jobs.fill_empty(), 0, "nothing more to fill: nobody is free")
	_free(g)


func test_fill_empty_does_not_use_those_it_is_told_to_skip() -> void:
	var g := _game()
	var sim = g.sim
	sim.jobs.unassign(_p(sim, "ana"))
	sim.jobs.unassign(_p(sim, "marcus"))
	var n: int = sim.jobs.fill_empty(["ana"])
	check(n >= 1, "a seat is filled")
	eq(String(sim.jobs.job_of(_p(sim, "ana"))), "", "but not with Ana, who is to be left out")
	eq(String(sim.jobs.job_of(_p(sim, "marcus"))) != "", true, "Marcus has a seat")
	_free(g)


func test_fill_empty_leaves_the_people_who_are_down_or_away_alone() -> void:
	var g := _game()
	var sim = g.sim
	sim.jobs.unassign(_p(sim, "marcus"))
	sim.jobs.unassign(_p(sim, "ana"))
	_p(sim, "marcus").downed = true
	_p(sim, "ana").away = {"kind": "trip"}
	eq(sim.jobs.fill_empty(), 0, "nobody who is down or away takes a seat")
	_free(g)


func test_fill_willingness_lists_the_seats_the_willing_and_the_stuck() -> void:
	var g := _game()
	var sim = g.sim
	for id in ["walt", "marcus", "ana"]:
		sim.jobs.unassign(_p(sim, id))
	_tend(sim)    # Ana is also a nurse on a case: she has no job now but is still tending
	_p(sim, "marcus").downed = true
	var w: Dictionary = sim.radio.fill_willingness()
	var seat_ids: Array = []
	for s in w.seats:
		seat_ids.append(String(s.station))
		check(int(s.left) > 0, "a seat is open at %s" % s.station)
	check(seat_ids.has("watch") and seat_ids.has("infirmary") and seat_ids.has("builders"), "the stations with open seats: %s" % str(seat_ids))
	eq(w.free, ["walt"], "Walt would take one")
	var stuck := {}
	for s in w.stuck:
		stuck[String(s.id)] = s
	check(stuck.has("ana") and stuck.has("marcus") and stuck.size() == 2, "Ana and Marcus are stuck: %s" % str(w.stuck))
	eq(String(stuck.marcus.why), "Marcus is down", "with words")
	eq(String(stuck.ana.why), "Ana: tending a patient, can't take a job now", "and Ana's")
	check(not stuck.has("ruth"), "the player is not on the list")
	_free(g)


func test_request_fill_fills_and_reports_who_could_not() -> void:
	var g := _game()
	var sim = g.sim
	for id in ["walt", "marcus", "ana"]:
		sim.jobs.unassign(_p(sim, id))
	_tend(sim)
	_p(sim, "marcus").downed = true
	var jobs_before := {}
	for p in sim.people:
		jobs_before[p.id] = sim.jobs.job_of(p)
	var r: Dictionary = sim.radio.request_fill()
	check(r.ok, "a seat was filled: %s" % str(r))
	eq(r.assigned.size(), 1, "one person")
	eq(String(r.assigned[0].who), "walt", "Walt")
	check(String(r.assigned[0].station) != "", "at a station")
	eq(String(sim.jobs.job_of(_p(sim, "walt"))), String(r.assigned[0].station), "and he has it")
	var stuck := {}
	for s in r.stuck:
		stuck[String(s.id)] = String(s.why)
	check(stuck.has("ana") and stuck.has("marcus"), "Ana and Marcus could not: %s" % str(r.stuck))
	eq(stuck.ana, "Ana: tending a patient, can't take a job now", "why")
	for p in sim.people:
		if jobs_before[p.id] != "":
			eq(String(sim.jobs.job_of(p)), String(jobs_before[p.id]), "%s was not taken off their job" % p.first)
	check(String(r.line) != "", "a line to show: %s" % str(r.line))
	var again: Dictionary = sim.radio.request_fill()
	check(not again.ok and again.assigned.is_empty(), "nothing more to fill")
	_free(g)


func test_request_fill_with_nobody_free_says_so() -> void:
	var g := _game()
	var sim = g.sim
	sim.jobs.auto_assign()    # everybody but the player has a job
	eq(String(sim.jobs.job_of(_p(sim, "ruth"))), "", "the player has none")
	var w: Dictionary = sim.radio.fill_willingness()
	check(w.free.is_empty() and w.stuck.is_empty(), "nobody is without a job: the player does not count")
	var r: Dictionary = sim.radio.request_fill()
	check(not r.ok and r.assigned.is_empty(), "nothing is filled")
	eq(String(r.line), "Nobody without a job can take a seat now.", "and it says why")
	eq(String(sim.jobs.job_of(_p(sim, "ruth"))), "", "the player has been given no seat")
	_free(g)


# ----------------------------------------------------------------- the build --

func test_build_willingness_says_what_it_needs() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 100.0
	var w: Dictionary = sim.radio.build_willingness("workshop")
	check(w.ok, "the workshop can be ordered: %s" % str(w))
	eq(String(w.why), "", "no reason against")
	eq(String(w.plot), String(sim.build.home_for("workshop")), "on its home")
	eq(int(w.cost), 30, "for 30 scrap")
	sim.stock.scrap = 10.0
	var poor: Dictionary = sim.radio.build_willingness("workshop")
	check(not poor.ok, "not enough scrap")
	eq(String(poor.why), "it needs 30 scrap", "in the build module's words")
	eq(String(poor.why), String(sim.build.why_not_build("workshop")), "which are its")
	sim.stock.scrap = 100.0
	# the catalogue is shared by every game of the process (build.gd's cache): the made-up rule is put back at once
	var tower: Dictionary = sim.build.building("watchtower")
	var had_requires = tower["requires"]
	tower["requires"] = "workshop"
	var needs: Dictionary = sim.radio.build_willingness("watchtower")
	tower["requires"] = had_requires
	eq(String(needs.why), "it needs the workshop first", "a prerequisite")
	var nothing: Dictionary = sim.radio.build_willingness("nowhere")
	check(not nothing.ok and String(nothing.why) == "there is no such building", "an unknown building: %s" % str(nothing))
	# one of a kind: once it is ordered, there is already one
	check(sim.build.order(String(w.plot), "workshop"), "ordered by hand")
	var twice: Dictionary = sim.radio.build_willingness("workshop")
	check(not twice.ok and String(twice.why).begins_with("there is already"), "only one: %s" % str(twice.why))
	_free(g)


func test_a_lot_that_is_not_claimed_is_a_reason_in_the_settlement_game() -> void:
	var g := Helpers.make(1, 1, 3)
	var sim = g.sim
	sim.stock.scrap = 100.0
	var w: Dictionary = sim.radio.build_willingness("scrap_yard")
	check(not w.ok and String(w.why).begins_with("claim") and String(w.why).ends_with("first"), "claim the lot first: %s" % str(w.why))
	_free(g)


func test_the_crew_note_is_advice_never_a_refusal() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 100.0
	var walt = _p(sim, "walt")
	eq(String(sim.radio.build_willingness("workshop").note), "", "Walt is on the Builders job: nothing to say")
	sim.jobs.unassign(walt)
	var none: Dictionary = sim.radio.build_willingness("workshop")
	check(none.ok, "no builders is not a refusal")
	eq(String(none.note), "Nobody is on the Builders job: give it to someone on the Jobs page, or the site waits", "the plan's words")
	sim.jobs.assign(walt, "builders")
	walt.downed = true
	var down: Dictionary = sim.radio.build_willingness("workshop")
	check(down.ok, "a builder who is down is not a refusal either")
	eq(String(down.note), "Walt is the only builder and is down", "the one builder")
	sim.jobs.assign(_p(sim, "hector"), "builders")
	var two: Dictionary = sim.radio.build_willingness("workshop")
	eq(String(two.note), "", "with a second builder on his feet there is nothing to say")
	_free(g)


func test_request_build_orders_pays_and_tells_in_the_lead_builders_words() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 100.0
	var walt = _p(sim, "walt")
	walt.trust = 85.0
	var plot := String(sim.build.home_for("workshop"))
	var r: Dictionary = sim.radio.request_build("workshop")
	check(r.ok, "ordered: %s" % str(r))
	eq(String(r.plot), plot, "on its home")
	eq(String(r.line), "On it.", "the lead builder says it, in a willing voice")
	near(float(sim.stock.scrap), 70.0, 0.0001, "30 scrap paid")
	check(not sim.build.plot(plot).site.is_empty(), "a site stands on the plot")
	eq(String(sim.build.plot(plot).site.building), "workshop", "for the workshop")
	var told := _news(sim, "build")
	eq(told.size(), 1, "the radio logs it")
	check(String(told[0].text).contains("Workshop"), "naming the building: %s" % str(told[0]))
	var said := _first_event(sim, "radio_line")
	eq(String(said.get("who", "")), "walt", "Walt said it")
	var again: Dictionary = sim.radio.request_build("workshop")
	check(not again.ok and String(again.why) != "" and String(again.line) == "", "a second one is refused with its reason: %s" % str(again))
	near(float(sim.stock.scrap), 70.0, 0.0001, "and nothing more is paid")
	eq(_news(sim, "build").size(), 1, "and nothing more is logged")
	_free(g)


func test_request_build_with_nobody_to_build_says_the_site_waits() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 100.0
	sim.jobs.unassign(_p(sim, "walt"))
	var r: Dictionary = sim.radio.request_build("tents")
	check(r.ok, "it is ordered all the same")
	check(String(r.line).contains("Builders"), "and says why nobody answers: %s" % str(r.line))
	_free(g)


func test_request_build_refused_changes_nothing() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 5.0
	var r: Dictionary = sim.radio.request_build("workshop")
	check(not r.ok, "not enough scrap")
	eq(String(r.why), "it needs 30 scrap", "the reason")
	near(float(sim.stock.scrap), 5.0, 0.0001, "nothing paid")
	eq(_news(sim, "build").size(), 0, "nothing logged")
	_free(g)
