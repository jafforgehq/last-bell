extends "res://tests/case.gd"
## The calls of the night and the forecast as a tool (round 19, slice 3, S3.3 and S3.4: scripts/sim/night_calls.gd, `radio.night`, the
## new kinds of calls in scripts/sim/radio.gd). A wall that is going (`going`), a brute on its way (`brute`), a section that has fallen
## (`breach`), the night that the lookout has read (`night`), the day-ahead notice of a Big Night (`forecast`): what raises each, the
## options and the default and the time of each, what an option does (two defenders sent, "I'm on my way" and the trust it earns or
## costs, closing a breach, the lure, the call to arms) and that none of it exists without an avatar. The road home is in
## tests/test_night_road.gd. Numbers are read through NightData, never copied. The waves' `big_night` and `outlook` are a fake here
## (a Big Night is made by hand), so these tests do not depend on the plan's tuning.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const NightCalls := preload("res://scripts/sim/night_calls.gd")

## Where the leader stands (open ground in the yard).
const LEADER_AT := Vector2(34.5, 32.5)
const BUS := 3    # the school bus on the north wall: centre (47.5, 18.9), Dez's post is there
const CONTAINER := 0    # the red container on the north wall


## The waves with a Big Night made by hand: `bigs` and `outlooks` map a day to what `big_night` and `outlook` answer.
class FakeWaves:
	extends "res://scripts/sim/waves.gd"
	var bigs := {}
	var outlooks := {}

	func big_night(day: int) -> Dictionary:
		return (bigs.get(day, {}) as Dictionary).duplicate(true)

	func outlook(day: int) -> Dictionary:
		return (outlooks.get(day, {}) as Dictionary).duplicate(true)


## What `Waves.outlook` says of a Siege on `day` (the plan's S3.1 shape).
static func siege(day: int) -> Dictionary:
	return {
		"day": day, "kind": "milestone", "id": "siege", "name": "The Siege", "size": 80, "low": 70, "high": 95, "side": "east", "sections": [12, 13],
		"section_text": "the east side: the second bus, the chain-link", "runners": false, "brutes": 2, "plated": 2, "first_at": 21.0, "brute_at": 23.0,
		"last_at": 28.5, "needs_you": true, "blurb": "Plated brutes at one wall. Be there.",
	}


## What `Waves.big_night` says of a Siege (every key the plan reads: the real `plan_for` runs on it too).
static func big_siege() -> Dictionary:
	var t := NightData.theme("siege")
	t["kind"] = "milestone"
	t["id"] = "siege"
	t["index"] = 0
	t["min_brutes"] = 0
	t["plated"] = true
	return t


static func ordinary(day: int) -> Dictionary:
	return {
		"day": day, "kind": "ordinary", "id": "", "name": "", "size": 35, "low": 30, "high": 40, "side": "north", "sections": [3], "section_text": "the north side: the school bus",
		"runners": false, "brutes": 0, "plated": 0, "first_at": 20.0, "brute_at": -1.0, "last_at": 27.0, "needs_you": false, "blurb": "",
	}


# ----------------------------------------------------------------- helpers --

## A quiet game with an avatar (Ruth, the player, in the yard) at `hour` of `day`: five people (Dez at the bus, Walt at the radio desk,
## Marcus on the lookout, Ana at the infirmary), no nights and no dead about, and the guns dry (nobody shoots what the test puts at the
## wall), so that a few steps change nothing but what is being looked at.
func _game(day: int = 3, hour: float = 22.0) -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.stock.ammo = 0.0
	var lead = _p(sim, "ruth")
	lead.x = LEADER_AT.x
	lead.y = LEADER_AT.y
	lead.path = []
	lead.goal_key = ""
	Helpers.at(sim, day, hour)
	sim.events.clear()
	return g


## The waves of the game replaced by the hand-made ones.
func _fake(sim) -> FakeWaves:
	var w := FakeWaves.new()
	w.setup(sim)
	w.start()
	w.enabled = false
	sim.waves = w
	return w


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _seg(sim, id: int):
	for s in sim.segments:
		if int(s.id) == id:
			return s
	return null


func _put(p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.path = []
	p.goal_key = ""
	p.moving = false


func _calls(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


## The calls of this kind that still wait for an answer.
func _open(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.open_calls():
		if e.kind == kind:
			out.append(e)
	return out


func _ids(c: Dictionary) -> Array:
	var out: Array = []
	for o in c.options:
		out.append(String(o.id))
	return out


## A wall section (by id) with a share of its health left, and its state worked out as the rules do.
func _hurt(sim, id: int, share: float) -> void:
	var s = _seg(sim, id)
	s.hp = s.max_hp * share
	sim._segment_state(s)


## A section goes down (the rules' own breach: its state, the banner, the alert).
func _fall(sim, id: int) -> void:
	_hurt(sim, id, 0.0)


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


## The compound sections a lure may be set on, best first: the most guns that cover it, then the most health, then the lowest id.
func _lure_ranking(sim, avoid = null) -> Array:
	var out: Array = []
	for s in sim.segments:
		if s.kind == sim.DOOR_KIND or int(s.id) >= 100 or s == avoid or sim.tactics.why_not_lure(s) != "":
			continue
		out.append(s)
	out.sort_custom(func(a, b):
		var ca: int = sim.tactics.coverage_of(a)
		var cb: int = sim.tactics.coverage_of(b)
		if ca != cb:
			return ca > cb
		var ha: float = a.hp / a.max_hp
		var hb: float = b.hp / b.max_hp
		if not is_equal_approx(ha, hb):
			return ha > hb
		return int(a.id) < int(b.id))
	return out


# ------------------------------------------------------------------- going --

func test_a_wall_under_four_tenths_with_two_of_the_dead_at_it_raises_going() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, NightData.num("calls.going_below") - 0.05)
	Helpers.run(sim, 0.1)
	var calls := _calls(sim, "going")
	eq(calls.size(), 1, "the wall that is going has a call")
	var c: Dictionary = calls[0]
	check(String(c.text).to_lower().contains("school bus"), "about the bus: %s" % str(c.text))
	check(String(c.text).contains("going"), "it says so: %s" % str(c.text))
	eq(_ids(c), ["hold", "reinforce", "coming", "fall_back"], "hold, send two, I'm on my way, give it up")
	eq(c.default, "hold", "the default is to hold")
	near(float(c.due) - float(c.t), NightData.num("calls.going_ttl_min"), 0.001, "it waits as long as the data says")
	for o in c.options:
		check(String(o.label) != "", "each option has a label")
	check(String(_option(c, "reinforce").label).to_lower().contains("two"), "it says how many are sent: %s" % str(_option(c, "reinforce")))
	eq(c.data.seg, BUS, "it keeps the section")
	g.world.free()


func _option(c: Dictionary, id: String) -> Dictionary:
	for o in c.options:
		if String(o.id) == id:
			return o
	return {}


func test_a_wall_above_that_or_with_one_of_the_dead_at_it_does_not() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, NightData.num("calls.going_below") + 0.1)
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "going").size(), 0, "a wall at four tenths and more is not going")
	_hurt(sim, BUS, NightData.num("calls.going_below") - 0.05)
	for z in sim.zombies:
		if z.slot != null and z != sim.zombies[0]:
			z.slot.who = null
			z.state = "wander"
			z.slot = null
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "going").size(), 0, "one of the dead at it is not enough")
	g.world.free()


func test_a_plated_brute_at_the_wall_raises_going_whatever_its_health() -> void:
	var g := _game()
	var sim = g.sim
	var z = Helpers.plated_brute(sim, BUS)
	check(z != null and z.plated, "a plated brute is at the bus")
	Helpers.run(sim, 0.1)
	var calls := _calls(sim, "going")
	eq(calls.size(), 1, "a plated brute at the wall is a call at once")
	check(String(calls[0].text).to_lower().contains("plated"), "and says so: %s" % str(calls[0].text))
	g.world.free()


func test_a_plain_brute_at_a_sound_wall_is_not_a_going_call() -> void:
	var g := _game()
	var sim = g.sim
	var z = Helpers.plated_brute(sim, BUS)
	z.plated = false
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "going").size(), 0, "a brute that is not plated is the old attack call's business")
	g.world.free()


# ---------------------------------------------------- going: a wall nobody covers --

## The first non-door section of the compound none of whose places any defender's post reaches (the avatar's own gun left out), or null.
func _uncovered(sim):
	for s in sim.segments:
		if s.kind == sim.DOOR_KIND or int(s.id) >= 100:
			continue
		var reached := false
		for p in sim.people:
			if p.player or p.dead:
				continue
			var at: Vector2 = sim.tactics.post_pos(p)
			var reach: float = sim.reach_at(p.gun, at, true)
			for sl in s.slots:
				if at.distance_to(Vector2(sl.x, sl.y)) <= reach:
					reached = true
		if not reached:
			return s
	return null


## The rules seconds that make `minutes` of the game's time.
func _secs(sim, minutes: float) -> float:
	return minutes / float(sim.min_per_sec)


## A quiet game with one of the dead clawing at a wall nobody covers (and the avatar far away from it): the section, its state worked out.
func _alone(hp_share: float = 0.9) -> Dictionary:
	var g := _game()
	var sim = g.sim
	var s = _uncovered(sim)
	check(s != null, "(a section that no post covers)")
	_put(_p(sim, "ruth"), LEADER_AT)
	_hurt(sim, int(s.id), hp_share)
	Helpers.attack(sim, int(s.id), 1)
	return {"g": g, "sim": sim, "seg": s}


func test_one_of_the_dead_clawing_a_wall_nobody_covers_raises_going_after_half_an_hour() -> void:
	var a := _alone()
	var sim = a.sim
	var s = a.seg
	var wait: float = NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)
	check(wait >= 20.0 and wait <= 60.0, "the wait is about half an hour: %s" % str(wait))
	Helpers.run(sim, _secs(sim, wait) * 0.7)
	eq(_calls(sim, "going").size(), 0, "not before the half hour: the guns of a covered wall are given that long, and this one has none")
	Helpers.run(sim, _secs(sim, wait) * 0.6)
	var calls := _calls(sim, "going")
	eq(calls.size(), 1, "then the wall that is being worn down has a call")
	var c: Dictionary = calls[0]
	check(String(c.text).to_lower().contains("nobody"), "it says nobody is there: %s" % str(c.text))
	check(String(c.text).to_lower().contains(String(s.name).to_lower()), "and which wall: %s" % str(c.text))
	check(String(c.sub).contains("1 of the dead") and String(c.sub).contains("%"), "and what is at it and how much is left: %s" % str(c.sub))
	eq(_ids(c), ["hold", "reinforce", "coming", "fall_back"], "the same options as a wall that is going")
	eq(c.default, "hold", "it only asks: the default is still to hold")
	eq(c.data.seg, int(s.id), "it keeps the section")
	near(float(c.due) - float(c.t), NightData.num("calls.going_ttl_min"), 0.001, "it waits as long as the data says")
	Helpers.run(sim, _secs(sim, wait))
	eq(_calls(sim, "going").size(), 1, "once, however long it goes on")
	a.g.world.free()


func test_a_wall_nobody_covers_that_would_hold_until_the_dead_go_home_is_no_call() -> void:
	var a := _alone()
	var sim = a.sim
	var s = a.seg
	s.max_hp = 6000.0    # (a wall that one of the dead cannot get through before dawn)
	s.hp = 6000.0
	sim._segment_state(s)
	Helpers.run(sim, _secs(sim, NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)) * 2.0)
	check(s.hp < s.max_hp, "(it is being clawed)")
	eq(_calls(sim, "going").size(), 0, "a wall that will stand till the morning needs no one")
	a.g.world.free()


func test_a_covered_wall_or_one_the_avatar_stands_at_is_not_called_for_one_of_the_dead() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.attack(sim, BUS, 1)    # (Dez's post is at the bus)
	check(sim.tactics.coverage_without_player(_seg(sim, BUS)) > 0, "(the bus has a gun on it)")
	_hurt(sim, BUS, 0.5)
	Helpers.run(sim, _secs(sim, NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)) * 3.0)
	eq(_calls(sim, "going").size(), 0, "a wall with a gun on it is the guns' business")
	g.world.free()
	var a := _alone()
	var sim2 = a.sim
	var s = a.seg
	var me = _p(sim2, "ruth")
	var spot: Vector2 = s.center + Vector2(-2.0, 0.0) if s.side == "E" else (s.center + Vector2(2.0, 0.0) if s.side == "W" else s.center + Vector2(0.0, 2.0))
	_put(me, spot)
	check(Vector2(me.x, me.y).distance_to(s.center) < NightData.num("rally.radius"), "(he stands within the rally's reach of it)")
	Helpers.run(sim2, _secs(sim2, NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)) * 3.0)
	eq(_calls(sim2, "going").size(), 0, "he is there: no call tells him so")
	a.g.world.free()


func test_the_half_hour_is_counted_from_the_dead_being_at_it_and_starts_again_when_it_is_left_alone() -> void:
	var a := _alone()
	var sim = a.sim
	var wait: float = NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)
	Helpers.run(sim, _secs(sim, wait) * 0.8)
	for z in sim.zombies:    # (the guns, or a hand, put it down)
		if z.slot != null:
			z.slot.who = null
		z.state = "dead"
		z.remove = true
	Helpers.run(sim, _secs(sim, 20.0))
	Helpers.attack(sim, int(a.seg.id), 1)
	Helpers.run(sim, _secs(sim, wait) * 0.8)
	eq(_calls(sim, "going").size(), 0, "the time at it before is not counted again")
	Helpers.run(sim, _secs(sim, wait) * 0.5)
	eq(_calls(sim, "going").size(), 1, "but half an hour of the new one is")
	a.g.world.free()


func test_the_calls_for_a_lone_attacker_and_for_a_wall_that_is_going_are_each_made_once_and_the_first_is_settled() -> void:
	var a := _alone()
	var sim = a.sim
	var s = a.seg
	Helpers.run(sim, _secs(sim, NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)) * 1.5)
	var first := _calls(sim, "going")
	eq(first.size(), 1, "(the call about the lone attacker)")
	Helpers.attack(sim, int(s.id), 3)
	_hurt(sim, int(s.id), NightData.num("calls.going_below") - 0.05)
	Helpers.run(sim, 0.2)
	var all := _calls(sim, "going")
	eq(all.size(), 2, "the wall that goes under four tenths with the crowd at it is a second call, not the first again")
	eq(first[0].answered, "hold", "and the first is settled by its default")
	check(first[0].by_default, "as nobody answered it")
	eq(_open(sim, "going").size(), 1, "one open call for the wall")
	a.g.world.free()


func test_a_lone_attacker_by_day_or_with_no_avatar_is_no_call() -> void:
	var a := _alone()
	var sim = a.sim
	Helpers.at(sim, 3, 14.0)
	sim.waves.enabled = false
	Helpers.run(sim, _secs(sim, NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)) * 3.0)
	eq(_calls(sim, "going").size(), 0, "by day nothing is called")
	a.g.world.free()
	var g := Helpers.make(1, 1, 5)
	var sim2 = g.sim
	sim2.waves.enabled = false
	sim2.zombies.clear()
	sim2.stock.ammo = 0.0
	Helpers.at(sim2, 3, 22.0)
	var s = _uncovered(sim2)
	check(s != null, "(a section nobody covers)")
	_hurt(sim2, int(s.id), 0.9)
	Helpers.attack(sim2, int(s.id), 1)
	Helpers.run(sim2, _secs(sim2, NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)) * 3.0)
	check(sim2.radio.news.is_empty(), "with no avatar the log stays empty: %s" % str(sim2.radio.news))
	g.world.free()


## A scenario that is Orientation Day's shape (it is told by its `after_step`) and not over.
class FakeLesson:
	extends "res://scripts/sim/scenario.gd"
	var finished := false

	func after_step() -> void:
		pass


func test_the_lessons_scripted_night_is_not_called_for_a_lone_attacker_and_the_real_nights_after_it_are() -> void:
	var a := _alone()
	var sim = a.sim
	var lesson := FakeLesson.new()
	lesson.setup(sim)
	sim.scenario = lesson
	Helpers.run(sim, _secs(sim, NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)) * 3.0)
	eq(_calls(sim, "going").size(), 0, "Orientation Day's night is the script's: no call about a wall nobody covers")
	lesson.finished = true
	Helpers.run(sim, _secs(sim, NightData.num("calls.unattended_min", NightCalls.UNATTENDED_MIN)) * 1.5)
	eq(_calls(sim, "going").size(), 1, "and when the lesson is over the real nights have it")
	a.g.world.free()


func test_going_is_raised_once_for_a_section_a_night_and_again_the_next_night() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, 0.3)
	Helpers.run(sim, 3.0)
	eq(_calls(sim, "going").size(), 1, "one call however long it lasts")
	var c: Dictionary = _calls(sim, "going")[0]
	check(sim.radio.answer(int(c.id), "hold"), "answered")
	Helpers.run(sim, 1.0)
	eq(_calls(sim, "going").size(), 1, "and no second call for the same wall once it is answered")
	# the next night
	for z in sim.zombies:
		z.state = "dead"
		z.remove = true
	for s in sim.segments:
		for sl in s.slots:
			sl.who = null
	Helpers.at(sim, 4, 22.0)
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, 0.3)
	Helpers.run(sim, 0.2)
	eq(_calls(sim, "going").size(), 2, "the next night's wall has its own call")
	g.world.free()


func test_going_settles_the_open_attack_call_by_its_default_and_quietly() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.attack(sim, BUS, 3)
	Helpers.run(sim, 3.0)
	var attack := _calls(sim, "attack")
	eq(attack.size(), 1, "the wall under attack has the old call first")
	eq(attack[0].answered, "", "and it is open")
	_hurt(sim, BUS, 0.3)
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "going").size(), 1, "then the wall is going")
	eq(attack[0].answered, "hold", "the old call is settled by its default")
	check(attack[0].by_default, "by default, as nobody answered it")
	eq(_open(sim, "attack").size(), 0, "and no old call is left open")
	eq(_open(sim, "going").size(), 1, "the new one is the open one")
	var answered_events := 0
	for e in sim.events:
		if e.get("type", "") == "radio_answered" and int(e.id) == int(attack[0].id):
			answered_events += 1
	eq(answered_events, 0, "and it was done quietly (no answer is announced)")
	g.world.free()


func test_a_plated_brute_at_a_wall_leaves_one_open_call_and_the_old_one_does_not_come_back() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.plated_brute(sim, BUS)
	Helpers.run(sim, 2.0)
	eq(_calls(sim, "going").size(), 1, "going is raised for the brute")
	eq(_open(sim, "going").size(), 1, "and it is the open one")
	eq(_open(sim, "attack").size(), 0, "the old call, if it was made, is settled")
	var n := _calls(sim, "attack").size()
	Helpers.run(sim, 3.0)
	eq(_calls(sim, "attack").size(), n, "and the wall's next knocks do not make another")
	g.world.free()


# ------------------------------------------------------------- reinforce, two --

func test_reinforcing_from_going_sends_exactly_two_and_not_the_walls_own_defenders() -> void:
	var g := _game()
	var sim = g.sim
	var n: int = int(NightData.num("calls.reinforce_n"))
	for p in sim.people:
		if not p.player:
			_put(p, sim.jobs.post_pos(p))    # everybody at their post
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, 0.3)
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "going")[0]
	var seg = _seg(sim, BUS)
	check(sim.radio.answer(int(c.id), "reinforce"), "the player answers")
	var sent: Array = []
	for p in sim.people:
		if p.order != null and p.drafted:
			sent.append(String(p.id))
	eq(sent.size(), n, "exactly %d are sent" % n)
	check(not sent.has("dez"), "Dez holds the bus himself: he is not the reinforcement (%s)" % str(sent))
	check(not sent.has("ruth"), "the leader sends himself nowhere")
	check(String(c.result).contains("(%d)" % n), "the line says how many: %s" % str(c.result))
	for id in sent:
		var p = _p(sim, id)
		check(Vector2(p.order.x, p.order.y).distance_to(seg.center) < 14.0, "%s goes to near the bus: %s" % [id, str(p.order)])
	g.world.free()


func test_the_old_attack_call_still_sends_everyone_who_is_free() -> void:
	var g := _game()
	var sim = g.sim
	for p in sim.people:
		if not p.player:
			_put(p, sim.jobs.post_pos(p))
	Helpers.attack(sim, BUS, 2)
	Helpers.run(sim, 3.0)
	var c: Dictionary = _calls(sim, "attack")[0]
	check(sim.radio.answer(int(c.id), "reinforce"), "answered")
	var sent := 0
	for p in sim.people:
		if p.order != null and p.drafted and not p.player:
			sent += 1
	eq(sent, 4, "the old call sends all four who are not the leader")
	g.world.free()


func test_reinforcing_sends_fewer_when_fewer_are_free() -> void:
	var g := _game()
	var sim = g.sim
	for p in sim.people:
		if not p.player:
			_put(p, sim.jobs.post_pos(p))
	for id in ["walt", "marcus", "ana"]:
		_p(sim, id).stance = "hold"    # asked to hold a spot: not free to be sent
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, 0.3)
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "going")[0]
	sim.radio.answer(int(c.id), "reinforce")
	var sent := 0
	for p in sim.people:
		if p.order != null and p.drafted and p.stance == "":
			sent += 1
	eq(sent, 1, "only Dez is free: he is sent (the call does what it can)")
	g.world.free()


# -------------------------------------------------------------------- coming --

func _going_at_the_bus(sim) -> Dictionary:
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, 0.3)
	Helpers.run(sim, 0.1)
	return _calls(sim, "going")[0]


func test_coming_lifts_the_defenders_near_the_wall_and_only_them() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_put(dez, Vector2(47.5, 24.0))
	var c := _going_at_the_bus(sim)
	var radius: float = NightData.num("rally.radius")
	var seg = _seg(sim, BUS)
	var before := {}
	for p in sim.people:
		before[String(p.id)] = sim.morale.value(p)
	check(sim.radio.answer(int(c.id), "coming"), "the player says he is coming")
	var lifted := 0
	for p in sim.people:
		var near_it: bool = not p.player and Vector2(p.x, p.y).distance_to(seg.center) <= radius
		var delta: float = sim.morale.value(p) - float(before[String(p.id)])
		if near_it:
			near(delta, NightData.num("calls.coming_morale"), 0.001, "%s near the wall is lifted by the data's number" % p.first)
			lifted += 1
		else:
			near(delta, 0.0, 0.001, "%s is not near it: nothing" % p.first)
	check(lifted >= 1, "Dez at least was near")
	check(String(sim.morale.shocks[dez.id][0].label) == "Help is on the way" or String(sim.morale.shocks[dez.id][sim.morale.shocks[dez.id].size() - 1].label) == "Help is on the way", "the reason is named")
	eq(int(sim.radio.night.focus.seg), BUS, "the radio remembers where he said he was going")
	near(float(sim.radio.night.focus.until) - sim.clock_min, NightData.num("calls.coming_window_min"), 0.5, "and for how long")
	g.world.free()


func test_arriving_in_time_earns_trust_once() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_put(dez, Vector2(47.5, 24.0))
	var c := _going_at_the_bus(sim)
	var trust: float = dez.trust
	sim.radio.answer(int(c.id), "coming")
	Helpers.run(sim, 0.2)
	near(dez.trust, trust, 0.0001, "he has not come yet: nothing")
	_put(_p(sim, "ruth"), Vector2(47.5, 24.5))    # at the bus, among them
	Helpers.run(sim, 0.2)
	near(dez.trust, trust + NightData.num("calls.kept_trust"), 0.0001, "he came when he said: Dez trusts him more")
	eq(sim.radio.trust_why(dez)[0].why, "You came when you said", "and the reason says so")
	check(sim.radio.night.focus.is_empty(), "the promise is kept and forgotten")
	Helpers.run(sim, 1.0)
	near(dez.trust, trust + NightData.num("calls.kept_trust"), 0.0001, "once only")
	Helpers.run(sim, NightData.num("calls.coming_window_min") / sim.min_per_sec + 1.0)
	near(dez.trust, trust + NightData.num("calls.kept_trust"), 0.0001, "and nothing is taken when the time is up")
	g.world.free()


func test_not_arriving_in_time_costs_trust() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	_put(dez, Vector2(47.5, 24.0))
	var c := _going_at_the_bus(sim)
	var trust: float = dez.trust
	var far: float = marcus.trust
	sim.radio.answer(int(c.id), "coming")
	Helpers.run(sim, NightData.num("calls.coming_window_min") / sim.min_per_sec - 1.0)
	near(dez.trust, trust, 0.0001, "the time is not up yet")
	Helpers.run(sim, 2.0)
	near(dez.trust, trust + NightData.num("calls.broken_trust"), 0.0001, "he said he was coming and did not")
	eq(sim.radio.trust_why(dez)[0].why, "You said you were coming", "and the reason says so")
	near(marcus.trust, far, 0.0001, "those who did not hear him are not let down")
	check(sim.radio.night.focus.is_empty(), "and it is over")
	Helpers.run(sim, 2.0)
	near(dez.trust, trust + NightData.num("calls.broken_trust"), 0.0001, "once only")
	g.world.free()


func test_coming_is_only_offered_while_the_avatar_is_at_the_base_and_up() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = _p(sim, "ruth")
	ruth.away = {"kind": "trip"}
	var c := _going_at_the_bus(sim)
	eq(_ids(c), ["hold", "reinforce", "fall_back"], "raised while he is out: a plain warning with what can be done from there")
	ruth.away = null
	g.world.free()
	var h := _game()
	var s2 = h.sim
	var r2 = _p(s2, "ruth")
	r2.downed = true
	var c2 := _going_at_the_bus(s2)
	check(not _ids(c2).has("coming"), "he cannot come when he is down")
	r2.downed = false
	h.world.free()


func test_a_coming_answered_after_he_has_left_does_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_put(dez, Vector2(47.5, 24.0))
	var c := _going_at_the_bus(sim)
	var ruth = _p(sim, "ruth")
	var value: float = sim.morale.value(dez)
	ruth.away = {"kind": "trip"}
	check(sim.radio.answer(int(c.id), "coming"), "it is answered")
	near(sim.morale.value(dez), value, 0.0001, "nobody is lifted by a promise of somebody who is not there")
	check(sim.radio.night.focus.is_empty(), "and nothing is promised")
	check(String(c.result) != "", "the line says why")
	ruth.away = null
	g.world.free()


# ------------------------------------------------------------------- brute --

## A brute (plated or not) on its way to the bus, `from` tiles away, with its place at the wall.
func _brute_to(sim, seg_id: int, from: Vector2, plated: bool):
	var z = sim.spawn(from.x, from.y, "approach", "brute")
	z.plated = plated
	check(sim.assign_slot(z, _seg(sim, seg_id)), "the brute has a place at the wall")
	return z


func test_a_brute_on_its_way_raises_one_call_with_its_options() -> void:
	var g := _game()
	var sim = g.sim
	var z = _brute_to(sim, BUS, Vector2(52.0, 10.2), true)
	Helpers.run(sim, 0.1)
	var calls := _calls(sim, "brute")
	eq(calls.size(), 1, "a brute with a place at the bus is a call")
	var c: Dictionary = calls[0]
	check(String(c.text).to_lower().contains("plated brute") and String(c.text).to_lower().contains("school bus"), "A plated brute at the school bus: %s" % str(c.text))
	var ids := _ids(c)
	check(ids.slice(0, 3) == ["watch", "coming", "reinforce"], "watch, I'll take it, send two (then the lure): %s" % str(ids))
	eq(c.default, "watch", "the default is to keep the guns on it")
	near(float(c.due) - float(c.t), NightData.num("calls.brute_ttl_min"), 0.001, "it waits as long as the data says")
	Helpers.run(sim, 2.0)
	eq(_calls(sim, "brute").size(), 1, "once for the section a night")
	check(z.slot != null, "(it still has its place)")
	g.world.free()


func test_a_plain_brute_is_a_brute_and_one_that_is_far_away_is_no_call_yet() -> void:
	var g := _game()
	var sim = g.sim
	_brute_to(sim, BUS, Vector2(52.0, 10.2), false)
	Helpers.run(sim, 0.1)
	var calls := _calls(sim, "brute")
	eq(calls.size(), 1, "an ordinary night's brute is a call too")
	check(String(calls[0].text).to_lower().contains("a brute") and not String(calls[0].text).to_lower().contains("plated"), "and not called plated: %s" % str(calls[0].text))
	g.world.free()
	var h := _game()
	var s2 = h.sim
	var far: float = NightData.num("calls.brute_warn_r")
	_brute_to(s2, BUS, Vector2(8.5, 63.5), true)    # the south west spawn point: about 59 tiles from the bus
	Helpers.run(s2, 0.1)
	eq(_calls(s2, "brute").size(), 0, "a brute still beyond %d tiles is not announced" % int(far))
	h.world.free()


func test_a_brute_that_is_not_coming_to_the_wall_is_no_call() -> void:
	var g := _game()
	var sim = g.sim
	var z = sim.spawn(47.5, 5.0, "wander", "brute")
	z.plated = true
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "brute").size(), 0, "a brute that wanders is not on its way to a wall")
	g.world.free()


func test_the_lure_option_names_the_best_defended_other_section_and_costs_scrap() -> void:
	var g := _game()
	var sim = g.sim
	for p in sim.people:
		if not p.player:
			_put(p, sim.jobs.post_pos(p))
	_p(sim, "dez").away = {"kind": "trip"}    # nobody covers the bus now: another wall is the better place for it
	_hurt(sim, BUS, 0.8)
	sim.stock.scrap = 20.0
	_brute_to(sim, BUS, Vector2(52.0, 10.2), true)
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "brute")[0]
	var best = _lure_ranking(sim, _seg(sim, BUS))[0]
	check(_ids(c).has("lure"), "a better defended wall is offered: %s" % str(_ids(c)))
	var label := String(_option(c, "lure").label)
	check(label.to_lower().contains(String(best.name).to_lower()), "it names the best of the others (%s): %s" % [best.name, label])
	check(label.contains("3 scrap"), "and what it costs: %s" % label)
	check(sim.radio.night.best_lure_section(_seg(sim, BUS)) == best, "best_lure_section agrees")
	var scrap: float = sim.stock.scrap
	check(sim.radio.answer(int(c.id), "lure"), "the player draws it off")
	eq(sim.tactics.lure_id, int(best.id), "the alarm rings on that section")
	near(sim.stock.scrap, scrap - sim.tactics.LURE_COST, 0.0001, "it cost three scrap")
	g.world.free()


func test_the_lure_from_the_brute_call_draws_the_plated_brute_to_the_other_wall() -> void:
	var g := _game()
	var sim = g.sim
	for p in sim.people:
		if not p.player:
			_put(p, sim.jobs.post_pos(p))
	_p(sim, "dez").away = {"kind": "trip"}
	_hurt(sim, BUS, 0.8)
	sim.stock.scrap = 20.0
	var z = _brute_to(sim, BUS, Vector2(52.0, 10.2), true)
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "brute")[0]
	var lured: int = int(c.data.lure)
	check(sim.radio.answer(int(c.id), "lure"), "the player draws it off")
	check(z.slot != null, "the brute still has a place at a wall")
	if z.slot != null:
		eq(int(z.slot.seg.id), lured, "and it is at the section the alarm rings on (every brute obeys it in avatar mode)")
	g.world.free()


func test_no_scrap_or_an_alarm_already_ringing_leaves_the_lure_out() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 1.0
	_p(sim, "dez").away = {"kind": "trip"}
	_brute_to(sim, BUS, Vector2(52.0, 10.2), true)
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "brute")[0]
	check(not _ids(c).has("lure"), "with no scrap to spare there is no lure: %s" % str(_ids(c)))
	check(sim.radio.night.best_lure_section() == null, "and no section to name")
	g.world.free()


func test_best_lure_section_skips_the_avoided_one_the_doors_the_fallen_and_the_lots() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 20.0
	var ranking := _lure_ranking(sim)
	var best = ranking[0]
	check(sim.radio.night.best_lure_section() == best, "the best of all")
	check(sim.radio.night.best_lure_section(best) == ranking[1], "the next when the best is to be avoided")
	check(sim.radio.night.best_lure_section(int(best.id)) == ranking[1], "(an id will do as well as the section)")
	for s in ranking:
		check(s.kind != sim.DOOR_KIND and int(s.id) < 100, "%s is a compound wall, not a door or a lot's" % s.name)
	_fall(sim, int(best.id))
	var after = sim.radio.night.best_lure_section()
	check(after != best and after != null, "a section that is down is no place for it")
	sim.tactics.lure_id = 5
	check(sim.radio.night.best_lure_section() == null, "and none at all while an alarm already rings")
	sim.tactics.lure_id = -1
	g.world.free()


# ------------------------------------------------------------------ breach --

func test_a_section_that_falls_at_night_raises_breach_once() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.run(sim, 0.1)
	_fall(sim, BUS)
	Helpers.run(sim, 0.1)
	var calls := _calls(sim, "breach")
	eq(calls.size(), 1, "the wall that has fallen has a call")
	var c: Dictionary = calls[0]
	check(String(c.text).to_lower().contains("school bus") and String(c.text).contains("down"), "it says what is down: %s" % str(c.text))
	eq(_ids(c), ["hold", "close", "fall_back", "coming"], "hold the line, close it, pull back, I'm on my way")
	eq(c.default, "hold", "the default is to hold")
	near(float(c.due) - float(c.t), NightData.num("calls.breach_ttl_min"), 0.001, "it waits as long as the data says")
	check(String(_option(c, "close").label).to_lower().contains("needs you"), "it says closing needs him there: %s" % str(_option(c, "close")))
	Helpers.run(sim, 3.0)
	eq(_calls(sim, "breach").size(), 1, "one call, not one a step")
	g.world.free()


func test_a_wall_that_falls_again_the_same_night_after_it_was_shut_is_a_new_breach() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.run(sim, 0.1)
	_fall(sim, BUS)
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "breach").size(), 1, "the first fall")
	_hurt(sim, BUS, 0.9)    # (mended above the rebuilding mark)
	Helpers.run(sim, 0.1)
	var shut := 0
	for e in sim.radio.news:
		if e.kind == "breach" and String(e.text).contains("shut again"):
			shut += 1
	eq(shut, 1, "it is shut again, in the news")
	_fall(sim, BUS)
	Helpers.run(sim, 0.1)
	var calls := _calls(sim, "breach")
	eq(calls.size(), 3, "and the second fall is a call of its own (the dead did not go home): %s" % str(calls.map(func(e): return e.text)))
	g.world.free()


func test_a_section_that_was_down_before_the_night_is_no_news_and_a_door_is_no_wall() -> void:
	var g := _game(3, 16.0)
	var sim = g.sim
	Helpers.run(sim, 0.1)
	_fall(sim, BUS)
	Helpers.run(sim, 0.1)
	Helpers.at(sim, 3, 20.0)
	Helpers.run(sim, 1.0)
	eq(_calls(sim, "breach").size(), 0, "a wall that fell by day is not a breach of the night: the day's crew has it")
	_fall(sim, 14)    # the west school door
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "breach").size(), 0, "and a school door is not a section of the wall")
	g.world.free()


func test_a_breach_settles_the_open_going_and_attack_calls_of_that_section() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.attack(sim, BUS, 3)
	Helpers.run(sim, 3.0)
	_hurt(sim, BUS, 0.3)
	Helpers.run(sim, 0.1)
	eq(_open(sim, "going").size(), 1, "the wall was going")
	_fall(sim, BUS)
	Helpers.run(sim, 0.1)
	eq(_open(sim, "going").size(), 0, "the going call is over: the wall is down")
	eq(_open(sim, "attack").size(), 0, "and so is the attack call")
	eq(_open(sim, "breach").size(), 1, "the breach is the call that is open")
	g.world.free()


func test_closing_a_breach_sends_the_two_nearest_to_mend_it_and_says_they_need_him() -> void:
	var g := _game()
	var sim = g.sim
	for p in sim.people:
		if not p.player:
			_put(p, sim.jobs.post_pos(p))
	Helpers.run(sim, 0.1)
	_fall(sim, BUS)
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "breach")[0]
	var seg = _seg(sim, BUS)
	check(sim.radio.answer(int(c.id), "close"), "the player answers: close it")
	var menders: Array = []
	for p in sim.people:
		if p.repair == seg:
			menders.append(p)
	eq(menders.size(), 2, "two go to mend it")
	check(not menders.has(_p(sim, "ruth")), "not the leader")
	var near_first := Vector2(menders[0].x, menders[0].y).distance_to(seg.center) <= Vector2(_p(sim, "ana").x, _p(sim, "ana").y).distance_to(seg.center)
	check(near_first, "and they are the nearest ones")
	check(String(c.result).contains("go to mend it") and String(c.result).contains("need you"), "the line says so: %s" % str(c.result))
	for p in menders:
		check(String(c.result).contains(String(p.first)), "and names %s: %s" % [p.first, str(c.result)])
	g.world.free()


func test_a_breach_that_is_shut_again_is_in_the_news() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.run(sim, 0.1)
	_fall(sim, BUS)
	Helpers.run(sim, 0.1)
	var before := _calls(sim, "breach").size()
	_hurt(sim, BUS, 0.9)    # mended above the rebuilding mark
	Helpers.run(sim, 0.1)
	var calls := _calls(sim, "breach")
	eq(calls.size(), before + 1, "a line is added")
	var last: Dictionary = calls[calls.size() - 1]
	check(String(last.text).to_lower().contains("school bus") and String(last.text).contains("shut again"), "it says so: %s" % str(last.text))
	check(last.options.is_empty(), "it is news, not a call")
	Helpers.run(sim, 2.0)
	eq(_calls(sim, "breach").size(), before + 1, "once")
	g.world.free()


func test_a_breach_raised_while_he_is_out_has_no_coming_and_no_close() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.run(sim, 0.1)
	_p(sim, "ruth").away = {"kind": "trip"}
	_fall(sim, BUS)
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "breach")[0]
	eq(_ids(c), ["hold", "fall_back"], "a plain warning: hold or pull back")
	_p(sim, "ruth").away = null
	g.world.free()


func test_falling_back_from_going_does_what_the_old_call_does() -> void:
	var g := _game()
	var sim = g.sim
	for p in sim.people:
		if not p.player:
			_put(p, sim.jobs.post_pos(p))
	var c := _going_at_the_bus(sim)
	check(sim.radio.answer(int(c.id), "fall_back"), "fall back")
	var dez = _p(sim, "dez")
	check(dez.order != null and dez.order.y > 45.0, "Dez, whose post is at the bus, goes into the school: %s" % str(dez.order))
	check(String(c.result).begins_with("Falling back"), "the old words: %s" % str(c.result))
	g.world.free()


# ------------------------------------------------------------- the night call --

## The lookout has given tonight's forecast (Marcus), and the waves say tonight is a Siege.
func _forecast_given(sim, outlook: Dictionary) -> void:
	var w := _fake(sim)
	w.outlooks[sim.day] = outlook
	if String(outlook.get("kind", "")) != "ordinary":
		w.bigs[sim.day] = big_siege()
	sim.tactics.forecast_day = sim.day
	sim.tactics.forecast_who = "marcus"


func test_the_night_call_comes_with_the_forecast_when_the_night_is_big() -> void:
	var g := _game(9, 17.0)
	var sim = g.sim
	_forecast_given(sim, siege(9))
	Helpers.run(sim, 0.1)
	var calls := _calls(sim, "night")
	eq(calls.size(), 1, "a Big Night read by the lookout is a call")
	var c: Dictionary = calls[0]
	check(String(c.text).contains("The Siege"), "it names the night: %s" % str(c.text))
	check(String(c.sub).contains("70 to 95") and String(c.sub).contains("east"), "and says how many and from where: %s" % str(c.sub))
	check(String(c.sub).contains("2 plated brutes after 23:00"), "and the brutes: %s" % str(c.sub))
	var ids := _ids(c)
	check(ids.slice(0, 2) == ["hold", "arms"], "understood, call to arms now (then the alarm): %s" % str(ids))
	if ids.size() > 2:
		eq(ids[2], "lure", "the alarm on a section is the third")
	eq(c.default, "hold", "the default is to understand")
	var to_the_bell: float = (sim.seasons.dusk_hour() - sim.hour) * 60.0
	near(float(c.due) - float(c.t), to_the_bell, 0.5, "it waits until the bell")
	Helpers.run(sim, 2.0)
	eq(_calls(sim, "night").size(), 1, "once a night")
	g.world.free()


func test_an_ordinary_night_or_no_lookout_or_no_waves_gives_no_night_call() -> void:
	var g := _game(9, 17.0)
	var sim = g.sim
	_forecast_given(sim, ordinary(9))
	Helpers.run(sim, 0.2)
	eq(_calls(sim, "night").size(), 0, "an ordinary night that should hold is not a call")
	g.world.free()
	var h := _game(9, 17.0)
	var s2 = h.sim
	var w := _fake(s2)
	w.outlooks[9] = siege(9)
	w.bigs[9] = big_siege()
	s2.tactics.forecast_day = 9
	s2.tactics.forecast_who = ""
	Helpers.run(s2, 0.2)
	eq(_calls(s2, "night").size(), 0, "nobody on watch, no forecast, no call")
	h.world.free()
	var k := _game(9, 17.0)
	var s3 = k.sim
	s3.tactics.forecast_day = 9
	s3.tactics.forecast_who = "marcus"
	Helpers.run(s3, 0.2)
	eq(_calls(s3, "night").size(), 0, "the waves say nothing special about tonight")
	k.world.free()


func test_the_night_call_is_raised_by_the_lookouts_own_report() -> void:
	var g := _game(9, 16.95)
	var sim = g.sim
	var w := _fake(sim)
	w.outlooks[9] = siege(9)
	w.bigs[9] = big_siege()
	var marcus = _p(sim, "marcus")
	Helpers.seat(sim, marcus, "watch")
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "night").size(), 0, "before the hour of the forecast: nothing")
	Helpers.at(sim, 9, 17.0)
	Helpers.run(sim, 0.2)
	eq(String(sim.tactics.forecast_who), "marcus", "Marcus gives the forecast")
	eq(_calls(sim, "night").size(), 1, "and the call comes with it")
	g.world.free()


func test_the_night_call_is_not_raised_after_the_bell() -> void:
	var g := _game(9, 20.0)
	var sim = g.sim
	_forecast_given(sim, siege(9))
	Helpers.run(sim, 0.2)
	eq(_calls(sim, "night").size(), 0, "too late to forecast: the bell has rung")
	g.world.free()


func test_the_call_to_arms_from_the_night_call_rings_the_alarm() -> void:
	var g := _game(9, 17.0)
	var sim = g.sim
	_forecast_given(sim, siege(9))
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "night")[0]
	check(not sim.radio.alarm_on, "not yet")
	check(sim.radio.answer(int(c.id), "arms"), "the player rings it")
	check(sim.radio.alarm_on, "the alarm is ringing")
	g.world.free()


func test_the_alarm_on_a_section_from_the_night_call_sets_the_lure() -> void:
	var g := _game(9, 17.0)
	var sim = g.sim
	sim.stock.scrap = 20.0
	_forecast_given(sim, siege(9))
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "night")[0]
	check(_ids(c).has("lure"), "the alarm is offered: %s" % str(_ids(c)))
	var label := String(_option(c, "lure").label)
	var best = _lure_ranking(sim)[0]
	check(label.to_lower().contains(String(best.name).to_lower()), "on the best defended section (%s): %s" % [best.name, label])
	var scrap: float = sim.stock.scrap
	check(sim.radio.answer(int(c.id), "lure"), "the player sets it")
	eq(sim.tactics.lure_id, int(best.id), "it rings there")
	near(sim.stock.scrap, scrap - sim.tactics.LURE_COST, 0.0001, "for the scrap it costs")
	g.world.free()


func test_the_night_call_without_the_scrap_has_no_alarm_option() -> void:
	var g := _game(9, 17.0)
	var sim = g.sim
	sim.stock.scrap = 0.0
	_forecast_given(sim, siege(9))
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "night")[0]
	eq(_ids(c), ["hold", "arms"], "no scrap, no alarm on a section")
	g.world.free()


func test_an_unanswered_night_call_is_understood_at_the_bell() -> void:
	var g := _game(9, 17.0)
	var sim = g.sim
	_forecast_given(sim, siege(9))
	Helpers.run(sim, 0.1)
	var c: Dictionary = _calls(sim, "night")[0]
	Helpers.run_to_hour(sim, sim.seasons.dusk_hour() + 0.05)
	eq(c.answered, "hold", "taken as understood")
	check(c.by_default, "by default")
	check(not sim.radio.alarm_on, "and nothing else was done")
	g.world.free()


# ------------------------------------------------------------ the day-ahead notice --

## Noon of day 9 with the radio desk staffed (Walt at it) and a Siege to come on day 10.
func _noon_before_a_siege() -> Dictionary:
	var g := _game(9, 11.9)
	var sim = g.sim
	var w := _fake(sim)
	w.outlooks[10] = siege(10)
	w.bigs[10] = big_siege()
	Helpers.seat(sim, _p(sim, "walt"), "radio")
	return g


func test_the_notice_comes_at_noon_with_the_desk_staffed_and_says_what_the_night_will_be() -> void:
	var g := _noon_before_a_siege()
	var sim = g.sim
	Helpers.run(sim, 0.1)
	eq(_calls(sim, "forecast").size(), 0, "before noon: nothing")
	Helpers.at(sim, 9, NightData.num("forecast.notice_hour"))
	Helpers.run(sim, 0.2)
	var calls := _calls(sim, "forecast")
	eq(calls.size(), 1, "at noon the desk gives the notice")
	var e: Dictionary = calls[0]
	eq(e.text, "Big Night tomorrow: The Siege", "the headline")
	check(String(e.sub).contains("About 70 to 95 from the east side (the second bus, the chain-link)."), "how many and where: %s" % str(e.sub))
	check(String(e.sub).contains("2 plated brutes after 23:00."), "the brutes: %s" % str(e.sub))
	var home_by: float = sim.seasons.dusk_hour() - NightData.num("forecast.road_margin_min") / 60.0
	var want := "Be home by %02d:%02d." % [int(home_by), roundi((home_by - floorf(home_by)) * 60.0)]
	check(String(e.sub).contains(want), "and when to be home (%s): %s" % [want, str(e.sub)])
	check(e.options.is_empty(), "it is news: no answer is asked")
	check(sim.alerts.has("bignight-next"), "an alert says it too")
	if sim.alerts.has("bignight-next"):
		near(float(sim.alerts["bignight-next"].ttl), 60.0, 0.001, "for a minute")
		eq(sim.alerts["bignight-next"].text, e.text, "the same words")
	Helpers.run(sim, 10.0)
	eq(_calls(sim, "forecast").size(), 1, "once")
	g.world.free()


func test_no_notice_when_nobody_is_at_the_desk_and_none_for_an_ordinary_night() -> void:
	var g := _noon_before_a_siege()
	var sim = g.sim
	sim.jobs.unassign(_p(sim, "walt"))
	Helpers.at(sim, 9, 12.0)
	Helpers.run(sim, 20.0)    # through the half hour that follows
	eq(_calls(sim, "forecast").size(), 0, "nobody at the desk, no notice (the night still comes)")
	g.world.free()
	var h := _game(9, 12.0)
	var s2 = h.sim
	var w := _fake(s2)
	w.outlooks[10] = ordinary(10)
	Helpers.seat(s2, _p(s2, "walt"), "radio")
	Helpers.run(s2, 0.5)
	eq(_calls(s2, "forecast").size(), 0, "an ordinary night is not announced")
	h.world.free()


func test_the_notice_is_made_again_the_next_day_and_a_late_desk_does_not_make_up_for_it() -> void:
	var g := _noon_before_a_siege()
	var sim = g.sim
	Helpers.at(sim, 9, 12.0)
	Helpers.run(sim, 0.2)
	eq(_calls(sim, "forecast").size(), 1, "day 9")
	var w: FakeWaves = sim.waves
	w.outlooks[11] = siege(11)
	Helpers.at(sim, 10, 12.0)
	Helpers.run(sim, 0.2)
	eq(_calls(sim, "forecast").size(), 2, "and on day 10 for day 11")
	g.world.free()
	var h := _noon_before_a_siege()
	var s2 = h.sim
	s2.jobs.unassign(_p(s2, "walt"))
	Helpers.at(s2, 9, 12.0)
	Helpers.run(s2, 0.2)
	Helpers.at(s2, 9, 14.0)
	Helpers.seat(s2, _p(s2, "walt"), "radio")
	Helpers.run(s2, 0.5)
	eq(_calls(s2, "forecast").size(), 0, "a desk staffed in the afternoon says nothing: the notice is the noon's")
	h.world.free()


func test_the_real_waves_give_a_notice_for_a_real_big_night() -> void:
	var g := _game(9, 11.9)
	var sim = g.sim
	var tomorrow: Dictionary = sim.waves.outlook(10)
	var big := not (tomorrow.is_empty() or String(tomorrow.get("kind", "ordinary")) == "ordinary")
	check(big, "day 10 is a real Big Night (a test of the real waves does not pass by finding none; round 19 review F8): %s" % str(tomorrow.get("kind")))
	if not big:
		g.world.free()
		return
	Helpers.seat(sim, _p(sim, "walt"), "radio")
	Helpers.at(sim, 9, 12.0)
	Helpers.run(sim, 0.2)
	var calls := _calls(sim, "forecast")
	eq(calls.size(), 1, "the real outlook of day 10 is announced")
	if not calls.is_empty():
		check(String(calls[0].text).begins_with("Big Night tomorrow: "), "in the same words: %s" % str(calls[0].text))
		check(String(calls[0].sub).contains("Be home by"), "with the hour to be home by: %s" % str(calls[0].sub))
	g.world.free()


func test_the_real_waves_give_the_night_call_on_the_big_nights_own_day() -> void:
	var g := _game(10, 16.99)
	var sim = g.sim
	var tonight: Dictionary = sim.waves.outlook(10)
	var big := not (tonight.is_empty() or String(tonight.get("kind", "ordinary")) == "ordinary")
	check(big, "day 10 is a real Big Night (a test of the real waves does not pass by finding none; round 19 review F8): %s" % str(tonight.get("kind")))
	if not big:
		g.world.free()
		return
	Helpers.seat(sim, _p(sim, "marcus"), "watch")
	Helpers.run(sim, 0.5)
	eq(String(sim.tactics.forecast_who), "marcus", "the lookout gave the forecast")
	var calls := _calls(sim, "night")
	eq(calls.size(), 1, "and the real night is a call")
	if not calls.is_empty():
		check(String(calls[0].text).contains(String(tonight.name)), "named: %s" % str(calls[0].text))
		check(String(calls[0].sub).contains("About %d to %d" % [int(tonight.low), int(tonight.high)]), "sized: %s" % str(calls[0].sub))
		if sim.tactics.forecast().has("ready"):
			check(String(calls[0].sub).contains("Posts "), "with the readiness of the walls: %s" % str(calls[0].sub))
	g.world.free()


# --------------------------------------------------------------- avatar mode --

func test_with_no_avatar_none_of_it_happens() -> void:
	var g := Helpers.make(1, 1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.stock.ammo = 0.0
	var w := _fake(sim)
	w.outlooks[10] = siege(10)
	w.outlooks[9] = siege(9)
	w.bigs[9] = big_siege()
	eq(sim.player_id, "", "no avatar")
	Helpers.seat(sim, _p(sim, "walt"), "radio")
	Helpers.at(sim, 9, 12.0)
	Helpers.run(sim, 0.5)
	Helpers.at(sim, 9, 17.0)
	sim.tactics.forecast_day = 9
	sim.tactics.forecast_who = "marcus"
	Helpers.run(sim, 0.5)
	Helpers.at(sim, 9, 22.0)
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, 0.3)
	_brute_to(sim, CONTAINER, Vector2(24.0, 9.0), true)
	Helpers.run(sim, 1.0)
	_fall(sim, BUS)
	Helpers.run(sim, 1.0)
	check(sim.radio.news.is_empty(), "the log is empty: %s" % str(sim.radio.news))
	check(not sim.alerts.has("bignight-next"), "no day-ahead alert")
	check(sim.radio.night.focus.is_empty(), "no promise")
	check(sim.radio.night.road_status().get("on", true) == false, "nobody is on the road")
	g.world.free()


# -------------------------------------------------------------------- saving --

func test_the_calls_and_the_promise_survive_a_save() -> void:
	var a := _game()
	var sim = a.sim
	var dez = _p(sim, "dez")
	_put(dez, Vector2(47.5, 24.0))
	var c := _going_at_the_bus(sim)
	sim.radio.answer(int(c.id), "coming")
	var brute = _brute_to(sim, BUS, Vector2(52.0, 10.2), true)
	Helpers.run(sim, 0.2)
	check(brute != null, "(a brute)")
	var d := SaveGame.to_dict(sim)
	check(d.modules.radio.has("night"), "the night calls are saved with the radio")
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads from text")
	var rb = b.sim.radio
	eq(rb.news.size(), sim.radio.news.size(), "the log")
	check(not rb.night.focus.is_empty(), "the promise is kept")
	eq(int(rb.night.focus.seg), BUS, "to the same wall")
	near(float(rb.night.focus.until), float(sim.radio.night.focus.until), 0.001, "until the same time")
	eq(rb.night.focus.who, sim.radio.night.focus.who, "and to the same people")
	eq(JSON.stringify(rb.night.save(), "", true), JSON.stringify(sim.radio.night.save(), "", true), "and the rest")
	# the loaded game does not call the same wall again
	var count := _calls(b.sim, "going").size() + _calls(b.sim, "brute").size()
	for z in b.sim.zombies:
		z.state = "dead"
	b.sim.update(1.0 / 30.0)
	eq(_calls(b.sim, "going").size() + _calls(b.sim, "brute").size(), count, "no call is raised twice for the same wall after a load")
	a.world.free()
	b.world.free()


func test_a_save_from_before_the_night_calls_loads_with_none() -> void:
	var a := _game()
	var sim = a.sim
	sim.radio.log_news("test", "Something", "")
	var d := SaveGame.to_dict(sim)
	d.modules.radio.erase("night")
	var b := _bare()
	check(SaveGame.apply(b.sim, d), "it loads")
	check(b.sim.radio.night.focus.is_empty(), "no promise")
	check(b.sim.radio.night.save().get("called", {}).is_empty(), "no call remembered")
	eq(b.sim.radio.news.size(), 1, "the radio is as it was")
	a.world.free()
	b.world.free()


func test_a_damaged_night_state_loads_as_nothing() -> void:
	var a := _game()
	var sim = a.sim
	var d := SaveGame.to_dict(sim)
	d.modules.radio["night"] = {"focus": "nonsense", "called": [1, 2], "seen": {"x": "y"}, "notice_day": "never", "breaches": 4}
	var b := _bare()
	check(SaveGame.apply(b.sim, d), "it loads")
	check(b.sim.radio.night.focus.is_empty(), "no promise")
	a.world.free()
	b.world.free()


func test_a_new_run_forgets_the_nights_calls() -> void:
	var g := _game()
	var sim = g.sim
	var c := _going_at_the_bus(sim)
	sim.radio.answer(int(c.id), "coming")
	check(not sim.radio.night.focus.is_empty(), "a promise is made")
	sim.radio.start()
	check(sim.radio.night.focus.is_empty(), "a new run starts with none")
	check(sim.radio.night.save().get("called", {}).is_empty(), "and no call is remembered")
	g.world.free()
