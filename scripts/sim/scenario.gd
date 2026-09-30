## The run: its length, the goal, and when it is over. Round 1 needs the start
## of a run, the day count and defeat when nobody is left; round 2 adds the Big
## Night and the rescue.
##
## Events this module adds to sim.events:
##   {"type": "over", "result": "defeat"}   the run has ended (sim.over is set)
## (sim.gd adds {"type": "day_start", "day": N} at each dawn; main.gd autosaves on it.)
extends RefCounted

## The run lasts this many days (the Big Night and the rescue come in round 2).
const TOTAL_DAYS := 30

var sim


func setup(s) -> void:
	sim = s


## Nothing to set up: Sim.start_run already starts a run on day 1 at 07:00.
func start() -> void:
	pass


## Every step: the run is lost when every survivor is dead or turned. Someone
## downed but not dead, or away on a trip, still counts as alive. Sets sim.over
## once; the rules stop stepping after that.
func update(_dt: float) -> void:
	if sim.over != "" or sim.people.is_empty():
		return
	for p in sim.people:
		if not p.dead:
			return
	sim.over = "defeat"
	sim.events.append({"type": "over", "result": "defeat"})
	sim.events.append({"type": "banner", "text": "Everyone is gone", "sub": "Nobody is left to hold the wall"})


## "DAY 7 OF 30" style numbers for the HUD.
func day() -> int:
	return sim.day


func total_days() -> int:
	return TOTAL_DAYS


## What the command line asks of a run, from the user arguments of the process:
## {} (no choice: the caller starts its default run), {"difficulty": 0 to 2,
## "seed": n} for `--new=<difficulty>` and `--seed=<n>` (a seed alone means a
## standard run), or {"load": path} for `--load=<path>`, which wins over the
## others. Values that are not whole numbers are ignored.
static func run_from_args(args: Array) -> Dictionary:
	var out := {}
	var load_path := ""
	for arg in args:
		var text := String(arg)
		if not text.begins_with("--"):
			continue
		var kv := text.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		var value := kv[1]
		match kv[0]:
			"new":
				if value.is_valid_int():
					out["difficulty"] = clampi(value.to_int(), 0, 2)
			"seed":
				if value.is_valid_int():
					out["seed"] = value.to_int()
					if not out.has("difficulty"):
						out["difficulty"] = 1
			"load":
				if value != "":
					load_path = value
	if load_path != "":
		return {"load": load_path}
	return out


## Nothing of its own to keep: the outcome is sim.over, which the save holds.
func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
