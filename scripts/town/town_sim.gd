## The rules of the town (feature/town-core, WP1): the colony's Sim on the generated 192 x 192 map, with the dead of the town dormant until the avatar, a shot or a light is
## near (scripts/town/dormant_dead.gd) and the town's own modules wired in by name.
##
## THE CLASS. `TownSim extends sim.gd` (the colony: radio, jobs, build, nights, briefing...). The plan (docs/superpowers/plans/2026-10-04-one-house-plan.md, 1.1) puts the
## school's assumptions in a `TownRules` between this class and Sim (WP5 owns `town_rules.gd`); until it lands the extends line below is `sim.gd`, and swapping it for
## `town_rules.gd` is one line. The overrides marked INTERIM are TownRules' by the plan; they are here only so that the colony's `update` runs on a town map, and they are
## deleted from this file when TownRules has them.
##
## WHAT THIS CLASS CHANGES (each measured, see the report):
##  1. `_separate` (the dead's crowd pass) is a square of how many there are in the colony's code (sim.gd 1831: every pair, every step); here a grid of one tile, and two
##     dead that both stand still are not asked: 100 awake dead cost 0.45 ms a step instead of 2.0.
##  2. a state "chase" in place of "hunt": hunt gives a dead one up at 14 tiles (Streets.GIVE_UP), asks the region of both (a flood of the whole map the first time and after
##     every door, wall or build) and searches a way every 0.8 s; chase gives up at `chase_give_up` (45), never asks a region, walks straight at the prey when a line of sight is
##     clear and searches the grid only when it is not, less often the farther the prey.
##  3. a state "still" (stands where it is: the base `match` has no case for it, so the preamble of `_update_zombie` is all it costs).
##  4. the noise of a shot goes to the field (`field.noise`) instead of the base's loop over every dead one.
##
## THE PARTS. `PARTS` maps a variable name of this class to the file of the module; a file that does not exist is skipped, so a package can land any time. A part is a RefCounted
## with `setup(sim)`, `start()`, `update(dt)`, `save()`, `load_state(d)` and optionally `prepare_load(data)`, `restore(before)`, `person_added(p)`, `pre_save()` and `enabled`;
## SaveGame finds each of them by its variable (it can save and load). `scenario` replaces the colony's Scenario when `one_house.gd` exists.
extends "res://scripts/sim/sim.gd"

const GRID_W := 1024
const TownMedical := preload("res://scripts/town/town_medical.gd")

## The town's modules, in the order they are made and stepped. (Plan 1.13.) `field` is stepped before the colony's step, the others after it.
const PARTS := {
	"houses": "res://scripts/town/houses.gd",
	"field": "res://scripts/town/dormant_dead.gd",
	"clearing": "res://scripts/town/clearing.gd",
	"search": "res://scripts/town/search.gd",
	"base": "res://scripts/town/base.gd",
	"sleep": "res://scripts/town/sleep.gd",
	"uses": "res://scripts/town/uses.gd",
	"rescue": "res://scripts/town/rescue.gd",
	"perimeter": "res://scripts/town/perimeter.gd",
	"scenario": "res://scripts/town/one_house.gd",
}

## The generated town (`TownGen.make`): the map data's "town_data".
var town_data: Dictionary = {}
var houses
var field
var clearing
var search
var base
var sleep
var uses
var rescue
var perimeter
## The names of the parts that exist (made from PARTS).
var parts_made: Array = []

var grid_separate := true
var chase_on := true
var chase_give_up := 45.0
var _grid := {}
## Microseconds spent in `_separate` and in `_chase`, and how many chases were stepped (for the measurements: whoever reads them resets them).
var sep_usec := 0
var chase_usec := 0
var chase_n := 0


func _init(data: Dictionary, w, effects) -> void:
	super(data, w, effects)
	town_data = data.get("town_data", {})
	medical = TownMedical.new()
	medical.setup(self)
	_make_parts()


## INTERIM (TownRules): `Sim._seed` indexes the school's wall sections, which a town starts without.
func _seed() -> void:
	pass


func _make_parts() -> void:
	parts_made.clear()
	for name in PARTS:
		var path: String = PARTS[name]
		if not ResourceLoader.exists(path):
			continue
		var m = (load(path) as GDScript).new()
		if name == "scenario":
			scenario = m
		else:
			set(name, m)
		if name == "field":
			m.setup(self, town_data)
			if not town_data.is_empty():
				m.load_records(town_data.dead)
		else:
			m.setup(self)
		if name == "houses":
			m.use_town(town_data)
		parts_made.append(name)


## The modules that are stepped after the colony's step (not the field, not the houses, not the scenario: the colony steps that one itself).
func _stepped_parts() -> Array:
	var out: Array = []
	for name in parts_made:
		if name == "field" or name == "houses" or name == "scenario":
			continue
		out.append(get(name))
	return out


## A new run: the colony's, then the town's: none of the dead the school starts with (INTERIM, TownRules), the school's night machinery off until the scenario switches it
## on (`OneHouse.begin` does the rest), and everybody at the start house.
func start_run(difficulty_index: int, seed_value: int) -> void:
	super(difficulty_index, seed_value)
	zombies.clear()
	events.clear()
	waves.enabled = false
	storyteller.enabled = false
	streets.enabled = false
	gate.enabled = false
	levels.enabled = false
	if not town_data.is_empty():
		var at: Vector2 = town_data.start.pos
		for p in people:
			p.x = at.x
			p.y = at.y
	for name in parts_made:
		if name == "scenario":
			continue
		var m = get(name)
		if m.has_method("start"):
			m.start()


func add_person(def: Dictionary) -> Person:
	var p := super(def)
	for m in _stepped_parts():
		if m.has_method("person_added"):
			m.person_added(p)
	return p


# ------------------------------------------------------------------ the step --

func _anchors() -> Array:
	var out: Array = []
	for p in people:
		if not p.dead and p.away == null:
			out.append(Vector2(p.x, p.y))
	return out


## The "they see you" rule of a place (raid_run.gd `_wake_the_dead`): a dead one that stands or wanders within seven tiles of a living person with a clear line goes after
## them. Only the awake ones are asked.
func _notice() -> void:
	for z in zombies:
		if z.state != "still" and z.state != "wander":
			continue
		for p in people:
			if p.dead or p.downed or p.away != null:
				continue
			var dx: float = p.x - z.x
			var dy: float = p.y - z.y
			if dx * dx + dy * dy < 49.0 and path_z.sight(world.solid_z, Vector2(z.x, z.y), Vector2(p.x, p.y), 0.15):
				start_chase(z, p)
				break


func update(dt: float) -> void:
	if over != "":
		return
	if field != null:
		field.update(dt, _anchors())
		_notice()
	var first_new := events.size()
	super(dt)
	for m in _stepped_parts():
		if m.has_method("update") and bool(m.get("enabled") if "enabled" in m else true):
			m.update(dt)
	_town_events(first_new)


## Before the attacks begin (no scenario, or one that says so) the school's words about the wall and the horde do not fit a street: the bell tolls and the night falls, nobody is
## sent to a wall. The banners that this step added are renamed in place, and the horde alert is dropped.
func _town_events(first_new: int) -> void:
	var attacks: bool = scenario.has_method("attacks_on") and bool(scenario.attacks_on())
	if attacks:
		return
	for i in range(first_new, events.size()):
		var e: Dictionary = events[i]
		if String(e.get("type", "")) != "banner":
			continue
		var text := String(e.get("text", ""))
		if text == "The bell rings":
			e["text"] = "The bell"
			e["sub"] = "Dusk: be indoors before dark"
		elif text.begins_with("Night ") and String(e.get("sub", "")).begins_with("Hold the wall"):
			e["sub"] = "The streets are not safe in the dark"
		elif text == "Dawn":
			e["sub"] = "The dead drift back to where they were"
		elif text.begins_with("Day ") and String(e.get("sub", "")).begins_with("Repair the wall"):
			e["sub"] = "Find survivors, search the houses"
	if alerts.has("horde"):
		alerts.erase("horde")
	if alerts.has("bell"):
		alerts.erase("bell")


## INTERIM (TownRules): only the night's wave dead (the ones with no record in the field) go back to the city at dawn; the town's own dead stay where they are.
func _dawn_sweep() -> void:
	var left := DAWN_LEAVES_PER_STEP
	for z in zombies:
		if left <= 0:
			return
		if field != null and field.rec_of.has(z):
			continue
		if z.state != "dying" and z.state != "dead" and z.state != "retreat":
			retreat(z)
			left -= 1


# ------------------------------------------------------------------ the dead --

## The noise of a shot goes to the field: the dormant dead within its radius wake and come, the awake that stand or wander within it come.
func _shot_noise(p: Person) -> void:
	if field != null:
		field.noise(Vector2(p.x, p.y), p)


func _hunt_allowed() -> bool:
	return true


func _update_zombie(z: Zombie, dt: float) -> void:
	var was_staggered := z.stagger > 0.0
	super(z, dt)
	if z.state == "chase" and not was_staggered:
		var t_in := Time.get_ticks_usec()
		_chase(z, dt)
		chase_usec += Time.get_ticks_usec() - t_in
		chase_n += 1


## Starts one of the dead after somebody: chase, or the colony's hunt when `chase_on` is off (the measurements compare the two).
func start_chase(z: Zombie, prey: Person) -> void:
	z.state = "chase" if chase_on else "hunt"
	z.hunt_id = String(prey.id)
	z.path = []
	z.path_i = 0
	z.repath = rng.randf() * 0.3


func _prey_of(z: Zombie) -> Person:
	for p in people:
		if String(p.id) == z.hunt_id and not p.dead and not p.downed and p.away == null:
			return p
	# the one they were after is gone: the nearest of the living
	var best: Person = null
	var bd := INF
	for p in people:
		if p.dead or p.downed or p.away != null:
			continue
		var d := Vector2(p.x - z.x, p.y - z.y).length()
		if d < bd:
			bd = d
			best = p
	if best != null:
		z.hunt_id = String(best.id)
	return best


func _chase(z: Zombie, dt: float) -> void:
	var prey := _prey_of(z)
	if prey == null:
		z.state = "wander"
		z.hunt_id = ""
		return
	var dx := prey.x - z.x
	var dy := prey.y - z.y
	var dist := sqrt(dx * dx + dy * dy)
	if dist > chase_give_up:
		z.state = "wander"
		z.hunt_id = ""
		z.path = []
		return
	if dist < 0.7:
		z.facing = facing_of(dx, dy, z.facing)
		z.attack_t -= dt
		if z.attack_t <= 0.0:
			z.attack_t = 1.3
			_bite(z, prey)
		return
	z.repath -= dt
	if z.repath <= 0.0 or z.path.is_empty() or z.path_i >= z.path.size():
		var me := Vector2(z.x, z.y)
		var you := Vector2(prey.x, prey.y)
		if dist < 14.0 and path_z.sight(world.solid_z, me, you, 0.3):
			z.path = [you]
			z.path_i = 0
			z.repath = 0.25 + rng.randf() * 0.15
		else:
			z.path = path_z.find(world.solid_z, z.x, z.y, prey.x, prey.y)
			z.path_i = 0
			z.repath = clampf(dist * 0.05, 0.6, 2.5) + rng.randf() * 0.5
			if z.path.is_empty():
				z.state = "wander"
				z.hunt_id = ""
				return
	var slow := z.speed * (0.85 if z.limp else 1.0)
	_follow(z, slow * 1.1, dt)


## The crowd pass on a grid of one tile: the pairs the colony asks (each pair once, nearer than sqrt(0.3)), not the square of everything.
func _separate() -> void:
	if not grid_separate:
		var t_old := Time.get_ticks_usec()
		super()
		sep_usec += Time.get_ticks_usec() - t_old
		return
	var t_in := Time.get_ticks_usec()
	var zs := zombies
	var n := zs.size()
	_grid.clear()
	for i in n:
		var a: Zombie = zs[i]
		if a.state == "dead" or a.state == "dying":
			continue
		var key := floori(a.y) * GRID_W + floori(a.x)
		var cell = _grid.get(key)
		if cell == null:
			_grid[key] = [i]
		else:
			cell.append(i)
	for i in n:
		var a: Zombie = zs[i]
		if a.state == "dead" or a.state == "dying":
			continue
		var cx := floori(a.x)
		var cy := floori(a.y)
		var a_still := a.state == "still"
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cell = _grid.get((cy + dy) * GRID_W + cx + dx)
				if cell == null:
					continue
				for j in cell:
					if j <= i:
						continue
					var b: Zombie = zs[j]
					if a_still and b.state == "still":
						continue
					var ex := b.x - a.x
					var ey := b.y - a.y
					var d2 := ex * ex + ey * ey
					if d2 > 0.3 or d2 < 1e-6:
						continue
					var dist := sqrt(d2)
					var push := (0.55 - dist) * 0.5
					var ux := ex / dist
					var uy := ey / dist
					var ma := a.state != "attack"
					var mb := b.state != "attack"
					if ma:
						_nudge(a, -ux * push * (1.0 if mb else 2.0), -uy * push * (1.0 if mb else 2.0))
					if mb:
						_nudge(b, ux * push * (1.0 if ma else 2.0), uy * push * (1.0 if ma else 2.0))
	sep_usec += Time.get_ticks_usec() - t_in


# ---------------------------------------------------------------------- saving --

## Called by main.gd before a save is written (SaveGame has no hook of its own): the awake dead that are of the town's records go back to sleep (their place and hit points
## kept), so that the whole population of the street is the field's compact array; the wave's dead have no record and are saved the old way. Parts with `pre_save` are told.
func pre_save() -> void:
	if field != null:
		field.sleep_all()
	for m in _stepped_parts():
		if m.has_method("pre_save"):
			m.pre_save()


## Before a save is read (SaveGame `apply`, hook H11 of WP5): the parts re-make what a load needs to find (the rescued, the base, the perimeter's sections), in the plan's order.
## Returns what `restore_load` needs to undo it.
func prepare_load(data: Dictionary):
	var before := {}
	for name in ["rescue", "base", "perimeter"]:
		var m = get(name)
		if m != null and m.has_method("prepare_load"):
			before[name] = m.prepare_load(data)
	return before


func restore_load(before) -> void:
	if typeof(before) != TYPE_DICTIONARY:
		return
	for name in before:
		var m = get(name)
		if m != null and m.has_method("restore"):
			m.restore(before[name])
