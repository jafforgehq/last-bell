extends "res://tests/case.gd"
## Round 25, S25.3 PROBLEMS (scripts/sim/problems.gd, assets/data/problems.json): the small trouble the base throws up. A leak drains the water, a jam stops the
## bench and the floodlights, a quarrel costs two people work and mood, a crack widens a wall; each is a marker with a timer that the avatar fixes with its
## own hands (E) or hands to somebody over the radio (who may refuse, take time and fail); left alone it reaches stage 2 (one call) and then does its damage.
## The rate is a hash of the state: no `sim.rng`. Everything is behind avatar mode in the settlement game; with no avatar every hook is neutral.

const Helpers := preload("res://tests/helpers.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const DT := 1.0 / 30.0


# ----------------------------------------------------------------- helpers --

func _p(sim, id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


## A quiet avatar game (Ruth, five at the base) at 09:00 on day 3, nobody working, the other new modules off, the schedule frozen (a test raises what it
## wants), 20 scrap and 100 water.
func _game(seed_value: int = 7) -> Dictionary:
	var g := Helpers.avatar_game(seed_value, 5)
	var sim = g.sim
	Helpers.quiet_base(sim)
	sim.problems.enabled = true
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.no_work(sim)
	Helpers.at(sim, 3, 9.0)
	sim.stock.scrap = 20.0
	sim.stock.water = 100.0
	sim.radio.news.clear()
	sim.events.clear()
	sim.problems.next_at = 1.0e9
	g["p"] = _p(sim, "ruth")
	return g


func _put(p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.path = []
	p.goal_key = ""
	p.moving = false


## Ruth stands `off` from the marker of this problem.
func _stand_by(g: Dictionary, id: String, off: Vector2 = Vector2(-1.0, 0.0)) -> void:
	_put(g.p, Vector2(g.sim.problems.record(id).at) + off)


## Two people at odds (a rift, so the pair scores high): the quarrel can be raised for them.
func _rift(sim, a: String, b: String) -> void:
	sim.relations.add(_p(sim, a), _p(sim, b), -45.0, "test")


func _events(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e.get("type", "")) == type:
			out.append(e)
	return out


func _news(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == kind:
			out.append(e)
	return out


func _step(sim, seconds: float) -> void:
	for i in int(seconds / DT):
		sim.problems.update(DT)


## The module's own steps only (the people stand where they are put), until the avatar's hands are done or `limit` seconds.
func _hands(sim, limit: float = 30.0) -> void:
	var n := 0
	while not sim.problems.fixing.is_empty() and n < int(limit / DT):
		sim.problems.update(DT)
		n += 1


## Raises and clears a problem at every half hour of the days 3 to 10 (the schedule alone: the looks, no stepping): ["p1:crack:3:8.5", ...].
func _month(g: Dictionary) -> Array:
	var sim = g.sim
	var out: Array = []
	sim.problems.next_at = 0.0
	for d in range(3, 11):
		for half in 48:
			Helpers.at(sim, d, float(half) * 0.5)
			sim.problems.look()
			for r in sim.problems.records:
				out.append("%s:%s:%d:%s" % [r.id, r.kind, d, str(float(half) * 0.5)])
			sim.problems.records.clear()    # (fixed at once: only the schedule is looked at)
		sim.radio.news.clear()
	return out


# -------------------------------------------------------------- the tests --
## Six tests, each running the cases of one part (a case is a `_` method below with its own game).

func test_the_schedule() -> void:
	_rate()
	_deterministic()


func test_each_kind_does_its_harm_and_its_end() -> void:
	_leak()
	_jam()
	_quarrel_effects()
	_crack()


func test_the_avatar_fixes_it_with_its_own_hands() -> void:
	_e_fix()
	_quarrel_outcomes()


func test_the_radio_asks_and_the_dice_decide() -> void:
	_asks()
	_delegate()


func test_escalation_and_the_calls() -> void:
	_stage_two()
	_past_its_time()


func test_save_load_and_neutrality() -> void:
	_save_and_neutral()


# ----------------------------------------------------------------- the rate --

func _rate() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	near(pr.gap_h(3), 36.0, 1.0e-9, "day 3: a day and a half")
	near(pr.gap_h(8), 30.0, 1.0e-9, "day 8")
	near(pr.gap_h(18), 18.0, 1.0e-9, "day 18: one a day")
	near(pr.gap_h(60), 18.0, 1.0e-9, "never under 18 hours")
	near(pr.gap_h(1), 36.0, 1.0e-9, "nor over 36")
	pr.next_at = 0.0
	Helpers.at(sim, 2, 9.0)
	check(not pr.allowed_now(), "none before day 3")
	Helpers.at(sim, 3, 9.0)
	check(pr.allowed_now(), "day 3, 09:00: one may come")
	var dusk: float = sim.seasons.dusk_hour()
	for h in [3.0, 7.0, 12.0, dusk - 1.5, dusk + 0.2, 22.0]:
		Helpers.at(sim, 3, h)
		check(not pr.allowed_now(), "not at %s (before 07:30, in the radio hour, in the two hours before dusk, at night)" % str(h))
	Helpers.at(sim, 3, dusk - 2.5)
	check(pr.allowed_now(), "and the afternoon is open until two hours before dusk")
	sim.radio.alarm_on = true
	check(not pr.allowed_now(), "never under the alarm")
	sim.radio.alarm_on = false
	var sick: int = sim.radio.raise_call("sick", "Ana is sick", "", [{"id": "x", "label": "x"}], "x", 600.0)
	check(not pr.allowed_now(), "nor with an urgent call open")
	sim.radio.answer(sick, "x")
	sim.radio.raise_call("idea", "An idea", "", [{"id": "x", "label": "x"}], "x", 600.0)
	check(pr.allowed_now(), "an idea waiting is not urgent")
	pr.next_at = float(sim.clock_min) + 100.0
	check(not pr.allowed_now(), "not before the gap is up")
	pr.next_at = 0.0
	check(pr.raise_problem("leak") != "" and pr.raise_problem("jam") != "", "two are raised")
	pr.next_at = 0.0
	check(not pr.allowed_now(), "never more than two open")
	g.world.free()


func _deterministic() -> void:
	var a := _game(11)
	var b := _game(11)
	var rng_before: int = a.sim.rng.state
	var month: Array = _month(a)
	eq(a.sim.rng.state, rng_before, "no draw of the rules' dice")
	eq(_month(b), month, "the same seed gives the same problems at the same half hours")
	check(month.size() >= 4 and month.size() <= 8, "about one every day and a half in days 3 to 10 (got %d)" % month.size())
	var dusk: float = a.sim.seasons.dusk_hour()
	for line in month:
		var parts: PackedStringArray = String(line).split(":")
		var h := float(parts[3])
		check(h >= 7.5 and h <= dusk - 2.0 and not (h >= 11.5 and h <= 12.5), "%s is raised in the working day" % line)
		check(int(parts[2]) >= 3, "%s: not before day 3" % line)
	var kinds := {}
	for line in month:
		kinds[String(line).split(":")[1]] = true
	check(kinds.size() >= 2, "the rotation brings more than one kind")
	a.world.free()
	b.world.free()


# --------------------------------------------------------------- the effects --

func _leak() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	var id: String = pr.raise_problem("leak")
	check(id != "", "a leak is raised")
	eq(pr.marks().size(), 1, "one marker")
	eq(String(pr.marks()[0].kind), "leak", "of the leak")
	check(String(pr.marks()[0].label).begins_with("Leak: "), "labelled with its time: %s" % pr.marks()[0].label)
	_step(sim, 20.0)
	near(sim.stock.water, 100.0 - 0.6, 0.01, "an hour of the leak: 0.6 of the water")
	sim.stock.water = 0.3
	_step(sim, 20.0)
	near(sim.stock.water, 0.0, 1.0e-9, "the stock never goes under nothing")
	sim.stock.water = 100.0
	_stand_by(g, id)
	check(sim.interact.use({"kind": "problem", "id": id}).ok, "Ruth starts on it")
	_hands(sim)
	check(not pr.has_open("leak"), "fixed")
	sim.stock.water = 100.0    # (it drained while she worked)
	_step(sim, 20.0)
	near(sim.stock.water, 100.0, 1.0e-9, "and the water stays")
	g.world.free()


func _jam() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	var dez = _p(sim, "dez")
	check(Helpers.seat(sim, dez, "bench"), "Dez is at the bench")
	sim.stock.ammo = 50.0
	sim.stock.scrap = 40.0
	Helpers.run(sim, 4.0)
	check(sim.stock.ammo > 50.0, "the bench makes ammo")
	check(not pr.blocks("bench") and not pr.blocks("floodlights"), "nothing is blocked")
	check(pr.raise_problem("jam") != "", "the generator jams")
	check(pr.blocks("bench"), "the bench is blocked")
	check(not pr.blocks("floodlights"), "the floodlights are not built, so nothing of them is blocked")
	check(String(sim.workshop.why_not_hand_craft(g.p)).contains("generator"), "and Ruth's own hands are told why: %s" % sim.workshop.why_not_hand_craft(g.p))
	sim.stock.ammo = 50.0
	sim.stock.scrap = 40.0
	Helpers.run(sim, 4.0)
	near(sim.stock.ammo, 50.0, 1.0e-9, "no ammo is made while it is jammed")
	var pl: Dictionary = sim.build.plot("floodlights_home")
	pl.building = "floodlights"
	sim.build.version += 1
	check(pr.blocks("floodlights"), "with floodlights built they are dark")
	near(sim.build.factor("night_reach_mult"), 1.0, 1.0e-9, "no extra reach by night")
	pr.records.clear()
	near(sim.build.factor("night_reach_mult"), 1.12, 1.0e-9, "mended, the lamps give their reach again")
	g.world.free()


func _quarrel_effects() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	check(pr.quarrel_pair().is_empty(), "nobody is at odds yet")
	_rift(sim, "dez", "walt")
	var pair: Array = pr.quarrel_pair()
	eq(pair.size(), 2, "now a pair is")
	var id: String = pr.raise_problem("quarrel")
	check(id != "", "the quarrel is raised")
	var ids: Array = pr.record(id).ids
	check(ids.has("dez") and ids.has("walt"), "for Dez and Walt")
	var dez = _p(sim, "dez")
	var ana = _p(sim, "ana")
	near(pr.perf_mult(dez), 0.85, 1.0e-9, "Dez works at 85%")
	near(pr.perf_mult(ana), 1.0, 1.0e-9, "Ana is not in it")
	var lines: Array = pr.mood_lines(dez)
	eq(lines.size(), 1, "one standing line")
	eq(String(lines[0].label), "Quarrel with Walt", "naming the other")
	near(float(lines[0].value), -3.0, 1.0e-9, "of -3")
	var seen := false
	for m in sim.morale._modifiers(dez):
		if String(m.label) == "Quarrel with Walt":
			seen = true
	check(seen, "morale's list carries it")
	check(sim.perf(dez) < sim.perf(ana) + 1.0e-9, "sim.perf carries the 85%")
	var before: float = sim.relations.affinity(dez, _p(sim, "walt"))
	pr.look()
	check(sim.relations.affinity(dez, _p(sim, "walt")) < before, "and each look they drift further apart")
	g.world.free()


func _crack() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	var id: String = pr.raise_problem("crack")
	check(id != "", "a crack is raised")
	var rec: Dictionary = pr.record(id)
	var seg = null
	for s in sim.segments:
		if int(s.id) == int(rec.seg):
			seg = s
	check(seg != null and String(seg.kind) != "door" and String(seg.kind) != "gate" and int(seg.id) < 100, "in a plain section of the compound wall")
	var full: float = seg.max_hp
	check(is_equal_approx(seg.hp, full), "the wall was whole")
	_step(sim, 20.0)
	near(seg.hp, full * (1.0 - 0.015), full * 0.0005, "an hour takes 1.5% of its strength")
	seg.hp = full * 0.26
	_step(sim, 40.0)
	near(seg.hp, full * 0.25, full * 0.0005, "never under a quarter")
	seg.hp = full
	_stand_by(g, id)
	check(sim.interact.use({"kind": "problem", "id": id}).ok, "Ruth shores it up")
	_hands(sim)
	check(not pr.has_open("crack"), "done")
	seg.hp = full    # (it widened while she worked)
	_step(sim, 20.0)
	near(seg.hp, full, 1.0e-6, "it stops widening")
	g.world.free()


# ---------------------------------------------------------- in person (E) --

func _e_fix() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	var id: String = pr.raise_problem("leak")
	_stand_by(g, id, Vector2(-3.0, 0.0))
	eq(pr.candidates().size(), 0, "three tiles off: nothing to use")
	_stand_by(g, id)
	var c: Array = pr.candidates()
	eq(c.size(), 1, "within reach: one thing")
	eq(String(c[0].label), "Fix the leak", "the prompt")
	check(bool(c[0].ok), "that can be used")
	check(String(sim.interact.best().kind) == "problem", "interact lists it first")
	sim.stock.scrap = 0.0
	check(not pr.candidates()[0].ok and String(pr.candidates()[0].why) == "needs 1 scrap", "no scrap: the reason is said")
	sim.stock.scrap = 20.0
	Helpers.at(sim, 3, 21.0)
	eq(String(pr.candidates()[0].why), "it is night", "at night: the reason is said")
	Helpers.at(sim, 3, 9.0)
	# the time depends on the skill
	g.p.skills["Building"] = 3
	var r1: Dictionary = sim.interact.use({"kind": "problem", "id": id})
	check(r1.ok, "E starts it")
	var slow: float = float(pr.fixing.total)
	check(float(r1.seconds) > 0.0 and is_equal_approx(float(r1.seconds), slow), "and says how long")
	eq(String(g.p.work), "hammer", "the hammer pose")
	check(String(pr.candidates()[0].label).begins_with("Stop"), "E again would stop it")
	check(sim.interact.use({"kind": "problem", "id": id}).has("stopped"), "E again stops it")
	check(pr.fixing.is_empty(), "nothing in hand")
	g.p.skills["Building"] = 9
	sim.interact.use({"kind": "problem", "id": id})
	var quick: float = float(pr.fixing.total)
	near(slow / quick, (0.7 + 0.08 * 9.0) / (0.7 + 0.08 * 3.0), 0.02, "Building 9 is faster than Building 3 by the speeds")
	# moving ends it, and nothing is paid
	var scrap: float = sim.stock.scrap
	_step(sim, 1.0)
	g.p.input_move = Vector2(1.0, 0.0)
	pr.update(DT)
	g.p.input_move = Vector2.ZERO
	check(pr.fixing.is_empty(), "walking away stops it")
	check(pr.has_open("leak"), "the leak is still there")
	near(sim.stock.scrap, scrap, 1.0e-9, "no scrap was paid")
	var off: Array = _events(sim, "fix_work")
	check(not off.is_empty() and not bool(off[off.size() - 1].on) and String(off[off.size() - 1].why) == "moved", "the end is told: moved")
	# the whole of it
	check(sim.interact.use({"kind": "problem", "id": id}).ok, "again")
	_hands(sim)
	check(not pr.has_open("leak"), "it is fixed")
	near(sim.stock.scrap, scrap - 1.0, 1.0e-9, "one scrap was paid")
	var line := ""
	for e in _news(sim, "problem"):
		if String(e.text).begins_with("Fixed"):
			line = String(e.text)
	eq(line, "Fixed: the leak (Ruth)", "the News says who")
	check(not _events(sim, "problem").filter(func(e): return String(e.state) == "fixed").is_empty(), "a problem event")
	g.world.free()


func _quarrel_outcomes() -> void:
	# Leading 9 and warm trust: settled, and they are closer
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	_rift(sim, "dez", "walt")
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	_put(dez, Vector2(40.0, 30.0))
	_put(walt, Vector2(41.0, 30.0))
	var id: String = pr.raise_problem("quarrel")
	check(id != "", "raised")
	_put(g.p, Vector2(40.5, 31.0))
	eq(String(pr.candidates()[0].label), "Hear them out", "the prompt")
	g.p.skills["Leading"] = 9
	dez.trust = 55.0
	walt.trust = 55.0
	var before: float = sim.relations.affinity(dez, walt)
	check(sim.interact.use({"kind": "problem", "id": id}).ok, "Ruth hears them out")
	eq(String(g.p.work), "", "no hammer for a talk")
	_hands(sim)
	check(not pr.has_open("quarrel"), "settled")
	check(sim.relations.affinity(dez, walt) > before + 3.0, "and they are closer (+4)")
	# Leading 3: they keep apart
	var g2 := _game()
	var sim2 = g2.sim
	_rift(sim2, "dez", "walt")
	_put(_p(sim2, "dez"), Vector2(40.0, 30.0))
	_put(_p(sim2, "walt"), Vector2(41.0, 30.0))
	sim2.jobs.assignments["dez"] = "garden"
	sim2.jobs.assignments["walt"] = "garden"
	var id2: String = sim2.problems.raise_problem("quarrel")
	_put(g2.p, Vector2(40.5, 31.0))
	g2.p.skills["Leading"] = 3
	var aff2: float = sim2.relations.affinity(_p(sim2, "dez"), _p(sim2, "walt"))
	check(sim2.interact.use({"kind": "problem", "id": id2}).ok, "again")
	_hands(sim2)
	check(not sim2.problems.has_open("quarrel"), "ended")
	var apart_line := ""
	for e in _news(sim2, "problem"):
		if String(e.text).begins_with("Kept apart"):
			apart_line = String(e.text)
	check(apart_line != "", "they keep apart: %s" % apart_line)
	near(sim2.relations.affinity(_p(sim2, "dez"), _p(sim2, "walt")), aff2, 1.0e-9, "with no gain between them")
	var moved: bool = sim2.jobs.job_of(_p(sim2, "walt")) != "garden" or sim2.jobs.job_of(_p(sim2, "dez")) != "garden"
	check(moved or String(sim2.jobs.post_ids.get("walt", "")) != String(sim2.jobs.post_ids.get("dez", "")), "one of them was moved")
	# Leading 0 and cold trust: no luck, six more hours, and their trust falls
	var g3 := _game()
	var sim3 = g3.sim
	_rift(sim3, "dez", "walt")
	_put(_p(sim3, "dez"), Vector2(40.0, 30.0))
	_put(_p(sim3, "walt"), Vector2(41.0, 30.0))
	var id3: String = sim3.problems.raise_problem("quarrel")
	_put(g3.p, Vector2(40.5, 31.0))
	g3.p.skills["Leading"] = 0
	_p(sim3, "dez").trust = 20.0
	_p(sim3, "walt").trust = 20.0
	var ttl: float = float(sim3.problems.record(id3).ttl_h)
	check(sim3.interact.use({"kind": "problem", "id": id3}).ok, "a third time")
	_hands(sim3)
	check(sim3.problems.has_open("quarrel"), "it did not work")
	near(float(sim3.problems.record(id3).ttl_h), ttl + 6.0, 1.0e-9, "they have six more hours")
	near(_p(sim3, "dez").trust, 19.0, 1.0e-9, "and trust is down by one")
	g.world.free()
	g2.world.free()
	g3.world.free()


# ----------------------------------------------------------------- by radio --

func _asks() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	var id: String = pr.raise_problem("jam")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	# the player cannot be asked
	var me: Dictionary = pr.fix_willingness(g.p, id)
	check(not me.ok and me.hard, "the player is nobody to ask")
	# the radio's own soft reason, in its own words, and Insist at the usual cost
	dez.bleeding = 1.0
	var w: Dictionary = pr.fix_willingness(dez, id)
	check(not w.ok and not w.hard, "a soft refusal")
	eq(String(w.why), String(sim.radio.reason_not(dez, "work").why), "in the radio's words")
	var r: Dictionary = sim.radio.request_fix(id, dez)
	check(not r.ok and not r.hard, "asked: no")
	eq(String(pr.record(id).fixer), "", "nobody is sent")
	var trust: float = dez.trust
	var pushed: Dictionary = sim.radio.request_fix(id, dez, {"insist": true})
	check(pushed.ok and pushed.insisted, "insisting sends them")
	near(dez.trust, trust - float(sim.radio.INSIST_COST), 1.0e-9, "at the usual cost of trust")
	eq(String(pr.record(id).fixer), "dez", "he is on it")
	dez.bleeding = 0.0
	# a second hand cannot join in
	var second: Dictionary = pr.fix_willingness(_p(sim, "walt"), id)
	check(not second.ok and String(second.why).contains("on it"), "Dez is on it: %s" % second.why)
	pr.records[0].fixer = ""
	pr.records[0].state = "idle"
	# a skill floor: the jam asks for Building 3
	var low: Dictionary = pr.fix_willingness(marcus, id)
	check(not low.ok and low.hard and String(low.why).contains("Building"), "Marcus has no Building: %s" % low.why)
	# the scrap
	sim.stock.scrap = 0.0
	check(String(pr.fix_willingness(dez, id).why) == "needs 1 scrap", "no scrap: refused")
	sim.stock.scrap = 20.0
	# the night
	Helpers.at(sim, 3, 22.0)
	check(not pr.fix_willingness(dez, id).ok, "nobody goes out at night")
	Helpers.at(sim, 3, 9.0)
	# one of a quarrelling pair
	pr.records.clear()
	_rift(sim, "dez", "walt")
	var q: String = pr.raise_problem("quarrel")
	var own: Dictionary = pr.fix_willingness(dez, q)
	check(not own.ok and own.hard, "one of the pair cannot settle their own: %s" % own.why)
	var floor_: Dictionary = pr.fix_willingness(marcus, q)
	check(not floor_.ok and String(floor_.why).contains("Leading"), "Leading 2 is the floor: %s" % floor_.why)
	# a person who can: the answer, the chance, the cost, the delay
	pr.records.clear()
	var jam: String = pr.raise_problem("jam")
	var ok: Dictionary = pr.fix_willingness(dez, jam)
	check(ok.ok, "Dez would go: %s" % ok.why)
	check(float(ok.chance) >= 0.2 and float(ok.chance) <= 0.95, "with a chance %s" % ok.chance)
	eq(int(ok.cost.scrap), 1, "for one scrap")
	check(float(ok.delay_s) >= float(sim.radio.delay_for(dez.trust)) and float(ok.eta_h) > 0.0, "after a delay, for some hours of work")
	check(["willing", "grudging", "doubtful"].has(String(ok.tone)) and String(ok.line) != "", "in a tone's words")
	var walt: Dictionary = pr.fix_willingness(_p(sim, "walt"), jam)
	check(not walt.ok or float(walt.chance) < float(ok.chance), "Dez (Building 9) is the better hand")
	eq(String(pr.best_for(jam).id), "dez", "best_for names him")
	g.world.free()


func _delegate() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	var dez = _p(sim, "dez")
	var id: String = pr.raise_problem("jam")
	Helpers.seat(sim, dez, "bench")
	var scrap: float = sim.stock.scrap
	var a: Dictionary = sim.radio.request_fix(id, dez)
	check(a.ok, "Dez agrees: %s" % a.why)
	eq(String(pr.record(id).state), "walking", "he is on his way")
	eq(String(pr.marks()[0].state), "walking", "and the marker says so")
	near(sim.stock.scrap, scrap, 1.0e-9, "nothing is paid until he starts")
	var seen_working := false
	for i in 1800:
		sim.update(DT)
		if String(pr.record(id).get("state", "")) == "working":
			seen_working = true
			break
	check(seen_working, "he gets there and works")
	near(sim.stock.scrap, scrap - 1.0, 1.0e-9, "the scrap is paid when he starts")
	# the dice: set the chance so that this problem's roll (a pure function of the problem, the person and the run) falls on one side
	var roll: float = pr.fix_roll(id, "dez")
	pr.records[0].chance = minf(1.0, roll + 0.01)
	for i in 1800:
		sim.update(DT)
		if not pr.has_open("jam"):
			break
	check(not pr.has_open("jam"), "roll %s under the chance: it is fixed" % roll)
	var fixed := false
	for e in _news(sim, "problem"):
		if String(e.text) == "Fixed: the generator (Dez)":
			fixed = true
	check(fixed, "the News says Dez did it")
	check(dez.order == null and not dez.drafted, "and he is free again")
	# the other side: failure keeps the problem and the scrap spent, and he is not asked twice
	var id2: String = pr.raise_problem("jam")
	var scrap2: float = sim.stock.scrap
	check(sim.radio.request_fix(id2, dez).ok, "asked again, for the next one")
	for i in 1800:
		sim.update(DT)
		if String(pr.record(id2).get("state", "")) == "working":
			break
	pr.records[0].chance = maxf(0.0, pr.fix_roll(id2, "dez") - 0.01)
	for i in 1800:
		sim.update(DT)
		if String(pr.record(id2).get("state", "")) == "idle":
			break
	check(pr.has_open("jam"), "failed: the jam is still there")
	near(sim.stock.scrap, scrap2 - 1.0, 1.0e-9, "and the scrap stays spent")
	var failed := false
	for e in _news(sim, "problem"):
		if String(e.text) == "Dez could not clear the jam":
			failed = true
	check(failed, "the News says he could not")
	var again: Dictionary = pr.fix_willingness(dez, id2)
	check(not again.ok and String(again.why).contains("already tried"), "he is not asked for it again: %s" % again.why)
	eq(String(pr.record(id2).fixer), "", "nobody is on it")
	# the dice are a pure function of the state
	near(pr.fix_roll("p1", "dez"), pr.fix_roll("p1", "dez"), 0.0, "the same inputs, the same number")
	check(pr.fix_roll("p1", "dez") >= 0.0 and pr.fix_roll("p1", "dez") < 1.0, "between 0 and 1")
	g.world.free()


# --------------------------------------------------------------- escalation --

func _stage_two() -> void:
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	var id: String = pr.raise_problem("jam")
	eq(int(pr.record(id).stage), 1, "it begins at stage 1")
	Helpers.at(sim, 3, 9.0 + 5.0)    # (the jam waits 12 hours: 5 is under half)
	pr.look()
	eq(int(pr.record(id).stage), 1, "still stage 1 before the halfway mark")
	Helpers.at(sim, 3, 9.0 + 7.0)
	pr.look()
	eq(int(pr.record(id).stage), 2, "past the halfway mark: stage 2")
	pr.look()
	var calls: Array = []
	for e in sim.radio.open_calls():
		if String(e.kind) == "problem":
			calls.append(e)
	eq(calls.size(), 1, "one call, and only one")
	var labels: Array = []
	for o in calls[0].options:
		labels.append(String(o.label))
	check(String(labels[0]).begins_with("Send Dez ("), "it offers the best hand: %s" % str(labels))
	eq(String(calls[0].default), "leave", "the default is to leave it")
	check(not _events(sim, "problem").filter(func(e): return String(e.state) == "stage2").is_empty(), "a stage2 event")
	check(sim.radio.answer(int(calls[0].id), "send"), "Send")
	eq(String(pr.record(id).fixer), "dez", "Dez is sent")
	g.world.free()


func _past_its_time() -> void:
	# a leak: twice the drain and 8 water, once
	var g := _game()
	var sim = g.sim
	var pr = sim.problems
	var id: String = pr.raise_problem("leak")
	sim.stock.water = 100.0
	Helpers.at(sim, 4, 4.0)    # (19 hours later: the leak waits 18)
	pr.look()
	check(bool(pr.record(id).late), "escalated")
	near(sim.stock.water, 92.0, 1.0e-9, "water -8 once")
	pr.look()
	near(sim.stock.water, 92.0, 1.0e-9, "and only once")
	_step(sim, 20.0)
	near(sim.stock.water, 92.0 - 1.2, 0.02, "the drain is doubled")
	check(pr.has_open("leak"), "it stays open")
	check(not _events(sim, "problem").filter(func(e): return String(e.state) == "escalated").is_empty(), "an escalated event")
	# a jam: wrecked, 3 scrap, double time, "No power" for everyone
	pr.records.clear()
	Helpers.at(sim, 3, 9.0)
	var jam: String = pr.raise_problem("jam")
	var fresh: float = pr._work_s(g.p, pr.records[0])
	Helpers.at(sim, 3, 22.0)
	pr.look()
	var rec: Dictionary = pr.record(jam)
	check(bool(rec.late) and int(rec.cost.scrap) == 3, "wrecked: it takes 3 scrap")
	near(pr._work_s(g.p, pr.records[0]) / fresh, 2.0, 1.0e-6, "and twice the time")
	var power := false
	for e in sim.morale.shocks.get("dez", []):
		if String(e.label) == "No power":
			power = true
	check(power, "everyone's mood takes the blow")
	# a crack: a fifth of the wall's strength
	pr.records.clear()
	Helpers.at(sim, 3, 9.0)
	var crack: String = pr.raise_problem("crack")
	var seg = null
	for s in sim.segments:
		if int(s.id) == int(pr.record(crack).seg):
			seg = s
	var full: float = seg.max_hp
	Helpers.at(sim, 3, 23.5)
	pr.look()
	near(seg.hp, full * 0.8, full * 0.001, "it lost a fifth")
	check(pr.has_open("crack"), "and stays open")
	# a quarrel: rivals, and a blow to each
	pr.records.clear()
	Helpers.at(sim, 3, 9.0)
	_rift(sim, "ana", "marcus")
	var q: String = pr.raise_problem("quarrel")
	check(q != "", "a quarrel")
	var ana = _p(sim, "ana")
	var marcus = _p(sim, "marcus")
	var aff: float = sim.relations.affinity(ana, marcus)
	Helpers.at(sim, 4, 10.0)
	pr.look()
	check(sim.relations.affinity(ana, marcus) <= aff - 6.0, "rivals now: -6 at least")
	var blow := false
	for e in sim.morale.shocks.get("ana", []):
		if float(e.value) <= -5.0:
			blow = true
	check(blow, "and -5 of mood")
	check(pr.has_open("quarrel"), "still open")
	# keeping them apart ends it with no gain
	var aff2: float = sim.relations.affinity(ana, marcus)
	var s: Dictionary = pr.separate(q)
	check(s.ok, "separate: %s" % s.why)
	check(not pr.has_open("quarrel"), "ended")
	near(sim.relations.affinity(ana, marcus), aff2, 1.0e-9, "no gain")
	g.world.free()


# ------------------------------------------------------------ save and neutral --

func _save_and_neutral() -> void:
	var a := _game()
	var sim = a.sim
	var pr = sim.problems
	var leak: String = pr.raise_problem("leak")
	var crack: String = pr.raise_problem("crack")
	check(leak != "" and crack != "", "two open")
	pr.records[0].stage = 2
	pr.records[0].tried = ["dez"]
	var d := SaveGame.to_dict(sim)
	check(d.modules.has("problems"), "the module is part of the save")
	var b := Helpers.make(7, 1, 5)
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads")
	var pb = b.sim.problems
	eq(pb.records.size(), 2, "both are back")
	eq(String(pb.records[0].id), leak, "the same ids")
	eq(int(pb.records[0].stage), 2, "the stage")
	eq(pb.records[0].tried, ["dez"], "who has tried")
	check(Vector2(pb.records[1].at).distance_to(Vector2(pr.records[1].at)) < 1.0e-6, "the place")
	eq(pb.count, pr.count, "the count")
	check(pb.fixing.is_empty(), "no hands in progress")
	eq(String(pb.pick_kind()), String(pr.pick_kind()), "and the rotation goes on the same")
	# a delegate at work is still at work after a load, and finishes
	var c := _game()
	var cp = c.sim.problems
	var jam: String = cp.raise_problem("jam")
	Helpers.seat(c.sim, _p(c.sim, "dez"), "bench")
	check(c.sim.radio.request_fix(jam, _p(c.sim, "dez")).ok, "Dez is sent")
	for i in 1800:
		c.sim.update(DT)
		if String(cp.record(jam).get("state", "")) == "working":
			break
	eq(String(cp.record(jam).state), "working", "he is at work")
	var mid := SaveGame.to_dict(c.sim)
	var e2 := Helpers.make(7, 1, 5)
	check(SaveGame.apply(e2.sim, SaveGame.from_text(SaveGame.to_text(mid))), "a save in the middle of it loads")
	var ep = e2.sim.problems
	eq(String(ep.record(jam).state), "working", "still at work")
	eq(String(ep.record(jam).fixer), "dez", "Dez")
	ep.records[0].chance = 1.0
	for i in 900:
		e2.sim.update(DT)
		if not ep.has_open("jam"):
			break
	check(not ep.has_open("jam"), "and it is done")
	check(_p(e2.sim, "dez").order == null and not _p(e2.sim, "dez").drafted, "with Dez free again")
	c.world.free()
	e2.world.free()
	# a save from before is a fresh module; a damaged one loads clean
	var old := Helpers.make(7, 1, 5)
	var d2 := SaveGame.to_dict(sim)
	d2.modules.erase("problems")
	check(SaveGame.apply(old.sim, d2), "a save from before loads")
	eq(old.sim.problems.records.size(), 0, "with nothing open")
	var bad := Helpers.make(7, 1, 5)
	var d3 := SaveGame.to_dict(sim)
	d3.modules["problems"] = {"records": [5, {"kind": "nope"}, {"id": "p1", "kind": "crack", "seg": 99, "at": [1, 2], "t0": 0.0}, {"id": "p2", "kind": "quarrel", "ids": ["dez", "ghost"], "at": [1, 2]},
		{"id": "p3", "kind": "leak", "at": [-50.0, 1.0e9], "t0": -4.0, "ttl_h": 1.0e9, "stage": 7, "fixer": "ghost", "state": "walking", "cost": {"scrap": 1.0e9}}], "count": -5, "next_at": "soon", "recent": ["x", "leak", "leak", "leak"]}
	check(SaveGame.apply(bad.sim, d3), "a damaged one loads")
	var rows: Array = bad.sim.problems.records
	eq(rows.size(), 1, "only the sound record is kept")
	check(String(rows[0].id) == "p3" and int(rows[0].stage) == 2 and float(rows[0].ttl_h) <= 400.0 and String(rows[0].fixer) == "", "clamped and cleaned")
	check(Vector2(rows[0].at).x >= 0.0 and Vector2(rows[0].at).y <= float(bad.sim.H), "the place is on the map")
	check(bad.sim.problems.count >= 3 and bad.sim.problems.recent.size() <= 2, "the count follows the ids")
	# no avatar: every hook is neutral and nothing happens
	var n := Helpers.make(7, 1, 5)
	var ns = n.sim
	var np = ns.problems
	check(not np.active(), "no avatar: not active")
	eq(np.raise_problem("leak"), "", "nothing can be raised")
	eq(np.marks(), [], "no marks")
	eq(np.candidates(), [], "nothing to use")
	eq(np.open(), [], "nothing open")
	check(not np.blocks("bench") and not np.blocks("floodlights") and not np.has_open("quarrel") and not np.allowed_now(), "nothing blocked, nothing allowed")
	near(np.perf_mult(ns.people[0]), 1.0, 0.0, "x1.0")
	eq(np.mood_lines(ns.people[0]), [], "no mood lines")
	Helpers.at(ns, 4, 9.0)
	np.next_at = 0.0
	Helpers.run(ns, 3.0)
	np.look()
	eq(np.records.size(), 0, "stepping raises nothing")
	check(np.count == 0 and not np.has_open("leak"), "no count")
	# the module never touches the rules' dice, with an avatar either
	var rng2: int = sim.rng.state
	pr.next_at = 0.0
	for i in 1200:
		pr.update(DT)
	pr.raise_problem("jam")
	pr.request_fix(pr.records[pr.records.size() - 1].id, _p(sim, "dez"))
	pr.best_for(leak)
	pr.separate("p99")
	pr.look()
	eq(sim.rng.state, rng2, "no draw from the rules' dice")
	a.world.free()
	b.world.free()
	old.world.free()
	bad.world.free()
	n.world.free()
