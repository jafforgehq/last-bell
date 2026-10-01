extends "res://tests/case.gd"
## The keys and clicks of the night tools in main.gd, on the real game scene (driven by hand
## like test_step_clock does): V flips the fields-of-fire view, L sets the alarm on the
## selected wall section or says why not, B flips auto-repair, a brute is easier to click, and
## the pitch of a groan follows the kind of the dead.

const Tactics := preload("res://scripts/sim/tactics.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Sound := preload("res://scripts/audio/sound.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")

const NORTH_BUS := 3
const DOOR := 14


## What main.gd plays sounds through, written down instead of heard.
class FakeSound:
	extends Node
	var plays: Array = []

	func play(sound_name: String, level: float = 1.0, pitch_var: float = 0.04, pitch_scale: float = 1.0) -> void:
		plays.append({"name": sound_name, "level": level, "var": pitch_var, "pitch": pitch_scale})

	func set_ambience(_night: float, _horde: float, _dt: float) -> void:
		pass

	func set_muted(_m: bool) -> void:
		pass


## How the test window was before the game scene changed it (it fits the window and sets its
## scaling): the tests that click with real input events after these need it back as it was.
var _window := {}


## The real game scene on a fixed seed, in the tree. Its own per-frame work is switched off:
## the tests drive `_process` by hand, so what the real frames' lengths were cannot matter.
func _game():
	var win: Window = Engine.get_main_loop().root
	_window = {"size": win.size, "position": win.position, "mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "scale_size": win.content_scale_size}
	Engine.set_meta("run", {"difficulty": 1, "seed": 7})
	var main = load("res://scenes/main.tscn").instantiate()
	win.add_child(main)
	main.set_process(false)
	return main


func _leave(main: Node) -> void:
	main.queue_free()
	await Engine.get_main_loop().process_frame
	var win: Window = Engine.get_main_loop().root
	win.content_scale_mode = _window.mode
	win.content_scale_aspect = _window.aspect
	win.content_scale_size = _window.scale_size
	win.size = _window.size
	win.position = _window.position


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


# ------------------------------------------------------------------- V --

func test_v_flips_the_fields_view_and_its_button() -> void:
	var main = _game()
	check(not main.fields and not main.hud.fields_on, "off at the start")
	main._key(KEY_V)
	check(main.fields, "V turns the view on")
	check(main.hud.fields_on, "and tells the HUD")
	eq(main.hud.fields_button.get_meta("icon").modulate, Hud.ACCENT, "the button is lit")
	main._key(KEY_V)
	check(not main.fields and not main.hud.fields_on, "V turns it off again")
	eq(main.hud.fields_button.get_meta("icon").modulate, Hud.INK2, "the button is dark")
	# the button does the same as the key
	main.hud.fields_button.pressed.emit()
	check(main.fields and main.hud.fields_on, "a press of the button flips it too")
	await _leave(main)


func test_the_view_changes_nothing_in_the_rules() -> void:
	# the same game, with the view on and off, plays the same
	var fingerprints: Array = []
	for on in [false, true]:
		var main = _game()
		if on:
			main._key(KEY_V)
		main.sim.minutes = 19.0 * 60.0
		main.sim.phase = main.sim.phase_at(main.sim.minutes)
		for i in 600:
			main._process(1.0 / 30.0)
			# now and then the frame ends, and the overlay draws what it was asked to
			if i % 100 == 99:
				await Engine.get_main_loop().process_frame
		var sim = main.sim
		var fp := "%d|%d|%.3f|%.3f" % [sim.zombies.size(), sim.kills, sim.stock.ammo, sim.stock.scrap]
		for p in sim.people:
			fp += "|%.3f,%.3f" % [p.x, p.y]
		fingerprints.append(fp)
		await _leave(main)
	eq(fingerprints[1], fingerprints[0], "with the view on or off")


## Two game hours of the real game from just before the lookout speaks, the view on: the
## forecast turns up in the clock and as an arrow at the map's edge, and the alarm, set by the
## key later on, is drawn with its time. (The test window is tiny, so the camera is pointed at
## each thing in turn: what is out of the window is not drawn.)
func test_an_evening_with_the_view_on_shows_the_forecast_and_the_alarm() -> void:
	var main = _game()
	var sim = main.sim
	main._key(KEY_V)
	sim.minutes = 16.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.clock_min = fposmod(sim.minutes - 420.0, 1440.0)
	sim.stock.scrap = 20.0
	var tree := Engine.get_main_loop()
	var most_arrows := 0
	var saw_alarm := false
	var line := ""
	var seg = sim.segments[NORTH_BUS]
	for i in 1200:
		main._process(1.0 / 30.0)
		if i == 300:
			# he has spoken (17:00 is about step 180): look at the first of the places he named
			main._focus(sim.tactics.forecast().spawns[0])
		if i == 600:
			main._select({"kind": "segment", "ref": seg})
			main._key(KEY_L)
			main._focus(OverlayNode.alarm_anchor(seg))
		if i % 60 == 59:
			await tree.process_frame
			await tree.process_frame
			if i < 600:
				most_arrows = maxi(most_arrows, main.overlay.drawn_spawns)
			else:
				saw_alarm = saw_alarm or main.overlay.drew_alarm
			if main.hud.forecast_label.visible:
				line = main.hud.forecast_label.text
	check(sim.tactics.forecast().get("given", false), "the lookout has spoken")
	check(line.begins_with("Tonight: about ") or line.begins_with("The last night"), "the clock carries his forecast: '%s'" % line)
	check(most_arrows >= 1, "an arrow was drawn where the dead come in: %d" % most_arrows)
	check(sim.tactics.lure_seg() == seg, "the alarm rings at the section it was set at")
	check(saw_alarm, "and was drawn")
	await _leave(main)


# ------------------------------------------------------------------- L --

func test_l_sets_the_alarm_on_the_selected_section() -> void:
	var main = _game()
	var sim = main.sim
	var seg = sim.segments[NORTH_BUS]
	sim.stock.scrap = 20.0
	main._select({"kind": "segment", "ref": seg})
	main._key(KEY_L)
	eq(sim.tactics.lure_seg(), seg, "the alarm rings at the selected section")
	near(float(sim.stock.scrap), 20.0 - Tactics.LURE_COST, 0.001, "and its scrap is paid")
	await _leave(main)


func test_l_says_why_when_the_alarm_cannot_be_set() -> void:
	var main = _game()
	var sim = main.sim
	var seg = sim.segments[NORTH_BUS]
	sim.stock.scrap = 20.0
	main._select({"kind": "segment", "ref": seg})
	main._key(KEY_L)
	# a second one while the first rings
	var scrap_after: float = sim.stock.scrap
	main._key(KEY_L)
	var why: String = sim.tactics.why_not_lure(seg)
	check(why != "", "the rules refuse it: '%s'" % why)
	check(main.hud.toast_panel.visible, "and a toast says so")
	eq(main.hud.toast_label.text, "Not now: " + why, "with the rules' own reason")
	eq(main.hud.toast_label.get_theme_color("font_color"), Hud.TOAST_COLOR.warn, "as a warning")
	near(float(sim.stock.scrap), scrap_after, 0.001, "nothing is paid for a refusal")
	# no scrap
	sim.tactics.lure_id = -1
	sim.stock.scrap = 1.0
	main._key(KEY_L)
	check(main.hud.toast_label.text.begins_with("Not now: ") and main.hud.toast_label.text.contains("scrap"), "short of scrap: '%s'" % main.hud.toast_label.text)
	# a school door
	sim.stock.scrap = 20.0
	main._select({"kind": "segment", "ref": sim.segments[DOOR]})
	main._key(KEY_L)
	check(main.hud.toast_label.text.begins_with("Not now: "), "a door: '%s'" % main.hud.toast_label.text)
	check(sim.tactics.lure_seg() == null, "and no alarm rings")
	await _leave(main)


func test_l_without_a_wall_selected_asks_for_one() -> void:
	var main = _game()
	var sim = main.sim
	sim.stock.scrap = 20.0
	main._select(null)
	main._key(KEY_L)
	eq(main.hud.toast_label.text, "Click a wall section first", "nothing selected")
	main._select({"kind": "person", "ref": _person(main, "ruth")})
	main.hud.toast_label.text = ""
	main._key(KEY_L)
	eq(main.hud.toast_label.text, "Click a wall section first", "a person selected")
	check(sim.tactics.lure_seg() == null and is_equal_approx(float(sim.stock.scrap), 20.0), "no alarm, no cost")
	await _leave(main)


# ------------------------------------------------------------------- B --

func test_b_flips_auto_repair_for_the_selected_person() -> void:
	var main = _game()
	var sim = main.sim
	var ana = _person(main, "ana")
	main._select({"kind": "person", "ref": ana})
	check(not sim.tactics.auto_repair(ana), "off for the nurse at the start")
	main._key(KEY_B)
	check(sim.tactics.auto_repair(ana), "B turns it on for the selected person")
	main._key(KEY_B)
	check(not sim.tactics.auto_repair(ana), "and off again")
	check(sim.tactics.auto_repair(_person(main, "dez")), "nobody else was touched")
	main._select(null)
	main._key(KEY_B)
	eq(main.hud.toast_label.text, "Click someone first", "with nobody selected it says so")
	await _leave(main)


func test_a_pans_the_view_and_does_not_flip_auto_repair() -> void:
	# A is the camera's key; B is the order's
	var main = _game()
	var ana = _person(main, "ana")
	main._select({"kind": "person", "ref": ana})
	main._key(KEY_A)
	check(not main.sim.tactics.auto_repair(ana), "A leaves auto-repair alone")
	await _leave(main)


# ------------------------------------------------------------------- clicking --

func test_a_brute_is_easier_to_click_than_a_walker_and_a_runner_no_harder() -> void:
	var main = _game()
	var sim = main.sim
	sim.zombies.clear()
	var walker = sim.spawn(30.0, 28.0, "wander", "walker")
	var runner = sim.spawn(33.0, 28.0, "wander", "runner")
	var brute = sim.spawn(36.0, 28.0, "wander", "brute")
	check(main._pick(Vector2(30.5, 28.0)) == null, "half a tile off a walker is a miss")
	var on_brute = main._pick(Vector2(36.5, 28.0))
	check(on_brute != null and on_brute.ref == brute, "but half a tile off a brute is a hit")
	# the box of a runner is no smaller than a walker's
	for pair in [[walker, 30.0], [runner, 33.0]]:
		var near_hit = main._pick(Vector2(pair[1] + 0.41, 28.0))
		check(near_hit != null and near_hit.ref == pair[0], "%s: 0.41 tile off is a hit" % pair[0].kind)
		check(main._pick(Vector2(pair[1] + 0.44, 28.0)) == null, "%s: 0.44 off is a miss" % pair[0].kind)
	# a brute is hit further off, too, but not beyond its own size
	check(main._pick(Vector2(36.0 + 0.42 * 1.4 - 0.02, 28.0)) != null, "a brute is hit out to its own width")
	check(main._pick(Vector2(36.0 + 0.42 * 1.4 + 0.05, 28.0)) == null, "and not beyond it")
	# the head of a brute is higher than a walker's
	check(main._pick(Vector2(36.0, 28.0 - 0.95 * 1.4 + 0.05)) != null, "a click on a brute's tall head hits")
	check(main._pick(Vector2(30.0, 28.0 - 0.95 * 1.4 + 0.05)) == null, "the same click over a walker does not")
	await _leave(main)


func test_a_person_is_picked_as_before() -> void:
	var main = _game()
	var ruth = _person(main, "ruth")
	var hit = main._pick(Vector2(ruth.x, ruth.y - 0.3))
	check(hit != null and hit.kind == "person" and hit.ref == ruth, "a click on Ruth selects her")
	check(main._pick(Vector2(ruth.x + 0.5, ruth.y)) == null, "half a tile off is still a miss for a person")
	await _leave(main)


# ------------------------------------------------------------------- sounds --

func test_a_groans_pitch_follows_the_kind_of_the_dead() -> void:
	var main = _game()
	var sim = main.sim
	main.sound.queue_free()
	var fake := FakeSound.new()
	main.sound = fake
	main.add_child(fake)
	var at: Vector2 = main.cam_center + Vector2(40.0, 0.0)
	for kind in ["walker", "runner", "brute"]:
		for i in 200:
			sim.events.append({"type": "groan", "x": at.x, "y": at.y, "kind": kind})
	# an event from before the kinds had one
	for i in 200:
		sim.events.append({"type": "groan", "x": at.x, "y": at.y})
	main._handle_events()
	var by_kind := {}
	for p in fake.plays:
		eq(p.name, "groan", "only groans were played")
		var key := "%.2f" % p.pitch
		by_kind[key] = p
	check(fake.plays.size() > 100, "a good many played (about 60%% of 800): %d" % fake.plays.size())
	check(by_kind.has("0.72"), "a brute's groan is played at 0.72")
	check(by_kind.has("1.30"), "a runner's at 1.3")
	check(by_kind.has("1.00"), "a walker's, and one with no kind, at the normal pitch")
	eq(by_kind.keys().size(), 3, "and no other pitch: %s" % str(by_kind.keys()))
	# a brute is louder than a walker from the same place
	check(by_kind["0.72"].level > by_kind["1.00"].level, "and a little louder: %.2f against %.2f" % [by_kind["0.72"].level, by_kind["1.00"].level])
	check(by_kind["1.30"].level <= by_kind["1.00"].level + 0.0001, "a runner is not louder")
	await _leave(main)


func test_the_alarm_rings_a_bell_when_it_is_set() -> void:
	var main = _game()
	main.sound.queue_free()
	var fake := FakeSound.new()
	main.sound = fake
	main.add_child(fake)
	main.sim.events.clear()
	main.sim.events.append({"type": "lure", "seg": NORTH_BUS})
	main._handle_events()
	eq(fake.plays.size(), 1, "one sound")
	eq(fake.plays[0].name, "bell", "a bell")
	check(fake.plays[0].pitch > 1.0, "higher than the dusk bell")
	await _leave(main)


func test_the_player_moves_the_pitch_by_the_scale_and_keeps_the_old_calls_working() -> void:
	var s := Sound.new()
	Engine.get_main_loop().root.add_child(s)
	s.setup({"groan": ["res://assets/audio/groan_0.wav"]})
	check(s.streams.has("groan") and s.streams.groan.size() == 1, "the groan loaded")
	s.play("groan", 1.0, 0.0, 0.72)
	near(s.players[0].pitch_scale, 0.72, 0.0001, "scaled down for a brute")
	s.play("groan", 1.0, 0.0, 1.3)
	near(s.players[1].pitch_scale, 1.3, 0.0001, "scaled up for a runner")
	s.play("groan", 1.0, 0.0)
	near(s.players[2].pitch_scale, 1.0, 0.0001, "the old call, with no scale, plays at the normal pitch")
	s.play("groan")
	check(absf(s.players[3].pitch_scale - 1.0) <= 0.04 + 0.0001, "and with the default wobble stays round it: %.3f" % s.players[3].pitch_scale)
	for i in 20:
		s.play("groan", 1.0, 0.1, 0.72)
		var p: float = s.players[(4 + i) % s.players.size()].pitch_scale
		check(p >= 0.72 * 0.9 - 0.0001 and p <= 0.72 * 1.1 + 0.0001, "the wobble is round the scaled pitch: %.3f" % p)
	s.muted = true
	var before: int = s.next
	s.play("groan", 1.0, 0.0, 0.72)
	eq(s.next, before, "muted: nothing is played")
	s.free()
