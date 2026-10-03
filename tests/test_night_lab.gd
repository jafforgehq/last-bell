extends "res://tests/case.gd"
## The night lab (round 19, slice 3, docs/superpowers/plans/2026-10-03-round-19.md, H3.2 and H3.3; tools/night_lab.gd): states of a
## no-avatar game at 17:30 of wanted days, each night played again from the same state in `none`, `idle` and `bot`, the same dice for the
## three of a rep, and a row for each night; the table and the six numeric targets are read from the rows.

const Helpers := preload("res://tests/helpers.gd")
const Lab := preload("res://tools/night_lab.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const HZ := 15.0


## A night row as `NightStats` makes it, with the fields a table or a target reads set by hand.
func _row(mode: String, day: int, kind: String, held: bool, extra: Dictionary = {}) -> Dictionary:
	var r := {
		"day": day, "kind": kind, "mode": mode, "size": 40, "plated": 0, "sections_fell": 0 if held else 1, "fell": [], "walls_fell": 0, "down_at_dawn": 0,
		"hp_lost": 20.0, "hp_by_seg": {}, "min_wall": 0.7, "died": 0, "downed": 0, "bites": 0, "held": held, "over": false, "ready": false,
		"ready_known": true, "people": 5, "stock_ammo0": 300.0, "stock_ammo": 280.0, "first_at": -1.0, "targets": [], "first_claw_at": -1.0,
		"avatar": {"present": 0.0, "threat_steps": 0, "present_steps": 0, "shots": 0, "kills": 0, "hp_min": 100.0, "downed": 0, "died": 0, "ammo": 0.0},
		"calls": {"raised": 0, "answered_by_player": 0, "by_default": 0, "mean_s": 0.0}, "brute_s": [],
	}
	r.merge(extra, true)
	return r


# ------------------------------------------------------------------ the flags --

func test_the_lab_reads_its_lists_and_ranges() -> void:
	eq(Lab.parse_ints("3,6,9,10"), [3, 6, 9, 10], "a list")
	eq(Lab.parse_ints("1..4"), [1, 2, 3, 4], "a range")
	eq(Lab.parse_ints("1..3,7,9..10"), [1, 2, 3, 7, 9, 10], "both")
	eq(Lab.parse_ints(""), [], "nothing")
	eq(Lab.parse_ints("x,2"), [2], "what is no number is left out")
	eq(Lab.parse_modes("none,idle,bot"), ["none", "idle", "bot"], "the three modes")
	eq(Lab.parse_modes("bot,idle,wizard"), ["idle", "bot"], "in the lab's order, an unknown one dropped")


# ------------------------------------------------------------------- the states --

func test_a_state_is_taken_at_half_past_five_of_a_wanted_day_and_a_lost_game_gives_no_later_one() -> void:
	var states: Dictionary = Lab.snapshots(3, [2, 3], 5, HZ)
	check(states.has(2), "a state for day 2")
	if states.has(2):
		var s: Dictionary = states[2]
		eq(int(s.day), 2, "of day 2")
		eq(String(s.phase), "day", "by day")
		check(float(s.minutes) >= 17.5 * 60.0 and float(s.minutes) < 17.5 * 60.0 + 3.0, "at 17:30 (%.1f min)" % float(s.minutes))
	for day in states:
		check([2, 3].has(int(day)), "only the wanted days")


# ------------------------------------------------------------ the same night, three ways --

func test_the_same_state_and_the_same_seed_give_the_same_row_twice() -> void:
	var states: Dictionary = Lab.snapshots(3, [2], 5, HZ)
	if not states.has(2):
		failures.append("no state for day 2")
		return
	var a: Dictionary = Lab.night(states[2], 3, 0, "idle", 2, 5, HZ)
	var b: Dictionary = Lab.night(states[2], 3, 0, "idle", 2, 5, HZ)
	eq(JSON.stringify(a, "", true, true), JSON.stringify(b, "", true, true), "the same row")
	eq(int(a.day), 2, "the night of day 2")
	eq(String(a.mode), "idle", "in its mode")
	eq(int(a.seed), 3, "the seed is in the row")
	eq(int(a.rep), 0, "and the rep")
	var c: Dictionary = Lab.night(states[2], 3, 1, "idle", 2, 5, HZ)
	check(int(c.rep) == 1, "another rep is another night (its dice are other)")


func test_the_three_modes_start_from_the_same_state_with_the_same_dice() -> void:
	var states: Dictionary = Lab.snapshots(3, [2], 5, HZ)
	if not states.has(2):
		failures.append("no state for day 2")
		return
	var starts: Dictionary = {}
	for mode in ["none", "idle", "bot"]:
		starts[mode] = Lab.start(states[2], 3, 4, mode, 5)
	var none_sim = starts.none.sim
	for mode in ["idle", "bot"]:
		var sim = starts[mode].sim
		eq(sim.day, none_sim.day, "%s: the same day" % mode)
		near(float(sim.minutes), float(none_sim.minutes), 0.0001, "%s: the same minute" % mode)
		eq(sim.rng.state, none_sim.rng.state, "%s: the same dice (state)" % mode)
		eq(sim.rng.seed, none_sim.rng.seed, "%s: the same dice (seed)" % mode)
		eq(JSON.stringify(sim.stock), JSON.stringify(none_sim.stock), "%s: the same stores" % mode)
		eq(sim.zombies.size(), none_sim.zombies.size(), "%s: the same dead" % mode)
		for i in sim.segments.size():
			near(float(sim.segments[i].hp), float(none_sim.segments[i].hp), 0.0001, "%s: the same wall %d" % [mode, i])
		for i in sim.people.size():
			if String(sim.people[i].id) == "ruth":
				continue
			near(float(sim.people[i].x), float(none_sim.people[i].x), 0.0001, "%s: %s stands where they did" % [mode, sim.people[i].first])
			near(float(sim.people[i].hp), float(none_sim.people[i].hp), 0.0001, "%s: %s has the health they had" % [mode, sim.people[i].first])
	eq(none_sim.player_id, "", "none: nobody is the player")
	eq(starts.idle.sim.player_id, "ruth", "idle: Ruth is")
	eq(starts.bot.sim.player_id, "ruth", "bot: Ruth is")
	var spot: Vector2 = BotLib.SAFE_SPOT
	var ruth = starts.idle.sim.avatar.player()
	check(Vector2(ruth.x, ruth.y).distance_to(spot) < 0.01, "an idle Ruth is in the school gym")
	for mode in starts:
		starts[mode].g.world.free()


func test_when_ruth_is_dead_in_the_state_the_next_in_line_is_the_avatar() -> void:
	var states: Dictionary = Lab.snapshots(3, [2], 5, HZ)
	if not states.has(2):
		failures.append("no state for day 2")
		return
	var state: Dictionary = states[2].duplicate(true)
	var killed := false
	for p in state.people:
		if String(p.id) == "ruth":
			p["dead"] = true
			p["downed"] = true
			p["hp"] = 0.0
			killed = true
	check(killed, "Ruth is in the state")
	for mode in ["idle", "bot"]:
		var st: Dictionary = Lab.start(state, 3, 0, mode, 5)
		var sim = st.sim
		check(String(sim.player_id) != "" and String(sim.player_id) != "ruth", "%s: somebody else is the avatar (%s)" % [mode, sim.player_id])
		var me = sim.avatar.player()
		check(me != null and not me.dead, "%s: and they are alive" % mode)
		st.g.world.free()
	var none: Dictionary = Lab.start(state, 3, 0, "none", 5)
	eq(none.sim.player_id, "", "none: nobody is")
	none.g.world.free()


func test_a_night_on_the_first_day_of_a_new_game_is_one_row_for_each_mode() -> void:
	var rows: Array = Lab.run([3], [2], 1, ["none", "idle"], 5, HZ, "")
	eq(rows.size(), 2, "two nights: one for each mode")
	for r in rows:
		eq(int(r.day), 2, "the night of day 2")
		eq(int(r.seed), 3, "of seed 3")
		for key in ["kind", "mode", "size", "sections_fell", "fell", "down_at_dawn", "hp_lost", "min_wall", "died", "downed", "bites", "held", "ready", "avatar", "calls", "brute_s"]:
			check(r.has(key), "the row has `%s`" % key)
	eq(String(rows[0].mode), "none", "the modes come in the lab's order")
	eq(String(rows[1].mode), "idle", "and idle after it")


# ------------------------------------------------------------- the table and the targets --

func test_the_table_has_a_line_for_each_group_and_mode_and_marks_a_thin_cell() -> void:
	var rows: Array = []
	for i in 50:
		rows.append(_row("idle", 3, "ordinary", i % 5 != 0))
	for i in 10:
		rows.append(_row("bot", 10, "milestone", true))
	var text: String = Lab.table_text(rows)
	check(text.contains("1-9"), "the ordinary nights of the first nine days")
	check(text.contains("big"), "the Big Nights")
	check(text.contains("idle") and text.contains("bot"), "the two modes")
	check(not text.contains("none"), "none is not in it: there is no night of it")
	var lines := text.split("\n")
	var thin := ""
	var full := ""
	for l in lines:
		if l.begins_with("big"):
			thin = l
		if l.begins_with("1-9"):
			full = l
	check(thin.contains("*"), "a cell of fewer than %d nights is starred: %s" % [Lab.MIN_CELL, thin])
	check(not full.contains("*"), "a cell of %d is not: %s" % [Lab.MIN_CELL, full])
	check(full.contains(" 80%"), "the held share of the 50 is 80%%: %s" % full)


func test_each_target_is_read_from_the_rows_and_is_not_met_when_the_rows_say_not() -> void:
	var rows: Array = []
	# ordinary nights 1 to 9: idle holds 90% (9 of 10), bot 98%
	for i in 60:
		rows.append(_row("idle", 3, "ordinary", i % 10 != 0, {"ready": true}))
		rows.append(_row("bot", 3, "ordinary", i % 50 != 0))
	# Big nights: idle holds 2 of 10; the bot 9 of 10, near the pressed wall
	for i in 50:
		rows.append(_row("idle", 10, "milestone", i % 5 == 0, {"died": 0 if i % 5 == 0 else 1}))
		rows.append(_row("bot", 10, "milestone", i % 10 != 0, {"avatar": {"present": 0.7, "threat_steps": 20, "present_steps": 14, "shots": 30, "kills": 10, "hp_min": 60.0, "downed": 0, "died": 0, "ammo": 6.0}}))
	var t: Dictionary = Lab.targets(rows)
	check(t.has("1") and t.has("2") and t.has("3") and t.has("4") and t.has("6"), "a verdict for targets 1, 2, 3, 4 and 6")
	eq(String(t["1"].verdict), "met", "ordinary nights, idle: held 90%% (%s)" % String(t["1"].text))
	eq(String(t["2"].verdict), "met", "Big Nights, idle: held 20%% (%s)" % String(t["2"].text))
	eq(String(t["3"].verdict), "met", "Big Nights, bot: 90%% held, present 0.7 (%s)" % String(t["3"].text))
	eq(String(t["4"].verdict), "met", "ordinary nights: the bot holds more than idle (%s)" % String(t["4"].text))
	# the same with a bot that does not hold the Big Night
	var bad: Array = []
	for r in rows:
		if String(r.mode) == "bot" and String(r.kind) == "milestone":
			var c: Dictionary = r.duplicate(true)
			c["held"] = false
			c["sections_fell"] = 1
			bad.append(c)
		else:
			bad.append(r)
	var tb: Dictionary = Lab.targets(bad)
	eq(String(tb["3"].verdict), "not met", "Big Nights, bot: none held (%s)" % String(tb["3"].text))
	eq(String(Lab.targets([])["1"].verdict), "no data", "with no nights there is no verdict")


func test_the_states_are_kept_in_a_directory_and_read_again_from_it() -> void:
	var dir := "user://test_r19_bot_states_%d" % OS.get_process_id()
	var first: Dictionary = Lab.states_for(3, [2], 5, HZ, dir)
	check(first.has(2), "the state is made")
	var file := dir.path_join("s3_d2.json")
	check(FileAccess.file_exists(file), "and kept")
	check(FileAccess.file_exists(dir.path_join("s3_index.json")), "with the index of what was asked for")
	var second: Dictionary = Lab.states_for(3, [2], 5, HZ, dir)
	check(second.has(2), "the next time it is read from there")
	if first.has(2) and second.has(2):
		eq(int(second[2].day), int(first[2].day), "the same day")
		eq(second[2].people.size(), first[2].people.size(), "the same people")
		eq(str(second[2].rng_state), str(first[2].rng_state), "the same dice")
	# a different crew is not the same states: they are made again
	var other: Dictionary = Lab.states_for(3, [2], 4, HZ, dir)
	check(other.has(2), "another crew is made again")
	var index = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("s3_index.json")))
	eq(int(index.crew), 4, "and the index says for which crew they are")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
