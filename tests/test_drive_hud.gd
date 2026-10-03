extends "res://tests/case.gd"
## The HUD of the live drive (round 21, V21.2: scripts/drive/drive_hud.gd; the "road" kind of scripts/ui/radio_kit.gd; the
## hooks of scripts/raid/raid_hud.gd). It is the place's HUD (cards, radio, News, call card, base clock, log, banner, toast,
## ammunition: all inherited) with a road panel, the gauges, the event card and the prompt pill added. The scene that mounts it
## (scripts/drive/drive_scene.gd) is another builder's: these tests drive it with a FAKE that has the same names (the plan's
## `leg`, `mode`, `in_car`, `aboard`, `road_progress`, `speed_now`, `pace`, `plan`, `road`, `car`, `autopilot`, `work_left`,
## `press_stop`, `choose`, `toggle_autopilot`), over the real game and the real place scene, so nothing but the drive is faked.

const GD := preload("res://scripts/game_data.gd")
const Kit := preload("res://tests/hud_kit.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const HudText := preload("res://tests/test_hud_text.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const RaidHud := preload("res://scripts/raid/raid_hud.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const DriveHud := preload("res://scripts/drive/drive_hud.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")

const W := 30
const H := 16
## The window sizes the HUD has to fit.
const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]
## The car of the fake: a pickup, cruising at 7.0 tiles a second, top 10.5.
const CRUISE := 7.0
const TOP := 10.5
const LEN := 300.0


## The scene of the drive, as the HUD sees it: the real place scene (a small site and a squad) with the names the plan gives
## the drive scene, table-driven by the test. It mounts the HUD under test in place of the place's own.
class FakeDrive:
	extends "res://scripts/raid/raid_scene.gd"
	const DriveHudScript := preload("res://scripts/drive/drive_hud.gd")
	var leg := "there"
	var mode := "drive"
	var car = null
	var plan: Array = []
	var road: Dictionary = {}
	var autopilot := false
	var work_left := 0.0
	var fake_speed := 0.0
	var fake_progress := 0.0
	var fake_pace := 1.0
	var asked: Array = []
	var chosen: Array = []
	var stops := 0
	var toggles := 0
	var options_of := {}
	var left_of := {}

	func mount_drive_hud() -> void:
		var old = hud_layer
		remove_child(old)
		old.free()
		hud_layer = DriveHudScript.new()
		hud_layer.layer = 4
		add_child(hud_layer)
		hud_layer.setup(hud, self)
		hud_layer.on_stage(leg, site)
		hud_layer.refresh()

	func in_car() -> bool:
		return car != null and (mode == "drive" or mode == "stopped")

	func aboard() -> Array:
		return run.squad if in_car() else []

	func road_progress() -> float:
		return fake_progress

	func speed_now() -> float:
		return fake_speed

	func pace() -> float:
		return fake_pace

	func event_options(uid: String) -> Array:
		return options_of.get(uid, [])

	func event_left(uid: String) -> float:
		return float(left_of.get(uid, -1.0))

	func press_stop() -> Dictionary:
		stops += 1
		return {"ok": true}

	func choose(uid: String, option_id: String) -> Dictionary:
		chosen.append([uid, option_id])
		return {"ok": true}

	func toggle_autopilot() -> void:
		toggles += 1
		autopilot = not autopilot


## A flow of the trip with the numbers the HUD reads: the clock of the leg, its pace and the place and the vehicle.
class FakeFlow:
	extends RefCounted
	var sim
	var place_id := "houses"
	var vehicle_id := ""
	var leg_pace := 1.0
	var road_total := 80.0
	var elapsed := 0.0
	var refusals: Array = []
	var going: Array = []

	func elapsed_min() -> float:
		return elapsed

	func road_progress() -> float:
		return 0.0

	func news_lines(_n: int = 6) -> Array:
		return []


## A site 30 x 16 of our own: open ground, a house in the middle, the entry on the left (as test_raid_scene's).
func _site() -> Dictionary:
	var data: Dictionary = GD.load_all().duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in H:
		for x in W:
			terrain.append(1)
			var wall := (x >= 14 and x <= 24 and y >= 3 and y <= 12) and (x == 14 or x == 24 or y == 3 or y == 12) and not (x == 14 and y == 8)
			solid.append(1 if wall else 0)
	data["W"] = W
	data["H"] = H
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	for k in ["objects", "walls", "marks", "lights", "trees", "segments", "people", "spawns"]:
		data[k] = []
	return {
		"name": "The road to The pharmacy", "kind": "road", "danger": 1, "size": Vector2i(W, H), "data": data,
		"entry": Vector2(3.5, 8.5), "exit": Rect2(1.0, 6.5, 5.0, 4.0), "vehicle_spot": Vector2(-1, -1),
		"containers": [], "dead": [], "rooms": [], "seed": 1,
		"road": {"len": LEN, "width": 30, "style": "urban", "dir": -1, "leg": "there", "slots": [], "dyn": [], "ambient": []},
	}


func _game(width: int = 1280, height: int = 800, crew: int = 3) -> Node:
	return TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": true}, width, height)


## The drive scene over `main`: a pickup, three aboard, on the way there at the start of the road.
func _open(main: Node, n: int = 3, leg: String = "there", by_car: bool = true) -> FakeDrive:
	var party: Array = []
	for i in n:
		party.append(main.sim.people[i])
	var scene := FakeDrive.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.leg = leg
	var vehicle: Dictionary = main.sim.vehicles.add("pickup") if by_car else {}
	var flow := FakeFlow.new()
	flow.sim = main.sim
	flow.vehicle_id = String(vehicle.get("id", ""))
	scene.flow = flow
	if by_car:
		scene.car = _car(float(main.sim.vehicles.kind_of(flow.vehicle_id).hp))
		scene.mode = "drive"
	else:
		scene.mode = "foot"
	scene.setup(main, main.hud, main.data, _site(), party, 300.0, "", 1.0, false)
	scene.mount_drive_hud()
	return scene


func _car(hp: float) -> Object:
	var c := FakeCar.new()
	c.hp = hp
	return c


## The car's data as the HUD reads it: hp, the kind's top and cruise speeds.
class FakeCar:
	extends RefCounted
	var hp := 90.0
	var cruise := 7.0
	var top := 10.5
	var kind := {"name": "Pickup", "hp": 90, "speed": 2.2}
	var speed := 0.0


func _tick(scene: FakeDrive, n: int = 1) -> void:
	for i in n:
		scene.hud_layer.refresh()
		await TutorialKit.settle()


func _leave(main: Node) -> void:
	await TutorialKit.leave(main)


# ------------------------------------------------------------- the hooks --

func test_the_road_is_a_kind_of_news_with_a_name_and_a_colour() -> void:
	eq(RadioKit.kind_name("road"), "Road", "the small capitals over a line of the log")
	var host := Hud.new()
	eq(RadioKit.kind_color(host, "road"), host.INFO, "blue, like a card of the storyteller, not the dim chalk of an unknown kind")
	host.free()


func test_the_place_hud_gives_the_drive_its_two_hooks_and_changes_nothing_by_them() -> void:
	var h := RaidHud.new()
	eq(h._legend_text(), RaidHud.LEGEND, "the place's own legend")
	eq(h._hide_for_drive(), false, "the place never hides the squad's verbs")
	h.free()


# ------------------------------------------------------------- the gauges --

func test_the_speed_word_and_the_dial_follow_the_car() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	for pair in [[0.0, "Stopped"], [0.2, "Stopped"], [1.5, "Slow"], [3.5, "Slow"], [4.5, "Cruising"], [7.0, "Cruising"], [7.5, "Fast"], [10.5, "Fast"], [-2.0, "Reversing"]]:
		scene.fake_speed = pair[0]
		h.refresh()
		eq(h.gauge_words().speed, pair[1], "the word at %.1f tiles a second" % pair[0])
		eq(h.dial_word.text, pair[1], "the dial's word at %.1f" % pair[0])
	scene.fake_speed = 2.0
	scene.car.speed = -2.0
	h.refresh()
	eq(h.gauge_words().speed, "Reversing", "a car going backwards (the scene gives a magnitude, the car its sign)")
	scene.car.speed = 0.0
	scene.fake_speed = 7.0
	h.refresh()
	near(h.dial.target, 7.0 / TOP, 0.001, "the dial fills the share of the top speed")
	near(h.dial.cruise_frac, CRUISE / TOP, 0.001, "and its mark is at cruising speed")
	eq(h.gauge_words().kmh, str(roundi(7.0 * DriveHud.KMH)), "the number on the dial")
	await _leave(main)


func test_the_fuel_is_the_trip_tank_draining_by_distance_and_the_base_tank_is_under_it() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	var flow = scene.flow
	var per_leg: float = main.sim.vehicles.fuel_for(flow.place_id, flow.vehicle_id) / 2.0
	check(per_leg > 0.0, "the pickup burns fuel on the way to the houses")
	main.sim.vehicles.fuel = 18.0
	var total := DriveHud.num(per_leg * 2.0)
	scene.fake_progress = 0.0
	h.refresh()
	eq(h.gauge_words().fuel, "Fuel %s of %s" % [total, total], "a full tank at the gate")
	eq(h.gauge_words().tank, "Base tank 18", "the base's own tank under it")
	scene.fake_progress = 0.5
	h.refresh()
	eq(h.gauge_words().fuel, "Fuel %s of %s" % [DriveHud.num(per_leg * 1.5), total], "half way there: a quarter of the trip's fuel is gone")
	near(h.fuel_bar.value, 0.75, 0.001, "and the bar says so")
	scene.fake_progress = 1.0
	h.refresh()
	eq(h.gauge_words().fuel, "Fuel %s of %s" % [DriveHud.num(per_leg), total], "at the place: one leg's worth is left for the way home")
	scene.leg = "home"
	scene.fake_progress = 0.0
	h.refresh()
	eq(h.gauge_words().fuel, "Fuel %s of %s" % [DriveHud.num(per_leg), total], "the way home begins with that")
	scene.fake_progress = 1.0
	h.refresh()
	eq(h.gauge_words().fuel, "Fuel 0 of %s" % total, "and ends with none: an eventless trip burns exactly the abstract trip's fuel")
	await _leave(main)


func test_the_hp_bar_goes_amber_under_half_and_red_under_a_third_with_the_engine_smoking() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	scene.car.hp = 90.0
	h.refresh()
	eq(h.gauge_words().hp, "Pickup 100%", "a new pickup")
	eq(h.hp_bar.color, Hud.OK, "green")
	eq(h.gauge_words().hp_note, "", "no word of smoke")
	check(not h.hp_note.visible, "and none shown")
	scene.car.hp = 40.0
	h.refresh()
	eq(h.gauge_words().hp, "Pickup 44%", "worn")
	eq(h.hp_bar.color, Hud.WARN, "amber under half")
	check(not h.hp_note.visible, "not smoking yet")
	scene.car.hp = 20.0
	h.refresh()
	eq(h.hp_bar.color, Hud.DANGER, "red under 30%")
	eq(h.gauge_words().hp_note, "The engine is smoking", "and it says so")
	check(h.hp_note.visible, "on the board")
	near(h.hp_bar.value, 20.0 / 90.0, 0.001, "the bar is the share")
	await _leave(main)


func test_the_road_shows_the_progress_the_ticks_of_events_met_and_the_clock_against_the_roads() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	scene.plan = [
		{"uid": "e1", "id": "smoke", "kind": "stop", "at": 0.2, "state": "done", "def": {}},
		{"uid": "e2", "id": "ambush", "kind": "dead", "at": 0.45, "state": "missed", "def": {}},
		{"uid": "e3", "id": "survivor", "kind": "stop", "at": 0.7, "state": "pending", "def": {}},
		{"uid": "e4", "id": "herd", "kind": "dead", "at": 0.85, "state": "pending", "def": {}},
	]
	scene.fake_progress = 0.5
	scene.flow.road_total = 80.0
	scene.flow.elapsed = 34.0
	h.refresh()
	eq(h.gauge_words().progress, "50%", "half way")
	near(h.route_bar.value, 0.5, 0.001, "the bar")
	eq(h.ticks().size(), 2, "a tick for each event already met, none for the ones ahead")
	near(float(h.ticks()[0].at), 0.2, 0.001, "at its place on the road")
	eq(h.gauge_words().delta, "Ahead of the clock: 6 min", "the leg is 6 minutes up: half of 80 less 34")
	eq(h.route_delta.get_theme_color("font_color"), Hud.OK, "in green")
	scene.flow.elapsed = 40.0
	h.refresh()
	eq(h.gauge_words().delta, "On time", "on the road's own clock")
	scene.flow.elapsed = 49.0
	h.refresh()
	eq(h.gauge_words().delta, "Behind: 9 min", "9 minutes behind")
	eq(h.route_delta.get_theme_color("font_color"), Hud.WARN, "in amber")
	check(h.route_caps.text.contains("ROAD THERE"), "the leg is named: %s" % h.route_caps.text)
	scene.leg = "home"
	h.refresh()
	check(h.route_caps.text.contains("ROAD HOME"), "and the way home: %s" % h.route_caps.text)
	await _leave(main)


func test_the_clock_is_the_flows_when_the_flow_keeps_it() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	var flow := FlowWithClock.new()
	flow.sim = main.sim
	scene.flow = flow
	scene.fake_progress = 0.25
	flow.leg_road_min = 60.0
	flow.elapsed = 9.0
	h.refresh()
	eq(h.gauge_words().delta, "Ahead of the clock: 6 min", "its own `delta_min` is the HUD's word: a quarter of 60 less 9")
	await _leave(main)


## A flow that has its own `delta_min` (the real one has).
class FlowWithClock:
	extends FakeFlow
	var leg_road_min := 60.0

	func delta_min(progress: float) -> float:
		return progress * leg_road_min - elapsed


# ----------------------------------------------------------- the event card --

## A survivor's card (two choices, the second taken by default after 8 s) in the plan, open: the car stands.
func _open_card(scene: FakeDrive, refused: bool = false, left: float = 6.0) -> void:
	scene.plan = [{"uid": "e1", "id": "survivor", "kind": "stop", "at": 0.4, "state": "open", "def": {
		"title": "Survivor", "text": "Someone waves from the verge. They look hungry, not hurt.", "kind": "stop", "ttl_s": 8.0, "auto": "drive_on",
		"choices": [{"id": "take", "label": "Take them in"}, {"id": "drive_on", "label": "Drive on"}]}}]
	scene.mode = "stopped"
	scene.fake_speed = 0.0
	scene.options_of = {"e1": [
		{"id": "take", "label": "Take them in", "ok": not refused, "why": "No seat free: the pickup seats 2" if refused else "", "auto": false},
		{"id": "drive_on", "label": "Drive on", "ok": true, "why": "", "auto": true},
	]}
	scene.left_of = {"e1": left}


func test_an_open_event_is_a_card_with_its_choices_keys_and_the_default_marked() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	h.refresh()
	check(not h.event_panel.visible, "no card with nothing open")
	eq(h.event_options(), [], "and no options")
	_open_card(scene)
	await _tick(scene, 2)
	check(h.event_panel.visible, "the card is up")
	eq(h.event_title.text, "Survivor", "its title")
	check(h.event_text.text.begins_with("Someone waves"), "and its line: %s" % h.event_text.text)
	var opts: Array = h.event_options()
	eq(opts.size(), 2, "two choices")
	eq(opts[0].text, "Take them in", "the first")
	eq(opts[0].key, "1", "on the 1")
	eq(opts[0].disabled, false, "which can be taken")
	eq(opts[0].auto, false, "and is not the default")
	eq(opts[1].text, "Drive on", "the second")
	eq(opts[1].key, "2", "on the 2")
	eq(opts[1].auto, true, "the default is marked")
	check(h.event_buttons[1].ring != null and h.event_buttons[0].ring == null, "the countdown ring is on the default and on no other")
	near(h.event_buttons[1].ring.frac, 6.0 / 8.0, 0.001, "six of its eight seconds are left")
	eq(h.event_buttons[1].ring.text, "6", "the number in the ring")
	check(not scene.paused, "the card pauses nothing")
	scene.left_of = {"e1": 2.0}
	h.refresh()
	near(h.event_buttons[1].ring.frac, 0.25, 0.001, "the ring runs down")
	scene.left_of = {"e1": -1.0}
	h.refresh()
	check(not h.event_buttons[1].ring.visible, "a card with no countdown has no ring")
	check(h.event_buttons[1].ring.get_meta("tag").visible, "it says 'default' instead")
	await _leave(main)


func test_a_refused_choice_is_greyed_with_its_reason_in_the_tooltip_and_in_amber_and_cannot_be_pressed() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	_open_card(scene, true)
	await _tick(scene, 2)
	var opts: Array = h.event_options()
	eq(opts[0].disabled, true, "the first is refused")
	eq(opts[0].why, "No seat free: the pickup seats 2", "with its reason")
	var b: Button = h.event_buttons[0].button
	check(b.disabled, "the button is greyed")
	eq(b.tooltip_text, "No seat free: the pickup seats 2", "its tooltip is the reason")
	var amber := false
	for c in h.event_buttons[0].line.get_children():
		if c is Label and c.text == "No seat free: the pickup seats 2":
			amber = c.get_theme_color("font_color") == Hud.WARN
	check(amber, "and the reason is written under it in amber")
	var r: Dictionary = h.press_option(0)
	eq(r.ok, false, "pressing it refuses")
	eq(r.why, "No seat free: the pickup seats 2", "with the reason")
	eq(scene.chosen, [], "and nothing is chosen")
	check(not h.toast_panel.visible and not h.event_note.visible, "the reason is on the card already: no toast to say it twice")
	h.toast("Something else happened", "info")
	eq(h.event_note.text, "Something else happened", "any other toast over a card is a line in it")
	check(h.event_note.visible and not h.toast_panel.visible, "and the card is where it shows")
	var ok_button: Button = h.event_buttons[1].button
	check(not ok_button.disabled and ok_button.tooltip_text == "", "the other is on offer")
	await _leave(main)


func test_pressing_a_choice_or_its_button_asks_the_scene_to_choose_it() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	_open_card(scene)
	await _tick(scene, 2)
	var r: Dictionary = h.press_option(1)
	eq(r.ok, true, "the scene took it")
	eq(scene.chosen, [["e1", "drive_on"]], "the event and the choice")
	h.event_buttons[0].button.pressed.emit()
	eq(scene.chosen.back(), ["e1", "take"], "a click on the button is the same")
	eq(h.press_option(5).ok, false, "there is no sixth choice")
	await _leave(main)


func test_an_event_the_rules_ask_nothing_of_is_no_card() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	# (an ambush has a choice in its def, but its card is "never": the scene's options for it are none)
	scene.plan = [{"uid": "e2", "id": "ambush", "kind": "dead", "at": 0.3, "state": "open", "def": {
		"title": "Ambush!", "text": "They pour from both verges.", "kind": "dead", "choices": [{"id": "through", "label": "Drive through or fight"}]}}]
	await _tick(scene, 2)
	check(not h.event_panel.visible, "an ambush has nothing to choose: no card")
	eq(h.event_options(), [], "and no options")
	await _leave(main)


## A scene with only the plan: nothing of `event_options`, `open_event` or `road_ctx` (the HUD takes what the entry and its def say).
class BareDrive:
	extends "res://scripts/raid/raid_scene.gd"
	var leg := "there"
	var mode := "stopped"
	var car = null
	var plan: Array = []

	func in_car() -> bool:
		return car != null


func test_a_scene_with_no_options_of_its_own_gets_the_defs_choices() -> void:
	var main := _game()
	var party: Array = [main.sim.people[0], main.sim.people[1]]
	var scene := BareDrive.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.car = _car(90.0)
	scene.setup(main, main.hud, main.data, _site(), party, 300.0, "", 1.0, false)
	var old = scene.hud_layer
	scene.remove_child(old)
	old.free()
	scene.hud_layer = DriveHud.new()
	scene.add_child(scene.hud_layer)
	scene.hud_layer.setup(main.hud, scene)
	var h = scene.hud_layer
	scene.plan = [{"uid": "e1", "id": "survivor", "kind": "stop", "at": 0.4, "state": "open", "def": {
		"title": "Survivor", "text": "Someone waves.", "kind": "stop", "auto": "drive_on",
		"choices": [{"id": "take", "label": "Take them in"}, {"id": "drive_on", "label": "Drive on"}]}}]
	h.refresh()
	await TutorialKit.settle()
	var opts: Array = h.event_options()
	eq(opts.size(), 2, "the def's own choices")
	eq(opts[1].auto, true, "the def's auto is marked")
	eq(h.press_option(0).ok, false, "(this scene cannot choose: the card says so rather than doing nothing)")
	await _leave(main)


func test_a_card_that_only_closes_has_its_ring_in_its_head() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	scene.plan = [{"uid": "e5", "id": "roadblock", "kind": "block", "at": 0.3, "state": "open", "def": {
		"title": "Roadblock", "text": "Wrecks across the road with one gap.", "kind": "block", "ttl_s": 8.0, "timeout": "close", "choices": [{"id": "clear", "label": "Clear it"}]}}]
	scene.mode = "stopped"
	scene.options_of = {"e5": [{"id": "clear", "label": "Clear it", "ok": true, "why": "", "auto": false}]}
	scene.left_of = {"e5": 5.0}
	await _tick(scene, 2)
	check(h.event_panel.visible, "the roadblock's card is up")
	check(h.event_buttons[0].ring == null, "no option is the default")
	check(h.event_ring.visible, "the card's own ring counts it down")
	near(h.event_ring.frac, 5.0 / 8.0, 0.001, "five of eight seconds")
	scene.left_of = {"e5": -1.0}
	h.refresh()
	check(not h.event_ring.visible, "none without a countdown")
	await _leave(main)


func test_the_card_goes_when_the_event_is_done_and_when_the_trip_is_over() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	_open_card(scene)
	await _tick(scene, 2)
	check(h.event_panel.visible, "open")
	scene.plan[0].state = "done"
	scene.mode = "drive"
	h.refresh()
	check(not h.event_panel.visible, "done: gone")
	eq(h.event_buttons.size(), 0, "with its buttons")
	_open_card(scene)
	h.refresh()
	check(h.event_panel.visible, "open again")
	scene.ended = true
	h.refresh()
	check(not h.event_panel.visible, "the trip is over: no card")
	await _leave(main)


# --------------------------------------------------------------- the prompt --

func test_the_prompt_asks_for_e_within_forty_tiles_of_a_stop() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	scene.plan = [{"uid": "e1", "id": "survivor", "kind": "stop", "at": 0.4, "state": "pending", "def": {"title": "Survivor", "text": "x", "kind": "stop", "choices": []}}]
	scene.fake_progress = 0.1
	h.refresh()
	eq(h.prompt_text(), "", "ninety tiles off: nothing")
	check(not h.prompt_panel.visible, "and no pill")
	scene.fake_progress = 0.3
	h.refresh()
	eq(h.prompt_text(), "E  Stop: someone is waving", "thirty tiles ahead")
	check(h.prompt_panel.visible and h.prompt_key.visible, "the pill with its key")
	eq(h.prompt_label.text, "Stop: someone is waving", "and the words")
	scene.fake_progress = 0.5
	h.refresh()
	eq(h.prompt_text(), "", "driven past it: nothing")
	scene.fake_progress = 0.3
	scene.plan[0].state = "open"
	h.refresh()
	eq(h.prompt_text(), "", "an open card has the keys: no pill")
	await _leave(main)


func test_the_prompt_for_a_roadblock_wants_the_car_slow_and_the_squads_work_has_a_clock() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	scene.plan = [{"uid": "e5", "id": "roadblock", "kind": "block", "at": 0.5, "state": "pending", "def": {"title": "Roadblock", "text": "x", "kind": "block", "choices": []}}]
	scene.fake_progress = 0.46
	scene.fake_speed = 6.0
	h.refresh()
	check(not h.prompt_text().begins_with("E"), "fast: a word of warning, no E: %s" % h.prompt_text())
	check(h.prompt_text().contains("Roadblock"), "about the roadblock")
	check(not h.prompt_key.visible, "with no key")
	scene.fake_speed = 1.0
	h.refresh()
	eq(h.prompt_text(), "E  Roadblock: clear it", "slow: E clears it")
	scene.mode = "out"
	scene.work_left = 6.2
	h.refresh()
	eq(h.prompt_text(), "Working at the stop: 7 s", "the squad is out: the seconds left")
	scene.work_left = 0.0
	h.refresh()
	eq(h.prompt_text(), "E  Back in the car", "and when they are done")
	await _leave(main)


# ------------------------------------------------------------------- the keys --

func _legend_words(h) -> Array:
	var out: Array = []
	for item in h.legend_panel.get_child(0).get_children():
		for c in item.get_children():
			if c is Label:
				out.append(c.text)
			elif c is PanelContainer:
				out.append_array(Kit.texts(c))
	return out


func test_the_legend_is_the_roads_in_a_car_with_tab_for_the_autopilot_and_the_places_on_foot() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	h.refresh()
	var text: String = h.legend_text()
	check(text.contains("W S gas and brake"), "in the car: %s" % text)
	check(text.contains("A D steer") and text.contains("E stop") and text.contains("Tab autopilot"), "steering, the stop and the autopilot: %s" % text)
	check(_legend_words(h).has("Tab") and _legend_words(h).has("autopilot"), "the board has the Tab chip and its word: %s" % str(_legend_words(h)))
	await _leave(main)
	main = _game()
	scene = _open(main, 3, "there", false)
	h = scene.hud_layer
	h.refresh()
	text = h.legend_text()
	check(text.contains("W A S D walk") and text.contains("E stop") and text.contains("F melee"), "on foot: %s" % text)
	check(not text.contains("Tab") and not text.contains("steer"), "no car, no Tab and no steering")
	check(not _legend_words(h).has("Tab"), "and the board has none")
	scene.leg = "place"
	h.on_stage("place", scene.site)
	check(h.legend_text() == RaidHud.new()._legend_text().map(func(e): return "%s %s" % [" ".join(PackedStringArray(e[0])), e[1]]).reduce(func(a, b): return a + ", " + b), "in the place it is the place's own: %s" % h.legend_text())
	await _leave(main)


func test_the_legend_fades_as_the_places_does() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	scene.legend_t = RaidHud.LEGEND_HOLD
	h.refresh()
	near(h.legend_panel.modulate.a, 1.0, 0.001, "at first it is there")
	scene.legend_t = 1.0
	h.refresh()
	near(h.legend_panel.modulate.a, 0.5, 0.001, "then it fades")
	scene.legend_t = 0.0
	h.refresh()
	near(h.legend_panel.modulate.a, 0.0, 0.001, "and goes")
	await _leave(main)


# ------------------------------------------------------------------ the squad --

func test_the_squads_verbs_are_off_the_radio_while_aboard_and_back_on_foot() -> void:
	var main := _game(1280, 800, 5)
	var scene := _open(main)
	var h = scene.hud_layer
	var dez = scene.run.squad[1]
	scene.select_contact("squad", dez)
	h.refresh()
	check(h._hide_for_drive(), "aboard: the squad's verbs are hidden")
	check(not h.contact_label.visible, "no name over the verbs")
	check(h.contact_hint.visible and h.contact_hint.text.contains("You are driving"), "'You are driving' under the contacts: %s" % h.contact_hint.text)
	check(h.radio_verbs.contact == null, "the verbs have nobody to ask")
	h.pick_contact("squad", dez)
	check(scene.contact.is_empty() or scene.contact.get("kind", "") != "squad" or h._hide_for_drive(), "a click on a card opens nothing")
	check(h.toast_label.text.contains("driving"), "and says why: %s" % h.toast_label.text)
	check(h.back_button.disabled and h.back_button.tooltip_text != "", "All back is off, with a reason: %s" % h.back_button.tooltip_text)
	var at_base: Array = scene.base_contacts()
	check(not at_base.is_empty(), "there are people at the base")
	h.pick_contact("base", at_base[0])
	eq(scene.contact.get("kind", ""), "base", "they stay on the radio while you drive")
	h.refresh()
	check(h.radio_verbs.contact == at_base[0], "with their verbs")
	# on foot (the car is gone): the squad is asked as in a place
	scene.car = null
	scene.mode = "foot"
	scene.select_contact("squad", dez)
	h.refresh()
	check(not h._hide_for_drive(), "on foot the verbs are back")
	check(h.radio_verbs.contact == dez, "for the one asked")
	check(not h.back_button.disabled, "and All back works")
	await _leave(main)


func test_the_cards_say_who_drives_and_who_rides() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	h.refresh()
	eq(h.cards[0].status.text, "Driving", "the one you lead drives")
	eq(h.cards[1].status.text, "Aboard", "the others ride")
	scene.autopilot = true
	h.refresh()
	eq(h.cards[0].status.text, "Autopilot", "and when the squad drives")
	check(h.cards[1].panel.tooltip_text.contains("driving"), "a card's tooltip says why a click does nothing: %s" % h.cards[1].panel.tooltip_text)
	scene.mode = "foot"
	scene.car = null
	h.refresh()
	check(h.cards[1].status.text != "Aboard", "on foot nobody is aboard: %s" % h.cards[1].status.text)
	await _leave(main)


func test_the_autopilot_button_toggles_it_and_shows_it_is_on() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	h.refresh()
	check(h.auto_button.visible, "in a car the button is there")
	check(h.auto_button.tooltip_text.contains("Tab"), "its tooltip says the key: %s" % h.auto_button.tooltip_text)
	h.auto_button.pressed.emit()
	eq(scene.toggles, 1, "it asks the scene")
	check(scene.autopilot, "and the autopilot is on")
	check(h.auto_button.text.contains("on"), "the button says so: %s" % h.auto_button.text)
	check(h.line_label.text.contains("W A S D"), "and the line under the road's name tells how to take the wheel: %s" % h.line_label.text)
	scene.mode = "foot"
	scene.car = null
	h.refresh()
	check(not h.auto_button.visible, "on foot there is nothing to hand the wheel of")
	check(not h.fuel_head.is_visible_in_tree() and not h.mini_box.visible, "and no gauges")
	await _leave(main)


# -------------------------------------------------------- the radio and the clock --

func test_the_call_card_and_the_news_work_on_the_road_at_the_legs_pace() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	scene.fake_pace = 1.2
	var call_id: int = main.sim.radio.raise_call("attack", "The east wall is under attack", "Three of the dead are at it", [{"id": "hold", "label": "Hold"}, {"id": "help", "label": "Send help"}], "hold", 30.0)
	await _tick(scene, 2)
	check(h.call_card.visible, "the call card is up on the road")
	eq(h.call_card.shown_id, call_id, "for the call")
	var speed: float = h.call_card.view.options.speed_getter.call()
	near(speed, 1.2 / 3.0, 0.0001, "its seconds are read at the leg's pace: a game minute is a fifth less than a second")
	var left: float = h.call_card.view.seconds_left()
	near(left, 30.0 / main.sim.min_per_sec / (1.2 / 3.0), 0.5, "30 minutes at 1.2 a second")
	check(h.base_panel.visible and h.clock_label.text != "", "the base's clock is there: %s" % h.clock_label.text)
	h.open_news(true)
	await _tick(scene, 2)
	check(h.news_panel.visible, "the News opens")
	eq(h.news_panel.call_ids(), [call_id], "with the open call in it")
	check(not h.call_card.visible, "and the card steps aside")
	h.open_news(false)
	await _tick(scene, 2)
	var picked: bool = h.call_card.view.buttons.has("help")
	check(picked, "the card's buttons are the call's")
	h.call_card.view.buttons["help"].pressed.emit()
	eq(RadioKit.entry_of(main.sim.radio, call_id).answered, "help", "and a click answers it")
	main.sim.radio.log_news("road", "Arrived 8 min early", "")
	h.open_news(true)
	await _tick(scene, 2)
	check(h.news_panel.row_kinds().has("road"), "a word from the road is in the News: %s" % str(h.news_panel.row_kinds()))
	scene.leg = "place"
	h.on_stage("place", scene.site)
	near(h.call_card.view.options.speed_getter.call(), PlaceFlow.PLACE_PACE, 0.0001, "in the place the seconds are the place's own")
	await _leave(main)


# ---------------------------------------------------------------- the stage --

func test_a_stage_change_names_the_place_panel_and_gives_the_bags_back_in_the_place() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	h.refresh()
	eq(h.place_label.text, "The road to The pharmacy", "the road's name")
	check(h.route_box.visible and not h.bags_box.visible, "the road is where the bags are")
	scene.leg = "place"
	var site := _site()
	site["name"] = "The pharmacy"
	h.on_stage("place", site)
	eq(h.place_label.text, "The pharmacy", "the place's name")
	check(not h.route_box.visible and h.bags_box.visible, "the bags are back, the road is gone")
	check(not h.mini_box.visible and not h.roomy_box.visible, "and the gauges with it")
	check(h.loot_panel.visible and h.weapon_panel.visible, "the rest is the place's")
	eq(h.bags_label.text, "0 of %d" % scene.run.capacity(), "the tally of the bags")
	await _leave(main)


func test_a_stage_with_another_squad_has_its_cards_made_again() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	eq(h.cards.size(), 3, "three cards")
	var first = h.cards[0].p
	scene.run.squad = scene.run.squad.slice(0, 2)
	h.on_stage("there", scene.site)
	eq(h.cards.size(), 2, "two cards for two")
	eq(h.cards[0].p, first, "the same people")
	eq(h.cards_grid.get_child_count(), 2, "and no stale card in the grid")
	await _leave(main)


# --------------------------------------------------------- layout and text --

func _hud_rects(h) -> Dictionary:
	var out := {
		"place": Kit.rect(h.place_panel), "road": Kit.rect(h.loot_panel), "cards": Kit.rect(h.cards_grid), "radio": Kit.rect(h.radio_panel),
		"log": Kit.rect(h.log_panel), "legend": Kit.rect(h.legend_panel), "ammo": Kit.rect(h.weapon_panel), "base": Kit.rect(h.base_panel),
		"banner": Kit.rect(h.banner), "toast": Kit.rect(h.toast_panel), "event": Kit.rect(h.event_panel), "prompt": Kit.rect(h.prompt_panel),
	}
	if h.call_card.visible:
		out["call"] = Kit.rect(h.call_card)
	if h.news_panel.visible:
		out["news"] = Kit.rect(h.news_panel)
	return out


## Everything the drive's HUD can show at once: the squad's cards, the road, the gauges, a card with a refused choice, the legend,
## the log, a banner, a toast, a call, and (with `news`) the News log.
func _busy(width: int, height: int, news: bool = false, card: bool = true) -> Dictionary:
	var main := _game(width, height, 5)
	var scene := _open(main, 3)
	scene.fake_speed = 6.0
	scene.fake_progress = 0.35
	scene.car.hp = 40.0
	scene.flow.road_total = 80.0
	scene.flow.elapsed = 20.0
	scene.plan = [{"uid": "e0", "id": "smoke", "kind": "stop", "at": 0.2, "state": "done", "def": {}}]
	if card:
		_open_card(scene, true)
	else:
		scene.plan.append({"uid": "e3", "id": "survivor", "kind": "stop", "at": 0.4, "state": "pending", "def": {"title": "Survivor", "text": "x", "kind": "stop", "choices": []}})
	for line in ["Dez shot one of the dead from the window.", "Ruth: the road bends west ahead.", "Marcus reloaded.", "The pickup scraped a wreck."]:
		scene.run.log.append(line)
	main.sim.radio.raise_call("attack", "The east wall is under attack", "Three of the dead are at it", [{"id": "hold", "label": "Hold"}, {"id": "help", "label": "Send help"}], "hold", 30.0)
	scene.hud_layer.show_banner("Ambush!", "The dead pour from both verges")
	scene.hud_layer.toast("Slow down: the dead are close", "warn")
	scene.legend_t = RaidHud.LEGEND_HOLD
	scene.paused = true
	if news:
		scene.hud_layer.open_news(true)
	for i in 3:
		scene.hud_layer.refresh()
		await TutorialKit.settle()
	return {"main": main, "scene": scene}


func _check_inside(rects: Dictionary, w: int, h: int, label: String) -> void:
	var win := Rect2(0, 0, w, h)
	for k in rects:
		if rects[k].size == Vector2.ZERO:
			continue
		check(win.encloses(rects[k].grow(-0.5)), "%s: the %s is inside the window: %s" % [label, k, str(rects[k])])


func test_nothing_overlaps_at_any_window_size_with_everything_showing() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1])
		var h = ctx.scene.hud_layer
		var rects := _hud_rects(h)
		var label := "%d x %d" % [size[0], size[1]]
		var tight: bool = size[0] < RaidHud.WIDE_W and size[1] < RaidHud.COMPACT_H
		for k in ["place", "road", "cards", "radio", "ammo", "base", "event", "call"] + ([] if tight else ["banner"]):
			check(rects.has(k) and rects[k].size != Vector2.ZERO, "%s: the %s shows" % [label, k])
		if tight:
			check(rects.banner.size == Vector2.ZERO, "%s: a short, narrow window gives the banner up while a card is open" % label)
		check(h.event_note.visible and not h.toast_panel.visible, "%s: the toast that was up when the card opened is a line in the card" % label)
		if size[0] >= RaidHud.WIDE_W:
			check(rects.log.size != Vector2.ZERO and rects.legend.size != Vector2.ZERO, "%s: the log and the legend show in a wide window" % label)
		eq(Kit.overlaps(rects), [], label)
		_check_inside(rects, size[0], size[1], label)
		await _leave(ctx.main)


func test_nothing_overlaps_with_the_news_open_either() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1], true)
		var h = ctx.scene.hud_layer
		var rects := _hud_rects(h)
		var label := "%d x %d with the News" % [size[0], size[1]]
		check(rects.has("news") and rects.news.size != Vector2.ZERO, "%s: the News is up" % label)
		if size[0] < RaidHud.WIDE_W:
			# a narrow window: the log is in the verbs' place, so the radio's body goes while it is up
			rects["radio_head"] = Rect2(rects.radio.position, Vector2(rects.radio.size.x, minf(rects.radio.size.y, 44.0)))
			rects.erase("radio")
		eq(Kit.overlaps(rects), [], label)
		_check_inside(rects, size[0], size[1], label)
		await _leave(ctx.main)


func test_the_prompt_pill_fits_too_and_so_does_a_stop_with_no_card_and_a_toast_over_it() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1], false, false)
		var h = ctx.scene.hud_layer
		var rects := _hud_rects(h)
		var label := "%d x %d with the pill" % [size[0], size[1]]
		check(rects.prompt.size != Vector2.ZERO, "%s: the pill shows" % label)
		check(rects.event.size == Vector2.ZERO, "%s: and the card does not" % label)
		check(rects.toast.size != Vector2.ZERO, "%s: with no card the toast is a board of its own" % label)
		eq(Kit.overlaps(rects), [], label)
		_check_inside(rects, size[0], size[1], label)
		await _leave(ctx.main)


func test_the_gauges_are_beside_the_ammunition_when_there_is_room_and_under_it_when_not() -> void:
	var wide: Dictionary = await _busy(1280, 800)
	var hw = wide.scene.hud_layer
	check(hw.roomy_box.visible and not hw.mini_box.visible, "1280: the dial and its columns")
	check(Kit.rect(hw.roomy_box).position.x > Kit.rect(hw.ammo_col).end.x - 0.5, "beside the ammunition: %s of %s" % [str(Kit.rect(hw.roomy_box)), str(Kit.rect(hw.ammo_col))])
	await _leave(wide.main)
	var narrow: Dictionary = await _busy(700, 700)
	var hn = narrow.scene.hud_layer
	check(hn.mini_box.visible and not hn.roomy_box.visible, "700: three short columns")
	check(Kit.rect(hn.mini_box).position.y >= Kit.rect(hn.ammo_col).end.y - 0.5, "under the ammunition")
	await _leave(narrow.main)


func _small_text(node: Node, out: Array = []) -> Array:
	if node is Label or node is Button:
		var size: int = node.get_theme_font_size("font_size")
		if size < Fonts.MIN_PX:
			out.append("%s '%s' is %d px" % [node.get_class(), str(node.get("text")), size])
	for c in node.get_children():
		_small_text(c, out)
	return out


func test_no_text_is_under_twelve_pixels_at_any_window_size() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1], true)
		eq(_small_text(ctx.scene.hud_layer), [], "%d x %d" % [size[0], size[1]])
		await _leave(ctx.main)
	check(DriveHud.SpeedDial.new().get_class() == "Control", "(the dial draws its words at 12 and 22 px: see its _draw)")
	var drawn := FileAccess.get_file_as_string("res://scripts/drive/drive_hud.gd")
	var bad: Array = []
	for m in RegEx.create_from_string("draw_string\\([^\\n]*?, (\\d+), ").search_all(drawn):
		if int(m.get_string(1)) < Fonts.MIN_PX:
			bad.append(m.get_string())
	eq(bad, [], "no drawn word is under 12 px")


func test_every_label_reads_on_its_board() -> void:
	var ctx: Dictionary = await _busy(1280, 800, true)
	var text_check = HudText.new()
	var worst := 99.0
	var worst_what := ""
	var labels: Array = []
	_labels_under(ctx.scene.hud_layer, labels)
	for l in labels:
		if not l.is_visible_in_tree() or String(l.text) == "":
			continue
		var ratio: float = text_check._worst_contrast(l, l.get_theme_color("font_color"), Color.WHITE)
		if ratio < worst:
			worst = ratio
			worst_what = "'%s'" % l.text
	check(worst >= HudText.AA, "the faintest word, %s, reads at %.2f:1" % [worst_what, worst])
	var board: Color = HudText.over(Hud.PANEL, Color.WHITE)
	for pair in [["INK", Hud.INK], ["INK2", Hud.INK2]]:
		check(HudText.contrast(pair[1], board) >= HudText.AA, "the words drawn on the dial and in the ring (%s) read" % pair[0])
	await _leave(ctx.main)


func _labels_under(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node)
	for c in node.get_children():
		_labels_under(c, out)


func _buttons_under(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_buttons_under(c, out)


func test_no_control_takes_focus_and_every_disabled_one_says_why() -> void:
	for size in [[1280, 800], [700, 560]]:
		var ctx: Dictionary = await _busy(size[0], size[1], true)
		var scene = ctx.scene
		var buttons: Array = []
		_buttons_under(scene.hud_layer, buttons)
		var disabled := 0
		for b in buttons:
			eq(b.focus_mode, Control.FOCUS_NONE, "%d: '%s' takes no focus" % [size[0], b.text])
			if b.disabled:
				disabled += 1
				check(b.tooltip_text != "", "%d: the disabled '%s' has a tooltip" % [size[0], b.text])
		check(disabled >= 2, "(the refused choice and All back are the disabled ones: %d)" % disabled)
		await _leave(ctx.main)


func test_resizing_the_window_lays_the_drive_out_again() -> void:
	var ctx: Dictionary = await _busy(1280, 800)
	var h = ctx.scene.hud_layer
	check(h.roomy_box.visible, "wide: the dial")
	TutorialKit.resize(700, 700)
	await TutorialKit.settle()
	h.refresh()
	await TutorialKit.settle()
	h.refresh()
	await TutorialKit.settle()
	check(h.mini_box.visible and not h.roomy_box.visible, "narrow: the columns")
	eq(Kit.overlaps(_hud_rects(h)), [], "and nothing overlaps")
	TutorialKit.resize(1280, 800)
	await TutorialKit.settle()
	h.refresh()
	await TutorialKit.settle()
	h.refresh()
	check(h.roomy_box.visible, "wide again: the dial is back")
	eq(Kit.overlaps(_hud_rects(h)), [], "and nothing overlaps")
	await _leave(ctx.main)


# ------------------------------------------------------ with the real drive scene --
# (scripts/drive/drive_scene.gd mounts this HUD itself: the names above are the ones it answers to)

## A live trip to the pharmacy begun over `main` (as tests/test_drive_scene.gd makes one): the first `n` of the crew in a pickup.
func _trip(main: Node, kind: String = "pickup", n: int = 2) -> Dictionary:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = true
	var sim = main.sim
	sim.vehicles.fuel = 60.0
	sim.waves.enabled = false
	sim.town.reveal("pharmacy")
	var vid := ""
	if kind != "":
		vid = String(sim.vehicles.add(kind).id)
	var party: Array = []
	for i in n:
		party.append(sim.people[i])
	var flow = PlaceFlow.new(sim)
	check(flow.begin(party, "pharmacy", vid), "the trip begins: %s" % flow.error)
	flow.live = true
	var place: Dictionary = sim.town.place("pharmacy")
	var scene := DriveScene.new()
	scene.no_events = true
	main.add_child(scene)
	scene.set_process(false)
	var maker := func(size: int, by_vehicle: bool) -> Dictionary: return SiteGen.make(place, 5, size, by_vehicle)
	scene.setup_trip(main, main.hud, main.data, flow, place, maker, party, float(sim.stock.ammo), kind, 1.0, false)
	scene.begin_trip(flow)
	return {"scene": scene, "flow": flow, "sim": sim}


## The HUD refreshed a few times with the engine's frames between, as the scene's own frames do (a label's wrapped height settles a frame late).
func _settled(h) -> void:
	for i in 3:
		h.refresh()
		await TutorialKit.settle()


func _real_leave(main: Node) -> void:
	PlaceFlow.live_enabled = true
	PlaceFlow.no_events = false
	DriveScene.stand_ins = {}
	await TutorialKit.leave(main)


func _play(scene: Node, seconds: float) -> void:
	for i in int(seconds * 30.0):
		scene.tick(1.0 / 30.0)


func test_the_real_scene_mounts_this_hud_and_the_gauges_follow_its_car() -> void:
	var main := _game()
	var t := _trip(main)
	var scene = t.scene
	var h = scene.hud_layer
	eq(h.get_script().resource_path, "res://scripts/drive/drive_hud.gd", "the scene's HUD is the drive's")
	_play(scene, 4.0)
	scene.stage("speed:1.0")
	scene.autopilot = false
	await _settled(h)
	var words: Dictionary = h.gauge_words()
	eq(words.speed, "Cruising", "at cruising speed: %s" % words.speed)
	check(String(words.fuel).begins_with("Fuel "), "the trip tank: %s" % words.fuel)
	check(String(words.hp).begins_with("Pickup "), "the pickup's condition: %s" % words.hp)
	near(h.route_bar.value, scene.road_progress(), 0.0001, "the road's bar is the car's progress")
	check(["On time", "Ahead", "Behind"].any(func(w): return String(words.delta).begins_with(w)), "the clock: %s" % words.delta)
	eq(h.line_label.text.begins_with("Drive to"), true, "the line under the road's name says what to do: %s" % h.line_label.text)
	eq(Kit.overlaps(_hud_rects(h)), [], "and nothing overlaps")
	check(h._hide_for_drive(), "the squad is aboard: its verbs are off")
	await _real_leave(main)


func test_a_real_stop_opens_its_card_with_the_options_the_rules_give_and_a_choice_closes_it() -> void:
	var main := _game()
	var t := _trip(main)
	var scene = t.scene
	var h = scene.hud_layer
	scene.stage("event:wreck_supplies@0.3+at:0.25")
	scene.autopilot = false
	scene.car.speed = 0.0
	scene.tick(1.0 / 30.0)
	h.refresh()
	await TutorialKit.settle()
	check(h.prompt_panel.visible, "the pill: %s" % h.prompt_text())
	check(h.prompt_text().begins_with("E  Stop:"), "it asks for E: %s" % h.prompt_text())
	scene.press_stop()
	await _settled(h)
	check(h.event_panel.visible, "the card is up")
	eq(h.event_title.text, "A wreck by the road", "the def's title")
	var opts: Array = h.event_options()
	eq(opts.size(), 2, "Search it and Drive on")
	eq(opts[1].auto, true, "Drive on is the default")
	check(h.event_buttons[1].ring != null and h.event_buttons[1].ring.visible, "its ring runs")
	check(not scene.paused, "nothing is paused")
	var r: Dictionary = h.press_option(1)
	eq(r.ok, true, "Drive on")
	h.refresh()
	check(not h.event_panel.visible, "the card is gone")
	await _real_leave(main)


func test_a_real_refusal_is_on_the_card_with_its_reason() -> void:
	var main := _game()
	var t := _trip(main, "pickup", 2)
	var scene = t.scene
	var h = scene.hud_layer
	# a checkpoint: Trade needs 20 scrap and a run needs a vehicle; with no scrap in the stores the trade is refused
	t.sim.stock.scrap = 0.0
	scene.stage("event:checkpoint@0.3+at:0.25")
	scene.autopilot = false
	scene.car.speed = 0.0
	scene.tick(1.0 / 30.0)
	scene.press_stop()
	await _settled(h)
	check(h.event_panel.visible, "the checkpoint's card is up")
	var opts: Array = h.event_options()
	eq(opts.size(), 4, "pay, trade, talk, run: four choices (keys 1 to 4)")
	var refused := 0
	for i in opts.size():
		if opts[i].disabled:
			refused += 1
			check(String(opts[i].why) != "", "'%s' is refused with a reason: %s" % [opts[i].text, opts[i].why])
			check(h.event_buttons[i].button.disabled and h.event_buttons[i].button.tooltip_text == String(opts[i].why), "its tooltip is the reason")
	check(refused >= 1, "something is refused (%d)" % refused)
	check(h.event_rows.columns == 2, "four choices stand two by two")
	eq(Kit.overlaps(_hud_rects(h)), [], "and nothing overlaps")
	await _real_leave(main)


func test_the_real_scene_ends_its_leg_into_the_place_and_the_hud_follows() -> void:
	var main := _game()
	var t := _trip(main)
	var scene = t.scene
	var h = scene.hud_layer
	h.refresh()
	check(h.route_box.visible and not h.bags_box.visible, "the road is where the bags are")
	scene.stage("end")
	var guard := 0
	while scene.leg != "place" and guard < 600:
		scene.tick(1.0 / 30.0)
		guard += 1
	eq(scene.leg, "place", "the place is next")
	h.refresh()
	await TutorialKit.settle()
	eq(h.place_label.text, String(scene.site.name), "the place's name")
	check(not h.route_box.visible and h.bags_box.visible, "the bags are back")
	check(not h.roomy_box.visible and not h.mini_box.visible, "no gauges in the place")
	eq(h.cards.size(), scene.run.squad.size(), "a card for each of the squad that is on this stage")
	check(not h._hide_for_drive(), "the verbs are the place's")
	check(h.legend_text().contains("W A S D walk"), "and the legend: %s" % h.legend_text())
	await _real_leave(main)


func test_the_real_scene_fits_at_every_window_size() -> void:
	for size in SIZES:
		var main := _game(size[0], size[1], 5)
		var t := _trip(main, "pickup", 2)
		var scene = t.scene
		var h = scene.hud_layer
		scene.stage("event:survivor@0.3+at:0.25")
		scene.autopilot = false
		scene.car.speed = 0.0
		scene.tick(1.0 / 30.0)
		scene.press_stop()
		scene.hud_layer.show_banner("Ambush!", "The dead pour from both verges")
		await _settled(h)
		var rects := _hud_rects(h)
		var label := "%d x %d" % [size[0], size[1]]
		check(h.event_panel.visible, "%s: the survivor's card is up" % label)
		eq(Kit.overlaps(rects), [], label)
		_check_inside(rects, size[0], size[1], label)
		eq(_small_text(h), [], "%s: nothing under 12 px" % label)
		await _real_leave(main)
