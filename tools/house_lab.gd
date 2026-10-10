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
##   --days=7            give up at the end of this day (a run that has not held by then is "unfinished"). With --nights=N and no --days: the larger of 7 and N + 4 (N = 7: day 11)
##   --nights=N          (PH5, docs/plan-7-day-demo.md step 1) the run is won at the dawn that makes N attack nights HELD (`end.nights_to_hold`; 0, the default, is the data's, 1: the first attack night, as it always was).
##                       A night not held does not count and the run goes on (the first-night cut "not held at dawn" is only for N = 1; an avatar that falls still ends the run unless --keepgoing). With N above 1 each
##                       run prints one line for each attack night (the size of the attack by kind, the wall, the crew at dawn, the ammo, the stores at dusk and at dawn, the real minutes, why a night was not held) and the lab
##                       ends with the SUMMARY TABLES: the nights over the runs of each mode, the total real minutes of a run (median, p10, p90) and where the days and nights go (walk, work, build, fight, wait). The
##                       rows are in the --out file too (`night_rows`, `split`, `rescue`)
##   --stage=NAME        start from OneHouse.stage_to: cleared, claimed, rescued2, fourth or night (the bot plays on from there)
##   --budget=N          CPU seconds a run may take at the most (default 0: none); a run over it is cut and says so
##   --set=a.b=1,c=2     numbers put over the run in memory, the files are not touched: one_house.json's (night.first=0.8, attack.cutoff_hour=15, start.stock.scrap=30) and the street's
##                       dead (field.wake_r=12, field.noise_by_gun.shotgun=16, field.noise_cap=6, field.active_cap=60, field.sleep_r=22, field.night_wake=1.7)
##   --jobs=4            play the runs in this many worker processes (each worker is this script, --worker)
##   --human=1.25        the factor of a person's pace over the bot's (reading a card, a menu, a look round): `real_min` is the awake game time over min_per_sec times this, plus 40 s a night
##                       slept in the bed; `bot_min` is the same without the factor
##   --candidate=best    which house the bot walks to from the entry and makes its base: best, ok, poor (the tier the town's candidates give it) or nearest (the nearest to the entry); the
##                       run begins at the entry as the game does (the arrival: scripts/town/arrival.gd), so a run is the walk in, the clear, the claim, the rescues and the night
##   --keepgoing         do not end a run when the avatar falls and the game goes on with somebody else (by default that is a lost run)
##   --orders=projects   how the bot orders the base: projects (the Build page's NEXT project, `perimeter.order_project`) or slots (a section at a time, `perimeter.order`)
##   --prep=N            the bot does not bring the LAST survivor the data asks for (the second, `attack.from_rescue`) home until N slots of the perimeter stand (0: it does not wait: the player who does not
##                       know that the second brings the dead every night; 3: the player who does)
##   --standin           a stand-in for the medic the lone avatar does not have (for a build in which the player cannot bandage themselves): a bleeding avatar with meds is bandaged
##                       by the lab, which says how often. Off by default: the avatar bandages herself with E ("Bandage yourself", medical.gd) and the bot does.
##   --tables=path.json  (PH5) plays nothing: prints the verdicts and the tables of a file a run wrote with --out (the summary table, the nights, the total real minutes, the day split)
##   --daywork           (PH5) the bot does not sit at home on the days of the attacks: it goes on bringing survivors home (the rescue spots and the beds allow) and searches the houses within 45 tiles of the base, the
##                       ones with dead in them too, home by 16:30. Off by default: the bot of the first attack night, and the numbers of the first night, are as they were
##   --scavengers=N      from the claim on, N of the crew are on the Scavenger job (scripts/town/crew_search.gd `stage_job`: the ones with no job first, then the radio desk, the lookout, the infirmary, the
##                       bench and the builders last): they search the cleared houses by day and the loot goes to the stores. The bot never asks the crew to search. 0 (the default): none, as it was
##   --scavhouses=K      with --scavengers: at the claim the K houses nearest the base (within 35 tiles) are cleared for nothing, as if the player had cleared the street: the scavengers' work. 0: only the houses the bot
##                       clears itself (the start house, which it has searched already, and the rescue houses)
##   --weather-first-night=storm   (RAIN) that weather through the first attack night only, dusk to dawn: storm, steady (rain), drizzle or clear (scripts/town/skies.gd `force_first_night`). Without
##                       it the town's own weather plays (about one day in two has a rain period): the lab shows what rain does to the night's balance
##   --trace=60          print a line of what the bot is doing every N game minutes (debugging the bot)
##   --out=path.json     write the runs, the verdicts and the notes there: the ONLY file a lab run writes
##   --quiet             only the verdict lines
## A run is about 30 to 90 CPU seconds in the whole town at 15 Hz.
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const HouseLib := preload("res://tools/house_bot.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")

const ONE_HOUSE := "res://scripts/town/one_house.gd"
## The plan's numbers (section 5).
## (BIGGER HOUSES: the start house is a family home of eight rooms with a dozen containers, and the bot searches every one of them before it claims: 14:00, it was 12:00)
## (EARLY, the start was too slow: the claim before 13:00 (was 14:00), TWO rescues by day 2 (was four by day 3), the first build ordered within two real minutes of the claim, and the whole loop 12 to 28 real minutes:
## only the early part is shortened, the owner does not want the rest to be)
const CLAIM_BEFORE_HOUR := 13.0
const RESCUES_BY_DAY := 2
const BUILD_WITHIN_MIN := 2.0
const REAL_MIN_FROM := 12.0
const REAL_MIN_TO := 28.0
## (EARLY, the first night is three people's: the bot at the wall holds at least 14 of 16 (7 of 8), an idle avatar at most 5 of 16 and ideally at least 2)
const HELD_BOT_SHARE := 0.875
const HELD_IDLE_MAX := 0.3125
const HELD_IDLE_MIN := 0.125
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


## PH5 (the seven-night measure, docs/plan-7-day-demo.md step 1): one row for each ATTACK night, kept as the lab plays. It only reads the sim (no draw, no write). A night runs from the first step of its day that is
## not "day" (the dusk) to the dawn the scenario judges (`night_log()`, one entry for each dawn); a night the run ends in is closed as it stands by `finish`. A row: {"night" (1 to N), "day", "dead": {walker, runner,
## brute} (the plan's counts), "size", "dusk" and "dawn": the stores {ammo, food, water, scrap, meds}, "wall_dusk" and "wall_dawn": {pct (hp over max hp of the base's sections), up, of}, "crew_dusk" and "crew_dawn":
## {alive, hurt (under 70 health, bleeding or infected), downed}, "ammo_min" (the lowest the stock was in the night), "hp_low" (the lowest health of whoever the player was), "real_min" (the night at a player's pace),
## "held" (the data's held_rule at the dawn), "rule" (which rule failed: avatar, house, base, wall; "crew" or "cut" when the run ended in the night)}; `join` adds NightStats' columns (sections fell, wall hp lost, died...).
class NightLog:
	extends RefCounted

	var sim
	var bot
	var human := 1.25
	var rows: Array = []
	var _cur: Dictionary = {}
	var _closed_day := -1
	var _seen := 0
	var _ammo_min := 0.0
	var _hp_min := 100.0
	var _slept0 := 0.0

	func _init(s, b, human_factor: float) -> void:
		sim = s
		bot = b
		human = human_factor

	func _stores() -> Dictionary:
		var out := {}
		for k in ["ammo", "food", "water", "scrap", "meds"]:
			out[k] = roundi(float(sim.stock.get(k, 0.0)))
		return out

	## The base's sections (the fence, the gate, the barred doors): their health over their full health, how many stand, how many there are.
	func _wall() -> Dictionary:
		var hp := 0.0
		var full := 0.0
		var up := 0
		var n := 0
		for s in HouseLib.base_sections(sim):
			n += 1
			hp += maxf(float(s.hp), 0.0)
			full += maxf(float(s.max_hp), 0.0)
			if int(s.state) != 3:
				up += 1
		return {"pct": snappedf(100.0 * hp / maxf(full, 1.0), 0.1), "up": up, "of": n}

	func _crew() -> Dictionary:
		var alive := 0
		var hurt := 0
		var downed := 0
		for p in sim.people:
			if p.dead or p.turned:
				continue
			alive += 1
			if p.downed:
				downed += 1
			elif float(p.hp) < 70.0 or float(p.bleeding) > 0.0 or float(p.infected_at) >= 0.0:
				hurt += 1
		return {"alive": alive, "hurt": hurt, "downed": downed}

	## Once per rules step (and per chunk of a sleep), while the attacks are on.
	func observe() -> void:
		var sc = sim.scenario
		if sc == null or not sc.has_method("judged_count"):
			return
		if _cur.is_empty():
			if String(sim.phase) != "day" and _closed_day != int(sim.day):
				_begin()
			return
		_ammo_min = minf(_ammo_min, float(sim.stock.ammo))
		var me = sim.avatar.player()
		if me != null:
			_hp_min = minf(_hp_min, float(me.hp))
		if int(sc.judged_count()) > _seen:
			_seen = int(sc.judged_count())
			var log: Array = sc.night_log()
			_close(log[log.size() - 1])

	func _begin() -> void:
		var day := int(sim.day)
		var plan: Dictionary = sim.waves.plan_for(day)
		var counts: Dictionary = plan.get("counts", {})
		_ammo_min = float(sim.stock.ammo)
		var me = sim.avatar.player()
		_hp_min = float(me.hp) if me != null else 100.0
		_slept0 = float(bot.slept_min)
		_cur = {
			"night": rows.size() + 1, "day": day, "dead": {"walker": int(counts.get("walker", 0)), "runner": int(counts.get("runner", 0)), "brute": int(counts.get("brute", 0))},
			"size": (plan.get("queue", []) as Array).size(), "dusk": _stores(), "wall_dusk": _wall(), "crew_dusk": _crew(), "clock0": float(sim.clock_min),
		}

	func _fill(held: bool, rule: String) -> void:
		var awake := maxf(float(sim.clock_min) - float(_cur.clock0) - (float(bot.slept_min) - _slept0), 0.0)
		_cur["held"] = held
		_cur["rule"] = rule
		_cur["dawn"] = _stores()
		_cur["wall_dawn"] = _wall()
		_cur["crew_dawn"] = _crew()
		_cur["ammo_min"] = roundi(_ammo_min)
		_cur["hp_low"] = roundi(_hp_min)
		_cur["real_min"] = snappedf(awake / maxf(float(sim.min_per_sec), 0.1) * human / 60.0, 0.01)
		_cur.erase("clock0")
		rows.append(_cur)
		_closed_day = int(_cur.day)
		_cur = {}

	func _close(judged: Dictionary) -> void:
		_fill(bool(judged.get("held", false)), String(judged.get("why", "")))

	## The run ended (or was cut): a night still open is closed as it stands.
	func finish(cut: String) -> void:
		if _cur.is_empty():
			return
		var rule := "cut"
		if cut == "avatar died":
			rule = "avatar"
		elif String(sim.over) == "defeat":
			rule = "crew"
		_fill(false, rule)
		(rows[rows.size() - 1] as Dictionary)["unfinished"] = true

	## NightStats' columns of the same night (by day): what fell, the wall's hp, who died or went down, the plated ones.
	func join(stats_rows: Array) -> void:
		for r in rows:
			for sr in stats_rows:
				if int(sr.get("day", -1)) != int(r.day):
					continue
				r["fell"] = int(sr.get("sections_fell", 0))
				r["wall_lost"] = roundi(float(sr.get("hp_lost", 0.0)))
				r["died"] = int(sr.get("died", 0))
				r["downed"] = int(sr.get("downed", 0))
				r["bites"] = int(sr.get("bites", 0))
				r["plated"] = int(sr.get("plated", 0))
				var av: Dictionary = sr.get("avatar", {})
				r["av_shots"] = int(av.get("shots", 0))
				r["av_kills"] = int(av.get("kills", 0))
				r["av_hp_min"] = roundi(float(av.get("hp_min", 100.0)))
				r["av_died"] = int(av.get("died", 0))
			r["reason"] = reason_of(r)

	## Why a night was not held, in the words of the report (empty when it was): the first that is true of avatar died; fence not mended (a section was already down at the dusk, nothing fell in the night, and it was
	## still down at the dawn: the last night's breach, nobody mended it); ammo out (the stock touched 0 in the night); crew died (somebody died in it); fence fell (a section fell in the night and was down at the dawn);
	## dead in the house.
	static func reason_of(r: Dictionary) -> String:
		if bool(r.get("held", false)):
			return ""
		var rule := String(r.get("rule", ""))
		if rule == "avatar" or int(r.get("av_died", 0)) > 0:
			return "avatar died"
		if rule == "cut":
			return "unfinished"
		var down_at_dusk: bool = int(r.get("wall_dusk", {}).get("up", 0)) < int(r.get("wall_dusk", {}).get("of", 0))
		if (rule == "wall" or rule == "base") and down_at_dusk and int(r.get("fell", 0)) == 0:
			return "fence not mended"
		if int(r.get("ammo_min", 1)) <= 0:
			return "ammo out"
		if rule == "crew" or int(r.get("died", 0)) > 0:
			return "crew died"
		if rule == "wall" or rule == "base":
			return "fence fell"
		if rule == "house":
			return "dead in the house"
		return rule


## PH5: where a run's real time goes. Each step's game minutes go to one cell of (day number, the day's light "d" or the night "n" (dusk to dawn: the night of day D ends at 06:30 of D+1), what the avatar was at): fight (the
## trigger held), walk (it moved), build (the task is a build), work (searching, claiming, a rescue, a bandage, a clear), wait (everything else: at home, hands off, a nap). The nights slept are the flat 40 real
## seconds of `real_seconds`, counted in `sleeps`. `export` gives real minutes at a player's pace.
class TimeSplit:
	extends RefCounted

	var sim
	var bot
	var human := 1.25
	var cells: Dictionary = {}
	var sleeps: Dictionary = {}
	var _last_clock := -1.0
	var _last_pos := Vector2.INF

	func _init(s, b, human_factor: float) -> void:
		sim = s
		bot = b
		human = human_factor

	## Once per rules step, after the update.
	func step() -> void:
		var clock := float(sim.clock_min)
		var me = sim.avatar.player() if String(sim.player_id) != "" else null
		var pos := Vector2(me.x, me.y) if me != null else Vector2.INF
		var from := _last_pos
		var dm := clock - _last_clock
		_last_clock = clock
		_last_pos = pos
		if dm <= 0.0 or dm > 5.0 or me == null or from == Vector2.INF:
			return
		var cat := "wait"
		var kind := String(bot.task.get("kind", ""))
		if bool(me.input_fire):
			cat = "fight"
		elif pos.distance_to(from) > 0.01 and pos.distance_to(from) < 1.5:
			cat = "walk"
		elif kind == "build":
			cat = "build"
		elif ["search", "claim", "heal", "reveal", "clear", "rescue"].has(kind):
			cat = "work"
		var key := "%d|%s|%s" % [int(sim.day), "d" if String(sim.phase) == "day" else "n", cat]
		cells[key] = float(cells.get(key, 0.0)) + dm

	## After a sleep: the clock jumped (not played), and one night was slept (`day` is the day it began on).
	func slept(day: int) -> void:
		sleeps[day] = int(sleeps.get(day, 0)) + 1
		_last_clock = float(sim.clock_min)
		var me = sim.avatar.player() if String(sim.player_id) != "" else null
		_last_pos = Vector2(me.x, me.y) if me != null else Vector2.INF

	## {"<day>": {"d": {cat: real minutes}, "n": {...}, "sleeps": n}}.
	func export() -> Dictionary:
		var out := {}
		var per := 1.0 / maxf(float(sim.min_per_sec), 0.1) * human / 60.0
		for key in cells:
			var parts := String(key).split("|")
			if not out.has(parts[0]):
				out[parts[0]] = {"d": {}, "n": {}, "sleeps": 0}
			(out[parts[0]][parts[1]] as Dictionary)[parts[2]] = snappedf(float(cells[key]) * per, 0.001)
		for day in sleeps:
			if not out.has(str(day)):
				out[str(day)] = {"d": {}, "n": {}, "sleeps": 0}
			out[str(day)]["sleeps"] = int(sleeps[day])
		return out


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
	var scav_houses := int(o.get("scavhouses", 0))
	var scav_cleared := false
	var scavengers := int(o.get("scavengers", 0))    # (CREW: this many of the crew are put on the Scavenger job from the claim on, `crew_search.stage_job`; the bot itself never asks the crew to search)
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
			# (PH5: the run is won at the dawn that makes N attack nights held; 0, the default, is the data's `end.nights_to_hold`, 1)
			if int(o.get("nights", 0)) > 0:
				sim.scenario.set_nights_to_hold(int(o.get("nights", 0)))
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
	# (RAIN) the first attack night's weather held (a storm, a steady rain, a drizzle, or none) whatever the town's own schedule says
	if String(o.get("weather_first_night", "")) != "" and sim.get("skies") != null:
		sim.skies.force_first_night(String(o.weather_first_night))
	var bot = HouseLib.HouseBot.new(sim, mode)
	bot.prep = int(o.get("prep", 0))
	bot.human = human
	bot.orders = String(o.get("orders", "projects"))
	bot.candidate = String(o.get("candidate", "best"))
	bot.daywork = bool(o.get("daywork", false))
	bot.note_start()
	var stats = BotLib.NightStats.new(sim, mode)
	var nlog := NightLog.new(sim, bot, human)
	var split := TimeSplit.new(sim, bot, human)
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
		# (PH5: with N nights to hold a night not held does not end the run: it does not count, and the next night comes)
		if has_scenario and sim.scenario.has_method("first_night_result") and String(sim.scenario.first_night_result()) == "not_held" and int(sim.scenario.nights_to_hold()) <= 1:
			cut = "not held at dawn"
			break
		bot.step(dt)
		if scavengers > 0 and (steps & 15) == 0 and sim.get("crew_search") != null and sim.base.claimed:
			if scav_houses > 0 and not scav_cleared:
				scav_cleared = true
				sim.crew_search.stage_cleared(scav_houses)    # (a player who has cleared the houses round the base: their dead are put down for nothing)
			sim.crew_search.stage_job(scavengers)
		sim.update(dt)
		bot.observe(dt)
		_observe_night(sim, stats, dt, nlog)
		split.step()
		sim.events.clear()
		steps += 1
		if bandage and (steps & 7) == 0:
			bandaged += _bandage(sim)
		# the sleep: the colony runs ahead a chunk at a time (the sleep screen's `advance`), watched as it goes
		var sl = sim.get("sleep")
		var slept_from := int(sim.day)
		var was_asleep: bool = sl != null and sl.active()
		while sl != null and sl.active() and sim.over == "":
			sl.advance()
			bot.observe(0.0)
			_observe_night(sim, stats, dt, nlog)
			sim.events.clear()
			if budget_ms > 0 and Time.get_ticks_msec() - t0 > budget_ms:
				break
		if was_asleep:
			split.slept(slept_from)
		if trace_min > 0.0 and float(sim.clock_min) - start_clock >= next_trace:
			next_trace += trace_min
			var tp = sim.avatar.player()
			print("  [trace] %s task %s hp %d (bleeding %.0f, infected %s) stock a%d s%d f%d meds %d people %d zombies %d%s" % [clock_text(int(sim.day), float(sim.hour)), String(bot.task.get("kind", "-")), roundi(float(tp.hp)), float(tp.bleeding), str(float(tp.infected_at) >= 0.0), roundi(float(sim.stock.ammo)), roundi(float(sim.stock.scrap)), roundi(float(sim.stock.food)), roundi(float(sim.stock.meds)), _alive(sim), sim.zombies.size(), " " + _states(sim) + "\n      " + bot.debug_line()])
	stats.finish()
	nlog.finish(cut)
	nlog.join(stats.rows)
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
		"scavengers": scavengers,
		"nights_to_hold": int(sim.scenario.nights_to_hold()) if has_scenario and sim.scenario.has_method("nights_to_hold") else 1,
		"held_nights": int(sim.scenario.report().nights) if has_scenario and sim.scenario.has_method("report") else 0,
		"night_rows": nlog.rows, "split": split.export(), "rescue": _rescue_note(sim), "crew_end": nlog._crew(),
	}
	if scavengers > 0 and sim.get("crew_search") != null:
		out["crew"] = (sim.crew_search.stats as Dictionary).duplicate(true)
	var shots := 0
	var kills := 0
	for pe in sim.people:
		shots += int(pe.stats.get("shots", 0))
		kills += int(pe.stats.get("kills", 0))
	out["stats"]["shots"] = shots
	out["stats"]["kills"] = kills
	# (INV-CORE: the pack's line: what she carried at the bell of the first attack night, the trips to the stash, the times the pack was full, what was left behind)
	var pinv = sim.get("inv")
	if pinv != null and pinv.on:
		var ps: Dictionary = pinv.stats
		out["pack"] = {"deposits": int(ps.deposits), "deposited": (ps.deposited as Dictionary).duplicate(), "full": int(ps.full), "dropped": int(ps.dropped), "left": int(pinv.left_behind()),
				"dusk": bot.pack_dusk, "peak_cells": int(ps.peak_cells), "picked": (ps.picked as Dictionary).duplicate(), "cells": Inventory.used_cells(pinv.pack),
				"ate": int(ps.get("ate", 0)), "drank": int(ps.get("drank", 0)), "went": pinv.went.duplicate(), "hunger_h": float(sim.avatar.player().hunger_h) if sim.avatar.player() != null else 0.0, "thirst_h": float(sim.avatar.player().thirst_h) if sim.avatar.player() != null else 0.0}
	out["verdict"] = verdict_of(out)
	OS.remove_logger(errors)
	g.world.free()
	return out


## The rescue spots of the town and how many joined: {"spots", "joined", "states": {state: n}, "beds_free"}.
static func _rescue_note(sim) -> Dictionary:
	var rs = sim.get("rescue")
	if rs == null:
		return {}
	var states := {}
	var list: Array = rs.list()
	for r in list:
		states[String(r.get("state", ""))] = int(states.get(String(r.get("state", "")), 0)) + 1
	var beds := -1
	if sim.get("recruits") != null and sim.recruits.has_method("housing_free"):
		beds = int(sim.recruits.housing_free())
	return {"spots": list.size(), "joined": int(rs.joined_count()), "states": states, "beds_free": beds}


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
static func _observe_night(sim, stats, dt: float, nlog = null) -> void:
	var sc = sim.scenario
	if sc != null and sc.has_method("attacks_on") and bool(sc.attacks_on()):
		stats.observe(dt)
		if nlog != null:
			nlog.observe()


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
	var fourth := _entry(run, "rescue", 2)    # (the second voice: the attacks begin with it. The key keeps its old name: `four_by_day3` is now "two rescues by day 2")
	v["rescues"] = _count(run, "rescue")
	v["four_by_day3"] = (int(fourth.day) <= RESCUES_BY_DAY) if not fourth.is_empty() else (false if bool(run.modules.get("rescue", false)) and bool(run.modules.get("base", false)) else null)
	v["slots_built"] = _count(run, "slot_built")
	# EARLY: the first build ordered within BUILD_WITHIN_MIN real minutes of the claim, and how long to the first fence (the front project's last section) after it
	var ordered := _entry(run, "slot_ordered")
	v["build_ordered_ok"] = (float(ordered.real) - float(claim.real) <= BUILD_WITHIN_MIN) if not claim.is_empty() and not ordered.is_empty() else (false if not claim.is_empty() else null)
	var fence := {}
	for e in run.timeline:
		if String(e.what) == "project_done" and String(e.get("project", "")) == "front":
			fence = e
			break
	v["fence_min"] = (float(fence.real) - float(claim.real)) if not claim.is_empty() and not fence.is_empty() else null
	var result := "unfinished"
	if _entry(run, "held").size() > 0 or String(run.over) == "victory":
		result = "held"
	elif String(run.over) == "defeat" or String(run.cut) == "avatar died" or String(run.cut) == "not held at dawn":
		result = "lost"
	v["result"] = result
	var arc_done: bool = result != "unfinished" and String(run.cut) == ""
	# (PH5: the 12 to 28 real minutes are the first attack night's loop; a run of several nights has no such limit yet)
	v["real_min_ok"] = (float(run.real_min) >= REAL_MIN_FROM and float(run.real_min) <= REAL_MIN_TO) if arc_done and int(run.get("nights_to_hold", 1)) <= 1 else null
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
		var build_ok := 0
		var build_known := 0
		var errs := 0
		var minutes: Array = []
		var marks := {"claim": [], "first_build": [], "first_fence": [], "two_rescues": [], "first_attack": [], "held": []}
		for r in list:
			var v: Dictionary = r.verdict
			if v.get("build_ordered_ok") != null:
				build_known += 1
				build_ok += 1 if bool(v.build_ordered_ok) else 0
			for pair in [["claim", _entry(r, "claim")], ["first_build", _entry(r, "slot_ordered")], ["two_rescues", _entry(r, "rescue", 2)], ["first_attack", _entry(r, "bell")], ["held", _entry(r, "held")]]:
				if not (pair[1] as Dictionary).is_empty() and (pair[1] as Dictionary).has("real"):
					(marks[pair[0]] as Array).append(float(pair[1].real))
			for e in r.timeline:
				if String(e.what) == "project_done" and String(e.get("project", "")) == "front" and e.has("real"):
					(marks["first_fence"] as Array).append(float(e.real))
					break
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
		out[m] = {"runs": list.size(), "held": held, "lost": lost, "claim_by_noon": [claim_ok, claim_known], "four_by_day3": [four_ok, four_known], "build_ordered": [build_ok, build_known], "real_min_ok": [min_ok, min_known], "errors": errs, "real_min": minutes,
			"marks": marks}
	return out


## "n/m" or "n/a".
static func _ratio(pair: Array) -> String:
	return "%d/%d" % [int(pair[0]), int(pair[1])] if int(pair[1]) > 0 else "no data"


static func verdict_lines(runs: Array) -> Array:
	var lines: Array = []
	var sum := summarise(runs)
	var hold := 1
	for r in runs:
		hold = maxi(hold, int(r.get("nights_to_hold", 1)))
	for m in sum:
		var s: Dictionary = sum[m]
		var n := int(s.runs)
		if hold > 1:
			# (PH5: a run of several nights: "held" is the run won at the dawn that makes N nights held; the first attack night's targets (88 percent, 31 percent, 12 to 28 minutes) are not this)
			lines.append("VERDICT %-4s: %d runs | claim before %02d:00 on day 1: %s | two rescues by day %d: %s | run WON (%d attack nights held): %d/%d (lost %d, unfinished %d) | errors %d" % [
				m, n, int(CLAIM_BEFORE_HOUR), _ratio(s.claim_by_noon), RESCUES_BY_DAY, _ratio(s.four_by_day3), hold, int(s.held), n, int(s.lost), n - int(s.held) - int(s.lost), int(s.errors)])
			continue
		lines.append("VERDICT %-4s: %d runs | claim before %02d:00 on day 1: %s | two rescues by day %d: %s | first build ordered within %d real minutes of the claim: %s | first attack held: %d/%d (lost %d) | real minutes %d-%d: %s | errors %d" % [
			m, n, int(CLAIM_BEFORE_HOUR), _ratio(s.claim_by_noon), RESCUES_BY_DAY, _ratio(s.four_by_day3), int(BUILD_WITHIN_MIN), _ratio(s.build_ordered), int(s.held), n, int(s.lost), int(REAL_MIN_FROM), int(REAL_MIN_TO), _ratio(s.real_min_ok), int(s.errors)])
		var med := []
		for k in ["claim", "first_build", "first_fence", "two_rescues", "first_attack", "held"]:
			var arr: Array = (s.marks[k] as Array).duplicate()
			arr.sort()
			med.append("%s %s" % [k.replace("_", " "), ("%.1f" % float(arr[arr.size() / 2])) if not arr.is_empty() else "-"])
		lines.append("  MILESTONES, median real minutes at a player's pace (the lab's --human): %s" % ", ".join(med))
		var share := float(s.held) / float(maxi(n, 1))
		if m == "bot":
			lines.append("  target: held in at least %d%% of runs with the bot at the wall (14 of 16): %s" % [roundi(HELD_BOT_SHARE * 100.0), "met" if share >= HELD_BOT_SHARE and n > 0 else ("NOT met" if n >= 4 else "no verdict: fewer than 4 runs")])
		elif m == "idle":
			var idle_word := "no verdict: fewer than 4 runs"
			if n >= 4:
				idle_word = "met" if share <= HELD_IDLE_MAX + 1.0e-6 and share >= HELD_IDLE_MIN - 1.0e-6 else ("NOT met: too many hold" if share > HELD_IDLE_MAX else "NOT met: none or almost none hold")
			lines.append("  target: an idle avatar holds in at most %d%% of runs (5 of 16) and ideally at least %d%% (2 of 16): %s" % [roundi(HELD_IDLE_MAX * 100.0), roundi(HELD_IDLE_MIN * 100.0), idle_word])
	return lines


# ------------------------------------------------------- the nights, one line each --

static func _sorted(a: Array) -> Array:
	var b: Array = a.duplicate()
	b.sort()
	return b


## The median of numbers (the mean of the middle two when even); NAN when there are none.
static func _med(a: Array) -> float:
	if a.is_empty():
		return NAN
	var b := _sorted(a)
	var n := b.size()
	return float(b[n / 2]) if n % 2 == 1 else (float(b[n / 2 - 1]) + float(b[n / 2])) / 2.0


## The p-th percentile (0 to 1) by linear steps between the sorted numbers; NAN when there are none.
static func _pctile(a: Array, p: float) -> float:
	if a.is_empty():
		return NAN
	var b := _sorted(a)
	var at := clampf(p, 0.0, 1.0) * float(b.size() - 1)
	var lo := int(floor(at))
	var hi := mini(lo + 1, b.size() - 1)
	return float(b[lo]) + (float(b[hi]) - float(b[lo])) * (at - float(lo))


static func _num(x: float, digits: int = 0) -> String:
	if is_nan(x):
		return "-"
	return ("%." + str(digits) + "f") % x


## One line for each attack night of a run (PH5): the number, held or not (and why), the size of the attack by kind, the wall, the crew at dawn, the avatar's lowest health, the ammo before and after, the stores at dusk and
## at dawn, and the real minutes the night took at the lab's player pace.
static func night_lines(r: Dictionary) -> Array:
	var lines: Array = []
	for n in r.get("night_rows", []):
		var d: Dictionary = n.dead
		var dusk: Dictionary = n.dusk
		var dawn: Dictionary = n.dawn
		var cd: Dictionary = n.crew_dawn
		var status := "HELD" if bool(n.held) else "NOT HELD (%s; the rule: %s; ammo low %d)" % [String(n.get("reason", "?")), String(n.get("rule", "?")), int(n.get("ammo_min", 0))]
		if bool(n.get("unfinished", false)):
			status += ", the run ended in it"
		lines.append("  night %d (D%d): %s | dead %d (%d walker, %d runner, %d brute) | wall lost %d hp, %d fell, %d%% -> %d%% | crew at dawn %d alive, %d hurt, %d downed, %d died | avatar hp low %d | ammo %d -> %d | dusk food %d water %d scrap %d meds %d | dawn food %d water %d scrap %d meds %d | %.1f real min" % [
			int(n.night), int(n.day), status, int(n.size), int(d.walker), int(d.runner), int(d.brute), int(n.get("wall_lost", 0)), int(n.get("fell", 0)), roundi(float(n.wall_dusk.pct)), roundi(float(n.wall_dawn.pct)),
			int(cd.alive), int(cd.hurt), int(cd.downed), int(n.get("died", 0)), int(n.get("hp_low", 0)), int(dusk.ammo), int(dawn.ammo), int(dusk.food), int(dusk.water), int(dusk.scrap), int(dusk.meds),
			int(dawn.food), int(dawn.water), int(dawn.scrap), int(dawn.meds), float(n.real_min)])
	var rs: Dictionary = r.get("rescue", {})
	if not rs.is_empty():
		lines.append("  rescue spots in this town: %d, joined %d (%s), beds free at the end %d | crew at the end %d" % [int(rs.spots), int(rs.joined), ", ".join((rs.states as Dictionary).keys().map(func(k): return "%s %d" % [k, int(rs.states[k])])), int(rs.get("beds_free", -1)), int((r.get("crew_end", {}) as Dictionary).get("alive", 0))])
	return lines


## The table of the nights over the runs of each mode (PH5): night by night how many runs got there, how many held it, the size of the attack, what was in the stores at dusk, who was alive at dawn, how long it took at
## the lab's pace and what the nights that were not held failed on.
static func night_table(runs: Array) -> Array:
	var lines: Array = []
	for m in ["bot", "idle"]:
		var list: Array = []
		for r in runs:
			if String(r.mode) == m and r.has("night_rows"):
				list.append(r)
		if list.is_empty():
			continue
		var most := 0
		var won := 0
		for r in list:
			most = maxi(most, (r.night_rows as Array).size())
			won += 1 if String(r.over) == "victory" else 0
		lines.append("NIGHTS, %s: %d runs, run won %d (%d%%). Per attack night; the stores are the MEDIAN at dusk (the lowest in brackets); crew alive is at dawn; a run that ended in a night counts it as not held" % [m, list.size(), won, roundi(100.0 * float(won) / float(list.size()))])
		lines.append("  night | there | held | held% | streak% | dead med (w/r/b) | ammo | food | water | scrap | meds | crew alive | wall lost hp | real min | not held because")
		for k in range(1, most + 1):
			var there := 0
			var held := 0
			var streak := 0
			var size: Array = []
			var kinds := [[], [], []]
			var res := {"ammo": [], "food": [], "water": [], "scrap": [], "meds": []}
			var crew: Array = []
			var lost: Array = []
			var mins: Array = []
			var why := {}
			for r in list:
				var rows: Array = r.night_rows
				var all_held := rows.size() >= k
				for i in mini(k, rows.size()):
					if not bool(rows[i].held):
						all_held = false
				streak += 1 if all_held else 0
				if rows.size() < k:
					continue
				var row: Dictionary = rows[k - 1]
				if String(row.get("rule", "")) == "cut":
					continue    # (the day limit or the budget ended the run inside it: it was not judged)
				there += 1
				held += 1 if bool(row.held) else 0
				size.append(int(row.size))
				kinds[0].append(int(row.dead.walker))
				kinds[1].append(int(row.dead.runner))
				kinds[2].append(int(row.dead.brute))
				for key in res:
					(res[key] as Array).append(int(row.dusk[key]))
				crew.append(int(row.crew_dawn.alive))
				lost.append(int(row.get("wall_lost", 0)))
				mins.append(float(row.real_min))
				if not bool(row.held):
					why[String(row.get("reason", "?"))] = int(why.get(String(row.get("reason", "?")), 0)) + 1
			var top := ""
			var top_n := 0
			var all_why: Array = []
			for w in why:
				all_why.append("%s %d" % [w, int(why[w])])
				if int(why[w]) > top_n:
					top_n = int(why[w])
					top = String(w)
			var cells: Array = []
			for key in ["ammo", "food", "water", "scrap", "meds"]:
				var arr: Array = res[key]
				cells.append("%s (%s)" % [_num(_med(arr)), _num(float(_sorted(arr)[0])) if not arr.is_empty() else "-"])
			lines.append("  %5d | %5d | %4d | %4s | %7s | %s (%s/%s/%s) | %s | %s | %s | %s | %s" % [
				k, there, held, _num(100.0 * float(held) / float(maxi(there, 1))) if there > 0 else "-", _num(100.0 * float(streak) / float(list.size())), _num(_med(size)), _num(_med(kinds[0])), _num(_med(kinds[1])), _num(_med(kinds[2])),
				" | ".join(cells), _num(_med(crew), 1), _num(_med(lost)), _num(_med(mins), 1), (top + " (" + ", ".join(all_why) + ")") if top != "" else "-"])
		lines.append("")
	return lines


## The numbers of attack night `k` over some runs: {"there" (runs that were judged in it), "held", "size": [], "res": {ammo, food, water, scrap, meds at dusk: []}, "crew": [] (alive at dawn), "mins": [], "why": {reason: n}}.
static func _night_cell(list: Array, k: int) -> Dictionary:
	var out := {"there": 0, "held": 0, "size": [], "res": {"ammo": [], "food": [], "water": [], "scrap": [], "meds": []}, "crew": [], "mins": [], "why": {}}
	for r in list:
		var rows: Array = r.night_rows
		if rows.size() < k:
			continue
		var row: Dictionary = rows[k - 1]
		if String(row.get("rule", "")) == "cut":
			continue    # (the day limit or the budget ended the run inside it: it was not judged)
		out["there"] = int(out.there) + 1
		out["held"] = int(out.held) + (1 if bool(row.held) else 0)
		(out.size as Array).append(int(row.size))
		for key in out.res:
			(out.res[key] as Array).append(int(row.dusk[key]))
		(out.crew as Array).append(int(row.crew_dawn.alive))
		(out.mins as Array).append(float(row.real_min))
		if not bool(row.held):
			var why := String(row.get("reason", "?"))
			out.why[why] = int(out.why.get(why, 0)) + 1
	return out


## "ammo out 14 of 20" (the most common reason a night was not held, of the nights that were not), "-" when all were.
static func _top_reason(why: Dictionary) -> String:
	var top := ""
	var top_n := 0
	var total := 0
	for w in why:
		total += int(why[w])
		if int(why[w]) > top_n:
			top_n = int(why[w])
			top = String(w)
	return "%s %d of %d" % [top, top_n, total] if top != "" else "-"


## THE SUMMARY TABLE (PH5), one row for each attack night: the share of the runs that held it, for the bot and for the idle avatar (of the runs that got to it), then over the bot's runs the median size of the attack,
## the stores at dusk, the crew alive at dawn and the real minutes the night took at the lab's pace, and the most common reason a night was not held, bot and idle.
static func summary_table(runs: Array) -> Array:
	var by := {"bot": [], "idle": []}
	var most := 0
	var won := {"bot": 0, "idle": 0}
	for r in runs:
		if by.has(String(r.mode)) and r.has("night_rows"):
			(by[String(r.mode)] as Array).append(r)
			most = maxi(most, (r.night_rows as Array).size())
			won[String(r.mode)] = int(won[String(r.mode)]) + (1 if String(r.over) == "victory" else 0)
	if most == 0:
		return []
	var lines: Array = []
	lines.append("SUMMARY TABLE by attack night. Runs: bot %d (won %d), idle %d (won %d). held = of the runs that got to the night (a run that ended inside one counts it as not held). The middle columns are the BOT's runs: the median size of the attack, the stores at dusk, the crew alive at dawn, the real minutes the night took at the lab's pace" % [(by.bot as Array).size(), int(won.bot), (by.idle as Array).size(), int(won.idle)])
	lines.append("  night | bot there | bot held% | idle there | idle held% | dead | ammo | food | water | scrap | meds | crew | real min | failure, bot | failure, idle")
	for k in range(1, most + 1):
		var b := _night_cell(by.bot, k)
		var i := _night_cell(by.idle, k)
		lines.append("  %5d | %9d | %9s | %10d | %10s | %4s | %4s | %4s | %5s | %5s | %4s | %4s | %8s | %s | %s" % [
			k, int(b.there), _num(100.0 * float(b.held) / float(maxi(int(b.there), 1))) if int(b.there) > 0 else "-", int(i.there), _num(100.0 * float(i.held) / float(maxi(int(i.there), 1))) if int(i.there) > 0 else "-",
			_num(_med(b.size)), _num(_med(b.res.ammo)), _num(_med(b.res.food)), _num(_med(b.res.water)), _num(_med(b.res.scrap)), _num(_med(b.res.meds)), _num(_med(b.crew), 1), _num(_med(b.mins), 1),
			_top_reason(b.why), _top_reason(i.why)])
	lines.append("")
	return lines


## The tables of runs of several nights (PH5): the summary table, the nights of each mode, the total real minutes and where the time goes. [] when no run had more than one night to hold.
static func table_lines(runs: Array) -> Array:
	var hold := 1
	for r in runs:
		hold = maxi(hold, int(r.get("nights_to_hold", 1)))
	if hold <= 1:
		return []
	var tables: Array = ["", "SUMMARY TABLES (PH5, %d attack nights to hold)" % hold, ""]
	tables.append_array(summary_table(runs))
	tables.append_array(night_table(runs))
	tables.append_array(total_lines(runs))
	tables.append("")
	tables.append_array(split_table(runs))
	return tables


## Real minutes of a whole run at the lab's pace (PH5): the median, the 10th and the 90th percentile, over all the runs of a mode and over the ones that were won.
static func total_lines(runs: Array) -> Array:
	var lines: Array = []
	for m in ["bot", "idle"]:
		var all: Array = []
		var won: Array = []
		for r in runs:
			if String(r.mode) != m:
				continue
			all.append(float(r.real_min))
			if String(r.over) == "victory":
				won.append(float(r.real_min))
		if all.is_empty():
			continue
		lines.append("TOTAL REAL MINUTES, %s: all %d runs: median %s, p10 %s, p90 %s | the %d runs won: median %s, p10 %s, p90 %s" % [
			m, all.size(), _num(_med(all), 1), _num(_pctile(all, 0.1), 1), _num(_pctile(all, 0.9), 1), won.size(), _num(_med(won), 1), _num(_pctile(won, 0.1), 1), _num(_pctile(won, 0.9), 1)])
	return lines


## The bucket a run ended in, "<day>|d" or "<day>|n" (the night of day D runs to 06:30 of D+1): its minutes are partial.
static func _end_bucket(r: Dictionary) -> String:
	var day := int(r.end.day)
	var hour := float(r.end.hour)
	if hour >= 19.0:
		return "%d|n" % day
	if hour < 6.5:
		return "%d|n" % (day - 1)
	return "%d|d" % day


## Where a day and a night go (PH5): for each day number, the real minutes of its daylight (06:30 to 19:00) and of its night (19:00 to 06:30), and the mean of each kind of time in them. walk: the avatar moved; work:
## searching, claiming, a rescue, a bandage; build: standing at a section; fight: the trigger held; wait: hands off, at home, a nap. The bucket a run ended in is left out (it is partial).
static func split_table(runs: Array) -> Array:
	var lines: Array = []
	var cats := ["walk", "work", "build", "fight", "wait"]
	for m in ["bot", "idle"]:
		var list: Array = []
		for r in runs:
			if String(r.mode) == m and r.has("split"):
				list.append(r)
		if list.is_empty():
			continue
		var last_day := 0
		for r in list:
			for key in (r.split as Dictionary).keys():
				last_day = maxi(last_day, int(key))
		lines.append("DAY SPLIT, %s: real minutes at the lab's player pace (median of the runs that played the whole bucket; the kinds are means). Buckets: the day is 06:30 to 19:00, the night 19:00 to 06:30" % m)
		for day in range(1, last_day + 1):
			for ph in ["d", "n"]:
				var totals: Array = []
				var sums := {}
				var slept := 0
				for r in list:
					if _end_bucket(r) == "%d|%s" % [day, ph]:
						continue
					var sp: Dictionary = (r.split as Dictionary).get(str(day), {})
					if sp.is_empty():
						continue
					var cell: Dictionary = sp.get(ph, {})
					var total := 0.0
					for c in cell:
						total += float(cell[c])
					if total <= 0.0:
						continue
					totals.append(total)
					for c in cell:
						sums[c] = float(sums.get(c, 0.0)) + float(cell[c])
					if ph == "n":
						slept += 1 if int(sp.get("sleeps", 0)) > 0 else 0
				if totals.is_empty():
					continue
				var parts: Array = []
				for c in cats:
					parts.append("%s %.1f" % [c, float(sums.get(c, 0.0)) / float(totals.size())])
				lines.append("  D%d %-5s | runs %2d | total %4.1f | %s%s" % [day, "day" if ph == "d" else "night", totals.size(), _med(totals), " ".join(parts), (" | %d slept the night (40 s each)" % slept) if slept > 0 else ""])
		lines.append("")
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
				detail = "rescue %d of 2 (%s)" % [int(e.count), String(e.id)]
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
			"chose":
				detail = "walks in to house %d: %s (%s, %.0f tiles)" % [int(e.house), String(e.label), String(e.tier), float(e.dist)]
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
	if r.has("crew"):
		var cw: Dictionary = r.crew
		var loot_parts: Array = []
		for k in ["food", "water", "ammo", "scrap", "meds"]:
			if int(cw.loot.get(k, 0)) > 0:
				loot_parts.append("%d %s" % [int(cw.loot[k]), k])
		var ended_parts: Array = []
		for k in cw.ended:
			ended_parts.append("%s %d" % [String(k), int(cw.ended[k])])
		lines.append("  scavengers %d: %d containers in %d houses, found %s | bitten %d | runs ended: %s" % [int(r.scavengers), int(cw.containers), int(cw.houses), ", ".join(loot_parts) if not loot_parts.is_empty() else "nothing", int(cw.bitten), ", ".join(ended_parts) if not ended_parts.is_empty() else "none"])
		# (SCAV3: the cars the scavengers searched and stripped, and what they gave)
		var car_parts: Array = []
		for k in ["food", "water", "ammo", "scrap", "meds"]:
			if int((cw.get("car_loot", {}) as Dictionary).get(k, 0)) > 0:
				car_parts.append("%d %s" % [int(cw.car_loot[k]), k])
		lines.append("    cars: %d searched, %d stripped, gave %s" % [int(cw.get("cars", 0)), int(cw.get("car_strips", 0)), ", ".join(car_parts) if not car_parts.is_empty() else "nothing"])
	if r.has("pack"):
		var pk: Dictionary = r.pack
		var du: Dictionary = pk.get("dusk", {})
		var dusk_text := "no attack bell"
		if not du.is_empty():
			var cu: Dictionary = du.get("units", {})
			dusk_text = "%d cells, %d ammo %d food %d water %d meds" % [int(du.get("cells", 0)), int(cu.get("ammo", 0)), int(cu.get("food", 0)), int(cu.get("water", 0)), int(cu.get("meds", 0))]
		var picked_parts: Array = []
		for k in ["food", "water", "ammo", "meds"]:
			picked_parts.append("%d %s" % [int((pk.get("picked", {}) as Dictionary).get(k, 0)), k])
		lines.append("  pack: at the first attack bell %s | trips to the stash %d | pack full %d times (%d items dropped) | peak %d of 32 cells | left behind %d units | took %s" % [dusk_text, int(pk.deposits), int(pk.full), int(pk.dropped), int(pk.get("peak_cells", 0)), int(pk.left), ", ".join(picked_parts)])
		var wnt: Dictionary = pk.get("went", {})
		lines.append("  needs: ate %d, drank %d from the pack | went hungry %s, thirsty %s in the run (no morning card here to ask) | at the end %.0f hours since a meal, %.0f since a drink" % [int(pk.get("ate", 0)), int(pk.get("drank", 0)), "yes" if bool(wnt.get("hungry", false)) else "no", "yes" if bool(wnt.get("thirsty", false)) else "no", float(pk.get("hunger_h", 0.0)), float(pk.get("thirst_h", 0.0))])
	if int(r.get("bandaged", 0)) > 0:
		lines.append("  NOTE: the lab bandaged the lone avatar %d times (a stand-in for the medic: the avatar's own bandage is E in the game)" % int(r.bandaged))
	lines.append("  real time at a player's pace: %.1f min (%.0f game min slept, in the bed) | rescues %d | slots built %d | first fence %s real min after the claim | bites %d | searches %d | shots %d, kills %d | hp low %d" % [float(r.real_min), float(r.slept_min), int(v.rescues), int(v.slots_built), ("%.1f" % float(v.fence_min)) if v.get("fence_min") != null else "-", int(r.stats.bites), int(r.stats.searched), int(r.stats.shots), int(r.stats.kills), roundi(float(r.stats.hp_min))])
	var row: Dictionary = r.night
	if int(r.get("nights_to_hold", 1)) > 1:
		# (PH5: a run of several nights: one line for each attack night; the "first attack night" line below is the last night's NightStats row, so it is left out)
		lines.append("  nights held %d of %d to hold" % [int(r.get("held_nights", 0)), int(r.nights_to_hold)])
		lines.append_array(night_lines(r))
		row = {}
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
	var opts := {"seeds": "1..4", "mode": "bot", "hz": "15", "blocks": "6", "days": "7", "stage": "", "budget": "0", "set": "", "prep": "0", "orders": "projects", "human": "1.25", "jobs": "1", "trace": "0", "out": "", "candidate": "best", "scavengers": "0", "scavhouses": "0", "weather-first-night": "", "nights": "0", "tables": ""}
	var quiet := false
	var worker := false
	var standin := false
	var keep_going := false
	var days_given := false
	var daywork := false
	for arg in OS.get_cmdline_user_args():
		var kv := String(arg).trim_prefix("--").split("=", true, 1)
		if kv[0] == "days":
			days_given = true
		if kv[0] == "daywork":
			daywork = true
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
	# (PH5: --tables=path.json prints the verdicts and the tables of a saved --out file and plays nothing)
	if String(opts.tables) != "":
		var saved = JSON.parse_string(FileAccess.get_file_as_string(String(opts.tables)))
		if typeof(saved) != TYPE_DICTIONARY or not (saved as Dictionary).has("runs"):
			printerr("house lab: %s is not a lab file" % opts.tables)
			quit(2)
			return
		var saved_runs: Array = saved.runs
		print("\n".join(verdict_lines(saved_runs)))
		print("\n".join(table_lines(saved_runs)))
		quit(0)
		return
	# (PH5: --nights=N plays to the dawn that makes N attack nights held; the day limit then leaves room for N nights and a few that were not held, unless --days says)
	if int(opts.nights) > 0 and not days_given:
		opts["days"] = str(maxi(int(opts.days), int(opts.nights) + 4))
	var seeds := parse_ints(String(opts.seeds))
	var modes: Array = []
	for m in String(opts.mode).split(",", false):
		if ["bot", "idle"].has(String(m)) and not modes.has(String(m)):
			modes.append(String(m))
	if seeds.is_empty() or modes.is_empty():
		printerr("house lab: nothing to play (seeds %s, mode %s)" % [opts.seeds, opts.mode])
		quit(2)
		return
	var play_opts := {"hz": float(opts.hz), "blocks": int(opts.blocks), "days": int(opts.days), "stage": String(opts.stage), "budget": float(opts.budget), "set": parse_set(String(opts.set)), "trace": float(opts.trace), "bandage": standin, "prep": int(opts.prep), "orders": String(opts.orders), "human": float(opts.human), "stop_on_death": not keep_going, "candidate": String(opts.candidate), "scavengers": int(opts.scavengers), "scavhouses": int(opts.scavhouses), "weather_first_night": String(opts["weather-first-night"]), "nights": int(opts.nights), "daywork": daywork}
	opts["daywork"] = daywork
	opts["bandage"] = standin
	opts["keepgoing"] = keep_going
	var jobs := clampi(int(opts.jobs), 1, 16)
	var started := Time.get_ticks_msec()
	if not quiet and not worker:
		print("Last Bell One House lab: seeds %s, mode %s, %d Hz, %d-block town, up to day %d%s%s" % [opts.seeds, ",".join(modes), roundi(float(opts.hz)), int(opts.blocks), int(opts.days), (", from stage " + String(opts.stage)) if String(opts.stage) != "" else "", (", %d workers" % jobs) if jobs > 1 else ""])
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
	# (PH5: runs of several nights: the table of the nights, the total real minutes and where the time goes)
	var tables := table_lines(runs)
	if not tables.is_empty():
		print("\n".join(tables))
		lines.append_array(tables)
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
		for k in ["hz", "blocks", "days", "stage", "budget", "set", "trace", "prep", "orders", "human", "candidate", "scavengers", "scavhouses", "weather-first-night", "nights"]:
			if String(opts[k]) != "" and String(opts[k]) != "0":
				a.append("--%s=%s" % [k, String(opts[k])])
		if bool(opts.get("bandage", false)):
			a.append("--standin")
		if bool(opts.get("keepgoing", false)):
			a.append("--keepgoing")
		if bool(opts.get("daywork", false)):
			a.append("--daywork")
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
