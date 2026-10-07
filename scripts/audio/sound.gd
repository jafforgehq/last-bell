## Plays the sounds baked from the web version's synthesiser: gunshots, the
## bell, groans, claws on the wall, hammering, plus three ambience loops
## (wind, crickets at night, the moan of the horde), and the menu sounds.
##
## The one-shots play on the `SFX` bus, the loops on `Ambience` and the menu sounds on
## `UI` (see buses.gd: the four buses are made here, and their volumes are the player's
## settings).
##
## Everything else the base sounds like (the bells, the groans and the brute's roar with their places, the footsteps, the gate, the doors,
## the hum of the generator and the radio, the night bed, the rain, the crows and dogs a long way off, the truck's engine) is the
## SOUNDSCAPE (scripts/audio/soundscape.gd), a child of this node: `attach(game)` gives it the game, `on_event(e)` the rules' events,
## `set_ambience` the darkness and the dead. The guns, the blows, the reload and the casings are played by `play` as they always were.
extends Node

const Buses := preload("res://scripts/audio/buses.gd")
const Soundscape := preload("res://scripts/audio/soundscape.gd")
const CombatSounds := preload("res://scripts/audio/combat_sounds.gd")
const Foley := preload("res://scripts/audio/foley.gd")
const FightSounds := preload("res://scripts/audio/fight_sounds.gd")

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
	# (the polish round: a hover tick, a card sliding onto the table, a soft chime for the briefing and the news, the radio's call tone and
	# the click of a button pressed and let go; tools/make_base_sounds.py)
	"ui_hover": ["res://assets/audio/ui_hover_0.wav"],
	"ui_card": ["res://assets/audio/ui_card_0.wav"],
	"ui_notify": ["res://assets/audio/ui_notify_0.wav"],
	"ui_radio_call": ["res://assets/audio/ui_radio_call_0.wav"],
	"ui_radio_on": ["res://assets/audio/ui_radio_on_0.wav"],
	"ui_radio_off": ["res://assets/audio/ui_radio_off_0.wav"],
}
## More of the sounds the map data names, added to their lists when the files are there (the data has the first of each: groan_0 to 3,
## hammer_0 and 1): four more groans and two more hammer strokes, so that no one pitch and no one blow is heard twice running.
const EXTRA := {
	"groan": ["res://assets/audio/groan_4.wav", "res://assets/audio/groan_5.wav", "res://assets/audio/groan_6.wav", "res://assets/audio/groan_7.wav"],
	"hammer": ["res://assets/audio/hammer_2.wav", "res://assets/audio/hammer_3.wav"],
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
var wind_level := 0.8
## The soundscape (scripts/audio/soundscape.gd).
var scape: Node
## The pump gun's blast and the blow's weight (scripts/audio/fight_sounds.gd; combat_fx.gd asks it).
var gunfight
var _hover_ms := 0


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
	# the gunfight's own (scripts/audio/combat_sounds.gd): the heavier rifles' shots, the hits, the clicks of a reload
	var fight := CombatSounds.sounds()
	for name in fight:
		if not streams.has(name):
			streams[name] = _load_list(fight[name])
	# the SOUND pass (scripts/audio/foley.gd): the pump gun's blast in the open and in a room, the wet blow of a kill, and a better take of five sounds the game already
	# names (the empty gun's click, a shell into the tube, the pump's rack, a blow in the air, a blow that lands): the old files stay for the school and the tests
	for pair in [["blast_out", "gun:out"], ["blast_in", "gun:in"], ["melee_kill", "melee:kill"]]:
		var made: Array = Foley.load_group(String(pair[1]))
		if not made.is_empty():
			streams[String(pair[0])] = made
	for old in Foley.OVERRIDES:
		var better: Array = Foley.load_group(String(Foley.OVERRIDES[old]))
		if not better.is_empty():
			streams[String(old)] = better
	gunfight = FightSounds.new(self)
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
	for name in EXTRA:
		for s2 in _load_list(EXTRA[name]):
			if not streams.has(name):
				streams[name] = []
			streams[name].append(s2)
	wind = _loop("wind_loop", 0.8)
	crickets = _loop("crickets_loop", 0.0)
	moan = _loop("moan_loop", 0.0)
	scape = Soundscape.new()
	scape.name = "Soundscape"
	add_child(scape)
	scape.setup(self)
	# a tick when the pointer comes onto a button that is made from now on (the menus and the pages are made when they are opened)
	if is_inside_tree() and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


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
	# (a game that has been replaced, by Continue or Load, is out of the tree with its voices: they cannot play, and the shell may still ask)
	if muted or not is_inside_tree() or not streams.has(name):
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
	if muted or not is_inside_tree() or not streams.has(name) or ui_players.is_empty():
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


## night: 0..1 darkness; horde: 0..1 how close and many the dead are. The wind is the day's and gives way to the night bed (the
## soundscape's); rain brings it up again; a bed that is silent is stopped (a loop that plays at nothing still costs a voice).
func set_ambience(night: float, horde: float, dt: float) -> void:
	var k := minf(1.0, dt * 2.0)
	cricket_level = lerpf(cricket_level, night * (1.0 - horde * 0.7), k)
	moan_level = lerpf(moan_level, horde, k)
	var rain: float = float(scape.bed_level.get("rain", 0.0)) if scape != null else 0.0
	wind_level = lerpf(wind_level, 0.8 * (1.0 - 0.55 * night) + 0.3 * rain, k)
	if wind != null:
		wind.volume_db = linear_to_db(maxf(wind_level, 0.0001))
	if crickets != null:
		crickets.volume_db = linear_to_db(maxf(cricket_level, 0.0001))
		_keep_playing(crickets, cricket_level)
	if moan != null:
		moan.volume_db = linear_to_db(maxf(moan_level, 0.0001)) + float(Foley.LEVEL_DB["moan"])    # (the SOUND pass: the horde at full was as loud as a groan three tiles away)
		_keep_playing(moan, moan_level)
	if scape != null:
		scape.beds_set(night, horde, dt)


## A loop is played while it is audible: stopped when it has gone (a voice saved), started again when it comes back.
func _keep_playing(p: AudioStreamPlayer, level: float) -> void:
	if p.stream == null:
		return
	if level < 0.003 and p.playing:
		p.stop()
	elif level >= 0.003 and not p.playing:
		p.play()


## Gives the soundscape the game (main.gd: the camera, the people, the hour), and tells it the rules' events as they happen (`on_event`).
func attach(game) -> void:
	if scape != null:
		scape.attach(game)


func on_event(e: Dictionary) -> void:
	if scape != null:
		scape.on_event(e)


## The truck on a trip (scripts/drive/drive_scene.gd): its engine and the road under it, by speed (tiles a second), top speed and throttle.
func engine(speed: float, top: float, throttle: float) -> void:
	if scape != null and not muted:
		scape.engine(speed, top, throttle)


func _process(dt: float) -> void:
	if scape != null:
		scape.update(dt)


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("tb_hover"):
		n.set_meta("tb_hover", true)
		(n as BaseButton).mouse_entered.connect(_on_hover.bind(n))


func _on_hover(b: BaseButton) -> void:
	if muted or not is_instance_valid(b) or b.disabled or not b.is_visible_in_tree():
		return
	var now := Time.get_ticks_msec()
	if now - _hover_ms < 70:
		return
	_hover_ms = now
	ui("ui_hover", 0.55, 0.03)


## The HUD's sound button. It mutes the Master bus and, apart from that, the volume
## settings stay as they are: the Master bus is muted while this or a volume of 0 asks for it.
func set_muted(m: bool) -> void:
	muted = m
	Buses.set_hud_muted(m)
