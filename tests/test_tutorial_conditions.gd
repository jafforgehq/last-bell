extends "res://tests/case.gd"
## The conditions of tutorial.json (scripts/tutorial_conditions.gd), one by one, on a headless
## Orientation Day and states written by hand: what each is true of and what it is not.

const Tut := preload("res://tests/tutorial_kit.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Coach := preload("res://scripts/ui/coach.gd")


func _ok(spec: Dictionary, sim, st: Dictionary = {}) -> bool:
	return Conditions.check(spec, sim, st)


func _c(name: String, params: Dictionary = {}) -> Dictionary:
	return {"cond": name, "params": params}


func test_the_registry_and_the_basics() -> void:
	var g := Tut.make()
	var sim = g.sim
	check(Conditions.has("next") and not Conditions.has("nonsense"), "the registry knows its names")
	check(_ok({}, sim), "an empty condition holds (a step with no start begins at once)")
	check(not _ok(_c("nonsense"), sim), "a condition that is not there does not")
	check(_ok(_c("always"), sim) and not _ok(_c("never"), sim), "always and never")
	check(not _ok(_c("next"), sim, {}), "Got it was not pressed")
	check(_ok(_c("next"), sim, {"next": true}), "and was")
	check(not _ok(_c("elapsed", {"seconds": 5}), sim, {"t": 4.9}) and _ok(_c("elapsed", {"seconds": 5}), sim, {"t": 5.0}), "elapsed")
	check(_ok(_c("did", {"what": "gizmo:draft"}), sim, {"did": {"gizmo:draft": 1.0}}), "did: it was done")
	check(not _ok(_c("did", {"what": "gizmo:draft"}), sim, {"did": {"gizmo:post": 1.0}}), "did: another thing was")
	check(not _ok(_c("did", {"what": "save"}), sim, {}), "did: nothing at all")
	check(_ok(_c("event", {"type": "shot", "min": 3}), sim, {"events": {"shot": 3.0}}), "event: enough of them")
	check(not _ok(_c("event", {"type": "shot", "min": 3}), sim, {"events": {"shot": 2.0}}), "event: not enough")
	check(_ok(_c("speed_pressed", {"n": 3}), sim, {"did": {"speed:3": 2.0}}) and not _ok(_c("speed_pressed", {"n": 3}), sim, {"did": {"speed:2": 1.0}}), "speed_pressed")
	check(_ok(_c("saved"), sim, {"did": {"save": 1.0}}) and not _ok(_c("saved"), sim, {"did": {}}), "saved")
	check(_ok(_c("fields_on"), sim, {"fields": true}) and not _ok(_c("fields_on"), sim, {"fields": false}), "fields_on")
	g.world.free()


func test_looking_around_needs_both_a_pan_and_a_zoom() -> void:
	var g := Tut.make()
	var sim = g.sim
	var spec := _c("look_around", {"pan": 6, "zoom": 0.15})
	check(not _ok(spec, sim, {"pan": 10.0, "zoom": 0.0}), "panning alone is not looking around")
	check(not _ok(spec, sim, {"pan": 0.0, "zoom": 1.0}), "nor is zooming alone")
	check(not _ok(spec, sim, {"pan": 5.9, "zoom": 0.2}), "a little pan is not enough")
	check(_ok(spec, sim, {"pan": 6.0, "zoom": 0.15}), "both, enough: it is")
	g.world.free()


func test_selected_names_a_person_or_a_wall_piece() -> void:
	var g := Tut.make()
	var sim = g.sim
	var ruth := _c("selected", {"who": "ruth"})
	check(_ok(ruth, sim, {"selection": {"kind": "person", "id": "ruth"}}), "Ruth is selected")
	check(not _ok(ruth, sim, {"selection": {"kind": "person", "id": "dez"}}), "Dez is not Ruth")
	check(not _ok(ruth, sim, {"selection": {}}), "nobody")
	check(not _ok(ruth, sim, {"selection": {"kind": "segment", "id": 3}}), "a wall piece is not Ruth")
	var bus := _c("selected", {"wall": 3})
	check(_ok(bus, sim, {"selection": {"kind": "segment", "id": 3}}), "the bus is selected")
	check(not _ok(bus, sim, {"selection": {"kind": "segment", "id": 2}}), "the gate is not the bus")
	check(not _ok(bus, sim, {"selection": {"kind": "person", "id": "ruth"}}), "nor is a person")
	g.world.free()


func test_orders_are_seen_as_they_are_given_and_carried_out() -> void:
	var g := Tut.make()
	var sim = g.sim
	var ruth = Tut.person(sim, "ruth")
	var hector = Tut.person(sim, "hector")
	var base := {"base": {"pos": {"ruth": [ruth.x, ruth.y], "hector": [hector.x, hector.y]}}}
	var ordered := _c("ordered", {"who": "ruth", "min_dist": 3})
	var arrived := _c("arrived", {"who": "ruth", "min_dist": 3})
	check(not _ok(ordered, sim, base) and not _ok(arrived, sim, base), "nothing ordered yet")
	# an order that is too near does not count
	sim.order_move(ruth, ruth.x + 1.0, ruth.y)
	check(not _ok(ordered, sim, base), "a step of one tile is not the lesson")
	# a proper one
	sim.order_move(ruth, ruth.x + 5.0, ruth.y)
	check(_ok(ordered, sim, base), "five tiles is")
	check(not _ok(arrived, sim, base), "but she has not got there")
	Tut.run(sim, 6.0)
	check(_ok(arrived, sim, base), "and then she has")
	var released := _c("released", {"who": "ruth"})
	check(not _ok(released, sim, base), "she is still under orders")
	sim.toggle_draft(ruth)
	check(_ok(released, sim, base), "released")
	# a post is not a walk, and a walk is not a post
	var posted := _c("posted", {"who": "hector"})
	var post_ordered := _c("post_ordered", {"who": "hector"})
	check(not _ok(post_ordered, sim, base), "no post ordered")
	sim.order_post(hector)
	check(_ok(post_ordered, sim, base) and not _ok(posted, sim, base), "ordered, and on the way")
	check(not _ok(_c("ordered", {"who": "hector"}), sim, base), "a post is not an order to walk")
	Tut.run(sim, 30.0)
	check(_ok(posted, sim, base), "and at the post")
	g.world.free()


func test_repairs_are_seen_when_ordered_and_when_done() -> void:
	var g := Tut.make()
	var sim = g.sim
	var bus = sim.segments[3]
	check(not _ok(_c("repair_ordered", {"wall": 3}), sim), "nobody sent to the bus")
	check(not _ok(_c("wall_mended", {"wall": 3, "frac": 0.99}), sim), "and the bus is worn")
	sim.order_repair(Tut.person(sim, "dez"), bus)
	check(_ok(_c("repair_ordered", {"wall": 3}), sim), "Dez is sent")
	check(not _ok(_c("repair_ordered", {"wall": 2}), sim), "not to the gate")
	Tut.run(sim, 40.0)
	check(_ok(_c("wall_mended", {"wall": 3, "frac": 0.99}), sim), "and the bus is mended")
	g.world.free()


func test_the_scavenging_dialog_and_the_party() -> void:
	var g := Tut.make()
	var sim = g.sim
	check(not _ok(_c("dialog_open"), sim, {"dialog": {"open": false, "site": ""}}), "no dialog")
	check(_ok(_c("dialog_open"), sim, {"dialog": {"open": true, "site": ""}}), "a dialog")
	check(not _ok(_c("site_chosen"), sim, {"dialog": {"open": true, "site": ""}}), "no place chosen")
	check(_ok(_c("site_chosen"), sim, {"dialog": {"open": true, "site": "houses"}}), "a place chosen")
	check(not _ok(_c("site_chosen"), sim, {"dialog": {"open": false, "site": "houses"}}), "a place chosen in a dialog that is closed is nothing")
	check(not _ok(_c("party_out"), sim), "no party")
	Tut.run(sim, 0.2)
	check(sim.scavenge.send([Tut.person(sim, "ana")], "houses"), "a party goes")
	check(_ok(_c("party_out"), sim), "a party is out")
	g.world.free()


func test_the_world_conditions_follow_the_clock() -> void:
	var g := Tut.make()
	var sim = g.sim
	check(not _ok(_c("forecast_given"), sim), "no forecast in the morning")
	check(not _ok(_c("bell_rung"), sim), "no bell")
	check(not _ok(_c("day_started", {"day": 2}), sim), "day 2 has not come")
	sim.scenario.coached = true
	Tut.run_to_clock(sim, 10.2 * 60.0)
	check(_ok(_c("forecast_given"), sim), "the lookout has spoken by 17:12")
	check(not _ok(_c("bell_rung"), sim), "but the bell has not rung")
	Tut.run_to_clock(sim, 12.2 * 60.0)
	check(_ok(_c("bell_rung"), sim), "it has by 19:12")
	Tut.run_to_clock(sim, 17.0 * 60.0 + 10.0)
	check(_ok(_c("bell_rung"), sim), "it counts through the night (past midnight, hour %.2f)" % sim.hour)
	check(not _ok(_c("day_started", {"day": 2}), sim), "day 2 has not begun in the night")
	Tut.run_to_clock(sim, 23.5 * 60.0 - 10.0)
	check(_ok(_c("bell_rung"), sim), "and through the dawn (%s)" % sim.phase)
	check(not _ok(_c("day_started", {"day": 2}), sim), "which is not yet the day")
	Tut.run_to_clock(sim, 23.5 * 60.0 + 10.0)
	check(_ok(_c("day_started", {"day": 2}), sim), "it has begun at 06:30 (hour %.2f, day %d, %s)" % [sim.hour, sim.day, sim.phase])
	check(not _ok(_c("bell_rung"), sim), "and the bell is over")
	g.world.free()


func test_ammo_spent_and_made() -> void:
	var g := Tut.make()
	var sim = g.sim
	var st := {"base": {"ammo": float(sim.stock.ammo)}}
	check(not _ok(_c("ammo_spent", {"min": 1}), sim, st), "none spent")
	sim.stock.ammo -= 0.6
	check(not _ok(_c("ammo_spent", {"min": 1}), sim, st), "three shots are not a whole round")
	sim.stock.ammo -= 0.6
	check(_ok(_c("ammo_spent", {"min": 1}), sim, st), "six are")
	var kst := {"base": {"kills": float(sim.kills)}}
	check(not _ok(_c("kills", {"min": 3}), sim, kst), "nobody shot")
	sim.kills += 2
	check(not _ok(_c("kills", {"min": 3}), sim, kst), "two are not three")
	sim.kills += 1
	check(_ok(_c("kills", {"min": 3}), sim, kst), "three are")
	check(not _ok(_c("ammo_gained", {"min": 8}), sim, st), "nothing made")
	sim.stock.ammo += 20.0
	check(_ok(_c("ammo_gained", {"min": 8}), sim, st), "ammo made")
	g.world.free()


func test_the_alarm_the_wound_the_fever_and_the_bench() -> void:
	var g := Tut.make()
	var sim = g.sim
	Tut.run_to_clock(sim, 700.0)
	check(not _ok(_c("lure_set"), sim), "no alarm")
	sim.stock.scrap = 20.0
	sim.tactics.order_lure(sim.segments[2])
	check(_ok(_c("lure_set"), sim), "the alarm rings")
	# a wound is seen before it is healed, so a step that begins before the wound is not done at once
	var walt = Tut.person(sim, "walt")
	var healed := _c("healed", {"who": "walt"})
	var st := {"t": 0.0}
	check(not _ok(healed, sim, st), "no wound yet, and the step is new: not done")
	sim.scenario.fire("scratch")
	check(not _ok(healed, sim, st), "the wound is open: not done")
	check(bool(st.get("seen", false)), "and the condition has noted it")
	Tut.run(sim, 60.0)
	check(walt.bleeding == 0.0, "Ana bandaged him")
	check(_ok(healed, sim, st), "healed")
	# and a wound that never comes does not hold the lesson up for ever
	var st2 := {"t": 3.5}
	check(_ok(_c("healed", {"who": "dez"}), sim, st2), "nothing to heal after a few seconds: the step goes on")
	# the fever: told to be treated, then cured
	var hector = Tut.person(sim, "hector")
	var cured := _c("cured", {"who": "hector"})
	var treat := _c("treat_ordered", {"who": "hector"})
	var st3 := {"t": 0.0}
	check(not _ok(cured, sim, st3), "not infected yet, the step is new: not done")
	sim.scenario.fire("fever")
	check(not _ok(treat, sim) and not _ok(cured, sim, st3), "a fever, not treated")
	check(sim.handle_gizmo("treat", {"kind": "person", "ref": hector}), "Treat is taken")
	check(_ok(treat, sim), "treatment ordered")
	Tut.run(sim, 90.0)
	check(_ok(cured, sim, st3), "cured")
	# the bench
	var dez = Tut.person(sim, "dez")
	sim.scenario.set_time(8.0, 2)
	check(not _ok(_c("crafting"), sim), "nobody at the worktable")
	check(sim.workshop.order_craft(dez), "Dez is given the bench")
	check(_ok(_c("crafting"), sim) and _ok(_c("crafting", {"who": "dez"}), sim), "someone has the worktable's job, and it is Dez: at once, before he has walked there (a lesson waiting for it holds the game still)")
	check(not sim.workshop.crafting(dez), "though he is not at work until he gets there")
	Tut.run(sim, 5.0)
	check(sim.workshop.crafting(dez), "and then he is")
	check(not _ok(_c("crafting", {"who": "ruth"}), sim), "not Ruth")
	g.world.free()


## The duty roster: whether its page is open (the coach notes that in `state.jobs`) and whether a job was
## given (the coach counts the rules' `assigned` events that name a station as `assigned:job`: one that
## takes a job away does not count, and the three at the very start of Orientation Day, which take the
## self-working jobs off, are of that kind).
func test_the_duty_roster_page_is_open_and_a_job_is_given() -> void:
	var g := Tut.make()
	var sim = g.sim
	check(Conditions.has("jobs_open") and Conditions.has("jobs_given"), "the registry knows both")
	check(not _ok(_c("jobs_open"), sim, {}), "no page is noted: it is not open")
	check(not _ok(_c("jobs_open"), sim, {"jobs": {"open": false}}), "a page that is shut")
	check(_ok(_c("jobs_open"), sim, {"jobs": {"open": true}}), "a page that is open")
	check(not _ok(_c("jobs_given"), sim, {}), "no events: nothing was given")
	check(not _ok(_c("jobs_given"), sim, {"events": {}}), "an empty list of events")
	check(not _ok(_c("jobs_given"), sim, {"events": {"assigned": 3.0}}), "assigned events by themselves are not enough: some take a job away")
	check(_ok(_c("jobs_given"), sim, {"events": {"assigned": 1.0, "assigned:job": 1.0}}), "one that names a station is")
	g.world.free()


## The lesson's own `done`, read from the data: the page was opened, a job was given and the page is shut again.
func test_the_duty_roster_lesson_is_done_when_a_job_was_given_and_the_page_is_closed() -> void:
	var step := {}
	for s in Coach.load_steps(Coach.CLASSIC_PATH):
		if String(s.id) == "jobs":
			step = s
	check(not step.is_empty(), "there is a lesson on the duty roster")
	if step.is_empty():
		return
	var g := Tut.make()
	var sim = g.sim
	var done: Dictionary = step.done
	var st := {"did": {}, "events": {}, "jobs": {"open": false}}
	check(not _ok(done, sim, st), "nothing done yet")
	st.did["jobs"] = 1.0
	st.jobs.open = true
	check(not _ok(done, sim, st), "the page is open, and nobody has been given anything")
	st.events["assigned"] = 1.0
	check(not _ok(done, sim, st), "a job was taken away, which is not what was asked")
	st.events["assigned:job"] = 1.0
	check(not _ok(done, sim, st), "a job was given, but the page is still open")
	st.jobs.open = false
	check(_ok(done, sim, st), "the page is shut again after a job was given: done")
	# opened and shut again with nothing given
	var looked := {"did": {"jobs": 1.0}, "events": {}, "jobs": {"open": false}}
	check(not _ok(done, sim, looked), "a look at the page and no job is not the lesson")
	g.world.free()


func test_combinators() -> void:
	var g := Tut.make()
	var sim = g.sim
	var yes := _c("always")
	var no := _c("never")
	check(_ok(_c("all", {"of": [yes, yes]}), sim) and not _ok(_c("all", {"of": [yes, no]}), sim), "all")
	check(_ok(_c("any", {"of": [no, yes]}), sim) and not _ok(_c("any", {"of": [no, no]}), sim), "any")
	check(_ok(_c("not", {"of": no}), sim) and not _ok(_c("not", {"of": yes}), sim), "not")
	check(_ok(_c("all", {"of": []}), sim), "all of nothing holds")
	check(not _ok(_c("any", {"of": []}), sim), "any of nothing does not")
	var nested := _c("all", {"of": [_c("any", {"of": [no, yes]}), _c("not", {"of": no})]})
	check(_ok(nested, sim), "they nest")
	g.world.free()


## The tip about building (a hint's trigger, not a lesson's): `can_build`, with the day and the scrap as its numbers.
func test_can_build_wants_the_day_the_scrap_and_nothing_built_or_going_up() -> void:
	var g := Tut.make()
	var sim = g.sim
	var spec := _c("can_build", {"day": 3, "scrap": 30})
	check(Conditions.has("can_build"), "the registry knows it")
	sim.day = 2
	sim.stock.scrap = 100.0
	check(not _ok(spec, sim), "not before the day")
	sim.day = 3
	check(_ok(spec, sim), "on the day, with the scrap")
	sim.stock.scrap = 29.9
	check(not _ok(spec, sim), "not short of the scrap")
	sim.stock.scrap = 100.0
	check(_ok(_c("can_build"), sim), "with no numbers it asks day 3 and 30 scrap")
	check(not _ok(_c("can_build", {"scrap": 101}), sim), "and takes the numbers it is given")
	sim.build.plot("workshop_home").site = {"building": "workshop", "progress": 0.0, "work": 24.0, "scrap": 30.0}
	check(not _ok(spec, sim), "not with a site going up")
	sim.build.plot("workshop_home").site = {}
	sim.build.plot("workshop_home").building = "workshop"
	check(not _ok(spec, sim), "nor with a building standing")
	g.world.free()
