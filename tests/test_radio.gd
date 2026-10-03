extends "res://tests/case.gd"
## The radio (round 17, scripts/sim/radio.gd): the player asks, the community answers. A request is refused only
## for a clear, visible reason; trust sets how willingly and how fast people answer; a stance (follow, hold,
## cover, search) is a goal in the yard's rules; the radio keeps a log of the news and raises calls with options
## (an attack on a wall section, a sickness) that take their default when nobody answers; the alarm is the call to
## arms. Everything of it that is automatic is behind avatar mode (`sim.player_id`): with no avatar nothing happens.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

## Where the leader stands (open ground in the yard), facing east.
const LEADER_AT := Vector2(34.5, 32.5)
const BUS := 3    # the bus on the north wall: its places are at (42.5 to 53, 15.1)


# ----------------------------------------------------------------- helpers --

## A quiet game with an avatar: Ruth (or `leader_id`) is the player, standing still at LEADER_AT, in the yard, at
## 09:00 of day 3 (so that a fever seven hours old is after the start of the run), no nights and no dead about.
func _game(leader_id: String = "ruth") -> Dictionary:
	var g := Helpers.make(1, 1, 6)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player(leader_id), "%s is the player" % leader_id)
	_put_leader(sim, _p(sim, leader_id), LEADER_AT, "E")
	_at(sim, 3, 9.0)
	sim.events.clear()
	return g


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## The leader is somewhere, still (the avatar stands where it is unless the player's hands move it).
func _put_leader(_sim, lead, at: Vector2, facing: String = "E") -> void:
	lead.x = at.x
	lead.y = at.y
	lead.facing = facing
	lead.path = []
	lead.goal_key = ""


func _at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day


func _night(sim) -> void:
	_at(sim, 3, 22.0)


## Someone is who they are asked to be: stands where they are and is a follower (no radio involved).
func _stand(p, stance: String, at: Vector2 = Vector2.ZERO) -> void:
	p.stance = stance
	p.stance_at = at
	p.drafted = true


## `n` of the dead clawing at the wall section `seg_id`, each at a place of it, about to strike.
func _attack(sim, seg_id: int, n: int) -> void:
	for s in sim.segments:
		if s.id != seg_id:
			continue
		for i in n:
			var sl = s.slots[i]
			var z = sim.spawn(sl.x, sl.y, "attack")
			z.slot = sl
			sl.who = z
			z.facing = sl.face
			z.attack_t = 0.0


func _calls(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


# ---------------------------------------------------------------- the verbs --

func test_the_six_verbs_and_their_names() -> void:
	var g := _game()
	var radio = g.sim.radio
	eq(radio.VERBS, ["come", "hold", "cover", "search", "back", "post"], "the six verbs, in order")
	eq(radio.verb_name("come"), "Come with me", "come")
	eq(radio.verb_name("hold"), "Hold here", "hold")
	eq(radio.verb_name("cover"), "Cover me", "cover")
	eq(radio.verb_name("search"), "Search that", "search")
	eq(radio.verb_name("back"), "Go back", "back")
	eq(radio.verb_name("post"), "To the walls", "post")
	g.world.free()


# ------------------------------------------------------------- willingness --

func test_a_clean_contact_is_willing_for_every_verb() -> void:
	var g := _game()
	var dez = _p(g.sim, "dez")
	for v in g.sim.radio.VERBS:
		var w: Dictionary = g.sim.radio.willingness(dez, v)
		check(w.ok, "Dez answers '%s': %s" % [v, str(w)])
		eq(w.why, "", "nothing to say against '%s'" % v)
		check(w.delay_s >= 0.5 and w.delay_s <= 4.0, "a delay between half a second and four: %s" % str(w.delay_s))
		check(w.tone in ["willing", "grudging", "doubtful"], "in a tone: %s" % str(w.tone))
	g.world.free()


func test_the_downed_the_dead_the_turned_and_the_away_are_not_asked_at_all() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	for state in ["downed", "dead", "turned", "away"]:
		match state:
			"downed":
				dez.downed = true
			"dead":
				dez.dead = true
			"turned":
				dez.dead = true
				dez.turned = true
			"away":
				dez.away = {"kind": "trip"}
		for v in sim.radio.VERBS:
			var w: Dictionary = sim.radio.willingness(dez, v)
			check(not w.ok, "a person who is %s cannot be asked '%s'" % [state, v])
			check(w.get("hard", false), "and that is not a refusal to argue with (%s, %s)" % [state, v])
			check(String(w.why).contains("Dez"), "the reason names them: %s" % str(w.why))
		dez.downed = false
		dez.dead = false
		dez.turned = false
		dez.away = null
	g.world.free()


func test_the_leader_cannot_ask_themselves() -> void:
	var g := _game()
	var w: Dictionary = g.sim.radio.willingness(_p(g.sim, "ruth"), "come")
	check(not w.ok, "Ruth is the player")
	g.world.free()


func test_a_bleeding_contact_will_not_come_cover_or_search_but_will_hold_go_back_and_man_a_post() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.bleeding = 4.0
	dez.wounds = 1
	for v in ["come", "cover", "search"]:
		var w: Dictionary = sim.radio.willingness(dez, v)
		check(not w.ok, "bleeding: no '%s'" % v)
		check(String(w.why).begins_with("Dez: ") and String(w.why).contains("bleeding") and String(w.why).contains("can't"), "the reason is shown: %s" % str(w.why))
		check(not w.get("hard", false), "but they could be pushed")
	for v in ["hold", "back", "post"]:
		check(sim.radio.willingness(dez, v).ok, "bleeding people can still '%s'" % v)
	g.world.free()


func test_a_fever_starving_thirst_and_being_shaken_are_reasons_to_refuse() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.infected_at = sim.clock_min - 7.0 * 60.0
	var w: Dictionary = sim.radio.willingness(dez, "come")
	check(not w.ok and String(w.why).contains("fever"), "a fever shows: %s" % str(w))
	dez.infected_at = -1.0
	check(sim.radio.willingness(dez, "come").ok, "the fever gone")
	dez.hunger_h = 40.0
	w = sim.radio.willingness(dez, "come")
	check(not w.ok and String(w.why).contains("starving"), "starving: %s" % str(w))
	dez.hunger_h = 0.0
	dez.thirst_h = 30.0
	w = sim.radio.willingness(dez, "cover")
	check(not w.ok and String(w.why).contains("parched"), "dehydrated: %s" % str(w))
	dez.thirst_h = 0.0
	sim.morale.set_value(dez, 40.0)
	w = sim.radio.willingness(dez, "search")
	check(not w.ok and String(w.why).contains("shaken"), "shaken: %s" % str(w))
	check(not w.get("hard", false), "a shaken person can be pushed")
	sim.morale.set_value(dez, 70.0)
	check(sim.radio.willingness(dez, "search").ok, "steady again")
	g.world.free()


func test_a_breakdown_is_a_refusal_for_every_verb_and_cannot_be_pushed() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	sim.morale.until[dez.id] = sim.clock_min + 60.0
	check(sim.morale.breakdown(dez), "Dez is in a breakdown")
	for v in sim.radio.VERBS:
		var w: Dictionary = sim.radio.willingness(dez, v)
		check(not w.ok and w.get("hard", false), "a breakdown: no '%s' (%s)" % [v, str(w)])
	g.world.free()


func test_the_busy_are_refused_with_the_reason_shown() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var hector = _p(sim, "hector")
	# a nurse with a patient
	sim.medical.jobs.append({"healer": ana, "patient": hector, "kind": "bandage", "work": 0.0, "stand": null, "anchor": Vector2.ZERO})
	var w: Dictionary = sim.radio.willingness(ana, "come")
	check(not w.ok, "Ana is tending a patient")
	eq(w.why, "Ana: tending a patient, can't come", "the reason, in words")
	check(sim.radio.willingness(ana, "back").ok, "but 'go back' is never refused for that")
	sim.medical.jobs.clear()
	check(sim.radio.willingness(ana, "come").ok, "and the patient seen to, she can come")
	g.world.free()


func test_the_only_one_at_the_infirmary_with_a_patient_stays() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var hector = _p(sim, "hector")
	eq(sim.jobs.job_of(ana), "infirmary", "Ana is the infirmary")
	check(sim.radio.willingness(ana, "come").ok, "no patient: free to go")
	hector.downed = true
	hector.stabilised = true
	hector.resting_bed = Vector2(47.0, 56.9)
	var w: Dictionary = sim.radio.willingness(ana, "come")
	check(not w.ok and String(w.why).contains("infirmary"), "a patient in a cot and nobody else on duty: %s" % str(w))
	var marcus = _p(sim, "marcus")
	sim.jobs.assign(marcus, "infirmary")
	check(sim.radio.willingness(ana, "come").ok, "with a second one on duty she can go")
	g.world.free()


func test_the_radio_desk_at_noon_and_the_lookout_before_the_forecast_are_busy() -> void:
	var g := _game("dez")
	var sim = g.sim
	var ruth = _p(sim, "ruth")
	var marcus = _p(sim, "marcus")
	eq(sim.jobs.job_of(ruth), "radio", "Ruth is the radio desk")
	eq(sim.jobs.job_of(marcus), "watch", "Marcus is the lookout")
	_at(sim, 3, 10.0)
	check(sim.radio.willingness(ruth, "come").ok, "at ten the desk is quiet")
	_at(sim, 3, 12.0)
	var w: Dictionary = sim.radio.willingness(ruth, "come")
	check(not w.ok and String(w.why).contains("radio"), "at noon the radio is hers: %s" % str(w))
	_at(sim, 3, 13.0)
	check(sim.radio.willingness(ruth, "come").ok, "after the hour she is free")
	_at(sim, 3, 15.0)
	check(sim.radio.willingness(marcus, "come").ok, "the lookout is free at three")
	_at(sim, 3, 16.7)
	w = sim.radio.willingness(marcus, "come")
	check(not w.ok and String(w.why).contains("forecast"), "half an hour before the forecast he is not: %s" % str(w))
	sim.tactics.forecast_day = sim.day
	check(sim.radio.willingness(marcus, "come").ok, "once the forecast is given he is free again")
	g.world.free()


func test_go_back_and_the_walls_are_only_refused_to_the_downed_and_the_away() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.bleeding = 4.0
	dez.hunger_h = 40.0
	sim.morale.set_value(dez, 20.0)
	for v in ["back", "post"]:
		check(sim.radio.willingness(dez, v).ok, "'%s' is asked of anyone on their feet" % v)
	dez.downed = true
	for v in ["back", "post"]:
		check(not sim.radio.willingness(dez, v).ok, "but not of someone down: '%s'" % v)
	g.world.free()


# -------------------------------------------------------------------- trust --

func test_trust_sets_the_delay_and_the_tone() -> void:
	var g := _game()
	var radio = g.sim.radio
	near(radio.delay_for(100.0), 0.5, 0.0001, "a trusted friend: half a second")
	near(radio.delay_for(80.0), 0.5, 0.0001, "from 80 up")
	near(radio.delay_for(20.0), 4.0, 0.0001, "a doubtful one: four seconds")
	near(radio.delay_for(0.0), 4.0, 0.0001, "and no worse")
	check(radio.delay_for(50.0) > 0.5 and radio.delay_for(50.0) < 4.0, "in between it is in between")
	check(radio.delay_for(60.0) < radio.delay_for(40.0), "more trust, a shorter delay")
	eq(radio.tone_for(90.0), "willing", "90")
	eq(radio.tone_for(55.0), "willing", "the start (55)")
	eq(radio.tone_for(40.0), "grudging", "40")
	eq(radio.tone_for(25.0), "doubtful", "25")
	var dez = _p(g.sim, "dez")
	dez.trust = 90.0
	var w: Dictionary = radio.willingness(dez, "come")
	near(w.delay_s, 0.5, 0.0001, "willingness carries the delay")
	eq(w.tone, "willing", "and the tone")
	dez.trust = 10.0
	w = radio.willingness(dez, "come")
	near(w.delay_s, 4.0, 0.0001, "a doubtful contact")
	eq(w.tone, "doubtful", "doubtful")
	g.world.free()


func test_trust_is_kept_between_0_and_100_with_the_reasons_remembered() -> void:
	var g := _game()
	var radio = g.sim.radio
	var dez = _p(g.sim, "dez")
	near(radio.trust_of(dez), 55.0, 0.0001, "everybody starts at 55")
	radio.add_trust(dez, 70.0, "Came back safe")
	near(radio.trust_of(dez), 100.0, 0.0001, "never over 100")
	radio.add_trust(dez, -250.0, "Left them behind")
	near(radio.trust_of(dez), 0.0, 0.0001, "never under 0")
	var why: Array = radio.trust_why(dez)
	eq(why.size(), 2, "two reasons so far")
	eq(why[0].why, "Left them behind", "the newest first")
	near(float(why[0].delta), -250.0, 0.0001, "with what it was")
	eq(why[1].why, "Came back safe", "then the one before")
	for i in 10:
		radio.add_trust(dez, 1.0, "Reason %d" % i)
	check(radio.trust_why(dez).size() <= 6, "only the last few are kept")
	eq(radio.trust_why(dez)[0].why, "Reason 9", "the newest is still first")
	eq(radio.trust_why(_p(g.sim, "ana")), [], "nobody else has any")
	g.world.free()


func test_a_trip_led_brings_trust_and_a_hurt_follower_costs_it() -> void:
	var g := _game()
	var sim = g.sim
	var radio = sim.radio
	var dez = _p(sim, "dez")
	var ana = _p(sim, "ana")
	var hector = _p(sim, "hector")
	hector.dead = true
	radio.on_trip_led([dez, ana, hector])
	near(radio.trust_of(dez), 57.0, 0.0001, "+2 for coming back safe from a trip you led")
	near(radio.trust_of(ana), 57.0, 0.0001, "for everyone who came back")
	near(radio.trust_of(hector), 55.0, 0.0001, "not for the dead")
	# hurt following a request within two minutes
	var walt = _p(sim, "walt")
	radio.request(walt, "come")
	Helpers.run(sim, 5.0)
	eq(walt.stance, "follow", "Walt follows")
	radio.on_hurt_following(walt)
	near(radio.trust_of(walt), 52.0, 0.0001, "-3 when someone is hurt following you")
	radio.on_hurt_following(walt)
	near(radio.trust_of(walt), 52.0, 0.0001, "once for each request")
	radio.on_hurt_following(dez)
	near(radio.trust_of(dez), 57.0, 0.0001, "and not for someone who was not following")
	# a long time after the request it is not the request's fault
	radio.request(dez, "come")
	Helpers.run(sim, 5.0)
	radio.tick(130.0)
	radio.on_hurt_following(dez)
	near(radio.trust_of(dez), 57.0, 0.0001, "more than two minutes after, it is nobody's fault")
	g.world.free()


# ------------------------------------------------------------------ requests --

func test_a_request_is_answered_at_once_and_the_stance_comes_after_the_delay() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.trust = 90.0
	var r: Dictionary = sim.radio.request(dez, "come")
	check(r.ok, "Dez agrees")
	eq(r.tone, "willing", "willingly")
	near(r.delay_s, 0.5, 0.0001, "in half a second")
	eq(r.line, "On my way.", "and says so")
	eq(dez.stance, "", "nothing yet: they have to hear it")
	Helpers.run(sim, 0.3)
	eq(dez.stance, "", "still nothing after 0.3 s")
	Helpers.run(sim, 0.4)
	eq(dez.stance, "follow", "after the delay they follow")
	check(dez.drafted, "and they are drafted, so the day's rules let them shoot")
	# a doubtful one is slower, and says so
	var ana = _p(sim, "ana")
	ana.trust = 10.0
	r = sim.radio.request(ana, "come")
	check(r.ok, "Ana agrees")
	eq(r.tone, "doubtful", "doubtfully")
	near(r.delay_s, 4.0, 0.0001, "in four seconds")
	eq(r.line, "...if you say so.", "with her voice")
	Helpers.run(sim, 3.5)
	eq(ana.stance, "", "not after 3.5 s")
	Helpers.run(sim, 1.0)
	eq(ana.stance, "follow", "but after four")
	g.world.free()


func test_a_refused_request_says_why_and_changes_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	sim.medical.jobs.append({"healer": ana, "patient": _p(sim, "hector"), "kind": "bandage", "work": 0.0, "stand": null, "anchor": Vector2.ZERO})
	var r: Dictionary = sim.radio.request(ana, "come")
	check(not r.ok, "refused")
	eq(r.why, "Ana: tending a patient, can't come", "with the reason")
	check(String(r.line) != "", "she says it")
	near(r.delay_s, 0.0, 0.0001, "at once")
	Helpers.run(sim, 6.0)
	eq(ana.stance, "", "and nothing happens")
	near(sim.radio.trust_of(ana), 55.0, 0.0001, "asking costs no trust")
	check(sim.radio.pending.is_empty(), "and nothing is waiting")
	var bad: Dictionary = sim.radio.request(_p(sim, "dez"), "dance")
	check(not bad.ok, "a verb that is not one is refused")
	g.world.free()


func test_a_later_request_replaces_one_still_waiting() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.trust = 90.0
	sim.radio.request(dez, "come")
	sim.radio.request(dez, "hold", {"at": Vector2(30.5, 38.5)})
	check(sim.radio.pending.size() == 1, "one request waits for Dez")
	Helpers.run(sim, 1.0)
	eq(dez.stance, "hold", "the last one is what he does")
	g.world.free()


func test_insisting_overrides_a_refusal_at_a_cost_of_trust_but_not_for_the_down() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.bleeding = 4.0
	dez.wounds = 1
	check(not sim.radio.request(dez, "come").ok, "refused as asked")
	near(sim.radio.trust_of(dez), 55.0, 0.0001, "no cost for asking")
	var mood_before: float = sim.morale.value(dez)
	var r: Dictionary = sim.radio.request(dez, "come", {"insist": true})
	check(r.ok, "insisted: he comes")
	eq(r.line, "...if you say so.", "grudgingly")
	near(sim.radio.trust_of(dez), 49.0, 0.0001, "at a cost of 6 trust")
	check(sim.morale.value(dez) < mood_before, "and a blow to his mood")
	check(String(sim.radio.trust_why(dez)[0].why) != "", "with the reason kept")
	Helpers.run(sim, 5.0)
	eq(dez.stance, "follow", "and he follows")
	# the down cannot be pushed
	var hector = _p(sim, "hector")
	hector.downed = true
	r = sim.radio.request(hector, "come", {"insist": true})
	check(not r.ok, "a person who is down cannot come however you insist")
	near(sim.radio.trust_of(hector), 55.0, 0.0001, "and it costs nothing")
	g.world.free()


func test_insisting_takes_a_nurse_off_her_patient() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var hector = _p(sim, "hector")
	hector.bleeding = 4.0
	hector.wounds = 1
	Helpers.run(sim, 0.5)
	check(not sim.medical.jobs.is_empty(), "Ana goes to bandage Hector")
	var r: Dictionary = sim.radio.request(ana, "come", {"insist": true})
	check(r.ok, "Ana is made to come")
	Helpers.run(sim, 5.0)
	eq(ana.stance, "follow", "she follows")
	var healing := false
	for j in sim.medical.jobs:
		healing = healing or j.healer == ana
	check(not healing, "and she is no longer a healer with a job")
	g.world.free()


# ------------------------------------------------------------------- stances --

func test_follow_stands_within_two_tiles_of_the_leader_and_faces_the_aim() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_stand(dez, "follow")
	dez.x = LEADER_AT.x - 10.0
	dez.y = LEADER_AT.y + 8.0
	var goal = sim.radio.stance_goal(dez)
	check(goal != null, "a follower has a goal")
	check(Vector2(goal.x, goal.y).distance_to(LEADER_AT) <= 2.2, "within 2.2 tiles of the leader: %s" % str(goal))
	check(not sim.world.is_solid(sim.world.solid_p, goal.x, goal.y), "on open ground")
	dez.x = LEADER_AT.x - 1.5
	dez.y = LEADER_AT.y + 0.8
	goal = sim.radio.stance_goal(dez)
	near(goal.x, dez.x, 0.0001, "near enough already, they stay where they are (x)")
	near(goal.y, dez.y, 0.0001, "(y)")
	eq(goal.face, "E", "and face where the leader aims (east)")
	_p(sim, "ruth").facing = "N"
	eq(sim.radio.stance_goal(dez).face, "N", "the aim turned north")
	g.world.free()


func test_follow_uses_the_aim_point_of_the_avatar_when_there_is_one() -> void:
	var g := _game()
	var sim = g.sim
	var lead = _p(sim, "ruth")
	if lead.get("input_aim") == null:
		g.world.free()
		return    # (no avatar yet: the facing above is what there is)
	var dez = _p(sim, "dez")
	_stand(dez, "follow")
	dez.x = LEADER_AT.x - 1.5
	dez.y = LEADER_AT.y + 0.8
	lead.input_aim = Vector2(LEADER_AT.x, LEADER_AT.y + 8.0)
	eq(sim.radio.stance_goal(dez).face, "S", "the mouse is to the south, so they face south")
	_stand(dez, "cover")
	var goal = sim.radio.stance_goal(dez)
	check(goal.y < LEADER_AT.y - 3.0, "and the cover stands north, behind the aim: %s" % str(goal))
	g.world.free()


func test_a_follower_walks_to_the_leader_and_keeps_up() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	sim.radio.request(dez, "come")
	Helpers.run(sim, 8.0)
	eq(dez.stance, "follow", "following")
	check(Vector2(dez.x, dez.y).distance_to(LEADER_AT) <= 2.4, "he is next to the leader: %s" % str(Vector2(dez.x, dez.y)))
	var lead = _p(sim, "ruth")
	_put_leader(sim, lead, Vector2(27.5, 38.5), "W")
	Helpers.run(sim, 8.0)
	check(Vector2(dez.x, dez.y).distance_to(Vector2(27.5, 38.5)) <= 2.4, "the leader moved and he moved with them: %s" % str(Vector2(dez.x, dez.y)))
	g.world.free()


func test_cover_stands_four_to_five_tiles_behind_the_aim() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_stand(dez, "cover")
	var goal = sim.radio.stance_goal(dez)
	var d := Vector2(goal.x, goal.y).distance_to(LEADER_AT)
	check(d >= 4.0 and d <= 5.0, "four to five tiles from the leader: %s" % str(d))
	check(goal.x < LEADER_AT.x - 3.0, "behind a leader who aims east, so to the west: %s" % str(goal))
	eq(goal.face, "E", "facing the way the leader aims")
	_p(sim, "ruth").facing = "N"
	goal = sim.radio.stance_goal(dez)
	check(goal.y > LEADER_AT.y + 3.0, "behind a leader who aims north is south: %s" % str(goal))
	# two of them do not stand on one spot
	var hector = _p(sim, "hector")
	_stand(hector, "cover")
	var a = sim.radio.stance_goal(dez)
	var b = sim.radio.stance_goal(hector)
	check(Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) >= 1.0, "two covering people are apart: %s %s" % [str(a), str(b)])
	g.world.free()


func test_hold_keeps_the_spot_where_the_leader_was_when_asked() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.trust = 90.0
	sim.radio.request(dez, "hold")
	var lead = _p(sim, "ruth")
	_put_leader(sim, lead, Vector2(28.5, 30.5), "E")    # the leader walks off before it is heard
	Helpers.run(sim, 10.0)
	eq(dez.stance, "hold", "holding")
	near(dez.stance_at.x, LEADER_AT.x, 0.0001, "the spot is where the leader stood when they asked (x)")
	near(dez.stance_at.y, LEADER_AT.y, 0.0001, "(y)")
	check(Vector2(dez.x, dez.y).distance_to(LEADER_AT) < 0.2, "and he stands there: %s" % str(Vector2(dez.x, dez.y)))
	var hector = _p(sim, "hector")
	hector.trust = 90.0
	sim.radio.request(hector, "hold", {"at": Vector2(30.5, 39.5)})
	Helpers.run(sim, 10.0)
	near(hector.stance_at.x, 30.5, 0.0001, "a spot given in the request is the spot")
	check(Vector2(hector.x, hector.y).distance_to(Vector2(30.5, 39.5)) < 0.2, "and he is there")
	g.world.free()


func test_search_keeps_the_point_to_be_searched() -> void:
	var g := _game()
	var sim = g.sim
	var hector = _p(sim, "hector")
	hector.trust = 90.0
	var r: Dictionary = sim.radio.request(hector, "search", {"at": Vector2(33.5, 40.5)})
	check(r.ok, "Hector will search")
	Helpers.run(sim, 8.0)
	eq(hector.stance, "search", "searching")
	near(hector.stance_at.x, 33.5, 0.0001, "the container's point (x)")
	near(hector.stance_at.y, 40.5, 0.0001, "(y)")
	check(Vector2(hector.x, hector.y).distance_to(Vector2(33.5, 40.5)) < 0.2, "he goes to it: %s" % str(Vector2(hector.x, hector.y)))
	g.world.free()


func test_go_back_clears_the_stance_and_the_job_is_theirs_again() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.trust = 90.0
	sim.radio.request(dez, "come")
	Helpers.run(sim, 2.0)
	eq(dez.stance, "follow", "following")
	var r: Dictionary = sim.radio.request(dez, "back")
	check(r.ok, "he is asked to go back")
	Helpers.run(sim, 1.0)
	eq(dez.stance, "", "no stance")
	eq(dez.stance_at, Vector2.ZERO, "no spot")
	check(not dez.drafted, "not drafted")
	check(dez.order == null, "no order")
	check(sim.radio.stance_goal(dez) == null, "no goal of the radio's")
	Helpers.run(sim, 12.0)
	check(Vector2(dez.x, dez.y).distance_to(sim.jobs.seat_pos(dez)) < 1.0, "and he is at his bench again: %s" % str(Vector2(dez.x, dez.y)))
	g.world.free()


func test_to_the_walls_sends_them_to_their_night_post() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.trust = 90.0
	sim.radio.request(dez, "come")
	Helpers.run(sim, 2.0)
	var r: Dictionary = sim.radio.request(dez, "post")
	check(r.ok, "to the walls")
	Helpers.run(sim, 1.0)
	eq(dez.stance, "", "the stance is gone")
	check(dez.order != null and dez.order.z > 0.5, "an order to the post")
	var post: Vector2 = sim.jobs.post_pos(dez)
	Helpers.run(sim, 15.0)
	check(Vector2(dez.x, dez.y).distance_to(post) < 0.5, "and he is at it: %s, the post is %s" % [str(Vector2(dez.x, dez.y)), str(post)])
	g.world.free()


func test_a_person_with_a_stance_still_shoots_what_they_see() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.trust = 90.0
	dez.x = 34.5
	dez.y = 36.5
	dez.path = []
	dez.goal_key = ""
	sim.radio.request(dez, "hold", {"at": Vector2(34.5, 36.5)})
	Helpers.run(sim, 1.5)
	eq(dez.stance, "hold", "holding")
	check(sim.phase == "day", "by day")
	var z = sim.spawn(dez.x + 5.0, dez.y, "wander")
	var hp0: float = z.hp
	var shots0: int = dez.stats.shots
	Helpers.run(sim, 6.0)
	check(dez.stats.shots > shots0, "he fired at it")
	check(z.hp < hp0 or z.state == "dying" or z.state == "dead", "and hit it")
	g.world.free()


func test_a_stance_ends_when_they_go_down_are_lost_or_leave() -> void:
	var g := _game()
	var sim = g.sim
	for state in ["downed", "dead", "turned", "away"]:
		var dez = _p(sim, "dez")
		_stand(dez, "follow")
		match state:
			"downed":
				dez.downed = true
			"dead":
				dez.dead = true
			"turned":
				dez.dead = true
				dez.turned = true
			"away":
				dez.away = {"kind": "trip"}
		check(sim.radio.stance_goal(dez) == null, "no goal for someone who is %s" % state)
		Helpers.run(sim, 0.2)
		eq(dez.stance, "", "the stance is cleared when they are %s" % state)
		dez.downed = false
		dez.dead = false
		dez.turned = false
		dez.away = null
	# a breakdown too
	var hector = _p(sim, "hector")
	_stand(hector, "hold", Vector2(30.5, 39.5))
	sim.morale.until[hector.id] = sim.clock_min + 60.0
	Helpers.run(sim, 0.2)
	eq(hector.stance, "", "and in a breakdown")
	# and the leader has no stance of their own
	var lead = _p(sim, "ruth")
	_stand(lead, "follow")
	Helpers.run(sim, 0.2)
	eq(lead.stance, "", "the leader is nobody's follower")
	g.world.free()


func test_a_person_with_a_stance_is_not_taken_as_a_healer() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var hector = _p(sim, "hector")
	sim.radio.request(ana, "hold", {"at": Vector2(34.5, 40.5)})
	Helpers.run(sim, 5.0)
	eq(ana.stance, "hold", "Ana holds")
	hector.bleeding = 4.0
	hector.wounds = 1
	Helpers.run(sim, 2.0)
	var healing := false
	for j in sim.medical.jobs:
		healing = healing or j.healer == ana
	check(not healing, "she is with the leader, not on the way to Hector")
	g.world.free()


func test_a_follower_left_behind_hurries_and_nobody_else_does() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	near(sim.radio.speed_of(dez), 3.0, 0.0001, "the usual walk")
	_stand(dez, "follow")
	dez.x = LEADER_AT.x - 2.0
	dez.y = LEADER_AT.y
	near(sim.radio.speed_of(dez), 3.0, 0.0001, "close behind: the usual walk")
	dez.x = LEADER_AT.x - 8.0
	check(sim.radio.speed_of(dez) > 3.2, "far behind the leader he hurries, faster than the avatar walks (3.2)")
	_stand(dez, "hold", Vector2(30.5, 39.5))
	near(sim.radio.speed_of(dez), 3.0, 0.0001, "someone holding a spot does not")
	var r: Dictionary = sim.radio.request(null, "come")
	check(not r.ok, "nobody is not asked")
	g.world.free()


func test_a_stance_can_be_set_at_once_for_a_squad_that_starts_out_following() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.order = Vector3(40.0, 30.0, 0.0)
	sim.radio.set_stance(dez, "follow")
	eq(dez.stance, "follow", "following at once")
	check(dez.drafted and dez.order == null, "drafted, and the old order is gone")
	check(sim.radio.stance_goal(dez) != null, "with a goal")
	sim.radio.set_stance(dez, "hold", Vector2(30.5, 39.5))
	eq(dez.stance_at, Vector2(30.5, 39.5), "a hold keeps its spot")
	sim.radio.set_stance(dez, "")
	eq(dez.stance, "", "an empty stance ends it")
	check(not dez.drafted, "and the draft")
	g.world.free()


# --------------------------------------------------------------------- news --

func test_the_log_keeps_sixty_entries_and_news_since_reads_from_an_id() -> void:
	var g := _game()
	var radio = g.sim.radio
	check(radio.news.is_empty(), "no news to begin with")
	for i in 70:
		radio.log_news("test", "Entry %d" % i, "sub %d" % i)
	eq(radio.news.size(), 60, "at most sixty")
	eq(radio.news[0].text, "Entry 10", "the oldest went first")
	eq(radio.news[59].text, "Entry 69", "the newest is last")
	var e: Dictionary = radio.news[59]
	eq(e.kind, "test", "kind")
	eq(e.sub, "sub 69", "sub")
	eq(e.day, g.sim.day, "the day")
	near(float(e.hour), 9.0, 0.001, "the hour")
	check(e.has("id") and e.has("t") and e.has("options") and e.has("answered"), "an entry has an id, a time, options and an answer")
	var mid: int = int(radio.news[54].id)
	var since: Array = radio.news_since(mid)
	eq(since.size(), 5, "five entries after the 55th")
	eq(since[0].text, "Entry 65", "from the next one")
	eq(radio.news_since(int(radio.news[59].id)), [], "nothing after the last")
	eq(radio.news_since(0).size(), 60, "everything since the start")
	eq(radio.latest_id(), int(radio.news[59].id), "the newest id")
	g.world.free()


func test_arrivals_successions_and_the_storytellers_cards_are_logged() -> void:
	var g := _game()
	var sim = g.sim
	sim.events.append({"type": "arrived", "who": "walt"})
	sim.events.append({"type": "succession", "from": "ruth", "to": "dez"})
	Helpers.run(sim, 0.1)
	var arrived := _calls(sim, "recruit")
	eq(arrived.size(), 1, "an arrival is logged")
	check(String(arrived[0].text).contains("Walt"), "with the name: %s" % str(arrived[0].text))
	var lost := _calls(sim, "succession")
	eq(lost.size(), 1, "a succession is logged")
	check(String(lost[0].text).contains("Dez") and String(lost[0].text).contains("Ruth"), "with both names: %s" % str(lost[0].text))
	# the storyteller's card with a choice: once when it comes, once when it is settled
	sim.storyteller.enabled = true
	sim.events.clear()
	check(sim.storyteller.force("stranger"), "a card is put up")
	Helpers.run(sim, 0.1)
	var story := _calls(sim, "story")
	eq(story.size(), 1, "the card is on the log")
	check(String(story[0].text).contains("gate"), "by its title: %s" % str(story[0].text))
	check(story[0].options.is_empty(), "the log only: the storyteller's own card stays")
	sim.storyteller.choose(2)
	Helpers.run(sim, 0.1)
	story = _calls(sim, "story")
	eq(story.size(), 2, "and again when it is settled")
	check(String(story[1].sub) != "", "with what came of it: %s" % str(story[1]))
	# a card with no choice is one entry
	var plain := ""
	for c in sim.storyteller.cards:
		if c.choices.is_empty() and plain == "":
			plain = String(c.id)
	check(plain != "", "the deck has a card with no choice")
	sim.storyteller.force(plain)
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "story").size(), 3, "a card with no choice is one entry")
	g.world.free()


func test_a_bite_in_the_step_costs_the_trust_of_the_one_who_was_following() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	dez.trust = 90.0
	sim.radio.request(dez, "come")
	Helpers.run(sim, 2.0)
	eq(dez.stance, "follow", "Dez follows")
	sim.events.append({"type": "bite", "x": dez.x, "y": dez.y, "who": "dez"})
	sim.events.append({"type": "bite", "x": hector.x, "y": hector.y, "who": "hector"})
	Helpers.run(sim, 0.1)
	near(sim.radio.trust_of(dez), 87.0, 0.0001, "Dez was bitten following: -3")
	near(sim.radio.trust_of(hector), 55.0, 0.0001, "Hector was not following anything")
	g.world.free()


func test_the_radio_works_in_a_place_without_the_colonys_steps() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var heard: Array = []
	sim.radio.on_applied = func(p, verb, at): heard.append([String(p.id), verb, at])
	dez.trust = 90.0
	sim.radio.request(dez, "hold", {"at": Vector2(30.5, 39.5)})
	sim.radio.tick(0.3)
	eq(dez.stance, "", "not yet")
	sim.radio.tick(0.3)
	eq(dez.stance, "hold", "the radio's own tick is enough: a place's scene calls it")
	eq(heard.size(), 1, "and the hook was told")
	eq(heard[0][1], "hold", "what was asked")
	eq(heard[0][2], Vector2(30.5, 39.5), "and where")
	sim.radio.request(dez, "back")
	sim.radio.tick(1.0)
	eq(heard.size(), 2, "'go back' is told too (a place's squad walks to the exit)")
	eq(heard[1][1], "back", "go back")
	var done := false
	for e in sim.events:
		done = done or (e.type == "stance" and e.who == "dez" and e.verb == "back")
	check(done, "and it is an event")
	g.world.free()


func test_a_leader_who_is_away_cannot_be_followed_but_can_send_people_to_the_walls() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_p(sim, "ruth").away = {"kind": "trip"}
	var r: Dictionary = sim.radio.request(dez, "come")
	check(not r.ok and String(r.why).contains("not at the base"), "they cannot come to a leader who is elsewhere: %s" % str(r.why))
	check(not sim.radio.request(dez, "cover").ok, "nor cover them")
	check(not sim.radio.request(dez, "hold").ok, "nor hold where they stand")
	check(sim.radio.request(dez, "hold", {"at": Vector2(30.5, 39.5)}).ok, "but they can hold a spot they are given")
	check(sim.radio.request(dez, "post").ok, "and go to the walls")
	check(sim.radio.request(dez, "back").ok, "and go back to work")
	_p(sim, "ruth").away = null
	g.world.free()


func test_the_leader_is_never_the_subject_of_a_fever_call() -> void:
	var g := _game()
	var sim = g.sim
	_p(sim, "ruth").infected_at = sim.clock_min - 7.0 * 60.0
	var dez = _p(sim, "dez")
	dez.infected_at = sim.clock_min - 7.0 * 60.0
	sim.medical.treat_orders[dez.id] = true
	Helpers.run(sim, 0.2)
	eq(_calls(sim, "sick").size(), 0, "the player knows they are ill, and Dez is already being treated")
	g.world.free()


# -------------------------------------------------------------------- calls --

func test_a_wall_under_attack_raises_one_call_with_three_options_and_holds_by_default() -> void:
	var g := _game()
	var sim = g.sim
	_night(sim)
	_attack(sim, BUS, 2)
	Helpers.run(sim, 3.0)
	var calls := _calls(sim, "attack")
	eq(calls.size(), 1, "the dead at the bus raise a call")
	var c: Dictionary = calls[0]
	check(String(c.text).to_lower().contains("bus"), "about the bus: %s" % str(c.text))
	var ids: Array = []
	for o in c.options:
		ids.append(o.id)
		check(String(o.label) != "", "each option has a label")
	eq(ids, ["hold", "reinforce", "fall_back"], "hold, send reinforcements, fall back to the school")
	eq(c.default, "hold", "the default is to hold")
	eq(c.answered, "", "nobody has answered")
	eq(sim.radio.open_calls().size(), 1, "it is an open call")
	Helpers.run(sim, 8.0)
	eq(_calls(sim, "attack").size(), 1, "one call for a section for a night, however long it lasts")
	check(sim.radio.open_calls().size() <= 1, "still the one")
	Helpers.run(sim, 6.0)
	eq(_calls(sim, "attack")[0].answered, "hold", "left alone, it takes its default after its time")
	check(_calls(sim, "attack")[0].by_default, "and says so")
	eq(sim.radio.open_calls().size(), 0, "no open call is left")
	g.world.free()


func test_reinforcements_send_everyone_who_is_free_to_the_section() -> void:
	var g := _game()
	var sim = g.sim
	_night(sim)
	var ana = _p(sim, "ana")
	var hector = _p(sim, "hector")
	hector.bleeding = 4.0
	hector.wounds = 1
	_attack(sim, BUS, 2)
	Helpers.run(sim, 2.5)
	check(not sim.medical.jobs.is_empty() and sim.medical.jobs[0].healer == ana, "Ana is on her way to Hector")
	var c: Dictionary = _calls(sim, "attack")[0]
	var seg: Vector2 = Vector2(47.5, 18.9)
	check(sim.radio.answer(int(c.id), "reinforce"), "the player answers")
	eq(c.answered, "reinforce", "answered")
	check(not c.by_default, "by the player")
	for id in ["dez", "marcus", "walt"]:
		var p = _p(sim, id)
		check(p.order != null and p.drafted, "%s is sent" % id)
		if p.order != null:
			check(Vector2(p.order.x, p.order.y).distance_to(seg) < 14.0, "%s is sent to near the bus: %s" % [id, str(p.order)])
	check(ana.order == null, "the nurse with a patient stays with her patient")
	check(_p(sim, "ruth").order == null or _p(sim, "ruth").order.z < 0.5, "the leader gives themselves no order")
	check(not sim.radio.answer(int(c.id), "hold"), "a call is answered once")
	g.world.free()


func test_falling_back_sends_the_people_of_that_section_to_the_school() -> void:
	var g := _game()
	var sim = g.sim
	_night(sim)
	_attack(sim, BUS, 2)
	Helpers.run(sim, 2.5)
	var c: Dictionary = _calls(sim, "attack")[0]
	check(sim.radio.answer(int(c.id), "fall_back"), "fall back")
	var dez = _p(sim, "dez")    # Dez holds the bus post
	check(dez.order != null, "Dez, whose post is at the bus, is ordered back: %s" % str(dez.order))
	if dez.order != null:
		check(dez.order.y > 45.0, "into the school, south of its north wall: %s" % str(dez.order))
	check(_p(sim, "hector").order == null, "Hector's post is elsewhere: he stays")
	check(_p(sim, "marcus").order == null, "so does Marcus")
	g.world.free()


func test_a_fever_raises_a_call_to_treat_or_keep_them_apart() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.infected_at = sim.clock_min - 7.0 * 60.0
	Helpers.run(sim, 0.2)
	var calls := _calls(sim, "sick")
	eq(calls.size(), 1, "a fever raises a call")
	var c: Dictionary = calls[0]
	check(String(c.text).contains("Dez"), "about Dez: %s" % str(c.text))
	var ids: Array = []
	for o in c.options:
		ids.append(o.id)
	eq(ids, ["treat", "apart"], "treat them or keep them apart")
	eq(c.default, "treat", "the default is to treat")
	Helpers.run(sim, 3.0)
	eq(_calls(sim, "sick").size(), 1, "one call for one sickness")
	check(sim.radio.answer(int(c.id), "treat"), "treat them")
	check(sim.medical.treat_orders.has("dez"), "and a treatment is ordered")
	g.world.free()


func test_keeping_them_apart_costs_a_little_morale_and_cures_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.infected_at = sim.clock_min - 7.0 * 60.0
	Helpers.run(sim, 0.2)
	var c: Dictionary = _calls(sim, "sick")[0]
	var before: float = sim.morale.value(dez)
	check(sim.radio.answer(int(c.id), "apart"), "apart")
	check(sim.morale.value(dez) < before, "he is lower for it")
	check(not sim.medical.treat_orders.has("dez"), "and no treatment")
	check(dez.infected_at >= 0.0, "the infection is still there")
	g.world.free()


func test_an_unanswered_fever_call_takes_the_treatment_by_default() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.infected_at = sim.clock_min - 7.0 * 60.0
	Helpers.run(sim, 0.2)
	var c: Dictionary = _calls(sim, "sick")[0]
	var open_for: float = float(c.due) - sim.clock_min
	check(open_for > 0.0, "it waits a while: %s game minutes" % str(open_for))
	Helpers.run(sim, open_for / sim.min_per_sec + 1.0)
	eq(c.answered, "treat", "nobody answered: it was treated")
	check(c.by_default, "by default")
	check(sim.medical.treat_orders.has("dez"), "and the treatment was ordered")
	g.world.free()


func test_any_call_takes_its_default_when_its_time_is_up() -> void:
	var g := _game()
	var sim = g.sim
	var radio = sim.radio
	var id: int = radio.raise_call("test", "A voice on the radio", "somewhere north", [{"id": "yes", "label": "Yes"}, {"id": "no", "label": "No"}], "no", 10.0)
	check(id > 0, "a call has an id")
	eq(radio.open_calls().size(), 1, "it is open")
	check(not radio.answer(id, "maybe"), "an option it does not have is not an answer")
	eq(radio.open_calls().size(), 1, "still open")
	Helpers.run(sim, 2.0)    # 6 game minutes
	eq(radio.open_calls().size(), 1, "still open after six minutes of ten")
	Helpers.run(sim, 2.0)
	eq(radio.open_calls().size(), 0, "and closed after twelve")
	var e: Dictionary = radio.news[radio.news.size() - 1]
	eq(e.answered, "no", "with its default")
	check(not radio.answer(id, "yes"), "too late")
	var id2: int = radio.raise_call("test", "Another", "", [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}], "a", 30.0)
	check(radio.answer(id2, "b"), "answered in time")
	eq(radio.news[radio.news.size() - 1].answered, "b", "as the player chose")
	check(not radio.answer(999, "a"), "a call that is not there")
	g.world.free()


func test_the_calls_come_and_default_while_the_colony_is_fast_forwarded() -> void:
	var g := _game()
	var sim = g.sim
	_night(sim)
	_attack(sim, BUS, 2)
	sim.events.append({"type": "arrived", "who": "walt"})
	var left: float = sim.fast_forward(60.0)
	near(left, 0.0, 0.0001, "an hour of game time is done")
	eq(_calls(sim, "recruit").size(), 1, "an arrival is read once, however many steps the fast-forward took")
	var calls := _calls(sim, "attack")
	eq(calls.size(), 1, "the wall under attack raised its call on the way")
	eq(calls[0].answered, "hold", "and nobody answered it, so it took its default")
	check(calls[0].by_default, "by default")
	g.world.free()


# -------------------------------------------------------------------- alarm --

func test_the_alarm_is_the_call_to_arms_and_standing_down_ends_it() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_at(sim, 3, 10.0)
	check(not sim.posts_manned(), "by day the posts are empty")
	_stand(dez, "follow")
	sim.radio.alarm(true)
	check(sim.radio.alarm_on, "the alarm rings")
	check(sim.posts_manned(), "the posts are manned at once, by day")
	check(sim.threat_by_day(), "the guns are free by day")
	check(sim.tactics.threat_until > sim.clock_min + 1000.0, "the threat is set far ahead")
	eq(dez.stance, "", "whoever was with the leader goes to the walls too")
	var post: Vector2 = sim.jobs.post_pos(dez)
	Helpers.run(sim, 15.0)
	check(Vector2(dez.x, dez.y).distance_to(post) < 0.5, "Dez is at his post: %s, the post is %s" % [str(Vector2(dez.x, dez.y)), str(post)])
	check(_calls(sim, "alarm").size() == 1, "the log says so")
	sim.radio.alarm(false)
	check(not sim.radio.alarm_on, "stood down")
	check(not sim.posts_manned(), "the posts are empty again")
	check(not sim.threat_by_day(), "and the day goes on")
	Helpers.run(sim, 15.0)
	check(Vector2(dez.x, dez.y).distance_to(sim.jobs.seat_pos(dez)) < 1.0, "Dez is back at his bench: %s" % str(Vector2(dez.x, dez.y)))
	check(_calls(sim, "alarm").size() == 2, "and the log has that too")
	g.world.free()


func test_the_alarm_stands_down_by_itself_at_dawn() -> void:
	var g := _game()
	var sim = g.sim
	_night(sim)
	sim.radio.alarm(true)
	check(sim.radio.alarm_on, "ringing in the night")
	_at(sim, 4, 5.4)
	Helpers.run(sim, 2.0)
	check(sim.radio.alarm_on, "still at the end of the night")
	_at(sim, 4, 6.3)
	Helpers.run(sim, 1.0)
	_at(sim, 4, 6.45)
	Helpers.run(sim, 20.0)
	check(sim.phase == "day", "it is day")
	check(not sim.radio.alarm_on, "and the alarm has been stood down")
	g.world.free()


# --------------------------------------------------------------- avatar mode --

func test_with_no_avatar_nothing_happens() -> void:
	var g := Helpers.make(1, 1, 6)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	eq(sim.player_id, "", "no avatar")
	_night(sim)
	var dez = _p(sim, "dez")
	dez.infected_at = sim.clock_min - 7.0 * 60.0
	sim.events.append({"type": "arrived", "who": "walt"})
	_attack(sim, BUS, 2)
	Helpers.run(sim, 20.0)
	check(sim.radio.news.is_empty(), "the log is empty: %s" % str(sim.radio.news))
	check(sim.radio.open_calls().is_empty(), "there is no call")
	check(sim.radio.pending.is_empty(), "nothing is waiting")
	check(not sim.radio.alarm_on, "no alarm")
	check(not sim.medical.treat_orders.has("dez"), "nobody was treated by a default")
	for p in sim.people:
		eq(p.stance, "", "no stances")
		near(p.trust, 55.0, 0.0001, "no trust has moved")
	g.world.free()


func test_asking_with_no_avatar_is_refused_not_obeyed() -> void:
	var g := Helpers.make(1, 1, 6)
	var r: Dictionary = g.sim.radio.request(_p(g.sim, "dez"), "come")
	check(not r.ok, "there is nobody to follow")
	g.world.free()


# --------------------------------------------------------------------- save --

func test_the_radio_survives_a_save() -> void:
	var a := _game()
	var sim = a.sim
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	dez.trust = 80.0
	sim.radio.add_trust(dez, -4.0, "Hurt following you")
	sim.radio.alarm(true)
	sim.radio.request(dez, "hold", {"at": Vector2(30.5, 39.5)})
	Helpers.run(sim, 5.0)
	hector.trust = 30.0
	sim.radio.request(hector, "come")    # still waiting for its delay
	var c: int = sim.radio.raise_call("test", "A voice", "north", [{"id": "yes", "label": "Yes"}, {"id": "no", "label": "No"}], "no", 30.0, {"seg": 3})
	sim.radio.log_news("test", "Something happened", "and then")
	check(not sim.radio.pending.is_empty(), "a request is waiting")
	var d := SaveGame.to_dict(sim)
	check(d.modules.has("radio"), "the radio is a module of the save")
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads from text")
	var rb = b.sim.radio
	eq(rb.news.size(), sim.radio.news.size(), "the log")
	eq(str(rb.news), str(sim.radio.news), "the same log, entry for entry")
	eq(rb.pending.size(), 1, "the waiting request")
	check(rb.alarm_on, "the alarm")
	var db = _p(b.sim, "dez")
	near(db.trust, 76.0, 0.0001, "trust is a person's own")
	eq(db.stance, "hold", "so is the stance")
	near(db.stance_at.x, 30.5, 0.0001, "and its spot")
	eq(rb.trust_why(db).size(), 1, "the reasons are remembered")
	eq(rb.trust_why(db)[0].why, "Hurt following you", "with their words")
	eq(rb.open_calls().size(), 1, "an open call is still open")
	check(rb.answer(c, "yes"), "and can still be answered")
	# the loaded one carries on: the waiting request is applied after its delay
	Helpers.run(b.sim, 6.0)
	eq(_p(b.sim, "hector").stance, "follow", "the waiting request came true after the load")
	a.world.free()
	b.world.free()


func test_a_save_from_before_the_radio_loads_with_an_empty_radio() -> void:
	var a := _game()
	a.sim.radio.log_news("test", "Something", "")
	a.sim.radio.alarm(true)
	var d := SaveGame.to_dict(a.sim)
	d.modules.erase("radio")
	var b := _bare()
	check(SaveGame.apply(b.sim, d), "it loads")
	check(b.sim.radio.news.is_empty(), "with no news")
	check(not b.sim.radio.alarm_on, "no alarm")
	check(b.sim.radio.pending.is_empty(), "nothing waiting")
	a.world.free()
	b.world.free()
