extends "res://tests/case.gd"
## Round 5, the Jobs screen (the Duty roster): the page that gives every person a day job (a station with seats) and
## a night post (a named place on the wall), the stations and their settings, Auto-assign and Clear; opened by J, the
## toolbar's clipboard or the job tag; the rules wait while it is open; hovering a row, a station or a post marks its
## place in the world. The rules behind it are tests/test_jobs.gd (the owner's): here the game is the HUD kit's, whose
## jobs module is the real one. The person panel's job tag and the M and B buttons are in test_hud_jobs.gd, the
## marks drawn in the world in test_hud_overlay.gd and the key J on the real scene in test_hud_keys.gd.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SIZES := [[700, 700], [980, 700], [1280, 800], [1920, 1080]]
const SHORT := [[700, 560], [1280, 600], [980, 480]]
const BLANK := {"station": "", "post": "", "person": ""}


## The mouse put in a corner where no control is (a pointer left over a button by an earlier test would let its
## tooltip come up in this one, and a tooltip is a window of its own with words on it).
func _park_the_mouse() -> void:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1, 1)
	ev.global_position = Vector2(1, 1)
	root.push_input(ev, true)


## The HUD has seen the game (as main.gd's frames give it) and the screen is open.
func _open(width: int = 1280, height: int = 800, speed: int = 1) -> Dictionary:
	_park_the_mouse()
	var ctx := Kit.build(width, height)
	Kit.update(ctx, speed)
	ctx.hud.open_jobs()
	return ctx


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


## A key as the engine hears it: through the whole input path (the screen's own handler first, then the controls).
func _press(code: Key) -> void:
	var root: Window = Engine.get_main_loop().root
	var down := _key(code)
	root.push_input(down, false)
	var up := _key(code)
	up.pressed = false
	root.push_input(up, false)


func _focus_owner() -> Control:
	return Engine.get_main_loop().root.gui_get_focus_owner()


# ------------------------------------------------------------------ the page --

func test_the_screen_has_a_row_for_each_person_and_a_card_for_each_station() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	check(s != null, "it opens")
	eq(s.rows.keys(), ["ruth", "dez", "ana", "marcus", "walt", "hector"], "a row for each of the six, in the crew's order")
	eq(s.station_cards.keys(), ["bench", "builders", "garden", "infirmary", "radio", "watch"], "and a card for each of the six stations")
	var all := Kit.texts(s)
	for t in ["Duty roster", "Workbench", "Wall crew", "Vegetable beds", "Infirmary", "Radio desk", "Lookout post", "STATIONS"]:
		check(all.has(t), "shows '%s'" % t)
	eq([s.auto_button.text, s.clear_button.text, s.close_button.text], ["Auto-assign", "Clear", "Close"], "and the three buttons")
	check(ctx.hud.modal_open(), "the HUD calls it a modal")
	Kit.free_all(ctx)


func test_a_row_shows_the_job_the_post_the_skills_and_what_they_are_doing() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var dez = Kit.person(ctx, "dez")
	dez.activity = "At the workbench"
	s.refresh()
	var row: Dictionary = s.rows.dez
	eq(Kit.texts(row.job), ["Workbench"], "the day job")
	eq(Kit.texts(row.post), ["The school bus"], "the night post")
	eq(Kit.texts(row.mood), ["Steady"], "a word for their mood")
	eq(Kit.texts(row.doing), ["At the workbench"], "what they are doing now")
	for skill in ["Shooting", "Building", "Medicine", "Leading"]:
		eq(Kit.texts(row.skills[skill]), [skill, str(dez.skills[skill])], "%s and its number" % skill)
	check(row.skills.Building.get_meta("marked"), "Building is marked: the Workbench asks for it")
	check(not row.skills.Shooting.get_meta("marked"), "the others are not")
	check(Kit.texts(row.who).has("Dez"), "the name is there")
	# someone else's: the nurse's skill is Medicine; with no job nothing is marked
	check(s.rows.ana.skills.Medicine.get_meta("marked") and not s.rows.ana.skills.Building.get_meta("marked"), "Ana's Medicine is the one marked")
	ctx.sim.jobs.unassign(Kit.person(ctx, "ana"))
	s.refresh()
	eq(Kit.texts(s.rows.ana.job), ["No job"], "with no job it says so")
	check(not s.rows.ana.skills.Medicine.get_meta("marked"), "and nothing is marked")
	Kit.free_all(ctx)


func test_the_page_follows_the_game_each_time_the_hud_is_updated() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var dez = Kit.person(ctx, "dez")
	dez.activity = "Fixing the generator"
	Kit.update(ctx)
	eq(Kit.texts(s.rows.dez.doing), ["Fixing the generator"], "what they are doing")
	dez.activity = "Carrying scrap"
	Kit.update(ctx)
	eq(Kit.texts(s.rows.dez.doing), ["Carrying scrap"], "and what they are doing next")
	ctx.sim.morale.values["dez"] = 10.0
	Kit.update(ctx)
	eq(Kit.texts(s.rows.dez.mood), ["Breaking"], "their mood")
	dez.skills["Building"] = 10
	Kit.update(ctx)
	check(Kit.texts(s.rows.dez.skills.Building).has("10"), "a skill that has grown: %s" % str(Kit.texts(s.rows.dez.skills.Building)))
	ctx.sim.jobs.assign(Kit.person(ctx, "hector"), "bench")
	Kit.update(ctx)
	eq(Kit.texts(s.rows.hector.job), ["Workbench"], "a job given somewhere else (the key M)")
	eq(s.station_cards.bench.pips.map(func(p): return p.get_meta("who")), ["dez", "hector"], "and the bench's seats")
	Kit.free_all(ctx)


func test_every_station_card_has_its_words_its_seats_and_its_crew() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	for st in ctx.sim.jobs.stations():
		var c: Dictionary = s.station_cards[st.id]
		var all := Kit.texts(c.card)
		check(all.has(String(st.name)) and all.has(String(st.blurb)), "%s: its name and what it does" % st.name)
		eq(c.pips.size(), int(st.seats), "%s: a pip for each seat" % st.name)
	var bench: Dictionary = s.station_cards.bench
	eq(bench.pips.map(func(p): return p.get_meta("who")), ["dez", ""], "the bench has Dez in one seat and one free")
	eq(Kit.texts(bench.card).has("Dez"), true, "and says who")
	eq(s.station_cards.builders.pips.map(func(p): return p.get_meta("who")), ["walt", "", ""], "the wall crew: Walt and two free")
	eq(Kit.texts(s.station_cards.radio.card).has("Ruth"), true, "Ruth is at the radio desk")
	check(Kit.texts(s.station_cards.garden.card).has("Hector"), "and Hector in the beds")
	ctx.sim.jobs.unassign(Kit.person(ctx, "dez"))
	s.refresh()
	eq(bench.pips.map(func(p): return p.get_meta("who")), ["", ""], "an empty station has its seats free")
	check(Kit.texts(bench.card).has("Nobody"), "and says nobody")
	Kit.free_all(ctx)


func test_opening_it_twice_does_not_stack_pages() -> void:
	var ctx := _open()
	var first = ctx.hud.jobs_screen
	ctx.hud.open_jobs()
	eq(ctx.hud.jobs_screen, first, "the same page")
	var pages := 0
	for c in ctx.hud.get_children():
		if c.get_script() == first.get_script():
			pages += 1
	eq(pages, 1, "only one in the tree")
	Kit.free_all(ctx)


func test_nothing_opens_while_another_page_is_up_or_in_a_game_without_jobs() -> void:
	var ctx := Kit.build()
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites()
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	ctx.hud.open_scavenge(ctx.hud.selection)
	ctx.hud.open_jobs()
	check(ctx.hud.jobs_screen == null, "not over the scavenging dialog")
	ctx.hud.scavenge_dialog.cancel()
	ctx.hud.open_jobs()
	check(ctx.hud.jobs_screen != null, "but once it is shut it opens")
	ctx.hud.close_jobs()
	# an older game with no jobs module
	var real = ctx.hud.sim_ref
	ctx.hud.sim_ref = {"stock": ctx.sim.stock}
	ctx.hud.open_jobs()
	check(ctx.hud.jobs_screen == null, "and not in a game with no jobs")
	ctx.hud.sim_ref = real
	Kit.free_all(ctx)


# ------------------------------------------------------------------ the alerts --

func test_the_alerts_for_an_empty_radio_desk_and_lookout_post_wear_the_radio_and_the_post_icons() -> void:
	var ctx := Kit.build()
	var cases := {"job-radio": "radio", "job-watch": "post"}
	for id in cases:
		eq(ctx.hud._alert_icon_name({"id": id, "level": "info"}), cases[id], id)
	ctx.sim.alert("job-radio", "info", "Nobody is at the radio desk", "There will be no call at noon unless someone sits there", null, 60.0)
	ctx.sim.alert("job-watch", "info", "Nobody is on watch", "There will be no forecast tonight unless someone is at the lookout post", null, 60.0)
	Kit.update(ctx)
	for id in cases:
		var it: Dictionary = ctx.hud.alert_items.get(id, {})
		check(not it.is_empty() and it.panel != null, "%s is in the feed" % id)
		if not it.is_empty() and it.panel != null:
			eq((it.icon as TextureRect).texture, ctx.hud.icons[cases[id]], "%s: with its icon" % id)
	# the older ones are as they were
	for pair in [["story", "radio"], ["story-fog", "radio"], ["forecast", "bell"], ["workshop-idle", "ammo"], ["seg-3", "wall"]]:
		eq(ctx.hud._alert_icon_name({"id": pair[0], "level": "warn"}), pair[1], pair[0])
	Kit.free_all(ctx)


# ------------------------------------------------------------------ the lists --

func test_the_job_list_shows_the_seats_left_and_the_full_stations_are_off() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var walt = Kit.person(ctx, "walt")
	s.open_job_list(walt)
	check(s.list != null and s.list_kind == "job", "the list is open")
	eq(s.list_items.keys(), ["bench", "builders", "garden", "infirmary", "radio", "watch", ""], "every station, then No job")
	for id in ["bench", "garden", "infirmary"]:
		check(not s.list_items[id].disabled, "%s has a seat for him" % id)
	check(Kit.texts(s.list_items.bench).has("1 left"), "the bench says one seat is left: %s" % str(Kit.texts(s.list_items.bench)))
	check(Kit.texts(s.list_items.garden).has("1 left"), "so does the garden")
	for id in ["radio", "watch"]:
		check(s.list_items[id].disabled, "%s is full: it is off" % id)
		check(Kit.texts(s.list_items[id]).has("full"), "and says so: %s" % str(Kit.texts(s.list_items[id])))
	check(not s.list_items.builders.disabled and Kit.texts(s.list_items.builders).has("current"), "his own job is marked current")
	check(not s.list_items[""].disabled and Kit.texts(s.list_items[""]).has("No job"), "No job can always be picked")
	check(Kit.texts(s.list).has("DAY JOB FOR WALT"), "the list says whose it is")
	check(Kit.texts(s.list).has("Point at a job to see its place in the yard"), "and what pointing at a line does")
	Kit.free_all(ctx)


func test_choosing_a_job_from_the_list_gives_it_and_the_page_follows() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var walt = Kit.person(ctx, "walt")
	s.open_job_list(walt)
	s.list_items.garden.pressed.emit()
	eq(ctx.sim.jobs.job_of(walt), "garden", "Walt is in the beds")
	check(s.list == null, "the list shuts")
	eq(Kit.texts(s.rows.walt.job), ["Vegetable beds"], "his row follows")
	eq(s.station_cards.garden.pips.map(func(p): return p.get_meta("who")), ["walt", "hector"], "and the station's seats")
	eq(s.station_cards.builders.pips.map(func(p): return p.get_meta("who")), ["", "", ""], "the wall crew is empty")
	s.open_job_list(walt)
	s.list_items[""].pressed.emit()
	eq(ctx.sim.jobs.job_of(walt), "", "No job takes him off it")
	eq(Kit.texts(s.rows.walt.job), ["No job"], "and the row says so")
	Kit.free_all(ctx)


func test_a_full_station_is_refused_and_the_page_says_why() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var walt = Kit.person(ctx, "walt")
	check(not s.choose_job(walt, "radio"), "the radio desk is full")
	eq(ctx.sim.jobs.job_of(walt), "builders", "Walt stays where he was")
	check(s.error_label.visible and s.error_label.text.contains("Radio desk is full"), "a line says why: '%s'" % s.error_label.text)
	check(s.choose_job(walt, "garden"), "a seat in the beds")
	check(not s.error_label.visible, "and the line goes")
	Kit.free_all(ctx)


func test_the_post_list_greys_a_taken_post_and_says_who_holds_it() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var ruth = Kit.person(ctx, "ruth")
	s.open_post_list(ruth)
	check(s.list != null and s.list_kind == "post", "the list is open")
	eq(s.list_items.size(), ctx.sim.jobs.posts().size(), "every post is on it")
	check(s.list_items.size() >= 19, "nineteen at least")
	check(s.list_items.bus.disabled and Kit.texts(s.list_items.bus).has("Dez"), "Dez has the bus: it is off and says so")
	check(s.list_items.west_fence.disabled and Kit.texts(s.list_items.west_fence).has("Ana"), "Ana has the west fence")
	check(not s.list_items.north_middle.disabled, "a free post can be taken")
	check(not s.list_items.gate.disabled and Kit.texts(s.list_items.gate).has("current"), "her own is marked current")
	check(Kit.texts(s.list).has("NIGHT POST FOR RUTH"), "the list says whose it is")
	check(Kit.texts(s.list).has("Point at a post to see it in the yard"), "and what pointing at a line does")
	for heading in ["North wall", "West wall", "East wall", "Towers"]:
		check(Kit.texts(s.list).has(heading.to_upper()), "the posts are grouped: %s" % heading)
	Kit.free_all(ctx)


func test_choosing_a_post_gives_it_and_a_taken_one_is_refused_with_who_holds_it() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var ruth = Kit.person(ctx, "ruth")
	s.open_post_list(ruth)
	s.list_items.north_middle.pressed.emit()
	eq(String(ctx.sim.jobs.post_of(ruth).id), "north_middle", "Ruth holds the middle of the north wall")
	eq(Kit.texts(s.rows.ruth.post), ["North wall, middle"], "her row says so")
	check(not s.choose_post(ruth, "bus"), "Dez has the bus")
	eq(String(ctx.sim.jobs.post_of(ruth).id), "north_middle", "she stays where she was")
	check(s.error_label.visible and s.error_label.text.contains("Dez"), "and the page says who holds it: '%s'" % s.error_label.text)
	check(s.choose_post(ruth, "gate"), "the gate is free now")
	check(not s.error_label.visible, "and the line goes")
	Kit.free_all(ctx)


func test_the_sliders_set_the_stations_settings() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var bench: Dictionary = s.station_cards.bench
	eq(bench.sliders.keys(), ["ammo_target", "scrap_reserve"], "the bench has its two")
	var target: HSlider = bench.sliders.ammo_target
	eq([target.min_value, target.max_value, target.step, target.value], [0.0, 800.0, 25.0, 300.0], "range, step and the default of the ammo target")
	eq(bench.values.ammo_target.text, "300 ammo", "its value with the unit")
	target.value = 450.0
	eq(int(ctx.sim.jobs.setting("bench", "ammo_target")), 450, "moving it sets the setting")
	eq(bench.values.ammo_target.text, "450 ammo", "and the page says so")
	bench.sliders.scrap_reserve.value = 8.0
	eq(int(ctx.sim.jobs.setting("bench", "scrap_reserve")), 8, "the scrap reserve too")
	eq(bench.values.scrap_reserve.text, "8 scrap", "with its unit")
	var crew: HSlider = s.station_cards.builders.sliders.repair_below
	crew.value = 50.0
	eq(int(ctx.sim.jobs.setting("builders", "repair_below")), 50, "the wall crew's threshold")
	eq(s.station_cards.builders.values.repair_below.text, "50%", "in per cent")
	check(Kit.texts(bench.card).has("Make ammo until the stock reaches") and Kit.texts(s.station_cards.builders.card).has("Mend walls that are under"), "each with its label from the data")
	check(s.station_cards.garden.sliders.is_empty() and s.station_cards.radio.sliders.is_empty(), "a station with no settings has no sliders")
	# a setting changed from outside shows when the page refreshes
	ctx.sim.jobs.set_setting("bench", "ammo_target", 600)
	s.refresh()
	eq([target.value, bench.values.ammo_target.text], [600.0, "600 ammo"], "the page follows the game")
	Kit.free_all(ctx)


func test_auto_assign_and_clear_work_from_the_page() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	s.clear_button.pressed.emit()
	for p in ctx.sim.people:
		eq(ctx.sim.jobs.job_of(p), "", "%s has no job after Clear" % p.first)
		eq(Kit.texts(s.rows[p.id].job), ["No job"], "%s's row says so" % p.first)
	for st in ctx.sim.jobs.stations():
		eq(s.station_cards[st.id].pips.filter(func(pip): return pip.get_meta("who") != "").size(), 0, "%s is empty" % st.name)
	var posts := {}
	for p in ctx.sim.people:
		posts[p.id] = String(ctx.sim.jobs.post_of(p).id)
	s.auto_button.pressed.emit()
	for pair in [["dez", "bench"], ["ana", "infirmary"], ["ruth", "radio"], ["marcus", "watch"]]:
		eq(ctx.sim.jobs.job_of(Kit.person(ctx, pair[0])), pair[1], "Auto-assign puts %s on %s" % pair)
		eq(Kit.texts(s.rows[pair[0]].job), [String(ctx.sim.jobs.station(pair[1]).name)], "%s's row follows" % pair[0])
	for p in ctx.sim.people:
		check(ctx.sim.jobs.job_of(p) != "", "%s has a job" % p.first)
		eq(String(ctx.sim.jobs.post_of(p).id), posts[p.id], "the night posts are not touched")
	Kit.free_all(ctx)


func test_people_who_are_dead_turned_or_away_are_shown_as_such_and_cannot_be_given_a_job() -> void:
	var ctx := Kit.build()
	Kit.person(ctx, "walt").dead = true
	Kit.person(ctx, "walt").turned = true
	Kit.person(ctx, "hector").dead = true
	Kit.person(ctx, "dez").away = {"kind": "party", "site": "pharmacy"}
	Kit.update(ctx)
	ctx.hud.open_jobs()
	var s = ctx.hud.jobs_screen
	eq(Kit.texts(s.rows.walt.mood), ["Turned"], "one who turned says so")
	eq(Kit.texts(s.rows.hector.mood), ["In memory"], "one who is remembered")
	eq(Kit.texts(s.rows.dez.mood), ["Away"], "one who is out scavenging")
	for id in ["walt", "hector", "dez"]:
		check(s.rows[id].job.disabled and s.rows[id].post.disabled, "%s cannot be given a job or a post" % id)
		var p = Kit.person(ctx, id)
		check(not s.choose_job(p, "garden") if id != "hector" else not s.choose_job(p, "bench"), "%s: the job is refused" % id)
		check(not s.choose_post(p, "north_middle"), "%s: the post is refused" % id)
		s.open_job_list(p)
		check(s.list == null, "%s: no list opens" % id)
	eq(Kit.texts(s.rows.walt.job), ["–"], "the turned have no job to show")
	check(not Kit.texts(s.rows.ana.mood).has("Away"), "the others are as they were")
	# a dead person's seat is free for the others
	eq(ctx.sim.jobs.seats_left("garden"), 2, "Hector's seat in the beds is free")
	check(s.choose_job(Kit.person(ctx, "ana"), "garden"), "so Ana can take it")
	Kit.free_all(ctx)


# --------------------------------------------------------- closing and the speed --

func test_the_page_pauses_the_game_and_gives_the_speed_back() -> void:
	var ctx := Kit.build()
	Kit.update(ctx, 2)
	ctx.hud.open_jobs()
	eq(ctx.speeds, [0], "paused on open")
	ctx.hud.jobs_screen.close_button.pressed.emit()
	eq(ctx.speeds, [0, 2], "and back to the old speed on Close")
	check(ctx.hud.jobs_screen == null and not ctx.hud.modal_open(), "the page is gone")
	ctx.speeds.clear()
	ctx.hud.open_jobs()
	ctx.hud.jobs_screen._input(_key(KEY_ESCAPE))
	eq(ctx.speeds, [0, 2], "Esc closes it the same way")
	ctx.speeds.clear()
	ctx.hud.open_jobs()
	ctx.hud.jobs_screen._input(_key(KEY_J))
	eq(ctx.speeds, [0, 2], "so does J")
	ctx.speeds.clear()
	ctx.hud.toggle_jobs()
	check(ctx.hud.jobs_screen != null, "toggle opens it")
	ctx.hud.toggle_jobs()
	check(ctx.hud.jobs_screen == null, "and shuts it")
	eq(ctx.speeds, [0, 2], "with the same pauses")
	ctx.speeds.clear()
	Kit.update(ctx, 0)
	ctx.hud.open_jobs()
	ctx.hud.close_jobs()
	eq(ctx.speeds, [], "a game that was paused stays paused")
	Kit.free_all(ctx)


func test_the_page_plays_the_menu_sounds() -> void:
	var ctx := Kit.build()
	Kit.update(ctx)
	var heard: Array = []
	ctx.hud.on_ui_sound = func(sound_name, _level): heard.append(sound_name)
	ctx.hud.open_jobs()
	eq(heard, ["ui_open"], "opening it")
	var s = ctx.hud.jobs_screen
	heard.clear()
	s.choose_job(Kit.person(ctx, "walt"), "garden")
	eq(heard, ["ui_click"], "a choice")
	heard.clear()
	s.choose_job(Kit.person(ctx, "walt"), "radio")
	eq(heard, ["ui_error"], "a choice that is refused")
	heard.clear()
	s.auto_button.pressed.emit()
	eq(heard, ["ui_confirm"], "Auto-assign")
	heard.clear()
	s.clear_button.pressed.emit()
	eq(heard, ["ui_click"], "Clear")
	heard.clear()
	s.close_button.pressed.emit()
	eq(heard, ["ui_close"], "closing it")
	# nothing listening: nothing breaks
	ctx.hud.on_ui_sound = Callable()
	ctx.hud.open_jobs()
	ctx.hud.close_jobs()
	Kit.free_all(ctx)


func test_escape_shuts_the_list_first_and_then_the_page() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	s.open_job_list(Kit.person(ctx, "ana"))
	check(s.list != null, "a list is open")
	s._input(_key(KEY_ESCAPE))
	check(s.list == null and ctx.hud.jobs_screen == s, "the first Esc shuts the list and leaves the page")
	s.open_post_list(Kit.person(ctx, "ana"))
	s._input(_key(KEY_J))
	check(ctx.hud.jobs_screen == null, "J shuts the page even with a list open")
	Kit.free_all(ctx)


func test_the_page_closes_when_the_run_ends() -> void:
	var ctx := _open()
	ctx.hud.save_paths = []
	ctx.sim.over = "defeat"
	Kit.update(ctx, 0)
	check(ctx.hud.jobs_screen == null and ctx.hud.game_over != null, "the report card takes its place")
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the marks --

func test_hovering_a_row_a_station_or_a_post_marks_its_place_in_the_world() -> void:
	var ctx := Kit.build()
	Kit.update(ctx)
	var marks: Array = []
	ctx.hud.on_jobs_hover = func(d): marks.append(d.duplicate())
	ctx.hud.open_jobs()
	var s = ctx.hud.jobs_screen
	eq(marks.back(), BLANK, "open: every station is marked faintly and nothing is lit")
	s.rows.dez.row.mouse_entered.emit()
	eq(marks.back(), {"station": "bench", "post": "bus", "person": "dez"}, "a row marks the person's station, post and the person")
	s.rows.dez.row.mouse_exited.emit()
	eq(marks.back(), BLANK, "and lets go")
	s.station_cards.garden.card.mouse_entered.emit()
	eq(marks.back(), {"station": "garden", "post": "", "person": ""}, "a station marks itself")
	s.station_cards.garden.card.mouse_exited.emit()
	eq(marks.back(), BLANK, "and lets go")
	s.open_post_list(Kit.person(ctx, "ruth"))
	eq(marks.back(), BLANK, "a list with nothing under the mouse marks nothing")
	s.list_items.north_middle.mouse_entered.emit()
	eq(marks.back(), {"station": "", "post": "north_middle", "person": "ruth"}, "a post on the list marks its place")
	s.close_list()
	eq(marks.back(), {"station": "radio", "post": "gate", "person": "ruth"}, "put away, the keyboard goes back to her button and her row is the one marked")
	s.rows.ruth.row.mouse_exited.emit()
	eq(marks.back(), BLANK, "and the mark goes when the pointer leaves her row")
	s.open_job_list(Kit.person(ctx, "ruth"))
	s.list_items.infirmary.mouse_entered.emit()
	eq(marks.back().station, "infirmary", "a station on the job list marks its place")
	s.close_list()
	s.rows.ana.job.focus_entered.emit()
	eq(marks.back(), {"station": "infirmary", "post": "west_fence", "person": "ana"}, "the keyboard on a row marks it the same way")
	ctx.hud.close_jobs()
	eq(marks.back(), {}, "closed: nothing is marked")
	eq(ctx.hud.jobs_hover, {}, "and the HUD remembers it")
	Kit.free_all(ctx)


func test_a_place_on_a_list_lets_the_page_fade_to_show_the_yard_and_it_comes_back() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	check(not s.peeking and s.panel.modulate.a > 0.99, "the page is solid at first")
	s.open_post_list(Kit.person(ctx, "ruth"))
	s.list_items.north_middle.mouse_entered.emit()
	check(s.peeking, "a post under the mouse: the page peeks")
	await Engine.get_main_loop().create_timer(0.3).timeout
	check(s.panel.modulate.a < 0.3, "the page is thin: %.2f" % s.panel.modulate.a)
	check(s.list.modulate.a > 0.99, "the list itself stays solid")
	s.close_list()
	check(not s.peeking, "the list shut: it does not")
	await Engine.get_main_loop().create_timer(0.3).timeout
	check(s.panel.modulate.a > 0.99, "and the page is solid again: %.2f" % s.panel.modulate.a)
	# a person's row or a station card does not fade the page: it would flicker as the mouse crosses the table
	s.rows.dez.row.mouse_entered.emit()
	s.station_cards.garden.card.mouse_entered.emit()
	check(not s.peeking, "no peek for a row or a card")
	# the job list peeks at stations, and "No job" at nothing
	s.open_job_list(Kit.person(ctx, "ruth"))
	s.list_items.garden.mouse_entered.emit()
	check(s.peeking and s.marks().station == "garden", "a station on the job list: the page peeks at it")
	s.list_items[""].mouse_entered.emit()
	check(not s.peeking, "No job marks no place")
	Kit.free_all(ctx)


func test_opening_a_list_does_not_fade_the_page_but_moving_about_it_with_the_keyboard_does() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.jobs_screen
	s.open_job_list(Kit.person(ctx, "walt"))
	await Kit.settle()
	await Kit.settle()
	check(not s.peeking, "the keyboard lands on the person's own job when the list opens: only a mark, no fade")
	eq(s.marks().station, "builders", "his own station is marked")
	_press(KEY_DOWN)
	await Kit.settle()
	check(s.peeking, "an arrow to another line: the page peeks at it")
	check(s.marks().station != "builders", "and that line's place is marked: %s" % str(s.marks()))
	s.close_list()
	check(not s.peeking, "shut: it is solid again")
	Kit.free_all(ctx)


func test_reduced_motion_peeks_at_once() -> void:
	var Prefs := load("res://scripts/prefs.gd")
	Prefs.path = "user://prefs_test.cfg"
	Prefs.reset()
	Prefs.set_value("ui", "reduce_motion", true)
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	s.show_marks("bench", "", "", true)
	check(s.panel.modulate.a < 0.3, "the page is thin at once: %.2f" % s.panel.modulate.a)
	s.show_marks()
	check(s.panel.modulate.a > 0.99, "and solid at once")
	Kit.free_all(ctx)
	Prefs.reset()


func test_a_closed_page_marks_nothing_whatever_its_controls_say_on_the_way_out() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	s.rows.dez.row.mouse_entered.emit()
	eq(ctx.hud.jobs_hover.person, "dez", "a row is marked")
	ctx.hud.close_jobs()
	eq(ctx.hud.jobs_hover, {}, "closed: nothing")
	# the controls that are freed with the page may still say they lost the mouse or the keyboard
	s.rows.dez.row.mouse_exited.emit()
	s.rows.dez.job.focus_exited.emit()
	s.station_cards.garden.card.mouse_entered.emit()
	s.show_marks("bench", "gate", "dez", true)
	eq(ctx.hud.jobs_hover, {}, "and it stays so")
	Kit.free_all(ctx)


func test_the_screen_can_be_told_to_mark_a_place_for_the_screenshots() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	s.show_marks("bench")
	eq(ctx.hud.jobs_hover, {"station": "bench", "post": "", "person": ""}, "a station")
	eq(s.marks(), {"station": "bench", "post": "", "person": ""}, "the page says what it marks")
	s.show_marks("", "gate")
	eq(ctx.hud.jobs_hover.post, "gate", "a post")
	Kit.free_all(ctx)


# ------------------------------------------------------------------- the keyboard --

func test_every_control_can_have_the_keyboard() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.jobs_screen
	var buttons := 0
	var sliders := 0
	for c in s.find_children("*", "Button", true, false):
		if not c.disabled:
			buttons += 1
			eq(c.focus_mode, Control.FOCUS_ALL, "the button '%s' can have the keyboard" % str(c.tooltip_text).left(24))
	for c in s.find_children("*", "HSlider", true, false):
		sliders += 1
		eq(c.focus_mode, Control.FOCUS_ALL, "a slider can have the keyboard")
	eq(buttons, 6 * 2 + 3, "two buttons for each person and the three at the foot")
	eq(sliders, 3, "and the three sliders")
	check(_focus_owner() == null, "nothing has the keyboard when the page opens")
	_press(KEY_TAB)
	check(_focus_owner() == s.rows.ruth.job, "the first Tab puts it on the first person's job")
	Kit.free_all(ctx)


func test_tab_enter_the_arrows_and_escape_work_the_page() -> void:
	var ctx := _open()
	await Kit.settle()
	await Kit.settle()
	var s = ctx.hud.jobs_screen
	_press(KEY_TAB)
	eq(_focus_owner(), s.rows.ruth.job, "the first Tab puts the keyboard on Ruth's job")
	_press(KEY_TAB)
	eq(_focus_owner(), s.rows.ruth.post, "Tab goes to her post")
	_press(KEY_TAB)
	eq(_focus_owner(), s.rows.dez.job, "and on to the next person's job")
	_press(KEY_ENTER)
	await Kit.settle()
	check(s.list != null and s.list_kind == "job" and s.list_for == Kit.person(ctx, "dez"), "Enter opens the list")
	var first := _focus_owner()
	check(first is Button and s.list.is_ancestor_of(first), "with the keyboard in it")
	_press(KEY_DOWN)
	var second := _focus_owner()
	check(second != first and second is Button and s.list.is_ancestor_of(second), "the arrow moves down the list")
	_press(KEY_UP)
	eq(_focus_owner(), first, "and back up")
	_press(KEY_ESCAPE)
	await Kit.settle()
	check(s.list == null and ctx.hud.jobs_screen == s, "Esc shuts the list")
	eq(_focus_owner(), s.rows.dez.job, "and the keyboard is back on the button it came from")
	# the choice by the keyboard: open Hector's, go down to No job and take it
	_press(KEY_TAB)
	_press(KEY_TAB)
	check(_focus_owner() == s.rows.ana.job, "Tab on")
	_press(KEY_ENTER)
	await Kit.settle()
	s.list_items[""].grab_focus()
	_press(KEY_ENTER)
	await Kit.settle()
	eq(ctx.sim.jobs.job_of(Kit.person(ctx, "ana")), "", "Enter on No job takes Ana off the infirmary")
	_press(KEY_ESCAPE)
	check(ctx.hud.jobs_screen == null, "Esc shuts the page")
	Kit.free_all(ctx)


## Where main.gd's _unhandled_input would be: it writes down the keys that reach it.
class Listener:
	extends Node
	var heard: Array = []

	func _unhandled_input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed:
			heard.append(ev.keycode)


func test_a_held_escape_or_j_shuts_one_thing_not_two() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.jobs_screen
	s.open_job_list(Kit.person(ctx, "ana"))
	await Kit.settle()
	s._input(_key(KEY_ESCAPE))
	check(s.list == null and ctx.hud.jobs_screen == s, "the first Esc shuts the list")
	s.open_job_list(Kit.person(ctx, "ana"))
	var echo := _key(KEY_ESCAPE)
	echo.echo = true
	s._input(echo)
	check(s.list != null and ctx.hud.jobs_screen == s, "the key repeating does nothing")
	var j_echo := _key(KEY_J)
	j_echo.echo = true
	s._input(j_echo)
	check(ctx.hud.jobs_screen == s, "nor does a repeating J")
	Kit.free_all(ctx)


func test_the_game_does_not_hear_the_keys_while_the_page_is_up() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.jobs_screen
	var listener := Listener.new()
	Engine.get_main_loop().root.add_child(listener)
	_press(KEY_R)
	_press(KEY_M)
	eq(listener.heard.filter(func(k): return k == KEY_R or k == KEY_M), [], "R and M are the page's, not the game's")
	s.open_job_list(Kit.person(ctx, "ana"))
	await Kit.settle()
	_press(KEY_B)
	eq(listener.heard.filter(func(k): return k == KEY_B), [], "nor with a list open")
	s.close()
	await Kit.settle()
	_press(KEY_R)
	eq(listener.heard.filter(func(k): return k == KEY_R), [KEY_R], "once the page is gone the keys reach the game again")
	listener.free()
	Kit.free_all(ctx)


func test_a_slider_moves_with_the_arrows() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.jobs_screen
	var slider: HSlider = s.station_cards.bench.sliders.ammo_target
	slider.grab_focus()
	eq(_focus_owner(), slider, "the keyboard is on the slider")
	_press(KEY_RIGHT)
	eq(int(ctx.sim.jobs.setting("bench", "ammo_target")), 325, "a step to the right is 25 more")
	_press(KEY_LEFT)
	_press(KEY_LEFT)
	eq(int(ctx.sim.jobs.setting("bench", "ammo_target")), 275, "two to the left")
	Kit.free_all(ctx)


func test_the_mouse_opens_a_list_and_picks_from_it() -> void:
	var ctx := _open()
	await Kit.settle()
	await Kit.settle()
	var s = ctx.hud.jobs_screen
	Kit.click_on(s.rows.walt.job)
	await Kit.settle()
	check(s.list != null and s.list_for == Kit.person(ctx, "walt"), "a click on the job opens the list")
	await Kit.settle()
	Kit.click_on(s.list_items.garden)
	eq(ctx.sim.jobs.job_of(Kit.person(ctx, "walt")), "garden", "a click on a station gives it")
	check(s.list == null, "and shuts the list")
	Kit.click_on(s.rows.ruth.post)
	await Kit.settle()
	check(s.list != null and s.list_kind == "post", "a click on the post opens the posts")
	await Kit.settle()
	Kit.click_on(s.list_items.bus)
	eq(String(ctx.sim.jobs.post_of(Kit.person(ctx, "ruth")).id), "gate", "a post that is taken does nothing")
	check(s.list != null, "and the list stays")
	Kit.click(Vector2(5, 5))
	check(s.list == null and ctx.hud.jobs_screen == s, "a click outside only shuts the list")
	Kit.click_on(s.clear_button)
	eq(ctx.sim.jobs.job_of(Kit.person(ctx, "dez")), "", "a click on Clear clears")
	Kit.click_on(s.close_button)
	check(ctx.hud.jobs_screen == null, "a click on Close closes")
	Kit.free_all(ctx)


## One turn of the mouse wheel at `at`, as the engine hears it.
func _wheel(at: Vector2, down: bool = true) -> void:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.factor = 1.0
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)


func test_the_wheel_scrolls_the_page_over_a_button_a_slider_or_a_card() -> void:
	var ctx: Dictionary = await _settled(700, 560)
	var s = ctx.hud.jobs_screen
	eq(s.scroll.scroll_vertical, 0, "the page starts at the top")
	_wheel(Kit.rect(s.rows.ruth.job).get_center())
	await Kit.settle()
	var after_button: int = s.scroll.scroll_vertical
	check(after_button > 0, "a turn of the wheel over a button scrolls the page: %d" % after_button)
	s.scroll.scroll_vertical = int(s.scroll.get_v_scroll_bar().max_value) - 40
	await Kit.settle()
	var slider: HSlider = s.station_cards.bench.sliders.ammo_target
	var before := int(s.scroll.scroll_vertical)
	_wheel(Kit.rect(slider).get_center(), false)
	await Kit.settle()
	check(s.scroll.scroll_vertical < before, "over a slider it scrolls the page, not the slider: %d then %d" % [before, s.scroll.scroll_vertical])
	eq(int(ctx.sim.jobs.setting("bench", "ammo_target")), 300, "and the setting is as it was")
	Kit.free_all(ctx)


func test_clicks_do_not_reach_the_game_behind_the_page() -> void:
	var ctx := _open()
	Kit.select(ctx, Kit.person(ctx, "ana"))
	await Kit.settle()
	var behind: Button = Kit.gizmo(ctx, "draft")
	Kit.click_on(behind)
	eq(ctx.pressed, [], "the Draft button under the page does not fire")
	Kit.free_all(ctx)


# --------------------------------------------------------- the marks in the world --
# (the overlay draws what main.gd's `jobs_hover` says; here main is a stand-in with that field)

const OverlayNode := preload("res://scripts/render/overlay_node.gd")


## What the overlay reads of main.gd.
class FakeMain:
	extends Node
	var sim
	var zoom_px := 12.0
	var selection = null
	var hover = null
	var order_mark = null
	var clock := 0.0
	var fields := false
	var jobs_hover := {}

	func view_pos(e) -> Vector2:
		return Vector2(e.x, e.y)


## An overlay in the tree over `ctx`'s game at `zoom` pixels a tile; `shift` moves the map in the window.
func _overlay(ctx: Dictionary, zoom: float, shift: Vector2 = Vector2.ZERO) -> Dictionary:
	var main := FakeMain.new()
	main.sim = ctx.sim
	main.zoom_px = zoom
	var layer := CanvasLayer.new()
	var overlay := OverlayNode.new()
	overlay.main = main
	layer.add_child(overlay)
	main.add_child(layer)
	Engine.get_main_loop().root.add_child(main)
	overlay.get_viewport().canvas_transform = Transform2D(0.0, Vector2.ONE * zoom / OverlayNode.TILE, 0.0, shift)
	return {"main": main, "overlay": overlay}


func _free_overlay(o: Dictionary) -> void:
	o.overlay.get_viewport().canvas_transform = Transform2D.IDENTITY
	o.main.free()


func _draw_once(o: Dictionary) -> void:
	o.overlay.queue_redraw()
	await Kit.settle()


func test_nothing_is_drawn_for_the_jobs_screen_while_it_is_shut() -> void:
	var ctx := Kit.build()
	var o := _overlay(ctx, 12.0)
	await _draw_once(o)
	eq([o.overlay.drawn_job_stations, o.overlay.drawn_job_lit, o.overlay.drew_job_post, o.overlay.drawn_job_edges], [0, 0, false, 0], "no marks")
	_free_overlay(o)
	Kit.free_all(ctx)


func test_with_the_page_up_every_station_is_marked_faintly_and_what_it_points_at_firmly() -> void:
	var ctx := Kit.build()
	var o := _overlay(ctx, 12.0)
	o.main.jobs_hover = BLANK.duplicate()
	await _draw_once(o)
	eq(o.overlay.drawn_job_stations, 6, "the six stations are marked")
	eq(o.overlay.drawn_job_lit, 0, "and none is lit")
	check(not o.overlay.drew_job_post, "no night post")
	o.main.jobs_hover = {"station": "bench", "post": "", "person": ""}
	await _draw_once(o)
	eq([o.overlay.drawn_job_stations, o.overlay.drawn_job_lit], [6, 1], "the bench is lit among the six")
	o.main.jobs_hover = {"station": "bench", "post": "gate", "person": "ruth"}
	await _draw_once(o)
	check(o.overlay.drew_job_post, "and a night post is marked with it")
	o.main.jobs_hover = {}
	await _draw_once(o)
	eq([o.overlay.drawn_job_stations, o.overlay.drawn_job_lit, o.overlay.drew_job_post], [0, 0, false], "the page shut: nothing again")
	_free_overlay(o)
	Kit.free_all(ctx)


func test_a_place_out_of_the_window_gets_an_arrow_at_the_edge() -> void:
	var ctx := Kit.build()
	# 40 px a tile with the map pushed far to the left of the window: the stations and the posts are all out of it
	var o := _overlay(ctx, 40.0, Vector2(-3000.0, -300.0))
	o.main.jobs_hover = {"station": "bench", "post": "gate", "person": ""}
	await _draw_once(o)
	eq(o.overlay.drawn_job_lit, 0, "the bench is out of the window")
	check(o.overlay.drawn_job_edges >= 1, "so an arrow shows the way: %d" % o.overlay.drawn_job_edges)
	# nothing lit and nothing out of the window: no arrows
	o.main.jobs_hover = BLANK.duplicate()
	await _draw_once(o)
	eq(o.overlay.drawn_job_edges, 0, "a station that is not lit gets no arrow")
	_free_overlay(o)
	Kit.free_all(ctx)


func test_the_marks_follow_the_game_and_cost_nothing_in_the_rules() -> void:
	var ctx := Kit.build()
	var o := _overlay(ctx, 12.0)
	o.main.jobs_hover = {"station": "radio", "post": "bus", "person": "dez"}
	var before := "%s|%s" % [str(ctx.sim.jobs.save()), str(ctx.sim.stock)]
	await _draw_once(o)
	eq("%s|%s" % [str(ctx.sim.jobs.save()), str(ctx.sim.stock)], before, "drawing changes nothing")
	_free_overlay(o)
	Kit.free_all(ctx)


# ------------------------------------------------------------- the page fits --

## Everything that is wrong with how the page sits in a window of this size, as words (none: it fits).
func _misfits(ctx: Dictionary, size: Array) -> Array:
	var bad: Array = []
	var s = ctx.hud.jobs_screen
	var win := Rect2(0, 0, size[0], size[1])
	var panel := Kit.rect(s.panel)
	if panel.size == Vector2.ZERO or not win.encloses(panel.grow(-0.5)):
		bad.append("the page %s is not inside the window" % str(panel))
	var scroll_rect := Kit.rect(s.scroll)
	if not panel.encloses(scroll_rect):
		bad.append("the body %s is not inside the page %s" % [str(scroll_rect), str(panel)])
	var foot := {"auto": Kit.rect(s.auto_button), "clear": Kit.rect(s.clear_button), "close": Kit.rect(s.close_button), "hint": Kit.rect(s.hint_label)}
	for name in foot:
		if foot[name].size == Vector2.ZERO or not panel.encloses(foot[name]):
			bad.append("the %s at the foot is not in the page: %s" % [name, str(foot[name])])
	bad.append_array(Kit.overlaps(foot))
	if scroll_rect.end.y > foot.auto.position.y + 0.5:
		bad.append("the body runs into the buttons at the foot")
	# nothing is wider than the room it is given
	if s.body.get_combined_minimum_size().x > s.scroll.size.x + 0.5:
		bad.append("the body asks for %.0f px and has %.0f" % [s.body.get_combined_minimum_size().x, s.scroll.size.x])
	# a row: its cells are apart and inside it
	for id in s.rows:
		var r: Dictionary = s.rows[id]
		var row := Kit.rect(r.row)
		var cells := {"who": Kit.rect(r.who), "job": Kit.rect(r.job), "post": Kit.rect(r.post), "skills": Kit.rect(r.skills.Shooting.get_parent()), "doing": Kit.rect(r.doing)}
		for name in cells:
			if cells[name].size == Vector2.ZERO or not row.encloses(cells[name].grow(-0.5)):
				bad.append("%s's %s %s is not in its row %s" % [id, name, str(cells[name]), str(row)])
		for hit in Kit.overlaps(cells):
			bad.append("%s's row: %s" % [id, hit])
		if row.end.x > scroll_rect.end.x + 0.5:
			bad.append("%s's row runs past the body" % id)
	# the stations: apart, inside the body, with their pips and sliders inside them
	var cards := {}
	for id in s.station_cards:
		var c: Dictionary = s.station_cards[id]
		cards[id] = Kit.rect(c.card)
		if cards[id].end.x > scroll_rect.end.x + 0.5:
			bad.append("the %s card runs past the body" % id)
		for pip in c.pips:
			if not cards[id].encloses(Kit.rect(pip).grow(-0.5)):
				bad.append("a seat of the %s is outside its card" % id)
		for key in c.sliders:
			if not cards[id].encloses(Kit.rect(c.sliders[key]).grow(-0.5)) or not cards[id].encloses(Kit.rect(c.values[key]).grow(-0.5)):
				bad.append("the %s slider of the %s is outside its card" % [key, id])
	bad.append_array(Kit.overlaps(cards))
	return bad


func _settled(width: int, height: int) -> Dictionary:
	var ctx := _open(width, height)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	# (once the page is laid out: before that every button is at the corner, and the engine takes the pointer there
	# to be on the one on top until it moves)
	_park_the_mouse()
	await Kit.settle()
	return ctx


func test_the_page_fits_and_overlaps_nothing_at_700_980_1280_and_1920() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _settled(size[0], size[1])
		eq(_misfits(ctx, size), [], "%d x %d" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_the_page_fits_a_short_window_and_scrolls() -> void:
	for size in SHORT:
		var ctx: Dictionary = await _settled(size[0], size[1])
		var s = ctx.hud.jobs_screen
		eq(_misfits(ctx, size), [], "%d x %d" % [size[0], size[1]])
		var room: float = s.scroll.size.y
		check(s.body.get_combined_minimum_size().y > room, "%d x %d: too short for it all, so the body scrolls (%.0f in %.0f)" % [size[0], size[1], s.body.get_combined_minimum_size().y, room])
		# scrolled to the end, the last station and the foot are there
		s.scroll.scroll_vertical = int(s.scroll.get_v_scroll_bar().max_value)
		await Kit.settle()
		var last := Kit.rect(s.station_cards.watch.card)
		var view := Kit.rect(s.scroll)
		check(view.grow(1.0).encloses(last.grow(-0.5)), "%d x %d: the last station card is in view at the end of the scroll: %s in %s" % [size[0], size[1], str(last), str(view)])
		Kit.free_all(ctx)


func test_the_whole_page_is_in_view_without_scrolling_in_a_window_800_tall() -> void:
	for size in [[1280, 800], [1920, 1080]]:
		var ctx: Dictionary = await _settled(size[0], size[1])
		var s = ctx.hud.jobs_screen
		check(s.body.get_combined_minimum_size().y <= s.scroll.size.y + 0.5, "%d x %d: the table and the stations fit (%.0f in %.0f)" % [size[0], size[1], s.body.get_combined_minimum_size().y, s.scroll.size.y])
		var view := Kit.rect(s.scroll)
		for id in s.station_cards:
			check(view.grow(1.0).encloses(Kit.rect(s.station_cards[id].card).grow(-0.5)), "%d x %d: the %s card is in view" % [size[0], size[1], id])
		Kit.free_all(ctx)


func test_a_narrow_window_stacks_the_rows_and_the_stations() -> void:
	var wide: Dictionary = await _settled(1280, 800)
	var narrow: Dictionary = await _settled(700, 700)
	var w = wide.hud.jobs_screen
	var n = narrow.hud.jobs_screen
	check(w._wide and w.table_head.visible, "wide: the table is on one line with its captions")
	check(not n._wide and not n.table_head.visible, "narrow: the rows run on and the captions go into the cells")
	var wr := Kit.rect(w.rows.dez.row)
	var nr := Kit.rect(n.rows.dez.row)
	check(nr.size.y > wr.size.y + 20.0, "a narrow row is taller (two lines): %.0f against %.0f" % [nr.size.y, wr.size.y])
	check(Kit.rect(n.rows.dez.skills.Shooting.get_parent()).position.y > Kit.rect(n.rows.dez.job).end.y, "the skills are on the second line, under the buttons")
	eq(w.stations_box.columns, 3, "wide: the stations go three across")
	check(n.stations_box.columns <= 2, "narrow: two across at most")
	for ctx in [wide, narrow]:
		Kit.free_all(ctx)


func test_the_page_is_laid_out_again_when_the_window_changes() -> void:
	var ctx: Dictionary = await _settled(1280, 800)
	var s = ctx.hud.jobs_screen
	Kit.resize(ctx, 700, 700)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	eq(_misfits(ctx, [700, 700]), [], "shrunk to 700")
	check(not s._wide, "and the rows are stacked")
	Kit.resize(ctx, 1280, 800)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	eq(_misfits(ctx, [1280, 800]), [], "grown back")
	check(s._wide, "and on one line again")
	Kit.free_all(ctx)


func test_the_lists_fit_the_window_and_scroll_when_they_are_long() -> void:
	for size in [[1280, 800], [700, 700], [700, 560]]:
		var ctx: Dictionary = await _settled(size[0], size[1])
		var s = ctx.hud.jobs_screen
		var win := Rect2(0, 0, size[0], size[1])
		for kind in ["job", "post"]:
			for id in ["ruth", "hector"]:
				var p = Kit.person(ctx, id)
				if kind == "job":
					s.open_job_list(p)
				else:
					s.open_post_list(p)
				await Kit.settle()
				await Kit.settle()
				var r := Kit.rect(s.list)
				check(r.size != Vector2.ZERO and win.encloses(r.grow(-0.5)), "%d x %d: %s list for %s is in the window: %s" % [size[0], size[1], kind, id, str(r)])
				var opener := Kit.rect(s.rows[id].job if kind == "job" else s.rows[id].post)
				check(not r.intersects(opener.grow(-1.0)), "%d x %d: the %s list does not cover its own button" % [size[0], size[1], kind])
				for item in s.list_items.values():
					var ir := Kit.rect(item)
					if ir.size != Vector2.ZERO and ir.end.y <= Kit.rect(s._list_scroll).end.y + 0.5 and ir.position.y >= Kit.rect(s._list_scroll).position.y - 0.5:
						check(r.encloses(ir.grow(-0.5)), "an item in view is inside the list")
				s.close_list()
		Kit.free_all(ctx)


# ------------------------------------------------------------------- the text --

func test_nothing_on_the_page_is_under_twelve_pixels_at_any_size() -> void:
	var tt := TextTests.new()
	for size in [[1280, 800], [700, 700], [700, 560]]:
		var ctx: Dictionary = await _settled(size[0], size[1])
		var s = ctx.hud.jobs_screen
		eq(tt._small_text(s), [], "%d x %d" % [size[0], size[1]])
		s.open_post_list(Kit.person(ctx, "ruth"))
		eq(tt._small_text(s), [], "%d x %d, with the post list" % [size[0], size[1]])
		s.open_job_list(Kit.person(ctx, "walt"))
		eq(tt._small_text(s), [], "%d x %d, with the job list" % [size[0], size[1]])
		s.close_list()
		s.choose_job(Kit.person(ctx, "walt"), "radio")
		eq(tt._small_text(s), [], "%d x %d, with the line at the foot" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_every_word_on_the_page_reads_on_the_paper_in_either_look() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		Hud.use_frames = frames
		var look := "frames" if frames else "flat"
		for size in [[1280, 800], [700, 700]]:
			_park_the_mouse()
			var ctx := Kit.build(size[0], size[1])
			Kit.person(ctx, "walt").dead = true
			Kit.person(ctx, "walt").turned = true
			Kit.person(ctx, "dez").away = {"kind": "party", "site": "pharmacy"}
			ctx.sim.morale.values["marcus"] = 30.0
			ctx.sim.morale.values["hector"] = 10.0
			ctx.sim.morale.values["ana"] = 90.0
			Kit.update(ctx)
			ctx.hud.open_jobs()
			var s = ctx.hud.jobs_screen
			await Kit.settle()
			await Kit.settle()
			_park_the_mouse()
			await Kit.settle()
			eq(tt._hard_to_read(s, Color.WHITE), [], "%s, %d: the page" % [look, size[0]])
			s.choose_job(Kit.person(ctx, "ruth"), "bench")
			s.choose_job(Kit.person(ctx, "ana"), "radio")
			eq(tt._hard_to_read(s, Color.WHITE), [], "%s, %d: with the line at the foot" % [look, size[0]])
			s.open_post_list(Kit.person(ctx, "ruth"))
			await Kit.settle()
			eq(tt._hard_to_read(s, Color.WHITE), [], "%s, %d: with the post list" % [look, size[0]])
			s.open_job_list(Kit.person(ctx, "hector"))
			await Kit.settle()
			eq(tt._hard_to_read(s, Color.WHITE), [], "%s, %d: with the job list (full stations greyed)" % [look, size[0]])
			eq(tt._dark_red_words(s), [], "%s, %d: no word in the dark red" % [look, size[0]])
			Kit.free_all(ctx)
	Hud.use_frames = true


func test_the_page_is_dark_ink_on_light_paper_and_the_buttons_are_the_dialogs() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	var fills: Array = Kit.fills(s.panel.get_theme_stylebox("panel"))
	check(fills[0].v > 0.7 and fills[1].v > 0.7, "the page is pale: %s" % str(fills))
	for l in s.find_children("*", "Label", true, false):
		var ink: Color = l.get_theme_color("font_color")
		if l.text != "" and ink.v > 0.5:
			failures.append("'%s' is set in a pale ink (%s) on a pale page" % [l.text, str(ink)])
	var close_box: StyleBox = s.close_button.get_theme_stylebox("normal")
	var dialog_ref: Button = ctx.hud._button("Close", true, true)
	eq(s.close_button.get_theme_color("font_color"), dialog_ref.get_theme_color("font_color"), "Close is the main choice, in the dialogs' gold")
	check(close_box != null, "with its own look")
	dialog_ref.free()
	Kit.free_all(ctx)


func test_the_parts_of_the_page_can_be_pointed_at_by_name() -> void:
	var ctx := _open()
	await Kit.settle()
	await Kit.settle()
	var h = ctx.hud
	var s = h.jobs_screen
	for pair in [["jobs", h.jobs_button], ["jobs.screen", s.panel], ["jobs.auto", s.auto_button], ["jobs.clear", s.clear_button], ["jobs.close", s.close_button],
			["jobs.row:dez", s.rows.dez.row], ["jobs.job:dez", s.rows.dez.job], ["jobs.post:ruth", s.rows.ruth.post], ["jobs.station:garden", s.station_cards.garden.card]]:
		var r: Rect2 = h.anchor_rect(pair[0])
		check(r.size != Vector2.ZERO and r == Kit.rect(pair[1]), "%s is found: %s" % [pair[0], str(r)])
	eq(h.anchor_rect("jobs.list"), Rect2(), "no list yet, no rectangle")
	s.open_post_list(Kit.person(ctx, "ruth"))
	await Kit.settle()
	check(h.anchor_rect("jobs.list").size != Vector2.ZERO and h.anchor_rect("jobs.item:north_middle").size != Vector2.ZERO, "the open list and a line of it")
	eq(h.anchor_rect("jobs.row:nobody"), Rect2(), "a person who is not there")
	eq(h.anchor_rect("jobs.station:nowhere"), Rect2(), "a station that is not")
	h.close_jobs()
	eq(h.anchor_rect("jobs.auto"), Rect2(), "and nothing once the page is shut")
	check(h.anchor_rect("jobs").size != Vector2.ZERO, "(the toolbar's own key stays)")
	Kit.free_all(ctx)


func test_the_tutorials_lock_ghosts_the_jobs_key_unless_the_step_teaches_it() -> void:
	var ctx := Kit.build()
	var b: Button = ctx.hud.jobs_button
	check(b.modulate.a > 0.99, "bright with no lock")
	ctx.hud.set_locked(func(kind: String, _arg): return kind == "jobs")
	check(b.modulate.a > 0.9, "bright while the step teaches it")
	ctx.hud.set_locked(func(_kind: String, _arg): return false)
	check(b.modulate.a < 0.5, "a ghost while it does not")
	eq(b.mouse_default_cursor_shape, Control.CURSOR_FORBIDDEN, "with a cursor that says no")
	check(not b.disabled, "but it can still be pressed: the game refuses and says why")
	ctx.hud.set_locked(Callable())
	check(b.modulate.a > 0.99 and b.mouse_default_cursor_shape == Control.CURSOR_ARROW, "and as it was once the lock is lifted")
	Kit.free_all(ctx)


func test_the_icons_of_the_stations_and_the_toolbar_are_there() -> void:
	var ctx := _open()
	var s = ctx.hud.jobs_screen
	for st in ctx.sim.jobs.stations():
		check(ctx.hud.icons.has(String(st.icon)), "the icon '%s' of the %s is loaded" % [st.icon, st.name])
	check(ctx.hud.icons.has("jobs") and ctx.hud.icons.has("moon"), "the clipboard and the moon too")
	check(s.rows.dez.post_icon.texture == ctx.hud.icons["moon"], "a post wears the moon")
	eq(ctx.hud.jobs_button.get_meta("icon").texture, ctx.hud.icons["jobs"], "the toolbar's key wears the clipboard")
	eq(ctx.hud.jobs_button.tooltip_text, "Jobs: who works where by day and holds which post at night\nKey: J", "and says what it is and its key")
	eq(ctx.hud.jobs_button.custom_minimum_size, ctx.hud.help_button.custom_minimum_size, "as big as its neighbours")
	eq(ctx.hud.jobs_button.focus_mode, Control.FOCUS_NONE, "and, like them, not a stop for the keyboard")
	Kit.free_all(ctx)


func test_the_clipboard_is_white_on_clear_and_64_pixels_like_the_other_icons() -> void:
	var path: String = Hud.EXTRA_ICONS["jobs"]
	check(ResourceLoader.exists(path), "the picture is imported: %s" % path)
	var tex: Texture2D = load(path)
	check(tex != null, "it loads")
	if tex == null:
		return
	eq(tex.get_size(), Vector2(64, 64), "64 by 64, as every icon is")
	var img: Image = tex.get_image()
	var opaque := 0
	var tinted := 0
	for y in 64:
		for x in 64:
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				opaque += 1
			if c.a > 0.02 and (c.r < 0.98 or c.g < 0.98 or c.b < 0.98):
				tinted += 1
	check(opaque > 300 and opaque < 2400, "a sensible amount of ink: %d px" % opaque)
	eq(tinted, 0, "pure white with alpha: the HUD tints it")


# ------------------------------------------------------------------------- fuzz --

## What the page says about everyone and every station, against what the game says: a list of what does not match.
func _page_matches_the_game(ctx: Dictionary) -> Array:
	var bad: Array = []
	var s = ctx.hud.jobs_screen
	var jobs = ctx.sim.jobs
	for p in ctx.sim.people:
		var r: Dictionary = s.rows[p.id]
		var gone: bool = p.dead or p.turned
		var want_job := "–" if gone else (String(jobs.station(jobs.job_of(p)).get("name", "No job")) if jobs.job_of(p) != "" else "No job")
		if Kit.texts(r.job) != [want_job]:
			bad.append("%s's job reads %s, not '%s'" % [p.id, str(Kit.texts(r.job)), want_job])
		var want_post := "–" if gone else String(jobs.post_of(p).name)
		if Kit.texts(r.post) != [want_post]:
			bad.append("%s's post reads %s, not '%s'" % [p.id, str(Kit.texts(r.post)), want_post])
		if r.job.disabled != not s.can_assign(p) or r.post.disabled != not s.can_assign(p):
			bad.append("%s's buttons are %s/%s with can_assign %s" % [p.id, r.job.disabled, r.post.disabled, s.can_assign(p)])
		for skill in ["Shooting", "Building", "Medicine", "Leading"]:
			var marked: bool = not gone and jobs.job_of(p) != "" and String(jobs.station(jobs.job_of(p)).skill) == skill
			if bool(r.skills[skill].get_meta("marked")) != marked:
				bad.append("%s's %s is marked %s" % [p.id, skill, r.skills[skill].get_meta("marked")])
	for st in jobs.stations():
		var c: Dictionary = s.station_cards[st.id]
		var crew: Array = jobs.crew_of(st.id)
		var want: Array = []
		for i in c.pips.size():
			want.append(String(crew[i].id) if i < crew.size() else "")
		var got: Array = c.pips.map(func(pip): return pip.get_meta("who"))
		if got != want:
			bad.append("%s's seats show %s, not %s" % [st.id, str(got), str(want)])
		for key in c.sliders:
			if not is_equal_approx(c.sliders[key].value, float(jobs.setting(st.id, key))):
				bad.append("%s's %s slider shows %s, not %s" % [st.id, key, str(c.sliders[key].value), str(jobs.setting(st.id, key))])
	return bad


func test_random_games_and_random_clicks_never_break_the_page() -> void:
	for seed_value in [51, 7, 2024, 31337]:
		await _fuzz(seed_value)


func _fuzz(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sizes := [[700, 700], [980, 700], [1280, 800], [1920, 1080], [700, 560], [1280, 600]]
	var activities := ["", "Sorting medicine", "Resting in the infirmary", "A very long line about what they are doing at the moment, and then a good deal more"]
	var bad: Array = []
	for round in 10:
		var size: Array = sizes[rng.randi() % sizes.size()]
		_park_the_mouse()
		var ctx := Kit.build(size[0], size[1])
		var sim = ctx.sim
		var jobs = sim.jobs
		var ids: Array = ["", "bench", "builders", "garden", "infirmary", "radio", "watch"]
		var posts: Array = []
		for po in jobs.posts():
			posts.append(String(po.id))
		for p in sim.people:
			p.dead = rng.randf() < 0.15
			p.turned = p.dead and rng.randf() < 0.5
			p.away = {"kind": "party", "site": "pharmacy"} if rng.randf() < 0.15 else null
			p.downed = rng.randf() < 0.1
			p.activity = activities[rng.randi() % activities.size()]
			jobs.assignments[p.id] = ids[rng.randi() % ids.size()]
			jobs.post_ids[p.id] = posts[rng.randi() % posts.size()]
			sim.morale.values[p.id] = rng.randf() * 100.0
			sim.morale.broke[p.id] = rng.randf() < 0.1
		Kit.update(ctx, rng.randi() % 4)
		ctx.hud.open_jobs()
		var s = ctx.hud.jobs_screen
		if s == null:
			bad.append("round %d: the page did not open" % round)
			Kit.free_all(ctx)
			continue
		await Kit.settle()
		for step in 22:
			var who = sim.people[rng.randi() % sim.people.size()]
			var what := rng.randi() % 11
			match what:
				0, 1:
					if what == 0:
						s.open_job_list(who)
					else:
						s.open_post_list(who)
					if s.list != null:
						var items: Array = s.list_items.values()
						var item: Button = items[rng.randi() % items.size()]
						if rng.randf() < 0.5:
							item.mouse_entered.emit()
						elif not item.disabled:
							item.pressed.emit()
				2:
					s.choose_job(who, ids[rng.randi() % ids.size()])
				3:
					s.choose_post(who, posts[rng.randi() % posts.size()] if rng.randf() < 0.9 else "nowhere")
				4:
					var st = jobs.stations()[rng.randi() % jobs.stations().size()]
					for key in s.station_cards[st.id].sliders:
						s.station_cards[st.id].sliders[key].value = rng.randf() * 900.0 - 50.0
				5:
					if rng.randf() < 0.5:
						s.auto_button.pressed.emit()
					else:
						s.clear_button.pressed.emit()
				6:
					s._input(_key(KEY_ESCAPE) if rng.randf() < 0.3 else _key(KEY_R))
				7:
					size = sizes[rng.randi() % sizes.size()]
					Kit.resize(ctx, size[0], size[1])
					await Kit.settle()
				8:
					s.rows[who.id].row.mouse_entered.emit()
				9:
					s.station_cards[jobs.stations()[rng.randi() % 6].id].card.mouse_entered.emit()
				10:
					# the game moves on under the page (a person dies, comes back, changes what they do)
					who.dead = rng.randf() < 0.2
					who.away = null if rng.randf() < 0.5 else {"kind": "party", "site": "houses"}
					who.activity = activities[rng.randi() % activities.size()]
					Kit.update(ctx, 0)
			if ctx.hud.jobs_screen == null:
				# (Esc shut it: the player opens it again)
				ctx.hud.open_jobs()
				s = ctx.hud.jobs_screen
				if s == null:
					bad.append("round %d step %d: it would not open again" % [round, step])
					break
				await Kit.settle()
			if s.list != null and rng.randf() < 0.3:
				s.close_list()
			s.refresh()
			if s.list == null:
				for line in _page_matches_the_game(ctx):
					bad.append("round %d step %d (%d): %s" % [round, step, what, line])
		if ctx.hud.jobs_screen == null:
			ctx.hud.open_jobs()
			s = ctx.hud.jobs_screen
		if s.list != null:
			s.close_list()
		await Kit.settle()
		await Kit.settle()
		for line in _misfits(ctx, size):
			bad.append("round %d at %d x %d: %s" % [round, size[0], size[1], line])
		Kit.free_all(ctx)
	eq(bad, [], "a random game under the page (seed %d)" % seed_value)
