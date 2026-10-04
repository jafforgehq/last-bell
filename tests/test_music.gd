extends "res://tests/case.gd"
## The music (scripts/audio/music.gd, the score of tools/make_score.py): the stems are there and loop; the mood follows the title, the rules'
## phase, being indoors, the dead, a fortress night, a played trip and how the run ended (and knows no map); the layers come in with the threat; a change of mood cross-fades with
## no hole and no pile-up, and the stems of a mood stay in step; the stingers play over it; a big event ducks it and it comes back; the
## Music slider and the HUD's sound button reach it; and the game wires it in (the title has its own track).

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
	m.sfx_duck_on = false    # (the guns' dip reads the SFX bus's peak; a test of the music alone does not want it)
	return m


func _free(m: Node) -> void:
	Engine.get_main_loop().root.remove_child(m)
	m.free()


func _done() -> void:
	Prefs.reset()
	Buses.hud_muted = false
	Buses.apply_all()


## `seconds` of the music's own time, in frames of a tenth of a second.
func _run(m: Node, seconds: float) -> void:
	var n := int(seconds / 0.1)
	for i in n:
		m._process(0.1)


## One step of the game: what main.gd does every tenth of a second, then the music's frame.
func _step(m: Node, in_run: bool, trip: bool, dark: float, horde: float, ctx: Dictionary = {}) -> void:
	m.follow(in_run, trip, dark, horde, 0.1, ctx)
	m._process(0.1)


## How far apart (seconds) the stems of a mood are in their loops (they were started together, so a hair).
func _spread(m: Node, stems: Array) -> float:
	var lo := 1.0e9
	var hi := -1.0e9
	for stem in stems:
		var x: float = m.players[stem].get_playback_position()
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi - lo


## The power of the base stems now: for two stems cross-fading by the quarter-power curve it is 1 all the way through.
func _base_power(m: Node) -> float:
	var p := 0.0
	for mood in Music.MOODS:
		var base: String = Music.MOODS[mood][0]
		if m.players.has(base):
			var s := sin(float(m.fade[base]) * PI * 0.5)
			p += s * s
	return p


func test_every_stem_is_there_mono_and_loops() -> void:
	for stem in Music.TRACKS:
		var path: String = Music.TRACKS[stem]
		check(ResourceLoader.exists(path), "%s: the file is imported" % stem)
		var s = load(path)
		check(s is AudioStreamWAV, "%s is a wav stream" % stem)
		if not s is AudioStreamWAV:
			continue
		check(not s.stereo, "%s is mono (the stems are kept small)" % stem)
		check([12000, 16000, 22050].has(s.mix_rate), "%s is 12, 16 or 22 kHz: %d" % [stem, s.mix_rate])
		check(s.get_length() >= 30.0 and s.get_length() <= 100.0, "%s: %.1f s" % [stem, s.get_length()])
	for name in Music.STINGERS:
		check(load(Music.STINGERS[name]) is AudioStreamWAV, "the %s stinger loads" % name)


func test_setup_makes_a_player_for_each_stem_on_the_music_bus_and_loops_it() -> void:
	_fresh()
	var m := _made()
	eq(m.players.size(), Music.TRACKS.size(), "a player for each stem")
	eq(m.stingers.size(), 4, "and one for each stinger")
	for stem in m.players:
		var p: AudioStreamPlayer = m.players[stem]
		eq(String(p.bus), "Music", "%s plays on the Music bus" % stem)
		eq(p.stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % stem)
		check(p.stream.loop_end > 0 and p.stream.loop_end <= int(p.stream.get_length() * p.stream.mix_rate), "%s loops over the whole of it" % stem)
		check(not p.playing, "%s is not playing before a mood is asked for" % stem)
	for name in m.stingers:
		eq(String(m.stingers[name].bus), "Music", "the %s stinger is on the Music bus" % name)
		eq(m.stingers[name].stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "and plays once")
	_free(m)
	_done()


# ------------------------------------------------------------------- mood --

func test_the_title_screen_has_the_title_track_and_a_run_that_is_over_goes_back_to_it() -> void:
	var m := _made()
	m.follow(false, false, 0.0, 0.0, 0.1)
	eq(m.mood, "title", "no run: the title")
	m.follow(true, false, 0.0, 0.0, 0.1)
	eq(m.mood, "outdoors", "a run by day, outside")
	m.follow(false, false, 0.9, 1.0, 0.1)
	eq(m.mood, "title", "the title again, whatever the sky and the dead are doing")
	_free(m)


func test_the_phase_picks_the_mood_and_the_dark_does_when_there_is_no_phase() -> void:
	var m := _made()
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day"})
	eq(m.mood, "outdoors", "the day outside is the tense exploring")
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "dusk"})
	eq(m.mood, "night", "the bell: the night's music begins with the dusk")
	m.follow(true, false, 0.9, 0.0, 0.1, {"phase": "night"})
	eq(m.mood, "night", "night")
	m.follow(true, false, 0.9, 0.0, 0.1, {"phase": "night", "fortress": true})
	eq(m.mood, "fortress", "a night of the fortress under attack has its own")
	m.follow(true, false, 0.9, 0.0, 0.1, {"phase": "night", "big": true})
	eq(m.mood, "fortress", "(the old name of it still works)")
	m.follow(true, false, 0.3, 0.0, 0.1, {"phase": "dawn", "fortress": true})
	eq(m.mood, "outdoors", "the dawn is the day's, even after an attack")
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day", "fortress": true})
	eq(m.mood, "outdoors", "and a fortress that is not attacked tonight is only day")
	# no phase (a test, a game without one): the dark, with a gap between the two thresholds
	var q := _made()
	q.follow(true, false, 0.1, 0.0, 0.1)
	eq(q.mood, "outdoors", "light")
	q.follow(true, false, Music.NIGHT_ON - 0.02, 0.0, 0.1)
	eq(q.mood, "outdoors", "not yet dark enough")
	q.follow(true, false, Music.NIGHT_ON + 0.02, 0.0, 0.1)
	eq(q.mood, "night", "dark")
	q.follow(true, false, (Music.NIGHT_ON + Music.NIGHT_OFF) / 2.0, 0.0, 0.1)
	eq(q.mood, "night", "a little lighter and it is still night (the gap between the two thresholds)")
	q.follow(true, false, Music.NIGHT_OFF - 0.02, 0.0, 0.1)
	eq(q.mood, "outdoors", "light enough to be day again")
	_free(m)
	_free(q)


func test_indoors_is_calm_and_a_doorway_does_not_make_the_music_flicker() -> void:
	var m := _made()
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day", "indoors": true})
	eq(m.mood, "outdoors", "a step through the door is not yet indoors")
	for i in int(Music.INDOORS_IN_S / 0.1) + 1:
		m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day", "indoors": true})
	eq(m.mood, "indoors", "a cleared house: the calm, sparse music, after a moment inside")
	for i in 10:
		m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day", "indoors": false})
	eq(m.mood, "indoors", "out for a second: still the house's")
	for i in int(Music.INDOORS_OUT_S / 0.1) + 1:
		m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day", "indoors": false})
	eq(m.mood, "outdoors", "out for a while: the day outside")
	# a flicker in the doorway never gets there
	for i in 30:
		m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day", "indoors": i % 2 == 0})
	eq(m.mood, "outdoors", "in and out every tenth of a second stays outside")
	# at night indoors is calm too, until the dead are at the door; the fortress is the fortress whether you are in it or not
	var q := _made()
	for i in 20:
		q.follow(true, false, 0.9, 0.0, 0.1, {"phase": "night", "indoors": true})
	eq(q.mood, "indoors", "a quiet night in a house")
	q.follow(true, false, 0.9, Music.INDOORS_BREAK + 0.1, 0.1, {"phase": "night", "indoors": true})
	eq(q.mood, "night", "the dead at the door: the night's tension, indoors or not")
	for i in 20:
		q.follow(true, false, 0.9, 0.0, 0.1, {"phase": "night", "indoors": true, "fortress": true})
	eq(q.mood, "fortress", "the attack on the fortified house: the fortress's, with the player inside")
	_free(m)
	_free(q)


func test_a_played_trip_has_the_exploring_music_and_gives_the_world_back() -> void:
	var m := _made()
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day", "indoors": false})
	eq(m.mood, "outdoors", "outside by day")
	m.follow(true, true, 0.0, 0.0, 0.1, {"phase": "day", "indoors": true})
	eq(m.mood, "outdoors", "a trip is the exploring music, indoors or not")
	m.follow(true, true, 0.9, 0.0, 0.1, {"phase": "night"})
	eq(m.mood, "night", "and at night the tense one")
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day"})
	eq(m.mood, "outdoors", "back home")
	_free(m)


func test_the_end_of_a_run_has_its_own_music() -> void:
	var m := _made()
	m.follow(false, false, 0.0, 0.0, 0.1, {"phase": "dawn", "over": "victory"})
	eq(m.mood, "endcard", "a victory: the tune in the major")
	check(m.duck_db <= 0.0 and m._duck_target <= Music.END_DUCK_DB + 0.01, "and the music dips while the card is read")
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day", "over": "defeat"})
	eq(m.mood, "", "a defeat: the stems fade out")
	check(m.stingers.defeat.playing, "and the sting plays")
	for i in int(Music.DEFEAT_QUIET_S / 0.1) + 5:
		m.follow(false, false, 0.0, 0.0, 0.1, {"over": "defeat"})
	eq(m.mood, "title", "and, after a quiet while, the title's tune comes back")
	m.follow(false, false, 0.0, 0.0, 0.1)
	m.notify("end_card")
	eq(m.mood, "endcard", "the end card, asked for by the game, is the major tune too")
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day"})
	eq(m.mood, "endcard", "and stays while the card is up")
	m.notify("end_card_off")
	m.follow(true, false, 0.0, 0.0, 0.1, {"phase": "day"})
	eq(m.mood, "outdoors", "until it is put away")
	_free(m)


# ---------------------------------------------------------------- layers --

func test_the_layers_come_in_with_the_threat_and_not_before() -> void:
	var m := _made()
	m.follow(true, false, 0.9, 0.0, 0.1, {"phase": "night", "progress": 0.0})
	m.threat = 0.0
	m.set_mood("night")
	near(m.stem_target("night_base"), 1.0, 0.0001, "the base is always whole")
	near(m.stem_target("night_pulse"), 0.0, 0.0001, "no threat: no pulse")
	m.threat = 0.4
	near(m.stem_target("night_pulse"), 1.0, 0.0001, "a few of the dead: the heartbeat")
	near(m.stem_target("night_perc"), 0.0, 0.0001, "but not the drums")
	m.threat = 0.9
	near(m.stem_target("night_perc"), 1.0, 0.0001, "a crowd at the wall: the drums")
	near(m.stem_target("fortress_brass"), 0.0, 0.0001, "and none of the fortress's stems in a night outside")
	m.set_mood("fortress")
	m.threat = 0.0
	check(m.stem_target("fortress_pulse") < 0.01 and m.stem_target("fortress_brass") == 0.0, "a fortress night with no one near: the base and, as the threat grows, the drum")
	m.threat = 0.3
	check(m.stem_target("fortress_pulse") == 1.0 and m.stem_target("fortress_brass") > 0.0 and m.stem_target("fortress_perc") == 0.0, "a few: the heavy drum, the brass coming")
	m.threat = 1.0
	for stem in Music.MOODS.fortress:
		near(m.stem_target(stem), 1.0, 0.0001, "everything at the wall: %s whole" % stem)
	_free(m)


func test_the_threat_rises_fast_and_falls_slowly_and_the_night_has_a_floor() -> void:
	var m := _made()
	m.follow(true, false, 0.9, 1.0, 1.0, {"phase": "night", "progress": 0.0})
	near(m.threat, Music.THREAT_UP, 0.001, "a crowd arrives: up by THREAT_UP a second")
	for i in 5:
		m.follow(true, false, 0.9, 1.0, 1.0, {"phase": "night"})
	near(m.threat, 1.0, 0.001, "and it is whole")
	m.follow(true, false, 0.9, 0.0, 10.0, {"phase": "night", "progress": 0.0})
	near(m.threat, 1.0 - Music.THREAT_DOWN * 10.0, 0.001, "they are gone: it falls slowly")
	for i in 100:
		m.follow(true, false, 0.9, 0.0, 1.0, {"phase": "night", "progress": 0.0})
	near(m.threat, Music.NIGHT_FLOOR, 0.001, "to the night's floor at dusk")
	for i in 100:
		m.follow(true, false, 0.9, 0.0, 1.0, {"phase": "night", "progress": 1.0})
	near(m.threat, Music.NIGHT_FLOOR + Music.NIGHT_RAMP, 0.001, "and a little more at the end of it")
	for i in 100:
		m.follow(true, false, 0.0, 0.0, 1.0, {"phase": "day"})
	near(m.threat, 0.0, 0.001, "by day nothing")
	for i in 100:
		m.follow(true, false, 0.9, 0.0, 1.0, {"phase": "night", "fortress": true, "progress": 0.0})
	near(m.threat, Music.FORT_FLOOR, 0.001, "the fortress has a lower floor, the attack makes the rest")
	_free(m)


# -------------------------------------------------------------- the fades --

func test_a_mood_fades_in_with_all_its_stems_started_together() -> void:
	_fresh()
	var m := _made()
	m.set_mood("night")
	_run(m, 0.5)
	for stem in Music.MOODS.night:
		check(m.players[stem].playing, "%s starts with the others" % stem)
	check(_spread(m, Music.MOODS.night) <= 0.1, "from the same place in their loops (%.3f s apart)" % _spread(m, Music.MOODS.night))
	var early: float = m.players.night_base.volume_db
	_run(m, Music.FADE_S)
	var full: float = m.players.night_base.volume_db
	check(full > early, "the base gets louder (%.1f then %.1f dB)" % [early, full])
	near(full, linear_to_db(Music.LEVEL), 0.05, "to the music's level (the files carry their loudness)")
	check(m.players.night_pulse.volume_db < -60.0, "a layer that is not asked for plays silent, so it is in step when it comes")
	for other in ["title", "indoors", "outdoors", "endcard", "fortress_base"]:
		check(not m.players[other].playing, "%s is not playing" % other)
	_free(m)
	_done()


func test_a_change_of_mood_cross_fades_without_a_hole_or_a_pile_up_and_stops_the_old_stems() -> void:
	_fresh()
	var m := _made()
	_step(m, true, false, 0.0, 0.0, {"phase": "day"})
	_run(m, Music.FADE_S + 1.0)
	var lowest := 9.0
	var highest := 0.0
	# the bell: the phase turns to dusk and the night's music crosses in over the day's
	for i in int((Music.FADE_S + 2.0) / 0.1):
		_step(m, true, false, 0.3, 0.0, {"phase": "dusk", "progress": 0.0})
		lowest = minf(lowest, _base_power(m))
		highest = maxf(highest, _base_power(m))
	check(lowest >= 0.9 and highest <= 1.1, "the base power of the cross-fade stays at 1 (%.2f to %.2f): no hole, no pile-up" % [lowest, highest])
	check(not m.players.outdoors.playing, "the day outside's stem has stopped")
	check(m.players.night_base.playing, "the night's plays")
	near(m.players.night_base.volume_db, linear_to_db(Music.LEVEL) + m.total_duck_db(), 0.05, "at the full level (less the dip under the stinger)")
	# and a mood that is changed back half way never goes quiet
	_step(m, true, false, 0.0, 0.0, {"phase": "day"})
	for i in 20:
		_step(m, true, false, 0.0, 0.0, {"phase": "day"})
	_step(m, true, false, 0.9, 0.0, {"phase": "night"})
	lowest = 9.0
	for i in 40:
		_step(m, true, false, 0.9, 0.0, {"phase": "night"})
		lowest = minf(lowest, _base_power(m))
	check(lowest >= 0.45, "a mood turned half way does not leave a hole: %.2f" % lowest)
	_free(m)
	_done()


func test_the_stems_of_a_mood_stay_in_step_when_it_comes_back() -> void:
	var m := _made()
	_step(m, true, false, 0.9, 0.0, {"phase": "night"})
	_run(m, 2.0)
	# the day is asked for for a second only: the night's stems are still fading, so they are never stopped and never restarted apart
	for i in 10:
		_step(m, true, false, 0.0, 0.0, {"phase": "day"})
	for i in 10:
		_step(m, true, false, 0.9, 0.0, {"phase": "night"})
	for stem in Music.MOODS.night:
		check(m.players[stem].playing, "%s kept playing" % stem)
	check(_spread(m, Music.MOODS.night) <= 0.1, "and they are all at the same place in their loops (%.3f s apart)" % _spread(m, Music.MOODS.night))
	_free(m)


func test_no_mood_fades_everything_out() -> void:
	var m := _made()
	m.set_mood("title")
	_run(m, Music.FADE_S + 1.0)
	check(m.players.title.playing, "playing")
	m.set_mood("")
	_run(m, Music.FADE_S + 1.0)
	for stem in m.players:
		check(not m.players[stem].playing, "%s is silent" % stem)
	_free(m)


func test_a_track_that_comes_back_does_not_start_where_it_always_does() -> void:
	var m := _made()
	var starts := {}
	for i in 6:
		m.set_mood("outdoors")
		_run(m, 0.3)
		starts[snappedf(m.players.outdoors.get_playback_position(), 0.5)] = true
		m.set_mood("night")
		_run(m, Music.FADE_S + 1.0)
	check(starts.size() > 1, "six comebacks, %d different places" % starts.size())
	_free(m)


# ---------------------------------------------------------- stingers, ducking --

func test_the_dusk_and_dawn_stingers_play_once_over_the_stems_which_dip() -> void:
	var m := _made()
	_step(m, true, false, 0.0, 0.0, {"phase": "day"})
	_step(m, true, false, 0.3, 0.0, {"phase": "dusk"})
	check(m.stingers.dusk.playing, "the dusk stinger comes with the bell")
	check(m._duck_target < 0.0, "and the stems dip under it")
	_step(m, true, false, 0.3, 0.0, {"phase": "dusk"})
	check(m.stinger("dusk") == false, "not twice")
	_step(m, true, false, 0.9, 0.0, {"phase": "night"})
	check(not m.stingers.dawn.playing, "the dawn's is not heard at night")
	_step(m, true, false, 0.3, 0.0, {"phase": "dawn"})
	check(m.stingers.dawn.playing, "the dawn's comes when the night is survived")
	eq(m.mood, "outdoors", "and the day's music begins under it")
	# a run loaded at the dawn or at the dusk has no stinger: it has not seen the phase turn
	var q := _made()
	_step(q, true, false, 0.3, 0.0, {"phase": "dawn"})
	check(not q.stingers.dawn.playing, "no dawn stinger without the turn of a phase that was seen")
	var r := _made()
	_step(r, true, false, 0.3, 0.0, {"phase": "dusk"})
	check(not r.stingers.dusk.playing, "nor a dusk one")
	_free(r)
	_free(m)
	_free(q)


func test_a_big_event_ducks_the_music_and_it_comes_back() -> void:
	_fresh()
	var m := _made()
	_step(m, true, false, 0.9, 0.0, {"phase": "night"})
	_run(m, Music.FADE_S + 1.0)
	var level: float = m.players.night_base.volume_db
	m.notify("brute")
	_run(m, 0.6)
	check(m.duck_db <= Music.BRUTE_DUCK_DB + 0.5 and m.duck_db >= Music.BRUTE_DUCK_DB - 0.5, "a brute roars: the music is down about %.0f dB (%.1f)" % [Music.BRUTE_DUCK_DB, m.duck_db])
	near(m.players.night_base.volume_db, level + m.duck_db, 0.3, "the stem's volume has it")
	m.duck(-4.0, 1.0)
	m.duck(-2.0, 1.0)
	check(m._duck_target <= Music.BRUTE_DUCK_DB + 0.01, "the strongest dip asked for is the one that holds")
	_run(m, Music.BRUTE_DUCK_S + Music.DUCK_RELEASE_S * 6.0)
	near(m.duck_db, 0.0, 0.05, "and it is given back")
	near(m.players.night_base.volume_db, level, 0.1, "the music is at its own level again")
	m.notify("gate")
	_run(m, 0.5)
	check(m.duck_db <= Music.GATE_DUCK_DB + 0.6, "the gate's lever dips it too (%.1f)" % m.duck_db)
	check(m.duck_db >= Music.MAX_DUCK_DB, "and never more than the most")
	_run(m, 6.0)
	near(m.duck_db, 0.0, 0.05, "restored")
	_free(m)
	_done()


func test_a_rescue_has_a_short_warm_stinger_and_a_few_in_a_row_each_have_one() -> void:
	var m := _made()
	_step(m, true, false, 0.0, 0.0, {"phase": "day"})
	m.notify("rescue")
	check(m.stingers.rescue.playing, "someone found: the stinger plays")
	check(m._duck_target <= Music.RESCUE_DUCK_DB + 0.01, "and the stems dip under it")
	m.notify("rescue")
	check(m.stinger("rescue") == false, "not twice at once")
	_run(m, Music.STINGER_GAPS.rescue + 0.5)
	m.stingers.rescue.stop()
	check(m.stinger("rescue"), "but the next one found a few seconds later has its own")
	check(m.stingers.rescue.stream.get_length() <= 8.0, "and it is short: %.1f s" % m.stingers.rescue.stream.get_length())
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
	check(["outdoors", "indoors", "night"].has(main2.music.mood), "a run has the day's, the house's or the night's track: %s" % main2.music.mood)
	check(main2.music.mood != "title", "and not the title's")
	# the context main.gd gives it is the rules' own
	var ctx: Dictionary = main2._music_context()
	eq(ctx.phase, String(main2.sim.phase), "the phase is the rules'")
	eq(ctx.over, "", "the run is not over")
	check(ctx.has("indoors"), "and whether the avatar is indoors")
	await Fakes.leave(g2)
	_done()


# ------------------------------------------------------- web and the reload --

func test_a_track_starts_from_the_top_on_the_web_and_anywhere_in_it_elsewhere() -> void:
	# on the web a sample's restart reuses its start offset, so a loop begun at 33 s of 64 replayed only its last half
	near(Music.start_offset(64.0, true, 0.7), 0.0, 0.0001, "the web starts at the top whatever the dice say")
	near(Music.start_offset(64.0, false, 0.5), 31.5, 0.0001, "elsewhere any place but the very end")
	near(Music.start_offset(64.0, false, 0.0), 0.0, 0.0001, "the lowest throw")
	check(Music.start_offset(64.0, false, 1.0) <= 63.0, "and never past the last second")
	near(Music.start_offset(0.5, false, 0.9), 0.0, 0.0001, "a very short track has no room to start later")


func test_the_music_outlives_a_scene_reload() -> void:
	# a new run, a load and the way back to the title reload the scene; the music has to be on the tree's root, made once,
	# or it cuts dead at the title's Start and fades in from nothing
	var tree: SceneTree = Engine.get_main_loop()
	var a = Music.shared(tree)
	var b = Music.shared(tree)
	check(a != null and a == b, "the second ask gets the same music, not a second one")
	await tree.process_frame
	check(a.get_parent() == tree.root, "it hangs on the root, not on a scene that is about to go")
	eq(a.players.size(), Music.TRACKS.size(), "with all its stems")
	check(Music.current() == a, "and the soundscape can find it")
	a.set_mood("night")
	var c = Music.shared(tree)
	check(c == a and c.mood == "night", "after a reload the new scene finds it playing the same mood")
	tree.root.remove_child(a)
	Engine.remove_meta(Music.META)
	a.free()
	var d = Music.shared(tree)
	check(d != a, "a music that has gone is made again")
	await tree.process_frame
	tree.root.remove_child(d)
	Engine.remove_meta(Music.META)
	d.free()
