extends "res://tests/case.gd"
## A headless bot plays the avatar's Orientation Day from the title to the last card through the real handlers (the keys held
## down, the mouse and its left button, R F T G L J, a click on a crew card, the radio's buttons and the call's, the pages and the
## coach's own buttons), with the coach teaching and the rules stepping: every step is reached in order, each one's lesson really
## happened in the world (the walk, the kill from the walkway, the reload, the answer of the radio, the refusal and the push, the
## call, the map, the alarm, the duty roster), nothing is skipped and nothing logs an error, and the lesson ends with the flag set.
## It is played from the title too (the first launch's card, the title's own button), and from a save made in the middle of it.

const Tut := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const Prefs := preload("res://scripts/prefs.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const MainScript := preload("res://scripts/main.gd")


func _ids(main) -> Array:
	var ids: Array = []
	for s in main.coach.steps:
		ids.append(String(s.id))
	return ids


func test_the_bot_plays_every_step_of_the_avatars_lesson_to_the_end() -> void:
	var quick_before := FileAccess.file_exists(SaveGame.QUICK_PATH)
	var quick_time := FileAccess.get_modified_time(SaveGame.QUICK_PATH) if quick_before else 0
	var main = Tut.avatar_game()
	var sim = main.sim
	await Tut.frames(main, 3)
	var all_ids := _ids(main)
	var me = sim.avatar.player()
	var start := Vector2(me.x, me.y)
	# each step is played up to the beginning of the next, and what it was to teach is looked for in the world
	for i in all_ids.size() - 1:
		var next: String = all_ids[i + 1]
		var r: Dictionary = await Bot.play(main, next, 400000, true)
		eq(r.stuck, "", "the bot was never stuck (at %s)" % all_ids[i])
		if r.stuck != "" or main.coach == null:
			break
		match all_ids[i]:
			"you":
				check(Tut.person(sim, "ruth").moving == false, "(a card to be read: nobody moved)")
			"walk":
				check(start.distance_to(Vector2(me.x, me.y)) >= 6.0, "Walk: she walked at least six tiles with the keys (from %s to %s)" % [str(start), str(Vector2(me.x, me.y))])
			"shoot":
				check(int(me.stats.kills) >= 1 and int(me.stats.shots) >= 1, "Aim and shoot: her own shot put a walker down (%d shots, %d kills)" % [me.stats.shots, me.stats.kills])
				check(sim.world.on_deck(me.x, me.y), "from the walkway (the ladder)")
				check(not main.firing and not Input.is_physical_key_pressed(KEY_D), "and the hands are let go")
			"reload":
				check(int(me.mag) == int(me.gun.mag) and me.reloading <= 0.0, "Reload and swing: the gun is full again")
			"crew":
				check(Bot.selected(main, "dez"), "Who is who: Dez's card was clicked")
			"come":
				check(String(Bot.person(main, "dez").stance) == "follow", "Ask, do not order: Dez follows")
			"refusal":
				check(float(sim.radio.trust_of(Bot.person(main, "ana"))) < float(sim.radio.TRUST_START), "A refusal: the push cost Ana's trust (%.0f)" % sim.radio.trust_of(Bot.person(main, "ana")))
			"news":
				var answered := false
				for e in sim.radio.news:
					if String(e.kind) == "attack" and String(e.answered) == "reinforce" and not bool(e.get("by_default", false)):
						answered = true
				check(answered, "News and calls: the player answered the attack call, by a button")
			"map":
				check(main.hud.scavenge_dialog == null, "The map: the board was read and shut")
			"alarm":
				check(not sim.radio.alarm_on, "The alarm: rung, and stood down")
				var rung := false
				for e in sim.radio.news:
					if String(e.kind) == "alarm" and String(e.text) == "Call to arms":
						rung = true
				check(rung, "and it was rung (the radio's log says so)")
			"dusk":
				check(sim.bell_rung and sim.kills >= 2, "Dusk: the bell rang and the dead were shot (%d)" % sim.kills)
			"jobs":
				pass
	eq(main.coach.step_id() if main.coach != null else "", "wrap", "the bot got to the last card")
	var rest: Dictionary = await Bot.play(main)
	eq(rest.stuck, "", "and played it")
	check(main.coach == null, "the coach finished")
	check(Prefs.flag("tutorial_done"), "the tutorial_done flag is set")
	eq(sim.over, "", "the run is not over")
	check(sim.scenario.finished and not sim.scenario.coached, "the scenario was let go")
	check(sim.waves.enabled, "and the real nights are on")
	check(main.speed > 0, "the game runs again")
	check(main.avatar_mode and sim.player_id == "ruth", "Ruth is still the player")
	# the duty roster's lesson: a job was given on the page, and the page was shut
	eq(sim.jobs.job_of(Bot.person(main, "hector")), "builders", "Hector was given the Builders job on the Duty roster")
	check(main.hud.jobs_screen == null, "and the page is shut")
	# the lesson touched none of the player's own saves
	eq(FileAccess.file_exists(SaveGame.QUICK_PATH), quick_before, "the real quick save was neither made nor removed")
	if quick_before:
		eq(FileAccess.get_modified_time(SaveGame.QUICK_PATH), quick_time, "nor changed")
	await Tut.leave(main)


## The title: the first launch's card (flag `tutorial_offered`) or the menu's own line asks for Orientation Day, the title asks the
## game for it, and the run that begins is played by the bot to the end, with the flag `tutorial_done` set at the last card.
func test_the_bot_plays_the_lesson_that_the_titles_first_launch_card_starts() -> void:
	var title = Tut.start({"title": true})
	await Tut.frames(title, 3)
	var picked: Array = []
	title.restart = func(meta): picked.append(meta)
	Prefs.set_flag("tutorial_offered", false)
	Prefs.set_flag("tutorial_done", false)
	title.shell.show_title()
	await Tut.settle()
	eq(title.shell.kinds(), ["orientation"], "the first time: the card")
	title.shell.top().start_button.pressed.emit()
	await Tut.settle()
	eq(picked.size(), 1, "Start Orientation Day begins a run")
	var meta: Dictionary = picked[0]
	eq(meta, {"tutorial": true, "avatar": true}, "the avatar's lesson")
	await Tut.leave(title)
	# the real game's scene, with that choice and no --noavatar
	check(MainScript.wants_avatar([], meta, false, true, true), "the real game plays it with an avatar")
	var main = Tut.start(meta)
	await Tut.frames(main, 3)
	check(main.avatar_mode and main.tutorial, "the choice is the avatar's Orientation Day")
	check(not Prefs.flag("tutorial_done"), "not done yet")
	var r: Dictionary = await Bot.play(main)
	eq(r.stuck, "", "the bot was never stuck")
	eq(r.seen, _ids_of_file(), "every step, in order")
	check(main.coach == null and Prefs.flag("tutorial_done"), "the lesson is done and the flag is set")
	await Tut.leave(main)


func _ids_of_file() -> Array:
	var ids: Array = []
	for s in Coach.load_steps(Coach.STEPS_PATH):
		ids.append(String(s.id))
	return ids


# ----------------------------------------------------------- a save in the middle --

func test_a_save_in_the_middle_of_the_avatars_lesson_resumes_it() -> void:
	var main = Tut.avatar_game()
	await Tut.frames(main, 3)
	var r: Dictionary = await Bot.play(main, "come", 400000, false)
	eq(r.stuck, "", "the bot got to the lesson on asking")
	var before := {
		"step": main.coach.step_id(),
		"phase": main.coach.phase,
		"fired": main.sim.scenario.fired.duplicate(),
		"fingerprint": Tut.fingerprint(main.sim),
		"state": main.coach.state.duplicate(true),
	}
	main._key(KEY_F5)
	var path: String = main.tutorial_save_path
	check(FileAccess.file_exists(path), "F5 wrote the tutorial's own file")
	await Tut.leave(main, true)
	var again = Tut.start({"load": path})
	await Engine.get_main_loop().process_frame
	var coach = again.coach
	check(again.tutorial and coach != null, "the tutorial is back, with its coach")
	if coach == null:
		await Tut.leave(again)
		return
	check(again.avatar_mode and again.sim.player_id == "ruth", "with Ruth as the player")
	check(again.sim.town.on and again.sim.scenario.avatar, "the town on and the lesson the avatar's")
	eq(coach.step_id(), before.step, "the same step")
	eq(Tut.fingerprint(again.sim), before.fingerprint, "the world as it was")
	eq(again.sim.scenario.fired, before.fired, "and the same beats")
	eq(coach.state.did, before.state.did, "what the player did")
	eq(coach.steps.size(), 13, "the avatar's steps (not the old yard's)")
	var played: Dictionary = await Bot.play(again)
	eq(played.stuck, "", "the loaded game plays on to the end")
	check(again.coach == null and Prefs.flag("tutorial_done"), "and the lesson finishes with the flag set")
	await Tut.leave(again)
