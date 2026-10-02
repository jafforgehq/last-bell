## Plays the sounds baked from the web version's synthesiser: gunshots, the
## bell, groans, claws on the wall, hammering, plus three ambience loops
## (wind, crickets at night, the moan of the horde), and the menu sounds.
##
## The one-shots play on the `SFX` bus, the loops on `Ambience` and the menu sounds on
## `UI` (see buses.gd: the four buses are made here, and their volumes are the player's
## settings).
extends Node

const Buses := preload("res://scripts/audio/buses.gd")

const POOL := 24
## The menu sounds have a small pool of their own, so a burst of clicks never takes a
## voice from the game's sounds.
const UI_POOL := 4
## The menu sounds (made by tools/make_ui_sounds.py). They are declared here, not in the
## map data, which is the baked game's.
const UI_SOUNDS := {
	"ui_click": ["res://assets/audio/ui_click_0.wav"],
	"ui_confirm": ["res://assets/audio/ui_confirm_0.wav"],
	"ui_error": ["res://assets/audio/ui_error_0.wav"],
	"ui_open": ["res://assets/audio/ui_open_0.wav"],
	"ui_close": ["res://assets/audio/ui_close_0.wav"],
}
## The sounds of a car trip (round 15, made by tools/make_car_sounds.py): a door opening and closing, the engine
## starting, the gate's motor. Declared here like the menu sounds and played the same way as the game's own one-shots,
## on the SFX bus: sound.play("car_door_open").
const CAR_SOUNDS := {
	"car_door_open": ["res://assets/audio/car_door_open.wav"],
	"car_door_close": ["res://assets/audio/car_door_close.wav"],
	"car_engine_start": ["res://assets/audio/car_engine_start.wav"],
	"car_gate_motor": ["res://assets/audio/car_gate_motor.wav"],
}

var streams := {} # name -> Array[AudioStream]
var players: Array = []
var ui_players: Array = []
var next := 0
var ui_next := 0
var wind: AudioStreamPlayer
var crickets: AudioStreamPlayer
var moan: AudioStreamPlayer
var muted := false
var cricket_level := 0.0
var moan_level := 0.0


func setup(sounds: Dictionary) -> void:
	# a new game starts with the sound on, whatever the last one left the bus at
	Buses.hud_muted = false
	Buses.apply_all()
	for name in sounds:
		var list: Array = []
		for path in sounds[name]:
			var s = load(path)
			if s != null:
				list.append(s)
		streams[name] = list
	for name in UI_SOUNDS:
		if not streams.has(name):
			streams[name] = _load_list(UI_SOUNDS[name])
	for name in CAR_SOUNDS:
		if not streams.has(name):
			streams[name] = _load_list(CAR_SOUNDS[name])
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	for i in UI_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		ui_players.append(p)
	wind = _loop("wind_loop", 0.8)
	crickets = _loop("crickets_loop", 0.0)
	moan = _loop("moan_loop", 0.0)


## The sounds at `paths` that are there (a file that is not imported yet is skipped,
## so a checkout that has not been imported plays on without them).
func _load_list(paths: Array) -> Array:
	var list: Array = []
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var s = load(path)
		if s != null:
			list.append(s)
	return list


func _loop(name: String, level: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Ambience"
	add_child(p)
	if not streams.has(name) or streams[name].is_empty():
		return p
	var s: AudioStreamWAV = streams[name][0]
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	p.stream = s
	p.volume_db = linear_to_db(maxf(level, 0.0001))
	p.play()
	return p


## `pitch_var` is the random wobble round the normal pitch; `pitch_scale` moves the
## whole sound up or down (0.72 is the deep groan of a brute, 1.3 a runner's thin one).
func play(name: String, level: float = 1.0, pitch_var: float = 0.04, pitch_scale: float = 1.0) -> void:
	if muted or not streams.has(name):
		return
	var list: Array = streams[name]
	if list.is_empty():
		return
	var p: AudioStreamPlayer = players[next]
	next = (next + 1) % players.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = linear_to_db(maxf(level, 0.0001))
	p.pitch_scale = maxf(0.05, (1.0 + (randf() - 0.5) * 2.0 * pitch_var) * pitch_scale)
	p.play()


## A menu sound (`ui_click`, `ui_confirm`, `ui_error`, `ui_open`, `ui_close`) on the
## `UI` bus, from the menu sounds' own few voices. Silent while the game is muted.
func ui(name: String, level: float = 1.0, pitch_var: float = 0.02) -> void:
	if muted or not streams.has(name) or ui_players.is_empty():
		return
	var list: Array = streams[name]
	if list.is_empty():
		return
	var p: AudioStreamPlayer = ui_players[ui_next]
	ui_next = (ui_next + 1) % ui_players.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = linear_to_db(maxf(level, 0.0001))
	p.pitch_scale = maxf(0.05, 1.0 + (randf() - 0.5) * 2.0 * pitch_var)
	p.play()


## night: 0..1 darkness; horde: 0..1 how close and many the dead are.
func set_ambience(night: float, horde: float, dt: float) -> void:
	var k := minf(1.0, dt * 2.0)
	cricket_level = lerpf(cricket_level, night * (1.0 - horde * 0.7), k)
	moan_level = lerpf(moan_level, horde, k)
	if crickets != null:
		crickets.volume_db = linear_to_db(maxf(cricket_level, 0.0001))
	if moan != null:
		moan.volume_db = linear_to_db(maxf(moan_level, 0.0001))


## The HUD's sound button. It mutes the Master bus and, apart from that, the volume
## settings stay as they are: the Master bus is muted while this or a volume of 0 asks for it.
func set_muted(m: bool) -> void:
	muted = m
	Buses.set_hud_muted(m)
