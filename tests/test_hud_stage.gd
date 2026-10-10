extends "res://tests/case.gd"
## HUD8, THE MINIMAL HUD (scripts/ui/hud_stage.gd): the stage table (which board is on in which phase of the first twenty minutes), the threat rule (when the fight is on, what collapses, when it returns), the
## ghost of a board that lies over a dead one, the HUD setting (Minimal, the default, and Full) and the key that puts the HUD away. The pure rules are tested on their own; then a real town run (the real
## HUD and the real parts) is stepped through the stages and a fight.

const Fakes := preload("res://tests/menu_fakes.gd")
const HudKit := preload("res://tests/hud_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const HudStage := preload("res://scripts/ui/hud_stage.gd")
const Prefs := preload("res://scripts/prefs.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")


func _begin() -> void:
	Prefs.path = "user://prefs_test.cfg"
	Prefs.reset()


# ----------------------------------------------------------------------- the pure rules --

func test_every_part_has_a_form_in_every_phase() -> void:
	for part in HudStage.PARTS:
		check(HudStage.TABLE.has(part), "the table has %s" % part)
		eq((HudStage.TABLE[part] as Array).size(), HudStage.PHASES.size(), "%s has a form for each phase" % part)
		check(HudStage.FULL.has(part), "the full HUD has %s" % part)
	for part in HudStage.THREAT_FORMS:
		check(HudStage.PARTS.has(part), "the threat rule names a part that exists: %s" % part)
	for part in HudStage.RETURN:
		check(HudStage.PARTS.has(part), "so does the order of the return: %s" % part)


func test_the_phase_follows_the_run() -> void:
	eq(HudStage.phase_of({"stage": "arrive"}), "road", "on the road in")
	eq(HudStage.phase_of({"stage": "arrive", "near": true}), "house", "a house to claim is near: the first house")
	eq(HudStage.phase_of({"stage": "alone", "near": false}), "house", "in the house, clearing it")
	eq(HudStage.phase_of({"stage": "cleared"}), "house", "the house is clear and not yet claimed")
	eq(HudStage.phase_of({"stage": "claimed", "crew": 0, "phase": "day"}), "claimed", "claimed, alone")
	eq(HudStage.phase_of({"stage": "growing", "crew": 1, "phase": "day"}), "rescue", "the first rescue")
	eq(HudStage.phase_of({"stage": "fortify", "crew": 2, "phase": "dusk"}), "dusk", "the first dusk")
	eq(HudStage.phase_of({"stage": "fortify", "crew": 2, "phase": "night"}), "night", "the first night")
	eq(HudStage.phase_of({"stage": "fortify", "crew": 2, "phase": "dawn"}), "morning", "the dawn")
	eq(HudStage.phase_of({"stage": "fortify", "crew": 2, "phase": "day", "card": true}), "morning", "the morning card is up")
	eq(HudStage.phase_of({"stage": "alone", "phase": "night", "card": true}), "house", "the road and the house come before the card and the clock")


func test_the_stage_table_is_the_audits() -> void:
	# the opening: the weapon panel and the objective's title line, one arrow, no stores, clock, crew, minimap or legend
	var road := {}
	for part in HudStage.PARTS:
		road[part] = HudStage.form_of(part, "road", false)
	eq(road.weapon, "min", "the weapon panel is the name and the rounds")
	eq(road.objective, "min", "the objective is its title line")
	eq(road.stores, "off", "no stores before the claim")
	eq(road.crew, "off", "no crew cards before the first rescue")
	eq(road.minimap, "off", "no minimap on the road")
	eq(road.clock, "min", "the clock is the day and the hour")
	eq(road.toolbar, "min", "the toolbar is pause, play, the controls and the menu")
	eq(road.edge, "one", "ONE arrow, to the best house")
	eq(road.legend, "off", "the legend of the keys dissolves into the lessons' cues")
	eq(road.cues, "on", "the lessons teach by their cues")
	# the first house brings the minimap (the objective's line carries the count: "2 of 5")
	eq(HudStage.form_of("minimap", "house", false), "on", "the minimap comes at the first house")
	eq(HudStage.form_of("objective", "house", false), "min", "the objective is a line in the house too, with the count in it")
	eq(HudStage.form_of("edge", "house", false), "off", "no arrows from the door")
	# the claim brings the stores and the full toolbar; the clock is the hour all day (the first dusk has the lookout's line); the objective is whole while the work is told
	for part in ["stores", "toolbar", "objective"]:
		eq(HudStage.form_of(part, "claimed", false), "full", "%s at the claim" % part)
	eq(HudStage.form_of("clock", "claimed", false), "min", "the clock is the hour at the claim")
	eq(HudStage.form_of("clock", "dusk", false), "mid", "and the first dusk's clock has the forecast")
	eq(HudStage.form_of("crew", "claimed", false), "off", "the crew cards wait for the first rescue")
	eq(HudStage.form_of("crew", "rescue", false), "full", "the crew cards come with the first rescue")
	eq(HudStage.form_of("edge", "rescue", false), "home", "the arrow home, from afar")
	for phase in HudStage.PHASES:
		eq(HudStage.form_of("lesson", phase, false), "off", "the lesson's card is merged into its cue in %s" % phase)
	eq(HudStage.form_of("stores", "night", false), "low", "the night's stores are the one that is low")
	eq(HudStage.form_of("clock", "night", false), "min", "the night's clock is the hour")
	eq(HudStage.form_of("crew", "night", false), "thin", "the night's cards are icons")
	eq(HudStage.form_of("crew", "morning", false), "thin", "and the morning's: the card has the names")
	eq(HudStage.form_of("objective", "morning", false), "off", "the morning's objective is in the card")
	eq(HudStage.form_of("objective", "night", false), "off", "the night has the banner and the clock, not an objective card")
	for phase in HudStage.PHASES:
		eq(HudStage.form_of("legend", phase, false), "off", "the legend is off in %s" % phase)
		eq(HudStage.form_of("weapon", phase, false), "min", "the weapon is the name and the rounds in %s" % phase)


func test_the_full_hud_is_every_board_and_h_puts_all_away() -> void:
	for phase in HudStage.PHASES:
		for part in HudStage.PARTS:
			eq(HudStage.form_of(part, phase, true, false, true), String(HudStage.FULL[part]), "%s in %s: the full HUD ignores the stage and the fight" % [part, phase])
			eq(HudStage.form_of(part, phase, false, true, true), "off", "%s: H puts it away in the full HUD too" % part)
			eq(HudStage.form_of(part, phase, false, true, false), "off", "%s: and in the minimal one" % part)


func test_a_fight_collapses_what_is_not_the_fight() -> void:
	# claimed, a walker at the door: the boards cut down, what was off stays off
	var want := {"stores": "low", "objective": "min", "crew": "thin", "clock": "min", "toolbar": "min", "edge": "off", "legend": "off", "cues": "fight", "alerts": "lines", "tips": "off", "radio": "off"}
	for part in want:
		eq(HudStage.form_of(part, "rescue", true), String(want[part]), "%s in a fight" % part)
	eq(HudStage.form_of("lesson", "rescue", true), "off", "the lesson's card is not there to ghost")
	eq(HudStage.form_of("weapon", "rescue", true), "min", "the gun stays")
	eq(HudStage.form_of("minimap", "rescue", true), "on", "the minimap stays")
	eq(HudStage.form_of("stores", "road", true), "off", "a board that is off stays off in a fight")
	eq(HudStage.form_of("crew", "claimed", true), "off", "no crew, no cards")
	eq(HudStage.form_of("objective", "night", true), "off", "the night's fight has no objective card")
	eq(HudStage.form_of("alerts", "road", true), "danger", "the dangers are never put away")
	check(HudStage.alpha_of("ghost") <= 0.3, "a ghost is about a quarter")
	eq(HudStage.alpha_of("off"), 0.0, "off is nothing")
	eq(HudStage.alpha_of("full"), 1.0, "a form is whole")


func test_the_threat_comes_at_14_tiles_stays_to_18_and_waits_for_the_shots() -> void:
	var t := HudStage.Threat.new()
	check(not t.step(0.1, INF, 99.0, 99.0), "nothing near: no fight")
	check(not t.step(0.1, 15.0, 99.0, 99.0), "a dead one at 15 tiles: not yet")
	check(t.step(0.1, 14.0, 99.0, 99.0), "a dead one at 14 tiles: the fight")
	check(t.step(0.1, 17.0, 99.0, 99.0), "it steps back to 17: the fight goes on (the hysteresis)")
	check(t.step(0.1, 18.0, 99.0, 99.0), "to exactly 18: on")
	check(not t.step(0.1, 18.5, 99.0, 99.0), "to 18.5 with no shot in 3 s: over")
	near(t.calm_for, 0.1, 0.001, "the quiet has begun")
	# a shot is the fight for 3 seconds, wherever the dead are
	var s := HudStage.Threat.new()
	check(s.step(0.1, INF, 0.0, 99.0), "she fired: the fight")
	check(s.step(0.1, INF, 3.0, 99.0), "3 seconds after the shot: still")
	check(not s.step(0.1, INF, 3.2, 99.0), "after the 3 seconds: over")
	# a wound is the fight for 3 seconds
	var h := HudStage.Threat.new()
	check(h.step(0.1, INF, 99.0, 0.5), "she was hurt a moment ago: the fight")
	check(not h.step(0.1, INF, 99.0, 3.5), "and not 3.5 seconds later")
	# the quiet is counted from the end
	var q := HudStage.Threat.new()
	q.step(0.1, 5.0, 99.0, 99.0)
	for i in 10:
		q.step(0.1, INF, 99.0, 99.0)
	near(q.calm_for, 1.0, 0.001, "ten tenths of a second of quiet")
	q.step(0.1, 10.0, 99.0, 99.0)
	near(q.calm_for, 0.0, 0.001, "and a dead one near stops the count")


func test_a_board_over_a_dead_one_is_seen_by_its_box() -> void:
	var box := HudStage.dead_box(Vector2(500, 400), 32.0)
	near(box.size.x, 32.0, 0.01, "a walker is a tile wide")
	near(box.size.y, 48.0, 0.01, "and a tile and a half tall")
	near(box.position.y, 400.0 - 0.85 * 32.0, 0.01, "its head is 0.85 tile over the point")
	var brute := HudStage.dead_box(Vector2(500, 400), 32.0, true)
	near(brute.size.x, 32.0 * 1.33, 0.01, "a brute is a third bigger")
	var grown := HudStage.dead_box(Vector2(500, 400), 32.0, false, 0.5)
	near(grown.size.x, 64.0, 0.01, "and a box is grown on every side")
	near(HudStage.covered(Rect2(0, 0, 10, 10), Rect2(5, 0, 10, 10)), 0.5, 0.001, "half of it is under")
	near(HudStage.covered(Rect2(0, 0, 10, 10), Rect2(20, 20, 5, 5)), 0.0, 0.001, "none")
	check(HudStage._touches(Rect2(0, 0, 10, 10), [Rect2(20, 20, 5, 5), Rect2(9, 9, 5, 5)]), "a board that meets a box")
	check(not HudStage._touches(Rect2(0, 0, 10, 10), [Rect2(20, 20, 5, 5)]), "and one that does not")


func test_the_hud_setting_is_minimal_and_old_files_have_it_too() -> void:
	Prefs.reset()
	eq(HudStage.mode(), "minimal", "a new player has the minimal HUD")
	# a settings file made before the setting existed: no key in it
	Prefs.set_value("ui", "scale", 1.0)
	eq(HudStage.mode(), "minimal", "a file without the key is minimal")
	HudStage.set_mode("full")
	eq(HudStage.mode(), "full", "Full is kept")
	Prefs.forget()
	eq(HudStage.mode(), "full", "in the file")
	HudStage.set_mode("nonsense")
	eq(HudStage.mode(), "full", "a word that is no mode changes nothing")
	Prefs.set_value("ui", "hud_mode", "nonsense")
	eq(HudStage.mode(), "minimal", "and one that is stored is read as minimal")
	Prefs.reset()


func test_the_settings_screen_has_the_hud_row() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_settings()
	await HudKit.settle()
	eq(screen.hud_buttons.keys(), ["minimal", "full"], "Minimal and Full")
	check(screen.hud_buttons["minimal"].button_pressed and not screen.hud_buttons["full"].button_pressed, "Minimal is lit by default")
	var before: int = ctx.main.names().count("apply_settings")
	screen.hud_buttons["full"].pressed.emit()
	eq(HudStage.mode(), "full", "Full is kept")
	check(screen.hud_buttons["full"].button_pressed and not screen.hud_buttons["minimal"].button_pressed, "and lit")
	eq(ctx.main.names().count("apply_settings"), before + 1, "the game was told")
	check(String(screen.hud_note.text).contains("Every board"), "the line under the buttons says what Full is")
	screen.hud_buttons["minimal"].pressed.emit()
	eq(HudStage.mode(), "minimal", "and back")
	Fakes.free_all(ctx)


func test_h_is_in_the_controls_table() -> void:
	var ControlsTable := preload("res://scripts/ui/controls_table.gd")
	check(ControlsTable.key_text("hud_hide") == "H", "the table has the key that puts the HUD away")
	var found := false
	for group in ControlsTable.hud_groups(false):
		for e in group[2]:
			if String(e[0]) == "H":
				found = true
	check(found, "and the help panel lists it")


func test_the_crews_troubles_are_one_line_and_the_early_game_shows_dangers_only() -> void:
	var ctx := HudKit.build()
	var hud = ctx.hud
	hud.stage_on = true
	hud.stage_alert_lines = true
	ctx.sim.alert("hurt-ana", "danger", "Ana is being bitten", "40% health", null, 600.0)
	ctx.sim.alert("down-ben", "danger", "Ben is down", "Get them to Ana", null, 600.0)
	ctx.sim.alert("slots-open", "info", "The base can grow", "Open the Build page (N)", null, 600.0)
	HudKit.update(ctx)
	check(hud.alert_items.has("crew-trouble"), "the crew's troubles are one line")
	check(not hud.alert_items.has("hurt-ana") and not hud.alert_items.has("down-ben"), "not one slip for each")
	eq(String(hud.alert_items["crew-trouble"].text), "Ben is down, Ana is being bitten", "who is down and who is bitten")
	check(hud.alert_items.has("slots-open"), "another alert is as it was")
	check(not hud.alert_items["slots-open"].subl.visible, "but is one line: the second is its tooltip")
	check(Hud._names_are(["Ana", "Ben", "Cy"], "down") == "Ana, Ben and Cy are down", "three names")
	check(Hud._names_are(["Ana"], "being bitten") == "Ana is being bitten", "one name")
	HudKit.free_all(ctx)
	# the early game: dangers only
	var early := HudKit.build()
	early.hud.stage_on = true
	early.hud.stage_alert_lines = true
	early.hud.stage_alert_danger_only = true
	early.sim.alert("slots-open", "info", "The base can grow", "Open the Build page (N)", null, 600.0)
	early.sim.alert("low-food", "warn", "Food is running out", "about 2 days left", null, 600.0)
	early.sim.alert("hurt-ana", "danger", "Ana is being bitten", "40% health", null, 600.0)
	HudKit.update(early)
	check(not early.hud.alert_items.has("slots-open") and not early.hud.alert_items.has("low-food"), "only the dangers are shown in the first minutes")
	check(early.hud.alert_items.has("crew-trouble"), "and a danger is")
	HudKit.free_all(early)


## A wall segment with what the radio's watch of the walls reads of it (the real segments are the base's).
class FakeSeg:
	extends RefCounted
	var id := 4
	var name := "East fence, south part"
	var state := 1
	var hp := 100.0
	var max_hp := 100.0
	var center := Vector2(20, 20)
	var slots: Array = []


class FakeSlot:
	extends RefCounted
	var who = null


class FakeWho:
	extends RefCounted
	var state := "attack"


func _watch(sim) -> void:
	var seg := FakeSeg.new()
	var slot := FakeSlot.new()
	slot.who = FakeWho.new()
	seg.slots = [slot]
	sim.segments = [seg]
	sim.radio._watch_the_walls()    # (it notes the wall's hit points the first time)
	seg.hp = 80.0
	sim.radio._watch_the_walls()


func test_the_town_has_no_attack_card_for_a_wall_under_attack_but_the_school_still_has() -> void:
	var town := Helpers.town_game(1, {"blocks": 2})
	var sim = town.sim
	_watch(sim)
	var kinds: Array = []
	for e in sim.radio.open_calls():
		kinds.append(String(e.kind))
	check(not kinds.has("attack"), "the town raises no attack card: the crew patrol by themselves")
	check(sim.alerts.has("attack-4"), "it says it in one line")
	if sim.alerts.has("attack-4"):
		eq(String(sim.alerts["attack-4"].text), "East fence, south part under attack", "the fence that is under attack")
	town.world.free()
	var school := Helpers.make(5, 1)
	_watch(school.sim)
	var school_kinds: Array = []
	for e in school.sim.radio.open_calls():
		school_kinds.append(String(e.kind))
	check(school_kinds.has("attack"), "the school's yard keeps its card, exactly as it was")
	for e in school.sim.radio.open_calls():
		if String(e.kind) == "attack":
			var labels: Array = []
			for o in e.options:
				labels.append(String(o.label))
			check(labels.has("Fall back to the school"), "with the school's words")
	school.world.free()


func test_the_calls_of_the_night_fall_back_to_the_house_in_the_town() -> void:
	var town := Helpers.town_game(1, {"blocks": 2})
	var sim = town.sim
	check(sim.radio.night._home_word() == "the house", "the town has no school to fall back to")
	town.world.free()
	var school := Helpers.make(5, 1)
	check(school.sim.radio.night._home_word() == "the school", "the school's yard says the school")
	school.world.free()


# -------------------------------------------------------------------------- a real run --

## {"main", "win", "saved", "stage": the hud_stage part, "hud"}: the real game scene of a mini town, in a window of a real size, not running by itself (a test steps it).
func _boot(width: int = 1280, height: int = 800) -> Dictionary:
	var win: Window = Engine.get_main_loop().root
	var saved := {"size": win.size, "position": win.position, "mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "scale_size": win.content_scale_size}
	win.size = Vector2i(width, height)
	Prefs.reset()
	Engine.set_meta("run", {"difficulty": 1, "seed": 7, "town": true, "avatar": true, "town_opts": {"blocks": 2}})
	var main = load("res://scenes/main.tscn").instantiate()
	win.add_child(main)
	main.set_process(false)
	var part = HudStage.of(main)
	return {"main": main, "win": win, "saved": saved, "stage": part, "hud": main.hud}


func _end(g: Dictionary) -> void:
	g.main.queue_free()
	await Engine.get_main_loop().process_frame
	var win: Window = g.win
	win.content_scale_mode = g.saved.mode
	win.content_scale_aspect = g.saved.aspect
	win.content_scale_size = g.saved.scale_size
	win.size = g.saved.size
	win.position = g.saved.position
	Prefs.reset()


## Puts the run in a stage of the scenario with none of the dead awake (a mini town has some near the start house: they are a fight).
func _go(g: Dictionary, stage_name: String) -> void:
	OneHouse.stage_to(g.main.sim, stage_name)
	g.main.sim.zombies.clear()


## An awake walker `tiles` from her, on a free tile that is out of doors or in her own house (the rules do not count one behind another house's walls).
func _spawn_at(g: Dictionary, tiles: float):
	var sim = g.main.sim
	var me = sim.avatar.player()
	var mine: int = int(sim.houses.house_at(me.x, me.y))
	for i in 36:
		var a := TAU * float(i) / 36.0
		var x := floorf(me.x + cos(a) * tiles) + 0.5
		var y := floorf(me.y + sin(a) * tiles) + 0.5
		if sim.world.is_solid(sim.world.solid_z, x, y) or sim.world.is_solid(sim.world.solid_p, x, y):
			continue
		var zh: int = int(sim.houses.house_at(x, y))
		if zh >= 0 and zh != mine:
			continue
		return sim.spawn(x, y, "approach", "walker")
	return null


## Steps the game scene `n` frames of `dt` seconds (the fades run on the frame's time).
func _step(g: Dictionary, n: int, dt: float = 0.1) -> void:
	for i in n:
		g.main._process(dt)
		g.hud.update_hud(g.main.sim, g.main.speed, true, 0)


func test_a_real_run_begins_with_the_minimal_hud_and_gains_boards_as_it_goes() -> void:
	var g := _boot()
	var stage = g.stage
	var hud = g.hud
	check(stage != null, "the town has the part")
	if stage == null:
		await _end(g)
		return
	g.main.speed = 0
	_step(g, 8)
	eq(stage.phase, "road", "the run begins on the road")
	check(not hud.res_panel.visible, "no stores yet")
	check(not hud.bar.visible, "no crew cards yet")
	check(hud.ammo_panel.visible and not hud.holster_button.visible, "the gun's readout is there, without its button")
	check(hud.clock.visible and not hud.strip.visible, "the clock is the day and the hour")
	check(hud.speed_panel.visible and not hud.fields_button.visible and not hud.jobs_button.visible and not hud.build_button.visible, "the toolbar has its few buttons")
	check(hud.speed_buttons[0].visible and hud.help_button.visible and hud.menu_button.visible, "pause, the controls and the menu are there")
	var th = g.main.town.part("town_hud")
	check(not th.obj_head.visible, "the objective is its one line")
	var mm = g.main.town.part("minimap")
	check(not mm.stage_on, "the minimap waits for the first house")
	# the claim: the stores, the whole clock and the toolbar
	_go(g, "claimed")
	_step(g, 8)
	eq(stage.phase, "claimed", "claimed")
	check(hud.res_panel.visible and hud.res_panel.modulate.a > 0.99, "the stores came, whole")
	check(not hud.strip.visible and hud.clock.visible, "the clock is still the hour")
	check(hud.speed_panel.visible and hud.jobs_button.visible and hud.build_button.visible and hud.speed_buttons[2].visible, "the toolbar is whole, but for the third speed and the fields of fire")
	check(not hud.fields_button.visible and not hud.speed_buttons[3].visible, "which have their keys")
	check(th.obj_head.visible, "the objective card has its heading")
	check(mm.stage_on, "and the minimap is on")
	check(not hud.bar.visible, "no cards: nobody has joined")
	# the first rescue: the crew's cards
	_go(g, "rescued2")
	_step(g, 8)
	eq(stage.phase, "rescue", "the crew is here")
	check(hud.bar.visible, "the crew's cards came")
	await _end(g)


func test_a_real_run_in_the_full_hud_is_every_board_always() -> void:
	var g := _boot()
	HudStage.set_mode("full")
	var stage = g.stage
	var hud = g.hud
	g.main.speed = 0
	_step(g, 12)
	check(stage._full, "the part knows it is the full HUD")
	check(hud.res_panel.visible and hud.res_panel.modulate.a > 0.99, "the stores are there on the road")
	check(hud.holster_button.visible, "the weapon button")
	check(hud.strip.visible and hud.fields_button.visible and hud.jobs_button.visible, "the whole clock and the whole toolbar")
	check(g.main.town.part("minimap").stage_on, "the minimap")
	check(not hud.stage_on, "the HUD has no stage forms")
	await _end(g)


func test_a_fight_collapses_the_boards_and_they_come_back_in_order() -> void:
	var g := _boot()
	var stage = g.stage
	var hud = g.hud
	var sim = g.main.sim
	_go(g, "rescued2")
	g.main.speed = 0
	_step(g, 10)
	check(not stage.threat.on, "no fight (nearest %s, shot %s, hurt %s, zombies %d)" % [str(stage._nearest), str(stage._shot_t), str(stage._hurt_t), sim.zombies.size()])
	eq(stage.form("crew"), "full", "the cards are whole")
	eq(stage.form("clock"), "min", "and the clock is the hour")
	eq(stage.form("toolbar"), "full", "and the toolbar whole")
	# a walker 8 tiles from her
	var z = _spawn_at(g, 8.0)
	check(z != null, "a walker was made 8 tiles from her")
	_step(g, 2)
	check(stage.threat.on, "a dead one at 8 tiles: the fight is on")
	eq(stage.form("clock"), "min", "the clock is the hour")
	eq(stage.form("crew"), "thin", "the cards are icons")
	eq(stage.form("objective"), "min", "the objective is a line")
	check(hud.stage_crew == "thin" and hud.stage_clock == "min", "and the HUD has laid them out so")
	check(not hud.strip.visible, "the clock's strip is away")
	# it is gone: the quiet comes, and the boards come back one after the other
	sim.zombies.clear()
	_step(g, 1, 0.1)
	check(not stage.threat.on, "the fight is over with the dead one gone and no shot")
	eq(stage.form("stores"), "full", "the stores are back at once")
	eq(stage.form("crew"), "thin", "the cards wait their turn")
	_step(g, 6, 0.1)
	eq(stage.form("crew"), "full", "the cards are back after half a second")
	eq(stage.form("toolbar"), "min", "the toolbar waits for its turn: a second after the stores")
	_step(g, 8, 0.1)
	eq(stage.form("toolbar"), "full", "and it is back")
	eq(stage.form("alerts"), "lines", "the alerts are lines all through")
	check(z != null, "the walker was made")
	await _end(g)


func test_what_can_wait_waits_for_the_quiet_of_24_tiles() -> void:
	var g := _boot()
	var stage = g.stage
	var hud = g.hud
	_go(g, "rescued2")
	g.main.speed = 0
	_step(g, 10)
	check(stage.quiet() and stage.tips_ok(), "nothing awake in view: the quiet, a tip may come")
	eq(hud.stage_call, "idea", "and a call that is an idea is one line, the rest whole")
	var z = _spawn_at(g, 20.0)
	check(z != null, "a walker was made 20 tiles from her")
	_step(g, 2)
	check(not stage.threat.on, "20 tiles is not a fight")
	check(not stage.quiet() and not stage.tips_ok(), "but it is not the quiet: no tip")
	eq(hud.stage_call, "line", "and every call is one line")
	g.main.sim.zombies.clear()
	_step(g, 2)
	check(stage.quiet() and stage.tips_ok(), "it goes: the quiet is back")
	eq(hud.stage_call, "idea", "an idea is a line again")
	await _end(g)


func test_a_board_over_a_dead_one_is_a_ghost_that_lets_the_pointer_through() -> void:
	var g := _boot()
	var stage = g.stage
	var hud = g.hud
	var sim = g.main.sim
	_go(g, "rescued2")
	g.main.speed = 0
	_step(g, 10)
	check(hud.clock.modulate.a > 0.99, "the clock is whole with nobody near")
	# a dead one under the middle of the clock: the tile that is there on the screen
	var rect: Rect2 = hud.clock.get_global_rect()
	var at: Vector2 = g.main.cam_center + (rect.get_center() - g.main._vp() * 0.5) / float(g.main.zoom_px)
	var z = sim.spawn(at.x, at.y, "approach", "walker")
	check(z != null, "a dead one was made under the clock")
	_step(g, 1, 0.05)
	check(hud.clock.modulate.a <= 0.3, "the clock is a ghost at once: %.2f" % hud.clock.modulate.a)
	check(hud.clock.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.time_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "and lets the pointer through")
	check(hud.ammo_panel.modulate.a > 0.9 or hud.ammo_panel.get_global_rect().intersects(HudStage.dead_box(g.main._tile_to_screen(Vector2(z.x, z.y)), g.main.zoom_px, false, 0.5)), "a board that is not over it stays whole")
	# it goes: the ghost holds for a second and then lifts
	sim.zombies.clear()
	_step(g, 5, 0.1)
	check(hud.clock.modulate.a <= 0.3, "half a second on, it is still a ghost")
	_step(g, 12, 0.1)
	check(hud.clock.modulate.a > 0.95, "and whole again after it has been clear for a second: %.2f" % hud.clock.modulate.a)
	await _end(g)


func test_h_puts_the_hud_away_and_brings_it_back() -> void:
	var g := _boot()
	var stage = g.stage
	var hud = g.hud
	_go(g, "rescued2")
	g.main.speed = 0
	_step(g, 10)
	check(hud.res_panel.visible and hud.clock.visible and hud.bar.visible, "the boards are up")
	var ev := InputEventKey.new()
	ev.keycode = KEY_H
	ev.pressed = true
	check(stage.on_key(ev), "H is the part's")
	check(stage.hidden, "the HUD is put away")
	_step(g, 8)
	check(not hud.res_panel.visible and not hud.clock.visible and not hud.bar.visible and not hud.ammo_panel.visible, "every board is gone")
	var th = g.main.town.part("town_hud")
	check(th.obj_card.modulate.a < 0.02 or not th.obj_card.visible, "and the objective")
	var again := InputEventKey.new()
	again.keycode = KEY_H
	again.pressed = true
	check(stage.on_key(again), "H again")
	_step(g, 8)
	check(hud.res_panel.visible and hud.clock.visible and hud.bar.visible and hud.ammo_panel.visible, "everything is back")
	var shift := InputEventKey.new()
	shift.keycode = KEY_H
	shift.shift_pressed = true
	shift.pressed = true
	check(not stage.on_key(shift), "Shift+H is nothing")
	await _end(g)


func test_a_banner_waits_for_the_quiet_and_goes_at_the_first_key() -> void:
	var g := _boot()
	var stage = g.stage
	var hud = g.hud
	var sim = g.main.sim
	_go(g, "rescued2")
	g.main.speed = 0
	_step(g, 10)
	# in a fight a banner is kept, and not shown
	check(_spawn_at(g, 6.0) != null, "a walker was made 6 tiles from her")
	_step(g, 2)
	hud.show_banner("The dusk bell", "Fortify")
	check(hud.banner.modulate.a < 0.01, "a banner is not shown in a fight")
	eq(stage._queue.size(), 1, "it is kept")
	sim.zombies.clear()
	_step(g, 40, 0.1)
	check(stage._queue.is_empty(), "the quiet came and the queue is shown or dropped")
	# a banner in the quiet hangs in the top strip, and the first key puts it away
	hud.show_banner("This house is yours", "Build the front fence")
	check(hud.banner.offset_top <= 10.0 + 86.0 + 10.0, "in the top strip, under the cards: %s" % str(hud.banner.offset_top))
	check(hud.banner.offset_right - hud.banner.offset_left <= hud.size.x * 0.45, "not wider than 40 percent of the window")
	_step(g, 7)
	hud.banner_tween.kill()
	hud.banner.modulate.a = 1.0
	var k := InputEventKey.new()
	k.keycode = KEY_W
	k.pressed = true
	stage.on_key(k)
	await Engine.get_main_loop().create_timer(0.5).timeout
	check(hud.banner.modulate.a < 0.02, "the first key put the banner away")
	await _end(g)
