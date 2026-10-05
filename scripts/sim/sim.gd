## The simulation: the clock, the six people, the dead, and the wall.
## Everything is in tile units; one tile is roughly a metre.
extends RefCounted

const Pathfinder := preload("res://scripts/sim/pathfinder.gd")
const Supplies := preload("res://scripts/sim/supplies.gd")
const Medical := preload("res://scripts/sim/medical.gd")
const Scavenge := preload("res://scripts/sim/scavenge.gd")
const Scenario := preload("res://scripts/sim/scenario.gd")
const Waves := preload("res://scripts/sim/waves.gd")
const Tactics := preload("res://scripts/sim/tactics.gd")
const Workshop := preload("res://scripts/sim/workshop.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const Morale := preload("res://scripts/sim/morale.gd")
const Bonds := preload("res://scripts/sim/bonds.gd")
const Skills := preload("res://scripts/sim/skills.gd")
const Barks := preload("res://scripts/sim/barks.gd")
const Storyteller := preload("res://scripts/sim/storyteller.gd")
const Jobs := preload("res://scripts/sim/jobs.gd")
const Build := preload("res://scripts/sim/build.gd")
const Recruits := preload("res://scripts/sim/recruits.gd")
const Town := preload("res://scripts/sim/town.gd")
const Lots := preload("res://scripts/sim/lots.gd")
const Seasons := preload("res://scripts/sim/seasons.gd")
const Streets := preload("res://scripts/sim/streets.gd")
const Nights := preload("res://scripts/sim/nights.gd")
const Vehicles := preload("res://scripts/sim/vehicles.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")
const Radio := preload("res://scripts/sim/radio.gd")
const Relations := preload("res://scripts/sim/relations.gd")
const Specialists := preload("res://scripts/sim/specialists.gd")
const Initiative := preload("res://scripts/sim/initiative.gd")
const Briefing := preload("res://scripts/sim/briefing.gd")
const Priorities := preload("res://scripts/sim/priorities.gd")
const Policies := preload("res://scripts/sim/policies.gd")
const Problems := preload("res://scripts/sim/problems.gd")
const Dilemmas := preload("res://scripts/sim/dilemmas.gd")
const Avatar := preload("res://scripts/sim/avatar.gd")
const Interact := preload("res://scripts/sim/interact.gd")
const Gate := preload("res://scripts/sim/gate.gd")
const Levels := preload("res://scripts/sim/levels.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")

## What a new run starts with (tuned later with the balance harness). Food and
## water are six days of full rations for the crew of six (6 x 1 x 6 food, 6 x
## 1.5 x 6 water): with no income the first person is hungry or thirsty on day 7.
const START_STOCK := {"ammo": 400.0, "scrap": 40.0, "food": 36.0, "water": 54.0, "meds": 10.0}
## The story, standard and brutal difficulties.
const DIFFICULTY_NAMES := ["Story", "Standard", "Brutal"]

## What one shot costs from the stock of ammo (a shotgun shell is a bigger share).
const SHOT_COST := 0.2
const SHELL_COST := 0.34
## A repair mends this many health points a second plus the repairer's Building
## skill (Dez 14, Marcus 6): it was a flat 9.
const REPAIR_BASE := 5.0
## The school's two north doors are wall sections of this kind. The building is
## shut to the dead until one is broken (see `refresh_school`).
const DOOR_KIND := "door"
## The school's tiles start at this row (its north wall).
const SCHOOL_TOP_ROW := 44
## The most of the dead sent back to the city in one step at dawn (each one is a
## path search).
const DAWN_LEAVES_PER_STEP := 6
## In a game with lots a retreating one of the dead is gone this near the spawn point it is walking to.
const RETREAT_DONE := 1.2
## What someone fights with when the stock cannot pay for another shot: the butt
## of their gun.
const BUTT := {"name": "Butt of the gun", "range": 1.9, "cooldown": 1.25, "melee": true, "dmg": 1.1, "acc": 0.7}

const PIVOT := {"S": Vector2(-0.04, -0.08), "E": Vector2(0.08, -0.14), "N": Vector2(0.26, -0.22)}

## Work life (round 16, the settlement game only). The compound is this rectangle of the map (the walls' outer
## edges: the north wall's walkway, the two side walkways and the school's front). The dead are a threat by day
## when one that is coming to the wall (approach, attack) or already in (breach) is within THREAT_R tiles of it,
## or the alarm rings; the crew goes to its posts then, and back to work once it has been quiet for
## THREAT_QUIET_MIN game minutes. At dawn the crew holds its posts only while some of the dead are still coming at
## the compound (the dawn sends them all back to the city in the first moments, so the dawn hour is work time).
## Someone is at work, for `Person.work`, when they stand within WORK_REACH tiles of the spot.
const COMPOUND := Rect2(20.0, 18.0, 44.0, 26.0)
const THREAT_R := 16.0
## (45 game minutes is fifteen real seconds at the normal speed: long enough to see the crew hold its posts, short enough that
## the day is not lost.)
const THREAT_QUIET_MIN := 45.0
const WORK_REACH := 0.6

## The colony goes on while the player is in a place (round 17): the place is stepped at 30 steps a second and the colony
## takes one step (of the same 1/30 s) for this many of them, which is one game minute per real second at the normal
## `min_per_sec` of 3 (an hour in a place is a minute of the day's twenty). `background_steps_for` is the helper the scene
## uses; `fast_forward` runs the colony quickly for the road there and back.
const PLACE_STEP_RATIO := 3
## The events that are only a sound or a picture and nothing else reads (main.gd plays them): `fast_forward` drops them
## after each step, so a long run of colony steps does not leave thousands of them to be played at once.
const FAST_FORWARD_NOISE := ["shot", "groan", "claw", "hammer", "stab", "thud", "reload"]


class Slot:
	extends RefCounted
	var x: float
	var y: float
	var ax: float
	var ay: float
	var face: String
	var who = null
	var seg = null


class Segment:
	extends RefCounted
	var id: int
	var kind: String
	var side: String
	var from: float
	var to: float
	var name: String
	var hp: float
	var max_hp: float
	var state := 0
	var tiles: Array = []
	var center := Vector2.ZERO
	var slots: Array = []
	var obj: Dictionary
	## The pictures of a wall section made in play (round 9, lots): its four damage states, each a list of
	## {file, x, y, w, h} in tiles. The map's own sections have theirs in their object.
	var art: Array = []


class Person:
	extends RefCounted
	var def: Dictionary
	var id: String
	var name: String
	var first: String
	var look: Dictionary
	var weapon: String
	var gun: Dictionary
	var x: float
	var y: float
	var facing := "S"
	var hp := 100.0
	var mag := 0
	var cooldown := 0.0
	var reloading := 0.0
	var aim := 0.0
	var target = null
	var path: Array = []
	var path_i := 0
	var goal_key := ""
	var moving := false
	var walk_phase := 0.0
	var drafted := false
	var order = null
	var repair = null
	var activity := ""
	## What they are doing at their spot right now ("" when walking or at nothing: see jobs.gd, `work` of a goal) and
	## for how many seconds (round 16, read by the drawing; the rules set it each step, so a save from before has none
	## and it is worked out again at once; the save's reflection keeps it like any other variable of the person).
	var work := ""
	var work_t := 0.0
	var recoil := 0.0
	var thrust := 0.0
	var downed := false
	var hammer_t := 0.0
	## Died (bled out, starved...) or turned: out of the game for good.
	var dead := false
	var turned := false
	## Game hours since they last ate a proper meal or drank.
	var hunger_h := 0.0
	var thirst_h := 0.0
	## Health lost per game hour from open wounds, and how many wounds are open.
	var bleeding := 0.0
	var wounds := 0
	## Game hours left to be stabilised while downed, or -1 when that does not apply.
	var bleed_out := -1.0
	var stabilised := false
	## When (in sim.clock_min game minutes) they were infected and will turn, or -1.
	var infected_at := -1.0
	var turn_at := -1.0
	## Where they are healing in bed (a Vector2), or null.
	var resting_bed = null
	## The scavenging party they are away with (they are off the map), or null.
	var away = null
	## Their own copy of the roster's skills, which grow with use (skills.gd): the rules
	## read these, never `def.skills`.
	var skills: Dictionary = {}
	## What they have done: kills, kills_night (since the last dusk), mended (HP), treated,
	## crafted (scrap) and shots.
	var stats: Dictionary = {}
	## The avatar and the radio (round 17, avatar.gd and radio.gd): the one the player controls; how far they trust the
	## player (0 to 100); what they have been asked to do ("", "follow", "hold", "cover", "search") and where to hold.
	var player := false
	var trust := 55.0
	var stance := ""
	var stance_at := Vector2.ZERO
	## What the player's hands ask of the avatar, set by the views every frame (avatar.gd, `set_input`): the walking
	## direction (a vector; its length does not matter), the point of the world (tiles) the mouse is over, the trigger,
	## and the two one-shot keys (reload, melee: taken at the next step). `melee_t` is the swing's cooldown and `bloom`
	## the spread that sustained fire builds up and a pause lets go.
	var input_move := Vector2.ZERO
	var input_aim := Vector2.ZERO
	var input_fire := false
	var input_reload := false
	var input_melee := false
	var melee_t := 0.0
	var bloom := 0.0
	## Round 23: the player has put the weapon away (Q): the view says so every frame, and only the drawing reads it (the pawn carries the gun low
	## and slack, with the hands off it). The rules never read it: with it set the view sends no aim and no trigger. Not saved.
	var holstered := false


class Zombie:
	extends RefCounted
	var x: float
	var y: float
	var look: Dictionary
	var look_index := 0
	var state: String
	var hp: float
	var speed: float
	var limp: bool
	var facing := "S"
	var moving := false
	var walk_phase := 0.0
	var t := 0.0
	var path: Array = []
	var path_i := 0
	var slot = null
	var attack_t := 0.0
	var stagger := 0.0
	var fall := 0.0
	var fall_dir := 1.0
	var groan_t := 0.0
	var repath := 0.0
	var wander_t := 0.0
	var dead_t := 0.0
	var remove := false
	## The name of the survivor this used to be, for one who turned.
	var turned_name := ""
	## The survivor a straggler of the streets is hunting by day (their id), while its state is "hunt".
	var hunt_id := ""
	## Walker, runner or brute (see kinds.gd), how big it is drawn, and the damage
	## of its claw on walls as a multiple of a walker's.
	var kind := "walker"
	var size := 1.0
	var claw := 1.0
	## A brute of a Big Night (round 19): armoured but for its head (nights.gd `damage_to`). Saved with the zombie, optional in a save.
	var plated := false


var world
var fx
## The feel of a fight, a render-only sink (scripts/render/combat_fx.gd): told who fired, what was hit and what was killed, and never asked
## anything. null in the tests and the balance harness; nothing it does is read by the rules.
var feel = null
var d: Dictionary
var W: int
var H: int
var path_z
var path_p
var minutes := 18.0 * 60.0 + 46.0
## Game minutes since the run began (never wraps at midnight), for timers.
var clock_min := 0.0
var min_per_sec := 3.0
var day := 3
var phase := "day"
var t := 0.0
var people: Array = []
var zombies: Array = []
var looks: Array = []
var segments: Array = []
var events: Array = []
var alerts := {}
var bell_rung := false
var spawn_t := 6.0
var kills := 0
var stock := {"ammo": 212.0, "scrap": 24.0, "food": 41.0, "water": 230.0, "meds": 7.0}
var on_segment_change: Callable
## A wall section was made or taken away in play (round 9): the world draws or drops its pictures.
var on_segment_added: Callable
var on_segment_removed: Callable
var spawns: Array = []
var guns: Dictionary
var weapons: Dictionary
## The one random source of the rules, seeded per run.
var rng := RandomNumberGenerator.new()
var run_seed := 0
## 0 story, 1 standard, 2 brutal.
var difficulty := 1
## Whether a person who bleeds out dies for good.
var permadeath := true
## "clear" or "rain" (set each dawn by the supplies module).
var weather := "clear"
## "" while the run goes on, then "defeat" or "victory". The rules stop stepping.
var over := ""
var supplies
var medical
var scavenge
var scenario
var waves
var tactics
var workshop
var traits
var morale
var bonds
var skills
var barks
var storyteller
var jobs
var build
var recruits
var town
var lots
var seasons
var streets
## Presence, plating and breaches (round 19, nights.gd): every hook of it is neutral without an avatar (`player_id`) and where
## `nights_on` is false.
var nights
var vehicles
var radio
var relations    # (round 20: who is close to whom)
var specialists    # (round 20: the one to call for a trade)
var initiative    # (round 20: what the community proposes over the radio)
## The base management of round 25 (avatar mode in a small settlement start only; every hook is neutral otherwise): the morning briefing and the evening
## debrief, the priorities the automation weighs (and the standing staffing), the four dials, the trouble that comes up and the fever dilemma.
var briefing
var priorities
var policies
var problems
var dilemmas
var avatar
## What the avatar uses where it stands (round 18, interact.gd): talk, a post, the bench, a car's fuel. Behind avatar mode.
var interact
## The Main gate as a real gate (round 22, gate.gd): opened and shut by the avatar's hands, by the keeper for a car or a party, and by the bell. Avatar
## mode only: `gate.active()` is false with no avatar and the section is the shut wall it always was.
var gate
## The ground and the decks (round 24, levels.gd): which level a person is on, and the solid tiles that keep the two apart. Avatar mode only.
var levels
## The id of the person the player controls ("" = no avatar: the old game, the harness and the tests; every rule of
## the avatar and the radio's news is behind this).
var player_id := ""
## Whether the nights' rules of round 19 (rally, plated brutes, hot breaches: nights.gd) apply in this sim. True in the settlement's own
## sim; a place's sim (raid_sim.gd) sets it false in its own `_init`. They also need an avatar: `Nights.active()`.
var nights_on := true
## How many people a run starts with: 6 (the classic start: tests, Orientation Day) or 3 (a small start:
## the others come over the radio, see recruits.gd). Set before `start_run`.
var crew_start := 6


## Whether this run is the demo (round 26: three nights, a short list of buildings and places, no dials, no trouble: scripts/sim/demo_run.gd is
## its scenario and the only thing that says so). Every part of the full game that the demo changes asks this, and answers as ever when it is false.
func is_demo() -> bool:
	return scenario != null and scenario.has_method("is_demo")


## One House hooks (scripts/town/town_rules.gd overrides them for the town; in every other game each answers as the school always did).
## Whether this is the One House town (a generated base, no school, no lots).
func is_one_house() -> bool:
	return false


## The middle of the base: where the night is "from" and the dead walk to when a wall is lost (the school's compound).
func base_center() -> Vector2:
	return Vector2(42.0, 32.0)


## Where the dead make for once they are in (the middle of the yard, where the stores are).
func yard_middle() -> Vector2:
	return nights.YARD_MIDDLE


## Whether the bell turns the wanderers of the streets into attackers.
func _wanderers_rally() -> bool:
	return true


## Whether the gate stands open to the dead (the school's gate), and whether this wall section is that gate.
func _any_gate_open() -> bool:
	return gate.lets_dead_in()


func _is_open_gate(s) -> bool:
	return int(s.id) == gate.SEGMENT


## When the `i`th of a night's `n` dead is let in, in seconds from the start of the dusk, as the forecast (`Waves._arrival_seconds`) works it out: `seconds` is the school's own
## answer (the dusk's single ones, then groups, spread over the night). The town's nights come in surges and answer for them (town_rules.gd).
func wave_let_in(_i: int, _n: int, seconds: float) -> float:
	return seconds


## How many of the dead count against the night's cap (`Waves.update`): all that are alive.
func alive_for_cap() -> int:
	var alive := 0
	for z in zombies:
		if z.state != "dead" and z.state != "dying":
			alive += 1
	return alive
## Whether the school's inside is open to the dead right now: a door is down or one
## of the dead is already in there.
var school_open := false
## The ground's connected stretches for the dead (see `region_at`), worked out when asked after a change.
var _regions := PackedInt32Array()
var _regions_dirty := true
var _school_inner: Array = []


func _init(data: Dictionary, w, effects) -> void:
	d = data
	world = w
	fx = effects
	W = int(d.W)
	H = int(d.H)
	min_per_sec = float(d.minPerSec)
	guns = d.guns
	weapons = d.weapons
	path_z = Pathfinder.new(W, H, world.solid_z)
	path_p = Pathfinder.new(W, H, world.solid_p)
	phase = phase_at(minutes)
	looks = d.zombieLooks
	for sp in d.spawns:
		spawns.append(Vector2(sp[0], sp[1]))
	for s in d.segments:
		var seg := Segment.new()
		seg.id = int(s.id)
		seg.kind = s.kind
		seg.side = s.side
		seg.from = s.from
		seg.to = s.to
		seg.name = s.name
		seg.hp = s.hp
		seg.max_hp = s.hp
		seg.tiles = s.tiles
		seg.center = Vector2(s.center.x, s.center.y)
		seg.obj = d.objects[_object_index(int(s.obj))]
		for sl in s.slots:
			var slot := Slot.new()
			slot.x = sl.x
			slot.y = sl.y
			slot.ax = sl.ax
			slot.ay = sl.ay
			slot.face = sl.face
			slot.seg = seg
			seg.slots.append(slot)
		segments.append(seg)
	var door_tiles := {}
	for seg in segments:
		if seg.kind == DOOR_KIND:
			for i in seg.tiles:
				door_tiles[int(i)] = true
	for i in W * H:
		@warning_ignore("integer_division")
		if int(d.solidZ[i]) == 1 and int(d.solidP[i]) == 0 and i / W >= SCHOOL_TOP_ROW and not door_tiles.has(i):
			_school_inner.append(i)
	for def in d.people:
		people.append(_make_person(def))
	supplies = Supplies.new()
	medical = Medical.new()
	scavenge = Scavenge.new()
	scenario = Scenario.new()
	waves = Waves.new()
	tactics = Tactics.new()
	workshop = Workshop.new()
	traits = Traits.new()
	morale = Morale.new()
	bonds = Bonds.new()
	skills = Skills.new()
	barks = Barks.new()
	storyteller = Storyteller.new()
	jobs = Jobs.new()
	build = Build.new()
	recruits = Recruits.new()
	town = Town.new()
	lots = Lots.new()
	seasons = Seasons.new()
	streets = Streets.new()
	nights = Nights.new()
	vehicles = Vehicles.new()
	radio = Radio.new()
	radio.setup(self)
	relations = Relations.new()
	relations.setup(self)
	specialists = Specialists.new()
	specialists.setup(self)
	initiative = Initiative.new()
	initiative.setup(self)
	briefing = Briefing.new()
	briefing.setup(self)
	priorities = Priorities.new()
	priorities.setup(self)
	policies = Policies.new()
	policies.setup(self)
	problems = Problems.new()
	problems.setup(self)
	dilemmas = Dilemmas.new()
	dilemmas.setup(self)
	avatar = Avatar.new()
	avatar.setup(self)
	interact = Interact.new()
	interact.setup(self)
	gate = Gate.new()
	gate.setup(self)
	levels = Levels.new()
	levels.setup(self)
	for m in [supplies, medical, scavenge, scenario, waves, tactics, workshop, traits, morale, bonds, skills, barks, storyteller, build, jobs, recruits, town, lots, seasons, streets, nights, vehicles]:
		m.setup(self)
	_seed()


func _object_index(id: int) -> int:
	for i in d.objects.size():
		if int(d.objects[i].id) == id:
			return i
	return 0


## A person made from a roster entry (the recruits' defs are shaped like one), not yet in the crew.
func make_person(def: Dictionary) -> Person:
	return _make_person(def)


## Someone joins the crew mid-run (a recruit at the gate): made, added, and the modules that keep a
## state for each person told.
func add_person(def: Dictionary) -> Person:
	var p := _make_person(def)
	people.append(p)
	for m in [morale, traits, bonds, jobs, skills, relations, specialists, priorities, policies]:
		if m.has_method("person_added"):
			m.person_added(p)
	return p


func _make_person(def: Dictionary) -> Person:
	var p := Person.new()
	p.def = def
	p.id = def.id
	p.name = def.name
	p.first = def.name.split(" ")[0]
	p.look = def.look
	p.weapon = def.weapon
	p.gun = weapons[def.weapon]
	p.x = def.job.x
	p.y = def.job.y
	p.mag = int(p.gun.get("mag", 0))
	p.cooldown = rng.randf()
	p.aim = guns[def.weapon].rest
	p.walk_phase = rng.randf() * 6.0
	p.activity = def.job.what
	p.skills = Skills.copy_of(def.skills)
	p.stats = Skills.new_stats()
	return p


var hour: float:
	get:
		return fmod(minutes / 60.0, 24.0)


static func phase_at(mins: float) -> String:
	var h := fmod(mins / 60.0, 24.0)
	if h >= 19.0 and h < 20.5:
		return "dusk"
	if h >= 20.5 or h < 5.5:
		return "night"
	if h < 6.5:
		return "dawn"
	return "day"


static func facing_of(dx: float, dy: float, prev: String = "") -> String:
	var ax := absf(dx)
	var ay := absf(dy)
	if (prev == "E" or prev == "W") and ax > ay * 0.8:
		return "E" if dx > 0 else "W"
	if (prev == "N" or prev == "S") and ay > ax * 0.8:
		return "S" if dy > 0 else "N"
	if ax > ay:
		return "E" if dx > 0 else "W"
	return "S" if dy > 0 else "N"


static func ang_diff(a: float, b: float) -> float:
	return atan2(sin(b - a), cos(b - a))


func _seed() -> void:
	for pair in [[1, 1], [2, 1], [2, 4], [7, 1], [11, 2], [0, 6]]:
		var sl: Slot = segments[pair[0]].slots[pair[1]]
		var z := spawn(sl.x, sl.y, "attack")
		z.slot = sl
		sl.who = z
		z.facing = sl.face
	for p in [[24, 9], [33.5, 11.4], [41, 7.4], [52, 10.2], [58.5, 8.4], [9, 27], [74.5, 27]]:
		spawn(p[0], p[1], "approach")
	for p in [[7.5, 47], [76.5, 45], [3.6, 8.6], [80, 8.2], [66, 7.2]]:
		spawn(p[0], p[1], "wander")


func spawn(x: float, y: float, state: String, kind: String = "walker") -> Zombie:
	var z := Zombie.new()
	z.x = x
	z.y = y
	z.look_index = rng.randi() % looks.size()
	z.look = looks[z.look_index]
	z.state = state
	var k: Dictionary = Kinds.KINDS[kind]
	z.kind = kind
	z.size = float(k.size)
	z.claw = float(k.claw)
	z.hp = int(k.hp[0]) + rng.randi() % (int(k.hp[1]) - int(k.hp[0]) + 1)
	z.speed = float(k.speed[0]) + rng.randf() * (float(k.speed[1]) - float(k.speed[0]))
	z.limp = rng.randf() < 0.4 and kind == "walker"
	z.walk_phase = rng.randf() * 6.0
	z.t = rng.randf() * 10.0
	z.attack_t = rng.randf()
	z.groan_t = 2.0 + rng.randf() * 10.0
	zombies.append(z)
	return z


func alert(id: String, level: String, text: String, sub: String, at, ttl: float = 5.0) -> void:
	var born := t
	if alerts.has(id):
		born = alerts[id].born
	alerts[id] = {"id": id, "level": level, "text": text, "sub": sub, "at": at, "t": t, "ttl": ttl, "born": born}


# ------------------------------------------------------------------ orders --

func toggle_draft(p: Person) -> void:
	if morale.breakdown(p) or p.player:
		return
	p.drafted = not p.drafted
	p.repair = null
	p.order = Vector3(p.x, p.y, 0) if p.drafted else null


func order_move(p: Person, x: float, y: float) -> bool:
	if p.downed or p.dead or p.away != null or morale.breakdown(p) or p.player:
		return false    # (nobody orders the player about: they walk by their own hands, avatar.gd)
	if world.is_solid(world.solid_p, x, y):
		return false
	p.drafted = true
	p.repair = null
	p.order = Vector3(x, y, 0)
	p.goal_key = ""
	return true


func order_post(p: Person) -> void:
	if morale.breakdown(p) or p.player:
		return
	p.drafted = true
	p.repair = null
	var at: Vector2 = jobs.post_pos(p)
	p.order = Vector3(at.x, at.y, 1)
	p.goal_key = ""


func order_repair(p: Person, seg: Segment) -> void:
	if morale.breakdown(p) or p.player:
		return
	p.drafted = false
	p.order = null
	p.repair = seg
	p.goal_key = ""
	tactics.forget_trip(p)    # this repair is an order now (the wall crew sets its own mark after sending someone)


## How well a person does things right now (shooting, repairing): 1.0 normal,
## less when hungry, thirsty or hurt.
func perf(p: Person) -> float:
	return supplies.perf(p) * medical.perf(p) * morale.perf(p) * storyteller.perf(p) * policies.perf_mult(p) * problems.perf_mult(p)


## How much a person's traits, company and mood change their aim right now (1.0 normally): a
## trait (Sharp-eyed, Nervous among a crowd of the dead), a friend close by (see bonds.gd) and
## being Shaken (see morale.gd).
func aim_factor(p: Person) -> float:
	return traits.mult(p, "aim") * (1.0 + bonds.aim_bonus(p)) * morale.aim_mult(p) * nights.aim_mult(p)


## Small status marks for a person's card and panel, from every module:
## [{"icon": String, "color": Color, "tip": String}].
func status_of(p: Person) -> Array:
	return supplies.status_of(p) + medical.status_of(p) + scavenge.status_of(p) + workshop.status_of(p) + morale.status_of(p) + storyteller.status_of(p)


## Game hours that pass in `dt` seconds of the rules' time.
func game_hours(dt: float) -> float:
	return dt * min_per_sec / 60.0


## A button the HUD offers for the selection (see the modules' gizmo()):
## true if a module took it.
func handle_gizmo(id: String, sel) -> bool:
	for m in [medical, scavenge, supplies, scenario, tactics, workshop, jobs]:
		if m.has_method("gizmo") and m.gizmo(id, sel):
			return true
	return false


## Sets up a fresh run on a newly built Sim: day 1 at 07:00, the starting
## stocks, a quiet yard, the seed and difficulty.
func start_run(difficulty_index: int, seed_value: int) -> void:
	difficulty = clampi(difficulty_index, 0, 2)
	run_seed = seed_value
	rng.seed = seed_value
	# what _make_person rolled before the seed was set
	for p in people:
		p.cooldown = rng.randf()
		p.walk_phase = rng.randf() * 6.0
	day = 1
	minutes = 7.0 * 60.0
	clock_min = 0.0
	phase = phase_at(minutes)
	bell_rung = false
	spawn_t = 6.0
	kills = 0
	over = ""
	weather = "clear"
	stock = START_STOCK.duplicate()
	events.clear()
	alerts.clear()
	zombies.clear()
	for seg in segments:
		for sl in seg.slots:
			sl.who = null
	for pos in [[7.5, 47], [76.5, 45], [3.6, 8.6], [80, 8.2]]:
		spawn(pos[0], pos[1], "wander")
	for m in [seasons, supplies, medical, scavenge, scenario, waves, tactics, workshop, traits, morale, bonds, skills, barks, storyteller, build, jobs, recruits, town, lots, streets, nights, vehicles]:
		m.start()
	radio.start()
	relations.start()
	specialists.start()
	initiative.start()
	policies.start()
	priorities.start()
	problems.start()
	dilemmas.start()
	briefing.start()
	avatar.start()
	interact.start()
	gate.start()
	levels.start()
	recruits.begin()
	town.begin()
	lots.begin()


# ------------------------------------------------------------------ update --

func update(dt: float) -> void:
	if over != "":
		return
	t += dt
	var before := phase
	minutes += dt * min_per_sec
	clock_min += dt * min_per_sec
	if minutes >= 24.0 * 60.0:
		minutes -= 24.0 * 60.0
	phase = seasons.phase_at(minutes)
	var h := hour
	if not bell_rung and h >= seasons.dusk_hour() and h < seasons.dusk_hour() + seasons.DUSK_H:
		bell_rung = true
		events.append({"type": "bell"})
		events.append({"type": "banner", "text": "The bell rings", "sub": "Everyone to the wall"})
		alert("bell", "info", "The bell has rung", "Everyone is heading to their posts", null, 14.0)
		skills.on_bell()
		barks.on_bell()
	if before != phase:
		if phase == "night":
			events.append({"type": "banner", "text": "Night %d" % day, "sub": "Hold the wall until dawn"})
			alert("horde", "warn", "The dead are coming", "More walkers every hour until dawn", null, 12.0)
		elif phase == "dawn":
			events.append({"type": "banner", "text": "Dawn", "sub": "The dead drift back into the city"})
		elif phase == "dusk":
			seasons.on_dusk()
		elif phase == "day":
			day += 1
			bell_rung = false
			seasons.on_new_day()
			streets.on_dawn()
			events.append({"type": "day_start", "day": day})
			events.append({"type": "banner", "text": "Day %d" % day, "sub": "Repair the wall before dusk"})
	_update_threat()

	scenario.update(dt)
	supplies.update(dt)
	medical.update(dt)
	scavenge.update(dt)
	waves.update(dt)
	tactics.update(dt)
	workshop.update(dt)
	morale.update(dt)
	barks.update(dt)
	storyteller.update(dt)
	jobs.update(dt)
	build.update(dt)
	recruits.update(dt)
	town.update(dt)
	lots.update(dt)
	streets.update(dt)
	# the gate (round 22, avatar mode only): after the trips and the callers have asked for it, before the people and the dead move
	gate.update(dt)
	levels.update(dt)    # (round 24: who is on the bridge, on which level; the solid tiles that keep the decks and the ground apart)
	nights.update(dt)

	if phase == "dawn":
		_dawn_sweep()
	for p in people:
		_update_person(p, dt)
	for z in zombies:
		_update_zombie(z, dt)
	refresh_school()
	_separate()
	var kept: Array = []
	for z in zombies:
		if not z.remove:
			kept.append(z)
	zombies = kept
	for id in alerts.keys():
		var a: Dictionary = alerts[id]
		if t - a.t > a.ttl:
			alerts.erase(id)
	# what the avatar is using (a post, the bench), after the people have moved (round 18, interact.gd)
	interact.update(dt)
	# the avatar's own hands at a wall, after the people and the dead have moved (round 19, nights.gd)
	nights.after_people(dt)
	# the community: who is close to whom, who is the one to call, what they propose (round 20), then the radio's news and calls
	# from what happened this step (last: it reads the step's events)
	relations.update(dt)
	specialists.update(dt)
	initiative.update(dt)
	policies.update(dt)    # (round 25: the base's management: the dials' weariness, the priorities' staffing, trouble, the dilemma, the briefing)
	priorities.update(dt)
	problems.update(dt)
	dilemmas.update(dt)
	briefing.update(dt)
	radio.update(dt)
	# Orientation Day's floor under the walls holds when the step is over too (the dead strike after the scenario's turn)
	if scenario.has_method("after_step"):
		scenario.after_step()


## Runs the colony `game_minutes` game minutes ahead as quickly as it can: the usual steps of 1/30 s (the last one a short
## one, so the minutes come out exact), no drawing (the effects are a sink meanwhile) and no sounds (the events that are
## only a sound or a picture are dropped after each step, `FAST_FORWARD_NOISE`; the banners, the bell and the rest stay
## for `main.gd`, and the radio's news collects inside `update` as ever). At most `max_steps_per_call` steps are taken
## in one call (200 game minutes at the normal speed with the default; a colony step costs about 0.2 ms, so a scene that
## keeps its frames passes about 60 and calls again next frame with what is left). Returns the game minutes still to go, 0 when it is done or when the run is over (`over`: nothing more can
## happen). A place's scene uses it for the road there and back (the abstract travel until the live drive).
func fast_forward(game_minutes: float, max_steps_per_call: int = 2000) -> float:
	var rate := float(min_per_sec)
	var goal := clock_min + game_minutes
	var left := game_minutes
	if left <= 1.0e-6 or over != "" or rate <= 0.0:
		return 0.0
	var real_fx = fx
	fx = FxNull.new()
	var steps := 0
	while left > 1.0e-6 and steps < max_steps_per_call and over == "":
		update(minf(StepClock.STEP, left / rate))
		steps += 1
		left = goal - clock_min
		for i in range(events.size() - 1, -1, -1):
			if FAST_FORWARD_NOISE.has(String(events[i].get("type", ""))):
				events.remove_at(i)
	fx = real_fx
	if over != "" or left <= 1.0e-6:
		return 0.0
	return left


## How many colony steps a place's scene takes for `raid_steps` steps of the place (see `PLACE_STEP_RATIO`; the scene keeps
## the place steps it has taken in all and asks for the total, so the remainder is never lost).
static func background_steps_for(raid_steps: int) -> int:
	@warning_ignore("integer_division")
	return maxi(raid_steps, 0) / PLACE_STEP_RATIO


# ------------------------------------------------------------------ people --

func _goal_for(p: Person):
	if p.downed or p.dead or p.away != null or morale.breakdown(p):
		return null
	if p.order != null:
		var is_post: bool = p.order.z > 0.5
		return {"x": p.order.x, "y": p.order.y, "face": _post_face(p) if is_post else "", "what": String(jobs.post_of(p).get("what", "Holding the wall")) if is_post else "Holding position"}
	var duty = medical.goal_for(p)
	if duty == null:
		duty = scavenge.goal_for(p)
	if duty == null:
		duty = workshop.goal_for(p)
	if duty != null:
		return duty
	# what the player has asked of them over the radio: follow, hold, cover, search (radio.gd; null with no stance)
	var asked = radio.stance_goal(p)
	if asked != null:
		return asked
	if p.repair != null:
		var s: Segment = p.repair
		var spot := repair_spot(s)
		return {"x": spot.x, "y": spot.y, "face": "N" if s.side == "S" else s.side, "what": "Mending the %s" % s.name.to_lower(), "work": "mend"}
	if posts_manned():
		# (the lookout keeps the tower through a day under attack: the forecast, and the eyes on the road)
		if phase == "day" and jobs.job_of(p) == "watch":
			return jobs.goal_for(p)
		return jobs.post_goal(p)
	return jobs.goal_for(p)


## Whether the crew holds its night posts right now: from the bell (or the dark) through the night and the dawn. In
## the settlement game (a small start) people are at work by day, so the dawn counts as night only while some of the
## dead are still coming at the compound (`_dead_coming`: the dawn turns them back in its first moments, and the dead
## drifting off no longer attack), and a day under attack (`threat_by_day`) puts the crew at its posts as the bell
## does. The classic start has the old rule: the posts from the bell to the end of the dawn.
## Where a person stands to mend a wall piece. In the settlement game by day it is on the yard side of the piece, off any
## deck: the piece's own middle is on the walkway, and nobody is to stand on the wall unless the dead are at it. The nearest
## open ground in from the piece (the scaffold's face under the walkway is shut ground, so it is the first open tile past it).
## The classic start, and a piece made in the streets (a lot's wall, id 100 and over), keep the piece's middle.
func repair_spot(s: Segment) -> Vector2:
	if not recruits.small or s.id >= 100:
		return s.center
	var inner := Vector2.ZERO
	match s.side:
		"N":
			inner = Vector2(0.0, 1.0)
		"S":
			inner = Vector2(0.0, -1.0)
		"W":
			inner = Vector2(1.0, 0.0)
		"E":
			inner = Vector2(-1.0, 0.0)
	if inner == Vector2.ZERO:
		return s.center
	for k in range(1, 61):
		var pt := s.center + inner * (0.25 * float(k))
		var tx := floori(pt.x)
		var ty := floori(pt.y)
		if tx < 0 or ty < 0 or tx >= world.W or ty >= world.H:
			break
		if int(world.solid_p[ty * world.W + tx]) == 0 and not world.on_deck(pt.x, pt.y):
			# a step clear of the edge, if that is still open ground
			var far := pt + inner * 0.4
			var fi: int = floori(far.y) * world.W + floori(far.x)
			if fi >= 0 and fi < world.solid_p.size() and int(world.solid_p[fi]) == 0 and not world.on_deck(far.x, far.y):
				return far
			return pt
	return s.center


func posts_manned() -> bool:
	if radio.alarm_on:
		return true    # the call to arms (radio.gd): everyone at their posts until it is stood down
	var night := phase == "night" or phase == "dawn" or (phase == "dusk" and bell_rung)
	if not recruits.small:
		return night
	if phase == "dawn":
		return _dead_coming()
	return night or threat_by_day()


## Whether the dead are at the wall by day (the settlement game; false at any other time): one that is coming to the
## compound's wall (approach), clawing at it (attack) or inside it (breach) within THREAT_R tiles of it, or the
## alarm ringing. Stragglers of the streets that only wander, or hunt someone who shot at them outside, are not a
## threat to the compound: the crew goes on working. Once it has stopped, THREAT_QUIET_MIN game minutes of quiet
## pass before the crew goes back to work. Kept up once a step (`_update_threat`); `tactics.threat_until` is saved.
func threat_by_day() -> bool:
	if radio.alarm_on and phase == "day":
		return true    # (the call to arms, in any start)
	return recruits.small and phase == "day" and clock_min < tactics.threat_until


func _update_threat() -> void:
	if not recruits.small:
		return    # (the classic start never has a day threat: nothing of this touches it)
	if phase != "day":
		tactics.threat_until = 0.0
		return
	var was := threat_by_day()
	if _under_attack():
		tactics.threat_until = clock_min + THREAT_QUIET_MIN
	if threat_by_day() and not was:
		# the wall crew's mending stops at once: the crew is called to its posts
		for p in people:
			tactics.call_back(p)
		alert("day-threat", "warn", "The dead are at the wall", "Everyone to their posts", null, 10.0)


## Whether, right now, some of the dead are coming to the compound's wall or the alarm rings.
func _under_attack() -> bool:
	return tactics.lure_id >= 0 or _dead_coming()


## Whether any of the dead is coming at the compound: on its way to a wall section (approach), clawing at it (attack)
## or inside it (breach), within THREAT_R tiles of it. The dead of the streets that wander, or hunt someone who shot at
## them, and the dead going back to the city are not.
func _dead_coming() -> bool:
	for z in zombies:
		if (z.state == "approach" or z.state == "attack" or z.state == "breach") and _compound_dist(z.x, z.y) <= THREAT_R:
			return true
	return false


## How far a point is from the compound's rectangle (0 inside it).
static func _compound_dist(x: float, y: float) -> float:
	var dx := maxf(maxf(COMPOUND.position.x - x, x - COMPOUND.end.x), 0.0)
	var dy := maxf(maxf(COMPOUND.position.y - y, y - COMPOUND.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)


func _post_face(p: Person) -> String:
	return String(jobs.post_of(p).get("face", "N"))


func _update_person(p: Person, dt: float) -> void:
	p.recoil = maxf(0.0, p.recoil - dt * 8.0)
	p.thrust = maxf(0.0, p.thrust - dt * 4.0)
	if p.downed or p.dead or p.away != null:
		if p.player and (p.downed or p.dead):
			avatar.clear_hands(p)    # (a person on the ground holds no trigger, no stick, no key: avatar.gd)
		_set_work(p, null, dt)
		return
	if p.player:
		# the player's own hands (avatar.gd): no goals, no orders, no auto-fire
		_set_work(p, null, dt)
		avatar.update(p, dt)
		return
	var goal = _goal_for(p)
	if goal != null:
		p.activity = goal.what
		var key := "%.1f,%.1f" % [goal.x, goal.y]
		var dist := Vector2(goal.x - p.x, goal.y - p.y).length()
		if dist < 0.08:
			p.moving = false
			p.path = []
			if p.target == null and goal.face != "":
				p.facing = goal.face
		else:
			if p.goal_key != key or p.path.is_empty():
				p.goal_key = key
				p.path = levels.find_path(p, goal.x, goal.y)    # (`path_p.find`; with an avatar the way off a deck is a ladder: levels.gd)
				if p.path.is_empty():
					# (no way there: the old yard walks straight at it. With an avatar the towers are shut, so a spot outside the shut gate has no way
					# in the grid, and nobody walks through the wall for it: they stay where they are until there is one)
					p.path = [Vector2(p.x, p.y)] if levels.active() else [Vector2(goal.x, goal.y)]
				p.path_i = 0
			_follow(p, radio.speed_of(p), dt)    # (3.0: whoever follows the player a long way behind hurries)
	if p.repair != null and not p.moving and (repair_spot(p.repair) - Vector2(p.x, p.y)).length() < 0.3:
		var s: Segment = p.repair
		p.activity = "Mending the %s" % s.name.to_lower()
		p.hammer_t -= dt
		if p.hammer_t <= 0.0:
			p.hammer_t = 0.45
			events.append({"type": "hammer", "x": p.x, "y": p.y})
			# the blow lands a step in front of the mender, towards the wall (he stands on the yard side of it)
			var toward := (s.center - Vector2(p.x, p.y)).normalized() if Vector2(p.x, p.y).distance_to(s.center) > 0.5 else Vector2.ZERO
			fx.hit_material(p.x + toward.x * 0.7, p.y + toward.y * 0.7, "metal")
		# (nights.repair_mult: 0.0 for a mender at a breach the dead are at, unless the avatar rallies them: round 19)
		var done: float = supplies.repair_budget(dt * (REPAIR_BASE + float(p.skills.Building)) * perf(p) * traits.mult(p, "repair") * nights.repair_mult(p, s))
		if done > 0.0:
			var before_hp := s.hp
			_repair_segment(s, done)
			skills.credit(p, "mended", s.hp - before_hp)
			if s.hp >= s.max_hp and s.hp > before_hp:
				morale.on_repaired(p)
		if s.hp >= s.max_hp:
			p.repair = null
	_set_work(p, goal, dt)
	_combat(p, dt)


## `Person.work`: the work word of the goal (jobs.gd) while the person stands at its spot and is not walking, else "";
## `work_t` counts the seconds it has gone on, from 0 when the word changes. The drawing reads them; no rule does.
func _set_work(p: Person, goal, dt: float) -> void:
	var word := ""
	if goal != null and not p.moving:
		word = String(goal.get("work", ""))
		if word != "" and Vector2(goal.x - p.x, goal.y - p.y).length() > WORK_REACH:
			word = ""
	if word != p.work:
		p.work = word
		p.work_t = 0.0
	elif word != "":
		p.work_t += dt


## Walk along a.path; returns true once the path is used up.
func _follow(a, speed: float, dt: float) -> bool:
	if a.path.is_empty() or a.path_i >= a.path.size():
		a.moving = false
		return true
	var target: Vector2 = a.path[a.path_i]
	var dx: float = target.x - a.x
	var dy: float = target.y - a.y
	var dist := sqrt(dx * dx + dy * dy)
	var step := speed * dt
	if dist <= step:
		a.x = target.x
		a.y = target.y
		a.path_i += 1
		if a.path_i >= a.path.size():
			a.moving = false
			return true
	else:
		a.x += dx / dist * step
		a.y += dy / dist * step
	a.moving = true
	a.walk_phase += dt * speed * 3.4
	a.facing = facing_of(dx, dy, a.facing)
	return false


## What one shot costs this person's gun from the stock.
func shot_cost(p: Person) -> float:
	return SHELL_COST if p.weapon == "shotgun" else SHOT_COST


## The weapon someone fights with right now: their own, or the butt of it when the
## stock is too low for another shot (a pike never runs dry).
func gun_of(p: Person) -> Dictionary:
	if p.gun.get("melee", false) or stock.ammo >= shot_cost(p):
		return p.gun
	return BUTT


## Whether it is night for the guns: from the bell (or the dark) to the end of dawn.
func is_night() -> bool:
	return phase == "night" or phase == "dawn" or (phase == "dusk" and bell_rung)


## How far a gun reaches right now for this person, in tiles (see `reach_at`): the person's place
## decides whether a watchtower is near. Without a person (the single-argument form) the place is
## left out.
func reach_of(gun: Dictionary, p = null) -> float:
	return reach_at(gun, null if p == null else Vector2(p.x, p.y))


## How far a gun reaches right now, in tiles: its own range, less in a fog (a card of the storyteller's),
## more from the bell to dawn if floodlights stand (the buildings' `night_reach_mult`; `night` asks for
## the night's reach by day, as the fields-of-fire view and the planners do), and for someone standing
## at `at` (a point in tiles; null for no place) more by the flat tiles of a watchtower near them
## (`reach_bonus_at`). A weapon in the hand never reaches less or further.
func reach_at(gun: Dictionary, at = null, night := false) -> float:
	if gun.get("melee", false):
		return float(gun.range)
	var reach: float = float(gun.range) * storyteller.reach_mult()
	if night or is_night():
		reach *= build.factor("night_reach_mult")
	if at != null:
		reach += build.reach_bonus_at(Vector2(at))
	return reach


## The range a shot's accuracy falls off against: the gun's own, longer by what the buildings add (the
## floodlights by night, a watchtower near the shooter), so that the reach they give is shot at the
## accuracy of the range it adds to and not at a negative one (fog shortens what the guns can see, not how
## well they shoot). A weapon in the hand is not helped.
func accuracy_range(gun: Dictionary, p: Person) -> float:
	var r: float = float(gun.range)
	if gun.get("melee", false):
		return r
	if is_night():
		r *= build.factor("night_reach_mult")
	return r + build.reach_bonus_at(Vector2(p.x, p.y))


## The chance one shot (one pellet) hits at this distance, before the aim factors: the gun's accuracy,
## the shooter's skill and how far the target is against `accuracy_range`.
func hit_chance(gun: Dictionary, p: Person, dist: float) -> float:
	var skill: float = float(p.skills.Shooting) / 10.0 * perf(p)
	return float(gun.acc) * (0.75 + skill * 0.35) * (1.0 - 0.5 * pow(dist / accuracy_range(gun, p), 2.0))


## Whether a point is in the yard (the dead there are shot first); a played trip's site has no yard.
func _in_yard(x: float, y: float) -> bool:
	return x > 20 and x < 64 and y > 18 and y < 44


func _find_target(p: Person):
	var rng: float = reach_of(gun_of(p), p)
	var best = null
	var best_score := INF
	for z in zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var dist := Vector2(z.x - p.x, z.y - p.y).length()
		if dist > rng:
			continue
		var inside: bool = _in_yard(z.x, z.y)
		var score := dist - (3.0 if z.state == "attack" else 0.0) - (12.0 if inside else 0.0) + float(Kinds.PRIORITY.get(z.kind, 0.0))
		if score < best_score:
			best_score = score
			best = z
	return best


## Whether one of the dead of the streets is hunting this person within reach of their gun: by day they defend themselves.
func _hunted(p: Person) -> bool:
	for z in zombies:
		if z.state == "hunt" and z.hunt_id == String(p.id):
			return true
	return false


func _combat(p: Person, dt: float) -> void:
	if p.reloading > 0.0:
		p.reloading -= dt
		if p.reloading <= 0.0:
			p.mag = int(p.gun.mag)
			p.reloading = 0.0
		p.aim += ang_diff(p.aim, _rest_angle(p)) * minf(1.0, dt * 6.0)
		return
	p.cooldown -= dt
	if p.moving or (phase == "day" and not p.drafted and not threat_by_day() and not _hunted(p)) or morale.breakdown(p):
		p.target = null
		p.aim += ang_diff(p.aim, _rest_angle(p)) * minf(1.0, dt * 6.0)
		return
	var gun := gun_of(p)
	if gun == BUTT and (phase == "night" or phase == "dusk" or p.drafted):
		alert("ammo-out", "danger", "Out of ammo", "The guns are silent. Send a party for more.", null, 20.0)
	var tz = p.target
	if tz == null or tz.state == "dying" or tz.state == "dead" or Vector2(tz.x - p.x, tz.y - p.y).length() > reach_of(gun, p):
		p.target = _find_target(p)
	if p.target == null:
		p.aim += ang_diff(p.aim, _rest_angle(p)) * minf(1.0, dt * 4.0)
		return
	var z: Zombie = p.target
	var ang := atan2(z.y - 0.3 - (p.y - 0.15), z.x - p.x)
	p.aim += ang_diff(p.aim, ang) * minf(1.0, dt * 9.0)
	p.facing = facing_of(cos(ang), sin(ang), p.facing)
	if p.cooldown <= 0.0 and absf(ang_diff(p.aim, ang)) < 0.1:
		_fire(p, z, ang)


func _rest_angle(p: Person) -> float:
	var r: float = guns[p.weapon].rest
	if p.weapon == "pike":
		return r
	if p.facing == "W":
		return PI - r
	if p.facing == "N":
		return -PI / 2.0 + 0.35
	return r


func muzzle(p: Person, ang: float) -> Vector2:
	var view := "E" if p.facing == "W" else p.facing
	var pv: Vector2 = PIVOT[view]
	var mx := -pv.x if p.facing == "W" else pv.x
	var length: float = guns[p.weapon].muzzle
	return Vector2(p.x + mx + cos(ang) * length, p.y + pv.y + sin(ang) * length)


func _fire(p: Person, z: Zombie, ang: float) -> void:
	var gun := gun_of(p)
	var dist := Vector2(z.x - p.x, z.y - p.y).length()
	if gun.get("melee", false):
		p.thrust = 1.0
		p.cooldown = float(gun.cooldown) * (0.9 + rng.randf() * 0.2) * nights.fire_mult(p)
		events.append({"type": "stab", "x": p.x, "y": p.y})
		if rng.randf() < float(gun.acc):
			_hurt_zombie(z, nights.damage_to(z, float(gun.dmg), nights.npc_weak(z)), ang, p, true)
		return
	p.mag -= 1
	p.stats.shots += 1
	p.recoil = 1.0
	p.cooldown = float(gun.cooldown) * (0.85 + rng.randf() * 0.3) * nights.fire_mult(p)
	var m := muzzle(p, ang)
	if feel != null:
		feel.shot(p, p.weapon, ang)
	fx.muzzle(m.x, m.y, ang, p.weapon == "shotgun" or p.weapon == "hunting")
	fx.casing(p.x, p.y - 0.15, ang, p.weapon == "shotgun")
	events.append({"type": "shot", "weapon": gun.sound, "gun": p.weapon, "x": p.x, "y": p.y})
	stock.ammo = maxf(0.0, stock.ammo - shot_cost(p))
	var pellets := int(gun.get("pellets", 1))
	var aim_f: float = aim_factor(p) * storyteller.aim_mult(dist)
	var dealt := 0.0
	for k in pellets:
		var pa := ang + (rng.randf() - 0.5) * float(gun.get("spread", 0.05))
		var p_hit := hit_chance(gun, p, dist) * aim_f
		var hit := rng.randf() < (p_hit * 0.7 if pellets > 1 else p_hit)
		var e: Vector2
		if hit:
			e = Vector2(z.x + (rng.randf() - 0.5) * 0.2, z.y - 0.3 + (rng.randf() - 0.5) * 0.3)
			dealt += float(gun.dmg)
		else:
			var over := dist + 1.0 + rng.randf() * 3.0
			var a2 := pa + (rng.randf() - 0.5) * 0.12
			e = Vector2(p.x + cos(a2) * over, p.y - 0.15 + sin(a2) * over)
			fx.smoke(e.x, e.y, 0.12, false)
		fx.tracer(m.x, m.y, e.x, e.y)
	if dealt > 0.0:
		# (a plated brute of a Big Night: the armoured share, or one shot in a dozen on its head; one die for it, none for anything else)
		_hurt_zombie(z, nights.damage_to(z, dealt, nights.npc_weak(z)), ang, p)
	if p.mag <= 0:
		p.reloading = float(gun.reload) * traits.mult(p, "reload")
		p.target = null
		events.append({"type": "reload", "x": p.x, "y": p.y})
	_shot_noise(p)


## Gunfire draws the dead (by day in the settlement game only those close by, and for the shooter: a shot at a
## straggler of the streets does not send the whole city against the walls). `_fire` and the avatar's shots call it.
func _shot_noise(p: Person) -> void:
	var shot_by_day: bool = town.on and phase == "day"
	for w in zombies:
		if w.state != "wander":
			continue
		var heard := Vector2(w.x - p.x, w.y - p.y).length()
		if shot_by_day:
			if heard < Streets.NOTICE_R + 2.0:
				w.state = "hunt"
				w.hunt_id = String(p.id)
				w.path = []
				w.repath = 0.0
		elif heard < 30.0:
			w.state = "approach"


## `shooter` is whoever struck the blow (it is credited with the kill, `melee` or not).
func _hurt_zombie(z: Zombie, dmg: float, ang: float, shooter: Person = null, melee := false) -> void:
	z.hp -= dmg
	z.stagger = 0.25
	if feel != null:
		feel.hit(z, ang, dmg, melee, shooter)    # (before the blood: it says whether this one is told, a hit on steel does not bleed)
	fx.blood(z.x, z.y - 0.25, cos(ang), sin(ang), 9)
	if z.hp <= 0.0 and z.state != "dying" and z.state != "dead":
		z.state = "dying"
		z.fall = 0.0
		z.fall_dir = 1.0 if cos(ang) >= 0.0 else -1.0
		if z.slot != null:
			z.slot.who = null
			z.slot = null
		kills += 1
		if shooter != null:
			skills.credit(shooter, "melee" if melee else "kills", 1.0)
			morale.on_kill(shooter)
			barks.on_kill(shooter)
		fx.decal(z.x + z.fall_dir * 0.35, z.y + 0.2, 0.25, 0.9)
		events.append({"type": "thud", "x": z.x, "y": z.y})
		if feel != null:
			feel.kill(z, ang, melee, shooter)


# ----------------------------------------------------------------- zombies --

func _assign_slot(z: Zombie) -> bool:
	return assign_slot(z, null)


## Gives one of the dead a free place at a wall section (the best by distance, how
## crowded it is and a little luck; the section with the alarm on it scores far
## better), or only at `only` when that is given. False if there is none or no way.
func assign_slot(z: Zombie, only) -> bool:
	var best: Slot = null
	var best_score := INF
	var yard_down := yard_open()
	var lured = tactics.lure_seg()
	# in a game with lots the dead only choose a place they can get to (a wall of the lots may shut the way)
	var gated: bool = lots.on
	var home_region := region_at(z.x, z.y) if gated else 0
	var gate_open: bool = _any_gate_open()
	for s in segments:
		if s.state == 3:
			continue
		if gate_open and _is_open_gate(s):
			continue    # (round 22: the gate stands open: nothing to claw at, they walk in)
		if only != null and s != only:
			continue
		if s.kind == DOOR_KIND and not yard_down:
			continue
		var crowd := 0
		for sl in s.slots:
			if sl.who != null:
				crowd += 1
		for sl in s.slots:
			if sl.who != null:
				continue
			if gated and home_region >= 0 and region_at(sl.ax, sl.ay) != home_region:
				continue
			var score := Vector2(sl.ax - z.x, sl.ay - z.y).length() + crowd * 1.2 + rng.randf() * 4.0
			if lured != null and s == lured:
				score -= Tactics.LURE_PULL
			if score < best_score:
				best_score = score
				best = sl
	if best == null:
		return false
	var path: Array = path_z.find(world.solid_z, z.x, z.y, best.ax, best.ay)
	if path.is_empty():
		return false
	best.who = z
	z.slot = best
	z.path = path
	z.path_i = 0
	return true


## A wall section made in play (a wall at a mouth of a lot, round 9): `def` has id, kind, side, from, to, name,
## hp, tiles, center, slots ({x, y, ax, ay, face}), obj ({cx, cy, w, h, a}) and art. Its tiles are shut on both
## walking grids and the world is told to draw it. Sections are only ever added at the end.
func add_segment(def: Dictionary) -> Segment:
	var seg := Segment.new()
	seg.id = int(def.id)
	seg.kind = String(def.kind)
	seg.side = String(def.side)
	seg.from = float(def["from"])
	seg.to = float(def.to)
	seg.name = String(def.name)
	seg.hp = float(def.hp)
	seg.max_hp = float(def.hp)
	seg.tiles = def.tiles
	seg.center = Vector2(def.center)
	seg.obj = def.obj
	seg.art = def.get("art", [])
	for sl in def.slots:
		var slot := Slot.new()
		slot.x = float(sl.x)
		slot.y = float(sl.y)
		slot.ax = float(sl.ax)
		slot.ay = float(sl.ay)
		slot.face = String(sl.face)
		slot.seg = seg
		seg.slots.append(slot)
	segments.append(seg)
	block_tiles(seg.tiles, true)
	if on_segment_added.is_valid():
		on_segment_added.call(seg)
	return seg


## Takes a wall section made in play away (a save is being loaded, a new run begins): its tiles open again.
func remove_segment(seg: Segment) -> void:
	for sl in seg.slots:
		if sl.who != null:
			var z = sl.who
			z.slot = null
			if z.state == "attack":
				z.state = "approach"
	segments.erase(seg)
	block_tiles(seg.tiles, false)
	if on_segment_removed.is_valid():
		on_segment_removed.call(seg)


## Which stretch of open ground (for the dead) the point is on, as a number, or -1 on a shut tile: two points
## with the same number can be walked between. Worked out again after any wall goes up or down.
func region_at(x: float, y: float) -> int:
	if _regions_dirty:
		_compute_regions()
	var tx := floori(x)
	var ty := floori(y)
	if tx < 0 or ty < 0 or tx >= W or ty >= H:
		return -1
	return _regions[ty * W + tx]


func _compute_regions() -> void:
	_regions_dirty = false
	_regions.resize(W * H)
	_regions.fill(-1)
	var solid: PackedByteArray = world.solid_z
	var label := 0
	var stack := PackedInt32Array()
	for start in W * H:
		if _regions[start] != -1 or solid[start] != 0:
			continue
		_regions[start] = label
		stack.append(start)
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := i % W
			@warning_ignore("integer_division")
			var y := i / W
			if x > 0 and _regions[i - 1] == -1 and solid[i - 1] == 0:
				_regions[i - 1] = label
				stack.append(i - 1)
			if x < W - 1 and _regions[i + 1] == -1 and solid[i + 1] == 0:
				_regions[i + 1] = label
				stack.append(i + 1)
			if y > 0 and _regions[i - W] == -1 and solid[i - W] == 0:
				_regions[i - W] = label
				stack.append(i - W)
			if y < H - 1 and _regions[i + W] == -1 and solid[i + W] == 0:
				_regions[i + W] = label
				stack.append(i + W)
		label += 1


## Whether a wall section of the yard (not a school door) is down.
func yard_open() -> bool:
	for s in segments:
		if s.kind != DOOR_KIND and s.state == 3 and s.id < Lots.FIRST_SEGMENT_ID:
			return true
	return _any_gate_open()    # (round 22: a gate that stands open is a way in, as a section that fell)


## A free place at a school door that is still up, for one of the dead who cannot
## get at a person hiding in the school: the nearest, if there is a way to it.
func _assign_door_slot(z: Zombie) -> bool:
	var best: Slot = null
	var best_score := INF
	for s in segments:
		if s.kind != DOOR_KIND or s.state == 3:
			continue
		for sl in s.slots:
			if sl.who != null:
				continue
			var score := Vector2(sl.ax - z.x, sl.ay - z.y).length() + rng.randf() * 2.0
			if score < best_score:
				best_score = score
				best = sl
	if best == null:
		return false
	var path: Array = path_z.find(world.solid_z, z.x, z.y, best.ax, best.ay)
	if path.is_empty():
		return false
	best.who = z
	z.slot = best
	z.path = path
	z.path_i = 0
	return true


## Whether a point is inside the school building (not the street around it).
func inside_school(x: float, y: float) -> bool:
	return y >= float(SCHOOL_TOP_ROW) + 0.5 and y < float(H) - 5.0 and x > 20.0 and x < 64.0


## How many of the dead are inside the compound, the yard or the school (not
## counting those on their way out): the stores are theirs to ruin.
func dead_inside() -> int:
	var n := 0
	for z in zombies:
		if z.state == "dying" or z.state == "dead" or z.state == "retreat":
			continue
		if (z.x > 20.0 and z.x < 64.0 and z.y > 18.0 and z.y < 44.0) or inside_school(z.x, z.y):
			n += 1
	return n


## Whether this person is inside the school building.
func in_school(p: Person) -> bool:
	return inside_school(p.x, p.y)


## The school's inside is open to the dead while a door is down or one of them is
## already in there (so nobody is walled in with the dead). Cheap: called every step.
func refresh_school() -> void:
	var want := false
	for s in segments:
		if s.kind == DOOR_KIND and s.state == 3:
			want = true
			break
	if not want and school_open:
		for z in zombies:
			if z.state != "dying" and z.state != "dead" and inside_school(z.x, z.y):
				want = true
				break
	if want == school_open:
		return
	school_open = want
	_regions_dirty = true
	for i in _school_inner:
		world.solid_z[int(i)] = 0 if want else 1
		path_z.set_solid(int(i), not want)
	if want:
		events.append({"type": "banner", "text": "The school is open", "sub": "The dead are inside"})


## The ground a wall section stands on, open or shut. A school door opens to the
## dead only: people walk through it whole.
func open_segment(s: Segment, open: bool) -> void:
	_regions_dirty = true
	if s.kind == DOOR_KIND:
		for i in s.tiles:
			world.solid_z[int(i)] = 0 if open else 1
			path_z.set_solid(int(i), not open)
		return
	world.set_walkable(s.tiles, open)
	for i in s.tiles:
		path_z.set_solid(int(i), not open)
		path_p.set_solid(int(i), not open)
	lots.after_segment_change(s)


## Shuts or opens ground for good, as a standing building's footprint does: the walking grid and both
## path grids (the same ground a wall section has, see `open_segment`).
func block_tiles(tiles: Array, blocked: bool) -> void:
	_regions_dirty = true
	world.set_walkable(tiles, not blocked)
	for i in tiles:
		path_z.set_solid(int(i), blocked)
		path_p.set_solid(int(i), blocked)


## At dawn the dead go back to the city, a few a step (each is a path search).
func _dawn_sweep() -> void:
	var left := DAWN_LEAVES_PER_STEP
	for z in zombies:
		if left <= 0:
			return
		if z.state != "dying" and z.state != "dead" and z.state != "retreat":
			retreat(z)
			left -= 1


func retreat(z: Zombie) -> void:
	if z.slot != null:
		z.slot.who = null
		z.slot = null
	var best: Vector2 = spawns[0]
	var bd := INF
	for s in spawns:
		var dist := Vector2(s.x - z.x, s.y - z.y).length()
		if dist < bd:
			bd = dist
			best = s
	z.state = "retreat"
	z.path = path_z.find(world.solid_z, z.x, z.y, best.x, best.y)
	z.path_i = 0


func _breached() -> bool:
	# (the compound's own sections: a wall across a street of the lots that has fallen opens the street, not the yard)
	for s in segments:
		if s.state == 3 and s.id < Lots.FIRST_SEGMENT_ID:
			return true
	return _any_gate_open()    # (round 22: the gate stands open: the dead walk in as through a section that fell)


## Whether one of the dead of the streets may go on hunting a survivor now: in the yard only by day (it gives up at
## nightfall: the night belongs to the walls). A place's sim says yes at every hour (raid_sim.gd): a place can be played
## at night.
func _hunt_allowed() -> bool:
	return phase == "day"


func _update_zombie(z: Zombie, dt: float) -> void:
	z.t += dt
	z.moving = false
	if z.state == "dying":
		z.fall = minf(1.0, z.fall + dt / 0.45)
		if z.fall >= 1.0:
			z.state = "dead"
			z.dead_t = 0.0
		return
	if z.state == "dead":
		z.dead_t += dt
		if z.dead_t > 70.0:
			z.remove = true
		return
	z.groan_t -= dt
	if z.groan_t <= 0.0:
		z.groan_t = 5.0 + rng.randf() * 12.0
		# the stragglers of the streets by day (the settlement game) groan a third as often: a dozen of them
		# every few seconds would be a wall of noise
		var stray: bool = town.on and z.state == "wander" and phase == "day"
		if stray:
			z.groan_t *= 3.0
		events.append({"type": "groan", "x": z.x, "y": z.y, "kind": z.kind, "stray": stray})
	if z.stagger > 0.0:
		z.stagger -= dt
		return
	var slow := z.speed * (0.85 if z.limp else 1.0)
	match z.state:
		"wander":
			z.wander_t -= dt
			if z.wander_t <= 0.0 or z.path.is_empty() or z.path_i >= z.path.size():
				z.wander_t = 6.0 + rng.randf() * 8.0
				for k in 6:
					var tx := z.x + (rng.randf() - 0.5) * 10.0
					var ty := z.y + (rng.randf() - 0.5) * 10.0
					if tx > 0 and ty > 0 and tx < W and ty < H and not world.is_solid(world.solid_z, tx, ty):
						z.path = path_z.find(world.solid_z, z.x, z.y, tx, ty)
						z.path_i = 0
						break
			_follow(z, slow * 0.55, dt)
			if bell_rung and _wanderers_rally() and rng.randf() < dt * 0.1:
				z.state = "approach"
		"retreat":
			if _follow(z, slow, dt):
				z.remove = true
			elif lots.on and not z.path.is_empty() and Vector2(z.x, z.y).distance_to(Vector2(z.path[z.path.size() - 1])) < RETREAT_DONE:
				# (a pocket behind a wall of the lots is two tiles wide: the dead who crowd it push each other off the
				# spawn point for good, so near enough is gone)
				z.remove = true
		"approach":
			if _breached() and rng.randf() < dt and not (z.slot != null and z.slot.seg.kind == DOOR_KIND):
				if z.slot != null:
					z.slot.who = null
					z.slot = null
				z.state = "breach"
				return
			if z.slot == null and not _assign_slot(z):
				z.state = "wander"
				return
			if not z.path.is_empty() and z.path_i < z.path.size():
				_follow(z, slow, dt)
				return
			# final shuffle up against the wall
			var dx: float = z.slot.x - z.x
			var dy: float = z.slot.y - z.y
			var dist := sqrt(dx * dx + dy * dy)
			if dist < 0.05:
				z.state = "attack"
				z.facing = z.slot.face
				return
			var step := minf(dist, slow * dt)
			z.x += dx / dist * step
			z.y += dy / dist * step
			z.moving = true
			z.walk_phase += dt * slow * 3.4
			z.facing = facing_of(dx, dy, z.facing)
		"attack":
			var s: Segment = z.slot.seg
			z.facing = z.slot.face
			if s.state == 3 or (_is_open_gate(s) and _any_gate_open()):
				# (round 22: a gate that has been opened under them is a way in as a section that fell)
				z.slot.who = null
				z.slot = null
				z.state = "breach"
				return
			z.attack_t -= dt
			if z.attack_t <= 0.0:
				z.attack_t = 1.1 + rng.randf() * 0.6
				_claw(z, s)
		"hunt":
			# a straggler of the streets after a survivor it saw outside the walls (round 12)
			var prey2: Person = null
			for p in people:
				if String(p.id) == z.hunt_id:
					prey2 = p
			if prey2 == null or prey2.dead or prey2.downed or prey2.away != null or not _hunt_allowed():
				z.state = "wander"
				z.hunt_id = ""
				return
			var hd := Vector2(prey2.x - z.x, prey2.y - z.y).length()
			if hd > Streets.GIVE_UP or region_at(prey2.x, prey2.y) != region_at(z.x, z.y):
				z.state = "wander"
				z.hunt_id = ""
				return
			if hd < 0.7:
				z.facing = facing_of(prey2.x - z.x, prey2.y - z.y, z.facing)
				z.attack_t -= dt
				if z.attack_t <= 0.0:
					z.attack_t = 1.3
					_bite(z, prey2)
				return
			z.repath -= dt
			if z.repath <= 0.0 or z.path.is_empty():
				z.repath = 0.8
				z.path = path_z.find(world.solid_z, z.x, z.y, prey2.x, prey2.y)
				z.path_i = 0
				if z.path.is_empty():
					z.state = "wander"
					z.hunt_id = ""
					return
			_follow(z, slow * 1.1, dt)
		"breach":
			z.repath -= dt
			# (avatar mode, round 22: a wall that is mended while they stand outside is a wall again: they go back to tearing at it, they do
			# not wait out the night by a shut gate)
			if nights.active() and not _breached() and not _in_the_yard(z.x, z.y) and not inside_school(z.x, z.y):
				z.path = []
				z.path_i = 0
				z.state = "approach"
				return
			var prey: Person = null
			var pd := INF
			for p in people:
				if p.downed or p.dead or p.away != null:
					continue
				var dist := Vector2(p.x - z.x, p.y - z.y).length()
				if dist < pd:
					pd = dist
					prey = p
			if prey == null:
				# (avatar mode, round 22: a lost wall lets the dead in even when there is nobody to go for: they make for the stores)
				if nights.active():
					_come_in(z, slow * 1.1, dt)
				return
			if pd < 0.7:
				z.facing = facing_of(prey.x - z.x, prey.y - z.y, z.facing)
				z.attack_t -= dt
				if z.attack_t <= 0.0:
					z.attack_t = 1.3
					_bite(z, prey)
				return
			# (avatar mode asks again once a second, as a person is asked: a dead one with no way to anybody is not a search a step)
			var avatar_game: bool = nights.active()
			if z.repath <= 0.0 or (z.path.is_empty() and not avatar_game):
				z.repath = 1.0
				if world.is_solid(world.solid_z, z.x, z.y):
					# a survivor who turned inside the school stands where the dead
					# cannot walk: there they hunt by the people's paths
					z.path = path_p.find(world.solid_p, z.x, z.y, prey.x, prey.y)
				else:
					z.path = path_z.find(world.solid_z, z.x, z.y, prey.x, prey.y)
				z.path_i = 0
				if z.path.is_empty() and not school_open and in_school(prey) and _assign_door_slot(z):
					z.state = "approach"
					return
				# a lost wall costs (round 22): no way to anybody, so they come in for the stores
				if z.path.is_empty() and avatar_game:
					z.path = path_z.find(world.solid_z, z.x, z.y, yard_middle().x, yard_middle().y)
					z.path_i = 0
			_follow(z, slow * 1.1, dt)


## Whether a point is in the compound's yard (the ground between the walls and the school: where the dead ruin the stores).
func _in_the_yard(x: float, y: float) -> bool:
	return x > 20.0 and x < 64.0 and y > 18.0 and y < 44.0


## Avatar mode (round 22): one of the dead in a breach with nobody to hunt walks to the middle of the yard, where the stores are (and stays
## there until the dawn: `dead_inside` ruins what it finds). Asked once a second.
func _come_in(z: Zombie, speed: float, dt: float) -> void:
	if (z.path.is_empty() or z.path_i >= z.path.size()) and z.repath <= 0.0:
		z.repath = 1.0
		z.path = path_z.find(world.solid_z, z.x, z.y, yard_middle().x, yard_middle().y)
		z.path_i = 0
	_follow(z, speed, dt)


func _claw(z: Zombie, s: Segment) -> void:
	_damage_segment(s, (1.0 + rng.randf() * 1.3) * z.claw)
	var mat := "wood" if (s.kind == "pallets" or s.kind == DOOR_KIND) else ("stone" if s.kind == "blocks" else "metal")
	var from_north := s.side == "N" or s.side == "S"
	var nx := 0.0 if from_north else (1.0 if s.side == "W" else -1.0)
	var ny := 1.0 if from_north else 0.0
	if rng.randf() < 0.6:
		fx.hit_material(z.x + nx * 0.35, z.y + ny * 0.25, mat)
	events.append({"type": "claw", "material": mat, "x": z.x, "y": z.y})
	var pct := roundi(s.hp / s.max_hp * 100.0)
	alert("seg-%d" % s.id, "danger" if pct < 34 else "warn", "%s under attack" % s.name, "%d%% intact" % pct, s.center, 4.0)
	medical.on_wall_claw(z, s)


func _damage_segment(s: Segment, amount: float) -> void:
	s.hp = maxf(0.0, s.hp - amount)
	_segment_state(s)


func _repair_segment(s: Segment, amount: float) -> void:
	s.hp = minf(s.max_hp, s.hp + amount)
	_segment_state(s)


func _segment_state(s: Segment) -> void:
	var f := s.hp / s.max_hp
	var st := 3 if s.hp <= 0.0 else (2 if f < 0.33 else (1 if f < 0.66 else 0))
	if s.state == 3 and st != 3 and f < 0.4:
		st = 3 # rebuilding a breach takes a while
	if st == s.state:
		return
	var was := s.state
	s.state = st
	if st == 3:
		open_segment(s, true)
		events.append({"type": "crash", "x": s.center.x, "y": s.center.y})
		events.append({"type": "banner", "text": "Breach!", "sub": "The %s is down" % s.name.to_lower()})
		alert("breach-%d" % s.id, "danger", "Breach at the %s" % s.name.to_lower(), "Walkers are getting in", s.center, 30.0)
		morale.on_breach()
		barks.on_breach(s)
	elif was == 3:
		open_segment(s, false)
	if on_segment_change.is_valid():
		on_segment_change.call(s)


func _bite(z: Zombie, p: Person) -> void:
	p.hp = maxf(0.0, p.hp - (9.0 + rng.randf() * 6.0))
	fx.blood(p.x, p.y - 0.25, p.x - z.x, p.y - z.y, 8)
	events.append({"type": "bite", "x": p.x, "y": p.y, "who": String(p.id)})
	alert("hurt-%s" % p.id, "danger", "%s is being bitten" % p.first, "%d%% health" % roundi(p.hp), Vector2(p.x, p.y), 6.0)
	medical.after_bite(z, p)
	if p.hp <= 0.0 and not p.downed:
		medical.on_downed(p, "bite")


func _separate() -> void:
	var n := zombies.size()
	for i in n:
		var a: Zombie = zombies[i]
		if a.state == "dead" or a.state == "dying":
			continue
		for j in range(i + 1, n):
			var b: Zombie = zombies[j]
			if b.state == "dead" or b.state == "dying":
				continue
			var dx := b.x - a.x
			var dy := b.y - a.y
			var d2 := dx * dx + dy * dy
			if d2 > 0.3 or d2 < 1e-6:
				continue
			var dist := sqrt(d2)
			var push := (0.55 - dist) * 0.5
			var ux := dx / dist
			var uy := dy / dist
			var ma := a.state != "attack"
			var mb := b.state != "attack"
			if ma:
				_nudge(a, -ux * push * (1.0 if mb else 2.0), -uy * push * (1.0 if mb else 2.0))
			if mb:
				_nudge(b, ux * push * (1.0 if ma else 2.0), uy * push * (1.0 if ma else 2.0))


## Push apart in the open only: a walker already shuffling into the wall line
## is left alone, and nobody is pushed into a wall.
func _nudge(z: Zombie, dx: float, dy: float) -> void:
	if world.is_solid(world.solid_z, z.x, z.y):
		return
	var nx := z.x + dx
	var ny := z.y + dy
	if nx <= 0.0 or ny <= 0.0 or nx >= W or ny >= H:
		return
	if world.is_solid(world.solid_z, nx, ny):
		return
	z.x = nx
	z.y = ny
