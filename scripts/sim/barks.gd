## Barks: the short lines people say when something happens (the bell, a wound, a
## friend down), from assets/data/barks.json. Rules only: it adds {"type": "bark",
## "who": id, "text": String, "context": String} events and the view draws them as
## speech bubbles. (Round 4: the stub with the agreed interface; the PEOPLE builder
## fills it in.)
extends RefCounted

var sim


func setup(s) -> void:
	sim = s


func start() -> void:
	pass


func update(_dt: float) -> void:
	pass


## This person says something fitting for `context` (if they are able and it is not
## too soon after the last time).
func say(_p, _context: String) -> void:
	pass


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
