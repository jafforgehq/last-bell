## Scavenging: the sites, sending a party, the walk to the gate, the trip and
## its return, loot, injuries and losses, and saving in the middle of a trip.
extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const MedicalModule := preload("res://scripts/sim/medical.gd")


## The medical module as scavenging sees it: it records every wound and death
## that is asked for and then does whatever the real module does. `stages`
## fakes the infection stage of a person (by id).
class Recorder:
	extends MedicalModule
	var wounds: Array = []
	var kills: Array = []
	var stages := {}
	## People (by id) the fake says are busy treating someone.
	var busy := {}

	func goal_for(p):
		if busy.has(p.id):
			return {"x": p.x, "y": p.y, "face": "", "what": "Bandaging someone"}
		return super.goal_for(p)

	func add_wound(p, kind: String) -> void:
		wounds.append([p.id, kind])
		super.add_wound(p, kind)

	func kill(p, cause: String) -> void:
		kills.append([p.id, cause])
		super.kill(p, cause)

	func infection_stage(p) -> String:
		return String(stages.get(p.id, ""))


## A supplies module that does nothing, for tests that look at the stock across
## a meal time.
class NoSupplies:
	extends RefCounted

	func setup(_s) -> void:
		pass

	func start() -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func perf(_p) -> float:
		return 1.0

	func repair_budget(amount: float) -> float:
		return amount

	func days_left(_kind: String) -> float:
		return 99.0

	func status_of(_p) -> Array:
		return []

	func save() -> Dictionary:
		return {}

	func load_state(_d: Dictionary) -> void:
		pass


# ------------------------------------------------------------------ helpers --

func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## Sets the time of day by hand (the trip timers are relative to the clock, so
## this is safe for tests that only look at the window).
func _at(sim, hour: float) -> void:
	sim.minutes = hour * 60.0
	sim.phase = Sim.phase_at(sim.minutes)


func _record(sim) -> Recorder:
	var rec := Recorder.new()
	rec.setup(sim)
	sim.medical = rec
	return rec


## Steps until `cond` is true or `seconds` have passed; says whether it became true.
func _until(sim, cond: Callable, seconds: float) -> bool:
	for i in int(seconds * 30.0):
		if cond.call():
			return true
		sim.update(1.0 / 30.0)
	return cond.call()


## Steps at 15 a second (the balance harness's fast rate).
func _run15(sim, seconds: float) -> void:
	for i in int(seconds * 15.0):
		sim.update(1.0 / 15.0)


func _via_json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


## Sends `who` to the site at 07:00 and gives the party a result chosen by hand.
func _send_with(sim, who: Array, site_id: String, loot: Dictionary, hurt: Dictionary, lost: Array) -> Dictionary:
	_at(sim, 7.0)
	check(sim.scavenge.send(who, site_id), "the party is sent")
	var party: Dictionary = sim.scavenge.parties[0]
	party.result = {"loot": loot, "hurt": hurt, "lost": lost}
	return party


## Steps until the party list is empty (the return step), with the stock as it
## was just before that step. Returns that stock.
func _run_until_back(sim, max_seconds: float) -> Dictionary:
	var before: Dictionary = sim.stock.duplicate()
	for i in int(max_seconds * 30.0):
		if sim.scavenge.parties.is_empty():
			break
		before = sim.stock.duplicate()
		sim.update(1.0 / 30.0)
	return before


func _banner_with(sim, text: String) -> bool:
	for e in sim.events:
		if e.type == "banner" and String(e.text).contains(text):
			return true
	return false


# -------------------------------------------------------------------- sites --

func test_the_three_sites_load_from_data() -> void:
	var g := Helpers.make(1, 1)
	var sites: Array = g.sim.scavenge.sites
	eq(sites.size(), 3, "three sites")
	var by := {}
	for s in sites:
		by[s.id] = s
		check(String(s.name) != "", "%s has a name" % s.id)
		check(String(s.blurb).length() > 20, "%s has a line of flavour" % s.id)
		check(String(s.image) == "res://assets/ui/sites/%s.png" % s.id, "%s has its picture path" % s.id)
		check(FileAccess.file_exists(String(s.image)), "%s has its picture" % s.id)
	check(by.has("pharmacy") and by.has("hardware") and by.has("houses"), "pharmacy, hardware and houses")
	eq(by.pharmacy.name, "The pharmacy", "the pharmacy's name")
	eq(by.hardware.name, "The hardware store", "the hardware store's name")
	eq(by.houses.name, "Neighbourhood houses", "the houses' name")
	eq([by.pharmacy.danger, by.hardware.danger, by.houses.danger], [2, 2, 1], "danger 2, 2 and 1")
	eq(by.pharmacy.loot.meds, [3, 6], "3 to 6 meds")
	eq(by.hardware.loot.scrap, [10, 20], "10 to 20 scrap")
	eq(by.hardware.loot.ammo, [20, 60], "20 to 60 ammo")
	eq(by.houses.loot.food, [8, 14], "8 to 14 food")
	eq(by.houses.loot.water, [10, 20], "10 to 20 water")
	check(by.pharmacy.extra.has("food"), "the pharmacy sometimes has food")
	check(by.houses.extra.has("meds"), "the houses sometimes have a med")
	eq(by.houses.extra.meds[1], 1, "and it is one med")
	g.world.free()


func test_available_sites_carry_what_the_hud_needs() -> void:
	var g := Helpers.make(1, 1)
	var list: Array = g.sim.scavenge.available_sites()
	eq(list.size(), 3, "three sites to pick from")
	var hints := {}
	for s in list:
		for k in ["id", "name", "blurb", "danger", "loot_hint", "available", "note", "image"]:
			check(s.has(k), "%s has %s" % [s.id, k])
		check(s.available, "%s is open on day 1" % s.id)
		hints[s.id] = String(s.loot_hint).to_lower()
	check(hints.pharmacy.contains("meds"), "the pharmacy is good for meds: " + hints.pharmacy)
	check(hints.hardware.contains("scrap") and hints.hardware.contains("ammo"), "the hardware store for scrap and ammo: " + hints.hardware)
	check(hints.houses.contains("food") and hints.houses.contains("water"), "the houses for food and water: " + hints.houses)
	g.world.free()


# ------------------------------------------------------------ when and who --

func test_can_send_only_in_the_morning_window() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	for c in [[6.49, false], [6.5, true], [7.0, true], [9.99, true], [10.0, false], [13.0, false], [18.9, false], [19.5, false], [23.0, false], [3.0, false], [6.0, false]]:
		_at(sim, c[0])
		eq(sim.scavenge.can_send(), c[1], "can_send at %.2f" % c[0])
	g.world.free()


func test_why_not_says_why() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	var sc = sim.scavenge
	eq(sc.why_not(), "", "nothing to explain when a party can go")
	_at(sim, 11.0)
	check(sc.why_not().to_lower().contains("late"), "after ten it is too late: '%s'" % sc.why_not())
	_at(sim, 21.0)
	check(sc.why_not().to_lower().contains("dark"), "nobody goes out after dark: '%s'" % sc.why_not())
	_at(sim, 6.0)
	check(sc.why_not().to_lower().contains("early"), "at dawn it is too early: '%s'" % sc.why_not())
	_at(sim, 7.0)
	for p in sim.people:
		p.downed = true
	check(sc.why_not().to_lower().contains("free"), "nobody is free: '%s'" % sc.why_not())
	check(not sc.can_send(), "and so nobody can be sent")
	for p in sim.people:
		p.downed = false
	check(sc.send([_p(sim, "dez")], "houses"), "a party goes")
	check(sc.why_not().to_lower().contains("already out"), "a party is already out: '%s'" % sc.why_not())
	g.world.free()


func test_a_crowd_of_the_dead_at_the_gate_blocks_sending() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var gate: Vector2 = sc.gate_center()
	sim.spawn(gate.x, gate.y - 8.0, "wander")
	sim.spawn(gate.x + 10.0, gate.y - 9.0, "wander")
	check(sc.can_send(), "two of the dead at the gate are not enough to stop a party")
	var third = sim.spawn(gate.x - 12.0, gate.y - 3.0, "wander")
	check(not sc.can_send(), "three within 20 tiles stop it")
	check(sc.why_not().to_lower().contains("dead at the gate"), "and it says so: '%s'" % sc.why_not())
	check(not sc.send([_p(sim, "dez")], "houses"), "nobody is sent")
	third.state = "dying"
	check(sc.can_send(), "a walker that has been put down does not count")
	third.state = "wander"
	third.x = gate.x
	third.y = gate.y - 25.0
	check(sc.can_send(), "one 25 tiles away does not count")
	third.x = gate.x + 19.0
	third.y = gate.y
	check(not sc.can_send(), "one at 19 tiles does")
	g.world.free()


func test_send_refuses_people_who_cannot_go() -> void:
	for what in ["dead", "downed", "away", "drafted", "delirious", "busy"]:
		var g := Helpers.make(2, 1)
		var sim = g.sim
		var rec := _record(sim)
		var sc = sim.scavenge
		var victim = _p(sim, "hector")
		var other = _p(sim, "dez")
		match what:
			"dead":
				victim.dead = true
			"downed":
				victim.downed = true
			"away":
				victim.away = {"kind": "exile"}
			"drafted":
				sim.toggle_draft(victim)
			"delirious":
				rec.stages[victim.id] = "delirious"
			"busy":
				rec.busy[victim.id] = true
		check(not sc.can_go(victim), "%s: cannot go" % what)
		check(not sc.free_survivors().has(victim), "%s: not among the free" % what)
		check(sc.free_survivors().has(other), "%s: others still are" % what)
		var state: int = sim.rng.state
		check(not sc.send([victim], "houses"), "%s: refused alone" % what)
		check(not sc.send([other, victim], "houses"), "%s: and as a pair" % what)
		check(sc.parties.is_empty(), "%s: no party was made" % what)
		eq(sim.rng.state, state, "%s: a refusal rolls no dice" % what)
		g.world.free()


func test_a_feverish_person_may_still_go() -> void:
	var g := Helpers.make(2, 1)
	var sim = g.sim
	var rec := _record(sim)
	rec.stages["ana"] = "feverish"
	check(g.sim.scavenge.can_go(_p(sim, "ana")), "feverish is not beyond feverish")
	check(sim.scavenge.send([_p(sim, "ana")], "houses"), "and Ana can be sent")
	g.world.free()


func test_send_refuses_bad_requests() -> void:
	var g := Helpers.make(2, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	var ana = _p(sim, "ana")
	var state: int = sim.rng.state
	check(not sc.send([], "houses"), "nobody is not a party")
	check(not sc.send([dez, hector, ana], "houses"), "three are too many")
	check(not sc.send([dez, dez], "houses"), "the same person twice")
	check(not sc.send([dez], "the_moon"), "an unknown site")
	_at(sim, 11.0)
	check(not sc.send([dez], "houses"), "too late in the day")
	_at(sim, 7.0)
	check(sc.parties.is_empty(), "nothing was started")
	eq(sim.rng.state, state, "refusals roll no dice")
	check(sc.send([dez, hector], "houses"), "two is fine")
	g.world.free()


func test_send_takes_one_or_two_and_clears_their_orders() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	sim.order_repair(hector, sim.segments[3])
	check(hector.repair != null, "Hector has a repair order")
	check(sc.send([dez, hector], "houses"), "two are sent")
	eq(sc.parties.size(), 1, "one party")
	var party: Dictionary = sc.parties[0]
	eq(party.members, ["dez", "hector"], "members are the ids, in order")
	eq(party.site, "houses", "to the houses")
	eq(party.state, "out", "they start out walking")
	near(party.return_at - sim.clock_min, 9.0 * 60.0, 0.5, "due back at 16:00, nine game hours after 07:00")
	check(hector.repair == null and not hector.drafted and hector.order == null, "their orders are cleared")
	check(sc.parties[0].result.has("loot"), "the result is decided at once")
	g.world.free()


func test_a_second_party_is_refused_while_one_is_out() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	var sc = sim.scavenge
	check(sc.send([_p(sim, "dez")], "houses"), "the first goes")
	check(not sc.can_send(), "no more can go")
	check(not sc.send([_p(sim, "hector")], "hardware"), "the second is refused")
	check(not sc.can_go(_p(sim, "dez")), "Dez is not free again")
	check(not sc.free_survivors().has(_p(sim, "dez")), "nor listed as free")
	eq(sc.parties.size(), 1, "still one party")
	g.world.free()


# ------------------------------------------------------------------ the trip --

func test_the_party_walks_to_the_gate_and_leaves_the_map() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	check(sc.send([dez, hector], "houses"), "they are sent")
	var gate: Vector2 = sc.gate_center()
	near(gate.x, 39.0, 0.01, "the gate is section 2: centre x")
	near(gate.y, 18.9, 0.01, "and centre y")
	sim.update(1.0 / 30.0)
	eq(dez.activity, "Heading for the gate", "they say where they are going")
	check(dez.moving, "and they walk")
	check(dez.away == null and hector.away == null, "nobody is through yet")
	var dist_at_exit := {}
	for i in 30 * 40:
		sim.update(1.0 / 30.0)
		for p in [dez, hector]:
			if p.away != null and not dist_at_exit.has(p.id):
				dist_at_exit[p.id] = Vector2(p.x, p.y).distance_to(gate)
		if dez.away != null and hector.away != null:
			break
	check(dez.away != null and hector.away != null, "both are through the gate within 40 seconds")
	for id in dist_at_exit:
		var d: float = dist_at_exit[id]
		check(d > 1.0 and d <= 1.2001, "%s went through as they reached 1.2 tiles of the gate (%.2f)" % [id, d])
	eq(sc.parties[0].state, "away", "the party is away once the last one is through")
	eq(dez.away.get("site", ""), "houses", "the away record says where")
	var before := [dez.x, dez.y]
	Helpers.run(sim, 3.0)
	eq([dez.x, dez.y], before, "away people do not move")
	check(not sim.order_move(dez, 50.0, 30.0), "and take no orders")
	g.world.free()


func test_the_party_is_back_at_sixteen_hundred_with_the_loot() -> void:
	var g := Helpers.make(4, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	_at(sim, 7.0)
	check(sc.send([dez, hector], "houses"), "sent at 07:00")
	var party: Dictionary = sc.parties[0]
	var loot: Dictionary = party.result.loot
	check(loot.has("food") and loot.food >= 8 and loot.food <= 14, "food within 8 to 14: %s" % str(loot))
	check(loot.has("water") and loot.water >= 10 and loot.water <= 20, "water within 10 to 20: %s" % str(loot))
	check(not loot.has("scrap") and not loot.has("ammo"), "no scrap or ammo in houses")
	check(loot.get("meds", 0) in [0, 1], "a med or none")
	# both come through safe: the injury rules have their own tests
	party.result.hurt = {}
	party.result.lost = []
	var want: Dictionary = party.result.loot.duplicate()
	Helpers.run_to_hour(sim, 15.9)
	eq(sc.parties.size(), 1, "still away at 15:54")
	check(dez.away != null and hector.away != null, "Dez and Hector are off the map")
	var before := _run_until_back(sim, 60.0)
	check(sc.parties.is_empty(), "the party is settled")
	near(sim.hour, 16.0, 0.02, "at 16:00")
	for id in ["dez", "hector"]:
		var p = _p(sim, id)
		check(p.away == null, "%s is back on the map" % id)
		check(Vector2(p.x, p.y).distance_to(sc.gate_center()) < 0.6, "%s is at the gate" % id)
		check(not p.dead and not p.downed, "%s is well" % id)
	for k in before:
		near(sim.stock[k], before[k] + float(want.get(k, 0)), 0.0001, "%s rose by exactly the loot" % k)
	check(sim.alerts.has("scav-1"), "an alert tells the story")
	var text: String = sim.alerts["scav-1"].text
	check(text.contains("Dez and Hector are back from the houses"), "the story names them and the place: '%s'" % text)
	check(text.contains("food"), "and what they brought: '%s'" % text)
	check(_banner_with(sim, "Back from"), "a banner as well")
	g.world.free()


func test_the_returned_walk_back_to_their_work() -> void:
	var g := Helpers.make(4, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var hector = _p(sim, "hector")
	var party := _send_with(sim, [hector], "houses", {"food": 6}, {}, [])
	check(party.members == ["hector"], "Hector goes alone")
	_run_until_back(sim, 600.0)
	check(hector.away == null, "Hector is back")
	Helpers.run(sim, 40.0)
	var job: Dictionary = hector.def.job
	check(Vector2(hector.x, hector.y).distance_to(Vector2(job.x, job.y)) < 1.0, "he walked back to the garden")
	g.world.free()


# ---------------------------------------------------------------- picked over --

func test_a_raided_site_is_picked_over_for_three_days_and_then_pays_less() -> void:
	var g := Helpers.make(5, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	_send_with(sim, [dez, hector], "houses", {"food": 10}, {}, [])
	_run_until_back(sim, 600.0)
	check(sc.parties.is_empty(), "they are back on day 1")
	var by := {}
	for s in sc.available_sites():
		by[s.id] = s
	check(not by.houses.available, "the houses are picked over")
	check(String(by.houses.note).contains("Picked over") and String(by.houses.note).contains("day 4"), "the note says when: '%s'" % by.houses.note)
	check(by.pharmacy.available and by.hardware.available, "the others are open")
	eq(by.pharmacy.note, "", "and have no note")
	sim.day = 2
	_at(sim, 7.0)
	check(not sc.send([dez], "houses"), "no raid on day 2")
	sim.day = 3
	check(not sc.send([dez], "houses"), "nor on day 3")
	sim.day = 4
	check(sc.send([dez, hector], "houses"), "on day 4 they can go again")
	near(sc.loot_scale("houses", [dez, hector]), 0.75, 0.0001, "but a quarter is gone: a raid three days ago")
	var r: Dictionary = sc.parties[0].result
	check(r.loot.food >= roundi(8 * 0.75) and r.loot.food <= roundi(14 * 0.75), "food is 75%% of 8 to 14: %d" % r.loot.food)
	check(r.loot.water >= roundi(10 * 0.75) and r.loot.water <= roundi(20 * 0.75), "water is 75%% of 10 to 20: %d" % r.loot.water)
	sc.parties.clear()
	var open := {}
	for s in sc.available_sites():
		open[s.id] = s
	check(String(open.houses.note).to_lower().contains("less"), "an open site that was raided says it has less: '%s'" % open.houses.note)
	sim.day = 5
	near(sc.loot_scale("houses", [dez, hector]), 1.0, 0.0001, "four days on it is whole again")
	g.world.free()


func test_a_new_run_forgets_the_raids() -> void:
	var g := Helpers.make(5, 1)
	var sim = g.sim
	var sc = sim.scavenge
	_send_with(sim, [_p(sim, "dez")], "houses", {"food": 10}, {}, [])
	_run_until_back(sim, 600.0)
	check(not sc.available_sites()[2].available, "picked over")
	sim.start_run(1, 9)
	check(sc.parties.is_empty(), "no party")
	for s in sc.available_sites():
		check(s.available, "%s is open again" % s.id)
	g.world.free()


func test_a_lone_scavenger_gets_less_and_a_leader_more() -> void:
	var g := Helpers.make(6, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	var ruth = _p(sim, "ruth")
	var walt = _p(sim, "walt")
	var ana = _p(sim, "ana")
	var marcus = _p(sim, "marcus")
	near(sc.loot_scale("houses", [dez, hector]), 1.0, 0.0001, "two without a leader")
	near(sc.loot_scale("houses", [dez]), 0.7, 0.0001, "one alone gets 70%")
	near(sc.loot_scale("houses", [ruth, dez]), 1.15, 0.0001, "Ruth (Leading 9) adds 15%")
	near(sc.loot_scale("houses", [walt, hector]), 1.15, 0.0001, "Walt (Leading 5) adds 15%")
	near(sc.loot_scale("houses", [ana, marcus]), 1.0, 0.0001, "Ana (Leading 4) does not")
	near(sc.loot_scale("houses", [ruth]), 0.7 * 1.15, 0.0001, "both, alone with Ruth")
	_at(sim, 7.0)
	check(sc.send([dez], "houses"), "Dez goes alone")
	var r: Dictionary = sc.parties[0].result
	check(r.loot.food >= roundi(8 * 0.7) and r.loot.food <= roundi(14 * 0.7), "lone food is 70%% of 8 to 14: %d" % r.loot.food)
	sc.parties.clear()
	check(sc.send([ruth, dez], "houses"), "Ruth and Dez go")
	r = sc.parties[0].result
	check(r.loot.food >= roundi(8 * 1.15) and r.loot.food <= roundi(14 * 1.15), "with a leader food is 115%% of 8 to 14: %d" % r.loot.food)
	g.world.free()


# ------------------------------------------------------------ injuries, losses --

func test_injury_and_loss_rates_follow_the_formula() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var marcus = _p(sim, "marcus")
	var hector = _p(sim, "hector")
	_at(sim, 7.0)
	var n := 2500
	for d in 3:
		sim.difficulty = d
		var mult: float = [0.5, 1.0, 1.6][d]
		for site_id in ["hardware", "houses"]:
			var danger: int = 2 if site_id == "hardware" else 1
			var who := [marcus, hector]
			var counts := [{"scratch": 0, "bite": 0, "lost": 0}, {"scratch": 0, "bite": 0, "lost": 0}]
			var scrap_sum := 0.0
			var ammo_sum := 0.0
			var paid := 0
			for i in n:
				sim.rng.seed = 7000 + i
				sc.parties.clear()
				if not sc.send(who, site_id):
					failures.append("could not send sample %d" % i)
					break
				var r: Dictionary = sc.parties[0].result
				for k in 2:
					var id: String = who[k].id
					if r.lost.has(id):
						counts[k].lost += 1
					elif r.hurt.has(id):
						counts[k][r.hurt[id]] += 1
				if not r.loot.is_empty():
					paid += 1
					scrap_sum += float(r.loot.get("scrap", 0))
					ammo_sum += float(r.loot.get("ammo", 0))
					for v in r.loot.values():
						check(v > 0, "no empty loot entries")
			for k in 2:
				var skill: float = float(who[k].def.skills.Shooting)
				var w := 0.12 * danger * mult * (1.0 - skill / 15.0)
				var l := 0.02 * mult if danger >= 2 else 0.0
				var want_hurt := (1.0 - l) * w
				var label := "difficulty %d, %s, %s" % [d, site_id, who[k].first]
				_rate(counts[k].lost, n, l, "lost, " + label)
				_rate(counts[k].scratch, n, want_hurt * 0.75, "scratched, " + label)
				_rate(counts[k].bite, n, want_hurt * 0.25, "bitten, " + label)
			if site_id == "hardware":
				near(scrap_sum / paid, 15.0, 0.4, "average scrap, difficulty %d" % d)
				near(ammo_sum / paid, 40.0, 1.2, "average ammo, difficulty %d" % d)
			else:
				eq(counts[0].lost + counts[1].lost, 0, "nobody is lost at the houses (difficulty %d)" % d)
	g.world.free()


## Checks that `count` out of `n` is about `p` (within 4.5 standard deviations).
func _rate(count: int, n: int, p: float, label: String) -> void:
	var tol := 4.5 * sqrt(p * (1.0 - p) / float(n)) + 1.0 / float(n)
	var got := float(count) / float(n)
	if absf(got - p) > tol:
		failures.append("%s: expected %.4f +- %.4f, got %.4f" % [label, p, tol, got])


func test_wounds_and_losses_reach_the_medical_module() -> void:
	var g := Helpers.make(8, 1)
	var sim = g.sim
	var rec := _record(sim)
	var sc = sim.scavenge
	var marcus = _p(sim, "marcus")
	var hector = _p(sim, "hector")
	_send_with(sim, [marcus, hector], "hardware", {"scrap": 14, "ammo": 35}, {"marcus": "bite"}, ["hector"])
	var before := _run_until_back(sim, 600.0)
	eq(rec.wounds, [["marcus", "bite"]], "Marcus's bite went to the medical module")
	eq(rec.kills, [["hector", "scavenging"]], "Hector's loss went to the medical module")
	check(marcus.away == null and not marcus.dead, "Marcus is home")
	check(hector.dead, "Hector is dead")
	check(hector.away is Dictionary and hector.away.get("kind", "") == "lost", "and stays off the map, recorded as lost")
	near(sim.stock.scrap, before.scrap + 14.0, 0.0001, "Marcus brought the scrap")
	near(sim.stock.ammo, before.ammo + 35.0, 0.0001, "and the ammo")
	var a: Dictionary = sim.alerts["scav-1"]
	check(String(a.text).contains("Marcus is back from the hardware store with 14 scrap and 35 ammo"), "the story: '%s'" % a.text)
	check(String(a.text).contains("Marcus was bitten"), "a bite is called a bite: '%s'" % a.text)
	check(String(a.text).contains("Hector did not come back"), "and the loss is told: '%s'" % a.text)
	eq(a.level, "danger", "a death is a danger alert")
	check(_banner_with(sim, "Hector"), "and the banner names him")
	g.world.free()


func test_a_scratch_is_reported_as_bleeding() -> void:
	var g := Helpers.make(8, 1)
	var sim = g.sim
	var rec := _record(sim)
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	_send_with(sim, [dez, marcus], "pharmacy", {"meds": 5}, {"marcus": "scratch"}, [])
	_run_until_back(sim, 600.0)
	eq(rec.wounds, [["marcus", "scratch"]], "a scratch went to the medical module")
	eq(rec.kills, [], "nobody died")
	var a: Dictionary = sim.alerts["scav-1"]
	check(String(a.text).contains("Dez and Marcus are back from the pharmacy with 5 meds. Marcus is bleeding."), "the story: '%s'" % a.text)
	eq(a.level, "warn", "a wound is a warning")
	g.world.free()


func test_a_clean_trip_is_an_info_alert() -> void:
	var g := Helpers.make(8, 1)
	var sim = g.sim
	var rec := _record(sim)
	_send_with(sim, [_p(sim, "dez")], "pharmacy", {"meds": 1}, {}, [])
	_run_until_back(sim, 600.0)
	eq(rec.wounds, [], "no wounds")
	var a: Dictionary = sim.alerts["scav-1"]
	check(String(a.text).contains("Dez is back from the pharmacy with 1 med."), "one med, not one meds: '%s'" % a.text)
	eq(a.level, "info", "an info alert")
	g.world.free()


func test_a_party_that_is_all_lost_brings_nothing_back() -> void:
	var g := Helpers.make(8, 1)
	var sim = g.sim
	var rec := _record(sim)
	var hector = _p(sim, "hector")
	_send_with(sim, [hector], "hardware", {"scrap": 14, "ammo": 35}, {}, ["hector"])
	var before := _run_until_back(sim, 600.0)
	eq(rec.kills, [["hector", "scavenging"]], "Hector did not come back")
	for k in before:
		near(sim.stock[k], before[k], 0.0001, "no %s came with nobody" % k)
	var a: Dictionary = sim.alerts["scav-1"]
	check(String(a.text).contains("Hector did not come back from the hardware store"), "the story: '%s'" % a.text)
	g.world.free()


func test_someone_who_died_away_does_not_come_back() -> void:
	var g := Helpers.make(8, 1)
	var sim = g.sim
	var rec := _record(sim)
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	_send_with(sim, [dez, hector], "hardware", {"scrap": 12}, {}, [])
	check(_until(sim, func(): return dez.away != null and hector.away != null, 40.0), "both are away")
	dez.dead = true
	dez.turned = true
	var before := _run_until_back(sim, 600.0)
	eq(rec.kills, [], "no second death is recorded for someone already dead")
	check(dez.dead and dez.away is Dictionary and dez.away.get("kind", "") == "lost", "Dez stays off the map")
	check(hector.away == null, "Hector is home")
	near(sim.stock.scrap, before.scrap + 12.0, 0.0001, "and brought the scrap")
	check(String(sim.alerts["scav-1"].text).contains("Dez did not come back"), "the story says so: '%s'" % sim.alerts["scav-1"].text)
	g.world.free()


# ------------------------------------------------------------------- dusk etc --

func test_dusk_brings_a_party_home_at_once() -> void:
	var g := Helpers.make(9, 1)
	var sim = g.sim
	sim.supplies = NoSupplies.new() # the 19:00 meal would take food in the same step
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var party := _send_with(sim, [dez], "houses", {"food": 7}, {}, [])
	check(_until(sim, func(): return dez.away != null, 40.0), "Dez is away")
	party.return_at += 100000.0
	_at(sim, 18.9)
	Helpers.run(sim, 1.0)
	check(sim.phase == "day", "it is still day at 18:57")
	eq(sc.parties.size(), 1, "still out before dusk")
	var food: float = sim.stock.food
	Helpers.run(sim, 3.0)
	check(sim.phase == "dusk", "it is dusk")
	check(sc.parties.is_empty(), "nobody is left out at dusk")
	check(dez.away == null, "Dez is back")
	near(sim.stock.food, food + 7.0, 0.0001, "with the food")
	g.world.free()


func test_a_party_that_never_left_is_dissolved_at_the_return_time() -> void:
	var g := Helpers.make(9, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var party := _send_with(sim, [dez], "houses", {"food": 7}, {}, [])
	# something keeps Dez from ever reaching the gate (the order is put back every step)
	var food: float = sim.stock.food
	party.return_at = sim.clock_min + 60.0
	for i in 30 * 25:
		sim.update(1.0 / 30.0)
		dez.x = 50.0
		dez.y = 30.0
		dez.moving = false
		if sc.parties.is_empty():
			break
	check(sc.parties.is_empty(), "the party is dissolved when its time is up")
	check(dez.away == null, "Dez never left")
	near(sim.stock.food, food, 0.0001, "and nothing came back")
	check(sc.available_sites()[2].available, "the houses were not raided")
	g.world.free()


func test_a_member_pulled_off_before_the_gate_leaves_the_party() -> void:
	var g := Helpers.make(10, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	_at(sim, 7.0)
	check(sc.send([dez, hector], "houses"), "both are sent")
	sc.parties[0].result = {"loot": {"food": 14, "water": 20}, "hurt": {"hector": "bite"}, "lost": []}
	check(sim.order_move(hector, 54.0, 30.0), "the player changes Hector's mind")
	sim.update(1.0 / 30.0)
	eq(sc.parties[0].members, ["dez"], "Hector is no longer in the party")
	var r: Dictionary = sc.parties[0].result
	check(r.loot.food >= roundi(8 * 0.7) and r.loot.food <= roundi(14 * 0.7), "a lone trip now, decided again: food is 70%% of 8 to 14: %d" % r.loot.food)
	check(r.loot.water <= roundi(20 * 0.7), "and water at most 14: %d" % r.loot.water)
	check(not r.hurt.has("hector"), "Hector's injury roll went with him")
	check(_until(sim, func(): return dez.away != null, 40.0), "Dez goes on alone")
	Helpers.run(sim, 10.0)
	check(hector.away == null, "Hector never left")
	eq(sc.parties[0].state, "away", "the party is away with Dez")
	g.world.free()


func test_a_trip_everyone_was_pulled_off_is_called_off() -> void:
	var g := Helpers.make(10, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	_at(sim, 7.0)
	check(sc.send([dez], "houses"), "Dez is sent")
	sim.toggle_draft(dez)
	sim.update(1.0 / 30.0)
	check(sc.parties.is_empty(), "nobody is left: the trip is off")
	check(dez.away == null, "Dez is at home")
	check(sc.can_send(), "a new party may be sent")
	check(sc.available_sites()[2].available, "the houses were not raided")
	g.world.free()


func test_a_member_who_goes_down_on_the_way_leaves_the_party() -> void:
	var g := Helpers.make(10, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	_at(sim, 7.0)
	check(sc.send([dez, hector], "houses"), "both are sent")
	hector.downed = true
	sim.update(1.0 / 30.0)
	eq(sc.parties[0].members, ["dez"], "a downed man does not go out")
	g.world.free()


func test_status_marks_show_who_is_out() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	eq(sc.status_of(dez), [], "no mark at home")
	_at(sim, 7.0)
	check(sc.send([dez], "houses"), "Dez goes")
	var m: Array = sc.status_of(dez)
	eq(m.size(), 1, "one mark while he walks to the gate")
	eq(m[0].icon, "away", "the away icon")
	check(m[0].color is Color, "with a colour")
	check(String(m[0].tip).to_lower().contains("scaveng"), "and a tip: '%s'" % m[0].tip)
	check(_until(sim, func(): return dez.away != null, 40.0), "Dez is away")
	m = sc.status_of(dez)
	eq(m[0].tip, "Away scavenging", "the tip while away")
	check(sim.status_of(dez).size() >= 1, "the rules' marks include it")
	eq(sc.status_of(_p(sim, "ana")), [], "Ana has none")
	_run_until_back(sim, 600.0)
	eq(sc.status_of(dez), [], "no mark once back")
	g.world.free()


func test_the_scavenge_button_is_left_to_the_dialog() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	var sel := {"kind": "person", "ref": _p(sim, "dez")}
	eq(sim.scavenge.gizmo("scavenge", sel), false, "the module does not take the button")
	eq(sim.handle_gizmo("scavenge", sel), false, "nor does the rules' gizmo handler")
	check(sim.scavenge.parties.is_empty(), "nobody was sent")
	g.world.free()


func test_a_member_pulled_off_after_the_others_left_keeps_the_trip_as_decided() -> void:
	var g := Helpers.make(10, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	var party := _send_with(sim, [dez, hector], "houses", {"food": 14}, {"hector": "bite", "dez": "scratch"}, [])
	check(_until(sim, func(): return dez.away != null, 40.0), "Dez is through")
	check(hector.away == null, "Hector is still walking")
	check(sim.order_move(hector, 54.0, 30.0), "the player calls Hector back")
	sim.update(1.0 / 30.0)
	eq(party.members, ["dez"], "Hector is out of the party")
	eq(party.result.loot, {"food": 14}, "the trip is not decided again once someone has left")
	eq(party.result.hurt, {"dez": "scratch"}, "only Hector's roll is gone")
	g.world.free()


func test_the_party_tells_when_it_leaves_and_when_a_trip_is_called_off() -> void:
	var g := Helpers.make(10, 1)
	var sim = g.sim
	var sc = sim.scavenge
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	_at(sim, 7.0)
	check(sc.send([dez, hector], "hardware"), "sent")
	check(not sim.alerts.has("scav-out-1"), "nothing is said while they walk")
	check(_until(sim, func(): return sc.parties[0].state == "away", 40.0), "both are through")
	check(sim.alerts.has("scav-out-1"), "a line says they left")
	var a: Dictionary = sim.alerts["scav-out-1"]
	check(String(a.text).contains("Dez and Hector left for the hardware store"), "it names them and the place: '%s'" % a.text)
	check(String(a.sub).contains("16:00"), "and when they are due: '%s'" % a.sub)
	sc.parties.clear()
	sim.day = 5
	_at(sim, 7.0)
	for p in [dez, hector]:
		p.away = null
	check(sc.send([_p(sim, "ana")], "pharmacy"), "a second trip, on another day")
	eq(sc.parties[0].n, 2, "is trip number 2")
	sim.toggle_draft(_p(sim, "ana"))
	sim.update(1.0 / 30.0)
	check(sim.alerts.has("scav-2"), "a trip called off says so")
	check(String(sim.alerts["scav-2"].text).contains("pharmacy"), "with the place: '%s'" % sim.alerts["scav-2"].text)
	g.world.free()


func test_trips_are_numbered_through_a_run() -> void:
	var g := Helpers.make(11, 1)
	var sim = g.sim
	var sc = sim.scavenge
	_record(sim)
	_send_with(sim, [_p(sim, "dez")], "houses", {"food": 7}, {}, [])
	_run_until_back(sim, 600.0)
	check(sim.alerts.has("scav-1") and String(sim.alerts["scav-1"].text).contains("Dez"), "the first trip has its alert and story")
	sim.day = 2
	_send_with(sim, [_p(sim, "hector")], "hardware", {"scrap": 11}, {}, [])
	_run_until_back(sim, 600.0)
	check(sim.alerts.has("scav-2") and String(sim.alerts["scav-2"].text).contains("Hector"), "the second has its own")
	eq(sc.save().trips, 2, "two trips are counted")
	eq(sc.save().raids, {"houses": [1], "hardware": [2]}, "and the raids are on record by site and day")
	sim.start_run(1, 3)
	eq(sc.save().trips, 0, "a new run starts counting again")
	g.world.free()


# ------------------------------------------------------ determinism and saves --

func test_a_seeded_trip_is_the_same_twice() -> void:
	var a := Helpers.make(21, 1)
	var b := Helpers.make(21, 1)
	var c := Helpers.make(22, 1)
	var results: Array = []
	for g in [a, b, c]:
		_at(g.sim, 7.0)
		g.sim.scavenge.send([_p(g.sim, "marcus"), _p(g.sim, "hector")], "hardware")
		results.append(g.sim.scavenge.parties[0].result.duplicate(true))
	eq(results[0], results[1], "the same seed decides the same trip")
	check(results[0] != results[2], "another seed decides another")
	for g in [a, b, c]:
		g.world.free()


func test_a_trip_survives_a_save_and_a_load_while_walking() -> void:
	var a := Helpers.make(7, 1)
	var b := Helpers.make(7, 1)
	var sa = a.sim
	var dez = _p(sa, "dez")
	_at(sa, 7.0)
	check(sa.scavenge.send([dez, _p(sa, "ana")], "pharmacy"), "sent")
	Helpers.run(sa, 1.0)
	var saved: Dictionary = _via_json(sa.scavenge.save())
	b.sim.scavenge.load_state(saved)
	eq(b.sim.scavenge.save(), sa.scavenge.save(), "the walking party round-trips through JSON")
	eq(b.sim.scavenge.parties[0].state, "out", "still out")
	eq(b.sim.scavenge.parties[0].members, ["dez", "ana"], "with the same members")
	check(_p(b.sim, "dez").away == null, "nobody is through yet")
	a.world.free()
	b.world.free()


func test_a_trip_survives_a_save_and_a_load_while_away() -> void:
	var a := Helpers.make(7, 1)
	var b := Helpers.make(7, 1)
	var sa = a.sim
	var sb = b.sim
	_at(sa, 7.0)
	check(sa.scavenge.send([_p(sa, "dez"), _p(sa, "ana")], "pharmacy"), "sent")
	check(_until(sa, func(): return sa.scavenge.parties[0].state == "away", 40.0), "both are away")
	# one more raid is on record, so the save has something to say about sites
	sa.scavenge.parties[0].result = {"loot": {"meds": 4}, "hurt": {"ana": "scratch"}, "lost": []}
	var saved: Dictionary = _via_json(sa.scavenge.save())
	sb.scavenge.load_state(saved)
	eq(sb.scavenge.save(), sa.scavenge.save(), "the away party round-trips through JSON")
	var dez = _p(sb, "dez")
	check(dez.away != null and dez.away.get("site", "") == "pharmacy", "its members are off the map again")
	eq(_p(sb, "hector").away, null, "the others are not")
	# the two games now have the same future: same clock, dice and stores
	for k in ["day", "minutes", "clock_min", "phase"]:
		sb.set(k, sa.get(k))
	sb.stock = sa.stock.duplicate()
	sb.rng.state = sa.rng.state
	var rec_a := _record(sa)
	var rec_b := _record(sb)
	var before_a := _run_until_back(sa, 600.0)
	var before_b := _run_until_back(sb, 600.0)
	check(sa.scavenge.parties.is_empty() and sb.scavenge.parties.is_empty(), "both parties came home")
	near(sa.stock.meds, before_a.meds + 4.0, 0.0001, "the original got the four meds the result said")
	near(sb.stock.meds, before_b.meds + 4.0, 0.0001, "and so did the loaded game")
	eq(rec_b.wounds, rec_a.wounds, "and the same wounds")
	eq(rec_a.wounds, [["ana", "scratch"]], "which were Ana's scratch")
	eq(sb.alerts["scav-1"].text, sa.alerts["scav-1"].text, "and the same story")
	a.world.free()
	b.world.free()


func test_raids_and_losses_survive_a_save() -> void:
	var a := Helpers.make(7, 1)
	var b := Helpers.make(7, 1)
	var sa = a.sim
	_rec_lost_trip(sa)
	var saved: Dictionary = _via_json(sa.scavenge.save())
	b.sim.scavenge.load_state(saved)
	eq(b.sim.scavenge.save(), sa.scavenge.save(), "raids and the lost round-trip")
	var hector = _p(b.sim, "hector")
	check(hector.away is Dictionary and hector.away.get("kind", "") == "lost", "Hector is still lost")
	check(not b.sim.scavenge.available_sites()[1].available, "the hardware store is still picked over")
	a.world.free()
	b.world.free()


func _rec_lost_trip(sim) -> void:
	_record(sim)
	_send_with(sim, [_p(sim, "hector")], "hardware", {"scrap": 10}, {}, ["hector"])
	_run_until_back(sim, 600.0)


func test_a_damaged_save_is_ignored_without_harm() -> void:
	var g := Helpers.make(7, 1)
	var sc = g.sim.scavenge
	sc.load_state({})
	eq(sc.parties.size(), 0, "an empty save is nothing")
	sc.load_state({"parties": [{"n": 1, "members": ["nobody"], "site": "houses", "state": "away", "return_at": 1.0, "result": {}}]})
	eq(sc.parties.size(), 1, "the party of nobody is loaded")
	Helpers.run(g.sim, 2.0)
	check(sc.parties.is_empty(), "a party of people who do not exist is dissolved, not a crash")
	g.world.free()


# ---------------------------------------------------------------------- fuzz --

func test_stocks_stay_positive_and_nobody_stays_away() -> void:
	for seed_value in range(1, 6):
		var g := Helpers.make(seed_value, seed_value % 3)
		var sim = g.sim
		var sc = sim.scavenge
		var dice := RandomNumberGenerator.new()
		dice.seed = seed_value * 97
		for day in 3:
			_at(sim, 6.5)
			var free: Array = sc.free_survivors()
			var open: Array = []
			for s in sc.available_sites():
				if s.available:
					open.append(s.id)
			if not free.is_empty() and not open.is_empty() and sc.can_send():
				var who := [free[dice.randi() % free.size()]]
				if free.size() > 1 and dice.randf() < 0.6:
					var second = free[dice.randi() % free.size()]
					if second != who[0]:
						who.append(second)
				sc.send(who, open[dice.randi() % open.size()])
			for sec in 580:
				_run15(sim, 1.0)
				for k in sim.stock:
					if sim.stock[k] < 0.0:
						failures.append("%s went negative (seed %d, day %d)" % [k, seed_value, day])
				if sc.parties.size() > 1:
					failures.append("two parties at once (seed %d)" % seed_value)
				for p in sim.people:
					if p.away != null and not p.dead and sc.parties.is_empty():
						failures.append("%s is away with no party (seed %d, hour %.2f)" % [p.id, seed_value, sim.hour])
				if sim.hour >= 16.2 and sim.hour < 19.0:
					break
			check(sc.parties.is_empty(), "the party is back by 16:15 (seed %d, day %d)" % [seed_value, day])
			for p in sim.people:
				check(p.away == null or p.dead, "%s is not stuck away (seed %d)" % [p.id, seed_value])
			# skip the night: the next morning at 06:30
			sim.clock_min += fposmod(6.5 * 60.0 - sim.minutes, 1440.0)
			sim.day += 1
			_at(sim, 6.5)
		g.world.free()
