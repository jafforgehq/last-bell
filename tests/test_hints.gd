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
	check(sim.build.order("salvage_bench_home", "salvage_bench"), "(a site is ordered)")
	sim.stock.scrap = 60.0
	check(not _holds("build", sim), "not once something is going up: the player has found the screen")
	sim.build.cancel("salvage_bench_home")
	sim.stock.scrap = 60.0
	check(_holds("build", sim), "a cancelled one has built nothing")
	sim.build.plot("workshop_home").building = "workshop"
	check(not _holds("build", sim), "not once something stands")
	for h in Hints.load_hints():
		if String(h.id) == "build":
			eq(h.get("anchor", []), ["build"], "it points at the toolbar's hammer")
			check(String(h.text).contains("N") and String(h.text).contains("salvage bench"), "and says the key and what to build first: %s" % h.text)
	g.world.free()


func test_the_build_tip_comes_last_so_that_it_never_hides_a_warning() -> void:
	var list := Hints.load_hints()
	eq(String(list[list.size() - 1].id), "build", "the last of the tips: the first whose moment has come is the one shown")


# ------------------------------------------------------- the avatar game's tips (round 22) --

## The tips of the avatar game, from the QA's list (I7): the ring round Ruth nobody had explained, E, a trip and its autopilot, a Big Night.
const AVATAR_TIPS := ["use", "ring", "bignight", "trips"]


func _holds_in(h_id: String, sim, state: Dictionary = {}) -> bool:
	for h in Hints.load_hints():
		if String(h.id) == h_id:
			return Conditions.check(h.start, sim, state)
	return false


func test_the_avatar_tips_are_there_with_words_for_the_avatar_and_come_before_the_build_tip() -> void:
	var list := Hints.load_hints()
	var at := {}
	for i in list.size():
		at[String(list[i].id)] = i
	for id in AVATAR_TIPS:
		check(at.has(id), "the tip '%s' is in the file" % id)
		if not at.has(id):
			continue
		var h: Dictionary = list[int(at[id])]
		check(int(at[id]) < int(at["build"]), "'%s' comes before the build tip (which is last)" % id)
		var words := String(h.get("text_avatar", h.get("text", "")))
		check(Coach.words(words) >= 8 and Coach.words(words) <= Coach.MAX_WORDS, "'%s' says it in %d words" % [id, Coach.words(words)])
	var text := {}
	for h in list:
		text[String(h.id)] = String(h.get("text_avatar", h.get("text", "")))
	check(String(text.get("use", "")).contains("E"), "the E tip names the key: %s" % text.get("use", ""))
	check(String(text.get("ring", "")).to_lower().contains("ring"), "the ring tip says ring: %s" % text.get("ring", ""))
	check(String(text.get("ring", "")).to_lower().contains("shoot"), "and what it is for: %s" % text.get("ring", ""))
	check(String(text.get("bignight", "")).to_lower().contains("big night") and String(text.get("bignight", "")).to_lower().contains("ring"), "the Big Night tip says what it needs and where the crew shoots better: %s" % text.get("bignight", ""))
	check(String(text.get("trips", "")).contains("Tab") and String(text.get("trips", "")).to_lower().contains("autopilot"), "the trip tip names Tab and the autopilot: %s" % text.get("trips", ""))
	check(String(text.get("trips", "")).contains("W A S D") or String(text.get("trips", "")).contains("WASD"), "and how the road is driven: %s" % text.get("trips", ""))


func test_none_of_the_avatar_tips_comes_in_the_old_game() -> void:
	var g := Helpers.make(5, 1)
	var sim = g.sim
	Helpers.at(sim, 9, 22.0)
	for id in AVATAR_TIPS:
		check(not _holds_in(id, sim, {"panel": "map"}), "%s: not without an avatar" % id)
	g.world.free()


func test_the_use_tip_comes_when_something_is_in_reach_of_the_avatar() -> void:
	var g := Helpers.avatar_game(5, 5)
	var sim = g.sim
	var ruth = sim.avatar.player()
	ruth.x = 34.5
	ruth.y = 32.5
	check(sim.interact.candidates().is_empty(), "(nothing is in reach in the open yard)")
	check(not _holds_in("use", sim), "use: not with nothing to use")
	var dez = null
	for p in sim.people:
		if p.id == "dez":
			dez = p
	ruth.x = dez.x + 0.5
	ruth.y = dez.y
	check(not sim.interact.candidates().is_empty(), "(Dez is in reach)")
	check(_holds_in("use", sim), "use: with somebody to talk to it is time to say what E is")
	ruth.downed = true
	check(not _holds_in("use", sim), "use: not while he is down (nothing can be used)")
	g.world.free()


func test_the_ring_tip_comes_at_night_with_the_avatar_up_at_the_base() -> void:
	var g := Helpers.avatar_game(5, 5)
	var sim = g.sim
	var ruth = sim.avatar.player()
	Helpers.at(sim, 2, 14.0)
	check(not _holds_in("ring", sim), "ring: not by day, though the ring is there")
	Helpers.at(sim, 2, 22.0)
	check(_holds_in("ring", sim), "ring: from the bell on")
	ruth.downed = true
	check(not _holds_in("ring", sim), "ring: not while he is down (the ring is not drawn)")
	ruth.downed = false
	ruth.away = {"kind": "party"}
	check(not _holds_in("ring", sim), "ring: nor while he is away on a trip")
	g.world.free()


func test_the_big_night_tip_comes_from_noon_the_day_before() -> void:
	var g := Helpers.avatar_game(5, 5)
	var sim = g.sim
	Helpers.at(sim, 3, 13.0)
	check(not _holds_in("bignight", sim), "bignight: not on an ordinary day")
	Helpers.at(sim, 9, 8.0)
	check(not _holds_in("bignight", sim), "bignight: not in the morning before it")
	Helpers.at(sim, 9, 12.5)
	check(_holds_in("bignight", sim), "bignight: from the noon notice of the day before")
	Helpers.at(sim, 10, 8.0)
	check(_holds_in("bignight", sim), "bignight: all the day of it")
	g.world.free()


func test_the_trips_tip_comes_with_the_map_page_open() -> void:
	var g := Helpers.avatar_game(5, 5)
	var sim = g.sim
	check(not _holds_in("trips", sim, {}), "trips: not with no page open")
	check(not _holds_in("trips", sim, {"panel": "news"}), "trips: not on the News page")
	check(_holds_in("trips", sim, {"panel": "map"}), "trips: on the map page")
	g.world.free()


func test_the_tips_for_the_avatar_come_on_the_real_scene_once_and_the_map_tip_with_the_map() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true})
	await Tut.frames(main, 3)
	_tips_on(main)
	var hints = main.hints
	Prefs.set_flag("hint_town")    # (the Town Board's own tip comes first in the file: it is not the one asked about)
	Prefs.set_flag("hint_use")
	Prefs.set_flag("hint_ring")
	Prefs.set_flag("hint_bignight")
	main.hud.open_radio("map")
	await Tut.frames(main, 40)
	eq(hints.shown_id(), "trips", "the trip tip is up with the map")
	check(String(hints.text_label.text).contains("Tab"), "in the avatar's words: '%s'" % hints.text_label.text)
	check(Prefs.flag("hint_trips"), "and is marked as shown the moment it was")
	hints.ok_button.pressed.emit()
	await Tut.frames(main, 4)
	main.hud.close_radio()
	main.hud.open_radio("map")
	await Tut.frames(main, 40 + 45 * 30)
	eq(hints.shown_id(), "", "and it does not come twice")
	await Tut.leave(main)


func test_the_green_ring_is_explained_on_the_card_of_the_one_who_wears_it() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true})
	await Tut.frames(main, 3)
	var tips := {}
	for c in main.hud.cards:
		main.hud._update_card(c, main.sim)
		tips[String(c.p.id)] = String(c.card.tooltip_text)
	check(String(tips.get("ruth", "")).contains("This is you") and String(tips.get("ruth", "")).contains("The green ring round you: the crew inside it shoots better"), "Ruth's card says what the ring is: '%s'" % tips.get("ruth", ""))
	check(not String(tips.get("dez", "")).contains("green ring"), "and nobody else's does: '%s'" % tips.get("dez", ""))
	await Tut.leave(main)


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
