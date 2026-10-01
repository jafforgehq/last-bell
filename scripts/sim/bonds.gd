## Bonds: who is close to whom (friend, family, mentor), from map.json. Being near a
## bonded person steadies a person, and losing one hurts. (Round 4: the stub with the
## agreed interface; the PEOPLE builder fills it in.)
extends RefCounted

var sim


func setup(s) -> void:
	sim = s


func start() -> void:
	pass


## This person's bonds: [{"who": Person, "kind": String}].
func of(_p) -> Array:
	return []


## Whether a bonded person (alive, up and on the map) is within `tiles` of this one.
func near(_p, _tiles: float) -> bool:
	return false


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
