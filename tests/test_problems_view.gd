extends "res://tests/case.gd"
## Round 25, V25.2 PROBLEMS-VIEW: the base's trouble, seen (scripts/render/base_marks.gd, scripts/ui/problem_list.gd, the overlay's one call and counters,
## main.gd's events and `focus_problem`). The rules are tests/test_problems.gd's: here the problems, the briefing and the dilemmas are STAND-INS (each
## extends the real module, so every hook the rules call still exists) that say what the test wants: the marks the views read, the candidates, who
## would be sent, what the radio answers. A marker for each kind with its words and the colour of its stage, the quarantine's sign, nothing without
## the marks, without an avatar or under a menu; the E prompt of a problem and its dim reason; the fix ring that fills; a facility's label near, far
## and with the Base page open; the Trouble list's rows, its Ask reaching `radio.request_fix` and printing the sim's own refusal.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const BaseMarks := preload("res://scripts/render/base_marks.gd")
const ProblemList := preload("res://scripts/ui/problem_list.gd")

const DT := 1.0 / 30.0
const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0
const ARENA := Rect2i(34, 26, 20, 12)


class FakeProblems:
	extends "res://scripts/sim/problems.gd"
	var list: Array = []
	var cands: Array = []
	var best = null
	var will := {}
	var asked: Array = []
	var separated: Array = []
	var reply := {"ok": true, "line": "On it", "why": "", "hard": false, "tone": "willing", "insisted": false, "chance": 0.72}

	func active() -> bool:
		return true

	func update(_dt: float) -> void:
		pass

	func marks() -> Array:
		return list

	func candidates() -> Array:
		return cands

	func record(id) -> Dictionary:
		for m in list:
			if String(m.id) == String(id):
				return {"id": m.id, "kind": m.kind, "at": m.at, "fixer": String(m.get("fixer", "")), "state": String(m.get("state", "idle"))}
		return {}

	func best_for(_id) -> Variant:
		return best

	func fix_willingness(p, _id) -> Dictionary:
		return will.get(String(p.id), {"ok": true, "why": "", "hard": false, "line": "On it", "tone": "willing", "delay_s": 12.0, "chance": 0.72, "cost": {"scrap": 1}, "eta_h": 0.5})

	func request_fix(id, p, args := {}) -> Dictionary:
		asked.append({"id": String(id), "who": String(p.id), "insist": bool(args.get("insist", false))})
		return reply

	func separate(id) -> Dictionary:
		separated.append(String(id))
		return {"ok": true, "line": "Kept apart: Dez works at the garden now", "why": ""}


class FakeBriefing:
	extends "res://scripts/sim/briefing.gd"
	var places: Array = []

	func facilities() -> Array:
		return places


class FakeDilemmas:
	extends "res://scripts/sim/dilemmas.gd"
	var list: Array = []

	func marks() -> Array:
		return list


class FakeInteract:
	extends RefCounted
	var cands: Array = []
	var posted := ""
	var working := ""
	var work_left := 0.0

	func candidates() -> Array:
		return cands

	func best() -> Dictionary:
		return cands[0] if not cands.is_empty() else {}

	func use(_cand: Dictionary = {}) -> Dictionary:
		return {"ok": true}


# ----------------------------------------------------------------- helpers --

## The real game (the classic start, or the small one with `crew` 3, which has the Base page: the avatar Ruth) with a clear arena, the camera on her, and
## (unless `fakes` is off) the stand-ins of the three modules and of the interact module in the sim.
func _game(crew: int = 6, fakes: bool = true) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": true}, 1280, 800)
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			main.world.solid_p[ty * main.world.W + tx] = 0
			main.world.solid_z[ty * main.world.W + tx] = 0
	var sim = main.sim
	sim.zombies.clear()
	sim.waves.enabled = false
	sim.jobs.clear()
	sim.tactics.chores = false
	if fakes:
		for name in ["problems", "briefing", "dilemmas"]:
			var fake = {"problems": FakeProblems, "briefing": FakeBriefing, "dilemmas": FakeDilemmas}[name].new()
			fake.setup(sim)
			sim.set(name, fake)
		sim.set_meta("interact_stub", FakeInteract.new())
	var me = sim.avatar.player()
	me.x = SPOT.x
	me.y = SPOT.y
	me.moving = false
	me.path = []
	main.cam_center = SPOT
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	main.overlay.base_marks.record = true
	return main


func _mark(id: String, kind: String, at: Vector2, label: String, stage: int = 1, pct: float = 0.4, state: String = "idle") -> Dictionary:
	return {"id": id, "kind": kind, "at": at, "label": label, "stage": stage, "pct": pct, "state": state}


func _draw_once(main: Node) -> void:
	main._process(DT)
	main.overlay.base_marks.forget()
	main.overlay.queue_redraw()
	await TutorialKit.settle()


## What the last draw kept of one kind ("problem", "facility", "sub", "quarantine", "fix").
func _tags(main: Node, what: String) -> Array:
	var out: Array = []
	for t in main.overlay.base_marks.tags:
		if String(t.what) == what:
			out.append(t)
	return out


func _tag_of(main: Node, what: String, id: String) -> Dictionary:
	for t in _tags(main, what):
		if String(t.id) == id:
			return t
	return {}


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


func _cand(id: String, label: String, ok: bool = true, why: String = "") -> Dictionary:
	return {"kind": "problem", "id": id, "label": label, "pos": SPOT + Vector2(1.2, 0.0), "dist": 1.2, "ok": ok, "why": why}


# ------------------------------------------------------------ the markers --

func test_a_marker_draws_for_each_kind_with_its_words_and_the_colour_of_its_stage() -> void:
	var main := _game()
	var pm = main.sim.problems
	pm.list = [
		_mark("p1", "leak", SPOT + Vector2(-5, -2), "Leak: 11 h left", 1, 0.4),
		_mark("p2", "jam", SPOT + Vector2(5, -2), "Jam: 5 h left", 2, 0.7),
		_mark("p3", "quarrel", SPOT + Vector2(-5, 3), "Quarrel: 20 h left", 0, 0.1),
		_mark("p4", "crack", SPOT + Vector2(5, 3), "Crack: 2 h left", 1, 1.0, "walking"),
	]
	main.sim.dilemmas.list = [{"kind": "quarantine", "at": SPOT + Vector2(0, -5), "label": "Quarantine: 2 days"}]
	await _draw_once(main)
	var o = main.overlay
	check(o.drew_problem_marks, "markers are drawn")
	eq(o.drawn_problem_marks, 5, "four problems and the sign of the quarantine")
	eq(o.drawn_problem_labels, 5, "each with its words")
	eq(o.base_marks.drawn_quarantine, 1, "one of them is the quarantine's")
	eq(String(_tag_of(main, "problem", "p1").get("text", "")), "Leak: 11 h left", "the rules' own words, not the view's")
	eq(String(_tag_of(main, "problem", "p3").get("text", "")), "Quarrel: 20 h left", "a quarrel's")
	eq(String(_tag_of(main, "quarantine", "").get("text", "")), "Quarantine: 2 days", "the quarantine's")
	eq(_tag_of(main, "problem", "p1").get("color"), BaseMarks.AMBER, "stage 1 is amber")
	eq(_tag_of(main, "problem", "p3").get("color"), BaseMarks.AMBER, "stage 0 is amber too")
	eq(_tag_of(main, "problem", "p2").get("color"), BaseMarks.RED, "stage 2 is red")
	eq(_tag_of(main, "problem", "p4").get("color"), BaseMarks.RED, "past its time is red")
	for t in main.overlay.base_marks.tags:
		check(Rect2(Vector2.ZERO, main._vp()).encloses(t.rect), "inside the window: %s" % str(t.rect))
		check(float(t.rect.size.y) >= 16.0, "the pill is tall enough for 12 px words: %s" % str(t.rect))
	# a thing off the window is not drawn
	pm.list = [_mark("p1", "leak", SPOT + Vector2(60, 0), "Leak: 11 h left")]
	main.sim.dilemmas.list = []
	await _draw_once(main)
	check(not main.overlay.drew_problem_marks, "a marker 60 tiles away is not drawn")
	# someone on the way: their name under the ring
	pm.list = [_mark("p1", "leak", SPOT + Vector2(-3, -2), "Leak: 11 h left", 1, 0.4, "walking")]
	pm.list[0]["fixer"] = "dez"
	await _draw_once(main)
	eq(String(_tag_of(main, "sub", "p1").get("text", "")), "Dez is on the way", "who has been sent")
	await TutorialKit.leave(main)


func test_nothing_is_drawn_for_no_marks_no_avatar_or_a_menu() -> void:
	var main := _game()
	var o = main.overlay
	main.sim.problems.list = []
	main.sim.briefing.places = []
	await _draw_once(main)
	check(not o.drew_problem_marks and not o.drew_facility_labels and not o.drew_fix_ring, "no problem, nothing drawn")
	main.sim.problems.list = [_mark("p1", "leak", SPOT + Vector2(-3, -2), "Leak: 11 h left")]
	main.sim.problems.fixing = {"id": "p1", "left": 5.0}
	main.sim.briefing.places = [{"id": "bench", "name": "Workshop", "pos": SPOT + Vector2(4, 0), "ok": false, "bottleneck": "waiting on scrap", "line": "Workshop: waiting on scrap"}]
	await _draw_once(main)
	check(o.drew_problem_marks and o.drew_facility_labels and o.drew_fix_ring, "with them, all three are drawn")
	# no avatar: the old yard
	var who: String = main.sim.player_id
	main.sim.player_id = ""
	await _draw_once(main)
	check(not o.drew_problem_marks and not o.drew_facility_labels and not o.drew_fix_ring, "without an avatar nothing is drawn")
	eq(o.base_marks.tags.size(), 0, "nor kept")
	main.sim.player_id = who
	# a menu over the game
	main.hud.last_speed = main.speed
	main.hud.open_jobs(main.sim)
	await _draw_once(main)
	check(not o.drew_problem_marks and not o.drew_facility_labels and not o.drew_fix_ring, "under a menu nothing is drawn")
	await TutorialKit.leave(main)


# --------------------------------------------------------------- the prompt --

func test_the_prompt_of_a_problem_says_what_e_does_and_dims_with_the_reason() -> void:
	var main := _game()
	var it: FakeInteract = main.sim.get_meta("interact_stub")
	var o = main.overlay
	it.cands = [_cand("p1", "Fix the leak")]
	await _draw_once(main)
	eq(o.prompt_text, "E  Fix the leak", "the key and what it does")
	check(o.prompt_ok and o.drew_prompt, "it may be done: the bright pill")
	eq(o.prompt_key, "problem:p1", "it is on the problem")
	it.cands = [_cand("p1", "Fix the leak", false, "needs 1 scrap")]
	await _draw_once(main)
	eq(o.prompt_text, "E  Fix the leak: needs 1 scrap", "the reason follows the words")
	check(not o.prompt_ok and o.drew_prompt, "the dim one, still drawn")
	check(o.prompt_rect.size.y > 30.0, "with the reason on a line of its own: %s" % str(o.prompt_rect))
	# the fix in hand: E is for it even with a person as near
	it.cands = [{"kind": "person", "id": "dez", "label": "Talk to Dez", "pos": SPOT + Vector2(1.0, 0.0), "dist": 1.0, "ok": true, "why": ""}, _cand("p1", "Fix the leak")]
	main.sim.problems.fixing = {"id": "p1", "left": 4.0}
	await _draw_once(main)
	eq(o.prompt_key, "problem:p1", "the fix being done keeps the prompt, a person as near does not take it")
	await TutorialKit.leave(main)


func test_the_fix_ring_fills_as_the_work_goes() -> void:
	var main := _game()
	var o = main.overlay
	var pm = main.sim.problems
	pm.list = [_mark("p1", "leak", SPOT + Vector2(-2, -2), "Leak: 11 h left")]
	pm.fixing = {}
	await _draw_once(main)
	check(not o.drew_fix_ring, "hands free: no ring")
	pm.fixing = {"id": "p1", "left": 8.0}
	await _draw_once(main)
	check(o.drew_fix_ring, "hands at it: the ring")
	near(o.fix_progress, 0.0, 0.01, "just begun")
	pm.fixing = {"id": "p1", "left": 2.0}
	await _draw_once(main)
	near(o.fix_progress, 0.75, 0.01, "three quarters of the way")
	eq(String(_tag_of(main, "fix", "p1").get("text", "")), "Fixing 2s", "with the seconds that are left")
	pm.fixing = {"id": "p1", "left": 2.0, "total": 10.0}
	await _draw_once(main)
	near(o.fix_progress, 0.8, 0.01, "the rules' own total, when they say it")
	pm.fixing = {}
	await _draw_once(main)
	check(not o.drew_fix_ring, "done: the ring goes")
	await TutorialKit.leave(main)


func test_a_stations_label_shows_near_the_avatar_and_far_only_with_the_base_page() -> void:
	var main := _game(3)
	var o = main.overlay
	main.sim.briefing.places = [
		{"id": "bench", "name": "Workshop", "pos": SPOT + Vector2(6, 0), "ok": false, "bottleneck": "waiting on scrap", "line": "Workshop: waiting on scrap"},
		{"id": "garden", "name": "Garden", "pos": SPOT + Vector2(-12.5, 0), "ok": false, "bottleneck": "nobody tending", "line": "Garden: nobody tending"},
		{"id": "radio", "name": "Radio desk", "pos": SPOT + Vector2(-6, 2), "ok": true, "bottleneck": "", "line": "Radio desk: ok"},
	]
	await _draw_once(main)
	eq(o.drawn_facility_labels, 1, "only the one that waits and is within 12 tiles")
	eq(String(_tag_of(main, "facility", "bench").get("text", "")), "Workshop: waiting on scrap", "the rules' own line")
	check(_tag_of(main, "facility", "garden").is_empty(), "the far one is not")
	check(_tag_of(main, "facility", "radio").is_empty(), "nor the one that works")
	# the Base page open: every one that waits, wherever it is (on the window)
	# (the panel says which page is up: the test puts it on the Base page without building the page, which is BASE-VIEW's and has its own tests)
	main.hud.radio_panel._page = "base"
	main.hud.radio_panel.visible = true
	await _draw_once(main)
	eq(main.hud.radio_page(), "base", "the Base page is up")
	eq(o.drawn_facility_labels, 2, "with the Base page up the far one shows too")
	check(not _tag_of(main, "facility", "garden").is_empty(), "the garden's label")
	main.hud.radio_panel.visible = false
	main.hud.radio_panel._page = ""
	await TutorialKit.leave(main)


# ---------------------------------------------------------------- the list --

func _list(main: Node) -> Control:
	var l := ProblemList.new()
	main.hud.add_child(l)
	l.setup(main.hud, func(): return main.sim)
	l.size = Vector2(420, 400)
	return l


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button and node.visible:
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _words(node: Node) -> String:
	var out: Array = []
	_collect(node, out)
	return " | ".join(out)


func _collect(node: Node, out: Array) -> void:
	if node is Control and not node.visible:
		return
	if (node is Label or node is Button) and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_collect(c, out)


func test_the_trouble_list_has_a_row_for_each_problem_and_ask_goes_to_the_radio() -> void:
	var main := _game()
	var pm = main.sim.problems
	var dez = _person(main, "dez")
	pm.list = [_mark("p1", "leak", SPOT + Vector2(-3, 0), "Leak: 11 h left", 1, 0.4), _mark("p2", "quarrel", SPOT + Vector2(3, 0), "Quarrel: 20 h left", 2, 0.6)]
	pm.best = dez
	var l := _list(main)
	l.refresh()
	await TutorialKit.settle()
	eq(l.rows.size(), 2, "a row for each open problem")
	check(not l.empty_label.visible, "so no 'no trouble' line")
	var words := _words(l)
	check(words.contains("Leak: 11 h left") and words.contains("Quarrel: 20 h left"), "the rules' words on the rows: %s" % words)
	eq(l.rows["p1"].ask.text, "Ask Dez to fix it (72%)", "the Ask names the person the rules would send and their chance")
	check(l.rows["p2"].apart.visible and not l.rows["p1"].apart.visible, "Keep them apart is a quarrel's alone")
	check(l.rows["p1"].glyph.color == BaseMarks.AMBER and l.rows["p2"].glyph.color == BaseMarks.RED, "the colours of the stages")
	# Ask reaches the radio (and through it the problems module), with the person
	l.rows["p1"].ask.pressed.emit()
	eq(pm.asked.size(), 1, "one request")
	eq(pm.asked[0], {"id": "p1", "who": "dez", "insist": false}, "for this problem, to Dez")
	check(l.rows["p1"].answer_row.visible, "the answer is under the row")
	eq(l.rows["p1"].answer.text, "Dez: On it", "in the person's words")
	check(not l.rows["p1"].insist.visible, "nothing to insist on")
	# a soft refusal: the rules' own words, amber, and Insist
	pm.reply = {"ok": false, "line": "", "why": "Dez: tending a patient, can't go", "hard": false, "tone": "refused", "insisted": false}
	l.rows["p1"].ask.pressed.emit()
	eq(l.rows["p1"].answer.text, "Dez: tending a patient, can't go", "the refusal is the sim's, letter for letter")
	eq(l.rows["p1"].answer.get_theme_color("font_color"), main.hud.WARN, "in amber")
	check(l.rows["p1"].insist.visible, "a soft one can be insisted on")
	l.rows["p1"].insist.pressed.emit()
	eq(pm.asked[pm.asked.size() - 1], {"id": "p1", "who": "dez", "insist": true}, "Insist asks again, pushing")
	# a hard refusal: no Insist
	pm.reply = {"ok": false, "line": "", "why": "Dez is down", "hard": true, "tone": "refused", "insisted": false}
	l.ask("p1", dez)
	eq(l.rows["p1"].answer.text, "Dez is down", "a hard refusal's words")
	check(not l.rows["p1"].insist.visible, "and no Insist")
	# the people to choose from, each with willing or their reason; a hard one is off with its reason as the tooltip
	var ana = _person(main, "ana")
	pm.will = {"ana": {"ok": false, "why": "Ana: tending a patient, can't go", "hard": false, "chance": 0.0}, "marcus": {"ok": false, "why": "Marcus is down", "hard": true, "chance": 0.0}}
	l.rows["p1"].more.pressed.emit()
	await TutorialKit.settle()
	var chips: Array = _buttons(l.rows["p1"].chips)
	check(chips.size() >= 3, "a chip for each person at the base: %d" % chips.size())
	var by_name := {}
	for b in chips:
		by_name[String(b.text).get_slice(":", 0).get_slice("  ", 0)] = b
	check(String(by_name["Ana"].text).contains("tending a patient"), "a refusal on its chip: %s" % by_name["Ana"].text)
	check(not by_name["Ana"].disabled, "a soft one can be asked")
	check(by_name["Marcus"].disabled and by_name["Marcus"].tooltip_text == "Marcus is down", "a hard one is off, and says why")
	check(String(by_name["Dez"].text).contains("72%"), "a willing one has its chance: %s" % by_name["Dez"].text)
	# Keep them apart reaches the rules; Go there reaches main.focus_problem through the HUD
	l.rows["p2"].apart.pressed.emit()
	eq(pm.separated, ["p2"], "the quarrel's two are kept apart by the rules")
	eq(l.rows["p2"].answer.text, "Kept apart: Dez works at the garden now", "the rules' line")
	l.rows["p1"].go.pressed.emit()
	eq(main.cam_glide_to, pm.list[0].at, "the camera is on its way to the marker")
	# the problem is gone: so is its row
	pm.list = [pm.list[1]]
	l.refresh()
	eq(l.rows.keys(), ["p2"], "the row of a problem that is gone goes")
	pm.list = []
	l.refresh()
	check(l.empty_label.visible and l.rows.is_empty(), "no trouble: the line that says so")
	# every control that is off says why
	pm.list = [_mark("p1", "leak", SPOT, "Leak: 11 h left")]
	pm.best = null
	l.refresh()
	check(l.rows["p1"].ask.disabled and l.rows["p1"].ask.tooltip_text != "", "nobody free: Ask is off with its reason")
	for b in _buttons(l):
		check(not b.disabled or b.tooltip_text != "", "a disabled control has a tooltip: %s" % b.text)
	await TutorialKit.leave(main)


# ------------------------------------------------------------------ events --

func test_a_new_problem_is_a_toast_and_an_alert_that_glides_the_camera_and_the_events_make_sound() -> void:
	var main := _game()
	var sim = main.sim
	sim.problems.list = [_mark("p1", "leak", SPOT + Vector2(-9, -4), "Leak: 18 h left")]
	sim.events.append({"type": "problem", "state": "raised", "id": "p1", "kind": "leak"})
	sim.events.append({"type": "fix_work", "on": true, "id": "p1"})
	main._handle_events()
	check(sim.alerts.has("trouble-p1"), "an alert for it")
	eq(String(sim.alerts["trouble-p1"].text), "Trouble: the leak", "in the words of the problem")
	eq(sim.alerts["trouble-p1"].at, SPOT + Vector2(-9, -4), "at its place")
	main._on_alert("trouble-p1")
	eq(main.cam_glide_to, SPOT + Vector2(-9, -4), "a click on the alert glides the camera there")
	check(main.focus_problem("p1"), "focus_problem finds an open problem")
	check(not main.focus_problem("nope"), "and says no to one that is not")
	for state in ["stage2", "fixed", "failed", "escalated"]:
		sim.events.append({"type": "problem", "state": state, "id": "p1", "kind": "jam"})
	main._handle_events()
	eq(sim.events.size(), 0, "every event is taken")
	await TutorialKit.leave(main)


# ------------------------------------------------------- the real modules --

func _press(main: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	main._unhandled_input(ev)


func test_against_the_real_rules_a_leak_is_marked_prompted_fixed_by_hand_listed_and_asked() -> void:
	var main := _game(3, false)
	var sim = main.sim
	check(main.stage_problem("leak"), "the rules raise a leak (the --problem=leak staging)")
	await _draw_once(main)
	var o = main.overlay
	var mark: Dictionary = sim.problems.marks()[0]
	var id := String(mark.id)
	check(o.drew_problem_marks and o.drawn_problem_labels == 1, "the marker is drawn")
	eq(String(_tag_of(main, "problem", id).get("text", "")), String(mark.label), "in the rules' own words")
	eq(o.prompt_text, "E  Fix the leak", "the prompt is on it, as the rules word it")
	# E starts the avatar's own hands: the ring fills
	_press(main, KEY_E)
	check(not sim.problems.fixing.is_empty(), "E starts the fix")
	await _draw_once(main)
	check(o.drew_fix_ring, "the ring is drawn round the body")
	for i in 20:
		main._process(DT)
	await _draw_once(main)
	check(o.fix_progress > 0.0 and o.fix_progress < 1.0, "and it fills as the work goes: %f" % o.fix_progress)
	_press(main, KEY_E)    # (E again leaves it)
	check(sim.problems.fixing.is_empty(), "E again stops the hands")
	# the list on the real module: the Ask is the rules' own
	var l := _list(main)
	l.refresh()
	eq(l.rows.keys(), [id], "a row for the problem")
	var best = sim.problems.best_for(id)
	check(best != null, "someone would be sent")
	var said: Dictionary = sim.radio.fix_willingness(best, id)
	check(String(l.rows[id].ask.text).begins_with("Ask %s" % String(best.first)), "the Ask names them: %s" % l.rows[id].ask.text)
	l.rows[id].ask.pressed.emit()
	eq(bool(l.answers[id].ok), bool(said.ok), "the answer is the rules' answer, not the view's")
	check(l.rows[id].answer_row.visible and String(l.rows[id].answer.text) != "", "and it is under the row")
	await TutorialKit.leave(main)
