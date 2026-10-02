extends "res://tests/case.gd"
## The sound table (assets/data/map.json, "sounds") and the menu sounds against every sound the game asks for by name:
## nothing the code plays may be missing (a missing sound is skipped without a word, so a typo would be silence).

const Sound := preload("res://scripts/audio/sound.gd")
const Buses := preload("res://scripts/audio/buses.gd")

## Every name the game plays (sound.play and the menus' ui): the ones named in the code, and the ones it builds from
## the kind of gun and of wall.
const PLAYED := ["bell", "crash", "thud", "stab", "reload", "groan", "bite", "hammer", "shot_pistol", "shot_rifle", "shot_shotgun",
		"scrape_wood", "scrape_stone", "scrape_metal"]
const LOOPS := ["wind_loop", "crickets_loop", "moan_loop"]
const WALL_MATERIALS := ["wood", "stone", "metal"]


func _map() -> Dictionary:
	var f := FileAccess.open("res://assets/data/map.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func test_every_sound_the_game_plays_is_in_the_table_and_its_file_loads() -> void:
	var sounds: Dictionary = _map().get("sounds", {})
	for name in PLAYED + LOOPS:
		check(sounds.has(name), "%s is in the table" % name)
		for path in sounds.get(name, []):
			check(ResourceLoader.exists(path), "%s: %s is imported" % [name, path])
			check(load(path) is AudioStreamWAV, "%s: %s loads as a sound" % [name, path])
		check(not sounds.get(name, []).is_empty(), "%s has at least one file" % name)


func test_every_gun_has_a_shot_and_every_kind_of_wall_has_a_scrape() -> void:
	var map := _map()
	var sounds: Dictionary = map.get("sounds", {})
	for id in map.get("weapons", {}):
		var w: Dictionary = map.weapons[id]
		if w.get("sound") == null:
			# the pike: a melee weapon, which is heard as the stab and never as a shot
			check(id == "pike", "%s has no shot sound: only the pike may be quiet" % id)
			continue
		check(sounds.has("shot_%s" % w.sound), "the %s's shot (shot_%s) is there" % [id, w.sound])
	for mat in WALL_MATERIALS:
		check(sounds.has("scrape_%s" % mat), "claws on %s have a sound" % mat)


func test_the_menu_sounds_are_all_there() -> void:
	for name in Sound.UI_SOUNDS:
		for path in Sound.UI_SOUNDS[name]:
			check(ResourceLoader.exists(path), "%s: %s is imported" % [name, path])


func test_setup_loads_every_sound_and_starts_the_loops() -> void:
	Buses.hud_muted = false
	var s := Sound.new()
	Engine.get_main_loop().root.add_child(s)
	s.setup(_map().get("sounds", {}))
	for name in PLAYED + LOOPS + Sound.UI_SOUNDS.keys() + Sound.CAR_SOUNDS.keys():
		check(s.streams.has(name) and not s.streams[name].is_empty(), "%s was loaded" % name)
	for loop in [s.wind, s.crickets, s.moan]:
		check(loop != null and loop.stream != null and loop.playing, "a loop is playing")
		eq(String(loop.bus), "Ambience", "on the Ambience bus")
		eq(loop.stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "and it loops")
	for p in s.players:
		eq(String(p.bus), "SFX", "the one-shots play on SFX")
	for p in s.ui_players:
		eq(String(p.bus), "UI", "the menu sounds on UI")
	# a sound asked for goes to a player and plays
	s.play("bell", 1.0, 0.0)
	var playing := 0
	for p in s.players:
		if p.playing:
			playing += 1
	eq(playing, 1, "play() starts exactly one voice")
	s.set_muted(true)
	s.play("bell", 1.0, 0.0)
	var after := 0
	for p in s.players:
		if p.playing:
			after += 1
	eq(after, 1, "a muted game starts no more")
	s.set_muted(false)
	Engine.get_main_loop().root.remove_child(s)
	s.free()
	Buses.hud_muted = false
	Buses.apply_all()


## How long each car sound should be (seconds, from and to): a door is a knock, the engine's start a couple of seconds
## with its tail, the gate's motor a second and a half.
const CAR_SOUND_LENGTH := {
	"car_door_open": [0.3, 0.9],
	"car_door_close": [0.3, 0.9],
	"car_engine_start": [2.0, 3.2],
	"car_gate_motor": [1.2, 2.0],
}
## tools/level_sounds.py puts the car sounds' loudest sample at this level (dBFS), give or take.
const CAR_SOUND_PEAK_DB := -8.0
const CAR_SOUND_PEAK_SLACK_DB := 1.5


func test_the_car_sounds_are_declared_imported_and_the_right_length() -> void:
	# round 15: the doors, the engine's start and the gate's motor (tools/make_car_sounds.py)
	for name in CAR_SOUND_LENGTH:
		var path := "res://assets/audio/%s.wav" % name
		check(Sound.CAR_SOUNDS.has(name) and Sound.CAR_SOUNDS[name] == [path], "%s is declared" % name)
		check(ResourceLoader.exists(path), "%s is imported" % path)
		var st = load(path)
		check(st is AudioStreamWAV, "%s loads as a sound" % path)
		if not st is AudioStreamWAV:
			continue
		var want: Array = CAR_SOUND_LENGTH[name]
		check(st.get_length() >= want[0] and st.get_length() <= want[1], "%s is %.2f s long (wanted %.1f to %.1f)" % [name, st.get_length(), want[0], want[1]])
		eq(st.mix_rate, 44100, "%s is 44.1 kHz" % name)
		check(not st.stereo, "%s is mono" % name)
		var head := FileAccess.get_file_as_bytes(path)
		eq(head.decode_u16(20), 1, "%s is plain PCM" % name)
		eq(head.decode_u16(22), 1, "%s has one channel" % name)
		eq(head.decode_u16(34), 16, "%s is 16-bit" % name)
	for name in Sound.CAR_SOUNDS:
		check(CAR_SOUND_LENGTH.has(name), "%s is one the test knows" % name)


func test_the_car_sounds_are_at_their_level_and_play() -> void:
	for name in Sound.CAR_SOUNDS:
		for path in Sound.CAR_SOUNDS[name]:
			var db := _peak_db(path)
			check(absf(db - CAR_SOUND_PEAK_DB) <= CAR_SOUND_PEAK_SLACK_DB, "%s peaks at %.1f dBFS (tools/level_sounds.py wants %.0f)" % [path, db, CAR_SOUND_PEAK_DB])
	Buses.hud_muted = false
	var s := Sound.new()
	Engine.get_main_loop().root.add_child(s)
	s.setup({})
	for name in Sound.CAR_SOUNDS:
		check(s.streams.has(name) and s.streams[name].size() == 1, "%s is loaded by setup" % name)
		var before := 0
		for p in s.players:
			if p.playing:
				before += 1
		s.play(name, 1.0, 0.0)
		var after := 0
		for p in s.players:
			if p.playing:
				after += 1
				eq(String(p.bus), "SFX", "%s plays on SFX" % name)
		eq(after, before + 1, "play(%s) starts one voice" % name)
	Engine.get_main_loop().root.remove_child(s)
	s.free()
	Buses.hud_muted = false
	Buses.apply_all()


func test_the_buses_come_from_a_layout_file_because_add_bus_breaks_the_web_mix() -> void:
	# On the web export every bus made at run time with AudioServer.add_bus() is filed in the wrong slot (the engine hands
	# the web layer -1 whatever position is given), and the mix is wired into a loop that never reaches the speakers: a
	# browser heard nothing. A bus layout loaded at start-up does not go through that, so the buses are in the project's
	# default layout (the web probe of 2026-10-02 measured it: the sources reach the destination only with the file).
	var path := String(ProjectSettings.get_setting("audio/buses/default_bus_layout", ""))
	eq(path, "res://default_bus_layout.tres", "the project loads its default layout")
	check(ResourceLoader.exists(path), "and the file is there")
	var layout = load(path)
	check(layout is AudioBusLayout, "it is a bus layout")
	if not layout is AudioBusLayout:
		return
	var want := ["SFX", "UI", "Ambience", "Music"]
	for i in want.size():
		eq(String(layout.get("bus/%d/name" % (i + 1))), want[i], "bus %d is %s" % [i + 1, want[i]])
		eq(String(layout.get("bus/%d/send" % (i + 1))), "Master", "%s is sent to Master" % want[i])
	# and what the running game has is the same, in the same order
	Buses.ensure()
	for i in want.size():
		eq(String(AudioServer.get_bus_name(i + 1)), want[i], "the running bus %d" % [i + 1])
		eq(String(AudioServer.get_bus_send(i + 1)), "Master", "%s plays through Master" % want[i])


## The loudest sample of a 16-bit PCM wav file, in dBFS (the source files, read straight; -120 for a file it cannot read).
func _peak_db(path: String) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -120.0
	var raw := f.get_buffer(f.get_length())
	var pos := 12
	while pos + 8 <= raw.size():
		var id := raw.slice(pos, pos + 4).get_string_from_ascii()
		var size := raw.decode_u32(pos + 4)
		if id == "data":
			var peak := 0
			var i := pos + 8
			var end := mini(pos + 8 + size, raw.size()) - 1
			while i < end:
				peak = maxi(peak, absi(raw.decode_s16(i)))
				i += 2
			return linear_to_db(maxf(float(peak) / 32768.0, 0.000001))
		pos += 8 + size + (size & 1)
	return -120.0


func test_no_sound_of_the_game_is_a_whisper_next_to_the_rest() -> void:
	# tools/level_sounds.py sets these levels (the baked files were 20 to 50 dB under the menu sounds): gunshots, bites,
	# hammering and the rest of the one-shots must peak above -24 dBFS, the beds (wind, crickets) above -34, and no
	# one-shot may be much louder than the bell or the menu sounds (-5 dBFS).
	var sounds: Dictionary = _map().get("sounds", {})
	for name in PLAYED:
		for path in sounds.get(name, []):
			var db := _peak_db(path)
			check(db >= -24.0, "%s peaks at %.1f dBFS: a whisper (above -24 is the least)" % [path, db])
			check(db <= -3.0, "%s peaks at %.1f dBFS: at the edge of clipping" % [path, db])
	for name in ["wind_loop", "crickets_loop"]:
		for path in sounds.get(name, []):
			var db := _peak_db(path)
			check(db >= -34.0, "%s peaks at %.1f dBFS: too faint to hear" % [path, db])
			check(db <= -12.0, "%s peaks at %.1f dBFS: a bed must sit under the rest" % [path, db])
	for name in Sound.UI_SOUNDS:
		for path in Sound.UI_SOUNDS[name]:
			var db := _peak_db(path)
			check(db >= -14.0 and db <= -3.0, "%s peaks at %.1f dBFS" % [path, db])
