extends "res://tests/case.gd"
## The seams of the round 19 merge (nights) with rounds 18 and 21: where the avatar's hand-mending (scripts/sim/nights.gd: `wall_candidates`,
## `mend_wall`, `stop_mend`, `working == "wall"`) meets round 18's E (scripts/sim/interact.gd, main.gd's E key, overlay_node.gd's prompt and
## ring), where the nights' warning meets round 18's Map page, and where the "leave by" line meets the live drive's scene.

const Helpers := preload("res://tests/helpers.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const Interact := preload("res://scripts/sim/interact.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const NightCalls := preload("res://scripts/sim/night_calls.gd")

const DT := 1.0 / 30.0
const PALLETS := 1
const CONTAINER := 0


func _seg(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


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


## A night game with the avatar (Ruth) standing at the mending place of the section `seg_id` at `share` of its health, with nobody else near
## her, nobody working, no dead, 40 scrap in store. Returns {"g", "sim", "me", "seg", "spot"}.
func _game(seg_id: int = CONTAINER, share: float = 0.35) -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, 3, 22.0)
	for p in sim.people:
		p.reloading = 1.0e6
	var seg = _seg(sim, seg_id)
	seg.hp = seg.max_hp * share
	sim._segment_state(seg)
	var me = sim.avatar.player()
	var spot: Vector2 = sim.repair_spot(seg)
	me.x = spot.x
	me.y = spot.y
	me.path = []
	for p in sim.people:
		if p != me:
			p.x = spot.x + 14.0
			p.y = spot.y + 14.0
			p.path = []
	sim.stock.scrap = 40.0
	sim.events.clear()
	return {"g": g, "sim": sim, "me": me, "seg": seg, "spot": spot}


func _free(m: Dictionary) -> void:
	m.g.world.queue_free()


func _steps(sim, n: int) -> void:
	for i in n:
		sim.update(DT)


# ------------------------------------------------------------- the E candidates (sim) --

func test_a_worn_wall_in_reach_is_one_of_the_things_e_could_use() -> void:
	var m := _game()
	var list: Array = m.sim.interact.candidates()
	var walls := list.filter(func(c): return c.kind == "wall")
	eq(walls.size(), 1, "one wall in reach: %s" % str(_kinds(list)))
	if walls.size() == 1:
		eq(walls[0].label, "Mend the Red container (35%)", "the nights' own label")
		eq(walls[0].id, str(CONTAINER), "named by the section's id")
		check(walls[0].ok and walls[0].why == "", "it can be used")
	eq(m.sim.interact.best().get("kind", ""), "wall", "and it is what E would do with nothing nearer")
	_free(m)


func test_a_sound_wall_is_not_listed_and_a_far_one_neither() -> void:
	var m := _game()
	m.seg.hp = m.seg.max_hp
	m.sim._segment_state(m.seg)
	check(not _kinds(m.sim.interact.candidates()).has("wall:%d" % CONTAINER), "a sound wall")
	m.seg.hp = m.seg.max_hp * 0.4
	m.me.x = m.spot.x + 5.0
	check(not _kinds(m.sim.interact.candidates()).has("wall:%d" % CONTAINER), "a worn one out of reach")
	_free(m)


func test_nothing_is_offered_with_no_avatar_or_where_the_nights_do_not_apply() -> void:
	var m := _game()
	m.sim.nights_on = false
	eq(m.sim.interact.candidates().filter(func(c): return c.kind == "wall"), [], "a place's sim: no wall")
	m.sim.nights_on = true
	check(m.sim.avatar.set_player(null), "no avatar")
	eq(m.sim.interact.candidates(), [], "none at all")
	var r: Dictionary = m.sim.interact.use({"kind": "wall", "id": str(CONTAINER)})
	check(not bool(r.ok), "and nothing is used")
	eq(m.sim.nights.working, "", "no session")
	_free(m)


func test_a_wall_ranks_last_on_a_tie_and_a_nearer_thing_is_first() -> void:
	var m := _game()
	var it = m.sim.interact
	eq(Interact.RANK.wall, 5, "the rank")
	var wall := {"kind": "wall", "id": "0", "dist": 1.0, "label": "", "pos": Vector2.ZERO, "ok": true, "why": ""}
	var car := {"kind": "vehicle", "id": "v", "dist": 1.1, "label": "", "pos": Vector2.ZERO, "ok": true, "why": ""}
	var bench := {"kind": "bench", "id": "bench", "dist": 1.2, "label": "", "pos": Vector2.ZERO, "ok": true, "why": ""}
	var post := {"kind": "post", "id": "gate", "dist": 1.25, "label": "", "pos": Vector2.ZERO, "ok": true, "why": ""}
	var who := {"kind": "person", "id": "dez", "dist": 1.3, "label": "", "pos": Vector2.ZERO, "ok": true, "why": ""}
	eq(_kinds(it._ordered([wall, car, bench, post, who])), ["person:dez", "post:gate", "bench:bench", "vehicle:v", "wall:0"], "within a third of a tile: person, post, bench, vehicle, wall")
	var near_wall := {"kind": "wall", "id": "0", "dist": 0.5, "label": "", "pos": Vector2.ZERO, "ok": true, "why": ""}
	eq(_kinds(it._ordered([car, near_wall]))[0], "wall:0", "a wall that is nearer by more than the tie wins")
	_free(m)


# ------------------------------------------------------------------------- E on the wall --

func test_e_on_a_wall_starts_the_session_and_e_again_stops_it() -> void:
	var m := _game()
	var sim = m.sim
	var r: Dictionary = sim.interact.use()
	check(bool(r.ok), "E: %s" % str(r))
	eq(r.kind, "wall", "of kind wall")
	eq(r.id, str(CONTAINER), "the section")
	eq(r.line, "Mending the red container.", "the nights' line")
	eq(sim.nights.working, "wall", "the hands are at the wall")
	check(sim.nights.work_left > 0.0, "with time to run")
	eq(_events(sim, "interact").size(), 1, "the views are told")
	eq(_events(sim, "wall_work").filter(func(e): return e.on).size(), 1, "and the session began")
	_steps(sim, 20)
	var again: Array = sim.interact.candidates().filter(func(c): return c.kind == "wall")
	eq(again.size(), 1, "the wall is still on offer")
	if again.size() == 1:
		eq(again[0].label, "Stop mending the red container", "as the one to stop")
	var stop: Dictionary = sim.interact.use()
	check(bool(stop.ok), "E again: %s" % str(stop))
	check(bool(stop.get("stopped", false)), "it stopped")
	eq(stop.line, "Stopped mending the red container.", "and says so")
	eq(sim.nights.working, "", "no session")
	var off: Array = _events(sim, "wall_work").filter(func(e): return not e.on)
	eq(off.size(), 1, "one ending")
	if off.size() == 1:
		eq(off[0].why, "stopped", "the reason")
		check(float(off[0].hp) > 0.0, "and what it mended")
	_free(m)


func test_e_on_a_refused_wall_says_why_and_still_tells_the_views() -> void:
	var m := _game()
	var sim = m.sim
	sim.stock.scrap = 0.0
	var r: Dictionary = sim.interact.use()
	check(not bool(r.ok), "refused")
	eq(r.kind, "wall", "the kind is kept")
	eq(r.why, "There is no scrap to spare", "with the nights' reason")
	eq(sim.nights.working, "", "nothing began")
	var told: Array = _events(sim, "interact")
	eq(told.size(), 1, "and the views are told")
	if told.size() == 1:
		check(not bool(told[0].ok), "that it was refused")
	var listed: Array = sim.interact.candidates().filter(func(c): return c.kind == "wall")
	if listed.size() == 1:
		check(not bool(listed[0].ok) and listed[0].why == "There is no scrap to spare", "the candidate is dim with the same reason")
	_free(m)


func test_starting_the_wall_stops_a_bench_session_first() -> void:
	var m := _game()
	var sim = m.sim
	var it = sim.interact
	it.working = "bench"
	it.work_left = 5.0
	m.me.work = "bench"
	var r: Dictionary = it.use({"kind": "wall", "id": str(CONTAINER)})
	check(bool(r.ok), "the wall: %s" % str(r))
	eq(it.working, "", "the bench session is over")
	eq(sim.nights.working, "wall", "and the wall's has begun")
	var bench_off: Array = _events(sim, "bench_work").filter(func(e): return not e.on)
	eq(bench_off.size(), 1, "the bench told it was stopped")
	if bench_off.size() == 1:
		eq(bench_off[0].why, "stopped", "by hand")
	_free(m)


func test_working_the_bench_ends_a_wall_session() -> void:
	var m := _game()
	var sim = m.sim
	check(bool(sim.nights.mend_wall(CONTAINER).ok), "the wall's session begins")
	Helpers.at(sim, 3, 10.0)
	sim.stock.ammo = 0.0
	sim.stock.scrap = 60.0
	var bench: Vector2 = sim.workshop.bench()
	m.me.x = bench.x
	m.me.y = bench.y + 0.5
	m.me.path = []
	var r: Dictionary = sim.interact.work_bench()
	check(bool(r.ok), "the bench: %s" % str(r))
	eq(sim.nights.working, "", "the wall's session is not left running under the bench's")
	eq(sim.interact.working, "bench", "the bench's session")
	var off: Array = _events(sim, "wall_work").filter(func(e): return not e.on)
	eq(off.size(), 1, "the wall's session said it ended")
	if off.size() == 1:
		eq(off[0].why, "stopped", "by hand")
	_free(m)


func test_a_wall_out_of_reach_does_not_take_the_session_over() -> void:
	var m := _game()
	var sim = m.sim
	check(bool(sim.interact.use().ok), "the first wall")
	var other = _seg(sim, PALLETS)
	other.hp = other.max_hp * 0.5
	sim._segment_state(other)
	var forced: Dictionary = sim.interact.use({"kind": "wall", "id": str(PALLETS)})
	check(not bool(forced.ok), "the other wall is not in reach: %s" % str(forced))
	eq(sim.nights.mend_seg, CONTAINER, "the first goes on")
	eq(sim.nights.working, "wall", "still working")
	_free(m)


# ----------------------------------------------------------------- E on the wall (views) --

## The real game with the avatar (Ruth) in the yard at the mending place of the Red container, which is at 35%, nobody else near, nothing
## about, scrap in store, the camera on her.
func _yard() -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true})
	var sim = main.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.jobs.clear()
	sim.tactics.chores = false
	sim.storyteller.enabled = false
	var seg = _seg(sim, CONTAINER)
	seg.hp = seg.max_hp * 0.35
	sim._segment_state(seg)
	var me = sim.avatar.player()
	var spot: Vector2 = sim.repair_spot(seg)
	for p in sim.people:
		p.path = []
		p.order = null
		p.goal_key = ""
		if p != me:
			p.x = spot.x + 14.0
			p.y = spot.y + 14.0
	me.x = spot.x
	me.y = spot.y
	sim.stock.scrap = 40.0
	main.cam_center = spot
	main.zoom_px = 40.0
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	return main


func _frames(main: Node, n: int) -> void:
	for i in n:
		main._process(DT)


func _draw_once(main: Node) -> void:
	main._process(DT)
	main.overlay.queue_redraw()
	await TutorialKit.settle()


func _press(main: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	main._unhandled_input(ev)


func test_the_prompt_offers_the_wall_and_e_mends_it_and_again_stops_it() -> void:
	var main := _yard()
	var sim = main.sim
	var o = main.overlay
	var h = main.hud
	await _draw_once(main)
	check(o.drew_prompt, "the pill is drawn")
	check(o.prompt_text.begins_with("E  Mend the Red container ("), "it says the key and the wall: %s" % o.prompt_text)
	check(o.prompt_ok, "it can be done")
	eq(o.prompt_key, "wall:%d" % CONTAINER, "the prompt is on the wall")
	check(Rect2(Vector2.ZERO, main._vp()).encloses(o.prompt_rect), "inside the window")
	_press(main, KEY_E)
	_frames(main, 1)
	eq(sim.nights.working, "wall", "E begins the hands at the wall")
	eq(h.toast_label.text, "Mending the red container.", "and the toast says so")
	eq(h.toast_col, h.INFO, "plain")
	_frames(main, 20)
	await _draw_once(main)
	check(o.drew_mend_ring, "the ring shows (read from the nights' session)")
	check(o.mend_progress > 0.0 and o.mend_progress < 1.0, "part of the way: %f" % o.mend_progress)
	eq(o.prompt_text, "E  Stop mending the red container", "the pill offers to stop")
	_press(main, KEY_E)
	_frames(main, 1)
	eq(sim.nights.working, "", "E again stops it")
	eq(h.toast_label.text, "Stopped mending the red container.", "and says so once")
	await _draw_once(main)
	check(not o.drew_mend_ring, "the ring is gone")
	await TutorialKit.leave(main)


func test_e_at_a_wall_with_no_scrap_is_a_refusal_in_amber_and_the_pill_is_dim() -> void:
	var main := _yard()
	var sim = main.sim
	sim.stock.scrap = 0.0
	await _draw_once(main)
	var o = main.overlay
	eq(o.prompt_text, "E  Mend the Red container (35%): There is no scrap to spare", "the reason follows the words")
	check(not o.prompt_ok, "the dim one")
	_press(main, KEY_E)
	_frames(main, 1)
	eq(main.hud.toast_label.text, "There is no scrap to spare", "a refusal says why")
	eq(main.hud.toast_col, main.hud.WARN, "in amber")
	eq(sim.nights.working, "", "nothing began")
	await TutorialKit.leave(main)


func test_a_whole_wall_is_told_in_a_toast_when_the_hands_are_done() -> void:
	var main := _yard()
	var sim = main.sim
	var seg = _seg(sim, CONTAINER)
	seg.hp = seg.max_hp * 0.94
	sim._segment_state(seg)
	await _draw_once(main)
	_press(main, KEY_E)
	_frames(main, 1)
	eq(sim.nights.working, "wall", "the hands are at it")
	var guard := 0
	while sim.nights.working == "wall" and guard < 900:
		_frames(main, 1)
		guard += 1
	eq(sim.nights.working, "", "it ended by itself")
	check(seg.hp >= seg.max_hp, "the wall is whole")
	eq(main.hud.toast_label.text, "The red container is whole again", "and it is said")
	await TutorialKit.leave(main)


func test_in_the_old_game_with_no_avatar_nothing_is_offered_at_a_wall() -> void:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": false})
	var sim = main.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	var seg = _seg(sim, CONTAINER)
	seg.hp = seg.max_hp * 0.35
	sim._segment_state(seg)
	eq(sim.interact.candidates(), [], "no candidates")
	eq(sim.nights.wall_candidates(), [], "and none of the nights'")
	_press(main, KEY_E)
	_frames(main, 2)
	eq(sim.nights.working, "", "E does nothing at the wall")
	await TutorialKit.leave(main)


# ------------------------------------------------------- the road call and the live drive --

## The party walks out of the place: the leader off the exit for a moment, then everyone in it, and a few frames for the scene to see it.
func _walk_out(scene) -> void:
	var spot: Vector2 = scene.site.exit.get_center()
	var lead = scene.leader()
	lead.x = spot.x + 7.0
	lead.path = []
	for i in 6:
		scene.tick(DT)
	for p in scene.run.squad:
		if not p.dead and not p.downed:
			p.x = spot.x + 0.3
			p.y = spot.y + 0.2
			p.path = []
	for i in 15:
		scene.tick(DT)


func test_the_real_road_call_sends_a_live_trip_home_and_the_line_follows_it_to_the_gate() -> void:
	PlaceFlow.live_enabled = true
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true})
	main.raid_stub = true
	var sim = main.sim
	sim.waves.enabled = false
	sim.storyteller.enabled = false
	Helpers.at(sim, 10, 8.0)
	check(not sim.waves.big_night(10).is_empty(), "day 10 is a Big Night")
	var scene = main.open_raid([sim.people[1], sim.people[2]], sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null and scene.get("leg") == "there", "the live drive: the road there")
	scene.stage("exit")
	var guard := 0
	while scene.leg == "there" and guard < 600:
		scene.tick(DT)
		guard += 1
	scene.tick(DT)
	eq(scene.leg, "place", "the place")
	var night = sim.radio.night
	var st: Dictionary = night.road_status()
	check(bool(st.on) and bool(st.in_place) and bool(st.big), "the road status: a trip is out, in its place, on a Big Night: %s" % str(st))
	var h = scene.hud_layer
	h.refresh()
	check(h.leave_label.visible and String(h.leave_label.text).begins_with("Dusk in "), "the place's line is up: %s" % h.leave_label.text)
	# the hour to leave by: the radio asks
	Helpers.at(sim, 10, NightCalls.hour_of(float(st.leave_by)))
	night.watch()
	var ask: Dictionary = {}
	for e in sim.radio.news:
		if e.kind == "night_road" and not (e.options as Array).is_empty():
			ask = e
	check(not ask.is_empty(), "the road call is raised")
	check(sim.radio.answer(int(ask.id), "home"), "the player says home")
	check(night.leave_requested, "the place's scene is asked to leave")
	scene.tick(DT)
	check(scene._leave_asked, "the squad is asked to go back")
	eq(scene.hint_line().begins_with("Head for the exit: the road home takes "), true, "the hint says where: %s" % scene.hint_line())
	_walk_out(scene)
	eq(scene.leg, "home", "the way home begins")
	check(not night.leave_requested, "the request was put down")
	var back: Dictionary = night.road_status()
	check(bool(back.on) and not bool(back.in_place), "the road status: on the road home now: %s" % str(back))
	h.refresh()
	check(h.leave_label.visible and String(h.leave_label.text).begins_with("On the road home: back by "), "the line says when they are back: %s" % h.leave_label.text)
	PlaceFlow.live_enabled = true
	await TutorialKit.leave(main)
