extends "res://tests/case.gd"
## The seams where round 18 (the radio panel, errands, the Jobs and Map pages), round 20 (relations, initiative, the idea call card) and
## round 21 met when they were merged. The radio's ONE list of reasons ("never two truths", `radio.reason_not`): the soft reason of
## company that round 20's relations module gives ("staying with Hector", "won't go with Walt", "won't work beside Walt") is the same
## words in a verb's refusal, the errand's chips and the Jobs page's refusals; an idea's errand is a real errand of round 18 (its terms,
## its penalty) and names nobody who would refuse the same trip if the player asked; and the slim call strip of the radio panel, with an
## idea's long "yes" in it, stays a strip at the five window sizes.

const Helpers := preload("res://tests/helpers.gd")
const IdeaKit := preload("res://tests/initiative_kit.gd")
const Kit := preload("res://tests/hud_kit.gd")
const Relations := preload("res://scripts/sim/relations.gd")
const RadioPanel := preload("res://scripts/ui/radio_panel.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## A settlement game with Ruth as the avatar and the real relations module, a quiet morning of day 3, nobody working.
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
	sim.day = 3
	sim.minutes = 9.0 * 60.0
	sim.clock_min = 2.0 * 1440.0 + (9.0 * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	var i := 0
	for p in sim.people:
		p.x = 4.0 + 9.0 * float(i)
		p.y = 10.0
		p.moving = false
		p.path = []
		p.goal_key = ""
		i += 1
	sim.events.clear()
	return g


# ------------------------------------------------------- one list of reasons --

func test_staying_with_a_hurt_friend_is_the_same_words_in_the_verb_the_errand_and_the_roster() -> void:
	var g := _game()
	var sim = g.sim
	var radio = sim.radio
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	_p(sim, "hector").downed = true    # (Dez's friend by the roster, alone)
	var verb: Dictionary = radio.willingness(dez, "come")
	check(not verb.ok and not verb.hard, "asked to come, Dez refuses softly")
	eq(String(verb.why), "Dez: staying with Hector, can't come", "in the verb's words")
	var go: Dictionary = radio.reason_not(dez, "go")
	check(not go.ok and not go.hard, "the roster's list refuses him too, softly")
	eq(String(go.why), "Dez: staying with Hector, can't go", "in the same words")
	eq(String(go.sentence), "Dez is staying with Hector", "and the sentence that names several")
	eq(String(go.line), "Staying with Hector, can't go.", "and what he says")
	# the errand chips: the page asks everybody at once, the radio says who would go and who would not, each in the list's words
	var w: Dictionary = radio.errand_willingness([dez, marcus], "houses")
	eq(w.going, [marcus], "Marcus would go")
	eq(w.refused.size(), 1, "and one refuses")
	eq(String(w.refused[0].why), String(go.why), "Dez, in the roster's words")
	check(not bool(w.refused[0].hard), "softly: it can be pushed")
	# asking him is refused with the same reason and costs nothing; pushing him goes, at the usual cost
	var asked: Dictionary = radio.request_errand([dez], "houses")
	check(not asked.ok, "the errand is refused for Dez alone")
	check(String(asked.why).contains("staying with Hector"), "with the reason: %s" % asked.why)
	# the Jobs page has a form of its own for the work: a friend's bed keeps nobody from a job (the contract: "work is another matter"),
	# so the same list says nothing there
	check(radio.job_willingness(dez, "").ok, "taking Dez off a job is not refused for a friend's sake")
	g.world.free()


func test_a_rival_at_the_station_is_the_same_words_in_the_roster_and_the_jobs_page() -> void:
	var g := _game()
	var sim = g.sim
	var radio = sim.radio
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	sim.relations.add("dez", "walt", -66.0, "x")
	check(sim.jobs.assign(walt, "bench"), "Walt is at the bench")
	var r: Dictionary = radio.reason_not(dez, "work")
	check(r.ok, "(no station named: nothing against a job at large)")
	var w: Dictionary = radio.job_willingness(dez, "bench")
	check(not w.ok and not w.hard, "Dez is not given the bench Walt works at, softly")
	eq(String(w.why), "Dez: won't work beside Walt, can't take a job now", "in the radio's words")
	check(String(w.line).begins_with("Won't work beside Walt"), "and says so: %s" % w.line)
	var shot: Dictionary = radio.request_job(dez, "bench")
	check(not shot.ok and String(shot.why) == String(w.why), "asked, the same refusal")
	var pushed: Dictionary = radio.request_job(dez, "bench", {"insist": true})
	check(pushed.ok and pushed.insisted, "pushed, he takes it")
	check(radio.job_willingness(dez, "").ok, "taking him off a job is another matter")
	g.world.free()


func test_company_among_those_asked_for_an_errand_is_judged_against_the_party_named() -> void:
	var g := _game()
	var sim = g.sim
	var radio = sim.radio
	var dez = _p(sim, "dez")
	var walt = _p(sim, "walt")
	var marcus = _p(sim, "marcus")
	sim.relations.add("dez", "walt", -66.0, "x")
	var both: Dictionary = radio.errand_willingness([dez, walt], "houses")
	eq(both.going, [], "enemies asked together: neither goes")
	eq(String(both.refused[0].why), "Dez: won't go with Walt, can't go", "Dez, in the list's words")
	eq(String(both.refused[1].why), "Walt: won't go with Dez, can't go", "and Walt")
	# the Map page asks everybody at the base at once; the party it means is the people ticked
	var everyone: Dictionary = radio.errand_willingness([dez, walt, marcus], "houses", "loot", "", ["marcus"])
	eq(everyone.going.size(), 3, "with Marcus ticked, everybody would go with him")
	var with_walt: Dictionary = radio.errand_willingness([dez, walt, marcus], "houses", "loot", "", ["walt"])
	eq(with_walt.going, [walt, marcus], "with Walt ticked, Dez would not (Walt and Marcus would)")
	eq(String(with_walt.refused[0].why), "Dez: won't go with Walt, can't go", "in the same words")
	g.world.free()


# ----------------------------------------------------------- an idea's errand --

func _errand_game() -> Dictionary:
	var g := IdeaKit.game(4, 1, false)    # (the real relations and specialists)
	var sim = g.sim
	sim.stock.food = 10.0
	IdeaKit.at(sim, 3, 9.0)
	return g


func test_an_ideas_errand_goes_as_round_18s_errand_with_its_penalty_and_news() -> void:
	var g := _errand_game()
	var sim = g.sim
	var c := IdeaKit.candidate(sim, "errand")
	check(not c.is_empty(), "the errand is an idea")
	check(String(c.text).ends_with("We'd find less without you."), "it says what the terms are: %s" % c.text)
	var id: int = IdeaKit.raise(sim, "errand")
	check(id != 0 and sim.radio.answer(id, "yes"), "a yes is taken")
	eq(sim.radio.errand_wait.size(), 1, "the errand is in the radio's queue, as any errand the player asks for (round 20 fix)")
	eq(sim.scavenge.parties.size(), 0, "nobody has left before the people's delay")
	sim.radio.tick(sim.radio.DELAY_SLOW + 0.1)
	eq(sim.scavenge.parties.size(), 1, "a party is out")
	var party: Dictionary = sim.scavenge.parties[0]
	check(sim.scavenge.is_errand(party), "an errand of round 18 (the player is not along)")
	check(bool(party.result.get("errand", false)), "its result says so")
	Helpers.run(sim, 40.0)
	var news: Array = []
	for e in sim.radio.news:
		news.append(String(e.kind))
	check(news.has("errand"), "and when they leave, the radio's news tells that they set off without the player: %s" % str(news))
	g.world.free()


func test_an_idea_never_names_somebody_who_would_refuse_the_same_trip_asked_by_the_player() -> void:
	var g := _errand_game()
	var sim = g.sim
	var radio = sim.radio
	sim.relations.add("dez", "ana", 80.0, "x")
	IdeaKit.who(sim, "ana").downed = true    # (Ana lies hurt: Dez, her friend, stays with her)
	check(String(radio.reason_not(IdeaKit.who(sim, "dez"), "go").why).contains("staying with Ana"), "Dez would refuse the player: staying with Ana")
	var c := IdeaKit.candidate(sim, "errand")
	check(not c.is_empty(), "there is still an errand to propose")
	check(not (c.others as Array).has("dez"), "but it does not offer Dez: %s" % str(c.others))
	check(c.who != "dez", "nor does Dez bring it")
	g.world.free()


# --------------------------------------------------------------- the call strip --

## An avatar game with the radio panel open on the Jobs page and an idea (with a long yes) as the oldest call, and a wall under attack.
func _strip_ctx(width: int, height: int) -> Dictionary:
	var ctx := Kit.build(width, height, 1, false, 3)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	var radio = sim.radio
	radio.raise_call("idea", "I could fix the east wall properly. About 20 scrap.", "Dez, the engineer: the crew stops when it is whole", [
		{"id": "yes", "label": "Yes: put up a workshop properly (30 scrap)"}, {"id": "later", "label": "Later"}, {"id": "no", "label": "No"},
	], "later", 360.0, {"idea": "fix_wall", "who": "dez", "others": [], "args": {}}, Vector2(40, 10))
	radio.raise_call("attack", "North wall under attack", "3 of the dead at it, 80% intact", [
		{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send reinforcements"}, {"id": "fall_back", "label": "Fall back to the school"},
	], "hold", 30.0, {"seg": 1}, Vector2(40, 10))
	sim.alert("a1", "danger", "Marcus is down", "Get them to Dez", null, 600.0)
	sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 600.0)
	Kit.update(ctx)
	ctx.hud.open_radio("jobs")
	return ctx


func test_the_slim_strip_keeps_its_buttons_whole_and_the_panel_clear_at_every_size() -> void:
	for size in SIZES:
		var ctx: Dictionary = _strip_ctx(size[0], size[1])
		for i in 2:
			Kit.update(ctx)
			await Kit.settle()
		var h = ctx.hud
		var where := "%d x %d" % [size[0], size[1]]
		var panel := Kit.rect(h.radio_panel)
		var strip := Kit.rect(h.radio_panel.call_strip)
		check(h.radio_panel.call_strip.visible and strip.size.y > 40.0, "%s: the strip is up (%s)" % [where, str(strip)])
		check(strip.size.y <= 160.0, "%s: and is a strip, not a column of wrapped words (%s)" % [where, str(strip)])
		check(panel.size.x <= (RadioPanel.WIDTH_COMPACT if h.compact else RadioPanel.WIDTH) + 0.5, "%s: the panel keeps its form's width (%s)" % [where, str(panel)])
		for b in h.radio_panel.call_strip.view.buttons.values():
			var r := Kit.rect(b)
			check(strip.encloses(r.grow(-0.5)), "%s: every button is inside the strip (%s in %s)" % [where, str(r), str(strip)])
			check(r.size.y <= 40.0, "%s: and is one line high (%s)" % [where, str(r)])
		var rects := {
			"clock": Kit.rect(h.clock), "ammo": Kit.rect(h.ammo_panel), "panel": panel, "speed": Kit.rect(h.speed_panel), "alerts": Kit.rect(h.alerts_box),
		}
		eq(Kit.overlaps(rects), [], "%s: the panel overlaps neither the clock, the gun's readout nor the toolbar" % where)
		Kit.free_all(ctx)
