extends "res://tests/case.gd"
## The audio buses (Master, and SFX, UI, Ambience and Music under it), the volumes the
## settings keep for them, the HUD's sound button, and the menu sounds.

const Buses := preload("res://scripts/audio/buses.gd")
const Sound := preload("res://scripts/audio/sound.gd")
const Prefs := preload("res://scripts/prefs.gd")

const PAIRS := [["master", "Master"], ["sfx", "SFX"], ["ui", "UI"], ["ambience", "Ambience"], ["music", "Music"]]


func _fresh() -> void:
	Prefs.path = "user://prefs_test.cfg"
	Prefs.reset()
	Buses.hud_muted = false
	Buses.apply_all()


## Back to how the other tests expect the buses.
func _done() -> void:
	Prefs.reset()
	Buses.hud_muted = false
	Buses.apply_all()


func _sound() -> Node:
	var s := Sound.new()
	Engine.get_main_loop().root.add_child(s)
	return s


func test_the_buses_are_made_under_master_and_only_once() -> void:
	Buses.ensure()
	var n := AudioServer.bus_count
	for bus_name in ["SFX", "UI", "Ambience", "Music"]:
		var i := AudioServer.get_bus_index(bus_name)
		check(i > 0, "%s is there" % bus_name)
		eq(String(AudioServer.get_bus_send(i)), "Master", "%s plays through Master" % bus_name)
	Buses.ensure()
	Buses.apply_all()
	Buses.ensure()
	eq(AudioServer.bus_count, n, "making them again adds none")
	eq(String(AudioServer.get_bus_name(0)), "Master", "Master is still the first")


func test_a_volume_is_an_amplitude_slider_in_decibels() -> void:
	near(Buses.to_db(1.0), 0.0, 0.001, "full volume is 0 dB")
	near(Buses.to_db(0.5), -6.0206, 0.01, "half the amplitude is -6 dB")
	near(Buses.to_db(0.25), -12.0412, 0.01, "a quarter, -12 dB")
	eq(Buses.to_db(0.0), Buses.SILENT_DB, "nothing is the floor")
	eq(Buses.to_db(0.00001), Buses.SILENT_DB, "and so is almost nothing")
	near(Buses.to_db(2.0), 0.0, 0.001, "never louder than full")


func test_each_bus_follows_its_setting() -> void:
	_fresh()
	for pair in PAIRS:
		var bus_name: String = pair[1]
		var i := AudioServer.get_bus_index(bus_name)
		near(AudioServer.get_bus_volume_db(i), 0.0, 0.001, "%s starts at full" % bus_name)
		Prefs.set_value("audio", pair[0], 0.5)
		Buses.apply(bus_name)
		near(AudioServer.get_bus_volume_db(i), -6.02, 0.05, "%s at half" % bus_name)
		check(not AudioServer.is_bus_mute(i), "%s is not muted at half" % bus_name)
		Prefs.set_value("audio", pair[0], 0.0)
		Buses.apply(bus_name)
		check(AudioServer.is_bus_mute(i), "%s is muted at nothing" % bus_name)
		check(Buses.is_silent(bus_name), "and is silent")
		Prefs.set_value("audio", pair[0], 1.0)
		Buses.apply(bus_name)
		check(not AudioServer.is_bus_mute(i) and not Buses.is_silent(bus_name), "%s is back" % bus_name)
	_done()


func test_one_bus_does_not_move_another() -> void:
	_fresh()
	Prefs.set_value("audio", "sfx", 0.2)
	Buses.apply_all()
	near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), Buses.to_db(0.2), 0.001, "effects are quiet")
	for other in ["Master", "UI", "Ambience", "Music"]:
		near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(other)), 0.0, 0.001, "%s is not" % other)
	_done()


func test_the_volumes_are_read_from_the_file_when_the_game_starts() -> void:
	_fresh()
	Prefs.set_value("audio", "ambience", 0.4)
	Prefs.set_value("audio", "master", 0.8)
	Prefs.forget()
	Buses.apply_all()
	near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")), Buses.to_db(0.4), 0.001, "ambience as kept")
	near(AudioServer.get_bus_volume_db(0), Buses.to_db(0.8), 0.001, "master as kept")
	_done()


func test_the_hud_mute_and_the_master_volume_do_not_undo_each_other() -> void:
	_fresh()
	check(not AudioServer.is_bus_mute(0), "sound is on")
	Buses.set_hud_muted(true)
	check(AudioServer.is_bus_mute(0), "the HUD button mutes")
	Buses.set_hud_muted(false)
	check(not AudioServer.is_bus_mute(0), "and unmutes")
	Prefs.set_value("audio", "master", 0.0)
	Buses.apply("Master")
	check(AudioServer.is_bus_mute(0), "a master volume of nothing mutes")
	Buses.set_hud_muted(true)
	Buses.set_hud_muted(false)
	check(AudioServer.is_bus_mute(0), "the button does not unmute a master that is at nothing")
	Prefs.set_value("audio", "master", 1.0)
	Buses.apply("Master")
	check(not AudioServer.is_bus_mute(0), "raising the volume unmutes")
	Buses.set_hud_muted(true)
	Prefs.set_value("audio", "master", 0.7)
	Buses.apply("Master")
	check(AudioServer.is_bus_mute(0), "and a volume change does not undo the button")
	_done()


func test_the_sound_button_still_mutes_the_game() -> void:
	_fresh()
	var s := _sound()
	s.setup({})
	s.set_muted(true)
	check(s.muted and AudioServer.is_bus_mute(0), "muted")
	s.set_muted(false)
	check(not s.muted and not AudioServer.is_bus_mute(0), "and back")
	# the next game starts with the sound on, whatever the last one left
	s.set_muted(true)
	var s2 := _sound()
	s2.setup({})
	check(not AudioServer.is_bus_mute(0), "a new game starts with the sound on")
	s.free()
	s2.free()
	_done()


func test_the_game_sounds_go_to_their_buses() -> void:
	_fresh()
	var s := _sound()
	s.setup({"groan": ["res://assets/audio/groan_0.wav"], "wind_loop": ["res://assets/audio/wind_loop.wav"], "crickets_loop": ["res://assets/audio/crickets_loop.wav"], "moan_loop": ["res://assets/audio/moan_loop.wav"]})
	eq(s.players.size(), Sound.POOL, "the pool is as it was")
	for p in s.players:
		eq(String(p.bus), "SFX", "a one-shot voice plays on SFX")
	for p in s.ui_players:
		eq(String(p.bus), "UI", "a menu voice plays on UI")
	for loop in [s.wind, s.crickets, s.moan]:
		eq(String(loop.bus), "Ambience", "a loop plays on Ambience")
	s.free()
	_done()


func test_the_menu_sounds_are_there_and_short() -> void:
	for sound_name in ["ui_click", "ui_confirm", "ui_error", "ui_open", "ui_close"]:
		var path := "res://assets/audio/%s_0.wav" % sound_name
		check(Sound.UI_SOUNDS.has(sound_name) and Sound.UI_SOUNDS[sound_name] == [path], "%s is declared" % sound_name)
		check(ResourceLoader.exists(path), "%s is imported" % sound_name)
		var st: AudioStreamWAV = load(path)
		check(st != null, "%s loads" % sound_name)
		if st == null:
			continue
		check(st.get_length() > 0.03 and st.get_length() < 1.0, "%s is short: %.2f s" % [sound_name, st.get_length()])
		eq(st.mix_rate, 44100, "%s is 44.1 kHz" % sound_name)
		check(not st.stereo, "%s is mono" % sound_name)
		# the file itself, as the other sounds are: 16-bit PCM, mono, 44.1 kHz
		var head := FileAccess.get_file_as_bytes(path)
		eq(head.decode_u16(20), 1, "%s is plain PCM" % sound_name)
		eq(head.decode_u16(22), 1, "%s has one channel" % sound_name)
		eq(head.decode_u32(24), 44100, "%s: the rate in the file" % sound_name)
		eq(head.decode_u16(34), 16, "%s is 16-bit" % sound_name)


func test_a_menu_sound_plays_on_the_ui_bus_from_its_own_voices() -> void:
	_fresh()
	var s := _sound()
	s.setup({})
	for sound_name in Sound.UI_SOUNDS:
		check(s.streams.has(sound_name) and s.streams[sound_name].size() == 1, "%s is loaded" % sound_name)
	s.ui("ui_click")
	check(s.ui_players[0].stream != null, "the first menu voice has the sound")
	eq(String(s.ui_players[0].bus), "UI", "on the UI bus")
	eq(s.ui_next, 1, "the next voice is next")
	eq(s.next, 0, "and the game's own voices are not touched")
	for i in 10:
		s.ui("ui_confirm")
	check(s.ui_next >= 0 and s.ui_next < Sound.UI_POOL, "the voices go round")
	var before: int = s.ui_next
	s.ui("no_such_sound")
	eq(s.ui_next, before, "a sound that does not exist is nothing")
	s.muted = true
	s.ui("ui_click")
	eq(s.ui_next, before, "muted: nothing plays")
	s.free()
	_done()


func test_the_old_calls_still_work() -> void:
	_fresh()
	var s := _sound()
	s.setup({"groan": ["res://assets/audio/groan_0.wav"]})
	s.play("groan", 1.0, 0.0, 0.72)
	near(s.players[0].pitch_scale, 0.72, 0.0001, "a one-shot, as before")
	s.set_ambience(1.0, 0.0, 1.0)
	s.free()
	_done()
