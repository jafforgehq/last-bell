extends "res://tests/case.gd"
## Round 16, the crew load: how many of the colony's job seats are staffed, and what the empty ones cost. The sum is
## scripts/sim/crew_load.gd (a seat is staffed by someone assigned to it who is here and up; only the stations the colony
## has count: the salvage bench once it stands). The strip in the HUD (`crew_load_panel`: "Seats 5 of 11", a tooltip that
## lists the empty seats in the order of what they cost, a click that opens the Duty roster) is a view of it, in the settlement
## game and the classic start alike. The Town Board's warning is in test_town_board.gd.

const Helpers := preload("res://tests/helpers.gd")
const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const CrewLoad := preload("res://scripts/sim/crew_load.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SIZES := [[1920, 1080], [1280, 800], [980, 700], [700, 700], [700, 560]]


func _person(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _names(report: Dictionary) -> Array:
	var out: Array = []
	for e in report.empty:
		out.append(String(e.id))
	return out


# --------------------------------------------------------------------- the sum --

func test_the_seats_are_those_of_the_stations_the_colony_has() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	var r := CrewLoad.report(sim)
	eq(int(r.seats), 11, "bench 2, builders 3, garden 2, infirmary 2, radio 1, lookout 1")
	eq(sim.jobs.stations().size(), 6, "six stations: the salvage bench is not built")
	sim.build.plot("salvage_bench_home").building = "salvage_bench"
	sim.build.version += 1
	eq(int(CrewLoad.report(sim).seats), 13, "with the salvage bench two more seats")
	sim.build.plot("workshop_home").building = "workshop"
	sim.build.plot("greenhouse_home").building = "greenhouse"
	sim.build.version += 1
	eq(int(CrewLoad.report(sim).seats), 13 + 1 + 2, "the workshop a third seat at the bench, the greenhouse two at the beds")
	g.world.free()


func test_a_seat_is_staffed_by_someone_assigned_who_is_here_and_up() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	var r := CrewLoad.report(sim)
	eq(int(r.staffed), 6, "six people, six jobs")
	eq(String(r.text), "Seats 6 of 11", "the strip's words")
	eq(String(r.short), "6/11", "and the short ones, for a narrow window")
	sim.jobs.unassign(_person(sim, "ruth"))
	eq(int(CrewLoad.report(sim).staffed), 5, "someone with no job holds no seat")
	sim.jobs.assign(_person(sim, "ruth"), "radio")
	var dez = _person(sim, "dez")
	dez.away = {"kind": "trip"}
	eq(int(CrewLoad.report(sim).staffed), 5, "someone on a trip holds none while they are away")
	dez.away = null
	eq(int(CrewLoad.report(sim).staffed), 6, "and has it back when they are home")
	sim.scavenge.parties.append({"members": ["dez"], "state": "out"})
	eq(int(CrewLoad.report(sim).staffed), 5, "someone walking to the gate with their party has left their seat too")
	sim.scavenge.parties.clear()
	dez.downed = true
	eq(int(CrewLoad.report(sim).staffed), 5, "nor someone who is down")
	dez.downed = false
	_person(sim, "walt").dead = true
	eq(int(CrewLoad.report(sim).staffed), 5, "nor the dead")
	g.world.free()


func test_a_crew_of_five_in_the_settlement_game() -> void:
	var g := Helpers.make(7, 1, 5)
	var sim = g.sim
	var r := CrewLoad.report(sim)
	eq(String(r.text), "Seats 5 of 11", "five people at five of eleven seats")
	eq(_names(r), ["builders", "bench", "infirmary", "garden"], "the radio desk and the lookout post are staffed; each of the others has a seat or two free")
	eq(String(r.level), "calm", "so it is calm")
	g.world.free()


func test_the_empty_seats_come_in_the_order_of_what_they_cost_you() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	sim.jobs.clear()
	var r := CrewLoad.report(sim)
	eq(_names(r), ["radio", "watch", "builders", "bench", "infirmary", "garden"], "the radio and the lookout first, then the builders, the bench, the infirmary and the beds")
	for e in r.empty:
		check(String(e.cost) != "" and String(e.name) != "", "%s has a name and says what it costs: '%s'" % [e.id, e.cost])
	var tip := String(r.tip)
	var at := -1
	for e in r.empty:
		var i := tip.find(String(e.name))
		check(i > at, "%s comes after the one before it in the tooltip" % e.id)
		at = i
	check(tip.contains("no forecast"), "the lookout's: no forecast: %s" % tip)
	check(tip.to_lower().contains("walls") and tip.to_lower().contains("wait"), "the builders': the walls and building wait: %s" % tip)
	check(tip.contains("Seats staffed: 0 of 11"), "and it says the sum: %s" % tip)
	check(tip.contains("(J)") or tip.contains("J"), "and where to go: the roster, key J")
	g.world.free()


func test_a_station_with_some_hands_costs_less_than_one_with_none() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	sim.jobs.clear()
	var walt = _person(sim, "walt")
	sim.jobs.assign(walt, "builders")
	var r := CrewLoad.report(sim)
	var b: Dictionary = {}
	for e in r.empty:
		if e.id == "builders":
			b = e
	check(not b.is_empty() and int(b.staffed) == 1 and int(b.missing) == 2, "the builders have one of three: %s" % str(b))
	check(String(b.cost).to_lower().contains("slower"), "and the walls go slower, not nowhere: '%s'" % b.cost)
	g.world.free()


func test_an_empty_desk_or_post_is_amber_everything_else_calm_and_nothing_is_red() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	eq(String(CrewLoad.report(sim).level), "calm", "everyone at a job: calm")
	sim.jobs.unassign(_person(sim, "hector"))
	sim.jobs.unassign(_person(sim, "ana"))
	sim.jobs.unassign(_person(sim, "walt"))
	eq(String(CrewLoad.report(sim).level), "calm", "the garden, the infirmary and the builders empty: still calm, the radio and the lookout are staffed")
	sim.jobs.unassign(_person(sim, "ruth"))
	eq(String(CrewLoad.report(sim).level), "warn", "the radio desk empty: amber")
	sim.jobs.assign(_person(sim, "ruth"), "radio")
	sim.jobs.unassign(_person(sim, "marcus"))
	eq(String(CrewLoad.report(sim).level), "warn", "the lookout post empty: amber")
	sim.jobs.clear()
	var lv := String(CrewLoad.report(sim).level)
	check(lv == "warn", "nobody anywhere is still amber, never a third colour: %s" % lv)
	g.world.free()


func test_the_radio_line_says_the_next_survivor_will_still_call() -> void:
	var g := Helpers.make(7, 1, 3)
	var sim = g.sim
	sim.jobs.unassign(_person(sim, "ruth"))
	var radio := ""
	for e in CrewLoad.report(sim).empty:
		if e.id == "radio":
			radio = String(e.cost)
	check(radio.to_lower().contains("still call"), "the first callers are heard with the desk empty: '%s'" % radio)
	sim.recruits.queue.clear()
	sim.recruits.queue.append(sim.recruits.make_def(0))    # a stranger is next
	for e in CrewLoad.report(sim).empty:
		if e.id == "radio":
			radio = String(e.cost)
	check(not radio.to_lower().contains("still call") and radio.to_lower().contains("stranger"), "a stranger needs the desk: '%s'" % radio)
	g.world.free()
	var c := Helpers.make(7, 1)
	c.sim.jobs.unassign(_person(c.sim, "ruth"))
	for e in CrewLoad.report(c.sim).empty:
		if e.id == "radio":
			radio = String(e.cost)
	check(not radio.to_lower().contains("stranger") and not radio.to_lower().contains("still call"), "the classic start has no callers to speak of: '%s'" % radio)
	c.world.free()


func test_what_a_party_would_leave_empty_is_a_station_that_has_someone_now_and_nobody_after() -> void:
	var g := Helpers.make(7, 1, 3)
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	var left: Array = CrewLoad.leaves_empty(sim, [ruth, dez])
	eq(left.map(func(e): return String(e.id)), ["radio", "bench"], "Ruth and Dez take the desk and the bench (the radio first)")
	eq(CrewLoad.leaves_empty(sim, [marcus]).map(func(e): return String(e.id)), ["watch"], "Marcus the lookout post")
	sim.jobs.unassign(ruth)
	eq(CrewLoad.leaves_empty(sim, [dez]).map(func(e): return String(e.id)), ["bench"], "a station that is empty already is not left empty by the trip")
	eq(CrewLoad.leaves_empty(sim, []).size(), 0, "nobody going, nothing left")
	var extra = sim.add_person(sim.recruits.queue.pop_front())    # (Ana: she has the infirmary: the bench is free to her)
	sim.jobs.assign(extra, "bench")
	eq(CrewLoad.leaves_empty(sim, [dez]).size(), 0, "with a second person at the bench it is not left empty")
	g.world.free()


func test_the_trip_line_names_what_is_left_empty_and_how_many_hold_the_yard() -> void:
	var g := Helpers.make(7, 1, 5)
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	var ana = _person(sim, "ana")
	var line := CrewLoad.trip_line(sim, [ruth, dez])
	check(line.begins_with("This leaves the Radio desk and the Workbench empty."), "the stations, in the order of what they cost: '%s'" % line)
	check(line.contains("3 stay to hold the yard") or not line.contains("stay"), "three stay: '%s'" % line)
	line = CrewLoad.trip_line(sim, [ruth, dez, marcus])
	check(line.begins_with("This leaves the Radio desk, the Lookout post and the Workbench empty."), "three of them: a list: '%s'" % line)
	check(line.contains("2 stay to hold the yard."), "two stay: '%s'" % line)
	line = CrewLoad.trip_line(sim, [ruth, dez, marcus, ana])
	check(line.contains("1 stays to hold the yard."), "one stays: '%s'" % line)
	eq(CrewLoad.trip_line(sim, []), "", "nobody chosen: nothing to say")
	# when nothing is left empty and the yard is not thin, there is nothing to say
	var spare = sim.add_person(sim.recruits.make_def(0))    # a stranger, with no job
	for i in 3:
		sim.add_person(sim.recruits.make_def(i + 1))
	eq(CrewLoad.trip_line(sim, [spare]), "", "a trip that empties nothing and leaves many at home says nothing")
	g.world.free()


func test_the_count_of_those_who_stay_leaves_out_the_away_and_the_down() -> void:
	var g := Helpers.make(7, 1, 5)
	var sim = g.sim
	var party := [_person(sim, "ruth"), _person(sim, "dez")]
	eq(CrewLoad.stay_count(sim, party), 3, "three of five stay")
	_person(sim, "walt").away = {"kind": "trip"}
	eq(CrewLoad.stay_count(sim, party), 2, "one is away already")
	_person(sim, "ana").downed = true
	eq(CrewLoad.stay_count(sim, party), 1, "one is down")
	g.world.free()


# ------------------------------------------------------------------- the strip --

func _ctx(width: int = 1280, height: int = 800, crew: int = 6) -> Dictionary:
	var ctx := Kit.build(width, height, 1, true, crew)
	Kit.update(ctx)
	return ctx


func test_the_strip_reads_the_seats_in_the_settlement_game() -> void:
	for crew in [3, 5]:
		var ctx := _ctx(1280, 800, crew)
		await Kit.settle()
		var h = ctx.hud
		check(h.crew_load_panel != null and h.crew_load_panel.is_visible_in_tree(), "crew %d: the strip is there" % crew)
		eq(h.crew_load_label.text, "Seats %d of 11" % crew, "crew %d: the seats" % crew)
		Kit.free_all(ctx)


func test_the_classic_start_has_no_strip_and_its_stores_column_is_as_it_was() -> void:
	var ctx := _ctx(1280, 800, 6)
	await Kit.settle()
	await Kit.settle()
	var h = ctx.hud
	check(not h.crew_load_panel.visible, "the classic start (six people, no callers) does not show it")
	eq(Kit.rect(h.crew_load_panel), Rect2(), "and it takes no room")
	near(h.left_col.size.y, h.res_panel.size.y, 0.5, "the column is the stores panel alone (the legend is not up)")
	Kit.free_all(ctx)


func test_the_strip_follows_a_trip_and_a_job_given() -> void:
	var ctx := _ctx(1280, 800, 5)
	var sim = ctx.sim
	var h = ctx.hud
	eq(h.crew_load_label.text, "Seats 5 of 11", "all at their seats")
	_person(sim, "walt").away = {"kind": "trip"}
	Kit.update(ctx)
	eq(h.crew_load_label.text, "Seats 4 of 11", "Walt is on a trip")
	_person(sim, "walt").away = null
	sim.jobs.unassign(_person(sim, "ana"))
	Kit.update(ctx)
	eq(h.crew_load_label.text, "Seats 4 of 11", "Ana has no job")
	sim.jobs.assign(_person(sim, "ana"), "infirmary")
	Kit.update(ctx)
	eq(h.crew_load_label.text, "Seats 5 of 11", "and gets one")
	sim.scavenge.parties.append({"members": ["dez"], "state": "out"})
	Kit.update(ctx)
	eq(h.crew_load_label.text, "Seats 4 of 11", "Dez is walking to the gate with a party: his seat is empty from then on")
	Kit.free_all(ctx)


func test_the_tooltip_lists_the_empty_seats_and_is_kept_with_the_strip() -> void:
	var ctx := _ctx(1280, 800, 3)
	var h = ctx.hud
	var tip: String = h.crew_load_panel.tooltip_text
	check(tip.contains("Seats staffed: 3 of 11"), "the sum: %s" % tip)
	for name in ["Builders", "Infirmary", "Vegetable beds"]:
		check(tip.contains(name), "the empty %s is listed: %s" % [name, tip])
	check(not tip.contains("Radio desk:") and not tip.contains("Lookout post:"), "the staffed ones are not: %s" % tip)
	ctx.sim.jobs.unassign(_person(ctx.sim, "ruth"))
	Kit.update(ctx)
	check(h.crew_load_panel.tooltip_text.contains("Radio desk"), "an empty desk is listed at once: %s" % h.crew_load_panel.tooltip_text)
	Kit.free_all(ctx)


func test_the_strip_is_calm_with_the_desk_and_the_post_staffed_and_amber_without() -> void:
	var ctx := _ctx(1280, 800, 5)
	var sim = ctx.sim
	var h = ctx.hud
	eq(h.crew_load_label.get_theme_color("font_color"), Hud.INK, "calm: the plain ink")
	sim.jobs.unassign(_person(sim, "marcus"))
	Kit.update(ctx)
	eq(h.crew_load_label.get_theme_color("font_color"), Hud.WARN, "the lookout post empty: amber")
	check(h.crew_load_label.get_theme_color("font_color") != Hud.DANGER_TEXT and h.crew_load_label.get_theme_color("font_color") != Hud.DANGER, "never the alarm red")
	sim.jobs.assign(_person(sim, "marcus"), "watch")
	Kit.update(ctx)
	eq(h.crew_load_label.get_theme_color("font_color"), Hud.INK, "and calm again")
	Kit.free_all(ctx)


func test_a_click_on_the_strip_opens_the_duty_roster() -> void:
	var ctx := _ctx(1280, 800, 3)
	await Kit.settle()
	var h = ctx.hud
	check(h.jobs_screen == null, "the roster is shut")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	h.crew_load_panel.gui_input.emit(ev)
	check(h.jobs_screen != null, "a click opens the Duty roster")
	Kit.free_all(ctx)


func test_the_strip_asks_the_game_before_it_opens_the_roster() -> void:
	var ctx := _ctx(1280, 800, 3)
	var asked := []
	ctx.hud.on_jobs = func(): asked.append("jobs")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ctx.hud.crew_load_panel.gui_input.emit(ev)
	eq(asked, ["jobs"], "it is main.gd's call (the tutorial's lock, another page up), as the toolbar's button is")
	check(ctx.hud.jobs_screen == null, "and the HUD did not open it by itself")
	ev.button_index = MOUSE_BUTTON_RIGHT
	ctx.hud.crew_load_panel.gui_input.emit(ev)
	eq(asked, ["jobs"], "a right click does nothing")
	Kit.free_all(ctx)


func test_the_strip_is_the_short_form_in_a_narrow_window() -> void:
	var ctx := _ctx(700, 700, 5)
	await Kit.settle()
	eq(ctx.hud.crew_load_label.text, "Seats 5/11", "a narrow window drops the 'of'")
	Kit.resize(ctx, 1280, 800)
	await Kit.settle()
	Kit.update(ctx)
	eq(ctx.hud.crew_load_label.text, "Seats 5 of 11", "and a wide one has it back")
	Kit.free_all(ctx)


func test_the_strip_fits_and_overlaps_nothing_in_any_window() -> void:
	for crew in [3, 5]:
		for size in SIZES:
			var ctx := _ctx(size[0], size[1], crew)
			var ana = Kit.person(ctx, "ruth")
			ctx.sim.alert("a1", "warn", "Food is running out", "about 2 days left", null, 60.0)
			ctx.sim.alert("a2", "info", "The bell has rung", "Everyone is heading to their posts", null, 60.0)
			Kit.select(ctx, ana)
			ctx.hud.set_fields(true)
			Kit.update(ctx)
			await Kit.settle()
			Kit.update(ctx)
			await Kit.settle()
			var h = ctx.hud
			var win := Rect2(0, 0, size[0], size[1])
			var rects := {
				"strip": Kit.rect(h.crew_load_panel), "stores": Kit.rect(h.res_panel), "legend": Kit.rect(h.fields_legend), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock),
				"alerts": Kit.rect(h.alerts_box), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "speed": Kit.rect(h.speed_panel),
			}
			check(rects.strip.size.x > 40.0 and rects.strip.size.y > 12.0, "%d x %d crew %d: the strip has a size: %s" % [size[0], size[1], crew, str(rects.strip)])
			eq(Kit.overlaps(rects), [], "%d x %d crew %d: nothing overlaps the strip" % [size[0], size[1], crew])
			for name in rects:
				if rects[name].size.x > 1.0 and rects[name].size.y > 1.0:
					check(win.encloses(rects[name].grow(-0.5)), "%d x %d crew %d: %s is in the window: %s" % [size[0], size[1], crew, name, str(rects[name])])
			eq(TextTests.new()._small_text(h.crew_load_panel), [], "%d x %d: nothing under 12 px in the strip" % [size[0], size[1]])
			Kit.free_all(ctx)
