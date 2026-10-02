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
	for name in PLAYED + LOOPS + Sound.UI_SOUNDS.keys():
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


func test_the_buses_are_filed_in_order_at_the_end_under_master() -> void:
	# They are made with an explicit position (buses.gd): the web export files a bus made at the default -1 in the wrong
	# slot and the whole mix goes silent in a browser. The order here is the order they are made in.
	Buses.ensure()
	var order := []
	for i in range(1, AudioServer.bus_count):
		order.append(String(AudioServer.get_bus_name(i)))
	eq(order.slice(0, 4), ["SFX", "UI", "Ambience", "Music"], "SFX, UI, Ambience and Music follow Master, in that order")
	eq(String(AudioServer.get_bus_name(0)), "Master", "Master is first")
	for name in Buses.NAMES:
		eq(String(AudioServer.get_bus_send(AudioServer.get_bus_index(name))), "Master", "%s is sent to Master" % name)


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
