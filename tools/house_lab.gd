## The One House lab (WP8, docs/superpowers/plans/2026-10-04-one-house-plan.md, section 5): plays the whole demo arc headless with `HouseBot` (tools/house_bot.gd) and prints the
## timeline of each run in game time (house clear, claim, each rescue, the fourth, each slot built, the bell, held or lost), the first attack night's `NightStats` row, the errors the
## game logged, what is missing and the verdicts of the plan's section 5. It is the acceptance test of the build: one command.
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --headless --path . --script res://tools/house_lab.gd -- --seeds=1..4 --hz=15 --mode=bot [--out=path.json]
##
## Flags (all optional):
##   --seeds=1..4        the seeds (a list or a range or both: 1..3,7); a seed is the town's and the run's
##   --mode=bot          bot: plays the first attack night at the wall; idle: the same days, then its hands off from that evening (the community alone); both: bot,idle
##   --hz=15             rules steps a second (the game's own is 30; the bot and the dead do not care at 15)
##   --blocks=6          the town's blocks (6: the whole town, 192 x 192; 2: a mini town of 64 x 64 for a quick look)
##   --days=7            give up at the end of this day (a run that has not held by then is "unfinished")
##   --stage=NAME        start from OneHouse.stage_to: cleared, claimed, rescued2, fourth or night (the bot plays on from there)
##   --budget=N          CPU seconds a run may take at the most (default 0: none); a run over it is cut and says so
##   --set=a.b=1,c=2     numbers put over the run in memory, the files are not touched: one_house.json's (night.first=0.8, attack.cutoff_hour=15, start.stock.scrap=30) and the street's
##                       dead (field.wake_r=12, field.noise_by_gun.shotgun=16, field.noise_cap=6, field.active_cap=60, field.sleep_r=22, field.night_wake=1.7)
##   --jobs=4            play the runs in this many worker processes (each worker is this script, --worker)
##   --human=1.25        the factor of a person's pace over the bot's (reading a card, a menu, a look round): `real_min` is the awake game time over min_per_sec times this, plus 40 s a night
##                       slept in the bed; `bot_min` is the same without the factor
##   --keepgoing         do not end a run when the avatar falls and the game goes on with somebody else (by default that is a lost run)
##   --prep=N            the bot does not bring the FOURTH survivor home until N slots of the perimeter stand (0: it does not wait: the player who does not know that the fourth
##                       brings the dead every night; 3: the player who does)
##   --standin           a stand-in for the medic the lone avatar does not have (for a build in which the player cannot bandage themselves): a bleeding avatar with meds is bandaged
##                       by the lab, which says how often. Off by default: the avatar bandages herself with E ("Bandage yourself", medical.gd) and the bot does.
##   --trace=60          print a line of what the bot is doing every N game minutes (debugging the bot)
##   --out=path.json     write the runs, the verdicts and the notes there: the ONLY file a lab run writes
##   --quiet             only the verdict lines
## A run is about 30 to 90 CPU seconds in the whole town at 15 Hz.
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const HouseLib := preload("res://tools/house_bot.gd")

const ONE_HOUSE := "res://scripts/town/one_house.gd"
## The plan's numbers (section 5).
const CLAIM_BEFORE_HOUR := 12.0
const RESCUES_BY_DAY := 3
const REAL_MIN_FROM := 20.0
const REAL_MIN_TO := 32.0
const HELD_BOT_SHARE := 0.75
const HELD_IDLE_SHARE := 0.25
const RESULT_TAG := "HOUSE_LAB_RESULT "
## The modules the arc needs, by the variable of the sim: what is not there is listed.
const MODULES := ["houses", "field", "clearing", "search", "base", "sleep", "uses", "rescue", "perimeter", "scenario"]


## Counts and keeps what the game logs as errors during a run (warnings are not errors).
class ErrorLog:
	extends Logger
	var count := 0
	var seen: Dictionary = {}
	var list: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		var text := "%s (%s:%d) %s" % [rationale if rationale != "" else code, file.get_file(), line, function]
		if not seen.has(text):
			seen[text] = 0
			if list.size() < 12:
				list.append(text)
		seen[text] = int(seen[text]) + 1


# ------------------------------------------------------------------------ flags --

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


## "a.b=1,c=2" as {"a.b": 1.0, "c": 2.0}.
static func parse_set(text: String) -> Dictionary:
	var out := {}
	for part in text.split(",", false):
		var kv := String(part).split("=", true, 1)
		if kv.size() == 2 and kv[1].is_valid_float():
			out[String(kv[0]).strip_edges()] = kv[1].to_float()
	return out


## Puts `path` ("night.first") = `value` in the scenario's data in memory.
static func _put(d: Dictionary, path: String, value: float) -> void:
	var keys := path.split(".")
	var at := d
	for i in keys.size() - 1:
		if typeof(at.get(keys[i])) != TYPE_DICTIONARY:
			at[keys[i]] = {}
		at = at[keys[i]]
	at[keys[keys.size() - 1]] = value


# ----------------------------------------------------------------------- a run --

## "D2 14:30".
static func clock_text(day: int, hour: float) -> String:
	var h := floori(hour)
	return "D%d %02d:%02d" % [day, h, roundi((hour - float(h)) * 60.0) % 60]


## Plays one seed to its end (held, lost, the day limit or the budget). Returns the run's row (plain data: it goes to JSON):
## {"seed", "mode", "timeline", "missing", "modules", "verdict", "errors", "night" (the first attack night's NightStats row or {}), "stats", "real_min", ...}.
static func play(seed_value: int, o: Dictionary = {}) -> Dictionary:
	var mode := String(o.get("mode", "bot"))
	var hz := clampf(float(o.get("hz", 15.0)), 5.0, 60.0)
	var blocks := int(o.get("blocks", 6))
	var max_day := int(o.get("days", 7))
	var budget_ms := int(float(o.get("budget", 0.0)) * 1000.0)
	var trace_min := float(o.get("trace", 0.0))
	var bandage: bool = bool(o.get("bandage", false))
	var bandaged := 0
	var human := float(o.get("human", 1.25))
	var errors := ErrorLog.new()
	OS.add_logger(errors)
	var t0 := Time.get_ticks_msec()
	var g := Helpers.town_game(seed_value, {"blocks": blocks})
	var sim = g.sim
	var module_state: Dictionary = {}
	for m in MODULES:
		module_state[m] = sim.get(m) != null if m != "scenario" else (sim.scenario != null and sim.scenario.has_method("go_to"))
	# the run as the game starts it: OneHouse.begin when the scenario is there
	var has_scenario: bool = bool(module_state.scenario)
	var stage_note := ""
	if ResourceLoader.exists(ONE_HOUSE):
		var OneHouse = load(ONE_HOUSE)
		if OneHouse != null and OneHouse.has_method("begin"):
			OneHouse.begin(sim, -1, seed_value)
			has_scenario = true
			module_state["scenario"] = true
			var sets: Dictionary = o.get("set", {})
			if not sets.is_empty():
				var data: Dictionary = sim.scenario.d()
				for k in sets:
					_put(data, String(k), float(sets[k]))
				sim.scenario.apply_stage()
				sim.scenario._apply_static()
				if sets.has("start.stock.scrap") or sets.has("start.stock.ammo") or sets.has("start.stock.food") or sets.has("start.stock.water") or sets.has("start.stock.meds"):
					for k in sets:
						if String(k).begins_with("start.stock."):
							sim.stock[String(k).trim_prefix("start.stock.")] = float(sets[k])
			var stage := String(o.get("stage", ""))
			if stage != "":
				stage_note = stage if OneHouse.stage_to(sim, stage) else "%s (refused)" % stage
	# the field's numbers (`--set=field.wake_r=14,field.noise_r=12,field.active_cap=30,field.sleep_r=45,field.night_mult=1.4`): put on the dead of the street directly
	var sets_all: Dictionary = o.get("set", {})
	for k in sets_all:
		if String(k).begins_with("field.noise_by_gun.") and sim.get("field") != null:
			sim.field.noise_by_gun[String(k).trim_prefix("field.noise_by_gun.")] = float(sets_all[k])
		elif String(k).begins_with("field.") and sim.get("field") != null:
			sim.field.set(String(k).trim_prefix("field."), float(sets_all[k]) if not ["field.active_cap", "field.noise_cap"].has(String(k)) else int(sets_all[k]))
	var bot = HouseLib.HouseBot.new(sim, mode)
	bot.prep = int(o.get("prep", 0))
	bot.note_start()
	var stats = BotLib.NightStats.new(sim, mode)
	var dt := 1.0 / hz
	var steps := 0
	var cut := ""
	var next_trace := 0.0
	var start_clock := float(sim.clock_min)
	sim.events.clear()
	while sim.over == "":
		if int(sim.day) > max_day:
			cut = "day limit"
			break
		if budget_ms > 0 and (steps & 255) == 0 and Time.get_ticks_msec() - t0 > budget_ms:
			cut = "budget"
			break
		if bot.avatar_dead and bool(o.get("stop_on_death", true)):
			cut = "avatar died"
			break
		# the first attack night was judged at the dawn and not held (a section down, the dead in the house...): the run is lost to the lab (the game itself goes on to the next night)
		if has_scenario and sim.scenario.has_method("first_night_result") and String(sim.scenario.first_night_result()) == "not_held":
			cut = "not held at dawn"
			break
		bot.step(dt)
		sim.update(dt)
		bot.observe(dt)
		_observe_night(sim, stats, dt)
		sim.events.clear()
		steps += 1
		if bandage and (steps & 7) == 0:
			bandaged += _bandage(sim)
		# the sleep: the colony runs ahead a chunk at a time (the sleep screen's `advance`), watched as it goes
		var sl = sim.get("sleep")
		while sl != null and sl.active() and sim.over == "":
			sl.advance()
			bot.observe(0.0)
			_observe_night(sim, stats, dt)
			sim.events.clear()
			if budget_ms > 0 and Time.get_ticks_msec() - t0 > budget_ms:
				break
		if trace_min > 0.0 and float(sim.clock_min) - start_clock >= next_trace:
			next_trace += trace_min
			var tp = sim.avatar.player()
			print("  [trace] %s task %s hp %d (bleeding %.0f, infected %s) stock a%d s%d f%d meds %d people %d zombies %d%s" % [clock_text(int(sim.day), float(sim.hour)), String(bot.task.get("kind", "-")), roundi(float(tp.hp)), float(tp.bleeding), str(float(tp.infected_at) >= 0.0), roundi(float(sim.stock.ammo)), roundi(float(sim.stock.scrap)), roundi(float(sim.stock.food)), roundi(float(sim.stock.meds)), _alive(sim), sim.zombies.size(), " " + _states(sim) + "\n      " + bot.debug_line()])
	stats.finish()
	var over := String(sim.over)
	var now_clock := float(sim.clock_min)
	var row: Dictionary = {}
	if not stats.rows.is_empty():
		row = (stats.rows[stats.rows.size() - 1] as Dictionary).duplicate(true)
	var out := {
		"seed": seed_value, "mode": mode, "blocks": blocks, "hz": hz, "stage": stage_note,
		"timeline": bot.timeline, "missing": bot.missing.keys(), "modules": module_state,
		"over": over, "cut": cut, "end": {"day": int(sim.day), "hour": snappedf(float(sim.hour), 0.01), "min": snappedf(now_clock - start_clock, 0.1)},
		"night": row, "stats": bot.stats, "slept_min": snappedf(bot.slept_min, 0.1),
		"real_min": snappedf(bot.real_seconds(now_clock, human) / 60.0, 0.1), "bot_min": snappedf(bot.real_seconds(now_clock) / 60.0, 0.1), "human": human, "steps": steps,
		"cpu_s": snappedf(float(Time.get_ticks_msec() - t0) / 1000.0, 0.1),
		"errors": errors.count, "error_list": errors.list,
		"people": _alive(sim), "task": String(bot.task.get("kind", "")), "bandaged": bandaged,
		"why": String(sim.scenario.first_night_why()) if has_scenario and sim.scenario.has_method("first_night_why") else "",
	}
	var shots := 0
	var kills := 0
	for pe in sim.people:
		shots += int(pe.stats.get("shots", 0))
		kills += int(pe.stats.get("kills", 0))
	out["stats"]["shots"] = shots
	out["stats"]["kills"] = kills
	out["verdict"] = verdict_of(out)
	OS.remove_logger(errors)
	g.world.free()
	return out


## The medic the lone avatar does not have: a bleeding avatar is bandaged with one meds (medical.gd's own bandage, `BANDAGE_MEDS`). 1 when it did.
static func _bandage(sim) -> int:
	var me = sim.avatar.player() if String(sim.player_id) != "" else null
	if me == null or me.dead or me.turned or float(me.bleeding) <= 0.0:
		return 0
	var cost := float(sim.medical.BANDAGE_MEDS)
	if float(sim.stock.meds) < cost:
		return 0
	sim.stock.meds = float(sim.stock.meds) - cost
	me.bleeding = 0.0
	me.wounds = 0
	return 1


## The awake dead by state, "approach 12 attack 3 still 8": for the trace.
static func _states(sim) -> String:
	var by := {}
	for z in sim.zombies:
		by[String(z.state)] = int(by.get(String(z.state), 0)) + 1
	var parts: Array = []
	for k in by:
		parts.append("%s %d" % [k, int(by[k])])
	return "[" + " ".join(parts) + "]"


static func _alive(sim) -> int:
	var n := 0
	for p in sim.people:
		if not (p.dead or p.turned):
			n += 1
	return n


## NightStats is for the attack nights only (the nights before the fourth rescue are the sleeper's): fed while the attacks are on, and at the end.
static func _observe_night(sim, stats, dt: float) -> void:
	var sc = sim.scenario
	if sc != null and sc.has_method("attacks_on") and bool(sc.attacks_on()):
		stats.observe(dt)


# --------------------------------------------------------------------- verdicts --

static func _entry(run: Dictionary, what: String, nth: int = 1) -> Dictionary:
	var n := 0
	for e in run.timeline:
		if String(e.what) == what:
			n += 1
			if n == nth:
				return e
	return {}


## The plan's section 5 for one run: {"claim_by_noon", "four_by_day3", "built", "result": "held"|"lost"|"unfinished", "real_min_ok", ...}; null where the arc did not get that far or the module is missing.
static func verdict_of(run: Dictionary) -> Dictionary:
	var v := {}
	var claim := _entry(run, "claim")
	v["claim_by_noon"] = (int(claim.day) == 1 and float(claim.hour) < CLAIM_BEFORE_HOUR) if not claim.is_empty() else null
	var fourth := _entry(run, "rescue", 4)
	v["rescues"] = _count(run, "rescue")
	v["four_by_day3"] = (int(fourth.day) <= RESCUES_BY_DAY) if not fourth.is_empty() else (false if bool(run.modules.get("rescue", false)) and bool(run.modules.get("base", false)) else null)
	v["slots_built"] = _count(run, "slot_built")
	var result := "unfinished"
	if _entry(run, "held").size() > 0 or String(run.over) == "victory":
		result = "held"
	elif String(run.over) == "defeat" or String(run.cut) == "avatar died" or String(run.cut) == "not held at dawn":
		result = "lost"
	v["result"] = result
	var arc_done: bool = result != "unfinished" and String(run.cut) == ""
	v["real_min_ok"] = (float(run.real_min) >= REAL_MIN_FROM and float(run.real_min) <= REAL_MIN_TO) if arc_done else null
	v["errors"] = int(run.errors)
	return v


static func _count(run: Dictionary, what: String) -> int:
	var n := 0
	for e in run.timeline:
		if String(e.what) == what:
			n += 1
	return n


## What the runs say against the plan, over all of them: lines of text and a dictionary of numbers.
static func summarise(runs: Array) -> Dictionary:
	var by_mode := {}
	for r in runs:
		var m := String(r.mode)
		if not by_mode.has(m):
			by_mode[m] = []
		(by_mode[m] as Array).append(r)
	var out := {}
	for m in by_mode:
		var list: Array = by_mode[m]
		var held := 0
		var lost := 0
		var claim_ok := 0
		var claim_known := 0
		var four_ok := 0
		var four_known := 0
		var min_ok := 0
		var min_known := 0
		var errs := 0
		var minutes: Array = []
		for r in list:
			var v: Dictionary = r.verdict
			held += 1 if String(v.result) == "held" else 0
			lost += 1 if String(v.result) == "lost" else 0
			if v.claim_by_noon != null:
				claim_known += 1
				claim_ok += 1 if bool(v.claim_by_noon) else 0
			if v.four_by_day3 != null:
				four_known += 1
				four_ok += 1 if bool(v.four_by_day3) else 0
			if v.real_min_ok != null:
				min_known += 1
				min_ok += 1 if bool(v.real_min_ok) else 0
			errs += int(r.errors)
			minutes.append(float(r.real_min))
		out[m] = {"runs": list.size(), "held": held, "lost": lost, "claim_by_noon": [claim_ok, claim_known], "four_by_day3": [four_ok, four_known], "real_min_ok": [min_ok, min_known], "errors": errs, "real_min": minutes}
	return out


## "n/m" or "n/a".
static func _ratio(pair: Array) -> String:
	return "%d/%d" % [int(pair[0]), int(pair[1])] if int(pair[1]) > 0 else "no data"


static func verdict_lines(runs: Array) -> Array:
	var lines: Array = []
	var sum := summarise(runs)
	for m in sum:
		var s: Dictionary = sum[m]
		var n := int(s.runs)
		lines.append("VERDICT %-4s: %d runs | claim before 12:00 on day 1: %s | four rescues by day %d: %s | first attack held: %d/%d (lost %d) | real minutes 20-32: %s | errors %d" % [
			m, n, _ratio(s.claim_by_noon), RESCUES_BY_DAY, _ratio(s.four_by_day3), int(s.held), n, int(s.lost), _ratio(s.real_min_ok), int(s.errors)])
		var share := float(s.held) / float(maxi(n, 1))
		if m == "bot":
			lines.append("  target: held in at least %d%% of runs with the bot at the wall (6 of 8): %s" % [roundi(HELD_BOT_SHARE * 100.0), "met" if share >= HELD_BOT_SHARE and n > 0 else ("NOT met" if n >= 4 else "no verdict: fewer than 4 runs")])
		elif m == "idle":
			lines.append("  target: held in at least %d%% of runs with an idle avatar (2 of 8): %s" % [roundi(HELD_IDLE_SHARE * 100.0), "met" if share >= HELD_IDLE_SHARE and n > 0 else ("NOT met" if n >= 4 else "no verdict: fewer than 4 runs")])
	return lines


# ---------------------------------------------------------------------- printing --

static func run_lines(r: Dictionary) -> Array:
	var lines: Array = []
	var head := "seed %d, %s" % [int(r.seed), String(r.mode)]
	if String(r.stage) != "":
		head += ", from stage %s" % String(r.stage)
	lines.append(head)
	for e in r.timeline:
		var at := clock_text(int(e.day), float(e.hour))
		var what := String(e.what)
		var detail := ""
		match what:
			"missing":
				detail = "%s: missing: %s" % [String(e.step), String(e.module)]
			"rescue":
				detail = "rescue %d of 4 (%s)" % [int(e.count), String(e.id)]
			"slot_built", "slot_ordered":
				detail = "%s %s %s" % [what.replace("_", " "), String(e.slot), String(e.kit)]
			"gave_up":
				detail = "gave up %s (%s)" % [String(e.task), String(e.why)]
			"rescue_asked":
				detail = "asked %s to come: %s" % [String(e.id), "yes" if bool(e.ok) else "refused"]
			"rescue_refused":
				detail = "%s would not come: %s" % [String(e.id), String(e.why)]
			"claim_refused":
				detail = "claim refused: %s" % String(e.why)
			"nap":
				detail = "nap at %d hp until %.1f" % [roundi(float(e.hp)), float(e.until)]
			"over":
				detail = "over: %s" % String(e.verdict)
			"held":
				detail = "the night is held"
			_:
				detail = what.replace("_", " ")
				if e.has("count"):
					detail += " %s" % str(e.count)
		lines.append("  %s  (+%5.0f min)  %s" % [at, float(e.min), detail])
	lines.append("  ends %s after %.0f game minutes (%s%s), %d people, %d steps, %.0f CPU s" % [clock_text(int(r.end.day), float(r.end.hour)), float(r.end.min), String(r.over) if String(r.over) != "" else (String(r.cut) if String(r.cut) != "" else "no end"), (": " + String(r.get("why", ""))) if String(r.get("why", "")) != "" else "", int(r.people), int(r.steps), float(r.cpu_s)])
	var v: Dictionary = r.verdict
	if int(r.get("bandaged", 0)) > 0:
		lines.append("  NOTE: the lab bandaged the lone avatar %d times (a stand-in for the medic: the avatar's own bandage is E in the game)" % int(r.bandaged))
	lines.append("  real time at a player's pace: %.1f min (%.0f game min slept, in the bed) | rescues %d | slots built %d | bites %d | searches %d | shots %d, kills %d | hp low %d" % [float(r.real_min), float(r.slept_min), int(v.rescues), int(v.slots_built), int(r.stats.bites), int(r.stats.searched), int(r.stats.shots), int(r.stats.kills), roundi(float(r.stats.hp_min))])
	var row: Dictionary = r.night
	if not row.is_empty():
		var av: Dictionary = row.get("avatar", {})
		lines.append("  first attack night: size %d, %s | sections fell %d, died %d, downed %d, bites %d | wall lost %.0f hp, lowest %.0f%% | avatar shots %d kills %d hp low %d | ammo left %.0f" % [
			int(row.get("size", 0)), "HELD" if bool(row.get("held", false)) else "not held (by NightStats: nothing fell, nobody died)", int(row.get("sections_fell", 0)), int(row.get("died", 0)),
			int(row.get("downed", 0)), int(row.get("bites", 0)), float(row.get("hp_lost", 0.0)), 100.0 * float(row.get("min_wall", 1.0)), int(av.get("shots", 0)), int(av.get("kills", 0)), roundi(float(av.get("hp_min", 0.0))), float(row.get("stock_ammo", 0.0))])
	if not (r.missing as Array).is_empty():
		lines.append("  MISSING: " + "; ".join(r.missing))
	if int(r.errors) > 0:
		lines.append("  ERRORS: %d logged" % int(r.errors))
		for e in r.error_list:
			lines.append("    " + String(e))
	return lines


# ------------------------------------------------------------------------- main --

func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var opts := {"seeds": "1..4", "mode": "bot", "hz": "15", "blocks": "6", "days": "7", "stage": "", "budget": "0", "set": "", "prep": "0", "human": "1.25", "jobs": "1", "trace": "0", "out": ""}
	var quiet := false
	var worker := false
	var standin := false
	var keep_going := false
	for arg in OS.get_cmdline_user_args():
		var kv := String(arg).trim_prefix("--").split("=", true, 1)
		if kv[0] == "quiet":
			quiet = true
		elif kv[0] == "worker":
			worker = true
		elif kv[0] == "standin":
			standin = true
		elif kv[0] == "keepgoing":
			keep_going = true
		elif opts.has(kv[0]) and kv.size() > 1:
			opts[kv[0]] = kv[1]
	var seeds := parse_ints(String(opts.seeds))
	var modes: Array = []
	for m in String(opts.mode).split(",", false):
		if ["bot", "idle"].has(String(m)) and not modes.has(String(m)):
			modes.append(String(m))
	if seeds.is_empty() or modes.is_empty():
		printerr("house lab: nothing to play (seeds %s, mode %s)" % [opts.seeds, opts.mode])
		quit(2)
		return
	var play_opts := {"hz": float(opts.hz), "blocks": int(opts.blocks), "days": int(opts.days), "stage": String(opts.stage), "budget": float(opts.budget), "set": parse_set(String(opts.set)), "trace": float(opts.trace), "bandage": standin, "prep": int(opts.prep), "human": float(opts.human), "stop_on_death": not keep_going}
	opts["bandage"] = standin
	opts["keepgoing"] = keep_going
	var jobs := clampi(int(opts.jobs), 1, 16)
	var started := Time.get_ticks_msec()
	if not quiet and not worker:
		print("Thirty Bells One House lab: seeds %s, mode %s, %d Hz, %d-block town, up to day %d%s%s" % [opts.seeds, ",".join(modes), roundi(float(opts.hz)), int(opts.blocks), int(opts.days), (", from stage " + String(opts.stage)) if String(opts.stage) != "" else "", (", %d workers" % jobs) if jobs > 1 else ""])
		print("")
	var runs: Array = []
	if jobs > 1 and not worker and seeds.size() * modes.size() > 1:
		runs = _in_workers(seeds, modes, opts, jobs)
		for r in runs:
			if not quiet:
				print("\n".join(run_lines(r)))
				print("")
	else:
		for sd in seeds:
			for m in modes:
				var o := play_opts.duplicate()
				o["mode"] = m
				var r := play(int(sd), o)
				runs.append(r)
				if worker:
					print(RESULT_TAG + JSON.stringify(r))
				elif not quiet:
					print("\n".join(run_lines(r)))
					print("")
	if worker:
		quit(0)
		return
	var lines := verdict_lines(runs)
	print("\n".join(lines))
	var all_missing := {}
	for r in runs:
		for k in r.missing:
			all_missing[String(k)] = true
	if not all_missing.is_empty():
		print("MISSING (steps skipped): " + "; ".join(all_missing.keys()))
	var total_errors := 0
	for r in runs:
		total_errors += int(r.errors)
	print("%d runs in %.0f s, %d errors logged" % [runs.size(), float(Time.get_ticks_msec() - started) / 1000.0, total_errors])
	if String(opts.out) != "":
		var f := FileAccess.open(String(opts.out), FileAccess.WRITE)
		if f == null:
			printerr("Could not write %s" % opts.out)
		else:
			f.store_string(JSON.stringify({"args": opts, "runs": runs, "summary": summarise(runs), "verdicts": lines}, "  ", true, true))
			f.close()
			print("Wrote %s" % opts.out)
	quit(0)


## The runs shared among `jobs` worker processes (this script with --worker, results on stdout) and gathered in order. Nothing is written to disk.
func _in_workers(seeds: Array, modes: Array, opts: Dictionary, jobs: int) -> Array:
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var pairs: Array = []
	for sd in seeds:
		for m in modes:
			pairs.append([int(sd), String(m)])
	var procs: Array = []
	for w in mini(jobs, pairs.size()):
		var seed_list: Array = []
		var mode_of: Array = []
		var i := w
		var mine: Array = []
		while i < pairs.size():
			mine.append(pairs[i])
			i += jobs
		# a worker plays one (seed, mode) pair at a time: its own process for each pair it is given, one after the other
		procs.append({"pairs": mine, "pid": 0, "stdio": null, "done": false, "k": 0})
	var rows: Array = []
	var args_of := func(pair: Array) -> Array:
		var a := ["--headless", "--path", project, "--script", "res://tools/house_lab.gd", "--", "--worker", "--seeds=%d" % int(pair[0]), "--mode=%s" % String(pair[1])]
		for k in ["hz", "blocks", "days", "stage", "budget", "set", "trace", "prep", "human"]:
			if String(opts[k]) != "" and String(opts[k]) != "0":
				a.append("--%s=%s" % [k, String(opts[k])])
		if bool(opts.get("bandage", false)):
			a.append("--standin")
		if bool(opts.get("keepgoing", false)):
			a.append("--keepgoing")
		return a
	var running := 0
	while true:
		running = 0
		for p in procs:
			if p.done:
				continue
			if int(p.pid) == 0:
				if int(p.k) >= (p.pairs as Array).size():
					p.done = true
					continue
				var info: Dictionary = OS.execute_with_pipe(exe, args_of.call(p.pairs[p.k]))
				p.pid = int(info.get("pid", 0))
				p.stdio = info.get("stdio")
				if int(p.pid) == 0:
					p.k = int(p.k) + 1
					continue
			running += 1
			var f: FileAccess = p.stdio
			if f != null:
				while f.get_position() < f.get_length() or true:
					var line := f.get_line()
					if line == "":
						break
					if line.begins_with(RESULT_TAG):
						var parsed = JSON.parse_string(line.trim_prefix(RESULT_TAG))
						if typeof(parsed) == TYPE_DICTIONARY:
							rows.append(parsed)
			if not OS.is_process_running(int(p.pid)):
				p.pid = 0
				p.stdio = null
				p.k = int(p.k) + 1
		if running == 0:
			break
		OS.delay_msec(200)
	if rows.size() < pairs.size():
		printerr("house lab: %d of %d runs left no result (a worker died); play them one by one with --jobs=1 to see why" % [pairs.size() - rows.size(), pairs.size()])
	rows.sort_custom(func(a, b): return int(a.seed) < int(b.seed) or (int(a.seed) == int(b.seed) and String(a.mode) < String(b.mode)))
	return rows
