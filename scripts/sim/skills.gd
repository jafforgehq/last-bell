## Skills grow with use: a person who shoots a lot shoots better, one who mends a lot
## builds faster; up to three points over where they started. Each person has their
## own copy (`Person.skills`). (Round 4: the stub with the agreed interface; the PEOPLE
## builder fills it in.)
extends RefCounted

var sim


func setup(s) -> void:
	sim = s


func start() -> void:
	pass


## How many points this person has gained per skill since the run began: {skill: n}.
func gained(_p) -> Dictionary:
	return {}


## Credit for work done: `kind` is "kills", "melee", "mended", "treated" or "crafted".
func credit(_p, _kind: String, _amount: float) -> void:
	pass


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
