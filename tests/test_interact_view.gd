extends "res://tests/case.gd"
## Round 18, V2.5 INTERACT-VIEW: what E does, seen (scripts/render/overlay_node.gd, scripts/ui/talk_card.gd, the HUD's talk section and
## main.gd's E key and events). The prompt (a pill beside the nearest thing in reach: "E  Talk to Dez", the reason of a refusal under
## it, dimmer), a post held wears the steady stance, a bench session its ring; E uses what the prompt is on; a person's answer is the
## talk card (what they say and need, trust, the radio's verbs: asks, never commands). The rules are tests/test_interact.gd's: here the
## game's interact module is a stand-in (`FakeInteract`, put in the sim's meta "interact_stub", which `TalkCard.interact_of` honours)
## that says what the test wants it to, and the last tests run against the real module when there is one.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Kit := preload("res://tests/hud_kit.gd")
const TextTests := preload("res://tests/test_hud_text.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const TalkCard := preload("res://scripts/ui/talk_card.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")

const DT := 1.0 / 30.0
const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0
const ARENA := Rect2i(34, 26, 20, 12)
const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]


## The interact module as the views meet it: the candidates are whatever a test sets, `use` does what the rules' would (a person is
## talked to and says their line, a post is taken and again left, the bench is worked and again stopped, a car's fuel is read, a
## refusal is told), and the events are the rules' own.
class FakeInteract:
	extends RefCounted
	const BENCH_SECONDS := 12.0
	const TALK_LEAVE := 3.5
	var sim
	var cands: Array = []
	var posted := ""
	var working := ""
	var work_left := 0.0
	var needs := {}
	var gain := 1.0
	var used: Array = []

	func candidates() -> Array:
		return cands

	func best() -> Dictionary:
		return cands[0] if not cands.is_empty() else {}

	func needs_of(p) -> Array:
		return needs.get(String(p.id), [])

	func talk_to(p) -> Dictionary:
		if p == null or p.dead or p.turned or p.player:
			return {"ok": false, "why": "Nobody there"}
		var n := needs_of(p)
		var line := String(n[0].line) if not n.is_empty() else "%s." % String(p.activity)
		sim.events.append({"type": "talk", "who": p.id, "line": line})
		return {"ok": true, "who": p.id, "line": line, "needs": n, "trust": p.trust, "tone": sim.radio.tone_of(p), "gain": gain}

	func take_post(post_id: String) -> Dictionary:
		posted = post_id
		sim.events.append({"type": "post_taken", "post": post_id})
		return {"ok": true, "line": "On the %s post. Steadier here." % post_id}

	func work_bench() -> Dictionary:
		working = "bench"
		work_left = BENCH_SECONDS
		sim.events.append({"type": "bench_work", "on": true})
		return {"ok": true, "line": "At the bench."}

	func use(cand: Dictionary = {}) -> Dictionary:
		var c := cand if not cand.is_empty() else best()
		used.append(c)
		if c.is_empty():
			return {"ok": false, "why": "Nothing here to use"}
		var out := {"ok": bool(c.ok), "kind": c.kind, "id": c.id, "why": String(c.why)}
		sim.events.append({"type": "interact", "kind": c.kind, "id": c.id, "ok": bool(c.ok)})
		if not bool(c.ok):
			return out
		match String(c.kind):
			"person":
				var who = null
				for p in sim.people:
					if p.id == c.id:
						who = p
				var r := talk_to(who)
				r.merge(out, true)
				return r
			"post":
				if posted == String(c.id):
					posted = ""
					sim.events.append({"type": "post_left"})
					out["left"] = true
					return out
				var r2 := take_post(String(c.id))
				r2.merge(out, true)
				return r2
			"bench":
				if working == "bench":
					working = ""
					sim.events.append({"type": "bench_work", "on": false, "ammo": 20, "scrap": 5})
					out["stopped"] = true
					return out
				var r3 := work_bench()
				r3.merge(out, true)
				return r3
			"vehicle":
				out["line"] = "Pickup: fuel 14 in the tank, about 5 hours of driving; 82% sound"
				return out
		return out


# ----------------------------------------------------------------- helpers --

## The real game (the classic start, six people) in a window of this size with the avatar (Ruth) in the middle of a clear arena, the
## camera on her, nobody working and nothing about, and the stand-in interact module installed.
func _game(width: int = 1280, height: int = 800) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 6, "avatar": true}, width, height)
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			main.world.solid_p[ty * main.world.W + tx] = 0
			main.world.solid_z[ty * main.world.W + tx] = 0
	var sim = main.sim
	sim.zombies.clear()
	sim.waves.enabled = false
	sim.jobs.clear()
	sim.tactics.chores = false
	var fake := FakeInteract.new()
	fake.sim = sim
	sim.set_meta("interact_stub", fake)
	_stand(main, _me(main), SPOT)
	main.cam_center = SPOT
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	return main


func _fake(main: Node) -> FakeInteract:
	return main.sim.get_meta("interact_stub")


func _me(main: Node):
	return main.sim.avatar.player()


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


func _stand(main: Node, p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.goal_key = ""
	p.order = null
	main._sync_views()


## A person at `dx`, `dy` tiles from the avatar, still.
func _beside(main: Node, id: String, dx: float, dy: float = 0.0):
	var p = _person(main, id)
	var me = _me(main)
	_stand(main, p, Vector2(me.x + dx, me.y + dy))
	return p


## A candidate as the rules give them.
func _cand(kind: String, id: String, label: String, dist: float, ok: bool = true, why: String = "", pos: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"kind": kind, "id": id, "label": label, "pos": pos, "dist": dist, "ok": ok, "why": why}


func _talk_cand(main: Node, id: String, dist: float = 1.0) -> Dictionary:
	var p = _person(main, id)
	return _cand("person", id, "Talk to %s" % String(p.first), dist, true, "", Vector2(p.x, p.y))


func _frames(main: Node, n: int, dt: float = DT) -> void:
	for i in n:
		main._process(dt)


func _draw_once(main: Node) -> void:
	main._process(DT)
	main.overlay.queue_redraw()
	await TutorialKit.settle()


func _press(main: Node, code: Key, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	ev.shift_pressed = shift
	main._unhandled_input(ev)


## The HUD's words: every visible label under a node.
func _words(node: Node) -> String:
	var out: Array = []
	_collect(node, out)
	return " | ".join(out)


func _collect(node: Node, out: Array) -> void:
	if node is Control and not node.visible:
		return
	if node is Label and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_collect(c, out)


func _need(id: String, text: String, line: String, page: String = "") -> Dictionary:
	return {"id": id, "text": text, "line": line, "page": page}


## Opens the talk card on `id` (Dez by default) beside the avatar, the way E does.
func _talk(main: Node, id: String = "dez", dx: float = 1.2) -> Dictionary:
	var p = _beside(main, id, dx)
	var fake := _fake(main)
	fake.cands = [_talk_cand(main, id, absf(dx))]
	_frames(main, 4)
	_press(main, KEY_E)
	_frames(main, 4)
	return {"p": p, "fake": fake}


func _free(main: Node) -> void:
	await TutorialKit.leave(main)


# ------------------------------------------------------- choosing the prompt --

func test_the_prompt_keeps_to_the_thing_it_is_on_until_another_is_a_third_of_a_tile_nearer() -> void:
	var dez := _cand("person", "dez", "Talk to Dez", 1.0)
	var ana := _cand("person", "ana", "Talk to Ana", 1.2)
	eq(OverlayNode.choose_prompt([], "person:dez"), {}, "nothing in reach, no prompt")
	eq(OverlayNode.choose_prompt([dez, ana], "")["id"], "dez", "with none held the nearest")
	eq(OverlayNode.choose_prompt([dez, ana], "person:dez")["id"], "dez", "the nearest, held")
	eq(OverlayNode.choose_prompt([dez, ana], "person:ana")["id"], "ana", "Ana is 0.2 farther: the prompt stays on her")
	var far := _cand("person", "ana", "Talk to Ana", 1.31)
	eq(OverlayNode.choose_prompt([dez, far], "person:ana")["id"], "dez", "at 0.31 farther it moves to the nearest")
	eq(OverlayNode.choose_prompt([dez], "person:ana")["id"], "dez", "a held thing out of reach is let go")
	eq(OverlayNode.key_of(dez), "person:dez", "a candidate's key is its kind and id")
	eq(OverlayNode.key_of({}), "", "none has none")


func test_what_the_avatar_has_begun_comes_first_so_that_e_can_end_it() -> void:
	var dez := _cand("person", "dez", "Talk to Dez", 1.0)
	var bench := _cand("bench", "bench", "Stop working the bench", 1.2)
	var far := _cand("bench", "bench", "Stop working the bench", 1.4)
	eq(OverlayNode.started_first([dez, bench], ["bench:bench"])[0]["id"], "bench", "the bench being worked, 0.2 behind Dez, is first")
	eq(OverlayNode.started_first([dez, far], ["bench:bench"])[0]["id"], "dez", "0.4 behind it is not")
	eq(OverlayNode.started_first([dez, bench], [])[0]["id"], "dez", "nothing begun, nothing moves")
	eq(OverlayNode.started_first([bench, dez], ["bench:bench"])[0]["id"], "bench", "already first")
	var post := _cand("post", "gate", "Leave the gate post", 1.1)
	eq(OverlayNode.started_first([dez, post], ["post:gate"])[0]["id"], "gate", "a post held too")


func test_with_a_session_going_the_prompt_and_e_are_on_the_bench_even_with_a_person_as_near() -> void:
	var main := _game()
	var fake := _fake(main)
	var me = _me(main)
	_beside(main, "dez", 1.0)
	fake.working = "bench"
	fake.work_left = 6.0
	fake.cands = [_talk_cand(main, "dez", 1.0), _cand("bench", "bench", "Stop working the bench", 1.1, true, "", Vector2(me.x, me.y + 1.1))]
	await _draw_once(main)
	eq(main.overlay.prompt_text, "E  Stop working the bench", "the pill offers to stop")
	_press(main, KEY_E)
	_frames(main, 1)
	eq(fake.working, "", "and E stops it, it does not talk")
	check(not main.hud.talk_open(), "no card")
	await _free(main)


# -------------------------------------------------------------- the prompt --

func test_the_prompt_stands_beside_the_nearest_thing_and_says_what_e_does() -> void:
	var main := _game()
	_beside(main, "dez", 1.2)
	_fake(main).cands = [_talk_cand(main, "dez", 1.2)]
	await _draw_once(main)
	var o = main.overlay
	check(o.drew_prompt, "the pill is drawn")
	eq(o.prompt_text, "E  Talk to Dez", "it says the key and what it does")
	check(o.prompt_ok, "talking may be done")
	eq(o.prompt_key, "person:dez", "it is on Dez")
	check(Rect2(Vector2.ZERO, main._vp()).encloses(o.prompt_rect), "inside the window: %s" % str(o.prompt_rect))
	var dez_px: Vector2 = main._tile_to_screen(Vector2(_person(main, "dez").x, _person(main, "dez").y))
	check(o.prompt_rect.position.distance_to(dez_px) < 260.0, "and beside him: %s %s" % [str(o.prompt_rect), str(dez_px)])
	for r in main.hud.covered_rects():
		check(not o.prompt_rect.intersects(r), "not under a board of the HUD: %s" % str(r))
	_fake(main).cands = []
	await _draw_once(main)
	check(not o.drew_prompt and o.prompt_text == "", "nothing in reach, no prompt")
	await _free(main)


func test_each_kind_of_thing_has_its_words() -> void:
	var main := _game()
	var me = _me(main)
	var at := Vector2(me.x + 1.0, me.y)
	var fake := _fake(main)
	for pair in [
		[_cand("post", "gate", "Take the gate post", 1.0, true, "", at), "E  Take the gate post"],
		[_cand("bench", "bench", "Work the bench", 1.0, true, "", at), "E  Work the bench"],
		[_cand("vehicle", "v1", "Check the pickup's fuel", 1.0, true, "", at), "E  Check the pickup's fuel"],
	]:
		fake.cands = [pair[0]]
		await _draw_once(main)
		eq(main.overlay.prompt_text, pair[1], "the words of a %s" % pair[0].kind)
		check(main.overlay.drew_prompt, "drawn: %s" % pair[1])
	await _free(main)


func test_a_refusal_is_drawn_dimmer_with_its_reason() -> void:
	var main := _game()
	var me = _me(main)
	_fake(main).cands = [_cand("post", "gate", "Take the gate post", 1.0, false, "Dez is at the post", Vector2(me.x + 1.0, me.y))]
	await _draw_once(main)
	var o = main.overlay
	eq(o.prompt_text, "E  Take the gate post: Dez is at the post", "the reason follows the words")
	check(not o.prompt_ok, "it is the dim one")
	check(o.drew_prompt, "and still drawn")
	check(o.prompt_rect.size.y > 30.0, "with the reason on a line of its own: %s" % str(o.prompt_rect))
	await _free(main)


func test_the_prompt_in_the_scene_does_not_flicker_between_two_people() -> void:
	var main := _game()
	var fake := _fake(main)
	_beside(main, "dez", 1.2)
	_beside(main, "ana", -1.3)
	fake.cands = [_talk_cand(main, "dez", 1.0), _talk_cand(main, "ana", 1.2)]
	await _draw_once(main)
	eq(main.overlay.prompt_key, "person:dez", "the nearest")
	fake.cands = [_talk_cand(main, "ana", 1.0), _talk_cand(main, "dez", 1.2)]
	await _draw_once(main)
	eq(main.overlay.prompt_key, "person:dez", "Ana is nearer by 0.2: the prompt stays on Dez")
	fake.cands = [_talk_cand(main, "ana", 0.8), _talk_cand(main, "dez", 1.2)]
	await _draw_once(main)
	eq(main.overlay.prompt_key, "person:ana", "by 0.4 it moves to Ana")
	await _free(main)


func test_e_does_what_the_pill_says_not_what_is_nearest_now() -> void:
	var main := _game()
	var fake := _fake(main)
	_beside(main, "dez", 1.2)
	_beside(main, "ana", -1.3)
	fake.cands = [_talk_cand(main, "dez", 1.0), _talk_cand(main, "ana", 1.2)]
	await _draw_once(main)
	fake.cands = [_talk_cand(main, "ana", 1.0), _talk_cand(main, "dez", 1.2)]
	_press(main, KEY_E)
	eq(fake.used.size(), 1, "E used something")
	eq(fake.used[0].id, "dez", "the thing the prompt was on, held")
	await _free(main)


func test_no_prompt_under_a_page_a_menu_a_place_or_in_the_old_yard() -> void:
	var main := _game()
	_beside(main, "dez", 1.2)
	_fake(main).cands = [_talk_cand(main, "dez", 1.2)]
	await _draw_once(main)
	check(main.overlay.drew_prompt, "there is one to start with")
	main.hud.open_jobs(main.sim)
	await _draw_once(main)
	check(not main.overlay.drew_prompt and main.overlay.prompt_text == "", "none under a page")
	main.hud.close_jobs()
	await _draw_once(main)
	check(main.overlay.drew_prompt, "and back when it is shut")
	main.open_pause()
	await _draw_once(main)
	check(not main.overlay.drew_prompt, "none under a menu")
	main.shell.close_all()
	main.raid = Node.new()
	await _draw_once(main)
	check(not main.overlay.drew_prompt, "none in a place")
	main.raid.free()
	main.raid = null
	await _draw_once(main)
	check(main.overlay.drew_prompt, "back in the yard")
	main.sim.over = "defeat"
	await _draw_once(main)
	check(not main.overlay.drew_prompt, "none at the end of the run")
	main.sim.over = ""
	await _free(main)
	var old = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 6}, 1280, 800)
	old.sim.set_meta("interact_stub", FakeInteract.new())
	var f = old.sim.get_meta("interact_stub")
	f.sim = old.sim
	f.cands = [_cand("person", "dez", "Talk to Dez", 1.0, true, "", Vector2(41, 30))]
	await _draw_once(old)
	check(not old.overlay.drew_prompt, "none in the old yard")
	await TutorialKit.leave(old)


func test_the_prompt_stays_with_the_radio_panel_open() -> void:
	var main := _game()
	if not main.hud.has_method("open_radio"):
		await _free(main)
		return
	_beside(main, "dez", 1.2)
	_fake(main).cands = [_talk_cand(main, "dez", 1.2)]
	main.hud.update_hud(main.sim, 1, true, 0)
	main.hud.open_radio("news")
	await TutorialKit.settle()
	await _draw_once(main)
	check(main.hud.radio_open(), "the panel is open")
	check(not main.hud.modal_open() and not main.avatar_hands_off(), "and it is not a modal")
	check(main.overlay.drew_prompt, "the prompt stays: %s" % str(main.overlay.prompt_rect))
	for r in main.hud.covered_rects():
		check(not main.overlay.prompt_rect.intersects(r), "off the panel and the boards: %s" % str(r))
	await _free(main)


# ------------------------------------------------------ stance and the bench --

func test_a_post_held_wears_the_steady_stance_and_the_bench_its_ring() -> void:
	var main := _game()
	var fake := _fake(main)
	await _draw_once(main)
	check(not main.overlay.drew_brace and not main.overlay.drew_bench_ring, "none of either at first")
	fake.posted = "gate"
	await _draw_once(main)
	check(main.overlay.drew_brace, "a post held: the steady stance")
	check(not main.overlay.drew_bench_ring, "and no ring")
	fake.posted = ""
	fake.working = "bench"
	fake.work_left = 9.0
	await _draw_once(main)
	check(main.overlay.drew_bench_ring, "the bench is being worked: its ring")
	near(main.overlay.bench_progress, 0.25, 0.001, "a quarter of the 12 seconds gone")
	fake.work_left = 3.0
	await _draw_once(main)
	near(main.overlay.bench_progress, 0.75, 0.001, "three quarters")
	fake.working = ""
	await _draw_once(main)
	check(not main.overlay.drew_bench_ring and not main.overlay.drew_brace, "and gone with it")
	await _free(main)


# ----------------------------------------------------------------- the E key --

func test_e_at_a_person_opens_the_card_and_they_say_their_line_over_their_head() -> void:
	var main := _game()
	var fake := _fake(main)
	fake.needs = {"dez": [_need("hungry", "Hungry", "I could eat something.")]}
	var dez = _beside(main, "dez", 1.2)
	fake.cands = [_talk_cand(main, "dez", 1.2)]
	_frames(main, 4)
	check(not main.hud.talk_open(), "no card yet")
	_press(main, KEY_E)
	_frames(main, 2)
	check(main.hud.talk_open(), "the card is open")
	eq(main.hud.talk_person(), dez, "for Dez")
	eq(fake.used.size(), 1, "E used the rules' interact once")
	var heard := false
	for b in main.overlay.bubbles:
		if b.p == dez and String(b.text) == "I could eat something.":
			heard = true
	check(heard, "his line is in a bubble over his head")
	check(main.hud.talk_card.is_visible_in_tree(), "the card is on the screen")
	await _free(main)


func test_e_again_closes_the_card_and_the_prompt_says_so() -> void:
	var main := _game()
	var fake := _fake(main)
	await _talk(main)
	check(main.hud.talk_open(), "open")
	await _draw_once(main)
	eq(main.overlay.prompt_text, "E  End the talk with Dez", "while it is open E ends it, and the pill says that")
	_press(main, KEY_E)
	check(not main.hud.talk_open(), "E again closed it")
	eq(fake.used.size(), 1, "without using the rules' interact again")
	await _draw_once(main)
	eq(main.overlay.prompt_text, "E  Talk to Dez", "and the pill is the talk again")
	await _free(main)


func test_escape_closes_the_card_before_anything_else() -> void:
	var main := _game()
	await _talk(main)
	check(main.hud.talk_open(), "open")
	_press(main, KEY_ESCAPE)
	check(not main.hud.talk_open(), "Esc closes the card")
	check(not main.menu_open, "and does not open the pause menu")
	_press(main, KEY_ESCAPE)
	check(main.menu_open, "the next one does")
	main.shell.close_all()
	await _free(main)


func test_e_at_a_post_the_bench_and_a_car_answers_in_a_toast_and_a_refusal_in_amber() -> void:
	var main := _game()
	var fake := _fake(main)
	var me = _me(main)
	var here := Vector2(me.x + 1.0, me.y)
	var h = main.hud
	fake.cands = [_cand("post", "gate", "Take the gate post", 1.0, true, "", here)]
	_frames(main, 3)
	_press(main, KEY_E)
	_frames(main, 1)
	eq(h.toast_label.text, "On the gate post. Steadier here.", "the post: the rules' line")
	eq(h.toast_col, h.INFO, "plain")
	fake.cands = [_cand("post", "gate", "Leave the gate post", 1.0, true, "", here)]
	_press(main, KEY_E)
	eq(h.toast_label.text, "Left the post", "again leaves it")
	fake.cands = [_cand("post", "bus", "Take the school bus post", 1.0, false, "Dez is at the post", here)]
	_frames(main, 3)
	_press(main, KEY_E)
	eq(h.toast_label.text, "Dez is at the post", "a refusal says why")
	eq(h.toast_col, h.WARN, "in amber")
	fake.cands = [_cand("vehicle", "v1", "Check the pickup's fuel", 1.0, true, "", here)]
	_frames(main, 3)
	_press(main, KEY_E)
	check(h.toast_label.text.begins_with("Pickup: fuel 14"), "a car: its fuel line: %s" % h.toast_label.text)
	fake.cands = [_cand("bench", "bench", "Work the bench", 1.0, true, "", here)]
	_frames(main, 3)
	_press(main, KEY_E)
	_frames(main, 1)
	eq(fake.working, "bench", "the bench is worked")
	check(not h.talk_open(), "no card for a thing")
	fake.cands = [_cand("bench", "bench", "Stop working the bench", 1.0, true, "", here)]
	_press(main, KEY_E)
	_frames(main, 1)
	eq(fake.working, "", "and stopped")
	check(h.toast_label.text.begins_with("Bench: 20 rounds from 5 scrap"), "with what it made: %s" % h.toast_label.text)
	await _free(main)


func test_e_with_nothing_in_reach_says_so_and_under_a_page_does_nothing() -> void:
	var main := _game()
	var fake := _fake(main)
	fake.cands = []
	_frames(main, 2)
	_press(main, KEY_E)
	eq(main.hud.toast_label.text, "Nothing here to use", "nothing to use")
	eq(main.hud.toast_col, main.hud.INFO, "said calmly")
	check(not main.hud.talk_open(), "no card")
	fake.cands = [_talk_cand(main, "dez", 1.0)]
	_beside(main, "dez", 1.0)
	fake.used = []
	main.hud.open_jobs(main.sim)
	await TutorialKit.settle()
	_press(main, KEY_E)
	eq(fake.used.size(), 0, "under a page E does not use anything")
	check(not main.hud.talk_open(), "and no card")
	main.hud.close_jobs()
	await _free(main)


func test_e_is_only_for_the_avatar() -> void:
	var old = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 6}, 1280, 800)
	var f := FakeInteract.new()
	f.sim = old.sim
	old.sim.set_meta("interact_stub", f)
	f.cands = [_cand("person", "dez", "Talk to Dez", 1.0, true, "", Vector2(41, 30))]
	_press(old, KEY_E)
	eq(f.used.size(), 0, "in the old yard E is nothing")
	await TutorialKit.leave(old)


func test_the_events_of_the_rules_have_their_sounds_and_a_bench_that_ends_says_what_it_made() -> void:
	var main := _game()
	var sim = main.sim
	var h = main.hud
	for e in [{"type": "interact", "kind": "post", "id": "gate", "ok": true}, {"type": "interact", "kind": "post", "id": "gate", "ok": false},
			{"type": "post_taken", "post": "gate"}, {"type": "post_left"}, {"type": "bench_work", "on": true},
			{"type": "bench_work", "on": false, "ammo": 14, "scrap": 7}, {"type": "bench_work", "on": false, "ammo": 0, "scrap": 0},
			{"type": "talk", "who": "dez", "line": "Hauling crates."}]:
		sim.events.append(e)
	_frames(main, 1)
	check(String(h.toast_label.text).begins_with("Bench: 14 rounds from 7 scrap"), "the bench said what it made: %s" % h.toast_label.text)
	var said := false
	for b in main.overlay.bubbles:
		if b.p == _person(main, "dez") and b.text == "Hauling crates.":
			said = true
	check(said, "a word is a bubble")
	await _free(main)


# ---------------------------------------------------------------- the card --

func test_the_card_says_what_they_say_what_they_need_and_how_far_they_trust() -> void:
	var main := _game()
	var fake := _fake(main)
	fake.needs = {"dez": [_need("hungry", "Hungry", "I could eat something."), _need("nojob", "No job: nothing to do. Give them one", "I have nothing to do.", "jobs")]}
	var t := await _talk(main)
	var h = main.hud
	var card = h.talk_card
	await TutorialKit.settle()
	var words := _words(card)
	check(words.contains("Dez"), "the name: %s" % words)
	check(words.contains("I could eat something."), "the line they say: %s" % words)
	check(words.contains("THEY NEED"), "the heading: %s" % words)
	check(words.contains("Hungry") and words.contains("No job: nothing to do. Give them one"), "each need: %s" % words)
	check(words.contains("TRUST"), "the trust: %s" % words)
	var radio = main.sim.radio
	eq(card.trust_word.text, radio.tone_of(t.p), "the word of the trust is the radio's")
	near(card.trust_bar.value, radio.trust_of(t.p) / 100.0, 0.001, "and the bar")
	eq(card.need_rows.size(), 2, "two needs")
	check(card.need_rows[0].button == null, "a need no page can mend has no button")
	check(card.need_rows[1].button != null, "a need a page can mend has one")
	check(card.need_rows[1].button.text.contains("Jobs"), "that says where: %s" % card.need_rows[1].button.text)
	await _free(main)


func test_a_need_with_a_page_opens_that_page_of_the_radio_for_them() -> void:
	var main := _game()
	_fake(main).needs = {"dez": [_need("nojob", "No job: nothing to do. Give them one", "I have nothing to do.", "jobs")]}
	await _talk(main)
	var card = main.hud.talk_card
	card.need_rows[0].button.pressed.emit()
	eq(card.last_page_request, {"page": "jobs", "focus": "dez"}, "the page and the person")
	if main.hud.has_method("open_radio"):
		check(main.hud.radio_open() and main.hud.radio_page() == "jobs", "the radio panel is on Jobs")
		check(not main.hud.modal_open(), "and it stays a board, not a page")
	await _free(main)


func test_a_person_with_no_needs_says_what_they_do_and_needs_nothing() -> void:
	var main := _game()
	var fake := _fake(main)
	await _talk(main)
	var card = main.hud.talk_card
	_person(main, "dez").activity = "Hauling crates"
	main.hud.update_hud(main.sim, 1, true, 0)
	await TutorialKit.settle()
	var words := _words(card)
	check(words.contains("Hauling crates."), "what they are doing: %s" % words)
	check(words.contains(TalkCard.NEED_NONE), "and that they need nothing: %s" % words)
	eq(card.need_rows.size(), 0, "no rows")
	# a need that comes up while the card is open is shown, and the line they say follows it
	fake.needs = {"dez": [_need("hungry", "Hungry", "I'm hungry.")]}
	main.hud.update_hud(main.sim, 1, true, 0)
	await TutorialKit.settle()
	words = _words(card)
	check(words.contains("Hungry") and words.contains("I'm hungry."), "a need that came up: %s" % words)
	eq(card.need_rows.size(), 1, "one row")
	await _free(main)


func test_the_word_of_the_day_is_in_the_card_once() -> void:
	var main := _game()
	var fake := _fake(main)
	fake.gain = 1.0
	await _talk(main)
	var card = main.hud.talk_card
	check(card.gain_label.visible and card.gain_label.text == "Had a word with you: trust +1", "the day's first word: %s" % card.gain_label.text)
	main.hud.hide_talk()
	fake.gain = 0.0
	_press(main, KEY_E)
	_frames(main, 3)
	check(main.hud.talk_open(), "open again")
	check(not card.gain_label.visible, "the second the same day earns no line")
	await _free(main)


func test_the_cards_verbs_are_the_radios_and_ask_never_command() -> void:
	var main := _game()
	var t := await _talk(main)
	var card = main.hud.talk_card
	var v = card.verbs
	eq(v.columns, 3, "three to a row")
	eq(v.verbs_shown(), ["come", "hold", "cover", "search", "back", "post"], "the six verbs of the radio")
	check(not v.buttons["search"].visible, "Search that is for a place: not offered in the yard")
	var radio = main.sim.radio
	var before: int = radio.pending.size()
	v.buttons["come"].pressed.emit()
	eq(radio.pending.size(), before + 1, "asking goes to the radio, which will do it after its delay")
	eq(radio.pending[radio.pending.size() - 1].verb, "come", "to come")
	check(String(v.reply.text).begins_with("Dez:"), "and what he says is in the card: %s" % v.reply.text)
	check(t.p.stance != "follow", "it is a request: nothing happens at once")
	await _free(main)


func test_a_refusal_shows_in_amber_in_the_card_and_insist_costs_trust() -> void:
	var main := _game()
	var ana = _person(main, "ana")
	ana.bleeding = 2.0
	ana.wounds = 1
	var t := await _talk(main, "ana")
	var card = main.hud.talk_card
	var v = card.verbs
	var trust0: float = ana.trust
	v.buttons["cover"].pressed.emit()
	check(not bool(v.last.ok), "she cannot cover you")
	check(String(v.reply.text).to_lower().contains("bleeding"), "and says why: %s" % v.reply.text)
	eq(v.reply.get_theme_color("font_color"), main.hud.WARN, "in amber")
	check(v.insist_button.visible, "a soft refusal can be insisted on")
	v.insist_button.pressed.emit()
	check(ana.trust < trust0, "insisting cost trust: %s -> %s" % [trust0, ana.trust])
	check(t.p == ana, "still her card")
	await _free(main)


func test_the_card_closes_when_the_talk_is_over() -> void:
	var cases := {
		"the avatar walks away": func(main, p): _stand(main, _me(main), Vector2(p.x + 4.0, p.y)),
		"they are downed": func(_main, p): p.downed = true,
		"they die": func(_main, p): p.dead = true,
		"they go away": func(_main, p): p.away = {"kind": "party"},
		"the avatar is down": func(main, _p): _me(main).downed = true,
		"a page opens": func(main, _p): main.hud.open_jobs(main.sim),
	}
	for label in cases:
		var main := _game()
		var t := await _talk(main)
		check(main.hud.talk_open(), "%s: open to begin with" % label)
		cases[label].call(main, t.p)
		main.hud.update_hud(main.sim, 1, true, 0)
		check(not main.hud.talk_open(), "%s: the card closes" % label)
		check(not main.hud.talk_card.visible, "%s: and is not on the screen" % label)
		if main.hud.jobs_screen != null:
			main.hud.close_jobs()
		await _free(main)


func test_the_card_stays_while_the_avatar_is_within_reach_and_the_game_runs_on() -> void:
	var main := _game()
	var t := await _talk(main)
	var speed0: int = main.speed
	_stand(main, _me(main), Vector2(t.p.x + 3.2, t.p.y))
	_frames(main, 12)
	check(main.hud.talk_open(), "3.2 tiles away it is still open")
	check(not main.hud.modal_open() and not main.avatar_hands_off(), "the card is not a modal: the hands are free")
	eq(main.speed, speed0, "nothing was paused")
	var steps: int = main.sim_steps
	_frames(main, 6)
	check(main.sim_steps > steps, "the game goes on")
	_stand(main, _me(main), Vector2(t.p.x + 3.6, t.p.y))
	main.hud.update_hud(main.sim, 1, true, 0)
	check(not main.hud.talk_open(), "past 3.5 tiles it closes")
	await _free(main)


func test_a_click_on_the_card_does_not_fire_the_gun() -> void:
	var main := _game()
	await _talk(main)
	await TutorialKit.settle()
	var card = main.hud.talk_card
	check(card.mouse_filter == Control.MOUSE_FILTER_STOP, "the card takes the mouse: a click on it is not a shot")
	await _free(main)


# ------------------------------------------------------------------ placing --

func test_the_card_keeps_off_the_person_the_avatar_and_the_window_edge_at_every_size() -> void:
	for size in SIZES:
		var main := _game(size[0], size[1])
		var t := await _talk(main)
		await TutorialKit.settle()
		_frames(main, 3)
		await TutorialKit.settle()
		var h = main.hud
		var card = h.talk_card
		check(h.talk_open(), "%d x %d: open" % [size[0], size[1]])
		var r: Rect2 = card.get_global_rect()
		var win := Rect2(Vector2.ZERO, Vector2(size[0], size[1]))
		check(win.encloses(r), "%d x %d: inside the window: %s" % [size[0], size[1], str(r)])
		var me = _me(main)
		var you: Vector2 = main._tile_to_screen(Vector2(me.x, me.y))
		check(not r.has_point(you), "%d x %d: not over the avatar (%s in %s)" % [size[0], size[1], str(you), str(r)])
		var them: Vector2 = main._tile_to_screen(Vector2(t.p.x, t.p.y - 0.5))
		check(not r.has_point(them), "%d x %d: not over the person" % [size[0], size[1]])
		await _free(main)


func test_place_chooses_the_side_with_room_and_keeps_to_it() -> void:
	var view := Rect2(0, 0, 1280, 800)
	var card := Vector2(330, 300)
	var bodies := func(placed: Dictionary, a: Vector2, b: Vector2) -> bool:
		var r := Rect2(placed.pos, card)
		return not r.intersects(Rect2(a.x - 24.0, a.y - 55.0, 48.0, 84.0)) and not r.intersects(Rect2(b.x - 24.0, b.y - 55.0, 48.0, 84.0))
	var right_of_you := TalkCard.place(card, Vector2(720, 400), Vector2(640, 400), 48.0, view, [])
	eq(right_of_you.side, "right", "a person on your right: the card beyond the two of them")
	check(bodies.call(right_of_you, Vector2(720, 400), Vector2(640, 400)), "off both")
	var left_of_you := TalkCard.place(card, Vector2(560, 400), Vector2(640, 400), 48.0, view, [])
	eq(left_of_you.side, "left", "a person on your left: the card on the left")
	check(bodies.call(left_of_you, Vector2(560, 400), Vector2(640, 400)), "off both")
	var edge := TalkCard.place(card, Vector2(1250, 400), Vector2(1180, 400), 48.0, view, [])
	check(view.encloses(Rect2(edge.pos, card)), "kept inside the window at its edge: %s" % str(edge.pos))
	check(bodies.call(edge, Vector2(1250, 400), Vector2(1180, 400)), "and still off both: %s" % str(edge))
	var boards := [Rect2(760, 0, 520, 800)]
	var avoided := TalkCard.place(card, Vector2(720, 400), Vector2(640, 400), 48.0, view, boards)
	check(avoided.side != "right", "a board on the right: another side (%s)" % avoided.side)
	# both sides clear: it stays on the one it was on
	var here := Vector2(700, 400)
	var you := Vector2(600, 400)
	eq(TalkCard.place(card, here, you, 48.0, view, [], "left").side, "left", "it stays on the left")
	eq(TalkCard.place(card, here, you, 48.0, view, [], "right").side, "right", "or on the right, whichever it was on")
	# unless that side is covered by a board
	var covered := TalkCard.place(card, here, you, 48.0, view, [Rect2(0, 0, 600, 800)], "left")
	eq(covered.side, "right", "a board over the side it was on moves it")
	# a small window: it covers neither of them where it can help it
	var tight := TalkCard.place(Vector2(330, 263), Vector2(398, 280), Vector2(350, 280), 40.0, Rect2(0, 0, 700, 560), [])
	check(not Rect2(tight.pos, Vector2(330, 263)).has_point(Vector2(350, 280)), "700 x 560: not over the avatar's middle: %s" % str(tight))


func test_the_card_keeps_out_from_under_the_radio_panel_and_the_game_goes_on() -> void:
	for size in [[1280, 800], [700, 560]]:
		var main := _game(size[0], size[1])
		if not main.hud.has_method("open_radio"):
			await _free(main)
			return
		main.hud.update_hud(main.sim, 1, true, 0)
		main.hud.open_radio("jobs")
		await TutorialKit.settle()
		var t := await _talk(main)
		await TutorialKit.settle()
		_frames(main, 4)
		await TutorialKit.settle()
		var card = main.hud.talk_card
		check(main.hud.talk_open(), "%d x %d: open beside the panel" % [size[0], size[1]])
		var panel: Rect2 = main.hud.anchor_rect("panel")
		if panel.size.x > 0.0 and size[0] >= 980:
			check(not card.get_global_rect().intersects(panel), "%d x %d: the card %s is off the panel %s" % [size[0], size[1], str(card.get_global_rect()), str(panel)])
		check(not main.hud.modal_open() and not main.avatar_hands_off(), "%d x %d: both are boards, not pages" % [size[0], size[1]])
		await _free(main)


func test_the_card_follows_the_person_when_the_camera_moves() -> void:
	var main := _game()
	var t := await _talk(main)
	await TutorialKit.settle()
	var card = main.hud.talk_card
	var before: Vector2 = card.position
	main.cam_center += Vector2(1.0, 0.0)
	main._apply_camera()
	_frames(main, 2)
	await TutorialKit.settle()
	check(card.position != before, "it moved with the world: %s -> %s" % [str(before), str(card.position)])
	check(main.hud.talk_open(), "and stayed open for %s" % t.p.first)
	await _free(main)


# -------------------------------------------------------------- the card as built --

func test_the_card_has_no_text_under_twelve_pixels_and_every_word_reads_and_nothing_takes_focus() -> void:
	for size in [[1280, 800], [700, 560]]:
		var main := _game(size[0], size[1])
		var fake := _fake(main)
		fake.needs = {"ana": [_need("bleed", "Bleeding: needs the infirmary", "I'm bleeding."), _need("nojob", "No job: nothing to do. Give them one", "Nothing to do.", "jobs")]}
		_person(main, "ana").bleeding = 2.0
		await _talk(main, "ana")
		await TutorialKit.settle()
		var card = main.hud.talk_card
		var v = card.verbs
		v.buttons["cover"].pressed.emit()
		await TutorialKit.settle()
		var tt := TextTests.new()
		eq(tt._small_text(card), [], "%d x %d: nothing under 12 px" % [size[0], size[1]])
		eq(tt._hard_to_read(card, Color.WHITE), [], "%d x %d: every word reads at 4.5:1" % [size[0], size[1]])
		var bad: Array = []
		var nodes: Array = [card]
		nodes.append_array(card.find_children("*", "Control", true, false))
		for c in nodes:
			if c is Control and c.focus_mode != Control.FOCUS_NONE:
				bad.append("%s %s" % [c.get_class(), c.name])
		eq(bad, [], "%d x %d: no control of the card takes the keyboard (WASD and E keep working)" % [size[0], size[1]])
		await _free(main)


func test_the_card_is_the_huds_and_has_an_anchor() -> void:
	var main := _game()
	await _talk(main)
	await TutorialKit.settle()
	var r: Rect2 = main.hud.anchor_rect("talk")
	check(r.size.x > 100.0 and r.size.y > 100.0, "the anchor `talk` is the card: %s" % str(r))
	eq(r, main.hud.talk_card.get_global_rect(), "its rectangle")
	check(main.hud.covered_rects().has(r), "and the bubbles keep out from under it")
	main.hud.hide_talk()
	eq(main.hud.anchor_rect("talk"), Rect2(), "none once it is shut")
	await _free(main)


func test_the_card_is_ignored_without_an_avatar_and_standing_alone_in_a_hud() -> void:
	var ctx := Kit.build(1280, 800)
	var sim = ctx.sim
	var f := FakeInteract.new()
	f.sim = sim
	sim.set_meta("interact_stub", f)
	Kit.update(ctx)
	ctx.hud.show_talk(Kit.person(ctx, "dez"), {})
	check(not ctx.hud.talk_open(), "no avatar, no card")
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	Kit.update(ctx)
	var dez = Kit.person(ctx, "dez")
	var me = sim.avatar.player()
	dez.x = me.x + 1.0
	dez.y = me.y
	ctx.hud.show_talk(dez, {"line": "Hello.", "gain": 0.0})
	await Kit.settle()
	check(ctx.hud.talk_open(), "with one, it opens (in a HUD that is no game's: the canvas stands in for the camera)")
	check(Rect2(Vector2.ZERO, Vector2(1280, 800)).encloses(ctx.hud.talk_card.get_global_rect()), "inside the window")
	Kit.update(ctx)
	check(ctx.hud.talk_open(), "and a HUD update keeps it")
	Kit.free_all(ctx)


func test_the_stand_in_is_found_before_the_games_own_interact() -> void:
	var g := TutorialKit.make()
	var sim = g.sim
	var real = sim.get("interact")
	eq(TalkCard.interact_of(sim), real, "with no stand-in it is the sim's own (null, or the module)")
	var f := FakeInteract.new()
	sim.set_meta("interact_stub", f)
	eq(TalkCard.interact_of(sim), f, "the stand-in wins")
	eq(TalkCard.interact_of(null), null, "and a game that is not there has none")
	eq(TalkCard.rule(f, "TALK_LEAVE", 9.0), 3.5, "a number of the rules' script is read from the script")
	eq(TalkCard.rule(f, "NOT_THERE", 9.0), 9.0, "or is the fallback")
	g.world.free()


# ------------------------------------------------------- the screenshots' flags --

func test_the_screenshot_staging_stands_beside_and_opens_the_card_takes_the_post_works_the_bench() -> void:
	var main := _game()
	var fake := _fake(main)
	fake.needs = {"ana": [_need("bleed", "Bleeding: needs the infirmary", "I'm bleeding.")]}
	_person(main, "ana").bleeding = 2.0
	check(main._stage_talk("ana", "cover"), "--talk=ana --talk-ask=cover")
	check(main.hud.talk_open() and main.hud.talk_person().id == "ana", "the card is open on Ana")
	check(not bool(main.hud.talk_card.verbs.last.get("ok", true)), "and the verb was asked: she cannot, in the card")
	var me = _me(main)
	check(Vector2(me.x, me.y).distance_to(Vector2(_person(main, "ana").x, _person(main, "ana").y)) < 1.5, "the avatar stands beside her")
	check(not main._stage_talk("nobody", ""), "no such person")
	main.hud.hide_talk()
	check(main._stage_post("gate"), "--post=gate")
	eq(fake.posted, "gate", "the avatar took the post")
	check(main._stage_bench(), "--bench")
	eq(fake.working, "bench", "and works the bench")
	await _free(main)


# -------------------------------------------------- against the real module --

## The real interact module of the game (round 18's rules), or null while it is not there: the tests below then have nothing to meet.
func _real(main: Node):
	main.sim.remove_meta("interact_stub")
	return main.sim.get("interact")


func test_with_the_real_rules_the_prompt_and_the_card_say_what_the_rules_say() -> void:
	var main := _game()
	var it = _real(main)
	if it == null:
		await _free(main)
		return
	var sim = main.sim
	var dez = _beside(main, "dez", 1.2)
	await _draw_once(main)
	eq(main.overlay.prompt_text, "E  Talk to Dez", "the prompt is the rules' label")
	check(main.overlay.drew_prompt, "drawn")
	var trust0: float = dez.trust
	_press(main, KEY_E)
	_frames(main, 3)
	check(main.hud.talk_open() and main.hud.talk_person() == dez, "E opens the card")
	var words := _words(main.hud.talk_card)
	var said := String(main.hud.talk_card.result.get("line", ""))
	check(said != "" and words.contains(said), "with what the rules have him say (%s): %s" % [said, words])
	check(main.hud.talk_card.gain_label.visible, "the day's word is told")
	near(dez.trust, trust0 + 1.0, 0.001, "and it earned its trust")
	var heard := false
	for b in main.overlay.bubbles:
		if b.p == dez:
			heard = true
	check(heard, "and he spoke over his head")
	for n in it.needs_of(dez):
		check(words.contains(String(n.text)), "each need the rules name is in the card: %s" % n.text)
	_press(main, KEY_E)
	check(not main.hud.talk_open(), "E again closes it")
	await _free(main)


func test_with_the_real_rules_a_post_is_taken_with_the_steady_mark_and_the_bench_worked_with_its_ring() -> void:
	var main := _game()
	var it = _real(main)
	if it == null:
		await _free(main)
		return
	var sim = main.sim
	var me = _me(main)
	sim.stock.ammo = 100.0
	sim.stock.scrap = 40.0
	var bench: Vector2 = sim.workshop.bench()
	_stand(main, me, bench + Vector2(0.0, 1.0))
	main.cam_center = Vector2(me.x, me.y)
	await _draw_once(main)
	check(main.overlay.prompt_text.begins_with("E  "), "a prompt at the bench: %s" % main.overlay.prompt_text)
	_press(main, KEY_E)
	_frames(main, 2)
	check(it.working == "bench", "E at the bench works it: %s" % main.hud.toast_label.text)
	await _draw_once(main)
	check(main.overlay.drew_bench_ring, "the ring shows")
	check(main.overlay.bench_progress >= 0.0 and main.overlay.bench_progress < 1.0, "part of the way")
	_press(main, KEY_E)
	_frames(main, 1)
	eq(it.working, "", "E again stops it")
	var post: Dictionary = sim.jobs.post("gate")
	_stand(main, me, post.pos + Vector2(0.4, 0.0))
	main.cam_center = Vector2(me.x, me.y)
	await _draw_once(main)
	_press(main, KEY_E)
	_frames(main, 2)
	check(it.posted == "gate", "E at the gate post takes it: %s" % main.hud.toast_label.text)
	await _draw_once(main)
	check(main.overlay.drew_brace, "the steady stance is marked")
	await _free(main)
