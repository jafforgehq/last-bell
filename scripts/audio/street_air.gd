## The quiet of the streets by day (round 12, "the living streets"): in a settlement game, with some of the dead about
## the streets (`sim.streets.street_dead() > 0`), now and then one of them groans a long way off. A rare, soft sound
## (the groan the dead already have, at a low volume and a lower pitch) from the place the straggler is, so that it
## comes from its side of the screen (an AudioStreamPlayer2D: the camera is the listener) and fades with the distance.
##
## - At most one every GAP_MIN to GAP_MAX seconds; never at night, at dusk or at dawn (the real groans are loud then),
##   never in the classic start, the tutorial or the title, and none while the game is paused, a menu is up or the game
##   is over (the timer waits, it does not run down).
## - One that is within NEAR of the camera is left to the real groans (sim.gd makes an event for every one of the dead,
##   main.gd plays them): this is for the ones that are out of sight.
## - Nothing here touches the rules.
extends Node2D

const GD := preload("res://scripts/game_data.gd")

const TILE := GD.TILE
## The seconds between two groans (a new one is drawn each time).
const GAP_MIN := 12.0
const GAP_MAX := 25.0
## How quiet (decibels: the real groan is 0), how low (pitch scale: lower sounds further off and heavier), how far it
## carries (tiles) and how near a straggler may be to the camera (tiles) for this to be its groan.
const LEVEL_DB := -10.0
const PITCH_MIN := 0.78
const PITCH_MAX := 0.92
const REACH := 70.0
const NEAR := 9.0
const POOL := 2
const BUS := "Ambience"

var game
var plays := 0
var last := {}

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _players: Array = []
var _next := 0


## `g` is main.gd (or a stand-in: it is asked for sim, speed, menu_open, sound and cam_center).
func setup(g) -> void:
	game = g
	_rng.randomize()
	_t = _gap()
	for i in POOL:
		var p := AudioStreamPlayer2D.new()
		p.bus = BUS
		p.max_distance = REACH * TILE
		add_child(p)
		_players.append(p)


func _gap() -> float:
	return _rng.randf_range(GAP_MIN, GAP_MAX)


## Whether it is a quiet day of a settlement game with the dead in the streets and the sound to hear it: the only time
## this plays and the only time its timer runs.
func quiet_day() -> bool:
	if game == null:
		return false
	var sim = game.sim
	if sim == null or sim.get("town") == null or not bool(sim.town.on):
		return false
	if String(sim.phase) != "day" or String(sim.over) != "":
		return false
	if int(game.speed) <= 0 or bool(game.menu_open):
		return false
	var sound = game.sound
	if sound == null or bool(sound.muted):
		return false
	return sim.streets != null and sim.streets.street_dead() > 0


## One of the dead of the streets that is out of sight, at random (null when there is none).
func pick():
	var sim = game.sim
	var far: Array = []
	for z in sim.zombies:
		if z.state != "wander" and z.state != "hunt":
			continue
		if Vector2(z.x, z.y).distance_to(game.cam_center) > NEAR:
			far.append(z)
	if far.is_empty():
		return null
	return far[_rng.randi() % far.size()]


## Called every frame with the frame's time (real seconds).
func update(dt: float) -> void:
	if not quiet_day():
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = _gap()
	var z = pick()
	if z != null:
		groan(Vector2(z.x, z.y))


## A groan from this place (tiles), if the game has the sound.
func groan(at: Vector2) -> void:
	var list: Array = game.sound.streams.get("groan", [])
	if list.is_empty():
		return
	var p: AudioStreamPlayer2D = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = list[_rng.randi() % list.size()]
	p.position = at * TILE
	p.volume_db = LEVEL_DB + _rng.randf_range(-3.0, 0.0)
	p.pitch_scale = _rng.randf_range(PITCH_MIN, PITCH_MAX)
	p.play()
	plays += 1
	last = {"x": at.x, "y": at.y, "db": p.volume_db, "pitch": p.pitch_scale}
