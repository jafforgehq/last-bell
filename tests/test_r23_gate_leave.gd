extends "res://tests/case.gd"
## Round 23, GATE-LEAVE: "we can't open the gate, we can't leave the map". The gate is easy to work (the prompt is at hand where a shut gate stops
## you, a click on its picture and Y and the clock's row work it, a hand that shuts it LOCKS it), the gate is never shut behind the avatar who is
## outside, and walking out through it and on past the line offers the Map once a crossing (scripts/sim/gate.gd, scripts/sim/interact.gd,
## scripts/main.gd, scripts/ui/hud.gd; the rules of round 22 are tests/test_gate_rules.gd's).

const Helpers := preload("res://tests/helpers.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Gate := preload("res://scripts/sim/gate.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const DT := 1.0 / 30.0
const ZOOM := 40.0
## Where a shut gate stops somebody who walks at it along the middle of the mouth, and the street 7 tiles out of the wall.
const AT_THE_FACE := Vector2(39.6, 21.3)
const STREET := Vector2(39.5, 8.0)
const YARD := Vector2(50.5, 30.5)


# ----------------------------------------------------------------- helpers --

## A quiet avatar game (Ruth the player) at 09:00 of day 1 with the avatar well away from the gate.
func _game() -> Dictionary:
	var g := Helpers.avatar_game(3, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.no_work(sim)
	Helpers.at(sim, 1, 9.0)
	sim.events.clear()
	sim.radio.news.clear()
	g["ruth"] = _p(sim, "ruth")
	_put(g.ruth, YARD)
	_put(_p(sim, "dez"), Vector2(44.5, 30.5))
	return g


func _p(sim, id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _put(p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.path = []
	p.goal_key = ""
	p.moving = false


func _go(sim, seconds: float) -> void:
	for i in int(round(seconds * 30.0)):
		sim.update(DT)


func _news(sim) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == "gate":
			out.append(String(e.text))
	return out


func _offers(sim, on: bool) -> int:
	var n := 0
	for e in sim.events:
		if String(e.get("type", "")) == "leave_offer" and bool(e.get("on", false)) == on:
			n += 1
	return n


## The real game (a small start with the avatar, Ruth) with the camera on the gate and the avatar at `at`.
func _main(at: Vector2) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true}, 1280, 800)
	var sim = main.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.jobs.clear()
	sim.tactics.chores = false
	_put(sim.avatar.player(), at)
	main.cam_center = Vector2(39.0, 20.0)
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	main._process(DT)
	return main


func _frames(main: Node, n: int) -> void:
	for i in n:
		main._process(DT)


func _toast(main: Node) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


func _click_at(main: Node, tile: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = main._tile_to_screen(tile)
	ev.pressed = true
	main._input(ev)
	main._unhandled_input(ev)
	ev = ev.duplicate()
	ev.pressed = false
	main._input(ev)
	main._unhandled_input(ev)


func _key(main: Node, code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	main._unhandled_input(ev)


# --------------------------------------------------------------- the prompt --

func test_the_prompt_is_at_hand_where_a_shut_gate_stops_you_and_reaches_three_and_a_half_tiles() -> void:
	var g := _game()
	var sim = g.sim
	eq(Gate.REACH, 3.5, "the reach")
	# walking straight at a shut gate along the mouth: where the face under the bridge stops the avatar
	_put(g.ruth, AT_THE_FACE)
	var c: Dictionary = sim.interact.best()
	eq(String(c.get("kind", "")), "gate", "the gate is the prompt where the shut gate stops you (it was 3.5 tiles from the old lever: out of reach)")
	eq(String(c.label), "Open the gate", "its words")
	check(bool(c.ok), "and it can be done")
	# the whole of the apron in front of the posts, west to east
	for x in [34.0, 36.0, 39.5, 41.0, 43.0]:
		_put(g.ruth, Vector2(x, 21.9))
		check(not sim.interact.gate_candidate().is_empty(), "in reach at x = %s" % str(x))
	# but not from across the yard
	_put(g.ruth, Vector2(39.5, 21.6 + Gate.REACH + 0.2))
	check(sim.interact.gate_candidate().is_empty(), "out of reach 3.7 tiles south of the front")
	var far: Dictionary = sim.interact.gate_candidate(Gate.CLICK_REACH)
	check(not far.is_empty() and bool(far.click), "a click reaches it from there: a candidate that only a click can use")
	var r: Dictionary = sim.interact.use(far)
	check(bool(r.ok) and sim.gate.held == "open", "and uses it: the gate is held open")
	_put(g.ruth, Vector2(39.5, 21.6 + Gate.CLICK_REACH + 0.5))
	check(sim.interact.gate_candidate(Gate.CLICK_REACH).is_empty(), "not from beyond six tiles")
	r = sim.interact.use(far)
	check(not bool(r.ok), "and a stale click is not used from there")
	g.world.free()


func test_a_click_on_the_gate_picture_and_the_keys_and_the_row_work_it_with_a_reason_when_too_far() -> void:
	var main := _main(Vector2(39.5, 26.0))    # (4.4 tiles from the front: beyond E, within a click)
	var sim = main.sim
	check(sim.gate.active(), "the gate has its rules")
	check(sim.interact.gate_candidate().is_empty(), "E would not reach from here")
	# a click on the leaf, from 4.4 tiles
	_click_at(main, Vector2(38.0, 17.8))
	eq(sim.gate.held, "open", "a click on the gate's picture opens it from within six tiles")
	eq(_toast(main), "Opening the gate.", "and says so")
	_frames(main, 90)
	check(sim.gate.open >= 1.0, "the leaves are open")
	# a click on a post, from beyond six tiles
	_put(sim.avatar.player(), Vector2(39.5, 29.0))
	_click_at(main, Vector2(36.3, 17.7))
	eq(sim.gate.held, "open", "nothing changed")
	eq(_toast(main), "Too far: walk to the gate", "and it says where to walk")
	# Y, at the gate and away from it
	_key(main, KEY_Y)
	eq(_toast(main), "Too far: walk to the gate", "Y works the gate only in reach")
	eq(sim.gate.held, "open", "(nothing changed)")
	_put(sim.avatar.player(), AT_THE_FACE + Vector2(0.0, 0.8))
	_frames(main, 3)
	_key(main, KEY_Y)
	eq(sim.gate.held, "shut", "Y in reach shuts it, and a hand that shuts locks it")
	eq(_toast(main), "Shutting the gate. Locked: cars wait outside", "with that said")
	# the clock's row: in reach it does the same (opens), away from it says where the lever is and the camera goes to it
	main.hud.on_gate.call()
	eq(sim.gate.held, "open", "the row works the gate in reach")
	_put(sim.avatar.player(), Vector2(50.5, 30.5))
	main.cam_hold = 0.0
	main.hud.on_gate.call()
	eq(_toast(main), "Walk to the gate lever (it is marked)", "away from it the row says where it is")
	check(main.cam_hold > 0.0 and main.cam_glide_to.distance_to(sim.gate.control_spot()) < 0.01, "and the camera goes to the lever")
	await TutorialKit.leave(main)


# --------------------------------------------------------------------- locks --

func test_a_hand_shut_gate_is_locked_until_the_player_opens_it_and_a_trip_the_avatar_leads_unlocks_it() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.ruth, AT_THE_FACE)
	check(bool(sim.gate.request(true).ok), "opened by hand")
	_go(sim, 2.5)
	var r: Dictionary = sim.gate.request(false)
	check(bool(r.ok) and bool(r.locked), "shut by hand: locked")
	_go(sim, 2.5)
	eq(sim.gate.open, 0.0, "shut")
	# a car that wants in waits outside, and the News says so once
	check(not sim.gate.demand("car_in", "The pickup"), "the car waits")
	_go(sim, 5.0)
	check(not sim.gate.demand("car_in", "The pickup"), "still")
	eq(sim.gate.open, 0.0, "the gate stays shut for it")
	check(_news(sim).any(func(t): return t.contains("The pickup") and t.contains("waits")), "the News says who waits")
	# the player opens it: it holds open, a car passes
	check(bool(sim.gate.request(true).ok), "opened again")
	_go(sim, 2.5)
	check(sim.gate.demand("car_in", "The pickup"), "now the car goes through")
	# locked again, and then the avatar leads a trip out: the lock is lifted, the gate opens for the party and shuts after
	sim.gate.request(false)
	_go(sim, 2.5)
	eq(sim.gate.held, "shut", "locked")
	var party: Dictionary = sim.scavenge.begin_played([g.ruth, _p(sim, "dez")], "houses", "loot", "")
	check(not party.is_empty(), "the trip begins")
	eq(sim.gate.held, "", "the lock is lifted: the avatar is the one leaving")
	_go(sim, 1.5)
	check(sim.gate.is_passable(), "the gate opens for the party")
	check(_news(sim).any(func(t): return t.contains("unlocked")), "and the News says it was unlocked")
	_go(sim, 12.0)
	eq(sim.gate.open, 0.0, "and shuts again a few seconds after")
	g.world.free()


# --------------------------------------------------------------- the outside --

func test_the_gate_is_not_shut_behind_the_avatar_and_a_shut_one_opens_for_them() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.ruth, AT_THE_FACE)
	sim.gate.request(true)
	_go(sim, 2.5)
	_put(g.ruth, STREET)
	sim.events.clear()
	sim.radio.news.clear()
	# the bell rings with the avatar outside: the keeper waits
	Helpers.at(sim, 1, 19.0)
	_go(sim, 8.0)
	check(sim.bell_rung, "the bell has rung")
	eq(sim.gate.open, 1.0, "the gate is still open")
	eq(_news(sim), ["The gate stays open for you"], "and the News says so, once")
	# back inside: it shuts for the night
	_put(g.ruth, Vector2(39.5, 25.0))
	_go(sim, 4.0)
	eq(sim.gate.open, 0.0, "shut once they are inside")
	check(_news(sim).has("The gate shuts for the night"), "the keeper's own line")
	# dawn with the avatar outside and the gate open: it is not asked to shut for a night that is over
	sim.gate.request(true)
	_go(sim, 2.5)
	_put(g.ruth, STREET)
	Helpers.at(sim, 2, 20.0)
	_go(sim, 1.0)
	Helpers.at(sim, 3, 8.0)
	_go(sim, 8.0)
	eq(sim.gate._forced, "", "nothing waits to be shut")
	check(sim.gate.open > 0.0, "and the gate is open for them still")
	# a gate that is shut (locked even) with the avatar outside opens as they come to it
	_put(g.ruth, AT_THE_FACE)
	sim.gate.request(false)
	_go(sim, 2.5)
	eq(sim.gate.open, 0.0, "shut")
	eq(sim.gate.held, "shut", "and locked")
	_put(g.ruth, Vector2(39.5, 13.0))
	sim.gate.held = "shut"
	_go(sim, 3.0)
	check(sim.gate.is_passable(), "it opens for the avatar who comes back to it, a lock does not keep them out")
	check(not bool(sim.gate.request(false).ok), "and a hand cannot shut it on them while they are outside")
	# a save with the avatar outside: loaded, the gate is as it was and no card comes up by itself
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var b := Helpers.make(3, 1, 5)
	check(SaveGame.apply(b.sim, d), "it loads")
	_put(_p(b.sim, "ruth"), STREET)
	b.sim.events.clear()
	_go(b.sim, 3.0)
	eq(b.sim.gate.open, sim.gate.open, "the leaves are where they were")
	eq(_offers(b.sim, true), 0, "no card on a load with the avatar out in the street")
	g.world.free()
	b.world.free()


# ------------------------------------------------------------------- leaving --

func test_walking_out_past_the_line_offers_the_map_once_and_e_opens_it() -> void:
	var main := _main(AT_THE_FACE)
	var sim = main.sim
	var me = sim.avatar.player()
	check(bool(sim.gate.request(true).ok), "the gate is opened")
	_frames(main, 90)
	_put(me, Vector2(39.5, 13.0))    # (outside the wall, but not past the line)
	_frames(main, 5)
	check(not sim.gate.leave_offer and not main.hud.leave_shown(), "no card just outside the wall")
	_put(me, STREET)
	_frames(main, 5)
	check(sim.gate.leave_offer, "past the line the Map is offered")
	check(main.hud.leave_shown(), "its card is up")
	eq(main.hud.leave_text(), "Leave the base?  E / click: open the Map", "with its words")
	# once a crossing: staying out, walking about, nothing new
	sim.events.clear()
	_put(me, Vector2(44.5, 7.0))
	_frames(main, 120)
	eq(_offers(sim, true), 0, "not offered again")
	# walking back inside the line puts it away
	_put(me, Vector2(39.5, 12.0))
	_frames(main, 3)
	check(not sim.gate.leave_offer and not main.hud.leave_shown(), "walking back dismisses it")
	_put(me, STREET)
	_frames(main, 120)
	check(not sim.gate.leave_offer, "and the same crossing is not offered again")
	# back to the wall, a cooldown, out again: a new crossing, and E (nothing at the feet to use) opens the Map
	_put(me, AT_THE_FACE)
	_frames(main, 30 * 22)
	_put(me, STREET)
	_frames(main, 5)
	check(sim.gate.leave_offer, "a new crossing makes a new offer")
	_key(main, KEY_E)
	eq(main.hud.radio_page(), "map", "E opens the Map, the radio panel's page")
	check(not sim.gate.leave_offer and not main.hud.leave_shown(), "and the offer is put away")
	# the card can be clicked too
	main.hud.close_radio()
	_put(me, AT_THE_FACE)
	_frames(main, 30 * 22)
	_put(me, STREET)
	_frames(main, 5)
	check(main.hud.leave_shown(), "(offered again)")
	main.hud.on_leave.call()
	eq(main.hud.radio_page(), "map", "a click on the card opens the Map too")
	await TutorialKit.leave(main)
	# never in Orientation Day: the gate has no rules there
	var t := TutorialKit.make_avatar()
	var tsim = t.sim
	_put(_p(tsim, "ruth"), STREET)
	tsim.events.clear()
	_go(tsim, 3.0)
	check(not tsim.gate.leave_offer and _offers(tsim, true) == 0, "no offer in Orientation Day")
	t.world.free()
