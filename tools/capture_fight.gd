extends "res://tools/capture_tap.gd"
## `--capture=fight`: Ruth's hands in a fight, for a movie run (docs/audio-capture.md): `engage` (capture_tap.gd) every frame, and waves of the dead put round her, one every WAVE_S seconds
## (`main.stage_fight`, the `--fight=` staging): from the street 12 tiles south with the gun, and two of them standing at her feet that she deals with by the butt of the gun (F: the swoosh, the
## thud, the kill). `--capture-waves=N` for fewer waves, 0 for the sim's own dead alone (a night's). The camera follows her. Pair it with `--weapon=shotgun` and a stage.
## The crew's own shots are the sim's.

const WAVE_S := 11.0
## n and kind, how far south of her, whether she fires, whether they stand where they are until hurt
const WAVES := [
	{"n": "4,walker", "d": 12.0, "gun": true, "still": false},
	{"n": "2,walker", "d": 1.4, "gun": false, "still": true},
	{"n": "6,mix", "d": 12.0, "gun": true, "still": false},
	{"n": "2,walker", "d": 1.4, "gun": false, "still": true},
	{"n": "7,mix", "d": 12.0, "gun": true, "still": false},
]

var _wave_t := 0.0
var _wave_i := 0
var _gun := true


## A night's dead come to a fence of their own choosing (a different one in each run): with nobody in reach she walks toward the nearest of the dead that is after the base (never nearer than
## 10 tiles), as a player would go to the wall that is under attack.
func _seek(sim, me) -> void:
	var best = null
	var best_d := 1.0e9
	for z in sim.zombies:
		if z.state != "approach" and z.state != "attack" and z.state != "breach" and z.state != "hunt" and z.state != "chase":
			continue
		var d := Vector2(z.x - me.x, z.y - me.y).length()
		if d < best_d:
			best_d = d
			best = z
	if best == null or best_d < 10.0:
		walk_keys(Vector2.ZERO, false)
		return
	walk_keys(walk_toward(Vector2(best.x, best.y), 9.0), false)


func _hands(dt: float) -> void:
	var sim = main.sim
	var me = sim.avatar.player()
	if me == null:
		return
	_wave_t -= dt
	var table: Array = WAVES
	if String(opts.get("mode", "")) == "melee":
		# `--capture-mode=melee`: three walkers at a time come at her from 4.5 tiles and she fights them with the butt of the gun, so that the dead are at arm's length growling and biting (the voices at 2.5 tiles of
		# docs/audio-mix.md, as a real run has them)
		table = [{"n": "3,walker", "d": 4.5, "gun": false, "still": false}, {"n": "3,walker", "d": 4.5, "gun": false, "still": false}, {"n": "3,walker", "d": 4.5, "gun": false, "still": false}]
	var waves := int(opts.get("waves", table.size()))
	if _wave_t <= 0.0 and _wave_i < mini(table.size(), waves):
		var w: Dictionary = table[_wave_i]
		var at := Vector2(me.x + (3.0 if _wave_i % 2 == 0 else -4.0), me.y + float(w.d))
		if float(w.d) < 3.0:
			at = Vector2(me.x, me.y + float(w.d))
		main.stage_fight("%s,%.1f,%.1f,%s" % [w.n, at.x, at.y, "0.6,still" if bool(w.still) else "3.0"])
		_gun = bool(w.gun)
		_wave_i += 1
		_wave_t = WAVE_S
	if engage(dt, 22.0 if waves > 0 else 14.0, _gun):
		walk_keys(Vector2.ZERO, false)
	elif waves == 0:
		_seek(sim, me)
	main.cam_hold = 0.0    # (the camera follows her, as in a real run: a screenshot's staging has it stay put)
	if frame % 150 == 0:
		print("CAPTURE fight frame %d: shots %d, swings %d, mag %d, ammo %d, wave %d" % [frame, shots, swings, int(me.mag), int(sim.stock.ammo), _wave_i])
