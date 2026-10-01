extends "res://tests/case.gd"
## A headless bot plays Orientation Day from the first card to the last through the real handlers
## (input events, the crew cards, the order keys and buttons, the scavenging dialog and the
## coach's own buttons) with the coach teaching and the rules stepping, and nothing goes wrong:
## every step is reached in order, the run is never over, and the lesson ends with the flag set.

const Tut := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Prefs := preload("res://scripts/prefs.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func test_a_bot_plays_every_step_to_the_end() -> void:
	var quick_before := FileAccess.file_exists(SaveGame.QUICK_PATH)
	var quick_time := FileAccess.get_modified_time(SaveGame.QUICK_PATH) if quick_before else 0
	var auto_before := FileAccess.file_exists(SaveGame.AUTO_PATH)
	var auto_time := FileAccess.get_modified_time(SaveGame.AUTO_PATH) if auto_before else 0
	var main = Tut.game()
	var sim = main.sim
	await Tut.frames(main, 3)
	var coach = main.coach
	check(coach != null, "the coach is there")
	var all_ids: Array = []
	for s in coach.steps:
		all_ids.append(String(s.id))
	var r: Dictionary = await Bot.play(main)
	eq(r.stuck, "", "the bot was never stuck")
	eq(r.seen, all_ids, "every step was reached, in order")
	check(main.coach == null, "the coach finished")
	check(Prefs.flag("tutorial_done"), "the tutorial_done flag is set")
	eq(sim.over, "", "the run is not over")
	check(sim.scenario.finished and not sim.scenario.coached, "the scenario was let go")
	check(sim.waves.enabled, "and the real nights are on")
	check(main.speed > 0, "the game runs again")
	# the lesson went through a dawn and a save, and touched none of the player's own saves
	check(FileAccess.file_exists(main.tutorial_save_path), "F5 wrote the tutorial's own file")
	main._key(KEY_F5)
	eq(FileAccess.file_exists(SaveGame.QUICK_PATH), quick_before, "the real quick save was neither made nor removed")
	if quick_before:
		eq(FileAccess.get_modified_time(SaveGame.QUICK_PATH), quick_time, "nor changed")
	eq(FileAccess.file_exists(SaveGame.AUTO_PATH), auto_before, "the dawn did not autosave")
	if auto_before:
		eq(FileAccess.get_modified_time(SaveGame.AUTO_PATH), auto_time, "or change the autosave")
	await Tut.leave(main)
