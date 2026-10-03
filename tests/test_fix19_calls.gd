extends "res://tests/case.gd"
## Fixes of the review of round 19, the calls of the night (F1, F2, F3, F7; docs: scratchpad review r19.md):
##   F1  the call card shows the most urgent open call, not the oldest; a `brute` call is settled when `going` or `breach` is raised for
##       the same wall; the card says how many others wait (they are in the News)
##   F2  the calls' timers are game minutes: when an urgent call is raised (a wall, a brute, the night) the game drops to 1x once and says so
##   F3  the alarm of the `night` call lasts until the night's brutes are dead or the dawn (it rang for three hours from 17:00 and the
##       brutes come after midnight)
##   F7  "I'm on my way" is a promise: from the wall itself it is no promise, and trust is paid once for each person a day
## Real waves, radio and sim throughout (the Big Night is the real day 10); numbers are read through NightData.

const Helpers := preload("res://tests/helpers.gd")
const Kit := preload("res://tests/hud_kit.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const NightCalls := preload("res://scripts/sim/night_calls.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")

const LEADER_AT := Vector2(34.5, 32.5)
const BUS := 3    # the school bus on the north wall: centre (47.5, 18.9), Dez's post is there
const BIG_DAY := 10


# ----------------------------------------------------------------- helpers --

## A quiet game with an avatar (Ruth, in the yard) at `hour` of `day`: no waves, no dead about, the guns dry.
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


func _hurt(sim, id: int, share: float) -> void:
	var s = _seg(sim, id)
	s.hp = s.max_hp * share
	sim._segment_state(s)


func _calls(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


func _open(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.open_calls():
		if e.kind == kind:
			out.append(e)
	return out


## A brute on its way to the bus, a plated one, with its place at the wall.
func _brute_to(sim, seg_id: int, from: Vector2):
	var z = sim.spawn(from.x, from.y, "approach", "brute")
	z.plated = true
	check(sim.assign_slot(z, _seg(sim, seg_id)), "the brute has a place at the wall")
	return z


## The wall of the bus going: three of the dead at it, under the going mark.
func _wall_goes(sim) -> void:
	Helpers.attack(sim, BUS, 3)
	_hurt(sim, BUS, NightData.num("calls.going_below") - 0.05)


## A call of the kind `going` with the promise among its options, raised by hand (the night module's own is once for a wall a night).
func _going_call(radio) -> int:
	return radio.raise_call("going", "The bus is going", "", [{"id": "hold", "label": "Hold"}, {"id": "coming", "label": "I'm on my way"}], "hold", 20.0, {"seg": BUS}, Vector2(47.5, 18.9))


func _call(radio, kind: String, ttl: float, seg: int = 1) -> int:
	return radio.raise_call(kind, "%s call" % kind, "", [{"id": "hold", "label": "Hold"}, {"id": "other", "label": "Other"}], "hold", ttl, {"seg": seg}, Vector2(40, 10))


# ===================================================================== F1 ==

func test_a_brute_call_is_settled_when_going_is_raised_for_its_wall() -> void:
	var g := _game()
	var sim = g.sim
	_brute_to(sim, BUS, Vector2(52.0, 10.2))
	Helpers.run(sim, 0.1)
	eq(_open(sim, "brute").size(), 1, "the brute on its way is a call")
	var brute: Dictionary = _calls(sim, "brute")[0]
	_wall_goes(sim)
	Helpers.run(sim, 0.1)
	eq(_open(sim, "going").size(), 1, "then the wall is going")
	eq(String(brute.answered), "watch", "the brute call is settled by its default: the wall's call says more")
	check(bool(brute.by_default), "by default")
	var open: Array = sim.radio.open_calls()
	eq(open.size(), 1, "one open call for one wall: %s" % str(open.map(func(e): return e.kind)))
	g.world.free()


func test_a_brute_call_is_settled_when_the_wall_it_comes_to_falls() -> void:
	var g := _game()
	var sim = g.sim
	_brute_to(sim, BUS, Vector2(52.0, 10.2))
	Helpers.run(sim, 0.1)
	var brute: Dictionary = _calls(sim, "brute")[0]
	eq(String(brute.answered), "", "the brute call is open")
	_hurt(sim, BUS, 0.0)
	Helpers.run(sim, 0.1)
	eq(_open(sim, "breach").size(), 1, "the wall is down: a breach call")
	eq(String(brute.answered), "watch", "and the brute call is over")
	eq(sim.radio.open_calls().size(), 1, "one open call for the wall: %s" % str(sim.radio.open_calls().map(func(e): return e.kind)))
	g.world.free()


func test_a_brute_that_comes_to_a_wall_already_going_is_still_told() -> void:
	var g := _game()
	var sim = g.sim
	_wall_goes(sim)
	Helpers.run(sim, 0.1)
	eq(_open(sim, "going").size(), 1, "the wall is going")
	_brute_to(sim, BUS, Vector2(52.0, 10.2))
	Helpers.run(sim, 0.1)
	eq(_open(sim, "brute").size(), 1, "a brute that comes to it afterwards is news (the alarm can draw it to another wall)")
	var best = RadioKit.most_urgent(sim.radio.open_calls())
	eq(String(best.kind), "going", "and the wall that is going is the one in front")
	g.world.free()


func test_the_most_urgent_call_is_the_one_in_front_not_the_oldest() -> void:
	var g := _game()
	var sim = g.sim
	var radio = sim.radio
	var idea := _call(radio, "idea", 360.0)
	var fever := _call(radio, "sick", 60.0)
	eq(int(RadioKit.most_urgent(radio.open_calls()).id), fever, "a fever (an hour) before an idea (six)")
	var brute := _call(radio, "brute", 45.0)
	eq(int(RadioKit.most_urgent(radio.open_calls()).id), brute, "a brute before a fever")
	var going := _call(radio, "going", 20.0)
	eq(int(RadioKit.most_urgent(radio.open_calls()).id), going, "a wall that is going before a brute")
	var breach := _call(radio, "breach", 20.0)
	eq(int(RadioKit.most_urgent(radio.open_calls()).id), going, "a breach and a going wall tie on the kind: the least time left, then the oldest")
	sim.clock_min += 5.0
	var later := _call(radio, "breach", 20.0, 2)
	eq(int(RadioKit.most_urgent(radio.open_calls()).id), going, "the one that runs out first stays in front")
	check(idea != breach and later != breach, "(distinct calls)")
	# answered ones are not open
	radio.answer(going, "hold")
	eq(int(RadioKit.most_urgent(radio.open_calls()).id), breach, "the next one comes up")
	eq(RadioKit.most_urgent([]), {}, "nothing: nothing")
	g.world.free()


func test_the_card_shows_the_wall_that_is_going_over_an_older_idea_and_says_how_many_wait() -> void:
	var ctx := Kit.build(1280, 800)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "Ruth plays")
	var radio = sim.radio
	var h = ctx.hud
	Kit.update(ctx)
	var idea := _call(radio, "idea", 360.0)
	Kit.update(ctx)
	eq(h.call_card.shown_id, idea, "alone, the idea is the card")
	check(not h.call_card.view.count_label.text.contains("more"), "and says nothing of others: %s" % h.call_card.view.count_label.text)
	var brute := _call(radio, "brute", 45.0)
	var going := _call(radio, "going", 20.0)
	Kit.update(ctx)
	await Kit.settle()
	eq(h.call_card.shown_id, going, "the wall that is going, though two calls are older")
	check(h.call_card.view.count_label.text.contains("+2 more in the News"), "the card says two more wait: %s" % h.call_card.view.count_label.text)
	h.toggle_news()
	Kit.update(ctx)
	eq(h.news_panel.call_ids(), [going, brute, idea], "the News lists them all, the card's call first")
	h.toggle_news()
	Kit.update(ctx)
	h.call_card.view.buttons["hold"].pressed.emit()
	Kit.update(ctx)
	eq(h.call_card.shown_id, brute, "answered: the brute is next")
	check(h.call_card.view.count_label.text.contains("+1 more in the News"), "with one more behind it: %s" % h.call_card.view.count_label.text)
	Kit.free_all(ctx)


# ===================================================================== F2 ==

## The game scene as test_radio_ui's bark test builds it; `then` is called with it, and the window is put back.
func _main_with(avatar: bool, then: Callable) -> void:
	var win: Window = Engine.get_main_loop().root
	var saved := {"size": win.size, "position": win.position, "mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "scale_size": win.content_scale_size}
	Engine.set_meta("run", {"difficulty": 1, "seed": 7})
	var main = load("res://scenes/main.tscn").instantiate()
	win.add_child(main)
	main.set_process(false)
	if avatar:
		main.sim.avatar.set_player("ruth")
	main.sim.events.clear()
	then.call(main)
	main.queue_free()
	await Engine.get_main_loop().process_frame
	win.content_scale_mode = saved.mode
	win.content_scale_aspect = saved.aspect
	win.content_scale_size = saved.scale_size
	win.size = saved.size
	win.position = saved.position


func test_an_urgent_call_drops_the_game_to_one_times_once_and_says_so() -> void:
	await _main_with(true, func(main):
		var radio = main.sim.radio
		main.speed = 3
		_call(radio, "going", 20.0)
		main._handle_events()
		eq(main.speed, 1, "a wall that is going: the game is slowed to 1x")
		var said: String = main.hud.toast_label.text
		check(said.to_lower().contains("slowing down") and said.to_lower().contains("call is waiting"), "and says so: %s" % said)
		main._set_speed(3)
		main._handle_events()
		eq(main.speed, 3, "the player can speed up again, and nothing slows it again for the same call")
		_call(radio, "breach", 20.0, 2)
		main._handle_events()
		eq(main.speed, 1, "a new urgent call slows it again")
		main.speed = 2
		_call(radio, "brute", 45.0, 3)
		_call(radio, "attack", 30.0, 4)
		main._handle_events()
		eq(main.speed, 1, "a brute and an attack are urgent too")
		main.speed = 3
		_call(radio, "night", 80.0)
		main._handle_events()
		eq(main.speed, 1, "and so is the night's own call")
	)


func test_a_calm_call_or_a_game_already_slow_or_paused_is_left_alone() -> void:
	await _main_with(true, func(main):
		var radio = main.sim.radio
		main.speed = 3
		_call(radio, "idea", 360.0)
		_call(radio, "sick", 60.0)
		main._handle_events()
		eq(main.speed, 3, "an idea or a fever does not slow the game")
		main.speed = 1
		_call(radio, "going", 20.0, 2)
		main._handle_events()
		eq(main.speed, 1, "at 1x nothing changes")
		main.speed = 0
		_call(radio, "going", 20.0, 3)
		main._handle_events()
		eq(main.speed, 0, "a paused game stays paused")
	)


func test_a_call_that_is_already_answered_does_not_slow_the_game() -> void:
	await _main_with(true, func(main):
		var radio = main.sim.radio
		var id := _call(radio, "going", 20.0)
		radio.answer(id, "hold")
		main.speed = 3
		main._handle_events()
		eq(main.speed, 3, "answered before the frame was handled: nothing to wait for")
	)


func test_the_old_game_without_an_avatar_is_not_slowed() -> void:
	await _main_with(false, func(main):
		main.speed = 3
		_call(main.sim.radio, "going", 20.0)
		main._handle_events()
		eq(main.speed, 3, "no avatar: the classic game as it was")
	)


# ===================================================================== F3 ==

## The real Big Night of day 10 at 17:00 with Marcus on the lookout: the forecast and its `night` call, the best alarm option, scrap in store.
func _siege_evening() -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, BIG_DAY, 16.99)
	sim.stock.scrap = 30.0
	sim.stock.ammo = 0.0
	var lead = _p(sim, "ruth")
	_put(lead, LEADER_AT)
	Helpers.seat(sim, _p(sim, "marcus"), "watch")
	Helpers.run(sim, 0.6)
	return g


func _night_call(sim) -> Dictionary:
	var calls := _open(sim, "night")
	check(calls.size() == 1, "the night call is open (a Big Night at day %d: %d)" % [BIG_DAY, calls.size()])
	return calls[0] if not calls.is_empty() else {}


func test_the_real_day_ten_is_a_big_night_with_brutes() -> void:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	check(not sim.waves.big_night(BIG_DAY).is_empty(), "day %d is a Big Night" % BIG_DAY)
	var brutes := 0
	for k in sim.waves.plan_for(BIG_DAY).queue:
		if k == "brute":
			brutes += 1
	check(brutes >= 2, "with plated brutes in the queue (%d)" % brutes)
	g.world.free()


func test_the_night_calls_alarm_rings_until_the_brutes_are_dead_or_the_dawn() -> void:
	var g := _siege_evening()
	var sim = g.sim
	var c := _night_call(sim)
	check(not c.is_empty() and _ids_of(c).has("lure"), "the alarm is offered with the night call: %s" % str(_ids_of(c)))
	if c.is_empty():
		g.world.free()
		return
	check(String(_option(c, "lure").label).to_lower().contains("brutes"), "and its words say how long: %s" % String(_option(c, "lure").label))
	var scrap: float = sim.stock.scrap
	check(sim.radio.answer(int(c.id), "lure"), "the player sets it")
	near(sim.stock.scrap, scrap - sim.tactics.LURE_COST, 0.0001, "for the scrap it says")
	check(sim.tactics.lure_seg() != null, "it rings")
	var to_dawn: float = fposmod(float(sim.seasons.dawn_hour()) - float(sim.hour), 24.0) * 60.0
	check(sim.tactics.lure_left_min() > sim.tactics.LURE_HOURS * 60.0 + 60.0, "far longer than three hours: %.0f minutes" % sim.tactics.lure_left_min())
	check(sim.tactics.lure_left_min() <= to_dawn + 0.5, "and never past the dawn (%.0f of %.0f)" % [sim.tactics.lure_left_min(), to_dawn])
	# the night: the dusk bell, midnight, the brutes (not yet spawned) are still to come
	var seg = sim.tactics.lure_seg()
	Helpers.at(sim, BIG_DAY, 23.5)
	Helpers.run(sim, 1.2)
	check(sim.tactics.lure_seg() == seg, "at half past eleven, three hours on, it still rings: the brutes have not come")
	# the brutes have come (all spawned) and one is alive
	sim.waves.night_day = BIG_DAY
	sim.waves.spawned = (sim.waves.plan_for(BIG_DAY).queue as Array).size()
	var brute = sim.spawn(40.0, 10.0, "approach", "brute")
	Helpers.run(sim, 1.2)
	check(sim.tactics.lure_seg() == seg, "all of them spawned and a brute alive: it rings")
	brute.state = "dead"
	Helpers.run(sim, 1.2)
	check(sim.tactics.lure_seg() == null, "the last brute is dead: the alarm stops")
	g.world.free()


func test_the_night_calls_alarm_stops_at_dawn_with_a_brute_still_alive() -> void:
	var g := _siege_evening()
	var sim = g.sim
	var c := _night_call(sim)
	if c.is_empty():
		g.world.free()
		return
	sim.radio.answer(int(c.id), "lure")
	check(sim.tactics.lure_seg() != null, "it rings")
	sim.spawn(40.0, 10.0, "approach", "brute")
	Helpers.at(sim, BIG_DAY + 1, sim.seasons.dawn_hour() + 0.05)
	Helpers.run(sim, 0.2)
	check(sim.tactics.lure_seg() == null, "at dawn it stops, brutes or not")
	g.world.free()


func test_an_alarm_set_by_hand_or_from_the_brute_call_is_still_three_hours() -> void:
	var g := _game(BIG_DAY, 22.0)
	var sim = g.sim
	sim.stock.scrap = 30.0
	var seg = _seg(sim, BUS)
	check(sim.tactics.order_lure(seg), "the old key sets the alarm")
	near(sim.tactics.lure_left_min(), sim.tactics.LURE_HOURS * 60.0, 0.5, "for three hours")
	g.world.free()
	var h := _game(BIG_DAY, 22.0)
	var s2 = h.sim
	s2.stock.scrap = 30.0
	_brute_to(s2, BUS, Vector2(52.0, 10.2))
	Helpers.run(s2, 0.1)
	var c: Dictionary = _calls(s2, "brute")[0]
	if _ids_of(c).has("lure"):
		check(s2.radio.answer(int(c.id), "lure"), "the brute call's lure")
		near(s2.tactics.lure_left_min(), s2.tactics.LURE_HOURS * 60.0, 0.5, "three hours: the brute is on its way now")
	h.world.free()


func test_the_alarm_until_the_brutes_are_down_survives_a_save() -> void:
	var g := _siege_evening()
	var sim = g.sim
	var c := _night_call(sim)
	if c.is_empty():
		g.world.free()
		return
	sim.radio.answer(int(c.id), "lure")
	var saved: Dictionary = sim.tactics.save()
	var h := Helpers.avatar_game(1, 5)
	var s2 = h.sim
	Helpers.at(s2, BIG_DAY, 17.5)
	s2.tactics.load_state(saved)
	eq(s2.tactics.lure_id, sim.tactics.lure_id, "the wall")
	near(s2.tactics.lure_until, sim.tactics.lure_until, 0.001, "the time")
	eq(s2.tactics.lure_brutes, true, "and that it is the alarm for the brutes")
	h.world.free()
	g.world.free()


func _ids_of(c: Dictionary) -> Array:
	var out: Array = []
	for o in c.options:
		out.append(String(o.id))
	return out


func _option(c: Dictionary, id: String) -> Dictionary:
	for o in c.options:
		if String(o.id) == id:
			return o
	return {}


# ===================================================================== F7 ==

## A wall going with Dez at the bus and the avatar where `at` says.
func _going_with(sim, at: Vector2) -> Dictionary:
	_put(_p(sim, "dez"), Vector2(47.5, 24.0))
	_put(_p(sim, "ruth"), at)
	_wall_goes(sim)
	Helpers.run(sim, 0.1)
	return _calls(sim, "going")[0]


func test_i_am_on_my_way_from_the_wall_itself_is_no_promise() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var c := _going_with(sim, Vector2(47.5, 24.5))    # (already among them)
	var trust: float = dez.trust
	var mood: float = sim.morale.value(dez)
	check(sim.radio.answer(int(c.id), "coming"), "he says it")
	Helpers.run(sim, 0.3)
	near(dez.trust, trust, 0.0001, "he is there already: nothing is earned")
	near(sim.morale.value(dez), mood, 0.0001, "nobody is lifted by help that is already here")
	check(sim.radio.night.focus.is_empty(), "and nothing is promised")
	check(String(c.result).to_lower().contains("already"), "the line says so: %s" % String(c.result))
	g.world.free()


func test_the_same_promise_farmed_three_times_pays_trust_once() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var bus_spot := Vector2(47.5, 24.5)
	var c := _going_with(sim, LEADER_AT)
	var trust: float = dez.trust
	check(sim.radio.answer(int(c.id), "coming"), "from afar: a real promise")
	_put(_p(sim, "ruth"), bus_spot)
	Helpers.run(sim, 0.2)
	var paid := NightData.num("calls.kept_trust")
	near(dez.trust, trust + paid, 0.0001, "kept: paid")
	# the same night: he steps away, says it again, and is back at once; three times
	var farm := 0
	for i in 3:
		_put(_p(sim, "ruth"), LEADER_AT)
		check(sim.radio.answer(_going_call(sim.radio), "coming"), "he promises again")
		_put(_p(sim, "ruth"), bus_spot)
		Helpers.run(sim, 0.2)
		farm += 1
	eq(farm, 3, "(three more promises)")
	near(dez.trust, trust + paid, 0.0001, "trust is paid once for a person a day, however often he promises and arrives: %.1f" % (dez.trust - trust))
	g.world.free()


func test_the_next_day_a_promise_kept_pays_again() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var bus_spot := Vector2(47.5, 24.5)
	var c := _going_with(sim, LEADER_AT)
	sim.radio.answer(int(c.id), "coming")
	_put(_p(sim, "ruth"), bus_spot)
	Helpers.run(sim, 0.2)
	var trust: float = dez.trust
	Helpers.at(sim, 4, 22.0)
	_put(_p(sim, "ruth"), LEADER_AT)
	sim.radio.answer(_going_call(sim.radio), "coming")
	_put(_p(sim, "ruth"), bus_spot)
	Helpers.run(sim, 0.2)
	near(dez.trust, trust + NightData.num("calls.kept_trust"), 0.0001, "a new day, a new promise kept: paid")
	g.world.free()


func test_the_trust_cap_survives_a_save() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var c := _going_with(sim, LEADER_AT)
	sim.radio.answer(int(c.id), "coming")
	_put(_p(sim, "ruth"), Vector2(47.5, 24.5))
	Helpers.run(sim, 0.2)
	var saved: Dictionary = sim.radio.night.save()
	var h := _game()
	var s2 = h.sim
	s2.radio.night.load_state(saved)
	var d2 = _p(s2, "dez")
	var trust: float = d2.trust
	_put(d2, Vector2(47.5, 24.0))
	_put(_p(s2, "ruth"), LEADER_AT)
	s2.radio.answer(_going_call(s2.radio), "coming")
	_put(_p(s2, "ruth"), Vector2(47.5, 24.5))
	Helpers.run(s2, 0.2)
	near(d2.trust, trust, 0.0001, "after a load, the same day: still paid once")
	check(dez != null, "(Dez)")
	g.world.free()
	h.world.free()
