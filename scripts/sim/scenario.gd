## The run: its length, the goal, and when it is over. Round 1 only needs the
## start of a run, the day count and defeat when nobody is left. STUB: the run
## builder fills this in.
extends RefCounted

## The run lasts this many days (the Big Night and the rescue come in round 2).
const TOTAL_DAYS := 30

var sim


func setup(s) -> void:
	sim = s


func start() -> void:
	pass


## Every step: detect defeat (every survivor dead or turned) and set sim.over.
func update(_dt: float) -> void:
	pass


## "DAY 7 OF 30" style numbers for the HUD.
func day() -> int:
	return sim.day


func total_days() -> int:
	return TOTAL_DAYS


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
