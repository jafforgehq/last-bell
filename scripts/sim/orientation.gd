## Orientation Day: the scenario the tutorial is taught in. A small scripted run that
## cannot be lost, so a new player learns the game by doing and nothing they try can
## end it. The coach (scripts/ui/coach.gd) teaches it from assets/data/tutorial.json;
## this module is the rules' side and works on its own, with no coach and no screen.
##
## What it is:
## - Story difficulty, a fixed seed, day 1 at 07:00, the school bus on the north wall
##   worn to 45% (the wall piece to mend) and a smaller store of ammo, so that the
##   number moves when the guns shoot. The jobs that work by themselves start off (nobody
##   is on the wall crew, the bench or the garden, and nobody mends a wall as a chore), or
##   Walt would mend the bus before the player gets to.
## - It can never be lost. Nobody dies (`permadeath` is off: someone who bleeds out is
##   stabilised instead), nobody turns (the turn of anyone infected is kept far off),
##   nobody leaves for good (a send-out is cancelled), a trip never loses or hurts
##   anyone and always brings something back, and no wall section falls below a floor.
##   It never sets `sim.over`.
## - The nights are scripted, not rolled. The normal waves are off (`waves.enabled`).
##   Four beats (see BEATS) bring the dead and the wounds the lessons need: three
##   walkers at the gate at dusk, four more from the north east, a scratch for Walt, a
##   fever for Hector. With no coach they happen on the game clock (`sim.clock_min`,
##   minutes since 07:00 on day 1); a coach takes them over (`coached`) and fires each
##   one (`fire`) when its lesson begins, so the dead never arrive before the card.
## - The lookout's forecast at 17:00 is true to the script (see OrientationWaves).
## - A treatment of an infection always works (see OrientationMedical), so a bad roll
##   cannot spoil the lesson.
## - Ruth starts in the yard, in view of the opening camera (she walks back to the radio
##   when she is let go), and `jump` puts the world the way a step expects, for starting
##   the tutorial at that step.
##
## THE AVATAR'S ORIENTATION DAY (round 17, `avatar`): the lesson the real game is taught in. Ruth is the player (main.gd
## names her after the run begins), the town is on (the board that G opens, as in a real run, with six people and the old
## school's buildings), the dead of the streets are off, and the bus is whole (nobody mends it: nothing here is the old
## yard's order). It adds two beats to the script, `stray` (one walker comes to the bus wall at the north: it is a lesson
## in aiming and in the ladder, so it is put again if somebody else shoots it before the player has fired at one) and
## `spent` (the magazine of the player's gun is left low, so that R has something to do), `assault` (two of the dead are at a
## wall section and the radio calls: the call card's lesson) and `home` (everyone back to their work, any call answered by its
## default); and the scratch comes with Ana at Walt's side at once (the radio refuses her in the hearing of the player, who
## has the game held). The classic Orientation Day (`avatar` false: `--noavatar`, a test) is as it was.
##
## When the lesson is over (`finish`, called by the coach on the last card or on Skip)
## the script stops and the real nights begin: the run goes on as a sandbox that still
## cannot be lost.
##
## It is installed the way the tests swap any scenario: `Orientation.begin(sim)` on a
## freshly built Sim (installs, then starts a run on the fixed seed). Saved with the
## run like every module (SaveGame finds it by reflection), so a load resumes the lesson:
## `step` and `coach_state` belong to the coach and are kept here for that.
##
## Events: none of its own. Alerts: `horde-a`, `horde-b` (the two groups), `scratch-walt`
## (the wound); the medical module raises the fever's.
extends "res://scripts/sim/scenario.gd"

## The seed of Orientation Day: it plays the same game every time.
const SEED := 1001
## The wall piece that starts worn (the school bus on the north wall), and how worn.
const BUS_ID := 3
const BUS_START := 0.45
## Where Ruth starts: in the yard, in view of the opening camera.
const RUTH_AT := Vector2(43.0, 22.5)
## No wall section is let fall below this share of its health.
const WALL_FLOOR := 0.2
## The ammo it starts with: a smaller store than a real run's, so the number moves.
const START_AMMO := 150.0
## A fever starts this many game hours before it is given (it shows from six), and
## the turn that never comes is this many hours after the infection.
const FEVER_AGO_H := 6.0
const TURN_AFTER_H := 72.0
## The turn of anyone infected is never nearer than this many game minutes.
const TURN_MARGIN_MIN := 600.0
## A trip that brings nothing back brings this.
const MERCY_LOOT := {"food": 10, "water": 12}
## The beats of the script: when the clock brings each by itself (game minutes since
## 07:00 on day 1) and what each is. The ids are what the lessons' `fire` names.
const BEATS := [
	{"id": "dusk", "at": 740.0},
	{"id": "more", "at": 810.0},
	{"id": "scratch", "at": 870.0},
	{"id": "fever", "at": 900.0},
]
## Where the dead come from: three at dusk at the north edge, heading for the main gate
## (the best defended wall piece), four from the north east a little later.
const DUSK_AT := [[28.0, 0.5], [29.4, 0.6], [28.6, 1.3]]
const DUSK_WALL := 2
const MORE_AT := [[60.5, 6.0], [62.0, 7.0], [63.5, 6.0], [62.0, 5.0]]
const MORE_WALL := 5
## Who gets the wound and the fever.
const SCRATCHED := "walt"
const FEVERISH := "hector"
## The avatar's lesson (see the top of the file): the beats it adds (they are never brought by the clock: only a
## lesson brings them), the lone walker's place (the north lane, in front of the bus section and its ladder) and how
## many times it is put again; and what the player's magazine is left at (a third of it, at least one round).
const AVATAR_BEATS := ["stray", "spent", "assault", "home"]
const STRAY_AT := [47.5, 9.0]
const STRAY_WALL := 3
const STRAY_TRIES := 3
const SPENT_SHARE := 0.34
## The wall that is under attack when the news comes (the blue container at the north east) and how many of the dead are at it.
const ASSAULT_WALL := 5
const ASSAULT_N := 2
## What the lookout says tonight brings: the two groups, from the spawn point nearest where
## the first group comes in.
const FORECAST_TOTAL := 7


## Waves for Orientation Day: the forecast tells what the script will bring (seven
## walkers from the north), and the nights are the script's until the lesson is over.
## After that the real waves take over (`scripted` is false).
class OrientationWaves:
	extends "res://scripts/sim/waves.gd"
	var scripted := true

	func plan_for(day: int) -> Dictionary:
		if scripted and day == 1:
			var queue: Array = []
			for i in FORECAST_TOTAL:
				queue.append("walker")
			return {
				"day": 1, "big": false, "budget": float(FORECAST_TOTAL), "queue": queue,
				"counts": {"walker": FORECAST_TOTAL, "runner": 0, "brute": 0},
				"heading": [_nearest_spawn()], "shown": FORECAST_TOTAL,
			}
		return super.plan_for(day)

	## The index of the spawn point nearest where the dusk group comes in.
	func _nearest_spawn() -> int:
		var from := Vector2(float(DUSK_AT[0][0]), float(DUSK_AT[0][1]))
		var best := 0
		var best_d := INF
		for i in sim.spawns.size():
			var d: float = from.distance_to(sim.spawns[i])
			if d < best_d:
				best_d = d
				best = i
		return best


## Medicine for Orientation Day: a treatment of an infection always takes (the rest is
## the module's own), so the lesson is never lost to a bad roll.
class OrientationMedical:
	extends "res://scripts/sim/medical.gd"

	func try_cure(_healer, patient) -> bool:
		_use_meds(CURE_MEDS)
		patient.infected_at = -1.0
		patient.turn_at = -1.0
		stage_seen.erase(patient.id)
		sim.alerts.erase("fever-%s" % patient.id)
		return true


## Which beats have happened (id to true).
var fired := {}
## The coach's place in its steps, and what it keeps for the step it is on (plain data):
## saved with the run, so a load resumes the lesson where it was.
var step := 0
var coach_state := {}
## A coach is teaching: it fires the beats itself, so the clock does not.
var coached := false
## The lesson is over: no more beats, the real nights are on.
var finished := false
## The first step of the rules has been taken (what is put right once, then left alone).
var prepared := false
## This is the avatar's Orientation Day (see the top of the file): `install` says so before the run begins.
var avatar := false
## The lone walker of the avatar's lesson: it is looked for again while this is on (the lesson has not been passed by
## the player: no kill of theirs since it came, `stray_kills`), up to STRAY_TRIES times (`stray_tries`).
var stray_open := false
var stray_kills := 0
var stray_tries := 0


## Swaps this scenario, the scripted waves and the forgiving medicine into a freshly
## built `sim` (before the run starts). Returns the scenario.
static func install(game, avatar_run: bool = false):
	var script: GDScript = load("res://scripts/sim/orientation.gd")
	var module = script.new()
	module.avatar = avatar_run
	game.scenario = module
	module.setup(game)
	# the lesson is scripted: nobody's mood moves and no radio card is drawn
	game.storyteller.enabled = false
	game.morale.enabled = false
	game.relations.enabled = false
	game.specialists.enabled = false
	game.initiative.enabled = false
	var waves := OrientationWaves.new()
	game.waves = waves
	waves.setup(game)
	var medical := OrientationMedical.new()
	game.medical = medical
	medical.setup(game)
	return module


## Installs it and starts the run on the fixed seed, on Story difficulty. `avatar_run`: the avatar's Orientation Day, which
## also puts the town on (G opens the board, as in a real run). The caller makes the player (`game.avatar.set_player`).
static func begin(game, avatar_run: bool = false):
	var module = install(game, avatar_run)
	game.start_run(0, SEED)
	if avatar_run:
		module.stage_town()
	return module


## Whether `data` (a save as SaveGame.read gives it) is an Orientation Day save.
static func is_save(data: Dictionary) -> bool:
	var modules = data.get("modules")
	if typeof(modules) != TYPE_DICTIONARY:
		return false
	var mine = modules.get("scenario")
	return typeof(mine) == TYPE_DICTIONARY and String(mine.get("kind", "")) == "orientation"


## Whether `module` (a sim's scenario) is Orientation Day.
static func is_orientation(module) -> bool:
	return module != null and module.has_method("fire") and module.has_method("jump")


# ----------------------------------------------------------------- the run --

func start() -> void:
	fired = {}
	step = 0
	coach_state = {}
	coached = false
	finished = false
	prepared = false
	stray_open = false
	stray_kills = 0
	stray_tries = 0
	sim.difficulty = 0
	sim.permadeath = false
	sim.stock.ammo = START_AMMO
	var waves = sim.waves
	waves.enabled = false
	if waves.get("scripted") != null:
		waves.scripted = true
	var bus = _segment(BUS_ID)
	if bus != null and not avatar:
		bus.hp = bus.max_hp * BUS_START
		sim._segment_state(bus)
	# Ruth starts out in the yard, in view: the first lesson sends her across it, and when she is
	# let go she walks back to the radio
	var ruth = _person("ruth")
	if ruth != null:
		ruth.x = RUTH_AT.x
		ruth.y = RUTH_AT.y
		ruth.goal_key = ""


## Every step: the safety nets (see the top of the file), the first-step tidying, and
## with no coach the beats that are due.
func update(_dt: float) -> void:
	_safety()
	# nobody mends a wall unasked while the lesson is on (not even as a chore): the lesson is to ask
	sim.tactics.chores = finished
	_prepare()
	if avatar and not finished:
		_keep_stray()
	if finished or coached:
		return
	for beat in BEATS:
		if not fired.has(beat.id) and sim.clock_min >= float(beat.at):
			fire(String(beat.id))


## What is put right once, before the first lesson that needs it (by the first step of the rules, or by a
## jump, which starts a lesson in the middle: the rules may not step at all before the duty roster's page,
## because the card holds the game): the jobs that would work on their own are off, so the lessons are to
## ask: nobody is on the wall crew, the bench or the garden (the radio desk, the lookout post and the
## infirmary change nothing the lessons measure, and the lookout's forecast is a lesson). A lesson that is
## over by then (it was skipped before the rules ever stepped) leaves the crew its jobs.
func _prepare() -> void:
	if prepared:
		return
	prepared = true
	if finished:
		return
	for id in ["dez", "walt", "hector"]:
		var p = _person(id)
		if p != null:
			sim.jobs.unassign(p)
	sim.tactics.auto_jobs.clear()


## It cannot be lost: nobody dies or turns or leaves, no wall falls, no trip goes wrong.
func _safety() -> void:
	sim.permadeath = false
	for s in sim.segments:
		var floor_hp: float = s.max_hp * (0.41 if s.state == 3 else WALL_FLOOR)
		if s.hp < floor_hp:
			s.hp = floor_hp
			sim._segment_state(s)
	var latest: float = sim.clock_min + TURN_MARGIN_MIN
	for p in sim.people:
		if p.infected_at >= 0.0 and p.turn_at >= 0.0 and p.turn_at < latest:
			p.turn_at = latest + TURN_MARGIN_MIN
	sim.medical.sendouts.clear()
	for party in sim.scavenge.parties:
		var result: Dictionary = party.result
		if not result.is_empty():
			result["lost"] = []
			result["hurt"] = {}
			if result.get("loot", {}).is_empty():
				result["loot"] = MERCY_LOOT.duplicate()


# ---------------------------------------------------------------- the beats --

## The ids of the beats.
func beat_ids() -> Array:
	var ids: Array = []
	for beat in BEATS:
		ids.append(String(beat.id))
	if avatar:
		ids.append_array(AVATAR_BEATS)
	return ids


## Whether the beat has happened.
func has_fired(id: String) -> bool:
	return fired.has(id)


## Brings a beat now: false (and nothing happens) if it already has or there is no such
## beat. "dusk" and "more" send the dead, "scratch" and "fever" hurt someone.
func fire(id: String) -> bool:
	if fired.has(id) or not beat_ids().has(id):
		return false
	fired[id] = true
	match id:
		"dusk":
			_send_dead(DUSK_AT, DUSK_WALL, "horde-a", "Walkers at the gate", "Three are coming from the north")
		"more":
			_send_dead(MORE_AT, MORE_WALL, "horde-b", "More are coming", "Four, from the north east")
		"scratch":
			_scratch(SCRATCHED)
			if avatar:
				sim.medical._assign()    # (Ana is on her way to him at once: the lesson has the game held, so no step would send her)
		"fever":
			_infect(FEVERISH)
		"stray":
			_stray()
		"spent":
			_spent()
		"assault":
			_assault()
		"home":
			_home()
	return true


## The script is over: no more beats, and the real nights begin.
func finish() -> void:
	finished = true
	stray_open = false
	coached = false
	sim.waves.enabled = true
	if sim.waves.get("scripted") != null:
		sim.waves.scripted = false


func _send_dead(points: Array, wall_id: int, alert_id: String, title: String, sub: String) -> void:
	var wall = _segment(wall_id)
	for pt in points:
		var z = sim.spawn(float(pt[0]), float(pt[1]), "approach")
		if wall != null:
			sim.assign_slot(z, wall)
	var at = wall.center if wall != null else null
	sim.alert(alert_id, "warn", title, sub, at, 12.0)


func _scratch(id: String) -> void:
	var p = _person(id)
	if p == null or p.dead or p.downed or p.away != null:
		return
	sim.medical.add_wound(p, "scratch")
	sim.fx.blood(p.x, p.y - 0.25, 0.0, 1.0, 5)
	sim.alert("scratch-%s" % p.id, "warn", "%s was scratched" % p.first, "It bleeds until it is bandaged", Vector2(p.x, p.y), 12.0)


## Infected FEVER_AGO_H hours ago, so the fever shows at once (the medical module
## says so), and the turn is days off.
func _infect(id: String) -> void:
	var p = _person(id)
	if p == null or p.dead or p.away != null or p.infected_at >= 0.0:
		return
	p.infected_at = maxf(0.0, sim.clock_min - FEVER_AGO_H * 60.0)
	p.turn_at = p.infected_at + TURN_AFTER_H * 60.0


# ------------------------------------------------- the avatar's lesson --

## The avatar's lesson is played in a town: the board that G opens, as in a real run (the six people, no recruits, no lots,
## and nothing of the streets: no dead about them by day).
func stage_town() -> void:
	sim.town.begin(true)
	sim.streets.enabled = false


## One walker comes to the bus wall from the north lane. The lesson is the player's own shot, so it is put again (a few times)
## while nobody has been shot by the player and nothing of the dead is left coming.
func _stray() -> void:
	stray_open = true
	stray_tries = 0
	var me = sim.avatar.player()
	stray_kills = int(me.stats.kills) if me != null else 0
	_put_stray()


func _put_stray() -> void:
	_send_dead([STRAY_AT], STRAY_WALL, "stray", "A walker at the north wall", "Shoot it from the walkway")


## While the lesson is open: the player's first kill closes it; else a walker that was taken by something else is put again.
func _keep_stray() -> void:
	if not stray_open:
		return
	var me = sim.avatar.player()
	if me == null or int(me.stats.kills) > stray_kills:
		stray_open = false
		return
	if stray_tries >= STRAY_TRIES:
		return
	for z in sim.zombies:
		if z.state == "approach" or z.state == "attack" or z.state == "hunt" or z.state == "breach":
			return
	stray_tries += 1
	_put_stray()


## Two of the dead are at a wall section, clawing: the radio's call (the real one, with its words and its three answers) is
## there at once, before any step of the rules (the lesson has the game held until it is answered).
func _assault() -> void:
	var seg = _segment(ASSAULT_WALL)
	if seg == null:
		return
	for i in mini(ASSAULT_N, seg.slots.size()):
		var sl = seg.slots[i]
		var z = sim.spawn(sl.x, sl.y, "attack")
		z.slot = sl
		sl.who = z
		z.facing = sl.face
		z.attack_t = 0.0
	sim.radio._watch_the_walls()    # (it notes how strong the wall is, then the first blow lands and it calls)
	seg.hp = maxf(0.0, seg.hp - 2.0)
	sim._segment_state(seg)
	sim.radio._watch_the_walls()


## The player's magazine is left low (a third full, one round at least) and no reload is on: R has something to do.
func _spent() -> void:
	stray_open = false
	var me = sim.avatar.player()
	if me == null or me.gun.get("melee", false):
		return
	me.reloading = 0.0
	me.mag = clampi(int(floor(float(me.gun.get("mag", 0)) * SPENT_SHARE)), 1, maxi(1, int(me.gun.get("mag", 1)) - 1))


## Everyone is back to what they were doing: no stance is held, and a call that waits for an answer is answered by its default.
func _home() -> void:
	sim.radio.pending.clear()
	for p in sim.people:
		sim.radio.clear_stance(p)
	for e in sim.radio.open_calls():
		sim.radio._settle(e, String(e.default), true)


# --------------------------------------------------- setting the scene up --

## Puts the world the way a lesson expects it, for starting the tutorial at a step
## (a screenshot, a test): `spec` may hold "hour" (0 to 24) and "day", "bus" (the
## bus's health, 0 to 1), "stock" ({store: amount}), "drafted" (ids sent to stand
## where they are), "post" (ids sent to their posts and standing there) and "fired"
## (beats to bring); and in the avatar's lesson "at" ([x, y]: where the player stands) and "mag" (the rounds left in their
## gun). Nothing in a normal run calls it.
func jump(spec: Dictionary) -> void:
	if spec.has("hour"):
		set_time(float(spec.hour), int(spec.get("day", sim.day)))
	if spec.has("bus"):
		var bus = _segment(BUS_ID)
		if bus != null:
			bus.hp = bus.max_hp * clampf(float(spec.bus), 0.0, 1.0)
			sim._segment_state(bus)
	var stock = spec.get("stock", {})
	if typeof(stock) == TYPE_DICTIONARY:
		for k in stock:
			sim.stock[String(k)] = float(stock[k])
	for id in spec.get("drafted", []):
		var p = _person(String(id))
		if p != null and not p.drafted:
			sim.toggle_draft(p)
	for id in spec.get("post", []):
		var p = _person(String(id))
		if p != null:
			sim.order_post(p)
			p.x = float(p.def.post.x)
			p.y = float(p.def.post.y)
	for id in spec.get("fired", []):
		fire(String(id))
	var me = sim.avatar.player() if avatar else null
	if me != null:
		var at = spec.get("at")
		if typeof(at) == TYPE_ARRAY and at.size() == 2:
			me.x = float(at[0])
			me.y = float(at[1])
			me.path = []
			me.moving = false
		if spec.has("mag") and not me.gun.get("melee", false):
			me.mag = clampi(int(spec.mag), 0, int(me.gun.get("mag", 0)))
	_prepare()


## Sets the time of day (and the day), the way the `--hour` flag does: the phase, the bell
## and the game clock follow.
func set_time(hour: float, day: int = 1) -> void:
	sim.day = maxi(day, 1)
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	# the rules' day turns over at 06:30, and the clock counts from 07:00 on day 1
	var into: float = sim.minutes - 420.0
	sim.clock_min = float(sim.day - 1) * 1440.0 + into if sim.minutes >= 390.0 else float(sim.day) * 1440.0 + into


# --------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {
		"kind": "orientation",
		"step": step,
		"fired": fired.keys(),
		"prepared": prepared,
		"coached": coached,
		"finished": finished,
		"avatar": avatar,
		"stray": [stray_open, stray_kills, stray_tries],
		"coach": coach_state.duplicate(true),
	}


func load_state(d: Dictionary) -> void:
	if String(d.get("kind", "")) != "orientation":
		return
	step = int(d.get("step", 0))
	fired = {}
	var ids = d.get("fired", [])
	if typeof(ids) == TYPE_ARRAY:
		for id in ids:
			fired[String(id)] = true
	prepared = bool(d.get("prepared", true))
	coached = bool(d.get("coached", false))
	finished = bool(d.get("finished", false))
	avatar = bool(d.get("avatar", false))
	if avatar:
		sim.streets.enabled = false    # (the harness's switch is not saved)
	stray_open = false
	stray_kills = 0
	stray_tries = 0
	var stray = d.get("stray", [])
	if typeof(stray) == TYPE_ARRAY and stray.size() == 3:
		stray_open = bool(stray[0])
		stray_kills = int(stray[1])
		stray_tries = int(stray[2])
	var kept = d.get("coach", {})
	coach_state = kept.duplicate(true) if typeof(kept) == TYPE_DICTIONARY else {}
	sim.waves.enabled = finished
	if sim.waves.get("scripted") != null:
		sim.waves.scripted = not finished


# ------------------------------------------------------------------ helpers --

func _segment(id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


func _person(id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null
