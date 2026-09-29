## Plays the sounds baked from the web version's synthesiser: gunshots, the
## bell, groans, claws on the wall, hammering, plus three ambience loops
## (wind, crickets at night, the moan of the horde).
extends Node

const POOL := 24

var streams := {} # name -> Array[AudioStream]
var players: Array = []
var next := 0
var wind: AudioStreamPlayer
var crickets: AudioStreamPlayer
var moan: AudioStreamPlayer
var muted := false
var cricket_level := 0.0
var moan_level := 0.0


func setup(sounds: Dictionary) -> void:
	for name in sounds:
		var list: Array = []
		for path in sounds[name]:
			var s = load(path)
			if s != null:
				list.append(s)
		streams[name] = list
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	wind = _loop("wind_loop", 0.8)
	crickets = _loop("crickets_loop", 0.0)
	moan = _loop("moan_loop", 0.0)


func _loop(name: String, level: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
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


func play(name: String, level: float = 1.0, pitch_var: float = 0.04) -> void:
	if muted or not streams.has(name):
		return
	var list: Array = streams[name]
	if list.is_empty():
		return
	var p: AudioStreamPlayer = players[next]
	next = (next + 1) % players.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = linear_to_db(maxf(level, 0.0001))
	p.pitch_scale = 1.0 + (randf() - 0.5) * 2.0 * pitch_var
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


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)
