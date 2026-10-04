## One step of the town (feature/town-core): what `RaidRun.update` does for a place (the people, the dead, the crowd pass) with the dormant field's
## wake and sleep in front of it. Built on a map made by town_gen.gd and the real World node of it (the walking grids and the pictures); the avatar is
## the one survivor (Ruth's roster entry) and is the player of the sim.
##
## `update(dt)` takes ONE step of the rules (1/30 s, StepClock.STEP) and keeps the microseconds each part took (`prof`), for the overlay and the bench.
extends RefCounted

const TownSim := preload("res://scripts/town/town_sim.gd")
const DormantDead := preload("res://scripts/town/dormant_dead.gd")

var sim
var field
var town: Dictionary
var avatar_p
var prof := {"field": 0, "people": 0, "zombies": 0, "separate": 0, "cleanup": 0, "total": 0, "steps": 0}
var invulnerable := false
var shots := 0
var elapsed := 0.0


## `world` is the World node built from `town.data`. `cap` is the active cap, `ai_chase` the new chase state (else the base's hunt),
## `grid_sep` the grid crowd pass (else the base's square).
func _init(the_town: Dictionary, the_world, fx, cap: int = 100, ai_chase: bool = true, grid_sep: bool = true) -> void:
	town = the_town
	sim = TownSim.new(town.data, the_world, fx)
	sim.phase = "day"
	sim.minutes = 10.0 * 60.0
	sim.stock.ammo = 400.0
	sim.chase_on = ai_chase
	sim.grid_separate = grid_sep
	avatar_p = sim.add_person(_ruth(town.data))
	sim.jobs.clear()
	sim.tactics.chores = false
	avatar_p.drafted = false
	var at: Vector2 = town.start.pos
	avatar_p.x = at.x
	avatar_p.y = at.y
	avatar_p.hp = 100.0
	sim.avatar.set_player(avatar_p)
	field = DormantDead.new()
	field.setup(sim, town)
	field.active_cap = cap
	field.load_records(town.dead)
	sim.on_noise = _on_noise
	sim.events.clear()


## Ruth's entry of the base roster (assets/data/map.json `people`), the only one the spike needs.
static func _ruth(data: Dictionary) -> Dictionary:
	var base := preload("res://scripts/game_data.gd").load_all()
	for p in base.people:
		if String(p.id) == "ruth":
			return p
	return base.people[0]


func _on_noise(at: Vector2) -> void:
	shots += 1
	field.noise(at, avatar_p)


func _anchors() -> Array:
	var out: Array = []
	for p in sim.people:
		if not p.dead:
			out.append(Vector2(p.x, p.y))
	return out


## The "they see you" rule of a place (raid_run.gd `_wake_the_dead`): a dead one that stands or wanders within NOTICE_R of a living person with a
## clear line goes after them. Only the real ones are asked.
func _notice() -> void:
	for z in sim.zombies:
		if z.state != "still" and z.state != "wander":
			continue
		for p in sim.people:
			if p.dead or p.downed:
				continue
			var dx: float = p.x - z.x
			var dy: float = p.y - z.y
			if dx * dx + dy * dy < 49.0 and sim.path_z.sight(sim.world.solid_z, Vector2(z.x, z.y), Vector2(p.x, p.y), 0.15):
				sim.start_chase(z, p)
				break


func update(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	elapsed += dt
	sim.t += dt
	if invulnerable:
		avatar_p.hp = 100.0
		avatar_p.downed = false
	# the field: wake, sleep, notice
	field.update(dt, _anchors())
	_notice()
	var t1 := Time.get_ticks_usec()
	for p in sim.people:
		sim._update_person(p, dt)
	var t2 := Time.get_ticks_usec()
	for z in sim.zombies:
		sim._update_zombie(z, dt)
	var t3 := Time.get_ticks_usec()
	sim._separate()
	var t4 := Time.get_ticks_usec()
	var kept: Array = []
	for z in sim.zombies:
		if not z.remove:
			kept.append(z)
	sim.zombies = kept
	sim.events.clear()
	var t5 := Time.get_ticks_usec()
	prof.field += t1 - t0
	prof.people += t2 - t1
	prof.zombies += t3 - t2
	prof.separate += t4 - t3
	prof.cleanup += t5 - t4
	prof.total += t5 - t0
	prof.steps += 1


func prof_reset() -> void:
	for k in prof:
		prof[k] = 0
