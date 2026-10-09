extends "res://tests/case.gd"
## What a save file says about itself (SaveGame.peek, read without loading it), which one
## Continue takes, and how the load list tells a good save from a damaged one.

const Fakes := preload("res://tests/menu_fakes.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")
const HudKit := preload("res://tests/hud_kit.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Helpers := preload("res://tests/helpers.gd")

var tmp_a := "user://test_menu_peek_a_%d.json" % OS.get_process_id()
var tmp_b := "user://test_menu_peek_b_%d.json" % OS.get_process_id()


func _clean() -> void:
	Fakes.clean([tmp_a, tmp_b])


# ------------------------------------------------------------------- peek --

func test_peek_reads_the_day_the_hour_the_difficulty_and_who_is_alive() -> void:
	_clean()
	check(Fakes.write_save(tmp_a, 7, 14.5, 2, 2), "the save was written")
	var info := SaveGame.peek(tmp_a)
	check(info.ok, "a good save: %s" % str(info))
	eq(info.day, 7, "the day")
	near(float(info.hour), 14.5, 0.0001, "the hour")
	eq(info.difficulty, 2, "the difficulty")
	eq(info.people, 4, "four alive of six")
	eq(info.crew, 6, "all of them counted")
	eq(info.version, SaveGame.VERSION, "the version of the file")
	eq(info.over, "", "the run goes on")
	check(info.exists, "it is there")
	check(int(info.modified) > 1600000000, "with the time it was written: %d" % int(info.modified))
	eq(info.reason, "", "and no complaint")
	_clean()


func test_peek_counts_the_turned_as_lost_too() -> void:
	_clean()
	var g := Helpers.make(5, 1)
	g.sim.people[0].turned = true
	g.sim.people[0].dead = true
	g.sim.people[1].dead = true
	SaveGame.write(g.sim, tmp_a)
	g.world.free()
	eq(SaveGame.peek(tmp_a).people, 4, "two of six are gone, whichever way")
	_clean()


func test_peek_does_not_change_the_file_and_needs_no_game() -> void:
	_clean()
	Fakes.write_save(tmp_a)
	var before := FileAccess.get_file_as_string(tmp_a)
	var when := FileAccess.get_modified_time(tmp_a)
	SaveGame.peek(tmp_a)
	SaveGame.peek(tmp_a)
	eq(FileAccess.get_file_as_string(tmp_a), before, "the file is as it was")
	eq(FileAccess.get_modified_time(tmp_a), when, "and was not touched")
	check(SaveGame.is_loadable(tmp_a), "it still loads")
	_clean()


func test_peek_of_a_missing_file_says_it_is_empty() -> void:
	var info := SaveGame.peek("user://there_is_no_such_save_%d.json" % OS.get_process_id())
	check(not info.ok, "not a save")
	check(not info.exists, "and not there")
	eq(info.reason, "Empty", "an empty slot")
	eq(info.modified, 0, "with no time")
	check(not info.has("day"), "and no day")


func test_peek_of_a_damaged_file_says_so() -> void:
	_clean()
	Fakes.write_text(tmp_a, "{ this is not json")
	var info := SaveGame.peek(tmp_a)
	check(not info.ok and info.exists, "a file that is not a save")
	eq(info.reason, "Damaged", "says damaged")
	check(int(info.modified) > 0, "and when it was written")
	Fakes.write_text(tmp_a, "")
	eq(SaveGame.peek(tmp_a).reason, "Damaged", "an empty file is damaged")
	Fakes.write_text(tmp_a, "[1, 2, 3]")
	eq(SaveGame.peek(tmp_a).reason, "Damaged", "JSON that is not a dictionary is damaged")
	# a save cut off half way
	Fakes.write_save(tmp_b)
	var text := FileAccess.get_file_as_string(tmp_b)
	Fakes.write_text(tmp_a, text.left(text.length() / 2))
	eq(SaveGame.peek(tmp_a).reason, "Damaged", "a save cut in half is damaged")
	_clean()


func test_peek_of_a_save_from_another_version_says_so() -> void:
	_clean()
	Fakes.write_save(tmp_a)
	var data := SaveGame.read(tmp_a)
	data["version"] = SaveGame.VERSION + 1
	Fakes.write_text(tmp_a, SaveGame.to_text(data))
	var info := SaveGame.peek(tmp_a)
	check(not info.ok, "not one this version loads")
	eq(info.reason, "Newer version", "says why (SAVE4: a later format is a newer version)")
	eq(info.version, SaveGame.VERSION + 1, "and which version it is")
	check(not SaveGame.is_loadable(tmp_a), "and is_loadable agrees")
	data["version"] = SaveGame.VERSION - 1
	Fakes.write_text(tmp_a, SaveGame.to_text(data))
	eq(SaveGame.peek(tmp_a).reason, "Older version", "an older one too")
	_clean()


func test_peek_of_a_save_with_its_numbers_wrong_is_damaged() -> void:
	_clean()
	Fakes.write_save(tmp_a)
	var good := SaveGame.read(tmp_a)
	var wrong := {
		"the day is text": {"day": "seven"},
		"no day at all": {"day": null},
		"day zero": {"day": 0},
		"a fraction of a day": {"day": 2.5},
		"a time past midnight": {"minutes": 25.0 * 60.0},
		"a negative time": {"minutes": -5.0},
		"a difficulty that does not exist": {"difficulty": 5},
		"a negative difficulty": {"difficulty": -1},
		"no people": {"people": null},
		"people that are not people": {"people": [1, 2, 3]},
		"no stock": {"stock": null},
	}
	for what in wrong:
		var data := good.duplicate(true)
		for k in wrong[what]:
			if wrong[what][k] == null:
				data.erase(k)
			else:
				data[k] = wrong[what][k]
		Fakes.write_text(tmp_a, SaveGame.to_text(data))
		var info := SaveGame.peek(tmp_a)
		check(not info.ok, "%s is not a save: %s" % [what, str(info)])
		eq(info.reason, "Damaged", "%s: damaged" % what)
	_clean()


func test_peek_agrees_with_a_real_load() -> void:
	# whatever peek calls good loads, and what it reads is what the game has
	_clean()
	Fakes.write_save(tmp_a, 11, 20.25, 0, 1)
	var info := SaveGame.peek(tmp_a)
	var g := Helpers.make(1, 1)
	check(SaveGame.apply(g.sim, SaveGame.read(tmp_a)), "the save loads")
	eq(g.sim.day, info.day, "the day it says is the day it has")
	near(g.sim.minutes / 60.0, float(info.hour), 0.0001, "so is the hour")
	eq(g.sim.difficulty, info.difficulty, "and the difficulty")
	var alive := 0
	for p in g.sim.people:
		if not p.dead and not p.turned:
			alive += 1
	eq(alive, info.people, "and who is alive")
	g.world.free()
	_clean()


# ----------------------------------------------------------------- words --

func test_the_words_that_describe_a_save() -> void:
	eq(Kit.clock_text(14.5), "14:30", "half past two")
	eq(Kit.clock_text(7.0), "07:00", "seven, with its nought")
	eq(Kit.clock_text(0.0), "00:00", "midnight")
	eq(Kit.clock_text(23.99), "23:59", "a minute before midnight")
	eq(Kit.clock_text(23.999), "00:00", "a hair before midnight rounds to midnight, not to 24:00")
	eq(Kit.clock_text(14.333), "14:20", "a third of an hour")
	var info := {"ok": true, "day": 7, "hour": 14.333, "difficulty": 1}
	eq(Kit.save_line(info), "Day 7, 14:20, Standard", "the line the Continue button shows")
	info["difficulty"] = 0
	eq(Kit.save_line(info), "Day 7, 14:20, Story", "Story")
	info["difficulty"] = 2
	eq(Kit.save_line(info), "Day 7, 14:20, Brutal", "Brutal")
	eq(Kit.save_line({"ok": false, "reason": "Damaged"}), "Damaged", "a save that is not good says why")
	eq(Kit.ago_text(1000, 1010), "just now", "ten seconds")
	eq(Kit.ago_text(1000, 1000 + 5 * 60), "5 min ago", "five minutes")
	eq(Kit.ago_text(1000, 1000 + 3 * 3600), "3 h ago", "three hours")
	eq(Kit.ago_text(1000, 1000 + 30 * 3600), "yesterday", "a day and a bit")
	check(Kit.ago_text(1000, 1000 + 10 * 86400).begins_with("Jan "), "a week on: the date: '%s'" % Kit.ago_text(1000, 1000 + 10 * 86400))
	eq(Kit.ago_text(0, 5000), "", "no time known")
	eq(Kit.percent_text(1.25), "125%", "a percentage")
	eq(Kit.percent_text(0.8), "80%", "eighty")


# ---------------------------------------------------------- the newest one --

func test_the_newest_save_is_the_one_written_last() -> void:
	var older := {"ok": true, "modified": 1000, "day": 9, "hour": 8.0}
	var newer := {"ok": true, "modified": 2000, "day": 3, "hour": 8.0}
	eq(Kit.newest_index([older, newer]), 1, "the later file")
	eq(Kit.newest_index([newer, older]), 0, "whichever place it is in")
	var damaged := {"ok": false, "exists": true, "modified": 3000, "reason": "Damaged"}
	eq(Kit.newest_index([older, damaged]), 0, "a damaged one is never taken, even the newest")
	eq(Kit.newest_index([damaged, newer, older]), 1, "the newest good one is")
	eq(Kit.newest_index([damaged]), -1, "nothing good: none")
	eq(Kit.newest_index([]), -1, "no saves: none")
	var empty := {"ok": false, "exists": false, "modified": 0, "reason": "Empty"}
	eq(Kit.newest_index([empty, empty]), -1, "empty slots: none")
	# the same second: the further on in the run
	var a := {"ok": true, "modified": 5000, "day": 4, "hour": 20.0}
	var b := {"ok": true, "modified": 5000, "day": 5, "hour": 6.0}
	eq(Kit.newest_index([a, b]), 1, "written in the same second: the later day")
	eq(Kit.newest_index([b, a]), 0, "in either order")


func test_continue_loads_the_newest_save() -> void:
	var ctx := Fakes.build()
	var shell = ctx.shell
	var paths: Array = ctx.paths
	check(shell.newest_save().is_empty(), "no saves: nothing to continue")
	check(not shell.continue_game(), "so Continue does not")
	check(ctx.main.last("load_run").is_empty(), "and loads nothing")
	check(shell.toast_panel.visible and shell.toast_label.text.contains("no saved game"), "it says there is none: '%s'" % shell.toast_label.text)
	check(ctx.sound.ui_played.has("ui_error"), "with the sound of no")
	# one save: that one
	Fakes.write_save(paths[0], 5, 9.0, 1)
	eq(shell.newest_save().slot.name, "Autosave", "the one save there is")
	# a second, written a moment later
	OS.delay_msec(1100)
	Fakes.write_save(paths[1], 2, 17.0, 0)
	var best: Dictionary = shell.newest_save()
	eq(best.slot.name, "Quick save", "the one written last, though it is the earlier day")
	eq(best.info.day, 2, "with its own day")
	check(shell.continue_game(), "Continue goes")
	eq(ctx.main.last("load_run"), ["load_run", paths[1]], "to the newest file")
	check(ctx.sound.ui_played.has("ui_confirm"), "with the sound of yes")
	# the newest goes bad: the one before it is taken
	Fakes.write_text(paths[1], "{ half a sav")
	best = shell.newest_save()
	eq(best.slot.name, "Autosave", "a damaged file is passed over")
	Fakes.free_all(ctx)


func test_a_save_that_cannot_be_loaded_is_not_loaded() -> void:
	var ctx := Fakes.build()
	var shell = ctx.shell
	Fakes.write_text(ctx.paths[0], "{ not a save")
	check(not shell.load_slot(ctx.paths[0]), "a damaged save is refused")
	check(ctx.main.last("load_run").is_empty(), "the game is not asked to load it")
	check(shell.toast_label.text.contains("damaged"), "and the toast says why: '%s'" % shell.toast_label.text)
	check(ctx.sound.ui_played.has("ui_error"), "with the sound of no")
	check(not shell.load_slot("user://nowhere_%d.json" % OS.get_process_id()), "a missing one too")
	check(shell.toast_label.text.to_lower().contains("empty"), "'%s'" % shell.toast_label.text)
	Fakes.write_save(ctx.paths[1])
	check(shell.load_slot(ctx.paths[1]), "a good one is loaded")
	eq(ctx.main.last("load_run"), ["load_run", ctx.paths[1]], "through the game")
	# the game itself may refuse
	ctx.main.load_ok = false
	check(not shell.load_slot(ctx.paths[1]), "if the game says no, that is the answer")
	check(shell.toast_label.text.contains("cannot be loaded"), "'%s'" % shell.toast_label.text)
	Fakes.free_all(ctx)


# --------------------------------------------------------------- the list --

func test_the_load_list_tells_each_slot_what_it_holds() -> void:
	var ctx := Fakes.build()
	var shell = ctx.shell
	Fakes.write_save(ctx.paths[0], 7, 7.0, 1, 1)
	Fakes.write_text(ctx.paths[1], "{ nope")
	var screen = shell.open_load(false)
	await HudKit.settle()
	eq(screen.rows.size(), 2, "a row for each slot")
	var good: Button = screen.rows[0].button
	var bad: Button = screen.rows[1].button
	var good_text: String = good.get_meta("sub").text
	check(good_text.begins_with("Day 7, 07:00, Standard"), "the good one: '%s'" % good_text)
	check(good_text.contains("5 of 6 alive"), "with who is alive: '%s'" % good_text)
	check(good_text.contains("just now") or good_text.contains("min ago"), "and when: '%s'" % good_text)
	var bad_text: String = bad.get_meta("sub").text
	check(bad_text.to_lower().contains("damaged") and bad_text.contains("cannot be loaded"), "the damaged one says so: '%s'" % bad_text)
	# a damaged one is not loaded when it is picked
	bad.pressed.emit()
	check(ctx.main.last("load_run").is_empty(), "nothing is loaded")
	check(screen.error_label.visible and screen.error_label.text.contains("damaged"), "the screen says so: '%s'" % screen.error_label.text)
	check(ctx.sound.ui_played.has("ui_error"), "with the sound of no")
	# the good one is
	good.pressed.emit()
	eq(ctx.main.last("load_run"), ["load_run", ctx.paths[0]], "the good one is loaded")
	Fakes.free_all(ctx)


func test_an_empty_slot_says_it_is_empty() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_load(true)
	await HudKit.settle()
	var text: String = screen.rows[0].button.get_meta("sub").text
	check(text.begins_with("Nothing saved here yet"), "'%s'" % text)
	var room_before: float = screen.scroll.custom_minimum_size.y
	screen.rows[0].button.pressed.emit()
	await HudKit.settle()
	check(screen.error_label.visible and screen.error_label.text.contains("nothing"), "picking it says so: '%s'" % screen.error_label.text)
	check(screen.scroll.custom_minimum_size.y > room_before, "and the list makes room for the line (%.0f to %.0f), so nothing has to scroll" % [room_before, screen.scroll.custom_minimum_size.y])
	check(screen.scroll.custom_minimum_size.y >= screen.body.get_combined_minimum_size().y - 0.5, "all of it shows")
	check(ctx.main.last("load_run").is_empty(), "and loads nothing")
	var notes := HudKit.texts(screen)
	check(notes.has("Loading replaces the game you are playing."), "from the pause menu the list warns that a load replaces the game")
	Fakes.free_all(ctx)
