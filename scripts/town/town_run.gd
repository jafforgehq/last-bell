## One town for the benchmarks and the standalone scene (`--town-spike`, tools/town_bench.gd): the real TownSim on a generated town and its World node, the avatar the one
## survivor (Ruth) and the player. `update(dt)` takes ONE step of the rules (the colony's `update`, which steps the field first) and keeps the microseconds each part took.
extends RefCounted

const TownBoot := preload("res://scripts/town/town_boot.gd")

var sim
var field
var town: Dictionary
var avatar_p
var prof := {"total": 0, "steps": 0}
var invulnerable := false
var elapsed := 0.0


## `world` is the World node built from `town.data`. `cap` is the active cap, `ai_chase` the new chase state (else the colony's hunt), `grid_sep` the grid crowd pass (else the square).
func _init(the_town: Dictionary, the_world, fx, cap: int = 100, ai_chase: bool = true, grid_sep: bool = true) -> void:
	town = the_town
	sim = TownBoot.sim(TownBoot.from_town(town), the_world, fx)
	sim.chase_on = ai_chase
	sim.grid_separate = grid_sep
	sim.start_run(1, int(town.seed))
	sim.minutes = 10.0 * 60.0
	sim.phase = "day"
	avatar_p = sim.people[0]
	avatar_p.hp = 100.0
	sim.avatar.set_player(avatar_p)
	sim.jobs.clear()
	sim.tactics.chores = false
	field = sim.field
	field.active_cap = cap
	sim.events.clear()


func update(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	elapsed += dt
	if invulnerable:
		avatar_p.hp = 100.0
		avatar_p.downed = false
	sim.update(dt)
	sim.events.clear()
	prof.total += Time.get_ticks_usec() - t0
	prof.steps += 1


func prof_reset() -> void:
	for k in prof:
		prof[k] = 0
