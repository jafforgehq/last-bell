## The pump gun's blast and the weight of a blow (the SOUND pass): the shot of the shotgun is one of three in the open or one of three in a room (the tail is short in the
## open, with one slap-back from across the street, and dense and dull in a house), and a kill by the blade or the butt has a wetter sound laid on the thud of the blow.
## The reload's clicks, the pump's rack, the empty gun's click, the swoosh and the thud are the same names the game always played (`shell_in`, `pump`, `dry_click`,
## `melee_swing`, `melee_hit`) with better files (scripts/audio/foley.gd OVERRIDES, sound.gd). Render and audio only: it reads where a shot was and plays; the rules never ask it anything.
##
## combat_fx.gd calls `shot` (from `shot_sound`) and plays `melee_kill` (from `kill`); everything else is what was there.
extends RefCounted

const Foley := preload("res://scripts/audio/foley.gd")

var sound
## Counts for the report: shots by room.
var played := {"gun_out": 0, "gun_in": 0}


func _init(sound_node = null) -> void:
	sound = sound_node


## The shot of a gun (the rules' "shot" event `e`: x, y, gun) heard from `listener` (tiles). True when this played it (the pump gun, with its own files there); false: the caller plays
## what it always did.
func shot(e: Dictionary, listener: Vector2) -> bool:
	if sound == null or String(e.get("gun", "")) != "shotgun":
		return false
	var at := Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
	var room := _indoors(at)
	var name := "blast_in" if room else "blast_out"
	if not sound.streams.has(name) or (sound.streams[name] as Array).is_empty():
		return false
	var gain: float = float(Foley.LEVEL_DB["gun_in" if room else "gun_out"])
	var near := clampf(1.0 - at.distance_to(listener) / 50.0, 0.12, 1.0) * randf_range(0.92, 1.0)
	sound.play(name, near * db_to_linear(gain), 0.04)
	played["gun_in" if room else "gun_out"] = int(played["gun_in" if room else "gun_out"]) + 1
	return true


## Whether a place is inside a house: the town's rules know (`sim.houses.house_at`), else the ground says (a floor), else not.
func _indoors(at: Vector2) -> bool:
	var scape = sound.get("scape") if sound != null else null
	if scape == null:
		return false
	return bool(scape.indoors_shot(at))
