## The night lab (round 19, slice 3: docs/superpowers/plans/2026-10-03-round-19.md, H3.2 and H3.3): the same night played three ways.
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --headless --path . --script res://tools/night_lab.gd -- --days=3,6,9,10 --seeds=1..8 --reps=6 --modes=none,idle,bot --crew=5 --jobs=4 [--out=path.json]
##
## For each seed a no-avatar game (the informed policy, as `tools/balance.gd --policy=informed`) is played once to 17:30 of each wanted
## day and its state taken (`SaveGame.to_dict`). Every state is then loaded into a fresh sim for every mode and every rep, the rules' dice
## re-seeded (`seed x 1000 + rep`: the three modes of a rep throw the same dice), the mode switched on and the night played to the first step
## of the next day by a fresh informed policy (the morning's chores marked done), and the `NightStats` row of it kept. The modes:
##   none   the night as it is today, no avatar (on a Big Night's day this is an ordinary night, a reference only)
##   idle   Ruth is the player and keeps her hands off, in the school gym: the community alone holds the night
##   bot    the bot plays her (tools/avatar_bot.gd)
## A night costs about a second and a half at 15 Hz.
##
## Flags (all optional):
##   --days=3,6,9,10,15,20  the days whose nights are played (the game must be alive at 17:30 of the day to give a state: a colony lost
##                          before it leaves its cells empty)
##   --seeds=1..8           the seeds of the no-avatar games (a list or a range, or both: 1..3,7)
##   --reps=6               how many times each state is played in each mode
##   --modes=none,idle,bot  which modes
##   --crew=5               the small start's crew (3 to 6); --campaign plays the four-season game
##   --hz=15                steps a second
##   --jobs=4               play the seeds in this many worker processes (the seeds are shared out)
##   --states=dir           keep the states there (and read them from there next time: the tuning runs the cells again on the same states)
##   --data=path            read another nights.json (a number tried before it is in the game)
##   --out=path.json        write every row, the table and the verdicts
##   --base                 round 25: the base management (briefing, priorities, dials, problems, dilemma) is ON in the idle and bot modes (off by default, as in the
##                          rounds before it)
##   --quiet                no lines (a worker's)
## It prints a line for each night, the table (a cell is a group of days and a mode; a cell of fewer than MIN_CELL nights is starred) and
## the verdict on each of the plan's numeric targets (docs/superpowers/plans/2026-10-03-round-19.md, H3.3).
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const Balance := preload("res://tools/balance.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const NightData := preload("res://scripts/sim/night_data.gd")

const MODES := ["none", "idle", "bot"]
## A cell of the table is trusted from this many nights.
const MIN_CELL := 48
## The hour of the wanted day the state is taken at.
const WANT_HOUR := 17.5


# ------------------------------------------------------------------------ flags --

## "3,6,9" or "1..8" or "1..3,7": the whole numbers in the order given (what is no number is left out).
static func parse_ints(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		var t := String(part).strip_edges()
		if t.contains(".."):
			var ends := t.split("..", false)
			if ends.size() == 2 and ends[0].is_valid_int() and ends[1].is_valid_int():
				for v in range(int(ends[0]), int(ends[1]) + 1):
					out.append(v)
		elif t.is_valid_int():
			out.append(t.to_int())
	return out


## The modes named, in the lab's order (none, idle, bot); an unknown name is dropped.
static func parse_modes(text: String) -> Array:
	var names := text.split(",", false)
	var out: Array = []
	for m in MODES:
		if names.has(m):
			out.append(m)
	return out


# ----------------------------------------------------------------------- states --

## The state at 17:30 of each of `days` of a no-avatar game of `seed_value` (the informed policy, the harness's settings), as
## {day: SaveGame.to_dict}. A game that is lost, or ends, before a day gives nothing for it.
static func snapshots(seed_value: int, days: Array, crew: int, hz: float) -> Dictionary:
	var out := {}
	var want: Array = days.duplicate()
	want.sort()
	if want.is_empty():
		return out
	var g := Helpers.make(seed_value, 1, crew, Balance.campaign)
	var sim = g.sim
	sim.streets.enabled = Balance.streets_on
	sim.storyteller.enabled = Balance.story_on
	var policy := Balance.policy_for(sim, false, true)
	var dt := 1.0 / hz
	var every := maxi(1, roundi(hz))
	var step := 0
	var last: int = int(want[want.size() - 1])
	while sim.over == "" and sim.day <= last and not want.is_empty():
		sim.update(dt)
		step += 1
		while not want.is_empty() and int(want[0]) < sim.day:
			want.pop_front()    # (a day that went by before the half hour: the game was started late)
		if not want.is_empty() and sim.day == int(want[0]) and sim.phase == "day" and float(sim.hour) >= WANT_HOUR:
			out[int(want[0])] = SaveGame.to_dict(sim)
			want.pop_front()
		if step % every == 0:
			policy.tick()
	g.world.free()
	return out


## What kind of night the day's night is in avatar mode (the Big Nights are a rule of avatar mode only): "ordinary", "milestone", "final".
static func kind_of_day(sim, day: int) -> String:
	var was: String = sim.player_id
	sim.player_id = "ruth"
	var big: Dictionary = sim.waves.big_night(day)
	sim.player_id = was
	if not big.is_empty():
		return String(big.get("kind", "milestone"))
	return "final" if bool(sim.waves.is_big(day)) else "ordinary"


## A fresh sim at `state` for a night: the rules' dice seeded `seed x 1000 + rep`, the mode switched on, a fresh informed policy that
## has had its mornings. {"g", "sim", "bot" (null for none), "policy", "stats"}. Free `g.world` when done.
static func start(state: Dictionary, seed_value: int, rep: int, mode: String, crew: int) -> Dictionary:
	var g := Helpers.make(seed_value, 1, crew, Balance.campaign)
	var sim = g.sim
	sim.streets.enabled = Balance.streets_on
	sim.storyteller.enabled = Balance.story_on
	if not SaveGame.apply(sim, state):
		push_error("night lab: the state of seed %d does not load" % seed_value)
	sim.rng.seed = seed_value * 1000 + rep
	var bot = null
	if mode != "none":
		# Ruth, or when the game she was in has lost her, the next in line (as the succession would choose)
		if not sim.avatar.set_player("ruth"):
			var next = sim.avatar._next_in_line(null)
			if next != null:
				sim.avatar.set_player(next)
		if not Balance.base_on:
			Helpers.quiet_base(sim)
		bot = BotLib.AvatarBot.new(sim, mode)
	var policy := Balance.policy_for(sim, false, true)
	# (it starts in the evening: the day's morning chores are done, as the game it was taken from did them)
	policy._jobs_day = sim.day
	policy._lots_day = sim.day
	policy._build_day = sim.day
	policy._sent_day = sim.day
	var stats := BotLib.NightStats.new(sim, mode)
	return {"g": g, "sim": sim, "bot": bot, "policy": policy, "stats": stats}


## Plays the night of `day` from `state` in `mode` and returns its row (`NightStats`, with "seed" and "rep" added).
static func night(state: Dictionary, seed_value: int, rep: int, mode: String, day: int, crew: int, hz: float) -> Dictionary:
	var st := start(state, seed_value, rep, mode, crew)
	var sim = st.sim
	var bot = st.bot
	var stats = st.stats
	var policy = st.policy
	var kind := kind_of_day(sim, day) if mode == "none" else ""
	var player := String(sim.player_id)
	var dt := 1.0 / hz
	var every := maxi(1, roundi(hz))
	var step := 0
	while sim.over == "" and sim.day <= day:
		if bot != null:
			bot.step(dt)
		sim.update(dt)
		stats.observe(dt)
		step += 1
		if step % every == 0:
			policy.tick()
	stats.finish()
	var row: Dictionary = stats.rows[stats.rows.size() - 1] if not stats.rows.is_empty() else {"day": day, "kind": "ordinary", "mode": mode, "held": false, "over": true, "missing": true}
	row = row.duplicate(true)
	if kind != "":
		row["kind"] = kind    # (the day's own kind: a `none` night on a Big Night's day is its ordinary night, said to be of the Big one for the table)
		row["ref"] = true
	row["seed"] = seed_value
	row["rep"] = rep
	row["player"] = player
	st.g.world.free()
	return row


# ------------------------------------------------------------------------- a run --

## `states_dir`'s file of a seed's states, or "".
static func _index_path(dir: String, seed_value: int) -> String:
	return dir.path_join("s%d_index.json" % seed_value) if dir != "" else ""


## The states of a seed: from `dir` when it has them for all the days (the same crew and speed), else made (and kept there).
static func states_for(seed_value: int, days: Array, crew: int, hz: float, dir: String) -> Dictionary:
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
		var idx = JSON.parse_string(FileAccess.get_file_as_string(_index_path(dir, seed_value))) if FileAccess.file_exists(_index_path(dir, seed_value)) else null
		if typeof(idx) == TYPE_DICTIONARY and int(idx.get("crew", -1)) == crew and is_equal_approx(float(idx.get("hz", 0.0)), hz) and bool(idx.get("campaign", false)) == Balance.campaign:
			var wanted: Array = idx.get("wanted", [])
			var covered := true
			for d in days:
				if not wanted.has(d) and not wanted.has(float(d)):
					covered = false
			if covered:
				var out := {}
				for d in idx.get("have", []):
					if days.has(int(d)):
						var path := dir.path_join("s%d_d%d.json" % [seed_value, int(d)])
						if FileAccess.file_exists(path):
							out[int(d)] = SaveGame.from_text(FileAccess.get_file_as_string(path))
				return out
	var made := snapshots(seed_value, days, crew, hz)
	if dir != "":
		var have: Array = []
		for d in made:
			have.append(int(d))
			var f := FileAccess.open(dir.path_join("s%d_d%d.json" % [seed_value, int(d)]), FileAccess.WRITE)
			if f != null:
				f.store_string(SaveGame.to_text(made[d]))
				f.close()
		var all_wanted: Array = []
		for d in days:
			all_wanted.append(int(d))
		var fi := FileAccess.open(_index_path(dir, seed_value), FileAccess.WRITE)
		if fi != null:
			fi.store_string(JSON.stringify({"crew": crew, "hz": hz, "campaign": Balance.campaign, "wanted": all_wanted, "have": have}))
			fi.close()
	return made


## Every night of the seeds, days, reps and modes: the rows (seed, day, mode in the lab's order, rep). `on_row`, if valid, is called with each row as it comes.
static func run(seeds: Array, days: Array, reps: int, modes: Array, crew: int, hz: float, states_dir: String, on_row: Callable = Callable()) -> Array:
	var rows: Array = []
	for sd in seeds:
		var states := states_for(int(sd), days, crew, hz, states_dir)
		for d in days:
			if not states.has(int(d)):
				continue
			for rep in reps:
				for m in MODES:
					if not modes.has(m):
						continue
					var r := night(states[int(d)], int(sd), rep, String(m), int(d), crew, hz)
					rows.append(r)
					if on_row.is_valid():
						on_row.call(r)
	return rows


# ---------------------------------------------------------------- table and verdicts --

## One line for a night.
static func night_line(r: Dictionary) -> String:
	var av: Dictionary = r.get("avatar", {})
	return "seed %2d day %2d rep %d %-4s %-9s %-4s | fell %d died %d down %d | lost %5.1f min wall %3.0f%% | present %.2f shots %3d | %s" % [
		int(r.get("seed", 0)), int(r.get("day", 0)), int(r.get("rep", 0)), String(r.get("mode", "")), String(r.get("kind", "")) + ("*" if bool(r.get("ref", false)) else ""),
		"HELD" if bool(r.get("held", false)) else "lost", int(r.get("sections_fell", 0)), int(r.get("died", 0)), int(r.get("downed", 0)),
		float(r.get("hp_lost", 0.0)), 100.0 * float(r.get("min_wall", 1.0)), float(av.get("present", 0.0)), int(av.get("shots", 0)),
		"colony lost" if bool(r.get("over", false)) else ("ready" if bool(r.get("ready", false)) else "not ready")]


## The table of the rows, as text: a line for each group of days and each mode; a cell of fewer than MIN_CELL nights ends with a star.
static func table_text(rows: Array) -> String:
	var lines: Array = [BotLib.table_header()]
	var cells := {}
	for r in rows:
		var key := "%s|%s" % [BotLib.group_of(r), String(r.get("mode", "none"))]
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(r)
	var thin := false
	for group in ["1-9", "11+", "big"]:
		for m in MODES:
			var key := "%s|%s" % [group, m]
			if not cells.has(key):
				continue
			var line: String = BotLib.cell_line(group, String(m), cells[key])
			if (cells[key] as Array).size() < MIN_CELL:
				line += " *"
				thin = true
			lines.append(line)
	if thin:
		lines.append("* fewer than %d nights: not a result, a hint" % MIN_CELL)
	return "\n".join(lines)


## The share of `rows` for which `test` is true (NAN when there are no rows).
static func _share(rows: Array, test: Callable) -> float:
	if rows.is_empty():
		return NAN
	var n := 0
	for r in rows:
		if bool(test.call(r)):
			n += 1
	return float(n) / float(rows.size())


static func _cell(rows: Array, mode: String, group: String) -> Array:
	var out: Array = []
	for r in rows:
		if String(r.get("mode", "")) == mode and BotLib.group_of(r) == group:
			out.append(r)
	return out


## A verdict: "met" when every part that could be measured is met (and one could), "not met" when one is not, else "no data".
static func _verdict(parts: Array) -> Dictionary:
	var measured := 0
	var failed := 0
	var texts: Array = []
	for p in parts:
		if p.get("ok") == null:
			texts.append("%s: no data" % p.name)
			continue
		measured += 1
		if not bool(p.ok):
			failed += 1
		texts.append("%s %s%s" % [p.name, p.value, " (ok)" if bool(p.ok) else " (NOT: %s)" % p.want])
	var verdict := "no data" if measured == 0 else ("not met" if failed > 0 else "met")
	return {"verdict": verdict, "text": "; ".join(texts)}


## A number of a target's verdict: NAN is "nothing to measure it from" (no verdict from it).
static func _part(name: String, value: float, want: String, ok, fmt := "%.2f") -> Dictionary:
	return {"name": name, "value": "-" if is_nan(value) else (fmt % value), "want": want, "ok": null if is_nan(value) else ok}


## An aggregate's share, which is -1 when it has nothing to take a share of: NAN then.
static func _k(v: float) -> float:
	return v if v >= 0.0 else NAN


## The plan's numeric targets, read from the rows (docs/superpowers/plans/2026-10-03-round-19.md, H3.3): {"1": {"verdict", "text"}, ...,
## "2", "3", "4", "6"}. Target 5 (no avatar: the golden numbers) is a test (tests/test_nights_regression.gd), and the full harness's
## "90% reach day 11" is `tools/balance.gd --avatar=idle`'s.
static func targets(rows: Array) -> Dictionary:
	var out := {}
	# 1: ordinary nights 1 to 9, idle
	var idle19 := _cell(rows, "idle", "1-9")
	var a1 := BotLib.aggregate(idle19)
	var down_share := _share(idle19, func(r): return int(r.get("downed", 0)) > 0)
	out["1"] = _verdict([
		_part("held", float(a1.held) if idle19.size() > 0 else NAN, ">= 0.80", float(a1.held) >= 0.80),
		_part("held when ready", _k(float(a1.held_ready)), ">= 0.90", float(a1.held_ready) >= 0.90),
		_part("someone downed", down_share, "<= 0.20", down_share <= 0.20),
		_part("deaths a night", float(a1.died) if idle19.size() > 0 else NAN, "<= 0.03", float(a1.died) <= 0.03, "%.3f"),
	])
	# 2: Big Nights, idle
	var idle_big := _cell(rows, "idle", "big")
	var a2 := BotLib.aggregate(idle_big)
	var live := _share(idle_big, func(r): return not bool(r.get("over", false)))
	out["2"] = _verdict([
		_part("held", float(a2.held) if idle_big.size() > 0 else NAN, "<= 0.35", float(a2.held) <= 0.35),
		_part("a section fell or someone died", 1.0 - float(a2.held) if idle_big.size() > 0 else NAN, ">= 0.70", 1.0 - float(a2.held) >= 0.70),
		_part("colonies that go on", live, ">= 0.95", live >= 0.95),
	])
	# 3: Big Nights, bot
	var bot_big := _cell(rows, "bot", "big")
	var a3 := BotLib.aggregate(bot_big)
	var has3 := bot_big.size() > 0
	var has_presence := false
	for r in bot_big:
		if int(r.get("avatar", {}).get("threat_steps", 0)) > 0:
			has_presence = true
	out["3"] = _verdict([
		_part("held", float(a3.held) if has3 else NAN, ">= 0.80", float(a3.held) >= 0.80),
		_part("sections fallen a night", float(a3.fell) if has3 else NAN, "<= 0.3", float(a3.fell) <= 0.3),
		_part("deaths a night", float(a3.died) if has3 else NAN, "<= 0.3", float(a3.died) <= 0.3),
		_part("presence", float(a3.presence) if has_presence else NAN, ">= 0.60", float(a3.presence) >= 0.60),
		_part("the avatar downed a night", float(a3.av_downed) if has3 else NAN, "<= 0.25", float(a3.av_downed) <= 0.25),
		_part("the avatar dead a night", float(a3.av_died) if has3 else NAN, "<= 0.05", float(a3.av_died) <= 0.05),
	])
	# 4: ordinary nights, bot against idle (a boon, not a necessity)
	var parts4: Array = []
	var idle_all: Array = []
	var bot_all: Array = []
	for g in ["1-9", "11+"]:
		var gi := _cell(rows, "idle", g)
		var gb := _cell(rows, "bot", g)
		idle_all.append_array(gi)
		bot_all.append_array(gb)
		if not gi.is_empty() and not gb.is_empty():
			var hi := float(BotLib.aggregate(gi).held)
			var hb := float(BotLib.aggregate(gb).held)
			parts4.append(_part("bot over idle, nights %s (points)" % g, 100.0 * (hb - hi), ">= -2 (never below idle minus 2)", hb >= hi - 0.02, "%.1f"))
	if not idle_all.is_empty() and not bot_all.is_empty():
		var gain := 100.0 * (float(BotLib.aggregate(bot_all).held) - float(BotLib.aggregate(idle_all).held))
		parts4.append(_part("bot over idle, all ordinary nights (points)", gain, ">= 5", gain >= 5.0, "%.1f"))
	if parts4.is_empty():
		parts4.append(_part("bot over idle", NAN, ">= 5", null))
	out["4"] = _verdict(parts4)
	# 6: the forecast: when the first of the dead came to the target sections, which sections took the hits, the brute's life
	var timed := 0
	var near_enough := 0
	var timed_big := 0
	var near_big := 0
	var big_rows: Array = []
	for r in rows:
		var is_big := BotLib.group_of(r) == "big"
		if is_big:
			big_rows.append(r)
		if float(r.get("first_at", -1.0)) >= 0.0:
			timed += 1
			timed_big += 1 if is_big else 0
			var claw := float(r.get("first_claw_at", -1.0))
			if claw >= 0.0 and absf(claw - float(r.first_at)) <= 1.5:
				near_enough += 1
				near_big += 1 if is_big else 0
	var on_target := 0
	var counted := 0
	for r in big_rows:
		var ts: Array = r.get("targets", [])
		var by: Dictionary = r.get("hp_by_seg", {})
		if ts.is_empty() or by.is_empty():
			continue
		counted += 1
		var order: Array = by.keys()
		order.sort_custom(func(a, b): return float(by[a]) > float(by[b]))
		var top: Array = order.slice(0, 3)
		var hit := false
		for t in ts:
			if top.has(str(int(t))):
				hit = true
		if hit:
			on_target += 1
	var life := {"crew_plated": [], "crew_plain": [], "avatar_plated": []}
	for r in rows:
		for b in r.get("brute_s", []):
			var key := "%s_%s" % [String(b.get("by", "crew")), "plated" if bool(b.get("plated", false)) else "plain"]
			if life.has(key):
				(life[key] as Array).append(float(b.s))
	var ratio := NAN
	if not (life.crew_plated as Array).is_empty() and not (life.crew_plain as Array).is_empty():
		ratio = _mean(life.crew_plated) / maxf(_mean(life.crew_plain), 0.1)
	var bot_s := _mean(life.avatar_plated) if not (life.avatar_plated as Array).is_empty() else NAN
	out["6"] = _verdict([
		_part("first_at within 1.5 h of the first dead at the target walls", float(near_enough) / float(timed) if timed > 0 else NAN, ">= 0.80", float(near_enough) / maxf(float(timed), 1.0) >= 0.80),
		_part("a target wall among the three hardest hit, Big Nights", float(on_target) / float(counted) if counted > 0 else NAN, ">= 0.70", float(on_target) / maxf(float(counted), 1.0) >= 0.70),
		_part("a plated brute lives (x a plain one's) under the crew's fire", ratio, ">= 2.5", ratio >= 2.5, "%.1f"),
		_part("a plated brute lives (s) under the avatar's fire", bot_s, "<= 10", bot_s <= 10.0, "%.1f"),
	])
	if timed_big > 0:
		out["6"]["text"] = "%s; (the first part for the Big Nights alone: %.2f of %d)" % [out["6"].text, float(near_big) / float(timed_big), timed_big]
	return out


static func _mean(list: Array) -> float:
	var t := 0.0
	for v in list:
		t += float(v)
	return t / float(maxi(list.size(), 1))


## The verdicts as lines of text.
static func targets_text(rows: Array) -> String:
	var t := targets(rows)
	var names := {"1": "ordinary nights 1-9, idle", "2": "Big Nights, idle", "3": "Big Nights, bot", "4": "ordinary nights, bot against idle", "6": "the forecast"}
	var lines: Array = []
	for k in ["1", "2", "3", "4", "6"]:
		lines.append("target %s (%s): %s. %s" % [k, names[k], String(t[k].verdict).to_upper(), t[k].text])
	lines.append("target 5 (no avatar: the golden numbers): tests/test_nights_regression.gd")
	return "\n".join(lines)


# ---------------------------------------------------------------------- the script --

var _quiet := false


func _initialize() -> void:
	_run_lab.call_deferred()


func _emit(r: Dictionary) -> void:
	if not _quiet:
		print(night_line(r))


func _run_lab() -> void:
	var opts := {"days": "3,6,9,10,15,20", "seeds": "1..8", "reps": "6", "modes": "none,idle,bot", "crew": "5", "hz": "15", "jobs": "1", "states": "", "data": "", "out": ""}
	var quiet := false
	for arg in OS.get_cmdline_user_args():
		var kv := String(arg).trim_prefix("--").split("=", true, 1)
		if kv[0] == "quiet":
			quiet = true
		elif kv[0] == "campaign":
			Balance.campaign = true
		elif kv[0] == "nostory":
			Balance.story_on = false
		elif kv[0] == "base":
			Balance.base_on = true
		elif opts.has(kv[0]) and kv.size() > 1:
			opts[kv[0]] = kv[1]
	if String(opts.data) != "":
		NightData.data_path = String(opts.data)
		NightData.forget()
	var days := parse_ints(String(opts.days))
	var seeds := parse_ints(String(opts.seeds))
	var modes := parse_modes(String(opts.modes))
	var reps := maxi(1, int(opts.reps))
	var crew := clampi(int(opts.crew), 3, 6)
	var hz := clampf(float(opts.hz), 5.0, 60.0)
	var jobs := clampi(int(opts.jobs), 1, 32)
	var states_dir := String(opts.states)
	if days.is_empty() or seeds.is_empty() or modes.is_empty():
		printerr("night lab: nothing to play (days %s, seeds %s, modes %s)" % [opts.days, opts.seeds, opts.modes])
		quit(2)
		return
	var started := Time.get_ticks_msec()
	if not quiet:
		print("Last Bell night lab: seeds %s, days %s, %d reps, modes %s, crew %d, %d Hz%s" % [opts.seeds, opts.days, reps, ",".join(modes), crew, roundi(hz), (", %d at a time" % jobs) if jobs > 1 and seeds.size() > 1 else ""])
		print("")
	var rows: Array = []
	if jobs > 1 and seeds.size() > 1 and not quiet:
		rows = _in_workers(seeds, jobs, opts, modes)
		for r in rows:
			print(night_line(r))
	else:
		_quiet = quiet
		rows = run(seeds, days, reps, modes, crew, hz, states_dir, Callable(self, "_emit"))
	if quiet:
		var f := FileAccess.open(String(opts.out), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"rows": rows}, "", true, true))
			f.close()
		quit(0)
		return
	print("")
	print(table_text(rows))
	print("")
	print(targets_text(rows))
	print("")
	print("%d nights in %.0f s" % [rows.size(), (Time.get_ticks_msec() - started) / 1000.0])
	if String(opts.out) != "":
		var fo := FileAccess.open(String(opts.out), FileAccess.WRITE)
		if fo == null:
			printerr("Could not write %s" % opts.out)
		else:
			fo.store_string(JSON.stringify({"args": opts, "rows": rows, "table": table_text(rows), "targets": targets(rows)}, "  ", true, true))
			fo.close()
			print("Wrote %s" % opts.out)
	quit(0)


## The seeds shared out among `jobs` worker processes (this same script, --quiet) and the rows gathered in order. A worker that leaves
## nothing has its seeds played here.
func _in_workers(seeds: Array, jobs: int, opts: Dictionary, modes: Array) -> Array:
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var scratch := ProjectSettings.globalize_path("user://")
	var workers: Array = []
	for w in mini(jobs, seeds.size()):
		var mine: Array = []
		var i := w
		while i < seeds.size():
			mine.append(seeds[i])
			i += jobs
		var names: Array = []
		for sd in mine:
			names.append(str(sd))
		var out := scratch.path_join("night_lab_worker_%d_%d.json" % [OS.get_process_id(), w])
		var args := ["--headless", "--path", project, "--script", "res://tools/night_lab.gd", "--", "--quiet", "--seeds=%s" % ",".join(names), "--days=%s" % opts.days,
			"--reps=%s" % opts.reps, "--modes=%s" % ",".join(modes), "--crew=%s" % opts.crew, "--hz=%s" % opts.hz, "--out=%s" % out]
		if String(opts.states) != "":
			args.append("--states=%s" % opts.states)
		if String(opts.data) != "":
			args.append("--data=%s" % opts.data)
		if Balance.campaign:
			args.append("--campaign")
		if Balance.base_on:
			args.append("--base")
		if not Balance.story_on:
			args.append("--nostory")
		workers.append({"pid": OS.create_process(exe, args), "out": out, "seeds": mine})
	while true:
		var running := 0
		for w in workers:
			if w.pid > 0 and OS.is_process_running(w.pid):
				running += 1
		if running == 0:
			break
		OS.delay_msec(300)
	var rows: Array = []
	for w in workers:
		var got := false
		if FileAccess.file_exists(w.out):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(w.out))
			if typeof(parsed) == TYPE_DICTIONARY:
				got = true
				rows.append_array(parsed.get("rows", []))
			DirAccess.remove_absolute(w.out)
		if not got:
			printerr("A worker left nothing for seeds %s; playing them here" % str(w.seeds))
			rows.append_array(run(w.seeds, parse_ints(String(opts.days)), maxi(1, int(opts.reps)), modes, clampi(int(opts.crew), 3, 6), clampf(float(opts.hz), 5.0, 60.0), String(opts.states)))
	rows.sort_custom(_row_before)
	return rows


## The order of the rows: seed, day, rep, then the modes in the lab's order.
static func _row_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.seed) != int(b.seed):
		return int(a.seed) < int(b.seed)
	if int(a.day) != int(b.day):
		return int(a.day) < int(b.day)
	if int(a.rep) != int(b.rep):
		return int(a.rep) < int(b.rep)
	return MODES.find(String(a.mode)) < MODES.find(String(b.mode))
