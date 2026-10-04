extends "res://tests/case.gd"
## Round 22, GATE-VIEW: what the screen says of the gate you can work with your own hands (docs: README "The gate"; the rules are
## scripts/sim/gate.gd, tests/test_gate_rules.gd). In avatar mode the leaves follow the rules' own `sim.gate.open` (not the vehicles' demand),
## a steel lever with a lamp stands at the control spot (green open, red shut, amber on the move), E at it has its prompt, its refusal in
## amber and its toast, the gateway and the lever are outlined faintly when you are near or the gate is held open at dusk, and the gateway's
## ring pulses when it is open in the dark; the clock has a lamp and a word ("Gate: open") with a tooltip; the gate's sounds are the rules'
## events, once each; the News has a Gate kind; and a tip says what the lever is for at the first dusk. With no avatar (the classic game, a
## test's, Orientation Day) the vehicles' demand rules the leaves as ever.
## The rules are not these tests' business: the gate's module is a stand-in (`FakeGate`, left in the sim's meta "gate_stub", which
## `GateKit.gate_of` honours) that says what each test wants it to, so this file does not depend on the module landing.

const Helpers := preload("res://tests/helpers.gd")
const Kit := preload("res://tests/hud_kit.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const TextTests := preload("res://tests/test_hud_text.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const GateNode := preload("res://scripts/render/gate_node.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")
const GateKit := preload("res://scripts/ui/gate_kit.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Hints := preload("res://scripts/ui/hints.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Coach := preload("res://scripts/ui/coach.gd")

const DT := 1.0 / 30.0
const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]
## The camera on the avatar's arena, and where the stand-in gate is (in the arena, so that the whole picture is in the window).
const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0
const ARENA := Rect2i(34, 26, 20, 12)
const LEVER := Vector2(44.0, 30.5)
const GATEWAY := Rect2(40.0, 27.0, 6.0, 2.5)


## The gate's module as the views meet it (scripts/sim/gate.gd's contract): `open` the real state, `held`, `active()` (avatar mode), the control
## spot, the gateway, who is in it, `request` (what E does: the rules' answer, with its line or its reason, and the event) and `step` (the
## leaves move OPEN_S seconds from one end to the other, and each end is told).
class FakeGate:
	extends RefCounted
	const OPEN_S := 0.8
	var sim
	var on := true
	var open := 0.0
	var target := 0.0
	var held := ""
	## Whether `state()` says which way the leaves go (a module that does not leaves the views to guess from where `open` was).
	var says := true
	var spot := LEVER
	var way := GATEWAY
	var blockers: Array = []
	var asked: Array = []

	func active() -> bool:
		return on

	func is_passable() -> bool:
		return open >= 0.999

	func control_spot() -> Vector2:
		return spot

	func gateway() -> Rect2:
		return way

	func who_blocks() -> Array:
		return blockers

	func demand(_reason: String, _who: String = "") -> bool:
		return is_passable()

	func update(_dt: float) -> void:
		pass

	func state() -> String:
		if not says:
			return ""
		if open <= 0.0 and target <= 0.0:
			return "shut"
		if open >= 1.0 and target >= 1.0:
			return "open"
		return "opening" if target > open else "closing"

	func request(want_open: bool, who: String = "player") -> Dictionary:
		asked.append([want_open, who])
		if not want_open and not blockers.is_empty():
			return {"ok": false, "why": "%s is in the gateway" % String(blockers[0]), "line": ""}
		target = 1.0 if want_open else 0.0
		held = "open" if want_open else ""
		if sim != null:
			sim.events.append({"type": "gate", "state": "opening" if want_open else "closing", "by": who})
		var dark: bool = sim != null and sim.is_night()
		if want_open:
			return {"ok": true, "why": "", "line": "Opening the gate: the dead can walk in." if dark else "Opening the gate.", "warn": dark, "open": true}
		return {"ok": true, "why": "", "line": "Shutting the gate.", "warn": false, "open": false}

	func step(dt: float) -> void:
		var before := open
		open = move_toward(open, target, dt / OPEN_S)
		if sim != null and not is_equal_approx(before, open) and is_equal_approx(open, target):
			sim.events.append({"type": "gate", "state": "open" if target >= 1.0 else "shut", "by": "player"})


## The interact module as the views meet it: the candidates are whatever a test sets, and `use` on the gate asks the gate's rules.
class FakeInteract:
	extends RefCounted
	const BENCH_SECONDS := 12.0
	const TALK_LEAVE := 3.5
	var sim
	var gate
	var cands: Array = []
	var posted := ""
	var working := ""
	var work_left := 0.0
	var used: Array = []
	## Whether the gate's answer has no line (the views then say it themselves).
	var quiet := false

	func candidates() -> Array:
		return cands

	func best() -> Dictionary:
		return cands[0] if not cands.is_empty() else {}

	func use(cand: Dictionary = {}) -> Dictionary:
		var c := cand if not cand.is_empty() else best()
		used.append(c)
		if c.is_empty():
			return {"ok": false, "why": "Nothing here to use"}
		sim.events.append({"type": "interact", "kind": c.kind, "id": c.id, "ok": bool(c.ok)})
		if not bool(c.ok):
			return {"ok": false, "kind": c.kind, "id": c.id, "why": String(c.why)}
		var r: Dictionary = gate.request(String(c.label).begins_with("Open"), "player")
		r["kind"] = "gate"
		r["id"] = c.id
		if quiet:
			r["line"] = ""
		return r


## A sound node that writes down what it is asked to play (and has every sound).
class Recorder:
	extends Node
	var streams := {"car_gate_motor": [1], "car_door_close": [1]}
	var played: Array = []

	func play(sound_name: String, _level: float = 1.0, _pitch_var: float = 0.04, _pitch_scale: float = 1.0) -> void:
		played.append(sound_name)

	func ui(_sound_name: String, _level: float = 1.0, _pitch_var: float = 0.02) -> void:
		pass


## A parking view whose demand is whatever a test says.
class Parking:
	extends "res://scripts/render/parking_node.gd"
	var want := 0.0

	func gate_demand() -> float:
		return want


# ----------------------------------------------------------------- helpers --

## A gate stand-in left in the sim's meta, in avatar mode unless `on` is false.
func _fake(sim, on: bool = true) -> FakeGate:
	var gate := FakeGate.new()
	gate.sim = sim
	gate.on = on
	sim.set_meta("gate_stub", gate)
	return gate


## A bare world and a gate node over it (no avatar): the node of the vehicle view, with the stand-in in the sim.
func _node(g: Dictionary):
	var gate = GateNode.new()
	g.world.add_child(gate)
	gate.setup(g.world, g.sim)
	return gate


## `frames` frames of the view at `dt` (the leaves' time) with the demand as given, the rules' step in each (as main.gd's frame does).
func _run(node, rules, frames: int, dt: float, demand: float = 0.0, scale: float = 1.0) -> void:
	for i in frames:
		for k in int(scale):
			rules.step(dt)
		node.follow(demand, dt * scale)


## The real game (the classic start, six people) in a window of this size with the avatar (Ruth) in the middle of a clear arena, the camera on
## her, nobody working and nothing about, the stand-in interact module and the stand-in gate installed.
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
	var gate := _fake(sim)
	var it := FakeInteract.new()
	it.sim = sim
	it.gate = gate
	sim.set_meta("interact_stub", it)
	var me = sim.avatar.player()
	_stand(main, me, SPOT)
	main.cam_center = SPOT
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	return main


func _stand(main: Node, p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.goal_key = ""
	p.order = null
	main._sync_views()


func _gate_of(main: Node) -> FakeGate:
	return main.sim.get_meta("gate_stub")


func _it_of(main: Node) -> FakeInteract:
	return main.sim.get_meta("interact_stub")


func _frames(main: Node, n: int, dt: float = DT) -> void:
	for i in n:
		main._process(dt)


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


func _cand(label: String, dist: float, ok: bool = true, why: String = "", pos: Vector2 = LEVER) -> Dictionary:
	return {"kind": "gate", "id": "gate", "label": label, "pos": pos, "dist": dist, "ok": ok, "why": why}


func _free(main: Node) -> void:
	await TutorialKit.leave(main)


## A HUD over a quiet game in avatar mode with the gate stand-in, the HUD having seen it once.
func _ctx(width: int = 1280, height: int = 800, player: String = "ruth") -> Dictionary:
	var ctx := Kit.build(width, height)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	if player != "":
		check(sim.avatar.set_player(player), "%s is the player" % player)
	ctx["gate"] = _fake(sim, player != "")    # (the rules are in charge in avatar mode only)
	Kit.update(ctx)
	return ctx


func _texts_of(node: Node) -> String:
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


# ------------------------------------------------------------------ the kit --

func test_the_states_of_the_leaves_have_their_names_and_lamps() -> void:
	eq(GateKit.state_of(0.0), "shut", "0 is shut")
	eq(GateKit.state_of(1.0), "open", "1 is open")
	eq(GateKit.state_of(0.4, 1), "opening", "on the way out")
	eq(GateKit.state_of(0.4, -1), "closing", "on the way back")
	eq(GateKit.state_of(0.7), "opening", "between the ends and no word of which way: the nearer end is where it goes")
	eq(GateKit.state_of(0.2), "closing", "the other way")
	eq(GateKit.lamp_color("shut"), GateKit.LAMP_SHUT, "a shut gate has the red lamp")
	eq(GateKit.lamp_color("open"), GateKit.LAMP_OPEN, "an open gate the green one")
	eq(GateKit.lamp_color("opening"), GateKit.LAMP_MOVING, "one on the move the amber one")
	eq(GateKit.lamp_color("closing"), GateKit.LAMP_MOVING, "both ways")
	check(GateKit.LAMP_OPEN != GateKit.LAMP_SHUT and GateKit.LAMP_OPEN != GateKit.LAMP_MOVING and GateKit.LAMP_SHUT != GateKit.LAMP_MOVING, "three colours")


func test_the_status_says_what_the_hud_shows() -> void:
	var g := Helpers.avatar_game(5, 5)
	var sim = g.sim
	var gate := _fake(sim)
	var st := GateKit.status(sim)
	eq(st.on, true, "on with the rules in charge")
	eq(st.text, "Gate: shut", "shut")
	eq(st.lamp, GateKit.LAMP_SHUT, "red")
	gate.open = 1.0
	eq(GateKit.status(sim).text, "Gate: open", "open")
	eq(GateKit.status(sim).lamp, GateKit.LAMP_OPEN, "green")
	gate.held = "open"
	eq(GateKit.status(sim).text, "Gate: held open", "held open")
	gate.open = 0.0
	gate.held = "shut"
	eq(GateKit.status(sim).text, "Gate: held shut", "held shut")
	gate.held = ""
	gate.open = 0.5
	gate.target = 1.0
	eq(GateKit.status(sim).text, "Gate: opening", "opening: the rules say which way it goes")
	eq(GateKit.status(sim, -1).text, "Gate: opening", "whatever the view's own guess")
	gate.target = 0.0
	eq(GateKit.status(sim).text, "Gate: closing", "closing")
	eq(GateKit.status(sim, 1).text, "Gate: closing", "whatever the view's own guess")
	gate.open = 0.5
	check(bool(GateKit.status(sim, 1, true).dark), "open in the dark is told")
	gate.open = 0.0
	check(not bool(GateKit.status(sim, 0, true).dark), "shut in the dark is not")
	gate.on = false
	eq(GateKit.status(sim).on, false, "off with no avatar")
	eq(GateKit.status(sim).text, "", "and no words")
	g.world.free()


func test_the_names_of_who_is_in_the_way_are_said_plainly() -> void:
	eq(GateKit.blocked_line([]), "", "no one")
	eq(GateKit.blocked_line(["Dez"]), "Dez is in the gateway", "one")
	eq(GateKit.blocked_line(["Dez", "Ana"]), "Dez and Ana are in the gateway", "two")
	eq(GateKit.blocked_line(["Dez", "Ana", "Walt"]), "Dez, Ana and Walt are in the gateway", "three")
	var g := Helpers.avatar_game(5, 5)
	var gate := _fake(g.sim)
	gate.blockers = ["Dez", g.sim.avatar.player()]
	eq(GateKit.blockers_of(gate), ["Dez", "Ruth"], "names as strings, or people")
	g.world.free()


func test_a_game_with_no_gate_module_has_no_gate_views() -> void:
	var g := Helpers.make(5, 1, 6)
	check(not GateKit.is_active(g.sim), "the classic game's gate is the vehicles'")
	eq(GateKit.status(g.sim).on, false, "no indicator")
	eq(GateKit.spot_of(null), Vector2.INF, "no lever without a module")
	eq(GateKit.gateway_of(null), Rect2(), "no gateway")
	g.world.free()


# ---------------------------------------------------------------- the node --

func test_with_no_avatar_the_demand_rules_the_leaves_as_it_always_did() -> void:
	var g := Helpers.make(1, 1)
	var rules := _fake(g.sim, false)
	rules.open = 1.0    # (the stand-in says "open", but its rules are not in charge: no avatar)
	var gate = _node(g)
	check(not gate.ruled(), "the leaves are not ruled by the gate's module")
	check(gate.is_shut(), "shut")
	for i in 4:
		gate.follow(1.0, 0.1)
	near(gate.open, 0.5, 0.0001, "half way after 0.4 seconds, as with the demand alone")
	for i in 7:
		gate.follow(1.0, 0.1)
	check(gate.is_open(), "open after 1.1 seconds")
	for i in 9:
		gate.follow(0.0, 0.1)
	check(gate.is_shut(), "shut again after 0.9 seconds, whatever the module's `open` says")
	check(not gate.lever.visible, "and no lever")
	g.world.free()


func test_with_no_gate_module_at_all_it_is_the_demand_too() -> void:
	var g := Helpers.make(1, 1)
	var gate = _node(g)
	gate.follow(1.0, 2.0)
	check(gate.is_open(), "the demand opens it")
	gate.follow(0.0, 2.0)
	check(gate.is_shut(), "and shuts it")
	check(not gate.ruled(), "no rules in charge")
	g.world.free()


func test_in_avatar_mode_the_leaves_follow_the_rules_open_and_not_the_demand() -> void:
	var g := Helpers.avatar_game(1, 5)
	var rules := _fake(g.sim)
	var gate = _node(g)
	check(gate.ruled(), "the module is in charge")
	gate.follow(1.0, 2.0)
	check(gate.is_shut(), "a car about to pass does not open it by itself: the rules' gate is shut")
	rules.open = 1.0
	gate.follow(0.0, 2.0)
	check(gate.is_open(), "the rules' gate is open: so are the leaves, whatever the demand")
	rules.open = 0.5
	gate.follow(1.0, 0.1)
	near(gate.open, 0.75, 0.0001, "on the way back it eases (a tenth of a second: CHASE over OPEN_TIME of it)")
	gate.follow(1.0, 0.1)
	near(gate.open, 0.5, 0.0001, "and stops where the rules are")
	gate.follow(1.0, 5.0)
	near(gate.open, 0.5, 0.0001, "however long the frame: it does not pass them")
	rules.open = 0.0
	gate.follow(1.0, 5.0)
	check(gate.is_shut(), "shut with the rules")
	g.world.free()


func test_the_leaves_keep_up_with_the_rules_at_every_game_speed() -> void:
	var main_script = load("res://scripts/main.gd")
	for speed in [0, 1, 2, 3]:
		var g := Helpers.avatar_game(1, 5)
		var rules := _fake(g.sim)
		var gate = _node(g)
		var rate: float = main_script.gate_rate(speed)
		var worst := 0.0
		rules.request(true)
		g.sim.events.clear()
		# a game second at a time on the screen is 1/60 s of the rules' own time, times the speed (gate_rate)
		for i in 240:
			rules.step(1.0 / 60.0 * rate)
			gate.follow(0.0, 1.0 / 60.0 * rate)
			worst = maxf(worst, absf(gate.open - rules.open))
		check(worst <= 0.5 / FakeGate.OPEN_S * 1.0 / 60.0 * rate + 0.001, "speed %d: the leaves are never more than a frame behind (%.3f)" % [speed, worst])
		near(gate.open, 1.0, 0.0001, "speed %d: and open when the rules are" % speed)
		rules.request(false)
		for i in 240:
			rules.step(1.0 / 60.0 * rate)
			gate.follow(0.0, 1.0 / 60.0 * rate)
		near(gate.open, 0.0, 0.0001, "speed %d: shut again with them" % speed)
		g.world.free()


func test_the_leaves_take_up_the_rules_leisurely_from_the_first_frame_of_a_load() -> void:
	# a gate that is already open when the view is made (a loaded game) is not shut by the leaves' own start: they ease to the rules' state
	var g := Helpers.avatar_game(1, 5)
	var rules := _fake(g.sim)
	rules.open = 1.0
	var gate = _node(g)
	check(gate.is_shut(), "the picture begins shut")
	gate.follow(0.0, 0.016)
	check(gate.open > 0.0, "and starts to open on the first frame")
	gate.follow(0.0, 1.0)
	check(gate.is_open(), "and stands open")
	g.world.free()


func test_a_screenshots_staged_gate_stays_where_it_was_put() -> void:
	var g := Helpers.avatar_game(1, 5)
	var rules := _fake(g.sim)
	var gate = _node(g)
	gate.stage_open(1.0)
	rules.open = 0.0
	gate.follow(0.0, 5.0)
	check(gate.is_open(), "staged open stays open (--gate-open=)")
	gate.snap(0.0)
	check(gate.is_shut(), "a snap puts the leaves there")
	rules.open = 1.0
	gate.follow(0.0, 5.0)
	check(gate.is_open(), "and they go on following the rules")
	g.world.free()


# --------------------------------------------------------------- the lever --

func test_the_lever_stands_at_the_control_spot_in_avatar_mode_only() -> void:
	var g := Helpers.avatar_game(1, 5)
	var rules := _fake(g.sim, false)
	rules.spot = Vector2(35.5, 21.5)
	var gate = _node(g)
	gate.follow(0.0, 0.1)
	check(not gate.lever.visible, "no lever while the rules are not in charge")
	eq(gate.lamp_state(), "", "and no lamp")
	rules.on = true
	gate.follow(0.0, 0.1)
	check(gate.lever.visible, "there is one in avatar mode")
	eq(gate.lever.position, Vector2(35.5, 21.5) * GateNode.TILE, "at the control spot")
	check(gate.lever.z_index > 4 and gate.lever.z_index < 6, "over the wall layers (4) and under the people (6): z %d" % gate.lever.z_index)
	rules.spot = Vector2(43.0, 21.0)
	gate.follow(0.0, 0.1)
	eq(gate.lever.position, Vector2(43.0, 21.0) * GateNode.TILE, "it goes where the rules move it")
	g.world.set_segment_state(2, 3)
	gate.follow(0.0, 0.1)
	check(not gate.lever.visible, "the wrecked gate has no lever to pull")
	g.world.set_segment_state(2, 0)
	gate.follow(0.0, 0.1)
	check(gate.lever.visible, "a gate mended has it again")
	g.world.free()


func test_the_lamp_is_red_shut_green_open_and_amber_on_the_move() -> void:
	var g := Helpers.avatar_game(1, 5)
	var rules := _fake(g.sim)
	var gate = _node(g)
	gate.follow(0.0, 0.1)
	eq(gate.lamp_state(), "shut", "shut")
	eq(gate.lever.lamp_color(), GateKit.LAMP_SHUT, "red")
	rules.request(true)
	for i in 4:
		rules.step(0.1)
		gate.follow(0.0, 0.1)
	eq(gate.lamp_state(), "opening", "opening while the leaves go out")
	eq(gate.lever.lamp_color(), GateKit.LAMP_MOVING, "amber (on the lit beat of its blink)")
	for i in 20:
		rules.step(0.1)
		gate.follow(0.0, 0.1)
	eq(gate.lamp_state(), "open", "open")
	eq(gate.lever.lamp_color(), GateKit.LAMP_OPEN, "green")
	rules.request(false)
	for i in 3:
		rules.step(0.1)
		gate.follow(0.0, 0.1)
	eq(gate.lamp_state(), "closing", "closing on the way back")
	for i in 20:
		rules.step(0.1)
		gate.follow(0.0, 0.1)
	eq(gate.lamp_state(), "shut", "shut again")
	eq(gate.lever.lamp_color(), GateKit.LAMP_SHUT, "red again")
	rules.held = "open"
	gate.follow(0.0, 0.1)
	eq(gate.lever.held, "open", "a held gate's lever knows it (a pin across its slot)")
	g.world.free()


func test_the_lamp_follows_the_leaves_not_the_rules() -> void:
	# the lamp never says what the leaves do not: the rules say open at once, the leaves are still on their way
	var g := Helpers.avatar_game(1, 5)
	var rules := _fake(g.sim)
	var gate = _node(g)
	rules.open = 1.0
	gate.follow(0.0, 0.1)
	check(gate.open > 0.0 and gate.open < 1.0, "the leaves are on the move")
	eq(gate.lamp_state(), "opening", "and the lamp is amber, not green")
	gate.follow(0.0, 2.0)
	eq(gate.lamp_state(), "open", "green when they have stopped")
	g.world.free()


func test_the_lever_is_drawn_and_drawn_again_when_its_state_changes() -> void:
	var g := Helpers.avatar_game(1, 5)
	var rules := _fake(g.sim)
	var gate = _node(g)
	gate.follow(0.0, 0.1)
	await TutorialKit.settle()
	var first: int = gate.lever.draws
	check(first >= 1, "drawn once it is shown (%d)" % first)
	await TutorialKit.settle()
	eq(gate.lever.draws, first, "and not again while nothing changes")
	for state in [[1.0, ""], [1.0, "open"], [0.0, "shut"]]:
		var before: int = gate.lever.draws
		rules.open = state[0]
		rules.held = state[1]
		gate.follow(0.0, 3.0)
		await TutorialKit.settle()
		check(gate.lever.draws > before, "drawn again at %s %s" % [str(state[0]), str(state[1])])
	g.world.free()


# ---------------------------------------------------------------- the prompt --

func test_the_gate_prompt_says_open_or_shut_and_is_ringed_at_the_lever() -> void:
	var main := _game()
	var o = main.overlay
	_it_of(main).cands = [_cand("Open the gate", 1.5)]
	await _draw_once(main)
	check(o.drew_prompt, "the pill is drawn")
	eq(o.prompt_text, "E  Open the gate", "it says the key and what it does")
	check(o.prompt_ok, "the gate may be used")
	eq(o.prompt_key, "gate:gate", "it is on the gate")
	check(Rect2(Vector2.ZERO, main._vp()).encloses(o.prompt_rect), "inside the window: %s" % str(o.prompt_rect))
	var lever_px: Vector2 = main._tile_to_screen(LEVER)
	check(o.prompt_rect.position.distance_to(lever_px) < 260.0, "beside the lever: %s %s" % [str(o.prompt_rect), str(lever_px)])
	check(o._spot_of(_cand("Open the gate", 1.5)).distance_to(lever_px) < 0.01, "the ring is on the lever")
	check(o._spot_of(_cand("Open the gate", 1.5, true, "", Vector2.ZERO)).distance_to(lever_px) < 0.01, "and when the candidate has no place the rules' control spot is it")
	_it_of(main).cands = [_cand("Shut the gate", 1.5)]
	await _draw_once(main)
	eq(o.prompt_text, "E  Shut the gate", "and the other way")
	await _free(main)


func test_a_refusal_at_the_lever_is_dim_with_its_reason() -> void:
	var main := _game()
	_it_of(main).cands = [_cand("Shut the gate", 1.5, false, "Dez is in the gateway")]
	await _draw_once(main)
	var o = main.overlay
	eq(o.prompt_text, "E  Shut the gate: Dez is in the gateway", "the reason follows the words")
	check(not o.prompt_ok, "it is the dim one")
	check(o.drew_prompt, "and still drawn")
	check(o.prompt_rect.size.y > 30.0, "with the reason on a line of its own: %s" % str(o.prompt_rect))
	await _free(main)


func test_e_at_the_lever_toasts_what_it_does_and_the_refusal_in_amber() -> void:
	var main := _game()
	var gate := _gate_of(main)
	var h = main.hud
	_it_of(main).cands = [_cand("Open the gate", 1.5)]
	_frames(main, 3)
	_press(main, KEY_E)
	eq(gate.asked, [[true, "player"]], "E asked the gate's rules to open it")
	eq(h.toast_label.text, "Opening the gate.", "the rules' line is the toast")
	eq(h.toast_col, h.INFO, "plain by day")
	Helpers.at(main.sim, 2, 22.0)
	gate.held = ""
	_it_of(main).cands = [_cand("Open the gate", 1.5)]
	_frames(main, 3)
	_press(main, KEY_E)
	eq(h.toast_label.text, "Opening the gate: the dead can walk in.", "in the dark it says what it lets in")
	eq(h.toast_col, h.WARN, "in amber")
	gate.blockers = ["Dez"]
	_it_of(main).cands = [_cand("Shut the gate", 1.5, false, "Dez is in the gateway")]
	_frames(main, 3)
	_press(main, KEY_E)
	eq(h.toast_label.text, "Dez is in the gateway", "a refusal says why")
	eq(h.toast_col, h.WARN, "in amber")
	await _free(main)


func test_a_gate_whose_rules_give_no_line_is_still_told() -> void:
	var main := _game()
	var h = main.hud
	_it_of(main).quiet = true
	_it_of(main).cands = [_cand("Open the gate", 1.5)]
	_frames(main, 3)
	_press(main, KEY_E)
	eq(h.toast_label.text, "Opening the gate", "said as the prompt said it")
	_it_of(main).cands = [_cand("Shut the gate", 1.5)]
	_frames(main, 3)
	_press(main, KEY_E)
	eq(h.toast_label.text, "Shutting the gate", "and the other way")
	await _free(main)


# ------------------------------------------------------------------- the sounds --

## The gate's sounds are the soundscape's now (scripts/audio/soundscape.gd `gate_event`, from the rules' event): a lever as the leaves begin to move and a slide
## a third of a second after, a clang as they come to rest. What it is playing from the gate's voices, by file.
func _gate_voices(scape: Node) -> Array:
	var out: Array = []
	for v in scape.voices:
		if v.kind == "gate" and v.p.playing and v.p.stream != null:
			out.append(String(v.p.stream.resource_path).get_file().get_basename())
	out.sort()
	return out


func test_the_gates_sounds_are_the_rules_events_once_each() -> void:
	var main := _game()
	var scape = main.sound.scape
	var sim = main.sim
	sim.events.clear()
	var base := int(scape.played.get("gate", 0))
	sim.events.append({"type": "gate", "state": "opening", "by": "player"})
	_frames(main, 1)
	eq(int(scape.played.get("gate", 0)) - base, 1, "the lever as the leaves begin to move")
	eq(_gate_voices(scape), ["gate_lever_0"], "which is the lever's")
	_frames(main, 3)
	eq(int(scape.played.get("gate", 0)) - base, 1, "and not again on the frames after (the event is handled once)")
	scape.update(0.4)
	eq(int(scape.played.get("gate", 0)) - base, 2, "the slide follows it")
	eq(_gate_voices(scape), ["gate_lever_0", "gate_slide_0"], "the lever's and the slide's")
	for v in scape.voices:
		v.p.stop()
	sim.events.append({"type": "gate", "state": "open", "by": "player"})
	_frames(main, 1)
	eq(int(scape.played.get("gate", 0)) - base, 3, "a clang as they come to rest open")
	eq(_gate_voices(scape), ["gate_clang_0"], "which is the clang's")
	for v in scape.voices:
		v.p.stop()
	sim.events.append({"type": "gate", "state": "closing", "by": "player"})
	_frames(main, 1)
	scape.update(0.4)
	eq(int(scape.played.get("gate", 0)) - base, 5, "the lever and the slide again as they begin to close")
	for v in scape.voices:
		v.p.stop()
	sim.events.append({"type": "gate", "state": "shut", "by": "player"})
	_frames(main, 1)
	eq(int(scape.played.get("gate", 0)) - base, 6, "a clang as they meet")
	eq(_gate_voices(scape), ["gate_clang_0"], "and it is the clang's")
	await _free(main)


func test_the_demands_own_motor_is_silent_while_the_rules_are_in_charge() -> void:
	var g := Helpers.avatar_game(1, 5)
	var rules := _fake(g.sim)
	var node = _node(g)
	var parking := Parking.new()
	g.world.add_child(parking)
	parking.sim = g.sim
	parking.gate = node
	var rec := Recorder.new()
	g.world.add_child(rec)
	parking.sound = rec
	parking._drive_gate(0.1)
	parking.want = 1.0
	parking._drive_gate(0.1)
	eq(rec.played, [], "a car about to pass makes no motor sound of its own in avatar mode")
	rules.on = false
	parking.want = 0.0
	parking._drive_gate(0.1)
	parking.want = 1.0
	parking._drive_gate(0.1)
	eq(rec.played, ["car_gate_motor"], "and without the avatar it does, as it always did")
	g.world.free()


func test_the_keeper_at_the_bell_and_a_gate_that_cannot_shut_have_a_banner_and_the_players_own_do_not() -> void:
	var main := _game()
	var h = main.hud
	var sim = main.sim
	h.banner_title.text = ""
	sim.events.append({"type": "gate", "state": "closing", "by": "player"})
	sim.events.append({"type": "gate", "state": "shut", "by": "player"})
	_frames(main, 1)
	eq(h.banner_title.text, "", "no banner for what the player did")
	sim.events.append({"type": "gate", "state": "shut", "by": "auto"})
	_frames(main, 1)
	eq(h.banner_title.text, "", "nor for the keeper's work for a car")
	sim.events.append({"type": "gate", "state": "closing", "by": "dusk"})
	_frames(main, 1)
	eq(h.banner_title.text, "", "nor while it is still closing")
	sim.events.append({"type": "gate", "state": "shut", "by": "dusk"})
	_frames(main, 1)
	eq(h.banner_title.text, "THE GATE IS SHUT", "the keeper shut it at the bell")
	eq(h.banner_sub.text, "The gate keeper shut it for the night", "for the night")
	h.banner_title.text = ""
	sim.radio.alarm_on = true
	sim.events.append({"type": "gate", "state": "shut", "by": "dusk"})
	_frames(main, 1)
	eq(h.banner_sub.text, "Call to arms: the gate keeper shut it", "or at the call to arms")
	sim.radio.alarm_on = false
	h.banner_title.text = ""
	sim.radio.log_news("gate", "The gate shuts for the night")
	_frames(main, 2)
	eq(h.banner_title.text, "", "the News' line of the shutting is not a second banner")
	sim.radio.log_news("gate", "The gate cannot shut yet", "Dez is in the gateway")
	_frames(main, 2)
	eq(h.banner_title.text, "THE GATE CANNOT SHUT YET", "a gate that cannot shut says so")
	eq(h.banner_sub.text, "Dez is in the gateway", "and who is in the way")
	h.banner_title.text = ""
	_frames(main, 5)
	eq(h.banner_title.text, "", "once")
	await _free(main)


# ----------------------------------------------------------------- the marks --

func test_near_the_lever_the_gateway_and_the_lever_are_outlined_faintly() -> void:
	var main := _game()
	var o = main.overlay
	var me = main.sim.avatar.player()
	Helpers.at(main.sim, 2, 12.0)
	_stand(main, me, LEVER + Vector2(-2.0, 0.5))
	await _draw_once(main)
	check(o.drew_gate_outline, "the gateway is outlined")
	check(o.drew_gate_spot, "and the lever ringed")
	check(not o.drew_gate_pulse, "no alarm by day")
	eq(o.gate_tag, "", "no words")
	check(o.gate_box.size.x > 100.0 and Rect2(Vector2.ZERO, main._vp()).intersects(o.gate_box), "in the window: %s" % str(o.gate_box))
	_stand(main, me, LEVER + Vector2(-2.0, 7.5))
	await _draw_once(main)
	check(not o.drew_gate_outline and not o.drew_gate_spot and not o.drew_gate_pulse, "farther than %d tiles from the lever: nothing" % int(OverlayNode.GATE_NEAR))
	await _free(main)


func test_a_gate_held_open_as_the_day_ends_is_outlined_in_gold_with_its_words_wherever_you_are() -> void:
	var main := _game()
	var o = main.overlay
	var gate := _gate_of(main)
	var me = main.sim.avatar.player()
	_stand(main, me, LEVER + Vector2(-2.0, 7.5))
	gate.open = 1.0
	gate.held = "open"
	Helpers.at(main.sim, 2, 12.0)
	await _draw_once(main)
	check(not o.drew_gate_outline and not o.drew_gate_pulse, "held open at noon, and far: nothing")
	Helpers.at(main.sim, 2, 18.3)
	await _draw_once(main)
	check(o.drew_gate_outline, "held open in the last hour before the bell: outlined")
	eq(o.gate_tag, "held open", "with its words")
	check(not o.drew_gate_pulse, "the bell has not rung: no alarm yet")
	gate.held = ""
	await _draw_once(main)
	check(not o.drew_gate_outline, "open but not held, and far: nothing (the keeper will see to it)")
	await _free(main)


func test_the_gates_words_keep_clear_of_the_prompt() -> void:
	var main := _game()
	var o = main.overlay
	var gate := _gate_of(main)
	var me = main.sim.avatar.player()
	gate.open = 1.0
	gate.held = "open"
	Helpers.at(main.sim, 2, 18.3)
	# the avatar stands just under the box, the prompt beside the lever (so the box's foot is where the pill would be)
	for lever in [LEVER, Vector2(43.0, 29.8), Vector2(41.5, 30.0)]:
		gate.spot = lever
		_stand(main, me, lever + Vector2(-1.2, 0.3))
		_it_of(main).cands = [_cand("Shut the gate", 1.2, true, "", lever)]
		await _draw_once(main)
		check(o.drew_prompt, "the prompt is up at %s" % str(lever))
		eq(o.gate_tag, "held open", "the words are asked for")
		check(o.drew_gate_tag, "and put down at %s: %s" % [str(lever), str(o.gate_tag_rect)])
		check(not o.gate_tag_rect.grow(2.0).intersects(o.prompt_rect), "clear of the pill: %s %s" % [str(o.gate_tag_rect), str(o.prompt_rect)])
		for r in main.hud.covered_rects():
			check(not o.gate_tag_rect.intersects(r), "and of the HUD's boards")
	await _free(main)


func test_a_gate_open_in_the_dark_has_a_ring_that_pulses() -> void:
	var main := _game()
	var o = main.overlay
	var gate := _gate_of(main)
	var me = main.sim.avatar.player()
	_stand(main, me, LEVER + Vector2(-2.0, 7.5))
	Helpers.at(main.sim, 2, 22.0)
	gate.open = 0.0
	await _draw_once(main)
	check(not o.drew_gate_pulse and not o.drew_gate_outline, "shut at night, and far: nothing to see")
	gate.open = 0.4
	await _draw_once(main)
	check(o.drew_gate_pulse, "not all the way shut in the dark: the ring pulses, wherever you stand")
	eq(o.gate_tag, "gate open", "and says so")
	check(not o.drew_gate_outline, "(in place of the faint outline)")
	gate.open = 1.0
	gate.held = "open"
	await _draw_once(main)
	check(o.drew_gate_pulse, "held open it is the same")
	eq(o.gate_tag, "gate held open", "and says it is held")
	Helpers.at(main.sim, 2, 14.0)
	await _draw_once(main)
	check(not o.drew_gate_pulse, "by day an open gate is no alarm")
	await _free(main)


func test_no_gate_marks_without_the_rules_in_charge() -> void:
	var main := _game()
	var o = main.overlay
	var gate := _gate_of(main)
	gate.on = false
	gate.open = 1.0
	Helpers.at(main.sim, 2, 22.0)
	await _draw_once(main)
	check(not o.drew_gate_pulse and not o.drew_gate_outline and not o.drew_gate_spot, "nothing drawn for a gate the avatar cannot work")
	await _free(main)


# ------------------------------------------------------------------- the clock --

func test_the_clock_has_a_lamp_and_a_word_for_the_gate_in_avatar_mode_only() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	await Kit.settle()
	check(h.gate_row.visible, "the row is there in avatar mode")
	eq(h.gate_text(), "Gate: shut", "it says shut")
	eq(h.gate_lamp.color, GateKit.LAMP_SHUT, "with the red lamp")
	ctx.gate.open = 1.0
	Kit.update(ctx)
	eq(h.gate_text(), "Gate: open", "open")
	eq(h.gate_lamp.color, GateKit.LAMP_OPEN, "green")
	ctx.gate.held = "open"
	Kit.update(ctx)
	eq(h.gate_text(), "Gate: held open", "held open")
	ctx.gate.held = ""
	ctx.gate.says = false    # (a module that does not say which way: the HUD guesses from where the leaves were)
	ctx.gate.open = 0.5
	Kit.update(ctx)
	eq(h.gate_text(), "Gate: closing", "half way, having come from open: it is closing")
	eq(h.gate_lamp.color, GateKit.LAMP_MOVING, "amber")
	ctx.gate.open = 0.8
	Kit.update(ctx)
	eq(h.gate_text(), "Gate: opening", "and on the way out again: opening")
	ctx.gate.says = true
	ctx.gate.target = 0.0
	Kit.update(ctx)
	eq(h.gate_text(), "Gate: closing", "with the rules saying which way, it is what they say")
	ctx.gate.on = false
	Kit.update(ctx)
	check(not h.gate_row.visible, "and gone when the rules are not in charge")
	eq(h.gate_text(), "", "with no words")
	Kit.free_all(ctx)


func test_the_gate_row_is_not_in_the_old_game() -> void:
	var ctx := _ctx(1280, 800, "")
	check(not ctx.hud.gate_row.visible, "no avatar, no row")
	eq(ctx.hud.gate_text(), "", "no words")
	Kit.free_all(ctx)


func test_the_word_is_amber_when_the_gate_is_open_in_the_dark() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	ctx.gate.open = 1.0
	Helpers.at(ctx.sim, 2, 13.0)
	Kit.update(ctx)
	eq(h.gate_label.get_theme_color("font_color"), Hud.INK2, "by day the word is the quiet chalk")
	Helpers.at(ctx.sim, 2, 22.0)
	Kit.update(ctx)
	eq(h.gate_label.get_theme_color("font_color"), Hud.WARN, "open at night it is amber")
	ctx.gate.open = 0.0
	Kit.update(ctx)
	eq(h.gate_label.get_theme_color("font_color"), Hud.INK2, "shut at night it is calm again")
	Kit.free_all(ctx)


func test_the_gate_row_reads_and_explains_itself() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	await Kit.settle()
	var back := {"the panel": Color(Hud.PANEL, 1.0), "over white": TextTests.over(Hud.PANEL, Color.WHITE)}
	for col in [Hud.INK2, Hud.WARN]:
		for where in back:
			var ratio := TextTests.contrast(col, back[where])
			check(ratio >= 4.5, "the gate's word in %s on %s is %.2f:1" % [str(col), where, ratio])
	check(h.gate_label.get_theme_font_size("font_size") >= Fonts.MIN_PX, "12 px or more")
	check(h.gate_label.get_theme_font_size("font_size") >= 12, "(and 12 is the floor)")
	for c in [h.gate_row, h.gate_label, h.gate_lamp]:
		check(c.focus_mode == Control.FOCUS_NONE, "%s takes no focus" % c.name)
	check(h.gate_row.mouse_filter == Control.MOUSE_FILTER_PASS and h.gate_label.mouse_filter == Control.MOUSE_FILTER_PASS, "the mouse may rest on it for its tooltip")
	for c in [h.gate_row, h.gate_label]:
		check(c.tooltip_text.contains("E") and c.tooltip_text.to_lower().contains("lever") and c.tooltip_text.to_lower().contains("lamp"), "the tooltip says what the lever and the lamp are: %s" % c.tooltip_text)
	check(h.gate_row.tooltip_text.to_lower().contains("dusk"), "and the dusk")
	check(h.anchor_rect("clock.gate").size.y > 0.0, "the tips can point at it (anchor clock.gate)")
	Kit.free_all(ctx)


func test_the_gate_row_fits_the_clock_at_every_size_with_a_forecast_alerts_and_a_call() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		ctx.sim.tactics.told = Kit.forecast({"kind": "milestone", "name": "The Siege", "total": 82, "low": 70, "high": 95, "side": "east", "heading": "east", "sections": [3, 4], "brutes": 2, "plated": 2, "first_at": 21.0, "brute_at": 23.0, "needs_you": true, "ready": {"walls": 0.82, "guns": 3, "manned": 5, "posts": 5, "holds": true}})
		ctx.sim.phase = "night"
		ctx.gate.open = 1.0
		ctx.gate.held = "open"
		ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
		ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
		ctx.sim.radio.raise_call("gate", "The gate is open and it is dark", "Shut it at the lever", [{"id": "shut", "label": "Shut it"}, {"id": "later", "label": "Leave it"}], "later", 60.0, {}, Vector2(39, 18))
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var where := "%d x %d" % [size[0], size[1]]
		check(h.gate_row.visible, "%s: the gate row shows" % where)
		eq(h.gate_text(), "Gate: held open", "%s: its words" % where)
		var clock := Kit.rect(h.clock)
		var row := Kit.rect(h.gate_row)
		check(row.size.x > 20.0 and row.size.y >= 12.0, "%s: it has a size: %s" % [where, str(row)])
		check(clock.grow(0.5).encloses(row), "%s: it is inside the clock: %s in %s" % [where, str(row), str(clock)])
		var win := Rect2(0, 0, size[0], size[1])
		check(win.encloses(clock.grow(-0.5)), "%s: the clock is in the window: %s" % [where, str(clock)])
		var rects := {"clock": clock, "alerts": Kit.rect(h.alerts_box), "call": Kit.rect(h.call_card), "stores": Kit.rect(h.res_panel), "cards": Kit.rect(h.bar), "speed": Kit.rect(h.speed_panel), "buttons": Kit.rect(h.gizmos)}
		eq(Kit.overlaps(rects), [], "%s: the boards of the HUD clear each other with the gate row" % where)
		if h.call_card.visible:
			check(win.encloses(Kit.rect(h.call_card).grow(-0.5)), "%s: the call is in the window: %s" % [where, str(Kit.rect(h.call_card))])
		check(Kit.rect(h.gate_label).size.x + 14.0 + 6.0 <= clock.size.x, "%s: the word fits the clock's width: %s" % [where, str(Kit.rect(h.gate_label))])
		if h.forecast_label.visible:
			check(Kit.rect(h.forecast_label).position.y >= row.end.y - 0.5, "%s: above the forecast, which is put away first" % where)
		Kit.free_all(ctx)


func test_resizing_the_window_keeps_the_gate_row_inside_the_clock() -> void:
	var ctx := _ctx(1280, 800)
	var h = ctx.hud
	await Kit.settle()
	for size in [[700, 560], [1280, 800], [980, 700]]:
		Kit.resize(ctx, size[0], size[1])
		await Kit.settle()
		await Kit.settle()
		check(Kit.rect(h.clock).grow(0.5).encloses(Kit.rect(h.gate_row)), "%d x %d: the row is in the clock" % [size[0], size[1]])
	Kit.free_all(ctx)


# --------------------------------------------------------------------- the news --

func test_the_gate_is_a_kind_of_news_with_a_name_and_a_colour() -> void:
	var ctx := _ctx()
	eq(RadioKit.kind_name("gate"), "Gate", "its name")
	eq(RadioKit.kind_color(ctx.hud, "gate"), Hud.WARN, "amber: a warning, not the dead at the wall")
	check(RadioKit.KIND_NAME.has("gate"), "named in the table, not made from the kind")
	eq(RadioKit.kind_name("attack"), "Attack", "the old ones are as they were")
	Kit.free_all(ctx)


func test_a_call_about_the_gate_is_the_generic_card_in_its_kind() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	var id: int = radio.raise_call("gate", "The gate is open and it is dark", "Shut it at the lever by the north wall", [{"id": "shut", "label": "I'll shut it"}, {"id": "later", "label": "Leave it"}], "later", 60.0, {}, Vector2(39, 18))
	Kit.update(ctx)
	await Kit.settle()
	var h = ctx.hud
	check(h.call_card.visible, "a card")
	eq(h.call_card.shown_id, id, "for it")
	var view = h.call_card.view
	eq(view.kind_label.text, "GATE", "its kind")
	eq(view.kind_label.get_theme_color("font_color"), Hud.WARN, "in amber")
	eq(view.buttons.keys(), ["shut", "later"], "a button for each way")
	ctx.hud.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	check(_texts_of(ctx.hud.news_panel).contains("GATE"), "and the News lists it as a Gate: %s" % _texts_of(ctx.hud.news_panel))
	Kit.free_all(ctx)


# ---------------------------------------------------------------------- the tip --

func test_the_gate_tip_is_in_the_file_before_the_build_tip_and_says_the_lever_and_the_dusk() -> void:
	var list := Hints.load_hints()
	var at := {}
	for i in list.size():
		at[String(list[i].id)] = i
	check(at.has("gate"), "the tip is in the file")
	check(int(at["gate"]) < int(at["build"]), "before the build tip, which is last")
	var h: Dictionary = list[int(at["gate"])]
	var words := String(h.get("text_avatar", h.get("text", "")))
	check(words.contains("Shut the gate at dusk") and words.contains("E at the gate lever"), "it says what to do: %s" % words)
	check(Coach.words(words) <= Coach.MAX_WORDS and Coach.words(words) >= 8, "in %d words" % Coach.words(words))
	eq(h.anchor, ["clock"], "it points at the clock, which has the gate's lamp (the part of the HUD every game has)")


func test_the_gate_tip_comes_in_the_last_hour_of_the_day_and_at_dusk_in_avatar_mode_only() -> void:
	var g := Helpers.avatar_game(5, 5)
	var sim = g.sim
	var gate := _fake(sim)
	var start := {"cond": "gate_dusk"}
	Helpers.at(sim, 3, 10.0)
	check(not Conditions.check(start, sim, {}), "not in the morning")
	Helpers.at(sim, 3, 17.5)
	check(not Conditions.check(start, sim, {}), "not at half past five")
	Helpers.at(sim, 3, 18.2)
	check(Conditions.check(start, sim, {}), "in the hour before the bell")
	Helpers.at(sim, 3, 19.5)
	check(Conditions.check(start, sim, {}), "at dusk")
	Helpers.at(sim, 3, 23.0)
	check(Conditions.check(start, sim, {}), "and in the night (a game loaded after dusk)")
	Helpers.at(sim, 4, 5.0)
	check(Conditions.check(start, sim, {}), "before the dawn too")
	gate.on = false
	check(not Conditions.check(start, sim, {}), "not when the rules are not in charge")
	g.world.free()
	var old := Helpers.make(5, 1, 6)
	Helpers.at(old.sim, 3, 19.5)
	check(not Conditions.check(start, old.sim, {}), "not in the old game")
	old.world.free()


# ----------------------------------------------------------------- the screenshots --

func test_stage_gate_puts_the_rules_and_the_leaves_where_a_screenshot_asks() -> void:
	var main := _game()
	var gate := _gate_of(main)
	check(main.stage_gate("open"), "--gate=open")
	near(gate.open, 1.0, 0.0001, "the rules' gate is open")
	eq(gate.held, "", "and not held")
	near(main.gate_node.open, 1.0, 0.0001, "so are the leaves, at once")
	check(main.stage_gate("held"), "--gate=held")
	eq(gate.held, "open", "held open")
	check(main.stage_gate("shut"), "--gate=shut")
	near(gate.open, 0.0, 0.0001, "shut")
	eq(gate.held, "", "not held")
	near(main.gate_node.open, 0.0, 0.0001, "the leaves too")
	check(not main.stage_gate("ajar"), "another word is not a gate")
	_frames(main, 3)
	near(main.gate_node.open, 0.0, 0.0001, "and the leaves go on following the rules")
	gate.open = 1.0
	_frames(main, 60)
	near(main.gate_node.open, 1.0, 0.0001, "(open when the rules open)")
	await _free(main)


func test_beside_the_gate_stands_the_avatar_at_the_lever() -> void:
	var main := _game()
	check(main._stage_beside_spec("gate"), "--beside=gate")
	var me = main.sim.avatar.player()
	var d := Vector2(me.x, me.y).distance_to(LEVER)
	check(d > 0.3 and d < 1.3, "a step from the lever: %.2f tiles" % d)
	await _free(main)
