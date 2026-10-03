extends "res://tests/case.gd"
## Round 18 ("Home"), integration: the whole slice played through the real game scene as a player plays it, the pieces the other
## test files take one at a time. A small start with the avatar (Ruth): she walks to Dez, talks (E) and asks him to come; takes the gate
## post and fires from it; works the bench and the ammo rises; opens the Jobs page with the radio panel open and moves Dez by radio while
## a night passes; orders a building from the Build page; delegates an errand from the Map page and it comes home with a smaller bag and
## its news line; a round 17 save (tests/fixtures/round17_avatar_save.json, written by the round 17 code) loads and works; and with no
## avatar none of it exists (no panel, E does nothing, an errand is the dice as before).
##
## The rules are tests/test_interact.gd's, test_errands.gd's and test_asks.gd's; the pages are test_jobs_page.gd's, test_build_page.gd's and
## test_map_page.gd's; the panel's own is test_radio_panel.gd's; the prompt and the card are test_interact_view.gd's.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const DT := 1.0 / 30.0
## Open ground in the yard (carved free of props) where the avatar walks, the bench is and Dez works.
const ARENA := Rect2i(34, 26, 20, 12)
const R17_SAVE := "res://tests/fixtures/round17_avatar_save.json"


# ----------------------------------------------------------------- helpers --

## The real game scene (a small start: Ruth, Dez and Marcus) in a window of this size, 07:00 of the first day, the dead and the
## storyteller away so that nothing but what the test does happens. `avatar` false is the old game.
func _game(avatar: bool = true, width: int = 1280, height: int = 800) -> Node:
	var meta := {"difficulty": 1, "seed": 7, "crew": 3}
	if avatar:
		meta["avatar"] = true
	var main = TutorialKit.start(meta, width, height)
	_quiet(main)
	return main


func _quiet(main: Node) -> void:
	var sim = main.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.storyteller.enabled = false
	sim.events.clear()
	main.hud.update_hud(sim, 1, true, 0)


func _arena(main: Node) -> void:
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			main.world.solid_p[ty * main.world.W + tx] = 0
			main.world.solid_z[ty * main.world.W + tx] = 0


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


func _me(main: Node):
	return main.sim.avatar.player()


func _stand(main: Node, p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.goal_key = ""
	p.order = null
	main._sync_views()


func _frames(main: Node, n: int) -> void:
	for i in n:
		main._process(DT)
		main.hud.update_hud(main.sim, main.speed, true, 0)


## The frames until `done` is true (at most `limit` of them): how many it took, -1 when it never came true.
func _until(main: Node, done: Callable, limit: int) -> int:
	for i in limit:
		if bool(done.call()):
			return i
		main._process(DT)
		main.hud.update_hud(main.sim, main.speed, true, 0)
	return limit if bool(done.call()) else -1


func _press(main: Node, code: Key, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	ev.shift_pressed = shift
	main._unhandled_input(ev)


func _hold(codes: Array, down: bool) -> void:
	for code in codes:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _draw_once(main: Node) -> void:
	main._process(DT)
	main.overlay.queue_redraw()
	await TutorialKit.settle()


## The game clock put at `hour` of `day`.
func _at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day


func _news_of(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == kind:
			out.append(e)
	return out


func _text_of(node: Node) -> String:
	var out: Array = []
	_collect(node, out)
	return " | ".join(out)


func _collect(node: Node, out: Array) -> void:
	if node is Control and not node.visible:
		return
	if node is Label and node.text != "":
		out.append(node.text)
	elif node is Button and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_collect(c, out)


# ------------------------------------------------- walk to Dez, talk, ask him --

func test_walk_to_dez_talk_and_ask_him_to_come() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	var dez = _person(main, "dez")
	check(sim.player_id == "ruth", "Ruth is the player")
	eq(sim.jobs.job_of(dez), "bench", "Dez is at the bench")
	_stand(main, me, Vector2(38.5, 34.5))
	main.cam_center = Vector2(me.x, me.y)
	_frames(main, 6)
	check(sim.interact.best().is_empty(), "nothing in reach where she starts")
	# W A S D walk her (up and to the right) until the nearest thing in reach is Dez
	_hold([KEY_W, KEY_D], true)
	var steps := _until(main, func(): return String(sim.interact.best().get("id", "")) == "dez", 200)
	_hold([KEY_W, KEY_D], false)
	check(steps >= 0, "she walked up to Dez (%d frames)" % steps)
	_frames(main, 2)
	check(Vector2(me.x, me.y).distance_to(Vector2(dez.x, dez.y)) <= sim.interact.TALK_REACH, "within the reach of a word")
	eq(String(sim.interact.best().get("kind", "")), "person", "a person beats the bench beside him")
	await _draw_once(main)
	eq(main.overlay.prompt_text, "E  Talk to Dez", "the prompt follows her to him")
	# E: the card, his line over his head, a word a day earns a little trust
	var trust0: float = sim.radio.trust_of(dez)
	_press(main, KEY_E)
	_frames(main, 2)
	check(main.hud.talk_open(), "the talk card is open")
	eq(main.hud.talk_person(), dez, "for Dez")
	check(not main.hud.modal_open(), "it is not a modal page")
	check(main.speed > 0, "the game did not stop")
	near(sim.radio.trust_of(dez), trust0 + sim.interact.TALK_TRUST, 0.001, "a word earns trust")
	eq(int(sim.interact.talked.get("dez", 0)), sim.day, "and it is noted for the day")
	var heard := false
	for b in main.overlay.bubbles:
		if b.p == dez:
			heard = true
	check(heard, "he says it in a bubble")
	# the verbs ask, they never command: "Come with me" is agreed after the radio's delay
	var verbs = main.hud.talk_card.verbs
	check(verbs.buttons.has("come") and not verbs.buttons["come"].disabled, "Come with me is on offer")
	var ans: Dictionary = verbs.press("come")
	check(bool(ans.ok), "he agrees: %s" % str(ans))
	check(float(ans.delay_s) > 0.0, "after a little while, not at once")
	eq(String(dez.stance), "", "he has not moved yet")
	var came := _until(main, func(): return String(dez.stance) == "follow", 300)
	check(came > 0, "then he follows (%d frames)" % came)
	# the same word twice in a day earns nothing the second time
	_press(main, KEY_E)    # (ends the talk)
	check(not main.hud.talk_open(), "E again ends the talk")
	var t1: float = sim.radio.trust_of(dez)
	var again: Dictionary = sim.interact.talk_to(dez)
	near(float(again.gain), 0.0, 0.0001, "no second word's worth today")
	near(sim.radio.trust_of(dez), t1, 0.0001, "trust is as it was")
	await TutorialKit.leave(main)


func test_a_refusal_in_the_talk_card_says_why_and_insisting_costs_trust() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	var dez = _person(main, "dez")
	dez.bleeding = 2.0
	_stand(main, me, Vector2(dez.x - 1.2, dez.y + 0.4))
	_frames(main, 4)
	_press(main, KEY_E)
	_frames(main, 2)
	check(main.hud.talk_open(), "the card is open")
	var card = main.hud.talk_card
	var seen := _text_of(card)
	check(seen.contains("Bleeding"), "his need is on the card: %s" % seen)
	var verbs = card.verbs
	var t0: float = sim.radio.trust_of(dez)
	var ans: Dictionary = verbs.press("cover")
	check(not bool(ans.ok), "he will not cover her while he bleeds")
	check(String(ans.why).contains("bleeding"), "and says why: '%s'" % String(ans.why))
	eq(verbs.reply.text, String(ans.why), "the reason is shown on the card")
	eq(verbs.reply.get_theme_color("font_color"), main.hud.WARN, "in amber")
	check(verbs.insist_button.visible, "Insist is there, for a soft refusal")
	var pushed: Dictionary = verbs.insist()
	check(bool(pushed.ok) and bool(pushed.insisted), "insisting overrides it")
	near(sim.radio.trust_of(dez), t0 - sim.radio.INSIST_COST, 0.001, "at a cost of trust")
	await TutorialKit.leave(main)


# -------------------------------------------------- the gate post, and fire --

func test_take_the_gate_post_and_fire_from_it() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	var gate: Dictionary = sim.jobs.post("gate")
	var gate_at := Vector2(gate.pos)
	var dez = _person(main, "dez")
	me.weapon = "rifle"
	me.gun = sim.weapons["rifle"]
	me.mag = int(me.gun.mag)
	_at(sim, 2, 22.0)
	sim.stock.ammo = 200.0
	check(sim.posts_manned(), "it is night and the posts are manned")
	# at the bus post Dez stands and holds it: she is refused, with the reason
	# (he stands at his post on one side of it, she a step off on the other: had she stood by him, E would have talked to him)
	var bus: Dictionary = sim.jobs.post("bus")
	_stand(main, dez, Vector2(bus.pos) + Vector2(1.4, 0.0))
	_stand(main, me, Vector2(bus.pos) + Vector2(-1.3, 0.0))
	_frames(main, 3)
	eq(String(sim.interact.best().get("id", "")), "bus", "the post is what she is by")
	var held_before: Dictionary = sim.jobs.post_ids.duplicate()
	_press(main, KEY_E)
	eq(main.hud.toast_label.text, "Dez is at the post", "a refusal at the post says why")
	eq(main.hud.toast_col, main.hud.WARN, "in amber")
	eq(sim.interact.posted, "", "she is not on it")
	eq(sim.jobs.post_ids, held_before, "and nobody was moved")
	# the gate post is hers: she steps to it, E, steady
	_stand(main, me, gate_at + Vector2(0.0, 0.9))
	_frames(main, 3)
	await _draw_once(main)
	eq(main.overlay.prompt_text, "E  Take the gate post", "the prompt is on the post")
	_press(main, KEY_E)
	eq(sim.interact.posted, "gate", "she is on the gate post")
	eq(main.hud.toast_label.text, "On the gate post. Steadier here.", "the toast says so")
	_frames(main, 2)
	var braced: float = sim.avatar.spread_of(me, me.gun)
	var braced_f: float = sim.interact.brace_factor(me)
	near(braced_f, sim.interact.BRACE, 0.0001, "standing still on the post she is braced")
	await _draw_once(main)
	check(main.overlay.drew_brace, "and the steady mark is drawn")
	# fire from it: the trigger is held, the magazine runs down, she stays on the post
	var mag0: int = me.mag
	main.mouse_screen = main._tile_to_screen(gate_at + Vector2(0.0, -6.0))
	main.firing = true
	_frames(main, 20)
	main.firing = false
	check(me.mag < mag0, "she fired from the post: %d rounds left of %d" % [me.mag, mag0])
	eq(sim.interact.posted, "gate", "and is still on it")
	# the same hands, off the post, are less steady
	var braced_again: float = sim.avatar.spread_of(me, me.gun)
	sim.interact.leave_post("test")
	var loose: float = sim.avatar.spread_of(me, me.gun)
	near(braced_again / loose, sim.interact.BRACE, 0.001, "the post is worth x%.1f of the spread" % sim.interact.BRACE)
	check(braced <= loose, "braced %.4f, loose %.4f" % [braced, loose])
	await TutorialKit.leave(main)


func test_taking_a_held_post_by_day_swaps_with_its_holder() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	var dez = _person(main, "dez")
	var bus: Dictionary = sim.jobs.post("bus")
	eq(String(sim.jobs.post_ids.get("dez", "")), "bus", "Dez holds the bus post")
	eq(String(sim.jobs.post_ids.get("ruth", "")), "gate", "Ruth the gate")
	_stand(main, me, Vector2(bus.pos) + Vector2(0.0, 0.9))
	_frames(main, 3)
	_press(main, KEY_E)
	eq(sim.interact.posted, "bus", "she took it by day")
	eq(String(sim.jobs.post_ids.get("dez", "")), "gate", "and he has her old one")
	eq(String(sim.jobs.post_ids.get("ruth", "")), "bus", "she has his")
	check(dez.away == null and not dez.dead, "(he is still here)")
	await TutorialKit.leave(main)


# ----------------------------------------------------- the bench, and ammo --

func test_work_the_bench_and_the_ammo_rises() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	var bench: Vector2 = sim.workshop.bench()
	_at(sim, 1, 9.0)
	sim.stock.ammo = 100.0
	sim.stock.scrap = 40.0
	sim.jobs.unassign(_person(main, "dez"))    # (so that the scrap that goes is hers alone)
	# a step north of the bench, further from Dez's seat than from the bench: the bench is what the prompt is on
	_stand(main, me, bench + Vector2(0.0, -1.1))
	_frames(main, 3)
	var best: Dictionary = sim.interact.best()
	eq(String(best.get("kind", "")), "bench", "the bench is the nearest thing in reach")
	await _draw_once(main)
	eq(main.overlay.prompt_text, "E  Work the bench", "the prompt says so")
	var ammo0: float = sim.stock.ammo
	var scrap0: float = sim.stock.scrap
	_press(main, KEY_E)
	eq(sim.interact.working, "bench", "she is at it")
	await _draw_once(main)
	check(main.overlay.drew_bench_ring, "the ring fills while she works")
	var done := _until(main, func(): return sim.interact.working == "", 600)
	check(done > 0, "the twelve seconds end by themselves (%d frames)" % done)
	var made: float = sim.stock.ammo - ammo0
	var used: float = scrap0 - sim.stock.scrap
	check(made > 0.0, "ammo rose by %.1f" % made)
	check(used > 0.0, "from %.1f scrap" % used)
	near(made, used * sim.workshop.ammo_per_scrap(), 0.01, "at the workshop's rate of rounds for a scrap")
	var hours: float = sim.game_hours(sim.interact.BENCH_SECONDS)
	var worker: float = sim.workshop.scrap_per_hour(me) * sim.perf(me) * hours
	near(used, worker * sim.interact.BENCH_MULT, maxf(0.05, 0.03 * used), "a half as much again as the same hands at a seat")
	await TutorialKit.leave(main)


func test_the_bench_is_refused_with_a_reason_at_night() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	var bench: Vector2 = sim.workshop.bench()
	_at(sim, 2, 22.0)
	_stand(main, me, bench + Vector2(0.0, -1.1))
	_frames(main, 3)
	_press(main, KEY_E)
	eq(sim.interact.working, "", "she does not work it")
	check(main.hud.toast_label.text.contains("night"), "the toast says why: '%s'" % main.hud.toast_label.text)
	eq(main.hud.toast_col, main.hud.WARN, "in amber")
	await TutorialKit.leave(main)


# --------------------------------- the Jobs page, the panel open, a night passes --

func test_move_dez_by_radio_from_the_jobs_page_while_a_night_passes() -> void:
	var main := _game()
	var sim = main.sim
	var dez = _person(main, "dez")
	var me = _me(main)
	_arena(main)
	_stand(main, me, Vector2(40.5, 33.5))
	_press(main, KEY_J)
	eq(main.hud.radio_page(), "jobs", "J opens the panel on the Jobs page")
	check(not main.hud.modal_open(), "non-modal")
	check(not main.avatar_hands_off(), "her hands are free")
	var page = main.hud.radio_panel.page_node("jobs")
	check(page.rows.has("dez"), "Dez has a row")
	# a day job and a night post, by request
	var job: Dictionary = page.choose_job(dez, "garden")
	check(bool(job.ok), "Dez takes the garden: %s" % str(job))
	eq(sim.jobs.job_of(dez), "garden", "it is his job")
	var post: Dictionary = page.choose_post(dez, "north_east")
	check(bool(post.ok), "and the north-east wall: %s" % str(post))
	eq(String(sim.jobs.post_ids.get("dez", "")), "north_east", "it is his post")
	# a refusal is shown with its reason where it was asked (the lone radio seat is hers)
	var no: Dictionary = page.choose_job(_person(main, "ruth"), "garden")
	check(not bool(no.ok) and String(no.why).contains("player"), "no seat for the player: '%s'" % String(no.why))
	# WASD still walks with the panel open
	var x0: float = me.x
	_hold([KEY_D], true)
	_frames(main, 15)
	_hold([KEY_D], false)
	check(me.x > x0 + 0.5, "she walked %.2f tiles with the panel open" % (me.x - x0))
	# a night passes with the panel open
	_at(sim, 1, 18.0)
	main.speed = 3
	var clock0: float = sim.clock_min
	var night := _until(main, func(): return sim.phase == "night" and sim.hour >= 23.0 and sim.hour < 23.5, 2400)
	check(night >= 0, "the night came (%d frames, now %.2f)" % [night, sim.hour])
	check(sim.clock_min > clock0 + 60.0, "the game did not stop for the panel")
	eq(main.hud.radio_page(), "jobs", "the panel is still open on Jobs")
	var at: Vector2 = Vector2(sim.jobs.post("north_east").pos)
	var held := Vector2(dez.x, dez.y).distance_to(at)
	check(held < 3.0, "Dez is at the north-east post in the night (%.1f tiles from it)" % held)
	main.speed = 1
	await TutorialKit.leave(main)


# ---------------------------------------------------- the Build page, an order --

func test_order_a_building_from_the_build_page() -> void:
	var main := _game()
	var sim = main.sim
	_press(main, KEY_N)
	eq(main.hud.radio_page(), "build", "N opens the Build page")
	check(main.build_open, "and the yard draws the plots' signs")
	var page = main.hud.radio_panel.page_node("build")
	sim.stock.scrap = 200.0
	var id := "workshop_home"
	check(page.rows.has(id), "the workshop has its slip")
	eq(page.reason_for(id), "", "nothing stands in the way")
	var scrap0: float = sim.stock.scrap
	var cost: int = int(sim.build.building(page.building_of(id)).get("scrap", 0))
	var res: Dictionary = page.order(id)
	check(bool(res.ok), "ordered: %s" % str(res))
	near(sim.stock.scrap, scrap0 - cost, 0.001, "paid: %d scrap" % cost)
	check(not sim.build.site_of(String(res.plot)).is_empty() if sim.build.has_method("site_of") else true, "a site stands on its plot")
	var logged := _news_of(sim, "build")
	check(not logged.is_empty(), "the radio logged the order")
	check(not logged.is_empty() and String(logged[0].text).contains("ordered"), "in words")
	# a second order of the same is refused, with the page's reason that is the sim's
	var again: Dictionary = page.order(id)
	check(not bool(again.ok), "not twice")
	var second := "bunk_house_home_2"
	eq(page.reason_for(second), String(sim.build.why_not(second, page.building_of(second))), "and the page's words for what cannot be ordered are the sim's")
	check(page.reason_for(second) != "", "(there is one)")
	# short of scrap it says so
	sim.stock.scrap = 3.0
	page.refresh(true)
	var poor: String = page.reason_for("greenhouse_home")
	check(poor.contains("scrap"), "short of scrap: '%s'" % poor)
	await TutorialKit.leave(main)


## The panel opened in a game that has been running a while (a player does not press N in the first frames): the Build page's list was
## squeezed to its least for good on the first open (it measured the panel before the panel had been sized to it), and the chosen
## building's Order button was out of sight.
func test_the_build_page_is_not_squeezed_when_it_is_opened_late() -> void:
	# (width, height, the least the panel is tall: a small window has little room, and then only the Order button must be in view)
	for size in [[1280, 800, 400.0], [1600, 1000, 400.0], [960, 600, 0.0], [700, 560, 0.0]]:
		var main := _game(true, size[0], size[1])
		var sim = main.sim
		for i in 40:
			await TutorialKit.settle()    # (the game has run for a while)
		_press(main, KEY_N)
		_frames(main, 12)
		await TutorialKit.settle()
		_frames(main, 12)
		var panel = main.hud.radio_panel
		var page = panel.page_node("build")
		sim.stock.scrap = 200.0
		page.select_building("workshop_home")
		_frames(main, 12)
		await TutorialKit.settle()
		_frames(main, 12)
		await TutorialKit.settle()
		var tag := "%dx%d" % [size[0], size[1]]
		var rect: Rect2 = panel.get_global_rect()
		check(rect.size.y >= float(size[2]), "%s: the panel is %.0f px tall, not squeezed to its least" % [tag, rect.size.y])
		var view: Rect2 = page.list_scroll.get_global_rect()
		var order: Rect2 = page.order_button.get_global_rect()
		check(order.size.x > 0.0 and view.encloses(order), "%s: the chosen building's Order button %s is in view in the list %s" % [tag, str(order), str(view)])
		await TutorialKit.leave(main)


# --------------------------------------------- an errand from the Map page --

func test_delegate_an_errand_from_the_map_page_and_it_comes_home_with_a_smaller_bag() -> void:
	var main := _game()
	var sim = main.sim
	var dez = _person(main, "dez")
	var marcus = _person(main, "marcus")
	_press(main, KEY_G)
	eq(main.hud.radio_page(), "map", "G opens the Map page")
	var page = main.hud.radio_panel.page_node("map")
	check(page.select_place("houses"), "the houses are chosen")
	check(page.toggle_person(dez), "Dez is ticked")
	check(page.toggle_person(marcus), "and Marcus")
	var note := String(page.errand_view().get("note", "")) if page.has_method("errand_view") else ""
	check(note == "" or note.contains("60%"), "(the errand's terms are written out: '%s')" % note)
	var res: Dictionary = page.act("errand")
	check(bool(res.get("ok", false)), "the errand is asked: %s" % str(res))
	eq(sim.radio.errand_wait.size(), 1, "it waits for the radio's delay")
	check(sim.scavenge.parties.is_empty(), "nobody has left yet")
	var stock0: Dictionary = sim.stock.duplicate()
	var left := _until(main, func(): return not sim.scavenge.parties.is_empty(), 400)
	check(left > 0, "after the delay they set off (%d frames)" % left)
	check(sim.radio.errand_wait.is_empty(), "the wait is over")
	var party: Dictionary = sim.scavenge.parties[0]
	check(bool(party.result.get("errand", false)), "it is an errand")
	check(not party.result.has("vehicle") and not party.result.has("rescue"), "no vehicle got going, nobody rescued")
	var told := _until(main, func(): return not _news_of(sim, "errand").is_empty(), 600)
	check(told >= 0, "they leave the gate and the News tells it (%d frames)" % told)
	var out_news := _news_of(sim, "errand")
	check(not out_news.is_empty() and String(out_news[0].text).contains("set off"), "the News says they set off")
	check(not out_news.is_empty() and String(out_news[0].sub).contains("less without you"), "and that they will find less: '%s'" % (String(out_news[0].sub) if not out_news.is_empty() else ""))
	# the same dice, with the player along (a played trip's: no errand), bring more
	var seed_value := 4242
	sim.rng.seed = seed_value
	var plain: Dictionary = sim.scavenge._decide_town(party.merged({"played": true}))
	sim.rng.seed = seed_value
	var worse: Dictionary = sim.scavenge._decide_town(party)
	var any := false
	for k in plain.loot:
		any = true
		var want: float = float(plain.loot[k]) * sim.scavenge.ERRAND_LOOT
		check(absf(float(worse.loot.get(k, 0)) - want) <= 1.0 + 0.001 * want, "%s: %d with her along, %d without (about %.0f%%)" % [k, plain.loot[k], worse.loot.get(k, 0), 100.0 * sim.scavenge.ERRAND_LOOT])
	check(any, "(the trip brings something)")
	check(not worse.has("rescue") and not worse.has("vehicle"), "and no rescue, no vehicle")
	# the trip runs its hours; it comes home
	main.speed = 3
	var home := _until(main, func(): return sim.scavenge.parties.is_empty(), 2400)
	main.speed = 1
	check(home > 0, "they came home (%d frames)" % home)
	var brought := {}
	for k in party.result.loot:
		brought[k] = int(party.result.loot[k])
	var came_back := _news_of(sim, "errand")
	check(came_back.size() >= 2, "the News has the return too")
	if came_back.size() >= 2:
		var last: Dictionary = came_back[came_back.size() - 1]
		var said := String(last.text) + " " + String(last.sub)
		if not brought.is_empty() and not bool(last.text.contains("did not come back")):
			check(said.contains("Without you along they found less"), "the return says it was less: '%s'" % said)
	for k in brought:
		check(sim.stock[k] >= float(stock0.get(k, 0.0)), "the stores did not shrink: %s" % k)
	await TutorialKit.leave(main)


func test_an_errand_that_cannot_start_when_its_delay_is_up_is_logged() -> void:
	var main := _game()
	var sim = main.sim
	var dez = _person(main, "dez")
	var r: Dictionary = sim.radio.request_errand([dez], "houses", "loot")
	check(bool(r.ok), "asked: %s" % str(r))
	_at(sim, 1, 18.9)    # (the dusk comes before they set off: nothing goes out after dark)
	sim.radio.errand_wait[0]["left"] = 0.0
	_frames(main, 3)
	var logged := _news_of(sim, "errand")
	check(not logged.is_empty() and String(logged[0].text).begins_with("The errand could not start"), "the radio says it could not start")
	eq(String(logged[0].sub), "Dez stays at the base.", "and who stays, in grammar")
	check(sim.scavenge.parties.is_empty(), "and nobody left")
	await TutorialKit.leave(main)


## The modal Town Board (Shift+G) in avatar mode: its Clear button sends the dice, which are an errand (no player along: the chance of
## clearing is ERRAND_CLEAR lower), so the chance it tells in words is the errand's, not the plain one.
func test_the_town_boards_clear_button_tells_the_errands_chance() -> void:
	var main := _game()
	var sim = main.sim
	_person(main, "dez").skills["Shooting"] = 8
	_person(main, "marcus").skills["Shooting"] = 0
	_press(main, KEY_G, true)
	check(main.hud.town_board_open(), "Shift+G opens the Town Board")
	var board = main.hud.scavenge_dialog
	check(board.select_place("pharmacy"), "the pharmacy is chosen")
	var plain: float = sim.scavenge.clear_chance(board.party, "pharmacy", false)
	var errand: float = sim.scavenge.clear_chance(board.party, "pharmacy", true)
	near(errand, plain + sim.scavenge.ERRAND_CLEAR, 0.0001, "the rules: the errand is 0.2 lower")
	var plain_words: String = board.chance_words(plain)
	var errand_words: String = board.chance_words(errand)
	check(plain_words != errand_words, "(the staging puts the two chances on either side of a word: %s %.2f, %s %.2f)" % [plain_words, plain, errand_words, errand])
	near(board.clear_chance(board.party, "pharmacy", true), errand, 0.0001, "the board's chance for an errand is the rules'")
	near(board.clear_chance(board.party, "pharmacy"), plain, 0.0001, "and without the flag the plain one")
	var tip: String = board.clear_button.tooltip_text
	check(tip.contains(errand_words), "Clear's tip says '%s' (the errand's chance): '%s'" % [errand_words, tip])
	check(not tip.contains(plain_words), "not '%s' (the plain one)" % plain_words)
	main.hud.scavenge_dialog.close()
	await TutorialKit.leave(main)


# ------------------------------------------------------- all the keys at once --

func test_the_keys_of_avatar_mode_do_not_collide() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	me.weapon = "rifle"
	me.gun = sim.weapons["rifle"]
	me.mag = int(me.gun.mag) - 5
	_stand(main, me, Vector2(40.5, 33.5))
	# T: the panel on News the first time, and T shuts it
	_press(main, KEY_T)
	eq(main.hud.radio_page(), "news", "T: News the first time")
	_press(main, KEY_T)
	eq(main.hud.radio_page(), "", "T again shuts it")
	# J, N, G one after the other: a page's key moves to that page; the same key shuts it
	_press(main, KEY_J)
	eq(main.hud.radio_page(), "jobs", "J")
	_press(main, KEY_N)
	eq(main.hud.radio_page(), "build", "N moves to Build")
	_press(main, KEY_G)
	eq(main.hud.radio_page(), "map", "G moves to Map")
	_press(main, KEY_T)
	eq(main.hud.radio_page(), "", "T shuts the panel, whatever its page")
	_press(main, KEY_T)
	eq(main.hud.radio_page(), "map", "and opens it again on the page it was left on")
	# E, R, F, L, V, Space and 1 to 3 do their own work with the panel open
	var mag0: int = me.mag
	_press(main, KEY_R)
	_frames(main, 120)
	check(me.mag > mag0, "R reloads with the panel open (%d to %d rounds)" % [mag0, me.mag])
	_press(main, KEY_V)
	check(main.fields, "V switches the fields of fire on")
	_press(main, KEY_V)
	_press(main, KEY_L)
	check(sim.radio.alarm_on, "L is the call to arms")
	_press(main, KEY_L)
	check(not sim.radio.alarm_on, "and stands it down")
	_press(main, KEY_SPACE)
	eq(main.speed, 0, "Space pauses")
	_press(main, KEY_SPACE)
	_press(main, KEY_3)
	eq(main.speed, 3, "3 is the fastest")
	_press(main, KEY_1)
	check(main.hud.radio_open(), "(the panel stayed open through all of it)")
	check(not main.hud.talk_open(), "(and no card opened)")
	# Esc: the talk card first, then the panel, then the pause menu
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(me.x + 1.0, me.y))
	_frames(main, 3)
	_press(main, KEY_E)
	check(main.hud.talk_open(), "E at Dez with the panel open: the card")
	check(main.hud.radio_open(), "the panel is still there")
	_press(main, KEY_ESCAPE)
	check(not main.hud.talk_open() and main.hud.radio_open(), "Esc closes the card first")
	_press(main, KEY_ESCAPE)
	check(not main.hud.radio_open() and not main.menu_open, "then the panel")
	_press(main, KEY_ESCAPE)
	check(main.menu_open, "then it is the pause menu")
	main.shell.close_all()
	# Shift+J is the modal full page (and it stops her hands)
	_press(main, KEY_J, true)
	check(main.hud.modal_open(), "Shift+J is the full roster")
	check(main.avatar_hands_off(), "which has her hands")
	_press(main, KEY_E)
	check(not main.hud.talk_open(), "E does nothing under a modal page")
	_press(main, KEY_T)
	check(not main.hud.radio_open(), "nor does T open the panel under it")
	main.toggle_jobs()
	check(not main.hud.modal_open(), "(the page is shut again)")
	await TutorialKit.leave(main)


func test_the_panel_never_hides_the_avatar_and_the_camera_keeps_her_in_view() -> void:
	for size in [[1280, 800], [700, 560]]:
		var main := _game(true, size[0], size[1])
		var sim = main.sim
		_arena(main)
		var me = _me(main)
		_stand(main, me, Vector2(40.5, 32.5))
		_press(main, KEY_J)
		_frames(main, 90)
		await TutorialKit.settle()
		var panel: Rect2 = main.hud.radio_panel.get_global_rect()
		var on: Vector2 = main._tile_to_screen(Vector2(me.x, me.y))
		check(not panel.has_point(on), "%dx%d: she (%.0f, %.0f) is not under the panel %s" % [size[0], size[1], on.x, on.y, str(panel)])
		var clock: Rect2 = main.hud.anchor_rect("clock")
		var toolbar: Rect2 = main.hud.anchor_rect("toolbar") if main.hud.has_method("anchor_rect") else Rect2()
		check(not panel.intersects(clock), "%dx%d: the panel is clear of the clock" % [size[0], size[1]])
		if toolbar.size.x > 0.0:
			check(not panel.intersects(toolbar), "%dx%d: and of the toolbar" % [size[0], size[1]])
		await TutorialKit.leave(main)


# ----------------------------------------------------------- a round 17 save --

func test_a_round_17_save_loads_and_round_18_works_in_it() -> void:
	var path := "user://test_r18_integ_r17.json"
	var text := FileAccess.get_file_as_string(R17_SAVE)
	check(text != "", "the fixture is there")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	check(SaveGame.is_loadable(path), "the save is one this version can load")
	var main = TutorialKit.start({"load": path}, 1280, 800)
	var sim = main.sim
	check(not main.load_failed, "it loaded")
	eq(sim.player_id, "ruth", "Ruth is still the player")
	var dez = _person(main, "dez")
	eq(String(dez.stance), "hold", "Dez is still holding where he was told")
	check(not _news_of(sim, "story").is_empty(), "the News log came with it")
	check(not sim.radio.open_calls().is_empty(), "and the call that waited")
	check(sim.radio.errand_wait.is_empty(), "no errand waits (it had none)")
	check(sim.interact.talked.is_empty() and sim.interact.posted == "" and sim.interact.working == "", "nothing is used (round 17 had no interact)")
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.storyteller.enabled = false
	main.hud.update_hud(sim, 1, true, 0)
	_frames(main, 30)
	# the new interface works in an old game
	for key in [KEY_J, KEY_N, KEY_G, KEY_T]:
		_press(main, key)
		_frames(main, 4)
		check(main.hud.radio_open(), "the panel opens on the key %d" % key)
		_press(main, key if key != KEY_T else KEY_T)
		check(not main.hud.radio_open(), "and shuts on the same")
	var me = _me(main)
	_stand(main, me, Vector2(dez.x - 1.0, dez.y))
	_frames(main, 3)
	_press(main, KEY_E)
	check(main.hud.talk_open(), "E at Dez opens the card in an old game")
	var again: Dictionary = main.hud.talk_card.verbs.press("back")
	check(bool(again.ok), "and he agrees to go back to work: %s" % str(again))
	# and a new save of it carries the new data and loads again
	var round_trip := SaveGame.to_text(SaveGame.to_dict(sim))
	var d: Dictionary = SaveGame.from_text(round_trip)
	check((d.modules as Dictionary).has("interact"), "a save made now has the interact module")
	check((d.modules.radio as Dictionary).has("errand_wait"), "and the errands waiting")
	await TutorialKit.leave(main, true)
	OS.move_to_trash(ProjectSettings.globalize_path(path))


func test_a_save_in_the_middle_of_an_errand_keeps_it_an_errand() -> void:
	var g := Helpers.make(7, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.storyteller.enabled = false
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	_at(sim, 1, 8.0)
	var dez = null
	for p in sim.people:
		if String(p.id) == "dez":
			dez = p
	var r: Dictionary = sim.radio.request_errand([dez], "houses", "loot")
	check(bool(r.ok), "asked")
	# saved while it waits for its delay
	var waiting := SaveGame.to_text(SaveGame.to_dict(sim))
	var g2 := Helpers.make(7, 1, 3)
	g2.sim.storyteller.enabled = false
	check(SaveGame.apply(g2.sim, SaveGame.from_text(waiting)), "the save with a waiting errand loads")
	eq(g2.sim.radio.errand_wait.size(), 1, "the errand still waits")
	Helpers.run(g2.sim, 6.0)
	check(not g2.sim.scavenge.parties.is_empty(), "and goes after its delay")
	check(bool(g2.sim.scavenge.parties[0].result.get("errand", false)), "as an errand")
	# saved while out
	var out := SaveGame.to_text(SaveGame.to_dict(g2.sim))
	var g3 := Helpers.make(7, 1, 3)
	g3.sim.storyteller.enabled = false
	check(SaveGame.apply(g3.sim, SaveGame.from_text(out)), "the save with a party out loads")
	check(not g3.sim.scavenge.parties.is_empty() and bool(g3.sim.scavenge.parties[0].result.get("errand", false)), "it is still an errand")
	Helpers.run(g3.sim, 400.0)
	check(g3.sim.scavenge.parties.is_empty(), "it came home")
	check(not _news_of(g3.sim, "errand").is_empty(), "with its news")
	g.world.free()
	g2.world.free()
	g3.world.free()


## The storyteller's "A crate in the road" sends a pair through `scavenge.send` too: it is a card's trip, not an errand the player asked
## for (the radio, the Map page, the old dialog), so in avatar mode it keeps the old numbers and the News does not say "without you".
func test_a_storyteller_card_party_is_not_an_errand() -> void:
	var g := Helpers.make(7, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	_at(sim, 3, 8.0)
	sim.storyteller.enabled = true
	check(sim.storyteller.force("supply_drop"), "the crate card is up")
	check(sim.storyteller.choose(0), "and the pair is sent")
	check(not sim.scavenge.parties.is_empty(), "they are out")
	if not sim.scavenge.parties.is_empty():
		var party: Dictionary = sim.scavenge.parties[0]
		check(not bool(party.result.get("errand", false)), "the card's party is not an errand")
		check(not sim.scavenge.is_errand(party), "is_errand is false for it")
	check(_news_of(sim, "errand").is_empty(), "the News says nothing of 'less without you'")
	# the same send, asked for by the player's side (the radio, the dialogs), is one
	var g2 := Helpers.make(7, 1, 3)
	var sim2 = g2.sim
	sim2.waves.enabled = false
	sim2.zombies.clear()
	sim2.avatar.set_player("ruth")
	_at(sim2, 3, 8.0)
	var dez = null
	for p in sim2.people:
		if String(p.id) == "dez":
			dez = p
	check(sim2.scavenge.send([dez], "houses"), "a trip asked for")
	check(bool(sim2.scavenge.parties[0].result.get("errand", false)), "is an errand")
	g.world.free()
	g2.world.free()


## E at someone who is down: the card opens and stays, with what they need (the one who needs it most is the one the player most wants to
## hear), their verbs off with the reason; it closes only if they fall while it is open. The word is not spent for nothing.
func test_e_at_a_downed_colonist_shows_the_card_with_what_they_need() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	var dez = _person(main, "dez")
	sim.jobs.unassign(dez)
	dez.bleeding = 2.0
	dez.downed = true
	_stand(main, me, Vector2(41.5, 33.0))
	_stand(main, dez, Vector2(42.7, 33.0))
	_frames(main, 4)
	_press(main, KEY_E)
	_frames(main, 3)
	check(main.hud.talk_open(), "the card is open for Dez, who is down")
	var seen := _text_of(main.hud.talk_card)
	check(seen.contains("Bleeding"), "and shows what he needs: %s" % seen)
	var come: Dictionary = main.hud.talk_card.verbs.verb_state("come")
	check(not bool(come.enabled) and String(come.why) != "", "his verbs are off, with the reason: '%s'" % String(come.why))
	# up and down again while it is open: it closes when he falls
	dez.downed = false
	_frames(main, 3)
	check(main.hud.talk_open(), "(he gets up: it stays)")
	dez.downed = true
	_frames(main, 3)
	check(not main.hud.talk_open(), "he falls with the card open: it closes")
	await TutorialKit.leave(main)


## The word of the day earns what trust can still rise by: at 100 nothing, and the card does not say "trust +1"; at 99.5 half a point.
func test_the_days_word_earns_only_what_the_trust_can_still_rise_by() -> void:
	var g := Helpers.make(7, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	var dez = null
	var marcus = null
	for p in sim.people:
		if String(p.id) == "dez":
			dez = p
		if String(p.id) == "marcus":
			marcus = p
	dez.trust = 100.0
	var full: Dictionary = sim.interact.talk_to(dez)
	near(float(full.gain), 0.0, 0.0001, "at 100 the word earns nothing")
	near(dez.trust, 100.0, 0.0001, "(trust is 100)")
	check(sim.radio.trust_why(dez).is_empty(), "and no reason is remembered for it")
	marcus.trust = 99.5
	var part: Dictionary = sim.interact.talk_to(marcus)
	near(float(part.gain), 0.5, 0.0001, "at 99.5 half a point")
	near(marcus.trust, 100.0, 0.0001, "(and it is 100 now)")
	g.world.free()


## The card open on someone who becomes the player (a succession) closes: they cannot be asked.
func test_the_talk_card_closes_on_the_person_who_becomes_the_player() -> void:
	var main := _game()
	var sim = main.sim
	_arena(main)
	var me = _me(main)
	var dez = _person(main, "dez")
	sim.jobs.unassign(dez)
	_stand(main, me, Vector2(41.5, 33.0))
	_stand(main, dez, Vector2(42.7, 33.0))
	_frames(main, 3)
	_press(main, KEY_E)
	_frames(main, 2)
	check(main.hud.talk_open(), "the card is open for Dez")
	check(sim.avatar.set_player("dez"), "Dez is the player now")
	_frames(main, 3)
	check(not main.hud.talk_open(), "the card has closed")
	await TutorialKit.leave(main)


## Errands that wait for their delay count against the parties the game allows: a third is refused when it is asked ("Both parties are
## out"), not accepted with "I'll go." and refused in the News two seconds later. Asking again for the same people replaces their errand.
func test_errands_that_wait_count_against_the_parties_the_game_allows() -> void:
	var g := Helpers.make(7, 1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.storyteller.enabled = false
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	_at(sim, 3, 8.0)
	var crew: Array = []
	for p in sim.people:
		if not p.player and crew.size() < 3:
			crew.append(p)
	check(crew.size() == 3, "three others to send")
	var first: Dictionary = sim.radio.request_errand([crew[0]], "houses", "loot")
	check(bool(first.ok), "the first is asked: %s" % str(first))
	var second: Dictionary = sim.radio.request_errand([crew[1]], "bakery", "loot")
	check(bool(second.ok), "and the second: %s" % str(second))
	var willing: Dictionary = sim.radio.errand_willingness([crew[2]], "pharmacy", "loot")
	check(not bool(willing.ok), "a third is not willing")
	eq(String(willing.why), "Both parties are out.", "and says why")
	var third: Dictionary = sim.radio.request_errand([crew[2]], "pharmacy", "loot")
	check(not bool(third.ok) and String(third.why) == "Both parties are out.", "asking is refused with it: %s" % str(third))
	eq(sim.radio.errand_wait.size(), 2, "and only two wait")
	# the same people asked again (another place): replaced, not counted twice
	var again: Dictionary = sim.radio.request_errand([crew[1]], "pharmacy", "loot")
	check(bool(again.ok), "asking for the same one again is fine: %s" % str(again))
	eq(sim.radio.errand_wait.size(), 2, "still two")
	# nothing logged as 'could not start' when they go
	Helpers.run(sim, 8.0)
	eq(sim.scavenge.parties.size(), 2, "both go")
	for e in _news_of(sim, "errand"):
		check(not String(e.text).begins_with("The errand could not start"), "no 'could not start': %s" % String(e.text))
	g.world.free()


## The News about an errand that could not go whole: the dead are not named, those on a trip of their own are not at the base, and those
## who were asked and could not go when the delay was up are told ("Marcus stays at the base. Marcus is down.").
func test_the_news_says_who_stayed_behind_from_an_errand() -> void:
	var g := Helpers.make(7, 1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.storyteller.enabled = false
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	_at(sim, 3, 8.0)
	var crew: Array = []
	for p in sim.people:
		if not p.player and crew.size() < 2:
			crew.append(p)
	var asked: Dictionary = sim.radio.request_errand(crew, "houses", "loot")
	check(bool(asked.ok), "two are asked: %s" % str(asked))
	crew[1].downed = true    # (the delay is not up yet)
	sim.radio.errand_wait[0]["left"] = 0.0
	Helpers.run(sim, 1.0)
	check(not sim.scavenge.parties.is_empty(), "the other goes")
	var told := _news_of(sim, "errand")
	var stay: Dictionary = {}
	for e in told:
		if String(e.text).ends_with("at the base."):
			stay = e
	check(not stay.is_empty(), "the News names the one who stays")
	if not stay.is_empty():
		eq(String(stay.text), "%s stays at the base." % String(crew[1].first), "in grammar")
		check(String(stay.sub).contains("is down"), "with his reason: '%s'" % String(stay.sub))
	g.world.free()
	# everybody gone (the dead are not named, the one away is not at the base): the failure names those who are here
	var g2 := Helpers.make(7, 1, 5)
	var sim2 = g2.sim
	sim2.waves.enabled = false
	sim2.zombies.clear()
	sim2.storyteller.enabled = false
	sim2.avatar.set_player("ruth")
	_at(sim2, 3, 8.0)
	var two: Array = []
	for p in sim2.people:
		if not p.player and two.size() < 3:
			two.append(p)
	check(bool(sim2.radio.request_errand(two, "houses", "loot").ok), "three are asked")
	two[0].dead = true
	two[1].away = {"kind": "trip"}
	_at(sim2, 3, 18.9)    # (the dusk: nobody goes out)
	sim2.radio.errand_wait[0]["left"] = 0.0
	Helpers.run(sim2, 0.5)
	var failed := _news_of(sim2, "errand")
	check(not failed.is_empty() and String(failed[0].text).begins_with("The errand could not start"), "it could not start")
	if not failed.is_empty():
		eq(String(failed[0].sub), "%s stays at the base." % String(two[2].first), "only the one who is here is named: '%s'" % String(failed[0].sub))
	g2.world.free()


## A damaged save's errand cannot wait for ever: `left` is held to the longest a delay can be.
func test_a_damaged_errand_wait_is_held_to_the_longest_delay() -> void:
	var g := Helpers.make(7, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.avatar.set_player("ruth")
	var data: Dictionary = SaveGame.to_dict(sim)
	data.modules.radio["errand_wait"] = [
		{"ids": ["dez"], "place": "houses", "action": "loot", "vehicle": "", "left": 1.0e300},
		{"ids": ["marcus"], "place": "bakery", "action": "loot", "vehicle": "", "left": -5.0},
	]
	var g2 := Helpers.make(7, 1, 3)
	check(SaveGame.apply(g2.sim, SaveGame.from_text(SaveGame.to_text(data))), "the save loads")
	var wait: Array = g2.sim.radio.errand_wait
	eq(wait.size(), 2, "both entries are kept")
	if wait.size() == 2:
		check(float(wait[0].left) <= g2.sim.radio.MAX_ERRAND_WAIT_S, "1e300 is held to %.0f s (got %s)" % [g2.sim.radio.MAX_ERRAND_WAIT_S, str(wait[0].left)])
		check(float(wait[1].left) >= 0.0, "and a negative one to 0")
	g.world.free()
	g2.world.free()


## Two small things of the HUD with the panel up: a long toast keeps inside the window (it keeps to the left of the panel, not off the left
## edge), and a click on a person's job tag opens the panel's Jobs page on their row and never shuts it.
func test_a_long_toast_stays_in_the_window_and_the_job_tag_never_shuts_the_panel() -> void:
	var main := _game(true, 700, 560)
	var h = main.hud
	_press(main, KEY_J)
	_frames(main, 4)
	h.toast("Not yet: first walk to the radio desk, then ask Dez and Marcus to come with you to the north wall.")
	_frames(main, 4)
	await TutorialKit.settle()
	var rect: Rect2 = h.toast_panel.get_global_rect()
	check(rect.position.x >= 0.0 and rect.end.x <= 700.0, "the toast %s is inside the 700 px window" % str(rect))
	var dez = _person(main, "dez")
	main._select({"kind": "person", "ref": dez})
	_frames(main, 4)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	h._on_job_tag_input(click)
	eq(h.radio_page(), "jobs", "the job tag shows the Jobs page")
	h._on_job_tag_input(click)
	eq(h.radio_page(), "jobs", "and a second click leaves it there")
	h.close_radio()
	h._on_job_tag_input(click)
	eq(h.radio_page(), "jobs", "(and opens it when it was shut)")
	await TutorialKit.leave(main)


# ---------------------------------------------------- with no avatar, nothing --

func test_with_no_avatar_nothing_of_round_18_exists() -> void:
	var main := _game(false)
	var sim = main.sim
	eq(sim.player_id, "", "nobody is the player")
	eq(main.avatar_mode, false, "the old yard")
	# no panel: its tabs are not offered, and nothing opens it
	check(not main.hud.news_button.visible, "no News button in the toolbar")
	main.hud.open_radio("jobs")
	check(not main.hud.radio_open(), "open_radio does nothing")
	main.hud.toggle_radio("news")
	check(not main.hud.radio_open(), "nor does toggle_radio")
	_press(main, KEY_T)
	check(not main.hud.radio_open(), "the T key is the old treat order, not the panel")
	# E does nothing
	var toast0 := String(main.hud.toast_label.text)
	_press(main, KEY_E)
	check(not main.hud.talk_open(), "E opens no card")
	eq(String(main.hud.toast_label.text), toast0, "and says nothing")
	eq(sim.interact.candidates(), [], "nothing is in reach of anything")
	eq(bool(sim.interact.use().get("ok", true)), false, "use is refused")
	check(not main.overlay.drew_prompt, "no prompt")
	# J, N and G are the old modal pages
	_press(main, KEY_J)
	check(main.hud.jobs_screen != null and not main.hud.radio_open(), "J is the Duty roster, the modal page")
	main.toggle_jobs()
	check(main.hud.jobs_screen == null, "(shut)")
	_press(main, KEY_N)
	check(main.hud.build_screen != null and not main.hud.radio_open(), "N is the Build screen")
	main.toggle_build()
	check(main.hud.build_screen == null, "(shut)")
	# an errand is the dice as before: no errand in the result, the same loot at the same dice
	var dez = _person(main, "dez")
	var marcus = _person(main, "marcus")
	_at(sim, 1, 8.0)
	check(sim.scavenge.send([dez, marcus], "houses", "loot", ""), "a party is sent")
	var party: Dictionary = sim.scavenge.parties[0]
	check(not party.result.has("errand"), "its result says nothing of an errand")
	check(not sim.scavenge.is_errand(party), "is_errand is false")
	sim.rng.seed = 99
	var a: Dictionary = sim.scavenge._decide_town(party)
	sim.rng.seed = 99
	var b: Dictionary = sim.scavenge._decide_town(party.merged({"played": true}))
	eq(a, b, "the same dice give the same bag as the player's own would")
	check(_news_of(sim, "errand").is_empty(), "no news of an errand")
	var chance: float = sim.scavenge.clear_chance([dez, marcus], "houses")
	near(chance, sim.scavenge.clear_chance([dez, marcus], "houses", false), 0.0, "the clear chance is the plain one")
	await TutorialKit.leave(main)
