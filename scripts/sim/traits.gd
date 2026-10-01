## Traits: two small, visible quirks for each person (Steady, Nervous, Tinkerer...) that
## nudge how they shoot, work and feel. The data is assets/data/traits.json; who has
## which is in map.json. (Round 4: this is the stub with the agreed interface; the
## PEOPLE builder fills it in.)
extends RefCounted

var sim


func setup(s) -> void:
	sim = s


func start() -> void:
	pass


## This person's traits: [{"id", "name", "blurb"}].
func of(_p) -> Array:
	return []


## The product of the traits' multipliers for `key` (1.0 when none apply). Keys: aim,
## reload, repair, craft, bandage, wound, dead_morale, morale_recover, grief, xp.
func mult(_p, _key: String) -> float:
	return 1.0


## The sum of the traits' additive effects for `key` (0.0 when none apply). Keys: cure, bond.
func add(_p, _key: String) -> float:
	return 0.0


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
