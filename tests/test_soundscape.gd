extends "res://tests/case.gd"
## The soundscape (scripts/audio/soundscape.gd): the dusk bell is four tolls and the other bells are single; a groan is one of eight, positional,
## at a random pitch, and the voices are capped (8 at once, 5 of them groans, the nearest kept) whatever the crowd; a brute's roar dips the music;
## the gate has its lever, its slide and its clang; footsteps follow the ground, are rate limited and are silent when the game is sped up; the beds
## follow the night, the rain and the dead and stop when they are silent; the far sounds come on timers only while the game runs; the truck's engine
## follows its speed and stops by itself; the doors, generators and radio desks, the surfaces and the gate come from the map's data and the rules, not
## from a map; and nothing here touches the rules (the golden tests' promise). A voice that "plays" in a test does not end by itself (no time passes in
## a frame), so a test that wants time to pass stops the voices (`_pass_time`).

const Sound := preload("res://scripts/audio/sound.gd")
const Soundscape := preload("res://scripts/audio/soundscape.gd")
const Music := preload("res://scripts/audio/music.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Fakes := preload("res://tests/menu_fakes.gd")


class FakeWorld:
	extends RefCounted
	var W := 20
	var H := 20
	var terrain := PackedByteArray()

	func _init() -> void:
		terrain.resize(400)
		terrain.fill(4)


class FakePerson:
	extends RefCounted
	var id := "p"
	var x := 5.5
	var y := 5.5
	var dead := false
	var turned := false
	var away = null
	var player := false


class FakeLevels:
	extends RefCounted
	var deck := false

	func on_deck(_p) -> bool:
		return deck


class FakeGate:
	extends RefCounted

	func control_spot() -> Vector2:
		return Vector2(3.0, 12.0)

	func gateway() -> Rect2:
		return Rect2(6.0, 4.0, 4.0, 6.0)


class FakeSim:
	extends RefCounted
	var people: Array = []
	var zombies: Array = []
	var phase := "night"
	var weather := "clear"
	var levels = null
	var jobs = null
	var gate = null


class FakeGame:
	extends Node
	var sim := FakeSim.new()
	var world := FakeWorld.new()
	var data := {
		"objects": [
			{"kind": "door", "cx": 10.0, "cy": 10.0, "w": 2.0, "h": 1.0},
			{"kind": "generator", "cx": 4.0, "cy": 4.0, "w": 1.0, "h": 1.0},
			{"kind": "radiodesk", "cx": 15.0, "cy": 15.0, "w": 2.0, "h": 1.0},
		],
		"terrainTypes": {"ASPHALT": {"id": 1}, "LINO": {"id": 6}, "WOOD": {"id": 8}, "GRASS": {"id": 4}, "CONCRETE": {"id": 12}, "MUDFLAT": {"id": 14}, "TILE_FLOOR": {"id": 15}},
	}
	var speed := 1
	var title_mode := false
	var menu_open := false
	var cam_center := Vector2(10.0, 10.0)


func _map_sounds() -> Dictionary:
	var f := FileAccess.open("res://assets/data/map.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d.get("sounds", {}) if d is Dictionary else {}


func _made() -> Dictionary:
	Buses.hud_muted = false
	var root: Node = Engine.get_main_loop().root
	var s := Sound.new()
	root.add_child(s)
	s.setup(_map_sounds())
	var g := FakeGame.new()
	root.add_child(g)
	s.attach(g)
	return {"s": s, "g": g, "sc": s.scape}


func _free(d: Dictionary) -> void:
	var root: Node = Engine.get_main_loop().root
	root.remove_child(d.s)
	root.remove_child(d.g)
	d.s.free()
	d.g.free()
	Buses.hud_muted = false
	Buses.apply_all()


func _run(sc: Node, seconds: float) -> void:
	for i in int(seconds / 0.05):
		sc.update(0.05)


## The voices have finished (a frame of a test does not last as long as the sounds do).
func _pass_time(sc: Node) -> void:
	for v in sc.voices:
		v.p.stop()
	for b in sc.bells:
		b.stop()


func test_everything_the_soundscape_names_is_loaded() -> void:
	var d := _made()
	var sc: Node = d.sc
	for key in ["bell:dusk", "bell:deep", "bell:alarm", "bell:chime", "bell:far", "step:dirt", "step:concrete", "step:wood", "gate:lever", "gate:slide", "gate:clang", "door:open", "door:close", "far:crow", "far:dog", "far:creak", "far:moan", "far:shot"]:
		check(sc.streams.has(key) and not sc.streams[key].is_empty(), "%s is loaded" % key)
	eq(sc.streams["bell:dusk"].size(), 3, "three strikes of the dusk bell")
	eq(sc.streams["groan"].size(), 8, "eight groans")
	eq(sc.streams["roar"].size(), 2, "two roars")
	eq(d.s.streams["groan"].size(), 8, "and Sound.play('groan') has all eight too (the map's four and four more)")
	eq(d.s.streams["hammer"].size(), 4, "four hammer strokes")
	for key in ["night_bed", "rain", "generator", "radio"]:
		check(sc.beds.has(key) and sc.beds[key].stream != null, "the %s bed is there" % key)
	check(sc.engine_player != null and sc.road_player != null, "and the truck's engine and road")
	for v in sc.voices:
		eq(String(v.p.bus), "SFX", "a positional voice is on SFX")
	eq(sc.voices.size(), Soundscape.MAX_VOICES, "eight positional voices, no more")
	_free(d)


func test_the_dusk_bell_is_four_tolls_and_the_others_are_one() -> void:
	var d := _made()
	var sc: Node = d.sc
	sc.ring("dusk")
	eq(int(sc.played.get("bell", 0)), 1, "the first toll at once")
	_run(sc, 3.0)
	check(int(sc.played.bell) >= 2 and int(sc.played.bell) <= 3, "two or three by three seconds: %d" % int(sc.played.bell))
	_run(sc, 6.0)
	eq(int(sc.played.bell), 4, "four tolls in all, not thirty")
	_run(sc, 10.0)
	eq(int(sc.played.bell), 4, "and then no more")
	for kind in ["alarm", "deep", "chime", "far"]:
		var before := int(sc.played.bell)
		sc.ring(kind)
		eq(int(sc.played.bell), before + 1, "%s is one sound" % kind)
	# the strikes of the dusk bell are not the same twice running
	var seen := {}
	for i in 12:
		sc.ring("dusk")
		_run(sc, 0.05)
	for b in sc.bells:
		if b.stream != null:
			seen[b.stream.resource_path] = true
	check(seen.size() >= 2, "more than one strike of the bell is used: %d" % seen.size())
	_free(d)


func test_groans_are_positional_varied_and_capped_and_the_nearest_are_kept() -> void:
	var d := _made()
	var sc: Node = d.sc
	var cam := Vector2(10.0, 10.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		var e := {"type": "groan", "x": cam.x + rng.randf_range(-30.0, 30.0), "y": cam.y + rng.randf_range(-30.0, 30.0), "kind": ["walker", "walker", "runner"][i % 3]}
		sc.groan(e, cam)
		if i % 20 == 0:
			check(sc.voices_playing() <= Soundscape.MAX_VOICES, "at most %d voices (%d)" % [Soundscape.MAX_VOICES, sc.voices_playing()])
			check(sc._count("groan") <= int(Soundscape.KIND_CAP.groan), "at most %d groans (%d)" % [int(Soundscape.KIND_CAP.groan), sc._count("groan")])
	check(int(sc.played.groan) >= 5, "a crowd is heard: %d played" % int(sc.played.groan))
	check(sc.dropped > 0, "and most of it is left out for the cap: %d dropped" % sc.dropped)
	var pitches := []
	for v in sc.voices:
		if v.kind == "groan" and v.p.playing:
			pitches.append(v.p.pitch_scale)
			check(v.p.pitch_scale >= 0.7 and v.p.pitch_scale <= 1.45, "a pitch in range: %.2f" % v.p.pitch_scale)
			check(v.p.max_distance == Soundscape.GROAN_REACH * Soundscape.TILE, "it carries GROAN_REACH tiles")
	# a near groan takes the place of a far one
	for i in 40:
		sc.groan({"x": cam.x + 2.0, "y": cam.y, "kind": "walker"}, cam)
	var near_one := false
	for v in sc.voices:
		if v.kind == "groan" and v.p.playing and absf(float(v.p.position.x) - 2.0 * Soundscape.TILE) < 1.0:
			near_one = true
			near(v.p.position.y, 0.0, 0.5, "it is where the groaner is: two tiles east of the listener")
	check(near_one, "a groan two tiles away is heard even when the crowd is far (the voices are the nearest)")
	# one pitch, many plays: the files and the pitches differ
	var files := {}
	for i in 80:
		_pass_time(sc)
		sc.groan({"x": cam.x + 4.0, "y": cam.y + 3.0, "kind": "walker"}, cam)
		for v in sc.voices:
			if v.kind == "groan" and v.p.stream != null:
				files[v.p.stream.resource_path] = true
	check(files.size() >= 6, "the eight groans are used: %d different files heard" % files.size())
	# a stray of the streets is quiet and low
	var quiet := _made()
	for i in 60:
		quiet.sc.groan({"x": 12.0, "y": 10.0, "kind": "walker", "stray": true}, Vector2(10.0, 10.0))
	for v in quiet.sc.voices:
		if v.kind == "groan" and v.p.playing:
			check(v.p.volume_db <= -9.0, "a straggler's groan is quiet: %.1f dB" % v.p.volume_db)
			check(v.p.pitch_scale <= 1.0, "and low: %.2f" % v.p.pitch_scale)
	_free(quiet)
	_free(d)


func test_a_brute_roars_with_its_distance_and_the_music_dips() -> void:
	var d := _made()
	var sc: Node = d.sc
	var root: Node = Engine.get_main_loop().root
	var m = Music.new()
	root.add_child(m)
	m.setup()
	m.sfx_duck_on = false
	Engine.set_meta(Music.META, m)
	var cam := Vector2(10.0, 10.0)
	for i in 30:
		sc._last_roar = -100.0
		sc.groan({"x": cam.x + 6.0, "y": cam.y, "kind": "brute"}, cam)
		if int(sc.played.get("roar", 0)) > 0:
			break
	eq(int(sc.played.get("roar", 0)), 1, "a brute's groan is a roar")
	check(m._duck_target <= Music.BRUTE_DUCK_DB + 0.01, "and the music is told to dip (%.1f)" % m._duck_target)
	var roar_voice = null
	for v in sc.voices:
		if v.kind == "roar":
			roar_voice = v
	check(roar_voice != null and roar_voice.p.max_distance >= Soundscape.ROAR_REACH * Soundscape.TILE - 1.0, "it carries far")
	# one roar at a time, and not twice within 2.5 s
	sc._last_roar = sc._t
	var before := int(sc.played.roar)
	sc.roar(cam + Vector2(8.0, 0.0), cam)
	eq(int(sc.played.roar), before, "a second roar is not played at once")
	# too far to hear
	sc._last_roar = -100.0
	sc.roar(cam + Vector2(Soundscape.ROAR_REACH + 10.0, 0.0), cam)
	eq(int(sc.played.roar), before, "and a roar out of reach is not heard")
	Engine.remove_meta(Music.META)
	root.remove_child(m)
	m.free()
	_free(d)


func test_the_gate_has_a_lever_a_slide_and_a_clang_and_the_music_dips_for_the_lever() -> void:
	var d := _made()
	var sc: Node = d.sc
	var root: Node = Engine.get_main_loop().root
	var m = Music.new()
	root.add_child(m)
	m.setup()
	m.sfx_duck_on = false
	Engine.set_meta(Music.META, m)
	sc.on_event({"type": "gate", "state": "opening", "by": "player"})
	eq(int(sc.played.get("gate", 0)), 1, "the lever's clunk and chain at once")
	check(m._duck_target <= Music.GATE_DUCK_DB + 0.01, "and the music dips under it")
	_run(sc, 0.4)
	eq(int(sc.played.gate), 2, "then the slide")
	sc.on_event({"type": "gate", "state": "open", "by": "player"})
	eq(int(sc.played.gate), 3, "and the clang at the stop")
	check(sc._count("gate") <= int(Soundscape.KIND_CAP.gate), "never more than the cap of gate voices")
	# the keeper at the dusk does not dip the music (it is not the player's lever)
	m._duck_target = 0.0
	m._duck_hold = 0.0
	sc.on_event({"type": "gate", "state": "closing", "by": "dusk"})
	check(m._duck_target == 0.0, "the keeper's lever at the bell does not")
	Engine.remove_meta(Music.META)
	root.remove_child(m)
	m.free()
	_free(d)


func test_the_gate_sounds_are_put_where_the_rules_gate_is_or_at_the_listener() -> void:
	var d := _made()
	var sc: Node = d.sc
	var g: FakeGame = d.g
	g.cam_center = Vector2(10.0, 10.0)
	sc.on_event({"type": "gate", "state": "opening", "by": "dusk"})
	var at_listener := false
	for v in sc.voices:
		if v.kind == "gate" and v.p.playing:
			at_listener = v.p.position.length() < 1.0
	check(at_listener, "a game with no gate in its rules: the sound is plain, at the listener")
	_pass_time(sc)
	g.sim.gate = FakeGate.new()
	sc.on_event({"type": "gate", "state": "opening", "by": "dusk"})
	var lever := false
	for v in sc.voices:
		if v.kind == "gate" and v.p.playing:
			lever = absf(float(v.p.position.x) - (3.0 - 10.0) * Soundscape.TILE) < 1.0 and absf(float(v.p.position.y) - (12.0 - 10.0) * Soundscape.TILE) < 1.0
	check(lever, "with the rules' gate: the lever's clunk is at the lever (3, 12), seen from the camera at (10, 10)")
	_pass_time(sc)
	sc.on_event({"type": "gate", "state": "open", "by": "dusk"})
	var mouth := false
	for v in sc.voices:
		if v.kind == "gate" and v.p.playing:
			mouth = absf(float(v.p.position.x) - (8.0 - 10.0) * Soundscape.TILE) < 1.0 and absf(float(v.p.position.y) - (7.0 - 10.0) * Soundscape.TILE) < 1.0
	check(mouth, "and the clang at the middle of the opening (8, 7)")
	_free(d)


func test_indoors_is_read_from_the_terrain_names_and_a_rescue_is_a_stinger() -> void:
	var d := _made()
	var sc: Node = d.sc
	var g: FakeGame = d.g
	check(not sc.avatar_indoors(), "no avatar: not indoors")
	var p := FakePerson.new()
	p.player = true
	p.x = 5.5
	p.y = 5.5
	g.sim.people = [p]
	check(not sc.avatar_indoors(), "on grass: outdoors")
	g.world.terrain[5 * 20 + 5] = 6
	check(sc.avatar_indoors(), "on lino: indoors")
	g.world.terrain[5 * 20 + 5] = 15
	check(sc.avatar_indoors(), "on a floor the map data calls TILE_FLOOR: indoors (the name says it, not the id)")
	g.world.terrain[5 * 20 + 5] = 12
	check(not sc.avatar_indoors(), "on concrete: outdoors")
	# a rescue: the small bell and the music's warm stinger, for any of the events the rules may use for it
	var root: Node = Engine.get_main_loop().root
	var m = Music.new()
	root.add_child(m)
	m.setup()
	m.sfx_duck_on = false
	Engine.set_meta(Music.META, m)
	for kind in ["arrived", "survivor", "rescued", "rescue"]:
		m.stingers.rescue.stop()
		m._stinger_at.clear()
		var before := int(sc.played.get("bell", 0))
		sc.on_event({"type": kind})
		eq(int(sc.played.bell), before + 1, "%s: the chime" % kind)
		check(m.stingers.rescue.playing, "%s: the rescue stinger" % kind)
	Engine.remove_meta(Music.META)
	root.remove_child(m)
	m.free()
	_free(d)


func test_footsteps_follow_the_ground_are_rate_limited_and_silent_when_sped_up() -> void:
	var d := _made()
	var sc: Node = d.sc
	var g: FakeGame = d.g
	eq(sc.surface_at(5.5, 5.5), "dirt", "grass is dirt")
	g.world.terrain[5 * 20 + 5] = 12
	eq(sc.surface_at(5.5, 5.5), "concrete", "concrete")
	g.world.terrain[5 * 20 + 5] = 8
	eq(sc.surface_at(5.5, 5.5), "wood", "wood")
	g.world.terrain[5 * 20 + 5] = 1
	eq(sc.surface_at(5.5, 5.5), "concrete", "asphalt is concrete")
	g.world.terrain[5 * 20 + 5] = 14
	eq(sc.surface_at(5.5, 5.5), "dirt", "a terrain the map data calls MUDFLAT is dirt: the surface comes from the name, not from a table of ids")
	g.world.terrain[5 * 20 + 5] = 4
	eq(sc.surface_at(-3.0, 5.0), "dirt", "off the map is dirt")
	var levels := FakeLevels.new()
	g.sim.levels = levels
	var p := FakePerson.new()
	p.player = true
	g.sim.people = [p]
	levels.deck = true
	eq(sc.surface_at(5.5, 5.5, p), "wood", "a person on a raised deck is on wood")
	levels.deck = false
	eq(sc.surface_at(5.5, 5.5, p), "dirt", "and off it on the ground again")
	# the avatar walks 3 tiles a second for five seconds
	g.cam_center = Vector2(5.5, 5.5)
	p.x = 3.0
	sc._foot_tick(0.1)
	for i in 50:
		p.x += 0.3
		_pass_time(sc)
		sc._foot_tick(0.1)
		sc._t += 0.1
	var steps := int(sc.played.get("step", 0))
	check(steps >= 14 and steps <= 19, "15 tiles of walking is about 17 steps (0.85 a stride): %d" % steps)
	# another person, far from the camera, is not heard
	var far := FakePerson.new()
	far.id = "far"
	far.x = 18.0
	far.y = 18.0
	g.sim.people = [p, far]
	sc._foot_tick(0.1)
	var before := int(sc.played.step)
	for i in 30:
		far.x -= 0.3
		sc._foot_tick(0.1)
	eq(int(sc.played.step), before, "a person 17 tiles from the camera makes no sound")
	# sped up: nothing
	g.speed = 3
	for i in 30:
		p.x += 0.3
		sc._foot_tick(0.1)
	eq(int(sc.played.step), before, "at 3x speed the steps are silent")
	check(sc._count("step") <= int(Soundscape.KIND_CAP.step), "and never more than the cap of step voices")
	_free(d)


func test_the_beds_follow_the_night_the_rain_and_the_dead_and_stop_when_silent() -> void:
	var d := _made()
	var s: Node = d.s
	var sc: Node = d.sc
	var g: FakeGame = d.g
	for i in 8:
		s.set_ambience(0.0, 0.0, 1.0)
	check(not s.crickets.playing and not s.moan.playing, "by day the crickets and the moan are stopped (a silent loop still costs a voice)")
	check(s.wind.playing, "the wind plays")
	check(not sc.beds.night_bed.playing and not sc.beds.rain.playing, "no night bed, no rain")
	for i in 8:
		s.set_ambience(1.0, 0.0, 1.0)
	check(s.crickets.playing and sc.beds.night_bed.playing, "at night the crickets and the cold bed")
	check(s.wind_level < 0.5, "and the wind is down: %.2f" % s.wind_level)
	for i in 8:
		s.set_ambience(1.0, 1.0, 1.0)
	check(s.moan.playing, "with the dead at the wall, the horde's moan")
	g.sim.weather = "rain"
	for i in 40:
		s.set_ambience(0.0, 0.0, 1.0)
	check(sc.beds.rain.playing, "rain brings the rain loop")
	check(s.wind_level >= 0.5, "and the wind up")
	g.sim.weather = "clear"
	for i in 60:
		s.set_ambience(0.0, 0.0, 1.0)
	check(not sc.beds.rain.playing, "and takes it away")
	_free(d)


func test_the_far_sounds_come_on_timers_and_only_while_the_game_runs() -> void:
	var d := _made()
	var sc: Node = d.sc
	var g: FakeGame = d.g
	for key in sc._far_timer:
		sc._far_timer[key] = 0.01
	g.speed = 0
	sc._tick(0.1)
	eq(int(sc.played.get("far", 0)), 0, "a paused game has no far sounds, and its timers wait")
	for key in sc._far_timer:
		near(float(sc._far_timer[key]), 0.01, 0.0001, "%s waits" % key)
	g.speed = 1
	g.menu_open = true
	sc._tick(0.1)
	eq(int(sc.played.get("far", 0)), 0, "a menu is the same")
	g.menu_open = false
	g.title_mode = true
	sc._tick(0.1)
	eq(int(sc.played.get("far", 0)), 0, "and the title")
	g.title_mode = false
	g.sim.phase = "night"
	sc._tick(0.1)
	check(int(sc.played.get("far", 0)) >= 1, "at night it begins (a dog, a moan, a creak, a far shot)")
	for v in sc.voices:
		if v.kind == "far" and v.p.playing:
			eq(String(v.p.bus), Buses.far_bus(), "a far sound is on the far bus")
			check(v.p.position.length() > 8.0 * Soundscape.TILE, "and a long way off or at least off to one side: %.0f px" % v.p.position.length())
	check(sc._count("far") <= int(Soundscape.KIND_CAP.far), "at most two at once")
	check(AudioServer.get_bus_index("Distant") >= 0, "the Distant bus exists")
	# by day the crow, not the dog
	var d2 := _made()
	d2.g.sim.phase = "day"
	for key in d2.sc._far_timer:
		d2.sc._far_timer[key] = 0.01
	d2.sc._tick(0.1)
	var crow := false
	for v in d2.sc.voices:
		if v.kind == "far" and v.p.stream != null and String(v.p.stream.resource_path).contains("crow"):
			crow = true
	var other := false
	for v in d2.sc.voices:
		if v.kind == "far" and v.p.stream != null and (String(v.p.stream.resource_path).contains("dog") or String(v.p.stream.resource_path).contains("gunshot") or String(v.p.stream.resource_path).contains("moan")):
			other = true
	check(not other, "no dogs, moans or shots by day")
	_free(d2)
	_free(d)


func test_the_engine_follows_the_speed_and_stops_when_it_is_not_asked_for() -> void:
	var d := _made()
	var sc: Node = d.sc
	d.s.engine(0.0, 4.8, 0.0)
	check(sc.engine_player.playing and sc.road_player.playing, "the engine and the road start")
	var idle: float = sc.engine_player.pitch_scale
	near(idle, 0.85, 0.01, "an idle")
	d.s.engine(4.8, 4.8, 1.0)
	check(sc.engine_player.pitch_scale > 2.0, "flat out the pitch is high: %.2f" % sc.engine_player.pitch_scale)
	check(sc.road_player.volume_db > linear_to_db(0.3), "and the road is loud")
	d.s.engine(2.4, 4.8, 0.5)
	check(sc.engine_player.pitch_scale > idle and sc.engine_player.pitch_scale < 2.5, "half speed is in between")
	_run(sc, 0.6)
	check(not sc.engine_player.playing and not sc.road_player.playing, "and when the leg is over and nobody asks, they stop by themselves")
	_free(d)


func test_the_generator_and_the_radio_sound_only_where_the_camera_is_near() -> void:
	var d := _made()
	var sc: Node = d.sc
	var g: FakeGame = d.g
	g.cam_center = Vector2(4.0, 4.0) + Vector2(3.0, 0.0)
	sc._hum_tick()
	check(sc.beds.generator.playing, "near the generator the map lists, it hums")
	check(sc.beds.generator.position.length() <= 4.0 * Soundscape.TILE, "from where it stands")
	g.cam_center = Vector2(-60.0, -60.0)
	sc._hum_tick()
	check(not sc.beds.generator.playing and not sc.beds.radio.playing, "far away neither plays")
	g.cam_center = Vector2(15.0, 15.0) + Vector2(2.0, 0.0)
	sc._hum_tick()
	check(sc.beds.radio.playing, "at the radio desk the radio crackles (nobody is asked: the desk counts as staffed)")
	# a map with neither has neither
	var bare := _made()
	bare.g.data = {"objects": []}
	bare.s.attach(bare.g)
	bare.g.cam_center = Vector2(4.0, 4.0)
	bare.sc._hum_tick()
	check(not bare.sc.beds.generator.playing and not bare.sc.beds.radio.playing, "a map with no generator and no radio desk has no hum")
	_free(bare)
	_free(d)


func test_a_door_opens_for_the_avatar_and_closes_behind() -> void:
	var d := _made()
	var sc: Node = d.sc
	var g: FakeGame = d.g
	var p := FakePerson.new()
	p.player = true
	p.x = 5.0
	p.y = 10.0
	g.sim.people = [p]
	g.cam_center = Vector2(8.0, 10.0)
	sc._door_tick(0.1)
	eq(int(sc.played.get("door", 0)), 0, "far from the door: nothing")
	p.x = 9.5
	sc._door_tick(0.1)
	eq(int(sc.played.get("door", 0)), 1, "at the door: it opens")
	_pass_time(sc)
	p.x = 5.0
	sc._door_tick(0.1)
	_run(sc, 0.7)
	eq(int(sc.played.door), 2, "and it closes after them")
	_free(d)


func test_nothing_the_soundscape_does_touches_the_rules() -> void:
	var g := Fakes.game({"difficulty": 0, "seed": 5})
	var main = g.main
	var state: int = main.sim.rng.state
	var clock: float = main.sim.clock_min
	var kills: int = main.sim.kills
	var zombies: int = main.sim.zombies.size()
	var c: Vector2 = main.cam_center
	for i in 60:
		main.sound.on_event({"type": "groan", "x": c.x + 5.0, "y": c.y + (i % 7), "kind": ["walker", "runner", "brute"][i % 3]})
	for t in ["bell", "lure", "season", "built", "arrived", "call_raised", "radio_line", "briefing", "story_card"]:
		main.sound.on_event({"type": t})
	for s in ["opening", "open", "closing", "shut"]:
		main.sound.on_event({"type": "gate", "state": s, "by": "player"})
	for i in 200:
		main.sound.scape.update(0.05)
	main.sound.set_ambience(0.9, 0.5, 0.1)
	main.sound.engine(1.0, 4.0, 0.5)
	eq(main.sim.rng.state, state, "the rules' random state is where it was")
	eq(main.sim.clock_min, clock, "the clock")
	eq(main.sim.kills, kills, "the kills")
	eq(main.sim.zombies.size(), zombies, "the dead")
	check(int(main.sound.scape.played.get("groan", 0)) + int(main.sound.scape.played.get("roar", 0)) >= 1, "and sound was made")
	await Fakes.leave(g)
