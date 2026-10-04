extends "res://tests/case.gd"
## The community's ideas (round 20, scripts/sim/initiative.gd): what the module does as a whole. Who may bring an idea and when
## (the hours, the caps, the three gaps, the trust gates), what a call carries, what yes, later and no cost, the re-check, the
## quiet after three refusals, the voice's opinion on a call, saves and determinism. What each of the thirteen ideas is and does is
## in test_ideas_effects.gd. The relations and specialists modules are the fakes of tests/initiative_kit.gd.

const Kit := preload("res://tests/initiative_kit.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


## A game in which the wall idea is on the table (a wall of the north side at 80%, nobody on the Builders).
func _wall_game(crew: int = 4) -> Dictionary:
	var g := Kit.game(crew)
	Kit.wear(g.sim, 5, 0.8)
	return g


## A call of an idea nobody has really thought of: for the tests of what answering costs.
func _fake_idea(sim, kind: String, who: String, others: Array = [], args: Dictionary = {}) -> int:
	return sim.radio.raise_call("idea", "%s: an idea" % who, "", [{"id": "yes", "label": "Yes"}, {"id": "later", "label": "Later"}, {"id": "no", "label": "No"}], "later", 360.0, {"idea": kind, "who": who, "others": others, "args": args, "cost": {}}, null)


func _free(g: Dictionary) -> void:
	g.world.free()


## Who would bring this kind of idea now ("" when nobody would).
func _who(sim, kind: String) -> String:
	return String(Kit.candidate(sim, kind).get("who", ""))


# ------------------------------------------------------------------- active --

func test_nothing_runs_without_an_avatar() -> void:
	var g := _wall_game()
	var sim = g.sim
	sim.avatar.set_player(null)
	check(not sim.initiative.active(), "no avatar: not active")
	eq(sim.initiative.candidates(), [], "no candidates")
	eq(sim.initiative.propose_now(), 0, "nothing is raised")
	var state: int = sim.rng.state
	for i in 60:
		sim.initiative.update(10.0)
	eq(sim.radio.news.size(), 0, "the radio has heard nothing")
	eq(sim.rng.state, state, "and no die was thrown")
	_free(g)


func test_the_classic_start_has_no_ideas() -> void:
	var g := Kit.game(6)
	var sim = g.sim
	Kit.wear(sim, 5, 0.8)
	check(String(sim.player_id) != "", "an avatar game")
	check(not sim.recruits.small, "of the classic six")
	check(not sim.initiative.active(), "not active")
	eq(sim.initiative.candidates(), [], "no candidates")
	eq(sim.initiative.look(), 0, "and a look raises nothing")
	_free(g)


func test_orientation_day_has_no_ideas() -> void:
	var g := _wall_game()
	var sim = g.sim
	check(sim.initiative.active(), "an avatar game in a small start is active")
	sim.initiative.enabled = false    # (what Orientation Day does)
	check(not sim.initiative.active(), "switched off, it is not")
	eq(sim.initiative.candidates(), [], "no candidates")
	eq(sim.initiative.propose_now(), 0, "nothing is raised")
	eq(sim.initiative.voice_opinion({"kind": "sick", "options": [], "answered": "", "data": {}}), {}, "and it has no opinion")
	_free(g)


# ----------------------------------------------------------------- a candidate --

func test_a_candidate_has_the_shape_of_the_contract() -> void:
	var g := _wall_game()
	var sim = g.sim
	var c := Kit.candidate(sim, "fix_wall")
	check(not c.is_empty(), "the wall idea is a candidate")
	for key in ["kind", "who", "others", "score", "text", "sub", "yes_label", "cost", "args"]:
		check(c.has(key), "it has %s" % key)
	eq(c.who, "dez", "Dez has it (the best Building at the base)")
	check(c.others is Array and c.cost is Dictionary and c.args is Dictionary, "the lists are lists")
	check(String(c.text).begins_with("Dez: "), "it is said by name: %s" % c.text)
	check(String(c.text).contains("scrap"), "with its price: %s" % c.text)
	check(float(c.cost.get("scrap", 0.0)) > 0.0, "the price is in the cost")
	var all: Array = sim.initiative.candidates()
	for i in range(1, all.size()):
		check(float(all[i - 1].score) >= float(all[i].score), "best first")
	_free(g)


func test_candidates_changes_nothing() -> void:
	var g := _wall_game()
	var sim = g.sim
	var before: Dictionary = sim.initiative.save()
	var state: int = sim.rng.state
	for i in 5:
		sim.initiative.candidates()
	eq(sim.initiative.save(), before, "the module is as it was")
	eq(sim.rng.state, state, "no die")
	eq(sim.radio.news.size(), 0, "nothing was said")
	_free(g)


func test_a_specialist_of_the_kind_proposes_first() -> void:
	var g := _wall_game()
	var sim = g.sim
	var plain := Kit.candidate(sim, "fix_wall")
	g.spec.holders["engineer"] = "marcus"
	var c := Kit.candidate(sim, "fix_wall")
	eq(c.who, "marcus", "the engineer brings it, though Dez builds better")
	check(float(c.score) > float(plain.score) - 3.0, "and the title is worth points: %s against %s" % [c.score, plain.score])
	_free(g)


# --------------------------------------------------------------------- a call --

func test_propose_now_raises_the_best_idea_as_a_call() -> void:
	var g := _wall_game()
	var sim = g.sim
	var want := Kit.candidate(sim, "fix_wall")
	var id := Kit.raise(sim, "fix_wall")
	check(id > 0, "a call id comes back")
	var e: Dictionary = sim.radio.news[sim.radio.news.size() - 1]
	eq(int(e.id), id, "it is the newest entry")
	eq(String(e.kind), "idea", "an idea")
	eq(String(e.text), String(want.text), "with the candidate's words")
	eq(String(e.sub), String(want.sub), "and its line")
	var ids: Array = []
	for o in e.options:
		ids.append(String(o.id))
	eq(ids, ["yes", "later", "no"], "yes, later, no")
	eq(String(e.options[0].label), String(want.yes_label), "yes says what it does")
	eq(String(e.default), "later", "later is the default")
	near(float(e.due), float(sim.clock_min) + sim.initiative.TTL_MIN, 0.001, "six hours to answer")
	eq(String(e.data.idea), "fix_wall", "the call keeps what it needs")
	eq(String(e.data.who), "dez", "who")
	check(e.data.has("others") and e.data.has("args") and e.data.has("cost"), "the others, the arguments, the cost")
	check(e.at is Vector2, "where the proposer stands")
	var barked := false
	for ev in sim.events:
		if ev.type == "bark" and ev.who == "dez" and not String(ev.text).begins_with("Dez"):
			barked = true
	check(barked, "the proposer says it aloud (a bubble)")
	eq(Kit.open_ideas(sim).size(), 1, "one idea waits")
	eq(sim.initiative.record_of(Kit.who(sim, "dez")).asked, 1, "Dez has been asked once")
	_free(g)


func test_a_call_that_is_not_answered_is_a_later() -> void:
	var g := _wall_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var id := Kit.raise(sim, "fix_wall")
	var trust: float = dez.trust
	var mood: float = sim.morale.value(dez)
	var scrap: float = sim.stock.scrap
	sim.clock_min += sim.initiative.TTL_MIN + 1.0
	sim.radio.update(0.0)
	var e: Dictionary = sim.radio._entry(id)
	eq(String(e.answered), "later", "later was taken")
	check(bool(e.by_default), "by default")
	eq(sim.initiative.record_of(dez).later, 1, "it counts as a later")
	near(dez.trust, trust, 1e-9, "no trust moved")
	near(sim.morale.value(dez), mood, 1e-9, "no mood moved")
	near(sim.stock.scrap, scrap, 1e-9, "no scrap was spent")
	check(dez.repair == null, "nobody went to the wall")
	_free(g)


# ------------------------------------------------------------------ the answers --

func test_yes_does_it_and_pleases_the_proposer() -> void:
	var g := _wall_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var id := Kit.raise(sim, "fix_wall")
	var trust: float = dez.trust
	var mood: float = sim.morale.value(dez)
	check(sim.radio.answer(id, "yes"), "the answer is taken")
	var e: Dictionary = sim.radio._entry(id)
	check(String(e.result).contains("Dez"), "the result says what came of it: %s" % e.result)
	check(dez.repair != null, "Dez goes to the wall")
	near(dez.trust, trust + sim.initiative.YES_TRUST, 1e-9, "he trusts you a little more")
	near(sim.morale.value(dez), mood + sim.initiative.YES_MORALE, 1e-9, "and is glad")
	var rec: Dictionary = sim.initiative.record_of(dez)
	eq(rec.yes, 1, "one yes")
	eq(sim.initiative.taken_of(dez), 1, "one taken up")
	_free(g)


func test_no_costs_the_proposer_a_little() -> void:
	var g := _wall_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var id := Kit.raise(sim, "fix_wall")
	var trust: float = dez.trust
	var mood: float = sim.morale.value(dez)
	check(sim.radio.answer(id, "no"), "the answer is taken")
	near(dez.trust, trust + sim.initiative.NO_TRUST, 1e-9, "a little less trust")
	near(sim.morale.value(dez), mood + sim.initiative.NO_MORALE, 1e-9, "a little less mood")
	check(dez.repair == null, "and nothing was done")
	eq(sim.initiative.record_of(dez).no, 1, "a no is counted")
	eq(sim.initiative.taken_of(dez), 0, "nothing taken up")
	_free(g)


func test_later_costs_nothing() -> void:
	var g := _wall_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var id := Kit.raise(sim, "fix_wall")
	var trust: float = dez.trust
	var mood: float = sim.morale.value(dez)
	check(sim.radio.answer(id, "later"), "the answer is taken")
	near(dez.trust, trust, 1e-9, "no trust")
	near(sim.morale.value(dez), mood, 1e-9, "no mood")
	check(dez.repair == null, "nothing was done")
	eq(sim.initiative.record_of(dez).later, 1, "a later is counted")
	_free(g)


func test_a_yes_is_checked_again_when_it_is_given() -> void:
	var g := _wall_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var id := Kit.raise(sim, "fix_wall")
	sim.stock.scrap = 2.0
	var trust: float = dez.trust
	check(sim.radio.answer(id, "yes"), "the answer is taken")
	var e: Dictionary = sim.radio._entry(id)
	check(String(e.result).begins_with("Not now: it needs "), "it says why not: %s" % e.result)
	check(String(e.result).contains("scrap"), "the scrap: %s" % e.result)
	check(dez.repair == null, "nothing was done")
	near(dez.trust, trust, 1e-9, "and it costs nothing")
	var rec: Dictionary = sim.initiative.record_of(dez)
	eq(rec.yes, 0, "it was not a yes")
	eq(rec.later, 1, "it counts as a later")
	_free(g)


# ------------------------------------------------------ three refusals in a row --

## Dez is the only one who may bring an idea (the others trust the leader too little), and the leader says no to all of them. The ideas
## come through the real schedule (`update`: the slow look, the gap between two proposals, a person's gap, a kind's gap, the shelves).
func _only_dez(sim) -> void:
	for id in ["marcus", "ana"]:
		Kit.who(sim, id).trust = sim.initiative.QUIET_TRUST - 1.0


## One slow look at this hour of this day; the idea it raised (if any) is answered with `option`. The kind that came, "" when none.
func _look_and_answer(sim, day: int, hour: float, option: String) -> String:
	Kit.at(sim, day, hour)
	sim.initiative.update(sim.initiative.TICK_S)
	var open: Array = Kit.open_ideas(sim)
	if open.is_empty():
		return ""
	var kind := String(open[0].data.idea)
	check(sim.radio.answer(int(open[0].id), option), "the answer to the %s idea is taken" % kind)
	return kind


func test_three_noes_in_a_row_through_the_real_schedule_and_the_proposer_goes_quiet() -> void:
	var g := _wall_game()
	var sim = g.sim
	_only_dez(sim)
	var dez = Kit.who(sim, "dez")
	var trust: float = dez.trust
	sim.stock.ammo = 100.0    # (the bench has no need yet: the wall is the first idea)
	eq(_look_and_answer(sim, 3, 9.0, "no"), "fix_wall", "day 3: the wall")
	eq(int(sim.initiative.record_of(dez).quiet_until), 0, "one no")
	sim.stock.ammo = 300.0    # (the bench stops at its line)
	eq(_look_and_answer(sim, 4, 9.0, "no"), "", "day 4: he was asked yesterday")
	eq(_look_and_answer(sim, 5, 9.0, "no"), "bench_target", "day 5 (his gap is two days): the bench, the wall being put away")
	eq(int(sim.initiative.record_of(dez).quiet_until), 0, "two noes")
	sim.stock.ammo = 600.0
	for q in sim.jobs.crew_of("radio"):
		sim.jobs.unassign(q)
	sim.jobs.unassign(dez)    # (nobody at the radio, and Dez with no job to do it)
	var news: int = sim.radio.news.size()
	eq(_look_and_answer(sim, 7, 9.0, "no"), "desk", "day 7: the radio desk")
	var rec: Dictionary = sim.initiative.record_of(dez)
	eq(int(rec.no), 3, "three noes")
	eq(int(rec.quiet_until), 7 + sim.initiative.QUIET_DAYS, "(days 3, 5 and 7) he is silent for three days: three in a row, in the span of the rule")
	near(dez.trust, trust + 3.0 * sim.initiative.NO_TRUST + sim.initiative.QUIET_TRUST_COST, 1e-9, "the third costs more trust")
	var line := ""
	for i in range(news, sim.radio.news.size()):
		if String(sim.radio.news[i].text).contains("stopped bringing ideas"):
			line = String(sim.radio.news[i].text)
	eq(line, "Dez has stopped bringing ideas", "the News says it")
	for day in [8, 9]:
		Kit.at(sim, day, 9.0)
		check(not sim.initiative._context().proposers.has(dez), "day %d: he brings nothing" % day)
	Kit.at(sim, 10, 9.0)
	check(sim.initiative._context().proposers.has(dez), "day 10: he may again")
	_free(g)


func test_a_no_does_not_come_back_from_the_same_person_for_a_while() -> void:
	var g := _wall_game()
	var sim = g.sim
	_only_dez(sim)
	eq(_look_and_answer(sim, 3, 9.0, "no"), "fix_wall", "day 3: the wall, turned down")
	var back := 0
	for day in range(4, 3 + sim.initiative.REFUSED_KIND_DAYS + 2):
		Kit.at(sim, day, 9.0)
		Kit.wear(sim, 5, 0.8)
		if _who(sim, "fix_wall") == "dez":
			back = day
			break
	eq(back, 3 + sim.initiative.REFUSED_KIND_DAYS, "he does not bring the same idea again for %d days (the kind's own gap is only three)" % sim.initiative.REFUSED_KIND_DAYS)
	# somebody else may, after the kind's own gap
	var h := _wall_game()
	var hs = h.sim
	_only_dez(hs)
	_look_and_answer(hs, 3, 9.0, "no")
	Kit.at(hs, 6, 9.0)
	Kit.wear(hs, 5, 0.8)
	Kit.who(hs, "marcus").trust = 55.0
	h.spec.holders["engineer"] = "marcus"
	eq(_who(hs, "fix_wall"), "marcus", "(another person may bring it once the kind's own gap is over)")
	_free(h)
	_free(g)


func test_a_yes_ends_a_run_of_noes() -> void:
	var g := _wall_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	for day in [3, 4]:
		Kit.at(sim, day, 9.0)
		sim.radio.answer(_fake_idea(sim, "supper", "dez"), "no")
	Kit.at(sim, 5, 9.0)
	sim.radio.answer(Kit.raise(sim, "fix_wall"), "yes")
	eq(sim.initiative.record_of(dez).yes, 1, "(a yes in the middle)")
	for day in [6, 7]:
		Kit.at(sim, day, 9.0)
		sim.radio.answer(_fake_idea(sim, "supper", "dez"), "no")
	eq(int(sim.initiative.record_of(dez).quiet_until), 0, "no, no, yes, no, no: not a run of three")
	Kit.at(sim, 8, 9.0)
	sim.radio.answer(_fake_idea(sim, "supper", "dez"), "no")
	eq(int(sim.initiative.record_of(dez).quiet_until), 8 + sim.initiative.QUIET_DAYS, "the third after the yes is")
	_free(g)


func test_noes_that_are_far_apart_do_not_add_up() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var span: int = sim.initiative.NO_WINDOW_DAYS
	for day in [3, 3 + span / 2 + 1, 3 + span + 1]:
		Kit.at(sim, day, 9.0)
		sim.radio.answer(_fake_idea(sim, "supper", "dez"), "no")
	eq(int(sim.initiative.record_of(dez).quiet_until), 0, "three noes spread over %d days are not a run in %d" % [span + 1, span])
	# (the window slides: the next one is three in a row over the last days)
	Kit.at(sim, 3 + span + 2, 9.0)
	sim.radio.answer(_fake_idea(sim, "supper", "dez"), "no")
	eq(int(sim.initiative.record_of(dez).quiet_until), 3 + span + 2 + sim.initiative.QUIET_DAYS, "but the last three, close enough, are")
	_free(g)


func test_a_quiet_person_brings_nothing_until_the_day() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.initiative.records["dez"] = {"asked": 3, "yes": 0, "no": 3, "later": 0, "quiet_until": 9, "last_day": 5, "no_days": []}
	Kit.wear(sim, 5, 0.8)
	Kit.at(sim, 8, 9.0)
	check(_who(sim, "fix_wall") != "dez", "quiet until day 9: nothing of his on day 8")
	Kit.at(sim, 9, 9.0)
	eq(_who(sim, "fix_wall"), "dez", "day 9: he may")
	_free(g)


# -------------------------------------------------------------- who may bring one --

func test_someone_with_little_trust_in_you_brings_nothing() -> void:
	var g := _wall_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	dez.trust = sim.initiative.QUIET_TRUST - 0.1
	check(_who(sim, "fix_wall") != "dez", "under 25 Dez brings nothing (somebody else may)")
	for c in sim.initiative.candidates():
		check(String(c.who) != "dez", "nothing of Dez's: %s" % c.kind)
	dez.trust = sim.initiative.QUIET_TRUST
	eq(_who(sim, "fix_wall"), "dez", "at 25 he may")
	_free(g)


func test_the_player_and_people_who_cannot_bring_an_idea() -> void:
	var g := _wall_game()
	var sim = g.sim
	var ruth = Kit.who(sim, "ruth")
	ruth.skills["Building"] = 10
	for c in sim.initiative.candidates():
		check(String(c.who) != "ruth", "never the player: %s" % c.kind)
	var dez = Kit.who(sim, "dez")
	dez.downed = true
	check(_who(sim, "fix_wall") != "dez", "not someone who is down")
	dez.downed = false
	dez.away = {"kind": "party"}
	check(_who(sim, "fix_wall") != "dez", "not someone who is away")
	dez.away = null
	dez.stance = "follow"
	check(_who(sim, "fix_wall") != "dez", "not someone who follows you")
	dez.stance = ""
	sim.morale.until["dez"] = sim.clock_min + 60.0
	check(_who(sim, "fix_wall") != "dez", "not someone in a breakdown")
	sim.morale.until.erase("dez")
	eq(_who(sim, "fix_wall"), "dez", "(and he is the one when none of that is so)")
	_free(g)


func test_a_person_is_asked_again_after_two_days_and_the_voice_after_one() -> void:
	var g := _wall_game()
	var sim = g.sim
	eq(_who(sim, "bench_target"), "dez", "(the bench idea is Dez's too)")
	Kit.raise(sim, "fix_wall")    # Dez, day 3
	eq(_who(sim, "bench_target"), "", "the same day: not Dez again")
	Kit.at(sim, 4, 9.0)
	eq(_who(sim, "bench_target"), "", "the next day too")
	Kit.at(sim, 5, 9.0)
	eq(_who(sim, "bench_target"), "dez", "after two days he may")
	# the voice has one day
	var h := _wall_game()
	var vsim = h.sim
	h.rel.voice_id = "dez"
	Kit.raise(vsim, "fix_wall")
	Kit.at(vsim, 4, 9.0)
	eq(_who(vsim, "bench_target"), "dez", "the voice may after one")
	_free(h)
	_free(g)


func test_a_kind_is_proposed_again_after_its_gap_of_days() -> void:
	var g := _wall_game()
	var sim = g.sim
	var gap: int = sim.initiative.GAP_KIND_DAYS
	sim.radio.answer(Kit.raise(sim, "fix_wall"), "no")
	g.spec.holders["engineer"] = "marcus"    # (somebody else would be the proposer: it is the kind that is held back)
	Kit.at(sim, 3 + gap - 1, 9.0)
	eq(_who(sim, "fix_wall"), "", "a day short of the gap: no")
	Kit.at(sim, 3 + gap, 9.0)
	eq(_who(sim, "fix_wall"), "marcus", "the gap on: yes")
	_free(g)


func test_a_kind_that_is_waiting_is_not_raised_again() -> void:
	var g := _wall_game()
	var sim = g.sim
	Kit.raise(sim, "fix_wall")
	Kit.at(sim, 9, 9.0)
	Kit.wear(sim, 5, 0.8)
	g.spec.holders["engineer"] = "marcus"
	eq(_who(sim, "fix_wall"), "", "the first is still open, and they do not ask twice")
	_free(g)


func test_later_twice_shelves_the_kind_for_a_while() -> void:
	var g := _wall_game()
	var sim = g.sim
	var gap: int = sim.initiative.GAP_KIND_DAYS
	check(sim.initiative.SHELVE_DAYS > gap, "a kind put away stays away longer than the ordinary gap between two of a kind (else shelving means nothing)")
	sim.radio.answer(Kit.raise(sim, "fix_wall"), "later")
	Kit.at(sim, 3 + gap, 9.0)
	Kit.wear(sim, 5, 0.8)
	check(not Kit.candidate(sim, "fix_wall").is_empty(), "after one later it comes back when its gap of days is over")
	sim.radio.answer(Kit.raise(sim, "fix_wall"), "later")
	Kit.at(sim, 3 + gap + sim.initiative.SHELVE_DAYS - 1, 9.0)
	Kit.wear(sim, 5, 0.8)
	eq(_who(sim, "fix_wall"), "", "after the second later it is put away for a while")
	Kit.at(sim, 3 + gap + sim.initiative.SHELVE_DAYS, 9.0)
	check(not Kit.candidate(sim, "fix_wall").is_empty(), "and comes back after %d days" % sim.initiative.SHELVE_DAYS)
	_free(g)


func test_a_yes_or_a_no_ends_a_run_of_laters() -> void:
	var g := _wall_game()
	var sim = g.sim
	var gap: int = sim.initiative.GAP_KIND_DAYS
	sim.radio.answer(Kit.raise(sim, "fix_wall"), "later")
	Kit.at(sim, 3 + gap, 9.0)
	Kit.wear(sim, 5, 0.8)
	sim.radio.answer(Kit.raise(sim, "fix_wall"), "no")
	Kit.at(sim, 3 + 2 * gap, 9.0)
	Kit.wear(sim, 5, 0.8)
	check(not Kit.candidate(sim, "fix_wall").is_empty(), "a no between the laters: not shelved")
	_free(g)


# ----------------------------------------------------------------- the schedule --

func test_ideas_come_from_day_three_by_day_and_not_at_the_radio_hour() -> void:
	var g := _wall_game()
	var sim = g.sim
	Kit.at(sim, 2, 9.0)
	check(not sim.initiative.allowed_now(), "not before day 3")
	Kit.at(sim, 3, 7.9)
	check(not sim.initiative.allowed_now(), "not before 08:00")
	Kit.at(sim, 3, 8.0)
	check(sim.initiative.allowed_now(), "from 08:00")
	Kit.at(sim, 3, 11.4)
	check(sim.initiative.allowed_now(), "until the radio hour")
	Kit.at(sim, 3, 12.0)
	check(not sim.initiative.allowed_now(), "not at the radio hour")
	Kit.at(sim, 3, 12.6)
	check(sim.initiative.allowed_now(), "after it")
	Kit.at(sim, 3, 17.5)
	check(sim.initiative.allowed_now(), "until 17:30")
	Kit.at(sim, 3, 17.6)
	check(not sim.initiative.allowed_now(), "not after")
	Kit.at(sim, 3, 22.0)
	check(not sim.initiative.allowed_now(), "never by night")
	_free(g)


func test_no_ideas_while_the_alarm_rings_or_the_dead_are_at_the_wall() -> void:
	var g := _wall_game()
	var sim = g.sim
	check(sim.initiative.allowed_now(), "(a quiet morning)")
	sim.radio.alarm(true)
	check(not sim.initiative.allowed_now(), "not under the call to arms")
	sim.radio.alarm(false)
	check(sim.initiative.allowed_now(), "and again when it is stood down")
	sim.tactics.threat_until = sim.clock_min + 100.0
	check(sim.threat_by_day(), "(the dead are at the wall)")
	check(not sim.initiative.allowed_now(), "not while they are")
	_free(g)


func test_an_idea_ends_by_dusk_and_takes_a_later_then() -> void:
	var g := _wall_game()
	var sim = g.sim
	var dusk: float = sim.seasons.dusk_hour()
	Kit.at(sim, 3, 9.0)
	var e: Dictionary = sim.radio._entry(Kit.raise(sim, "fix_wall"))
	near(float(e.due) - float(sim.clock_min), sim.initiative.TTL_MIN, 0.001, "in the morning: six hours")
	sim.radio.answer(int(e.id), "later")
	Kit.at(sim, 6, 17.3)
	g.rel.voice_id = "dez"
	for p in sim.people:
		sim.morale.set_value(p, 40.0)    # (a camp that could do with a supper)
	var id := Kit.raise(sim, "supper")
	check(id > 0, "(the evening's idea is the supper)")
	e = sim.radio._entry(id)
	near(float(e.due) - float(sim.clock_min), (dusk - 17.3) * 60.0, 0.01, "at 17:18: only until dusk, not six hours (it would stand open through the night)")
	Kit.at(sim, 6, dusk - 0.01)
	sim.radio.update(0.0)
	eq(String(sim.radio._entry(id).answered), "", "(still open a moment before dusk)")
	Kit.at(sim, 6, dusk)
	sim.radio.update(0.0)
	e = sim.radio._entry(id)
	eq(String(e.answered), "later", "at dusk it takes later")
	check(bool(e.by_default), "by default")
	eq(Kit.open_ideas(sim).size(), 0, "and there is no idea open at night")
	_free(g)


func test_the_last_proposal_is_an_hour_before_dusk_in_a_season_of_early_dusks() -> void:
	var g := _wall_game()
	var sim = g.sim
	sim.seasons._dusk = 16.5    # (winter)
	Kit.at(sim, 3, 15.4)
	check(sim.initiative.allowed_now(), "at 15:24, over an hour to dusk")
	Kit.at(sim, 3, 15.6)
	check(not sim.initiative.allowed_now(), "at 15:36 less than an hour is left: none")
	sim.seasons._dusk = 19.0
	Kit.at(sim, 3, 17.5)
	check(sim.initiative.allowed_now(), "(in autumn 17:30 is the last, as it was)")
	_free(g)


func test_no_idea_is_raised_while_an_urgent_call_is_open() -> void:
	var g := _wall_game()
	var sim = g.sim
	check(sim.initiative.allowed_now(), "(a quiet morning)")
	var attack := _attack_call(sim, 3)
	check(not sim.initiative.allowed_now(), "an attack call is open: no idea")
	eq(sim.initiative.look(), 0, "a look raises nothing")
	sim.radio.answer(attack, "hold")
	check(sim.initiative.allowed_now(), "answered: it may")
	var sick := _sick_call(sim, "marcus")
	check(not sim.initiative.allowed_now(), "a fever call is open: no idea")
	sim.radio.answer(sick, "treat")
	var night: int = sim.radio.raise_call("night", "Big Night tonight", "", [{"id": "hold", "label": "Understood"}], "hold", 60.0, {}, null)
	check(not sim.initiative.allowed_now(), "a call of the night too")
	sim.radio.answer(night, "hold")
	_fake_idea(sim, "supper", "ana")
	check(sim.initiative.allowed_now(), "(an idea that waits is no urgent call: a second may come)")
	_free(g)


func test_two_ideas_wait_at_most() -> void:
	var g := _wall_game()
	var sim = g.sim
	_fake_idea(sim, "supper", "marcus")
	check(sim.initiative.allowed_now(), "one waits: one more may come")
	_fake_idea(sim, "supper", "ana")
	check(not sim.initiative.allowed_now(), "two wait: no more")
	eq(sim.initiative.look(), 0, "a look raises nothing")
	_free(g)


func test_a_proposal_waits_four_game_hours_for_the_next() -> void:
	var g := _wall_game()
	var sim = g.sim
	check(sim.initiative.look() > 0, "the first comes")
	check(not sim.initiative.allowed_now(), "at once there is no second")
	sim.clock_min += sim.initiative.GAP_ALL_MIN - 1.0
	check(not sim.initiative.allowed_now(), "not after 3 h 59 min")
	sim.clock_min += 2.0
	check(sim.initiative.allowed_now(), "after the gap between two proposals")
	_free(g)


func test_the_slow_look_raises_an_idea() -> void:
	var g := _wall_game()
	var sim = g.sim
	sim.initiative.update(9.9)
	eq(Kit.open_ideas(sim).size(), 0, "not before the slow look is due")
	sim.initiative.update(0.2)
	eq(Kit.open_ideas(sim).size(), 1, "the look raises the best idea")
	sim.initiative.update(10.0)
	eq(Kit.open_ideas(sim).size(), 1, "and the next look, so soon, raises none")
	_free(g)


func test_the_game_loop_with_ideas_throws_the_same_dice_as_without() -> void:
	var a := _wall_game()
	var b := _wall_game()
	b.sim.initiative.enabled = false
	for i in 900:
		a.sim.update(1.0 / 30.0)
		b.sim.update(1.0 / 30.0)
	check(Kit.open_ideas(a.sim).size() + a.sim.initiative.record_of(Kit.who(a.sim, "dez")).asked + a.sim.initiative.record_of(Kit.who(a.sim, "marcus")).asked > 0, "ideas came in the game that has them")
	eq(Kit.open_ideas(b.sim).size(), 0, "and none in the other")
	eq(a.sim.rng.state, b.sim.rng.state, "the dice of the two games are in the same place")
	_free(a)
	_free(b)


func test_nobody_brings_ideas_to_a_leader_the_community_does_not_trust() -> void:
	var g := _wall_game()
	var sim = g.sim
	g.rel.community = sim.initiative.COMMUNITY_MIN - 0.5
	eq(sim.initiative.look(), 0, "a look raises nothing")
	check(not sim.initiative.allowed_now(), "the whole yard is silent")
	var said: Array = []
	for e in sim.radio.news:
		if String(e.text) == "Nobody brings you ideas any more":
			said.append(e)
	eq(said.size(), 1, "the News says so")
	sim.initiative.look()
	sim.initiative.look()
	said.clear()
	for e in sim.radio.news:
		if String(e.text) == "Nobody brings you ideas any more":
			said.append(e)
	eq(said.size(), 1, "once")
	g.rel.community = sim.initiative.COMMUNITY_MIN
	check(sim.initiative.allowed_now(), "at 35 they speak again")
	_free(g)


# ----------------------------------------------------------------- the voice speaks --

func _attack(sim, seg_id: int, n: int) -> void:
	for s in sim.segments:
		if s.id != seg_id:
			continue
		for i in n:
			var sl = s.slots[i]
			var z = sim.spawn(sl.x, sl.y, "attack")
			z.slot = sl
			sl.who = z


func _attack_call(sim, seg_id: int) -> int:
	return sim.radio.raise_call("attack", "A wall under attack", "", [{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send reinforcements"}, {"id": "fall_back", "label": "Fall back to the school"}], "hold", 30.0, {"seg": seg_id}, null)


func _sick_call(sim, who: String) -> int:
	return sim.radio.raise_call("sick", "%s has a fever" % who, "", [{"id": "treat", "label": "Treat them"}, {"id": "apart", "label": "Keep them apart"}], "treat", 60.0, {"who": who}, null)


func test_the_marksman_gives_his_opinion_on_an_attack() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	g.spec.holders["marksman"] = "marcus"
	_attack(sim, 3, 2)
	var e: Dictionary = sim.radio._entry(_attack_call(sim, 3))
	var o: Dictionary = sim.initiative.voice_opinion(e)
	eq(o.get("who", ""), "marcus", "Marcus")
	eq(o.get("first", ""), "Marcus", "by his first name")
	eq(o.get("title", ""), "the marksman", "as the marksman")
	eq(o.get("option", ""), "hold", "hold: two at a wall that is whole")
	eq(o.get("line", ""), "Marcus, the marksman: hold.", "in his words")
	_free(g)


func test_the_opinion_on_an_attack_follows_the_wall() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	g.spec.holders["marksman"] = "marcus"
	_attack(sim, 3, 4)
	var e: Dictionary = sim.radio._entry(_attack_call(sim, 3))
	eq(sim.initiative.voice_opinion(e).get("option", ""), "reinforce", "four or more at the wall: reinforce")
	Kit.wear(sim, 3, 0.3)
	eq(sim.initiative.voice_opinion(e).get("option", ""), "fall_back", "a wall under 35%: fall back")
	_free(g)


func test_with_no_marksman_the_voice_speaks_on_an_attack() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	g.rel.voice_id = "ana"
	_attack(sim, 3, 1)
	var e: Dictionary = sim.radio._entry(_attack_call(sim, 3))
	var o: Dictionary = sim.initiative.voice_opinion(e)
	eq(o.get("who", ""), "ana", "Ana, whom people turn to")
	eq(o.get("title", ""), "", "no title")
	eq(o.get("line", ""), "Ana: hold.", "no title in the line")
	g.rel.voice_id = ""
	eq(sim.initiative.voice_opinion(e), {}, "with neither there is no opinion")
	_free(g)


func test_the_medic_gives_his_opinion_on_a_fever() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	g.spec.holders["medic"] = "ana"
	var e: Dictionary = sim.radio._entry(_sick_call(sim, "dez"))
	var o: Dictionary = sim.initiative.voice_opinion(e)
	eq(o.get("line", ""), "Ana, the medic: treat them.", "with medicine to spare: treat")
	eq(o.get("option", ""), "treat", "the option")
	sim.stock.meds = 1.0
	eq(sim.initiative.voice_opinion(e).get("option", ""), "apart", "with less than two: keep them apart")
	eq(sim.initiative.voice_opinion(e).get("line", ""), "Ana, the medic: keep them apart.", "in words")
	g.spec.holders.erase("medic")
	g.rel.voice_id = "dez"
	eq(sim.initiative.voice_opinion(e), {}, "(the one who is sick does not give an opinion on it)")
	g.rel.voice_id = "marcus"
	eq(sim.initiative.voice_opinion(e).get("who", ""), "marcus", "with no medic the voice")
	_free(g)


func test_the_voice_gives_her_opinion_on_an_idea() -> void:
	var g := _wall_game()
	var sim = g.sim
	g.rel.voice_id = "ana"
	var e: Dictionary = sim.radio._entry(Kit.raise(sim, "fix_wall"))
	var o: Dictionary = sim.initiative.voice_opinion(e)
	eq(o.get("option", ""), "yes", "a price well under half of the scrap: yes")
	eq(o.get("who", ""), "ana", "Ana")
	sim.stock.scrap = float(e.data.cost.scrap) * 1.5
	eq(sim.initiative.voice_opinion(e).get("option", ""), "later", "a price over half of what there is: later")
	g.rel.voice_id = "dez"
	eq(sim.initiative.voice_opinion(e), {}, "never on their own idea")
	g.rel.voice_id = ""
	eq(sim.initiative.voice_opinion(e), {}, "and nobody to ask")
	_free(g)


func test_no_opinion_on_what_is_answered_or_not_known() -> void:
	var g := _wall_game()
	var sim = g.sim
	g.rel.voice_id = "ana"
	var id := Kit.raise(sim, "fix_wall")
	sim.radio.answer(id, "later")
	eq(sim.initiative.voice_opinion(sim.radio._entry(id)), {}, "none on a call that is settled")
	var other: Dictionary = sim.radio._entry(sim.radio.raise_call("stranger", "Someone at the gate", "", [{"id": "in", "label": "Let them in"}], "in", 30.0, {}, null))
	eq(sim.initiative.voice_opinion(other), {}, "none on a kind it has no view of")
	eq(sim.initiative.voice_opinion({}), {}, "none on nothing")
	_free(g)


# --------------------------------------------------------------------- determinism --

func _history(g: Dictionary) -> Array:
	var sim = g.sim
	var out: Array = []
	for day in range(3, 9):
		Kit.at(sim, day, 9.0)
		Kit.wear(sim, 5, 0.8)
		sim.supplies.sources_day = day
		var id: int = sim.initiative.look()
		if id != 0:
			var e: Dictionary = sim.radio._entry(id)
			out.append([day, String(e.data.idea), String(e.data.who), String(e.text)])
			sim.radio.answer(id, "no" if day % 2 == 0 else "later")
	return out


func test_two_games_bring_the_same_ideas_and_throw_no_die() -> void:
	var a := _wall_game()
	var b := _wall_game()
	var state: int = a.sim.rng.state
	var ha := _history(a)
	var hb := _history(b)
	check(not ha.is_empty(), "some ideas came")
	eq(ha, hb, "the same list of (day, kind, who, words)")
	eq(a.sim.rng.state, state, "the dice were not touched")
	_free(a)
	_free(b)


# ---------------------------------------------------------------------------- saves --

func test_a_save_keeps_the_ideas_the_records_and_the_waiting_call() -> void:
	var a := _wall_game()
	var sim = a.sim
	var id := Kit.raise(sim, "fix_wall")
	sim.radio.answer(_fake_idea(sim, "supper", "marcus"), "no")
	var dez = Kit.who(sim, "dez")
	sim.initiative.update(4.0)
	var d: Dictionary = SaveGame.to_dict(sim)
	check(d.modules.has("initiative"), "the module is saved with the others")
	var b := Kit.game(4)
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads")
	var rec: Dictionary = b.sim.initiative.record_of(Kit.who(b.sim, "dez"))
	eq(rec, sim.initiative.record_of(dez), "the records are as they were")
	eq(b.sim.initiative.taken_of(Kit.who(b.sim, "dez")), sim.initiative.taken_of(dez), "and what was taken up")
	eq(b.sim.initiative.save(), sim.initiative.save(), "the whole module is as it was")
	var e: Dictionary = b.sim.radio._entry(id)
	check(not e.is_empty() and String(e.answered) == "", "the waiting call is still waiting")
	check(b.sim.radio.answer(id, "yes"), "and can be answered")
	check(Kit.who(b.sim, "dez").repair != null, "and a yes does it")
	_free(a)
	_free(b)


func test_a_save_from_before_the_ideas_loads_fresh() -> void:
	var g := _wall_game()
	var sim = g.sim
	sim.initiative.load_state({})
	eq(sim.initiative.record_of(Kit.who(sim, "dez")).asked, 0, "nobody was asked")
	check(sim.initiative.lessons().is_empty(), "no lesson")
	check(not Kit.candidate(sim, "fix_wall").is_empty(), "and the ideas come as at the start")
	_free(g)


func test_a_damaged_save_is_cleaned() -> void:
	var g := _wall_game()
	var sim = g.sim
	sim.initiative.load_state({
		"acc": NAN, "last_all": "never", "last_kind": {"fix_wall": 3, "no_such_kind": 4, "supper": "x"},
		"records": {
			"dez": {"asked": 4, "yes": -2, "no": 1.5, "later": NAN, "quiet_until": INF, "last_day": 3, "no_days": [3, "x", NAN, 4]},
			"nobody": {"asked": 9}, "marcus": "bad", "ana": {"asked": 2, "yes": 1}},
		"shelved": {"fix_wall": 9, "ghost": 3}, "streaks": {"fix_wall": 1, "ghost": 2},
		"doing": [{"teacher": "ana", "student": "ghost", "skill": "Medicine", "until": 5.0}, "junk", {"teacher": "dez"}],
		"hushed": "yes", "stats": {"raised": "many"},
	})
	var dez: Dictionary = sim.initiative.record_of(Kit.who(sim, "dez"))
	eq(dez.asked, 4, "a good number is kept")
	check(dez.yes >= 0 and dez.no >= 0 and dez.later >= 0, "no negative counts: %s" % str(dez))
	check(is_finite(float(dez.quiet_until)), "no infinity")
	eq(sim.initiative.record_of(Kit.who(sim, "ana")).asked, 2, "another good one is kept")
	eq(sim.initiative.record_of(Kit.who(sim, "marcus")).asked, 0, "a bad entry is dropped")
	check(not sim.initiative.records.has("nobody"), "an unknown person is dropped")
	check(not sim.initiative.last_kind.has("no_such_kind"), "an unknown kind is dropped")
	check(sim.initiative.lessons().is_empty(), "a lesson of somebody who is not there is dropped")
	var saved: Dictionary = sim.initiative.save()
	check(is_finite(float(saved.acc)) and is_finite(float(saved.last_all)), "the numbers that come back out are finite")
	_free(g)
