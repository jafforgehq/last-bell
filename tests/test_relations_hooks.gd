extends "res://tests/case.gd"
## The hooks of relations.gd (round 20) in the modules that read it: bonds (the friends made in play), morale (a friend steadies, a
## rival wears, a partner's loss is felt harder), the radio (a friend in the squad warms a request, a hurt friend keeps someone home,
## an enemy in the squad refuses, a push reaches a friend's friends), jobs (the fit), medical (a rescue), scavenge (a trip home) and
## the player's succession. And the other half of the promise: with no avatar (or the module off) every one of them is exactly as it
## was. The module's own rules are in test_relations.gd.

const Helpers := preload("res://tests/helpers.gd")
const Relations := preload("res://scripts/sim/relations.gd")
const Morale := preload("res://scripts/sim/morale.gd")


# ----------------------------------------------------------------- helpers --

func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## The same game as test_relations.gd: a settlement game with Ruth as the avatar, everybody far from everybody, nobody working, a
## quiet morning of day 3.
func _game() -> Dictionary:
	var g := Helpers.make(1, 1, 6)
	var sim = g.sim
	sim.recruits.small = true
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.initiative.enabled = false
	sim.specialists.enabled = false
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	Helpers.no_work(sim)
	_at(sim, 3, 9.0)
	var i := 0
	for p in sim.people:
		_place(p, 4.0 + 9.0 * float(i), 10.0)
		i += 1
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


func _firsts(list: Array) -> Array:
	var out: Array = []
	for b in list:
		out.append("%s:%s" % [b.who.first, b.role])
	out.sort()
	return out


## The label of a morale reason, with its value, or {} when there is none.
func _reason(sim, p, label: String) -> Dictionary:
	for e in sim.morale.explain(p):
		if String(e.label) == label:
			return e
	return {}


## Dez and Ana made a couple (the way the rules would have: friends first, then days).
func _couple(sim, a: String, b: String) -> void:
	var r = sim.relations
	r.add(a, b, 90.0, "x")
	var day: int = sim.day
	sim.day = day + Relations.PARTNER_DAYS
	r.add(a, b, 1.0, "x")
	sim.day = day
	eq(r.kind(a, b), "partner", "%s and %s are a couple" % [a, b])


# ------------------------------------------------------------------------ bonds --

func test_bonds_lists_a_friend_made_in_play_and_nothing_extra_without_an_avatar() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	eq(_firsts(sim.bonds.of(dez)), ["Hector:friend"], "the roster alone")
	check(not sim.bonds.bonded(dez, walt), "Dez and Walt are no bond")
	r.add("dez", "walt", 50.0, "x")
	eq(_firsts(sim.bonds.of(dez)), ["Hector:friend", "Walt:friend"], "now Walt is one")
	check(sim.bonds.bonded(dez, walt) and sim.bonds.bonded(walt, dez), "bonded, both ways")
	_place(walt, dez.x + 5.0, dez.y)
	check(sim.bonds.near(dez, 6.0), "within six tiles")
	near(sim.bonds.aim_bonus(dez), sim.bonds.AIM_BONUS + sim.traits.add(dez, "bond"), 0.0001, "a friend within six tiles steadies the aim")
	_place(walt, dez.x + 8.0, dez.y)
	near(sim.bonds.aim_bonus(dez), 0.0, 0.0001, "and not from further off")
	_place(walt, dez.x + 5.0, dez.y)
	r.enabled = false
	eq(_firsts(sim.bonds.of(dez)), ["Hector:friend"], "with the module off the roster alone again")
	check(not sim.bonds.bonded(dez, walt), "and no bond")
	near(sim.bonds.aim_bonus(dez), 0.0, 0.0001, "and no aim bonus")
	g.world.free()


func test_bonds_without_an_avatar_is_the_rosters_own() -> void:
	var g := Helpers.make(1, 1, 6)
	var sim = g.sim
	var dez = _p(sim, "dez")
	var ruth = _p(sim, "ruth")
	eq(_firsts(sim.bonds.of(dez)), ["Hector:friend"], "Dez")
	eq(_firsts(sim.bonds.of(ruth)), ["Ana:friend", "Marcus:family"], "Ruth")
	check(sim.bonds.bonded(dez, _p(sim, "hector")), "bonded")
	check(not sim.bonds.bonded(dez, _p(sim, "walt")), "not bonded")
	g.world.free()


# ----------------------------------------------------------------------- morale --

func test_morale_a_friend_made_in_play_steadies_a_rival_wears_and_a_partner_is_missed_more() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	var marcus = _p(sim, "marcus")
	# a friend near
	r.add("dez", "walt", 50.0, "x")
	_place(walt, dez.x + 4.0, dez.y)
	var near_walt := _reason(sim, dez, "Near Walt")
	check(not near_walt.is_empty(), "Dez is steadied by Walt: %s" % str(sim.morale.explain(dez)))
	near(float(near_walt.get("value", 0.0)), Morale.NEAR_BOND, 0.05, "by the usual amount")
	# a rival near
	r.add("dez", "marcus", -40.0, "x")
	_place(marcus, dez.x, dez.y + 3.5)
	var edge := _reason(sim, dez, "On edge near Marcus")
	check(not edge.is_empty(), "and wears on by Marcus: %s" % str(sim.morale.explain(dez)))
	near(float(edge.get("value", 0.0)), Relations.RIVAL_NEAR, 0.05, "by RIVAL_NEAR")
	var with_rival: float = sim.morale.target(dez)
	_place(marcus, dez.x, dez.y + 4.5)
	check(_reason(sim, dez, "On edge near Marcus").is_empty(), "not from over 4 tiles")
	near(with_rival - float(sim.morale.target(dez)), Relations.RIVAL_NEAR, 0.0001, "the target moves by that much")
	_place(marcus, dez.x, dez.y + 3.5)
	marcus.downed = true
	check(_reason(sim, dez, "On edge near Marcus").is_empty(), "not from one who is down")
	marcus.downed = false
	r.enabled = false
	check(_reason(sim, dez, "On edge near Marcus").is_empty(), "nor with the module off")
	check(_reason(sim, dez, "Near Walt").is_empty(), "and the friend made in play steadies no more")
	g.world.free()


func test_morale_grief_a_partner_is_hit_thirty_percent_harder_and_a_made_friend_counts_as_a_friend() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	_couple(sim, "dez", "ana")
	r.add("walt", "hector", 50.0, "x")
	sim.medical.kill(_p(sim, "dez"), "bled out")
	var ana_shock := {}
	for e in sim.morale.shocks.get("ana", []):
		if String(e.label) == "Dez died":
			ana_shock = e
	check(not ana_shock.is_empty(), "Ana mourns Dez")
	near(float(ana_shock.get("value", 0.0)), Morale.FRIEND_LOST * sim.traits.mult(_p(sim, "ana"), "grief") * 1.3, 0.0001, "a partner: the friend's loss times 1.3")
	var hector_shock := {}
	for e in sim.morale.shocks.get("hector", []):
		if String(e.label) == "Dez died":
			hector_shock = e
	near(float(hector_shock.get("value", 0.0)), Morale.FRIEND_LOST * sim.traits.mult(_p(sim, "hector"), "grief"), 0.0001, "a roster friend: the friend's loss")
	sim.medical.kill(_p(sim, "hector"), "bled out")
	var walt_shock := {}
	for e in sim.morale.shocks.get("walt", []):
		if String(e.label) == "Hector died":
			walt_shock = e
	near(float(walt_shock.get("value", 0.0)), Morale.FRIEND_LOST * sim.traits.mult(_p(sim, "walt"), "grief"), 0.0001, "a friend made in play: a friend's loss, not a stranger's")
	var marcus_shock := {}
	for e in sim.morale.shocks.get("marcus", []):
		if String(e.label) == "Hector died":
			marcus_shock = e
	near(float(marcus_shock.get("value", 0.0)), Morale.OTHER_LOST, 0.0001, "and anyone else: the others' share")
	var loss: Dictionary = r.recent_loss()
	eq(loss.id, "hector", "the loss is kept for the farewell")
	g.world.free()


func test_morale_without_the_module_a_loss_is_what_it_was() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	r.add("walt", "hector", 50.0, "x")
	r.enabled = false
	sim.medical.kill(_p(sim, "hector"), "bled out")
	var walt_shock := {}
	for e in sim.morale.shocks.get("walt", []):
		if String(e.label) == "Hector died":
			walt_shock = e
	near(float(walt_shock.get("value", 0.0)), Morale.OTHER_LOST, 0.0001, "Walt was no friend of Hector's as far as the roster knows")
	check(r.recent_loss().is_empty(), "and nothing was remembered")
	g.world.free()


# ------------------------------------------------------------------------ radio --

func test_radio_a_friend_in_the_squad_warms_a_request_and_a_rival_cools_it() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var radio = sim.radio
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	var base_delay: float = radio.delay_for(45.0)
	dez.trust = 45.0
	var w0: Dictionary = radio.willingness(dez, "come")
	check(w0.ok, "Dez would come")
	eq(w0.tone, "grudging", "at 45, grudgingly")
	near(float(w0.delay_s), base_delay, 0.0001, "with the delay of 45")
	r.add("dez", "walt", 50.0, "x")
	near(r.company_pull(dez, "come"), 0.0, 0.0001, "a friend who is not in the squad does nothing")
	walt.stance = "follow"
	walt.drafted = true
	near(r.company_pull(dez, "come"), Relations.FRIEND_PULL, 0.0001, "a friend who follows warms")
	var w1: Dictionary = radio.willingness(dez, "come")
	eq(w1.tone, "willing", "45 + 6 is over 50: willingly")
	near(float(w1.delay_s), radio.delay_for(45.0 + Relations.FRIEND_PULL), 0.0001, "and sooner")
	for verb in ["cover", "search"]:
		near(r.company_pull(dez, verb), Relations.FRIEND_PULL, 0.0001, "%s too" % verb)
	for verb in ["hold", "back", "post"]:
		near(r.company_pull(dez, verb), 0.0, 0.0001, "%s is not about company" % verb)
	near(float(dez.trust), 45.0, 0.0001, "the pull is never stored")
	# a rival cools
	dez.trust = 33.0
	r.add("dez", "walt", -100.0, "x")    # (Walt: from friend to rival, at -50)
	near(r.company_pull(dez, "come"), Relations.RIVAL_PUSH, 0.0001, "a rival who follows cools")
	var w2: Dictionary = radio.willingness(dez, "cover")
	eq(w2.tone, "doubtful", "33 - 6 is under 30: doubtfully")
	# a friend who has been agreed to (a request waiting) counts too
	walt.stance = ""
	walt.drafted = false
	dez.trust = 55.0
	r.add("dez", "walt", 200.0, "x")
	near(r.company_pull(dez, "come"), 0.0, 0.0001, "(Walt stands where he is again)")
	walt.trust = 55.0
	check(radio.request(walt, "come").ok, "Walt is asked, and agrees")
	near(r.company_pull(dez, "come"), Relations.FRIEND_PULL, 0.0001, "and Dez is warmed by that")
	g.world.free()


func test_radio_a_friend_who_lies_hurt_keeps_someone_home_and_insisting_overrides_it() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var radio = sim.radio
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")    # Dez's friend by the roster
	eq(r.company_reason(dez, "come"), "", "nothing amiss")
	hector.downed = true
	eq(r.company_reason(dez, "come"), "staying with Hector", "a friend is down")
	eq(r.company_reason(dez, "cover"), "staying with Hector", "for cover too")
	eq(r.company_reason(dez, "search"), "staying with Hector", "and search")
	eq(r.company_reason(dez, "go"), "staying with Hector", "and any going")
	eq(r.company_reason(dez, "work"), "", "(work is another matter)")
	var w: Dictionary = radio.willingness(dez, "come")
	check(not w.ok and not w.hard, "Dez refuses, softly")
	eq(w.why, "Dez: staying with Hector, can't come", "in the radio's words")
	check(String(w.line).begins_with("Staying with Hector"), "and says so: %s" % w.line)
	check(radio.willingness(dez, "hold").ok, "he can still hold where he stands")
	check(radio.willingness(dez, "back").ok and radio.willingness(dez, "post").ok, "and go back or to the walls")
	# someone else is with the patient
	var ana = _p(sim, "ana")
	_place(ana, hector.x + 1.0, hector.y)
	eq(r.company_reason(dez, "come"), "", "Ana is beside him: he is not alone")
	_place(ana, 80.0, 40.0)
	eq(r.company_reason(dez, "come"), "staying with Hector", "she goes: he is alone again")
	# bleeding, a bed, a fever
	hector.downed = false
	eq(r.company_reason(dez, "come"), "", "he is up")
	hector.bleeding = 2.0
	eq(r.company_reason(dez, "come"), "staying with Hector", "bleeding")
	hector.bleeding = 0.0
	hector.resting_bed = Vector2(hector.x, hector.y)
	eq(r.company_reason(dez, "come"), "staying with Hector", "in a bed")
	hector.resting_bed = null
	# insisting overrides it at the usual cost
	hector.downed = true
	var trust := float(dez.trust)
	var refused: Dictionary = radio.request(dez, "come")
	check(not refused.ok and not refused.hard, "asked, he refuses")
	var pushed: Dictionary = radio.request(dez, "come", {"insist": true})
	check(pushed.ok and pushed.insisted, "pushed, he comes")
	near(float(dez.trust), trust - radio.INSIST_COST, 0.0001, "at the usual cost of trust")
	check(not _reason(sim, dez, "Pushed to go when they could not").is_empty(), "and mood")
	# with the module off, there is no such reason
	r.enabled = false
	eq(r.company_reason(dez, "come"), "", "nothing")
	check(radio.willingness(dez, "come").ok, "off: willing as ever")
	g.world.free()


func test_radio_an_enemy_in_the_squad_refuses_and_an_enemy_at_the_station_will_not_share_it() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var radio = sim.radio
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	r.add("dez", "walt", -60.0, "x")
	walt.stance = "follow"
	walt.drafted = true
	eq(r.company_reason(dez, "come"), "", "a rival is not yet an enemy (-60)")
	check(radio.willingness(dez, "come").ok, "he comes, if coolly")
	near(r.company_pull(dez, "come"), Relations.RIVAL_PUSH, 0.0001, "(coolly)")
	r.add("dez", "walt", -6.0, "x")
	eq(r.company_reason(dez, "come"), "won't go with Walt", "-66 is")
	var w: Dictionary = radio.willingness(dez, "cover")
	check(not w.ok and not w.hard, "a soft refusal")
	eq(w.why, "Dez: won't go with Walt, can't cover you", "in the radio's words")
	# named going-with
	walt.stance = ""
	walt.drafted = false
	eq(r.company_reason(dez, "go"), "", "Walt is not going")
	eq(r.company_reason(dez, "go", "", ["walt"]), "won't go with Walt", "an errand with Walt in it")
	eq(r.company_reason(dez, "go", "", [walt]), "won't go with Walt", "(people or ids)")
	eq(r.company_reason(dez, "go", "", ["marcus"]), "", "with Marcus he would")
	# the same station
	check(sim.jobs.assign(walt, "bench"), "Walt is at the bench")
	eq(r.company_reason(dez, "work", "bench"), "won't work beside Walt", "Dez will not work beside him")
	eq(r.company_reason(dez, "work", "builders"), "", "elsewhere he will")
	eq(r.company_reason(dez, "work", ""), "", "(no station, no reason)")
	g.world.free()


func test_radio_a_push_reaches_the_friends_of_the_one_pushed_once_an_hour_and_never_twice_over() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var radio = sim.radio
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	var walt = _p(sim, "walt")
	var ana = _p(sim, "ana")
	r.add("dez", "walt", 50.0, "x")
	_couple(sim, "dez", "ana")
	radio.add_trust(dez, -6.0, "You pushed them to go when they could not")
	near(float(dez.trust), 49.0, 0.0001, "Dez himself")
	for q in [hector, walt, ana]:
		near(float(q.trust), 55.0 - 6.0 * Relations.ECHO_SHARE, 0.0001, "%s feels a quarter of it" % q.first)
	eq(radio.trust_why(hector)[0].why, "How you treated Dez", "with the reason")
	check(radio.trust_why(dez)[0].why != "How you treated Dez", "(Dez's own reason is his own)")
	radio.add_trust(dez, -6.0, "again")
	near(float(hector.trust), 55.0 - 6.0 * Relations.ECHO_SHARE, 0.0001, "not twice in an hour")
	sim.clock_min += 61.0
	radio.add_trust(dez, -6.0, "an hour on")
	near(float(hector.trust), 55.0 - 12.0 * Relations.ECHO_SHARE, 0.0001, "an hour later, yes")
	near(float(dez.trust), 55.0 - 18.0, 0.0001, "Dez's own number only moved by what was done to him")
	# a good turn travels too; a small one does not
	var before := float(walt.trust)
	radio.add_trust(dez, Relations.ECHO_MIN - 0.5, "a small one")
	near(float(walt.trust), before, 0.0001, "under ECHO_MIN: nothing")
	sim.clock_min += 61.0
	radio.add_trust(dez, 4.0, "A good turn")
	near(float(walt.trust), before + 4.0 * Relations.ECHO_SHARE, 0.0001, "a gain of 3 or more: a quarter")
	# never recursive: a big push on Dez does not come back to Dez through his friends
	sim.clock_min += 61.0
	var dez_was := float(dez.trust)
	radio.add_trust(dez, -20.0, "a great wrong")
	near(float(dez.trust), dez_was - 20.0, 0.0001, "the echo never echoes")
	# the player's own pairs are no part of it
	var marcus = _p(sim, "marcus")
	var ruth = _p(sim, "ruth")
	var marcus_was := float(marcus.trust)
	radio.add_trust(ruth, -10.0, "x")
	near(float(marcus.trust), marcus_was, 0.0001, "nothing is passed on from the player")
	# off: nothing at all
	r.enabled = false
	sim.clock_min += 61.0
	var hector_was := float(hector.trust)
	radio.add_trust(dez, -10.0, "x")
	near(float(hector.trust), hector_was, 0.0001, "with the module off")
	g.world.free()


# ------------------------------------------------------------------------- jobs --

func test_jobs_a_friend_at_a_station_is_a_reason_to_sit_there_and_a_rival_a_reason_not_to() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	var marcus = _p(sim, "marcus")
	var base: float = sim.jobs._fit(dez, "builders")
	check(sim.jobs.assign(walt, "builders"), "Walt on the builders")
	near(sim.jobs._fit(dez, "builders"), base, 0.0001, "no tie, no change")
	r.add("dez", "walt", 50.0, "x")
	near(r.fit_adjust(dez, "builders"), Relations.FIT_FRIEND, 0.0001, "a friend there: +0.5")
	near(sim.jobs._fit(dez, "builders"), base + Relations.FIT_FRIEND, 0.0001, "in the fit")
	near(r.fit_adjust(dez, "bench"), 0.0, 0.0001, "not at another station")
	check(sim.jobs.assign(marcus, "builders"), "Marcus too")
	r.add("dez", "marcus", 45.0, "x")
	near(r.fit_adjust(dez, "builders"), Relations.FIT_FRIEND_MAX, 0.0001, "two friends: +1.0")
	r.add("dez", "marcus", -85.0, "x")    # Marcus: a rival now (-40)
	near(r.fit_adjust(dez, "builders"), Relations.FIT_FRIEND + Relations.FIT_RIVAL, 0.0001, "a friend and a rival: +0.5 and -1.5")
	r.enabled = false
	near(sim.jobs._fit(dez, "builders"), base, 0.0001, "off: the fit is what it was")
	g.world.free()


# ---------------------------------------------------------------------- medical --

func test_medical_looking_after_someone_brings_them_closer() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var ana = _p(sim, "ana")
	var walt = _p(sim, "walt")
	sim.stock.meds = 10.0
	sim.medical._finish({"healer": ana, "patient": walt, "kind": "bandage"})
	near(r.affinity("ana", "walt"), Relations.RESCUE_GAIN, 0.0001, "a bandage")
	walt.downed = true
	walt.stabilised = false
	var dez = _p(sim, "dez")
	sim.medical._finish({"healer": dez, "patient": walt, "kind": "bandage"})
	near(r.affinity("dez", "walt"), Relations.RESCUE_GAIN + Relations.RESCUE_DOWNED_GAIN, 0.0001, "and for one who was down, more")
	r.enabled = false
	var hector = _p(sim, "hector")
	sim.medical._finish({"healer": hector, "patient": walt, "kind": "bandage"})
	r.enabled = true
	near(r.affinity("hector", "walt"), 0.0, 0.0001, "off: nothing")
	g.world.free()


# --------------------------------------------------------------------- scavenge --

func test_scavenge_a_trip_home_together_brings_a_party_closer_more_when_someone_is_hurt() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	_at(sim, 3, 7.0)
	check(sim.scavenge.send([dez, walt], "houses"), "Dez and Walt are sent")
	var party: Dictionary = sim.scavenge.parties[0]
	party.result = {"loot": {"food": 5}, "hurt": {"walt": "scratch"}, "lost": []}
	var guard := 0
	while String(party.state) != "away" and guard < 3000:
		sim.update(1.0 / 30.0)
		guard += 1
	eq(String(party.state), "away", "they are out")
	var before: float = r.affinity("dez", "walt")
	sim.scavenge._come_back(party)
	near(r.affinity("dez", "walt") - before, Relations.TRIP_GAIN + Relations.TRIP_HURT_GAIN, 0.0001, "home together, one hurt")
	g.world.free()


# ----------------------------------------------------------------------- avatar --

func test_avatar_the_next_in_line_is_the_one_the_community_stands_by() -> void:
	var g := _game()
	var sim = g.sim
	var r = sim.relations
	# Dez is liked: three friends of 60. Walt has the better Leading (5 against 2) and nobody's standing
	for who in ["ana", "marcus", "walt"]:
		r.add("dez", who, 60.0, "x")
	check(r.standing(_p(sim, "dez")) > r.standing(_p(sim, "walt")), "Dez stands higher")
	check(r.succession_bonus(_p(sim, "dez")) > r.succession_bonus(_p(sim, "walt")), "so his bonus is bigger")
	sim.medical.kill(_p(sim, "ruth"), "bled out")
	eq(sim.player_id, "dez", "Dez leads now")
	g.world.free()
	# the same, with the module off: the best Leading, as before
	var h := _game()
	var hs = h.sim
	for who in ["ana", "marcus", "walt"]:
		hs.relations.add("dez", who, 60.0, "x")
	hs.relations.enabled = false
	hs.medical.kill(_p(hs, "ruth"), "bled out")
	eq(hs.player_id, "walt", "Walt leads: the best Leading, as before")
	h.world.free()


# ------------------------------------------------------------------- the promise --

func test_nothing_changes_without_an_avatar() -> void:
	var g := Helpers.make(1, 1, 6)
	var sim = g.sim
	var r = sim.relations
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	var radio = sim.radio
	check(not r.active(), "no avatar, no relations")
	var w: Dictionary = radio.willingness(dez, "come")
	check(w.ok, "willing")
	near(float(w.delay_s), radio.delay_for(float(dez.trust)), 0.0, "with the delay of his own trust, to the last digit")
	eq(w.tone, radio.tone_for(float(dez.trust)), "and the tone")
	var fit: float = sim.jobs._fit(dez, "builders")
	var again: float = sim.jobs._fit(dez, "builders")
	eq(fit, again, "the fit")
	var reasons_before: int = sim.morale.explain(dez).size()
	radio.add_trust(dez, -6.0, "x")
	for q in sim.people:
		if q != dez:
			eq(float(q.trust), 55.0, "%s is not moved by an echo" % q.first)
	eq(sim.morale.explain(dez).size(), reasons_before, "no new reasons")
	sim.medical.kill(walt, "bled out")
	for q in sim.people:
		if q.id == "marcus":
			for e in sim.morale.shocks.get("marcus", []):
				if String(e.label) == "Walt died":
					near(float(e.value), Morale.FRIEND_LOST * sim.traits.mult(q, "grief"), 0.0, "a friend's loss, to the last digit (no factor but one)")
	eq(r.recent_loss(), {}, "no loss kept")
	g.world.free()
