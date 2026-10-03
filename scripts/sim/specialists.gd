## Specialists (round 20, slice 4): a stub the sim wires in until its builder replaces the body. See
## docs/superpowers/plans/2026-10-03-round-20.md for the contract. Inactive (`enabled` false, or no avatar) it changes nothing.
extends RefCounted

var sim
var enabled := true


func setup(s) -> void:
	sim = s


func start() -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game, not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != ""


func update(_dt: float) -> void:
	pass
