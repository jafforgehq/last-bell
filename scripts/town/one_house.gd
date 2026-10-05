## The One House run (WP6, plan 1.8 to 1.11 of docs/superpowers/plans/2026-10-04-one-house-plan.md): ONE survivor in ONE house of a big town. This is `sim.scenario` of
## a town game (scripts/town/town_sim.gd makes it by name), the rules' side of the whole game flow; the numbers and the words are the data,
## `assets/data/one_house.json` (over which `one_house_tuning.json`, the lab's, is merged key by key). It works on its own, with no screen.
##
## THE STAGES. `alone` (the start) -> `cleared` (the start house has no dead left) -> `claimed` (the house is the base) -> `growing` (the first survivors have come) ->
## `fortify` (the FOURTH one has: the dead come every night from the first dusk) -> `held` (the first attack night is over and the base stands: the run is won,
## `sim.over = "victory"`, the end card). Stages only go forward. Other packages tell this module what happened (`on_house_clear`, `on_claimed`, `on_survivor_joined`).
##
## THE SOLO START. `begin` makes the run: Ruth alone (the player), the data's stores, 08:00 of day 1, `min_per_sec` 2.0, `recruits.small` with no caller on the radio, the
## school's town board, lots, streets, storyteller, gate and levels off, the waves off until the fourth rescue, and the community modules (`briefing`, `priorities`, `initiative`,
## `relations`...) switched on by how many people there are (`apply_stage`, from the data's `modules_from_crew`, again at every change of the crew).
##
## THE GUIDE. Seven lessons, none blocking (walk; aim and shoot; open a door and go in; clear the house; search; claim; and, once someone is on the radio, ask them for something:
## click a person or a card, pick a verb on the wheel; `on_asked`, which main.gd calls). Each is DONE when its condition is true, read from the
## state of the rules (not from the event stream: a scenario's `update` runs before the step's events exist, and the screen clears them every frame). `guide()` is the first
## one not done (the one just done is shown as done for three seconds), `{}` when there is none (the first six are the first day's, until the first survivor has come; the lesson
## marked `crew` has that stage). `objective()` is the line under the clock, with a bearing target.
##
## THE END. The first attack night is the night of `first_day` (the day of the fourth rescue, or the next one when it comes after the cutoff hour). From the dawn after it
## the night is HELD as soon as the data's `held_rule` is true (whoever leads is alive, no dead are in the house, a section of the base still stands): `sim.over = "victory"`.
## When nobody is left the run is lost, as ever. Saved with the run (`kind: one_house`, which `is_save` reads so that a load installs it before the save is read).
##
## NOT DEFINED, on purpose: `is_demo()` (the school demo's views key off it) and `after_step()` (Orientation Day's marker).
##
## Events added: {"type": "attacks_on", "from_day": d}, {"type": "held", "night": n}, {"type": "over", "result": "victory" | "defeat"} and their banners.
extends "res://scripts/sim/scenario.gd"

const GD := preload("res://scripts/game_data.gd")
const Demo := preload("res://scripts/demo.gd")
const NightData := preload("res://scripts/sim/night_data.gd")

const KIND := "one_house"
const DATA_PATH := "res://assets/data/one_house.json"
const TUNING_PATH := "res://assets/data/one_house_tuning.json"
const STAGES := ["alone", "cleared", "claimed", "growing", "fortify", "held"]
## The stages `go_to` (staging for screenshots, the lab and the tests) knows.
const STAGE_NAMES := ["alone", "cleared", "claimed", "rescued2", "fourth", "night"]
## Seconds of rules time between looks at the lessons and the clock of the run.
const TICK := 0.25
## How long the lesson just done is shown as done.
const FLASH_S := 3.0
## A move of more than this many tiles in one step is a jump (a placing), not a walk.
const JUMP_TILES := 1.5
const NEVER := 99999
## The sections of the base are the ids below this (the lots' walls of the school are above: `Lots.FIRST_SEGMENT_ID`).
const SEGMENT_LIMIT := 100

## What the run is when the files say nothing (or cannot be read): only the numbers, the words come with the file.
const FALLBACK := {
	"min_per_sec": 2.0,
	"difficulty": 1,
	"total_days": 5,
	"ideas_from_day": 2,
	"start": {"hour": 8.0, "stock": {"ammo": 40, "scrap": 10, "food": 12, "water": 18, "meds": 2}},
	"modules_from_crew": {"briefing": 3, "priorities": 3, "initiative": 3, "relations": 4, "policies": 99, "problems": 99, "dilemmas": 99, "specialists": 99},
	"attack": {"from_rescue": 4, "cutoff_hour": 17.0},
	"night": {"first": 1.0, "growth": 0.15},
	"big_night": {},
	"held_rule": {"avatar_alive": true, "house_empty": true, "base_standing": true},
	"guide": [],
	"objective": {},
	"words": {},
	"end": {},
}

var _d := {}
## Whether this is the One House run (a `begin`, an `install` or a load): until then this module does nothing by itself, so that a town game that is only a test bed is as it was.
var _begun := false
var _stage := "alone"
## How many survivors the rescue module says have joined, and how many `go_to` made up for a screenshot.
var _module_joined := 0
var _staged_joins := 0
var _attacks := false
var _first_day := -1
var _cleared := {}
var _done := {}
var _walked := 0.0
## How many times the player has picked a verb on the command wheel (the lesson of asking the crew).
var _asked := 0
var _last_pos := Vector2.INF
var _held_nights := 0
## The day whose dawn has been judged (-1: none), and how the first attack night ended ("", "held" or "not_held").
var _dawn_day := -1
var _first_result := ""
var _first_why := ""
var _crew_seen := -1
var _dirty := true
var _t := 0.0
var _flash_id := ""
var _flash_until := -1.0
var _town_seed := 0
var _size := [0, 0]


func setup(s) -> void:
	sim = s


## A new run (`start_run` calls it): everything of this module is as at the start. It is not the One House run until `begin` says so.
func start() -> void:
	_d = {}
	_begun = false
	_stage = "alone"
	_module_joined = 0
	_staged_joins = 0
	_attacks = false
	_first_day = -1
	_cleared = {}
	_done = {}
	_walked = 0.0
	_asked = 0
	_last_pos = Vector2.INF
	_held_nights = 0
	_dawn_day = -1
	_first_result = ""
	_first_why = ""
	_crew_seen = -1
	_dirty = true
	_t = 0.0
	_flash_id = ""
	_flash_until = -1.0


# ------------------------------------------------------------------- the data --

## The run's data: the file over the fallbacks, the lab's tuning file over that (a copy: the caller may do what it likes with it).
static func data() -> Dictionary:
	var out: Dictionary = FALLBACK.duplicate(true)
	for path in [DATA_PATH, TUNING_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var json := JSON.new()
		# (the instance's `parse` says nothing about a damaged file: the fallbacks stand in, quietly)
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
			out = _merge(out, json.data)
	return out


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over:
		if String(k).begins_with("_"):
			continue
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = _merge(out[k], over[k])
		else:
			out[k] = over[k].duplicate(true) if (over[k] is Dictionary or over[k] is Array) else over[k]
	return out


static func _dig(from: Dictionary, path: String, fallback = null):
	var cur = from
	for key in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(key):
			cur = cur[key]
		else:
			return fallback
	return cur


## A line of the run's words by its dotted path in the file ("words.tagline"), `fallback` when there is none (the title asks for its tagline this way).
static func text(path: String, fallback: String = "") -> String:
	var v = _dig(data(), path, fallback)
	return String(v) if typeof(v) == TYPE_STRING else fallback


func d() -> Dictionary:
	if _d.is_empty():
		_d = data()
	return _d


func _cfg(path: String, fallback = null):
	return _dig(d(), path, fallback)


## "Find survivors: %d of %d" filled in, or the template as it stands when its holes and the values do not match (a damaged data file shows its words, never an error).
static func _fmt(template: String, args: Array) -> String:
	if template.count("%d") + template.count("%s") != args.size():
		return template
	return template % args


# ------------------------------------------------------------ making the run --

## Swaps the One House scenario into a freshly built `game` (before the run starts, or before a save is read) and puts its switches on it. A town game already has one (its own
## part: scripts/town/town_sim.gd); a game that has not gets a new one. Returns it.
static func install(game):
	var module = game.scenario
	if module == null or not module.has_method("go_to"):
		var script: GDScript = load("res://scripts/town/one_house.gd")
		module = script.new()
		game.scenario = module
		module.setup(game)
	module._activate()
	return module


## Installs it and starts the run: Ruth alone in the start house at 08:00 of day 1. `difficulty` -1 is the data's; `seed_value` is the run's seed (the town's own is made from it
## by the factory that built `game`). Returns the module.
static func begin(game, difficulty: int = -1, seed_value: int = 0):
	var module = install(game)
	module._begin_run(difficulty, seed_value)
	return module


## Whether `game` is a town game (it has the town's houses), which is what makes a new run of it a One House run.
static func wanted(game) -> bool:
	return game != null and game.get("houses") != null


## The tips of the school (assets/data/hints.json) for a town run: only the ones the run's data names (`hints`: the school's id to what it says here), each with the run's own
## id (so that they come once in the town, whatever the player has seen in the school), its words and its numbers over the school's. Everything else of the school's is left out.
static func town_hints(list: Array) -> Array:
	var table: Dictionary = data().get("hints", {})
	var out: Array = []
	for h in list:
		var id := String(h.get("id", ""))
		if not table.has(id) or not table[id] is Dictionary:
			continue
		var mine: Dictionary = (h as Dictionary).duplicate(true)
		var over: Dictionary = table[id]
		if over.has("text"):
			mine.erase("text_avatar")
			mine.erase("text_avatar_always")
		for k in over:
			mine[k] = over[k].duplicate(true) if (over[k] is Dictionary or over[k] is Array) else over[k]
		out.append(mine)
	return out


## Whether the New game of this game begins the town run: the real game (the scene of scripts/main.gd, not a test's stand-in for it) unless `--school` asks for the old start
## (the school's yard, a crew of three or five) or the demo is on. `main_node` is the game's main node (`shell.main`).
static func town_start(main_node) -> bool:
	if "--school" in OS.get_cmdline_user_args() or Demo.on():
		return false
	var script = main_node.get_script() if main_node != null else null
	return script != null and String(script.resource_path) == "res://scripts/main.gd"


## Whether `data` (a save as SaveGame.read gives it) is a One House save.
static func is_save(data: Dictionary) -> bool:
	var modules = data.get("modules")
	if typeof(modules) != TYPE_DICTIONARY:
		return false
	var mine = modules.get("scenario")
	return typeof(mine) == TYPE_DICTIONARY and String(mine.get("kind", "")) == KIND


## The seed of the town a One House save was made in, or -1 (the factory that builds a town game from a save needs it before the save is read).
static func town_seed_of(data: Dictionary) -> int:
	var modules = data.get("modules")
	var mine = modules.get("scenario") if typeof(modules) == TYPE_DICTIONARY else null
	if typeof(mine) == TYPE_DICTIONARY and String(mine.get("kind", "")) == KIND and mine.has("town_seed"):
		return int(mine.town_seed)
	return -1


## Puts the run in a stage for a screenshot, the lab or a test: "cleared", "claimed", "rescued2", "fourth" or "night" (the clock just before the first attack's dusk), "alone"
## does nothing. It does what the real thing does where the module is there (the dead of the house are put down, the base is claimed) and makes the rest up. False for a
## game that is not a One House game, or a name it does not know. Says nothing else: the caller looks at `stage()`.
static func stage_to(game, stage_name: String) -> bool:
	var module = game.scenario if game != null else null
	if module == null or not module.has_method("go_to"):
		return false
	return module.go_to(stage_name)


func _activate() -> void:
	_begun = true
	_dirty = true
	_apply_static()


func _begin_run(difficulty: int, seed_value: int) -> void:
	var diff: int = int(_cfg("difficulty", 1)) if difficulty < 0 else difficulty
	sim.crew_start = 3
	sim.seasons.campaign = false
	sim.start_run(diff, seed_value)
	sim.zombies.clear()
	_begun = true
	_solo()
	var start: Dictionary = _cfg("start", {})
	_set_clock(1, float(start.get("hour", 8.0)))
	for k in sim.stock.keys():
		sim.stock[k] = 0.0
	var stock = start.get("stock", {})
	for k in stock:
		sim.stock[String(k)] = float(stock[k])
	var town_data = sim.get("town_data")
	if typeof(town_data) == TYPE_DICTIONARY and not town_data.is_empty():
		_town_seed = int(town_data.get("seed", 0))
		var sz = town_data.get("size", Vector2i.ZERO)
		_size = [int(sz.x), int(sz.y)] if typeof(sz) == TYPE_VECTOR2I else [0, 0]
	else:
		_town_seed = seed_value
	_calm_the_start()
	_apply_static()
	_apply_flags()
	apply_stage()
	sim.events.clear()


## The first minutes are quiet: the dead round the start house that would wander (the generator lets some of the street's walk) stand where they are, as the ones inside the houses do, until
## somebody is near them. A shot is heard and brings those near; nobody is brought by a dead one that happened to walk by in the first minute. (Only the records: nothing is awake yet.)
func _calm_the_start() -> void:
	var field = sim.get("field")
	if field == null or not ("stands" in field) or not ("xs" in field):
		return
	var r := float(_cfg("calm_start_r", 32.0))
	if r <= 0.0:
		return
	var at := _start_pos()
	var r2 := r * r
	for i in int(field.n):
		if int(field.stands[i]) == 0 and Vector2(field.xs[i], field.ys[i]).distance_squared_to(at) < r2:
			field.stands[i] = 1


## One person, Ruth, the player, and nobody on the radio: the recruits are a small start's with no caller (`recruits.small`, so that every module of the community sees a small
## start), the others of the roster are not in the crew, and nobody has a job.
func _solo() -> void:
	var rc = sim.recruits
	rc.small = true
	rc.queue.clear()
	rc.incoming.clear()
	rc.next_call_day = NEVER
	var ruth = null
	for p in sim.people:
		if String(p.id) == "ruth":
			ruth = p
	var keep: Array = [ruth] if ruth != null else []
	if sim.people.size() != keep.size():
		sim.people = keep
		for m in [sim.morale, sim.traits, sim.bonds, sim.jobs, sim.skills, sim.supplies]:
			m.start()    # (what recruits.begin does after it has cut the crew down)
	if ruth == null:
		ruth = sim.add_person(_ruth_def())
	sim.avatar.set_player(String(ruth.id))


## Ruth's entry of the roster (assets/data/map.json), at the start house, with no seat and no post of the school's: the avatar is nobody's worker.
func _ruth_def() -> Dictionary:
	var def: Dictionary = {}
	var roster: Array = GD.load_all().people
	for p in roster:
		if String(p.id) == "ruth":
			def = p.duplicate(true)
	if def.is_empty():
		def = (roster[0] as Dictionary).duplicate(true)
	var at := _start_pos()
	def["station"] = ""
	def["post_id"] = ""
	def["job"] = {"x": at.x, "y": at.y, "what": "At home"}
	def["post"] = {"x": at.x, "y": at.y, "what": "At home"}
	return def


## The free tile of the start house where a run begins (the town's own), or where Ruth stands when the game has no town.
func _start_pos() -> Vector2:
	var houses = sim.get("houses")
	if houses != null:
		var town = houses.get("town")
		if typeof(town) == TYPE_DICTIONARY and town.has("start"):
			return Vector2(town.start.pos)
	var p = sim.avatar.player()
	return Vector2(p.x, p.y) if p != null else Vector2.ZERO


## The clock at `hour` (0 to 24) of `day`, with what hangs on it settled (as tests/helpers.gd `at` does).
func _set_clock(day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.seasons.phase_at(sim.minutes)
	sim.bell_rung = hour >= float(sim.seasons.dusk_hour()) or hour < 6.0
	sim.supplies.sources_day = day


## What the One House run keeps in the colony whatever the crew is: the clock's speed, and the school's town board, lots, streets, storyteller, gate and levels off (they are the
## school's: a compound, a gate that is a wall section, a noon card, a deck).
func _apply_static() -> void:
	sim.min_per_sec = float(_cfg("min_per_sec", 2.0))
	sim.town.on = false
	sim.lots.on = false
	sim.streets.enabled = false
	sim.storyteller.enabled = false
	sim.gate.enabled = false
	sim.levels.enabled = false
	sim.seasons.campaign = false
	# (a run of few rounds: forty is a fine start, the school's "running low" of sixty would be a standing alert)
	if sim.supplies != null and sim.supplies.get("low_ammo") != null:
		sim.supplies.low_ammo = float(_cfg("low_ammo", 10.0))


## What follows the stage of the run, looked at every tick: the nights' machinery is on from the first attack night, and the street's dead wake no more near the base through it.
func _apply_flags() -> void:
	var on := attacks_on()
	sim.waves.enabled = on
	var field = sim.get("field")
	if field != null and "pause_wake" in field:
		var hold: bool = on and (sim.phase == "dusk" or sim.phase == "night" or sim.phase == "dawn")
		var sleeper = sim.get("sleep")
		if sleeper != null and sleeper.has_method("active") and bool(sleeper.active()):
			hold = true    # (the avatar asleep keeps the street asleep: the sleep sets it, and this would put it back every tick)
		if bool(field.pause_wake) != hold:
			field.pause_wake = hold


## Switches each community module on or off by how many people there are (the data's `modules_from_crew`: from that many on; 99 is never in this run). Called at the start and
## at every change of the crew: a person joins, a person is lost.
func apply_stage() -> void:
	var crew := crew_count()
	_crew_seen = crew
	var table = _cfg("modules_from_crew", {})
	for name in table:
		var m = sim.get(String(name))
		if m != null and "enabled" in m:
			m.enabled = crew >= int(table[name])


# ----------------------------------------------------------------- the stages --

func stage() -> String:
	return _stage


func _stage_idx() -> int:
	return STAGES.find(_stage)


func _advance(to: String) -> void:
	if STAGES.find(to) > _stage_idx():
		_stage = to


## How many survivors have joined (the rescue module's count, and the ones a staging made up).
func rescued() -> int:
	return _module_joined + _staged_joins


## The living people, the avatar counted.
func crew_count() -> int:
	var rc = sim.get("recruits")
	if rc != null and rc.has_method("crew_size"):
		return int(rc.crew_size())
	var n := 0
	for p in sim.people:
		if not p.dead and not p.turned:
			n += 1
	return n


## Whether the dead come at the base: from the first attack night on.
func attacks_on() -> bool:
	return _attacks and sim.day >= _first_day


## Whether the lookout's forecast and the alert of the dead coming are told: the same.
func forecast_on() -> bool:
	return attacks_on()


## The start house has no dead left (clearing calls it for every house it finds cleared).
func on_house_clear(h: int) -> void:
	_cleared[int(h)] = true
	var houses = sim.get("houses")
	if houses == null or int(h) == int(houses.start_house()):
		_advance("cleared")


## The house is the base now (`base.claim` calls it).
func on_claimed(_h: int) -> void:
	_advance("claimed")


## A survivor has joined (the rescue module calls it with its own count of them): the crew changes, and the fourth makes the dead come.
func on_survivor_joined(_p, count: int) -> void:
	_module_joined = maxi(_module_joined, int(count))
	_advance("growing")
	apply_stage()
	if not _attacks and rescued() >= int(_cfg("attack.from_rescue", 4)):
		_fourth()


func _fourth() -> void:
	_attacks = true
	var late: bool = float(sim.hour) >= float(_cfg("attack.cutoff_hour", 17.0))
	_first_day = sim.day + 1 if late else sim.day
	_advance("fortify")
	var words = _cfg("words.fourth_tomorrow" if late else "words.fourth_tonight", ["Four voices on the radio", ""])
	# (the rescue module says {"type": "fourth"} itself when the fourth arrives: this module adds only what is its own)
	sim.events.append({"type": "attacks_on", "from_day": _first_day})
	sim.events.append({"type": "banner", "text": String(words[0]), "sub": String(words[1])})
	var news = _cfg("words.news_fourth", words)
	if sim.get("radio") != null:
		sim.radio.log_news("story", String(news[0]), String(news[1]))
	_apply_flags()


# ----------------------------------------------------------------- every step --

## Every step: the walk is counted; every TICK seconds the run looks at itself (nobody left, the crew, the flags, the lessons, the dawn).
func update(dt: float) -> void:
	if not _begun or sim.over != "":
		return
	_track_walk()
	_t += dt
	if _t < TICK and not _dirty:
		return
	_t = 0.0
	if _nobody_left():
		return
	if _dirty:
		_dirty = false
		_apply_static()
	_apply_flags()
	if crew_count() != _crew_seen:
		apply_stage()
	_watch_the_dawn()
	_watch_the_lessons()


func _track_walk() -> void:
	var p = sim.avatar.player()
	if p == null:
		return
	var at := Vector2(p.x, p.y)
	if _last_pos != Vector2.INF:
		var step := at.distance_to(_last_pos)
		if step < JUMP_TILES:
			_walked += step
	_last_pos = at


## The run is lost when nobody is left alive (and not turned).
func _nobody_left() -> bool:
	if sim.people.is_empty():
		return false
	for p in sim.people:
		if not p.dead and not p.turned:
			return false
	sim.over = "defeat"
	var words = _cfg("words.defeat", ["The house is empty", ""])
	sim.events.append({"type": "over", "result": "defeat"})
	sim.events.append({"type": "banner", "text": String(words[0]), "sub": String(words[1])})
	return true


## The reckoning of a night, ONCE, at the first moment of the day after it (the dawn has been the dead's hour to retreat and the crew's to mend: the dawn hour is the player's last
## chance to shut a breach). The night is held when the data's rule is true then and the run is won; when it is not the night is not held (the banner says why), the run goes on
## and the next dawn is judged the same way (the dead come every night, a little more each).
func _watch_the_dawn() -> void:
	if not _attacks or _stage == "held" or sim.day <= _first_day or sim.phase != "day" or _dawn_day == sim.day:
		return
	_dawn_day = sim.day
	var why := _not_held_because()
	if why == "":
		_stage = "held"
		_held_nights += 1
		if _first_result == "":
			_first_result = "held"
		sim.over = "victory"
		sim.events.append({"type": "held", "night": _first_day})
		sim.events.append({"type": "over", "result": "victory"})
		var words := victory_banner()
		sim.events.append({"type": "banner", "text": words[0], "sub": words[1]})
		return
	if _first_result == "":
		_first_result = "not_held"
		_first_why = why
	var told = _cfg("words.not_held", {})
	var line = told.get(why, ["The night is not held", ""]) if told is Dictionary else ["The night is not held", ""]
	sim.events.append({"type": "night_not_held", "why": why, "night": sim.day - 1})
	sim.events.append({"type": "banner", "text": String(line[0]), "sub": String(line[1])})
	if sim.get("radio") != null:
		sim.radio.log_news("story", String(line[0]), String(line[1]))


## How the first attack night ended, for the lab and the end card: "" while it has not been judged, "held", or "not_held" (the dawn found the base not whole, or somebody gone).
func first_night_result() -> String:
	return _first_result


## Why the first attack night was not held ("wall", "house", "base" or "avatar"; "" when it was, or has not been judged).
func first_night_why() -> String:
	return _first_why


func _held_ok() -> bool:
	return _not_held_because() == ""


## Why this dawn does not hold the night ("" when it does): "avatar" (whoever leads is gone), "house" (the dead are in it), "base" (nothing of the base stands) or "wall" (a section of the
## base is down: a breach not mended by dawn).
func _not_held_because() -> String:
	var rule = _cfg("held_rule", {})
	if bool(rule.get("avatar_alive", true)):
		var p = sim.avatar.player()
		if p == null or p.dead or p.turned:
			return "avatar"
	if bool(rule.get("house_empty", true)) and _dead_in_the_house() > 0:
		return "house"
	if bool(rule.get("base_standing", true)) and not _base_standing():
		return "base"
	if bool(rule.get("base_whole", false)) and _sections_down() > 0:
		return "wall"
	return ""


## How many sections of the base are down now (the fence, the gate, the barred doors: ids below the lots').
func _sections_down() -> int:
	var n := 0
	for s in sim.segments:
		if int(s.id) < SEGMENT_LIMIT and int(s.state) == 3:
			n += 1
	return n


## The base's house, or the start house before a claim; -1 when the game has no town.
func _base_house() -> int:
	var base = sim.get("base")
	if base != null and bool(base.get("claimed")):
		return int(base.house)
	var houses = sim.get("houses")
	return int(houses.start_house()) if houses != null else -1


## The dead in the base's house now: the town's own (its records, awake or not) and the night's, which are not records.
func _dead_in_the_house() -> int:
	var houses = sim.get("houses")
	var h := _base_house()
	if houses == null or h < 0:
		return 0
	var n := int(houses.dead_in_house(h))
	for z in sim.zombies:
		if z.state != "dying" and z.state != "dead" and z.state != "retreat" and houses.house_at(z.x, z.y) == h:
			n += 1
	return n


## A section of the base is up: any of the wall sections the game has that has not fallen (a town has the base's doors and fence and nothing else).
func _base_standing() -> bool:
	for s in sim.segments:
		if int(s.state) != 3:
			return true
	return false


# -------------------------------------------------------------------- the guide --

func _watch_the_lessons() -> void:
	var lessons = _cfg("guide", [])
	if _done.size() >= lessons.size():
		return
	var newest := -1
	for i in lessons.size():
		var id := String(lessons[i].get("id", ""))
		if id == "" or _done.has(id):
			continue
		if _cond(lessons[i].get("cond", {})):
			_done[id] = true
			_flash_id = id
			_flash_until = float(sim.t) + FLASH_S
			newest = i
	# (a player who has done a later lesson has the idea of the earlier ones: they are not asked again)
	for i in newest:
		_done[String(lessons[i].get("id", ""))] = true


func _cond(c: Dictionary) -> bool:
	match String(c.get("type", "")):
		"walked":
			return _walked >= float(c.get("n", 6))
		"kills":
			return int(sim.kills) >= int(c.get("n", 1))
		"rooms_seen":
			return _rooms_seen() >= int(c.get("n", 2))
		"house_clear":
			return _stage_idx() >= 1
		"searched":
			return _searched() >= int(c.get("n", 1))
		"claimed":
			return _stage_idx() >= 2
		"asked":
			return _asked >= int(c.get("n", 1))
	return false


## The rooms of the start house the avatar has opened; another house entered counts for all of them.
func _rooms_seen() -> int:
	var clearing = sim.get("clearing")
	var houses = sim.get("houses")
	if clearing == null or houses == null:
		return 0
	var h: int = houses.start_house()
	var n := 0
	for r in houses.rooms_of(h):
		if clearing.is_revealed(int(r)):
			n += 1
	if clearing.has_method("explored"):
		for e in clearing.explored():
			if int(e) != h:
				return NEVER
	return n


## How many containers have been searched (the search module's own count, its table of looted ones, else the ones of the start house and of the base).
func _searched() -> int:
	var search = sim.get("search")
	if search == null:
		return 0
	if search.has_method("looted_count"):
		return int(search.looted_count())
	if "looted" in search and search.looted is Dictionary:
		return (search.looted as Dictionary).size()
	var houses = sim.get("houses")
	if houses == null:
		return 0
	var n := 0
	var seen := {}
	for h in [int(houses.start_house()), _base_house()]:
		if seen.has(h):
			continue
		seen[h] = true
		for c in houses.containers_of(h):
			if search.is_looted(String(c.id)):
				n += 1
	return n


## How many containers of the start house nobody has searched yet.
func _unsearched_here() -> int:
	var search = sim.get("search")
	var houses = sim.get("houses")
	if search == null or houses == null:
		return 0
	var n := 0
	for c in houses.containers_of(int(houses.start_house())):
		if not search.is_looted(String(c.id)):
			n += 1
	return n


## The lesson of now: {"id", "title", "text", "goal", "done", "n", "of", "progress"}: the first not done (the one just done, for a few seconds, with `done` true), {} when
## there is none to give. `progress` is a short count when the lesson has one ("2 of 3 rooms clear").
func guide() -> Dictionary:
	if not _begun or _stage_idx() >= 5:
		return {}
	# (the lessons are for the first day, the lone survivor's: with the first voice on the radio they are over, and the lessons of the crew (`"crew": true`: how to ask
	# them for something) take their place until the fortify stage ends; the night itself teaches nothing)
	var crew := _stage_idx() >= 3
	var lessons: Array = []
	for l in _cfg("guide", []):
		if bool(l.get("crew", false)) == crew:
			lessons.append(l)
	if _flash_id != "" and float(sim.t) < _flash_until:
		for i in lessons.size():
			if String(lessons[i].get("id", "")) == _flash_id:
				return _lesson_out(lessons[i], i, lessons.size(), true)
	for i in lessons.size():
		if not _done.has(String(lessons[i].get("id", ""))):
			return _lesson_out(lessons[i], i, lessons.size(), false)
	return {}


## The player gave an order from the command wheel (main.gd: a verb was picked on someone, and they said yes or no): the lesson of asking the crew counts it.
func on_asked() -> void:
	_asked += 1
	_dirty = true


func _lesson_out(l: Dictionary, i: int, n: int, done: bool) -> Dictionary:
	var progress := ""
	if String(l.get("id", "")) == "clear" and not done:
		var rooms := _rooms_progress()
		if int(rooms.of) > 0:
			progress = _fmt(String(_cfg("objective.clear.sub", "%d of %d rooms clear")), [rooms.clear, rooms.of])
	return {"id": String(l.get("id", "")), "title": String(l.get("title", "")), "text": String(l.get("text", "")), "goal": String(l.get("goal", "")), "done": done, "n": i + 1, "of": n, "progress": progress}


## {"clear", "of", "at"}: how many rooms of the start house are clear, how many it has, and the middle of the nearest that is not (null when they all are or there is no town).
func _rooms_progress() -> Dictionary:
	var out := {"clear": 0, "of": 0, "at": null}
	var houses = sim.get("houses")
	var clearing = sim.get("clearing")
	if houses == null:
		return out
	var me = sim.avatar.player()
	var here := Vector2(me.x, me.y) if me != null else Vector2.ZERO
	var best := INF
	for r in houses.rooms_of(houses.start_house()):
		out.of = int(out.of) + 1
		if clearing != null and clearing.is_clear(int(r)):
			out.clear = int(out.clear) + 1
			continue
		var mid := Vector2(Rect2i(houses.room(int(r)).rect).get_center())
		if here.distance_to(mid) < best:
			best = here.distance_to(mid)
			out.at = mid
	return out


# ---------------------------------------------------------------- the objective --

## The line the player reads under the clock: {"id", "text", "sub", "at": Vector2 or null (where to look), "step", "of"}. It follows `stage()`: clear the house, claim it, find the
## survivors (n of four), fortify before dark, hold the night, the night is held.
func objective() -> Dictionary:
	var out := {"id": "", "text": "", "sub": "", "at": null, "step": 0, "of": 0}
	if not _begun:
		return out
	match _stage:
		"alone":
			var rooms := _rooms_progress()
			out.id = "clear"
			out.text = String(_cfg("objective.clear.text", "Clear the house"))
			if int(rooms.of) > 0:
				out.sub = _fmt(String(_cfg("objective.clear.sub", "")), [rooms.clear, rooms.of])
			else:
				out.sub = String(_cfg("objective.clear.sub_unknown", ""))
			out.at = rooms.at
			out.step = int(rooms.clear)
			out.of = int(rooms.of)
		"cleared":
			out.id = "claim"
			out.text = String(_cfg("objective.claim.text", "Claim the house"))
			var search_first := String(_cfg("objective.claim.sub_search", ""))
			out.sub = search_first if search_first != "" and _unsearched_here() > 0 else String(_cfg("objective.claim.sub", ""))
			out.at = _front_door()
		"claimed", "growing":
			var want := int(_cfg("attack.from_rescue", 4))
			out.id = "rescue"
			out.text = _fmt(String(_cfg("objective.rescue.text", "Find survivors: %d of %d")), [rescued(), want])
			out.sub = String(_cfg("objective.rescue.sub", ""))
			out.at = _survivor_bearing()
			out.step = rescued()
			out.of = want
		"fortify":
			var night: bool = attacks_on() and (sim.phase == "dusk" or sim.phase == "night" or sim.phase == "dawn")
			var key := "hold" if night else "fortify"
			out.id = key
			out.text = String(_cfg("objective.%s.text" % key, ""))
			out.sub = String(_cfg("objective.%s.sub" % key, ""))
			if key == "fortify":
				out.sub = _fortify_sub(String(out.sub))
			out.at = _base_center()
		"held":
			out.id = "held"
			out.text = String(_cfg("objective.held.text", "The night is held"))
			out.sub = String(_cfg("objective.held.sub", ""))
	return out


## What the line under "Fortify the house before dark" says: the project to order next ("Order the front fence on the Build page (N)"), that what can be ordered is going up, or that
## everything is built; `fallback` (the file's plain line) when there are no projects to speak of.
func _fortify_sub(fallback: String) -> String:
	var per = sim.get("perimeter")
	if per == null or not per.has_method("projects"):
		return fallback
	var infos: Array = per.projects()
	if infos.is_empty():
		return fallback
	var going := false
	for p in infos:
		if bool(p.get("recommended", false)):
			return _fmt(String(_cfg("objective.fortify.sub_next", fallback)), [String(p.noun)])
		if String(p.get("state", "")) == "building":
			going = true
	return String(_cfg("objective.fortify.sub_going", fallback)) if going else String(_cfg("objective.fortify.sub_done", fallback))


## The outside of the start house's front door, in tiles (the middle of the house when it has none), null with no town.
func _front_door() -> Variant:
	var houses = sim.get("houses")
	if houses == null:
		return null
	var h: int = houses.start_house()
	var door = _exterior_door(h)
	if not door.is_empty():
		return Vector2(door.out) + Vector2(0.5, 0.5)
	var rect = houses.house(h).get("rect")
	return Vector2(Rect2i(rect).get_center()) if rect != null else null


## The exterior door on the house's front side ({} when it has none).
func _exterior_door(h: int) -> Dictionary:
	var houses = sim.get("houses")
	var front := String(houses.house(h).get("front", ""))
	var any := {}
	for door in houses.doors_of(h):
		if not bool(door.get("exterior", false)):
			continue
		if String(door.get("side", "")) == front:
			return door
		if any.is_empty():
			any = door
	return any


func _base_center() -> Variant:
	var base = sim.get("base")
	if base != null and bool(base.get("claimed")) and base.has_method("center"):
		return base.center()
	return null


## Where the nearest survivor not yet at the base is (their spot, in tiles), null when there are none to point at.
func _survivor_bearing() -> Variant:
	var rescue = sim.get("rescue")
	if rescue == null or not rescue.has_method("list"):
		return null
	var me = sim.avatar.player()
	var here := Vector2(me.x, me.y) if me != null else Vector2.ZERO
	var best = null
	var best_d := INF
	for r in rescue.list():
		var st := String(r.get("state", ""))
		var pos = r.get("pos")
		if st == "joined" or st == "lost" or typeof(pos) != TYPE_VECTOR2:
			continue
		if here.distance_to(pos) < best_d:
			best_d = here.distance_to(pos)
			best = pos
	return best


# --------------------------------------------------------------- the nights --

## The run's length for the clock and the briefing: the data's, and never less than the day after the first attack night.
func total_days() -> int:
	return maxi(int(_cfg("total_days", 5)), _first_day + 1)


## The first day of the community's ideas (initiative.gd asks).
func idea_day() -> int:
	return int(_cfg("ideas_from_day", 2))


## The size of the night after `day` over what an ordinary night of the avatar game is (waves.gd): the data's, growing a little each attack night, 1 before the attacks.
func night_mult(day: int) -> float:
	if _first_day < 0 or day < _first_day:
		return 1.0
	return maxf(float(_cfg("night.first", 1.0)) * (1.0 + float(_cfg("night.growth", 0.15)) * float(day - _first_day)), 0.05)


## The Big Night after `day` as waves.gd's `big_night` answers it: {} (the first attack night is an ordinary one) unless the data asks for a theme's numbers (brutes).
func big_night_for(day: int) -> Dictionary:
	var mine = _cfg("big_night", {})
	if _first_day < 0 or day != _first_day or not mine is Dictionary or (mine as Dictionary).is_empty():
		return {}
	var t := NightData.theme(String(mine.get("theme", "siege")))
	for k in mine:
		t[k] = mine[k]
	var span := _range(t.get("brute_at", []))
	return {
		"kind": "milestone", "id": "siege", "index": 0, "name": String(t.get("name", "The first night")), "factor": maxf(float(t.get("factor", 1.0)), 1.0),
		"runners": clampf(float(t.get("runners", 0.0)), 0.0, 0.8), "brutes": clampf(float(t.get("brutes", 0.2)), 0.0, 0.8),
		"min_brutes": maxi(0, int(t.get("min_brutes", 1))), "headings": clampi(int(t.get("headings", 1)), 1, 2), "main_share": clampf(float(t.get("main_share", 0.9)), 0.0, 1.0),
		"brute_at": span, "cap": maxi(10, int(t.get("cap", 50))), "blurb": String(t.get("blurb", "")), "plated": bool(t.get("plated", false)),
	}


func _range(v) -> Array:
	var lo := 0.3
	var hi := 0.65
	if typeof(v) == TYPE_ARRAY and v.size() == 2:
		lo = float(v[0])
		hi = float(v[1])
	lo = clampf(lo, 0.0, 0.99)
	return [lo, clampf(hi, lo + 0.01, 1.0)]


func victory_banner() -> Array:
	var words = _cfg("words.victory", ["The night is held", ""])
	return [String(words[0]), String(words[1])]


# --------------------------------------------------------------- the report --

## What the end card tells of the run so far: {"nights" (held), "of", "alive", "lost" (dead or turned), "kills" (the dead put down), "rescued", "houses" (cleared), "built"
## (sections of the base made), "days", "stage"}.
func report() -> Dictionary:
	var alive := 0
	var lost := 0
	for p in sim.people:
		if p.dead or p.turned:
			lost += 1
		else:
			alive += 1
	var built := 0
	var perimeter = sim.get("perimeter")
	if perimeter != null and perimeter.has_method("built_count"):
		built = int(perimeter.built_count())
	return {
		"nights": _held_nights, "of": 1, "alive": alive, "lost": lost, "kills": int(sim.kills), "rescued": rescued(), "houses": _cleared.size(), "built": built,
		"days": int(sim.day), "stage": _stage,
	}


## The end card of the run: {"title", "line", "full", "thanks", "caps", "stats": [[label, value]...]}: the words are the data's, the numbers the run's own.
func end_card() -> Dictionary:
	var r := report()
	var e: Dictionary = _cfg("end", {})
	var labels: Dictionary = e.get("labels", {})
	return {
		"title": String(e.get("title", "The night is held")), "line": String(e.get("line", "")), "full": String(e.get("full", "")), "thanks": String(e.get("thanks", "")),
		"caps": String(e.get("caps", "")),
		"stats": [
			[String(labels.get("nights", "Nights held")), str(r.nights)],
			[String(labels.get("people", "People at the house")), str(r.alive)],
			[String(labels.get("houses", "Houses cleared")), str(r.houses)],
			[String(labels.get("kills", "The dead put down")), str(r.kills)],
			[String(labels.get("built", "Fence and gate built")), str(r.built)],
			[String(labels.get("days", "Days")), str(r.days)],
		],
	}


# ---------------------------------------------------------------------- staging --

## Puts the run in `stage_name` (see `stage_to`). A run that has not begun is begun first.
func go_to(stage_name: String) -> bool:
	if not STAGE_NAMES.has(stage_name):
		return false
	if not _begun:
		_begin_run(-1, int(sim.run_seed))
	var upto := STAGE_NAMES.find(stage_name)
	if upto >= 1:
		_stage_clear()
	if upto >= 2:
		_stage_claim()
	if upto >= 3:
		_set_clock(2, 10.0)
		_stage_join(2 - rescued())
	if upto >= 4:
		_set_clock(3, 10.0)
		_stage_join(int(_cfg("attack.from_rescue", 4)) - rescued())
	if upto >= 5:
		_set_clock(maxi(_first_day, sim.day), 18.75)
		sim.waves.night_day = -1
	_apply_flags()
	return true


## The dead of the start house put down, its rooms opened, and the clearing module given a moment to notice (`on_house_clear` is called here when it does not).
func _stage_clear() -> void:
	var houses = sim.get("houses")
	var field = sim.get("field")
	var clearing = sim.get("clearing")
	var h: int = houses.start_house() if houses != null else -1
	var me = sim.avatar.player()
	if houses != null and field != null and field.has_method("wake_house"):
		field.wake_house(h)
		for z in sim.zombies.duplicate():
			if z.state != "dying" and z.state != "dead" and houses.house_at(z.x, z.y) == h:
				sim._hurt_zombie(z, 9999.0, 0.0, me)
	if houses != null and clearing != null:
		for r in houses.rooms_of(h):
			clearing.reveal(int(r), "stage")
	for i in 20:
		sim.update(1.0 / 30.0)
	if _stage_idx() < 1 and h >= 0:
		on_house_clear(h)
	elif _stage_idx() < 1:
		_advance("cleared")


## The avatar just inside the front door and the house claimed (by the base module when it is there, else the stage is just set).
func _stage_claim() -> void:
	var houses = sim.get("houses")
	var base = sim.get("base")
	var h: int = houses.start_house() if houses != null else -1
	if houses != null:
		var door = _exterior_door(h)
		var me = sim.avatar.player()
		if not door.is_empty() and me != null:
			me.x = float(door["in"].x) + 0.5
			me.y = float(door["in"].y) + 0.5
	if base != null and base.has_method("claim") and h >= 0:
		base.claim(h)
	if _stage_idx() < 2:
		on_claimed(h)


## `n` survivors made up and at the avatar's side (people with the data's own defs, away from the rescue module's records), as if they had come.
func _stage_join(n: int) -> void:
	for i in maxi(n, 0):
		var def: Dictionary = sim.recruits.make_def(50 + rescued())
		var p = sim.add_person(def)
		sim.recruits.arrived.append(def)
		var me = sim.avatar.player()
		if me != null:
			p.x = me.x + 0.8 + 0.4 * float(i)
			p.y = me.y + 0.6
		_staged_joins += 1
		if sim.jobs.has_method("fill_empty"):
			sim.jobs.fill_empty()
		on_survivor_joined(p, 0)


# ------------------------------------------------------------------------ the save --

## What the run keeps: the stage and the counters, the lessons done, the town's seed and size (the town is made again from them), the clock's speed.
func save() -> Dictionary:
	return {
		"kind": KIND, "v": 1, "stage": _stage, "joined": _module_joined, "staged": _staged_joins, "attacks": _attacks, "first_day": _first_day,
		"cleared": _cleared.keys(), "done": _done.keys(), "walked": _walked, "held": _held_nights, "dawn_day": _dawn_day, "first_result": _first_result, "first_why": _first_why, "town_seed": _town_seed, "size": _size,
		"min_per_sec": float(sim.min_per_sec),
	}


func load_state(s: Dictionary) -> void:
	start()
	_begun = true
	var st := String(s.get("stage", "alone"))
	_stage = st if STAGES.has(st) else "alone"
	_module_joined = int(s.get("joined", 0))
	_staged_joins = int(s.get("staged", 0))
	_attacks = bool(s.get("attacks", false))
	_first_day = int(s.get("first_day", -1))
	for h in s.get("cleared", []):
		_cleared[int(h)] = true
	for id in s.get("done", []):
		_done[String(id)] = true
	_walked = float(s.get("walked", 0.0))
	_held_nights = int(s.get("held", 0))
	_dawn_day = int(s.get("dawn_day", -1))
	_first_result = String(s.get("first_result", ""))
	_first_why = String(s.get("first_why", ""))
	_town_seed = int(s.get("town_seed", 0))
	var sz = s.get("size", [0, 0])
	_size = [int(sz[0]), int(sz[1])] if typeof(sz) == TYPE_ARRAY and sz.size() == 2 else [0, 0]
	# (the clock's speed is the data's, `_apply_static`; the modules that load after this one may touch what the run keeps in them: the next tick puts it all again)
	_dirty = true
	_apply_static()
	_apply_flags()
	apply_stage()
