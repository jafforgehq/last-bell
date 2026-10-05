## The sounds of a fight that the baked set (map.json's `sounds`) does not have (P-COMBAT, made by tools/make_combat_sounds.py): the shots of the
## hunting rifle and the M1 (the baked `shot_rifle` is the carbine's), a bullet in flesh, on a brute's steel and in a wall, a blow in the air and
## one that lands, the click of an empty gun, the magazine, the bolt, a shell into the tube, the pump and a casing on the ground. The baked
## `shot_pistol`, `shot_rifle`, `shot_shotgun` and `thud` were made again by the same tool, under the same names.
## Declared here, like the menu's and the car's, and played the same way (`sound.play("hit_flesh")`); scripts/audio/sound.gd loads them.
extends RefCounted

const DIR := "res://assets/audio/"
## name -> how many files there are (`<name>_0.wav` ...).
const COUNTS := {
	"shot_service": 1, "shot_hunting": 1,
	"hit_flesh": 3, "hit_plate": 3, "hit_wall": 2,
	"melee_swing": 2, "melee_hit": 2,
	"dry_click": 1, "mag_out": 1, "mag_in": 1, "bolt": 1, "shell_in": 2, "pump": 1, "casing": 2,
}


## name -> the paths of its files.
static func sounds() -> Dictionary:
	var out := {}
	for name in COUNTS:
		var list: Array = []
		for i in int(COUNTS[name]):
			list.append("%s%s_%d.wav" % [DIR, name, i])
		out[name] = list
	return out
