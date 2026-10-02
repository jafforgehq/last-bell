extends "res://tests/case.gd"
## The music (scripts/audio/music.gd, the loops of tools/make_music.py): the four files are there and are loops;
## the mood follows the title, the hour, the dead and a played trip; a change of mood cross-fades; the Music
## slider and the HUD's sound button reach it; and the game wires it in (the title has its own track).

const Fakes := preload("res://tests/menu_fakes.gd")
const Music := preload("res://scripts/audio/music.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Settings := preload("res://scripts/ui/settings_menu.gd")


func _fresh() -> void:
	Prefs.path = "user://prefs_test.cfg"
	Prefs.reset()
	Prefs.set_flag("tutorial_offered")
	Buses.hud_muted = false
	Buses.apply_all()


func _made() -> Node:
	var m = Music.new()
	Engine.get_main_loop().root.add_child(m)
	m.setup()
	return m


func _free(m: Node) -> void:
	Engine.get_main_loop().root.remove_child(m)
	m.free()


## `seconds` of the music's own time, in frames of a tenth of a second.
func _run(m: Node, seconds: float) -> void:
	var n := int(seconds / 0.1)
	for i in n:
		m._process(0.1)


func test_the_four_loops_are_there_mono_and_a_minute_or_so_long() -> void:
	for name in ["title", "day", "night", "danger"]:
		var path: String = Music.TRACKS[name]
		check(ResourceLoader.exists(path), "%s: the file is imported" % name)
		var s = load(path)
		check(s is AudioStreamWAV, "%s is a wav stream" % name)
		if not s is AudioStreamWAV:
			continue
		check(not s.stereo, "%s is mono (the loops are kept small)" % name)
		eq(s.mix_rate, 22050, "%s is 22050 Hz" % name)
		check(s.get_length() >= 30.0 and s.get_length() <= 90.0, "%s is long enough not to be heard to repeat: %.1f s" % [name, s.get_length()])


func test_setup_makes_a_player_for_each_loop_on_the_music_bus_and_loops_it() -> void:
	_fresh()
	var m := _made()
	eq(m.players.size(), 4, "four players")
	for name in m.players:
		var p: AudioStreamPlayer = m.players[name]
		eq(String(p.bus), "Music", "%s plays on the Music bus" % name)
		eq(p.stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % name)
		check(p.stream.loop_end > 0 and p.stream.loop_end <= int(p.stream.get_length() * p.stream.mix_rate), "%s loops over the whole of it" % name)
		check(not p.playing, "%s is not playing before a mood is asked for" % name)
	_free(m)
	_done()


func _done() -> void:
	Prefs.reset()
	Buses.hud_muted = false
	Buses.apply_all()


# ------------------------------------------------------------------- mood --

func test_the_title_screen_has_the_title_track_and_a_run_that_is_over_goes_back_to_it() -> void:
	var m := _made()
	m.follow(false, false, 0.0, 0.0, 0.1)
	eq(m.mood, "title", "no run: the title")
	m.follow(true, false, 0.0, 0.0, 0.1)
	eq(m.mood, "day", "a run by day")
	m.follow(false, false, 0.9, 1.0, 0.1)
	eq(m.mood, "title", "the title again, whatever the sky and the dead are doing")
	_free(m)


func test_night_comes_with_the_dark_and_does_not_flicker_at_the_edge() -> void:
	var m := _made()
	m.follow(true, false, 0.1, 0.0, 0.1)
	eq(m.mood, "day", "light")
	m.follow(true, false, Music.NIGHT_ON - 0.02, 0.0, 0.1)
	eq(m.mood, "day", "not yet dark enough")
	m.follow(true, false, Music.NIGHT_ON + 0.02, 0.0, 0.1)
	eq(m.mood, "night", "dark")
	m.follow(true, false, (Music.NIGHT_ON + Music.NIGHT_OFF) / 2.0, 0.0, 0.1)
	eq(m.mood, "night", "a little lighter and it is still night (the gap between the two thresholds)")
	m.follow(true, false, Music.NIGHT_OFF - 0.02, 0.0, 0.1)
	eq(m.mood, "day", "light enough to be day again")
	_free(m)


func test_the_dead_at_the_wall_make_the_music_danger_for_at_least_a_while() -> void:
	var m := _made()
	m.follow(true, false, 0.8, 0.3, 0.1)
	eq(m.mood, "night", "a few of the dead are not danger")
	m.follow(true, false, 0.8, Music.DANGER_ON + 0.05, 0.1)
	eq(m.mood, "danger", "a crowd is")
	m.follow(true, false, 0.8, 0.0, 0.1)
	eq(m.mood, "danger", "and the music does not drop out the moment the camera loses them")
	var left := 0.0
	while left < Music.MIN_DANGER_S - 1.0:
		m.follow(true, false, 0.8, 0.0, 0.5)
		left += 0.5
	eq(m.mood, "danger", "still danger just before the minimum")
	m.follow(true, false, 0.8, 0.0, 2.0)
	eq(m.mood, "night", "and then back to the night")
	m.follow(true, false, 0.1, 0.9, 0.1)
	eq(m.mood, "danger", "by day too")
	_free(m)


func test_a_played_trip_has_the_tense_track_and_gives_the_yard_back() -> void:
	var m := _made()
	m.follow(true, false, 0.0, 0.0, 0.1)
	eq(m.mood, "day", "the yard by day")
	m.follow(true, true, 0.0, 0.0, 0.1)
	eq(m.mood, "night", "a trip is tense even at noon")
	m.follow(true, true, 0.0, 1.0, 0.1)
	eq(m.mood, "night", "and the yard's dead are not its business")
	m.follow(true, false, 0.0, 0.0, 0.1)
	eq(m.mood, "day", "back in the yard")
	_free(m)


# -------------------------------------------------------------- the fades --

func test_a_mood_fades_in_and_only_its_track_plays() -> void:
	_fresh()
	var m := _made()
	m.set_mood("day")
	_run(m, 0.5)
	check(m.players.day.playing, "the track starts")
	var early: float = m.players.day.volume_db
	_run(m, Music.FADE_S)
	var full: float = m.players.day.volume_db
	check(full > early, "and gets louder (%.1f then %.1f dB)" % [early, full])
	near(full, linear_to_db(Music.LEVEL), 0.05, "to the music's level, which is under the sounds")
	for other in ["title", "night", "danger"]:
		check(not m.players[other].playing, "%s is not playing" % other)
	_free(m)
	_done()


func test_a_change_of_mood_cross_fades_without_a_hole_and_stops_the_old_track() -> void:
	_fresh()
	var m := _made()
	m.set_mood("day")
	_run(m, Music.FADE_S + 1.0)
	m.set_mood("night")
	_run(m, Music.FADE_S * 0.5)
	check(m.players.day.playing and m.players.night.playing, "halfway, both are heard")
	var sum: float = db_to_linear(m.players.day.volume_db) + db_to_linear(m.players.night.volume_db)
	check(sum >= Music.LEVEL * 0.9, "and together they are not quieter than one: %.2f of %.2f" % [sum, Music.LEVEL])
	_run(m, Music.FADE_S)
	check(not m.players.day.playing, "the old track has stopped")
	check(m.players.night.playing, "the new one plays")
	near(m.players.night.volume_db, linear_to_db(Music.LEVEL), 0.05, "at the full level")
	_free(m)
	_done()


func test_no_mood_fades_everything_out() -> void:
	var m := _made()
	m.set_mood("title")
	_run(m, Music.FADE_S + 1.0)
	check(m.players.title.playing, "playing")
	m.set_mood("")
	_run(m, Music.FADE_S + 1.0)
	for name in m.players:
		check(not m.players[name].playing, "%s is silent" % name)
	_free(m)


func test_a_track_that_comes_back_does_not_start_where_it_always_does() -> void:
	var m := _made()
	var starts := {}
	for i in 6:
		m.set_mood("day")
		_run(m, 0.3)
		starts[snappedf(m.players.day.get_playback_position(), 0.5)] = true
		m.set_mood("night")
		_run(m, Music.FADE_S + 1.0)
	check(starts.size() > 1, "six comebacks, %d different places" % starts.size())
	_free(m)


# ------------------------------------------------------------ the controls --

func test_the_music_slider_and_the_sound_button_silence_it() -> void:
	_fresh()
	check(not Buses.is_silent("Music"), "the music has its volume to begin with")
	Prefs.set_value("audio", "music", 0.0)
	Buses.apply("Music")
	check(Buses.is_silent("Music"), "the slider at 0 mutes the Music bus")
	Prefs.set_value("audio", "music", 1.0)
	Buses.apply("Music")
	check(not Buses.is_silent("Music"), "and back")
	Buses.set_hud_muted(true)
	check(Buses.is_silent("Master"), "the HUD's sound button mutes Master, which the music is under")
	eq(String(AudioServer.get_bus_send(AudioServer.get_bus_index("Music"))), "Master", "the Music bus is under Master")
	_done()


func test_settings_has_a_music_slider() -> void:
	var keys := []
	for row in Settings.VOLUMES:
		keys.append(row[0])
		if row[0] == "music":
			eq(row[2], "Music", "it moves the Music bus")
	check(keys.has("music"), "the settings list has a Music row: %s" % str(keys))


# ------------------------------------------------------------- in the game --

func test_the_game_plays_the_title_track_on_the_title_and_the_day_track_in_a_run() -> void:
	_fresh()
	var g := Fakes.game({"title": true})
	var main = g.main
	check(main.music != null, "the game has the music")
	for i in 8:
		main._process(0.05)
	eq(main.music.mood, "title", "the title's track on the title screen")
	await Fakes.leave(g)
	_fresh()
	var g2 := Fakes.game({"difficulty": 0, "seed": 3})
	var main2 = g2.main
	for i in 8:
		main2._process(0.05)
	check(["day", "night"].has(main2.music.mood), "a run has the day's or the night's track: %s" % main2.music.mood)
	check(main2.music.mood != "title", "and not the title's")
	await Fakes.leave(g2)
	_done()
