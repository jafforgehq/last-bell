extends "res://tests/case.gd"
## The fever outbreak, the one hard choice of the base (round 25, scripts/sim/dilemmas.gd, S25.4 of the round's plan): when it is raised, what
## treating and quarantining each do in the base, the default after the timer, the spread and the risk that follow the player's own dials, the
## medic's opinion, saves. The relations and specialists modules are the fakes of tests/initiative_kit.gd; the problems module is a fake with the
## one thing the dilemma reads of it (an open leak); the policies module is the real one with its `current` and `weary` set by hand.

const Kit := preload("res://tests/initiative_kit.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


## The problems module as far as the dilemma reads it.
class FakeProblems:
	extends RefCounted
	var leak := false

	func has_open(kind) -> bool:
		return leak and String(kind) == "leak"


## A settlement game with an avatar (Ruth, Dez, Marcus, Ana, Walt) at 09:00 on day 4 with the storyteller's fevers switched on (a fever is the
## storyteller's: nothing is sick while it is off), nobody near anybody, plenty of everything but what a test sets.
func _game(crew: int = 5) -> Dictionary:
	var g := Kit.game(crew)
	var sim = g.sim
	sim.storyteller.enabled = true
	Kit.at(sim, 4, 9.0)
	var i := 0
	for p in sim.people:
		p.x = 50.0 + float(i) * 8.0    # (eight tiles apart: out of each other's reach)
		p.y = 20.0
		i += 1
	sim.events.clear()
	sim.radio.news.clear()
	return g


func _free(g: Dictionary) -> void:
	g.world.free()


func _p(sim, id: String):
	return Kit.who(sim, id)


## A passing fever on this person (the storyteller's own record of it), `hours` long.
func _sick(sim, id: String, hours: float = 20.0) -> void:
	sim.storyteller.sick[id] = float(sim.clock_min) + hours * 60.0


## The open calls of this kind.
func _calls(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.open_calls():
		if String(e.kind) == kind:
			out.append(e)
	return out


## The News lines of this kind whose text has this in it.
func _lines(sim, kind: String, part: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == kind and String(e.text).find(part) >= 0:
			out.append(e)
	return out


## Raises the dilemma for Dez and Marcus with `meds` in the stores; the entry of the call.
func _outbreak(sim, meds: float) -> Dictionary:
	sim.stock.meds = meds
	_sick(sim, "dez")
	_sick(sim, "marcus")
	var id: int = sim.dilemmas.raise()
	return sim.radio._entry(id)


## The value of a reason on a person's mood list, 0.0 when it is not there.
func _mood(sim, p, label: String) -> float:
	for m in sim.morale.explain(p):
		if String(m.label) == label:
			return float(m.value)
	return 0.0


# ------------------------------------------------------------------ neutral --

func test_nothing_runs_without_an_avatar_or_when_switched_off() -> void:
	for how in ["no avatar", "switched off", "classic start"]:
		var g := _game(6 if how == "classic start" else 5)
		var sim = g.sim
		_sick(sim, "dez")
		_sick(sim, "marcus")
		if how == "no avatar":
			sim.avatar.set_player(null)
		elif how == "switched off":
			sim.dilemmas.enabled = false
		check(not sim.dilemmas.active(), "%s: not active" % how)
		eq(sim.dilemmas.trigger(), {}, "%s: no trigger" % how)
		check(not sim.dilemmas.claims(_p(sim, "dez")), "%s: no claim" % how)
		eq(sim.dilemmas.raise(), 0, "%s: no call" % how)
		eq(sim.dilemmas.marks(), [], "%s: no sign" % how)
		eq(sim.dilemmas.opinion({"data": {"patients": ["dez"]}}), {}, "%s: no opinion" % how)
		eq(sim.dilemmas.risk_rate(), 0.0, "%s: no risk" % how)
		var state: int = sim.rng.state
		var before: Dictionary = sim.dilemmas.save()
		for i in 40:
			sim.dilemmas.update(10.0)
		eq(sim.dilemmas.save(), before, "%s: nothing moved" % how)
		eq(sim.radio.news.size(), 0, "%s: the radio heard nothing" % how)
		eq(sim.rng.state, state, "%s: and no die was thrown" % how)
		_free(g)


# ------------------------------------------------------------ the trigger and the call --

func test_the_trigger_the_claim_and_the_call() -> void:
	_trigger_sides()
	_claims_keep_the_plain_call_away()
	_call_shape()
	_call_schedule()


func _trigger_sides() -> void:
	var g := _game()
	var sim = g.sim
	eq(sim.dilemmas.trigger(), {}, "nobody is sick: nothing")
	_sick(sim, "dez")
	sim.stock.meds = 3.9
	var t: Dictionary = sim.dilemmas.trigger()
	eq(t.get("patients", []), ["dez"], "one fever and the medicine under what it costs plus three: a dilemma")
	near(float(t.get("need", 0.0)), 1.0, 0.001, "treating costs one")
	near(float(t.get("meds", 0.0)), 3.9, 0.001, "of the stores' 3.9")
	sim.stock.meds = 4.0
	eq(sim.dilemmas.trigger(), {}, "with the medicine to spare: the plain call goes on")
	_sick(sim, "marcus")
	eq(sim.dilemmas.trigger().get("patients", []), ["dez", "marcus"], "two at once is one even with plenty")
	sim.medical.keep_apart(_p(sim, "dez"))
	eq(sim.dilemmas.trigger(), {}, "one of them already apart: one fever and the stores to spare")
	_sick(sim, "ruth")
	_sick(sim, "ana")
	eq(sim.dilemmas.trigger().get("patients", []), ["marcus", "ana"] if sim.people.find(_p(sim, "marcus")) < sim.people.find(_p(sim, "ana")) else ["ana", "marcus"], "the leader is never one of them")
	_p(sim, "ana").infected_at = float(sim.clock_min)
	sim.stock.meds = 3.0
	eq(sim.dilemmas.trigger().get("patients", []), ["marcus"], "nor one who is infected (a bite has its own call)")
	_free(g)


func _claims_keep_the_plain_call_away() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.meds = 6.0
	_sick(sim, "dez")
	_sick(sim, "marcus")
	check(sim.dilemmas.claims(_p(sim, "dez")), "claimed: the call can be raised now")
	sim.radio.update(1.0 / 30.0)
	eq(_calls(sim, "sick").size(), 0, "no plain fever call")
	Kit.at(sim, 3, 9.0)
	check(not sim.dilemmas.claims(_p(sim, "dez")), "before the first day there is no dilemma")
	sim.radio.update(1.0 / 30.0)
	eq(_calls(sim, "sick").size(), 2, "the plain call goes on as it did")
	var h := _game()
	var s2 = h.sim
	s2.stock.meds = 6.0
	_sick(s2, "dez")
	_sick(s2, "marcus")
	s2.radio.alarm_on = true
	check(not s2.dilemmas.claims(_p(s2, "dez")), "under the alarm: the plain call, not the dilemma")
	_free(g)
	_free(h)


func _call_shape() -> void:
	var g := _game()
	var sim = g.sim
	var ideas_before: bool = sim.initiative.allowed_now()
	var e := _outbreak(sim, 5.0)
	check(not e.is_empty(), "raised")
	eq(String(e.kind), "dilemma", "a dilemma call")
	eq(String(e.text), "Fever in the camp: Dez and Marcus", "who")
	eq(String(e.sub), "Medicine: 5. Treating both costs 2.", "the stores and the price")
	eq(String(e.default), "quarantine", "the default is the quarantine")
	near(float(e.due), float(sim.clock_min) + sim.dilemmas.TTL_MIN, 0.001, "with its time")
	var labels := {}
	for o in e.options:
		labels[String(o.id)] = String(o.label)
	eq(labels.get("treat", ""), "Treat both: 2 medicine (5 in the stores)", "treating says what it costs")
	check(String(labels.get("quarantine", "")).begins_with("Quarantine: apart for 2 days"), "quarantine says how long: %s" % labels.get("quarantine", ""))
	var urgent := false
	for ev in sim.events:
		if ev.get("type", "") == "call_raised" and bool(ev.get("urgent", false)):
			urgent = true
	check(urgent, "an urgent call: the game drops to 1x")
	check(ideas_before and not sim.initiative.allowed_now(), "the ideas wait while it is open")
	eq(sim.dilemmas.raise(), 0, "one at a time")
	sim.radio.answer(int(e.id), "treat")
	_sick(sim, "walt")
	_sick(sim, "ana")
	eq(sim.dilemmas.raise(), 0, "and not again before the gap is over")
	Kit.at(sim, 4 + sim.dilemmas.GAP_DAYS, 9.0)
	_sick(sim, "walt")
	_sick(sim, "ana")
	check(sim.dilemmas.raise() > 0, "after it, again")
	_free(g)


func _call_schedule() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.meds = 5.0
	_sick(sim, "dez")
	_sick(sim, "marcus")
	Kit.at(sim, 4, 22.0)
	eq(sim.dilemmas.look(), 0, "not at night")
	Kit.at(sim, 4, 9.0)
	var wall: int = sim.radio.raise_call("attack", "North wall under attack", "", [{"id": "hold", "label": "Hold"}], "hold", 30.0, {"seg": 1}, null)
	eq(sim.dilemmas.look(), 0, "not on top of an attack")
	sim.radio.answer(wall, "hold")
	var idea: int = sim.radio.raise_call("idea", "Dez: an idea", "", [{"id": "yes", "label": "Yes"}], "yes", 60.0, {}, null)
	check(idea > 0 and sim.dilemmas.look() > 0, "an idea may wait")
	_free(g)


# --------------------------------------------------------------------- the answers --

func test_treat_does_what_it_says() -> void:
	_treat_all()
	_treat_some()
	_treat_none()


func test_quarantine_and_the_default_do_what_they_say() -> void:
	_quarantine_does()
	_quarantine_ends()
	_default_after_timer()
	_stale_call_closed()


func _treat_all() -> void:
	var g := _game()
	var sim = g.sim
	var e := _outbreak(sim, 5.0)
	sim.radio.answer(int(e.id), "treat")
	near(float(sim.stock.meds), 3.0, 0.001, "two medicine spent")
	check(not sim.storyteller.is_sick(_p(sim, "dez")) and not sim.storyteller.is_sick(_p(sim, "marcus")), "both fevers have broken")
	eq(sim.dilemmas.closed, {}, "nobody is apart")
	eq(sim.dilemmas.marks(), [], "no sign")
	check(String(sim.radio._entry(int(e.id)).result).begins_with("Dez and Marcus treated (2 medicine)"), "the line: %s" % sim.radio._entry(int(e.id)).result)
	near(_mood(sim, _p(sim, "walt"), "They were treated"), 1.0, 0.001, "the camp is a little lifted")
	eq(sim.dilemmas.look(), 0, "and it is over: nothing is raised")
	_free(g)


func _treat_some() -> void:
	var g := _game()
	var sim = g.sim
	var e := _outbreak(sim, 1.5)
	check(String(e.sub).find("the stores cover 1 of 2") >= 0, "the call says the stores will not cover both: %s" % e.sub)
	sim.radio.answer(int(e.id), "treat")
	near(float(sim.stock.meds), 0.5, 0.001, "one medicine spent")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	check(sim.storyteller.is_sick(dez) != sim.storyteller.is_sick(marcus), "one of them is treated and the other is not")
	var left = dez if sim.storyteller.is_sick(dez) else marcus
	check(sim.medical.is_apart(left), "the one it could not reach is kept apart")
	eq(sim.dilemmas.closed.ids, [String(left.id)], "and it is a quarantine of one")
	check(String(sim.radio._entry(int(e.id)).result).find("kept apart") >= 0, "the line says so: %s" % sim.radio._entry(int(e.id)).result)
	_free(g)


func _treat_none() -> void:
	var g := _game()
	var sim = g.sim
	for p in sim.people:
		p.skills["Medicine"] = 0
	var e := _outbreak(sim, 8.0)
	check(String(e.options[0].label).find("nobody can") >= 0, "the label says it cannot be done: %s" % e.options[0].label)
	sim.radio.answer(int(e.id), "treat")
	near(float(sim.stock.meds), 8.0, 0.001, "nothing was spent")
	check(sim.medical.is_apart(_p(sim, "dez")) and sim.medical.is_apart(_p(sim, "marcus")), "both are kept apart instead")
	_free(g)


func _quarantine_does() -> void:
	var g := _game()
	var sim = g.sim
	var e := _outbreak(sim, 5.0)
	var state: int = sim.rng.state
	sim.radio.answer(int(e.id), "quarantine")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	check(sim.medical.is_apart(dez) and sim.medical.is_apart(marcus), "both lie apart")
	var goal = sim.medical.goal_for(dez)
	check(goal != null and String(goal.what) == "Resting apart", "off their work, resting")
	near(float(sim.stock.meds), 5.0, 0.001, "no medicine spent")
	eq(sim.dilemmas.closed.ids, ["dez", "marcus"], "the quarantine holds them")
	near(float(sim.dilemmas.closed.until), float(sim.clock_min) + sim.dilemmas.QUARANTINE_H * 60.0, 0.001, "for two days")
	var marks: Array = sim.dilemmas.marks()
	eq(marks.size(), 1, "one sign")
	eq(String(marks[0].label), "Quarantine: 2 days", "its words")
	eq(String(marks[0].kind), "quarantine", "its kind")
	check(Vector2(marks[0].at).distance_to(sim.medical.apart_spot(dez)) < 0.01, "over the bunks where they lie")
	near(_mood(sim, dez, "Kept apart"), -4.0, 0.01, "mood: kept apart")
	near(_mood(sim, _p(sim, "walt"), "Fever in the camp"), -2.0, 0.01, "mood: fever in the camp for the rest")
	check(_mood(sim, dez, "Fever in the camp") == 0.0, "(not for the ones apart)")
	# the plain call stays away from them and the lines hold while the quarantine does
	sim.radio.update(1.0 / 30.0)
	eq(_calls(sim, "sick").size(), 0, "no plain call for those held")
	for i in 12:
		sim.morale.update(10.0)    # (half a game hour each: without the look's top-up it would be gone in two)
		sim.dilemmas.look()
	check(_mood(sim, dez, "Kept apart") <= -3.5, "six hours on: still held (%s)" % _mood(sim, dez, "Kept apart"))
	check(_mood(sim, _p(sim, "walt"), "Fever in the camp") <= -1.5, "and the camp's too (%s)" % _mood(sim, _p(sim, "walt"), "Fever in the camp"))
	check(sim.dilemmas.debrief_lines().size() >= 2, "the evening debrief has its lines: %s" % str(sim.dilemmas.debrief_lines()))
	eq(sim.rng.state, state, "and no die was thrown")
	_free(g)


func _quarantine_ends() -> void:
	var g := _game()
	var sim = g.sim
	sim.radio.answer(int(_outbreak(sim, 5.0).id), "quarantine")
	sim.storyteller.sick.erase("dez")
	sim.dilemmas.look()
	eq(sim.dilemmas.closed.ids, ["marcus"], "one is well: one is left")
	sim.storyteller.sick.erase("marcus")
	sim.dilemmas.look()
	eq(sim.dilemmas.closed, {}, "none is sick: it ends")
	eq(sim.dilemmas.marks(), [], "the sign is gone")
	eq(_lines(sim, "sick", "The fever is over").size(), 1, "the News says so")
	var h := _game()
	var s2 = h.sim
	s2.radio.answer(int(_outbreak(s2, 5.0).id), "quarantine")
	s2.clock_min = float(s2.clock_min) + s2.dilemmas.QUARANTINE_H * 60.0 + 1.0
	_sick(s2, "dez", 30.0)
	_sick(s2, "marcus", 30.0)
	s2.dilemmas.look()
	eq(s2.dilemmas.closed, {}, "at its time it is lifted, whoever is still sick")
	eq(_lines(s2, "sick", "The quarantine is lifted").size(), 1, "and the News says that")
	check(s2.medical.is_apart(_p(s2, "dez")), "(they go on resting apart until they are well, as medical.gd has it)")
	_free(g)
	_free(h)


func _default_after_timer() -> void:
	var g := _game()
	var sim = g.sim
	var e := _outbreak(sim, 5.0)
	check(String(e.answered) == "", "nobody has answered")
	sim.clock_min = float(e.due) + 1.0
	sim.radio.update(1.0 / 30.0)
	var done: Dictionary = sim.radio._entry(int(e.id))
	eq(String(done.answered), "quarantine", "the timer took the default")
	check(bool(done.by_default), "by default")
	check(sim.medical.is_apart(_p(sim, "dez")) and sim.medical.is_apart(_p(sim, "marcus")), "and they lie apart")
	near(float(sim.stock.meds), 5.0, 0.001, "no medicine spent")
	eq(int(sim.dilemmas.tallies().by_default), 1, "counted")
	_free(g)


func _stale_call_closed() -> void:
	var g := _game()
	var sim = g.sim
	var e := _outbreak(sim, 5.0)
	sim.storyteller.sick.erase("dez")
	sim.storyteller.sick.erase("marcus")
	sim.dilemmas.look()
	check(String(sim.radio._entry(int(e.id)).answered) != "", "the card goes")
	eq(String(sim.radio._entry(int(e.id)).result), "The fever passed before anyone answered", "and says why")
	_free(g)


# ----------------------------------------------------------- the spread and the risk --

func test_the_fever_spreads_and_the_risk_follows_the_dials() -> void:
	_spread_catches()
	_spread_apart_fraction()
	_risk_dials()
	_risk_full()
	_risk_cause()


## A game with Dez sick and Marcus a tile from him (nobody else near), the call kept out of the way; whether Dez lies apart is the test's.
func _beside(apart: bool) -> Dictionary:
	var g := _game()
	var sim = g.sim
	sim.dilemmas.last_day = int(sim.day)
	_sick(sim, "dez")
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	dez.x = 10.0
	dez.y = 10.0
	marcus.x = 11.0
	marcus.y = 10.0
	if apart:
		sim.medical.keep_apart(dez)
	return g


func _spread_catches() -> void:
	var g := _beside(false)
	var sim = g.sim
	sim.dilemmas.look()
	near(float(sim.dilemmas.exposure.get("marcus", 0.0)), 0.35, 0.001, "a look beside a fever: 0.35")
	check(not sim.dilemmas.exposure.has("walt"), "nobody far away has any")
	sim.dilemmas.look()
	sim.dilemmas.look()
	check(sim.storyteller.is_sick(_p(sim, "marcus")), "the third look: Marcus has it")
	eq(_lines(sim, "sick", "Marcus caught it").size(), 1, "the News says so")
	check(not sim.dilemmas.exposure.has("marcus"), "and the exposure is spent")
	var left: float = float(sim.storyteller.sick["marcus"]) - float(sim.clock_min)
	near(left, sim.dilemmas.SICK_H * 60.0, 1.0, "for eighteen hours")
	sim.storyteller.sick.erase("dez")
	sim.dilemmas.exposure["walt"] = 0.5
	sim.dilemmas.look()
	near(float(sim.dilemmas.exposure.get("walt", 0.0)), 0.4, 0.001, "with nobody sick near, exposure wears off")
	_free(g)


func _spread_apart_fraction() -> void:
	var open := _beside(false)
	var shut := _beside(true)
	open.sim.dilemmas.look()
	shut.sim.dilemmas.look()
	var a: float = float(open.sim.dilemmas.exposure.get("marcus", 0.0))
	var b: float = float(shut.sim.dilemmas.exposure.get("marcus", 0.0))
	near(a, 0.35, 0.001, "not apart: 0.35 a look")
	near(b / a, 0.15, 0.001, "apart: x0.15")
	_free(open)
	_free(shut)


func _risk_dials() -> void:
	var g := _game()
	var sim = g.sim
	var base: float = sim.dilemmas.risk_rate()
	near(base, 0.002, 1.0e-9, "five people at full rations: the base alone")
	sim.policies.current["rations"] = "half"
	near(sim.dilemmas.risk_rate() - base, 0.003, 1.0e-9, "half rations add")
	sim.policies.current["rations"] = "hungry"
	var hungry: float = sim.dilemmas.risk_rate() - base
	near(hungry, 0.006, 1.0e-9, "hungry rations add more")
	sim.policies.current["rations"] = "full"
	sim.policies.current["hours"] = "overtime"
	near(sim.dilemmas.risk_rate(), base, 1.0e-9, "overtime with nobody worn out adds nothing")
	sim.policies.weary["dez"] = 61.0
	near(sim.dilemmas.risk_rate() - base, 0.005, 1.0e-9, "overtime with somebody worn out adds")
	sim.policies.current["hours"] = "normal"
	near(sim.dilemmas.risk_rate(), base, 1.0e-9, "(on normal hours it does not)")
	var fake := FakeProblems.new()
	var real = sim.problems
	sim.problems = fake
	near(sim.dilemmas.risk_rate(), base, 1.0e-9, "no leak")
	fake.leak = true
	near(sim.dilemmas.risk_rate() - base, 0.003, 1.0e-9, "an open leak adds")
	sim.policies.current["rations"] = "hungry"
	sim.policies.current["hours"] = "overtime"
	near(sim.dilemmas.risk_rate() - base, 0.014, 1.0e-9, "and they add up")
	# the look grows the risk by exactly that
	sim.dilemmas.last_day = int(sim.day)
	var before: float = sim.dilemmas.risk
	sim.dilemmas.look()
	near(sim.dilemmas.risk - before, sim.dilemmas.risk_rate(), 1.0e-9, "each look")
	sim.problems = real
	_free(g)


func _risk_full() -> void:
	var g := _game()
	var sim = g.sim
	sim.dilemmas.last_day = int(sim.day)
	var state: int = sim.rng.state
	sim.policies.weary["ruth"] = 99.0    # (the leader is never the one)
	sim.policies.weary["dez"] = 80.0
	sim.policies.weary["marcus"] = 50.0
	sim.dilemmas.risk = 0.9995
	sim.dilemmas.look()
	check(sim.storyteller.is_sick(_p(sim, "dez")), "the most worn out has the fever")
	check(not sim.storyteller.is_sick(_p(sim, "marcus")) and not sim.storyteller.is_sick(_p(sim, "ruth")), "nobody else")
	near(float(sim.storyteller.sick["dez"]) - float(sim.clock_min), 24.0 * 60.0, 1.0, "for a day")
	eq(sim.dilemmas.risk, 0.0, "the risk starts again")
	eq(_lines(sim, "sick", "Dez has a fever").size(), 1, "the News says so")
	eq(String(_lines(sim, "sick", "Dez has a fever")[0].sub), "Run down: a crowded camp", "and why (nothing but the crowd)")
	# a tie in weariness: the hungrier, then the smaller id
	sim.storyteller.sick.erase("dez")
	sim.policies.weary["dez"] = 50.0
	_p(sim, "marcus").hunger_h = 9.0
	sim.dilemmas.risk = 0.9995
	sim.dilemmas.look()
	check(sim.storyteller.is_sick(_p(sim, "marcus")), "a tie: the hungrier")
	sim.storyteller.sick.erase("marcus")
	_p(sim, "marcus").hunger_h = 0.0
	sim.dilemmas.risk = 0.9995
	sim.dilemmas.look()
	check(sim.storyteller.is_sick(_p(sim, "dez")), "a tie in everything: the smaller id")
	eq(sim.rng.state, state, "and no die was thrown")
	_free(g)


func _risk_cause() -> void:
	var g := _game()
	var sim = g.sim
	sim.dilemmas.last_day = int(sim.day)
	sim.policies.current["rations"] = "hungry"
	sim.dilemmas.risk = 0.9999
	sim.dilemmas.look()
	var lines := _lines(sim, "sick", "has a fever")
	eq(lines.size(), 1, "a fever")
	eq(String(lines[0].sub), "Run down: hungry rations", "and the rations are the reason")
	_free(g)


# ---------------------------------------------------------------------- the opinion --

func test_the_medic_says_treat_when_the_medicine_stretches_and_quarantine_when_it_does_not() -> void:
	var g := Kit.game(5)
	var sim = g.sim
	sim.storyteller.enabled = true
	Kit.at(sim, 4, 9.0)
	g.spec.holders["medic"] = "ana"
	var e := _outbreak(sim, 5.0)
	var o: Dictionary = sim.initiative.voice_opinion(e)
	eq(String(o.get("line", "")), "Ana, the medic: treat them.", "with the medicine for both")
	eq(String(o.get("option", "")), "treat", "the option")
	sim.stock.meds = 1.5
	o = sim.initiative.voice_opinion(e)
	eq(String(o.get("option", "")), "quarantine", "with too little")
	eq(String(o.get("line", "")), "Ana, the medic: keep them apart, the medicine will not stretch.", "in words")
	g.spec.holders.erase("medic")
	g.rel.voice_id = ""
	eq(sim.initiative.voice_opinion(e), {}, "with no medic and no voice: none")
	g.rel.voice_id = "walt"
	eq(String(sim.initiative.voice_opinion(e).get("who", "")), "walt", "with no medic: the voice")
	g.spec.holders["medic"] = "dez"
	g.rel.voice_id = "walt"
	check(String(sim.initiative.voice_opinion(e).get("who", "")) != "dez", "(a patient is never the one who says it)")
	_free(g)


# ------------------------------------------------------------------------------ save --

func test_saves() -> void:
	_save_keeps()
	_save_damaged()


func _save_keeps() -> void:
	var a := _game()
	var sim = a.sim
	sim.radio.answer(int(_outbreak(sim, 5.0).id), "quarantine")
	sim.dilemmas.exposure["walt"] = 0.4
	sim.dilemmas.risk = 0.31
	sim.dilemmas.update(4.0)
	var d: Dictionary = SaveGame.to_dict(sim)
	check(d.modules.has("dilemmas"), "the module is saved with the others")
	var b := _game()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads")
	eq(b.sim.dilemmas.save(), sim.dilemmas.save(), "the whole module is as it was")
	eq(b.sim.dilemmas.closed.ids, ["dez", "marcus"], "the quarantine is still on")
	eq(b.sim.dilemmas.marks().size(), 1, "with its sign")
	check(b.sim.dilemmas.claims(_p(b.sim, "dez")), "and the plain call is still kept away")
	_free(a)
	_free(b)


func _save_damaged() -> void:
	var g := _game()
	var sim = g.sim
	sim.dilemmas.risk = 0.5
	sim.dilemmas.load_state({})
	eq(sim.dilemmas.risk, 0.0, "a save from before is a fresh module")
	eq(sim.dilemmas.closed, {}, "no quarantine")
	sim.dilemmas.load_state({
		"risk": NAN, "acc": INF, "last_day": "x", "exposure": {"walt": 7.0, "ghost": 0.5, "dez": "bad", "ana": -3.0},
		"closed": {"until": INF, "ids": ["dez"]}, "stats": {"raised": -4, "meds": NAN, "caught": "many"}, "notes": ["junk", {"day": 3}, {"day": NAN, "text": "x"}, {"day": 4, "text": "Fever: Dez"}],
	})
	eq(sim.dilemmas.risk, 0.0, "a risk that is not a number is none")
	check(is_finite(sim.dilemmas.save().acc), "the numbers that come back out are finite")
	eq(sim.dilemmas.exposure.get("walt", -1.0), 1.0, "an exposure is kept within 0 and 1")
	eq(sim.dilemmas.exposure.get("ana", -1.0), 0.0, "(from below too)")
	check(not sim.dilemmas.exposure.has("ghost") and not sim.dilemmas.exposure.has("dez"), "an unknown person and a bad number are dropped")
	eq(sim.dilemmas.closed, {}, "a quarantine with no time is dropped")
	check(int(sim.dilemmas.stats.raised) >= 0 and is_finite(float(sim.dilemmas.stats.meds)), "no negative or broken counts")
	eq(sim.dilemmas.notes, [{"day": 4, "text": "Fever: Dez"}], "only the sound note is kept")
	sim.dilemmas.load_state({"closed": {"until": 9000.0, "ids": ["ghost", "marcus", "marcus"]}})
	eq(sim.dilemmas.closed.ids, ["marcus"], "a quarantine keeps the people who are there, once")
	_free(g)
