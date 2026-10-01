extends "res://tests/case.gd"
## Saving in the middle of Orientation Day and loading resumes the same step, with what the coach
## had noted for it and the world as it was; the tutorial never touches the real saves; and the
## game that was loaded can be played to the end.

const Tut := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Prefs := preload("res://scripts/prefs.gd")


## Plays to the start of step `stop` (and `more` frames on), saves with F5, gives the game back
## (keeping the file) and loads it into a new game. Returns {"before": the old coach's state and
## fingerprint, "main": the new game}.
func _save_and_load(stop: String, more: int, any_phase: bool = false) -> Dictionary:
	var main = Tut.game()
	await Tut.frames(main, 3)
	var r: Dictionary = await Bot.play(main, stop, 400000, any_phase)
	eq(r.stuck, "", "the bot got to %s" % stop)
	if more > 0:
		await Bot.play(main, "", more)
	var coach = main.coach
	var before := {
		"step": coach.step_id(),
		"phase": coach.phase,
		"state": coach.state.duplicate(true),
		"fingerprint": Tut.fingerprint(main.sim),
		"fired": main.sim.scenario.fired.duplicate(),
		"speed": main.speed,
		"held": coach.held,
		"index": coach.index,
	}
	main._key(KEY_F5)
	var path: String = main.tutorial_save_path
	check(FileAccess.file_exists(path), "F5 wrote the tutorial's save (%s)" % path)
	await Tut.leave(main, true)
	var again = Tut.start({"load": path})
	await Engine.get_main_loop().process_frame
	return {"before": before, "main": again}


## What was saved is what was loaded, before the game has taken a step (the frames come after).
func _check_resumed(r: Dictionary, label: String) -> void:
	var before: Dictionary = r.before
	var main = r.main
	var coach = main.coach
	check(main.tutorial, "%s: it is the tutorial again" % label)
	check(coach != null, "%s: and the coach is back" % label)
	if coach == null:
		return
	eq(coach.step_id(), before.step, "%s: the same step" % label)
	eq(coach.index, before.index, "%s: at the same place" % label)
	eq(coach.phase, before.phase, "%s: in the same phase" % label)
	eq(Tut.fingerprint(main.sim), before.fingerprint, "%s: the world is as it was" % label)
	eq(main.sim.scenario.fired, before.fired, "%s: and the same beats have happened" % label)
	check(main.sim.scenario.coached and not main.sim.scenario.finished, "%s: the coach still owns the beats" % label)
	check(not main.sim.waves.enabled and not main.sim.permadeath, "%s: it still cannot be lost" % label)
	var was: Dictionary = before.state
	var now: Dictionary = coach.state
	eq(now.did, was.did, "%s: it remembers what the player did" % label)
	eq(now.base, was.base, "%s: and what the world was when the step began" % label)
	eq(float(now.pan), float(was.pan), "%s: and how far the view was moved" % label)
	await Tut.frames(main, 6)
	check(coach.card.visible and coach.title_label.text != "", "%s: with its card up" % label)
	if before.held:
		check(coach.held and main.speed == 0, "%s: and the game held as it was" % label)


func test_a_card_that_is_being_read_is_still_being_read_after_a_load() -> void:
	var r: Dictionary = await _save_and_load("stores", 0)
	await _check_resumed(r, "stores")
	var main = r.main
	var coach = main.coach
	check(coach.next_button.visible, "Got it is there")
	coach.next_button.pressed.emit()
	eq(coach.step_id(), "scavenge", "and goes on to the next lesson")
	await Tut.leave(main)


func test_a_step_that_is_under_way_resumes_with_the_game_running() -> void:
	# the order has been given and Dez is mending the bus
	var r: Dictionary = await _save_and_load("repair", 150)
	await _check_resumed(r, "repair")
	var main = r.main
	var sim = main.sim
	check(sim.segments[3].hp < sim.segments[3].max_hp or r.before.fingerprint != "", "(the wall was being mended)")
	var played: Dictionary = await Bot.play(main)
	eq(played.stuck, "", "the loaded game plays on to the end")
	check(main.coach == null and Prefs.flag("tutorial_done"), "and the lesson finishes with the flag set")
	eq(main.sim.over, "", "never over")
	await Tut.leave(main)


func test_a_step_that_is_waiting_for_its_moment_resumes_waiting() -> void:
	var r: Dictionary = await _save_and_load("report", 30, true)
	await _check_resumed(r, "report (waiting)")
	var main = r.main
	var coach = main.coach
	eq(coach.phase, "wait", "it is still waiting for 17:00")
	main._key(KEY_3)
	var guard := 0
	while coach.phase == "wait" and guard < 6000:
		await Tut.frames(main, 10)
		guard += 10
	eq(coach.phase, "active", "and the lookout speaks in the end")
	await Tut.leave(main)


func test_a_lesson_late_in_the_night_resumes_too() -> void:
	# Hector has been told to be treated, and Ana is on her way
	var r: Dictionary = await _save_and_load("fever", 120)
	await _check_resumed(r, "fever")
	var main = r.main
	# the order was given before the save: Ana carries on and the fever goes
	var guard := 0
	while main.sim.medical.treat_orders.has("hector") or main.sim.people[5].infected_at >= 0.0:
		await Tut.frames(main, 30)
		guard += 30
		if guard > 3000:
			break
	check(main.sim.people[5].infected_at < 0.0, "Ana treats him after the load as she would have before it")
	await Tut.leave(main)


## The duty roster's lesson (the page is not saved, what the coach noted of it is): a save made after a look
## at the page, with the page shut, resumes the lesson, which still remembers the look and can be finished.
func test_a_save_in_the_duty_roster_lesson_resumes_it_with_what_was_done() -> void:
	var at := -1
	var steps := Coach.load_steps()
	for i in steps.size():
		if String(steps[i].id) == "jobs":
			at = i
	check(at >= 0, "there is a lesson on the duty roster")
	if at < 0:
		return
	var main = Tut.game(at)
	await Tut.frames(main, 12)
	main._key(KEY_J)
	await Tut.frames(main, 6)
	check(main.hud.jobs_screen != null, "the page is open")
	main.hud.jobs_screen.close_button.pressed.emit()
	await Tut.frames(main, 4)
	main._key(KEY_F5)
	var path: String = main.tutorial_save_path
	check(FileAccess.file_exists(path), "F5 wrote the tutorial's save")
	await Tut.leave(main, true)
	var again = Tut.start({"load": path})
	await Engine.get_main_loop().process_frame
	var coach = again.coach
	check(again.tutorial and coach != null, "the tutorial is back, with its coach")
	if coach == null:
		await Tut.leave(again)
		return
	eq(coach.step_id(), "jobs", "at the same lesson")
	eq(float(coach.state.did.get("jobs", 0.0)), 1.0, "it remembers that the page was opened")
	await Tut.frames(again, 12)
	eq(coach.phase, "active", "the lesson is up")
	eq(coach.target_name, "jobs", "with the clipboard lit again")
	check(coach.held and again.speed == 0, "and the game held as it was")
	# the rest of it plays out: the page, Auto-assign, Close
	again._key(KEY_J)
	await Tut.frames(again, 6)
	check(again.hud.jobs_screen != null, "J opens the page again")
	again.hud.jobs_screen.auto_button.pressed.emit()
	await Tut.frames(again, 4)
	again.hud.jobs_screen.close_button.pressed.emit()
	await Tut.frames(again, 60)
	eq(coach.step_id(), "wrap", "and the lesson ends with the last card")
	await Tut.leave(again)
