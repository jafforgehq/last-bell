extends "res://tests/case.gd"
## Round 18, S2.2 INTERACT (scripts/sim/interact.gd): the avatar uses what is near it. E talks to a person, takes a night post
## (the holder swaps posts with the avatar; steadier aim while it holds it), works the bench with its own hands and reads a
## car's fuel. Everything is behind avatar mode (`sim.player_id != ""`): with no avatar `interact` does nothing. The views
## (the prompt, the talk card) are tests/test_interact_view.gd's.

const Helpers := preload("res://tests/helpers.gd")
const Convoy := preload("res://scripts/sim/convoy.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const DT := 1.0 / 30.0
## The arena: open ground in the yard, carved free of props, where the avatar stands and the bench is.
const ARENA := Rect2i(34, 26, 20, 12)
const AT := Vector2(40.5, 30.5)
const GATE_SPOT := Vector2(39.0, 18.7)
const BUS_SPOT := Vector2(47.5, 18.7)


# ----------------------------------------------------------------- helpers --

func _p(sim, id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0


func _night(sim) -> void:
	_at(sim, 2, 22.0)
	sim.storyteller.enabled = false


## A quiet game at 09:00 with the avatar (Ruth, or `who`) at AT in a clear arena, nobody working, 100 ammo and 40 scrap.
func _game(who: String = "ruth", crew: int = 6) -> Dictionary:
	var g := Helpers.make(7, 1, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.no_work(sim)
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			g.world.solid_p[ty * g.world.W + tx] = 0
			g.world.solid_z[ty * g.world.W + tx] = 0
	check(sim.avatar.set_player(who), "%s is the player" % who)
	var p = _p(sim, who)
	p.x = AT.x
	p.y = AT.y
	p.path = []
	p.goal_key = ""
	_at(sim, 1, 9.0)
	sim.stock.ammo = 100.0
	sim.stock.scrap = 40.0
	sim.events.clear()
	g["p"] = p
	return g


func _put(p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.path = []
	p.goal_key = ""
	p.moving = false


func _events(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e.get("type", "")) == type:
			out.append(e)
	return out


func _kinds(list: Array) -> Array:
	var out: Array = []
	for c in list:
		out.append("%s:%s" % [c.kind, c.id])
	return out


## The avatar stands at the bench (a step to its side), the others away.
func _at_bench(g: Dictionary) -> void:
	var b: Vector2 = g.sim.workshop.bench()
	_put(g.p, b + Vector2(0.0, 1.0))


# --------------------------------------------------------- no avatar, no rules --

func test_with_no_avatar_interact_does_nothing() -> void:
	var g := Helpers.make(7, 1, 6)
	var sim = g.sim
	check(sim.interact != null, "the module exists")
	eq(sim.interact.candidates(), [], "nothing to use")
	eq(sim.interact.best(), {}, "no best")
	var r: Dictionary = sim.interact.use()
	eq(r.ok, false, "use is refused")
	eq(r.why, "Nothing here to use", "with the plain reason")
	eq(sim.interact.take_post("gate").ok, false, "no post is taken")
	eq(sim.interact.work_bench().ok, false, "no bench is worked")
	eq(sim.interact.brace_factor(_p(sim, "ruth")), 1.0, "no brace")
	sim.events.clear()
	Helpers.run(sim, 3.0)
	for type in ["interact", "talk", "post_taken", "post_left", "bench_work"]:
		eq(_events(sim, type).size(), 0, "no %s event" % type)
	eq(sim.interact.posted, "", "nobody is on a post")
	eq(sim.interact.working, "", "nobody works the bench")
	g.world.free()


# ----------------------------------------------------------------- candidates --

func test_candidates_are_the_things_in_reach_nearest_first() -> void:
	var g := _game()
	var sim = g.sim
	eq(sim.interact.candidates(), [], "nobody near, nothing to use")
	var dez = _p(sim, "dez")
	var hector = _p(sim, "hector")
	var ana = _p(sim, "ana")
	_put(dez, AT + Vector2(1.5, 0.0))
	_put(hector, AT + Vector2(0.0, -1.7))
	_put(ana, AT + Vector2(2.5, 0.0))    # out of reach
	var list: Array = sim.interact.candidates()
	eq(_kinds(list), ["person:dez", "person:hector"], "the two within 1.9 tiles, the nearer first")
	eq(list[0].label, "Talk to Dez", "the label says what E does")
	near(list[0].dist, 1.5, 0.001, "and how far")
	check(list[0].ok and list[0].why == "", "talking is always possible")
	eq(list[0].pos, Vector2(dez.x, dez.y), "at the person")
	eq(sim.interact.best().id, "dez", "best is the first")
	_put(ana, AT + Vector2(1.89, 0.0))
	eq(_kinds(sim.interact.candidates()), ["person:dez", "person:hector", "person:ana"], "1.89 is still in reach")
	_put(ana, AT + Vector2(1.95, 0.0))
	eq(sim.interact.candidates().size(), 2, "and 1.95 is not")
	g.world.free()


func test_a_person_beats_a_post_beats_the_bench_beats_a_car_on_a_tie() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var bench: Vector2 = sim.workshop.bench()
	# the avatar 1.27 tiles from the bench; Dez 1.4 from the avatar: within 0.3 of the bench, so the person first
	_put(g.p, bench + Vector2(-0.9, 0.9))
	_put(dez, Vector2(g.p.x, g.p.y) + Vector2(0.0, 1.4))
	var d_bench: float = Vector2(g.p.x, g.p.y).distance_to(bench)
	check(d_bench > 1.2 and d_bench < 1.4, "the bench is a little nearer than Dez: %.2f" % d_bench)
	eq(_kinds(sim.interact.candidates()), ["person:dez", "bench:bench"], "a person wins the tie")
	# 1.8 away he loses to the nearer bench (more than 0.3 behind)
	_put(dez, Vector2(g.p.x, g.p.y) + Vector2(0.0, 1.8))
	eq(_kinds(sim.interact.candidates()), ["bench:bench", "person:dez"], "farther by more than 0.3, the bench is first")
	# a parked car is a candidate within 3 tiles of the middle of its bay
	var v: Dictionary = sim.vehicles.add("pickup")
	var bay: Vector2 = Convoy.bay(int(v.spot))
	_put(g.p, bay + Vector2(1.5, 0.0))
	eq(_kinds(sim.interact.candidates()), ["vehicle:%s" % v.id], "a parked car in reach")
	_put(g.p, bay + Vector2(3.2, 0.0))
	eq(_kinds(sim.interact.candidates()), [], "3.2 tiles from the middle of the bay it is out of reach")
	v["state"] = "out"
	_put(g.p, bay + Vector2(1.5, 0.0))
	eq(_kinds(sim.interact.candidates()), [], "and a car that is out is not there to check")
	g.world.free()


func test_a_post_is_a_candidate_on_the_walkway_and_a_held_one_says_leave() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.p, GATE_SPOT)
	# (round 23: the gate is in reach from the walkway above it too, ranked after the post: this test is about the posts)
	var list: Array = sim.interact.candidates().filter(func(c): return String(c.kind) != "gate")
	eq(_kinds(list), ["post:gate"], "the gate post is in reach")
	eq(list[0].label, "Take the gate post", "named as the gate post")
	check(list[0].ok, "free to take (it is day)")
	_put(g.p, GATE_SPOT + Vector2(1.5, 0.0))
	eq(sim.interact.candidates().filter(func(c): return String(c.kind) != "gate").size(), 0, "1.5 tiles away it is out of reach (1.4)")
	_put(g.p, BUS_SPOT)
	check(sim.interact.take_post("bus").ok, "the bus post is taken")
	eq(sim.interact.candidates()[0].label, "Leave the school bus post", "a held post offers to leave it")
	g.world.free()


func test_a_post_a_manned_holder_stands_at_is_a_dim_candidate_with_the_reason() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_night(sim)
	_put(g.p, BUS_SPOT)
	_put(dez, Vector2(47.5, 18.8) + Vector2(1.2, 0.0))    # Dez holds the bus post and is at it
	var list: Array = sim.interact.candidates()
	eq(list[0].id, "bus", "the post is listed")
	eq(list[0].ok, false, "but not takeable")
	eq(list[0].why, "Dez is at the post", "and says why")
	g.world.free()


func test_nothing_in_reach_when_the_avatar_is_down_away_or_gone() -> void:
	var g := _game()
	var sim = g.sim
	_put(_p(sim, "dez"), AT + Vector2(1.0, 0.0))
	eq(sim.interact.candidates().size(), 1, "to begin with Dez is there")
	g.p.downed = true
	eq(sim.interact.candidates(), [], "down: nothing")
	g.p.downed = false
	g.p.away = {"state": "away"}
	eq(sim.interact.candidates(), [], "away on a trip: nothing")
	g.p.away = null
	eq(sim.interact.candidates().size(), 1, "back")
	var dez = _p(sim, "dez")
	dez.dead = true
	eq(sim.interact.candidates(), [], "the dead are not there to talk to")
	dez.dead = false
	dez.away = {"state": "away"}
	eq(sim.interact.candidates(), [], "nor are those away")
	g.world.free()


# ----------------------------------------------------------------------- talk --

func test_a_word_earns_a_little_trust_once_a_day() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_put(dez, AT + Vector2(1.0, 0.0))
	dez.activity = "Hauling crates"
	var t0: float = dez.trust
	var r: Dictionary = sim.interact.talk_to(dez)
	check(r.ok, "he talks")
	eq(r.who, "dez", "it names him")
	eq(r.gain, 1.0, "a word earns the trust")
	near(dez.trust, t0 + 1.0, 0.0001, "his trust is up by one")
	near(r.trust, dez.trust, 0.0001, "the answer says where it stands")
	eq(r.tone, sim.radio.tone_of(dez), "and the tone")
	eq(r.line, "Hauling crates.", "with nothing the matter his line is what he is doing")
	eq(sim.radio.trust_why(dez)[0].why, "Had a word with you", "the reason is remembered")
	var again: Dictionary = sim.interact.talk_to(dez)
	eq(again.gain, 0.0, "a second word the same day earns nothing")
	near(dez.trust, t0 + 1.0, 0.0001, "his trust is as it was")
	check(again.ok, "but he still talks")
	sim.day = 2
	eq(sim.interact.talk_to(dez).gain, 1.0, "the next day it earns again")
	near(dez.trust, t0 + 2.0, 0.0001, "and he trusts a little more")
	var talks: Array = _events(sim, "talk")
	eq(talks.size(), 3, "an event for each word")
	eq(talks[0].who, "dez", "naming him")
	eq(talks[0].line, "Hauling crates.", "and his line")
	g.world.free()


func test_a_person_turns_to_face_the_avatar_once_they_are_talked_to() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_put(dez, AT + Vector2(1.2, 0.0))
	dez.facing = "N"
	sim.interact.talk_to(dez)
	eq(dez.facing, "W", "he faces the avatar to his west")
	_put(dez, AT + Vector2(0.0, -1.2))
	sim.interact.talk_to(dez)
	eq(dez.facing, "S", "and to his south")
	g.world.free()


func test_only_the_leader_and_the_gone_cannot_be_talked_to() -> void:
	var g := _game()
	var sim = g.sim
	var r: Dictionary = sim.interact.talk_to(g.p)
	eq(r.ok, false, "you cannot talk to yourself")
	eq(r.why, "Nobody there", "the plain reason")
	var dez = _p(sim, "dez")
	dez.dead = true
	eq(sim.interact.talk_to(dez).ok, false, "the dead do not answer")
	dez.dead = false
	dez.turned = true
	eq(sim.interact.talk_to(dez).ok, false, "nor the turned")
	eq(sim.interact.talk_to(null).ok, false, "nor nobody")
	var ana = _p(sim, "ana")
	ana.downed = true
	check(sim.interact.talk_to(ana).ok, "someone down can still be talked to")
	eq(_events(sim, "talk").size(), 1, "and only that was an event")
	g.world.free()


func test_what_a_person_needs_in_the_order_of_the_contract() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_at(sim, 3, 9.0)    # (a fever seven hours old is after the start of the run)
	eq(sim.interact.needs_of(dez), [], "nothing the matter")
	dez.bleeding = 2.0
	dez.infected_at = float(sim.clock_min) - 60.0 * (sim.medical.FEVER_H + 1.0)
	dez.hunger_h = sim.supplies.STARVING_H + 1.0
	dez.thirst_h = sim.supplies.PARCHED_H + 1.0
	sim.morale.set_value(dez, 40.0)
	dez.mag = 0
	sim.stock.ammo = 10.0
	var needs: Array = sim.interact.needs_of(dez)
	var ids: Array = []
	for n in needs:
		ids.append(n.id)
		check(String(n.text) != "" and String(n.line) != "" and n.has("page"), "%s has text, a line and a page" % n.id)
	eq(ids, ["bleeding", "infection", "starving", "parched", "shaken", "ammo"], "the order of the contract")
	eq(needs[0].text, "Bleeding: needs the infirmary", "the first need's text")
	eq(needs[0].page, "", "bleeding has no page")
	eq(needs[4].text, "Shaken: needs a quiet hour", "shaken")
	eq(needs[5].text, "Out of ammo", "no ammunition")
	# the milder words, when not so bad
	dez.bleeding = 0.0
	dez.infected_at = -1.0
	dez.hunger_h = sim.supplies.HUNGRY_H + 1.0
	dez.thirst_h = sim.supplies.THIRSTY_H + 1.0
	sim.morale.set_value(dez, 70.0)
	dez.mag = 5
	var mild: Array = sim.interact.needs_of(dez)
	var mids: Array = []
	for n in mild:
		mids.append(n.id)
	eq(mids, ["hungry", "thirsty"], "hungry and thirsty when it is not yet starving")
	eq(mild[0].text, "Hungry", "plainly")
	g.world.free()


func test_a_need_is_the_line_they_say_and_no_job_in_a_settlement_game_points_to_the_jobs_page() -> void:
	var g := _game("ruth", 3)
	var sim = g.sim
	check(sim.recruits.small, "a settlement game")
	var dez = _p(sim, "dez")
	eq(sim.jobs.job_of(dez), "", "Dez has no job")
	var needs: Array = sim.interact.needs_of(dez)
	eq(needs.size(), 1, "one need")
	eq(needs[0].id, "no_job", "no job")
	eq(needs[0].text, "No job: nothing to do. Give them one", "in the words of the contract")
	eq(needs[0].page, "jobs", "with the Jobs page")
	_put(dez, AT + Vector2(1.0, 0.0))
	eq(sim.interact.talk_to(dez).line, String(needs[0].line), "and the line they say is the first need's")
	check(String(needs[0].line) != "", "it is not empty")
	# the player has no seat and never needs one; at night the posts are the job
	eq(sim.interact.needs_of(g.p), [], "the avatar needs no job")
	_night(sim)
	eq(sim.interact.needs_of(dez), [], "at night nobody lacks a job")
	g.world.free()


# ----------------------------------------------------------------------- posts --

func test_taking_a_post_swaps_it_with_the_holder_and_puts_the_avatar_on_it() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	eq(sim.jobs.post_ids["dez"], "bus", "Dez holds the bus post")
	eq(sim.jobs.post_ids["ruth"], "gate", "and Ruth the gate")
	_put(g.p, BUS_SPOT + Vector2(0.5, 0.0))
	dez.goal_key = "x"
	var r: Dictionary = sim.interact.take_post("bus")
	check(r.ok, "the post is taken: %s" % r.get("why", ""))
	eq(r.line, "On the school bus post. Steadier here.", "the line says so")
	eq(r.held_by_swap, "dez", "Dez is the one who swapped")
	eq(sim.jobs.post_ids["ruth"], "bus", "Ruth holds the bus post now")
	eq(sim.jobs.post_ids["dez"], "gate", "and Dez the gate")
	eq(dez.goal_key, "", "his path is worked out again")
	eq(sim.interact.posted, "bus", "the avatar is posted")
	check(Vector2(g.p.x, g.p.y).distance_to(Vector2(47.5, 18.8)) < 0.25, "on the post: %s" % str(Vector2(g.p.x, g.p.y)))
	check(not sim.avatar._blocked(g.p.x, g.p.y), "on ground it can stand on")
	eq(g.p.facing, "N", "facing the way the post faces")
	var ev: Array = _events(sim, "post_taken")
	eq(ev.size(), 1, "one event")
	eq(ev[0].post, "bus", "naming the post")
	# every person still has a post of their own
	var seen := {}
	for p in sim.people:
		var id: String = sim.jobs.post_ids[String(p.id)]
		check(not seen.has(id), "post %s is held by one person only" % id)
		seen[id] = true
	g.world.free()


func test_a_post_nobody_holds_is_just_taken() -> void:
	var g := _game()
	var sim = g.sim
	var free_post := ""
	var held := {}
	for k in sim.jobs.post_ids:
		held[String(sim.jobs.post_ids[k])] = true
	for po in sim.jobs.posts():
		if not held.has(String(po.id)):
			free_post = String(po.id)
			break
	check(free_post != "", "there is a post nobody holds")
	var old_post: String = sim.jobs.post_ids["ruth"]
	_put(g.p, Vector2(sim.jobs.post(free_post).pos))
	var r: Dictionary = sim.interact.take_post(free_post)
	check(r.ok, "it is taken")
	eq(r.held_by_swap, "", "nobody swapped")
	eq(sim.jobs.post_ids["ruth"], free_post, "it is hers")
	check(old_post != free_post, "and the old one is let go")
	g.world.free()


func test_a_post_far_away_is_refused() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.p, GATE_SPOT + Vector2(2.0, 0.0))
	var r: Dictionary = sim.interact.take_post("gate")
	eq(r.ok, false, "refused")
	eq(r.why, "Too far from the post", "the reason")
	eq(sim.jobs.post_ids["ruth"], "gate", "nothing changed")
	eq(sim.interact.posted, "", "not posted")
	eq(sim.interact.take_post("nowhere").ok, false, "no such post")
	g.world.free()


func test_a_post_is_refused_while_the_posts_are_manned_and_the_holder_is_at_it() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_night(sim)
	check(sim.posts_manned(), "the posts are manned")
	_put(g.p, BUS_SPOT)
	_put(dez, Vector2(47.5, 18.8) + Vector2(1.2, 0.0))    # within 1.5 tiles of the post
	var r: Dictionary = sim.interact.take_post("bus")
	eq(r.ok, false, "refused")
	eq(r.why, "Dez is at the post", "naming him")
	eq(sim.jobs.post_ids["dez"], "bus", "he keeps it")
	eq(sim.jobs.post_ids["ruth"], "gate", "and she hers")
	eq(sim.interact.posted, "", "not posted")
	eq(_events(sim, "post_taken").size(), 0, "no event")
	# a holder farther than 1.5 tiles is not at it
	_put(dez, Vector2(47.5, 18.8) + Vector2(1.6, 0.0))
	check(sim.interact.take_post("bus").ok, "1.6 tiles away he is not at the post: it is taken")
	eq(sim.jobs.post_ids["dez"], "gate", "and he has hers")
	g.world.free()


func test_by_day_the_swap_works_even_with_the_holder_at_the_post() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	check(not sim.posts_manned(), "nothing is manned by day")
	_put(g.p, BUS_SPOT)
	_put(dez, Vector2(47.5, 18.8))
	check(sim.interact.take_post("bus").ok, "taken")
	eq(sim.jobs.post_ids["dez"], "gate", "he has the gate")
	g.world.free()


func test_a_post_the_avatar_already_holds_needs_no_swap() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.p, GATE_SPOT)
	var r: Dictionary = sim.interact.take_post("gate")
	check(r.ok, "taken")
	eq(r.held_by_swap, "", "no swap")
	eq(sim.jobs.post_ids["ruth"], "gate", "hers still")
	eq(sim.interact.posted, "gate", "and posted")
	g.world.free()


func test_a_holder_who_is_away_or_down_is_swapped_too() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_night(sim)
	_put(g.p, BUS_SPOT)
	dez.away = {"state": "away"}
	check(sim.interact.take_post("bus").ok, "the post of somebody away is taken, and swapped")
	eq(sim.jobs.post_ids["dez"], "gate", "he has the avatar's old one when he is back")
	sim.interact.leave_post()
	dez.away = null
	sim.jobs.post_ids["dez"] = "bus"
	sim.jobs.post_ids["ruth"] = "gate"
	_put(dez, Vector2(47.5, 18.8))
	dez.downed = true
	var r: Dictionary = sim.interact.take_post("bus")
	check(r.ok, "a holder who lies at the post is not manning it: %s" % r.get("why", ""))
	g.world.free()


func test_a_dead_holder_does_not_hold_a_post_against_the_avatar() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_night(sim)
	_put(dez, Vector2(47.5, 18.8))
	dez.dead = true
	_put(g.p, BUS_SPOT)
	var r: Dictionary = sim.interact.take_post("bus")
	check(r.ok, "taken from the dead")
	eq(sim.jobs.post_ids["ruth"], "bus", "hers")
	g.world.free()


func test_posted_means_steadier_aim_only_while_still() -> void:
	var g := _game()
	var sim = g.sim
	var gun: Dictionary = g.p.gun
	_put(g.p, BUS_SPOT)
	var loose: float = sim.avatar.spread_of(g.p, gun)
	eq(sim.interact.brace_factor(g.p), 1.0, "no brace on open ground")
	check(sim.interact.take_post("bus").ok, "posted")
	near(sim.interact.brace_factor(g.p), 0.7, 0.0001, "the brace is 0.7")
	near(sim.avatar.spread_of(g.p, gun), loose * 0.7, loose * 0.001, "the spread is 0.7 of what it was")
	g.p.moving = true
	eq(sim.interact.brace_factor(g.p), 1.0, "moving, no brace")
	var moving_posted: float = sim.avatar.spread_of(g.p, gun)
	sim.interact.leave_post()
	near(sim.avatar.spread_of(g.p, gun), moving_posted, 0.000001, "and moving it is the same as off the post")
	g.p.moving = false
	eq(sim.interact.brace_factor(g.p), 1.0, "leaving the post ends the brace")
	near(sim.avatar.spread_of(g.p, gun), loose, 0.000001, "the spread is back")
	check(sim.interact.brace_factor(_p(sim, "dez")) == 1.0, "nobody else is braced")
	g.world.free()


func test_leaving_the_post_says_so_and_walking_away_ends_it() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.p, BUS_SPOT)
	sim.interact.take_post("bus")
	sim.events.clear()
	sim.interact.leave_post("test")
	eq(sim.interact.posted, "", "off the post")
	var ev: Array = _events(sim, "post_left")
	eq(ev.size(), 1, "one event")
	eq(ev[0].post, "bus", "naming it")
	sim.interact.leave_post()
	eq(_events(sim, "post_left").size(), 1, "leaving a post one is not on says nothing")
	# walking away ends it by itself
	_put(g.p, BUS_SPOT)
	sim.interact.take_post("bus")
	sim.events.clear()
	sim.avatar.set_input(Vector2(1.0, 0.0), Vector2(60.0, 18.7), false)
	Helpers.run(sim, 0.1)
	eq(sim.interact.posted, "bus", "a step or two away it is still held")
	Helpers.run(sim, 0.5)
	sim.avatar.set_input(Vector2.ZERO, Vector2(60.0, 18.7), false)
	eq(sim.interact.posted, "", "walking more than 0.8 of a tile away ends it")
	eq(_events(sim, "post_left").size(), 1, "and says so")
	g.world.free()


func test_being_downed_ends_the_post_but_a_call_to_arms_does_not() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.p, BUS_SPOT)
	sim.interact.take_post("bus")
	sim.radio.alarm(true)
	Helpers.run(sim, 0.5)
	eq(sim.interact.posted, "bus", "the alarm does not end it")
	g.p.downed = true
	Helpers.run(sim, 0.1)
	eq(sim.interact.posted, "", "a fall does")
	eq(_events(sim, "post_left").size(), 1, "and says so")
	g.world.free()


func test_a_new_player_does_not_inherit_the_post() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.p, BUS_SPOT)
	sim.interact.take_post("bus")
	var dez = _p(sim, "dez")
	_put(dez, BUS_SPOT + Vector2(0.3, 0.0))
	check(sim.avatar.set_player("dez"), "Dez is the player now")
	Helpers.run(sim, 0.1)
	eq(sim.interact.posted, "", "the post was Ruth's")
	g.world.free()


# ----------------------------------------------------------------------- bench --

func test_the_bench_session_makes_the_ammo_at_one_and_a_half_times_the_persons_rate() -> void:
	var g := _game()
	var sim = g.sim
	_at_bench(g)
	var ammo0: float = sim.stock.ammo
	var scrap0: float = sim.stock.scrap
	var crafted0: float = float(g.p.stats.get("crafted", 0.0))
	var skill0: int = int(g.p.skills.Building)
	var r: Dictionary = sim.interact.work_bench()
	check(r.ok, "the session starts: %s" % r.get("why", ""))
	eq(sim.interact.working, "bench", "working the bench")
	near(sim.interact.work_left, 12.0, 0.0001, "for twelve seconds")
	var on: Array = _events(sim, "bench_work")
	eq(on.size(), 1, "an event")
	eq(on[0].on, true, "it is on")
	Helpers.run(sim, 1.0)
	eq(g.p.work, "bench", "the drawing's work word is the bench's")
	eq(g.p.activity, "Working the bench", "and the card says it")
	check(g.p.work_t > 0.5 and g.p.work_t < 1.5, "the pose's clock runs: %.2f" % g.p.work_t)
	Helpers.run(sim, 11.0)
	eq(sim.interact.working, "", "twelve seconds later it is over")
	var used: float = scrap0 - float(sim.stock.scrap)
	var made: float = float(sim.stock.ammo) - ammo0
	var rate: float = sim.workshop.scrap_per_hour(g.p)
	near(used, rate * 1.5 * 0.6 * sim.perf(g.p), 0.02, "it used 1.5 x %.2f scrap an hour for 0.6 of an hour: %.3f" % [rate, used])
	near(made, used * sim.workshop.ammo_per_scrap(), 0.001, "and made exactly 8 ammo from each: %.3f" % made)
	check(made > 20.0, "a real handful: %.1f" % made)
	near(float(g.p.stats.crafted) - crafted0, used, 0.001, "the scrap is credited as crafted")
	check(g.p.skills.Building >= skill0, "and it counts toward Building")
	var off: Array = _events(sim, "bench_work")
	eq(off.size(), 2, "two events in all")
	eq(off[1].on, false, "the second is off")
	eq(off[1].why, "done", "because the twelve seconds were up")
	near(float(off[1].scrap), used, 0.001, "it tells the scrap used")
	near(float(off[1].ammo), made, 0.001, "and the ammo made")
	check(_events(sim, "hammer").size() >= 8, "the hammer rings: %d" % _events(sim, "hammer").size())
	check(_events(sim, "craft").size() >= 4, "and the craft numbers float up: %d" % _events(sim, "craft").size())
	g.world.free()


func test_the_card_shows_the_avatar_making_ammo_only_while_it_works() -> void:
	var g := _game()
	var sim = g.sim
	_at_bench(g)
	eq(sim.workshop.status_of(g.p), [], "idle, no mark")
	check(not sim.workshop.crafting(g.p), "not at work")
	sim.interact.work_bench()
	check(sim.workshop.crafting(g.p), "at work")
	eq(sim.workshop.status_of(g.p).size(), 1, "the mark of the worktable")
	sim.interact.stop_work("test")
	check(not sim.workshop.crafting(g.p), "and not any more")
	g.world.free()


func test_a_worker_at_the_bench_is_not_changed_by_the_avatar() -> void:
	# the same hour of Dez's work, with and without an avatar elsewhere: the avatar adds only its own sessions
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	Helpers.seat(sim, dez, "bench")
	var ammo0: float = sim.stock.ammo
	Helpers.run(sim, 20.0)
	var rate: float = sim.workshop.scrap_per_hour(dez) * sim.perf(dez)
	near(float(sim.stock.ammo) - ammo0, rate * sim.workshop.ammo_per_scrap(), 3.0, "Dez at the bench makes ammo as ever")
	g.world.free()


func test_the_avatar_and_a_worker_make_ammo_together() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	Helpers.seat(sim, dez, "bench")
	_put(dez, sim.jobs.seat_pos(dez))
	_at_bench(g)
	var ammo0: float = sim.stock.ammo
	check(sim.interact.work_bench().ok, "the avatar joins at the bench")
	Helpers.run(sim, 12.0)
	var both: float = float(sim.stock.ammo) - ammo0
	var dez_part: float = sim.workshop.scrap_per_hour(dez) * sim.perf(dez) * 0.6 * sim.workshop.ammo_per_scrap()
	var ruth_part: float = sim.workshop.scrap_per_hour(g.p) * 1.5 * sim.perf(g.p) * 0.6 * sim.workshop.ammo_per_scrap()
	near(both, dez_part + ruth_part, 1.5, "each makes their own: %.1f of %.1f" % [both, dez_part + ruth_part])
	g.world.free()


func test_the_bench_session_stops_when_the_avatar_moves_or_fires() -> void:
	var g := _game()
	var sim = g.sim
	_at_bench(g)
	check(sim.interact.work_bench().ok, "start")
	Helpers.run(sim, 1.0)
	sim.avatar.set_input(Vector2(1.0, 0.0), Vector2(60.0, 30.0), false)
	Helpers.run(sim, 0.1)
	eq(sim.interact.working, "", "walking stops it")
	var off: Array = _events(sim, "bench_work")
	eq(off[off.size() - 1].on, false, "with an event")
	sim.avatar.set_input(Vector2.ZERO, Vector2(60.0, 30.0), false)
	_at_bench(g)
	check(sim.interact.work_bench().ok, "again")
	Helpers.run(sim, 0.5)
	sim.avatar.set_input(Vector2.ZERO, Vector2(60.0, 30.0), true)
	Helpers.run(sim, 0.1)
	eq(sim.interact.working, "", "the trigger stops it")
	sim.avatar.set_input(Vector2.ZERO, Vector2(60.0, 30.0), false)
	# a hand on the keys at the moment of E: refused rather than started and stopped
	sim.avatar.set_input(Vector2(1.0, 0.0), Vector2(60.0, 30.0), false)
	var r: Dictionary = sim.interact.work_bench()
	eq(r.ok, false, "while walking it is not started")
	eq(r.why, "Stand still to work the bench", "and says why")
	g.world.free()


func test_the_bench_session_stops_when_the_avatar_is_hurt_or_down() -> void:
	var g := _game()
	var sim = g.sim
	_at_bench(g)
	check(sim.interact.work_bench().ok, "start")
	Helpers.run(sim, 0.5)
	g.p.hp -= 6.0
	Helpers.run(sim, 0.1)
	eq(sim.interact.working, "", "a wound stops it")
	_at_bench(g)
	g.p.hp = 100.0
	check(sim.interact.work_bench().ok, "again")
	Helpers.run(sim, 0.5)
	g.p.downed = true
	Helpers.run(sim, 0.1)
	eq(sim.interact.working, "", "a fall stops it")
	g.world.free()


func test_the_bench_session_stops_with_the_scrap_or_the_ammo_limit() -> void:
	var g := _game()
	var sim = g.sim
	_at_bench(g)
	sim.stock.ammo = 299.5
	check(sim.interact.work_bench().ok, "start: a little room")
	Helpers.run(sim, 3.0)
	eq(sim.interact.working, "", "the ammo reached its target and the session ended")
	near(float(sim.stock.ammo), 300.0, 0.01, "at the target")
	sim.stock.ammo = 100.0
	sim.stock.scrap = 4.2    # reserve 3 + 1.2
	_at_bench(g)
	check(sim.interact.work_bench().ok, "start with a little scrap")
	Helpers.run(sim, 12.0)
	eq(sim.interact.working, "", "ended")
	check(float(sim.stock.scrap) >= 3.0 - 0.001, "the reserve is kept: %.3f" % float(sim.stock.scrap))
	g.world.free()


func test_the_bench_session_is_refused_with_the_workshops_reason() -> void:
	var g := _game()
	var sim = g.sim
	_at_bench(g)
	sim.stock.ammo = 300.0
	var r: Dictionary = sim.interact.work_bench()
	eq(r.ok, false, "refused at the target")
	eq(r.why, "the ammo is at its target (300)", "with the number")
	eq(r.why, sim.workshop.why_not_hand_craft(g.p), "the workshop's own words")
	sim.stock.ammo = 100.0
	sim.stock.scrap = 3.5
	eq(sim.interact.work_bench().why, "there is no scrap to spare", "no scrap")
	sim.stock.scrap = 40.0
	_night(sim)
	eq(sim.interact.work_bench().why, "it is night: everyone is at their post", "not at night")
	eq(sim.interact.working, "", "nothing started")
	eq(_events(sim, "bench_work").size(), 0, "and no event")
	_at(sim, 1, 9.0)
	_put(g.p, sim.workshop.bench() + Vector2(3.0, 0.0))
	var far: Dictionary = sim.interact.work_bench()
	eq(far.ok, false, "too far")
	eq(far.why, "Too far from the bench", "says so")
	g.world.free()


func test_hand_work_does_not_need_a_seat_but_the_old_craft_reasons_stay() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	var hector = _p(sim, "hector")
	var walt = _p(sim, "walt")
	var ana = _p(sim, "ana")
	# the bench's two seats are taken, so a third cannot be given the job
	check(sim.jobs.assign(dez, "bench"), "Dez has a seat")
	check(sim.jobs.assign(marcus, "bench"), "and Marcus")
	eq(sim.workshop.why_not_craft(hector), "no free seat at the Workbench", "a third has no seat")
	eq(sim.workshop.why_not_hand_craft(hector), "", "but their own hands can work the bench")
	walt.dead = true
	eq(sim.workshop.why_not_hand_craft(walt), "they are gone", "not the dead")
	ana.downed = true
	eq(sim.workshop.why_not_hand_craft(ana), "they are down", "not the down")
	ana.downed = false
	ana.away = {"state": "away"}
	eq(sim.workshop.why_not_hand_craft(ana), "they are away", "not the away")
	g.world.free()


# -------------------------------------------------------------------- vehicles --

func test_checking_a_car_reads_the_fuel_and_changes_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	sim.vehicles.fuel = 14.0
	v["hp"] = 74.0
	var r: Dictionary = sim.interact.check_vehicle(String(v.id))
	check(r.ok, "it can be read")
	eq(r.line, "Pickup: fuel 14 in the tank, about 4 hours of driving; 82% sound", "the line")
	near(sim.vehicles.fuel, 14.0, 0.0001, "no fuel was spent")
	near(float(v.hp), 74.0, 0.0001, "and the car is as it was")
	sim.vehicles.fuel = 0.0
	check(String(sim.interact.check_vehicle(String(v.id)).line).contains("tank is empty"), "an empty tank is said plainly: %s" % sim.interact.check_vehicle(String(v.id)).line)
	sim.vehicles.fuel = 3.5
	eq(sim.interact.check_vehicle(String(v.id)).line, "Pickup: fuel 3.5 in the tank, about 1 hour of driving; 82% sound", "one hour")
	eq(sim.interact.check_vehicle("nope").ok, false, "no such car")
	v["state"] = "out"
	var out: Dictionary = sim.interact.check_vehicle(String(v.id))
	eq(out.ok, false, "a car that is out cannot be read")
	eq(out.why, "The pickup is out", "and says so")
	g.world.free()


# ------------------------------------------------------------------------- use --

func test_use_does_what_the_best_candidate_says() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_put(dez, AT + Vector2(1.0, 0.0))
	var r: Dictionary = sim.interact.use()
	check(r.ok, "used")
	eq(r.kind, "person", "a person")
	eq(r.id, "dez", "Dez")
	eq(r.who, "dez", "he talked")
	var ev: Array = _events(sim, "interact")
	eq(ev.size(), 1, "an interact event")
	eq(ev[0].kind, "person", "of that kind")
	eq(ev[0].id, "dez", "and that id")
	eq(ev[0].ok, true, "that worked")
	g.world.free()


func test_use_at_a_post_takes_it_and_again_leaves_it() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.p, BUS_SPOT)
	var r: Dictionary = sim.interact.use()
	check(r.ok, "taken: %s" % r.get("why", ""))
	eq(r.kind, "post", "a post")
	eq(sim.interact.posted, "bus", "posted")
	var back: Dictionary = sim.interact.use()
	check(back.ok, "again is fine")
	eq(back.kind, "post", "still a post")
	eq(back.left, true, "it says it was left")
	eq(sim.interact.posted, "", "off the post")
	eq(_events(sim, "post_left").size(), 1, "an event")
	g.world.free()


func test_use_at_a_refused_post_says_why_and_still_tells_the_views() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_night(sim)
	_put(g.p, BUS_SPOT)
	_put(dez, Vector2(47.5, 18.8) + Vector2(1.2, 0.0))
	var r: Dictionary = sim.interact.use()
	eq(r.ok, false, "refused")
	eq(r.kind, "post", "a post")
	eq(r.why, "Dez is at the post", "with the reason")
	var ev: Array = _events(sim, "interact")
	eq(ev.size(), 1, "an event")
	eq(ev[0].ok, false, "marked as failed")
	g.world.free()


func test_use_at_the_bench_starts_it_and_again_stops_it() -> void:
	var g := _game()
	var sim = g.sim
	_at_bench(g)
	var r: Dictionary = sim.interact.use()
	check(r.ok, "started: %s" % r.get("why", ""))
	eq(r.kind, "bench", "the bench")
	eq(sim.interact.working, "bench", "working")
	eq(sim.interact.candidates()[0].label, "Stop working the bench", "the label offers to stop")
	Helpers.run(sim, 1.0)
	var stop: Dictionary = sim.interact.use()
	check(stop.ok, "stopped")
	eq(stop.stopped, true, "it says so")
	eq(sim.interact.working, "", "not working")
	check(_events(sim, "bench_work").size() == 2, "on and off")
	g.world.free()


func test_use_at_a_car_gives_the_fuel_line() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 9.0
	_put(g.p, Convoy.bay(int(v.spot)) + Vector2(1.5, 0.0))
	var list: Array = sim.interact.candidates()
	eq(list[0].label, "Check the sedan's fuel", "the label")
	var r: Dictionary = sim.interact.use()
	check(r.ok, "read")
	eq(r.kind, "vehicle", "a car")
	eq(r.line, sim.interact.check_vehicle(String(v.id)).line, "the line is the check's")
	g.world.free()


func test_use_with_nothing_in_reach_and_with_a_stale_candidate() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_put(dez, AT + Vector2(1.0, 0.0))
	var cand: Dictionary = sim.interact.best()
	_put(dez, AT + Vector2(6.0, 0.0))
	var r: Dictionary = sim.interact.use(cand)
	eq(r.ok, false, "a candidate that has gone out of reach is not used")
	eq(r.why, "Nothing here to use", "the plain reason")
	eq(_events(sim, "interact").size(), 0, "and nothing is told")
	g.world.free()


# ------------------------------------------------------------------------ save --

func test_posted_and_the_days_words_survive_a_save() -> void:
	var a := _game()
	var sim = a.sim
	_put(a.p, BUS_SPOT)
	sim.interact.take_post("bus")
	sim.interact.talk_to(_p(sim, "dez"))
	var d := SaveGame.to_dict(sim)
	check(d.modules.has("interact"), "the module is part of the save")
	var b := Helpers.make(7, 1, 6)
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads")
	eq(b.sim.interact.posted, "bus", "still on the post")
	near(b.sim.interact.brace_factor(_p(b.sim, "ruth")), 0.7, 0.0001, "and braced")
	eq(b.sim.interact.talked.get("dez", -1), 1, "the word with Dez was today's")
	eq(b.sim.interact.talk_to(_p(b.sim, "dez")).gain, 0.0, "so a second one earns nothing")
	a.world.free()
	b.world.free()


func test_a_session_in_progress_is_not_resumed() -> void:
	var a := _game()
	var sim = a.sim
	_at_bench(a)
	check(sim.interact.work_bench().ok, "start")
	Helpers.run(sim, 2.0)
	var d := SaveGame.to_dict(sim)
	eq(d.modules.interact.working, "bench", "the file says what was going on")
	var b := Helpers.make(7, 1, 6)
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads")
	eq(b.sim.interact.working, "", "but it is not resumed")
	near(b.sim.interact.work_left, 0.0, 0.0001, "no time is left")
	a.world.free()
	b.world.free()


func test_a_save_from_before_the_module_and_a_damaged_one_load_clean() -> void:
	var a := _game()
	var sim = a.sim
	var d := SaveGame.to_dict(sim)
	d.modules.erase("interact")
	var b := Helpers.make(7, 1, 6)
	check(SaveGame.apply(b.sim, d), "a save from round 17 loads")
	eq(b.sim.interact.posted, "", "no post")
	eq(b.sim.interact.working, "", "no work")
	eq(b.sim.interact.talked, {}, "no words")
	var i = b.sim.interact
	i.load_state({"posted": 5, "working": [], "work_left": "x", "talked": "words"})
	eq(i.posted, "", "a post that is not text")
	eq(i.working, "", "work that is not text")
	eq(i.talked, {}, "words that are not a table")
	i.load_state({"posted": "no_such_post", "working": "bench", "work_left": 5.0, "talked": {"dez": "x", "ana": 3.0, "ruth": -1.0, "walt": 2}})
	eq(i.posted, "", "a post that does not exist")
	eq(i.working, "", "and work is never resumed")
	eq(i.talked, {"ana": 3, "walt": 2}, "only the sound words are kept")
	i.load_state({"posted": "gate"})
	eq(i.posted, "", "a post the avatar is not standing at is let go")
	var c := Helpers.make(7, 1, 6)
	c.sim.interact.load_state({"posted": "gate"})
	eq(c.sim.interact.posted, "", "and so is one with no avatar")
	a.world.free()
	b.world.free()
	c.world.free()
