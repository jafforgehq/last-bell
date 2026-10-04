extends "res://tests/case.gd"
## Round 19, the nights, integration (docs/superpowers/plans/2026-10-03-round-19.md, "Integration (orchestrator)"; the review's F8): the pieces
## of the round meet here with the REAL modules, no fake waves, no fake nights, no fake interact: an avatar game on day 9 to 10, the
## day-ahead notice at noon from a staffed radio desk, the real plan of the Big Night (The Siege: plated brutes in the middle of the night
## at one wall), the forecast's call at 17:00, the night itself played through (plated brutes arrive, the calls come, the HUD's call card
## shows the most urgent one, the bot answers), the avatar mending a fallen wall by E, the bot holding a Big Night more often than an idle
## avatar, a trip that is out at the dusk and what the radio says of it, and a save from before the round that loads and plays a night.
## A real night is about four thousand steps: a few seconds each. Numbers are read through NightData; what is asserted is structure and
## direction (the tuning moves the numbers, never these).

const Helpers := preload("res://tests/helpers.gd")
const Balance := preload("res://tools/balance.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const NightCalls := preload("res://scripts/sim/night_calls.gd")
const NightKit := preload("res://scripts/ui/night_kit.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const DAY := 10    # the first Big Night of an Autumn game
const HZ := 15.0
const BUS := 3


# ----------------------------------------------------------------- helpers --

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


## A game with an avatar (Ruth) at `hour` of `day`, the real waves (off until a test turns them on).
func _game(day: int, hour: float, seed_value: int = 1) -> Dictionary:
	var g := Helpers.avatar_game(seed_value, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, day, hour)
	sim.events.clear()
	return g


func _news(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


## The HUD over a real game, as the game scene makes it (the Kit's fakes are not used: the sim is the one being played).
func _hud_for(g: Dictionary) -> Dictionary:
	var holder := Control.new()
	holder.size = Vector2(1280, 800)
	Engine.get_main_loop().root.add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	hud.on_select = func(_s): pass
	hud.on_focus = func(_p): pass
	hud.on_speed = func(_s): pass
	hud.on_gizmo = func(_id): pass
	hud.on_alert = func(_id): pass
	hud.on_sound = func(): pass
	hud.setup(g.data, g.sim.people)
	return {"holder": holder, "hud": hud}


# ------------------------------------------------------- the day-ahead notice --

func test_the_real_notice_of_the_siege_comes_at_noon_of_day_nine_from_a_staffed_desk() -> void:
	var g := _game(DAY - 1, 11.9)
	var sim = g.sim
	var theme := NightData.theme("siege")
	check(sim.waves.big_night(DAY - 1).is_empty(), "day 9's own night is an ordinary one")
	var tomorrow: Dictionary = sim.waves.outlook(DAY)
	eq(String(tomorrow.get("kind", "")), "milestone", "tomorrow is a Big Night by the real waves: %s" % str(tomorrow.get("kind")))
	eq(String(tomorrow.get("name", "")), String(theme.name), "The Siege")
	check(Helpers.seat(sim, _p(sim, "walt"), "radio"), "Walt is at the radio desk")
	Helpers.run(sim, 0.3)
	eq(_news(sim, "forecast").size(), 0, "before noon: nothing")
	Helpers.at(sim, DAY - 1, 12.0)
	Helpers.run(sim, 0.3)
	var notes := _news(sim, "forecast")
	eq(notes.size(), 1, "at noon the radio says it")
	if not notes.is_empty():
		eq(String(notes[0].text), "Big Night tomorrow: %s" % String(theme.name), "who and what")
		var home := NightCalls.clock_text(float(sim.seasons.dusk_hour()) - NightData.num("forecast.road_margin_min") / 60.0)
		check(String(notes[0].sub).contains("Be home by %s." % home), "and when to be home: %s" % String(notes[0].sub))
		check(String(notes[0].sub).contains("About %d to %d" % [int(tomorrow.low), int(tomorrow.high)]), "and how many: %s" % String(notes[0].sub))
		check(String(notes[0].sub).contains("plated brutes"), "and the plated brutes: %s" % String(notes[0].sub))
		check(notes[0].options.is_empty(), "it is news, not a call")
	check(sim.alerts.has("bignight-next"), "with an alert")
	var badge: Dictionary = NightKit.badge(sim, sim.tactics.forecast())
	eq(String(badge.get("state", "")), "tomorrow", "and the badge by the day counter says so")
	g.world.free()


func test_nobody_at_the_desk_no_notice_and_the_night_comes_all_the_same() -> void:
	var g := _game(DAY - 1, 11.9)
	var sim = g.sim
	for p in sim.people:
		if sim.jobs.job_of(p) == "radio":
			sim.jobs.unassign(p)
	check(sim.jobs.operator("radio") == null, "nobody is at the radio desk")
	Helpers.at(sim, DAY - 1, 12.0)
	Helpers.run(sim, 0.5)
	eq(_news(sim, "forecast").size(), 0, "no notice")
	check(not sim.waves.big_night(DAY).is_empty(), "(the Big Night is coming all the same)")
	g.world.free()


# ----------------------------------------------------------------- the plan --

func test_the_real_plan_of_the_siege_has_plated_brutes_in_the_middle_of_the_night_at_one_wall() -> void:
	var g := _game(DAY, 8.0)
	var sim = g.sim
	var theme := NightData.theme("siege")
	var plan: Dictionary = sim.waves.plan_for(DAY)
	eq(String(plan.kind), "milestone", "a milestone night")
	eq(String(plan.id), "siege", "the siege")
	check(bool(plan.plated), "its brutes are plated")
	near(float(plan.main_share), float(theme.main_share), 1.0e-9, "most of it from one side")
	eq((plan.heading as Array).size(), 1, "one heading")
	var queue: Array = plan.queue
	var brutes: Array = []
	for i in queue.size():
		if queue[i] == "brute":
			brutes.append(i)
	check(brutes.size() >= 2, "at least two brutes at this crew (%d)" % brutes.size())
	var lo: float = float(theme.brute_at[0])
	var hi: float = float(theme.brute_at[1])
	for i in brutes:
		var at: float = float(i) / float(queue.size())
		check(at >= lo - 0.05 and at <= hi + 0.05, "a brute at %.2f of the night, inside %.2f to %.2f" % [at, lo, hi])
	var outlook: Dictionary = sim.waves.outlook(DAY)
	eq(int(outlook.plated), brutes.size(), "the outlook counts them")
	check((outlook.sections as Array).size() >= 1, "and names the wall they come to")
	g.world.free()


# ------------------------------------------------------------- the night played --

## A Big Night's evening of day 10 at 16:55 with Marcus on the lookout, the informed policy keeping the community (as the harness does) and
## `mode` ("idle", "bot") in Ruth's hands. {"g", "sim", "bot", "policy", "stats", "mode"}.
func _evening(seed_value: int, mode: String) -> Dictionary:
	var g := _game(DAY, 16.9, seed_value)
	var sim = g.sim
	sim.waves.enabled = true
	sim.rng.seed = seed_value * 1000 + 7
	Helpers.seat(sim, _p(sim, "marcus"), "watch")
	var bot = BotLib.AvatarBot.new(sim, mode)
	var policy := Balance.policy_for(sim, false, true)
	policy._jobs_day = sim.day
	policy._lots_day = sim.day
	policy._build_day = sim.day
	policy._sent_day = sim.day
	var stats := BotLib.NightStats.new(sim, mode)
	return {"g": g, "sim": sim, "bot": bot, "policy": policy, "stats": stats, "mode": mode}


## The night played to the first step of the next day (or the game's end). `each_second` is called with the evening once a second.
func _play(m: Dictionary, each_second: Callable = Callable()) -> void:
	var sim = m.sim
	var dt := 1.0 / HZ
	var every := roundi(HZ)
	var step := 0
	while sim.over == "" and sim.day <= DAY:
		m.bot.step(dt)
		sim.update(dt)
		m.stats.observe(dt)
		step += 1
		if step % every == 0:
			m.policy.tick()
			if each_second.is_valid():
				each_second.call(m)
	m.stats.finish()


func _row(m: Dictionary) -> Dictionary:
	var rows: Array = m.stats.rows
	return rows[rows.size() - 1] if not rows.is_empty() else {}


func test_a_real_big_night_plated_brutes_arrive_the_calls_come_and_the_card_shows_the_urgent_one() -> void:
	var m := _evening(3, "bot")
	var sim = m.sim
	var hud_set := _hud_for(m.g)
	var hud = hud_set.hud
	var seen := {"plated": 0, "multi": 0, "wrong": 0, "kinds": {}, "card": 0, "idea": 0, "urgent_with_idea": 0}
	_play(m, func(mm):
		# an idea that someone brought at 17:18 (round 20), open for twelve hours: the old card showed the OLDEST call, and so hid the wall
		# (it was six hours until the round 19 tuning, which moved the first wall's call, a plated brute's at about 23:45, past the idea's end)
		if int(seen.idea) == 0 and float(mm.sim.hour) >= 17.3:
			seen.idea = mm.sim.radio.raise_call("idea", "Ana has an idea", "A cot for the infirmary", [{"id": "yes", "label": "Yes"}, {"id": "later", "label": "Later"}], "later", 720.0)
		for z in mm.sim.zombies:
			if bool(z.plated) and z.state != "dead" and z.state != "dying":
				seen.plated = maxi(int(seen.plated), 1)
		var open: Array = mm.sim.radio.open_calls()
		for e in open:
			seen.kinds[String(e.kind)] = true
		if open.size() >= 2:
			# a second of the night with two calls open: the card must be the most urgent, never merely the oldest
			hud.update_hud(mm.sim, 1, true, 0)
			seen.multi = int(seen.multi) + 1
			var want: Dictionary = RadioKit.most_urgent(open)
			if hud.call_card.shown_id != int(want.id):
				seen.wrong = int(seen.wrong) + 1
			if RadioKit.urgency_of(String(want.kind)) < 2:
				seen.urgent_with_idea = int(seen.urgent_with_idea) + 1
				if int(hud.call_card.shown_id) == int(seen.idea):
					seen.wrong = int(seen.wrong) + 1
		elif open.size() == 1:
			hud.update_hud(mm.sim, 1, true, 0)
			if hud.call_card.shown_id == int(open[0].id):
				seen.card = int(seen.card) + 1
	)
	check(int(seen.plated) == 1, "plated brutes arrived in the night")
	var kinds: Dictionary = seen.kinds
	check(kinds.has("night"), "the forecast's call was made at 17:00 (%s)" % str(kinds.keys()))
	check(kinds.has("brute") or kinds.has("going") or kinds.has("breach"), "and the night raised calls for a wall or a brute (%s)" % str(kinds.keys()))
	check(int(seen.urgent_with_idea) > 0, "(a wall's or a brute's call was open beside the idea for %d seconds)" % int(seen.urgent_with_idea))
	eq(int(seen.wrong), 0, "whenever two calls were open the HUD's card was the most urgent, never the older idea (%d seconds)" % int(seen.multi))
	check(int(seen.card) > 0, "and a single open call was the card (%d seconds)" % int(seen.card))
	var row := _row(m)
	eq(String(row.get("kind", "")), "milestone", "the night's row says it was a Big Night")
	check(int(row.get("plated", 0)) >= 2, "with its plated brutes counted: %s" % str(row.get("plated")))
	var av: Dictionary = row.get("avatar", {})
	check(int(av.get("shots", 0)) > 0, "the bot fired: %s" % str(av.get("shots")))
	check(float(av.get("present", 0.0)) > 0.2, "and stood where the pressure was: presence %.2f" % float(av.get("present", 0.0)))
	check(int((row.get("calls", {}) as Dictionary).get("answered_by_player", 0)) > 0, "and answered calls: %s" % str(row.get("calls")))
	hud_set.holder.free()
	m.g.world.free()


func test_an_idle_avatar_is_never_where_the_pressure_is() -> void:
	var m := _evening(3, "idle")
	_play(m)
	var row := _row(m)
	var av: Dictionary = row.get("avatar", {})
	eq(float(av.get("present", -1.0)), 0.0, "idle: presence 0")
	eq(int(av.get("shots", -1)), 0, "and no shot")
	m.g.world.free()


func test_the_bot_holds_a_big_night_more_often_than_an_idle_avatar() -> void:
	# the same evening (same seed, same dice) three ways round, over a few seeds: a held night is no section fallen and nobody dead
	var held := {"idle": 0, "bot": 0}
	var fell := {"idle": 0.0, "bot": 0.0}
	var lost := {"idle": 0.0, "bot": 0.0}
	var nights := 0
	for seed_value in [3, 4, 5, 6]:
		nights += 1
		for mode in ["idle", "bot"]:
			var m := _evening(seed_value, mode)
			_play(m)
			var row := _row(m)
			held[mode] += 1 if bool(row.get("held", false)) else 0
			fell[mode] += float(row.get("sections_fell", 0))
			lost[mode] += float(row.get("hp_lost", 0.0))
			m.g.world.free()
	check(held.bot >= held.idle, "the bot holds the Big Night at least as often as idle: %d against %d of %d" % [held.bot, held.idle, nights])
	check(held.bot > held.idle or fell.bot < fell.idle or lost.bot < lost.idle,
		"and it is a difference: held %d against %d, sections fallen %.0f against %.0f, wall lost %.0f against %.0f" % [held.bot, held.idle, fell.bot, fell.idle, lost.bot, lost.idle])


# ------------------------------------------------------ the avatar mends a breach by E --

func test_the_bot_answers_a_breach_walks_to_it_and_mends_it_with_the_real_e() -> void:
	var g := _game(DAY, 22.0)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.stock.scrap = 60.0
	sim.stock.ammo = 0.0
	for p in sim.people:
		if not p.player:
			p.x = 20.0
			p.y = 60.0
			p.path = []
			p.goal_key = ""
	var seg = _seg(sim, BUS)
	var bot = BotLib.AvatarBot.new(sim, "bot")
	var me = sim.avatar.player()
	me.x = 34.5
	me.y = 32.5
	me.path = []
	sim.radio.night.seen[BUS] = 0
	seg.hp = 0.0
	sim._segment_state(seg)
	check(seg.state == 3, "the bus is down")
	var dt := 1.0 / HZ
	var shut_at := -1.0
	var worked := false
	var t := 0.0
	while t < 90.0 and shut_at < 0.0:
		bot.step(dt)
		sim.update(dt)
		t += dt
		worked = worked or String(sim.nights.working) == "wall"
		if seg.state != 3 and seg.hp / seg.max_hp > 0.4 - 1.0e-6:
			shut_at = t
	var calls := _news(sim, "breach")
	var asked := false
	for e in calls:
		if not e.options.is_empty():
			asked = true
			eq(String(e.answered), "close", "the breach call was answered: close it")
	check(asked, "the radio raised a breach call")
	check(bot.mends > 0 and worked, "the bot pressed E at the wall (%d times) and the avatar's hands worked there" % bot.mends)
	check(shut_at > 0.0, "the wall stands again above %d%% within %.0f seconds" % [int(NightData.num("breach.close_share", 0.4) * 100.0), t])
	var shut_news := false
	for e in calls:
		if String(e.text).contains("is shut again"):
			shut_news = true
	check(shut_news, "and the radio says it is shut again")
	check(sim.stock.scrap < 60.0, "the scrap it cost is gone: %.0f" % sim.stock.scrap)
	g.world.free()


# ------------------------------------------------------------- a trip out at dusk --

func test_a_trip_out_at_dusk_is_warned_and_the_avatar_comes_home_in_the_dark() -> void:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	var g := _game(DAY, 8.0)
	var sim = g.sim
	var note: Dictionary = sim.scavenge.night_warning("houses", "", 1.0)
	check(bool(note.big) and String(note.text).begins_with("Big Night tonight"), "the Map says tonight is a Big Night (the real waves): %s" % String(note.text))
	var flow = PlaceFlow.new(sim)
	check(flow.begin([_p(sim, "ruth"), _p(sim, "dez")], "houses", ""), "the trip begins: %s" % flow.error)
	var party: Dictionary = flow.party
	check(bool(party.get("live", false)), "it is a live drive")
	var road: float = sim.scavenge.road_minutes("houses", "")
	var margin: float = NightData.num("forecast.road_margin_min")
	# in the place, an hour before the hour to leave by: the radio warns
	Helpers.at(sim, DAY, float(sim.seasons.dusk_hour()) - (margin + road) / 60.0 - 0.5)
	Helpers.run(sim, 0.2)
	var soon := _news(sim, "night_road")
	eq(soon.size(), 1, "a line at 'soon'")
	if not soon.is_empty():
		check(String(soon[0].text).contains("a Big Night with it") and String(soon[0].text).contains("leave by"), soon[0].text)
	# at the hour: the call
	Helpers.at(sim, DAY, float(sim.seasons.dusk_hour()) - (margin + road) / 60.0)
	Helpers.run(sim, 0.2)
	var ask: Dictionary = {}
	for e in _news(sim, "night_road"):
		if not e.options.is_empty():
			ask = e
	check(not ask.is_empty(), "and the call to head home at the hour to leave by")
	if not ask.is_empty():
		check(String(ask.sub).contains("in the dark"), "which says what staying means for a trip he drives: %s" % String(ask.sub))
	# he stays: the bell rings with him in the place
	Helpers.at(sim, DAY, float(sim.seasons.dusk_hour()) + 0.2)
	Helpers.run(sim, 0.2)
	var still := false
	for e in _news(sim, "night_road"):
		if String(e.text).begins_with("You are still out"):
			still = true
	check(still, "the radio notes that he is still out when the bell rings")
	# the place is over, the road home is driven in the dark, and the party comes in at the gate by night
	sim.scavenge.finish_played(party, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	flow.begin_leg("home")
	var st: Dictionary = sim.radio.night.road_status()
	eq(String(st.stage), "home", "on the road home")
	check(bool(st.live) and not String(st.text).contains("out tonight"), "which is not 'out tonight': %s" % String(st.text))
	Helpers.at(sim, DAY, float(sim.seasons.dusk_hour()) + 2.0)
	Helpers.run(sim, 1.0)
	check(not sim.scavenge.parties.is_empty(), "the colony does not bring them in by its own clock while the drive is on")
	sim.scavenge.arrive_home(party)
	var guard := 0
	while not sim.scavenge.parties.is_empty() and guard < 100:
		Helpers.run(sim, 1.0)
		guard += 1
	check(sim.scavenge.parties.is_empty(), "the drive ends at the gate and they are home, at night")
	check(String(sim.phase) != "day", "(it is %s)" % sim.phase)
	PlaceFlow.live_enabled = true
	g.world.free()


# --------------------------------------------------------------- a save from before --

func test_a_save_from_before_the_round_loads_and_plays_a_night() -> void:
	var m := _evening(5, "bot")
	var sim = m.sim
	Helpers.run(sim, 2.0)
	var d: Dictionary = SaveGame.to_dict(sim)
	# a round 18 save has none of what the round added: the radio's night module, the nights' own module, the alarm's flag, and no plated zombie
	var mods: Dictionary = d.get("modules", {})
	check(mods.has("radio") and (mods.radio as Dictionary).has("night"), "(the save has the radio's night module: %s)" % str((mods.get("radio", {}) as Dictionary).keys()))
	(mods.radio as Dictionary).erase("night")
	mods.erase("nights")
	(mods.tactics as Dictionary).erase("lure_brutes")
	for z in d.get("zombies", []):
		(z as Dictionary).erase("plated")
	var g2 := Helpers.make(5, 1, 5)
	var s2 = g2.sim
	check(SaveGame.apply(s2, d), "the save loads")
	check(s2.avatar.set_player("ruth") or String(s2.player_id) == "ruth", "Ruth plays")
	var bot2 = BotLib.AvatarBot.new(s2, "bot")
	var stats2 := BotLib.NightStats.new(s2, "bot")
	var steps := 0
	while s2.over == "" and s2.day <= DAY and steps < int(HZ) * 400:
		bot2.step(1.0 / HZ)
		s2.update(1.0 / HZ)
		stats2.observe(1.0 / HZ)
		steps += 1
	stats2.finish()
	check(s2.day > DAY or s2.over != "", "the night was played to its end (day %d, %s)" % [s2.day, s2.over])
	check(not stats2.rows.is_empty(), "with a row of it")
	g2.world.free()
	m.g.world.free()
