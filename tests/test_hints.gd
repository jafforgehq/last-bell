extends "res://tests/case.gd"
## The tips of a normal run (scripts/ui/hints.gd, assets/data/hints.json): the data, what sets each
## one off, and the card on the real game scene: once each, one at a time, never in the way.

const Tut := preload("res://tests/tutorial_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Hints := preload("res://scripts/ui/hints.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Prefs := preload("res://scripts/prefs.gd")


# ----------------------------------------------------------------------- data --

func test_the_tips_file_is_valid_and_every_tip_is_short_and_known() -> void:
	var list := Hints.load_hints()
	check(list.size() >= 6, "a handful of tips: %d" % list.size())
	var ids := {}
	var table := Conditions.registry()
	for h in list:
		var id := String(h.get("id", ""))
		check(id != "" and not ids.has(id), "unique ids: %s" % id)
		ids[id] = true
		check(String(h.get("title", "")) != "" and String(h.title).length() <= 28, "%s has a short title" % id)
		var n := Coach.words(String(h.get("text", "")))
		check(n >= 8 and n <= Coach.MAX_WORDS, "%s has %d words" % [id, n])
		var start: Dictionary = h.get("start", {})
		check(table.has(String(start.get("cond", ""))), "%s: its trigger '%s' is a condition" % [id, start.get("cond", "")])
		for name in h.get("anchor", []):
			check(String(name) == "clock" or String(name) == "stores" or String(name).begins_with("stores.") or String(name) == "build" or String(name) == "town", "%s: '%s' is a part of the HUD that is always there" % [id, name])
		check(not Prefs.DEFAULTS.flags.has("hint_%s" % id), "%s starts unseen" % id)


# ------------------------------------------------------------------- triggers --

func _holds(h_id: String, sim) -> bool:
	for h in Hints.load_hints():
		if String(h.id) == h_id:
			return Conditions.check(h.start, sim, {})
	return false


func test_each_tip_is_set_off_by_what_it_is_about() -> void:
	var g := Helpers.make(5, 1)
	var sim = g.sim
	for id in ["dusk", "stores", "ammo", "wound", "fever", "breach", "runner", "brute", "build"]:
		check(not _holds(id, sim), "%s: not at the start of a run" % id)
	# dusk: the bell
	Helpers.run_to_hour(sim, 19.2)
	check(_holds("dusk", sim), "dusk: once the bell has rung")
	# stores: under two days of food or water
	sim.stock.food = 20.0
	check(not _holds("stores", sim), "stores: about three days of food is not low")
	sim.stock.food = 9.0
	check(_holds("stores", sim), "stores: a day and a half is")
	sim.stock.food = 100.0
	sim.stock.water = 5.0
	check(_holds("stores", sim), "stores: or of water")
	# ammo
	sim.stock.ammo = 70.0
	check(not _holds("ammo", sim), "ammo: seventy rounds is plenty")
	sim.stock.ammo = 40.0
	check(_holds("ammo", sim), "ammo: forty is not")
	# a wound and a fever
	var ruth = sim.people[0]
	sim.medical.add_wound(ruth, "scratch")
	check(_holds("wound", sim), "wound: someone bleeds")
	ruth.bleeding = 0.0
	check(not _holds("wound", sim), "wound: and does not")
	ruth.infected_at = 1.0
	sim.clock_min = 700.0
	check(_holds("fever", sim), "fever: an infection of eleven hours shows")
	# a wall down
	var seg = sim.segments[3]
	sim._damage_segment(seg, seg.hp + 1.0)
	check(_holds("breach", sim), "breach: a wall piece is down")
	# runners and brutes
	sim.spawn(30.0, 5.0, "approach", "runner")
	check(_holds("runner", sim) and not _holds("brute", sim), "runner: a runner is about, a brute is not")
	sim.spawn(32.0, 5.0, "approach", "brute")
	check(_holds("brute", sim), "brute: and then a brute")
	g.world.free()


## The tip about building: from the third day, with 30 scrap in the stores and nothing built or going up.
func test_the_build_tip_comes_from_the_third_day_with_the_scrap_and_nothing_built() -> void:
	var g := Helpers.make(5, 1)
	var sim = g.sim
	sim.day = 3
	sim.stock.scrap = 60.0
	check(_holds("build", sim), "day 3, 60 scrap, nothing built: it is time")
	sim.day = 2
	check(not _holds("build", sim), "not on the second day")
	sim.day = 9
	check(_holds("build", sim), "and on any day after")
	sim.stock.scrap = 29.0
	check(not _holds("build", sim), "not with 29 scrap")
	sim.stock.scrap = 30.0
	check(_holds("build", sim), "with 30 it is")
	sim.stock.scrap = 60.0
	check(sim.build.order("south_east_corner", "salvage_bench"), "(a site is ordered)")
	sim.stock.scrap = 60.0
	check(not _holds("build", sim), "not once something is going up: the player has found the screen")
	sim.build.cancel("south_east_corner")
	sim.stock.scrap = 60.0
	check(_holds("build", sim), "a cancelled one has built nothing")
	sim.build.plot("junk_corner").building = "workshop"
	check(not _holds("build", sim), "not once something stands")
	for h in Hints.load_hints():
		if String(h.id) == "build":
			eq(h.get("anchor", []), ["build"], "it points at the toolbar's hammer")
			check(String(h.text).contains("N") and String(h.text).contains("salvage bench"), "and says the key and what to build first: %s" % h.text)
	g.world.free()


func test_the_build_tip_comes_last_so_that_it_never_hides_a_warning() -> void:
	var list := Hints.load_hints()
	eq(String(list[list.size() - 1].id), "build", "the last of the tips: the first whose moment has come is the one shown")


# ------------------------------------------------------------------- the card --

## A normal run on the real scene with the tips armed (the tests run headless, where they are not).
func _run() -> Node:
	var main = Tut.start({"difficulty": 1, "seed": 5})
	return main


func _tips_on(main) -> void:
	main.hints.armed = true
	main.sim.t = 60.0


func test_a_normal_run_has_tips_and_the_tutorial_does_not() -> void:
	var main = _run()
	await Tut.frames(main, 3)
	check(main.hints != null and main.coach == null, "a normal run has the tips")
	check(not main.hints.armed, "quiet in a headless run, so the tests never write the player's flags")
	await Tut.leave(main)
	var tut = Tut.game()
	await Tut.frames(tut, 3)
	check(tut.hints == null, "the tutorial has none")
	await Tut.leave(tut)


func test_a_tip_comes_once_with_a_ring_and_goes_when_it_is_read() -> void:
	var main = _run()
	await Tut.frames(main, 3)
	_tips_on(main)
	var hints = main.hints
	var speed_before: int = main.speed
	main.sim.stock.ammo = 40.0
	await Tut.frames(main, 40)
	eq(hints.shown_id(), "ammo", "the ammo tip is up")
	check(Prefs.flag("hint_ammo"), "and is marked as shown the moment it was")
	check(hints.card.visible, "its card is on the screen")
	check(hints.target_rect.size.x > 0.0, "with the Ammo row lit")
	var card: Rect2 = hints.card.get_global_rect()
	var vp: Vector2 = main._vp()
	check(Rect2(Vector2.ZERO, vp).grow(1.0).encloses(card), "inside the window (%s in %s)" % [str(card), str(vp)])
	check(not card.intersects(hints.target_rect), "and off what it lights")
	eq(main.speed, speed_before, "it did not touch the speed")
	check(main._allows("gizmo", "post") and main._allows("speed", 3) and not hints.card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "and locked nothing")
	hints.ok_button.pressed.emit()
	await Tut.frames(main, 4)
	eq(hints.shown_id(), "", "Got it takes it away")
	check(not hints.card.visible, "the card is gone")
	# the same thing again, and nothing comes
	main.sim.stock.ammo = 30.0
	await Tut.frames(main, 40 + 45 * 30)
	eq(hints.shown_id(), "", "the same tip does not come twice")
	await Tut.leave(main)


func test_the_build_tip_lights_the_hammer_and_comes_once() -> void:
	var main = _run()
	await Tut.frames(main, 3)
	_tips_on(main)
	var hints = main.hints
	main.sim.day = 3
	main.sim.stock.scrap = 45.0
	await Tut.frames(main, 40)
	eq(hints.shown_id(), "build", "the build tip is up")
	check(Prefs.flag("hint_build"), "and is marked as shown the moment it was")
	check(hints.target_rect.size.x > 0.0 and hints.target_rect == main.hud.anchor_rect("build"), "with the toolbar's hammer lit: %s" % str(hints.target_rect))
	var card: Rect2 = hints.card.get_global_rect()
	check(Rect2(Vector2.ZERO, main._vp()).grow(1.0).encloses(card) and not card.intersects(hints.target_rect), "inside the window and off what it lights")
	check(hints.text_label.text.begins_with("The crew can build now. Press N"), "saying what the key does: '%s'" % hints.text_label.text)
	hints.ok_button.pressed.emit()
	await Tut.frames(main, 4)
	eq(hints.shown_id(), "", "Got it takes it away")
	await Tut.frames(main, 40 + 45 * 30)
	eq(hints.shown_id(), "", "the same thing again, and nothing comes: once is all")
	await Tut.leave(main)


func test_one_at_a_time_and_not_too_often() -> void:
	var main = _run()
	await Tut.frames(main, 3)
	_tips_on(main)
	var hints = main.hints
	main.sim.stock.ammo = 40.0
	main.sim.stock.food = 5.0
	await Tut.frames(main, 40)
	eq(hints.shown_id(), "stores", "the first of the tips in the file whose moment has come")
	for i in 90:
		hints.tick(0.5)
	# it stayed its twenty-five seconds and went by itself
	eq(hints.shown_id(), "", "a tip goes by itself after a while")
	check(hints.quiet_s > 0.0, "and the next waits its turn")
	for i in 20:
		hints.tick(0.5)
	eq(hints.shown_id(), "", "ten seconds on, still quiet")
	var waited := 0.0
	while hints.shown_id() == "" and waited < 60.0:
		hints.tick(0.5)
		waited += 0.5
	eq(hints.shown_id(), "ammo", "the second one comes when the wait is over")
	check(waited > 10.0 and waited < 25.0, "after the rest of the forty-five seconds: %.1f" % waited)
	await Tut.leave(main)


func test_a_tip_does_not_come_too_soon_or_into_a_menu_or_when_it_is_off() -> void:
	var main = _run()
	await Tut.frames(main, 3)
	var hints = main.hints
	hints.armed = true
	main.sim.stock.ammo = 40.0
	# the first twenty seconds of a run
	main.sim.t = 5.0
	for i in 6:
		hints.tick(0.5)
	eq(hints.shown_id(), "", "not in the first twenty seconds")
	main.sim.t = 60.0
	# under the scavenging dialog
	Bot.card_click(main, "ana")
	main._key(KEY_G)
	check(main.hud.scavenge_dialog != null, "(the dialog is open)")
	for i in 6:
		hints.tick(0.5)
	eq(hints.shown_id(), "", "not over a dialog")
	main.hud.scavenge_dialog.cancel()
	await Tut.frames(main, 2)
	# the setting
	Prefs.set_value("ui", "hints", false)
	for i in 6:
		hints.tick(0.5)
	eq(hints.shown_id(), "", "not when the settings have tips off")
	check(not Prefs.flag("hint_ammo"), "and nothing is marked as shown")
	Prefs.set_value("ui", "hints", true)
	for i in 6:
		hints.tick(0.5)
	eq(hints.shown_id(), "ammo", "back on, it comes")
	# the card turns them off for good
	hints.off_button.pressed.emit()
	check(not Prefs.on("ui", "hints"), "Turn tips off sets the setting")
	eq(hints.shown_id(), "", "and takes the card away")
	main.sim.stock.food = 5.0
	for i in 200:
		hints.tick(0.5)
	eq(hints.shown_id(), "", "no more come")
	await Tut.leave(main)


func test_a_tip_that_is_up_hides_while_a_menu_is_over_the_game() -> void:
	var main = _run()
	await Tut.frames(main, 3)
	_tips_on(main)
	main.sim.stock.ammo = 40.0
	await Tut.frames(main, 40)
	var hints = main.hints
	eq(hints.shown_id(), "ammo", "a tip is up")
	main.open_pause()
	await Tut.frames(main, 4)
	check(main.menu_open, "(the pause menu is open)")
	check(not hints.card.visible, "the card gives way to it")
	main.shell.close_all()
	main.resume()
	await Tut.frames(main, 6)
	check(hints.card.visible, "and is back when it is shut")
	await Tut.leave(main)


func test_every_word_on_a_tip_is_big_enough_and_reads_on_the_panel() -> void:
	var HudText := load("res://tests/test_hud_text.gd")
	var Hud := load("res://scripts/ui/hud.gd")
	var Fonts := load("res://scripts/ui/fonts.gd")
	var main = _run()
	await Tut.frames(main, 3)
	_tips_on(main)
	main.sim.stock.ammo = 40.0
	await Tut.frames(main, 40)
	var hints = main.hints
	eq(hints.shown_id(), "ammo", "a tip is up")
	var worst: Color = HudText.over(Hud.PANEL, Color.WHITE)
	for n in [hints.title_label, hints.text_label, hints.off_button, hints.ok_button]:
		var px: int = n.get_theme_font_size("font_size")
		check(px >= Fonts.MIN_PX, "'%s' is %d px" % [n.text, px])
		var colour: Color = n.get_theme_color("font_color")
		if n == hints.ok_button:
			check(HudText.contrast(colour, Hud.ACCENT) >= HudText.AA, "'%s' reads on the gold" % n.text)
		else:
			check(HudText.contrast(colour, Color(Hud.PANEL, 1.0)) >= HudText.AA and HudText.contrast(colour, worst) >= HudText.AA, "'%s' reads on the panel" % n.text)
	await Tut.leave(main)
