## Wounds, bleeding, bandages, the downed, healing in bed and infection.
## STUB: the medical builder fills this in; the rules already call every
## method below. The defaults keep today's behaviour (a person at 0 health is
## downed for good).
extends RefCounted

var sim


func setup(s) -> void:
	sim = s


func start() -> void:
	pass


## Every step: bleeding, bleed-out timers, healing in bed, infection, turning.
func update(_dt: float) -> void:
	pass


## A multiplier (1.0 normal) for how well a person works or shoots, for
## example less when badly hurt.
func perf(_p) -> float:
	return 1.0


## A goal the rules walk a person to, {"x", "y", "face", "what"}, for a healer
## with a patient or a patient on the way to bed; or null.
func goal_for(_p):
	return null


## A zombie just bit `p` (health already reduced, blood and alert done).
## Start a wound and roll for infection.
func after_bite(_z, _p) -> void:
	pass


## A zombie clawing at a wall section may scratch a defender right behind it.
func on_wall_claw(_z, _seg) -> void:
	pass


## `p` reached 0 health ("bite", "bleeding", "hunger", "thirst"...). The default
## is the old behaviour: downed for good, with the alert.
func on_downed(p, _cause: String) -> void:
	p.downed = true
	p.moving = false
	sim.alert("down-%s" % p.id, "danger", "%s is down" % p.first, "Get them to Ana", Vector2(p.x, p.y), 60.0)


## Give `p` a wound: kind "scratch" or "bite" (a bite rolls for infection).
## Used by the scavenging module for injuries outside the walls.
func add_wound(_p, _kind: String) -> void:
	pass


## `p` dies for good (cause is a short word such as "scavenging").
func kill(p, _cause: String) -> void:
	p.dead = true
	p.downed = true


## Whether the HUD should offer "Treat" for `p` (wounded, bleeding or infected).
func can_treat(_p) -> bool:
	return false


## Whether the HUD should offer "Send out" for `p` (infected).
func can_send_out(_p) -> bool:
	return false


## "", "feverish" or "delirious": what the panel shows for an infected person.
func infection_stage(_p) -> String:
	return ""


## Marks for the card and panel: wound, fever, downed, resting...
func status_of(_p) -> Array:
	return []


## Handles the HUD buttons "treat" and "sendout" for the selection
## {"kind": "person", "ref": Person}. True if it took the button.
func gizmo(_id: String, _sel) -> bool:
	return false


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
